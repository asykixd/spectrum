# Spectrum

macOS notch app combining two ideas: NotchNook-style now-playing music (Dynamic Island look)
and Lumio-style pixel office showing AI coding agents' live activity. Nothing else from NotchNook.

## Commands
- Format: `swift format --in-place --recursive Sources Tests Package.swift`
- Lint: `swift format lint --strict --recursive Sources Tests Package.swift`
- Build / run: `swift build`, `swift run Spectrum`
- Test: `swift test` (Swift Testing, `@Test` / `#expect`)
  - With Command Line Tools only (no Xcode), the Testing macro plugin isn't found by default:
    `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`

## Layout
- `Sources/SpectrumCore` — UI-free logic (hook event decoding, agent state, now-playing model). All tests target this.
- `Sources/Spectrum` — AppKit/SwiftUI app: `NotchPanel` (borderless panel over the notch), views.
- `Tests/SpectrumCoreTests` — unit tests.

## Conventions
- Keep logic in `SpectrumCore` so it's testable without a window server.
- Agents are tracked via Claude Code hooks (stdin JSON: `session_id`, `hook_event_name`, `tool_name`, ...).
- Permissions: users grant whatever is needed (Accessibility, Automation, media/private APIs like MediaRemote). Don't design around missing permissions; just request them.
- Not sandboxed / not App Store — private frameworks are acceptable.
