import Citadel
import Crypto
import Foundation
import NIOCore
import NIOSSH
import _CryptoExtras

/// SFTP via Citadel (pure Swift SSH on SwiftNIO).
struct SFTPUploader: Uploader {
    let config: ServerConfig
    let hostKeys: HostKeyStore

    /// SFTP write requests are capped at 32 KB; keep several in flight so latency doesn't dominate.
    private static let chunkSize = 32_000
    private static let maxInFlight = 32

    func upload(_ file: URL, as remoteName: String, progress: @escaping ProgressHandler) async throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let total = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int64 ?? 0
        let remotePath = config.remoteFilePath(remoteName)

        try await withSFTP { sftp in
            let remoteFile: SFTPFile
            do {
                remoteFile = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
            } catch let status as SFTPMessage.Status where status.errorCode == .noSuchFile {
                try await createDirectories(sftp)
                remoteFile = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
            }
            let target = UncheckedSendable(remoteFile)

            do {
                try await withThrowingTaskGroup(of: Int.self) { group in
                    var offset: UInt64 = 0
                    var sent: Int64 = 0
                    var inFlight = 0
                    let reporter = ProgressReporter(handler: progress)

                    func collect(_ written: Int) throws {
                        inFlight -= 1
                        sent += Int64(written)
                        if !reporter.report(sent: sent, total: total) { throw UploadError.cancelled }
                    }

                    while true {
                        try Task.checkCancellation()
                        if inFlight >= Self.maxInFlight, let written = try await group.next() {
                            try collect(written)
                        }
                        guard let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty else { break }
                        let chunkOffset = offset
                        offset += UInt64(data.count)
                        inFlight += 1
                        group.addTask {
                            try await target.value.write(ByteBuffer(bytes: data), at: chunkOffset)
                            return data.count
                        }
                    }
                    for try await written in group {
                        try collect(written)
                    }
                    if total == 0 { progress(1) }
                }
                try await remoteFile.close()
            } catch {
                try? await remoteFile.close()
                if error is CancellationError { throw UploadError.cancelled }
                throw error
            }
        }
    }

    func delete(remoteName: String) async throws {
        try await withSFTP { sftp in
            try await sftp.remove(at: config.remoteFilePath(remoteName))
        }
    }

    func testConnection() async throws {
        try await withSFTP { sftp in
            let path = config.remoteComponents.isEmpty && !config.isAbsolutePath ? "." : config.remoteFilePath("").dropLastSlash
            _ = try await sftp.listDirectory(atPath: path)
        }
    }

    // MARK: - Connection

    private func withSFTP(_ body: (SFTPClient) async throws -> Void) async throws {
        guard !config.host.isEmpty, !config.username.isEmpty else { throw UploadError.notConfigured }

        let client: SSHClient
        do {
            client = try await SSHClient.connect(
                host: config.host,
                port: config.port,
                authenticationMethod: authenticationMethod(),
                hostKeyValidator: .custom(TrustOnFirstUse(host: "\(config.host):\(config.port)", store: hostKeys)),
                reconnect: .never,
                connectTimeout: .seconds(20)
            )
        } catch let error as UploadError {
            throw error
        } catch let error as SSHClientError {
            switch error {
            case .allAuthenticationOptionsFailed, .unsupportedPasswordAuthentication, .unsupportedPrivateKeyAuthentication:
                throw UploadError.authentication
            default:
                throw UploadError.connection(String(describing: error))
            }
        } catch let error as HostKeyMismatch {
            throw UploadError.hostKeyChanged(host: error.host)
        } catch {
            if let mismatch = Self.findHostKeyMismatch(in: error) {
                throw UploadError.hostKeyChanged(host: mismatch.host)
            }
            throw UploadError.connection(error.localizedDescription)
        }

        do {
            let sftp = try await client.openSFTP()
            try await body(sftp)
            try? await sftp.close()
            try? await client.close()
        } catch {
            try? await client.close()
            let status: SFTPMessage.Status? = switch error {
            case let status as SFTPMessage.Status: status
            case SFTPError.errorStatus(let status): status
            default: nil
            }
            if let status {
                throw UploadError.server(Self.describe(status))
            }
            throw error
        }
    }

    private func createDirectories(_ sftp: SFTPClient) async throws {
        var path = config.isAbsolutePath ? "" : "."
        for component in config.remoteComponents {
            path += "/" + component
            try? await sftp.createDirectory(atPath: path)
        }
    }

    private func authenticationMethod() throws -> SSHAuthenticationMethod {
        switch config.credentials {
        case .password(let password):
            return .passwordBased(username: config.username, password: password)
        case .privateKey(let key, let passphrase):
            let decryptionKey = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
            if let ed25519 = try? Curve25519.Signing.PrivateKey(sshEd25519: key, decryptionKey: decryptionKey) {
                return .ed25519(username: config.username, privateKey: ed25519)
            }
            if let rsa = try? Insecure.RSA.PrivateKey(sshRsa: key, decryptionKey: decryptionKey) {
                return .rsa(username: config.username, privateKey: rsa)
            }
            throw UploadError.invalidPrivateKey
        }
    }

    private static func describe(_ status: SFTPMessage.Status) -> String {
        switch status.errorCode {
        case .noSuchFile: "The remote folder doesn't exist."
        case .permissionDenied: "Permission denied on the server. Check the remote path."
        default: status.message.isEmpty ? "SFTP error: \(status.errorCode)" : status.message
        }
    }

    private static func findHostKeyMismatch(in error: any Error) -> HostKeyMismatch? {
        if let mismatch = error as? HostKeyMismatch { return mismatch }
        let mirror = Mirror(reflecting: error)
        for child in mirror.children {
            if let nested = child.value as? any Error, let mismatch = findHostKeyMismatch(in: nested) {
                return mismatch
            }
        }
        return nil
    }
}

struct HostKeyMismatch: Error {
    let host: String
}

/// Trusts a host's key the first time it's seen, then rejects any different key.
final class TrustOnFirstUse: NIOSSHClientServerAuthenticationDelegate, Sendable {
    let host: String
    let store: HostKeyStore

    init(host: String, store: HostKeyStore) {
        self.host = host
        self.store = store
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let presented = String(openSSHPublicKey: hostKey)
        if let known = store.trustedKey(host) {
            if known == presented {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyMismatch(host: host))
            }
        } else {
            store.trust(presented, host)
            validationCompletePromise.succeed(())
        }
    }
}

struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private extension String {
    var dropLastSlash: String {
        count > 1 && hasSuffix("/") ? String(dropLast()) : self
    }
}
