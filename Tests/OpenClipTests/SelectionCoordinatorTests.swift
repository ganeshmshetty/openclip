import XCTest
@testable import Core

fileprivate struct MockApp: AppIdentifying {
    let bundleIdentifier: String?
    let localizedName: String?
}

@MainActor
final class SelectionCoordinatorTests: XCTestCase {
    @MainActor
    final class MockMonitor: SelectionMonitoring {
        var onSelection: ((SelectionContext) -> Void)?
        var isStarted = false
        func start() { isStarted = true }
        func stop() { isStarted = false }
    }
    
    func testSelectionCoordinatorDelegatesStartAndStop() {
        let mockMonitor = MockMonitor()
        let coordinator = SelectionCoordinator(monitor: mockMonitor)
        
        coordinator.start()
        XCTAssertTrue(mockMonitor.isStarted)
        
        coordinator.stop()
        XCTAssertFalse(mockMonitor.isStarted)
    }
    
    func testSelectionCoordinatorEmitsSelectionContext() {
        let mockMonitor = MockMonitor()
        let coordinator = SelectionCoordinator(monitor: mockMonitor)
        
        var receivedContext: SelectionContext?
        coordinator.onSelection = { context in
            receivedContext = context
        }
        coordinator.start()
        
        let app = MockApp(bundleIdentifier: "com.apple.Notes", localizedName: "Notes")
        let sampleContext = SelectionContext(
            text: "Selected text",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        
        mockMonitor.onSelection?(sampleContext)
        XCTAssertEqual(receivedContext?.text, "Selected text")
    }
    
    func testSelectionCoordinatorHandlesNilCallbacksGracefully() {
        let mockMonitor = MockMonitor()
        let coordinator = SelectionCoordinator(monitor: mockMonitor)
        coordinator.start()
        
        let app = MockApp(bundleIdentifier: "com.apple.TextEdit", localizedName: "TextEdit")
        let sampleContext = SelectionContext(
            text: "Sample",
            sourceApp: app,
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        
        mockMonitor.onSelection?(sampleContext)
        XCTAssertEqual(coordinator.currentSelection?.text, "Sample")
    }
}
