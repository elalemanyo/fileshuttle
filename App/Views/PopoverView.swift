import SwiftUI
import UniformTypeIdentifiers

/// Solid backgrounds (like BucketDrop) instead of the translucent popover material:
/// a light gray top with the drop zone and a white list below.
enum PopoverStyle {
    static let topColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.17, alpha: 1)
            : NSColor(white: 0.955, alpha: 1)
    }
    static let listColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1)
            : NSColor.white
    }
    static let top = Color(nsColor: topColor)
    static let list = Color(nsColor: listColor)
}

struct PopoverView: View {
    let model: AppModel
    let openSettings: () -> Void

    @AppStorage(PrefKey.host) private var host = ""
    @AppStorage(PrefKey.transferProtocol) private var transferProtocol = "sftp"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isConfigured {
                VStack(spacing: 10) {
                    DropZone(model: model)
                    ForEach(model.jobs) { job in
                        JobRow(job: job) { model.cancel(job) }
                    }
                    if let error = model.errorMessage {
                        ErrorBanner(message: error) { model.errorMessage = nil }
                    }
                }
                .padding(16)
                .animation(.snappy, value: model.jobs.map(\.id))

                Divider()
                HistoryList(model: model)
                    .background(PopoverStyle.list)
            } else {
                NotConfiguredView(openSettings: openSettings)
            }
        }
        .frame(width: 320)
        .background(PopoverStyle.top)
        // The popover becomes key when opened, which would draw a focus ring on the first control.
        .focusEffectDisabled()
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("FileShuttle").font(.headline)
                if !host.isEmpty {
                    Text("\(transferProtocol.uppercased()) · \(host)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()

            Menu {
                Button("Upload Clipboard") { model.uploadClipboard() }
                Button("Choose Files…") { model.chooseFiles() }
                Divider()
                Button("Clear History", role: .destructive) { model.history.clear() }
                    .disabled(model.history.items.isEmpty)
                Divider()
                Button("Quit FileShuttle") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")

            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Drop zone

private struct DropZone: View {
    let model: AppModel
    @State private var isTargeted = false
    @State private var isHovering = false

    var body: some View {
        Button {
            model.chooseFiles()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "arrow.down.circle" : "arrow.up.circle")
                    .font(.system(size: 28, weight: .light))
                    .contentTransition(.symbolEffect(.replace))
                Text(isTargeted ? "Release to upload" : "Drop files here or click to select")
                    .font(.callout)
            }
            .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(Color.primary.opacity(isHovering ? 0.08 : 0.05)))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.primary.opacity(0.1)), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadFileURL() { urls.append(url) }
                }
                model.upload(files: urls)
            }
            return true
        }
    }
}

private extension NSItemProvider {
    func loadFileURL() async throws -> URL? {
        let item = try await loadItem(forTypeIdentifier: UTType.fileURL.identifier)
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return item as? URL
    }
}

// MARK: - Active uploads

private struct JobRow: View {
    let job: UploadJob
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.name).font(.callout).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(job.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
            }
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Cancel upload")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NotConfiguredView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text("Connect a server").font(.headline)
            Text("Add your FTP or SFTP server and the public URL where uploaded files are served.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings…", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
