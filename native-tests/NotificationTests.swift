import Foundation
import UserNotifications

@MainActor
final class NotificationCenterFixture: LocalNotificationCenter {
    var status: UNAuthorizationStatus = .notDetermined
    var grant = true
    var failure: NSError?
    var requests = 0
    var posted: [LocalChange] = []
    var reminders: [SchoolTaskReminder] = []
    var holdReminders = false
    var pendingReminder: CheckedContinuation<Void, Never>?

    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        requests += 1
        if let failure { throw failure }
        status = grant ? .authorized : .denied
        return grant
    }
    func post(_ change: LocalChange) async throws {
        if let failure { throw failure }
        posted.append(change)
    }
    func replaceTaskReminders(_ reminders: [SchoolTaskReminder]) async throws {
        if holdReminders {
            holdReminders = false
            await withCheckedContinuation { pendingReminder = $0 }
        }
        if let failure { throw failure }
        self.reminders = reminders
    }
}

@main
@MainActor
struct NotificationTests {
    static func main() async {
        let suite = "librus-notification-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenterFixture()
        var settingsOpened = false
        let notifications = SchoolNotifications(center: center, defaults: defaults) {
            settingsOpened = true
            return true
        }

        center.status = .denied
        await notifications.enable()
        assert(!notifications.enabled, "Denied permission must keep notifications disabled")
        assert(notifications.needsSettings && settingsOpened, "Denied permission must open settings")
        assert(notifications.message?.contains("Ustawienia") == true)
        assert(center.requests == 0, "Repeated requests cannot override a system denial")

        center.status = .authorized
        await notifications.refresh()
        assert(notifications.enabled, "Returning from settings must finish enabling notifications")
        assert(notifications.message == nil, "The old permission error must disappear")
        let restored = SchoolNotifications(center: center, defaults: defaults, openSettings: { true })
        await restored.refresh()
        assert(restored.enabled, "The notification preference must survive reopening the app")

        center.status = .denied
        await notifications.refresh()
        assert(!notifications.enabled, "Revoking permission must update the app's state")
        notifications.disable()
        center.status = .authorized
        await notifications.refresh()
        assert(!notifications.enabled, "System permission must not override the user's app switch")
        await notifications.post([LocalChange(title: "Synthetic", body: "Synthetic")])
        assert(center.posted.isEmpty, "The disabled switch must prevent notification delivery")

        center.status = .notDetermined
        await notifications.enable()
        assert(notifications.enabled && center.requests == 1)
        await notifications.sendTest()
        assert(center.posted.count == 1 && center.posted[0].title.contains("Test"))
        assert(notifications.message == "Powiadomienie testowe wysłane.")

        center.status = .notDetermined
        center.grant = false
        settingsOpened = false
        await notifications.enable()
        assert(!notifications.enabled && notifications.needsSettings && settingsOpened)

        center.status = .notDetermined
        center.failure = NSError(domain: "SyntheticNotificationError", code: 42)
        await notifications.enable()
        assert(!notifications.enabled && !notifications.busy)
        assert(notifications.message?.contains("SyntheticNotificationError, 42") == true)
        await taskReminders(notifications, center)
        print("Swift notifications: permissions, recovery, reminders, cancellation, privacy and in-flight clearing passed")
    }

    static func taskReminders(_ notifications: SchoolNotifications, _ center: NotificationCenterFixture) async {
        center.failure = nil
        center.status = .authorized
        await notifications.enable()
        let now = Date()
        let future = now.addingTimeInterval(3600)
        let task = SchoolTask(id: "task-one", title: "Synthetic private title", reminderAt: future)
        let past = SchoolTask(id: "past", title: "Past", reminderAt: now.addingTimeInterval(-1))
        let done = SchoolTask(id: "done", title: "Done", reminderAt: future, completedAt: now)
        notifications.setTasks([task, past, done], at: now)
        await wait { center.reminders.count == 1 }
        assert(center.reminders[0].taskID == "task-one" && center.reminders[0].fireAt == future)
        let request = center.reminders[0].request()
        assert(!request.content.title.contains(task.title) && !request.content.body.contains(task.title))
        assert(request.trigger is UNCalendarNotificationTrigger)
        var completed = task
        completed.completedAt = now
        notifications.setTasks([completed], at: now)
        await wait { center.reminders.isEmpty }
        notifications.setTasks([task], at: now)
        await wait { center.reminders.count == 1 }
        notifications.disable()
        await wait { center.reminders.isEmpty }
        await notifications.enable()
        await wait { center.reminders.count == 1 }
        center.holdReminders = true
        var updated = task
        updated.reminderAt = future.addingTimeInterval(60)
        notifications.setTasks([updated], at: now)
        await wait { center.pendingReminder != nil }
        notifications.setTasks([], at: now)
        center.pendingReminder?.resume()
        center.pendingReminder = nil
        await wait { center.reminders.isEmpty }
    }

    static func wait(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Reminder operation did not finish")
            await Task.yield()
        }
    }
}
