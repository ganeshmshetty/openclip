# OpenClip Directory Structure

Annotated source tree. See `docs/architecture/overview.md` for the architectural (target-split)
view; this is the detailed per-file map.

```text
Sources/
├── Core/                                     # Domain Logic (Pure Swift Target)
│   ├── Log.swift                             # Single logging surface: Log enum, LogChannel, LogSink protocol, LogLevel, LogMessage (see docs/logging.md)
│   ├── Actions/
│   │   ├── Action.swift                      # Action protocol
│   │   ├── ActionChrome.swift                # UI metadata policy enum
│   │   ├── ActionContext.swift               # Action resolution context
│   │   ├── ActionCoordinator.swift           # Action execution coordinator & composition root (wires managers to registry)
│   │   ├── ActionResult.swift                # Action result value types
│   │   ├── ActionDelivery.swift              # Per-action delivery: secondary outcome + per-click toasts
│   │   ├── ActionResultDelivery.swift        # Select → Probe → Toast: paste-vs-copy delivery decision (resolves (result, toast))
│   │   ├── DeliveryDecoratedAction.swift     # Pure wrapper stamping a declared ActionDelivery onto an action
│   │   ├── ActionCustomizationManager.swift  # User action overrides (title/icon); delegates I/O to SettingsStore
│   │   ├── ActionRegistry.swift              # Storage, ordering, and transform default-on/off policy
│   │   ├── ActionSearch.swift                # Popup mode enum + pure substring matcher for the action-search palette
│   │   ├── GroupAction.swift                 # Pure group-row action (chrome .showSubActions); perform → .none
│   │   ├── KeyPressSpec.swift                # Key-press spec ("mod+mod+key") parsed from manifest keyPress
│   │   ├── Builtin/                          # Core builtin actions (Copy, Cut, Paste, etc.)
│   │   ├── BuiltinRegistry.swift             # Default builtin actions catalog
│   │   ├── ConfigurableAction.swift          # Configurable action protocol (preferenceIconName)
│   │   ├── Custom/                           # Custom action draft DTO
│   │   │   └── CustomActionDraft.swift       # Value-type DTO for form editing
│   │   ├── CustomAction.swift                # Custom action domain model
│   │   ├── ExtensionOption.swift             # Extension option models
│   │   ├── ModifierFlags.swift               # Keyboard modifier flags
│   │   ├── MathEvaluator.swift               # Deterministic exception-free arithmetic parser (replaces NSExpression; used by CalculateAction)
│   │   ├── URLTemplateAction.swift           # Web search / URL template action
│   │   └── WordCompletionProviding.swift     # Completion provider protocol
│   ├── Extensions/
│   │   ├── ActionFactory.swift               # Action factory protocol
│   │   ├── ExtensionManager.swift            # Extension loader; reports changes via onRegister/onUnregister callbacks
│   │   ├── ExtensionsAPIClient.swift         # Remote store API client
│   │   ├── ExtensionsModels.swift            # Store models & DTOs
│   │   ├── Manifest/                         # Extension manifest structures
│   │   │   ├── ExtensionActionKind.swift     # Normalized extension kind enum
│   │   │   ├── ExtensionManifest.swift       # Extension manifest decoder
│   │   │   ├── ExtensionManifestStore.swift  # Manifest file locate/read/write (shared home)
│   │   │   └── ManifestValidation.swift      # Manifest validation pass + empty capability gate + fingerprint record
│       │   ├── OpenClipSnippetParser.swift       # Standalone snippet header parser (nonisolated, pure text); body mode ends only at `#` header keys, `//` lines stay body
│   │   ├── ScriptAction.swift                # Executable script action
│   │   └── ShellProcessRunner.swift          # Shared subprocess executor; GCD-timer 30s watchdog + readabilityHandler reads (never blocks a thread); hosts TimeoutFlag/OnceGate; maps stdout JSON via ShellResultMapper
│   ├── Rules/                                # App-specific policy rules
│   │   ├── AppRule.swift                     # AppPolicyContext (5 active fields) + AppRule Codable model
│   │   └── RuleEngine.swift
│   ├── Selection/                            # Text selection & monitoring models
│   │   ├── AppFilter.swift
│   │   ├── AppIdentifying.swift
│   │   ├── Constants.swift                   # Domain/runtime constants (timeouts, key codes, env vars, manifest keys) — no UI sizing
│   │   ├── SelectionContext.swift
│   │   ├── SelectionMonitoring.swift
│   │   └── TextRetrieving.swift
│   ├── Settings/                             # Settings subsystem
│   │   ├── SettingKey.swift                  # Strongly-typed setting keys
│   │   └── SettingsStore.swift               # Central SettingsStore protocol + DefaultSettingsStore adapter
│   └── Utils/
│       └── TextPlaceholderEngine.swift       # Dynamic text template engine
└── OpenClip/                                 # App Target (macOS App / AppKit / SwiftUI)
    ├── AI/                                   # AI Assistant & Providers
    ├── AIProvider.swift
    ├── AIServiceManager.swift            # cloudAPIKey is Keychain-backed (@Published), other prefs via @AppStorage
    └── Providers/                        # Apple Intelligence, Cloud, Ollama, BrowserRedirect
        ├── CloudAPIProvider.swift        # OpenAI-compatible / Anthropic / Gemini cloud chat
        └── CloudAPIProviderDTOs.swift    # Codable chat request/response payloads for the cloud APIs
    ├── Actions/                              # Runtime actions requiring AppKit/JavaScript
    ├── AppleScriptAction.swift
    ├── JavaScriptAction.swift            # Manifests JS actions; short-circuits to .openConfiguration when a required option is unresolved, else delegates to OpenClipJSHost (options via injected ActionOptionReading)
    ├── KeyPressAction.swift              # type: "keyPress" runtime → .keyPress(KeyPressSpec)
    ├── NamedServiceAction.swift          # type: "service" runtime → .showServices(text)
    ├── OpenClipJSHost.swift              # JS bridge (openclip.*) + effect resolver + .openConfiguration short-circuit support
    ├── OpenClipJSHostSupport.swift       # Threading/support boxes for the JS host (TimeoutFlag, gate, JS context/value/runloop boxes, promise state)
    └── ShortcutAction.swift              # type: "shortcut" runtime → .runShortcut(name:input:)
    ├── App/
    ├── AppDelegate.swift                     # Reads isAppEnabled / hasCompletedOnboarding via DefaultSettingsStore (SettingKey)
    ├── OpenClipApp.swift                     # SwiftUI App Entrypoint
    ├── Platform/                             # macOS Platform Services
    │   ├── AppleScriptRunner.swift           # Bounded off-main AppleScript executor (killable osascript subprocess via ShellProcessRunner)
    │   ├── BuiltinActions/                   # AppKit platform actions (Services, Finder)
    │   ├── Effects/
    │   │   └── ActionResultHandler.swift     # Platform side-effects handler
    │   ├── Extensions/
    │   │   ├── DefaultActionFactory.swift    # ActionFactory implementation (routing kinds incl. keyPress/shortcut/service/group)
    │   │   ├── KeychainActionOptionStore.swift  # Composite option store; .secret options → Keychain
    │   │   ├── OpenClipSnippetParser+DefaultFactory.swift
    │   │   └── RemoteExtensionInstaller.swift
    │   ├── HotkeyManager.swift               # Global shortcut manager (⌥⌘C toggles popup actions → search → dismiss when visible)
    │   ├── InstalledAppsScanner.swift        # App scanner
    │   ├── KeychainStore.swift               # Generic-password SecItem wrapper for sensitive credentials (AI API key)
    │   ├── LaunchAtLoginManager.swift        # Login item manager (SMAppService; persisted state via SettingKey.startAtLogin)
    │   ├── MacSelectionMonitor.swift         # Global accessibility monitor
    │   ├── MacTextRetriever.swift            # TextRetrieving facade over SelectionRetrievalCoordinator
    │   ├── OnceResume.swift                  # Exactly-once continuation resume gate (AX read + AppleScript deadline races)
    │   ├── PermissionManager.swift           # Accessibility permission manager
    │   ├── Selection/                        # Fresh-AX selection retrieval (coordinator + strategies)
    │   │   ├── AXElementInspector.swift      # Fresh focused-app/UI-element snapshot (never system-wide focused element)
    │   │   ├── AXTextControlStrategy.swift   # kAXSelectedText read for native text controls
    │   │   ├── AXWebAreaStrategy.swift       # WebKit marker-range read (settle-retry lives in the coordinator)
    │   │   ├── BrowserScriptStrategy.swift   # AppleScript-bridge page-selection read (Safari/Chromium/Firefox/Arc) + URL
    │   │   ├── CursorClassifier.swift        # Cursor image → CursorClass
    │   │   └── SelectionRetrievalCoordinator.swift # Gate + mode routing + inspect watchdog + AX Edit ▸ Copy press
    │   └── DebugLogging/                             # In-process debug log store, file sink + --dump-logs CLI (App target)
    │       ├── DebugLogEntry.swift                   # Captured log entry model (timestamp/category/level/message)
    │       ├── DebugLogLevel.swift                   # Severity level enum (values mirror OSLogEntryLog.Level)
    │       ├── DebugLogBuffer.swift                  # Thread-safe capacity-capped ring buffer (LogSink)
    │       ├── DebugLogStore.swift                   # Buffer-backed log store (0ms delay, zero polling) + .shared
    │       ├── DebugLogFilter.swift                  # Pure category/level/count filter
    │       ├── DebugLogCommand.swift                 # --dump-logs arg parsing + line formatting
    │       └── RotatingFileLogSink.swift             # Thread-safe rotating file appender (~/Library/Logs/OpenClip/openclip.log, 5MB cap, 3 backups)
    ├── StatusBarController.swift             # Reads/writes isAppEnabled via DefaultSettingsStore (SettingKey)
    └── UI/                                   # User Interface (SwiftUI & AppKit Panels)
        ├── AppIcon.swift                     # App icon loaded from the bundle's AppIcon.icns (avoids the generic placeholder NSApp.applicationIconImage can return for LSUIElement apps)
        ├── Design/
        │   └── LiquidGlass.swift             # glassSurface modifier: Liquid Glass (.glassEffect) on macOS 26+, .ultraThinMaterial fallback on macOS 14-15
        ├── Icons/
        │   └── ActionIconView.swift          # Dynamic icon renderer
        ├── Onboarding/                       # First-launch 4-step wizard (Welcome → AI → Extensions → Finish)
        │   ├── OnboardingView.swift          # Step flow; Finish step shows PopupPreview + PopupThemeSelector
        │   ├── OnboardingWindowController.swift  # Transparent borderless window hosting the solid rounded card
        │   └── RecommendedExtensionsView.swift   # Top store extensions by downloadCount + Install File
        ├── Popup/                            # Floating popup panel
        │   ├── PopupModeStore.swift            # Shared observable actions↔search↔content mode + resultCard payload (statuses now live in the toast, not the store)
        │   ├── PopupMetrics.swift                # UI-only popup/search/AI-card sizing + placement/dismissal constants (App target, not Core)
        │   ├── PopupPanel.swift                # NSPanel subclass (scoped allowsKey + bottom-edge pin on content-driven resize)
        │   ├── PopupGesturePolicy.swift        # Derived popup interaction policy from chrome + conformance (App target — UI-only)
        │   ├── PopupPositioner.swift           # Frame math & screen clamping (pure static, no singletons)
        │   ├── PopupPreview.swift              # Static popup bar preview (fixed canonical actions; Preferences Appearance tab + onboarding Finish)
        │   ├── PopupSearchView.swift           # Action-search palette: field + ranked results as one surface with the bar
        │   ├── PopupThemeModel.swift           # Theme resolution: category (classic/glass) + shared appearance → tokens/colorScheme
        │   ├── PopupThemeSelector.swift        # Theme control: two rows (Classic|Glass, then System/Light/Dark); storage popupTheme + popupThemeColor
        │   ├── PopupView.swift               # SwiftUI popup bar (action bar / AI / completions / search-mode / content result-card branch + ⌘ affordance)
        │   ├── PopupWindowController.swift   # Window lifecycle + mode state machine (bar/search/content) + event monitoring
        │   ├── ResultCardView.swift          # Native result card (back chevron + action icon/sparkles + title header, scrollable body, Copy/Paste footer) for .content mode — any text-returning action renders here
        │   ├── ToastPanel.swift                # Non-key floating NSPanel behind the status toast (borderless, non-activating, never key)
        │   ├── ToastView.swift                 # One-line SwiftUI toast `[spinner | icon] message`, PopupThemeModel-themed
        │   ├── ToastPanelController.swift      # Owns the toast panel + auto-dismiss timer; single status surface (replaces the inline banner)
        │   ├── PopupHoverSupport.swift         # Shared popup hover-state singleton + hover-target/frame preference keys (bar)
        │   └── SearchHoverSupport.swift        # Search-palette hover-target/frame preference keys
        └── Preferences/                      # Settings & preferences views
            ├── ActionAppearanceFields.swift
            ├── AddCustomActionSheet.swift
            ├── AIConfigureForm.swift           # Shared AI engine/provider form (Preferences AI tab + onboarding AI step)
            ├── ActionsTabView.swift            # Actions tab: reorderable list + ActionRowView/PackageHeaderRowView + add/install controls
            ├── AboutTabView.swift              # About tab: app icon/name/version
            ├── AppearanceTabView.swift         # Appearance tab: popup preview + theme selector
            ├── DynamicActionConfigView.swift
            ├── EditActionSheet.swift
            ├── ExtensionCardView.swift         # Store grid card for a single extension listing
            ├── ExtensionInstallPanel.swift     # Shared "Install File…" NSOpenPanel presenter
            ├── ExtensionsStoreView.swift       # Extension store browser (ViewModel + ExtensionStoreView)
            ├── GeneralTabView.swift            # General tab: enable toggle, hotkey, start-at-login, permissions
            └── PreferencesView.swift
```