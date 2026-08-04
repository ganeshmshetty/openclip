# OpenClip Directory Structure

Annotated source tree. See `docs/architecture/overview.md` for the architectural (target-split)
view; this is the detailed per-file map.

```text
Sources/
├── Core/                                     # Domain Logic (Pure Swift Target)
│   ├── Actions/
│   │   ├── Action.swift                      # Action protocol
│   │   ├── ActionChrome.swift                # UI metadata policy enum
│   │   ├── ActionContext.swift               # Action resolution context
│   │   ├── ActionCoordinator.swift           # Action execution coordinator & composition root (wires managers to registry)
│   │   ├── ActionResult.swift                # Action result value types
│   │   ├── ActionResultAdapter.swift         # Single after/stayVisible translator for extension runtime results
│   │   ├── ActionCustomizationManager.swift  # User action overrides (title/icon); delegates I/O to SettingsStore
│   │   ├── ActionPresentation.swift          # Presentation styling generator
│   │   ├── ActionRegistry.swift              # Storage, ordering, and transform default-on/off policy
│   │   ├── GroupAction.swift                 # Pure group-row action (chrome .showTransformMenu); perform → .none
│   │   ├── KeyPressSpec.swift                # Key-press spec ("mod+mod+key") parsed from manifest keyPress
│   │   ├── BubbleContent.swift               # Popup bubble value-type model (rows/options/emphasis)
│   │   ├── Builtin/                          # Core builtin actions (Copy, Cut, Paste, etc.)
│   │   │   └── TransformTextAction.swift     # TransformCase enum & transform implementations (default-on/off policy lives in TransformCase.defaultDisabledActionIDs; isRelevant(for:) drives menu smart-filtering)
│   │   ├── BuiltinRegistry.swift             # Default builtin actions catalog
│   │   ├── ConfigurableAction.swift          # Configurable action protocol (preferenceIconName)
│   │   ├── Custom/                           # Custom action draft DTO
│   │   │   └── CustomActionDraft.swift       # Value-type DTO for form editing
│   │   ├── CustomAction.swift                # Custom action domain model
│   │   ├── ExtensionOption.swift             # Extension option models
│   │   ├── ModifierFlags.swift               # Keyboard modifier flags
│   │   ├── PopupGesturePolicy.swift          # Derived popup interaction policy (click/long-press/hover) from chrome + conformance
│   │   ├── ResultBubbleProviding.swift       # Opt-in PreviewProviding / ResultBubbleProviding protocols for the bubble
│   │   ├── URLTemplateAction.swift           # Web search / URL template action
│   │   └── WordCompletionProviding.swift     # Completion provider protocol
│   ├── Extensions/
│   │   ├── ActionFactory.swift               # Action factory protocol
│   │   ├── ExtensionManager.swift            # Extension loader; reports changes via onRegister/onUnregister callbacks
│   │   ├── ExtensionsAPIClient.swift         # Remote store API client
│   │   ├── ExtensionsModels.swift            # Store models & DTOs
│   │   ├── Manifest/                         # Extension manifest structures
│   │   │   ├── ExtensionActionKind.swift     # Normalized extension kind enum
│   │   │   └── ExtensionManifest.swift       # Extension manifest decoder
│   │   ├── OpenClipSnippetParser.swift       # Standalone snippet header parser (currently @MainActor); body mode ends only at `#` header keys, `//` lines stay body
│   │   ├── ScriptAction.swift                # Executable script action
│   │   └── ShellProcessRunner.swift          # Shared subprocess executor + 30s watchdog; hosts TimeoutFlag/OnceGate; maps stdout JSON via ShellResultMapper
│   ├── Rules/                                # App-specific policy rules
│   │   ├── AppRule.swift                     # AppPolicyContext (5 active fields) + AppRule Codable model
│   │   └── RuleEngine.swift
│   ├── Selection/                            # Text selection & monitoring models
│   │   ├── AppFilter.swift
│   │   ├── AppIdentifying.swift
│   │   ├── Constants.swift                   # Timing thresholds, key codes, settings keys, scriptTimeout
│   │   ├── SelectionContext.swift
│   │   ├── SelectionCoordinator.swift
│   │   ├── SelectionMonitoring.swift
│   │   └── TextRetrieving.swift
│   ├── Settings/                             # Settings subsystem
│   │   ├── SettingKey.swift                  # Strongly-typed setting keys
│   │   └── SettingsStore.swift               # Central SettingsStore protocol + DefaultSettingsStore adapter
│   └── Utils/
│       └── TextPlaceholderEngine.swift       # Dynamic text template engine
└── OpenClip/                                 # App Target (macOS App / AppKit / SwiftUI)
    ├── AI/                                   # AI Assistant & Providers
    │   ├── AIProvider.swift
    │   ├── AIServiceManager.swift            # cloudAPIKey is Keychain-backed (@Published), other prefs via @AppStorage
    │   └── Providers/                        # Apple Intelligence, Cloud, Ollama, BrowserRedirect
    ├── Actions/                              # Runtime actions requiring AppKit/JavaScript
    │   ├── AppleScriptAction.swift
    │   ├── JavaScriptAction.swift            # Manifests JS actions; short-circuits to .openConfiguration when a required option is unresolved, else delegates to OpenClipJSHost (options via injected ActionOptionReading)
    │   ├── KeyPressAction.swift              # type: "keyPress" runtime → .keyPress(KeyPressSpec)
    │   ├── NamedServiceAction.swift          # type: "service" runtime → .showServices(text)
    │   ├── OpenClipJSHost.swift              # JS bridge (openclip.*) + effect resolver + .openConfiguration short-circuit support
    │   └── ShortcutAction.swift              # type: "shortcut" runtime → .runShortcut(name:input:)
    ├── App/
    │   └── AppServices.swift                 # UI-facing composition root
    ├── AppDelegate.swift                     # Reads isAppEnabled / hasCompletedOnboarding via UserDefaults.standard
    ├── OpenClipApp.swift                     # SwiftUI App Entrypoint
    ├── Platform/                             # macOS Platform Services
    │   ├── BuiltinActions/                   # AppKit platform actions (Services, Finder)
    │   ├── Effects/
    │   │   └── ActionResultHandler.swift     # Platform side-effects handler
    │   ├── Extensions/
    │   │   ├── DefaultActionFactory.swift    # ActionFactory implementation (routing kinds incl. keyPress/shortcut/service/group)
    │   │   ├── KeychainActionOptionStore.swift  # Composite option store; .secret options → Keychain
    │   │   ├── OpenClipSnippetParser+DefaultFactory.swift
    │   │   └── RemoteExtensionInstaller.swift
    │   ├── HotkeyManager.swift               # Global shortcut manager
    │   ├── InstalledAppsScanner.swift        # App scanner
    │   ├── KeychainStore.swift               # Generic-password SecItem wrapper for sensitive credentials (AI API key)
    │   ├── LaunchAtLoginManager.swift        # Login item manager
    │   ├── MacSelectionMonitor.swift         # Global accessibility monitor
    │   ├── MacTextRetriever.swift            # AX selection read + Safari JS; grabPasteboard apps use Cmd+C fallback
    │   └── PermissionManager.swift           # Accessibility permission manager
    ├── StatusBarController.swift             # Reads/writes isAppEnabled via UserDefaults.standard
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
        │   ├── BubbleCardView.swift            # Reusable bubble renderer (info/result/menu) for hover info, results, sub-actions
        │   ├── PopupPanel.swift                # NSPanel subclass
        │   ├── PopupPositioner.swift           # Frame math & screen clamping (pure static, no singletons)
        │   ├── PopupPreview.swift              # Static popup bar preview (fixed canonical actions; Preferences Appearance tab + onboarding Finish)
        │   ├── PopupThemeSelector.swift        # Theme control: System/Light/Dark apart from Glass; storage popupTheme + popupThemeColor
        │   ├── PopupView.swift               # SwiftUI popup bar
        │   └── PopupWindowController.swift   # Window lifecycle + bubble panel + hover/long-press timers
        └── Preferences/                      # Settings & preferences views
            ├── ActionAppearanceFields.swift
            ├── AddCustomActionSheet.swift
            ├── AIConfigureForm.swift           # Shared AI engine/provider form (Preferences AI tab + onboarding AI step)
            ├── DynamicActionConfigView.swift
            ├── EditActionSheet.swift
            ├── ExtensionsStoreView.swift
            └── PreferencesView.swift
```