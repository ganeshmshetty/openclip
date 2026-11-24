# Contributing to OpenClip

Thanks for wanting to help! OpenClip is a lightweight macOS utility that turns any
selected text into instant actions. Contributions come in many forms: bug reports,
documentation, extension packages, and code.

This file is the entry point for **code contributions**. The authoritative
engineering reference — hard design rules, architecture, and current-state debt —
lives in [`AGENTS.md`](AGENTS.md) and the [`docs/`](docs/index.md) hub. Both are
required reading before touching code.

## Getting started

**Prerequisites:** macOS 14+, [Xcode 27+](https://apps.apple.com/us/app/xcode/id497799835),
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/ganeshmshetty/openclip.git
cd openclip

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
| `scripts/` | `dev_run`, `test`, `package_app`, `clean`, `install_extension` helpers. |
| `docs/` | Architecture, developer guide, runtimes, user guide, logging. |

Two directories in your working copy are **not part of this repository**: `Extensions/` is a
separate clone of the extension catalog, and `web/` is the marketing site. Both are gitignored
here, so `git ls-files` will not list them and nothing in either can be committed here. Extension
changes go to the [openclip-extensions](https://github.com/ganeshmshetty/openclip-extensions)
catalog.

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

1. **Small fixes, documentation, translations, and small improvements can go straight to a PR.**
   For new features, substantial UI changes, or architecture changes, open an issue first
   to agree on scope before implementing.
2. **Add tests** when you change behavior, and make sure the quick build gate and
   full suite pass before pushing.
3. **Keep PRs focused** on a single concern. Rebase onto `main` before submitting.
4. **Update docs** (`AGENTS.md`, `docs/`) when you change behavior or add a
   convention — same commit is ideal.
5. In the PR description, describe the change and what you tested.

Extension authors: the extension format is documented in
[`Extensions/AGENTS.md`](Extensions/AGENTS.md) if you have the catalog cloned locally; the
authoritative version is the `AGENTS.md` at the root of
[openclip-extensions](https://github.com/ganeshmshetty/openclip-extensions).

## Filing issues and picking one up

Issues are the front door, so it's worth knowing what happens after you file one.

**What happens when you file an issue.** Bug reports ask what happened, how to reproduce it,
and your OpenClip and macOS versions. If reproduction is intermittent or unknown, say so.
The affected app, expected behavior, chip architecture, screenshots, and logs are optional.
Feature requests require only the problem you want to solve; a proposed solution and examples
are optional. The forms apply `bug` or `enhancement`; maintainers add other labels during triage.
An automated pass greets first-time contributors and may suggest a possible duplicate. Those
suggestions are hints, not verdicts, and do not automatically close your issue.

**How to work on one.** Say “I'd like to work on this” in a comment. Claiming is optional:
`/claim` requests assignment and adds `status:claimed`. Check existing assignments before starting
substantial work and coordinate with anyone already working on it. If you stop, leave a comment
so the maintainer can release the assignment. Maintainers may check in and release inactive claims.

**Before you open the pull request.** Explain what changed, why, and how you verified it.
Issue links are optional: use `Fixes #<number>` for a complete resolution or `Related to #<number>`
for partial work. `Build & Tests` performs verification. `PR Intake` only reminds authors about
empty descriptions; it does not require an issue or repeat verification claims in bot comments.

## Contribution scope and review

OpenClip focuses on selected-text actions and reliable native macOS behavior. Specialized
integrations generally belong in extensions. Discuss large features first; experiments can be
shared as drafts. A working feature may be declined if its scope or ongoing maintenance cost
is too large for the project.

Review comments should distinguish required fixes (correctness, privacy, compatibility, or
maintainability), optional suggestions, and minor nits. Only required fixes block approval.
Review timing depends on maintainer availability; there is no guaranteed response deadline.
When declining a contribution, explain the reason and close it rather than leaving it pending.

## Issue labels

Use a small active set:

- `bug`, `enhancement`, `documentation`: the kind of work.
- `good first issue`, `help wanted`: work ready for contributors.
- `status:needs-info`: waiting on specific information from the reporter.
- `status:claimed`: an optional assignment, maintained by `/claim`.
- `duplicate`: links a report to an existing issue.

Retire `area:*`, `involvement:*`, `status:needs-triage`, `status:confirmed`, `invalid`,
`question`, and `wontfix` from active use. Use the issue conversation for confirmation,
questions, and reasons for closing. Historical labels may remain on older issues to preserve
context; the intake workflow does not add or remove them.

## Code of Conduct

All interactions in this project are governed by our
[Code of Conduct](CODE_OF_CONDUCT.md). Be respectful and kind; maintainers enforce
it fairly and promptly when incidents are reported.

## License

OpenClip is AGPL-3.0 licensed. By submitting a contribution you agree that your
contribution is provided under the GNU Affero General Public License v3.0, and
you grant the project maintainer a perpetual, worldwide, royalty-free right to
relicense your contribution under any license, so the project can be relicensed
in the future without contacting every contributor.