import XCTest
@testable import Core

final class TransformTextActionTests: XCTestCase {
    func testCaseConversions() {
        let text = "hello world example"
        XCTAssertEqual(TransformCase.uppercase.transform(text), "HELLO WORLD EXAMPLE")
        XCTAssertEqual(TransformCase.lowercase.transform(text), "hello world example")
        XCTAssertEqual(TransformCase.titleCase.transform(text), "Hello World Example")
        XCTAssertEqual(TransformCase.camelCase.transform(text), "helloWorldExample")
        XCTAssertEqual(TransformCase.pascalCase.transform(text), "HelloWorldExample")
    }
    
    func testTextCleaningAndLineTools() {
        XCTAssertEqual(TransformCase.trimWhitespace.transform("   hello world   \n\n"), "hello world")
        XCTAssertEqual(TransformCase.sortLines.transform("banana\napple\ncherry"), "apple\nbanana\ncherry")
        XCTAssertEqual(TransformCase.removeDuplicates.transform("apple\napple\nbanana"), "apple\nbanana")
        XCTAssertEqual(TransformCase.reverseText.transform("hello"), "olleh")
    }
    
    func testEncodingAndJSON() {
        XCTAssertEqual(TransformCase.urlEncode.transform("hello world"), "hello%20world")
        XCTAssertEqual(TransformCase.urlDecode.transform("hello%20world"), "hello world")
        XCTAssertEqual(TransformCase.base64Encode.transform("hello"), "aGVsbG8=")
        XCTAssertEqual(TransformCase.base64Decode.transform("aGVsbG8="), "hello")
        
        let rawJSON = "{\"name\":\"openclip\",\"version\":1}"
        let formatted = TransformCase.formatJSON.transform(rawJSON)
        XCTAssertTrue(formatted.contains("\n"))
        XCTAssertTrue(formatted.contains("\"name\" : \"openclip\"") || formatted.contains("\"name\": \"openclip\""))
    }
}
