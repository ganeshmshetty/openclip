// SecretStore.swift
// OpenClip
//
// File-backed secrets storage (~/.openclip/secrets.json) with POSIX 0600 (owner-only)
// file permissions. Replaces macOS Keychain to avoid code-signing ACL prompts,
// build-signature mismatches, and user authorization dialogs.
import Foundation
import Core
import Security

public enum SecretStore {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var fileURL: URL = Constants.secretsFileURL
    private nonisolated(unsafe) static var _cache: [String: String]? = nil

    /// Overrides the file URL for testing (in-memory or temp file).
    public static func setFileURLForTesting(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        fileURL = url
        _cache = nil
    }

    /// Resets the store with specific contents for test isolation.
    public static func resetForTesting(with initialData: [String: String] = [:]) {
        lock.lock()
        defer { lock.unlock() }
        _cache = initialData
        saveToDiskLocked(initialData)
    }

    public static func get(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let store = loadCacheLocked()
        return store?[account]
    }

    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var store = loadCacheLocked() else { return false }
        store[account] = value
        guard saveToDiskLocked(store) else { return false }
        _cache = store
        return true
    }

    @discardableResult
    public static func delete(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var store = loadCacheLocked() else { return false }
        guard store.removeValue(forKey: account) != nil else { return true }
        guard saveToDiskLocked(store) else { return false }
        _cache = store
        return true
    }

    // MARK: - Private Disk Storage

    private static func loadCacheLocked() -> [String: String]? {
        if let cache = _cache {
            return cache
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
                    Log.settings.error("Secrets file at \(fileURL.path) is not a valid JSON dictionary of strings")
                    return nil
                }
                _cache = json
                return json
            } catch {
                Log.settings.error("Failed to read secrets file at \(fileURL.path): \(error.localizedDescription)")
                return nil
            }
        }

        var loaded: [String: String] = [:]
        // One-time legacy migration: check if legacy Keychain had aiCloudAPIKey
        if let migrated = readLegacyKeychainLocked() {
            loaded["aiCloudAPIKey"] = migrated
            if saveToDiskLocked(loaded) {
                deleteLegacyKeychainLocked()
            }
        }

        _cache = loaded
        return loaded
    }

    @discardableResult
    private static func saveToDiskLocked(_ data: [String: String]) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        do {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [FileAttributeKey.posixPermissions: 0o700]
                )
            }
        } catch {
            Log.settings.error("Failed to create secrets directory \(directory.path): \(error.localizedDescription)")
            return false
        }

        let tempFileURL = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer {
            if FileManager.default.fileExists(atPath: tempFileURL.path) {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
            guard FileManager.default.createFile(
                atPath: tempFileURL.path,
                contents: jsonData,
                attributes: [FileAttributeKey.posixPermissions: 0o600]
            ) else {
                Log.settings.error("Failed to create staged secrets file at \(tempFileURL.path)")
                return false
            }

            guard rename(tempFileURL.path, fileURL.path) == 0 else {
                let err = errno
                Log.settings.error("Failed to atomically install secrets file at \(fileURL.path): \(String(cString: strerror(err)))")
                return false
            }

            return true
        } catch {
            Log.settings.error("Failed to write secrets to \(fileURL.path): \(error.localizedDescription)")
            return false
        }
    }

    private static func legacyKeychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.openclip.app",
            kSecAttrAccount as String: "aiCloudAPIKey"
        ]
    }

    /// Best-effort one-time read of legacy Keychain credential without deleting it.
    private static func readLegacyKeychainLocked() -> String? {
        var query = legacyKeychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    /// Deletes legacy Keychain entry only after file persistence has succeeded.
    private static func deleteLegacyKeychainLocked() {
        SecItemDelete(legacyKeychainQuery() as CFDictionary)
    }
}
