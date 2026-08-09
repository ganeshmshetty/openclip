// SettingsStore.swift
// OpenClip
//
// Defines the central SettingsStore protocol and DefaultSettingsStore adapter for typed application configuration management through the Settings Door.
import Foundation
import Combine

public protocol SettingsStore: AnyObject, Sendable {
    func get<T>(_ key: SettingKey<T>) -> T
    func set<T>(_ key: SettingKey<T>, value: T)
    func publisher<T>(for key: SettingKey<T>) -> AnyPublisher<T, Never>
}

public final class DefaultSettingsStore: SettingsStore, @unchecked Sendable {
    public static let shared = DefaultSettingsStore()
    private let userDefaults: UserDefaults
    // Combine's PassthroughSubject is not thread-safe: `set` may be called from any thread, so all
    // sends are serialized under `lock`. UserDefaults itself is thread-safe, so `get`/`set` reads
    // and writes stay unlocked. Using a recursive lock allows subscribers to call `set` during
    // notification dispatch without deadlocking.
    private let lock = NSRecursiveLock()
    private let subject = PassthroughSubject<String, Never>()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func get<T>(_ key: SettingKey<T>) -> T {
        if T.self == Set<String>.self {
            let array = userDefaults.stringArray(forKey: key.name) ?? []
            return (Set(array) as! T)
        }
        if T.self == Data?.self {
            return (userDefaults.data(forKey: key.name) as! T)
        }
        return (userDefaults.object(forKey: key.name) as? T) ?? key.defaultValue
    }

    public func set<T>(_ key: SettingKey<T>, value: T) {
        if let setVal = value as? Set<String> {
            userDefaults.set(Array(setVal), forKey: key.name)
        } else {
            userDefaults.set(value, forKey: key.name)
        }
        lock.lock()
        subject.send(key.name)
        lock.unlock()
    }

    public func publisher<T>(for key: SettingKey<T>) -> AnyPublisher<T, Never> {
        subject
            .filter { $0 == key.name }
            .map { [weak self] _ in self?.get(key) ?? key.defaultValue }
            .eraseToAnyPublisher()
    }
}
