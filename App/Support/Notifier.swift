import AppKit
import UserNotifications

/// Posts "upload finished" notifications; clicking one opens the link.
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
        if let string = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: string) {
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }
    }
}
