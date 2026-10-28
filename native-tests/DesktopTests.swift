import Foundation

@MainActor
final class MemorySecrets: SecretStore {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ key: String, data: Data) throws { values[key] = data }
    func delete(_ key: String) throws { values[key] = nil }
}

@main
@MainActor
struct DesktopTests {
    static func main() throws {
        let old = SchoolSnapshot(studentName: "Synthetic private name", fetchedAt: "2026-10-28",
                                 sections: ["grades": [SchoolItem(id: "p:1", title: "Matematyka",
                                                                  value: "83,3%")]])
        let failed = SchoolSnapshot(studentName: "Synthetic private name", fetchedAt: "2026-10-29",
                                    sections: ["grades": []], errors: ["grades": "connection_error"])
        let merged = failed.merging(previous: old)
        assert(merged.sections["grades"]?.first?.value == "83,3%")
        assert(merged.errors["grades"] == "connection_error")
        assert(SchoolChanges.between(old: nil, new: old).isEmpty)
        assert(SchoolChanges.between(old: old, new: merged).isEmpty)
        let initiallyFailed = SchoolSnapshot(studentName: "Uczeń", fetchedAt: "2026-10-27",
                                             sections: ["grades": []], errors: ["grades": "connection_error"])
        assert(SchoolChanges.between(old: initiallyFailed, new: old).isEmpty)
        let planBefore = SchoolSnapshot(studentName: "Uczeń", fetchedAt: "2026-10-27",
            sections: ["timetable": [SchoolItem(id: "1", title: "Matematyka", date: "2026-10-29")]])
        let planAfter = SchoolSnapshot(studentName: "Uczeń", fetchedAt: "2026-10-28",
            sections: ["timetable": [SchoolItem(id: "1", title: "Matematyka", date: "2026-10-29", canceled: true)]])
        let fixedNow = ISO8601DateFormatter().date(from: "2026-10-28T10:00:00Z")!
        assert(SchoolChanges.between(old: planBefore, new: planAfter, at: fixedNow).count == 1)

        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let secrets = MemorySecrets()
        let cache = directory.appending(path: "snapshot.enc")
        let vault = SecureVault(secrets: secrets, cacheURL: cache)
        try vault.saveAccount(LoginInput(login: "1234567", password: "synthetic-password"))
        try vault.saveSnapshot(old)
        let account = try vault.loadAccount()
        let restored = try vault.loadSnapshot()
        assert(account?.password == "synthetic-password")
        assert(restored?.studentName == "Synthetic private name")
        var bytes = try Data(contentsOf: cache)
        assert(!String(decoding: bytes, as: UTF8.self).contains("Synthetic private name"))
        let mode = try FileManager.default.attributesOfItem(atPath: cache.path)[.posixPermissions] as? Int
        assert(mode == 0o600)
        bytes[bytes.count - 1] ^= 1
        try bytes.write(to: cache)
        do {
            _ = try vault.loadSnapshot()
            fatalError("Tampered cache accepted")
        } catch { }
        try vault.clear()
        assert(secrets.values.isEmpty)
        assert(!FileManager.default.fileExists(atPath: cache.path))
        print("Swift desktop: failed-section cache, notification baseline, encryption and logout passed")
    }
}
