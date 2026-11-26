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

    func testOversizedTextIsSkipped() {
        let reader = ClipBasketPasteboardReader(maxTextBytes: 4)
        pasteboard.setString("more than four bytes", forType: .string)

        XCTAssertEqual(reader.read(from: pasteboard), .ignored(.oversizedText))
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

    func testMediaPasteRequiresTheCapturedTargetToStayFrontmost() {
        XCTAssertTrue(ClipBasketPaster.canPost(targetPID: nil, frontmostPID: 42))
        XCTAssertTrue(ClipBasketPaster.canPost(targetPID: 42, frontmostPID: 42))
        XCTAssertFalse(ClipBasketPaster.canPost(targetPID: 42, frontmostPID: 7))
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
        identity: @escaping @MainActor () -> AppIdentity? = {
            AppIdentity(bundleIdentifier: "com.example.editor", localizedName: "Editor")
        },
        excluded: @escaping @MainActor (String) -> Bool = { _ in false },
        disabled: @escaping @MainActor (AppIdentity) -> Bool = { _ in false }
    ) -> ClipBasketPasteboardMonitor {
        ClipBasketPasteboardMonitor(
            pasteboard: pasteboard,
            accessPolicy: PasteboardAccessPolicy(read: { .allowed }),
            frontmostIdentity: identity,
            isExcluded: excluded,
            isDisabled: disabled
        )
    }

    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async {
        for _ in 0..<Int(timeout * 100) {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }

    func testCapturesTextChange() async {
        let monitor = makeMonitor()
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.tick()

        await waitFor("captured text") { captured == [.text(RichPasteboardPayload(plainText: "copied"))] }
    }

    func testExcludedAppIsIgnored() async {
        let monitor = makeMonitor(
            identity: { AppIdentity(bundleIdentifier: "com.pilotmoon.popclip") },
            excluded: { $0 == "com.pilotmoon.popclip" }
        )
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.tick()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(captured.isEmpty)
    }

    func testDisabledRuleIsIgnored() async {
        let monitor = makeMonitor(disabled: { _ in true })
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("copied", forType: .string)
        monitor.tick()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(captured.isEmpty)
    }

    func testAccessDeniedIsIgnored() async {
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
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(captured.isEmpty)
    }

    func testMarkedPasteboardWritesAreIgnored() async {
        let monitor = makeMonitor()
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("basket paste", forType: .string)
        for type in ClipBasketPaster.selfWriteMarkerTypes {
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(type))
        }
        monitor.tick()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(captured.isEmpty)

        pasteboard.clearContents()
        pasteboard.setString("user copy", forType: .string)
        monitor.tick()
        await waitFor("user copy captured") {
            captured == [.text(RichPasteboardPayload(plainText: "user copy"))]
        }
    }

    func testAppSwitchBetweenPollsDiscardsAmbiguousCopy() async {
        var identity = AppIdentity(bundleIdentifier: "com.example.one")
        let monitor = makeMonitor(identity: { identity })
        var captured: [ClipBasketContent] = []
        monitor.onCapture = { content, _ in captured.append(content) }

        pasteboard.clearContents()
        pasteboard.setString("one", forType: .string)
        monitor.tick()
        await waitFor("first copy captured") {
            captured == [.text(RichPasteboardPayload(plainText: "one"))]
        }

        identity = AppIdentity(bundleIdentifier: "com.example.two")
        pasteboard.clearContents()
        pasteboard.setString("two", forType: .string)
        monitor.tick()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(captured.count, 1, "the writer app is ambiguous across an app switch")

        monitor.tick()
        pasteboard.clearContents()
        pasteboard.setString("three", forType: .string)
        monitor.tick()
        await waitFor("copy after a settled app switch") {
            captured == [
                .text(RichPasteboardPayload(plainText: "one")),
                .text(RichPasteboardPayload(plainText: "three"))
            ]
        }
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
