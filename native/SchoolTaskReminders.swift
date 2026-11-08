import Foundation
import UserNotifications

struct SchoolTaskReminder: Equatable, Sendable {
    static let identifierPrefix = "schoolside.task."
    let taskID: String
    let fireAt: Date
    var identifier: String { Self.identifierPrefix + taskID }

    func request() -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(AppIdentity.name) · Przypomnienie"
        content.body = "Masz zadanie do załatwienia. Otwórz Organizer w Schoolside."
        content.sound = .default
        content.userInfo = ["schoolsideTaskID": taskID]
        var date = SchoolDates.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
        date.timeZone = SchoolDates.calendar.timeZone
        return UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false))
    }
}

enum SchoolTaskReminders {
    static func pending(_ tasks: [SchoolTask], at now: Date) -> [SchoolTaskReminder] {
        tasks.compactMap { task in
            guard !task.isCompleted, let date = task.reminderAt,
                  date.timeIntervalSince1970.isFinite, date > now else { return nil }
            return SchoolTaskReminder(taskID: task.id, fireAt: date)
        }.sorted { ($0.fireAt, $0.taskID) < ($1.fireAt, $1.taskID) }
    }

    @MainActor
    static func replace(_ reminders: [SchoolTaskReminder], in center: UNUserNotificationCenter) async throws {
        let desired = Set(reminders.map(\.identifier))
        let pending = await center.pendingNotificationRequests()
        let obsolete = pending.map(\.identifier).filter {
            $0.hasPrefix(SchoolTaskReminder.identifierPrefix) && !desired.contains($0)
        }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        let delivered = await center.deliveredNotifications()
        let cleared = delivered.map { $0.request.identifier }.filter {
            $0.hasPrefix(SchoolTaskReminder.identifierPrefix) && !desired.contains($0)
        }
        center.removeDeliveredNotifications(withIdentifiers: cleared)
        for reminder in reminders { try await center.add(reminder.request()) }
    }
}
