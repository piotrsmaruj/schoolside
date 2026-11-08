import Foundation
import UserNotifications

@MainActor
final class OrganizerSecrets: SecretStore {
    var values: [String: Data] = [:]
    var fail = false
    func read(_ key: String) throws -> Data? {
        if fail { throw DesktopError.cache }
        return values[key]
    }
    func write(_ key: String, data: Data) throws { values[key] = data }
    func delete(_ key: String) throws { values[key] = nil }
}

@MainActor
final class OrganizerCenter: LocalNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func post(_ change: LocalChange) async throws { fatalError("Unexpected notification") }
    func replaceTaskReminders(_ reminders: [SchoolTaskReminder]) async throws { }
}

actor OrganizerBackend: SchoolBackendRunning {
    var current = SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-11-08", sections: [
        "homework": [SchoolItem(id: "h1", title: "Zadanie", date: "2026-11-10", homeworkDueDate: "2026-11-10")],
    ])
    var waiting: CheckedContinuation<Void, Never>?
    var hold = false
    var failAuthentication = false
    var isWaiting: Bool { waiting != nil }
    func holdNext() { hold = true }
    func release() { waiting?.resume(); waiting = nil }
    func set(_ value: SchoolSnapshot) { current = value }
    func expireSession() { failAuthentication = true }
    func run(_ request: SchoolRequest) async throws -> SchoolResponse {
        precondition(request.operation == "sync")
        if hold { hold = false; await withCheckedContinuation { waiting = $0 } }
        if failAuthentication { failAuthentication = false; throw DesktopError.remote("auth_failed") }
        return SchoolResponse(ok: true, session: nil, snapshot: current, message: nil, attachment: nil, errorCode: nil)
    }
}

@main
@MainActor
struct OrganizerModelTests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-08T12:00:00Z")!

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "schoolside-organizer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = OrganizerSecrets()
        let vault = SecureVault(secrets: secrets, cacheURL: directory.appending(path: "snapshot.enc"))
        try vault.saveAccount(LoginInput(login: "1234567", password: "synthetic"))
        let backend = OrganizerBackend()
        let notifications = SchoolNotifications(center: OrganizerCenter(), defaults: defaults)
        let model = SchoolViewModel(backend: backend, vault: vault, notifications: notifications, now: { now })
        defer { model.stop() }
        model.bootstrap()
        try await wait { model.snapshot != nil && !model.busy }
        assert(model.organizerTasks.count == 1)
        let homeworkID = model.organizerTasks[0].id
        assert(model.completeTask(homeworkID, completed: true))
        let saved = try vault.loadSnapshot()
        assert(saved?.organizer?.tasks[0].isCompleted == true)
        try await editingDuringSync(model, backend)
        failedWriteIsNotPublished(model, secrets)
        try await reauthenticationKeepsTasks(model, backend)
        try await missingSourceAndRestore(model, backend, vault, notifications)
        model.logout()
        assert(model.organizerTasks.isEmpty && secrets.values.isEmpty)
        let cleared = try vault.loadSnapshot()
        assert(cleared == nil)
        print("Swift organizer model: persistence, in-flight edits, failed writes, archived source, restart and logout passed")
    }

    static func reauthenticationKeepsTasks(_ model: SchoolViewModel, _ backend: OrganizerBackend) async throws {
        await backend.expireSession()
        model.refresh()
        try await wait { !model.busy && !model.signedIn }
        assert(model.organizerTasks.count == 2)
        model.login(LoginInput(login: "1234567", password: "synthetic-new-password"))
        try await wait { !model.busy && model.signedIn }
        assert(model.organizerTasks.count == 2, "Renewing credentials for the same parent must preserve local tasks")
        assert(model.organizerTasks.first { $0.isAutomatic }?.isCompleted == true)
    }

    static func editingDuringSync(_ model: SchoolViewModel, _ backend: OrganizerBackend) async throws {
        await backend.holdNext()
        model.refresh()
        try await wait { await backend.isWaiting }
        let own = SchoolTask(id: "own", title: "Podpisać zgodę", dueDate: "2026-11-09")
        assert(model.saveTask(own))
        await backend.release()
        try await wait { !model.busy }
        assert(model.organizerTasks.count == 2 && model.organizerTasks.contains { $0.id == "own" })
        assert(model.organizerTasks.first { $0.isAutomatic }?.isCompleted == true)
        var automatic = model.organizerTasks.first { $0.isAutomatic }!
        automatic.title = "Nie wolno nadpisać tytułu źródła"
        automatic.note = "Własna notatka"
        assert(model.saveTask(automatic))
        assert(model.organizerTasks.first { $0.isAutomatic }?.title == "Zadanie")
        assert(!model.deleteTask(automatic.id), "Imported homework is completed rather than deleted")
    }

    static func failedWriteIsNotPublished(_ model: SchoolViewModel, _ secrets: OrganizerSecrets) {
        secrets.fail = true
        assert(!model.saveTask(SchoolTask(id: "failed", title: "Nie zapisze się")))
        assert(!model.organizerTasks.contains { $0.id == "failed" } && model.errorMessage != nil)
        assert(!model.completeTask("own", completed: true))
        assert(model.organizerTasks.first { $0.id == "own" }?.isCompleted == false)
        secrets.fail = false
        assert(!model.saveTask(SchoolTask(title: "  ")))
        assert(!model.saveTask(SchoolTask(title: "Błędna data", dueDate: "2026-02-31")))
        assert(!model.saveTask(SchoolTask(title: "Minione przypomnienie", reminderAt: now.addingTimeInterval(-1))))
    }

    static func missingSourceAndRestore(_ model: SchoolViewModel, _ backend: OrganizerBackend,
                                       _ vault: SecureVault, _ notifications: SchoolNotifications) async throws {
        let source = SchoolItem(id: "message", title: "Zgoda", body: "Zapisana treść", date: "2026-11-08")
        let task = model.task(for: source, in: .messages)
        assert(model.saveTask(task))
        await backend.set(SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-11-08", sections: ["homework": []]))
        model.refresh()
        try await wait { !model.busy }
        model.openTaskSource(task)
        assert(model.selectedItem?.body == "Zapisana treść")
        assert(model.detailSourceArchived, "A missing message must show its saved copy without a network read")
        let restored = SchoolViewModel(backend: backend, vault: vault, notifications: notifications, now: { now })
        defer { restored.stop() }
        restored.bootstrap()
        try await wait { restored.snapshot != nil && !restored.busy }
        assert(restored.organizerTasks.count == 3)
        assert(restored.organizerTasks.first { $0.isAutomatic }?.note == "Własna notatka")
        assert(restored.deleteTask("own"))
        assert(restored.organizerTasks.count == 2)
        restored.login(LoginInput(login: "7654321", password: "synthetic-other"))
        try await wait { !restored.busy }
        assert(restored.organizerTasks.isEmpty, "Switching accounts must not carry personal tasks to another student")
    }

    static func wait(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            precondition(ContinuousClock.now < deadline, "Organizer operation did not finish")
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
