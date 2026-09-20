// FileOutputTests.swift
// OpenClipTests

import XCTest
import AppKit
@testable import Core
@testable import OpenClip

final class FileOutputTests: XCTestCase {
    private var tempDir: URL!
    private var isolatedSettings: MemorySettingsStore!

    /// Resets shared state and creates an isolated directory and settings store for each test.
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("OpenClipFileOutputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        isolatedSettings = MemorySettingsStore()
    }

    /// Removes the isolated test directory after each test.
    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - FileOutputPayload Tests

    /// Verifies that a payload derives its display name, extension, and image status from its URL.
    func testFileOutputPayloadDisplayNameAndExtension() {
        let fileURL = tempDir.appendingPathComponent("document.pdf")
        let payload = FileOutputPayload(url: fileURL)

        XCTAssertEqual(payload.displayName, "document.pdf")
        XCTAssertEqual(payload.fileExtension, "pdf")
        XCTAssertFalse(payload.isImage)
    }

    /// Verifies that an explicit display filename controls extension and image detection.
    func testFileOutputPayloadExplicitFilename() {
        let fileURL = tempDir.appendingPathComponent("random-temp-1234")
        let payload = FileOutputPayload(url: fileURL, filename: "my-photo.PNG")

        XCTAssertEqual(payload.displayName, "my-photo.PNG")
        XCTAssertEqual(payload.fileExtension, "png")
        XCTAssertTrue(payload.isImage)
    }

    /// Verifies the supported image-extension allowlist and representative non-image extensions.
    func testFileOutputPayloadImageExtensions() {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "svg", "icns", "bmp", "tiff", "heic"]
        for ext in imageExtensions {
            let payload = FileOutputPayload(url: tempDir.appendingPathComponent("img.\(ext)"))
            XCTAssertTrue(payload.isImage, "Extension .\(ext) should be recognized as an image")
        }

        let nonImageExtensions = ["txt", "pdf", "zip", "mp3", "mov", "json", "swift"]
        for ext in nonImageExtensions {
            let payload = FileOutputPayload(url: tempDir.appendingPathComponent("doc.\(ext)"))
            XCTAssertFalse(payload.isImage, "Extension .\(ext) should not be recognized as an image")
        }
    }

    // MARK: - ActionResult Properties

    /// Verifies dismissal and toast properties for preview, copy, and save file results.
    func testActionResultFileDismissAndToastProperties() {
        let fileURL = tempDir.appendingPathComponent("sample.txt")
        let fileResult = ActionResult.file(FileOutputPayload(url: fileURL))
        let copyFileResult = ActionResult.copyFile(fileURL)
        let saveFileResult = ActionResult.saveFile(fileURL)

        XCTAssertFalse(fileResult.dismissesPopup, "File result should keep popup open for preview")
        XCTAssertFalse(fileResult.containsToast, "File result does not contain inline toast")

        XCTAssertTrue(copyFileResult.dismissesPopup, "Copy file result should dismiss popup")
        XCTAssertTrue(saveFileResult.dismissesPopup, "Save file result should dismiss popup")
    }

    // MARK: - ActionResultDelivery Resolution

    /// Verifies that secondary-click delivery converts a file preview into a copy operation.
    func testActionResultDeliveryFileResolvesToCopyOnSecondaryClick() {
        let fileURL = tempDir.appendingPathComponent("sample.txt")
        let payload = FileOutputPayload(url: fileURL)

        // Primary click keeps .file
        let (primaryResolved, primaryToast) = ActionResultDelivery.resolve(
            raw: .file(payload),
            clickIntent: .primary,
            canPaste: true,
            delivery: .none
        )
        if case .file(let resPayload) = primaryResolved {
            XCTAssertEqual(resPayload.url, fileURL)
        } else {
            XCTFail("Expected .file on primary click")
        }
        XCTAssertNil(primaryToast)

        // Secondary click resolves to .copyFile
        let (secondaryResolved, secondaryToast) = ActionResultDelivery.resolve(
            raw: .file(payload),
            clickIntent: .secondary,
            canPaste: true,
            delivery: .none
        )
        if case .copyFile(let copyURL) = secondaryResolved {
            XCTAssertEqual(copyURL, fileURL)
        } else {
            XCTFail("Expected .copyFile on secondary click")
        }
        XCTAssertEqual(secondaryToast?.message, "Copied File")
    }

    /// Verifies the companion toasts emitted for explicit copy and save delivery.
    func testActionResultDeliveryToastsForCopyFileAndSaveFile() {
        let fileURL = tempDir.appendingPathComponent("sample.txt")

        let (_, copyToast) = ActionResultDelivery.resolve(
            raw: .copyFile(fileURL),
            clickIntent: .primary,
            canPaste: true,
            delivery: .none
        )
        XCTAssertEqual(copyToast?.message, "Copied File")

        let (_, saveToast) = ActionResultDelivery.resolve(
            raw: .saveFile(fileURL),
            clickIntent: .primary,
            canPaste: true,
            delivery: .none
        )
        XCTAssertEqual(saveToast?.message, "File Saved")
    }

    // MARK: - ShellResultMapper File Detection & JSON Parsing

    /// Verifies plain-text file detection for paths, file URLs, missing files, and ordinary output.
    func testDetectFileResultExistingFile() throws {
        let testFile = tempDir.appendingPathComponent("test_output.txt")
        try "Hello File".write(to: testFile, atomically: true, encoding: .utf8)

        // Absolute path
        let detected = ShellResultMapper.detectFileResult(from: testFile.path)
        XCTAssertNotNil(detected)
        if case .file(let payload) = detected {
            XCTAssertEqual(payload.url.path, testFile.path)
            XCTAssertEqual(payload.displayName, "test_output.txt")
        } else {
            XCTFail("Expected .file result")
        }

        // File URL format
        let detectedURL = ShellResultMapper.detectFileResult(from: "file://" + testFile.path)
        XCTAssertNotNil(detectedURL)

        // Non-existent path returns nil
        let nonExistent = ShellResultMapper.detectFileResult(from: "/tmp/non_existent_openclip_\(UUID().uuidString).txt")
        XCTAssertNil(nonExistent)

        // Arbitrary stdout text returns nil
        let arbitraryText = ShellResultMapper.detectFileResult(from: "This is just ordinary output text")
        XCTAssertNil(arbitraryText)
    }

    /// Verifies structured shell output mapping for preview, copy, and save file actions.
    func testShellResultMapperFileJSON() throws {
        let testFile = tempDir.appendingPathComponent("report.pdf")
        try "dummy pdf".write(to: testFile, atomically: true, encoding: .utf8)

        // File effect preview
        let jsonPreview = """
        {"type": "file", "path": "\(testFile.path)"}
        """
        let resultPreview = ShellResultMapper.actionResult(from: jsonPreview, actionID: "test")
        if case .file(let payload) = resultPreview {
            XCTAssertEqual(payload.url.path, testFile.path)
        } else {
            XCTFail("Expected .file result from JSON")
        }

        // File effect copy
        let jsonCopy = """
        {"type": "copyFile", "path": "\(testFile.path)"}
        """
        let resultCopy = ShellResultMapper.actionResult(from: jsonCopy, actionID: "test")
        if case .copyFile(let url) = resultCopy {
            XCTAssertEqual(url.path, testFile.path)
        } else {
            XCTFail("Expected .copyFile result from JSON")
        }

        // File effect save
        let jsonSave = """
        {"type": "saveFile", "path": "\(testFile.path)"}
        """
        let resultSave = ShellResultMapper.actionResult(from: jsonSave, actionID: "test")
        if case .saveFile(let url) = resultSave {
            XCTAssertEqual(url.path, testFile.path)
        } else {
            XCTFail("Expected .saveFile result from JSON")
        }
    }

    /// Verifies that base64 file output is decoded, cached, and mapped to its requested action.
    func testShellResultMapperBase64FileData() throws {
        let rawContent = "Base64 encoded file content"
        let base64 = rawContent.data(using: .utf8)!.base64EncodedString()

        let json = """
        {"type": "file", "data": "\(base64)", "filename": "generated.txt", "action": "save"}
        """
        let result = ShellResultMapper.actionResult(from: json, actionID: "test")
        if case .saveFile(let url) = result {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            let readBack = try String(contentsOf: url, encoding: .utf8)
            XCTAssertEqual(readBack, rawContent)
            // Cleanup
            try? FileManager.default.removeItem(at: url)
        } else {
            XCTFail("Expected .saveFile result for base64 file data with action save")
        }
    }

    // MARK: - ActionResultHandler Tests

    /// Verifies that copying a file writes a file URL to the configured pasteboard.
    @MainActor
    func testActionResultHandlerCopyFileWritesToPasteboard() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-File-\(UUID().uuidString)"))
        let handler = DefaultActionResultHandler(settingsStore: isolatedSettings, pasteboard: isolatedPasteboard)

        let testFile = tempDir.appendingPathComponent("copy_test.png")
        try "image bytes".write(to: testFile, atomically: true, encoding: .utf8)

        try await handler.handle(ActionResult.copyFile(testFile), in: nil)

        // Check pasteboard item
        guard let items = isolatedPasteboard.pasteboardItems, let first = items.first else {
            XCTFail("Pasteboard items must not be empty")
            return
        }

        // NSPasteboard writes fileURL as file-url string type
        let fileURLType = NSPasteboard.PasteboardType("public.file-url")
        let urlString = first.string(forType: fileURLType)
        XCTAssertNotNil(urlString)
        XCTAssertTrue(urlString?.contains("copy_test.png") == true)
    }

    /// Verifies that saving a file uses the configured destination directory.
    @MainActor
    func testActionResultHandlerSaveFileSavesToConfiguredDirectory() async throws {
        let customSaveDir = tempDir.appendingPathComponent("CustomSaves")
        try FileManager.default.createDirectory(at: customSaveDir, withIntermediateDirectories: true)
        isolatedSettings.set(.fileSaveLocation, value: customSaveDir.path)

        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-File-\(UUID().uuidString)"))
        let handler = DefaultActionResultHandler(settingsStore: isolatedSettings, pasteboard: isolatedPasteboard)

        let sourceFile = tempDir.appendingPathComponent("downloaded_doc.txt")
        try "important data".write(to: sourceFile, atomically: true, encoding: .utf8)

        try await handler.handle(ActionResult.saveFile(sourceFile), in: nil)

        let destinationFile = customSaveDir.appendingPathComponent("downloaded_doc.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFile.path))
        let content = try String(contentsOf: destinationFile, encoding: .utf8)
        XCTAssertEqual(content, "important data")
    }

    /// Verifies that saving preserves an existing file and creates a collision-safe destination.
    @MainActor
    func testActionResultHandlerSaveFileHandlesNameCollisions() async throws {
        let customSaveDir = tempDir.appendingPathComponent("CollisionSaves")
        try FileManager.default.createDirectory(at: customSaveDir, withIntermediateDirectories: true)
        isolatedSettings.set(.fileSaveLocation, value: customSaveDir.path)

        // Pre-create file with same name
        let existingFile = customSaveDir.appendingPathComponent("report.txt")
        try "version 1".write(to: existingFile, atomically: true, encoding: .utf8)

        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-File-\(UUID().uuidString)"))
        let handler = DefaultActionResultHandler(settingsStore: isolatedSettings, pasteboard: isolatedPasteboard)

        let sourceFile = tempDir.appendingPathComponent("report.txt")
        try "version 2".write(to: sourceFile, atomically: true, encoding: .utf8)

        try await handler.handle(ActionResult.saveFile(sourceFile), in: nil)

        // Original report.txt should still exist with "version 1"
        let origContent = try String(contentsOf: existingFile, encoding: .utf8)
        XCTAssertEqual(origContent, "version 1")

        // New file should be saved as report (1).txt
        let collisionFile = customSaveDir.appendingPathComponent("report (1).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: collisionFile.path), "Collision file should be renamed to 'report (1).txt'")
        let newContent = try String(contentsOf: collisionFile, encoding: .utf8)
        XCTAssertEqual(newContent, "version 2")
    }

    /// Verifies MIME-based image detection and extension fallback behavior.
    func testFileOutputPayloadMimeTypeImageDetection() {
        let pdfFile = tempDir.appendingPathComponent("image.bin")
        let pngMimePayload = FileOutputPayload(url: pdfFile, mimeType: "image/png")
        XCTAssertTrue(pngMimePayload.isImage, "MIME image/png should be recognized as image")

        let svgMimePayload = FileOutputPayload(url: pdfFile, mimeType: "image/svg+xml")
        XCTAssertTrue(svgMimePayload.isImage, "MIME image/svg+xml should be recognized as image")

        let upperMimePayload = FileOutputPayload(url: pdfFile, mimeType: "IMAGE/JPEG")
        XCTAssertTrue(upperMimePayload.isImage, "Case-insensitive MIME should be recognized as image")

        let octetStreamImg = FileOutputPayload(url: tempDir.appendingPathComponent("photo.PNG"), mimeType: "application/octet-stream")
        XCTAssertTrue(octetStreamImg.isImage, "Fallback to valid image extension when MIME is generic")

        let pdfPayload = FileOutputPayload(url: tempDir.appendingPathComponent("doc.pdf"), mimeType: "application/pdf")
        XCTAssertFalse(pdfPayload.isImage, "application/pdf should not be recognized as image")
    }

    /// Verifies that embedded output filenames cannot escape the managed output directory.
    func testShellResultMapperRejectsPathTraversalInFilename() throws {
        let b64 = Data("hello content".utf8).base64EncodedString()
        let jsonTraversal = """
        {"type": "file", "data": "\(b64)", "filename": "../../traversal.txt"}
        """
        let result = ShellResultMapper.actionResult(from: jsonTraversal, actionID: "test")
        guard case .file(let payload) = result else {
            return XCTFail("Expected .file result")
        }
        // Filename should be sanitized to traversal.txt, not escaping temp directory
        XCTAssertEqual(payload.displayName, "traversal.txt")
        XCTAssertEqual(payload.url.deletingLastPathComponent().standardizedFileURL.path, Constants.outputsDirectory.standardizedFileURL.path)
        XCTAssertFalse(payload.url.path.contains(".."))
    }

    /// Verifies that missing file references produce an error result.
    func testShellResultMapperRejectsNonExistentFiles() {
        let missingPath = "/tmp/does_not_exist_\(UUID().uuidString).pdf"

        let fileJson = """
        {"type": "file", "path": "\(missingPath)"}
        """
        let result1 = ShellResultMapper.actionResult(from: fileJson, actionID: "test")
        guard case .toast(let feedback1) = result1 else {
            return XCTFail("Expected .toast error for non-existent file path")
        }
        XCTAssertEqual(feedback1.message, "File not found")
        XCTAssertEqual(feedback1.style, .error)

        let copyJson = """
        {"type": "copyFile", "path": "\(missingPath)"}
        """
        let result2 = ShellResultMapper.actionResult(from: copyJson, actionID: "test")
        guard case .toast(let feedback2) = result2 else {
            return XCTFail("Expected .toast error for non-existent copy file path")
        }
        XCTAssertEqual(feedback2.message, "File not found")
        XCTAssertEqual(feedback2.style, .error)
    }

    /// Verifies that replacement actions preserve returned paths as text rather than file previews.
    func testCustomActionDoesNotInterceptFilePathWhenReplaceSelectionIsTrue() async throws {
        let testFile = tempDir.appendingPathComponent("output_path.txt")
        try "file content".write(to: testFile, atomically: true, encoding: .utf8)

        let actionReplace = CustomAction(
            id: "com.test.replace",
            title: "Replace with Path",
            iconName: "terminal",
            type: .shellScript(script: "echo '\(testFile.path)'", replaceSelection: true)
        )

        let selection = SelectionContext(
            text: "input",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "TestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection)

        let result = try await actionReplace.perform(context)
        // Since replaceSelection is true, the action wants to replace the selection with the output path string,
        // so it must NOT be hijacked into a .file result card!
        guard case .paste(let pastedText) = result else {
            return XCTFail("Expected .paste when replaceSelection is true, got \(result)")
        }
        XCTAssertEqual(pastedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), testFile.path)
    }

    /// Verifies JavaScript object returns for file preview, save, and missing-file errors.
    func testJSHostFileReturnActions() async throws {
        let testFile = tempDir.appendingPathComponent("js_output.txt")
        try "JS file content".write(to: testFile, atomically: true, encoding: .utf8)

        let host = OpenClipJSHost()
        let selection = SelectionContext(
            text: "input",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "TestApp"),
            cursorPosition: .zero,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection)
        let optionStore = SecretActionOptionStore()

        // 1. Returning { type: "file", path: ... }
        let script1 = "function action(text) { return { type: 'file', path: '\(testFile.path)' }; }"
        let req1 = OpenClipJSHost.Request(
            actionID: "test.js.file",
            scriptCode: script1,
            context: context,
            options: [],
            optionStore: optionStore,
            rules: ExtensionActionRules()
        )
        let res1 = try await host.run(req1)
        guard case .file(let payload) = res1 else {
            return XCTFail("Expected .file, got \(res1)")
        }
        XCTAssertEqual(payload.url.path, testFile.path)

        // 2. Returning { type: "file", action: "save", path: ... }
        let script2 = "function action(text) { return { type: 'file', action: 'save', path: '\(testFile.path)' }; }"
        let req2 = OpenClipJSHost.Request(
            actionID: "test.js.save",
            scriptCode: script2,
            context: context,
            options: [],
            optionStore: optionStore,
            rules: ExtensionActionRules()
        )
        let res2 = try await host.run(req2)
        guard case .saveFile(let savedURL) = res2 else {
            return XCTFail("Expected .saveFile, got \(res2)")
        }
        XCTAssertEqual(savedURL.path, testFile.path)

        // 3. Returning non-existent path
        let script3 = "function action(text) { return { type: 'file', path: '/tmp/non_existent_\(UUID().uuidString).txt' }; }"
        let req3 = OpenClipJSHost.Request(
            actionID: "test.js.missing",
            scriptCode: script3,
            context: context,
            options: [],
            optionStore: optionStore,
            rules: ExtensionActionRules()
        )
        let res3 = try await host.run(req3)
        guard case .toast(let feedback) = res3 else {
            return XCTFail("Expected .toast error, got \(res3)")
        }
        XCTAssertEqual(feedback.message, "File not found")
        XCTAssertEqual(feedback.style.rawValue, "error")
    }

    // MARK: - Image Output UX & Sizing Tests

    /// Verifies that copying a real image file writes both NSURL and rich image representations (PNG and TIFF).
    @MainActor
    func testActionResultHandlerCopyImageFileWritesDualFormatPasteboard() async throws {
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("OpenClipTest-DualImage-\(UUID().uuidString)"))
        let handler = DefaultActionResultHandler(settingsStore: isolatedSettings, pasteboard: isolatedPasteboard)

        let testFile = tempDir.appendingPathComponent("image_copy_test.png")
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 16,
            pixelsHigh: 16,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let pngData = rep.representation(using: .png, properties: [:])!
        try pngData.write(to: testFile)

        try await handler.handle(ActionResult.copyFile(testFile), in: nil)

        // Verify URL is present on pasteboard
        let fileURLType = NSPasteboard.PasteboardType("public.file-url")
        let urlString = isolatedPasteboard.string(forType: fileURLType)
        XCTAssertNotNil(urlString)
        XCTAssertTrue(urlString?.contains("image_copy_test.png") == true)

        // Verify PNG and TIFF are also available on pasteboard for web/rich-text paste destinations
        let pasteboardPNG = isolatedPasteboard.data(forType: .png)
        let pasteboardTIFF = isolatedPasteboard.data(forType: .tiff)
        XCTAssertNotNil(pasteboardPNG, "Pasteboard should have PNG data for image file copy")
        XCTAssertNotNil(pasteboardTIFF, "Pasteboard should have TIFF data for image file copy")
    }

    /// Verifies that imageCardSize computes balanced dimensions for small, portrait, landscape, and square images.
    func testResultCardImageCardSizeAspectRatios() {
        // Fallback for nil image
        let fallback = ResultCardView.imageCardSize(imageSize: nil, userSize: nil, isUserSized: false)
        XCTAssertEqual(fallback, CGSize(width: 370.0, height: 290.0))

        // Small icon (48x48) -> compact card
        let smallIcon = ResultCardView.imageCardSize(imageSize: CGSize(width: 48, height: 48), userSize: nil, isUserSized: false)
        XCTAssertEqual(smallIcon, CGSize(width: 320.0, height: 240.0))

        // Portrait image (9:16 ratio, e.g. 1080x1920) -> tall card
        let portrait = ResultCardView.imageCardSize(imageSize: CGSize(width: 1080, height: 1920), userSize: nil, isUserSized: false)
        XCTAssertEqual(portrait.height, 380.0)
        XCTAssertEqual(portrait.width, 320.0)

        // Landscape image (16:9 ratio, e.g. 1920x1080) -> wider card
        let landscape = ResultCardView.imageCardSize(imageSize: CGSize(width: 1920, height: 1080), userSize: nil, isUserSized: false)
        XCTAssertEqual(landscape.height, 275.0)
        XCTAssertEqual(landscape.width, 370.0)

        // Square image (1:1 ratio, e.g. 1024x1024) -> balanced card
        let square = ResultCardView.imageCardSize(imageSize: CGSize(width: 1024, height: 1024), userSize: nil, isUserSized: false)
        XCTAssertEqual(square.width, 350.0)
        XCTAssertEqual(square.height, 330.0)

        // Manually resized by user -> preserves verbatim size
        let customUser = CGSize(width: 500, height: 450)
        let userSized = ResultCardView.imageCardSize(imageSize: CGSize(width: 1080, height: 1920), userSize: customUser, isUserSized: true)
        XCTAssertEqual(userSized, customUser)
    }
}
