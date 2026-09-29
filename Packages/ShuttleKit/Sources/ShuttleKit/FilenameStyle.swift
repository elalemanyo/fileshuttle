import Foundation

public enum FilenameStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case originalWithHash
    case hash
    case date

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .original: "Original filename"
        case .originalWithHash: "Filename + hash"
        case .hash: "Hash only"
        case .date: "Date and time"
        }
    }

    /// Example shown next to the picker in Settings.
    public var example: String {
        remoteName(for: "Screenshot 2026.png", hash: "k3x9q2", date: Date(timeIntervalSince1970: 1_790_000_000))
    }

    public func remoteName(for localName: String, hash: String = FilenameStyle.randomHash(), date: Date = .now) -> String {
        let url = URL(fileURLWithPath: localName)
        let ext = url.pathExtension
        let stem = Self.sanitize(url.deletingPathExtension().lastPathComponent)
        let suffix = ext.isEmpty ? "" : "." + ext.lowercased()

        switch self {
        case .original:
            return (stem.isEmpty ? hash : stem) + suffix
        case .originalWithHash:
            return (stem.isEmpty ? hash : "\(stem)-\(hash)") + suffix
        case .hash:
            return hash + suffix
        case .date:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd-HHmmss"
            return formatter.string(from: date) + "-" + hash.prefix(3) + suffix
        }
    }

    public static func randomHash(length: Int = 6) -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Makes a name safe for URLs: whitespace becomes "-", reserved characters are dropped.
    static func sanitize(_ name: String) -> String {
        let collapsed = name.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        let forbidden = CharacterSet(charactersIn: "/\\?#%&+:*\"<>|'`")
        return String(String.UnicodeScalarView(collapsed.unicodeScalars.filter { !forbidden.contains($0) }))
    }
}
