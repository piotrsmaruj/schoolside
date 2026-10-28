import Foundation

protocol SchoolBackendRunning: Sendable {
    func run(_ request: SchoolRequest) async throws -> SchoolResponse
}

actor SchoolBackend: SchoolBackendRunning {
    private let root: URL
    init(root: URL) { self.root = root }

    func run(_ request: SchoolRequest) async throws -> SchoolResponse {
        let child = Process()
        let interpreter = root.appending(path: ".venv/bin/python")
        child.executableURL = interpreter
        child.arguments = ["-E", "-s", root.appending(path: "src/run_school.py").path]
        child.currentDirectoryURL = root
        child.environment = ["PATH": "/usr/bin:/bin", "LANG": "pl_PL.UTF-8"]
        let input = Pipe(), output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        guard FileManager.default.isExecutableFile(atPath: interpreter.path)
        else { throw DesktopError.runtime }
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(200)) } catch { return }
            if child.isRunning { child.terminate() }
        }
        defer { watchdog.cancel() }
        return try await withTaskCancellationHandler {
            try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(request))
            try input.fileHandleForWriting.close()
            return try await readResponse(child, output.fileHandleForReading)
        } onCancel: {
            if child.isRunning { child.terminate() }
        }
    }

    private func readResponse(_ child: Process, _ output: FileHandle) async throws -> SchoolResponse {
        let data = await Task.detached(priority: .userInitiated) {
            let data = output.readDataToEndOfFile()
            child.waitUntilExit()
            return data
        }.value
        try Task.checkCancellation()
        guard child.terminationStatus == 0 || child.terminationStatus == 1
        else { throw DesktopError.transport }
        let response: SchoolResponse
        do { response = try JSONDecoder().decode(SchoolResponse.self, from: data) }
        catch { throw DesktopError.transport }
        guard response.ok else { throw DesktopError.remote(response.errorCode ?? "internal_error") }
        return response
    }
}
