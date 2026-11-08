import SwiftUI

@MainActor
private final class SchoolMessageBrowser: ObservableObject {
    @Published var filter: SchoolMessageFilter = .all
}

struct SchoolMessagesView: View {
    @ObservedObject var model: SchoolViewModel
    @StateObject private var browser = SchoolMessageBrowser()
    @EnvironmentObject private var appearance: SchoolAppearance

    private var listing: SchoolMessageList {
        SchoolMessageList(model.items(.messages), filter: browser.filter,
                          search: model.search, selectedID: model.selectedMessage?.id)
    }

    var body: some View {
        HSplitView {
            messageList.frame(minWidth: 310, idealWidth: 350, maxWidth: 440)
            messageDetail.frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SchoolPalette.canvas)
        .tint(SchoolPalette.accent)
    }

    private var messageList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Filtr wiadomości", selection: $browser.filter) {
                ForEach(SchoolMessageFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }.pickerStyle(.segmented).controlSize(appearance.textSize == .large ? .regular : .small)
                .padding(.horizontal, 16).padding(.top, 12)
            Text("Wiadomości: \(listing.items.count)")
                .schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText).padding(.horizontal, 16)
            if listing.items.isEmpty {
                ContentUnavailableView("Brak wiadomości", systemImage: "envelope",
                    description: Text(model.search.isEmpty && browser.filter == .all
                        ? "Wiadomości pojawią się po synchronizacji."
                        : "Zmień filtr lub tekst wyszukiwania."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { messageRows }
        }.background(SchoolPalette.sidebar)
    }

    private var messageRows: some View {
        let current = listing
        return ScrollView {
            LazyVStack(spacing: appearance.density.rowSpacing) {
                ForEach(current.items) { item in
                    SchoolMessageRow(item: item, isSelected: current.selectedID == item.id) {
                        model.selectMessage(item)
                    }.disabled(model.busy && !model.messageLoading)
                }
            }.padding(.horizontal, 12).padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var messageDetail: some View {
        if let item = model.selectedMessage {
            VStack(alignment: .leading, spacing: 16) {
                detailHeading(item)
                if listing.selectedID == nil {
                    Label("Ta wiadomość jest poza bieżącym filtrem lub wynikami wyszukiwania.",
                          systemImage: "line.3.horizontal.decrease.circle")
                        .schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
                }
                Divider().overlay(SchoolPalette.border)
                if model.messageLoading {
                    loadingMessage
                } else if let error = model.messageError {
                    messageFailure(error, item: item)
                } else { fullMessage(item) }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(SchoolPalette.surface)
        } else {
            ContentUnavailableView("Wybierz wiadomość", systemImage: "envelope.open",
                description: Text("Kliknij wiadomość na liście, aby pobrać i przeczytać jej pełną treść."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SchoolPalette.surface)
        }
    }

    private func detailHeading(_ item: SchoolItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title).schoolFont(.title2).fontWeight(.semibold)
                .foregroundStyle(SchoolPalette.primaryText).textSelection(.enabled)
            if !item.subtitle.isEmpty {
                Label(item.subtitle, systemImage: "person")
                    .schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                Label(SchoolDates.display(item.date), systemImage: "calendar")
                if !item.time.isEmpty { Text(item.time) }
                if SchoolMessageList.hasAttachments(item) {
                    Label("Załączniki", systemImage: "paperclip")
                }
            }.schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
        }
    }

    private var loadingMessage: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Pobieram pełną treść wiadomości…")
                .schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageFailure(_ error: String, item: SchoolItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nie udało się otworzyć wiadomości", systemImage: "exclamationmark.triangle")
                .schoolFont(.headline).foregroundStyle(SchoolPalette.warning)
            Text(error).schoolFont(.callout).foregroundStyle(SchoolPalette.primaryText).textSelection(.enabled)
            Button("Spróbuj ponownie") { model.selectMessage(item) }
                .disabled(model.busy && !model.messageLoading)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(SchoolPalette.warningSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func fullMessage(_ item: SchoolItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SchoolTaskAddButton(model: model, item: item, section: .messages)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(item.body.isEmpty ? "Wiadomość nie zawiera tekstu." : item.body)
                        .foregroundStyle(SchoolPalette.primaryText).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).lineSpacing(6)
                    ForEach(SchoolLinks.urls(in: item.body), id: \.self) { url in
                        Link(destination: url) { Label(url.absoluteString, systemImage: "link") }
                            .foregroundStyle(SchoolPalette.accent).schoolFont(.callout)
                    }
                    if !item.attachments.isEmpty { attachments(item) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func attachments(_ item: SchoolItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Załączniki").schoolFont(.headline).foregroundStyle(SchoolPalette.primaryText)
            ForEach(item.attachments) { attachment in
                Button { model.saveAttachment(attachment, of: item) } label: {
                    Label(attachment.name, systemImage: "arrow.down.doc")
                }.disabled(model.busy)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(SchoolPalette.raised, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SchoolMessageRow: View {
    @EnvironmentObject private var appearance: SchoolAppearance
    let item: SchoolItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                metadata
                title
                if !item.body.isEmpty {
                    Text(item.body).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
                        .lineLimit(appearance.density.bodyLines)
                }
            }.padding(appearance.density.rowPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? SchoolPalette.selection : SchoolPalette.surface,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? SchoolPalette.accent : SchoolPalette.border, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var metadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.subtitle.isEmpty ? "Wiadomość" : item.subtitle)
                .lineLimit(1).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            Spacer(minLength: 4)
            Text(SchoolDates.display(item.date)).schoolFont(.caption2)
                .foregroundStyle(SchoolPalette.secondaryText)
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            if item.unread {
                Circle().fill(SchoolPalette.accent).frame(width: 6, height: 6)
                    .accessibilityLabel("Nieprzeczytana")
            }
            Text(item.title).schoolFont(.callout).fontWeight(item.unread ? .semibold : .medium)
                .foregroundStyle(SchoolPalette.primaryText).lineLimit(2)
            Spacer(minLength: 0)
            if SchoolMessageList.hasAttachments(item) {
                Image(systemName: "paperclip").foregroundStyle(SchoolPalette.secondaryText)
                    .accessibilityLabel("Z załącznikami")
            }
        }
    }
}
