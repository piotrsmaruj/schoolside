import SwiftUI

private enum SchoolOrganizerMode: String, CaseIterable, Identifiable {
    case tasks, week
    var id: String { rawValue }
    var title: String { self == .tasks ? "Do ogarnięcia" : "Najbliższe 7 dni" }
}

@MainActor
private final class SchoolOrganizerBrowser: ObservableObject {
    @Published var mode: SchoolOrganizerMode = .tasks
    @Published var showCompleted = false
    @Published var editingTask: SchoolTask?
    @Published var pendingSource: SchoolTask?
}

struct SchoolOrganizerView: View {
    @ObservedObject var model: SchoolViewModel
    @StateObject private var browser = SchoolOrganizerBrowser()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls.padding(.horizontal, 24)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if browser.mode == .tasks { taskList(now: context.date) }
                        else { week(now: context.date) }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }
        }.sheet(item: $browser.editingTask, onDismiss: openPendingSource) { task in
            SchoolTaskEditor(model: model, task: task, onOpenSource: task.source == nil ? nil : {
                browser.pendingSource = model.organizerTasks.first { $0.id == task.id } ?? task
                browser.editingTask = nil
            })
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Widok organizera", selection: $browser.mode) {
                    ForEach(SchoolOrganizerMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 380)
                Spacer()
                Button { browser.editingTask = SchoolTask(title: "") } label: {
                    Label("Nowe zadanie", systemImage: "plus")
                }.disabled(model.snapshot == nil)
            }
            HStack {
                Text("Do zrobienia: \(model.organizerTasks.filter { !$0.isCompleted }.count)")
                Spacer()
                Toggle("Pokaż zrobione", isOn: $browser.showCompleted).toggleStyle(.checkbox)
            }.font(.callout).foregroundStyle(SchoolPalette.secondaryText)
        }
    }

    @ViewBuilder
    private func taskList(now: Date) -> some View {
        let list = SchoolTaskList(model.organizerTasks, search: model.search, now: now, showCompleted: browser.showCompleted)
        if list.groups.isEmpty {
            ContentUnavailableView(model.search.isEmpty ? "Wszystko ogarnięte" : "Brak pasujących zadań",
                systemImage: "checkmark.circle", description: Text(model.search.isEmpty
                    ? "Zadania domowe pojawiają się automatycznie. Możesz też dodać własne zadanie lub utworzyć je z wiadomości."
                    : "Zmień tekst wyszukiwania lub pokaż zrobione zadania."))
                .frame(maxWidth: .infinity).padding(.top, 60)
        } else {
            ForEach(list.groups) { group in
                taskGroup(group.title, tasks: group.tasks, warning: group.kind == .overdue)
            }
        }
    }

    private func week(now: Date) -> some View {
        let overview = SchoolWeekOverview(tasks: model.organizerTasks, events: model.items(.agenda), now: now,
                                         showCompleted: browser.showCompleted, search: model.search)
        return Group {
            if !overview.overdue.isEmpty { taskGroup("Zaległe", tasks: overview.overdue, warning: true) }
            ForEach(overview.days) { day in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(dayTitle(day.date, now: now)).font(.headline)
                        Spacer()
                        Text("Zadania: \(day.pendingCount) · Wydarzenia: \(day.events.count)")
                            .font(.caption).foregroundStyle(SchoolPalette.secondaryText)
                    }
                    ForEach(day.events) { event in eventRow(event) }
                    ForEach(day.tasks) { task in taskRow(task, showDate: false) }
                    if day.tasks.isEmpty && day.events.isEmpty {
                        Text(model.search.isEmpty ? "Brak zaplanowanych spraw" : "Brak pasujących wpisów")
                            .font(.callout).foregroundStyle(SchoolPalette.secondaryText).padding(.vertical, 8)
                    }
                }
            }
            if !overview.undated.isEmpty { taskGroup("Bez terminu", tasks: overview.undated) }
        }
    }

    private func taskGroup(_ title: String, tasks: [SchoolTask], warning: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline).foregroundStyle(warning ? SchoolPalette.warning : SchoolPalette.primaryText)
                Text("\(tasks.count)").font(.caption).foregroundStyle(SchoolPalette.secondaryText)
            }
            ForEach(tasks) { task in taskRow(task) }
        }
    }

    private func taskRow(_ task: SchoolTask, showDate: Bool = true) -> some View {
        SchoolOrganizerTaskRow(task: task, showDate: showDate,
            toggle: { model.completeTask(task.id, completed: !task.isCompleted) },
            edit: { browser.editingTask = task })
    }

    private func eventRow(_ item: SchoolItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar").foregroundStyle(SchoolPalette.accent).padding(.top, 3)
            Button { model.openItem(item, in: .agenda) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).fontWeight(.medium)
                    if !item.body.isEmpty { Text(item.body).font(.callout).lineLimit(3) }
                    if !item.time.isEmpty { Text(item.time).font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            Button("Zaplanuj przygotowanie") { browser.editingTask = model.task(for: item, in: .agenda) }
                .controlSize(.small)
        }.padding(14).background(SchoolPalette.raised, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dayTitle(_ day: String, now: Date) -> String {
        guard let date = SchoolDates.parseDay(day) else { return day }
        let weekday = SchoolDates.formatted(date, "EEEE, d MMM")
        return day == SchoolDates.dayKey(now) ? "Dzisiaj · \(weekday)" : weekday.prefix(1).uppercased() + weekday.dropFirst()
    }

    private func openPendingSource() {
        guard let task = browser.pendingSource else { return }
        browser.pendingSource = nil
        model.openTaskSource(task)
    }
}

private struct SchoolOrganizerTaskRow: View {
    @EnvironmentObject private var appearance: SchoolAppearance
    let task: SchoolTask
    let showDate: Bool
    let toggle: () -> Void
    let edit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(task.isCompleted ? SchoolPalette.success : SchoolPalette.secondaryText)
            }.buttonStyle(.plain)
                .accessibilityLabel("\(task.isCompleted ? "Przywróć zadanie" : "Oznacz jako zrobione"): \(task.title)")
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).fontWeight(.medium).strikethrough(task.isCompleted)
                    if !task.note.isEmpty {
                        Text(task.note).font(.callout).lineLimit(appearance.density.bodyLines)
                            .foregroundStyle(SchoolPalette.secondaryText)
                    }
                    metadata
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(SchoolPalette.secondaryText)
        }.padding(appearance.density.rowPadding)
            .background(SchoolPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var metadata: some View {
        HStack(spacing: 12) {
            if let source = task.source { Label(source.section.title, systemImage: source.section.icon) }
            else { Label("Własne zadanie", systemImage: "pencil") }
            if showDate, let due = task.dueDate { Text(SchoolDates.display(due)) }
            if let reminder = task.reminderAt, !task.isCompleted {
                Label(SchoolDates.formatted(reminder, "d MMM, HH:mm"), systemImage: "bell")
            }
        }.font(.caption).foregroundStyle(SchoolPalette.secondaryText)
    }
}
