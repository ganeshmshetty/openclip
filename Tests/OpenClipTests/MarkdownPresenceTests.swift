import XCTest
import Core

final class MarkdownPresenceTests: XCTestCase {

    func testPlainProseStaysPlain() {
        XCTAssertFalse(MarkdownPresence.isMarkdown(""))
        XCTAssertFalse(MarkdownPresence.isMarkdown("这是一段普通的翻译结果，没有任何格式。"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("The quick brown fox jumps over the lazy dog.\nSecond line of prose."))
    }

    func testHeadings() {
        XCTAssertTrue(MarkdownPresence.isMarkdown("# Title"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("### Section\nbody"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("## 安装步骤\n正文"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("## インストール"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("#hashtag without space"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("####### seven hashes"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("mid-line # is not a heading"))
    }

    func testLists() {
        XCTAssertTrue(MarkdownPresence.isMarkdown("- first\n- second"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("* item"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("1. step one\n2. step two"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("3) parenthesized"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("version 1.2.3 released"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("-5 degrees outside"))
    }

    func testInlineMarkers() {
        XCTAssertTrue(MarkdownPresence.isMarkdown("this is **bold** text"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("some `code` inline"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("see [the docs](https://example.com)"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("really *important* point"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("2*3*4 is arithmetic"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("a lone ** marker"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("snake_case_name stays plain"))
    }

    func testCodeFences() {
        XCTAssertTrue(MarkdownPresence.isMarkdown("```swift\nlet x = 1\n```"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("```swift\nlet x = 1"))
        // Shell output inside a fence must not leak block detection, but the fence itself renders.
        XCTAssertTrue(MarkdownPresence.isMarkdown("```\n# comment\n* glob\n```"))
    }

    func testShellOutputStaysPlain() {
        XCTAssertFalse(MarkdownPresence.isMarkdown("# comment line\nls *.swift\nrm -rf build"))
        XCTAssertFalse(MarkdownPresence.isMarkdown("total 24\n-rw-r--r-- 1 tim staff 512 Nov 12 file.txt"))
    }

    func testBlockquoteAndTableAndRule() {
        XCTAssertTrue(MarkdownPresence.isMarkdown("> quoted line"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("| a | b |\n| - | - |"))
        XCTAssertTrue(MarkdownPresence.isMarkdown("above\n---\nbelow"))
    }

    func testOversizedTextStaysPlain() {
        let huge = String(repeating: "# heading\n", count: 4_000)
        XCTAssertFalse(MarkdownPresence.isMarkdown(huge))
    }
}