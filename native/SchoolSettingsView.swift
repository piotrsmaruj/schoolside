import SwiftUI

@MainActor
final class SchoolSettingsState: ObservableObject {
    @Published var confirmLogout = false
}

struct SchoolSettingsView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = SchoolSettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Ustawienia", systemImage: "gearshape").schoolFont(.title2).fontWeight(.semibold)
                Spacer()
                Button("Gotowe") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Form {
                appearanceSettings
                Section("Powiadomienia") {
                    SchoolNotificationControls(notifications: model.notifications)
                }
                accountSettings
                Section("O aplikacji") {
                    Text(AppIdentity.name).fontWeight(.semibold)
                    Text(AppIdentity.tagline)
                    Text(AppIdentity.affiliation).schoolFont(.caption1)
                }
            }.formStyle(.grouped)
        }.padding(24).frame(width: 560 * appearance.textSize.scale, height: 620)
            .confirmationDialog("Wylogować i usunąć lokalne dane?", isPresented: $state.confirmLogout) {
                Button("Wyloguj i usuń dane", role: .destructive) { model.logout(); dismiss() }
                Button("Anuluj", role: .cancel) { }
            } message: {
                Text("Hasło, sesja, dane Librusa i zadania organizera zostaną usunięte z tego Maca. Przypomnienia zostaną odwołane. Pobrane załączniki pozostaną.")
            }
    }

    private var appearanceSettings: some View {
        Section("Wygląd") {
            Picker("Motyw", selection: $appearance.theme) {
                ForEach(SchoolTheme.allCases) { Text($0.title).tag($0) }
            }
            Picker("Widok list", selection: $appearance.density) {
                ForEach(SchoolDensity.allCases) { Text($0.title).tag($0) }
            }
            Picker("Rozmiar tekstu", selection: $appearance.textSize) {
                ForEach(SchoolTextSize.allCases) { Text($0.title).tag($0) }
            }
            Text("Duży powiększa tekst, daty i opisy w całej aplikacji.")
                .schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            Text("Kompaktowy mieści więcej wpisów. Wygodny zostawia więcej odstępów.")
                .schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
        }
    }

    private var accountSettings: some View {
        Section("Konto i dane") {
            if let name = model.snapshot?.studentName { LabeledContent("Uczeń", value: name) }
            Text("Dane offline, oznaczenia nowości i organizer są szyfrowane na tym Macu.")
                .schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            Button("Wyloguj i usuń lokalne dane", role: .destructive) { state.confirmLogout = true }
        }
    }
}
