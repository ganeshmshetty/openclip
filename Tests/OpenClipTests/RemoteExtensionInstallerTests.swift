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
}
