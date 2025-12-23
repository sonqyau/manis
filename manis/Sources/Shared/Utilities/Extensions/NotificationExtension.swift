import Foundation
import UserNotifications

enum NotificationExtension {
    static func sendNotification(title: String, body: String, category: String? = nil) async {
        guard await isNotificationAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let category {
            content.categoryIdentifier = category
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil,
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    static func isNotificationAuthorized() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let authorized = settings.authorizationStatus == .authorized ||
                    settings.authorizationStatus == .provisional
                continuation.resume(returning: authorized)
            }
        }
    }
}
