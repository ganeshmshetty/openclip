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
- **Isolated file-backed secrets.** AI provider API keys and secret options are stored securely
  in `~/.openclip/secrets.json` with POSIX 0600 permissions via `SecretStore`, never written to
  plain preferences or UserDefaults.
- **Credentials never in URLs.** Gemini authentication uses the `x-goog-api-key`
  header only, so keys cannot leak through logged or shared URLs.
- **Subprocess sandboxing.** Script actions run under a 30-second watchdog that
  terminates stuck processes (process-group kill) so scripts cannot run or hang
  indefinitely.
- **Hardened runtime.** The app target builds with `ENABLE_HARDENED_RUNTIME`
  enabled (see `project.yml`).
- **Private-by-default logging.** Text, clipboard, and extension data stay
  default-private in logs; only ids and URLs are logged publicly.