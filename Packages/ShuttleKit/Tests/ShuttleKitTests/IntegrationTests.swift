import Foundation
import Testing
@testable import ShuttleKit

/// Runs against local containers. Start them with `scripts/test-servers.sh`, then:
/// SHUTTLE_INTEGRATION=1 swift test
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SHUTTLE_INTEGRATION"] == "1"), .serialized)
struct IntegrationTests {
    static let memoryKeys: HostKeyStore = {
        let keys = KeyBox()
        return HostKeyStore(trustedKey: { keys.get($0) }, trust: { keys.set($0, for: $1) })
    }()

    func makeFile(bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "shuttle-\(UUID().uuidString).bin")
        try Data((0..<bytes).map { UInt8($0 % 251) }).write(to: url)
        return url
    }

    @Test(arguments: [TransferProtocol.sftp, .ftp])
    func uploadAndDelete(_ proto: TransferProtocol) async throws {
        let config = ServerConfig(
            transferProtocol: proto,
            host: "127.0.0.1",
            port: proto == .sftp ? 2222 : 2121,
            username: "foo",
            credentials: .password("pass"),
            remotePath: proto == .sftp ? "upload/nested/dir" : "nested/dir",
            publicURL: "https://example.com"
        )
        let uploader = makeUploader(for: config, hostKeys: Self.memoryKeys)
        _ = try? await uploader.testConnection()

        let file = try makeFile(bytes: 3_000_000)
        defer { try? FileManager.default.removeItem(at: file) }
        let progress = ProgressLog()
        try await uploader.upload(file, as: "test-\(proto).bin", progress: { progress.append($0) })
        #expect(progress.last == 1)
        try await uploader.testConnection()
        try await uploader.delete(remoteName: "test-\(proto).bin")
    }

    @Test func wrongPasswordIsAuthenticationError() async {
        let config = ServerConfig(transferProtocol: .sftp, host: "127.0.0.1", port: 2222, username: "foo",
                                  credentials: .password("nope"), remotePath: "upload", publicURL: "")
        await #expect {
            try await makeUploader(for: config, hostKeys: Self.memoryKeys).testConnection()
        } throws: { error in
            if case .authentication = error as? UploadError { return true }
            return false
        }
    }
}


final class KeyBox: @unchecked Sendable {
    private var keys: [String: String] = [:]
    private let lock = NSLock()
    func get(_ host: String) -> String? { lock.withLock { keys[host] } }
    func set(_ key: String, for host: String) { lock.withLock { keys[host] = key } }
}

final class ProgressLog: @unchecked Sendable {
    private var values: [Double] = []
    private let lock = NSLock()
    func append(_ value: Double) { lock.withLock { values.append(value) } }
    var last: Double? { lock.withLock { values.last } }
}
