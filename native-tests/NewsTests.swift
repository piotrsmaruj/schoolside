import Foundation

@main
struct NewsTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-28T10:00:00Z")!

    static func main() throws {
        firstFetchAndPersistence()
        failuresAndRecovery()
        timetableChanges()
        recoveryKeepsBaseline()
        rollingTimetableWindow()
        notificationParity()
        try compatibility()
        print("Swift news: baseline, persistence, review, partial failure, slot changes and legacy cache passed")
    }

    static func snapshot(_ sections: [String: [SchoolItem]], errors: [String: String] = [:]) -> SchoolSnapshot {
        SchoolSnapshot(studentName: "Synthetic student", fetchedAt: "2026-10-28", sections: sections, errors: errors)
    }

    static func firstFetchAndPersistence() {
        let grade = SchoolItem(id: "g1", title: "Matematyka", value: "80%")
        let old = snapshot(["grades": []])
        var fresh = snapshot(["grades": [grade]])
        assert(SchoolNews.updated(previous: nil, fresh: fresh, at: now).isEmpty)
        fresh.news = SchoolNews.updated(previous: old, fresh: fresh, at: now)
        assert(fresh.news?.count == 1, "A newly added grade must appear in the feed")
        assert(fresh.news?.first?.section == .grades && fresh.news?.first?.item.value == "80%")
        let repeated = SchoolNews.updated(previous: fresh, fresh: fresh, at: now.addingTimeInterval(900))
        assert(repeated == fresh.news, "Polling must not clear or duplicate unseen news")
        var correctedGrade = grade
        correctedGrade.value = "90%"
        let corrected = snapshot(["grades": [correctedGrade]])
        assert(SchoolNews.updated(previous: fresh, fresh: corrected, at: now).first?.item.value == "90%",
               "An unseen entry must display the current corrected value")
        fresh.news = SchoolNews.reviewing(repeated, section: .grades, item: grade)
        assert(fresh.news?.isEmpty == true)
        assert(SchoolNews.updated(previous: fresh, fresh: fresh, at: now).isEmpty,
               "A reviewed grade must not reappear on the next poll")
    }

    static func failuresAndRecovery() {
        let grade = SchoolItem(id: "g1", title: "Matematyka")
        var old = snapshot(["grades": []])
        let fresh = snapshot(["grades": [grade]])
        old.errors["grades"] = "connection_error"
        assert(SchoolNews.updated(previous: old, fresh: fresh, at: now).isEmpty)
        assert(SchoolNews.updated(previous: snapshot([:]), fresh: fresh, at: now).isEmpty)
        var known = fresh
        known.news = SchoolNews.updated(previous: snapshot(["grades": []]), fresh: fresh, at: now)
        let failed = snapshot(["grades": []], errors: ["grades": "connection_error"])
        assert(SchoolNews.updated(previous: known, fresh: failed, at: now) == known.news,
               "A failed section must preserve its unseen entries")
    }

    static func timetableChanges() {
        let lesson = SchoolItem(id: "index:0", title: "Matematyka", date: "2026-10-29", time: "08:00–08:45")
        var changed = lesson
        changed.canceled = true
        let old = snapshot(["timetable": [lesson]])
        let fresh = snapshot(["timetable": [changed]])
        let news = SchoolNews.updated(previous: old, fresh: fresh, at: now)
        assert(news.count == 1 && news[0].section == .timetable && news[0].item.canceled)
        let renumbered = SchoolItem(id: "index:9", title: "Matematyka", date: lesson.date, time: lesson.time)
        assert(SchoolNews.updated(previous: old, fresh: snapshot(["timetable": [renumbered]]), at: now).isEmpty)
        let parallel = SchoolItem(id: "parallel", title: "Fizyka", date: lesson.date, time: lesson.time)
        let grouped = snapshot(["timetable": [lesson, parallel]])
        assert(SchoolNews.updated(previous: grouped, fresh: snapshot(["timetable": [parallel, lesson]]), at: now).isEmpty)
        assert(SchoolNews.updated(previous: old, fresh: snapshot(["timetable": []]), at: now).count == 1)
        let referenceFailure = snapshot(["timetable": [changed]], errors: ["references": "connection_error"])
        assert(SchoolNews.updated(previous: old, fresh: referenceFailure, at: now).isEmpty)
        let afterLesson = now.addingTimeInterval(3 * 24 * 60 * 60)
        assert(SchoolNews.updated(previous: old, fresh: fresh, at: afterLesson).isEmpty)
    }

    static func compatibility() throws {
        let legacy = Data(#"{"student_name":"Synthetic","fetched_at":"2026-10-28","sections":{},"errors":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(SchoolSnapshot.self, from: legacy)
        assert(decoded.news == nil)
        let old = snapshot(["messages": []])
        var fresh = snapshot(["messages": [SchoolItem(id: "m1", title: "Synthetic message", unread: true)]])
        fresh.news = SchoolNews.updated(previous: old, fresh: fresh, at: now)
        let restored = try JSONDecoder().decode(SchoolSnapshot.self, from: JSONEncoder().encode(fresh))
        assert(restored.news == fresh.news && restored.news?.count == 1)
    }

    static func recoveryKeepsBaseline() {
        let first = snapshot(["grades": [], "timetable": []]).merging(previous: nil)
        let failed = snapshot(["grades": [], "timetable": []],
            errors: ["grades": "connection_error", "timetable": "connection_error"]).merging(previous: first)
        let recovered = snapshot([
            "grades": [SchoolItem(id: "new-after-failure", title: "Matematyka", value: "90%")],
            "timetable": [SchoolItem(id: "new-slot", title: "Matematyka", date: "2026-10-29", time: "09:00–09:45")],
        ])
        let entries = SchoolNews.updated(previous: failed, fresh: recovered, at: now)
        assert(Set(entries.map(\.section)) == [.grades, .timetable],
               "Recovery must compare against the last successful baseline, including an empty baseline")
    }

    static func rollingTimetableWindow() {
        let shared = SchoolItem(id: "same", title: "Polski", date: "2026-11-03", time: "09:00–09:45")
        let addedWeek = SchoolItem(id: "new-week", title: "Matematyka", date: "2026-11-10", time: "09:00–09:45")
        let sunday = SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-11-01",
                                    sections: ["timetable": [shared]])
        let monday = SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-11-02",
                                    sections: ["timetable": [shared, addedWeek]])
        let mondayNow = ISO8601DateFormatter().date(from: "2026-11-02T07:00:00Z")!
        assert(SchoolNews.updated(previous: sunday, fresh: monday, at: mondayNow).isEmpty,
               "A newly fetched week must establish a baseline rather than create change alerts")
    }

    static func notificationParity() {
        let before = SchoolItem(id: "index:0", title: "Matematyka", date: "2026-10-29", time: "08:00–08:45")
        let after = SchoolItem(id: "index:9", title: "Matematyka", date: before.date, time: before.time)
        let old = snapshot(["timetable": [before]])
        let fresh = snapshot(["timetable": [after]])
        assert(SchoolChanges.between(old: old, new: fresh, at: now).isEmpty,
               "Notifications must ignore renumbering just like the news feed")
        var canceled = after
        canceled.canceled = true
        assert(SchoolChanges.between(old: old, new: snapshot(["timetable": [canceled]]), at: now).count == 1)
    }
}
