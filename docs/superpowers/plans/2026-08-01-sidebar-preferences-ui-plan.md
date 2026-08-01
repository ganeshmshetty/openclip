# Sidebar Preferences UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform `PreferencesView.swift` from a top `TabView` into a Raycast-style split layout with a left navigation sidebar, icon-only footer (`?` and GitHub), and dark grouped setting cards.

**Architecture:** Create `PreferencesSidebar` and `SettingsGroupCard` components in `PreferencesView.swift`. Update `GeneralTab`, `AppearanceTab`, `ActionsTab`, `AppRulesTab`, and `AboutTab` to use `SettingsGroupCard`.

**Tech Stack:** Swift 6 (strict concurrency) · SwiftUI · AppKit

## Global Constraints

- Language: Swift 6 strict concurrency — zero warnings.
- Footer icons: `questionmark.circle` and `code` (GitHub link) — icon-only, no text labels.
- Preserves all state bindings (`popupStyle`, `theme`, `popupSize`, `disabledActionIDs`).
- All unit tests must pass cleanly.
- Commit after each task.

---

## File Structure

- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift`
- Modify: `Sources/OpenClip/UI/Preferences/AppRulesTab.swift`

---

## Task 1: Create `PreferencesSidebar` & `SettingsGroupCard` in `PreferencesView.swift`

**Files:**
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift`

- [ ] **Step 1: Implement `PreferencesSidebar` with icon-only footer (`?` & GitHub)**

```swift
struct PreferencesSidebar: View {
    @Binding var selectedTab: Int
    
    private let tabs: [(id: Int, title: String, icon: String)] = [
        (0, "General", "gearshape"),
        (1, "Appearance", "paintpalette"),
        (2, "Actions", "bolt.fill"),
        (3, "App Rules", "macwindow.badge.gearshape"),
        (4, "About", "info.circle")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tabs, id: \.id) { tab in
                Button {
                    selectedTab = tab.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 20)
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(selectedTab == tab.id ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedTab == tab.id ? Color.accentColor : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Divider()
                .padding(.vertical, 4)
            
            // Icon-only Footer: Help (?) and GitHub
            HStack(spacing: 12) {
                Button {
                    if let url = URL(string: "https://github.com/ganesh/openclip#readme") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Help & Documentation")
                
                Button {
                    if let url = URL(string: "https://github.com/ganesh/openclip") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "code")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open GitHub Repository")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .padding(12)
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }
}
```

- [ ] **Step 2: Implement `SettingsGroupCard` container view**

```swift
struct SettingsGroupCard<Content: View>: View {
    let title: String?
    let content: Content
    
    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}
```

- [ ] **Step 3: Update `PreferencesView.body` to render split layout**

```swift
    public var body: some View {
        HStack(spacing: 0) {
            PreferencesSidebar(selectedTab: $selectedTab)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text(tabTitle(for: selectedTab))
                    .font(.title2)
                    .bold()
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                
                Divider()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch selectedTab {
                        case 0: GeneralTab()
                        case 1: AppearanceTab(popupStyle: $popupStyle, theme: $theme, popupSize: $popupSize)
                        case 2: ActionsTab(disabledActionIDs: $disabledActionIDs)
                        case 3: AppRulesTab()
                        case 4: AboutTab()
                        default: EmptyView()
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 720, height: 500)
        .onAppear {
            loadDisabledActionIDs()
        }
        .onChange(of: disabledActionIDs) { _, _ in
            saveDisabledActionIDs()
        }
    }
```

- [ ] **Step 4: Run unit tests to verify zero regressions**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS.

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/OpenClip/UI/Preferences/PreferencesView.swift docs/superpowers/specs/2026-08-01-sidebar-preferences-ui-design.md docs/superpowers/plans/2026-08-01-sidebar-preferences-ui-plan.md
git commit -m "feat(ui): implement Raycast-style sidebar preferences layout with icon-only footer"
```

---

## Task 2: Refactor Settings Tabs & Live Verification

**Files:**
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift`
- Modify: `Sources/OpenClip/UI/Preferences/AppRulesTab.swift`

- [ ] **Step 1: Refactor `GeneralTab` to use `SettingsGroupCard`**

Update `GeneralTab` to wrap Shortcut, Startup, and Permissions in `SettingsGroupCard`s with smooth inset rows.

- [ ] **Step 2: Refactor `AppearanceTab` to use `SettingsGroupCard`**

Wrap Style, Theme, and Size pickers in `SettingsGroupCard`s.

- [ ] **Step 3: Run unit tests to verify build & tests pass**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS (all 52 unit tests passing).

- [ ] **Step 4: Rebuild & launch app via `dev_run.sh`**

Run: `./scripts/dev_run.sh`
Expected: OpenClip launches cleanly. Preferences window shows the sleek Raycast-style sidebar with icon-only footer and dark card settings.

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/OpenClip/UI/Preferences/PreferencesView.swift Sources/OpenClip/UI/Preferences/AppRulesTab.swift
git commit -m "style(ui): refactor settings tabs to dark card layout"
```
