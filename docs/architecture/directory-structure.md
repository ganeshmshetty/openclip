# OpenClip Directory Structure

Annotated source tree. See `docs/architecture/overview.md` for the architectural (target-split)
view; this is the detailed per-file map.

```text
Sources/
├── Core/                                     # Domain Logic (Pure Swift Target)
│   ├── Core.swift                            # Module exports
│   ├── Log.swift                             # Single logging surface: Log enum, LogChannel, LogSink protocol, LogLevel, LogMessage (see docs/logging.md)
│   ├── Actions/
│   │   ├── Action.swift                      # Action protocol
│   │   ├── ActionChrome.swift                # UI metadata policy enum
│   │   ├── ActionContext.swift               # Action resolution context
│   │   ├── ActionCoordinator.swift           # Action execution coordinator & composition root (wires managers to registry)
│   │   ├── ActionCustomizationManager.swift  # User action overrides (title/icon); delegates I/O to SettingsStore
│   │   ├── ActionDelivery.swift              # Per-action delivery: secondary outcome + per-click toasts
│   │   ├── ActionGroupDef.swift              # User-defined action group Codable model
│   │   ├── ActionIdentity.swift              # Action identification helpers (builtin, AI preset, extension package)
│   │   ├── ActionMatchInfo.swift             # Regex match context & capture payload
│   │   ├── ActionRegistry.swift              # Storage, ordering, and transform default-on/off policy
│   │   ├── ActionResult.swift                # Action result value types
│   │   ├── ActionResultDelivery.swift        # Select → Probe → Toast: paste-vs-copy delivery decision (resolves (result, toast))
│   │   ├── ActionSearch.swift                # Popup mode enum + pure substring matcher for the action-search palette
│   │   ├── ActionVisibility.swift            # Pure visibility & requirement evaluation logic
│   │   ├── Builtin/                          # Core builtin actions (Copy, Cut, Paste, Calculate, Calendar, Define, Search)
│   │   │   ├── CalculateAction.swift
│   │   │   ├── CalendarAction.swift
│   │   │   ├── CopyAction.swift
│   │   │   ├── CutAction.swift
│   │   │   ├── DefineAction.swift
│   │   │   ├── PasteAction.swift
│   │   │   ├── SearchAction.swift
│   │   │   └── SearchEnginePreset.swift      # Built-in search engine preset configurations
│   │   ├── BuiltinRegistry.swift             # Default builtin actions catalog
│   │   ├── ConfigurableAction.swift          # Configurable action protocol (preferenceIconName)
│   │   ├── ConfigurationRequest.swift        # Required-option configuration request model
│   │   ├── Custom/                           # Custom action draft DTO
│   │   │   └── CustomActionDraft.swift       # Value-type DTO for form editing
│   │   ├── CustomAction.swift                # Custom action domain model
│   │   ├── CustomGroupAction.swift           # Custom action group runtime instance
│   │   ├── DeliveryDecoratedAction.swift     # Pure wrapper stamping a declared ActionDelivery onto an action
│   │   ├── ExtensionActionRules.swift        # Action requirements & visibility rules evaluator
│   │   ├── ExtensionOption.swift             # Extension option models
│   │   ├── GroupAction.swift                 # Pure group-row action (chrome .showSubActions); perform → .none
│   │   ├── KeyPressSpec.swift                # Key-press spec ("mod+mod+key") parsed from manifest keyPress
│   │   ├── MathEvaluator.swift               # Deterministic exception-free arithmetic parser (replaces NSExpression; used by CalculateAction)
│   │   ├── MenuDecoratedAction.swift         # Sub-menu relevance decorator
│   │   ├── ModifierFlags.swift               # Keyboard modifier flags
│   │   ├── PasteRequiringAction.swift        # Protocol for actions requiring paste capability (Paste, Cut)
│   │   ├── RelevanceProviding.swift          # Sub-menu relevance protocol
│   │   ├── RichPasteboardPayload.swift       # Multi-format pasteboard payload (text, HTML, RTF)
│   │   ├── StatusFeedback.swift              # Toast notification model
│   │   ├── SubAction.swift                   # SubActionProviding protocol
│   │   ├── TopLevelActionItem.swift          # Top-level action/group representation
│   │   ├── URLTemplateAction.swift           # Web search / URL template action
│   │   └── WordCompletionProviding.swift     # Completion provider protocol
│   ├── Extensions/
│   │   ├── ActionFactory.swift               # Action factory protocol
│   │   ├── ExtensionManager.swift            # Extension loader; reports changes via onRegister/onUnregister callbacks
│   │   ├── ExtensionPackageInfo.swift        # Metadata for installed extension packages
│   │   ├── ExtensionStoreCache.swift         # In-memory store cache
│   │   ├── ExtensionUpdateBatchResult.swift  # Batch update result summary
│   │   ├── ExtensionUpdatePlanner.swift      # Extension update plan evaluator
│   │   ├── ExtensionsAPIClient.swift         # Remote store API client
│   │   ├── ExtensionsModels.swift            # Store models & DTOs
│   │   ├── Manifest/                         # Extension manifest structures
│   │   │   ├── ActionRequirements.swift      # Requirements model (regex, apps, requiredOptions, expression)
│   │   │   ├── ExtensionActionKind.swift     # Normalized extension kind enum
│   │   │   ├── ExtensionManifest.swift       # Extension manifest decoder
│   │   │   ├── ExtensionManifestStore.swift  # Manifest file locate/read/write (shared home)
│   │   │   ├── ManifestValidation.swift      # Manifest validation pass + empty capability gate + fingerprint record
│   │   │   └── ValidateExpression.swift      # Computed visibility expression DSL AST & evaluator
│   │   ├── OpenClipSnippetParser.swift       # Standalone snippet header parser (nonisolated, pure text); body mode ends only at `#` header keys, `//` lines stay body
│   │   ├── ScriptAction.swift                # Executable script action
│   │   ├── ShellProcessRunner.swift          # Shared subprocess executor; GCD-timer 60s watchdog always terminates the child, signals the process group only when the child is group leader, and otherwise signals snapshotted descendants individually + readabilityHandler reads (never blocks a thread); hosts TimeoutFlag/OnceGate; maps stdout JSON via ShellResultMapper
│   │   └── Trust/                            # Extension trust & consent gate
│   │       ├── ContentFingerprint.swift      # Package SHA-256 fingerprinting
│   │       ├── ExtensionPackageHashResolver.swift # Recursive package hashing
│   │       ├── ExtensionRiskProfile.swift    # Extension risk assessment
│   │       ├── ExtensionTrustGate.swift      # Trust state decision engine
│   │       ├── ExtensionTrustState.swift     # Trust lifecycle states (seen/trusted/revoked)
│   │       └── SemanticVersion.swift         # Semantic version parser & comparator
│   ├── Lifecycle/
│   │   └── AppLaunchClassifier.swift         # Startup scenario classifier (firstInstall, appUpdate, permissionRecovery, normalLaunch)
│   ├── Rules/                                # App-specific policy rules
│   │   ├── AppRule.swift                     # AppPolicyContext (5 active fields) + AppRule Codable model
│   │   ├── DefaultAppRules.swift             # Curated default application policy rules
│   │   ├── PasteAvailability.swift           # Paste availability tri-state (canPaste, cannotPaste, unknown)
│   │   ├── RuleEngine.swift                  # Rule lookup and policy resolver
│   │   ├── SelectionGatePolicy.swift         # Pre-retrieval role & cursor gate policy
│   │   └── SelectionRetrievalMode.swift      # Selection retrieval strategy selector
│   ├── Selection/                            # Text selection & monitoring models
│   │   ├── AppFilter.swift                   # App bundle filtering helpers
│   │   ├── AppIdentifying.swift              # Application identity protocol
│   │   ├── BrowserDetector.swift             # Browser bundle ID classifier
│   │   ├── Constants.swift                   # Domain/runtime constants (timeouts, key codes, env vars, manifest keys) — no UI sizing
│   │   ├── SelectionContext.swift            # Selection snapshot context
│   │   ├── SelectionMonitoring.swift         # Selection monitor protocol
│   │   ├── TextRetrieving.swift              # Text retrieval protocol
│   │   └── TextSanitizer.swift               # Whitespace & zero-width character sanitization
│   ├── Settings/                             # Settings subsystem
│   │   ├── ActionOptionStore.swift           # ActionOptionReading & ActionOptionWriting protocols + SettingsActionOptionStore
│   │   ├── ActionUsageStore.swift            # Usage frequency tracking for search ranking
│   │   ├── SettingKey.swift                  # Strongly-typed setting keys
│   │   └── SettingsStore.swift               # Central SettingsStore protocol + DefaultSettingsStore adapter
│   └── Utils/
│       └── TextPlaceholderEngine.swift       # Dynamic text template engine ({text}, {query}, {html}, {rtf}, {matched}, {captureN}, {bundleID})
└── OpenClip/                                 # App Target (macOS App / AppKit / SwiftUI)
    ├── AppDelegate.swift                     # Reads isAppEnabled / hasCompletedOnboarding via DefaultSettingsStore (SettingKey)
    ├── OpenClipApp.swift                     # SwiftUI App Entrypoint
    ├── StatusBarController.swift             # Status bar item management (reads/writes isAppEnabled / showMenuBarIcon)
    ├── AI/                                   # AI Assistant & Providers
    │   ├── AIAction.swift                    # Action conforming AI preset runner
    │   ├── AIActionSync.swift                # Synchronizes AIAction instances with AIServiceManager presets
    │   ├── AIProvider.swift                  # AIProvider protocol & prompt formatting
    │   ├── AIServiceManager.swift            # cloudAPIKey is SecretStore-backed (@Published), other prefs via @AppStorage
    │   ├── AIToolsAction.swift               # AI Tools group launcher action
    │   └── Providers/                        # Apple Intelligence, Cloud, Ollama, BrowserRedirect
    │       ├── AppleIntelligenceProvider.swift # On-device Apple Intelligence runner
    │       ├── BrowserRedirectProvider.swift   # Browser search redirect runner
    │       ├── CloudAPIProvider.swift        # OpenAI-compatible / Anthropic / Gemini / DeepSeek / Groq cloud chat
    │       ├── CloudAPIProviderDTOs.swift    # Codable chat request/response payloads for cloud APIs
    │       └── OllamaProvider.swift          # Local Ollama runner
    ├── Notifications/
    │   └── Notification.Name+OpenClip.swift  # Internal notification names
    ├── Platform/                             # macOS Platform Services
    │   ├── ActionIconImageHelper.swift       # Icon rendering helper
    │   ├── AppIdentifying+NSRunningApplication.swift # AppIdentifying conformance
    │   ├── AppleScriptRunner.swift           # Bounded off-main AppleScript executor (killable osascript subprocess via ShellProcessRunner)
    │   ├── AppUpdateManager.swift            # Sparkle software update coordinator
    │   ├── BuiltinActions/                   # AppKit platform actions (Services, Finder, Completions)
    │   │   ├── CompletionAction.swift
    │   │   ├── OpenURLAction.swift
    │   │   └── RevealInFinderAction.swift
    │   ├── DebugLogging/                     # In-process debug log store, file sink + --dump-logs CLI (App target)
    │   │   ├── DebugLogBuffer.swift          # Thread-safe capacity-capped ring buffer (LogSink)
    │   │   ├── DebugLogCommand.swift         # --dump-logs arg parsing + line formatting
    │   │   ├── DebugLogEntry.swift           # Captured log entry model (timestamp/category/level/message)
    │   │   ├── DebugLogFilter.swift          # Pure category/level/count filter
    │   │   ├── DebugLogLevel.swift           # Severity level enum (values mirror OSLogEntryLog.Level)
    │   │   ├── DebugLogStore.swift           # Buffer-backed log store (0ms delay, zero polling) + .shared
    │   │   ├── LogExporter.swift             # Diagnostic log archive exporter
    │   │   └── RotatingFileLogSink.swift     # Thread-safe rotating file appender (~/Library/Logs/OpenClip/openclip.log, 5MB cap, 3 backups)
    │   ├── Effects/
    │   │   └── ActionResultHandler.swift     # Platform side-effects handler (pasteboard, workspace, sharing, shortcuts, key events)
    │   ├── Extensions/
    │   │   ├── CustomActionManifestWriter.swift # GUI-authored custom action manifest serializer
    │   │   ├── DefaultActionFactory.swift    # ActionFactory implementation (routing kinds incl. keyPress/shortcut/service/group)
    │   │   ├── ExtensionsDirectoryWatcher.swift # Hot reload directory watcher for ~/.openclip/extensions
    │   │   ├── ExtensionUpdateManager.swift  # Extension store update checker
    │   │   ├── OpenClipSnippetParser+DefaultFactory.swift # Snippet parser factory integration
    │   │   ├── RemoteExtensionInstaller.swift # Zip download and extraction installer
    │   │   └── SecretActionOptionStore.swift # Composite option store; .secret options → SecretStore (~/.openclip/secrets.json)
    │   ├── HotkeyManager.swift               # Global shortcut manager (⌥⌘C toggles popup actions → search → dismiss when visible)
    │   ├── InstalledAppsScanner.swift        # Running and installed app scanner
    │   ├── LaunchAtLoginManager.swift        # Login item manager (SMAppService; persisted state via SettingKey.startAtLogin)
    │   ├── MacSelectionMonitor.swift         # Global accessibility selection monitor
    │   ├── MacTextRetriever.swift            # TextRetrieving facade over SelectionRetrievalCoordinator
    │   ├── OnceResume.swift                  # Exactly-once continuation resume gate (AX read + AppleScript deadline races)
    │   ├── PasteAvailabilityProbe.swift      # AX probe walking Edit ▸ Paste menu items
    │   ├── PasteboardCopyEngine.swift        # Transient pasteboard archive-and-restore copy engine
    │   ├── PasteboardSnapshot.swift          # Pasteboard item state capture
    │   ├── PermissionManager.swift           # Accessibility permission manager
    │   ├── Runtimes/                         # Runtime action executors requiring AppKit / JavaScriptCore
    │   │   ├── AppleScriptAction.swift       # AppleScript action runtime
    │   │   ├── JavaScriptAction.swift        # Manifests JS actions; short-circuits to .openConfiguration when required option unresolved, else delegates to OpenClipJSHost
    │   │   ├── JSNativeFetch.swift           # JS fetch() URLSession polyfill
    │   │   ├── KeyPressAction.swift          # type: "keyPress" runtime → .keyPress(KeyPressSpec)
    │   │   ├── NamedServiceAction.swift      # type: "service" runtime → .showServices(text)
    │   │   ├── OpenClipJSHost.swift          # JS bridge (openclip.*) + effect resolver + .openConfiguration short-circuit support
    │   │   ├── OpenClipJSHostSupport.swift   # Threading/support boxes for the JS host (TimeoutFlag, gate, JS context/value/runloop boxes, promise state)
    │   │   ├── OpenClipModuleLoader.swift    # CommonJS require() module loader and containment validator
    │   │   └── ShortcutAction.swift          # type: "shortcut" runtime → .runShortcut(name:input:)
    │   ├── SecretStore.swift                 # File-backed secrets storage (~/.openclip/secrets.json, POSIX 0600)
    │   ├── Selection/                        # Fresh-AX selection retrieval (coordinator + strategies)
    │   │   ├── AXElementInspector.swift      # Fresh focused-app/UI-element snapshot (never system-wide focused element)
    │   │   ├── AXMenuNavigator.swift         # Accessibility menu traversal for Edit ▸ Copy/Paste
    │   │   ├── AXTextControlStrategy.swift   # kAXSelectedText read for native text controls
    │   │   ├── AXWebAreaStrategy.swift       # WebKit marker-range read (settle-retry lives in the coordinator)
    │   │   ├── BrowserScriptStrategy.swift   # AppleScript-bridge page-selection read (Safari/Chromium/Firefox/Arc) + URL
    │   │   ├── CursorClassifier.swift        # Cursor image → CursorClass
    │   │   └── SelectionRetrievalCoordinator.swift # Gate + mode routing + inspect watchdog + AX Edit ▸ Copy press
    │   └── UnifiedIconProvider.swift         # Unified icon loader and cache
    ├── Resources/
    │   └── Localizable.xcstrings             # App string catalog (en source + zh-Hans). Regenerate with scripts/generate_localizable.py
    ├── Settings/
    │   └── SettingKey+MenuBar.swift          # Menu bar visibility setting key definition
    └── UI/                                   # User Interface (SwiftUI & AppKit Panels)
        ├── AppIcon.swift                     # App icon loaded from bundle AppIcon.icns
        ├── CoachMark/
        │   └── CoachMarkController.swift     # First-launch coach-mark nudge
        ├── Design/
        │   └── LiquidGlass.swift             # glassSurface modifier: Liquid Glass (.glassEffect) on macOS 26+, .ultraThinMaterial fallback on macOS 14-15
        ├── Icons/
        │   ├── ActionIconView.swift          # Dynamic icon renderer
        │   └── LocalIconCache.swift          # In-memory and disk icon image cache
        ├── Onboarding/                       # First-launch 4-step wizard (Welcome → Access → Extensions → Try It)
        │   ├── OnboardingView.swift          # Step flow view (Welcome, Access, Extensions, Try It)
        │   ├── OnboardingWindowController.swift # Transparent borderless window hosting the onboarding card
        │   ├── RecommendedExtensionsView.swift  # Top recommended extensions listing + Install File
        │   └── SandboxTextView.swift         # Interactive text selection playground
        ├── PermissionRecovery/
        │   ├── PermissionRecoveryView.swift  # Accessibility permission re-prompt UI
        │   └── PermissionRecoveryWindowController.swift # Permission recovery window controller
        ├── Popup/                            # Floating popup panel
        │   ├── GroupSubActionBarView.swift   # Sub-bar action items view
        │   ├── PopupGesturePolicy.swift      # Derived popup interaction policy from chrome + conformance (App target — UI-only)
        │   ├── PopupHoverSupport.swift       # Shared popup hover-state singleton + hover-target/frame preference keys (bar)
        │   ├── PopupMetrics.swift            # UI-only popup/search/AI-card sizing + placement/dismissal constants (App target, not Core)
        │   ├── PopupModeStore.swift          # Shared observable actions↔search↔content mode + resultCard payload
        │   ├── PopupPageLayout.swift         # Pagination metrics & chunking
        │   ├── PopupPanel.swift              # NSPanel subclass (scoped allowsKey + bottom-edge pin on content-driven resize)
        │   ├── PopupPositioner.swift         # Frame math & screen clamping (pure static, no singletons)
        │   ├── PopupPreview.swift            # Static popup bar preview (fixed canonical actions; Preferences Appearance tab)
        │   ├── PopupSearchView.swift         # Action-search palette: field + ranked results as one surface with the bar
        │   ├── PopupThemeModel.swift         # Theme resolution: category (classic/glass) + shared appearance → tokens/colorScheme
        │   ├── PopupThemeSelector.swift      # Theme control: two rows (Classic|Glass, then System/Light/Dark); storage popupTheme + popupThemeColor
        │   ├── PopupView.swift               # SwiftUI popup bar (action bar / AI / completions / search-mode / content result-card branch + ⌘ affordance)
        │   ├── PopupWindowController.swift   # Window lifecycle + mode state machine (bar/search/content) + event monitoring
        │   ├── ResultCardView.swift          # Native result card (back chevron + action icon/sparkles + title header, scrollable body, Copy/Paste footer) for .content mode
        │   ├── SearchHoverSupport.swift      # Search-palette hover-target/frame preference keys
        │   ├── SubBarPanel.swift             # Sub-action menu floating NSPanel
        │   ├── SubBarPanelController.swift   # Controller managing the sub-action bar panel lifecycle
        │   ├── SubBarState.swift             # Sub-bar visibility state model
        │   ├── ToastPanel.swift              # Non-key floating NSPanel behind the status toast
        │   ├── ToastPanelController.swift    # Owns the toast panel + auto-dismiss timer; single status surface
        │   └── ToastView.swift               # One-line SwiftUI toast `[spinner | icon] message`, PopupThemeModel-themed
        └── Preferences/                      # Settings & preferences views
            ├── AboutTabView.swift            # About tab: app icon/name/version
            ├── ActionAppearanceFields.swift
            ├── ActionsTabView.swift          # Actions tab: reorderable list + ActionRowView/PackageHeaderRowView + add/install controls
            ├── AddCustomActionSheet.swift    # Sheet to create new custom action
            ├── AIConfigureForm.swift         # Shared AI engine/provider form
            ├── AITab.swift                   # Preferences AI configuration tab
            ├── AppearanceTabView.swift       # Appearance tab: popup preview + theme selector
            ├── AppPickerSheet.swift          # Running/installed app selector sheet
            ├── AppRulesTab.swift             # Application rules configuration tab
            ├── CreateGroupSheet.swift        # Custom action group creation sheet
            ├── DynamicActionConfigView.swift # Dynamic extension options configuration view
            ├── EditActionSheet.swift         # Custom action editor sheet
            ├── EditGroupSheet.swift          # Custom action group editor sheet
            ├── ExtensionCardView.swift       # Store grid card for a single extension listing
            ├── ExtensionInstallPanel.swift   # Shared "Install File…" NSOpenPanel presenter
            ├── ExtensionsStoreView.swift     # Extension store browser (ViewModel + ExtensionStoreView)
            ├── GeneralTabView.swift          # General tab: enable toggle, hotkey, start-at-login, menu bar, permissions
            ├── IconPickerView.swift          # SF Symbol icon picker sheet
            └── PreferencesView.swift         # Preferences window root view tab bar
```