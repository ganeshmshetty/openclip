import Foundation
import ApplicationServices
import Core

@MainActor
public final class AXHelperClient: ObservableObject, Sendable {
    public static let shared = AXHelperClient()

    private let machServiceName: String
    private var connection: NSXPCConnection?
    private let localPermissionChecker: @Sendable (Bool) -> Bool

    public init(
        machServiceName: String = AXHelperConstants.machServiceName,
        localPermissionChecker: @escaping @Sendable (Bool) -> Bool = { prompt in
            let options = prompt ? ["AXTrustedCheckOptionPrompt": true] as CFDictionary : nil
            return AXIsProcessTrustedWithOptions(options)
        }
    ) {
        self.machServiceName = machServiceName
        self.localPermissionChecker = localPermissionChecker
    }

    private func getOrCreateConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }
        let conn = NSXPCConnection(machServiceName: machServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: AXHelperServiceProtocol.self)
        let onDisconnect: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                self?.connection = nil
            }
        }
        conn.interruptionHandler = onDisconnect
        conn.invalidationHandler = onDisconnect
        conn.resume()
        self.connection = conn
        return conn
    }

    public func isHelperAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            let once = OnceResume<Bool>()
            let conn = getOrCreateConnection()
            let errorHandler: @Sendable (Error) -> Void = { _ in
                once.resume(continuation, with: false)
            }
            guard let proxy = conn.remoteObjectProxyWithErrorHandler(errorHandler) as? AXHelperServiceProtocol else {
                once.resume(continuation, with: false)
                return
            }
            let reply: @Sendable (Bool) -> Void = { isAlive in
                once.resume(continuation, with: isAlive)
            }
            proxy.ping(withReply: reply)
        }
    }

    public func checkAccessibility(prompt: Bool) async -> Bool {
        if await isHelperAvailable() {
            let fallbackChecker = localPermissionChecker
            return await withCheckedContinuation { continuation in
                let once = OnceResume<Bool>()
                let conn = getOrCreateConnection()
                let errorHandler: @Sendable (Error) -> Void = { _ in
                    let fallback = fallbackChecker(prompt)
                    once.resume(continuation, with: fallback)
                }
                guard let proxy = conn.remoteObjectProxyWithErrorHandler(errorHandler) as? AXHelperServiceProtocol else {
                    let fallback = fallbackChecker(prompt)
                    once.resume(continuation, with: fallback)
                    return
                }
                let reply: @Sendable (Bool) -> Void = { isGranted in
                    once.resume(continuation, with: isGranted)
                }
                proxy.checkAccessibilityPermission(prompt: prompt, withReply: reply)
            }
        } else {
            return checkLocalAccessibilityPermission(prompt: prompt)
        }
    }

    public func retrieveSelectedText(pid: Int32) async -> AXSelectionPayload? {
        if await isHelperAvailable() {
            return await withCheckedContinuation { continuation in
                let once = OnceResume<AXSelectionPayload?>()
                let conn = getOrCreateConnection()
                let errorHandler: @Sendable (Error) -> Void = { _ in
                    once.resume(continuation, with: nil)
                }
                guard let proxy = conn.remoteObjectProxyWithErrorHandler(errorHandler) as? AXHelperServiceProtocol else {
                    once.resume(continuation, with: nil)
                    return
                }
                let reply: @Sendable (Data?) -> Void = { data in
                    guard let data,
                          let payload = try? JSONDecoder().decode(AXSelectionPayload.self, from: data) else {
                        once.resume(continuation, with: nil)
                        return
                    }
                    once.resume(continuation, with: payload)
                }
                proxy.retrieveSelectedText(pid: pid, withReply: reply)
            }
        }
        return nil
    }

    public func postKey(keyCode: UInt16, flags: UInt64) async -> Bool {
        if await isHelperAvailable() {
            return await withCheckedContinuation { continuation in
                let once = OnceResume<Bool>()
                let conn = getOrCreateConnection()
                let errorHandler: @Sendable (Error) -> Void = { _ in
                    once.resume(continuation, with: false)
                }
                guard let proxy = conn.remoteObjectProxyWithErrorHandler(errorHandler) as? AXHelperServiceProtocol else {
                    once.resume(continuation, with: false)
                    return
                }
                let reply: @Sendable (Bool) -> Void = { success in
                    once.resume(continuation, with: success)
                }
                proxy.postKey(keyCode: keyCode, flags: flags, withReply: reply)
            }
        }
        return false
    }

    public nonisolated func checkLocalAccessibilityPermission(prompt: Bool) -> Bool {
        localPermissionChecker(prompt)
    }
}
