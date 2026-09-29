import Foundation

/// Reports new screenshots using Spotlight's `kMDItemIsScreenCapture` flag,
/// so it works whatever the screenshot folder or file naming is.
final class ScreenshotWatcher {
    private let query = NSMetadataQuery()
    private let onScreenshot: (URL) -> Void
    private var startedAt = Date.now
    private var seen = Set<String>()

    init(onScreenshot: @escaping (URL) -> Void) {
        self.onScreenshot = onScreenshot
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [Self.screenshotDirectory]
        query.notificationBatchingInterval = 0.5
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
    }

    var isRunning: Bool { query.isStarted }

    func start() {
        guard !query.isStarted else { return }
        startedAt = .now
        query.start()
    }

    func stop() {
        query.stop()
    }

    /// Where macOS saves screenshots (`defaults read com.apple.screencapture location`), falling back to Desktop.
    static var screenshotDirectory: URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !location.isEmpty {
            return URL(filePath: (location as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return URL.desktopDirectory
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        let added = (notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem]) ?? []
        let changed = (notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem]) ?? []

        for item in added + changed {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seen.contains(path),
                  let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date,
                  created >= startedAt,
                  FileManager.default.fileExists(atPath: path) else { continue }
            seen.insert(path)
            onScreenshot(URL(filePath: path))
        }
    }
}
