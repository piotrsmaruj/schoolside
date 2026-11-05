import Foundation

enum SchoolGradeMode: String, CaseIterable, Identifiable {
    case recent, subjects
    var id: Self { self }
    var title: String { self == .recent ? "Ostatnie" : "Przedmioty" }
}

enum SchoolGradeSemester: Hashable {
    case all, semester(Int), unknown
}

enum SchoolGradeCategory: Hashable {
    case all, named(String), unknown
}

struct SchoolGradeCategoryOption: Identifiable, Equatable {
    let id: String
    let title: String
}

/// Point-grade result: 100 * sum(points * weight) / sum(maximum * weight).
struct SchoolGradeAverage {
    let percentage: Double?
    let count: Int

    init(items: [SchoolItem]) {
        let values = items.compactMap(Self.contribution)
        count = values.count
        let earned = values.reduce(0) { $0 + $1.earned }
        let possible = values.reduce(0) { $0 + $1.possible }
        guard earned.isFinite, possible.isFinite, possible > 0 else {
            percentage = nil
            return
        }
        let result = (earned / possible) * 100
        percentage = result.isFinite ? result : nil
    }

    private static func contribution(_ item: SchoolItem) -> (earned: Double, possible: Double)? {
        guard item.countsToAverage == true,
              let points = item.gradePoints, points.isFinite, points >= 0,
              let maximum = item.gradeMaxPoints, maximum.isFinite, maximum > 0,
              let weight = item.gradeWeight, weight.isFinite, weight > 0 else { return nil }
        let earned = points * weight
        let possible = maximum * weight
        guard earned.isFinite, possible.isFinite, possible > 0 else { return nil }
        return (earned, possible)
    }

    var displayValue: String {
        guard let percentage else { return "—" }
        return percentage.formatted(.number.locale(Locale(identifier: "pl_PL"))
            .precision(.fractionLength(2)).rounded(rule: .toNearestOrAwayFromZero)) + "%"
    }

    var explanation: String {
        guard percentage != nil else {
            return "Brak ocen procentowych z danymi do obliczenia średniej. Odśwież dane, jeśli pochodzą ze starszej wersji."
        }
        return "100 × suma(punkty × waga) / suma(maksymalne punkty × waga), z widocznych ocen tego przedmiotu. "
            + "Uwzględnione oceny: \(count). Pomijamy oceny wyłączone ze średniej w Librusie oraz wpisy bez pełnych danych."
    }
}

struct SchoolGradeSubject: Identifiable {
    let id: String
    let title: String
    let items: [SchoolItem]
    var average: SchoolGradeAverage { SchoolGradeAverage(items: items) }
}

/// Filtering never guesses missing metadata; picker options describe the full source.
struct SchoolGradeList {
    let recent: [SchoolItem]
    let subjects: [SchoolGradeSubject]
    let semesters: [Int]
    let categories: [SchoolGradeCategoryOption]
    let hasUnknownSemester: Bool
    let hasUnknownCategory: Bool

    init(items: [SchoolItem], search: String = "", semester: SchoolGradeSemester = .all,
         category: SchoolGradeCategory = .all) {
        semesters = Array(Set(items.compactMap(\.semester))).sorted()
        categories = Self.categoryOptions(items)
        hasUnknownSemester = items.contains { $0.semester == nil }
        hasUnknownCategory = items.contains { Self.cleaned($0.category).isEmpty }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        recent = items.filter {
            Self.matches($0, semester: semester) && Self.matches($0, category: category)
                && Self.matches($0, search: query)
        }.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date
        }
        subjects = Self.grouped(recent)
    }

    private static func matches(_ item: SchoolItem, semester: SchoolGradeSemester) -> Bool {
        switch semester {
        case .all: true
        case .semester(let selected): item.semester == selected
        case .unknown: item.semester == nil
        }
    }

    private static func matches(_ item: SchoolItem, category: SchoolGradeCategory) -> Bool {
        switch category {
        case .all: true
        case .named(let selected): key(item.category) == key(selected)
        case .unknown: cleaned(item.category).isEmpty
        }
    }

    private static func matches(_ item: SchoolItem, search: String) -> Bool {
        search.isEmpty || [item.title, item.subtitle, item.body, item.value, item.category ?? ""]
            .contains { $0.localizedStandardContains(search) }
    }

    private static func categoryOptions(_ items: [SchoolItem]) -> [SchoolGradeCategoryOption] {
        let names = Set(items.map { cleaned($0.category) }.filter { !$0.isEmpty }).sorted()
        let grouped = Dictionary(grouping: names, by: { key($0) })
        return grouped.map { SchoolGradeCategoryOption(id: $0.key, title: $0.value[0]) }
            .sorted { ordered($0.title, $1.title, firstID: $0.id, secondID: $1.id) }
    }

    private static func grouped(_ items: [SchoolItem]) -> [SchoolGradeSubject] {
        Dictionary(grouping: items, by: subjectKey).map { id, history in
            let title = history.map { cleaned($0.title) }.sorted().first ?? "Przedmiot"
            return SchoolGradeSubject(id: id, title: title, items: history)
        }.sorted { ordered($0.title, $1.title, firstID: $0.id, secondID: $1.id) }
    }

    private static func subjectKey(_ item: SchoolItem) -> String {
        let identifier = cleaned(item.subjectId)
        return identifier.isEmpty ? "title:\(key(item.title))" : "subject:\(identifier)"
    }

    private static func cleaned(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func key(_ text: String?) -> String {
        cleaned(text).folding(options: .caseInsensitive, locale: Locale(identifier: "pl_PL"))
    }

    private static func ordered(_ first: String, _ second: String, firstID: String, secondID: String) -> Bool {
        let comparison = first.compare(second, options: [.caseInsensitive, .numeric], locale: Locale(identifier: "pl_PL"))
        return comparison == .orderedSame ? firstID < secondID : comparison == .orderedAscending
    }
}
