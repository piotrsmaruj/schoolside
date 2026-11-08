import AppKit
import Foundation
import OSLog

@MainActor
final class SchoolViewModel: ObservableObject {
    @Published var selectedSection: SchoolSection = .today
    @Published var selectedItem: SchoolItem?
    @Published var detailSection: SchoolSection?
    @Published var detailSourceArchived = false
    @Published var selectedMessage: SchoolItem?
    @Published private(set) var messageLoading = false
    @Published private(set) var messageError: String?
    @Published var snapshot: SchoolSnapshot?
    @Published var busy = false
    @Published var errorMessage: String?
    @Published var showLogin = false
    @Published var showSettings = false
    @Published var search = ""
    @Published private(set) var signedIn = false
    @Published private(set) var nextRefreshAt: Date?
    let notifications: SchoolNotifications

    private let backend: any SchoolBackendRunning
    private let vault: SecureVault
    let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private var account: LoginInput?
    private var session: SavedSession?
    private var operation: Task<Void, Never>?
    private var messageRequestId: UUID?
    private var messageDetails: [String: SchoolItem] = [:]
    private var timer: Task<Void, Never>?
    private var started = false
    private var stopped = false
    private let refreshInterval: TimeInterval
    private let logger = Logger(subsystem: "local.librus.desktop", category: "sync")

    convenience init() {
        let root = Bundle.main.object(forInfoDictionaryKey: "SchoolProjectRoot") as? String ?? ""
        let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask)[0].appending(path: "LibrusLocal")
        let vault = SecureVault(secrets: KeychainSecrets(service: "local.librus.desktop"),
                            cacheURL: directory.appending(path: "snapshot.enc"))
        self.init(backend: SchoolBackend(root: URL(fileURLWithPath: root)), vault: vault,
                  notifications: SchoolNotifications())
    }

    init(backend: any SchoolBackendRunning, vault: SecureVault, notifications: SchoolNotifications,
         refreshInterval: TimeInterval = 15 * 60, now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = {
             try await Task.sleep(for: .seconds($0))
         }) {
        self.backend = backend
        self.vault = vault
        self.notifications = notifications
        self.refreshInterval = refreshInterval
        self.now = now
        self.sleep = sleep
    }

    func bootstrap() {
        guard !started else { return }
        started = true
        do {
            account = try vault.loadAccount()
            session = try vault.loadSession()
            snapshot = try vault.loadSnapshot()
            if var cached = snapshot {
                cached.organizer = SchoolOrganizer.reconcile(cached.organizer ?? SchoolOrganizerState(), snapshot: cached)
                snapshot = cached
            }
            signedIn = account != nil
        } catch { errorMessage = "Nie udało się odczytać zapisanych danych. \(error.localizedDescription)" }
        notifications.setTasks(organizerTasks, at: now())
        refresh()
        Task { await notifications.refresh() }
    }

    func refreshIfStale() {
        guard !stopped, let nextRefreshAt, now() >= nextRefreshAt else { return }
        refresh()
    }

    private func scheduleRefresh() {
        timer?.cancel()
        guard !stopped, let nextRefreshAt else { return }
        timer = Task { [weak self, sleep, now] in
            do { try await sleep(max(0, nextRefreshAt.timeIntervalSince(now()))) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refreshIfStale()
        }
    }

    private func finishOperation() {
        busy = false
        guard !stopped, account != nil else {
            timer?.cancel()
            nextRefreshAt = nil
            return
        }
        if let nextRefreshAt, now() >= nextRefreshAt { refresh() }
        else { scheduleRefresh() }
    }

    func login(_ credentials: LoginInput) {
        guard !stopped, !busy else { return }
        synchronize(credentials, newLogin: true)
    }

    func refresh() {
        guard !stopped, !busy, let account else { return }
        synchronize(account, newLogin: false)
    }

    private func synchronize(_ credentials: LoginInput, newLogin: Bool) {
        busy = true
        errorMessage = nil
        timer?.cancel()
        nextRefreshAt = now().addingTimeInterval(refreshInterval)
        logger.info("Synchronization started")
        let request = SchoolRequest(operation: "sync", login: credentials.login,
                                    password: credentials.password, session: newLogin ? nil : session)
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            await self.performSynchronization(request, credentials: credentials)
        }
    }

    private func performSynchronization(_ request: SchoolRequest, credentials: LoginInput) async {
        do {
            let response = try await backend.run(request)
            try Task.checkCancellation()
            let changes = try acceptSnapshot(response, credentials: credentials)
            logger.info("Synchronization completed")
            await notifications.post(changes)
        } catch is CancellationError {
            logger.info("Synchronization canceled")
            errorMessage = "Synchronizacja przerwana."
        } catch {
            logger.error("Synchronization failed")
            handle(error)
        }
    }

    private func acceptSnapshot(_ response: SchoolResponse, credentials: LoginInput) throws -> [LocalChange] {
        guard let fresh = response.snapshot else { throw DesktopError.transport }
        let savedAccount = account == nil ? try vault.loadAccount() : account
        let sameAccount = savedAccount?.login == credentials.login
        let previous = sameAccount ? snapshot : nil
        if !sameAccount {
            notifications.setTasks([], at: now())
            try vault.clear()
            messageDetails.removeAll()
            selectedMessage = nil
        }
        var merged = fresh.merging(previous: previous)
        merged.news = SchoolNews.updated(previous: previous, fresh: fresh, at: now())
        merged.organizer = SchoolOrganizer.reconcile(previous?.organizer ?? SchoolOrganizerState(), snapshot: fresh)
        snapshot = merged
        account = credentials
        signedIn = true
        showLogin = false
        try vault.saveAccount(credentials)
        try persist(response)
        if let snapshot { try vault.saveSnapshot(snapshot) }
        notifications.setTasks(organizerTasks, at: now())
        return SchoolChanges.between(old: previous, new: fresh)
    }

    private func persist(_ response: SchoolResponse) throws {
        if let value = response.session {
            session = value
            try vault.saveSession(value)
        }
    }

    private func handle(_ error: Error) {
        errorMessage = error.localizedDescription
        if case DesktopError.remote(let code) = error,
           ["auth_failed", "captcha_required", "account_action_required"].contains(code) {
            account = nil
            session = nil
            signedIn = false
            showLogin = snapshot != nil
        }
    }

    func openMessage(_ item: SchoolItem) { selectMessage(item) }

    func selectMessage(_ item: SchoolItem) {
        guard !stopped, !busy || messageLoading, let account else { return }
        detailSection = .messages
        detailSourceArchived = false
        if messageLoading { operation?.cancel() }
        let requestId = UUID()
        messageRequestId = requestId
        selectedSection = .messages
        selectedItem = nil
        selectedMessage = item
        messageError = nil
        errorMessage = nil
        if let cached = messageDetails[messageKey(item)] {
            selectedMessage = cached
            messageLoading = false
            finishOperation()
            return
        }
        busy = true
        messageLoading = true
        let request = SchoolRequest(operation: "message", login: account.login,
            password: account.password, session: session, messageId: item.id)
        operation = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.messageRequestId == requestId { self.messageLoading = false; self.finishOperation() }
            }
            await self.fetchMessage(request, item: item, requestId: requestId)
        }
    }

    private func fetchMessage(_ request: SchoolRequest, item: SchoolItem, requestId: UUID) async {
        do {
            let response = try await backend.run(request)
            try Task.checkCancellation()
            guard messageRequestId == requestId else { return }
            try acceptMessage(response, preview: item)
        } catch is CancellationError {
            if messageRequestId == requestId { messageError = "Pobieranie wiadomości przerwane." }
        } catch {
            guard messageRequestId == requestId else { return }
            messageError = error.localizedDescription
            handle(error)
        }
    }

    private func acceptMessage(_ response: SchoolResponse, preview: SchoolItem) throws {
        guard var full = response.message else { throw DesktopError.transport }
        full.unread = false
        messageDetails[messageKey(preview)] = full
        selectedMessage = full
        snapshot?.sections["messages"] = items(.messages).map { $0.id == preview.id ? full : $0 }
        snapshot?.news = SchoolNews.reviewing(news, section: .messages, item: full)
        try persist(response)
        if let snapshot { try vault.saveSnapshot(snapshot) }
    }

    private func messageKey(_ item: SchoolItem) -> String { "\(item.mailbox):\(item.id)" }

    func saveAttachment(_ attachment: SchoolAttachment, of item: SchoolItem) {
        guard !busy else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: attachment.name).lastPathComponent
        panel.begin { [weak self] result in
            guard result == .OK, let destination = panel.url else { return }
            Task { @MainActor in self?.download(attachment, of: item, to: destination) }
        }
    }

    private func download(_ attachment: SchoolAttachment, of item: SchoolItem, to url: URL) {
        guard let account, !busy else { return }
        busy = true
        errorMessage = nil
        let kind = (detailSection ?? selectedSection) == .homework ? "homework_attachment" : "attachment"
        operation = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation() }
            do {
                let request = SchoolRequest(operation: kind, login: account.login,
                    password: account.password, session: self.session,
                    messageId: item.id, attachmentId: attachment.id)
                let response = try await self.backend.run(request)
                try Task.checkCancellation()
                guard let payload = response.attachment,
                      let data = Data(base64Encoded: payload.data) else { throw DesktopError.transport }
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                try self.persist(response)
            } catch { self.handle(error) }
        }
    }

    func items(_ section: SchoolSection) -> [SchoolItem] { snapshot?.sections[section.rawValue] ?? [] }
    var unreadCount: Int { items(.messages).filter(\.unread).count }
    var news: [SchoolNewsEntry] { snapshot?.news ?? [] }

    func openItem(_ item: SchoolItem, in section: SchoolSection) {
        detailSection = section
        detailSourceArchived = false
        if section == .messages { selectMessage(item); return }
        selectedSection = section
        selectedItem = item
        snapshot?.news = SchoolNews.reviewing(news, section: section, item: item)
        saveLocalChanges()
    }

    func openNews(_ entry: SchoolNewsEntry) {
        openItem(entry.item, in: entry.section)
    }

    func markAllNewsReviewed() {
        snapshot?.news = []
        saveLocalChanges()
    }

    private func saveLocalChanges() {
        guard let snapshot else { return }
        do { try vault.saveSnapshot(snapshot) }
        catch { errorMessage = error.localizedDescription }
    }

    func saveOrganizerState(_ state: SchoolOrganizerState) -> Bool {
        guard var updated = snapshot else {
            errorMessage = SchoolOrganizerError.unavailable.localizedDescription
            return false
        }
        updated.organizer = state
        do {
            try vault.saveSnapshot(updated)
            snapshot = updated
            errorMessage = nil
            notifications.setTasks(state.tasks, at: now())
            return true
        } catch {
            logger.error("Organizer persistence failed")
            errorMessage = "Nie udało się zapisać zadania. \(error.localizedDescription)"
            return false
        }
    }

    func logout() {
        messageRequestId = nil
        messageDetails.removeAll()
        selectedMessage = nil
        messageLoading = false
        messageError = nil
        busy = false
        operation?.cancel()
        timer?.cancel()
        nextRefreshAt = nil
        account = nil
        session = nil
        snapshot = nil
        selectedItem = nil
        detailSection = nil
        detailSourceArchived = false
        signedIn = false
        showLogin = false
        notifications.setTasks([], at: now())
        do { try vault.clear() } catch { errorMessage = error.localizedDescription }
    }

    func cancel() { operation?.cancel() }
    func stop() {
        stopped = true
        messageRequestId = nil
        messageDetails.removeAll()
        messageLoading = false
        busy = false
        nextRefreshAt = nil
        operation?.cancel()
        timer?.cancel()
    }

}
