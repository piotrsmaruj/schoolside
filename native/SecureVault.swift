import CryptoKit
import Foundation
import Security

@MainActor
protocol SecretStore {
    func read(_ key: String) throws -> Data?
    func write(_ key: String, data: Data) throws
    func delete(_ key: String) throws
}

@MainActor
final class KeychainSecrets: SecretStore {
    private let service: String
    init(service: String) { self.service = service }

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: key]
    }

    func read(_ key: String) throws -> Data? {
        var lookup = query(key)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DesktopError.keychain(status) }
        return result as? Data
    }

    func write(_ key: String, data: Data) throws {
        let status = SecItemUpdate(query(key) as CFDictionary,
                                  [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(key)
            item[kSecValueData as String] = data
            let inserted = SecItemAdd(item as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw DesktopError.keychain(inserted) }
        } else if status != errSecSuccess { throw DesktopError.keychain(status) }
    }

    func delete(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound
        else { throw DesktopError.keychain(status) }
    }
}

@MainActor
final class SecureVault {
    private let secrets: any SecretStore
    private let cacheURL: URL
    private let accountKey = "parent-account"
    private let sessionKey = "librus-session"
    private let encryptionKey = "offline-cache-key"

    init(secrets: any SecretStore, cacheURL: URL) {
        self.secrets = secrets
        self.cacheURL = cacheURL
    }

    func saveAccount(_ account: LoginInput) throws {
        try secrets.write(accountKey, data: JSONEncoder().encode(account))
    }
    func loadAccount() throws -> LoginInput? {
        guard let data = try secrets.read(accountKey) else { return nil }
        return try JSONDecoder().decode(LoginInput.self, from: data)
    }
    func saveSession(_ session: SavedSession) throws {
        try secrets.write(sessionKey, data: JSONEncoder().encode(session))
    }
    func loadSession() throws -> SavedSession? {
        guard let data = try secrets.read(sessionKey) else { return nil }
        return try JSONDecoder().decode(SavedSession.self, from: data)
    }

    private func cacheKey(create: Bool) throws -> SymmetricKey? {
        if let data = try secrets.read(encryptionKey) { return SymmetricKey(data: data) }
        guard create else { return nil }
        let key = SymmetricKey(size: .bits256)
        try secrets.write(encryptionKey, data: key.withUnsafeBytes { Data($0) })
        return key
    }

    func saveSnapshot(_ snapshot: SchoolSnapshot) throws {
        guard let key = try cacheKey(create: true) else { throw DesktopError.cache }
        let encrypted = try AES.GCM.seal(JSONEncoder().encode(snapshot), using: key)
        guard let data = encrypted.combined else { throw DesktopError.cache }
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }

    func loadSnapshot() throws -> SchoolSnapshot? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }
        guard let key = try cacheKey(create: false) else { throw DesktopError.cache }
        do {
            let box = try AES.GCM.SealedBox(combined: Data(contentsOf: cacheURL))
            return try JSONDecoder().decode(SchoolSnapshot.self, from: AES.GCM.open(box, using: key))
        } catch { throw DesktopError.cache }
    }

    func clear() throws {
        var firstError: Error?
        for key in [accountKey, sessionKey, encryptionKey] {
            do { try secrets.delete(key) } catch { if firstError == nil { firstError = error } }
        }
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            do { try FileManager.default.removeItem(at: cacheURL) }
            catch { if firstError == nil { firstError = error } }
        }
        if let firstError { throw firstError }
    }
}
