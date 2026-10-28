import Foundation

struct TimetableDay: Identifiable {
    let date: String
    let title: String
    let shortDate: String
    let weekend: Bool
    var id: String { date }
}

struct TimetableWeek {
    let days: [TimetableDay]
    let slots: [String]
    let items: [SchoolItem]
    let title: String

    init(items: [SchoolItem], offset: Int, now: Date = Date(), search: String = "") {
        let allDays = Self.weekDays(offset: offset, now: now)
        let dates = Set(allDays.map(\.date))
        let published = items.filter { dates.contains($0.date) }
        let publishedDates = Set(published.map(\.date))
        days = allDays.filter { !$0.weekend || publishedDates.contains($0.date) }
        self.items = published.filter { item in
            search.isEmpty || [item.title, item.subtitle, item.body].contains {
                $0.localizedCaseInsensitiveContains(search)
            }
        }.sorted { ($0.date, $0.time, $0.id) < ($1.date, $1.time, $1.id) }
        slots = Set(self.items.map(\.time)).sorted { (Self.startMinute($0), $0) < (Self.startMinute($1), $1) }
        title = "\(days.first?.shortDate ?? "") – \(days.last?.shortDate ?? "")"
    }

    func lessons(on date: String, at time: String) -> [SchoolItem] {
        items.filter { $0.date == date && $0.time == time }
    }

    private static func weekDays(offset: Int, now: Date) -> [TimetableDay] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
        let monday = calendar.dateInterval(of: .weekOfYear, for: shifted)?.start ?? shifted
        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: monday) else { return nil }
            return TimetableDay(date: formatted(date, "yyyy-MM-dd", calendar),
                title: formatted(date, "EEEE", calendar).capitalized,
                shortDate: formatted(date, "d MMM", calendar), weekend: calendar.isDateInWeekend(date))
        }
    }

    private static func formatted(_ date: Date, _ format: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func startMinute(_ time: String) -> Int {
        let components = time.prefix(5).split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return .max }
        return components[0] * 60 + components[1]
    }
}
