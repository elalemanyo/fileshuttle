import CCurl
import Foundation
import Synchronization

/// FTP and explicit FTPS via the libcurl that ships with macOS.
struct FTPUploader: Uploader {
    let config: ServerConfig

    func upload(_ file: URL, as remoteName: String, progress: @escaping ProgressHandler) async throws {
        let url = directoryURL() + Self.encode(remoteName)
        let reporter = ProgressReporter(handler: progress)
        let path = file.path(percentEncoded: false)

        try await withTaskCancellationHandler {
            try await run(url: url) { options, errbuf, errlen in
                ccurl_upload(options, path, { ctx, sent, total in
                    let reporter = Unmanaged<ProgressReporter>.fromOpaque(ctx!).takeUnretainedValue()
                    return reporter.report(sent: sent, total: total) ? 0 : 1
                }, Unmanaged.passUnretained(reporter).toOpaque(), errbuf, errlen)
            }
        } onCancel: {
            reporter.cancel()
        }
        withExtendedLifetime(reporter) {}
    }

    func delete(remoteName: String) async throws {
        try await run(url: directoryURL()) { options, errbuf, errlen in
            ccurl_command(options, "DELE \(remoteName)", errbuf, errlen)
        }
    }

    func testConnection() async throws {
        try await run(url: directoryURL()) { options, errbuf, errlen in
            ccurl_command(options, nil, errbuf, errlen)
        }
    }

    // MARK: - Helpers

    private func run(
        url: String,
        _ body: @escaping @Sendable (UnsafePointer<ccurl_options>, UnsafeMutablePointer<CChar>, Int) -> Int32
    ) async throws {
        guard !config.host.isEmpty else { throw UploadError.notConfigured }
        let password: String
        switch config.credentials {
        case .password(let value): password = value
        case .privateKey: throw UploadError.server("FTP doesn't support key authentication.")
        }
        let username = config.username
        let requireTLS: Int32 = config.transferProtocol == .ftps ? 1 : 0

        let (code, message): (Int32, String) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                url.withCString { cURL in
                    username.withCString { cUser in
                        password.withCString { cPass in
                            var options = ccurl_options(
                                url: cURL,
                                username: cUser,
                                password: cPass,
                                require_tls: requireTLS,
                                connect_timeout: 20
                            )
                            var errbuf = [CChar](repeating: 0, count: 512)
                            let code = errbuf.withUnsafeMutableBufferPointer { buf in
                                body(&options, buf.baseAddress!, buf.count)
                            }
                            let message = String(decoding: errbuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                            continuation.resume(returning: (code, message))
                        }
                    }
                }
            }
        }

        switch code {
        case 0: return
        case 42: throw UploadError.cancelled // CURLE_ABORTED_BY_CALLBACK
        case 67: throw UploadError.authentication // CURLE_LOGIN_DENIED
        case 64: throw UploadError.connection("The server doesn't support FTP over TLS.") // CURLE_USE_SSL_FAILED
        case 6, 7, 28: throw UploadError.connection(message) // resolve, connect, timeout
        default: throw UploadError.server(message)
        }
    }

    private func directoryURL() -> String {
        let host = config.host.contains(":") ? "[\(config.host)]" : config.host
        var url = "ftp://\(host):\(config.port)/"
        // libcurl treats paths as relative to the login directory; %2F makes them absolute.
        if config.isAbsolutePath { url += "%2F" }
        for component in config.remoteComponents {
            url += Self.encode(component) + "/"
        }
        return url
    }

    private static func encode(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/", ";"])) ?? component
    }
}

/// Bridges libcurl's C progress callback to Swift, throttled to ~0.5% steps.
final class ProgressReporter: Sendable {
    private let handler: ProgressHandler
    private let cancelled = Atomic<Bool>(false)
    private let lastReported = Mutex<Double>(-1)

    init(handler: @escaping ProgressHandler) {
        self.handler = handler
    }

    func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    /// Returns false when the transfer should stop.
    func report(sent: Int64, total: Int64) -> Bool {
        if cancelled.load(ordering: .relaxed) { return false }
        guard total > 0 else { return true }
        let fraction = min(1, Double(sent) / Double(total))
        let shouldReport = lastReported.withLock { last in
            guard fraction - last >= 0.005 || (fraction == 1 && last < 1) else { return false }
            last = fraction
            return true
        }
        if shouldReport { handler(fraction) }
        return true
    }
}
