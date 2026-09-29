import Foundation

public enum TransferProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case ftp
    case ftps
    case sftp

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ftp: "FTP"
        case .ftps: "FTPS (FTP over TLS)"
        case .sftp: "SFTP (SSH)"
        }
    }

    public var defaultPort: Int {
        switch self {
        case .ftp, .ftps: 21
        case .sftp: 22
        }
    }
}

public enum Credentials: Sendable {
    case password(String)
    /// OpenSSH-formatted private key (ed25519 or RSA).
    case privateKey(String, passphrase: String?)
}

public struct ServerConfig: Sendable {
    public var transferProtocol: TransferProtocol
    public var host: String
    public var port: Int
    public var username: String
    public var credentials: Credentials
    /// Directory on the server, relative to the login directory unless it starts with "/".
    public var remotePath: String
    /// Public base URL that serves `remotePath`.
    public var publicURL: String

    public init(
        transferProtocol: TransferProtocol,
        host: String,
        port: Int,
        username: String,
        credentials: Credentials,
        remotePath: String,
        publicURL: String
    ) {
        self.transferProtocol = transferProtocol
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port
        self.username = username
        self.credentials = credentials
        self.remotePath = remotePath.trimmingCharacters(in: .whitespacesAndNewlines)
        self.publicURL = publicURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Path components of `remotePath`, with "." and empty segments removed.
    var remoteComponents: [String] {
        remotePath.split(separator: "/").map(String.init).filter { $0 != "." && !$0.isEmpty }
    }

    var isAbsolutePath: Bool { remotePath.hasPrefix("/") }

    /// `remotePath` joined with `name`, suitable for SFTP.
    func remoteFilePath(_ name: String) -> String {
        let dir = remoteComponents.joined(separator: "/")
        let prefix = isAbsolutePath ? "/" : ""
        return dir.isEmpty ? prefix + name : prefix + dir + "/" + name
    }

    /// Shareable link for an uploaded file.
    public func shareURL(for remoteName: String) -> URL? {
        var base = publicURL
        guard !base.isEmpty else { return nil }
        if !base.lowercased().hasPrefix("http://") && !base.lowercased().hasPrefix("https://") {
            base = "https://" + base
        }
        if !base.hasSuffix("/") { base += "/" }
        let encoded = remoteName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? remoteName
        return URL(string: base + encoded)
    }
}
