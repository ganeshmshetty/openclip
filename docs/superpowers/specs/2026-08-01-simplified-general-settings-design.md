# Simplified General Settings Tab Design Spec

**Goal:** Simplify the `GeneralTab` in `PreferencesView.swift` by adopting a clean, native macOS Form layout that removes redundant card containers and verbose copy.

## Design Details

### 1. Form Structure
Replace the three heavy `VStack` card containers (`fill(Color.primary.opacity(0.04))`) with a native SwiftUI `Form` using standard section groupings:

- **Shortcut Section**:
  - `Form` row with label "Global Activation Shortcut" and `KeyboardShortcuts.Recorder(for: .togglePopup)` on the right.
- **Startup Section**:
  - `Form` toggle for "Start OpenClip at Login".
- **Permissions Section**:
  - Compact row showing Accessibility access status ("Granted" / "Required") with an "Open Settings" button.

### 2. Copy & Layout
- Concise labels without multi-line explanatory paragraphs.
- Native spacing and macOS system typography.
