import Foundation

struct SchoolAgendaGroup: Identifiable {
    enum Kind: String, CaseIterable { case today, upcoming, undated, past }
    let kind: Kind
    let items: [SchoolItem]
    var id: String { kind.rawValue }
    var title: String {
        switch kind {
        case .today: "Dzisiaj"
        case .upcoming: "Nadchodzące"
        case .undated: "Bez daty"
        case .past: "Minione"
        }
    }
}

struct SchoolAgendaList {
    let groups: [SchoolAgendaGroup]

    init(_ events: [SchoolItem], search: String = "", now: Date) {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = events.filter { item in
            query.isEmpty || [item.title, item.subtitle, item.body].contains { $0.localizedStandardContains(query) }
        }
        let grouped = Dictionary(grouping: visible) { Self.kind($0, now: now) }
        groups = SchoolAgendaGroup.Kind.allCases.compactMap { kind in
            guard let items = grouped[kind] else { return nil }
            let ordered = items.sorted {
                let left = (Self.start($0), $0.id)
                let right = (Self.start($1), $1.id)
                return kind == .past ? left > right : left < right
            }
            return SchoolAgendaGroup(kind: kind, items: ordered)
        }
    }

    private static func kind(_ item: SchoolItem, now: Date) -> SchoolAgendaGroup.Kind {
        guard let day = SchoolDates.parseDay(item.date) else { return .undated }
        if SchoolDates.isPastEvent(item, now: now) { return .past }
        return SchoolDates.calendar.isDate(day, inSameDayAs: now) ? .today : .upcoming
    }

    private static func start(_ item: SchoolItem) -> Date {
        SchoolDates.time(item.time, on: item.date) ?? SchoolDates.parseDay(item.date) ?? .distantFuture
    }
}
