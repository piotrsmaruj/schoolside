import SwiftUI

@MainActor
final class TimetableSelection: ObservableObject {
    @Published var offset = 0
}

struct SchoolTimetableView: View {
    @ObservedObject var model: SchoolViewModel
    @StateObject private var selection = TimetableSelection()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            weekContent(now: context.date)
        }
    }

    private func weekContent(now: Date) -> some View {
        let week = TimetableWeek(items: model.items(.timetable), offset: selection.offset,
                                 now: now, search: model.search)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("Tydzień", selection: $selection.offset) {
                    Text("Bieżący tydzień").tag(0)
                    Text("Następny tydzień").tag(1)
                }.pickerStyle(.segmented).frame(maxWidth: 340)
                Spacer()
                Text(week.title).font(.callout).foregroundStyle(SchoolPalette.secondaryText)
            }.padding(.horizontal, 28)
            if week.items.isEmpty {
                ContentUnavailableView("Brak lekcji", systemImage: "calendar",
                    description: Text(model.search.isEmpty ? "Nie ma opublikowanych lekcji na ten tydzień."
                        : "Brak lekcji pasujących do wyszukiwania."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { timetable(week, now: now) }
        }
    }

    private func timetable(_ week: TimetableWeek, now: Date) -> some View {
        GeometryReader { geometry in
            let width = max(135, (geometry.size.width - 118 - CGFloat(week.days.count) * 8) / CGFloat(week.days.count))
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Godzina").font(.caption).foregroundStyle(SchoolPalette.secondaryText).frame(width: 62)
                        ForEach(week.days) { day in dayHeader(day, width: width, now: now) }
                    }
                    ScrollView(.vertical) { lessonRows(week: week, width: width, now: now) }
                }.padding(.horizontal, 28).frame(height: geometry.size.height)
            }
        }
    }

    private func lessonRows(week: TimetableWeek, width: CGFloat, now: Date) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(week.slots, id: \.self) { slot in
                GridRow(alignment: .top) {
                    Text(slot.isEmpty ? "Brak godziny" : slot.replacingOccurrences(of: "–", with: "\n"))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(SchoolPalette.secondaryText)
                        .frame(width: 62).padding(.top, 12).accessibilityLabel(slot)
                    ForEach(week.days) { day in
                        lessonCell(week.lessons(on: day.date, at: slot), width: width, now: now)
                    }
                }
            }
        }.padding(.bottom, 20)
    }

    private func dayHeader(_ day: TimetableDay, width: CGFloat, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.title).font(.callout).fontWeight(.semibold)
            Text(day.shortDate).font(.caption).foregroundStyle(SchoolPalette.secondaryText)
        }.frame(width: width, alignment: .leading).padding(.vertical, 10)
            .foregroundStyle(day.date == SchoolDates.dayKey(now) ? SchoolPalette.accent : SchoolPalette.primaryText)
    }

    private func lessonCell(_ lessons: [SchoolItem], width: CGFloat, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if lessons.isEmpty {
                RoundedRectangle(cornerRadius: 10).fill(SchoolPalette.raised)
                    .frame(height: 92).accessibilityLabel("Brak lekcji")
            }
            ForEach(lessons) { item in lessonCard(item, now: now) }
        }.frame(width: width, alignment: .topLeading)
    }

    private func lessonCard(_ item: SchoolItem, now: Date) -> some View {
        let presentation = SchoolTimetablePresentation(item: item, news: model.news, now: now)
        return Button { model.openItem(item, in: .timetable) } label: {
            VStack(alignment: .leading, spacing: 6) {
                lessonTiming(presentation)
                Text(item.title).font(.callout).fontWeight(.semibold).strikethrough(presentation.isCanceled)
                    .foregroundStyle(SchoolPalette.primaryText)
                Text(item.subtitle).font(.caption).foregroundStyle(SchoolPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                lessonChanges(presentation)
            }.padding(10).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .background(cardBackground(presentation), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(cardBorder(presentation), lineWidth: 1))
        }.buttonStyle(.plain).help("\(item.title) · \(item.subtitle)")
            .accessibilityElement(children: .combine)
            .accessibilityHint("\(SchoolDates.display(item.date)), \(item.time). Otwiera szczegóły i oznacza zmianę jako przejrzaną.")
    }

    @ViewBuilder
    private func lessonTiming(_ presentation: SchoolTimetablePresentation) -> some View {
        if presentation.timing == .current {
            Label("Teraz", systemImage: "clock.fill").font(.caption).fontWeight(.semibold)
                .foregroundStyle(SchoolPalette.accent)
        } else if presentation.timing == .finished {
            Text("Zakończona").font(.caption).foregroundStyle(SchoolPalette.secondaryText)
        }
        if let status = presentation.statusLabel {
            Text(status).font(.caption).fontWeight(.semibold).foregroundStyle(SchoolPalette.warning)
        }
    }

    @ViewBuilder
    private func lessonChanges(_ presentation: SchoolTimetablePresentation) -> some View {
        if presentation.hasUnseenChange {
            Label("Nowa zmiana", systemImage: "circle.fill").font(.caption).fontWeight(.semibold)
                .foregroundStyle(SchoolPalette.warning).accessibilityLabel("Nieprzejrzana zmiana planu")
            ForEach(presentation.changeDescriptions, id: \.self) { description in
                Text(description).font(.caption).foregroundStyle(SchoolPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cardBackground(_ presentation: SchoolTimetablePresentation) -> Color {
        if presentation.timing == .current { return SchoolPalette.selection }
        return presentation.hasUnseenChange || presentation.isCanceled ? SchoolPalette.warningSurface : SchoolPalette.surface
    }

    private func cardBorder(_ presentation: SchoolTimetablePresentation) -> Color {
        if presentation.timing == .current { return SchoolPalette.accent }
        return presentation.hasUnseenChange ? SchoolPalette.warning : SchoolPalette.border
    }
}
