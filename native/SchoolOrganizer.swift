import Foundation

struct SchoolTaskSource: Codable, Equatable, Sendable {
    let section: SchoolSection
    var item: SchoolItem

    var key: String {
        [section.rawValue, section == .messages ? item.mailbox : "", item.id].joined(separator: "|")
    }
}

struct SchoolTask: Codable, Equatable, Identifiable, Sendable {
    var id = UUID().uuidString
    var title: String
    var note = ""
    var dueDate: String?
    var reminderAt: Date?
    var completedAt: Date?
    var source: SchoolTaskSource?

    var isAutomatic: Bool { source?.section == .homework }
    var isCompleted: Bool { completedAt != nil }
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (dueDate.map { Self.validDay($0) != nil } ?? true)
    }

    static func validDay(_ value: String) -> String? {
        guard value.count == 10, let parsed = SchoolDates.parseDay(value),
              SchoolDates.dayKey(parsed) == value else { return nil }
        return value
    }
}

struct SchoolOrganizerState: Codable, Equatable, Sendable {
    var tasks: [SchoolTask] = []
}

enum SchoolOrganizer {
    /// Repeated or partial syncs must never reset personal notes or completion.
    static func reconcile(_ state: SchoolOrganizerState, snapshot: SchoolSnapshot) -> SchoolOrganizerState {
        guard snapshot.errors["homework"] == nil, let homework = snapshot.sections["homework"] else { return state }
        var result = state
        for item in homework {
            let source = SchoolTaskSource(section: .homework, item: item)
            if let index = result.tasks.firstIndex(where: { $0.source?.key == source.key }) {
                result.tasks[index].title = item.title
                result.tasks[index].dueDate = item.homeworkDueDate.flatMap(SchoolTask.validDay)
                result.tasks[index].source = source
            } else {
                result.tasks.append(task(for: item, in: .homework, state: result))
            }
        }
        return result
    }

    static func task(for item: SchoolItem, in section: SchoolSection,
                     state: SchoolOrganizerState) -> SchoolTask {
        let source = SchoolTaskSource(section: section, item: item)
        if let existing = state.tasks.first(where: { $0.source?.key == source.key }) { return existing }
        let dueDate: String?
        if section == .homework { dueDate = item.homeworkDueDate.flatMap(SchoolTask.validDay) }
        else if section == .agenda { dueDate = SchoolTask.validDay(String(item.date.prefix(10))) }
        else { dueDate = nil }
        let title = section == .agenda ? "Przygotować: \(item.title)" : item.title
        return SchoolTask(id: section == .homework ? "homework:\(item.id)" : UUID().uuidString,
                          title: title, dueDate: dueDate, source: source)
    }
}

struct SchoolTaskGroup: Identifiable {
    enum Kind: String { case overdue, today, upcoming, undated, completed }
    let kind: Kind
    let title: String
    let tasks: [SchoolTask]
    var id: String { kind.rawValue }
}

struct SchoolTaskList {
    let groups: [SchoolTaskGroup]

    init(_ tasks: [SchoolTask], search: String = "", now: Date, showCompleted: Bool = false) {
        let today = SchoolDates.dayKey(now)
        let visible = tasks.filter { Self.matches($0, search: search) && (showCompleted || !$0.isCompleted) }
        let grouped = Dictionary(grouping: visible) { Self.kind($0, today: today) }
        let kinds: [(SchoolTaskGroup.Kind, String)] = [(.overdue, "Zaległe"), (.today, "Dzisiaj"),
            (.upcoming, "Nadchodzące"), (.undated, "Bez terminu"), (.completed, "Zrobione")]
        groups = kinds.compactMap { kind, title in
            guard let entries = grouped[kind], !entries.isEmpty else { return nil }
            return SchoolTaskGroup(kind: kind, title: title, tasks: Self.sorted(entries))
        }
    }

    static func matches(_ task: SchoolTask, search: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [task.title, task.note, task.source?.item.body ?? "",
                                task.source?.item.subtitle ?? ""].contains { $0.localizedStandardContains(query) }
    }

    static func sorted(_ tasks: [SchoolTask]) -> [SchoolTask] {
        tasks.sorted {
            let left = ($0.dueDate ?? "9999-12-31", $0.title, $0.id)
            let right = ($1.dueDate ?? "9999-12-31", $1.title, $1.id)
            return left < right
        }
    }

    private static func kind(_ task: SchoolTask, today: String) -> SchoolTaskGroup.Kind {
        if task.isCompleted { return .completed }
        guard let due = task.dueDate.flatMap(SchoolTask.validDay) else { return .undated }
        if due < today { return .overdue }
        return due == today ? .today : .upcoming
    }
}
