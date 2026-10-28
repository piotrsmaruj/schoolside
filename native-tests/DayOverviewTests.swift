import Foundation

@main
struct DayOverviewTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-28T10:00:00Z")!

    static func main() {
        currentAndNextLesson()
        tomorrowAndMidnight()
        eventsAndHomework()
        invalidTimes()
        failedModulesAreNotEmptyDays()
        print("Swift day: current/next lesson, cancellation, tomorrow, Warsaw midnight, events and homework passed")
    }

    static func snapshot(_ sections: [String: [SchoolItem]]) -> SchoolSnapshot {
        SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-10-28", sections: sections)
    }

    static func currentAndNextLesson() {
        let lessons = [
            SchoolItem(id: "next", title: "Angielski", date: "2026-10-28", time: "11:30–12:15"),
            SchoolItem(id: "current", title: "WF", date: "2026-10-28", time: "10:40–11:25"),
            SchoolItem(id: "last", title: "Historia", date: "2026-10-28", time: "13:25–14:10", canceled: true),
        ]
        let day = SchoolDayOverview(snapshot: snapshot(["timetable": lessons]), offset: 0, now: now)
        assert(day.currentLesson?.id == "current", "11:00 Warsaw is inside the 10:40 lesson")
        assert(day.nextLesson?.id == "next")
        assert(day.endTime == "12:15", "Canceled lessons must not extend the school day")
        assert(day.lessons.map(\.id) == ["current", "next", "last"])
    }

    static func tomorrowAndMidnight() {
        let lesson = SchoolItem(id: "tomorrow", title: "Matematyka", date: "2026-10-29", time: "08:00–08:45")
        let data = snapshot(["timetable": [lesson]])
        let day = SchoolDayOverview(snapshot: data, offset: 1, now: now)
        assert(day.dayKey == "2026-10-29" && day.currentLesson == nil && day.nextLesson?.id == "tomorrow")
        let midnight = ISO8601DateFormatter().date(from: "2026-10-28T23:30:00Z")!
        assert(SchoolDayOverview(snapshot: data, offset: 0, now: midnight).dayKey == "2026-10-29")
        assert(SchoolDates.relativeDay("2026-10-29", now: now) == "Jutro")
        assert(SchoolDates.relativeDay("2026-10-31", now: now) == "Za 3 dni")
        for timestamp in ["2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z"] {
            let changingClocks = ISO8601DateFormatter().date(from: timestamp)!
            assert(SchoolDayOverview(snapshot: nil, offset: 1, now: changingClocks).dayKey == "2026-10-26",
                   "Both occurrences of 02:30 during the DST fallback must have the same tomorrow")
        }
    }

    static func eventsAndHomework() {
        let events = [
            SchoolItem(id: "late", title: "Historia", date: "2026-10-29", time: "12:00:00"),
            SchoolItem(id: "early", title: "Matematyka", date: "2026-10-29", time: "09:00:00"),
            SchoolItem(id: "past", title: "Polski", date: "2026-10-28", time: "08:00:00"),
        ]
        let homework = [SchoolItem(id: "due", title: "Zadanie", date: "2026-10-29"),
                        SchoolItem(id: "old", title: "Stare", date: "2026-10-27")]
        let day = SchoolDayOverview(snapshot: snapshot(["agenda": events, "homework": homework]), offset: 0, now: now)
        assert(day.events.map(\.id) == ["early", "late"], "Events must sort by both day and time")
        assert(day.homework.map(\.id) == ["due"], "The preview contains homework due tomorrow")
        assert(day.currentLesson == nil && day.nextLesson == nil && day.endTime == nil)
    }

    static func invalidTimes() {
        let invalid = SchoolItem(id: "bad", title: "Lekcja", date: "2026-10-28", time: "nieznana")
        let day = SchoolDayOverview(snapshot: snapshot(["timetable": [invalid]]), offset: 0, now: now)
        assert(day.lessons.count == 1 && day.currentLesson == nil && day.endTime == nil)
    }

    static func failedModulesAreNotEmptyDays() {
        let failed = SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-10-28",
            sections: ["timetable": [], "homework": []],
            errors: ["timetable": "connection_error", "homework": "connection_error"])
        let firstFailure = SchoolDayOverview(snapshot: failed, offset: 0, now: now)
        assert(firstFailure.planState == .unavailable && firstFailure.homeworkState == .unavailable,
               "A failed fetch must never be presented as a valid day without lessons or homework")
        let baseline = snapshot(["timetable": [], "homework": []]).merging(previous: nil)
        let cached = failed.merging(previous: baseline)
        let stale = SchoolDayOverview(snapshot: cached, offset: 0, now: now)
        assert(stale.planState == .stale && stale.homeworkState == .stale)
        let emptyDay = SchoolDayOverview(snapshot: baseline, offset: 0, now: now)
        assert(emptyDay.planState == .available && emptyDay.homeworkState == .available)
    }
}
