import Foundation

@main
struct GradeListTests {
    static func main() throws {
        recentOrderAndFilters()
        stableCategoryOptions()
        subjectHistory()
        try legacyCache()
        print("Swift grades: recent order, semester/category/search filters, stable groups and legacy cache passed")
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

    static func legacyCache() throws {
        let data = Data(#"{"id":"old","title":"Matematyka","subtitle":"","body":"","date":"2026-02-01","time":"","value":"5","unread":false,"canceled":false,"mailbox":"inbox","attachments":[]}"#.utf8)
        let item = try JSONDecoder().decode(SchoolItem.self, from: data)
        assert(item.semester == nil && item.category == nil && item.subjectId == nil)
        let list = SchoolGradeList(items: [item])
        assert(list.recent.count == 1 && list.subjects.count == 1)
        assert(list.semesters.isEmpty && list.categories.isEmpty)
        assert(SchoolGradeList(items: [item], semester: .semester(2)).recent.isEmpty,
               "A February date must not invent semester metadata")
    }
}
