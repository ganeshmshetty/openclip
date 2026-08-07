import Foundation
import Combine
@testable import Core

/// In-memory `SettingsStore` test double. Lets tests exercise store-backed behavior (builtin
/// settings, registry disable lists, customization overrides) without touching
/// `UserDefaults.standard`, the real preferences domain, or `DefaultSettingsStore.shared`.
///
/// `Set<String>` and `Data?` values are stored natively (no UserDefaults array/Data encoding),
/// so the store needs none of `DefaultSettingsStore`'s value special-casing.
final class MemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private let subject = PassthroughSubject<String, Never>()

    func get<T>(_ key: SettingKey<T>) -> T {
        lock.lock()
        defer { lock.unlock() }
        return (values[key.name] as? T) ?? key.defaultValue
    }

    func set<T>(_ key: SettingKey<T>, value: T) {
        lock.lock()
        values[key.name] = value
        subject.send(key.name)
        lock.unlock()
    }

    func publisher<T>(for key: SettingKey<T>) -> AnyPublisher<T, Never> {
        subject
            .filter { $0 == key.name }
            .map { [weak self] _ in self?.get(key) ?? key.defaultValue }
            .eraseToAnyPublisher()
    }
}
