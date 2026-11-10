<div align="center">
  <img src="./assets/app-icon.png" alt="OpenClip" width="80" height="80" />
  <h1>OpenClip</h1>
  <p>The open-source text action popup for macOS.</p>

  <p>
    <a href="https://github.com/ganeshmshetty/openclip/releases"><img src="https://img.shields.io/badge/macOS-14.0+-black?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL_3.0-blue?style=flat-square" alt="License" /></a>
    <a href="https://github.com/ganeshmshetty/homebrew-tap"><img src="https://img.shields.io/badge/brew-openclip-ffcc00?style=flat-square&logo=homebrew&logoColor=black" alt="Homebrew" /></a>
    <a href="https://discord.gg/acYYdzM7jR"><img src="https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Discord" /></a>
  </p>

  <p>
    <a href="https://github.com/sponsors/ganeshmshetty"><img src="https://img.shields.io/badge/Sponsor-EA4AAA?style=flat-square&logo=githubsponsors&logoColor=white" alt="GitHub Sponsors" /></a>
    <a href="https://buymeacoffee.com/ganeshmshetty"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?style=flat-square&logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee" /></a>
    <a href="https://ko-fi.com/ganeshmshetty"><img src="https://img.shields.io/badge/Ko--fi-FF5E5B?style=flat-square&logo=kofi&logoColor=white" alt="Ko-fi" /></a>
  </p>

  <br />

  <img src="./assets/all.gif" alt="OpenClip in action" width="480" />
</div>

<br />

Select text in any app, and OpenClip pops up with contextual actions — transform text, run shell scripts, trigger shortcuts, evaluate math expressions, or query AI models.

## Sponsors

<table><tr>
<td><a href="https://www.infistar.cc/register?aff=CWD4X8S4&ref_source=link"><img src="https://assets.getopenclip.app/sponsor-infistar.png" alt="Infistar" width="48"></a></td>
<td>Thanks to <a href="https://www.infistar.cc/register?aff=CWD4X8S4&ref_source=link">Infistar</a> for sponsoring OpenClip.</td>
</tr></table>

## Installation

### Homebrew (Recommended)
```bash
brew install --cask openclip
```

### Direct Download
Download the latest `.dmg` from [Releases](https://github.com/ganeshmshetty/openclip/releases).

## Features

- **Contextual bar**: Appears instantly near your selection with relevant actions (case transform, search, copy/cut, math, or custom scripts).
- **Search palette (`⌥⌘C`)**: Press hotkey to fuzzy search your entire action catalog.
- **Extensions**: Write or install custom extensions in JavaScript, Shell, AppleScript, or URL schemes.
- **Native & fast**: Written in Swift 6 with strict concurrency; lightweight background footprint.
- **Optional AI actions**: Run text through local Ollama models, Apple Intelligence, or OpenAI/Anthropic keys.
- **Privacy-first**: Zero telemetry, no analytics, 100% local execution.

## Extensions

Extensions are simple folders in `~/.openclip/extensions/`. A basic URL lookup extension only needs an `openclip.json`:

```json
{
  "identifier": "com.example.lookup",
  "name": "Wikipedia Lookup",
  "actions": [
    {
      "title": "Lookup",
      "icon": "symbol(magnifyingglass)",
      "type": "url",
      "url": "https://en.wikipedia.org/wiki/Special:Search?search={query}"
    }
  ]
}
```

Install community extensions from **Preferences → Extension Store**, or read the [extension docs](docs/developer-guide/index.md).

## Building from Source

**Prerequisites:** macOS 14+, Xcode 16+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/ganeshmshetty/openclip.git
cd openclip

# Generate Xcode project
xcodegen generate

# Build and run
./scripts/dev_run.sh

# Run tests
./scripts/test.sh

# Package release DMG
./scripts/package_app.sh
```

## Community & Support

- **Docs:** [Documentation Hub](docs/index.md)
- **Discord:** [Join Community](https://discord.gg/acYYdzM7jR)
- **Issues:** [Report a bug](https://github.com/ganeshmshetty/openclip/issues)
- **Sponsor:** [GitHub Sponsors](https://github.com/sponsors/ganeshmshetty) · [Buy Me a Coffee](https://buymeacoffee.com/ganeshmshetty) · [Ko-fi](https://ko-fi.com/ganeshmshetty)

## License

[AGPL-3.0](LICENSE) © 2026 Ganesh M and OpenClip Contributors. See [NOTICE.md](NOTICE.md).
