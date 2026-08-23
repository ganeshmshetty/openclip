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

When launched for the first time, OpenClip presents a 3-step onboarding wizard:

1. **Welcome**: Overview of how OpenClip works, plus the Accessibility permission check. Access can also be granted later from Preferences.
2. **AI Assistant**: Pick and configure an AI engine (Apple Intelligence, Ollama, Cloud, or Browser Redirect). Optional — change anytime in **Preferences → AI**.
3. **Extensions**: Browse recommended extensions or install one from a file.

Onboarding can be skipped at any step; finishing it starts text-selection monitoring and shows a one-time tip near the menu bar icon. You can also trigger the popup anytime with the global shortcut (**⌥⌘C** by default), and change the popup bar's theme anytime in **Preferences → Appearance**.
