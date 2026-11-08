import Foundation

struct SchoolAttachment: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct SchoolItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var subtitle = ""
    var body = ""
    var date = ""
    var time = ""
    var value = ""
    var unread = false
    var canceled = false
    var mailbox = "inbox"
    var attachments: [SchoolAttachment] = []
    var semester: Int?
    var category: String?
    var subjectId: String?
    var hasAttachments: Bool?
    var gradePoints: Double?
    var gradeMaxPoints: Double?
    var gradeWeight: Double?
    var countsToAverage: Bool?
    var homeworkDueDate: String?

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, body, date, time, value, unread, canceled, mailbox, attachments, semester, category
        case subjectId = "subject_id"
        case hasAttachments = "has_attachments"
        case gradePoints = "grade_points"
        case gradeMaxPoints = "grade_max_points"
        case gradeWeight = "grade_weight"
        case countsToAverage = "counts_to_average"
        case homeworkDueDate = "homework_due_date"
    }
}

struct SchoolSnapshot: Codable, Sendable {
    let studentName: String
    let fetchedAt: String
    var sections: [String: [SchoolItem]] = [:]
    var errors: [String: String] = [:]
    var news: [SchoolNewsEntry]?
    /// Last successful baseline per module; a failed fetch must not advance it.
    var sectionFetches: [String: String]?
    var organizer: SchoolOrganizerState?

    enum CodingKeys: String, CodingKey {
        case studentName = "student_name"
        case fetchedAt = "fetched_at"
        case sections, errors, news, organizer
        case sectionFetches = "section_fetches"
    }

    func merging(previous: SchoolSnapshot?) -> SchoolSnapshot {
        var merged = self
        for key in errors.keys {
            if let cached = previous?.sections[key] { merged.sections[key] = cached }
        }
        if errors["references"] != nil, let cached = previous?.sections["timetable"] {
            merged.sections["timetable"] = cached
        }
        var dates = previous?.sectionFetches ?? [:]
        if let previous {
            for key in previous.sections.keys { dates[key] = previous.successfulFetchDate(for: key) }
        }
        for key in sections.keys where errors[key] == nil && (key != "timetable" || errors["references"] == nil) {
            dates[key] = fetchedAt
        }
        merged.sectionFetches = dates
        return merged
    }

    func successfulFetchDate(for section: String) -> String? {
        if let sectionFetches { return sectionFetches[section] }
        guard sections[section] != nil, errors[section] == nil,
              section != "timetable" || errors["references"] == nil else { return nil }
        return fetchedAt
    }
}

struct SchoolNewsEntry: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case added, changed, removed }
    let section: SchoolSection
    let key: String
    var item: SchoolItem
    let detectedAt: Date
    var kind: Kind = .added
    var previousItem: SchoolItem?
    var id: String { "\(section.rawValue):\(key)" }
}

struct LocalChange: Sendable {
    let title: String
    let body: String
}

enum SchoolChanges {
    static func between(old: SchoolSnapshot?, new: SchoolSnapshot, at now: Date = Date()) -> [LocalChange] {
        guard let old else { return [] }
        var changes: [LocalChange] = []
        for key in ["grades", "messages", "agenda", "homework"]
            where new.errors[key] == nil && old.successfulFetchDate(for: key) != nil {
            let seen = Set((old.sections[key] ?? []).map(\.id))
            let added = (new.sections[key] ?? []).filter { !seen.contains($0.id) }
            if !added.isEmpty {
                changes.append(LocalChange(title: SchoolSection(rawValue: key)?.title ?? "Librus",
                                           body: "Nowe wpisy: \(added.count)"))
            }
        }
        if !SchoolNews.planChanges(previous: old, fresh: new, at: now).isEmpty {
            changes.append(LocalChange(title: "Plan lekcji", body: "Zmienił się plan nadchodzących lekcji."))
        }
        return changes
    }

}

enum SchoolSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, news, organizer, timetable, grades, messages, agenda, attendance, homework, announcements
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Dzisiaj"
        case .news: "Co nowego"
        case .organizer: "Organizer"
        case .timetable: "Plan lekcji"
        case .grades: "Oceny"
        case .messages: "Wiadomości"
        case .agenda: "Terminarz"
        case .attendance: "Frekwencja"
        case .homework: "Zadania"
        case .announcements: "Ogłoszenia"
        }
    }
    var icon: String {
        switch self {
        case .today: "sun.max"
        case .news: "bell.badge"
        case .organizer: "checklist"
        case .timetable: "calendar"
        case .grades: "chart.bar.xaxis"
        case .messages: "envelope"
        case .agenda: "calendar.badge.clock"
        case .attendance: "person.badge.clock"
        case .homework: "checklist"
        case .announcements: "megaphone"
        }
    }
}

struct SavedSession: Codable, Sendable {
    let cookies: [[String: String]]
    let loggedInAt: Double
    enum CodingKeys: String, CodingKey { case cookies; case loggedInAt = "logged_in_at" }
}

struct SchoolRequest: Encodable, Sendable {
    let operation: String
    let login: String
    let password: String
    var session: SavedSession?
    var messageId: String?
    var attachmentId: String?
    enum CodingKeys: String, CodingKey {
        case operation, login, password, session
        case messageId = "message_id"
        case attachmentId = "attachment_id"
    }
}

struct SchoolResponse: Decodable, Sendable {
    let ok: Bool
    let session: SavedSession?
    let snapshot: SchoolSnapshot?
    let message: SchoolItem?
    let attachment: DownloadedAttachment?
    let errorCode: String?
    enum CodingKeys: String, CodingKey {
        case ok, session, snapshot, message, attachment
        case errorCode = "error_code"
    }
}

struct DownloadedAttachment: Decodable, Sendable {
    let name: String
    let data: String
}

enum DesktopError: LocalizedError {
    case keychain(Int32), cache, runtime, transport, canceled, remote(String)
    var errorDescription: String? {
        switch self {
        case .keychain: "Nie udało się uzyskać dostępu do Pęku kluczy."
        case .cache: "Nie udało się odczytać lub zapisać lokalnych danych offline."
        case .runtime: "Brakuje lokalnego środowiska aplikacji. Sprawdź README."
        case .transport: "Nie udało się odczytać odpowiedzi procesu pobierającego dane."
        case .canceled: "Operacja została przerwana."
        case .remote("attachment_too_large"): "Załącznik przekracza limit 25 MB."
        case .remote(let code): ProbeCopy.error(code)
        }
    }
}
