import SwiftUI

@MainActor
private final class SchoolTaskEditorState: ObservableObject {
    @Published var draft: SchoolTask
    @Published var hasDueDate: Bool
    @Published var dueDate: Date
    @Published var hasReminder: Bool
    @Published var reminderAt: Date
    @Published var failure: String?
    @Published var confirmDelete = false

    init(task: SchoolTask, now: Date) {
        draft = task
        hasDueDate = task.dueDate != nil
        dueDate = task.dueDate.flatMap(SchoolDates.parseDay) ?? now
        hasReminder = task.reminderAt != nil
        reminderAt = task.reminderAt ?? SchoolDates.calendar.date(byAdding: .hour, value: 1, to: now) ?? now
    }
}

struct SchoolTaskEditor: View {
    @ObservedObject var model: SchoolViewModel
    @ObservedObject private var notifications: SchoolNotifications
    @Environment(\.dismiss) private var dismiss
    @StateObject private var form: SchoolTaskEditorState
    private let initial: SchoolTask
    private let onOpenSource: (() -> Void)?

    init(model: SchoolViewModel, task: SchoolTask, onOpenSource: (() -> Void)? = nil) {
        self.model = model
        notifications = model.notifications
        initial = task
        self.onOpenSource = onOpenSource
        _form = StateObject(wrappedValue: SchoolTaskEditorState(task: task, now: model.now()))
    }

    private var existing: SchoolTask? { model.organizerTasks.first { $0.id == initial.id } }
    private var current: SchoolTask { existing ?? initial }
    private var candidate: SchoolTask {
        var task = form.draft
        task.dueDate = task.isAutomatic ? current.dueDate : form.hasDueDate ? SchoolDates.dayKey(form.dueDate) : nil
        task.reminderAt = form.hasReminder ? form.reminderAt : nil
        return task
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "Nowe zadanie" : "Edytuj zadanie").font(.title2).fontWeight(.semibold)
            Form {
                taskFields
                reminderFields
                if let source = current.source { sourceFields(source) }
            }.formStyle(.grouped)
            if let failure = form.failure { Text(failure).font(.callout).foregroundStyle(SchoolPalette.warning) }
            actions
        }.padding(24).frame(width: 620, height: 650)
            .environment(\.locale, Locale(identifier: "pl_PL"))
            .environment(\.timeZone, SchoolDates.calendar.timeZone)
            .confirmationDialog("Usunąć to zadanie?", isPresented: $form.confirmDelete) {
                Button("Usuń zadanie", role: .destructive) {
                    if model.deleteTask(initial.id) { dismiss() } else { form.failure = model.errorMessage }
                }
                Button("Anuluj", role: .cancel) { }
            }
    }

    private var taskFields: some View {
        Section("Zadanie") {
            if form.draft.isAutomatic {
                LabeledContent("Tytuł", value: current.title)
                LabeledContent("Termin z Librusa", value: current.dueDate.map(SchoolDates.display) ?? "Bez terminu")
                Text("Tytuł i termin aktualizują się z Librusa. Twoja notatka i odhaczenie pozostają zapisane.")
                    .font(.caption).foregroundStyle(SchoolPalette.secondaryText)
            } else {
                TextField("Tytuł", text: $form.draft.title)
                Toggle("Termin zadania", isOn: $form.hasDueDate)
                if form.hasDueDate { DatePicker("Do kiedy", selection: $form.dueDate, displayedComponents: .date) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Twoja notatka").font(.caption).foregroundStyle(SchoolPalette.secondaryText)
                TextEditor(text: $form.draft.note).font(.body).frame(minHeight: 76)
                    .accessibilityLabel("Twoja notatka")
            }
        }
    }

    private var reminderFields: some View {
        Section("Przypomnienie") {
            Toggle("Przypomnij mi", isOn: $form.hasReminder)
            if form.hasReminder {
                DatePicker("Kiedy", selection: $form.reminderAt, displayedComponents: [.date, .hourAndMinute])
                if current.isCompleted {
                    Text("Zadanie jest zrobione — przypomnienie pozostaje wyłączone.")
                        .font(.caption).foregroundStyle(SchoolPalette.secondaryText)
                }
                if !notifications.enabled {
                    Text("Włącz powiadomienia Schoolside, aby otrzymywać przypomnienia.")
                        .font(.caption).foregroundStyle(SchoolPalette.warning)
                    SchoolNotificationControls(notifications: notifications)
                }
            }
        }
    }

    private func sourceFields(_ source: SchoolTaskSource) -> some View {
        Section("Źródło · \(source.section.title)") {
            Text(source.item.title).fontWeight(.medium)
            if !source.item.body.isEmpty {
                DisclosureGroup("Zapisany opis") { Text(source.item.body).textSelection(.enabled) }
            }
            if source.section == .agenda && !form.draft.isAutomatic {
                Text("Możesz ustawić wcześniejszy termin, aby zaplanować przygotowanie do wydarzenia.")
                    .font(.caption).foregroundStyle(SchoolPalette.secondaryText)
            }
            if let onOpenSource { Button("Pokaż źródło", action: onOpenSource) }
        }
    }

    private var actions: some View {
        HStack {
            if existing != nil && !form.draft.isAutomatic {
                Button("Usuń", role: .destructive) { form.confirmDelete = true }
            }
            Spacer()
            Button("Anuluj") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Zapisz") {
                if model.saveTask(candidate) { dismiss() } else { form.failure = model.errorMessage }
            }.buttonStyle(.borderedProminent).tint(SchoolPalette.accent)
                .keyboardShortcut(.defaultAction).disabled(!candidate.isValid)
        }
    }
}

@MainActor
private final class SchoolTaskSelection: ObservableObject {
    @Published var task: SchoolTask?
}

struct SchoolTaskAddButton: View {
    @ObservedObject var model: SchoolViewModel
    let item: SchoolItem
    let section: SchoolSection
    @StateObject private var selection = SchoolTaskSelection()

    private var exists: Bool {
        let key = SchoolTaskSource(section: section, item: item).key
        return model.organizerTasks.contains { $0.source?.key == key }
    }

    var body: some View {
        Button {
            selection.task = model.task(for: item, in: section)
        } label: {
            Label(exists ? "Otwórz zadanie w organizerze" : "Dodaj do ogarnięcia", systemImage: "checklist")
        }.disabled(model.snapshot == nil)
            .sheet(item: $selection.task) { task in SchoolTaskEditor(model: model, task: task) }
    }
}
