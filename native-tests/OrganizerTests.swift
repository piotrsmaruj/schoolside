import Foundation

@main
struct OrganizerTests {
    static let now = ISO8601DateFormatter().date(from: "2026-10-24T10:00:00Z")!

    static func main() throws {
        automaticHomeworkSurvivesChanges()
        failuresAndMissingSourcesKeepTasks()
        sourceIdentityAndSearch()
        missingHomeworkDeadlineIsUndated()
        weekUsesCalendarDays()
        try oldSnapshotAndValidation()
        print("Swift organizer: automatic import, stable completion, failures, source identity, search and calendar days passed")
    }

    static func missingHomeworkDeadlineIsUndated() {
        let homework = SchoolItem(id: "undated", title: "Bez terminu", date: "2026-10-20")
        let state = SchoolOrganizer.reconcile(SchoolOrganizerState(), snapshot: snapshot([homework]))
        assert(state.tasks.first?.dueDate == nil, "The creation date must not become a homework deadline")
    }

    static func automaticHomeworkSurvivesChanges() {
        let item = SchoolItem(id: "h1", title: "Rozdział", body: "Ćwiczenia", date: "2026-10-25", homeworkDueDate: "2026-10-25")
        var state = SchoolOrganizer.reconcile(SchoolOrganizerState(), snapshot: snapshot([item]))
        assert(state.tasks.count == 1 && state.tasks[0].dueDate == "2026-10-25")
        assert(state.tasks[0].isAutomatic)
        state.tasks[0].completedAt = now
        state.tasks[0].note = "Własna notatka"
        var changed = item
        changed.title = "Nowy temat"
        changed.date = "2026-10-27"
        changed.homeworkDueDate = "2026-10-27"
        state = SchoolOrganizer.reconcile(state, snapshot: snapshot([changed, changed]))
        assert(state.tasks.count == 1)
        assert(state.tasks[0].title == "Nowy temat" && state.tasks[0].dueDate == "2026-10-27")
        assert(state.tasks[0].completedAt == now && state.tasks[0].note == "Własna notatka")
    }

    static func failuresAndMissingSourcesKeepTasks() {
        let item = SchoolItem(id: "h1", title: "Zadanie", date: "2026-10-25")
        let state = SchoolOrganizer.reconcile(SchoolOrganizerState(), snapshot: snapshot([item]))
        var failed = snapshot([])
        failed.errors["homework"] = "connection_error"
        assert(SchoolOrganizer.reconcile(state, snapshot: failed) == state)
        let missing = SchoolOrganizer.reconcile(state, snapshot: snapshot([]))
        assert(missing.tasks == state.tasks, "A missing source must not erase a personal obligation")
        assert(missing.tasks[0].source?.item.body == item.body)
    }

    static func sourceIdentityAndSearch() {
        let item = SchoolItem(id: "1", title: "Zgoda", body: "Wycieczka w góry", mailbox: "inbox")
        let first = SchoolOrganizer.task(for: item, in: .messages, state: SchoolOrganizerState())
        var state = SchoolOrganizerState(tasks: [first])
        let same = SchoolOrganizer.task(for: item, in: .messages, state: state)
        assert(same.id == first.id)
        let event = SchoolOrganizer.task(for: item, in: .agenda, state: state)
        assert(event.id != first.id)
        var sent = item
        sent.mailbox = "sent"
        assert(SchoolOrganizer.task(for: sent, in: .messages, state: state).id != first.id)
        state.tasks[0].note = "Podpisać wieczorem"
        assert(SchoolTaskList(state.tasks, search: "wieczorem", now: now).groups.flatMap(\.tasks).count == 1)
        assert(SchoolTaskList(state.tasks, search: "GÓRY", now: now).groups.flatMap(\.tasks).count == 1)
        assert(SchoolTaskList(state.tasks, search: "nie ma", now: now).groups.isEmpty)
    }

    static func weekUsesCalendarDays() {
        let tasks = [
            SchoolTask(id: "old", title: "Zaległe", dueDate: "2026-10-23"),
            SchoolTask(id: "today", title: "Dzisiaj", dueDate: "2026-10-24"),
            SchoolTask(id: "last", title: "Ostatni dzień", dueDate: "2026-10-30"),
            SchoolTask(id: "outside", title: "Po tygodniu", dueDate: "2026-10-31"),
            SchoolTask(id: "none", title: "Bez terminu"),
            SchoolTask(id: "bad", title: "Zła data", dueDate: "2026-02-31"),
            SchoolTask(id: "done", title: "Zrobione", dueDate: "2026-10-25", completedAt: now),
        ]
        let events = [SchoolItem(id: "e1", title: "Sprawdzian", date: "2026-10-25"),
                      SchoolItem(id: "canceled", title: "Odwołane", date: "2026-10-25", canceled: true)]
        let week = SchoolWeekOverview(tasks: tasks, events: events, now: now)
        assert(week.days.map(\.date) == ["2026-10-24", "2026-10-25", "2026-10-26", "2026-10-27",
                                        "2026-10-28", "2026-10-29", "2026-10-30"])
        assert(week.days[0].tasks.map(\.id) == ["today"])
        assert(week.days[1].events.map(\.id) == ["e1"] && week.days[1].tasks.isEmpty)
        assert(week.days[6].tasks.map(\.id) == ["last"])
        assert(week.overdue.map(\.id) == ["old"])
        assert(Set(week.undated.map(\.id)) == ["none", "bad"])
        let withDone = SchoolWeekOverview(tasks: tasks, events: events, now: now, showCompleted: true)
        assert(withDone.days[1].tasks.map(\.id) == ["done"])
        assert(SchoolWeekOverview(tasks: tasks, events: events, now: now, search: "Sprawdzian").days[1].events.count == 1)
    }

    static func oldSnapshotAndValidation() throws {
        let data = Data(#"{"student_name":"Synthetic","fetched_at":"2026-10-24","sections":{},"errors":{}}"#.utf8)
        let old = try JSONDecoder().decode(SchoolSnapshot.self, from: data)
        assert(old.organizer == nil)
        assert(!SchoolTask(id: "empty", title: "   ").isValid)
        assert(!SchoolTask(id: "date", title: "Zadanie", dueDate: "2026-02-31").isValid)
        assert(SchoolTask(id: "valid", title: "Zadanie").isValid)
    }

    static func snapshot(_ homework: [SchoolItem]) -> SchoolSnapshot {
        SchoolSnapshot(studentName: "Synthetic", fetchedAt: "2026-10-24", sections: ["homework": homework])
    }
}
