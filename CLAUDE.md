# Spectrum

macOS notch app combining two ideas: NotchNook-style now-playing music (Dynamic Island look)
and Lumio-style pixel office showing AI coding agents' live activity. Nothing else from NotchNook.

## Product behavior (source of truth)
- Behaves like iPhone Dynamic Island: when no music is playing and the agents panel is closed, Spectrum is invisible — nothing outside the hardware notch.
- Music playing → compact live activity on the notch ears; hover expands it.
- Agents are shown only on demand: double-tap ⌘ opens a panel with two tabs — (1) sessions list: who is working on what, who is waiting; (2) pixel office.

## Commands
- Format: `swift format --in-place --recursive Sources Tests Package.swift`
- Lint: `swift format lint --strict --recursive Sources Tests Package.swift`
- Build / run: `swift build`, `.build/debug/Spectrum`
- UI check without music/agents: `.build/debug/Spectrum preview <dir>` renders every mode to PNG
- README screenshots: render with `preview`, crop into `docs/screenshots/` (demo data only, never real sessions)
- App bundle: `scripts/bundle.sh <version>` → `dist/Spectrum.app` + zip; icon: `scripts/make-icon.sh`
- Test: `swift test` (Swift Testing, `@Test` / `#expect`)
  - With Command Line Tools only (no Xcode), the Testing macro plugin isn't found by default:
    `swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`

## Layout
- `Sources/SpectrumCore` — UI-free logic: hook events, `SessionStore`, `AgentSocket`, `HookInstaller`, `NowPlaying`, `DoubleTapDetector`, `NotchMode`, `NotchGeometry`. All tests target this.
- `Sources/Spectrum` — AppKit/SwiftUI app: `main.swift` (CLI subcommands), `AppDelegate` (wiring, hover polling), monitors (`NowPlayingMonitor`, `AgentMonitor`, `ShortcutMonitor`), `NotchModel` + `NotchLayout`, views (`NotchRootView`, `MusicViews`, `AgentsPanelView`, `OfficeView`, `PixelArt`).
- `Tests/SpectrumCoreTests` — unit tests.

## Conventions
- Keep logic in `SpectrumCore` so it's testable without a window server.
- Agents are tracked via Claude Code hooks (stdin JSON: `session_id`, `hook_event_name`, `tool_name`, ...). `Spectrum hook` forwards it over `~/Library/Application Support/Spectrum/agent.sock`; it must stay silent on stdout and exit 0.
- Claude app chats come from its accessibility tree (`ClaudeChatMonitor`, `ClaudeChatSnapshot`); keep chats for 15 minutes after last seen.
- Sessions are grouped by `SessionGroups` (code / chats / AFK); the office has matching zones.
- `@State` and other SwiftUI macros fail to build with Command Line Tools only; keep view state in `NotchModel`.
- `ImageRenderer` (preview command) can't draw `ScrollView`, `Form` or `Menu`; those show blank or 🚫 in previews.
- Energy matters: no polling while the island is hidden, timers get `tolerance`, the Claude AX walk uses `AXUIElementCopyMultipleAttributeValues` and `ChatPollPolicy`. Measure with `top -pid` before/after perf changes.
- Haptics only on island open/close. The user explicitly does not want them on player controls or tab switches.
- Now playing uses Spotify / Music AppleScript. Don't use MediaRemote or inject code into Apple binaries to bypass its entitlement check.
- Permissions: users grant whatever is needed (Accessibility, Automation, media/private APIs like MediaRemote). Don't design around missing permissions; just request them.
- Not sandboxed / not App Store — private frameworks are acceptable.
