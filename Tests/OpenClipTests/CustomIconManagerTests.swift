import XCTest
import AppKit
@testable import Core
@testable import OpenClip

@MainActor
final class CustomIconManagerTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        TestIsolation.reset()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CustomIconManagerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        try await super.tearDown()
    }

    func testNormalizeHost() {
        XCTAssertEqual(CustomIconManager.normalizeHost(from: "github.com"), "github.com")
        XCTAssertEqual(CustomIconManager.normalizeHost(from: "https://apple.com/mac/"), "apple.com")
        XCTAssertEqual(CustomIconManager.normalizeHost(from: "http://SUB.DOMAIN.co.uk:8080/path"), "sub.domain.co.uk")
        XCTAssertNil(CustomIconManager.normalizeHost(from: ""))
        XCTAssertNil(CustomIconManager.normalizeHost(from: "   "))
    }

    func testImportValidImage() throws {
        let sourceURL = tempDirectoryURL.appendingPathComponent("test_icon.png")
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.blue.set()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create test PNG")
            return
        }
        try png.write(to: sourceURL)

        let manager = CustomIconManager(directoryURL: tempDirectoryURL)
        let iconId = try manager.importIcon(from: sourceURL)
        XCTAssertTrue(iconId.hasPrefix(Constants.customIconPrefix))
        XCTAssertTrue(iconId.hasSuffix(".png"))
        XCTAssertTrue(manager.customIcons.contains(iconId))

        // Cleanup
        manager.deleteCustomIcon(named: iconId)
        XCTAssertFalse(manager.customIcons.contains(iconId))
    }

    func testImportNonexistentFileThrows() {
        let missingURL = tempDirectoryURL.appendingPathComponent("does_not_exist.png")
        let manager = CustomIconManager(directoryURL: tempDirectoryURL)
        XCTAssertThrowsError(try manager.importIcon(from: missingURL)) { error in
            guard let iconError = error as? CustomIconError else {
                XCTFail("Expected CustomIconError, got \(error)")
                return
            }
            if case .fileNotFound = iconError {} else {
                XCTFail("Expected fileNotFound, got \(iconError)")
            }
        }
    }

    func testImportUnsupportedFileTypeThrows() throws {
        let txtURL = tempDirectoryURL.appendingPathComponent("notes.txt")
        try "hello".write(to: txtURL, atomically: true, encoding: .utf8)
        let manager = CustomIconManager(directoryURL: tempDirectoryURL)
        XCTAssertThrowsError(try manager.importIcon(from: txtURL)) { error in
            guard let iconError = error as? CustomIconError else {
                XCTFail("Expected CustomIconError, got \(error)")
                return
            }
            if case .unsupportedFileType = iconError {} else {
                XCTFail("Expected unsupportedFileType, got \(iconError)")
            }
        }
    }

    func testDeleteCustomIconRejectsPathTraversalAndEmptyID() throws {
        let manager = CustomIconManager(directoryURL: tempDirectoryURL)
        // Ensure root directory exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectoryURL.path))

        // Deleting empty ID or custom: prefix should NOT delete directoryURL
        manager.deleteCustomIcon(named: "")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectoryURL.path))

        manager.deleteCustomIcon(named: "custom:")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectoryURL.path))

        // Deleting with path traversal should NOT delete parent directory
        manager.deleteCustomIcon(named: "custom:../../sensitive")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectoryURL.path))

        manager.deleteCustomIcon(named: "custom:..")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectoryURL.path))
    }
}
