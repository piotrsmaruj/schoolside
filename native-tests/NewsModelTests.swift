import Foundation
import UserNotifications

@MainActor
final class NewsMemorySecrets: SecretStore {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ key: String, data: Data) throws { values[key] = data }
    func delete(_ key: String) throws { values[key] = nil }
}

@MainActor
final class NewsSilentCenter: LocalNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func post(_ change: LocalChange) async throws { fatalError("Notifications are disabled in this test") }
    func replaceTaskReminders(_ reminders: [SchoolTaskReminder]) async throws { }
}

actor NewsBackend: SchoolBackendRunning {
    var current = SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-10-28",
                                sections: ["grades": [], "messages": []])
    private(set) var messageReads = 0
    private var heldMessages: Set<String> = []
    private var pendingMessages: [String: CheckedContinuation<Void, Never>] = [:]
    func setSnapshot(_ value: SchoolSnapshot) { current = value }
    func holdMessage(_ id: String) { heldMessages.insert(id) }
    var pendingIDs: Set<String> { Set(pendingMessages.keys) }
    func releaseMessage(_ id: String) {
        heldMessages.remove(id)
        pendingMessages.removeValue(forKey: id)?.resume()
    }

    func run(_ request: SchoolRequest) async throws -> SchoolResponse {
        precondition(request.login == "1234567" && request.password == "synthetic")
        if request.operation == "message" {
            guard let id = request.messageId, ["m1", "m2"].contains(id) else { fatalError("Unexpected message request") }
            messageReads += 1
            if heldMessages.contains(id) { await withCheckedContinuation { pendingMessages[id] = $0 } }
            return SchoolResponse(ok: true, session: nil, snapshot: nil,
                message: SchoolItem(id: id, title: "Synthetic message", body: id == "m1" ? "Full body" : "Second body"),
                attachment: nil, errorCode: nil)
        }
        precondition(request.operation == "sync")
        return SchoolResponse(ok: true, session: nil, snapshot: current, message: nil, attachment: nil, errorCode: nil)
    }
}

@main
@MainActor
struct NewsModelTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "librus-news-model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = SecureVault(secrets: NewsMemorySecrets(), cacheURL: directory.appending(path: "snapshot.enc"))
        try vault.saveAccount(LoginInput(login: "1234567", password: "synthetic"))
        let notifications = SchoolNotifications(center: NewsSilentCenter(), defaults: defaults)
        let backend = NewsBackend()
        let model = SchoolViewModel(backend: backend, vault: vault, notifications: notifications)
        defer { model.stop() }
        model.bootstrap()
        try await wait { model.snapshot != nil && !model.busy }
        assert(model.news.isEmpty)
        try await additionsAndReview(model, backend, vault)
        model.stop()
        try await restoreAndOpenMessage(backend, vault, notifications)
        try await rapidSelectionAndLogout(backend, vault, notifications)
        print("Swift news model: sync accumulation, persisted review, restart and explicit message reading passed")
    }

    static func additionsAndReview(_ model: SchoolViewModel, _ backend: NewsBackend,
                                   _ vault: SecureVault) async throws {
        let grade = SchoolItem(id: "g1", title: "Matematyka", value: "80%")
        let fresh = SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-10-28", sections: [
            "grades": [grade], "messages": [SchoolItem(id: "m1", title: "Synthetic message", unread: true)],
        ])
        await backend.setSnapshot(fresh)
        model.refresh()
        try await wait { !model.busy }
        assert(model.news.count == 2, "New records must appear in the real ViewModel")
        model.refresh()
        try await wait { !model.busy }
        assert(model.news.count == 2)
        model.openItem(grade, in: .grades)
        assert(model.news.count == 1 && model.selectedItem?.id == "g1")
        let persisted = try vault.loadSnapshot()
        assert(persisted?.news?.count == 1 && persisted?.news?.first?.section == .messages)
        let reads = await backend.messageReads
        assert(reads == 0, "Collecting news must never open a full message")
    }

    static func restoreAndOpenMessage(_ backend: NewsBackend, _ vault: SecureVault,
                                      _ notifications: SchoolNotifications) async throws {
        let restored = SchoolViewModel(backend: backend, vault: vault, notifications: notifications)
        defer { restored.stop() }
        restored.bootstrap()
        try await wait { restored.snapshot != nil && !restored.busy }
        assert(restored.news.count == 1 && restored.news[0].section == .messages)
        restored.openNews(restored.news[0])
        try await wait { !restored.busy }
        assert(restored.news.isEmpty && restored.selectedMessage?.body == "Full body" && restored.unreadCount == 0,
               "An explicit click must open the full message in the side pane")
        assert(restored.selectedItem == nil, "Messages must not open a modal detail sheet")
        let reads = await backend.messageReads
        assert(reads == 1)
        restored.selectMessage(restored.items(.messages)[0])
        try await wait { !restored.busy }
        let cachedReads = await backend.messageReads
        assert(cachedReads == 1, "Reselecting an already opened message must reuse its full body")
        let persisted = try vault.loadSnapshot()
        assert(persisted?.news?.isEmpty == true)
        try await reviewDuringRefresh(restored, backend, vault)
    }

    static func rapidSelectionAndLogout(_ backend: NewsBackend, _ vault: SecureVault,
                                        _ notifications: SchoolNotifications) async throws {
        var fresh = await backend.current
        let first = SchoolItem(id: "m1", title: "First preview", unread: true)
        let second = SchoolItem(id: "m2", title: "Second preview", unread: true)
        fresh.sections["messages"] = [first, second]
        await backend.setSnapshot(fresh)
        let model = SchoolViewModel(backend: backend, vault: vault, notifications: notifications)
        defer { model.stop() }
        model.bootstrap()
        try await wait { model.snapshot != nil && !model.busy }
        await backend.holdMessage("m1")
        model.selectMessage(first)
        try await wait { await backend.pendingIDs.contains("m1") }
        model.selectMessage(second)
        try await wait { model.selectedMessage?.body == "Second body" && !model.busy }
        await backend.releaseMessage("m1")
        for _ in 0..<100 { await Task.yield() }
        assert(model.selectedMessage?.id == "m2" && model.messageError == nil && !model.busy)
        try await logoutDuringMessage(model, first, backend)
    }

    static func logoutDuringMessage(_ model: SchoolViewModel, _ item: SchoolItem,
                                     _ backend: NewsBackend) async throws {
        await backend.holdMessage("m1")
        model.selectMessage(item)
        try await wait { await backend.pendingIDs.contains("m1") }
        model.logout()
        await backend.releaseMessage("m1")
        for _ in 0..<100 { await Task.yield() }
        assert(model.selectedMessage == nil && model.snapshot == nil && !model.messageLoading && !model.busy,
               "A late response after logout must not restore private message content")
    }

    static func reviewDuringRefresh(_ model: SchoolViewModel, _ backend: NewsBackend,
                                    _ vault: SecureVault) async throws {
        var fresh = await backend.current
        fresh.sections["grades", default: []].append(SchoolItem(id: "g2", title: "Synthetic new grade", value: "90%"))
        await backend.setSnapshot(fresh)
        model.refresh()
        try await wait { !model.busy }
        assert(model.news.count == 1)
        model.refresh()
        model.markAllNewsReviewed()
        try await wait { !model.busy }
        assert(model.news.isEmpty, "A response in flight must not restore reviewed news")
        let saved = try vault.loadSnapshot()
        assert(saved?.news?.isEmpty == true)
    }

    static func wait(until condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            precondition(ContinuousClock.now < deadline, "ViewModel operation did not finish")
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
