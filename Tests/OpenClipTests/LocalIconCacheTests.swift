import XCTest
import AppKit
@testable import OpenClip

final class LocalIconCacheTests: XCTestCase {
    private var tempDirectoryURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalIconCacheTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
        try await super.tearDown()
    }

    @MainActor
    func testValidImageIsCached() throws {
        let fileURL = tempDirectoryURL.appendingPathComponent("valid_icon.png")
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create PNG data")
            return
        }
        try pngData.write(to: fileURL)

        let loaded1 = LocalIconCache.shared.image(for: fileURL)
        XCTAssertNotNil(loaded1)

        let loaded2 = LocalIconCache.shared.image(for: fileURL)
        XCTAssertNotNil(loaded2)
    }

    @MainActor
    func testMissingFileIsCachedAsNegativeEntry() throws {
        let missingFileURL = tempDirectoryURL.appendingPathComponent("missing_icon_\(UUID().uuidString).png")

        // 1. Initial attempt on missing file returns nil
        let loadedInitial = LocalIconCache.shared.image(for: missingFileURL)
        XCTAssertNil(loadedInitial)

        // 2. Write a file to that location after the failed load
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.blue.set()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            try pngData.write(to: missingFileURL)
        }

        // 3. Second attempt should still return nil because the failed load was cached as a negative entry
        let loadedSecond = LocalIconCache.shared.image(for: missingFileURL)
        XCTAssertNil(loadedSecond, "Expected missing file to be served from negative cache as nil")
    }
}
