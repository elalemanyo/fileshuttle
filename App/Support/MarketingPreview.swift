#if DEBUG
import AppKit
import SwiftUI

/// Debug helper: `FileShuttle --preview <file.png>` renders the README / release image:
/// the real popover with demo data over an illustrated background. 1280×800 pt at 2x.
///
/// Run it with argument-domain overrides so the header shows a demo server, e.g.
/// `-host files.example.com -protocol sftp -username demo -publicURL https://files.example.com/`.
enum MarketingPreview {
    static let size = NSSize(width: 1280, height: 800)
    private static let menuBarHeight: CGFloat = 30
    private static let iconCenterX: CGFloat = 962

    static func render(to url: URL) {
        NSApp.appearance = NSAppearance(named: .aqua)
        let popover = popoverImage()

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        drawSky()
        drawSun(at: NSPoint(x: 1000, y: 250))
        drawClouds()
        drawHills()
        drawFlightPath()
        drawMenuBar()
        drawPopover(popover)
        drawHeadline()

        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: - Popover

    /// The real `PopoverView`, rendered with demo history and an upload in progress.
    private static func popoverImage() -> NSImage {
        let model = AppModel(history: HistoryStore(items: demoItems()))
        model.showDemoJob(name: "Holiday photos.zip", progress: 0.64)

        let hosting = NSHostingView(rootView: PopoverView(model: model, openSettings: {}))
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        // Give Quick Look time to produce the thumbnails.
        for _ in 0..<20 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: .now + 0.1)
        }
        let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func drawPopover(_ content: NSImage) {
        let arrowHeight: CGFloat = 11, arrowWidth: CGFloat = 26, radius: CGFloat = 14
        let top = size.height - menuBarHeight - 4 - arrowHeight
        let frame = NSRect(x: iconCenterX - content.size.width / 2, y: top - content.size.height,
                           width: content.size.width, height: content.size.height)

        let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: iconCenterX - arrowWidth / 2 - 4, y: frame.maxY))
        arrow.curve(to: NSPoint(x: iconCenterX, y: frame.maxY + arrowHeight),
                    controlPoint1: NSPoint(x: iconCenterX - arrowWidth / 2 + 4, y: frame.maxY),
                    controlPoint2: NSPoint(x: iconCenterX - 3, y: frame.maxY + arrowHeight))
        arrow.curve(to: NSPoint(x: iconCenterX + arrowWidth / 2 + 4, y: frame.maxY),
                    controlPoint1: NSPoint(x: iconCenterX + 3, y: frame.maxY + arrowHeight),
                    controlPoint2: NSPoint(x: iconCenterX + arrowWidth / 2 - 4, y: frame.maxY))
        arrow.close()
        path.append(arrow)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 40
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        shadow.set()
        PopoverStyle.topColor.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).addClip()
        content.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    // MARK: - Demo data

    private static func demoItems() -> [HistoryItem] {
        let dir = FileManager.default.temporaryDirectory.appending(path: "FileShuttlePreview", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let screenshot = writeImage(dir.appending(path: "screenshot.png"), size: NSSize(width: 640, height: 400), draw: drawDemoScreenshot)
        let sunset = writeImage(dir.appending(path: "sunset.png"), size: NSSize(width: 600, height: 600), draw: drawDemoPhoto)
        let palette = writeImage(dir.appending(path: "palette.png"), size: NSSize(width: 600, height: 600), draw: drawDemoPalette)

        func item(_ name: String, _ size: Int64, minutesAgo: Double, file: URL? = nil) -> HistoryItem {
            HistoryItem(fileName: name, remoteName: name, url: URL(string: "https://files.example.com/\(name)")!,
                        size: size, date: .now - minutesAgo * 60,
                        localPath: file?.path(percentEncoded: false), server: "demo")
        }
        return [
            item("Screenshot 2026-09-29 at 09.41.png", 812_000, minutesAgo: 0.5, file: screenshot),
            item("invoice-september.pdf", 96_000, minutesAgo: 12),
            item("sunset-lisbon.jpg", 2_400_000, minutesAgo: 47, file: sunset),
            item("product-demo.mp4", 48_200_000, minutesAgo: 180),
            item("brand-colors.png", 364_000, minutesAgo: 60 * 26, file: palette),
            item("meeting-notes.txt", 4_000, minutesAgo: 60 * 50),
        ]
    }

    private static func writeImage(_ url: URL, size: NSSize, draw: @escaping (NSRect) -> Void) -> URL {
        let image = NSImage(size: size, flipped: false) { rect in draw(rect); return true }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
        return url
    }

    private static func drawDemoScreenshot(_ rect: NSRect) {
        NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.45, blue: 0.95, alpha: 1),
                   ending: NSColor(srgbRed: 0.67, green: 0.38, blue: 0.88, alpha: 1))!.draw(in: rect, angle: -30)
        let window = rect.insetBy(dx: 70, dy: 50)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: window, xRadius: 14, yRadius: 14).fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: window.minX + 20 + CGFloat(i) * 22, y: window.maxY - 30, width: 13, height: 13)).fill()
        }
        NSColor(white: 0.9, alpha: 1).setFill()
        for i in 0..<6 {
            let width = [380, 300, 420, 260, 340, 200][i]
            NSBezierPath(roundedRect: NSRect(x: window.minX + 30, y: window.maxY - 80 - CGFloat(i) * 38, width: CGFloat(width), height: 16),
                         xRadius: 8, yRadius: 8).fill()
        }
    }

    private static func drawDemoPhoto(_ rect: NSRect) {
        NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.55, blue: 0.35, alpha: 1),
                            NSColor(srgbRed: 0.99, green: 0.80, blue: 0.55, alpha: 1)])!.draw(in: rect, angle: 90)
        NSColor(srgbRed: 1, green: 0.95, blue: 0.8, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 220, y: 230, width: 160, height: 160)).fill()
        NSColor(srgbRed: 0.25, green: 0.30, blue: 0.55, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: rect.width, height: 250).fill()
        NSColor(srgbRed: 0.18, green: 0.20, blue: 0.40, alpha: 1).setFill()
        let hill = NSBezierPath()
        hill.move(to: .zero)
        hill.curve(to: NSPoint(x: rect.width, y: 180), controlPoint1: NSPoint(x: 200, y: 360), controlPoint2: NSPoint(x: 400, y: 120))
        hill.line(to: NSPoint(x: rect.width, y: 0))
        hill.fill()
    }

    private static func drawDemoPalette(_ rect: NSRect) {
        let colors: [NSColor] = [.systemPink, .systemOrange, .systemYellow, .systemTeal, .systemIndigo, .systemPurple]
        let band = rect.width / CGFloat(colors.count)
        for (i, color) in colors.enumerated() {
            color.setFill()
            NSRect(x: CGFloat(i) * band, y: 0, width: band + 1, height: rect.height).fill()
        }
    }

    // MARK: - Background art

    private static func drawSky() {
        NSGradient(colors: [
            NSColor(srgbRed: 1.00, green: 0.80, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.96, green: 0.74, blue: 0.72, alpha: 1),
            NSColor(srgbRed: 0.62, green: 0.70, blue: 0.93, alpha: 1),
            NSColor(srgbRed: 0.32, green: 0.47, blue: 0.86, alpha: 1),
        ], atLocations: [0, 0.3, 0.62, 1], colorSpace: .sRGB)!
            .draw(in: NSRect(origin: .zero, size: size), angle: 90)
    }

    private static func drawSun(at center: NSPoint) {
        NSGradient(colors: [NSColor(srgbRed: 1, green: 0.95, blue: 0.8, alpha: 0.95),
                            NSColor(srgbRed: 1, green: 0.85, blue: 0.6, alpha: 0.35),
                            NSColor(srgbRed: 1, green: 0.8, blue: 0.6, alpha: 0)],
                   atLocations: [0, 0.25, 1], colorSpace: .sRGB)!
            .draw(fromCenter: center, radius: 0, toCenter: center, radius: 420, options: [])
    }

    private static func drawClouds() {
        // Kept clear of the headline area (x < 760, y 240…640) so the text stays readable.
        cloud(center: NSPoint(x: 110, y: 745), scale: 0.75)
        cloud(center: NSPoint(x: 600, y: 745), scale: 0.8)
        cloud(center: NSPoint(x: 1210, y: 560), scale: 1.1)
        cloud(center: NSPoint(x: 1250, y: 300), scale: 0.8)
        cloud(center: NSPoint(x: 790, y: 150), scale: 0.55)
    }

    /// A fluffy cloud: overlapping puffs with a soft edge, lit from above and warm underneath.
    private static func cloud(center: NSPoint, scale: CGFloat) {
        let puffs: [(CGFloat, CGFloat, CGFloat)] = [
            (-120, 0, 60), (-60, 30, 80), (20, 50, 95), (100, 25, 75), (160, 0, 55), (0, -10, 70), (-170, -15, 40),
        ]
        let path = NSBezierPath()
        for (dx, dy, r) in puffs {
            let radius = r * scale
            path.appendOval(in: NSRect(x: center.x + dx * scale - radius, y: center.y + dy * scale - radius,
                                       width: radius * 2, height: radius * 2))
        }
        path.windingRule = .nonZero

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = NSColor.white.withAlphaComponent(0.7)
        glow.shadowBlurRadius = 30 * scale
        glow.set()
        NSColor.white.withAlphaComponent(0.85).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [NSColor(srgbRed: 1, green: 0.84, blue: 0.74, alpha: 0.75),
                            NSColor.white.withAlphaComponent(0)])!
            .draw(in: NSRect(x: center.x - 260 * scale, y: center.y - 100 * scale, width: 520 * scale, height: 150 * scale), angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawHills() {
        let layers: [(NSColor, [CGFloat])] = [
            (NSColor(srgbRed: 0.62, green: 0.60, blue: 0.82, alpha: 0.75), [210, 250, 190, 240, 200]),
            (NSColor(srgbRed: 0.45, green: 0.45, blue: 0.72, alpha: 0.85), [150, 120, 175, 130, 160]),
            (NSColor(srgbRed: 0.30, green: 0.31, blue: 0.56, alpha: 1), [80, 110, 70, 95, 60]),
        ]
        for (color, heights) in layers {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: 0))
            path.line(to: NSPoint(x: 0, y: heights[0]))
            let step = size.width / CGFloat(heights.count - 1)
            for i in 1..<heights.count {
                let x0 = CGFloat(i - 1) * step, x1 = CGFloat(i) * step
                path.curve(to: NSPoint(x: x1, y: heights[i]),
                           controlPoint1: NSPoint(x: x0 + step * 0.5, y: heights[i - 1]),
                           controlPoint2: NSPoint(x: x1 - step * 0.5, y: heights[i]))
            }
            path.line(to: NSPoint(x: size.width, y: 0))
            path.close()
            color.setFill()
            path.fill()
        }
    }

    /// A paper plane with a dashed loop trail, bottom left.
    private static func drawFlightPath() {
        let trail = NSBezierPath()
        trail.move(to: NSPoint(x: -20, y: 50))
        trail.curve(to: NSPoint(x: 300, y: 110), controlPoint1: NSPoint(x: 140, y: 20), controlPoint2: NSPoint(x: 250, y: 40))
        trail.curve(to: NSPoint(x: 240, y: 190), controlPoint1: NSPoint(x: 340, y: 170), controlPoint2: NSPoint(x: 290, y: 215))
        trail.curve(to: NSPoint(x: 560, y: 185), controlPoint1: NSPoint(x: 190, y: 160), controlPoint2: NSPoint(x: 380, y: 100))
        trail.lineWidth = 3
        trail.lineCapStyle = .round
        trail.setLineDash([2, 12], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.85).setStroke()
        trail.stroke()

        let config = NSImage.SymbolConfiguration(pointSize: 54, weight: .regular)
        guard let plane = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let white = NSImage(size: plane.size, flipped: false) { rect in
            plane.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        white.draw(in: NSRect(x: 552, y: 172, width: plane.size.width, height: plane.size.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Menu bar

    private static func drawMenuBar() {
        let bar = NSRect(x: 0, y: size.height - menuBarHeight, width: size.width, height: menuBarHeight)
        NSColor.white.withAlphaComponent(0.35).setFill()
        bar.fill()

        let textColor = NSColor(white: 0.08, alpha: 1)
        let baseline = bar.minY + 7
        var x: CGFloat = 20
        for (index, title) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
            let attributed = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 13.5, weight: index == 0 ? .bold : .regular),
                .foregroundColor: textColor,
            ])
            attributed.draw(at: NSPoint(x: x, y: baseline))
            x += attributed.size().width + 20
        }

        // Status items, right to left: clock, control centre, battery, wifi, our plane.
        let clock = NSAttributedString(string: "Tue 29 Sep  9:41", attributes: [
            .font: NSFont.systemFont(ofSize: 13.5, weight: .medium), .foregroundColor: textColor,
        ])
        var right = size.width - 18 - clock.size().width
        clock.draw(at: NSPoint(x: right, y: baseline))
        for symbol in ["switch.2", "battery.75percent", "wifi", "magnifyingglass"] {
            right -= 40
            drawSymbol(symbol, centerX: right + 12, in: bar, color: textColor)
        }

        // Highlighted FileShuttle item.
        let highlight = NSRect(x: iconCenterX - 16, y: bar.minY + 3, width: 32, height: bar.height - 6)
        NSColor.white.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: highlight, xRadius: 6, yRadius: 6).fill()
        drawSymbol("paperplane", centerX: iconCenterX, in: bar, color: textColor)
    }

    private static func drawSymbol(_ name: String, centerX: CGFloat, in bar: NSRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: centerX - symbol.size.width / 2, y: bar.midY - symbol.size.height / 2,
                               width: symbol.size.width, height: symbol.size.height))
    }

    // MARK: - Headline

    private static func drawHeadline() {
        let left: CGFloat = 76
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 0.12, green: 0.14, blue: 0.38, alpha: 0.5)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -3)

        // App icon + name.
        let icon = NSApp.applicationIconImage!
        icon.draw(in: NSRect(x: left - 8, y: 548, width: 76, height: 76))
        NSAttributedString(string: "FileShuttle", attributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .bold),
            .foregroundColor: NSColor.white,
            .shadow: shadow,
        ]).draw(at: NSPoint(x: left + 76, y: 568))

        let headline = NSMutableParagraphStyle()
        headline.lineHeightMultiple = 0.92
        NSAttributedString(string: "Drop a file.\nGet a link.", attributes: [
            .font: NSFont.systemFont(ofSize: 76, weight: .heavy),
            .foregroundColor: NSColor.white,
            .shadow: shadow,
            .paragraphStyle: headline,
        ]).draw(in: NSRect(x: left, y: 350, width: 640, height: 190))

        let body = NSMutableParagraphStyle()
        body.lineHeightMultiple = 1.15
        NSAttributedString(
            string: "A tiny menu bar app that uploads to your own FTP, FTPS or SFTP server and puts the link on your clipboard.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.95),
                .shadow: shadow,
                .paragraphStyle: body,
            ]
        ).draw(in: NSRect(x: left, y: 262, width: 560, height: 80))
    }
}
#endif
