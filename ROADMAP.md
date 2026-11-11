# Roadmap

## Now
- [x] Universal `Spectrum.app` with `Info.plist` usage descriptions and an app icon; release workflow
- [x] Jump to the agent's original macOS Terminal tab from the sessions list
- [x] Launch at login
- [x] Allow or deny permission requests from the island (`PermissionRequest` hook)
- [x] Task progress from `TodoWrite` and the Task tools around the avatar in the sessions list
- [x] Office tool animations: a page for reading, code for edits, a terminal, a browser for the web
- [x] Subagents as interns on their agent's desk in the office
- [x] Boss tab: time worked per project, what each did, tokens and money at API prices, the five-hour window
- [x] Start a new Claude Code session in a project from the panel (opens in Terminal)
- [x] Session summary: files changed, lines added and removed since the last prompt
- [x] Stop the boss, transcript and chat timers while the panel is closed
- [x] Reload the open transcript on hook events or file writes, reading only appended bytes
- [x] Stream transcripts in chunks in `UsageScanner` and skip decoding message payloads without usage or prompts
- [x] Persist `UsageScanner` offsets and totals so the boss tab can show cached data after a relaunch

## Next
- [x] Track local Codex sessions in the list and pixel office, with transcripts and approvals
- [x] Opt-in now playing and play/pause for Safari, Google Chrome, and QuickTime Player
- [x] Opt-in waveform driven by real audio levels on macOS 14.2 and later
- [x] Synced lyrics in the expanded player (LRCLIB)
- [x] Poll the pointer slower while it is far from the notch
- [x] Poll native playback only while paused, and poll extra sources only while their apps are running
- [x] Rasterize the static office layer and pause it when nothing moves
- [x] Bound the Spotify artists cache; cache artwork and lyrics on disk
- [x] Signposts and a `UsageScanner` benchmark to catch performance regressions
- [x] "Always Allow" for exact Claude Code shell rules in project-local `permissions.allow`
- [x] Keyboard control: Return allows once, Escape denies, arrows move through sessions
- [ ] Pulse again when an agent has waited longer than a set time
- [ ] Spend limits for the day and the five-hour window, cost per session in the list
- [ ] Respect Focus and screen sharing: no pulses, no session content
- [ ] Pill fallback on displays without a notch
- [ ] Snapshot tests from `preview` renders
- [ ] Fuzz tests for the transcript, usage, now playing and chat parsers
- [ ] Test that `Spectrum hook` exits quickly when the app is down or stuck

## Later
- [ ] Cursor and GitHub Copilot agents
- [ ] Reply to Claude app chats from the panel
- [ ] Developer ID signing and notarization once an Apple Developer Program membership is available
- [ ] Auto-update with Sparkle (after notarization)
- [ ] `Spectrum diag`: socket, hooks, accessibility and recent events

## Done in 1.0.0
- [x] Dynamic Island behaviour: invisible when idle, compact live activity, expanded player on hover
- [x] Now playing for Spotify and Apple Music, featured artists, swipe to change track
- [x] Agents panel on a double tap: sessions list and pixel office, grouped into Claude Code / Chats / AFK
- [x] Claude Code hooks over a local socket, hook installer, conversation view, replies via `claude -p --resume`
- [x] Claude app chats from the last 15 minutes via Accessibility
- [x] Clawd characters, clickable office, day/night lighting
- [x] Pulse when an agent needs the user, checkmark when a task finishes
- [x] Settings window and panel menu
- [x] Energy: under 1% CPU while hidden; chat tracking slows down and pauses on battery
