# Simplified General Settings Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `GeneralTab` in `PreferencesView.swift` to present a clean, native macOS Form layout without heavy card containers and verbose copy.

**Architecture:** Replace the 3 bordered card `VStack`s in `GeneralTab` with a clean `Form` containing grouped sections for Shortcut, Startup, and System Permissions.

**Tech Stack:** SwiftUI (AppKit environment) · KeyboardShortcuts · LaunchAtLoginManager

## Global Constraints

- Language: Swift 6 strict concurrency — zero warnings.
- Preserves all functionality (`KeyboardShortcuts.Recorder`, `launchManager.isEnabled`, `isAXTrusted` check).
- All unit tests in `Tests/OpenClipTests/` must pass cleanly.
- Commit after task completion.

---

## Task 1: Refactor `GeneralTab` to Native Form Layout

**Files:**
- Modify: `Sources/OpenClip/UI/Preferences/PreferencesView.swift:70-205`

- [ ] **Step 1: Inspect `GeneralTab` current implementation**

Verify current `GeneralTab` lines in `Sources/OpenClip/UI/Preferences/PreferencesView.swift`.

- [ ] **Step 2: Update `GeneralTab` in `PreferencesView.swift`**

Replace lines 70-204 in `PreferencesView.swift` with:
```swift
@MainActor
struct GeneralTab: View {
    @ObservedObject private var launchManager = LaunchAtLoginManager.shared
    @State private var isAXTrusted: Bool = AXIsProcessTrustedWithOptions(nil)
    
    var body: some View {
        Form {
            Section("Shortcut") {
                HStack {
                    Text("Trigger Popup")
                        .font(.body)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePopup)
                }
            }
            
            Section("Startup") {
                Toggle("Start OpenClip at Login", isOn: $launchManager.isEnabled)
                    .toggleStyle(.checkbox)
            }
            
            Section("Permissions") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility Access")
                            .font(.body)
                        Text(isAXTrusted ? "Active" : "Required for text selection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(isAXTrusted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(isAXTrusted ? "Granted" : "Required")
                            .font(.caption)
                            .foregroundColor(isAXTrusted ? .green : .orange)
                        
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .onAppear {
            isAXTrusted = AXIsProcessTrustedWithOptions(nil)
        }
    }
}
```

- [ ] **Step 3: Run unit tests to verify zero regressions**

Run: `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`
Expected: PASS with 0 failures.

- [ ] **Step 4: Rebuild and test app execution**

Run: `./scripts/dev_run.sh`
Expected: App launches cleanly with simplified General tab layout.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenClip/UI/Preferences/PreferencesView.swift docs/superpowers/plans/2026-08-01-simplified-general-settings-plan.md
git commit -m "refactor(ui): simplify General tab in PreferencesView to native Form layout"
```
