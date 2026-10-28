import Foundation
import UserNotifications

@MainActor
final class RefreshSecrets: SecretStore {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ key: String, data: Data) throws { values[key] = data }
    func delete(_ key: String) throws { values[key] = nil }
}

@MainActor
final class SilentNotifications: LocalNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus { .denied }
    func requestAuthorization() async throws -> Bool { false }
    func post(_ change: LocalChange) async throws { fatalError("Test notifications must stay disabled") }
}

@MainActor
final class ManualRefreshClock {
    struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    private var sleepers: [UUID: Sleeper] = [:]

    func sleep(_ interval: TimeInterval) async throws {
        guard interval > 0 else { try Task.checkCancellation(); return }
        let id = UUID()
        let deadline = date.addingTimeInterval(interval)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in
                self.sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
            }
        }
    }

    func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
        for (id, sleeper) in sleepers where sleeper.deadline <= date {
            sleepers.removeValue(forKey: id)?.continuation.resume()
        }
    }

    var hasSleeper: Bool { !sleepers.isEmpty }
}

actor RefreshBackend: SchoolBackendRunning {
    private var syncCount = 0
    private var holdNext = false
    private var pending: CheckedContinuation<Void, Never>?
    private var failNext = false

    func holdNextRequest() { holdNext = true }
    func failNextSync() { failNext = true }
    var hasPendingRequest: Bool { pending != nil }
    func releaseRequest() { pending?.resume(); pending = nil }

    func run(_ request: SchoolRequest) async throws -> SchoolResponse {
        precondition(request.login == "1234567" && request.password == "synthetic-password")
        if holdNext {
            holdNext = false
            await withCheckedContinuation { pending = $0 }
        }
        if request.operation == "message" {
            precondition(request.messageId == "synthetic-message")
            return SchoolResponse(ok: true, session: nil, snapshot: nil,
                message: SchoolItem(id: "synthetic-message", title: "Synthetic message"),
                attachment: nil, errorCode: nil)
        }
        precondition(request.operation == "sync")
        if failNext { failNext = false; throw DesktopError.remote("connection_error") }
        syncCount += 1
        let snapshot = SchoolSnapshot(studentName: "Snapshot \(syncCount)", fetchedAt: "2026-10-28")
        return SchoolResponse(ok: true, session: nil, snapshot: snapshot, message: nil,
                              attachment: nil, errorCode: nil)
    }
}

@main
@MainActor
struct RefreshTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "librus-refresh-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = SecureVault(secrets: RefreshSecrets(), cacheURL: directory.appending(path: "snapshot.enc"))
        try vault.saveAccount(LoginInput(login: "1234567", password: "synthetic-password"))
        let clock = ManualRefreshClock()
        let backend = RefreshBackend()
        let model = SchoolViewModel(backend: backend, vault: vault,
            notifications: SchoolNotifications(center: SilentNotifications(), defaults: defaults),
            now: { clock.date }, sleep: { try await clock.sleep($0) })
        defer { model.stop() }

        model.bootstrap()
        try await wait("Initial snapshot and timer") {
            model.snapshot?.studentName == "Snapshot 1" && !model.busy && clock.hasSleeper
        }
        try await manualReset(model, clock)
        try await busyDeadline(model, clock, backend)
        try await wakeAndRetry(model, clock, backend)
        try await logoutAndStop(model, clock)
        print("Swift refresh: manual reset, repeat, busy deadline, wake, retry, logout and stop passed")
    }

    static func manualReset(_ model: SchoolViewModel, _ clock: ManualRefreshClock) async throws {
        clock.advance(2 * 60)
        model.refresh()
        try await wait("Manual refresh") { model.snapshot?.studentName == "Snapshot 2" && !model.busy }
        clock.advance(13 * 60)
        for _ in 0..<100 { await Task.yield() }
        assert(model.snapshot?.studentName == "Snapshot 2", "Do not refresh before the new deadline")
        clock.advance(2 * 60)
        try await wait("Automatic refresh must run 15 minutes after the manual refresh") {
            model.snapshot?.studentName == "Snapshot 3" && !model.busy
        }
        assert(model.nextRefreshAt == clock.date.addingTimeInterval(15 * 60))
        clock.advance(15 * 60)
        try await wait("Automatic refresh must repeat") { model.snapshot?.studentName == "Snapshot 4" && !model.busy }
    }

    static func busyDeadline(_ model: SchoolViewModel, _ clock: ManualRefreshClock,
                             _ backend: RefreshBackend) async throws {
        clock.advance(14 * 60)
        await backend.holdNextRequest()
        model.openMessage(SchoolItem(id: "synthetic-message", title: "Synthetic message"))
        try await wait("Message request in progress") { await backend.hasPendingRequest }
        clock.advance(60)
        for _ in 0..<100 { await Task.yield() }
        assert(model.busy && model.snapshot?.studentName == "Snapshot 4", "Requests must not overlap")
        await backend.releaseRequest()
        try await wait("A busy deadline must refresh immediately after the message finishes") {
            model.snapshot?.studentName == "Snapshot 5" && !model.busy
        }
    }

    static func wakeAndRetry(_ model: SchoolViewModel, _ clock: ManualRefreshClock,
                             _ backend: RefreshBackend) async throws {
        clock.advance(60 * 60)
        model.refreshIfStale()
        model.refreshIfStale()
        try await wait("Wake and timer must coalesce overdue work") {
            model.snapshot?.studentName == "Snapshot 6" && !model.busy
        }
        await backend.failNextSync()
        clock.advance(15 * 60)
        try await wait("Network failure must be visible") { model.errorMessage != nil && !model.busy }
        assert(model.snapshot?.studentName == "Snapshot 6", "Keep the last good snapshot")
        clock.advance(15 * 60)
        try await wait("Automatic retries must survive a network failure") {
            model.snapshot?.studentName == "Snapshot 7" && model.errorMessage == nil && !model.busy
        }
    }

    static func logoutAndStop(_ model: SchoolViewModel, _ clock: ManualRefreshClock) async throws {
        model.logout()
        clock.advance(60 * 60)
        model.refreshIfStale()
        assert(model.nextRefreshAt == nil && model.snapshot == nil)
        model.login(LoginInput(login: "1234567", password: "synthetic-password"))
        try await wait("Logging in must restore automatic refresh") {
            model.snapshot?.studentName == "Snapshot 8" && !model.busy && clock.hasSleeper
        }
        model.stop()
        clock.advance(60 * 60)
        model.refreshIfStale()
        model.refresh()
        try await wait("Stopping must cancel the scheduled refresh") { !clock.hasSleeper }
        assert(model.nextRefreshAt == nil && model.snapshot?.studentName == "Snapshot 8" && !model.busy)
    }

    static func wait(_ message: String, until condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            precondition(ContinuousClock.now < deadline, message)
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
