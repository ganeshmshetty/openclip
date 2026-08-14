import XCTest
import AppKit
@testable import OpenClip

@MainActor
final class MacSelectionMonitorTests: XCTestCase {

    func testCommandATriggersSelectionRetrieval() {
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x08, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: []))
    }

    func testShiftArrowTriggersSelectionRetrieval() {
        for keyCode: UInt16 in [0x7B, 0x7C, 0x7D, 0x7E] {
            XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: [.shift]), "keyCode 0x\(String(keyCode, radix: 16))")
        }
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.shift, .command]))
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7E, flags: [.shift, .option]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.option]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.shift, .command]))
    }

    func testPlainKeysDoNotTrigger() {
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: []))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.shift]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x31, flags: [.command]))
    }

    func testCapsLockDoesNotSilenceTriggers() {
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x00, flags: [.capsLock, .command]))
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x08, flags: [.capsLock, .command]))
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.capsLock, .shift]))
        for keyCode: UInt16 in [0x7C, 0x7D, 0x7E] {
            XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: keyCode, flags: [.capsLock, .shift]), "keyCode 0x\(String(keyCode, radix: 16))")
        }
        XCTAssertFalse(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.capsLock]))
        XCTAssertTrue(MacSelectionMonitor.isSelectionTrigger(keyCode: 0x7B, flags: [.capsLock, .shift, .command]))
    }

    func testRapidKeyboardSelectionTriggersCancelPriorPendingTask() {
        let monitor = MacSelectionMonitor()
        
        // First trigger spawns initial debounce task
        monitor.handleSelectionTrigger(isSelectAll: false)
        let firstTask = monitor.debounceTask
        XCTAssertNotNil(firstTask)
        XCTAssertFalse(firstTask?.isCancelled == true)

        // Rapid second trigger immediately cancels prior task and replaces it
        monitor.handleSelectionTrigger(isSelectAll: false)
        XCTAssertTrue(firstTask?.isCancelled == true)
        
        let secondTask = monitor.debounceTask
        XCTAssertNotNil(secondTask)
        XCTAssertFalse(secondTask?.isCancelled == true)

        // Cleanup
        secondTask?.cancel()
    }
}
