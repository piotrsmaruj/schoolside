import Foundation

@main
struct GradeListTests {
    static func main() throws {
        recentOrderAndFilters()
        stableCategoryOptions()
        subjectHistory()
        try weightedPointsAverage()
        percentageAverages()
        averageUsesVisibleGrades()
        averageRejectsMissingOrInvalidData()
        averageRejectsInvalidMaximaAndWeights()
        fractionalWeights()
        roundingMatchesLibrus()
        try averageMetadataDecoding()
        try legacyCache()
        print("Swift grades: filters, groups, percentage averages, exclusions and legacy cache passed")
    }

    static let items = [
        SchoolItem(id: "older", title: "Matematyka", subtitle: "Kartkówka", body: "Ułamki", date: "2026-10-01", value: "5", semester: 1, category: "Kartkówka", subjectId: "2"),
        SchoolItem(id: "newest", title: "Matematyka", subtitle: "Sprawdzian · 25 / 30 pkt", date: "2026-10-28", value: "83,3%", semester: 2, category: "Sprawdzian", subjectId: "2"),
        SchoolItem(id: "same-date", title: "Angielski", date: "2026-10-28", value: "4", semester: 1, category: " kartkówka ", subjectId: "3"),
        SchoolItem(id: "legacy", title: "Historia", date: "2026-02-01", value: "3"),
    ]

    static func recentOrderAndFilters() {
        assert(SchoolGradeList(items: items).recent.map(\.id) == ["newest", "same-date", "older", "legacy"])
        let first = SchoolGradeList(items: items, semester: .semester(1), category: .named("kartkówka"))
        assert(first.recent.map(\.id) == ["same-date", "older"])
        assert(SchoolGradeList(items: items, search: "ułamki").recent.map(\.id) == ["older"])
        assert(SchoolGradeList(items: items, search: "83,3%").recent.map(\.id) == ["newest"])
        assert(SchoolGradeList(items: items, semester: .unknown).recent.map(\.id) == ["legacy"])
        assert(SchoolGradeList(items: items, category: .unknown).recent.map(\.id) == ["legacy"])
        assert(SchoolGradeList(items: items, search: "nieistniejący").recent.isEmpty)
    }

    static func stableCategoryOptions() {
        let filtered = SchoolGradeList(items: items, search: "Historia", semester: .semester(9))
        assert(filtered.semesters == [1, 2])
        assert(filtered.categories.map(\.id) == ["kartkówka", "sprawdzian"])
        assert(filtered.categories.map(\.title) == ["Kartkówka", "Sprawdzian"])
        assert(filtered.hasUnknownSemester && filtered.hasUnknownCategory)
        assert(filtered.categories == SchoolGradeList(items: items.reversed()).categories,
               "Options must not change with source order, search or another filter")
    }

    static func subjectHistory() {
        let list = SchoolGradeList(items: items.reversed())
        assert(list.subjects.map(\.title) == ["Angielski", "Historia", "Matematyka"])
        let math = list.subjects.last!
        assert(math.items.map(\.id) == ["newest", "older"])
        let sameNames = [SchoolItem(id: "a", title: "Przedmiot", subjectId: "10"),
                         SchoolItem(id: "b", title: "Przedmiot", subjectId: "11"),
                         SchoolItem(id: "c", title: " Historia "),
                         SchoolItem(id: "d", title: "historia")]
        let groups = SchoolGradeList(items: sameNames).subjects
        assert(groups.count == 3, "Different known subject IDs must stay distinct")
        assert(groups.first?.items.count == 2, "Legacy subject titles form a case-insensitive fallback group")
        assert(SchoolGradeList(items: items, search: "Sprawdzian").subjects.first?.id == math.id)
    }

    static let averageItems = [
        SchoolItem(id: "small", title: "Matematyka", subtitle: "6 / 10 pkt", value: "60%", semester: 1, category: "Kartkówka", subjectId: "2", gradePoints: 6, gradeMaxPoints: 10, gradeWeight: 2, countsToAverage: true),
        SchoolItem(id: "large", title: "Matematyka", subtitle: "100 / 100 pkt", value: "100%", semester: 2, category: "Sprawdzian", subjectId: "2", gradePoints: 100, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: true),
        SchoolItem(id: "bonus", title: "Angielski", value: "110%", semester: 1, subjectId: "3", gradePoints: 110, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: true),
        SchoolItem(id: "excluded", title: "Matematyka", value: "0%", subjectId: "2", gradePoints: 0, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: false),
        SchoolItem(id: "standard", title: "Matematyka", value: "5", subjectId: "2"),
    ]

    static func weightedPointsAverage() throws {
        let data = Data(#"[{"id":"a","title":"Matematyka","subtitle":"","body":"","date":"","time":"","value":"60%","unread":false,"canceled":false,"mailbox":"inbox","attachments":[],"grade_percentage":60,"counts_to_average":true,"grade_points":6,"grade_max_points":10,"grade_weight":2},{"id":"b","title":"Matematyka","subtitle":"","body":"","date":"","time":"","value":"100%","unread":false,"canceled":false,"mailbox":"inbox","attachments":[],"grade_percentage":100,"counts_to_average":true,"grade_points":100,"grade_max_points":100,"grade_weight":1}]"#.utf8)
        let decoded = try JSONDecoder().decode([SchoolItem].self, from: data)
        let average = SchoolGradeAverage(items: decoded)
        assert(abs(average.percentage! - 93.33333333333333) < 0.000001,
               "Librus point result uses weighted earned / weighted possible, not the mean of percentages")
    }

    static func percentageAverages() {
        let list = SchoolGradeList(items: averageItems)
        let math = list.subjects.first { $0.id == "subject:2" }!
        assert(abs(math.average.percentage! - 93.33333333333333) < 0.000001 && math.average.count == 2,
               "Both category weight and maximum points must affect the subject result")
        assert(math.average.displayValue == "93,33%")
        let english = list.subjects.first { $0.id == "subject:3" }!
        assert(abs(english.average.percentage! - 110) < 0.000001 && english.average.count == 1,
               "A subject average must not include grades from another subject")
        let precise = SchoolGradeAverage(items: [
            SchoolItem(id: "a", title: "Matematyka", value: "83,3%", gradePoints: 83.34, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: true),
            SchoolItem(id: "b", title: "Matematyka", value: "83,3%", gradePoints: 83.38, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: true),
        ])
        assert(abs(precise.percentage! - 83.36) < 0.000001)
        assert(precise.displayValue == "83,36%", "Round the result, not the source grades")
    }

    static func averageUsesVisibleGrades() {
        let filtered = SchoolGradeList(items: averageItems, search: "matematyka",
                                       semester: .semester(1), category: .named("kartkówka"))
        assert(filtered.subjects.first?.average.percentage == 60)
        assert(filtered.subjects.first?.average.count == 1)
        let second = SchoolGradeList(items: averageItems, semester: .semester(2))
        assert(second.subjects.first?.average.percentage == 100)
        assert(second.subjects.first?.average.count == 1)
        assert(SchoolGradeList(items: averageItems, search: "brak wyników").subjects.isEmpty)
    }

    static func averageRejectsMissingOrInvalidData() {
        let invalid = [Double.nan, .infinity, -.infinity, -10].enumerated().map { index, value in
            SchoolItem(id: "invalid:\(index)", title: "Przedmiot", gradePoints: value, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: true)
        }
        let unavailable = SchoolGradeAverage(items: invalid + [
            SchoolItem(id: "legacy", title: "Przedmiot", value: "80%"),
            SchoolItem(id: "unknown", title: "Przedmiot", gradePoints: 90, gradeMaxPoints: 100, gradeWeight: 1),
            SchoolItem(id: "missing", title: "Przedmiot", countsToAverage: true),
        ])
        assert(unavailable.percentage == nil && unavailable.count == 0)
        assert(unavailable.displayValue == "—")
        let zero = SchoolGradeAverage(items: [
            SchoolItem(id: "zero", title: "Przedmiot", gradePoints: 0, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: true),
        ])
        assert(zero.percentage == 0 && zero.count == 1 && zero.displayValue == "0,00%")
        assert(SchoolGradeAverage(items: []).percentage == nil)
    }

    static func averageRejectsInvalidMaximaAndWeights() {
        let invalid: [Double?] = [nil, 0, -1, .nan, .infinity, -.infinity]
        for value in invalid {
            let maximum = SchoolItem(id: "maximum", title: "Przedmiot", gradePoints: 10,
                                     gradeMaxPoints: value, gradeWeight: 1, countsToAverage: true)
            let weight = SchoolItem(id: "weight", title: "Przedmiot", gradePoints: 10,
                                    gradeMaxPoints: 100, gradeWeight: value, countsToAverage: true)
            let result = SchoolGradeAverage(items: [maximum, weight])
            assert(result.count == 0 && result.percentage == nil)
        }
    }

    static func fractionalWeights() {
        let result = SchoolGradeAverage(items: [
            SchoolItem(id: "small", title: "Przedmiot", gradePoints: 6, gradeMaxPoints: 10, gradeWeight: 0.5, countsToAverage: true),
            SchoolItem(id: "large", title: "Przedmiot", gradePoints: 100, gradeMaxPoints: 100, gradeWeight: 1, countsToAverage: true),
            SchoolItem(id: "ignored", title: "Przedmiot", gradePoints: 0, gradeMaxPoints: 100, gradeWeight: 0, countsToAverage: true),
        ])
        assert(result.count == 2 && result.displayValue == "98,10%",
               "Fractional weights must survive and zero weights must not count")
    }

    static func roundingMatchesLibrus() {
        let result = SchoolGradeAverage(items: [
            SchoolItem(id: "rounding", title: "Przedmiot", gradePoints: 381, gradeMaxPoints: 800,
                       gradeWeight: 1, countsToAverage: true),
        ])
        assert(result.percentage == 47.625)
        assert(result.displayValue == "47,63%", "A half cent must round up, as in Librus, rather than to even")
    }

    static func averageMetadataDecoding() throws {
        let data = Data(#"{"id":"point:1","title":"Matematyka","subtitle":"25 / 30 pkt","body":"","date":"2026-10-28","time":"","value":"83,3%","unread":false,"canceled":false,"mailbox":"inbox","attachments":[],"grade_points":25,"grade_max_points":30,"grade_weight":1,"counts_to_average":true}"#.utf8)
        let item = try JSONDecoder().decode(SchoolItem.self, from: data)
        let average = SchoolGradeAverage(items: [item])
        assert(average.count == 1 && average.displayValue == "83,33%")
        assert(abs(average.percentage! - 83.33333333333333) < 0.000001)
        let restored = try JSONDecoder().decode(SchoolItem.self, from: JSONEncoder().encode(item))
        assert(restored == item, "Average inputs must survive an offline cache round trip")
    }

    static func legacyCache() throws {
        let data = Data(#"{"id":"old","title":"Matematyka","subtitle":"","body":"","date":"2026-02-01","time":"","value":"5","unread":false,"canceled":false,"mailbox":"inbox","attachments":[]}"#.utf8)
        let item = try JSONDecoder().decode(SchoolItem.self, from: data)
        assert(item.semester == nil && item.category == nil && item.subjectId == nil)
        assert(item.gradePoints == nil && item.gradeMaxPoints == nil && item.gradeWeight == nil)
        assert(item.countsToAverage == nil)
        let list = SchoolGradeList(items: [item])
        assert(list.recent.count == 1 && list.subjects.count == 1)
        assert(list.semesters.isEmpty && list.categories.isEmpty)
        assert(list.subjects.first?.average.percentage == nil, "An old cache must not invent average eligibility")
        assert(SchoolGradeList(items: [item], semester: .semester(2)).recent.isEmpty,
               "A February date must not invent semester metadata")
    }
}
