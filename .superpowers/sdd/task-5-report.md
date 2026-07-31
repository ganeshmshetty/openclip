# Task 5 Report: Phase 5 — Extension System

## Status
DONE

## Commits Made
- `0baeee7` Implement Task 5: Phase 5 - Extension System

## Test Summary
- Verified successful compilation via `xcodebuild -scheme OpenClip -configuration Debug build`. The project builds cleanly with zero errors.
- Adhered to Swift 6 strict concurrency guidelines (`@Sendable`, `Task.detached`, `@MainActor`).
- Scripts are run asynchronously without blocking the Main Actor.

## Work Completed
1. Added extension-specific constants to `Sources/Core/Selection/Constants.swift`.
2. Modified `ActionResult.swift` and `PopupWindowController.swift` to support `.paste(String)` responses from scripts.
3. Created `ScriptAction.swift` in `Sources/Core/Extensions` to execute arbitrary scripts via Foundation `Process`. The selected text is sent to STDIN and via the `POPCLIP_TEXT` environment variable. The STDOUT is parsed as JSON.
4. Created `ExtensionManager.swift` in `Sources/Core/Extensions` to scan `~/.openclip/extensions` for extensions on app launch. It supports reading directories with `manifest.json` as well as standalone scripts containing metadata headers (e.g. `# Title: My Action`).
5. Updated `AppDelegate.swift` to asynchronously load the extensions and register them via `ActionRegistry`.
6. Regenerated the Xcode project file via `xcodegen` and ran `xcodebuild` successfully.

## Concerns
- Sandboxing: macOS application sandboxing might prevent the app from executing arbitrary scripts from `~/.openclip/extensions` or from passing them standard UNIX paths without appropriate entitlements or a user-selected folder bookmark.
- Permissions: `.sh` scripts may need to be marked as executable (`chmod +x`), but `ScriptAction` checks for this and falls back to invoking via `/bin/bash` when necessary. 
- JSON Decoding failures in scripts will just be ignored or fall back gracefully, but debugging third-party extensions might be difficult without a logging surface for the end user.

## Fix Report
1. Fixed Unix Pipe Deadlock in `ScriptAction.swift` by using detached tasks to write to STDIN and read from STDOUT/STDERR asynchronously.
2. Refactored `ExtensionManager.swift` to execute directory scanning and file IO on background tasks instead of blocking `@MainActor`.
3. Fixed hardcoded slicing for script headers in `ExtensionManager.swift` by splitting on ":" and trimming.
4. Added logic to `ExtensionManager.swift` to fallback to scanning for standalone executable scripts in subdirectories missing `manifest.json`.
5. Removed fallback logic in `ScriptAction.swift` that blindly executed non-executable scripts via `/bin/bash` since it broke other script types (e.g., Python).
6. Removed hardcoded numbers/strings (e.g. `50`, `"POPCLIP_TEXT"`) and replaced them with `Constants` in `Constants.swift`.
7. Created `ExtensionManagerTests.swift` and `ScriptActionTests.swift` inside `Tests/OpenClipTests` with tests for logic parsing and script execution. Mocked `Constants.extensionsDirectory` using `nonisolated(unsafe)` for testing.
8. Recompiled and ran all 19 unit tests with `xcodebuild test -scheme OpenClip -destination 'platform=macOS,arch=arm64'`. All tests passed successfully.
