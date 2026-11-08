import Foundation

struct SchoolWeekDay: Identifiable {
    let date: String
    let tasks: [SchoolTask]
    let events: [SchoolItem]
    var id: String { date }
    var pendingCount: Int { tasks.filter { !$0.isCompleted }.count }
}

struct SchoolWeekOverview {
    static let dayCount = 7
    let days: [SchoolWeekDay]
    let overdue: [SchoolTask]
    let undated: [SchoolTask]

    init(tasks: [SchoolTask], events: [SchoolItem], now: Date,
         showCompleted: Bool = false, search: String = "") {
        let visible = SchoolTaskList.sorted(tasks.filter {
            (showCompleted || !$0.isCompleted) && SchoolTaskList.matches($0, search: search)
        })
        let today = SchoolDates.dayKey(now)
        overdue = visible.filter { $0.dueDate.flatMap(SchoolTask.validDay).map { $0 < today } ?? false }
        undated = visible.filter { $0.dueDate.flatMap(SchoolTask.validDay) == nil }
        let start = SchoolDates.calendar.startOfDay(for: now)
        days = (0..<Self.dayCount).compactMap { offset in
            guard let day = SchoolDates.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = SchoolDates.dayKey(day)
            return SchoolWeekDay(date: key, tasks: visible.filter { $0.dueDate == key },
                events: Self.events(events, on: key, search: search))
        }
    }

    private static func events(_ events: [SchoolItem], on day: String, search: String) -> [SchoolItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter {
            !$0.canceled && String($0.date.prefix(10)) == day
                && (query.isEmpty || [$0.title, $0.body, $0.subtitle].contains { $0.localizedStandardContains(query) })
        }.sorted { ($0.time, $0.title, $0.id) < ($1.time, $1.title, $1.id) }
    }
}
