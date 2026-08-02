# Installation & Onboarding Guide

Welcome to OpenClip! This guide will walk you through installing OpenClip on macOS, granting required permissions, and configuring your initial setup.

---

## System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later.
- **Architecture**: Universal binary (Apple Silicon M1/M2/M3/M4 & Intel processors).
- **Permissions**: Accessibility permission is required for global text selection detection.

---

## Installation Steps

1. **Download OpenClip**: Download the latest release `.dmg` or `.zip` file from the official releases page.
2. **Move to Applications**: Drag `OpenClip.app` into your `/Applications` folder.
3. **Launch OpenClip**: Open `OpenClip.app` from Finder or Spotlight.

---

## Granting Accessibility Permissions

OpenClip relies on macOS Accessibility APIs (`AXUIElement`) to detect text selection events and extract selected text directly without polluting your clipboard.

```
System Settings ---> Privacy & Security ---> Accessibility ---> Enable OpenClip
```

1. On first launch, OpenClip will prompt you to grant Accessibility permissions.
2. Click **Open System Settings**.
3. Navigate to **Privacy & Security > Accessibility**.
4. Toggle the switch next to **OpenClip** to **On**.
5. Authenticate with your Mac password or Touch ID.

> [!NOTE]
> OpenClip reads selected text strictly in real-time when mouse drag or selection events occur. No keystrokes or selection histories are logged or stored locally.

---

## First-Launch Onboarding Workflow

When launched for the first time, OpenClip presents an onboarding assistant:

1. **Permission Check**: Verifies that Accessibility permission is granted.
2. **Shortcut Setup**: Explains global hotkey triggers and mouse-release detection.
3. **Quick Test**: Demonstrates selecting text in any text field to trigger the floating popup bar.
4. **Login Item Configuration**: Option to enable launch at login (`LaunchAtLoginManager`).
