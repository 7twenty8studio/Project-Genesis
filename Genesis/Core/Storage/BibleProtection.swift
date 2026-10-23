import CryptoKit
import Foundation
import Security

/// Encryption for licensed Bible text kept on the device. Biblica's licence
/// asks for "industry standard encryption" against copying, and Lockman's
/// that taking a large part of a Bible out of the app be "difficult or
/// impractical" (LICENSED_BIBLES.md › 5). A YouVersion Platform Bible is
/// stored sealed with AES-256-GCM under a key made on this device and kept
/// in its Keychain (this device only, never synced or backed up), and is
/// opened into memory to read (`SQLiteDatabase(contents:)`), so the text is
/// never in a readable file. The files are also left out of backups; on
/// another device (or if the key is lost) they can't be opened and are
/// downloaded again.
enum BibleProtection {
    enum Failure: Error {
        case notSealed
        case keychain(OSStatus)
    }

    /// Marks a sealed file: "VBE" and the format.
    static let magic = Data("VBE1".utf8)

    static func seal(_ plain: Data, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key).combined else { throw Failure.notSealed }
        return magic + combined
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        guard isSealed(sealed) else { throw Failure.notSealed }
        let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(magic.count))
        return try AES.GCM.open(box, using: key)
    }

    static func isSealed(_ data: Data) -> Bool {
        data.count > magic.count && data.prefix(magic.count) == magic
    }

    /// Whether a file on disk is sealed (reads only its first bytes).
    static func isSealed(fileAt url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: magic.count)) == magic
    }

    /// Seals `plain` with this device's key and writes it, protected until
    /// the phone is first unlocked and left out of backups.
    static func write(_ plain: Data, to url: URL) throws {
        let sealed = try seal(plain, key: try deviceKey())
        try sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = url
        try? file.setResourceValues(values)
    }

    /// A file's contents, opened with this device's key if sealed.
    static func read(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        return isSealed(data) ? try open(data, key: try deviceKey()) : data
    }

    // MARK: The device's key

    private static let service = "com.7twenty8studio.versely.bible-protection"
    private static let account = "bibles"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedKey: SymmetricKey?

    /// This device's key, made the first time it's needed.
    static func deviceKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cachedKey { return cachedKey }
        if let stored = try storedKey() {
            cachedKey = stored
            return stored
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem, let stored = try storedKey() {
            cachedKey = stored
            return stored
        }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        cachedKey = key
        return key
    }

    private static func storedKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else { throw Failure.keychain(status) }
        return SymmetricKey(data: data)
    }
}
