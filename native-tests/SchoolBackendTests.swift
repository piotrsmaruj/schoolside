import Foundation

@main
struct SchoolBackendTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appending(path: ".venv/bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(atPath: root.appending(path: ".venv/bin/python").path,
                                                 withDestinationPath: CommandLine.arguments[1])
        let script = #"""
        import json, os, sys
        request = json.load(sys.stdin)
        assert len(sys.argv) == 1
        assert request["password"] == "synthetic-🙂-'$`"
        assert request["password"] not in os.environ.values()
        print(json.dumps({"ok": True, "snapshot": {"student_name": "Uczeń", "fetched_at": "2026-10-28",
            "sections": {"grades": [{"id":"p:1", "title":"Matematyka", "subtitle":"", "body":"",
                "date":"", "time":"", "value":"83,3%", "unread":False, "canceled":False,
                "mailbox":"inbox", "attachments":[]}]}, "errors": {}}}))
        """#
        try script.write(to: root.appending(path: "src/run_school.py"), atomically: true, encoding: .utf8)
        let backend = SchoolBackend(root: root)
        let request = SchoolRequest(operation: "sync", login: "1234567", password: "synthetic-🙂-'$`")
        let response = try await backend.run(request)
        assert(response.snapshot?.sections["grades"]?.first?.value == "83,3%")
        try "import time; time.sleep(5)".write(to: root.appending(path: "src/run_school.py"),
                                              atomically: true, encoding: .utf8)
        let pending = Task { try await backend.run(request) }
        try await Task.sleep(for: .milliseconds(100))
        pending.cancel()
        do {
            _ = try await pending.value
            fatalError("Canceled request succeeded")
        } catch is CancellationError { }
        print("Swift desktop: process boundary, percent-grade decoding and cancellation passed")
    }
}
