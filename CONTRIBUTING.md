# Contributing to OpenClip

Thanks for wanting to help! OpenClip is a lightweight macOS utility that turns any
selected text into instant actions. Contributions come in many forms: bug reports,
documentation, extension packages, and code.

This file is the entry point for **code contributions**. The authoritative
engineering reference — hard design rules, architecture, and current-state debt —
lives in [`AGENTS.md`](AGENTS.md) and the [`docs/`](docs/index.md) hub. Both are
required reading before touching code.

## Getting started

**Prerequisites:** macOS 14+, [Xcode 16+](https://apps.apple.com/us/app/xcode/id497799835),
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/ganeshmshetty/openclip.git
cd openclip

# Populate the extension-catalog submodule
git submodule update --init

# Generate the Xcode project (re-run after adding/removing .swift files)
xcodegen generate
```

`project.yml` is the source of truth for the Xcode project — the `.xcodeproj` is
generated and should not be edited by hand.

## Project layout

| Path | What it is |
| :--- | :--- |
| `Sources/Core` | Pure-domain framework: models, actions, rules, selection logic, settings, manifest parsers. **No `AppKit`/`SwiftUI`.** |
| `Sources/OpenClip` | App target: AppKit panels, SwiftUI views, platform side-effect handlers, AI providers, composition root. |
| `Tests/OpenClipTests` | XCTest suites for both targets. |
| `Extensions/` | Git submodule hosting the official & community extension catalog (`openclip-extensions`). |
| `docs/` | Architecture, developer guide, runtimes, user guide, logging. |
| `scripts/` | `dev_run`, `test`, `package_app`, `clean`, `install_extension` helpers. |
| `web/` | Website / extension-store site (Next.js), deployed separately. |

## Development workflow

Prefer the `scripts/` wrappers over raw `xcodebuild`/`xcodegen`. Full list is in
`AGENTS.md` §2; the essentials:

| Task | Command |
| :--- | :--- |
| Quick compile gate | `timeout -k 5 60 xcodebuild -project OpenClip.xcodeproj -scheme OpenClip -destination 'platform=macOS' build` |
| Core domain tests (<1s) | `./scripts/test.sh core` |
| Full test suite (0 skips) | `timeout -k 10 60 ./scripts/test.sh` |
| Single test class | `./scripts/test.sh SettingsStoreTests` |
| Run the app | `./scripts/dev_run.sh` |
| Package a Release | `./scripts/package_app.sh` |
| Clean build artifacts | `./scripts/clean.sh` |

Always run the quick build gate first, then the full suite once at the end. The
suite runs deterministically (~45 s) but still wrap it in a timeout.

## Code style & hard rules

These change behavior — keep them. (Condensed from `AGENTS.md` §4, which is the
authority; read it in full before editing.)

- **Module boundaries.** Never `import AppKit`/`SwiftUI` in `Sources/Core/Actions/`
  or `Sources/Core/Settings/`.
- **No `UserDefaults.standard`.** Use `SettingKey`/`SettingsStore`; production code
  goes through `DefaultSettingsStore.shared`. Tests inject the shared
  `MemorySettingsStore` test double or a per-test `DefaultSettingsStore(userDefaults: suiteName)`.
- **Data-driven UI.** Drive rendering from `action.chrome`,
  `ConfigurableAction.preferenceIconName`, and `action.gesturePolicy` — never
  `switch action.id`, Swift type checks, or hidden singleton wiring in Core.
- **Single `Log` surface.** Every log message goes through a category on the `Log`
  enum — never `print()`. Text, clipboard, and extension data stay default-private;
  hot paths (per-mouse-move hover, high-frequency view bodies) are never logged.
- **Swift 6 strict concurrency.** No captured mutable locals in continuation
  resume-once flags (use `@unchecked Sendable` classes like `TimeoutFlag`
  /`OnceGate`), and never `Self.<static>` inside a `Task.detached` closure — see
  `docs/runtimes/javascript.md`.
- **Subprocess actions need a timeout watchdog** that terminates past
  `Constants.scriptTimeout` (30 s), and read pipes via GCD `readabilityHandler` —
  never a blocking `readToEnd()`.
- **Test isolation.** Any test class touching app singletons
  (`ActionRegistry.shared`, `RuleEngine.shared`, `ExtensionManager.shared`,
  `ActionCustomizationManager.shared`) must call `TestIsolation.reset()` from
  `setUp()`.
- **Docs stay current.** After a meaningful batch of edits, refresh `AGENTS.md` and
  the docs it points to if they'd otherwise drift (`AGENTS.md` §6).

## Commit conventions

OpenClip uses [Conventional Commits](https://www.conventionalcommits.org/). Prefixes
in active use:

```
feat:  fix:  refactor:  docs:  chore:  style:  test:  ui:  log:  ext:  perf:
```

Keep messages focused and lowercase-scope where applicable (e.g. `feat(extensions):`).

## Submitting changes

1. **Open an issue first** for behavioral changes or anything design-sensitive;
   small fixes and docs can go straight to a PR.
2. **Add tests** when you change behavior, and make sure the quick build gate and
   full suite pass before pushing.
3. **Keep PRs focused** on a single concern. Rebase onto `main` before submitting.
4. **Update docs** (`AGENTS.md`, `docs/`) when you change behavior or add a
   convention — same commit is ideal.
5. In the PR description, describe the change and what you tested.

Extension authors: the extension format is documented in
[`Extensions/AGENTS.md`](Extensions/AGENTS.md); the built-in
store catalog lives in the `Extensions/` submodule.

## Code of Conduct

All interactions in this project are governed by our
[Code of Conduct](CODE_OF_CONDUCT.md). Be respectful and kind; maintainers enforce
it fairly and promptly when incidents are reported.

## License

OpenClip is MIT-licensed. By contributing, you agree that your contributions are
provided under the MIT License.