import XCTest
@testable import Core
@testable import OpenClip

final class RemoteExtensionInstallerTests: XCTestCase {
    func testValidateDestinationPathPreventsZipSlip() {
        let targetDir = URL(fileURLWithPath: "/Users/test/.openclip/extensions")
        let validPath = URL(fileURLWithPath: "/Users/test/.openclip/extensions/my_extension.openclipext")
        let invalidPath = URL(fileURLWithPath: "/Users/test/.openclip/extensions/../../etc/passwd")
        
        XCTAssertTrue(RemoteExtensionInstaller.isPathSafe(destinationURL: validPath, baseDirectory: targetDir))
        XCTAssertFalse(RemoteExtensionInstaller.isPathSafe(destinationURL: invalidPath, baseDirectory: targetDir))
    }

    func testValidateDestinationPathRejectsPrefixSibling() {
        let targetDir = URL(fileURLWithPath: "/Users/test/.openclip/extensions")
        let sibling = URL(fileURLWithPath: "/Users/test/.openclip/extensions2/my_extension.openclipext")
        let baseFile = URL(fileURLWithPath: "/Users/test/.openclip/extensions")
        
        XCTAssertFalse(RemoteExtensionInstaller.isPathSafe(destinationURL: sibling, baseDirectory: targetDir))
        XCTAssertTrue(RemoteExtensionInstaller.isPathSafe(destinationURL: baseFile, baseDirectory: targetDir))
    }

    func testAllowsStoreHostsAndOfficialGitHubRelease() {
        XCTAssertTrue(RemoteExtensionInstaller.isAllowedSource(URL(string: "https://www.getopenclip.app/packages/test.zip")!))
        XCTAssertTrue(RemoteExtensionInstaller.isAllowedSource(URL(string: "https://getopenclip.app/packages/test.zip")!))
        XCTAssertTrue(RemoteExtensionInstaller.isAllowedSource(URL(string: "https://github.com/ganeshmshetty/openclip-extensions/releases/download/com.test@1.0.0/Test.openclipext.zip")!))
    }

    func testRejectsArbitraryGitHubRepositoryAndRawHost() {
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(URL(string: "https://github.com/attacker/repo/releases/download/v1/evil.zip")!))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(URL(string: "https://raw.githubusercontent.com/ganeshmshetty/openclip-extensions/main/evil.zip")!))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(URL(string: "https://getopenclip.vercel.app/packages/test.zip")!))
    }

    func testRejectsNonHTTPSAndNonDefaultPort() {
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(URL(string: "http://www.getopenclip.app/packages/test.zip")!))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(URL(string: "https://github.com:8443/ganeshmshetty/openclip-extensions/releases/download/v1/test.zip")!))
    }

    func testRejectsDotSegmentAndEncodedTraversal() {
        let base = "https://github.com/ganeshmshetty/openclip-extensions/releases/download/"
        let literal = URL(string: base + "../../attacker/evil/releases/download/v1/evil.zip")!
        let encoded = URL(string: base + "%2e%2e/%2e%2e/attacker/evil/releases/download/v1/evil.zip")!
        let doubleEncoded = URL(string: base + "%252e%252e/%252e%252e/attacker/evil/releases/download/v1/evil.zip")!

        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(literal))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(encoded))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(doubleEncoded))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedRedirect(literal, allowsGitHubAssets: true))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedRedirect(encoded, allowsGitHubAssets: true))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedRedirect(doubleEncoded, allowsGitHubAssets: true))
    }

    func testGitHubAssetRedirectsRequireGitHubReleaseSource() {
        let asset = URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/test.zip")!
        XCTAssertTrue(RemoteExtensionInstaller.isAllowedRedirect(asset, allowsGitHubAssets: true))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedRedirect(asset, allowsGitHubAssets: false))
        XCTAssertFalse(RemoteExtensionInstaller.isAllowedSource(asset))
        XCTAssertTrue(RemoteExtensionInstaller.isAllowedRedirect(
            URL(string: "https://www.getopenclip.app/packages/test.zip")!,
            allowsGitHubAssets: false
        ))
    }
}
