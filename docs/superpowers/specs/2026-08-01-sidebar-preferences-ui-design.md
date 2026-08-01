# Sidebar Preferences UI Design Spec

**Goal:** Redesign `PreferencesView.swift` to adopt a Raycast/CleanShot-style left sidebar navigation layout with grouped settings cards and icon-only bottom footer actions (`?` and GitHub).

## Visual & Component Design

### 1. Window & Sidebar Layout (`HStack(spacing: 0)`)
- **Left Sidebar (`width: 210`)**:
  - Dark container background (`Color(nsColor: .windowBackgroundColor)` or `Color(white: 0.12)`).
  - Navigation Items:
    - `gearshape` — General
    - `paintpalette` — Appearance
    - `bolt.fill` — Actions
    - `macwindow.badge.gearshape` — App Rules
    - `info.circle` — About
  - Selection Pill: Active tab highlighted in `Color.blue` with `cornerRadius: 8`.
  - **Bottom Footer (Icon-only)**:
    - Left-aligned horizontal stack with `questionmark.circle` (Help) and `code` / `globe` (GitHub) buttons without text labels.

### 2. Right Detail Content Area
- Bold Title Header for current tab.
- **Grouped Settings Cards (`SettingsGroupCard`)**:
  - `VStack` enclosed in `RoundedRectangle(cornerRadius: 10)` with dark fill `Color(white: 0.16)`.
  - Rows separated by thin `Divider()`.
