# OpenClip Source Architecture (`Sources/`)

This directory contains the Swift codebase for OpenClip, divided into two distinct framework targets:

## Target Boundaries

```
Sources/
├── Core/               # Pure domain framework (Core.framework)
│   ├── Actions/        # Abstract action definitions, rules, relevance models
│   ├── Canvas/         # Dynamic Canvas UI specifications, AST & JSON DSL parsers
│   ├── Extensions/     # Manifest schemas, validation, extension manager
│   ├── Rules/          # Application context rules & engine
│   ├── Selection/      # Selection context data structures & protocols
│   ├── Settings/       # Abstract settings keys & storage contracts
│   └── Utils/          # Pure string & placeholder expansion engines
│
└── OpenClip/           # macOS Application (OpenClip.app)
    ├── AI/             # AI service integrations (Ollama, Cloud API, Apple Intelligence)
    ├── Notifications/  # macOS system notification names & dispatchers
    ├── Platform/       # macOS OS adapters (Accessibility API, Pasteboard, Hotkeys, Keychain)
    │   └── Runtimes/   # Concrete action execution engines (JS, AppleScript, KeyPress, Canvas)
    └── UI/             # macOS AppKit windows (NSPanel) & SwiftUI views
        ├── Design/     # LiquidGlass & visual design tokens
        ├── Icons/      # SVG/PNG icon view renderers & caches
        ├── Onboarding/ # Onboarding window & view controllers
        ├── Popup/      # Floating popup window, positioner, hover & preview views
        └── Preferences/# App settings tabs & extension store views
```

### 1. `Sources/Core` (Pure Business Logic)
- **Target**: `Core.framework`
- **Dependencies**: Pure Swift (`Foundation`, `Combine`, `CoreGraphics` only).
- **Rule**: No AppKit, SwiftUI, JavaScriptCore, or OS side-effects are permitted in `Core`. All types here are platform-agnostic and fully testable in headless environments.

### 2. `Sources/OpenClip` (macOS Integration & UI)
- **Target**: `OpenClip.app`
- **Dependencies**: `Core`, `AppKit`, `SwiftUI`, `JavaScriptCore`, `KeyboardShortcuts`, `ApplicationServices`, `Security`, `ServiceManagement`.
- **Role**: Contains all macOS platform adapters, AppKit floating windows, SwiftUI preference panels, global hotkey listeners, system selection monitoring, and concrete execution runtimes in `Platform/Runtimes/`.
