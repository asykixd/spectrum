# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-27

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

[0.1.0]: https://github.com/asykixd/spectrum/releases/tag/v0.1.0
