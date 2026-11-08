import SwiftUI

struct SchoolNewsView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    private var filtered: [SchoolNewsEntry] {
        guard !model.search.isEmpty else { return model.news }
        return model.news.filter {
            [$0.section.title, $0.item.title, $0.item.body, $0.item.subtitle]
                .contains { $0.localizedCaseInsensitiveContains(model.search) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Nieprzejrzane wpisy: \(model.news.count)").schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText)
                Spacer()
                Button("Oznacz wszystkie jako przejrzane") { model.markAllNewsReviewed() }
                    .disabled(model.news.isEmpty)
            }.padding(.horizontal, 24)
            if filtered.isEmpty {
                ContentUnavailableView(model.search.isEmpty ? emptyTitle : "Brak wyników",
                    systemImage: model.search.isEmpty ? "checkmark.circle" : "magnifyingglass",
                    description: Text(model.search.isEmpty ? "Nowe wpisy i zmiany pojawią się po poprawnej synchronizacji."
                        : "Zmień tekst wyszukiwania."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { entries }
        }
    }

    private var emptyTitle: String {
        model.snapshot?.errors.isEmpty == false ? "Brak nowości w pobranych danych" : "Jesteś na bieżąco"
    }

    private var entries: some View {
        ScrollView {
            LazyVStack(spacing: appearance.density.rowSpacing) {
                ForEach(filtered) { entry in
                    SchoolNewsRow(entry: entry) { model.openNews(entry) }
                        .padding(appearance.density.rowPadding)
                        .background(SchoolPalette.surface, in: RoundedRectangle(cornerRadius: 12))
                        .disabled(model.busy && entry.section == .messages)
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
        }
    }
}

struct SchoolNewsPreview: View {
    @ObservedObject var model: SchoolViewModel
    var body: some View {
        SchoolPanel(title: "Co nowego · \(model.news.count)", symbol: "bell.badge") {
            if model.news.isEmpty {
                Label(model.snapshot?.errors.isEmpty == false ? "Niepełne dane" : "Jesteś na bieżąco",
                      systemImage: model.snapshot?.errors.isEmpty == false ? "exclamationmark.triangle" : "checkmark.circle")
                    .schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText)
                Text(model.snapshot?.errors.isEmpty == false ? "Nie udało się sprawdzić wszystkich modułów."
                     : "Nowe wpisy pozostaną tutaj do przejrzenia.").schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            }
            ForEach(Array(model.news.prefix(3))) { entry in
                SchoolNewsRow(entry: entry) { model.openNews(entry) }
                    .disabled(model.busy && entry.section == .messages)
            }
            if !model.news.isEmpty {
                Button("Przejrzyj nowości") { model.selectedSection = .news; model.search = "" }
                    .schoolFont(.caption1).foregroundStyle(SchoolPalette.accent)
            }
        }
    }
}

struct SchoolNewsRow: View {
    let entry: SchoolNewsEntry
    let action: () -> Void
    private var label: String {
        if entry.section == .timetable { return entry.kind == .removed ? "Lekcja usunięta" : "Zmiana planu" }
        return entry.section.title
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.section.icon).foregroundStyle(entry.section == .timetable ? SchoolPalette.warning : SchoolPalette.accent)
                    .frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
                    Text(entry.item.title).schoolFont(.callout).fontWeight(.semibold)
                    if !entry.item.value.isEmpty { Text(entry.item.value).schoolFont(.callout).foregroundStyle(SchoolPalette.accent) }
                    Text(detail).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").schoolFont(.caption2).foregroundStyle(SchoolPalette.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var detail: String {
        if entry.section == .timetable { return "\(SchoolDates.display(entry.item.date)) · \(entry.item.time)" }
        return entry.item.body.isEmpty ? entry.item.subtitle : entry.item.body
    }
}
