# Decision Tools experiment — summary

Branch: `feat/decision-tools-experiment`  
Feature stack: **Decision Tools** as a first-class peer to AI Tools (judge selection → typed answers; never paste essays).

## How to try it (on macOS)

1. `cd` to this repo, `xcodegen generate`, then `./scripts/dev_run.sh` (or open `OpenClip.xcodeproj`).
2. Open **Settings → Decisions** (sidebar, next to AI). Toggle **Enable Decision Tools**.
3. Pick a provider:
   - **Laya (local)** — press **Install Laya**: OpenClip creates `~/.openclip/laya/venv` (uv, else python3 ≥ 3.10), installs `laya` + PyTorch, downloads the checkpoint (~800 MB) and keeps `laya_bridge.py` resident. No key, nothing leaves the Mac.
   - **Jev** — set Base URL (`https://api.typesafe.ai/v1`) + API key (SecretStore).
4. Enable default tools (Smart action, Triage, Reply as…, Send to…, Safe to share?, Fix path, Clean this list) or add/edit/duplicate/delete like AI tools.
5. Select text → open the popup → **Decision Tools** bar entry (or palette search for a tool name) → see the **decision card** (chips + confidence), not an AI prose card.
6. Optional: enable **Live assist** (off by default) on the Decisions page, or for 30 minutes / 1 hour / until tomorrow from the menu bar's **Live Assist** submenu; read the privacy blurb on the Decisions page.

No real API keys are committed. Unit tests cover packing, parsing, tree stepping, bulk split/reduce, and mock provider evaluation (`./scripts/test.sh` on macOS).

## Implemented

| Area | Status |
| :--- | :--- |
| Core models (`DecisionQuestion` / `Answer` / `Presentation`, packer, response parser) | Done |
| Decision trees (coarse→fine, fan-out, fail-closed, depth cap) + Triage builtin tree | Done |
| Bulk map/reduce (line/row/word/span/paragraph, unit cap ~100, wall-clock budget) | Done |
| Providers: Jev (System One POST), Laya via managed Python runtime + bundled bridge | Done (Jev wire format still unverified against the real API) |
| `DecisionServiceManager` + SecretStore keys + Settings keys / catalog | Done |
| Default tools CRUD (add/edit/duplicate/delete/reorder) + Defaults reset | Done |
| Bar launcher `builtin.decisionTools` + palette presets (`chrome.source == .decision`) | Done |
| Settings page **Decisions** (peer to AI) + toolbar enable toggle | Done |
| Answer UI: `DecisionCardView` chips + confidence meter + confirm / paste-filtered | Done |
| `ActionResult.decision` + popup presentation path | Done |
| Live assist engine: opt-in, debounce 100–300ms, cancel in-flight, prefer Laya, privacy copy | Done |
| Unit tests (packer, parser, tree, bulk, actions/chrome) | Done |
| CHANGELOG Unreleased + user-guide / logging / directory-structure notes | Done |

## Stubbed / partial (clear TODOs)

| Gap | Notes |
| :--- | :--- |
| **Full any-field AX focus monitoring** | Setting + debounce engine + privacy docs ship; `axFocusMonitoringAvailable == false` with Settings status. Live assist uses current OpenClip selection / explicit `schedule(selectionText:)`. |
| **Live palette intent / Safe-to-share pill chrome** | Engine APIs (`DecisionLiveSuggestion.Kind`) exist; wiring into every palette/pill surface is minimal — call `DecisionLiveAssistEngine.shared.schedule(...)` from selection/palette hosts as follow-up. |
| **Linux compile** | macOS AppKit/SwiftUI app; this environment cannot run `xcodebuild`. Files are under `Sources/` and `Tests/` so `xcodegen generate` picks them up from `project.yml` globs. |

## Major new files

### Core
- `Sources/Core/Decisions/DecisionQuestion.swift`
- `Sources/Core/Decisions/DecisionAnswer.swift`
- `Sources/Core/Decisions/DecisionTree.swift`
- `Sources/Core/Decisions/DecisionBulk.swift`
- `Sources/Core/Decisions/DecisionToolPreset.swift`

### App
- `Sources/OpenClip/Decisions/DecisionProvider.swift`
- `Sources/OpenClip/Decisions/DecisionServiceManager.swift`
- `Sources/OpenClip/Decisions/DecisionAction.swift`
- `Sources/OpenClip/Decisions/DecisionToolsAction.swift`
- `Sources/OpenClip/Decisions/DecisionActionSync.swift`
- `Sources/OpenClip/Decisions/DecisionLiveAssistEngine.swift`
- `Sources/OpenClip/Decisions/Providers/JevDecisionProvider.swift`
- `Sources/OpenClip/Decisions/Providers/LayaDecisionProvider.swift`
- `Sources/OpenClip/Decisions/Laya/LayaRuntime.swift`
- `Sources/OpenClip/Resources/laya_bridge.py`
- `Sources/OpenClip/UI/Preferences/LayaRuntimeSection.swift`
- `Sources/OpenClip/Settings/SettingKey+Decisions.swift`
- `Sources/OpenClip/UI/Preferences/DecisionsPage.swift`
- `Sources/OpenClip/UI/Popup/DecisionCardView.swift`

### Tests
- `Tests/OpenClipTests/DecisionQuestionPackerTests.swift`
- `Tests/OpenClipTests/DecisionResponseParserTests.swift`
- `Tests/OpenClipTests/DecisionTreeStepperTests.swift`
- `Tests/OpenClipTests/DecisionBulkTests.swift`
- `Tests/OpenClipTests/DecisionActionTests.swift`
- `Tests/OpenClipTests/ActionChromeDecisionTests.swift`

## Project wiring notes

- `project.yml` already globs `Sources/Core`, `Sources/OpenClip`, `Tests/OpenClipTests` — **re-run `xcodegen generate`** after pull so new Swift files enter the Xcode project.
- Extended seams: `ActionChrome.Source.decision`, `launchesDecisions`, `ActionResult.decision`, `ActionIdentity.isDecisionPreset`, registry bar/palette filters, Settings router/sidebar/toolbar, `AppDelegate` sync bootstrap.
- Swift 6 / concurrency: managers and providers are `@MainActor`; Core decision types are `Sendable`.
