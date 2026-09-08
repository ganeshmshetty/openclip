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
        // The loader uses resolvingSymlinksInPath (same as isPathSafe). That call rewrites the
        // /private prefix of temp paths. The rewrite direction changes with Foundation version.
        // Compare path suffixes. Do not compare URL equality.
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

    // MARK: - Containment after the `.js` / `index.js` fallbacks (issue #39)

    /// `leak` does not exist. The pre-check passes. `leak.js` is a symlink out of the package.
    func testRejectsSymlinkEscapeViaAppendedExtension() throws {
        let (root, outside) = try makeScratch()
        try write("module.exports = 'LEAKED';", to: "secret.js", in: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("leak.js"),
            withDestinationURL: outside.appendingPathComponent("secret.js")
        )
        do {
            let module = try OpenClipModuleLoader.load(specifier: "./leak", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected outsidePackage, but loaded \(module.url.path) with source \(module.source)")
        } catch let error as ModuleResolutionError {
            XCTAssertEqual(error, .outsidePackage("./leak"))
        }
    }

    /// `dir` is a real directory in the package. The pre-check passes. `dir/index.js` points out.
    func testRejectsSymlinkEscapeViaDirectoryIndex() throws {
        let (root, outside) = try makeScratch()
        try write("module.exports = 'LEAKED';", to: "secret.js", in: outside)
        let dir = root.appendingPathComponent("dir")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("index.js"),
            withDestinationURL: outside.appendingPathComponent("secret.js")
        )
        do {
            let module = try OpenClipModuleLoader.load(specifier: "./dir", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected outsidePackage, but loaded \(module.url.path) with source \(module.source)")
        } catch let error as ModuleResolutionError {
            XCTAssertEqual(error, .outsidePackage("./dir"))
        }
    }

    /// In-package symlinks stay valid. The module reports the real path (Node default).
    /// The per-run cache and `__dirname` then see one canonical file.
    func testResolvesInPackageSymlinkAndReturnsRealPath() throws {
        let (root, _) = try makeScratch()
        try write("module.exports = 'real';", to: "lib/real.js", in: root)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("alias.js"),
            withDestinationURL: root.appendingPathComponent("lib/real.js")
        )
        let module = try OpenClipModuleLoader.load(specifier: "./alias", requiringDirectory: root, packageRoot: root)
        XCTAssertEqual(module.source, "module.exports = 'real';")
        XCTAssertTrue(module.url.path.hasSuffix("/package/lib/real.js"), module.url.path)
        XCTAssertTrue(module.directoryURL.path.hasSuffix("/package/lib"), module.directoryURL.path)
        let direct = try OpenClipModuleLoader.load(specifier: "./lib/real.js", requiringDirectory: root, packageRoot: root)
        XCTAssertEqual(module.url, direct.url)
    }

    /// An in-package directory symlink stays valid. Resolution uses the real directory.
    func testResolvesThroughInPackageSymlinkedDirectory() throws {
        let (root, _) = try makeScratch()
        try write("module.exports = 'x';", to: "real/x.js", in: root)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("lib"),
            withDestinationURL: root.appendingPathComponent("real")
        )
        let module = try OpenClipModuleLoader.load(specifier: "./lib/x", requiringDirectory: root, packageRoot: root)
        XCTAssertEqual(module.source, "module.exports = 'x';")
        XCTAssertTrue(module.directoryURL.path.hasSuffix("/package/real"), module.directoryURL.path)
    }

    /// A dangling link is not found. `fileExists` follows the link and finds no file.
    func testDanglingSymlinkIsNotFound() throws {
        let (root, outside) = try makeScratch()
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("leak.js"),
            withDestinationURL: outside.appendingPathComponent("missing.js")
        )
        do {
            _ = try OpenClipModuleLoader.load(specifier: "./leak", requiringDirectory: root, packageRoot: root)
            XCTFail("Expected notFound")
        } catch let error as ModuleResolutionError {
            guard case .notFound(_, let tried) = error else { return XCTFail("Expected notFound, got \(error)") }
            XCTAssertTrue(tried.contains { $0.hasSuffix("package/leak.js") })
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