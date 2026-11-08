import Foundation

enum SchoolOrganizerError: LocalizedError {
    case unavailable, invalidTask, pastReminder, automaticDeletion, missingTask
    var errorDescription: String? {
        switch self {
        case .unavailable: "Najpierw pobierz dane ucznia, aby korzystać z organizera."
        case .invalidTask: "Podaj tytuł i poprawny termin zadania."
        case .pastReminder: "Wybierz przyszłą datę przypomnienia."
        case .automaticDeletion: "Zadanie z Librusa możesz oznaczyć jako zrobione."
        case .missingTask: "Nie ma już tego zadania w organizerze."
        }
    }
}

extension SchoolViewModel {
    var organizerState: SchoolOrganizerState { snapshot?.organizer ?? SchoolOrganizerState() }
    var organizerTasks: [SchoolTask] { organizerState.tasks }

    func task(for item: SchoolItem, in section: SchoolSection) -> SchoolTask {
        SchoolOrganizer.task(for: item, in: section, state: organizerState)
    }

    @discardableResult
    func saveTask(_ edited: SchoolTask) -> Bool {
        var state = organizerState
        let index = state.tasks.firstIndex {
            $0.id == edited.id || (edited.source != nil && $0.source?.key == edited.source?.key)
        }
        let existing = index.map { state.tasks[$0] }
        var task = preparedTask(edited, existing: existing)
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard task.isValid else { errorMessage = SchoolOrganizerError.invalidTask.localizedDescription; return false }
        if let reminder = task.reminderAt, reminder <= now(), reminder != existing?.reminderAt {
            errorMessage = SchoolOrganizerError.pastReminder.localizedDescription
            return false
        }
        if let index { state.tasks[index] = task } else { state.tasks.append(task) }
        return saveOrganizerState(state)
    }

    private func preparedTask(_ edited: SchoolTask, existing: SchoolTask?) -> SchoolTask {
        guard let existing else { return edited }
        var task = edited
        task.id = existing.id
        task.completedAt = existing.completedAt
        task.source = existing.source
        if existing.isAutomatic {
            task.title = existing.title
            task.dueDate = existing.dueDate
        }
        return task
    }

    @discardableResult
    func completeTask(_ id: String, completed: Bool) -> Bool {
        var state = organizerState
        guard let index = state.tasks.firstIndex(where: { $0.id == id }) else {
            errorMessage = SchoolOrganizerError.missingTask.localizedDescription
            return false
        }
        state.tasks[index].completedAt = completed ? now() : nil
        return saveOrganizerState(state)
    }

    @discardableResult
    func deleteTask(_ id: String) -> Bool {
        guard let task = organizerTasks.first(where: { $0.id == id }) else { return false }
        guard !task.isAutomatic else {
            errorMessage = SchoolOrganizerError.automaticDeletion.localizedDescription
            return false
        }
        var state = organizerState
        state.tasks.removeAll { $0.id == id }
        return saveOrganizerState(state)
    }

    func openTaskSource(_ task: SchoolTask) {
        guard let source = task.source else { return }
        let current = items(source.section).first {
            SchoolTaskSource(section: source.section, item: $0).key == source.key
        }
        if let current, source.section != .messages || signedIn {
            openItem(current, in: source.section)
        } else {
            detailSection = source.section
            detailSourceArchived = true
            selectedItem = source.item
        }
    }
}
