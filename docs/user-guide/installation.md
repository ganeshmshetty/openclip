# Installation and onboarding

This page covers installing OpenClip on macOS, granting the permission it needs, and what you see the first time you launch it.

## System requirements

- macOS 14.0 (Sonoma) or later.
- Apple Silicon (M1 through M4) or Intel. The app is a universal binary.
- Accessibility permission, so OpenClip can detect when you select text.

The interface follows the macOS system language. English, Simplified Chinese, Traditional Chinese, French, and Japanese are bundled.

## Installation steps

1. Download the latest `.dmg` or `.zip` from the releases page.
2. Drag `OpenClip.app` into your `/Applications` folder.
3. Open `OpenClip.app` from Finder or Spotlight.

Releases are signed with an Apple Developer ID certificate and notarized by Apple, so OpenClip opens normally. You don't need to right-click to open it or strip a quarantine attribute with `xattr`. If macOS says the app "cannot be opened because the developer cannot be verified", you don't have a release build, so check where the download came from.

To check a copy before launching it:

```bash
spctl -a -vv -t exec /Applications/OpenClip.app
# accepted
# source=Notarized Developer ID

xcrun stapler validate /Applications/OpenClip.app
# The validate action worked!
```

## Granting Accessibility permission

OpenClip uses the macOS Accessibility API (`AXUIElement`) to read the text you select without touching your clipboard.

1. On first launch, OpenClip asks for Accessibility permission. Click **Open System Settings**.
2. Go to **Privacy & Security > Accessibility**.
3. Turn on the switch next to **OpenClip**.
4. Confirm with your Mac password or Touch ID.

> [!NOTE]
> OpenClip reads the selection only when you select text with the mouse. It doesn't log keystrokes and it doesn't store what you selected.

## First launch

The first time you open OpenClip it shows a four-step setup:

1. **Welcome** explains the idea: select text, then pick an action.
2. **Access** checks the Accessibility permission. Everything runs on your Mac.
3. **Extensions** offers a few useful ones, such as translation, word count, and speech, each with a one-click install.
4. **Try it** is a small sandbox where you can select text and see the real action bar.

You can skip any step. Finishing setup starts text-selection monitoring. After that you can open the popup at any time with the global shortcut (**⌥⌘C** by default), set up AI providers in **Preferences > AI**, and change the popup's look in **Preferences > Customize**.
