import Foundation

/// Derives local clock and change labels without fetching data or marking news reviewed.
struct SchoolTimetablePresentation {
    enum Timing { case current, finished, upcoming, unknown }
    let timing: Timing
    let statusLabel: String?
    let hasUnseenChange: Bool
    let changeDescriptions: [String]
    var isCanceled: Bool { statusLabel == "Odwołana" }

    init(item: SchoolItem, news: [SchoolNewsEntry], now: Date) {
        statusLabel = Self.status(for: item)
        timing = Self.timing(for: item, canceled: statusLabel == "Odwołana", now: now)
        let entry = news.first { $0.section == .timetable && $0.key == SchoolNews.key(item, in: .timetable) }
        hasUnseenChange = entry != nil
        changeDescriptions = entry.map { Self.describe($0, for: item) } ?? []
    }

    private static func status(for item: SchoolItem) -> String? {
        let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if item.canceled || value == "odwołana" { return "Odwołana" }
        return value == "zastępstwo" ? "Zastępstwo" : nil
    }

    private static func timing(for item: SchoolItem, canceled: Bool, now: Date) -> Timing {
        guard !canceled, let bounds = SchoolDates.lessonBounds(item) else { return .unknown }
        if now < bounds.start { return .upcoming }
        return now < bounds.end ? .current : .finished
    }

    private static func describe(_ entry: SchoolNewsEntry, for item: SchoolItem) -> [String] {
        guard sameContent(entry.item, item) else { return ["Zmiana w tej godzinie"] }
        guard let previous = entry.previousItem else { return [genericChange(entry)] }
        var changes: [String] = []
        if let before = room(in: previous), let after = room(in: item), before != after {
            changes.append("Sala \(before) → \(after)")
        }
        if !previous.time.isEmpty, !item.time.isEmpty, previous.time != item.time {
            changes.append("Godzina \(previous.time) → \(item.time)")
        }
        return changes.isEmpty ? ["Zmiana planu"] : changes
    }

    private static func genericChange(_ entry: SchoolNewsEntry) -> String {
        switch entry.kind {
        case .added: "Nowa lekcja"
        case .changed: "Zmiana planu"
        case .removed: "Lekcja usunięta"
        }
    }

    private static func room(in item: SchoolItem) -> String? {
        let rooms = item.subtitle.components(separatedBy: " · ").compactMap { component -> String? in
            let value = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.lowercased().hasPrefix("sala ") else { return nil }
            let room = String(value.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return room.isEmpty ? nil : room
        }
        return rooms.count == 1 ? rooms.first : nil
    }

    private static func sameContent(_ left: SchoolItem, _ right: SchoolItem) -> Bool {
        left.date == right.date && left.time == right.time && left.title == right.title &&
        left.subtitle == right.subtitle && left.body == right.body && left.value == right.value &&
        left.canceled == right.canceled
    }
}
