import Foundation

public typealias ProgressHandler = @Sendable (_ fraction: Double) -> Void

public protocol Uploader: Sendable {
    /// Uploads `file` into the configured remote directory as `remoteName`.
    func upload(_ file: URL, as remoteName: String, progress: @escaping ProgressHandler) async throws
    /// Removes a previously uploaded file from the server.
    func delete(remoteName: String) async throws
    /// Logs in and checks that the remote directory is reachable.
    func testConnection() async throws
}

public enum UploadError: LocalizedError, Sendable {
    case notConfigured
    case connection(String)
    case authentication
    case hostKeyChanged(host: String)
    case invalidPrivateKey
    case server(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "The server isn't configured yet."
        case .connection(let message): "Couldn't connect: \(message)"
        case .authentication: "Login failed. Check the username and password or key."
        case .hostKeyChanged(let host): "The SSH host key for \(host) changed. Reset trusted keys in Settings if this is expected."
        case .invalidPrivateKey: "The private key couldn't be read. Use an unencrypted or passphrase-protected OpenSSH ed25519/RSA key."
        case .server(let message): message
        case .cancelled: "Upload cancelled."
        }
    }
}

/// Remembers SSH host keys (trust on first use).
public struct HostKeyStore: Sendable {
    public var trustedKey: @Sendable (_ host: String) -> String?
    public var trust: @Sendable (_ key: String, _ host: String) -> Void

    public init(
        trustedKey: @escaping @Sendable (String) -> String?,
        trust: @escaping @Sendable (String, String) -> Void
    ) {
        self.trustedKey = trustedKey
        self.trust = trust
    }

    public static let userDefaults = HostKeyStore(
        trustedKey: { UserDefaults.standard.dictionary(forKey: "trustedHostKeys")?[$0] as? String },
        trust: { key, host in
            var keys = UserDefaults.standard.dictionary(forKey: "trustedHostKeys") ?? [:]
            keys[host] = key
            UserDefaults.standard.set(keys, forKey: "trustedHostKeys")
        }
    )

    public static func resetUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "trustedHostKeys")
    }
}

public func makeUploader(for config: ServerConfig, hostKeys: HostKeyStore = .userDefaults) -> any Uploader {
    switch config.transferProtocol {
    case .ftp, .ftps: FTPUploader(config: config)
    case .sftp: SFTPUploader(config: config, hostKeys: hostKeys)
    }
}
