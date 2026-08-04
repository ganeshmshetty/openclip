import XCTest
@testable import Core

final class TransformTextActionTests: XCTestCase {
    func testCaseConversions() {
        let text = "hello world example"
        XCTAssertEqual(TransformCase.uppercase.transform(text), "HELLO WORLD EXAMPLE")
        XCTAssertEqual(TransformCase.lowercase.transform(text), "hello world example")
        XCTAssertEqual(TransformCase.titleCase.transform(text), "Hello World Example")
        XCTAssertEqual(TransformCase.camelCase.transform(text), "helloWorldExample")
    }
}
