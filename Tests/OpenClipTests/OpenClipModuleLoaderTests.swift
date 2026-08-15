import XCTest
@testable import OpenClip

final class OpenClipModuleLoaderTests: XCTestCase {
    /// Creates a temp "package root" plus a sibling temp dir (for outside-package fixtures).
    private func makeScratch() throws -> (root: URL, outside: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("loader-\(UUID().uuidString)")
        let root = base.appendingPathComponent("package")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return (root, base)
    }

    private func write(_ text: String, to relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testResolvesExplicitExtension() throws {
        let (root, _) = try makeScratch()
        try write("module.exports = 'hi';", to: "lib/helper.js", in: root)
        let module = try OpenClipModuleLoader.load(specifier: "./lib/helper.js", requiringDirectory: root, packageRoot: root)
        XCTAssertEqual(module.source, "module.exports = 'hi';")
        // Loader normalizes via resolvingSymlinksInPath (like isPathSafe), which rewrites
        // /var -> /private/var on macOS, so compare path suffixes, not URL equality.
        XCTAssertTrue(module.directoryURL.path.hasSuffix("/package/lib"))
    }

    func testAppendsJSExtension() throws {
        let (root, _) = try makeScratch()
        try write("module.exports = 'x';", to: "lib/helper.js", in: root)
        let module = try OpenClipModuleLoader.load(specifier: "./lib/helper", requiringDirectory: root, packageRoot: root)
        XCTAssertEqual(module.source, "module.exports = 'x';")
    }

    func testResolvesDirectoryToIndexJS() throws {
        let (root, _) = try makeScratch()
        try write("module.exports = 'indexed';", to: "lib/index.js", in: root)
        let module = try OpenClipModuleLoader.load(specifier: "./lib", requiringDirectory: root, packageRoot: root)
        XCTAssertEqual(module.source, "module.exports = 'indexed';")
    }

    func testResolvesNestedRelativeToRequiringDirectory() throws {
        let (root, _) = try makeScratch()
        try write("module.exports = 'sib';", to: "sub/sibling.js", in: root)
        let module = try OpenClipModuleLoader.load(specifier: "./sibling.js", requiringDirectory: root.appendingPathComponent("sub"), packageRoot: root)
        XCTAssertEqual(module.source, "module.exports = 'sib';")
    }

    func testRejectsParentEscape() throws {
        let (root, outside) = try makeScratch()
        try write("secret", to: "secret.txt", in: outside)
        do {
            _ = try OpenClipModuleLoader.load(specifier: "../secret.txt", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected outsidePackage")
        } catch let error as ModuleResolutionError {
            XCTAssertEqual(error, .outsidePackage("../secret.txt"))
        }
    }

    func testRejectsAbsolutePath() throws {
        let (root, _) = try makeScratch()
        do {
            _ = try OpenClipModuleLoader.load(specifier: "/etc/passwd", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected absolutePath")
        } catch let error as ModuleResolutionError {
            XCTAssertEqual(error, .absolutePath("/etc/passwd"))
        }
    }

    func testRejectsNodeBuiltinWithExplicitMessage() throws {
        let (root, _) = try makeScratch()
        do {
            _ = try OpenClipModuleLoader.load(specifier: "fs", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected bareSpecifier")
        } catch let error as ModuleResolutionError {
            XCTAssertEqual(error, .bareSpecifier("fs"))
            XCTAssertTrue(error.message.contains("Node builtin"))
            XCTAssertTrue(error.message.contains("fs"))
        }
    }

    func testRejectsBareSpecifierWithBundleHint() throws {
        let (root, _) = try makeScratch()
        do {
            _ = try OpenClipModuleLoader.load(specifier: "lodash", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected bareSpecifier")
        } catch let error as ModuleResolutionError {
            XCTAssertEqual(error, .bareSpecifier("lodash"))
            XCTAssertTrue(error.message.contains("bundle"))
        }
    }

    func testRejectsSymlinkEscape() throws {
        let (root, outside) = try makeScratch()
        try write("secret", to: "secret.txt", in: outside)
        let link = root.appendingPathComponent("leak.js")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.appendingPathComponent("secret.txt"))
        do {
            _ = try OpenClipModuleLoader.load(specifier: "./leak.js", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected outsidePackage")
        } catch let error as ModuleResolutionError {
            XCTAssertEqual(error, .outsidePackage("./leak.js"))
        }
    }

    func testNotFoundReportsTriedCandidates() throws {
        let (root, _) = try makeScratch()
        do {
            _ = try OpenClipModuleLoader.load(specifier: "./nope", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected notFound")
        } catch let error as ModuleResolutionError {
            guard case .notFound(_, let tried) = error else { return XCTFail("Expected notFound, got \(error)") }
            XCTAssertTrue(tried.contains { $0.hasSuffix("package/nope") })
            XCTAssertTrue(tried.contains { $0.hasSuffix("package/nope.js") })
        }
    }

    func testEmptyFileIsValidModule() throws {
        let (root, _) = try makeScratch()
        try write("", to: "empty.js", in: root)
        let module = try OpenClipModuleLoader.load(specifier: "./empty.js", requiringDirectory: root, packageRoot: root)
        XCTAssertEqual(module.source, "")
    }
}