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
}
