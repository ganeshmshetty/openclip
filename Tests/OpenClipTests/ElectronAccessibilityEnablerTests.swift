import XCTest
import AppKit
import ApplicationServices
import os
@testable import OpenClip

@MainActor
final class ElectronAccessibilityEnablerTests: XCTestCase {
    private final class StubApp: NSRunningApplication {
        private let pid: pid_t
        init(pid: pid_t) {
            self.pid = pid
            super.init()
        }
        override var bundleIdentifier: String? { "com.example.electron" }
        override var processIdentifier: pid_t { pid }
    }

    private final class SetterLog: @unchecked Sendable {
        let pids = OSAllocatedUnfairLock<[pid_t]>(initialState: [])
        var count: Int { pids.withLock { $0.count } }
    }

    private func waitForCalls(_ log: SetterLog, count: Int) async {
        for _ in 0..<200 where log.count < count {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    func testDetectsElectronFrameworkInBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let electron = root.appendingPathComponent("Electron.app")
        let native = root.appendingPathComponent("Native.app")
        try FileManager.default.createDirectory(
            at: electron.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: native.appendingPathComponent("Contents/Frameworks/Sparkle.framework"),
            withIntermediateDirectories: true)

        XCTAssertTrue(ElectronAccessibilityEnabler.isElectronApp(bundleURL: electron))
        XCTAssertFalse(ElectronAccessibilityEnabler.isElectronApp(bundleURL: native))
        XCTAssertFalse(ElectronAccessibilityEnabler.isElectronApp(bundleURL: nil))
    }

    /// Forks can rename the Electron framework (the Codex app ships "Codex Framework.framework").
    /// The shipped app source under Resources identifies them without a bundle-ID allowlist.
    func testDetectsRenamedElectronFrameworkByResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let renamed = root.appendingPathComponent("Codex.app")
        let unpacked = root.appendingPathComponent("Unpacked.app")
        try FileManager.default.createDirectory(
            at: renamed.appendingPathComponent("Contents/Frameworks/Codex Framework.framework"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: renamed.appendingPathComponent("Contents/Resources"),
            withIntermediateDirectories: true)
        try Data().write(to: renamed.appendingPathComponent("Contents/Resources/app.asar"))
        try FileManager.default.createDirectory(
            at: unpacked.appendingPathComponent("Contents/Resources/app"),
            withIntermediateDirectories: true)

        XCTAssertTrue(ElectronAccessibilityEnabler.isElectronApp(bundleURL: renamed))
        XCTAssertTrue(ElectronAccessibilityEnabler.isElectronApp(bundleURL: unpacked))
    }

    func testSetsManualAccessibilityOncePerElectronProcess() async {
        let log = SetterLog()
        let enabler = ElectronAccessibilityEnabler(isElectron: { _ in true }, setter: { pid in
            log.pids.withLock { $0.append(pid) }
            return .success
        })
        let app = StubApp(pid: 4242)
        enabler.enableIfNeeded(for: app)
        enabler.enableIfNeeded(for: app)
        await waitForCalls(log, count: 1)
        enabler.enableIfNeeded(for: app)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(log.pids.withLock { $0 }, [4242], "activation and every mouse-down must not re-send the AX set")
    }

    func testSkipsNonElectronAndOwnProcess() async {
        let log = SetterLog()
        var checked: [pid_t] = []
        let enabler = ElectronAccessibilityEnabler(isElectron: { app in
            checked.append(app.processIdentifier)
            return false
        }, setter: { pid in
            log.pids.withLock { $0.append(pid) }
            return .success
        })
        enabler.enableIfNeeded(for: StubApp(pid: 777))
        enabler.enableIfNeeded(for: StubApp(pid: 777))
        enabler.enableIfNeeded(for: StubApp(pid: ProcessInfo.processInfo.processIdentifier))
        enabler.enableIfNeeded(for: nil)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(log.count, 0)
        XCTAssertEqual(checked, [777], "the bundle check runs once per process and never for OpenClip itself")
    }

    func testFailedSetIsRetriedOnNextRequest() async {
        let log = SetterLog()
        let enabler = ElectronAccessibilityEnabler(isElectron: { _ in true }, setter: { pid in
            let attempt = log.pids.withLock { pids -> Int in
                pids.append(pid)
                return pids.count
            }
            return attempt == 1 ? .cannotComplete : .success
        })
        let app = StubApp(pid: 5151)
        enabler.enableIfNeeded(for: app)
        await waitForCalls(log, count: 1)
        // Let the failure clear its decision on the main actor.
        try? await Task.sleep(nanoseconds: 50_000_000)
        enabler.enableIfNeeded(for: app)
        await waitForCalls(log, count: 2)
        enabler.enableIfNeeded(for: app)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(log.count, 2, "a cold app that refused the set gets one more try, then no more")
    }
}
