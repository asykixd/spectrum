# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.9] - 2026-11-12

### Added

- Allow or deny Claude Code permission requests from the island: hover the warning to see the
  command, file or URL. Without an answer the terminal asks after a minute. Hooks from an older
  version are updated on launch.
- Task progress in the sessions list: a ring around the avatar and "2/4 Writing the view", from
  the agent's `TodoWrite` list or the newer `TaskCreate` / `TaskUpdate` tools.
- What an agent changed since your last prompt, "2 files +22 −33", in its session row.
- Office monitors show what the tool does: a page of text while reading, a terminal for
  commands, a browser for web search, code for edits.
- Subagents appear as small interns on their agent's desk.
- Synced lyrics in the expanded player, from lrclib.net; can be turned off in Settings.
- Start a new Claude Code session from the panel: pick a recent folder, type an optional first
  prompt, and it opens in Terminal.
- Boss tab: today's cost at API prices, tokens, time agents worked and the current five-hour
  window, with a row per project showing its time, cost and last prompt.
- Track local Codex, Cursor and GitHub Copilot sessions in the list and office. Cursor and Copilot
  report activity and do not handle approvals in Spectrum.
- Jump to the original Terminal tab from a session and reply to the currently open Claude desktop
  chat from the panel.
- Navigate the focused agent panel with the keyboard, answer permission requests, and allow an
  exact Claude Code command for one project when Claude offers a local rule.
- Get one follow-up reminder for acknowledged requests and see the waiting-agent count in the
  expanded player.
- Set daily and five-hour cost warnings and see estimated Claude Code cost per session.
- Enable playback controls for supported Safari, Chrome and QuickTime media, or drive the compact
  waveform from system audio on macOS 14.2 or later.
- Open Spectrum at login, hide agent details manually, and use a floating island on displays
  without a hardware notch.
- Run `Spectrum diag` to check hook installation, the agent socket and recent event types.
- Download a universal disk image or ZIP from GitHub Releases.

### Changed

- Only the open tab in the agents panel shows its title; the others show an icon.
- Quieter island signals: a small warning icon with a thin blinking outline when an agent needs
  you, and a small checkmark that stays for three seconds instead of 1.6.
- Agent signals no longer hide the playing music: the icon rides on the artwork as a badge and
  the outline blinks around the live activity.
- Read appended transcript records on demand, cache usage reports and bound artwork and lyrics
  caches.
- Reduce background polling and pause office animation when the room is empty or Reduce Motion
  is enabled.

### Fixed

- Avoid accidental double-tap shortcut triggers and keep AppleScript objects on their script queue.
- Bound hook wait times when the app is unavailable or unresponsive and handle malformed or
  out-of-range event values.

## [1.0.0] - 2026-10-27

First release.

### Added

- Dynamic Island–style notch: invisible when idle, compact live activity while music plays,
  expanded player on hover with progress and controls.
- Now playing from Spotify and Apple Music, including every featured artist on Spotify tracks;
  two-finger swipe across the player changes the track.
- Agents panel on a double tap of ⌘ (or ⌥ / ⌃): Claude Code sessions, Claude app chats and AFK
  agents, grouped in a list and in a pixel-art office.
- Pixel office with Clawd mascots (or people), a meeting room for chats, a lounge for idle
  agents, day/night lighting from the Mac's clock; hover and click agents to open them.
- Conversation view from Claude Code transcripts and replies to idle sessions through a
  background `claude -p --resume`.
- The island pulses when an agent needs permission or an answer and flashes a checkmark when a
  task finishes.
- One-click Claude Code hook installer that keeps existing hooks and follows the app when it
  moves.
- Settings window: shortcut, music, chats and their retention, battery behaviour, alerts,
  haptics, character style, replies, hooks.
- Universal `Spectrum.app` (Apple silicon and Intel) with a Clawd icon, built by
  `scripts/bundle.sh` and attached to GitHub releases by CI.

[Unreleased]: https://github.com/asykixd/spectrum/compare/v1.0.9...HEAD
[1.0.9]: https://github.com/asykixd/spectrum/compare/v1.0.0...v1.0.9
[1.0.0]: https://github.com/asykixd/spectrum/releases/tag/v1.0.0
