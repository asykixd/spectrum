<div align="center">

# Spectrum

**Dynamic Island for the Mac notch: now-playing music and a live pixel office of your AI coding agents.**

[![CI](https://img.shields.io/github/actions/workflow/status/asykixd/spectrum/ci.yml?branch=main&style=flat-square&label=CI)](https://github.com/asykixd/spectrum/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square&logo=apple)](#installation)
[![Swift 6](https://img.shields.io/badge/Swift-6-blue?style=flat-square&logo=swift&logoColor=white)](Package.swift)

</div>

<!-- Demo: add a screenshot or GIF of the notch here once the UI lands, e.g. docs/demo.gif -->

Spectrum is a native macOS notch app written in Swift and SwiftUI that behaves like the iPhone
Dynamic Island. When nothing is playing it is invisible. When music plays, the notch grows into a
compact live activity with artwork and a waveform. Double-tap <kbd>⌘</kbd> and it opens your AI
agents: a list of Claude Code sessions showing who is working and who is waiting for you, and a
pixel-art office where every session sits at its own desk.

> [!NOTE]
> Spectrum is in early development. The notch panel and the Claude Code event model work today;
> everything else below is tracked in [ROADMAP.md](ROADMAP.md).

## Features

| Feature | Status |
| --- | --- |
| Borderless panel sized to the hardware notch, content on the left and right "ears" | Done |
| Invisible when idle, like Dynamic Island | Planned |
| Claude Code hook event decoding and per-session activity state (thinking, tool use, waiting, finished) | Done |
| Now playing: artwork, title, artist, play/pause/next for Music, Spotify and browsers | Planned |
| Compact live activity while music plays: artwork and audio waveform, expands on hover | Planned |
| Double-tap <kbd>⌘</kbd> to open the agents panel | Planned |
| Sessions list: who is working on what, who is waiting for input, jump to terminal | Planned |
| Pixel office: one character per agent session, desk screen shows the current activity | Planned |
| Codex, Cursor and GitHub Copilot agents | Planned |

## Installation

Requires macOS 14 or later and Swift 6 (Xcode or Command Line Tools). There are no prebuilt
releases yet; build from source:

```sh
git clone https://github.com/asykixd/spectrum.git
cd spectrum
swift build -c release
```

## Usage

```sh
swift run Spectrum
```

In the current build a placeholder panel is always shown around the notch so you can see that the
app runs; it will become invisible when idle. Spectrum runs as an accessory app, so it has no Dock
icon or menu. To quit:

```sh
pkill -f Spectrum
```

## How it works

```mermaid
flowchart LR
    CC[Claude Code hooks] -- JSON events --> Core[SpectrumCore<br/>AgentEvent / AgentActivity]
    MR[MediaRemote<br/>now playing] -. planned .-> Core
    Core --> UI[Notch panel<br/>SwiftUI]
```

- `Sources/SpectrumCore`: UI-free logic: hook payload decoding, agent activity state, notch geometry.
- `Sources/Spectrum`: AppKit/SwiftUI app: a non-activating `NSPanel` above the menu bar.

Spectrum is not sandboxed and not distributed through the App Store. It is designed to use the
system permissions users grant it (Accessibility, Automation) and private frameworks such as
MediaRemote.

## Development

```sh
swift format lint --strict --recursive Sources Tests Package.swift
swift build
swift test
```

<details>
<summary>Running tests with Command Line Tools only (no Xcode)</summary>

The Swift Testing macro plugin is not found by default:

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

</details>

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## License

[MIT](LICENSE)

---

<div align="center">
<sub>Built with <a href="https://claude.com/claude-code">Claude Code</a>.</sub>
</div>
