import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct HistoryList: View {
    let model: AppModel
    @State private var pendingDelete: HistoryItem?

    private let rowHeight: CGFloat = 56
    private let maxHeight: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Uploads")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            if model.history.items.isEmpty {
                Text("Uploads will appear here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.history.items) { item in
                            HistoryRow(item: item, model: model) { pendingDelete = item }
                            if item.id != model.history.items.last?.id {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.automatic)
                .frame(height: min(CGFloat(model.history.items.count) * rowHeight + 6, maxHeight))
            }
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.fileName ?? "") from the server?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let item = pendingDelete { model.deleteFromServer(item) }
            }
        } message: {
            Text("The link will stop working. This can't be undone.")
        }
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let model: AppModel
    let requestDelete: () -> Void

    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(item: item)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(copied ? "Link copied" : subtitle)
                    .font(.caption)
                    .foregroundStyle(copied ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovering {
                HStack(spacing: 0) {
                    IconButton("doc.on.doc", help: "Copy link") { copyLink() }
                    IconButton("arrow.up.right.square", help: "Open in browser") { NSWorkspace.shared.open(item.url) }
                }
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { copyLink() }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .contextMenu {
            Button("Copy Link") { copyLink() }
            Button("Open in Browser") { NSWorkspace.shared.open(item.url) }
            if let path = item.localPath, FileManager.default.fileExists(atPath: path) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
                }
            }
            Divider()
            Button("Remove from History") { model.history.remove(item) }
            Button("Delete from Server…", role: .destructive, action: requestDelete)
        }
        .help(item.url.absoluteString)
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        return "\(size) · \(item.date.formatted(.relative(presentation: .named)))"
    }

    private func copyLink() {
        model.copy(item.url.absoluteString)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    init(_ symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// 36pt rounded tile: a Quick Look thumbnail of the local file, or a symbol for its type.
private struct Thumbnail: View {
    let item: HistoryItem
    @State private var image: NSImage?

    private let size: CGFloat = 36
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        ZStack {
            shape.fill(Color.primary.opacity(0.05))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: Self.symbol(for: item.fileName))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .task(id: item.id) {
            image = await Self.thumbnail(for: item, size: size)
        }
    }

    private static let cache = NSCache<NSString, NSImage>()

    private static func thumbnail(for item: HistoryItem, size: CGFloat) async -> NSImage? {
        guard let path = item.localPath, FileManager.default.fileExists(atPath: path) else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(filePath: path),
            size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        cache.setObject(rep.nsImage, forKey: path as NSString)
        return rep.nsImage
    }

    private static func symbol(for name: String) -> String {
        guard let type = UTType(filenameExtension: URL(filePath: name).pathExtension) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) { return "video" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .sourceCode) { return "chevron.left.forwardslash.chevron.right" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}
