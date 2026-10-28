import Foundation

@main
struct TimetablePresentationTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-28T07:15:00Z")!

    static func main() throws {
        roomChangeKeepsPreviousLesson()
        parallelLessonsMatchWithoutProviderIDs()
        ambiguousParallelLessonsHaveNoPreviousLesson()
        movedLessonKeepsPreviousTime()
        swappedOccupiedSlotsPreserveLessonIdentity()
        differentSubjectInSameSlotHasNoPreviousLesson()
        substituteTeacherKeepsUnambiguousSubject()
        ambiguousSequentialLessonsHaveNoPreviousLesson()
        windowAndRecoveryRemainSafe()
        try previousLessonSurvivesCache()
        currentLessonUsesWarsawTimeAndBoundaries()
        statusAndUnknownTimesRemainExplicit()
        changesDescribeOnlyKnownValues()
        parallelCardsDoNotBorrowAnotherLessonsRoom()
        reviewAndWeekSelectionRemainCompatible()
        print("Swift timetable presentation: clock boundaries, cancellation, substitutions, changes, parallel matching, review and cache passed")
    }

    static func lesson(_ id: String = "index:0", title: String = "Matematyka",
                       teacher: String = "Nauczyciel A", room: String = "12",
                       time: String = "08:00–08:45", date: String = "2026-10-28") -> SchoolItem {
        SchoolItem(id: id, title: title, subtitle: "\(teacher) · Sala \(room)", date: date, time: time)
    }

    static func snapshot(_ items: [SchoolItem], fetchedAt: String = "2026-10-28") -> SchoolSnapshot {
        SchoolSnapshot(studentName: "Synthetic", fetchedAt: fetchedAt, sections: ["timetable": items])
    }

    static func changes(_ old: [SchoolItem], _ new: [SchoolItem]) -> [SchoolNewsEntry] {
        SchoolNews.planChanges(previous: snapshot(old), fresh: snapshot(new), at: now)
    }

    static func roomChangeKeepsPreviousLesson() {
        let before = lesson()
        let after = lesson("index:99", room: "24")
        let entries = changes([before], [after])
        assert(entries.count == 1 && entries[0].kind == .changed)
        assert(entries[0].previousItem == before, "A room change must preserve the unambiguous previous lesson")
        assert(changes([before], [lesson("index:99")]).isEmpty, "Positional IDs are not lesson identity")
    }

    static func parallelLessonsMatchWithoutProviderIDs() {
        let before = lesson("index:0")
        let unchanged = lesson("index:1", title: "Fizyka", room: "33")
        let changed = lesson("index:1", room: "24")
        let entries = changes([before, unchanged], [unchanged, changed])
        assert(entries.count == 1 && entries[0].previousItem == before,
               "Subtract unchanged parallel lessons before matching; provider IDs can be reused")

        let otherBefore = lesson("index:2", title: "Fizyka", room: "30")
        let otherAfter = lesson("index:0", title: "Fizyka", room: "34")
        let multiple = changes([before, otherBefore], [changed, otherAfter])
        assert(multiple.count == 1 && multiple[0].previousItem?.title == multiple[0].item.title,
               "Distinct subjects allow unique matching when two parallel lessons change")
    }

    static func ambiguousParallelLessonsHaveNoPreviousLesson() {
        let old = [lesson("index:0", room: "12"), lesson("index:1", room: "14")]
        let new = [lesson("index:0", room: "24"), lesson("index:1", room: "26")]
        let entries = changes(old, new)
        assert(entries.count == 1 && entries[0].previousItem == nil,
               "Parallel lessons with the same subject and teacher must not get a random old room")
    }

    static func movedLessonKeepsPreviousTime() {
        let before = lesson()
        let after = lesson("index:9", time: "09:00–09:45")
        let entries = changes([before], [after])
        assert(entries.count == 2, "Keep slot-based additions/removals compatible with review keys")
        assert(entries.first(where: { $0.item.time == after.time })?.previousItem == before,
               "An unambiguous lesson moved on the same day must retain its former time")
        let ambiguousOld = [before, lesson("index:1", time: "10:00–10:45")]
        assert(changes(ambiguousOld, [after]).first(where: { $0.item.time == after.time })?.previousItem == nil)
    }

    static func swappedOccupiedSlotsPreserveLessonIdentity() {
        let math = lesson("index:0", room: "12")
        let polish = lesson("index:1", title: "Polski", teacher: "Nauczyciel B", room: "33", time: "09:00–09:45")
        let movedMath = lesson("index:1", room: "12", time: "09:00–09:45")
        let movedPolish = lesson("index:0", title: "Polski", teacher: "Nauczyciel B", room: "33")
        let entries = changes([math, polish], [movedPolish, movedMath])
        assert(entries.count == 2)
        let mathChange = entries.first { $0.item.title == "Matematyka" }!
        let polishChange = entries.first { $0.item.title == "Polski" }!
        assert(mathChange.previousItem == math && polishChange.previousItem == polish,
               "Swapped occupied slots must match the original subject, never the displaced lesson")
        assert(SchoolTimetablePresentation(item: movedMath, news: entries, now: now).changeDescriptions ==
            ["Godzina 08:00–08:45 → 09:00–09:45"])
        assert(SchoolTimetablePresentation(item: movedPolish, news: entries, now: now).changeDescriptions ==
            ["Godzina 09:00–09:45 → 08:00–08:45"])
    }

    static func differentSubjectInSameSlotHasNoPreviousLesson() {
        let before = lesson()
        let after = lesson("index:0", title: "Polski", room: "24")
        let entries = changes([before], [after])
        assert(entries.count == 1 && entries[0].previousItem == nil,
               "A different subject replacing a removed lesson is not its previous version")
        assert(SchoolTimetablePresentation(item: after, news: entries, now: now).changeDescriptions == ["Zmiana planu"])
    }

    static func substituteTeacherKeepsUnambiguousSubject() {
        let before = lesson()
        var after = lesson("index:9", teacher: "Zastępujący nauczyciel", room: "24")
        after.value = "Zastępstwo"
        let entries = changes([before], [after])
        assert(entries.count == 1 && entries[0].previousItem == before,
               "An unambiguous same-subject substitution may change its teacher")
        let presentation = SchoolTimetablePresentation(item: after, news: entries, now: now)
        assert(presentation.statusLabel == "Zastępstwo" && presentation.changeDescriptions == ["Sala 12 → 24"])
    }

    static func ambiguousSequentialLessonsHaveNoPreviousLesson() {
        let old = [lesson("index:0", room: "12"), lesson("index:1", room: "14", time: "09:00–09:45")]
        let new = [lesson("index:0", room: "24"), lesson("index:1", room: "26", time: "09:00–09:45")]
        let entries = changes(old, new)
        assert(entries.count == 2 && entries.allSatisfy { $0.previousItem == nil },
               "Multiple changed lessons sharing subject and teacher make their previous rooms ambiguous")
        for entry in entries {
            assert(SchoolTimetablePresentation(item: entry.item, news: entries, now: now).changeDescriptions == ["Zmiana planu"])
        }
    }

    static func windowAndRecoveryRemainSafe() {
        let shared = lesson(date: "2026-11-03")
        let newWeek = lesson("index:2", date: "2026-11-10")
        let sunday = snapshot([shared], fetchedAt: "2026-11-01")
        let monday = snapshot([shared, newWeek], fetchedAt: "2026-11-02")
        let mondayNow = ISO8601DateFormatter().date(from: "2026-11-02T07:00:00Z")!
        assert(SchoolNews.planChanges(previous: sunday, fresh: monday, at: mondayNow).isEmpty)
        let first = snapshot([lesson()]).merging(previous: nil)
        var failed = snapshot([])
        failed.errors["timetable"] = "connection_error"
        let cached = failed.merging(previous: first)
        let entries = SchoolNews.planChanges(previous: cached, fresh: snapshot([lesson(room: "24")]), at: now)
        assert(entries.first?.previousItem == lesson(), "Partial failures must retain the successful baseline")
    }

    static func currentLessonUsesWarsawTimeAndBoundaries() {
        let item = lesson()
        let beginning = ISO8601DateFormatter().date(from: "2026-10-28T07:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2026-10-28T07:45:00Z")!
        assert(SchoolTimetablePresentation(item: item, news: [], now: beginning).timing == .current)
        assert(SchoolTimetablePresentation(item: item, news: [], now: end).timing == .finished,
               "A lesson ends at its end boundary; it cannot remain highlighted during a break")
        assert(SchoolTimetablePresentation(item: item, news: [], now: beginning.addingTimeInterval(-1)).timing == .upcoming)
        assert(SchoolTimetablePresentation(item: lesson(date: "2026-10-29"), news: [], now: now).timing == .upcoming)
        var canceled = item
        canceled.canceled = true
        assert(SchoolTimetablePresentation(item: canceled, news: [], now: now).timing != .current)
        let parallel = lesson("parallel", title: "Fizyka")
        assert(SchoolTimetablePresentation(item: parallel, news: [], now: now).timing == .current,
               "Every active parallel lesson is highlighted")
    }

    static func statusAndUnknownTimesRemainExplicit() {
        var replacement = lesson()
        replacement.value = "Zastępstwo"
        assert(SchoolTimetablePresentation(item: replacement, news: [], now: now).statusLabel == "Zastępstwo")
        replacement.canceled = true
        assert(SchoolTimetablePresentation(item: replacement, news: [], now: now).statusLabel == "Odwołana")
        replacement.canceled = false
        replacement.value = "Odwołana"
        let canceled = SchoolTimetablePresentation(item: replacement, news: [], now: now)
        assert(canceled.statusLabel == "Odwołana" && canceled.timing != .current)
        assert(SchoolTimetablePresentation(item: lesson(time: "brak"), news: [], now: now).timing == .unknown)
        assert(SchoolTimetablePresentation(item: lesson(time: "08:45–08:00"), news: [], now: now).timing == .unknown)
        assert(SchoolTimetablePresentation(item: lesson(), news: [], now: now).statusLabel == nil)
    }

    static func changesDescribeOnlyKnownValues() {
        let before = lesson()
        let after = lesson("index:9", room: "24", time: "09:00–09:45")
        let entry = SchoolNewsEntry(section: .timetable, key: "2026-10-28|09:00–09:45", item: after,
            detectedAt: now, kind: .changed, previousItem: before)
        let presentation = SchoolTimetablePresentation(item: after, news: [entry], now: now)
        assert(presentation.hasUnseenChange)
        assert(presentation.changeDescriptions == ["Sala 12 → 24", "Godzina 08:00–08:45 → 09:00–09:45"])
        var noRoom = before
        noRoom.subtitle = "Nauczyciel A"
        let unknownEntry = SchoolNewsEntry(section: .timetable, key: entry.key, item: after,
            detectedAt: now, kind: .changed, previousItem: noRoom)
        assert(SchoolTimetablePresentation(item: after, news: [unknownEntry], now: now).changeDescriptions ==
            ["Godzina 08:00–08:45 → 09:00–09:45"], "Missing room data must not invent an old room")
        let generic = SchoolNewsEntry(section: .timetable, key: entry.key, item: after,
            detectedAt: now, kind: .changed)
        assert(SchoolTimetablePresentation(item: after, news: [generic], now: now).changeDescriptions == ["Zmiana planu"])
    }

    static func parallelCardsDoNotBorrowAnotherLessonsRoom() {
        let before = lesson()
        let changed = lesson("index:9", room: "24")
        let parallel = lesson("index:8", title: "Fizyka", room: "33")
        let entries = changes([before, parallel], [changed, parallel])
        let presentation = SchoolTimetablePresentation(item: parallel, news: entries, now: now)
        assert(presentation.hasUnseenChange && presentation.changeDescriptions == ["Zmiana w tej godzinie"],
               "A slot-level alert on a different parallel lesson must stay generic")
        let ambiguous = changes([before, lesson("index:2", room: "14")],
                                [changed, lesson("index:3", room: "26")])
        assert(SchoolTimetablePresentation(item: ambiguous[0].item, news: ambiguous, now: now).changeDescriptions ==
            ["Zmiana planu"])
    }

    static func reviewAndWeekSelectionRemainCompatible() {
        let before = lesson()
        let changed = lesson("index:9", room: "24")
        let entries = changes([before], [changed])
        let reviewed = SchoolNews.reviewing(entries, section: .timetable, item: changed)
        let presentation = SchoolTimetablePresentation(item: changed, news: reviewed, now: now)
        assert(!presentation.hasUnseenChange && presentation.changeDescriptions.isEmpty)
        let nextWeek = lesson("next", date: "2026-11-02")
        let weekend = lesson("weekend", date: "2026-10-31")
        let items = [changed, nextWeek, weekend, lesson("parallel", title: "Fizyka")]
        let week = TimetableWeek(items: items, offset: 0, now: now, search: "Matematyka")
        assert(week.items.count == 2 && week.days.last?.date == "2026-10-31")
        assert(TimetableWeek(items: items, offset: 1, now: now).items.map(\.id) == ["next"])
    }

    static func previousLessonSurvivesCache() throws {
        let entries = changes([lesson()], [lesson(room: "24")])
        let restored = try JSONDecoder().decode([SchoolNewsEntry].self, from: JSONEncoder().encode(entries))
        assert(restored == entries && restored.first?.previousItem == lesson())
        let legacy = Data(#"{"section":"timetable","key":"2026-10-28|08:00–08:45","item":{"id":"old","title":"Matematyka","subtitle":"","body":"","date":"2026-10-28","time":"08:00–08:45","value":"","unread":false,"canceled":false,"mailbox":"inbox","attachments":[]},"detectedAt":0,"kind":"changed"}"#.utf8)
        let decoded = try JSONDecoder().decode(SchoolNewsEntry.self, from: legacy)
        assert(decoded.previousItem == nil)
    }
}
