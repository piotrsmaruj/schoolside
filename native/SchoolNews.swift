import Foundation

enum SchoolNews {
    /// Keeps unseen entries until reviewed and compares each module with its last valid baseline.
    static func updated(previous: SchoolSnapshot?, fresh: SchoolSnapshot, at now: Date) -> [SchoolNewsEntry] {
        guard let previous else { return [] }
        var entries = (previous.news ?? []).filter { isRelevant($0, fresh: fresh, now: now) }.map { entry in
            guard entry.section != .timetable, fresh.errors[entry.section.rawValue] == nil,
                  let current = fresh.sections[entry.section.rawValue]?.first(where: { $0.id == entry.item.id })
            else { return entry }
            var updated = entry
            updated.item = current
            return updated
        }
        entries += addedItems(previous: previous, fresh: fresh, at: now)
        entries += planChanges(previous: previous, fresh: fresh, at: now)
        let unique = entries.reduce(into: [String: SchoolNewsEntry]()) { $0[$1.id] = $1 }
        return unique.values.sorted {
            $0.detectedAt == $1.detectedAt ? $0.id < $1.id : $0.detectedAt > $1.detectedAt
        }
    }

    static func reviewing(_ entries: [SchoolNewsEntry], section: SchoolSection,
                          item: SchoolItem) -> [SchoolNewsEntry] {
        entries.filter { $0.section != section || $0.key != key(item, in: section) }
    }

    static func key(_ item: SchoolItem, in section: SchoolSection) -> String {
        section == .timetable ? "\(item.date)|\(item.time)" : item.id
    }

    private static func isRelevant(_ entry: SchoolNewsEntry, fresh: SchoolSnapshot, now: Date) -> Bool {
        if entry.section == .timetable { return entry.item.date >= SchoolDates.dayKey(now) }
        guard fresh.errors[entry.section.rawValue] == nil,
              let items = fresh.sections[entry.section.rawValue] else { return true }
        return items.contains { $0.id == entry.item.id }
    }

    private static func addedItems(previous: SchoolSnapshot, fresh: SchoolSnapshot,
                                   at now: Date) -> [SchoolNewsEntry] {
        let sections: [SchoolSection] = [.grades, .messages, .agenda, .homework, .announcements]
        return sections.flatMap { section -> [SchoolNewsEntry] in
            guard previous.successfulFetchDate(for: section.rawValue) != nil, fresh.errors[section.rawValue] == nil,
                  let old = previous.sections[section.rawValue] else { return [] }
            let seen = Set(old.map(\.id))
            return (fresh.sections[section.rawValue] ?? []).filter { !seen.contains($0.id) }.map {
                SchoolNewsEntry(section: section, key: $0.id, item: $0, detectedAt: now)
            }
        }
    }

    /// Provider IDs are positional. Compare slot contents only within both fetched windows.
    static func planChanges(previous: SchoolSnapshot, fresh: SchoolSnapshot,
                                    at now: Date) -> [SchoolNewsEntry] {
        guard let lastSuccess = previous.successfulFetchDate(for: "timetable"), fresh.errors["timetable"] == nil,
              fresh.errors["references"] == nil,
              let old = previous.sections["timetable"], let new = fresh.sections["timetable"],
              let oldWindow = SchoolDates.timetableWindow(lastSuccess),
              let newWindow = SchoolDates.timetableWindow(fresh.fetchedAt) else { return [] }
        let start = max(SchoolDates.dayKey(now), SchoolDates.dayKey(max(oldWindow.start, newWindow.start)))
        let end = SchoolDates.dayKey(min(oldWindow.end, newWindow.end))
        let before = Dictionary(grouping: old.filter { $0.date >= start && $0.date < end }) { key($0, in: .timetable) }
        let after = Dictionary(grouping: new.filter { $0.date >= start && $0.date < end }) { key($0, in: .timetable) }
        let unmatchedOld = unmatched(Array(before.values.joined()), comparedWith: Array(after.values.joined()))
        let unmatchedNew = unmatched(Array(after.values.joined()), comparedWith: Array(before.values.joined()))
        return Set(before.keys).union(after.keys).compactMap { slot in
            slotChange(slot, before: before[slot] ?? [], after: after[slot] ?? [],
                       unmatchedOld: unmatchedOld, unmatchedNew: unmatchedNew, at: now)
        }
    }

    private static func slotChange(_ slot: String, before: [SchoolItem], after: [SchoolItem],
                                   unmatchedOld: [SchoolItem], unmatchedNew: [SchoolItem],
                                   at now: Date) -> SchoolNewsEntry? {
        guard signatures(before) != signatures(after) else { return nil }
        let oldChanges = unmatched(before, comparedWith: after)
        let newChanges = unmatched(after, comparedWith: before)
        guard let item = newChanges.first ?? after.first ?? before.first else { return nil }
        let kind: SchoolNewsEntry.Kind = after.isEmpty ? .removed : before.isEmpty ? .added : .changed
        var previous: SchoolItem?
        if !newChanges.isEmpty {
            previous = previousLesson(for: item, slotOld: oldChanges, slotNew: newChanges,
                                      old: unmatchedOld, new: unmatchedNew)
        }
        return SchoolNewsEntry(section: .timetable, key: slot, item: item, detectedAt: now,
                               kind: kind, previousItem: previous)
    }

    /// Remove equal occurrences rather than IDs; parallel duplicate lessons are a multiset.
    private static func unmatched(_ items: [SchoolItem], comparedWith others: [SchoolItem]) -> [SchoolItem] {
        var remaining = others
        return items.filter { item in
            guard let index = remaining.firstIndex(where: {
                $0.date == item.date && $0.time == item.time && LessonSignature($0) == LessonSignature(item)
            }) else { return true }
            remaining.remove(at: index)
            return false
        }
    }

    private static func previousLesson(for item: SchoolItem, slotOld: [SchoolItem], slotNew: [SchoolItem],
                                       old: [SchoolItem], new: [SchoolItem]) -> SchoolItem? {
        // Match across all changed slots before considering the lesson previously occupying this slot.
        if let matched = uniqueIdentityMatch(for: item, old: old, new: new) { return matched }
        guard slotOld.count == 1, slotNew.count == 1,
              !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let previous = old.filter { $0.date == item.date && $0.title == item.title }
        let replacements = new.filter { $0.date == item.date && $0.title == item.title }
        // A new teacher can identify a substitution only for one same-subject lesson in this slot.
        guard previous.count == 1, replacements.count == 1,
              let matched = previous.first, matched.time == item.time else { return nil }
        return matched
    }

    private static func uniqueIdentityMatch(for item: SchoolItem, old: [SchoolItem],
                                            new: [SchoolItem]) -> SchoolItem? {
        let identity = LessonIdentity(item)
        let candidates = old.filter { $0.date == item.date && LessonIdentity($0) == identity }
        let replacements = new.filter { $0.date == item.date && LessonIdentity($0) == identity }
        guard candidates.count == 1, replacements.count == 1 else { return nil }
        return candidates.first
    }

    private struct LessonIdentity: Equatable {
        let title: String
        let teacher: String

        init(_ item: SchoolItem) {
            title = item.title
            teacher = item.subtitle.components(separatedBy: " · ").filter {
                !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("sala ")
            }.joined(separator: " · ")
        }
    }

    private static func signatures(_ items: [SchoolItem]) -> [LessonSignature: Int] {
        Dictionary(grouping: items.map(LessonSignature.init), by: { $0 }).mapValues(\.count)
    }

    private struct LessonSignature: Hashable {
        let title: String
        let subtitle: String
        let body: String
        let value: String
        let canceled: Bool

        init(_ item: SchoolItem) {
            title = item.title
            subtitle = item.subtitle
            body = item.body
            value = item.value
            canceled = item.canceled
        }
    }
}
