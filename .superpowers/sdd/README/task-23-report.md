# Task 23 Report: JavaScriptCanvasEngine (compile-once JSScript, mount/dispatch, watchdog)

## Overview
Implemented `JavaScriptCanvasEngine: CanvasScripting, @unchecked Sendable`, powering JS canvas evaluation with single `JSVirtualMachine` session lifecycle, compile-once script, fresh `JSContext` per mount/dispatch, watchdog timeout bounds, and bounded in-flight synchronous evaluations (`OpenClipJSHost.syncEvaluationGate`).

## Changes Made
- Created `Sources/OpenClip/Actions/JavaScriptCanvasEngine.swift`:
  - `JavaScriptCanvasEngine: CanvasScripting, @unchecked Sendable`
  - `CanvasJSRuntimeError` enum (`.scriptException`, `.asyncNotSupported`, `.missingUISymbol`)
  - Fresh `JSContext(virtualMachine: virtualMachine)` per mount/dispatch.
  - Setup `CanvasScriptBox` (`installH` + `installCanvasBridge`).
  - Supports promise settlement in dispatch handlers, rejects async `ui` with `.asyncNotSupported`, bounds CPU runaway via watchdog `TimeoutFlag`, and limits concurrent sync script evaluations via `OpenClipJSHost.syncEvaluationGate`.
- Extended `Sources/OpenClip/Actions/CanvasScriptBox.swift`:
  - Added `installCanvasBridge(in:input:optionValues:effectsBox:keepVisibleBox:)` and `CanvasEffectsBox`/`CanvasKeepVisibleBox` support classes.
- Updated `Sources/OpenClip/Actions/OpenClipJSHost.swift`:
  - Made `syncEvaluationGate` internal (`static let syncEvaluationGate`).
- Updated `Sources/OpenClip/UI/Popup/PopupWindowController.swift`:
  - Replaced `UnavailableCanvasEngine()` with `JavaScriptCanvasEngine()`.
- Deleted `Sources/OpenClip/UI/Popup/UnavailableCanvasEngine.swift`.
- Executed `xcodegen generate` (project regenerated).
- Created `Tests/OpenClipTests/JavaScriptCanvasEngineTests.swift`:
  - 15 comprehensive unit tests covering counter mount/dispatch, textField change/submit, effect collection, keepVisible unwrapping, unknown handler fallback, tree limits, non-object UI return, missing UI symbol, watchdog timeout on mount/dispatch, sync cap, async UI rejection, gate slot release, helper re-installation, and async promise settlement.

## Verification
1. `JavaScriptCanvasEngineTests`:
   - `./scripts/test.sh JavaScriptCanvasEngineTests` -> **TEST SUCCEEDED** (15/15 tests passed).
2. `PopupCanvasTests`:
   - `./scripts/test.sh PopupCanvasTests` -> **TEST SUCCEEDED** (all tests passed).
3. Full Test Suite:
   - `./scripts/test.sh` -> **TEST SUCCEEDED** (100% full suite passing).
