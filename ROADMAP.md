# Roadmap

## Now
- [ ] Signed and notarized `.app` bundle with `Info.plist` usage descriptions, so granted permissions bind to Spectrum, not the terminal; release workflow
- [x] Invisible when idle: with no music playing and the agents panel closed, nothing is drawn outside the hardware notch
- [x] Now playing: track, artist, artwork and play/pause/next for Spotify and Apple Music (AppleScript)
- [x] Compact live activity while music plays: artwork on the left ear, animated waveform on the right; expands on hover
- [x] Double-tap ⌘ toggles the agents panel (global modifier-key monitor)
- [x] Receive Claude Code hook events (local socket) and track sessions by `session_id`

## Next
- [x] Agents panel, tab 1 — sessions list: each chat with its project, current activity and who is waiting for input
- [x] Agents panel, tab 2 — pixel office: one character per session, desk screen shows the current activity
- [x] Hook installer that adds Spectrum hooks to `~/.claude/settings.json`
- [ ] Jump to the agent's terminal window from the sessions list
- [ ] Codex support

## Later
- [ ] Browsers and other players in now playing (MediaRemote ignores third-party apps since macOS 15.4)
- [ ] Waveform driven by real audio levels instead of an animation
- [ ] Cursor and GitHub Copilot agents
- [ ] Reply to an agent from the notch
- [ ] Optional notch nudge when an agent waits for input (off by default to keep the idle notch invisible)
- [ ] Settings window (shortcut, which modules are shown)
