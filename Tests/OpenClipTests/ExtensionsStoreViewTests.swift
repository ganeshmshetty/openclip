import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionsStoreViewTests: XCTestCase {
    @MainActor
    func testExtensionsStoreViewModelInitialState() {
        let viewModel = ExtensionsStoreViewModel()
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertEqual(viewModel.selectedCategory, "All")
        XCTAssertTrue(viewModel.extensions.isEmpty)
        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertFalse(viewModel.isLoading)
    }
}
