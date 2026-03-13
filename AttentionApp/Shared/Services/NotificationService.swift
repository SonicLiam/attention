import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Schedule

    func scheduleNotification(for todoId: UUID, title: String, date: Date, offset: ReminderOffset) {
        let fireDate = date.addingTimeInterval(offset.timeInterval)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Attention"
        content.body = title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let identifier = notificationId(todoId: todoId, offset: offset)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request)
    }

    func cancelNotifications(for todoId: UUID) {
        let identifiers = ReminderOffset.allCases.map { notificationId(todoId: todoId, offset: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func notificationId(todoId: UUID, offset: ReminderOffset) -> String {
        "todo-\(todoId.uuidString)-\(offset.rawValue)"
    }
}
