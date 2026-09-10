# Security Policy

## Supported Versions

OpenClip has not shipped a tagged release yet. The current supported line is the
`main` branch (pre-release):

| Version | Supported |
| :--- | :--- |
| `main` (unreleased) | ✅ |

Once tagged releases exist, this table will track the latest release and any
supported backport lines.

## Reporting a Vulnerability

Please report suspected vulnerabilities **privately** using GitHub Private
Vulnerability Reporting (Security Advisories) on this repository:

**https://github.com/ganeshmshetty/openclip/security/advisories/new**

Do **not** open a public issue or pull request for a suspected vulnerability.

Include in your report:

- A description of the flaw and its potential impact.
- Steps to reproduce — the more concrete (code, crafted extension package or
  manifest, URL, script), the better.
- Any relevant versions (app, macOS, Swift/Xcode).
- Whether you have a suggested fix.

After submitting you will receive an acknowledgement within **5 business days** and
a status update within **30 days**. If the report is confirmed, a fix ships as soon
as possible and the report is coordinated privately.

## Scope

This policy covers the OpenClip macOS application and the `Core` framework in this
repository.

Third-party extensions and their scripts run with your session privileges and are
the responsibility of their authors — install only what you trust. Vulnerabilities
in upstream dependencies (e.g. `KeyboardShortcuts`, `SDWebImageSwiftUI`) should be
reported to their maintainers, though a private heads-up here is appreciated.

## Security-relevant behavior

- **Selection privacy.** OpenClip reads selected text through macOS Accessibility
  APIs and logs or stores nothing about your selections; it does not touch or
  pollute the clipboard while monitoring.
- **Secure extension installs.** Remote extension downloads require HTTPS and are
  validated against Zip-Slip traversal before install.
- **Contained JS modules.** `require()` in JS extension packages resolves modules within
  the package boundary; the boundary is enforced on the symlink-resolved canonical path of the
  opened file, rejecting `../` escapes and symlinks targeting files outside the package directory.
- **Isolated file-backed secrets.** AI provider API keys and secret options are stored securely
  in `~/.openclip/secrets.json` with POSIX 0600 permissions via `SecretStore`, never written to
  plain preferences or UserDefaults.
- **Credentials never in URLs.** Gemini authentication uses the `x-goog-api-key`
  header only, so keys cannot leak through logged or shared URLs.
- **Subprocess sandboxing.** Script actions run under a 30-second watchdog that
  terminates stuck processes (process-group kill) so scripts cannot run or hang
  indefinitely.
- **Hardened runtime, verified on the artifact.** Release builds are signed with
  `--options runtime` and a minimal entitlements file that grants one exception,
  `com.apple.security.automation.apple-events`, needed by AppleScript actions.
  JIT, library-validation, and `DYLD_*` exceptions are all deliberately withheld.
  The build setting alone was not enough to trust: the packaging scripts used to
  finish with `codesign --deep`, which silently replaced Xcode's hardened
  signature with an ad-hoc one, so `scripts/verify_signing.sh` now reads the
  finished bundle — every nested binary included — and fails the build if the
  hardened runtime is missing or the signed entitlements differ from the
  checked-in file. See
  [docs/developer-guide/signing-and-notarization.md](docs/developer-guide/signing-and-notarization.md).
- **Developer ID signing and notarization.** Releases are signed with a
  Developer ID Application certificate and a secure timestamp, then submitted to
  Apple's notary service and stapled, so the app and the disk image both carry
  their ticket offline. The signature's designated requirement pins the bundle
  identifier and Team ID rather than a per-build hash, which is also what lets
  the Accessibility grant survive an update.
- **Verifiable release builds.** Release `.zip` and `.dmg` artifacts carry a
  Sigstore build-provenance attestation binding them to the tag and workflow run
  that produced them, so any download can be checked against its origin:
  `gh attestation verify OpenClip-v<version>.dmg --repo ganeshmshetty/openclip`.
  Sparkle auto-updates are separately signed with an Ed25519 key.
- **Private-by-default logging.** Text, clipboard, and extension data stay
  default-private in logs; only ids and URLs are logged publicly.