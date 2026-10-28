import AppKit
import Foundation

@MainActor
final class ProbeRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var report: ProbeReport?
    @Published private(set) var errorMessage: String?

    private var process: Process?
    private var generation = UUID()
    private var watchdog: Task<Void, Never>?
    private let maximumInputBytes = 64 * 1024
    private let processTimeout: Duration
    private let configuredRoot: URL?

    init(projectDirectory: URL? = nil, processTimeout: Duration = .seconds(200)) {
        self.configuredRoot = projectDirectory
        self.processTimeout = processTimeout
    }

    func start(login: String, password: String) {
        guard !running, LoginInput.isValid(login: login, password: password) else { return }
        report = nil
        errorMessage = nil
        do {
            let payload = try JSONEncoder().encode(LoginInput(login: login, password: password))
            guard payload.count <= maximumInputBytes else {
                errorMessage = ProbeCopy.error("invalid_input")
                return
            }
            try launch(payload: payload)
        } catch {
            cancel()
            errorMessage = "Nie udało się uruchomić testu. Sprawdź przygotowanie aplikacji w README."
            running = false
        }
    }

    private func launch(payload: Data) throws {
        let project = try projectDirectory()
        let child = Process()
        child.executableURL = project.appending(path: ".venv/bin/python")
        child.arguments = ["-E", "-s", project.appending(path: "src/run_probe.py").path]
        child.currentDirectoryURL = project
        child.environment = ["PATH": "/usr/bin:/bin", "LANG": "pl_PL.UTF-8"]
        let input = Pipe()
        let output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child
        running = true
        generation = UUID()
        let token = generation
        collectOutput(child: child, handle: output.fileHandleForReading, token: token)
        armWatchdog(token: token)
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()
    }

    private func projectDirectory() throws -> URL {
        if let configuredRoot { return configuredRoot }
        guard let path = Bundle.main.object(forInfoDictionaryKey: "ProbeProjectRoot") as? String else {
            throw CocoaError(.fileNoSuchFile)
        }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard FileManager.default.isExecutableFile(atPath: root.appending(path: ".venv/bin/python").path)
        else { throw CocoaError(.fileNoSuchFile) }
        return root
    }

    private func collectOutput(child: Process, handle: FileHandle, token: UUID) {
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                let data = handle.readDataToEndOfFile()
                child.waitUntilExit()
                return (data, child.terminationStatus)
            }.value
            guard let self, self.generation == token else { return }
            self.watchdog?.cancel()
            self.process = nil
            self.running = false
            guard result.1 == 0 || result.1 == 1 else {
                self.errorMessage = ProbeCopy.error("internal_error")
                return
            }
            do {
                self.report = try JSONDecoder().decode(ProbeReport.self, from: result.0)
            } catch {
                self.errorMessage = ProbeCopy.error("invalid_response")
            }
        }
    }

    private func armWatchdog(token: UUID) {
        watchdog = Task { [weak self, processTimeout] in
            do { try await Task.sleep(for: processTimeout) } catch { return }
            guard let self, self.generation == token, self.running else { return }
            self.cancel()
            self.errorMessage = ProbeCopy.error("timed_out")
        }
    }

    func cancel() {
        generation = UUID()
        watchdog?.cancel()
        stopProcess()
        if running { errorMessage = "Test przerwany." }
        running = false
    }

    private func stopProcess() {
        guard let child = process else { return }
        process = nil
        if child.isRunning { child.terminate() }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
}
