import AppKit
import UniformTypeIdentifiers

/// Temporary files the app creates (zips, clipboard contents). Deleted after upload.
struct StagedFile {
    let url: URL
    /// Name shown in history, e.g. "3 files.zip" or "Clipboard.png".
    let displayName: String
    /// Folder to remove once the upload is finished, if the file is temporary.
    let tempDirectory: URL?
    /// Original local file, when the upload is a real file on disk.
    var localFile: URL? { tempDirectory == nil ? url : nil }

    func cleanUp() {
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
    }
}

enum Staging {
    enum Failure: LocalizedError {
        case zipFailed
        case emptyClipboard

        var errorDescription: String? {
            switch self {
            case .zipFailed: "Couldn't create the zip archive."
            case .emptyClipboard: "The clipboard has nothing to upload."
            }
        }
    }

    nonisolated static func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "FileShuttle/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Zips `items` (files and/or folders) into one archive.
    @concurrent
    nonisolated static func zip(_ items: [URL], name: String) async throws -> StagedFile {
        let dir = try makeTempDirectory()
        let staging = dir.appending(path: "items", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        // Symlink everything into one folder so the archive has a flat, tidy root. `zip` follows symlinks.
        var used = Set<String>()
        for item in items {
            var linkName = item.lastPathComponent
            var counter = 2
            while used.contains(linkName) {
                linkName = "\(item.deletingPathExtension().lastPathComponent) \(counter).\(item.pathExtension)"
                counter += 1
            }
            used.insert(linkName)
            try FileManager.default.createSymbolicLink(at: staging.appending(path: linkName), withDestinationURL: item)
        }

        let archive = dir.appending(path: name)
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/zip")
        process.currentDirectoryURL = staging
        process.arguments = ["-r", "-q", "-X", archive.path(percentEncoded: false), "."]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: dir)
            throw Failure.zipFailed
        }
        return StagedFile(url: archive, displayName: name, tempDirectory: dir)
    }

    /// Writes whatever is on the clipboard to disk: files, an image or text.
    static func fromClipboard(_ pasteboard: NSPasteboard = .general) throws -> [StagedFile] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return urls.map { StagedFile(url: $0, displayName: $0.lastPathComponent, tempDirectory: nil) }
        }

        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let dir = try makeTempDirectory()
            let url = dir.appending(path: "Clipboard \(stamp).png")
            try png.write(to: url)
            return [StagedFile(url: url, displayName: url.lastPathComponent, tempDirectory: dir)]
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let dir = try makeTempDirectory()
            let url = dir.appending(path: "Clipboard \(stamp).txt")
            try Data(text.utf8).write(to: url)
            return [StagedFile(url: url, displayName: url.lastPathComponent, tempDirectory: dir)]
        }

        throw Failure.emptyClipboard
    }
}
