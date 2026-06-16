# Ghostty Parity Matrix

This matrix tracks iGhostty against the public Ghostty feature documentation
used for the June 15, 2026 parity pass. `+ssh` remains version-gated because
Ghostty documents it as tip/1.4.0-only.

## Legend

- Shipped: implemented in iGhostty.
- Partial: implemented with important limits.
- Planned: app-layer work remains.
- Blocked: requires `libghostty-spm`/`libghostty` API surface that is not
  currently available here.
- Non-goal: intentionally outside this app's scope.

## Core Terminal

| Area | Status | iGhostty state |
| --- | --- | --- |
| VT/xterm emulation | Shipped | Provided by `GhosttyTerminal` / `libghostty`. |
| GPU rendering | Shipped | Metal-backed Ghostty terminal surface. |
| Fonts, ligatures, IME, mouse, selection | Shipped | Inherited from GhosttyTerminal, with app-level profile controls. |
| Kitty graphics protocol | Shipped | Exposed through libghostty terminal core. |
| OSC 7 cwd | Shipped | Updates session cwd and window `representedURL`. |
| OSC 8 hyperlinks | Shipped | Open-URL and hover-link delegates are wired to AppKit. |
| OSC 9 / 777 notifications | Shipped | Desktop-notification delegate uses macOS notifications. |
| OSC 9;4 progress | Shipped | Progress delegate records current progress state. |
| Command finished | Shipped | Command-finished delegate records exit and duration state. |
| Text selection requests | Shipped | Selection request delegate copies requested text to pasteboard. |

## Resources And Environment

| Area | Status | iGhostty state |
| --- | --- | --- |
| `TERM=xterm-ghostty` | Shipped | New profiles default to `xterm-ghostty`; blank TERM falls back to it. |
| Bundled terminfo source | Shipped | `Support/GhosttyResources/share/terminfo/ghostty.terminfo`. |
| Bundled compiled terminfo | Shipped | Local `67/ghostty` and `78/xterm-ghostty` entries copied into app bundle. |
| Shell integration resources | Shipped | Ghostty zsh, bash, fish, elvish, and nushell integrations are bundled. |
| `ghostty` resource shim | Shipped | `Resources/GhosttyResources/bin/ghostty` forwards to iGhostty. |
| PTY env vars | Shipped | Exports `GHOSTTY_RESOURCES_DIR`, `GHOSTTY_BIN_DIR`, `TERMINFO`, `COLORTERM`, `TERM_PROGRAM`, and `TERM_PROGRAM_VERSION`. |
| Resource validation UI | Shipped | Settings reports missing bundled resource paths. |

## Shell Integration

| Area | Status | iGhostty state |
| --- | --- | --- |
| `shell-integration` setting | Shipped | Profiles support detect, none, zsh, bash, fish, elvish, and nushell. |
| `shell-integration-features` | Shipped | Profiles expose comma-separated Ghostty feature names. |
| Default features | Shipped | Defaults to `cursor,path,title`; `cursor` follows the Text tab blink setting, prompt marks are opt-in with `prompt`, and SSH/sudo wrappers are opt-in. |
| zsh auto-injection | Shipped | Uses Ghostty's `ZDOTDIR` integration path. |
| fish/elvish/nushell auto-injection | Shipped | Uses XDG data directory integration paths. |
| bash auto-injection | Partial | Uses Ghostty's POSIX-mode ENV injection for non-system bash; `/bin/bash` is left untouched to avoid breaking macOS shell startup. |
| Prompt navigation | Shipped | Menu actions call `jump_to_prompt:-1` and `jump_to_prompt:1`; profiles must include the `prompt` shell-integration feature to emit prompt marks. |

## Configuration And Themes

| Area | Status | iGhostty state |
| --- | --- | --- |
| Ghostty theme catalog | Shipped | `GhosttyThemeCatalog` augments native iGhostty schemes. |
| Separate light/dark selection | Shipped | Profiles keep independent light and dark scheme choices and previews. |
| Native settings GUI | Partial | High-value settings are first-class; the full Ghostty reference is not duplicated. |
| Raw config overrides | Shipped | `key = value` lines compose after native settings; repeated keys are preserved. |
| Invalid override reporting | Shipped | The profile editor reports malformed override lines. |
| Custom shaders | Non-goal | `libghostty-spm` intentionally trims shader tooling from this app. |
| Terminal inspector | Non-goal | Ghostty developer inspector is not exposed in iGhostty. |

## macOS App Layer

| Area | Status | iGhostty state |
| --- | --- | --- |
| Native windows, tabs, splits | Shipped | AppKit windows, native tabs, nested splits, and drop-down terminal. |
| Active-directory proxy icon | Shipped | Focused terminal cwd updates `NSWindow.representedURL`. |
| Secure Keyboard Entry | Shipped | Manual menu toggle, automatic password-prompt heuristic, and lock indicator. |
| Desktop notification permission | Partial | Requests notification authorization when a terminal requests notification delivery. |
| Public AppleScript object model | Planned | Existing test automation is not a public AppleScript dictionary. |
| Shortcuts/App Intents | Planned | UI preference exists; public App Intents still need implementation. |
| Automation allow/deny enforcement | Planned | The existing automation channel remains debug-only via `IGHOSTTY_AUTOMATION=1`. |
| Auto-update | Shipped | Sparkle 2 is embedded, with menu/settings controls and appcast generation for GitHub Releases. |

## SSH

| Area | Status | iGhostty state |
| --- | --- | --- |
| `iGhostty +ssh` | Shipped | Wraps ssh, exports Ghostty env, installs remote terminfo, and falls back safely. |
| `iGhostty +ssh-cache` | Shipped | Supports list, add, remove, clear, host lookup, and expiration setting storage. |
| Alternate ssh executable | Shipped | `--ssh=PATH`. |
| Forward env controls | Shipped | `--forward-env=false`, `--terminfo=false`, and `--cache=false`. |
| Remote install strategy | Partial | Uses local bundled terminfo source through remote `tic`; complex ssh command edge cases may need hardening. |

## Tests To Keep Current

- Build checks: `swift build`, `make app`, and packaged-app launch.
- Resource checks: bundled terminfo exists, `infocmp -x xterm-ghostty` works with
  the bundled `TERMINFO`, and Settings reports no missing Ghostty resources.
- Override parser checks: repeated keys, malformed lines, and native-setting
  composition order.
- SSH helper checks: cache add/list/remove/clear and mocked ssh/tic success and
  fallback paths.
- Automation checks: prompt navigation, OSC 7 cwd, OSC 8 URL opening, OSC 9/777
  notifications, OSC 9;4 progress, command-finished notifications, and secure
  input toggle state.
