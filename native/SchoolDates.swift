import Foundation

enum SchoolDates {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    static func dayKey(_ date: Date) -> String { formatted(date, "yyyy-MM-dd") }
    static var today: String { dayKey(Date()) }

    static func parseDay(_ value: String) -> Date? {
        let parser = formatter("yyyy-MM-dd")
        parser.isLenient = false
        return parser.date(from: String(value.prefix(10)))
    }

    static func display(_ value: String) -> String {
        guard let date = parseDay(value) else { return "—" }
        return formatted(date, "d MMM yyyy")
    }

    static func syncDisplay(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: value) else { return display(value) }
        return formatted(date, "d MMM, HH:mm")
    }

    static func relativeDay(_ value: String, now: Date) -> String {
        guard let date = parseDay(value) else { return "Brak daty" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day ?? 0
        switch days {
        case 0: return "Dzisiaj"
        case 1: return "Jutro"
        case 2...6: return "Za \(days) dni"
        default: return formatted(date, "d MMM")
        }
    }

    static func time(_ value: String, on day: String) -> Date? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute), let date = parseDay(day) else { return nil }
        let second = parts.count == 3 ? Int(parts[2]) : 0
        guard let second, (0..<60).contains(second) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: date)
    }

    static func lessonBounds(_ item: SchoolItem) -> DateInterval? {
        let parts = item.time.replacingOccurrences(of: "-", with: "–").split(separator: "–")
        guard parts.count == 2,
              let start = time(String(parts[0]).trimmingCharacters(in: .whitespaces), on: item.date),
              let end = time(String(parts[1]).trimmingCharacters(in: .whitespaces), on: item.date), end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func timetableWindow(_ fetchedAt: String) -> DateInterval? {
        guard let date = parseDay(fetchedAt) else { return nil }
        let daysSinceMonday = (calendar.component(.weekday, from: date) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: date),
              let end = calendar.date(byAdding: .day, value: 14, to: monday) else { return nil }
        return DateInterval(start: monday, end: end)
    }

    static func formatted(_ date: Date, _ format: String) -> String {
        formatter(format).string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
