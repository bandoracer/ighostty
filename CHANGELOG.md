# Changelog

All notable changes to iGhostty are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.4] - 2026-06-16

### Added

- Color scheme management now distinguishes built-in and user-created schemes,
  flags schemes modified from their source, and adds revert, duplicate, rename,
  and delete actions for profile color schemes.

### Changed

- Profiles whose `TERM` is still the legacy `xterm-256color` default are
  migrated to `xterm-ghostty` on settings load and import, so existing installs
  pick up the Ghostty terminfo automatically. Explicitly customized `TERM`
  values are left untouched.

## [1.0.3] - 2026-06-15

- Maintenance and packaging improvements; build 4.

## [1.0.2] - 2026-06-14

- Maintenance and packaging improvements; build 3.

## [1.0.1] - 2026-06-13

- Maintenance and packaging improvements; build 2.

## [1.0.0] - 2026-06-13

Initial release.

### Added

- libghostty terminal core: VT/xterm emulation, GPU-backed rendering, CoreText
  fonts, keyboard/mouse input, IME, selection, and clipboard behavior.
- Drop-down (Quake-style) terminal with configurable double-tap-modifier or
  classic-shortcut activation, all-Spaces / over-full-screen presentation, and a
  pin toggle.
- iTerm2 configuration import from `com.googlecode.iterm2.plist`, Dynamic
  Profiles JSON, and `.itermcolors` color schemes.
- Separate light/dark theme selection per profile, with built-in theme pairs and
  the generated Ghostty theme catalog.
- Bundled Ghostty runtime resources (shell integration, terminfo, `ghostty`
  shim) and a Ghostty-compatible PTY environment.
- Shell-integration controls and advanced raw Ghostty `key = value` config
  overrides per profile.
- Splits, native tabs, broadcast input, prompt navigation, OSC 7 cwd tracking,
  find, per-session font zoom, and other terminal controls.
- Secure Keyboard Entry with automatic password-prompt detection.
- `iGhostty +ssh` / `+ssh-cache` helpers for remote `xterm-ghostty` terminfo.
- Always-on background service with login-item support.
- Built-in updates via Sparkle 2.

[Unreleased]: https://github.com/bandoracer/ighostty/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/bandoracer/ighostty/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/bandoracer/ighostty/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/bandoracer/ighostty/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/bandoracer/ighostty/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/bandoracer/ighostty/releases/tag/v1.0.0
