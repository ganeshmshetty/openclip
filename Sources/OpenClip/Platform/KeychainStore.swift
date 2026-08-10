// KeychainStore.swift
// OpenClip
//
// Generic-password Keychain wrapper for storing sensitive user credentials (e.g. cloud AI API keys)
// outside of UserDefaults. Uses kSecClassGenericPassword keyed by service + account.
import Foundation
import Security

enum KeychainStore {
    private static let defaultService = "com.openclip.app"
    private static let isRunningInTest: Bool = {
        NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }()
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _inMemoryStore: [String: String] = [:]

    static func get(account: String, service: String = defaultService) -> String? {
        if isRunningInTest {
            lock.lock()
            defer { lock.unlock() }
            return _inMemoryStore["\(service).\(account)"]
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, account: String, service: String = defaultService) -> Bool {
        if isRunningInTest {
            lock.lock()
            _inMemoryStore["\(service).\(account)"] = value
            lock.unlock()
            return true
        }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        // SecItemUpdate cannot retarget kSecAttrAccessible of an existing item; it fails with
        // errSecParam (accessibility migration) — replace it, restoring the prior credential if the
        // replacement fails so the old value is never lost to a delete-before-successful-replace.
        guard updateStatus == errSecParam else { return false }
        let previous = get(account: account, service: service)
        guard SecItemDelete(query as CFDictionary) == errSecSuccess else { return false }
        var replaceQuery = query
        replaceQuery[kSecValueData as String] = data
        replaceQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(replaceQuery as CFDictionary, nil) == errSecSuccess { return true }
        if let previous {
            var restoreQuery = query
            restoreQuery[kSecValueData as String] = Data(previous.utf8)
            restoreQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(restoreQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }


    @discardableResult
    static func delete(account: String, service: String = defaultService) -> Bool {
        if isRunningInTest {
            lock.lock()
            _inMemoryStore.removeValue(forKey: "\(service).\(account)")
            lock.unlock()
            return true
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
