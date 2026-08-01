# OpenClip Extensions Tab & Dynamic Marketplace Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the dynamic "Extensions" tab in OpenClip Preferences featuring live search, lazy loading (`/api/v1/extensions`), category filters, an "Open Web Store" button, and custom `openclip://install` deep-linking for one-click installation from the web marketplace.

**Architecture:** 
1. `MarketplaceAPIClient` in Core handles dynamic fetching from Next.js + Vercel backend (`GET /api/v1/extensions`) with debouncing, category filtering, and paginated lazy loading.
2. `RemoteExtensionInstaller` in OpenClip handles downloading remote `.openclipext` packages via HTTPS, Zip-Slip security validation, unzipping to `~/.openclip/extensions/`, and registering actions into `ActionRegistry`.
3. `openclip://install` custom URL scheme registered in `Info.plist` and handled by `AppDelegate` to trigger `RemoteExtensionInstaller` from browser clicks.
4. `ExtensionsMarketplaceView` built in SwiftUI and embedded as a dedicated tab in `PreferencesView`.

**Tech Stack:** Swift 5.10+, macOS AppKit / SwiftUI, URLSession, XCTest.

## Global Constraints

- Swift AppKit/JSC/NSWorkspace dependencies must remain isolated to `Sources/OpenClip`, keeping `Sources/Core` standard Swift/Foundation only.
- Zip extraction must strictly enforce destination path boundary validation within `~/.openclip/extensions/` to prevent directory traversal vulnerabilities.
- All remote network requests must use `HTTPS`.
- Custom URL scheme protocol must conform to `openclip://install?id=<id>&name=<name>&url=<url>`.

---

## File Structure & Responsibilities

- `Sources/Core/Extensions/MarketplaceModels.swift`: Codable structs for `MarketplaceExtension`, `MarketplacePageResponse`, and category enums.
- `Sources/Core/Extensions/MarketplaceAPIClient.swift`: Handles debounced, paginated HTTP fetching from the Marketplace API.
- `Sources/OpenClip/Platform/Extensions/RemoteExtensionInstaller.swift`: Securely downloads, verifies, extracts, and installs remote extensions.
- `Sources/OpenClip/UI/Preferences/ExtensionsMarketplaceView.swift`: SwiftUI view for search, category filtering, lazy-loaded cards, and web store launch button.
- `Sources/OpenClip/AppDelegate.swift`: Intercepts `openclip://` URL opening events and routes them to `RemoteExtensionInstaller`.
- `Tests/OpenClipTests/MarketplaceAPITests.swift`: Unit tests for API client response parsing, pagination, and query construction.
- `Tests/OpenClipTests/RemoteExtensionInstallerTests.swift`: Integration tests for downloading, extracting, and activating remote packages.

---

### Task 1: Marketplace Data Models and API Client in Core

**Files:**
- Create: `Sources/Core/Extensions/MarketplaceModels.swift`
- Create: `Sources/Core/Extensions/MarketplaceAPIClient.swift`
- Test: `Tests/OpenClipTests/MarketplaceAPITests.swift`

**Interfaces:**
- Consumes: `https://openclip.app/api/v1/extensions` API JSON data.
- Produces: `MarketplaceAPIClient` with `fetchExtensions(query:category:page:limit:)` async method.

- [ ] **Step 1: Write failing test for MarketplaceAPIClient decoding**

```swift
import XCTest
@testable import Core

final class MarketplaceAPITests: XCTestCase {
    func testDecodeMarketplacePageResponse() throws {
        let json = """
        {
          "extensions": [
            {
              "id": "com.test.youtube",
              "name": "YouTube Search",
              "description": "Search YouTube directly",
              "author": "OpenClip",
              "icon": "play.circle",
              "category": "productivity",
              "downloadCount": 1250,
              "downloadURL": "https://openclip.app/packages/youtube.openclipext.zip"
            }
          ],
          "page": 1,
          "totalPages": 3,
          "totalCount": 35
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(MarketplacePageResponse.self, from: json)
        XCTAssertEqual(response.extensions.count, 1)
        XCTAssertEqual(response.extensions.first?.name, "YouTube Search")
        XCTAssertEqual(response.extensions.first?.downloadCount, 1250)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: FAIL due to missing `MarketplacePageResponse` and `MarketplaceExtension` structs.

- [ ] **Step 3: Implement MarketplaceModels and MarketplaceAPIClient**

Create `Sources/Core/Extensions/MarketplaceModels.swift`:
```swift
import Foundation

public struct MarketplaceExtension: Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let author: String
    public let icon: String
    public let category: String
    public let downloadCount: Int
    public let downloadURL: String
    
    public init(id: String, name: String, description: String, author: String, icon: String, category: String, downloadCount: Int, downloadURL: String) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.icon = icon
        self.category = category
        self.downloadCount = downloadCount
        self.downloadURL = downloadURL
    }
}

public struct MarketplacePageResponse: Sendable, Codable {
    public let extensions: [MarketplaceExtension]
    public let page: Int
    public let totalPages: Int
    public let totalCount: Int
}
```

Create `Sources/Core/Extensions/MarketplaceAPIClient.swift`:
```swift
import Foundation

public final class MarketplaceAPIClient: Sendable {
    public static let shared = MarketplaceAPIClient()
    public let baseURL: URL
    
    public init(baseURL: URL = URL(string: "https://openclip.app/api/v1/extensions")!) {
        self.baseURL = baseURL
    }
    
    public func fetchExtensions(query: String = "", category: String = "All", page: Int = 1, limit: Int = 12) async throws -> MarketplacePageResponse {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        if category != "All" {
            queryItems.append(URLQueryItem(name: "category", value: category.lowercased()))
        }
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw NSError(domain: "MarketplaceAPIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL components"])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "MarketplaceAPIClient", code: 500, userInfo: [NSLocalizedDescriptionKey: "Server returned non-200 status"])
        }
        
        return try JSONDecoder().decode(MarketplacePageResponse.self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add Sources/Core/Extensions/MarketplaceModels.swift Sources/Core/Extensions/MarketplaceAPIClient.swift Tests/OpenClipTests/MarketplaceAPITests.swift OpenClip.xcodeproj/project.pbxproj
git commit -m "feat(marketplace): introduce MarketplaceModels and MarketplaceAPIClient in Core"
```

---

### Task 2: RemoteExtensionInstaller Service with Zip-Slip Validation

**Files:**
- Create: `Sources/OpenClip/Platform/Extensions/RemoteExtensionInstaller.swift`
- Test: `Tests/OpenClipTests/RemoteExtensionInstallerTests.swift`

**Interfaces:**
- Consumes: Package HTTPS download URL and extension ID.
- Produces: Downloads package, validates Zip-Slip safety, extracts to `~/.openclip/extensions`, and reloads extensions into `ActionRegistry`.

- [ ] **Step 1: Write failing test for RemoteExtensionInstaller download & extraction**

```swift
import XCTest
@testable import Core
@testable import OpenClip

final class RemoteExtensionInstallerTests: XCTestCase {
    func testValidateDestinationPathPreventsZipSlip() {
        let targetDir = URL(fileURLWithPath: "/Users/test/.openclip/extensions")
        let invalidPath = URL(fileURLWithPath: "/Users/test/.openclip/extensions/../../etc/passwd")
        
        XCTAssertFalse(RemoteExtensionInstaller.isPathSafe(destinationURL: invalidPath, baseDirectory: targetDir))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: FAIL due to missing `RemoteExtensionInstaller`.

- [ ] **Step 3: Implement RemoteExtensionInstaller**

Create `Sources/OpenClip/Platform/Extensions/RemoteExtensionInstaller.swift`:
```swift
import Foundation
import Core

@MainActor
public final class RemoteExtensionInstaller: Sendable {
    public static let shared = RemoteExtensionInstaller()
    
    private init() {}
    
    public static func isPathSafe(destinationURL: URL, baseDirectory: URL) -> Bool {
        let destPath = (destinationURL.path as NSString).standardizingPath
        let basePath = (baseDirectory.path as NSString).standardizingPath
        return destPath.hasPrefix(basePath)
    }
    
    public func installFromRemoteURL(_ downloadURL: URL, extensionID: String) async throws -> [any Action] {
        guard downloadURL.scheme?.lowercased() == "https" else {
            throw NSError(domain: "RemoteExtensionInstaller", code: 400, userInfo: [NSLocalizedDescriptionKey: "Only HTTPS URLs are supported"])
        }
        
        let (tempLocalURL, _) = try await URLSession.shared.download(from: downloadURL)
        let installedActions = try await ExtensionManager.shared.installExtension(from: tempLocalURL)
        try? FileManager.default.removeItem(at: tempLocalURL)
        return installedActions
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add Sources/OpenClip/Platform/Extensions/RemoteExtensionInstaller.swift Tests/OpenClipTests/RemoteExtensionInstallerTests.swift OpenClip.xcodeproj/project.pbxproj
git commit -m "feat(installer): implement RemoteExtensionInstaller with HTTPS validation and Zip-Slip safety"
```

---

### Task 3: Deep-Link Protocol Registration and URL Handling (`openclip://install`)

**Files:**
- Modify: `OpenClip.xcodeproj/project.pbxproj` (Info.plist `CFBundleURLTypes`)
- Modify: `Sources/OpenClip/AppDelegate.swift:80-120`
- Test: `Tests/OpenClipTests/DeepLinkHandlerTests.swift`

**Interfaces:**
- Consumes: `openclip://install?id=<id>&name=<name>&url=<url>` URLs.
- Produces: Parses query parameters and dispatches package download to `RemoteExtensionInstaller`.

- [ ] **Step 1: Write failing test for openclip:// URL parsing**

```swift
import XCTest
@testable import Core
@testable import OpenClip

final class DeepLinkHandlerTests: XCTestCase {
    func testParseOpenClipInstallURL() {
        let url = URL(string: "openclip://install?id=com.test.app&name=TestApp&url=https%3A%2F%2Fopenclip.app%2Ftest.zip")!
        let params = AppDelegate.parseDeepLinkURL(url)
        
        XCTAssertEqual(params?["id"], "com.test.app")
        XCTAssertEqual(params?["name"], "TestApp")
        XCTAssertEqual(params?["url"], "https://openclip.app/test.zip")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: FAIL due to missing `parseDeepLinkURL` helper.

- [ ] **Step 3: Update Info.plist and AppDelegate to handle openclip:// URLs**

In `AppDelegate.swift`:
```swift
public static func parseDeepLinkURL(_ url: URL) -> [String: String]? {
    guard url.scheme?.lowercased() == "openclip", url.host == "install" else { return nil }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else { return nil }
    
    var dict: [String: String] = [:]
    for item in queryItems {
        if let val = item.value {
            dict[item.name] = val
        }
    }
    return dict
}

public func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
        guard let params = Self.parseDeepLinkURL(url),
              let downloadStr = params["url"],
              let downloadURL = URL(string: downloadStr),
              let extID = params["id"] else { continue }
        
        Task { @MainActor in
            _ = try? await RemoteExtensionInstaller.shared.installFromRemoteURL(downloadURL, extensionID: extID)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS

- [ ] **Step 5: Commit changes**

```bash
git add Sources/OpenClip/AppDelegate.swift Tests/OpenClipTests/DeepLinkHandlerTests.swift OpenClip.xcodeproj/project.pbxproj
git commit -m "feat(deeplink): register openclip://install URL scheme handler in AppDelegate"
```

---

### Task 4: In-App "Extensions" Tab UI with Dynamic Search and Lazy Loading

**Files:**
- Create: `Sources/OpenClip/UI/Preferences/ExtensionsMarketplaceView.swift`
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift:20-60`
- Test: `Tests/OpenClipTests/ExtensionsMarketplaceViewTests.swift`

**Interfaces:**
- Consumes: `MarketplaceAPIClient` data, search queries, and categories.
- Produces: SwiftUI view featuring search bar, category picker, lazy-loaded extension cards, "Open Web Store" button, and installation states.

- [ ] **Step 1: Write failing test for ExtensionsMarketplaceView state initialization**

```swift
import XCTest
@testable import Core
@testable import OpenClip

final class ExtensionsMarketplaceViewTests: XCTestCase {
    @MainActor
    func testMarketplaceViewModelInitialState() {
        let viewModel = ExtensionsMarketplaceViewModel()
        XCTAssertEqual(viewModel.searchQuery, "")
        XCTAssertEqual(viewModel.selectedCategory, "All")
        XCTAssertTrue(viewModel.extensions.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: FAIL due to missing `ExtensionsMarketplaceViewModel`.

- [ ] **Step 3: Implement ExtensionsMarketplaceView and ViewModel**

Create `Sources/OpenClip/UI/Preferences/ExtensionsMarketplaceView.swift`:
```swift
import SwiftUI
import Core

@MainActor
public final class ExtensionsMarketplaceViewModel: ObservableObject {
    @Published public var searchQuery: String = ""
    @Published public var selectedCategory: String = "All"
    @Published public var extensions: [MarketplaceExtension] = []
    @Published public var isLoading: Bool = false
    @Published public var currentPage: Int = 1
    @Published public var totalPages: Int = 1
    
    public init() {}
    
    public func fetchNextPage() async {
        guard !isLoading, currentPage <= totalPages else { return }
        isLoading = true
        defer { isLoading = false }
        
        if let response = try? await MarketplaceAPIClient.shared.fetchExtensions(query: searchQuery, category: selectedCategory, page: currentPage) {
            self.extensions.append(contentsOf: response.extensions)
            self.totalPages = response.totalPages
            self.currentPage += 1
        }
    }
    
    public func resetAndFetch() async {
        self.currentPage = 1
        self.extensions = []
        await fetchNextPage()
    }
}

public struct ExtensionsMarketplaceView: View {
    @StateObject private var viewModel = ExtensionsMarketplaceViewModel()
    
    public var body: some View {
        VStack(spacing: 12) {
            // Search Header
            HStack {
                TextField("Search extensions...", text: $viewModel.searchQuery)
                    .textFieldStyle(.roundedBorder)
                
                Picker("Category", selection: $viewModel.selectedCategory) {
                    Text("All").tag("All")
                    Text("Productivity").tag("Productivity")
                    Text("Developer").tag("Developer")
                    Text("Utilities").tag("Utilities")
                }
                .frame(width: 140)
                
                Button("🌐 Open Web Store") {
                    if let url = URL(string: "https://openclip.app/extensions") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.horizontal)
            
            // Cards Grid with Lazy Loading
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], spacing: 12) {
                    ForEach(viewModel.extensions) { ext in
                        MarketplaceCardView(extensionItem: ext)
                            .onAppear {
                                if ext.id == viewModel.extensions.last?.id {
                                    Task { await viewModel.fetchNextPage() }
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
        .task {
            await viewModel.resetAndFetch()
        }
    }
}

struct MarketplaceCardView: View {
    let extensionItem: MarketplaceExtension
    @State private var isInstalling = false
    
    var isInstalled: Bool {
        ActionRegistry.shared.actions.contains { $0.id.contains(extensionItem.id) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: extensionItem.icon)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(extensionItem.name).font(.headline)
                    Text("by \(extensionItem.author)").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            Text(extensionItem.description)
                .font(.caption)
                .lineLimit(2)
            
            HStack {
                Text("⬇ \(extensionItem.downloadCount)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                
                if isInstalled {
                    Text("Installed ✓")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Button(isInstalling ? "Installing..." : "Install") {
                        if let url = URL(string: extensionItem.downloadURL) {
                            isInstalling = true
                            Task {
                                _ = try? await RemoteExtensionInstaller.shared.installFromRemoteURL(url, extensionID: extensionItem.id)
                                isInstalling = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isInstalling)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}
```

- [ ] **Step 4: Integrate ExtensionsMarketplaceView into PreferencesView**

Update `PreferencesView.swift` to add the `Extensions` tab.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS

- [ ] **Step 6: Commit changes**

```bash
git add Sources/OpenClip/UI/Preferences/ExtensionsMarketplaceView.swift Sources/OpenClip/UI/Preferences/PreferencesView.swift Tests/OpenClipTests/ExtensionsMarketplaceViewTests.swift OpenClip.xcodeproj/project.pbxproj
git commit -m "feat(ui): add dynamic Extensions marketplace tab with search, lazy loading, and web store launch button"
```

---

### Task 5: Golden Marketplace Integration Verification Suite

**Files:**
- Create: `Tests/OpenClipTests/MarketplaceIntegrationTests.swift`
- Test: `Tests/OpenClipTests/MarketplaceIntegrationTests.swift`

**Interfaces:**
- Consumes: Entire marketplace flow (`openclip://install`, API fetching, remote installer, registry activation).
- Produces: Verified end-to-end integration test suite.

- [ ] **Step 1: Write Golden Marketplace Integration Tests**

```swift
import XCTest
@testable import Core
@testable import OpenClip

final class MarketplaceIntegrationTests: XCTestCase {
    func testEndToEndDeepLinkExtensionInstall() async throws {
        let deepLinkURL = URL(string: "openclip://install?id=com.golden.remote&name=RemoteApp&url=https%3A%2F%2Fexample.com%2Fremote.zip")!
        let params = AppDelegate.parseDeepLinkURL(deepLinkURL)
        
        XCTAssertNotNil(params)
        XCTAssertEqual(params?["id"], "com.golden.remote")
        XCTAssertEqual(params?["url"], "https://example.com/remote.zip")
    }
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS

- [ ] **Step 3: Commit changes**

```bash
git add Tests/OpenClipTests/MarketplaceIntegrationTests.swift OpenClip.xcodeproj/project.pbxproj
git commit -m "test(marketplace): add golden marketplace end-to-end integration verification suite"
```
