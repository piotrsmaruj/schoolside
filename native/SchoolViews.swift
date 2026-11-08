import SwiftUI

@MainActor
final class DesktopLoginForm: ObservableObject {
    @Published var login = ""
    @Published var password = ""
}

struct DesktopRootView: View {
    @ObservedObject var model: SchoolViewModel
    var body: some View {
        Group {
            if model.signedIn || model.snapshot != nil { SchoolDashboard(model: model) }
            else { SchoolLoginView(model: model) }
        }
        .frame(minWidth: 1020, minHeight: 700)
        .task { model.bootstrap() }
        .sheet(isPresented: $model.showLogin) {
            VStack {
                SchoolLoginView(model: model)
                Button("Wróć do zapisanych danych") { model.showLogin = false }.padding(.bottom)
            }.frame(width: 600, height: 520)
        }
        .sheet(isPresented: $model.showSettings) {
            SchoolSettingsView(model: model)
        }
    }
}

struct SchoolLoginView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    @StateObject private var form = DesktopLoginForm()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "graduationcap.fill").font(.system(size: 44)).foregroundStyle(SchoolPalette.accent)
            Text(AppIdentity.name).schoolFont(.largeTitle).fontWeight(.semibold)
            Text(AppIdentity.tagline)
                .foregroundStyle(SchoolPalette.secondaryText)
            Text(AppIdentity.affiliation).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            VStack(alignment: .leading, spacing: 12) {
                TextField("Numeryczny login rodzica", text: $form.login)
                SecureField("Hasło do Synergii", text: $form.password).onSubmit(login)
            }.textFieldStyle(.roundedBorder).disabled(model.busy)
            Button(action: login) {
                HStack { if model.busy { ProgressView().controlSize(.small) }; Text("Połącz i zapamiętaj") }
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(SchoolPalette.accent).keyboardShortcut(.defaultAction)
            .disabled(model.busy || !LoginInput.isValid(login: form.login, password: form.password))
            if let error = model.errorMessage {
                Text(error).schoolFont(.callout).foregroundStyle(SchoolPalette.warning)
            }
            Text("Hasło i sesja zostaną zapisane w Pęku kluczy na tym Macu. Dane offline są szyfrowane.")
                .schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
        }.frame(maxWidth: 400 * appearance.textSize.scale).padding(40)
    }
    private func login() {
        guard LoginInput.isValid(login: form.login, password: form.password) else { return }
        let account = LoginInput(login: form.login, password: form.password)
        form.password = ""
        model.login(account)
    }
}

struct SchoolDashboard: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                heading
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .schoolFont(.callout).foregroundStyle(SchoolPalette.warning).padding(.horizontal, 28).padding(.bottom, 12)
                }
                if [.today, .news, .organizer].contains(model.selectedSection), !relevantFailures.isEmpty {
                    Label("Nie udało się odświeżyć: \(relevantFailures.map(\.title).joined(separator: ", ")). Dane mogą być nieaktualne.",
                          systemImage: "exclamationmark.triangle")
                        .schoolFont(.callout).foregroundStyle(SchoolPalette.warning).padding(.horizontal, 24).padding(.bottom, 12)
                } else if let code = model.snapshot?.errors[model.selectedSection.rawValue]
                    ?? (model.selectedSection == .timetable ? model.snapshot?.errors["references"] : nil) {
                    Text("Pokazuję ostatnie dostępne dane. \(ProbeCopy.error(code))")
                        .schoolFont(.caption1).foregroundStyle(SchoolPalette.warning).padding(.horizontal, 28)
                }
                if model.selectedSection == .today { SchoolTodayView(model: model) }
                else if model.selectedSection == .news { SchoolNewsView(model: model) }
                else if model.selectedSection == .organizer { SchoolOrganizerView(model: model) }
                else if model.selectedSection == .timetable { SchoolTimetableView(model: model) }
                else if model.selectedSection == .grades { SchoolGradesView(model: model) }
                else if model.selectedSection == .messages { SchoolMessagesView(model: model) }
                else if model.selectedSection == .agenda { SchoolAgendaView(model: model) }
                else { records }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $model.selectedItem) { item in SchoolDetailView(model: model, original: item) }
        .searchable(text: $model.search, prompt: "Szukaj w tej zakładce")
        .background(SchoolPalette.canvas)
    }

    private var relevantFailures: [SchoolSection] {
        let failures = SchoolDayOverview.failedSections(in: model.snapshot)
        return model.selectedSection == .organizer ? failures.filter { [.homework, .agenda].contains($0) } : failures
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppIdentity.name, systemImage: "graduationcap.fill")
                .schoolFont(.title2).fontWeight(.semibold).foregroundStyle(SchoolPalette.accent).padding(.bottom, 8)
            Text(AppIdentity.tagline).schoolFont(.caption2).foregroundStyle(SchoolPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
            ForEach(SchoolSection.allCases) { section in
                Button {
                    model.selectedItem = nil
                    model.detailSection = nil
                    model.selectedSection = section
                    model.search = ""
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.icon).frame(width: 20)
                        Text(section.title).fixedSize(horizontal: true, vertical: false)
                        Spacer()
                        let count = section == .messages ? model.unreadCount : section == .news ? model.news.count : 0
                        if count > 0 {
                            Text("\(count)").schoolFont(.caption1).fontWeight(.semibold)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(SchoolPalette.selection, in: Capsule())
                        }
                    }.schoolFont(.callout).padding(.horizontal, 12).padding(.vertical, 9)
                        .background(model.selectedSection == section ? SchoolPalette.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(model.selectedSection == section ? SchoolPalette.accent : SchoolPalette.primaryText)
                }.buttonStyle(.plain)
            }
            Spacer()
            Divider()
            Button { model.showSettings = true } label: {
                Label("Ustawienia", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }.buttonStyle(.plain).keyboardShortcut(",", modifiers: .command)
        }.padding(16).frame(width: 220 * appearance.textSize.scale).background(SchoolPalette.sidebar)
    }

    private var heading: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.selectedSection.title).schoolFont(.title1).fontWeight(.semibold)
                Text(model.snapshot?.studentName ?? "Uczeń").schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText)
            }
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
                Button("Przerwij") { model.cancel() }
            } else {
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Odśwież dane").disabled(!model.signedIn)
            }
            if !model.signedIn { Button("Zaloguj ponownie") { model.showLogin = true } }
        }.padding(.horizontal, 24).padding(.vertical, 20)
    }

    private var filtered: [SchoolItem] {
        let items = model.items(model.selectedSection)
        let ordered = model.selectedSection == .timetable || model.selectedSection == .agenda
            || model.selectedSection == .homework ? items.sorted { ($0.date, $0.time) < ($1.date, $1.time) }
            : items.sorted { $0.date > $1.date }
        guard !model.search.isEmpty else { return ordered }
        return ordered.filter { [$0.title, $0.subtitle, $0.body].contains {
            $0.localizedCaseInsensitiveContains(model.search)
        } }
    }

    private var records: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: appearance.density.rowSpacing) {
                if filtered.isEmpty {
                    ContentUnavailableView("Brak wpisów", systemImage: model.selectedSection.icon,
                        description: Text(model.busy ? "Dane są pobierane…" : "Nie ma tu jeszcze danych do wyświetlenia."))
                        .frame(maxWidth: .infinity).padding(.top, 80)
                }
                ForEach(filtered) { item in
                    SchoolRecordRow(item: item, showDate: true,
                        isNew: model.news.contains { $0.section == model.selectedSection && $0.key == SchoolNews.key(item, in: model.selectedSection) }) {
                        model.openItem(item, in: model.selectedSection)
                    }.disabled(model.busy && model.selectedSection == .messages)
                }
            }.padding(.horizontal, 24).padding(.bottom, 20)
        }
    }

    private var footer: some View {
        HStack {
            Circle().fill(model.errorMessage == nil && (model.snapshot?.errors.isEmpty ?? true) ? SchoolPalette.success : SchoolPalette.warning)
                .frame(width: 6, height: 6)
            Text(model.busy ? "Synchronizacja…" : "Ostatnia synchronizacja: \(SchoolDates.syncDisplay(model.snapshot?.fetchedAt ?? ""))")
            Spacer()
            if let next = model.nextRefreshAt, !model.busy {
                Text("Następne odświeżenie: \(next, style: .time)")
            }
        }.schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText).padding(16)
    }
}

struct SchoolNotificationControls: View {
    @ObservedObject var notifications: SchoolNotifications
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(notifications.enabled ? "Wyłącz powiadomienia" :
                notifications.needsSettings ? "Ustawienia powiadomień…" : "Włącz powiadomienia") {
                if notifications.enabled { notifications.disable() }
                else { Task { await notifications.enable() } }
            }.disabled(notifications.busy)
            if notifications.enabled {
                Button("Test powiadomienia") { Task { await notifications.sendTest() } }
            }
            if let message = notifications.message { Text(message).fixedSize(horizontal: false, vertical: true) }
        }.buttonStyle(.plain).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
    }
}

struct SchoolRecordRow: View {
    @EnvironmentObject private var appearance: SchoolAppearance
    let item: SchoolItem
    var showDate = false
    var isPast = false
    var isNew = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if !item.value.isEmpty {
                    Text(item.value).schoolFont(appearance.density == .compact ? .headline : .title3).fontWeight(.semibold)
                        .foregroundStyle(item.canceled ? SchoolPalette.secondaryText : SchoolPalette.accent)
                        .frame(minWidth: 58).padding(appearance.density.rowPadding)
                        .background(SchoolPalette.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                recordContent
                Spacer(minLength: 10)
                Image(systemName: "chevron.right").schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            }.padding(appearance.density.rowPadding).frame(maxWidth: .infinity, alignment: .leading)
                .background(isPast ? SchoolPalette.raised : SchoolPalette.surface,
                            in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private var recordContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if item.unread { Circle().fill(SchoolPalette.accent).frame(width: 6, height: 6) }
                Text(item.title).fontWeight(item.unread || isNew ? .semibold : .medium)
                    .foregroundStyle(isPast ? SchoolPalette.secondaryText : SchoolPalette.primaryText)
                    .strikethrough(item.canceled).fixedSize(horizontal: false, vertical: true)
            }
            if !item.subtitle.isEmpty { Text(item.subtitle).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText) }
            if !item.body.isEmpty {
                Text(item.body).lineLimit(appearance.density.bodyLines).schoolFont(.callout)
                    .foregroundStyle(isPast ? SchoolPalette.secondaryText : SchoolPalette.primaryText)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata }
                VStack(alignment: .leading, spacing: 6) { metadata }
            }.schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if showDate { Label(SchoolDates.display(item.date), systemImage: "calendar") }
        if !item.time.isEmpty { Text(item.time).monospacedDigit() }
        if isNew { Text("Nowe").foregroundStyle(SchoolPalette.accent) }
        if isPast { Text("Minione").fontWeight(.medium) }
    }
}

struct SchoolDetailView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    let original: SchoolItem
    private var item: SchoolItem { model.selectedItem ?? original }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title).schoolFont(.title2).fontWeight(.semibold)
                    Text(item.subtitle).foregroundStyle(SchoolPalette.secondaryText)
                    Text(SchoolDates.display(item.date)).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
                }
                Spacer()
                if !item.value.isEmpty { Text(item.value).schoolFont(.largeTitle).foregroundStyle(SchoolPalette.accent) }
                Button { model.selectedItem = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(SchoolPalette.secondaryText)
            }
            Divider()
            if model.detailSourceArchived {
                Label("Zapisana kopia źródła. Wpis nie jest dostępny w bieżących danych.", systemImage: "archivebox")
                    .schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            }
            if let section = model.detailSection, [.agenda, .homework].contains(section) {
                SchoolTaskAddButton(model: model, item: item, section: section)
            }
            if model.busy { ProgressView().controlSize(.small) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.body.isEmpty ? "Brak dodatkowego opisu." : item.body)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(6)
                    ForEach(SchoolLinks.urls(in: item.body), id: \.self) { url in
                        Link(destination: url) { Label(url.host ?? "Otwórz link", systemImage: "link") }
                    }
                }
            }
            ForEach(item.attachments) { attachment in
                Button { model.saveAttachment(attachment, of: item) } label: {
                    Label(attachment.name, systemImage: "arrow.down.doc")
                }.disabled(model.busy || !model.signedIn || model.detailSourceArchived)
            }
            if let error = model.errorMessage { Text(error).schoolFont(.caption1).foregroundStyle(SchoolPalette.warning) }
        }.padding(30).frame(width: 700 * appearance.textSize.scale, height: 560)
    }
}

enum SchoolLinks {
    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Array(Set(matches.compactMap(\.url).filter {
            ["https", "http", "mailto"].contains($0.scheme?.lowercased() ?? "")
        })).sorted { $0.absoluteString < $1.absoluteString }
    }
}
