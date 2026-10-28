# Roadmap

## Now
- [x] Universal `Spectrum.app` with `Info.plist` usage descriptions and an app icon; release workflow
- [ ] Developer ID signing and notarization, so the app opens without the quarantine workaround
- [ ] Jump to the agent's terminal window from the sessions list
- [ ] Launch at login

- [ ] Allow or deny permission requests from the island (`PermissionRequest` hook)
- [ ] Task progress from `TodoWrite` on the avatar and under the island
- [ ] Office tool animations: reading, typing, terminal, globe for web search
- [ ] Subagents as interns next to their agent in the office
- [ ] Boss's office: hours worked per agent, what each did, tokens and money spent, 5-hour limit
- [ ] Start a new Claude Code session in a project from the panel
- [ ] Session summary when a task finishes: files changed, lines added and removed

## Next
- [ ] Codex support
- [ ] Browsers and other players in now playing (MediaRemote ignores third-party apps since macOS 15.4)
- [ ] Waveform driven by real audio levels instead of an animation
- [ ] Synced lyrics in the expanded player (LRCLIB)

## Later
- [ ] Cursor and GitHub Copilot agents
- [ ] Reply to Claude app chats from the panel

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
