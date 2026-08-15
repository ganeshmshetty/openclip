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

    private func writePackage(identifier: String, manifestURL: URL, scriptURL: URL, script: String) throws {
        try """
        {"identifier":"\(identifier)","name":"Pkg","actions":[{"title":"A","type":"script","script":"main.sh"}]}
        """.write(to: manifestURL, atomically: true, encoding: .utf8)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    }
}