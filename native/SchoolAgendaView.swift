import SwiftUI

@MainActor
private final class SchoolAgendaBrowser: ObservableObject {
    @Published var showPast = false
}

struct SchoolAgendaView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    @StateObject private var browser = SchoolAgendaBrowser()
    private static let statusRefreshInterval: TimeInterval = 60

    private var isSearching: Bool { !model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.statusRefreshInterval)) { context in
            let list = SchoolAgendaList(model.items(.agenda), search: model.search, now: context.date)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if list.groups.isEmpty { emptyResults }
                    ForEach(list.groups) { group in
                        if group.kind == .past {
                            DisclosureGroup(isExpanded: Binding(get: { browser.showPast || isSearching }, set: { browser.showPast = $0 })) {
                                rows(group).padding(.top, 10)
                            } label: { heading(group) }
                                .tint(SchoolPalette.accent)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                heading(group)
                                rows(group)
                            }
                        }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }

    private var emptyResults: some View {
        ContentUnavailableView(isSearching ? "Brak pasujących wydarzeń" : "Brak wydarzeń",
            systemImage: SchoolSection.agenda.icon,
            description: Text(isSearching ? "Zmień tekst wyszukiwania."
                : model.busy ? "Dane są pobierane…" : "Wydarzenia pojawią się po synchronizacji."))
            .frame(maxWidth: .infinity).padding(.top, 60)
    }

    private func heading(_ group: SchoolAgendaGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.title).schoolFont(.headline)
                .foregroundStyle(group.kind == .past ? SchoolPalette.secondaryText : SchoolPalette.primaryText)
            Text("\(group.items.count)").schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(SchoolPalette.raised, in: Capsule())
        }
    }

    private func rows(_ group: SchoolAgendaGroup) -> some View {
        LazyVStack(spacing: appearance.density.rowSpacing) {
            ForEach(group.items) { item in
                SchoolRecordRow(item: item, showDate: true, isPast: group.kind == .past,
                    isNew: model.news.contains { $0.section == .agenda && $0.key == SchoolNews.key(item, in: .agenda) }) {
                    model.openItem(item, in: .agenda)
                }
            }
        }
    }
}
