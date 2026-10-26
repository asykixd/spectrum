# Spectrum

A macOS notch app: Dynamic Island–style now-playing music, plus a pixel office that shows
what your AI coding agents (Claude Code, Codex, ...) are doing in real time.

## Install

Requires macOS 14+ and Swift 6.

```sh
git clone <repo-url> spectrum && cd spectrum
swift build -c release
```

## Usage

```sh
swift run Spectrum
```

On first launch macOS asks for the permissions Spectrum needs (Accessibility, Automation for
music players).

## Development

```sh
swift format lint --strict --recursive Sources Tests Package.swift
swift build
swift test
```

With Command Line Tools only (no Xcode), point the compiler at the Swift Testing macro plugin:

```sh
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## License

MIT — see [LICENSE](LICENSE).
