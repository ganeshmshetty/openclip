import XCTest
@testable import Core

final class ProtocolConformanceTests: XCTestCase {
    func testConfigurableActionProtocolExists() {
        let _: (any ConfigurableAction).Type = (any ConfigurableAction).self
        XCTAssertTrue(true)
    }

    func testWordCompletionProvidingProtocolExists() {
        let _: (any WordCompletionProviding).Type = (any WordCompletionProviding).self
        XCTAssertTrue(true)
    }
}
