import XCTest
import AppKit
@testable import Core
@testable import OpenClip

@MainActor
final class ClipBasketPasteboardReaderTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipBasketReader-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() async throws {
        pasteboard?.releaseGlobally()
        pasteboard = nil
        try await super.tearDown()
    }

    func testReadsPlainText() {
        pasteboard.setString("hello", forType: .string)

        switch ClipBasketPasteboardReader().read(from: pasteboard) {
        case .content(.text(let payload)):
            XCTAssertEqual(payload.plainText, "hello")
        default:
            XCTFail("Expected text content")
        }
    }

    func testFilesWinOverText() {
        let url = URL(fileURLWithPath: "/tmp/basket.txt")
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString("/tmp/basket.txt", forType: .string)

        switch ClipBasketPasteboardReader().read(from: pasteboard) {
        case .content(.files(let urls)):
            XCTAssertEqual(urls, [url])
        default:
            XCTFail("Expected file content")
        }
    }

    func testImageWinsOverText() throws {
        let data = try makePNGData()
        pasteboard.setData(data, forType: .png)
        pasteboard.setString("fallback", forType: .string)

        switch ClipBasketPasteboardReader().read(from: pasteboard) {
        case .content(.image(let imageData, let uti, let width, let height)):
            XCTAssertEqual(imageData, data)
            XCTAssertEqual(uti, "public.png")
            XCTAssertGreaterThan(width ?? 0, 0)
            XCTAssertGreaterThan(height ?? 0, 0)
        default:
            XCTFail("Expected image content")
        }
    }

    func testOversizedImageIsSkipped() throws {
        let data = try makePNGData()
        let reader = ClipBasketPasteboardReader(maxImageBytes: 4)
        pasteboard.setData(data, forType: .png)
        pasteboard.setString("fallback", forType: .string)

        XCTAssertEqual(reader.read(from: pasteboard), .ignored(.oversizedImage))
    }

    func testProtectedPasteboardIsSkipped() {
        for type in ClipBasketPasteboardReader.protectedTypes {
            pasteboard.clearContents()
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            pasteboard.setString("secret", forType: .string)
            XCTAssertEqual(ClipBasketPasteboardReader().read(from: pasteboard), .ignored(.protected))
        }
    }

    func testEmptyPasteboardIsIgnored() {
        XCTAssertEqual(ClipBasketPasteboardReader().read(from: pasteboard), .ignored(.empty))
    }

    private func makePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}

@MainActor
final class ClipBasketPasteboardMonitorTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        try await super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipBasketMonitor-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() async throws {
        pasteboard?.releaseGlobally()
        pasteboard = nil
        try await super.tearDown()
    }

    private func makeMonitor(
        identity: AppIdentity? = AppIdentity(bundleIdentifier: "com.example.editor", localizedName: "Editor"),
        excluded: @escaping @MainActor (String) -> Bool = { _ in false },
        disabled: @escaping @MainActor (AppIdentity) -> Bool = { _ in false }
    ) -> ClipBasketPasteboardMonitor {
        ClipBasketPasteboardMonitor(
            pasteboard: pasteboard,
            accessPolicy: PasteboardAccessPolicy(read: { .allowed }),
            frontmostIdentity: { identity },
            isExcluded: excluded,
            isDisabled: disabled
        )
    }

    func testCapturesTextChange() {
        let monitor = makeMonitor()
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.tick()

        XCTAssertEqual(captured, [.text(RichPasteboardPayload(plainText: "copied"))])
    }

    func testExcludedAppIsIgnored() {
        let monitor = makeMonitor(excluded: { $0 == "com.pilotmoon.popclip" })
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }
        let excludedMonitor = ClipBasketPasteboardMonitor(
            pasteboard: pasteboard,
            accessPolicy: PasteboardAccessPolicy(read: { .allowed }),
            frontmostIdentity: { AppIdentity(bundleIdentifier: "com.pilotmoon.popclip") },
            isExcluded: { $0 == "com.pilotmoon.popclip" },
            isDisabled: { _ in false }
        )
        excludedMonitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.tick()
        excludedMonitor.tick()

        XCTAssertEqual(captured.count, 1)
    }

    func testDisabledRuleIsIgnored() {
        let monitor = makeMonitor(disabled: { _ in true })
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.tick()

        XCTAssertTrue(captured.isEmpty)
    }

    func testAccessDeniedIsIgnored() {
        let monitor = ClipBasketPasteboardMonitor(
            pasteboard: pasteboard,
            accessPolicy: PasteboardAccessPolicy(read: { .denied }),
            frontmostIdentity: { AppIdentity(bundleIdentifier: "com.example.editor") },
            isExcluded: { _ in false },
            isDisabled: { _ in false }
        )
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.tick()

        XCTAssertTrue(captured.isEmpty)
    }

    func testSelfWritesAreIgnored() {
        let monitor = makeMonitor()
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        monitor.beginSelfWrite()
        pasteboard.clearContents()
        pasteboard.setString("basket paste", forType: .string)
        monitor.tick()
        monitor.endSelfWrite()
        XCTAssertTrue(captured.isEmpty)

        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)
        monitor.tick()
        XCTAssertEqual(captured, [.text(RichPasteboardPayload(plainText: "user copy"))])
    }

    func testStartAndStopToggleRunning() {
        let monitor = makeMonitor()
        XCTAssertFalse(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
    }
}
