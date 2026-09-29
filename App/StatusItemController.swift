import AppKit
import SwiftUI

/// Owns the menu bar icon: accepts file drops on it, shows upload progress and toggles the popover.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var isDragging = false {
        didSet { updateIcon() }
    }

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        super.init()

        let hosting = NSHostingController(rootView: PopoverView(
            model: model,
            openSettings: { [weak self] in
                self?.popover.performClose(nil)
                openSettings()
            }
        ))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.setAccessibilityLabel("FileShuttle")
            // A transparent view on top of the button receives drags (and clicks).
            let dropView = StatusDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onClick = { [weak self] in self?.togglePopover() }
            dropView.onDragChange = { [weak self] in self?.isDragging = $0 }
            dropView.onDrop = { [weak self] in self?.model.upload(files: $0) }
            button.addSubview(dropView)
        }

        updateIcon()
        observeModel()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            addSolidBackground()
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
            updateIcon()
        }
    }

    /// Paints the whole popover (arrow included) with the window color, replacing the translucent
    /// material that lets busy wallpapers show through.
    private func addSolidBackground() {
        guard let frameView = popover.contentViewController?.view.window?.contentView?.superview,
              !frameView.subviews.contains(where: { $0 is PopoverBackgroundView }) else { return }
        let background = PopoverBackgroundView(frame: frameView.bounds)
        background.autoresizingMask = [.width, .height]
        frameView.addSubview(background, positioned: .below, relativeTo: nil)
    }

    func popoverDidClose(_ notification: Notification) {
        updateIcon()
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.iconState
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.observeModel()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.image(for: model.iconState, highlighted: isDragging)
        button.highlight(isDragging || popover.isShown)
    }
}

private final class PopoverBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PopoverStyle.topColor.setFill()
        dirtyRect.fill()
    }
}

/// Transparent overlay on the status bar button. It's the drop target for files dragged onto
/// the menu bar icon, and forwards clicks since it sits above the button.
final class StatusDropView: NSView {
    var onClick: () -> Void = {}
    var onDragChange: (Bool) -> Void = { _ in }
    var onDrop: ([URL]) -> Void = { _ in }

    private let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Plain file URLs (Finder) plus file promises (screenshot thumbnail, Photos, browsers).
        registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick()
    }

    // MARK: NSDraggingDestination

    private func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private func promises(_ pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        guard !fileURLs(pasteboard).isEmpty || !promises(pasteboard).isEmpty else { return [] }
        onDragChange(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragChange(false)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        onDragChange(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDragChange(false)
        let pasteboard = sender.draggingPasteboard

        let urls = fileURLs(pasteboard)
        if !urls.isEmpty {
            onDrop(urls)
            return true
        }

        let receivers = promises(pasteboard)
        guard !receivers.isEmpty, let destination = try? Staging.makeTempDirectory() else { return false }
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: destination, operationQueue: promiseQueue) { @Sendable [weak self] url, error in
                guard error == nil else { return }
                Task { @MainActor in self?.onDrop([url]) }
            }
        }
        return true
    }
}

/// Menu bar paper plane: an outline at rest, filling with green from the bottom while uploading,
/// fully green for a moment when done and red after a failure.
enum StatusIcon {
    private static let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
    private static let outline = NSImage(systemSymbolName: "paperplane", accessibilityDescription: "FileShuttle")!
        .withSymbolConfiguration(config)!
    private static let filled = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "FileShuttle")!
        .withSymbolConfiguration(config)!

    static func image(for state: IconState, highlighted: Bool) -> NSImage {
        switch state {
        case .idle:
            // Template images adapt to the menu bar (light, dark, tinted) automatically.
            let image = (highlighted ? filled : outline).copy() as! NSImage
            image.isTemplate = true
            return image
        case .uploading(let progress):
            // The plane widens from its bottom tip, so fill height ∝ √progress keeps the
            // green area proportional to progress. Always show a bit so it's clear something started.
            return plane(fill: max(0.18, sqrt(min(max(progress, 0), 1))), color: .systemGreen)
        case .success:
            return plane(fill: 1, color: .systemGreen)
        case .failure:
            return plane(fill: 1, color: .systemRed)
        }
    }

    /// Outline in the menu bar's text color with `fill` (0…1) of the plane coloured from the bottom up.
    /// Drawn lazily, so `labelColor` resolves against the status bar's current appearance.
    private static func plane(fill: Double, color: NSColor) -> NSImage {
        let image = NSImage(size: outline.size, flipped: false) { rect in
            if fill < 1 {
                tinted(outline, .labelColor).draw(in: rect)
            }
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: 0, y: 0, width: rect.width, height: rect.height * fill).clip()
            tinted(filled, color).draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.accessibilityDescription = "FileShuttle"
        return image
    }

    private static func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
