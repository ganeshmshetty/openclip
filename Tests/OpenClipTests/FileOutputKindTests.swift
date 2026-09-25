import XCTest
@testable import Core

final class FileOutputKindTests: XCTestCase {
    func testMIMEKinds() {
        let cases: [(String, FileOutputKind)] = [
            ("image/png", .image),
            ("image/heic", .image),
            ("application/pdf", .pdf),
            ("text/plain", .text),
            ("text/csv", .text),
            ("text/markdown", .text),
            ("application/json", .text),
            ("application/xml", .text),
            ("text/yaml", .text),
            ("application/x-yaml", .text),
            ("text/html", .other),
            ("application/rtf", .other),
        ]
        for (mime, expected) in cases {
            XCTAssertEqual(FileOutputKind.resolve(mimeType: mime, fileExtension: ""), expected, mime)
        }
    }

    func testExtensionKinds() {
        let cases: [(String, FileOutputKind)] = [
            ("md", .text), ("csv", .text), ("json", .text), ("yaml", .text),
            ("swift", .text), ("py", .text), ("sql", .text), ("txt", .text),
            ("png", .image), ("heic", .image), ("svg", .image),
            ("pdf", .pdf),
            ("docx", .other), ("xlsx", .other), ("mp4", .other), ("zip", .other), ("openclipunknown", .other),
        ]
        for (ext, expected) in cases {
            XCTAssertEqual(FileOutputKind.resolve(mimeType: nil, fileExtension: ext), expected, ext)
        }
    }

    func testGenericMIMEFallsBackToExtension() {
        XCTAssertEqual(FileOutputKind.resolve(mimeType: "application/octet-stream", fileExtension: "png"), .image)
        XCTAssertEqual(FileOutputKind.resolve(mimeType: "application/octet-stream", fileExtension: "csv"), .text)
    }

    func testPayloadKindAndIsImage() {
        XCTAssertEqual(FileOutputPayload(url: URL(fileURLWithPath: "/tmp/report.csv")).kind, .text)
        XCTAssertEqual(FileOutputPayload(url: URL(fileURLWithPath: "/tmp/notes.md")).kind, .text)
        XCTAssertEqual(FileOutputPayload(url: URL(fileURLWithPath: "/tmp/paper.pdf")).kind, .pdf)
        XCTAssertEqual(FileOutputPayload(url: URL(fileURLWithPath: "/tmp/archive.zip")).kind, .other)
        XCTAssertTrue(FileOutputPayload(url: URL(fileURLWithPath: "/tmp/photo.png")).isImage)
        XCTAssertFalse(FileOutputPayload(url: URL(fileURLWithPath: "/tmp/report.csv")).isImage)
    }

    func testTemporaryOutputUsesWidenedExtensions() throws {
        let cases: [(String, String)] = [
            ("text/markdown", "md"),
            ("text/csv", "csv"),
            ("text/yaml", "yaml"),
            ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx"),
            ("audio/wav", "wav"),
            ("video/quicktime", "mov"),
        ]
        let data = Data("hello".utf8)
        for (mime, ext) in cases {
            let url = try XCTUnwrap(ShellResultMapper.writeTemporaryOutput(data: data, filename: nil, mimeType: mime))
            XCTAssertEqual(url.pathExtension, ext, mime)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
