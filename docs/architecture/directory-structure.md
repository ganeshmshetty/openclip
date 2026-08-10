# OpenClip Directory Structure

Annotated source tree. See `docs/architecture/overview.md` for the architectural (target-split)
view; this is the detailed per-file map.

```text
Sources/
├── Core/                                     # Domain Logic (Pure Swift Target)
│   ├── Log.swift                             # Single Log enum: per-subsystem os.Logger categories (see docs/logging.md)
│   ├── Actions/
│   │   ├── Action.swift                      # Action protocol
│   │   ├── ActionChrome.swift                # UI metadata policy enum
│   │   ├── ActionContext.swift               # Action resolution context
│   │   ├── ActionCoordinator.swift           # Action execution coordinator & composition root (wires managers to registry)
│   │   ├── ActionResult.swift                # Action result value types
│   │   ├── ActionResultAdapter.swift         # Single after/stayVisible translator for extension runtime results
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
│   │   ├── PopupGesturePolicy.swift          # Derived popup interaction policy (click/long-press/hover) from chrome + conformance
│   │   ├── ResultContentProviding.swift       # Opt-in PreviewProviding / ResultContentProviding protocols for the content canvas
│   │   ├── URLTemplateAction.swift           # Web search / URL template action
│   │   └── WordCompletionProviding.swift     # Completion provider protocol
│   ├── Canvas/                               # Interactive canvas component model (pure, spec §4–§6)
│   │   ├── CanvasComponent.swift             # Typed component tree + props + CanvasEvent/CanvasEffect/CanvasHandler
│   │   ├── CanvasSessionState.swift          # App-owned session state bag (JSONValue values)
│   │   ├── CanvasLimits.swift                # Canvas tree limits + CanvasTreeValidator (structural rejection)
│   │   ├── CanvasScripting.swift             # Engine-agnostic mount/dispatch seam (CanvasMountRequest/Result, CanvasDispatchRequest/Result)
│   │   ├── CanvasElementSpec.swift           # Neutral Codable element-object form of a canvas node (h() output)
│   │   ├── CanvasElementParser.swift         # CanvasElementSpec → CanvasComponent (lenient per-node, strict structurally)
│   │   ├── CanvasFocus.swift                 # Focus-priority ordering over interactive nodes (firstInteractiveID)
│   │   └── CanvasDSL.swift                   # Canvas.build result-builder + Canvas.* constructors (native trees)
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
│   │   ├── Constants.swift                   # Timing thresholds, key codes, settings keys, scriptTimeout
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
    │   ├── AIProvider.swift
    │   ├── AIServiceManager.swift            # cloudAPIKey is Keychain-backed (@Published), other prefs via @AppStorage
    │   └── Providers/                        # Apple Intelligence, Cloud, Ollama, BrowserRedirect
    │       ├── CloudAPIProvider.swift        # OpenAI-compatible / Anthropic / Gemini cloud chat
    │       └── CloudAPIProviderDTOs.swift    # Codable chat request/response payloads for the cloud APIs
    ├── Actions/                              # Runtime actions requiring AppKit/JavaScript
    │   ├── AppleScriptAction.swift
    │   ├── CanvasScriptBox.swift              # Canvas JSContext glue: h() helper, element bridging, openclip canvas bridge
    │   ├── JavaScriptAction.swift            # Manifests JS actions; short-circuits to .openConfiguration when a required option is unresolved, else delegates to OpenClipJSHost (options via injected ActionOptionReading)
    │   ├── JavaScriptCanvasAction.swift      # type: "canvas" runtime → .showCanvas mount request (never runs the script itself)
    │   ├── JavaScriptCanvasEngine.swift      # In-process JavaScriptCore CanvasScripting engine (session VM, mount/dispatch eval)
    │   ├── KeyPressAction.swift              # type: "keyPress" runtime → .keyPress(KeyPressSpec)
    │   ├── NamedServiceAction.swift          # type: "service" runtime → .showServices(text)
    │   ├── OpenClipJSHost.swift              # JS bridge (openclip.*) + effect resolver + .openConfiguration short-circuit support
    │   ├── OpenClipJSHostSupport.swift       # Threading/support boxes for the JS host (TimeoutFlag, gate, JS context/value/runloop boxes, promise state)
    │   └── ShortcutAction.swift              # type: "shortcut" runtime → .runShortcut(name:input:)
    ├── App/
    ├── AppDelegate.swift                     # Reads isAppEnabled / hasCompletedOnboarding via UserDefaults.standard
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
    │   ├── LaunchAtLoginManager.swift        # Login item manager
    │   ├── MacSelectionMonitor.swift         # Global accessibility monitor
    │   ├── MacTextRetriever.swift            # AX selection read + Safari JS; grabPasteboard apps use Cmd+C fallback
    │   ├── OnceResume.swift                  # Exactly-once continuation resume gate (AX read + AppleScript deadline races)
    │   ├── PermissionManager.swift           # Accessibility permission manager
    │   └── DebugLogging/                             # In-process debug log store + --dump-logs CLI (App target)
    │       ├── DebugLogEntry.swift                   # Captured log entry model (timestamp/category/level/message)
    │       ├── DebugLogLevel.swift                   # Severity level enum (values mirror OSLogEntryLog.Level)
    │       ├── DebugLogBuffer.swift                  # Thread-safe capacity-capped ring buffer
    │       ├── DebugLogReader.swift                  # LogReading protocol + OSLogStore-backed UnifiedLogReader
    │       ├── DebugLogStore.swift                   # 1s background poller + .shared
    │       ├── DebugLogFilter.swift                  # Pure category/level/count filter
    │       └── DebugLogCommand.swift                 # --dump-logs arg parsing + line formatting
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
        │   ├── PopupModeStore.swift            # Shared observable actions↔search↔content mode + content/preview/statusBanner payloads; preview passes a throwaway store
        │   ├── PopupPanel.swift                # NSPanel subclass (scoped allowsKey + bottom-edge pin on content-driven resize)
        │   ├── PopupPositioner.swift           # Frame math & screen clamping (pure static, no singletons)
        │   ├── PopupPreview.swift              # Static popup bar preview (fixed canonical actions; Preferences Appearance tab + onboarding Finish)
        │   ├── PopupPreviewStrip.swift         # Compact inline hover-preview strip stacked with the bar
        │   ├── PopupSearchView.swift           # Action-search palette: field + ranked results as one surface with the bar
        │   ├── PopupThemeModel.swift           # Theme resolution: category (classic/glass) + shared appearance → tokens/colorScheme
        │   ├── PopupThemeSelector.swift        # Theme control: two rows (Classic|Glass, then System/Light/Dark); storage popupTheme + popupThemeColor
        │   ├── PopupView.swift               # SwiftUI popup bar (action bar / AI / completions / search-mode / content-canvas branch + ⌘ affordance)
        │   ├── PopupWindowController.swift   # Window lifecycle + mode state machine (bar/search/content) + hover/long-press timers
        │   ├── CanvasComponentView.swift       # Renders one CanvasComponent node (stack/text/button/field/toggle/…)
        │   ├── CanvasHeaderView.swift          # Chrome header (title/icon + back chevron) for the content-canvas surface
        │   ├── CanvasSession.swift             # Observable unit: one tree + app-owned state + chrome header + optional scripting engine
        │   ├── CanvasSessionController.swift   # Single active session owner: serialized mount/dispatch chain + focus restore; effects/status/armed doors
        │   ├── CanvasSessionView.swift         # Content-canvas surface: chrome header + scrollable body + Esc collapse (.onKeyPress)
        │   ├── PopupHoverSupport.swift         # Shared popup hover-state singleton + hover-target/frame preference keys (bar)
        │   ├── SearchHoverSupport.swift        # Search-palette hover-target/frame preference keys
        │   └── CanvasHoverSupport.swift        # Content-canvas hover-target/frame preference keys
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
            ├── InstalledExtensionsView.swift   # Installed extensions sub-tab with per-row uninstall
            └── PreferencesView.swift
```