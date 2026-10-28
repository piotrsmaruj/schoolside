import SwiftUI

@MainActor
private final class SchoolGradeBrowser: ObservableObject {
    @Published var mode: SchoolGradeMode = .recent
    @Published var semester: SchoolGradeSemester = .all
    @Published var category: SchoolGradeCategory = .all
    @Published var expandedSubjects: Set<String> = []

    func toggle(_ subject: SchoolGradeSubject) {
        if expandedSubjects.contains(subject.id) { expandedSubjects.remove(subject.id) }
        else { expandedSubjects.insert(subject.id) }
    }
}

struct SchoolGradesView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    @StateObject private var browser = SchoolGradeBrowser()

    private var list: SchoolGradeList {
        SchoolGradeList(items: model.items(.grades), search: model.search,
                        semester: browser.semester, category: browser.category)
    }

    private var hasFilters: Bool {
        browser.semester != .all || browser.category != .all || !model.search.isEmpty
    }

    var body: some View {
        let grades = list
        VStack(alignment: .leading, spacing: 14) {
            controls(grades).padding(.horizontal, 24)
            if model.snapshot?.errors["grade_categories"] != nil {
                Label("Nie udało się pobrać rodzajów prac. Oceny są nadal dostępne.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(SchoolPalette.warning).padding(.horizontal, 24)
            }
            if grades.recent.isEmpty { emptyResults }
            else {
                ScrollView {
                    LazyVStack(spacing: appearance.density.rowSpacing) {
                        if browser.mode == .recent {
                            ForEach(grades.recent) { grade in row(grade) }
                        } else {
                            ForEach(grades.subjects) { subject in subjectGroup(subject) }
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 20)
                }
            }
        }.foregroundStyle(SchoolPalette.primaryText)
    }

    private func controls(_ grades: SchoolGradeList) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Widok ocen", selection: $browser.mode) {
                    ForEach(SchoolGradeMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented).frame(width: 260)
                Spacer()
                Text("Oceny: \(grades.recent.count)").font(.callout).foregroundStyle(SchoolPalette.secondaryText)
            }
            HStack(spacing: 14) {
                Picker("Semestr", selection: $browser.semester) {
                    Text("Wszystkie").tag(SchoolGradeSemester.all)
                    ForEach(grades.semesters, id: \.self) { semester in
                        Text("\(semester)").tag(SchoolGradeSemester.semester(semester))
                    }
                    if grades.hasUnknownSemester { Text("Brak semestru").tag(SchoolGradeSemester.unknown) }
                }.frame(maxWidth: 210)
                Picker("Rodzaj pracy", selection: $browser.category) {
                    Text("Wszystkie").tag(SchoolGradeCategory.all)
                    ForEach(grades.categories) { category in
                        Text(category.title).tag(SchoolGradeCategory.named(category.id))
                    }
                    if grades.hasUnknownCategory { Text("Brak rodzaju").tag(SchoolGradeCategory.unknown) }
                }.frame(maxWidth: 290)
                Spacer(minLength: 0)
                if hasFilters { Button("Wyczyść filtry", action: clearFilters).font(.caption) }
            }
        }.tint(SchoolPalette.accent)
    }

    private var emptyResults: some View {
        ContentUnavailableView(model.items(.grades).isEmpty ? "Brak ocen" : "Brak wyników",
            systemImage: "chart.bar",
            description: Text(model.items(.grades).isEmpty ? "Oceny pojawią się po poprawnej synchronizacji."
                : "Zmień wyszukiwanie, semestr lub rodzaj pracy."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ grade: SchoolItem) -> some View {
        SchoolRecordRow(item: grade, showDate: true) { model.openItem(grade, in: .grades) }
    }

    private func subjectGroup(_ subject: SchoolGradeSubject) -> some View {
        let expanded = browser.expandedSubjects.contains(subject.id)
        return VStack(alignment: .leading, spacing: appearance.density.rowSpacing) {
            Button { browser.toggle(subject) } label: {
                HStack(spacing: 12) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption).frame(width: 12).foregroundStyle(SchoolPalette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subject.title).font(.headline)
                        Text("Liczba ocen: \(subject.items.count)")
                            .font(.caption).foregroundStyle(SchoolPalette.secondaryText)
                    }
                    Spacer()
                    if let latest = subject.items.first {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(latest.value).font(.headline).foregroundStyle(SchoolPalette.accent)
                            Text(SchoolDates.display(latest.date)).font(.caption)
                                .foregroundStyle(SchoolPalette.secondaryText)
                        }
                    }
                }.padding(appearance.density.rowPadding).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("\(subject.title), liczba ocen: \(subject.items.count)")
                .accessibilityValue(expanded ? "Historia rozwinięta" : "Historia zwinięta")
                .accessibilityHint("Rozwiń lub zwiń historię ocen przedmiotu")
            if expanded {
                ForEach(subject.items) { grade in row(grade) }
                    .padding(.horizontal, appearance.density.rowPadding)
                    .padding(.bottom, appearance.density.rowPadding)
            }
        }.background(SchoolPalette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SchoolPalette.border))
    }

    private func clearFilters() {
        browser.semester = .all
        browser.category = .all
        model.search = ""
    }
}
