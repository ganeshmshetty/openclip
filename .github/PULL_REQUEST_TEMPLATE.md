## Summary
<!-- Concise description of what this PR does and the problem it solves. -->

Fixes # <!-- Link issue here (e.g. Fixes #6) -->

> **Note:** If you are adding or updating a community extension, please submit your PR to [ganeshmshetty/openclip-extensions](https://github.com/ganeshmshetty/openclip-extensions) instead.

---

## Type of Change
- [ ] Bug fix (non-breaking change fixing an issue)
- [ ] New feature (non-breaking change adding functionality)
- [ ] Extension Runtime / Bridge update (JS host, AppleScript runner, Shell executor)
- [ ] UI / Theme / Accessibility improvement
- [ ] Performance / Concurrency optimization
- [ ] Localization (`Localizable.xcstrings`)
- [ ] Documentation update
- [ ] Build tooling / CI / Scripts

---

## Testing & Verification

### Environment Tested:
- **macOS Version:** <!-- e.g. macOS 15.0 / macOS 14.5 -->
- **Architecture:** <!-- Apple Silicon / Intel -->
- **Target Apps Verified:** <!-- e.g. Safari, Notes, VS Code, Terminal -->

### Test Execution:
- [ ] Ran `./scripts/test.sh core` (< 1s domain test suite)
- [ ] Ran `./scripts/test.sh` (Full suite passes with 0 failures/skips)
- [ ] Tested live in app via `./scripts/dev_run.sh`

---

## Screenshots / Screen Recordings (if applicable)
<!-- If this PR changes UI or visual behavior, include a before/after screenshot or video. -->

| Before | After |
| :---: | :---: |
| *(Image/Video)* | *(Image/Video)* |

---

## Architectural & Code Checklist
- [ ] **Swift 6 Concurrency:** Builds cleanly with complete strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`) with zero data races.
- [ ] **Core Purity:** No `AppKit` or `SwiftUI` imports in `Sources/Core/`.
- [ ] **Settings & Secrets:** Uses `SettingsStore` / `SecretStore` (no direct `UserDefaults.standard` in new code).
- [ ] **Subprocess Safety:** Any new subprocess enforces `Constants.scriptTimeout` (30 s) watchdog and non-blocking I/O.
- [ ] **Dual-Sink Logging:** Logs through `Log` subsystem categories (no raw `print()` or ad-hoc `Logger()`).
- [ ] **Localization:** User-facing strings use `String(localized:)` and are recorded in `Localizable.xcstrings`.
