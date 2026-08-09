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
    /// Serializes each value write with its notification, so a concurrent setter can never publish a
    /// value it didn't write. Distinct from `lock` (which guards the values dictionary): notifications
    /// are queued under `notificationLock` and drained with the lock released, so a synchronous
    /// subscriber that calls `get` or `set` during delivery never deadlocks.
    private let notificationLock = NSLock()
    private var pendingNotifications: [String] = []
    private var isDelivering = false

    func get<T>(_ key: SettingKey<T>) -> T {
        lock.lock()
        defer { lock.unlock() }
        return (values[key.name] as? T) ?? key.defaultValue
    }

    func set<T>(_ key: SettingKey<T>, value: T) {
        lock.lock()
        values[key.name] = value
        lock.unlock()
        notificationLock.lock()
        pendingNotifications.append(key.name)
        notificationLock.unlock()
        deliverPendingNotifications()
    }

    /// Drains `pendingNotifications` FIFO, holding `notificationLock` only between sends — never during
    /// `subject.send`. The `isDelivering` flag makes re-entrant `set`s from a subscriber safe: they
    /// enqueue and return, and the in-flight drain picks the new item up in order.
    private func deliverPendingNotifications() {
        notificationLock.lock()
        guard !isDelivering else {
            notificationLock.unlock()
            return
        }
        isDelivering = true
        while !pendingNotifications.isEmpty {
            let name = pendingNotifications.removeFirst()
            notificationLock.unlock()
            subject.send(name)
            notificationLock.lock()
        }
        isDelivering = false
        notificationLock.unlock()
    }

    func publisher<T>(for key: SettingKey<T>) -> AnyPublisher<T, Never> {
        subject
            .filter { $0 == key.name }
            .map { [weak self] _ in self?.get(key) ?? key.defaultValue }
            .eraseToAnyPublisher()
    }
}
