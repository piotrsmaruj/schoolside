import Foundation
import UserNotifications

@MainActor
final class NotificationCenterFixture: LocalNotificationCenter {
    var status: UNAuthorizationStatus = .notDetermined
    var grant = true
    var failure: NSError?
    var requests = 0
    var posted: [LocalChange] = []

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
        print("Swift notifications: denied permission, settings recovery, persistence, revocation and test delivery passed")
    }
}
