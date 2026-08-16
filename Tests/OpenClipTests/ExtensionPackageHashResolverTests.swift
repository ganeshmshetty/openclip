import XCTest
@testable import Core

final class ExtensionPackageHashResolverTests: XCTestCase {
    var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testOpenClipVersionDecodes() throws {
        let data = Data("""
        {"identifier":"com.t.v","name":"V","openClipVersion":"1.5.0",
         "actions":[{"title":"A","type":"url","url":"https://x.com/{query}"}]}
        """.utf8)
        let manifest = try ExtensionManifestStore.decodeManifest(from: data)
        XCTAssertEqual(manifest.openClipVersion, "1.5.0")
    }

    func testManifestHashChangesWhenScriptChanges() throws {
        let pkg = tempDir.appendingPathComponent("hash.openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        let scriptURL = pkg.appendingPathComponent("main.sh")
        try writePackage(identifier: "com.t.hash", manifestURL: manifestURL, scriptURL: scriptURL, script: "echo one")

        let manifest = ExtensionManifestStore.readManifest(at: manifestURL)!
        let before = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest))

        try "echo two".write(to: scriptURL, atomically: true, encoding: .utf8)
        let after = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest))
        XCTAssertNotEqual(before, after, "a script edit must change the package hash")
    }

    func testStandaloneScriptFileHashIsContentSensitive() throws {
        let file = tempDir.appendingPathComponent("standalone.sh")
        try "content-a".write(to: file, atomically: true, encoding: .utf8)
        let h1 = try XCTUnwrap(ExtensionPackageHashResolver.fileHash(file))
        try "content-b".write(to: file, atomically: true, encoding: .utf8)
        let h2 = try XCTUnwrap(ExtensionPackageHashResolver.fileHash(file))
        XCTAssertEqual(h1.count, 64)
        XCTAssertNotEqual(h1, h2)
    }

    @MainActor
    func testPackageHashForPackageIDFindsManifestPackage() throws {
        let pkg = tempDir.appendingPathComponent("find.openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        let scriptURL = pkg.appendingPathComponent("main.sh")
        try writePackage(identifier: "com.t.find", manifestURL: manifestURL, scriptURL: scriptURL, script: "echo find")

        let hash = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(forPackageID: "com.t.find", in: tempDir))
        XCTAssertEqual(hash, ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: ExtensionManifestStore.readManifest(at: manifestURL)!))
    }

    func testAddingReferencedScriptChangesHash() throws {
        let pkg = tempDir.appendingPathComponent("multi.openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        let scriptURL = pkg.appendingPathComponent("main.sh")
        try writePackage(identifier: "com.t.multi", manifestURL: manifestURL, scriptURL: scriptURL, script: "echo one")

        let manifest = ExtensionManifestStore.readManifest(at: manifestURL)!
        let before = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest))

        let secondScript = pkg.appendingPathComponent("aux.sh")
        try "echo two".write(to: secondScript, atomically: true, encoding: .utf8)
        let extended = ExtensionMetadata(
            identifier: manifest.identifier, name: manifest.name,
            actions: manifest.actions + [ExtensionActionMetadata(title: "B", script: "aux.sh", type: "script")],
            version: manifest.version
        )
        let after = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: extended))
        XCTAssertNotEqual(before, after, "adding a referenced script component must change the package hash")
    }

    func testUnreadableReferencedScriptIsSkippedNotFatal() throws {
        let pkg = tempDir.appendingPathComponent("skip.openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        try """
        {"identifier":"com.t.skip","name":"Pkg","actions":[
          {"title":"A","type":"script","script":"missing.sh"},
          {"title":"B","type":"script","script":"present.sh"}
        ]}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)
        try "echo present".write(to: pkg.appendingPathComponent("present.sh"), atomically: true, encoding: .utf8)

        let manifest = ExtensionManifestStore.readManifest(at: manifestURL)!
        let hash = ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest)
        XCTAssertNotNil(hash, "an unreadable referenced script must not void the package hash")
    }

    @MainActor
    func testManifestLookupByPackageID() throws {
        let pkg = tempDir.appendingPathComponent("lookup.openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        let scriptURL = pkg.appendingPathComponent("main.sh")
        try writePackage(identifier: "com.t.lookup", manifestURL: manifestURL, scriptURL: scriptURL, script: "echo lookup")

        let manifest = try XCTUnwrap(ExtensionManifestStore.manifest(forPackageID: "com.t.lookup", in: tempDir))
        XCTAssertEqual(manifest.identifier, "com.t.lookup")
        XCTAssertNil(ExtensionManifestStore.manifest(forPackageID: "com.t.missing", in: tempDir))
    }

    func testReferencedScriptEscapingViaParentTraversalIsSkipped() throws {
        let outsideScript = tempDir.appendingPathComponent("outside.sh")
        try "echo outside".write(to: outsideScript, atomically: true, encoding: .utf8)

        let pkg = tempDir.appendingPathComponent("escape.openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        try """
        {"identifier":"com.t.escape","name":"Escape","actions":[{"title":"A","type":"script","script":"../outside.sh"}]}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let manifest = ExtensionManifestStore.readManifest(at: manifestURL)!
        let hash1 = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest))

        // Modifying the outside script must not change the package hash since it was skipped
        try "echo modified".write(to: outsideScript, atomically: true, encoding: .utf8)
        let hash2 = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest))
        XCTAssertEqual(hash1, hash2, "outside script via traversal must be ignored by packageHash")
    }

    func testReferencedScriptSymlinkEscapingIsSkipped() throws {
        let outsideScript = tempDir.appendingPathComponent("outside_symlink.sh")
        try "echo outside".write(to: outsideScript, atomically: true, encoding: .utf8)

        let pkg = tempDir.appendingPathComponent("symlink.openclipext")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        let manifestURL = pkg.appendingPathComponent("openclip.json")
        let symlinkURL = pkg.appendingPathComponent("link.sh")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideScript)

        try """
        {"identifier":"com.t.symlink","name":"Symlink","actions":[{"title":"A","type":"script","script":"link.sh"}]}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)

        let manifest = ExtensionManifestStore.readManifest(at: manifestURL)!
        let hash1 = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest))

        // Modifying the outside script targeted by symlink must not change the package hash
        try "echo modified".write(to: outsideScript, atomically: true, encoding: .utf8)
        let hash2 = try XCTUnwrap(ExtensionPackageHashResolver.packageHash(manifestURL: manifestURL, manifest: manifest))
        XCTAssertEqual(hash1, hash2, "outside script via symlink must be ignored by packageHash")
    }

    private func writePackage(identifier: String, manifestURL: URL, scriptURL: URL, script: String) throws {
        try """
        {"identifier":"\(identifier)","name":"Pkg","actions":[{"title":"A","type":"script","script":"main.sh"}]}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    }
}