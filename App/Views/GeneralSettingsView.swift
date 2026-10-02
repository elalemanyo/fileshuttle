import KeyboardShortcuts
import ServiceManagement
import ShuttleKit
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(PrefKey.filenameStyle) private var filenameStyle = FilenameStyle.originalWithHash
    @AppStorage(PrefKey.multipleFiles) private var multipleFiles = MultipleFilesMode.zip
    @AppStorage(PrefKey.uploadScreenshots) private var uploadScreenshots = false
    @AppStorage(PrefKey.notify) private var notify = true
    @AppStorage(PrefKey.playSound) private var playSound = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var checkForUpdates = Updater.shared.automaticallyChecksForUpdates
    @State private var installUpdates = Updater.shared.automaticallyDownloadsUpdates
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Uploads") {
                Picker("File names", selection: $filenameStyle) {
                    ForEach(FilenameStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                LabeledContent("Example") {
                    Text(filenameStyle.example).foregroundStyle(.secondary)
                }
                Picker("Multiple files", selection: $multipleFiles) {
                    ForEach(MultipleFilesMode.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle(isOn: $uploadScreenshots) {
                    Text("Upload new screenshots automatically")
                    Text("Watches \((ScreenshotWatcher.screenshotDirectory.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)")
                }
                KeyboardShortcuts.Recorder("Upload clipboard", name: .uploadClipboard)
            }

            Section {
                Toggle("Show a notification", isOn: $notify)
                Toggle("Play a sound", isOn: $playSound)
            } header: {
                Text("When an upload finishes")
            } footer: {
                Text("The link is always copied to the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if Updater.shared.isConfigured {
                Section("Updates") {
                    Toggle("Automatically check for updates", isOn: $checkForUpdates)
                        .onChange(of: checkForUpdates) { _, enabled in
                            Updater.shared.automaticallyChecksForUpdates = enabled
                        }
                    Toggle("Automatically download and install updates", isOn: $installUpdates)
                        .disabled(!checkForUpdates)
                        .onChange(of: installUpdates) { _, enabled in
                            Updater.shared.automaticallyDownloadsUpdates = enabled
                        }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("FileShuttle").font(.title2.weight(.semibold))
            Text(version).foregroundStyle(.secondary)
            if Updater.shared.isConfigured {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.canCheckForUpdates)
            }
            Text("Drop files on the menu bar icon and get a shareable link.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            VStack(spacing: 4) {
                Link("Based on the original FileShuttle", destination: URL(string: "https://github.com/FileShuttle/fileshuttle")!)
                Link("Design inspired by BucketDrop", destination: URL(string: "https://github.com/fayazara/bucketdrop")!)
            }
            .font(.callout)
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
