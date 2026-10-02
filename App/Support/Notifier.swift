import AppKit
import UserNotifications

/// Posts "upload finished" notifications; clicking one opens the link.
/// Also posts "update available", which opens Sparkle's update window when clicked.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func uploaded(_ name: String, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Link copied"
        content.body = name
        content.userInfo = ["url": url.absoluteString]
        post(content)
    }

    func failed(_ name: String, error: any Error) {
        let content = UNMutableNotificationContent()
        content.title = "Upload failed"
        content.body = "\(name): \(error.localizedDescription)"
        post(content)
    }

    /// Only posts if notifications are already allowed; we never ask for permission just for this.
    static func updateAvailable(version: String) {
        let center = UNUserNotificationCenter.current()
        Task {
            guard await center.notificationSettings().authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "FileShuttle \(version) is available"
            content.body = "Click to install the update."
            content.userInfo = ["action": "update"]
            try? await center.add(UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil))
        }
    }

    private func post(_ content: UNMutableNotificationContent) {
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if info["action"] as? String == "update" {
            await MainActor.run { Updater.shared.checkForUpdates() }
        } else if let string = info["url"] as? String,
           let url = URL(string: string) {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
    }
}
