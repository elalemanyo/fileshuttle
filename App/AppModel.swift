import AppKit
import KeyboardShortcuts
import Observation
import OSLog
import ShuttleKit

private let log = Logger(subsystem: "de.elalemanyo.FileShuttle", category: "upload")

enum IconState: Equatable {
    case idle
    case uploading(Double)
    case success
    case failure
}

struct UploadJob: Identifiable {
    let id = UUID()
    var name: String
    var progress: Double = 0
    var task: Task<Void, Never>?
}

@Observable
final class AppModel {
    let history: HistoryStore
    private(set) var jobs: [UploadJob] = []
    var errorMessage: String?
    private(set) var isConfigured = Preferences.isConfigured

    /// Brief ✓ / ⚠︎ shown in the menu bar after an upload finishes.
    private var flash: IconState?
    private var flashTask: Task<Void, Never>?

    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private lazy var screenshots = ScreenshotWatcher { [weak self] url in
        self?.upload(files: [url])
    }

    var iconState: IconState {
        if !jobs.isEmpty {
            return .uploading(jobs.map(\.progress).reduce(0, +) / Double(jobs.count))
        }
        return flash ?? .idle
    }

    init(history: HistoryStore = HistoryStore()) {
        self.history = history
        Preferences.registerDefaults()
        if Preferences.notify { notifier.requestAuthorization() }
        KeyboardShortcuts.onKeyUp(for: .uploadClipboard) { [weak self] in
            self?.uploadClipboard()
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }
        preferencesChanged()
    }

    private func preferencesChanged() {
        let configured = Preferences.isConfigured
        if configured != isConfigured { isConfigured = configured }
        if Preferences.uploadScreenshots {
            screenshots.start()
        } else if screenshots.isRunning {
            screenshots.stop()
        }
    }

    // MARK: - Uploading

    /// Entry point for drops, the file picker and screenshots.
    func upload(files urls: [URL]) {
        guard !urls.isEmpty else { return }
        let containsFolder = urls.contains { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        if containsFolder || (urls.count > 1 && Preferences.multipleFiles == .zip) {
            let name = urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "\(urls.count) files.zip"
            start(name: name) {
                [try await Staging.zip(urls, name: name)]
            }
        } else {
            let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
            start(name: name) {
                urls.map { StagedFile(url: $0, displayName: $0.lastPathComponent, tempDirectory: nil) }
            }
        }
    }

    func uploadClipboard() {
        do {
            let files = try Staging.fromClipboard()
            start(name: files.count == 1 ? files[0].displayName : "\(files.count) files") { files }
        } catch {
            report(error, name: "Clipboard")
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Upload"
        NSApp.activate()
        if panel.runModal() == .OK {
            upload(files: panel.urls)
        }
    }

    #if DEBUG
    /// Shows a fake in-progress upload, for screenshots.
    func showDemoJob(name: String, progress: Double) {
        jobs.append(UploadJob(name: name, progress: progress))
    }
    #endif

    func cancel(_ job: UploadJob) {
        job.task?.cancel()
    }

    private func start(name: String, prepare: @escaping () async throws -> [StagedFile]) {
        guard isConfigured else {
            report(UploadError.notConfigured, name: name)
            return
        }
        errorMessage = nil
        log.info("Starting upload: \(name, privacy: .public)")
        var job = UploadJob(name: name)
        let id = job.id
        job.task = Task { [weak self] in
            await self?.run(jobID: id, name: name, prepare: prepare)
        }
        jobs.append(job)
    }

    private func run(jobID: UUID, name: String, prepare: () async throws -> [StagedFile]) async {
        var staged: [StagedFile] = []
        defer {
            staged.forEach { $0.cleanUp() }
            jobs.removeAll { $0.id == jobID }
        }

        do {
            let config = try Preferences.serverConfig()
            let uploader = makeUploader(for: config)
            let style = Preferences.filenameStyle
            staged = try await prepare()

            var links: [URL] = []
            for (index, file) in staged.enumerated() {
                let remoteName = style.remoteName(for: file.displayName)
                let base = Double(index) / Double(staged.count)
                let share = 1 / Double(staged.count)
                try await uploader.upload(file.url, as: remoteName) { fraction in
                    Task { @MainActor [weak self] in
                        self?.setProgress(base + fraction * share, for: jobID)
                    }
                }
                guard let link = config.shareURL(for: remoteName) else { continue }
                links.append(link)
                history.add(HistoryItem(
                    fileName: file.displayName,
                    remoteName: remoteName,
                    url: link,
                    size: Self.fileSize(file.url),
                    date: .now,
                    localPath: file.localFile?.path(percentEncoded: false),
                    server: Self.serverID(config)
                ))
            }

            log.info("Uploaded \(name, privacy: .public): \(links.map(\.absoluteString), privacy: .public)")
            copy(links.map(\.absoluteString).joined(separator: "\n"))
            if Preferences.playSound { NSSound(named: "Glass")?.play() }
            if Preferences.notify, let first = links.first {
                notifier.uploaded(staged.count == 1 ? staged[0].displayName : name, url: first)
            }
            showFlash(.success)
        } catch UploadError.cancelled {
            // User cancelled, nothing to report.
        } catch is CancellationError {
        } catch {
            report(error, name: name)
        }
    }

    private func setProgress(_ progress: Double, for id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].progress = progress
    }

    private func report(_ error: any Error, name: String) {
        log.error("Upload of \(name, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        errorMessage = error.localizedDescription
        if Preferences.notify { notifier.failed(name, error: error) }
        showFlash(.failure)
    }

    private func showFlash(_ state: IconState) {
        flash = state
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(state == .failure ? 4 : 2))
            guard !Task.isCancelled else { return }
            flash = nil
        }
    }

    // MARK: - History actions

    func copy(_ string: String) {
        guard !string.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func deleteFromServer(_ item: HistoryItem) {
        Task {
            do {
                let config = try Preferences.serverConfig()
                guard Self.serverID(config) == item.server else {
                    errorMessage = "\(item.fileName) was uploaded to a different server."
                    return
                }
                try await makeUploader(for: config).delete(remoteName: item.remoteName)
                history.remove(item)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private static func serverID(_ config: ServerConfig) -> String {
        "\(config.transferProtocol.rawValue)://\(config.username)@\(config.host):\(config.port)/\(config.remotePath)"
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
