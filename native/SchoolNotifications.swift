import AppKit
import Combine
import OSLog
import UserNotifications

@MainActor
protocol LocalNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func post(_ change: LocalChange) async throws
    func replaceTaskReminders(_ reminders: [SchoolTaskReminder]) async throws
}

@MainActor
final class SystemLocalNotificationCenter: NSObject, LocalNotificationCenter, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ change: LocalChange) async throws {
        let content = UNMutableNotificationContent()
        content.title = "\(AppIdentity.name) · \(change.title)"
        content.body = change.body
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func replaceTaskReminders(_ reminders: [SchoolTaskReminder]) async throws {
        try await SchoolTaskReminders.replace(reminders, in: center)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@MainActor
final class SchoolNotifications: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsSettings = false
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    private let center: any LocalNotificationCenter
    private let defaults: UserDefaults
    private let openSettings: @MainActor () -> Bool
    private let preferenceKey = "localNotificationsEnabled"
    private let logger = Logger(subsystem: "local.librus.desktop", category: "notifications")
    private var taskReminders: [SchoolTaskReminder] = []
    private var reminderRevision = 0
    private var updatingReminders = false

    init(center: any LocalNotificationCenter = SystemLocalNotificationCenter(),
         defaults: UserDefaults = .standard,
         openSettings: @escaping @MainActor () -> Bool = SchoolNotifications.openSystemSettings) {
        self.center = center
        self.defaults = defaults
        self.openSettings = openSettings
    }

    func refresh() async {
        let status = await center.authorizationStatus()
        needsSettings = status == .denied
        enabled = defaults.bool(forKey: preferenceKey) && [.authorized, .provisional].contains(status)
        if enabled { message = nil }
        reminderRevision += 1
        await synchronizeReminders()
    }

    func enable() async {
        guard !busy else { return }
        busy = true
        enabled = false
        message = nil
        defaults.set(true, forKey: preferenceKey)
        defer { busy = false }
        await refresh()
        if needsSettings { showSettings(); return }
        do {
            if !enabled { _ = try await center.requestAuthorization() }
            await refresh()
            if needsSettings { showSettings() }
        } catch {
            await refresh()
            if needsSettings { showSettings() }
            else { report(error, operation: "włączyć powiadomień") }
        }
    }

    func disable() {
        defaults.set(false, forKey: preferenceKey)
        enabled = false
        message = nil
        reminderRevision += 1
        Task { await synchronizeReminders() }
    }

    func setTasks(_ tasks: [SchoolTask], at now: Date) {
        taskReminders = SchoolTaskReminders.pending(tasks, at: now)
        reminderRevision += 1
        Task { await refresh() }
    }

    /// Serialize system writes; a newer logout/disable must win over a suspended write.
    private func synchronizeReminders() async {
        guard !updatingReminders else { return }
        updatingReminders = true
        defer { updatingReminders = false }
        while true {
            let revision = reminderRevision
            let desired = enabled ? taskReminders.filter { $0.fireAt > Date() } : []
            do { try await center.replaceTaskReminders(desired) }
            catch { report(error, operation: "zaplanować przypomnienia") }
            if revision == reminderRevision { return }
        }
    }

    func post(_ changes: [LocalChange]) async {
        await refresh()
        guard enabled else { return }
        for change in changes {
            do { try await center.post(change) }
            catch { report(error, operation: "wyświetlić powiadomienia") }
        }
    }

    func sendTest() async {
        await refresh()
        guard enabled else { message = "Najpierw włącz powiadomienia."; return }
        do {
            try await center.post(LocalChange(title: "Test powiadomień", body: "Powiadomienia aplikacji Schoolside na tym Macu działają."))
            message = "Powiadomienie testowe wysłane."
        } catch { report(error, operation: "wyświetlić powiadomienia testowego") }
    }

    private func showSettings() {
        let opened = openSettings()
        message = opened
            ? "Ustawienia macOS → Powiadomienia → Schoolside: włącz powiadomienia, a potem wróć do aplikacji."
            : "Otwórz Ustawienia macOS → Powiadomienia → Schoolside i włącz powiadomienia."
    }

    private func report(_ error: Error, operation: String) {
        let failure = error as NSError
        logger.error("Notification operation failed: \(failure.domain, privacy: .public) \(failure.code)")
        message = "Nie udało się \(operation) (\(failure.domain), \(failure.code))."
    }

    private static func openSystemSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=local.librus.desktop")
        else { return false }
        return NSWorkspace.shared.open(url)
    }
}
