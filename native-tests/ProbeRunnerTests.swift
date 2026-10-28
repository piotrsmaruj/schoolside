import Foundation

@main
@MainActor
struct ProbeRunnerTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let python = CommandLine.arguments[1]
        try FileManager.default.createDirectory(
            at: root.appending(path: ".venv/bin"), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appending(path: "src"), withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: ".venv/bin/python").path, withDestinationPath: python
        )
        let script = #"""
        import json, os, sys, time
        data = json.load(sys.stdin)
        assert len(sys.argv) == 1
        assert data["login"] == "1234567"
        assert data["password"] == " żółć '$`\\\n🙂 "
        assert data["password"] not in os.environ.values()
        print(json.dumps({"protocol_version": 1, "authenticated": True,
                          "session_reused": True, "modules": []}))
        """#
        try script.write(to: root.appending(path: "src/run_probe.py"),
                         atomically: true, encoding: .utf8)
        let runner = ProbeRunner(projectDirectory: root, processTimeout: .seconds(3))
        runner.start(login: " 1234567 ", password: " żółć '$`\\\n🙂 ")
        try await waitForCompletion(runner)
        assert(runner.report?.authenticated == true)
        assert(runner.errorMessage == nil)

        try "import time; time.sleep(5)".write(
            to: root.appending(path: "src/run_probe.py"), atomically: true, encoding: .utf8
        )
        runner.start(login: "1234567", password: "synthetic")
        assert(runner.running)
        runner.cancel()
        assert(!runner.running)
        assert(runner.report == nil)
        let cancellation = runner.errorMessage
        try await Task.sleep(for: .milliseconds(100))
        assert(runner.errorMessage == cancellation)

        let timed = ProbeRunner(projectDirectory: root, processTimeout: .milliseconds(100))
        timed.start(login: "1234567", password: "synthetic")
        try await waitForCompletion(timed)
        assert(timed.report == nil)
        assert(timed.errorMessage == ProbeCopy.error("timed_out"))
        print("Swift: private stdin transport, cancellation and timeout passed")
    }

    static func waitForCompletion(_ runner: ProbeRunner) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while runner.running && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        assert(!runner.running, "Child process did not complete")
    }
}
