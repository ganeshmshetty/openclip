# Settings UI Sidebar Migration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the current Settings/Preferences window from a standard `TabView` to a modern macOS `NavigationSplitView` sidebar layout, matching premium macOS apps.

## Constraints & Requirements
- Target UI: Sleek sidebar on the left, detail content on the right.
- The bottom of the sidebar must contain only two icons: `?` (Help) and the GitHub icon (with **no text**).
- Update the window chrome in `StatusBarController` to look seamless (`.fullSizeContentView` + `.titlebarAppearsTransparent = true`).
- Ensure all tests continue to pass cleanly.

---

## Task 1: Update NSWindow Styling for Modern Sidebar

**Files:**
- Modify: `Sources/OpenClip/StatusBarController.swift`

- [ ] **Step 1: Modify `showPreferences()` in `StatusBarController.swift`**
Update the window creation logic to support a seamless titlebar and larger default size.
```swift
        let controller = NSHostingController(rootView: PreferencesView())
        let window = NSWindow(contentViewController: controller)
        window.title = "OpenClip Preferences"
        window.setContentSize(NSSize(width: 700, height: 500))
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.center()
        self.preferencesWindow = window
```

- [ ] **Step 2: Commit Task 1**
```bash
git add Sources/OpenClip/StatusBarController.swift
git commit -m "feat(ui): update Preferences window styling for seamless sidebar layout"
```

---

## Task 2: Refactor `PreferencesView` to `NavigationSplitView`

**Files:**
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift`

- [ ] **Step 1: Define `PreferenceTab` Enum**
Create an enum to drive the selection in the sidebar.
```swift
enum PreferenceTab: String, CaseIterable, Hashable {
    case general = "General"
    case appearance = "Appearance"
    case actions = "Actions"
    case appRules = "App Rules"
    case about = "About"
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .actions: return "bolt.fill"
        case .appRules: return "macwindow.badge.gearshape"
        case .about: return "info.circle"
        }
    }
}
```

- [ ] **Step 2: Rewrite `PreferencesView` Body**
Replace `TabView` with `NavigationSplitView`.
Add the sidebar items using `List(selection: $selectedTab)` and `.listStyle(.sidebar)`.
Add the bottom footer with `Spacer()` and the two icon buttons (Help and GitHub) with NO text.
```swift
    @State private var selectedTab: PreferenceTab? = .general
    
    public var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(PreferenceTab.allCases, id: \.self) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 250)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 16) {
                    Button(action: {
                        if let url = URL(string: "https://openclip.app/help") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("Help Center")
                    
                    Button(action: {
                        if let url = URL(string: "https://github.com/openclip-app/openclip") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        // Assuming you don't have a custom asset, use standard sf symbol or Text
                        Image(systemName: "curlybraces.square")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .help("GitHub Repository")
                    
                    Spacer()
                }
                .padding()
            }
        } detail: {
            Group {
                switch selectedTab {
                case .general: GeneralTab()
                case .appearance: AppearanceTab(popupStyle: $popupStyle, theme: $theme, popupSize: $popupSize)
                case .actions: ActionsTab(disabledActionIDs: $disabledActionIDs)
                case .appRules: AppRulesTab()
                case .about: AboutTab()
                case .none: Text("Select a setting")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { loadDisabledActionIDs() }
        .onChange(of: disabledActionIDs) { _, _ in saveDisabledActionIDs() }
    }
```
*(Make sure to verify if `github.logo` or something similar exists, otherwise use a placeholder system symbol or let it be handled accurately).*

- [ ] **Step 3: Verify and run tests**
Run `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'` to verify everything builds properly.

- [ ] **Step 4: Launch and observe**
Run `./scripts/dev_run.sh` to see the new gorgeous sidebar in action.

- [ ] **Step 5: Commit Task 2**
```bash
git add Sources/OpenClip/UI/Preferences/PreferencesView.swift
git commit -m "feat(ui): migrate Preferences window to modern NavigationSplitView sidebar layout"
```
