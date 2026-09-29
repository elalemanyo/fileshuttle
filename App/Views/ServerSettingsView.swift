import ShuttleKit
import SwiftUI
import UniformTypeIdentifiers

struct ServerSettingsView: View {
    @AppStorage(PrefKey.transferProtocol) private var transferProtocol = TransferProtocol.sftp
    @AppStorage(PrefKey.host) private var host = ""
    @AppStorage(PrefKey.port) private var port = 22
    @AppStorage(PrefKey.username) private var username = ""
    @AppStorage(PrefKey.authMethod) private var authMethod = AuthMethod.password
    @AppStorage(PrefKey.privateKeyPath) private var privateKeyPath = ""
    @AppStorage(PrefKey.remotePath) private var remotePath = "./"
    @AppStorage(PrefKey.publicURL) private var publicURL = ""
    @AppStorage(PrefKey.filenameStyle) private var filenameStyle = FilenameStyle.originalWithHash

    @State private var password = Keychain.get(SecretKey.password) ?? ""
    @State private var passphrase = Keychain.get(SecretKey.keyPassphrase) ?? ""
    @State private var test = TestState.idle

    enum TestState: Equatable {
        case idle, running, success, failure(String)
    }

    var body: some View {
        Form {
            Section {
                Picker("Protocol", selection: $transferProtocol) {
                    ForEach(TransferProtocol.allCases) { Text($0.displayName).tag($0) }
                }
                .onChange(of: transferProtocol) { old, new in
                    if port == old.defaultPort { port = new.defaultPort }
                }

                TextField("Host", text: $host, prompt: Text("files.example.com"))
                TextField("Port", value: $port, format: .number.grouping(.never))
                TextField("Username", text: $username)

                if transferProtocol == .sftp {
                    Picker("Sign in with", selection: $authMethod) {
                        Text("Password").tag(AuthMethod.password)
                        Text("SSH key").tag(AuthMethod.privateKey)
                    }
                    .pickerStyle(.segmented)
                }

                if transferProtocol == .sftp && authMethod == .privateKey {
                    LabeledContent("Private key") {
                        HStack {
                            TextField("Private key", text: $privateKeyPath, prompt: Text("~/.ssh/id_ed25519"))
                                .labelsHidden()
                            Button("Choose…", action: chooseKey)
                        }
                    }
                    SecureField("Key passphrase", text: $passphrase, prompt: Text("Optional"))
                        .onChange(of: passphrase) { Keychain.set(passphrase, for: SecretKey.keyPassphrase) }
                } else {
                    SecureField("Password", text: $password)
                        .onChange(of: password) { Keychain.set(password, for: SecretKey.password) }
                }
            } header: {
                Text("Connection")
            } footer: {
                if transferProtocol == .ftp {
                    Label("Plain FTP sends your password unencrypted. Choose FTPS or SFTP if your host supports it.",
                          systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("Remote folder", text: $remotePath, prompt: Text("./public_html/files"))
                TextField("Public URL", text: $publicURL, prompt: Text("https://example.com/files/"))
                LabeledContent("Links look like") {
                    Text(exampleLink)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Destination")
            } footer: {
                Text("The remote folder is relative to your login folder unless it starts with “/”. The public URL is the web address serving that folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Test Connection", action: runTest)
                        .disabled(test == .running || host.isEmpty)
                    Spacer()
                    testStatus
                }
                if transferProtocol == .sftp {
                    HStack {
                        Text("Host keys are trusted on first connection.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Forget Trusted Keys") { HostKeyStore.resetUserDefaults() }
                    }
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var exampleLink: String {
        let config = ServerConfig(transferProtocol: transferProtocol, host: host, port: port, username: username,
                                  credentials: .password(""), remotePath: remotePath, publicURL: publicURL)
        return config.shareURL(for: filenameStyle.example)?.absoluteString ?? "—"
    }

    @ViewBuilder
    private var testStatus: some View {
        switch test {
        case .idle:
            EmptyView()
        case .running:
            ProgressView().controlSize(.small)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .lineLimit(3)
                .font(.callout)
        }
    }

    private func runTest() {
        test = .running
        Task {
            do {
                var config = try Preferences.serverConfigIgnoringURL()
                config.publicURL = publicURL
                try await makeUploader(for: config).testConnection()
                test = .success
            } catch {
                test = .failure(error.localizedDescription)
            }
        }
    }

    private func chooseKey() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL.homeDirectory.appending(path: ".ssh")
        panel.showsHiddenFiles = true
        panel.prompt = "Use Key"
        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        }
    }
}
