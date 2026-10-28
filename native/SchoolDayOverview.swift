import Foundation

enum SchoolDataState { case available, stale, unavailable }

struct SchoolDayOverview {
    let planState: SchoolDataState
    let homeworkState: SchoolDataState
    let agendaState: SchoolDataState
    let gradesState: SchoolDataState
    let dayKey: String
    let lessons: [SchoolItem]
    let currentLesson: SchoolItem?
    let nextLesson: SchoolItem?
    let endTime: String?
    let events: [SchoolItem]
    let homework: [SchoolItem]
    let recentGrades: [SchoolItem]

    init(snapshot: SchoolSnapshot?, offset: Int, now: Date) {
        planState = Self.state(snapshot, section: .timetable)
        homeworkState = Self.state(snapshot, section: .homework)
        agendaState = Self.state(snapshot, section: .agenda)
        gradesState = Self.state(snapshot, section: .grades)
        let selectedDay = SchoolDates.dayKey(SchoolDates.calendar.date(byAdding: .day, value: offset, to: now) ?? now)
        dayKey = selectedDay
        lessons = Self.sortedLessons((snapshot?.sections["timetable"] ?? []).filter { $0.date == selectedDay })
        let active = lessons.filter { !$0.canceled }
        currentLesson = active.first {
            guard let bounds = SchoolDates.lessonBounds($0) else { return false }
            return bounds.start <= now && now < bounds.end
        }
        nextLesson = active.first { (SchoolDates.lessonBounds($0)?.start ?? .distantPast) > now }
        endTime = active.compactMap { SchoolDates.lessonBounds($0)?.end }.max().map {
            SchoolDates.formatted($0, "HH:mm")
        }
        events = Self.upcoming(snapshot?.sections["agenda"] ?? [], from: dayKey, now: now)
        let tomorrow = SchoolDates.dayKey(SchoolDates.calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        homework = (snapshot?.sections["homework"] ?? []).filter { String($0.date.prefix(10)) == tomorrow }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        recentGrades = (snapshot?.sections["grades"] ?? []).sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    private static func sortedLessons(_ items: [SchoolItem]) -> [SchoolItem] {
        items.sorted {
            let left = SchoolDates.lessonBounds($0)?.start ?? .distantFuture
            let right = SchoolDates.lessonBounds($1)?.start ?? .distantFuture
            return left == right ? $0.id < $1.id : left < right
        }
    }

    private static func upcoming(_ items: [SchoolItem], from day: String, now: Date) -> [SchoolItem] {
        items.filter {
            guard SchoolDates.parseDay($0.date) != nil, String($0.date.prefix(10)) >= day else { return false }
            return SchoolDates.time($0.time, on: $0.date).map { $0 >= now } ?? true
        }.sorted { ($0.date, $0.time, $0.id) < ($1.date, $1.time, $1.id) }
    }

    static func failedSections(in snapshot: SchoolSnapshot?) -> [SchoolSection] {
        SchoolSection.allCases.filter {
            snapshot?.errors[$0.rawValue] != nil || ($0 == .timetable && snapshot?.errors["references"] != nil)
        }
    }

    private static func state(_ snapshot: SchoolSnapshot?, section: SchoolSection) -> SchoolDataState {
        guard let snapshot else { return .unavailable }
        if failedSections(in: snapshot).contains(section) {
            return snapshot.successfulFetchDate(for: section.rawValue) == nil ? .unavailable : .stale
        }
        return snapshot.sections[section.rawValue] == nil ? .unavailable : .available
    }
}
