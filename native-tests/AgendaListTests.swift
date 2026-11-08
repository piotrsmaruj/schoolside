import Foundation

@main
struct AgendaListTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-24T08:30:00Z")!

    static func main() {
        groupsAndChronology()
        searchIncludesPastEvents()
        clockAndWarsawMidnight()
        print("Swift agenda: grouping, chronology, past search, invalid dates and Warsaw midnight passed")
    }

    static func groupsAndChronology() {
        let items = [
            SchoolItem(id: "later", title: "Później", date: "2026-10-27"),
            SchoolItem(id: "oldest", title: "Dawno", date: "2026-10-20"),
            SchoolItem(id: "today-late", title: "Dzisiaj później", date: "2026-10-24", time: "14:00"),
            SchoolItem(id: "invalid", title: "Zła data", date: "2026-02-31"),
            SchoolItem(id: "tomorrow", title: "Jutro", date: "2026-10-25"),
            SchoolItem(id: "today-early", title: "Dzisiaj rano", date: "2026-10-24", time: "8:00"),
            SchoolItem(id: "today", title: "Całodniowe", date: "2026-10-24"),
            SchoolItem(id: "yesterday", title: "Wczoraj", date: "2026-10-23"),
            SchoolItem(id: "undated", title: "Bez daty"),
        ]
        let list = SchoolAgendaList(items, now: now)
        assert(list.groups.map(\.kind) == [.today, .upcoming, .undated, .past])
        assert(list.groups[0].items.map(\.id) == ["today", "today-late"])
        assert(list.groups[1].items.map(\.id) == ["tomorrow", "later"])
        assert(Set(list.groups[2].items.map(\.id)) == ["invalid", "undated"])
        assert(list.groups[3].items.map(\.id) == ["today-early", "yesterday", "oldest"])
        assert(list.groups.flatMap(\.items).count == items.count, "Every event must remain available exactly once")
    }

    static func searchIncludesPastEvents() {
        let past = SchoolItem(id: "past", title: "Matematyka", body: "Powtórka z geometrii", date: "2026-10-20")
        let future = SchoolItem(id: "future", title: "Polski", subtitle: "Wycieczka", date: "2026-10-26")
        let list = SchoolAgendaList([future, past], search: "  GEOMETRII  ", now: now)
        assert(list.groups.map(\.kind) == [.past])
        assert(list.groups[0].items.map(\.id) == ["past"])
        assert(SchoolAgendaList([future, past], search: "wycieczka", now: now).groups[0].items == [future])
        assert(SchoolAgendaList([future, past], search: "nie ma", now: now).groups.isEmpty)
        assert(SchoolAgendaList([], now: now).groups.isEmpty)
    }

    static func clockAndWarsawMidnight() {
        let event = SchoolItem(id: "timed", title: "Sprawdzian", date: "2026-10-24", time: "10:30")
        assert(SchoolAgendaList([event], now: now).groups[0].kind == .today)
        assert(SchoolAgendaList([event], now: now.addingTimeInterval(1)).groups[0].kind == .past)
        let allDay = SchoolItem(id: "all-day", title: "Całodniowe", date: "2026-10-24")
        let midnight = ISO8601DateFormatter().date(from: "2026-10-24T22:00:00Z")!
        assert(SchoolAgendaList([allDay], now: midnight.addingTimeInterval(-1)).groups[0].kind == .today)
        assert(SchoolAgendaList([allDay], now: midnight).groups[0].kind == .past)
    }
}
