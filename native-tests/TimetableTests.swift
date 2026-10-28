import Foundation

@main
struct TimetableTests {
    static func main() {
        let now = ISO8601DateFormatter().date(from: "2026-10-28T10:00:00Z")!
        let lessons = [
            SchoolItem(id: "late", title: "Geografia", date: "2026-10-26", time: "10:40–11:25"),
            SchoolItem(id: "early", title: "Matematyka", date: "2026-10-26", time: "08:00–08:45"),
            SchoolItem(id: "group-a", title: "Angielski A", date: "2026-10-27", time: "08:00–08:45"),
            SchoolItem(id: "group-b", title: "Angielski B", date: "2026-10-27", time: "08:00–08:45", canceled: true),
            SchoolItem(id: "next", title: "Polski", date: "2026-11-02", time: "08:00–08:45"),
        ]
        let current = TimetableWeek(items: lessons, offset: 0, now: now)
        assert(current.days.map(\.date) == ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30"])
        assert(current.slots == ["08:00–08:45", "10:40–11:25"], "Time rows must be chronological")
        assert(current.lessons(on: "2026-10-26", at: "08:00–08:45").map(\.id) == ["early"])
        let parallel = current.lessons(on: "2026-10-27", at: "08:00–08:45")
        assert(parallel.count == 2 && parallel.contains(where: \.canceled), "Parallel and cancelled lessons must remain visible")
        assert(current.lessons(on: "2026-10-28", at: "08:00–08:45").isEmpty)
        assert(!current.title.isEmpty && current.days[0].title == "Poniedziałek")
        assert(TimetableWeek(items: lessons, offset: 1, now: now).items.map(\.id) == ["next"])
        let searched = TimetableWeek(items: lessons, offset: 0, now: now, search: "matematyka")
        assert(searched.items.map(\.id) == ["early"])

        let weekend = SchoolItem(id: "weekend", title: "Warsztaty", date: "2026-10-31", time: "09:00–10:00")
        let withWeekend = TimetableWeek(items: lessons + [weekend], offset: 0, now: now)
        assert(withWeekend.days.last?.date == "2026-10-31", "Published weekend lessons must not disappear")
        let warsawMonday = ISO8601DateFormatter().date(from: "2026-11-01T23:30:00Z")!
        assert(TimetableWeek(items: lessons, offset: 0, now: warsawMonday).days.first?.date == "2026-11-02")
        assert(TimetableWeek(items: [], offset: 0, now: now).days.count == 5)
        print("Swift timetable: week/day grouping, time order, parallel lessons, cancellation, search and Warsaw timezone passed")
    }
}
