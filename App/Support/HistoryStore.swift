import Foundation
import Observation

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var fileName: String
    var remoteName: String
    var url: URL
    var size: Int64
    var date: Date
    /// Local file that was uploaded, used for thumbnails and "Show in Finder".
    var localPath: String?
    /// Server the file went to, so deleting only targets the same server.
    var server: String
}

/// Recent uploads, persisted as a small JSON file in Application Support.
@Observable
final class HistoryStore {
    private(set) var items: [HistoryItem] = []
    private let limit = 100
    /// nil for in-memory stores (demo data).
    private let fileURL: URL?

    init() {
        let dir = URL.applicationSupportDirectory.appending(path: "FileShuttle", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "history.json")
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
        }
    }

    /// In-memory store that never touches disk.
    init(items: [HistoryItem]) {
        self.items = items
        fileURL = nil
    }

    func add(_ item: HistoryItem) {
        items.insert(item, at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
        save()
    }

    func remove(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
