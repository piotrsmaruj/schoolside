import AppKit
import SwiftUI

@main
struct ConnectionCheckApp: App {
    @StateObject private var runner = ProbeRunner()

    init() {
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        Window("Schoolside — test połączenia", id: "connection") {
            ConnectionView(runner: runner)
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.willTerminateNotification
                )) { _ in runner.cancel() }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

@MainActor
final class LoginForm: ObservableObject {
    @Published var login = ""
    @Published var password = ""
}

struct ConnectionView: View {
    @ObservedObject var runner: ProbeRunner
    @StateObject private var form = LoginForm()
    @FocusState private var focusedField: Field?

    enum Field { case login, password }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            loginForm
            if runner.running { progress }
            if let message = runner.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.callout)
            }
            if let report = runner.report { results(report) }
            Spacer(minLength: 0)
            Text("Dane logowania są używane tylko podczas tego testu i nie są zapisywane.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 650, height: runner.report == nil ? 420 : 770)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { focusedField = .login }
        .onDisappear { runner.cancel() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 30)).foregroundStyle(.teal)
                .frame(width: 64, height: 64)
                .background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 5) {
                Text("Schoolside — test połączenia").font(.title2).fontWeight(.semibold)
                Text(AppIdentity.tagline).font(.caption).foregroundStyle(.secondary)
                Text("Konto rodzica · jeden uczeń").foregroundStyle(.secondary)
            }
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Sprawdzimy dostęp do danych i ponowne użycie sesji.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text("Login rodzica").font(.callout).fontWeight(.medium)
                TextField("Numeryczny login otrzymany ze szkoły", text: $form.login)
                    .disabled(runner.running)
                    .focused($focusedField, equals: .login)
                    .onSubmit { focusedField = .password }
                    .accessibilityIdentifier("parentLogin")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Hasło").font(.callout).fontWeight(.medium)
                SecureField("Hasło do Synergii", text: $form.password)
                    .disabled(runner.running)
                    .focused($focusedField, equals: .password)
                    .onSubmit(start)
                    .accessibilityIdentifier("parentPassword")
            }
            HStack {
                Button("Sprawdź połączenie", action: start)
                    .buttonStyle(.borderedProminent).tint(.teal)
                    .keyboardShortcut(.defaultAction)
                    .disabled(runner.running || !LoginInput.isValid(
                        login: form.login, password: form.password
                    ))
                if runner.running { Button("Przerwij") { runner.cancel() } }
            }.padding(.top, 3)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var progress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Łączenie i sprawdzanie modułów…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func results(_ report: ProbeReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(resultTitle(report), systemImage: report.authenticated
                  ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.headline).foregroundStyle(report.authenticated ? .teal : .orange)
            if let code = report.errorCode {
                Text(ProbeCopy.error(code)).font(.callout).foregroundStyle(.secondary)
            }
            if let diagnostic = ProbeCopy.diagnostic(report.diagnosticCode) {
                Text(diagnostic).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(report.modules) { module in
                HStack {
                    Image(systemName: statusIcon(module.status))
                        .foregroundStyle(statusColor(module.status)).frame(width: 20)
                    Text(module.title)
                    Spacer()
                    Text(module.detail).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Divider()
            sessionResult(report)
        }
    }

    private func sessionResult(_ report: ProbeReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.sessionReused == true ? "Sesja działa bez ponownego logowania hasłem."
                 : "Ponowne użycie sesji nie zostało potwierdzone.")
                .font(.callout).fontWeight(.medium)
            if let code = report.sessionErrorCode {
                Text(ProbeCopy.error(code)).font(.caption).foregroundStyle(.secondary)
            }
            Text("Test nie otwiera wiadomości ani nie zmienia ich statusu przeczytania.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resultTitle(_ report: ProbeReport) -> String {
        if !report.authenticated { return "Nie udało się zalogować" }
        return report.hasIssues ? "Logowanie działa — część testów wymaga uwagi" : "Połączenie działa"
    }

    private func statusIcon(_ status: ModuleStatus) -> String {
        switch status {
        case .available, .empty: "checkmark.circle.fill"
        case .unavailable: "lock.circle"
        case .error: "exclamationmark.circle"
        case .notChecked: "minus.circle"
        }
    }

    private func statusColor(_ status: ModuleStatus) -> Color {
        switch status {
        case .available, .empty: .teal
        case .unavailable, .error: .orange
        case .notChecked: .secondary
        }
    }

    private func start() {
        guard LoginInput.isValid(login: form.login, password: form.password), !runner.running
        else { return }
        let secret = form.password
        form.password = ""
        runner.start(login: form.login, password: secret)
    }
}
