### Task 19 Report: Migrate ResultContentProviding + CalculateAction + beginLongPressIfNeeded + ActionResultAdapter

**Status:** Completed
**Timestamp:** 2026-08-09T09:57:30+05:30

#### Summary of Changes:
1. **ResultContentProviding protocol (`Sources/Core/Actions/ResultContentProviding.swift`)**:
   - Updated `makeContent(for:)` signature to return `CanvasComponent?` instead of `PopupContent?`.

2. **CalculateAction (`Sources/Core/Actions/Builtin/CalculateAction.swift`)**:
   - Rewrote `makeContent(for:)` to return a `CanvasComponent` tree using `Canvas.build` DSL, producing a `.stack` containing a result string `Canvas.text` and `.button` options for paste/copy with `CanvasIconSource.symbol` icons.

3. **PopupWindowController (`Sources/OpenClip/UI/Popup/PopupWindowController.swift`)**:
   - Updated `beginLongPressIfNeeded(at:)` to retrieve `CanvasComponent?` from `ResultContentProviding.makeContent` and arm the panel using `armCanvas(tree:header:)` with a `CanvasHeader`.

4. **ActionResultAdapter (`Sources/Core/Actions/ActionResultAdapter.swift`)**:
   - Updated `apply(raw:after:stayVisible:title:icon:)` so `.showResult` returns `.showContentTree` built via `Canvas.build` DSL with `CanvasHeader`.
   - Updated runtime presentations passthrough matching to include `showContentTree` and `showCanvas`.

5. **Tests (`Tests/OpenClipTests/CalculateActionTests.swift`, `Tests/OpenClipTests/ActionResultAdapterTests.swift`)**:
   - Updated `CalculateActionTests.swift` to verify `makeContent` returns a `CanvasComponent` stack containing the text string and buttons with corresponding `.paste`/`.copy` canvas effects.
   - Updated `ActionResultAdapterTests.swift` to verify `.showResult` wraps copy and paste outcomes into `.showContentTree` with `CanvasHeader` and `CanvasComponent` buttons.

#### Verification & Test Execution:
- **`xcodegen generate`**: Synchronized project files successfully.
- **Specific Tests**:
  - `CalculateActionTests`: Passed (10 tests, 0 failures)
  - `ActionResultAdapterTests`: Passed (10 tests, 0 failures)
  - `PopupCanvasTests`: Passed (12 tests, 0 failures)
- **Full Test Suite**: `./scripts/test.sh` passed cleanly with 0 failures.
