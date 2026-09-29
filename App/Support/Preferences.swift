import Foundation
import KeyboardShortcuts
import ShuttleKit

enum AuthMethod: String, CaseIterable, Identifiable {
    case password
    case privateKey

    var id: String { rawValue }
}

enum MultipleFilesMode: String, CaseIterable, Identifiable {
    case zip
    case separately

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zip: "Zip into one archive"
        case .separately: "Upload each file"
        }
    }
}

/// UserDefaults keys, shared by `@AppStorage` in the views and `Preferences` below.
enum PrefKey {
    static let transferProtocol = "protocol"
    static let host = "host"
    static let port = "port"
    static let username = "username"
    static let authMethod = "authMethod"
    static let privateKeyPath = "privateKeyPath"
    static let remotePath = "remotePath"
    static let publicURL = "publicURL"
    static let filenameStyle = "filenameStyle"
    static let multipleFiles = "multipleFiles"
    static let notify = "notify"
    static let playSound = "playSound"
    static let uploadScreenshots = "uploadScreenshots"
}

/// Secrets live in the Keychain, never in UserDefaults.
enum SecretKey {
    static let password = "server-password"
    static let keyPassphrase = "ssh-key-passphrase"
}

extension KeyboardShortcuts.Name {
    static let uploadClipboard = Self("uploadClipboard", initial: .init(.u, modifiers: [.option, .command]))
}

enum Preferences {
    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            PrefKey.transferProtocol: TransferProtocol.sftp.rawValue,
            PrefKey.port: 22,
            PrefKey.authMethod: AuthMethod.password.rawValue,
            PrefKey.remotePath: "./",
            PrefKey.filenameStyle: FilenameStyle.originalWithHash.rawValue,
            PrefKey.multipleFiles: MultipleFilesMode.zip.rawValue,
            PrefKey.notify: true,
            PrefKey.playSound: true,
            PrefKey.uploadScreenshots: false,
        ])
    }

    static var filenameStyle: FilenameStyle {
        FilenameStyle(rawValue: defaults.string(forKey: PrefKey.filenameStyle) ?? "") ?? .originalWithHash
    }

    static var multipleFiles: MultipleFilesMode {
        MultipleFilesMode(rawValue: defaults.string(forKey: PrefKey.multipleFiles) ?? "") ?? .zip
    }

    static var notify: Bool { defaults.bool(forKey: PrefKey.notify) }
    static var playSound: Bool { defaults.bool(forKey: PrefKey.playSound) }
    static var uploadScreenshots: Bool { defaults.bool(forKey: PrefKey.uploadScreenshots) }

    private static var hasLogin: Bool {
        !(defaults.string(forKey: PrefKey.host) ?? "").isEmpty
            && !(defaults.string(forKey: PrefKey.username) ?? "").isEmpty
    }

    static var isConfigured: Bool {
        hasLogin && !(defaults.string(forKey: PrefKey.publicURL) ?? "").isEmpty
    }

    /// Builds the current server configuration. Throws if a key file can't be read.
    static func serverConfig() throws -> ServerConfig {
        guard isConfigured else { throw UploadError.notConfigured }
        return try serverConfigIgnoringURL()
    }

    /// Like `serverConfig()` but doesn't require a public URL, for "Test Connection".
    static func serverConfigIgnoringURL() throws -> ServerConfig {
        guard hasLogin else { throw UploadError.notConfigured }
        let proto = TransferProtocol(rawValue: defaults.string(forKey: PrefKey.transferProtocol) ?? "") ?? .sftp
        let auth = AuthMethod(rawValue: defaults.string(forKey: PrefKey.authMethod) ?? "") ?? .password

        let credentials: Credentials
        if proto == .sftp, auth == .privateKey {
            let path = (defaults.string(forKey: PrefKey.privateKeyPath) ?? "") as NSString
            guard let key = try? String(contentsOfFile: path.expandingTildeInPath, encoding: .utf8) else {
                throw UploadError.invalidPrivateKey
            }
            credentials = .privateKey(key, passphrase: Keychain.get(SecretKey.keyPassphrase))
        } else {
            credentials = .password(Keychain.get(SecretKey.password) ?? "")
        }

        let port = defaults.integer(forKey: PrefKey.port)
        return ServerConfig(
            transferProtocol: proto,
            host: defaults.string(forKey: PrefKey.host) ?? "",
            port: port > 0 ? port : proto.defaultPort,
            username: defaults.string(forKey: PrefKey.username) ?? "",
            credentials: credentials,
            remotePath: defaults.string(forKey: PrefKey.remotePath) ?? "",
            publicURL: defaults.string(forKey: PrefKey.publicURL) ?? ""
        )
    }
}
