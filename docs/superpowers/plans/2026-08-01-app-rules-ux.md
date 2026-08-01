# App Rules UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul the App Rules UI to support adding non-running installed applications & wildcards, provide a clean blacklist-first list view, and add a three-dots (`...`) action dropdown menu for advanced per-app toggles.

**Architecture:** 
1. Create `InstalledAppsScanner` helper to discover `.app` bundles in `/Applications` and `~/Applications`.
2. Refactor `AppRulesTab.swift` to use `AppPickerSheet` (tabs for Running Apps, Installed Apps, and Custom Wildcard).
3. Replace inline expandable app row UI with a flat row presenting an Enable/Disable toggle, status badge, and a `Menu` button (`...`) with options to toggle formatting, clipboard mode, or delete.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSWorkspace`, `NSMenu`), XCTest.

## Global Constraints
- Language: Swift 6 (strict concurrency, `@MainActor` UI components).
- Build target: macOS 13+.
- Unit tests: Must pass via `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`.

---

### Task 1: Create InstalledAppsScanner Helper & Unit Tests

**Files:**
- Create: `Sources/OpenClip/Platform/InstalledAppsScanner.swift`
- Create: `Tests/OpenClipTests/InstalledAppsScannerTests.swift`

**Interfaces:**
- Produces: `struct InstalledAppInfo: Identifiable, Sendable { let name: String; let bundleIdentifier: String; let path: String; let icon: NSImage }`
- Produces: `InstalledAppsScanner.scanInstalledApps() async -> [InstalledAppInfo]`

- [ ] **Step 1: Write failing unit test for InstalledAppsScanner**
Create `Tests/OpenClipTests/InstalledAppsScannerTests.swift` testing that `InstalledAppsScanner` returns non-empty installed apps and includes Finder or Safari.

- [ ] **Step 2: Implement InstalledAppsScanner**
Create `Sources/OpenClip/Platform/InstalledAppsScanner.swift` to scan `/Applications` and `~/Applications` for `.app` packages, read bundle info via `Bundle(path:)` or `NSWorkspace.shared.urlForApplication`, and return `InstalledAppInfo`.

- [ ] **Step 3: Verify tests pass**
Run `xcodegen generate` and `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`.

- [ ] **Step 4: Commit**
`git add Sources/OpenClip/Platform/InstalledAppsScanner.swift Tests/OpenClipTests/InstalledAppsScannerTests.swift OpenClip.xcodeproj && git commit -m "feat(rules): add InstalledAppsScanner helper and tests"`

---

### Task 2: Build AppPickerSheet & Redesign AppRulesTab UI

**Files:**
- Create: `Sources/OpenClip/UI/Preferences/AppPickerSheet.swift`
- Modify: `Sources/OpenClip/UI/Preferences/AppRulesTab.swift`

**Interfaces:**
- Consumes: `InstalledAppsScanner`, `RuleEngine`
- Produces: `AppPickerSheet(onSelect: (String) -> Void)`
- Produces: Redesigned `AppRulesTab` with direct toggles and `...` dropdown menu.

- [ ] **Step 1: Create AppPickerSheet**
Implement tabbed picker sheet in `AppPickerSheet.swift` with:
- Tab 1: Running Apps (with icon + search)
- Tab 2: Installed Apps (using `InstalledAppsScanner`)
- Tab 3: Custom / Wildcard (TextField for entering bundle IDs like `com.jetbrains.*`)

- [ ] **Step 2: Redesign AppRulesTab row view with 3-Dots Menu**
In `AppRulesTab.swift`:
- Replace row chevron expansion with a flat row layout.
- Include app icon, app name, bundle ID, and a clear `Toggle` for Enable/Disable (Blacklist).
- Add a `Menu` button (`Image(systemName: "ellipsis.circle")` / `"ellipsis"`) containing:
  - Toggle Enable/Disable
  - Toggle Formatting (`denyFormatting`)
  - Toggle Force Clipboard (`grabPasteboard`)
  - Delete Rule

- [ ] **Step 3: Test and build**
Run `xcodegen generate` and `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`.

- [ ] **Step 4: Launch and verify**
Run `./scripts/dev_run.sh` to visually test adding installed apps and toggling rules via the three-dots menu.

- [ ] **Step 5: Commit**
`git add Sources/OpenClip/UI/Preferences/AppPickerSheet.swift Sources/OpenClip/UI/Preferences/AppRulesTab.swift OpenClip.xcodeproj && git commit -m "feat(ui): implement AppPickerSheet and three-dots action dropdown for App Rules"`
