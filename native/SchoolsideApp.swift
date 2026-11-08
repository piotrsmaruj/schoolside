import AppKit
import SwiftUI

@main
struct SchoolsideApp: App {
    @StateObject private var model = SchoolViewModel()
    @StateObject private var appearance = SchoolAppearance()
    init() { signal(SIGPIPE, SIG_IGN) }
    var body: some Scene {
        Window(AppIdentity.name, id: "main") {
            DesktopRootView(model: model)
                .schoolFont(.body)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.theme.colorScheme)
                .tint(SchoolPalette.accent)
                .accentColor(SchoolPalette.accent)
                .foregroundStyle(SchoolPalette.primaryText)
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(
                    for: NSWorkspace.didWakeNotification
                )) { _ in model.refreshIfStale() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification
                )) { _ in model.stop() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    model.refreshIfStale()
                    Task { await model.notifications.refresh() }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .defaultPosition(.center)
        MenuBarExtra {
            QuickSchoolView(model: model)
                .schoolFont(.body)
                .environmentObject(appearance)
                .preferredColorScheme(appearance.theme.colorScheme)
                .tint(SchoolPalette.accent)
                .foregroundStyle(SchoolPalette.primaryText)
        } label: {
            Image(systemName: "graduationcap")
            if model.unreadCount > 0 { Text("\(model.unreadCount)") }
        }.menuBarExtraStyle(.window)
    }
}

struct QuickSchoolView: View {
    @ObservedObject var model: SchoolViewModel
    @EnvironmentObject private var appearance: SchoolAppearance
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(AppIdentity.name, systemImage: "graduationcap.fill").schoolFont(.headline).foregroundStyle(SchoolPalette.accent)
            Text(AppIdentity.tagline).schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            Text(model.snapshot?.studentName ?? "Zaloguj się w aplikacji").foregroundStyle(SchoolPalette.secondaryText)
            Text("Nieprzeczytane wiadomości: \(model.unreadCount)")
            Text("Nieprzejrzane nowości: \(model.news.count)").schoolFont(.callout).foregroundStyle(SchoolPalette.secondaryText)
            if let next = model.nextRefreshAt {
                Text("Następne odświeżenie: \(next, style: .time)").schoolFont(.caption1).foregroundStyle(SchoolPalette.secondaryText)
            }
            ForEach(Array(model.items(.timetable).filter { $0.date == SchoolDates.today }.prefix(5))) { item in
                HStack { Text(item.time).foregroundStyle(SchoolPalette.secondaryText); Text(item.title).strikethrough(item.canceled) }
                    .schoolFont(.callout)
            }
            Divider()
            Button("Otwórz Schoolside") { openWindow(id: "main"); NSApp.activate() }
            Button("Odśwież dane") { model.refresh() }.disabled(model.busy || !model.signedIn)
            Button("Zakończ") { NSApp.terminate(nil) }
        }.padding(22).frame(width: 330 * appearance.textSize.scale)
    }
}
