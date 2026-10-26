# Roadmap

## Now
- [ ] Signed and notarized `.app` bundle with `Info.plist` usage descriptions, so granted permissions bind to Spectrum, not the terminal; release workflow
- [ ] Invisible when idle: with no music playing and the agents panel closed, nothing is drawn outside the hardware notch
- [ ] Now playing: track, artist, artwork and play/pause/next via MediaRemote (Music, Spotify, browsers)
- [ ] Compact live activity while music plays: artwork on the left ear, audio waveform on the right; expands on hover
- [ ] Double-tap ⌘ toggles the agents panel (global modifier-key monitor)
- [ ] Receive Claude Code hook events (local socket) and track sessions by `session_id`

## Next
- [ ] Agents panel, tab 1 — sessions list: each chat with its project, current activity and who is waiting for input
- [ ] Agents panel, tab 2 — pixel office: one character per session, desk screen shows the current activity
- [ ] Hook installer that adds Spectrum hooks to `~/.claude/settings.json`
- [ ] Jump to the agent's terminal window from the sessions list
- [ ] Codex support

## Later
- [ ] Cursor and GitHub Copilot agents
- [ ] Reply to an agent from the notch
- [ ] Optional notch nudge when an agent waits for input (off by default to keep the idle notch invisible)
- [ ] Settings window (shortcut, which modules are shown)
