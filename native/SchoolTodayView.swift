import SwiftUI

@MainActor
final class SchoolDaySelection: ObservableObject {
    @Published var offset = 0
}

struct SchoolTodayView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    @StateObject private var selection = SchoolDaySelection()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let day = SchoolDayOverview(snapshot: model.snapshot, offset: selection.offset, now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    dayPicker(day)
                    summary(day, now: context.date)
                    HStack(alignment: .top, spacing: 20) {
                        mainColumn(day, now: context.date).frame(maxWidth: .infinity)
                        sideColumn(day).frame(width: 292)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private func dayPicker(_ day: SchoolDayOverview) -> some View {
        HStack {
            Picker("Dzień", selection: $selection.offset) {
                Text("Dzisiaj").tag(0)
                Text("Jutro").tag(1)
            }.pickerStyle(.segmented).frame(width: 200)
            Spacer()
            Text(SchoolDates.display(day.dayKey)).schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText)
        }
    }

    private func summary(_ day: SchoolDayOverview, now: Date) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180 * appearance.textSize.scale), alignment: .top)], spacing: 10) {
            SchoolSummaryCard(title: selection.offset == 0 ? "Teraz" : "Lekcje jutro",
                value: selection.offset == 0 ? currentTitle(day)
                    : day.planState == .unavailable ? "Plan niedostępny" : "\(day.lessons.filter { !$0.canceled }.count)",
                detail: day.currentLesson?.time ?? (day.planState == .unavailable ? "Nie udało się pobrać planu"
                    : selection.offset == 0 ? "Według planu lekcji" : "Opublikowany plan"),
                symbol: "clock")
            SchoolSummaryCard(title: selection.offset == 0 ? "Następna lekcja" : "Pierwsza lekcja",
                value: day.nextLesson?.title ?? (day.planState == .available ? "Brak kolejnych lekcji" : "Plan niedostępny"),
                detail: day.nextLesson?.time ?? "", symbol: "arrow.right.circle")
            SchoolSummaryCard(title: "Koniec zajęć", value: day.endTime ?? "—",
                detail: day.planState == .unavailable ? "Plan niedostępny" : "Lekcje: \(day.lessons.filter { !$0.canceled }.count)", symbol: "flag.checkered")
            SchoolSummaryCard(title: "Najbliższe wydarzenie",
                value: day.events.first?.title ?? (day.agendaState == .available ? "Brak wydarzeń" : "Terminarz niedostępny"),
                detail: day.events.first.map {
                    [SchoolDates.relativeDay($0.date, now: now), $0.body].filter { !$0.isEmpty }.joined(separator: " · ")
                } ?? "W opublikowanym terminarzu",
                symbol: "calendar.badge.clock")
        }
    }

    private func currentTitle(_ day: SchoolDayOverview) -> String {
        if day.planState == .unavailable { return model.busy ? "Pobieram plan…" : "Plan niedostępny" }
        if let current = day.currentLesson { return current.title }
        if day.nextLesson != nil { return "Przerwa" }
        return day.lessons.isEmpty ? "Dzień bez lekcji" : "Lekcje zakończone"
    }

    private func mainColumn(_ day: SchoolDayOverview, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(selection.offset == 0 ? "Plan na dziś" : "Plan na jutro", symbol: "calendar")
                if day.lessons.isEmpty {
                    empty(day.planState == .available ? "Nie ma opublikowanych lekcji na ten dzień."
                        : "Nie udało się pobrać planu lekcji.")
                }
                ForEach(day.lessons) { item in
                    SchoolRecordRow(item: item) { model.openItem(item, in: .timetable) }
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(day.currentLesson?.id == item.id ? SchoolPalette.accent : .clear, lineWidth: 1.5))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("W najbliższym czasie", symbol: "calendar.badge.clock")
                if day.events.isEmpty {
                    empty(day.agendaState == .available ? "Brak nadchodzących wydarzeń." : "Nie udało się pobrać terminarza.")
                }
                ForEach(Array(day.events.prefix(5))) { item in
                    eventRow(item, now: now)
                }
            }
        }
    }

    private func sideColumn(_ day: SchoolDayOverview) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SchoolNewsPreview(model: model)
            SchoolPanel(title: "Zadania na jutro", symbol: "checklist") {
                if day.homework.isEmpty {
                    empty(day.homeworkState == .available ? "Brak zadań na jutro w Librusie." : "Nie udało się pobrać zadań.")
                }
                ForEach(Array(day.homework.prefix(3))) { item in
                    smallItem(item, in: .homework)
                }
                if day.homework.count > 3 { sectionLink("Wszystkie zadania", to: .homework) }
            }
            SchoolPanel(title: "Ostatnie oceny", symbol: "chart.bar") {
                if day.recentGrades.isEmpty {
                    empty(day.gradesState == .available ? "Nie ma jeszcze opublikowanych ocen." : "Nie udało się pobrać ocen.")
                }
                ForEach(Array(day.recentGrades.prefix(3))) { item in
                    smallItem(item, in: .grades)
                }
                if !day.recentGrades.isEmpty { sectionLink("Wszystkie oceny", to: .grades) }
            }
        }
    }

    private func eventRow(_ item: SchoolItem, now: Date) -> some View {
        Button { model.openItem(item, in: .agenda) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(SchoolDates.relativeDay(item.date, now: now)).schoolFont(.caption1).fontWeight(.semibold)
                    .foregroundStyle(SchoolPalette.accent).frame(width: 64, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).schoolFont(.callout).fontWeight(.semibold)
                    if !item.body.isEmpty { Text(item.body).schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText).lineLimit(2) }
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(SchoolPalette.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func smallItem(_ item: SchoolItem, in section: SchoolSection) -> some View {
        Button { model.openItem(item, in: section) } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).schoolFont(.callout).fontWeight(.medium)
                    Text(section == .grades ? item.subtitle : item.body).schoolFont(.caption1)
                        .foregroundStyle(SchoolPalette.secondaryText).lineLimit(2)
                }
                Spacer(minLength: 0)
                if !item.value.isEmpty { Text(item.value).schoolFont(.headline).foregroundStyle(SchoolPalette.accent) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func sectionLink(_ title: String, to section: SchoolSection) -> some View {
        Button(title) { model.selectedSection = section; model.search = "" }.schoolFont(.caption1).foregroundStyle(SchoolPalette.accent)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).schoolFont(.headline).padding(.bottom, 4)
    }

    private func empty(_ text: String) -> some View {
        Text(text).schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText).padding(.vertical, 6)
    }

}

struct SchoolSummaryCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText).lineLimit(1)
            Text(value).schoolFont(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            Text(detail.isEmpty ? " " : detail).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText).lineLimit(2)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
            .background(SchoolPalette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SchoolPalette.border))
    }
}

struct SchoolPanel<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).schoolFont(.headline)
            content
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(SchoolPalette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(SchoolPalette.border))
    }
}
