import XCTest
@testable import OpenClip

@MainActor
final class InstalledAppsScannerTests: XCTestCase {
    func testScanInstalledAppsReturnsApps() async {
        let scanner = InstalledAppsScanner()
        let apps = await scanner.scanInstalledApps()
        
        XCTAssertFalse(apps.isEmpty, "InstalledAppsScanner should find at least one installed application in /Applications")
        
        // Ensure common system apps or standard apps like Safari/Finder or Xcode exist in list
        let containsApp = apps.contains { app in
            app.bundleIdentifier.contains("apple") || app.bundleIdentifier.contains("com.")
        }
        XCTAssertTrue(containsApp)
    }
}
