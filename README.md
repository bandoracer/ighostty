# iGhostty

**iTerm2-style terminal polish on libghostty.** A native macOS terminal built
with AppKit and Swift, backed by `GhosttyTerminal` / `libghostty` for terminal
emulation, rendering, input, selection, and Ghostty-compatible configuration.

[![CI](https://github.com/bandoracer/ighostty/actions/workflows/ci.yml/badge.svg)](https://github.com/bandoracer/ighostty/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)](#build--run)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](#build--run)

iGhostty pairs Ghostty's embeddable terminal core with an iTerm2-style macOS
app layer: a Quake-style drop-down terminal, per-profile light/dark themes,
iTerm2 config import, native tabs and splits, and built-in updates. The
emulator, renderer, and input handling come from `libghostty`; iGhostty owns
everything around it.

## Contents

- [Features](#features)
- [Compatibility](#compatibility)
  - [iTerm2 compatibility](#iterm2-compatibility)
  - [Ghostty features](#ghostty-features)
- [Build & run](#build--run)
- [Download & install](#download--install)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Ghostty resources and SSH](#ghostty-resources-and-ssh)
- [Settings file](#settings-file)
- [Architecture](#architecture)
- [Testing hook](#testing-hook)
- [Contributing](#contributing)
- [License & credits](#license--credits)
- [Roadmap](#roadmap)

## Features

- **libghostty terminal core** - VT/xterm emulation, GPU-backed rendering,
  CoreText font handling, keyboard/mouse input, IME, selection, and clipboard
  behavior come from the embeddable Ghostty core.
- **Drop-down terminal** - double-tap Control by default (configurable: any
  modifier, or a classic keyboard shortcut). The panel slides from the top,
  covers the menu bar like iTerm2's hotkey window, joins every Space, floats
  over full-screen apps, keeps sessions alive while hidden, and includes a pin
  button to disable auto-hide. System-wide double-tap detection needs
  Accessibility access; shortcut mode needs no permissions.
- **iTerm2 config compatibility** - import profiles from
  `com.googlecode.iterm2.plist` ("New Bookmarks") or Dynamic Profiles JSON:
  colors, font, command, working directory (including "Recycle" reuse),
  columns/rows, scrollback, transparency/blur, cursor type, option-as-meta,
  bell, and close-on-exit all map across. `.itermcolors` schemes import in the
  Colors tab.
- **Separate light and dark themes** - follow system appearance, force light, or
  force dark. Profiles keep separate light and dark color-scheme selections
  with side-by-side previews, plus manual ANSI-16 editing for either variant.
- **Built-in schemes** - Codex-style scheme families plus the generated
  Ghostty theme catalog from `GhosttyTheme`, preserving separate light and dark
  selection.
- **Ghostty runtime resources** - the app bundle includes Ghostty shell
  integration scripts, `xterm-ghostty` terminfo source and compiled entries,
  and a `ghostty` shim on `GHOSTTY_BIN_DIR`.
- **Ghostty-compatible PTY environment** - new sessions default to
  `TERM=xterm-ghostty` and export `GHOSTTY_RESOURCES_DIR`, `GHOSTTY_BIN_DIR`,
  `TERMINFO`, `COLORTERM`, `TERM_PROGRAM`, and `TERM_PROGRAM_VERSION`.
- **Shell integration controls** - profiles can detect the shell, disable
  integration, or force a supported shell mode, with editable Ghostty
  `shell-integration-features`. The `cursor` feature follows the profile's
  Text tab cursor blink setting.
- **Advanced Ghostty config overrides** - profile-level `key = value` lines are
  composed after native settings, including repeated keys such as `keybind`.
- **Window styles** - standard themed title bar, or compact with no title bar
  and traffic lights floating over the terminal. Switch live in Settings.
- **Always-on background service** - optional login item starts iGhostty
  invisibly with the drop-down hotkey armed. `Cmd-Q` closes terminal windows but
  keeps the background service and drop-down sessions alive; `Option-Cmd-Q`
  quits completely. Launching the app again brings back the Dock icon and a
  regular window.
- **Rich settings GUI** - System Settings-style window with toolbar tabs for
  profiles, colors, hotkey window behavior, imports/exports, and maintenance.
  Changes apply live to open terminals.
- **Splits and tabs** - `Cmd-D` / `Shift-Cmd-D` splits, directional focus,
  pane cycling, maximize active pane, inactive-pane desaturation, new windows,
  and native tabs.
- **Broadcast input** - type into every pane in the active tab at once.
- **Prompt navigation and cwd tracking** - optional shell integration prompt
  marks drive Ghostty `jump_to_prompt` actions, and OSC 7 updates
  active-directory tracking and the macOS proxy icon.
- **Window titles that track the shell** - titles update live from the active
  process and working directory.
- **Find and terminal controls** - scrollback search, clear buffer, copy on
  select, per-session font zoom, visual/audible bell, transparency toggle,
  mouse reporting, and quit confirmation for active jobs.
- **Terminal callbacks** - command-finished state, progress reports, desktop
  notifications, URL opening, hover links, and selection requests are wired to
  macOS app behavior.
- **Secure Keyboard Entry** - manual menu toggle plus automatic password-prompt
  detection, with a visible lock indicator while secure input is active.
- **Ghostty SSH helpers** - `iGhostty +ssh` installs/caches `xterm-ghostty`
  terminfo on remote hosts where possible, and `iGhostty +ssh-cache` manages
  the local cache.
- **Built-in updates** - Sparkle 2 powers automatic update checks, the
  `Check for Updates...` app-menu item, and release appcast generation from the
  signed DMG.

See [`GHOSTTY_PARITY.md`](GHOSTTY_PARITY.md) for the living Ghostty support
matrix, including remaining app-layer gaps and intentional non-goals.

## Compatibility

iGhostty aims to feel familiar coming from iTerm2 while running on Ghostty's
terminal core. Two compatibility surfaces matter: **importing your iTerm2
configuration**, and **how much of Ghostty** is exposed.

### iTerm2 compatibility

iGhostty imports iTerm2 settings from three sources:

| Source | What it contains | Where to import |
| --- | --- | --- |
| `~/Library/Preferences/com.googlecode.iterm2.plist` | All of your iTerm2 profiles (the `New Bookmarks` array) | Settings → Advanced → *Import iTerm2…* |
| Dynamic Profiles file (JSON or plist with a `Profiles` array) | One or more shareable profiles | Settings → Advanced → *Import iTerm2…* |
| `.itermcolors` file | A single color scheme | Colors tab → *Import iTerm2 Scheme (.itermcolors)…* |

Profile import maps these iTerm2 keys onto iGhostty profile settings:

| iTerm2 setting | iGhostty profile setting | Notes |
| --- | --- | --- |
| Name | Profile name | |
| Custom Command + Command | Login shell vs. custom command + arguments | `Custom Shell`/`Yes` ⇒ custom command; otherwise login shell |
| Custom Directory + Working Directory | Working directory | `Yes` ⇒ custom path, `Recycle` ⇒ reuse previous session's directory, otherwise home |
| Normal Font | Font family + size | Size clamped to 6–72 pt |
| Columns / Rows | Initial columns / rows | |
| Scrollback Lines / Unlimited Scrollback | Scrollback | |
| Transparency | Background transparency | iTerm2's `0 = opaque` scale, clamped to ≤ 0.9 |
| Blur / Blur Radius | Background blur + radius | Radius clamped to 0–64 |
| Cursor Type | Cursor shape | `0` underline, `1` bar, `2` block |
| Blinking Cursor | Cursor blink | Also drives the `cursor` shell-integration feature |
| Option Key Sends | Option-as-meta | Non-zero ⇒ Option sends meta |
| Mouse Reporting | Mouse reporting | |
| Silence Bell / Visual Bell | Audible bell / visual bell | |
| Terminal Type | `TERM` value | |
| Close Sessions On End | Close-on-exit behavior | |
| Ansi 0–15, Background, Foreground, Cursor, Cursor Text, Selection | Color scheme | Imported as a `<name> (iTerm2)` scheme |

Anything iTerm2-specific that has no iGhostty equivalent (triggers, smart
selection, AppleScript, semantic history, status bar components, etc.) is not
imported — see the [Roadmap](#roadmap) for what's planned and
[`GHOSTTY_PARITY.md`](GHOSTTY_PARITY.md) for intentional non-goals.

### Ghostty features

The terminal emulator, GPU renderer, font/ligature/IME handling, mouse,
selection, and the Kitty graphics protocol all come from `libghostty`, so
behavior tracks upstream Ghostty. iGhostty adds Ghostty-aware app integration on
top:

| Ghostty capability | iGhostty support |
| --- | --- |
| VT/xterm emulation, GPU rendering, fonts, IME, selection | Shipped via `GhosttyTerminal` / `libghostty` |
| Kitty graphics protocol | Shipped (libghostty core) |
| `xterm-ghostty` terminfo + bundled shell integration | Shipped; bundled in the app and exported into every PTY |
| Shell integration (zsh, bash, fish, elvish, nushell) | Shipped; per-profile detect / disable / force-shell, plus editable `shell-integration-features` |
| OSC 7 cwd, OSC 8 hyperlinks, OSC 9/777 notifications, OSC 9;4 progress | Shipped; wired to AppKit (proxy icon, link opening, notifications) |
| Command-finished / desktop notifications | Shipped |
| Prompt navigation (`jump_to_prompt`) | Shipped; enable the `prompt` shell-integration feature to emit marks |
| Ghostty theme catalog | Shipped; augments iGhostty's built-in schemes |
| Raw Ghostty `key = value` config overrides (incl. repeated `keybind`) | Shipped per profile |
| `+ssh` remote `xterm-ghostty` terminfo install | Shipped (see [SSH](#ghostty-resources-and-ssh)) |
| Custom shaders, terminal inspector | Non-goals (trimmed by `libghostty-spm`) |

The full, status-tracked matrix — including partials, planned work, and
non-goals — lives in [`GHOSTTY_PARITY.md`](GHOSTTY_PARITY.md).

## Build & run

```sh
make app      # builds dist/iGhostty.app (release) with generated icon
make dmg      # builds dist/iGhostty-<version>.dmg with app + Applications shortcut
make appcast  # builds dist/appcast.xml for Sparkle/GitHub Releases
make run      # build + open
swift build   # debug build through SwiftPM
swift test    # focused Ghostty parity unit tests
```

Release builds require a dated `CHANGELOG.md` section for the version in
`Support/Info.plist`; `make appcast` fails if the release notes are missing.
See [`docs/RELEASING.md`](docs/RELEASING.md) for the full publish procedure.

Requires Xcode's Swift toolchain (Swift 5.9+ / macOS 13+). Dependencies resolve
through SwiftPM; the terminal surface comes from
[`libghostty-spm`](https://github.com/Lakr233/libghostty-spm).

## Download & install

Download the latest `iGhostty-<version>.dmg` from GitHub Releases, open it, and
drag `iGhostty.app` to `Applications`.

Local release builds are signed with the available Apple Development identity
when present. They are not Developer ID notarized unless you build with a
Developer ID Application certificate and submit the DMG for notarization.

**First launch (Gatekeeper).** If a build is signed but not notarized, macOS may
refuse to open it the first time. Right-click (or Control-click) `iGhostty.app`
and choose **Open**, then confirm — or clear the quarantine flag manually:

```sh
xattr -dr com.apple.quarantine /Applications/iGhostty.app
```

Sparkle updates use:

```text
https://github.com/bandoracer/ighostty/releases/latest/download/appcast.xml
```

The Sparkle public EdDSA key is embedded in `Support/Info.plist`; the matching
private key is stored in the local Keychain under account `dev.ighostty.app`.
Use `make sparkle-key-help` for key export/import commands and `make appcast`
after the final signed or notarized DMG is built.

## Keyboard shortcuts

| Action | Keys |
| --- | --- |
| New window / tab | `Cmd-N` / `Cmd-T` |
| Split vertically / horizontally | `Option-V` / `Option-H` (also `Cmd-D` / `Shift-Cmd-D`) |
| Focus pane in direction | `Cmd-Option-Left/Up/Down/Right` |
| Next / previous pane | `Cmd-]` / `Cmd-[` |
| Maximize active pane | `Shift-Cmd-Return` |
| Broadcast input to all panes in tab | `Option-Cmd-I` |
| Edit session's profile | `Cmd-I` |
| Close pane -> tab / all panes in tab / window | `Cmd-W` / `Option-Cmd-W` / `Shift-Cmd-W` |
| Select tab by number | `Cmd-1` ... `Cmd-9` |
| Previous / next tab | `Shift-Cmd-[` / `Shift-Cmd-]` |
| Find / next / previous / use selection | `Cmd-F` / `Cmd-G` / `Shift-Cmd-G` / `Cmd-E` |
| Previous / next prompt | `Cmd-Up` / `Cmd-Down` |
| Clear buffer | `Cmd-K` |
| Reset terminal emulator state | `Cmd-R` |
| Scroll to top / end | `Cmd-Home` / `Cmd-End` |
| Font bigger / smaller / reset | `Cmd-+` / `Cmd--` / `Cmd-0` |
| Use transparency | `Cmd-U` |
| Full screen | `Cmd-Return` (also `Control-Cmd-F`) |
| Drop-down terminal | double-tap `Control` (configurable, global) |
| Open profiles | `Cmd-O` |
| Settings | `Cmd-,` |
| Secure Keyboard Entry | app menu toggle |
| Close windows, keep background service | `Cmd-Q` / Dock Quit |
| Restart completely, including background process | app menu |
| Quit completely, including background process | `Option-Cmd-Q` |

## Ghostty resources and SSH

Packaged builds copy bundled Ghostty resources to:

```text
iGhostty.app/Contents/Resources/GhosttyResources
```

Debug `swift build` runs resolve the same resources from
`Support/GhosttyResources` when launched from the repository root. Every PTY
gets the Ghostty resource, terminfo, and binary paths in its environment, so
local shells can use `xterm-ghostty` without a separate install.

The SSH helper is available from the app executable:

```sh
iGhostty +ssh host.example.com
iGhostty +ssh --cache=false -- user@host
iGhostty +ssh-cache --host=user@host
iGhostty +ssh-cache --remove=user@host
```

When remote terminfo installation fails, `+ssh` warns and falls back to
`TERM=xterm-256color`.

## Settings file

Human-readable JSON at:

```text
~/Library/Application Support/iGhostty/settings.json
```

Export and import are available from Settings -> Advanced.

## Architecture

```text
Sources/iGhostty/
  main.swift, AppDelegate.swift     AppKit lifecycle, actions, dynamic menus
  MainMenu.swift                    full menu bar built in code
  Models.swift                      Profile / ColorScheme / AppSettings (Codable)
  SettingsStore.swift               JSON persistence + live-change notifications
  AppUpdater.swift                   Sparkle updater controller
  GhosttyIntegration.swift           resources, shell integration, themes, overrides
  GhosttySSHCLI.swift                +ssh and +ssh-cache command-line helpers
  SecureInputManager.swift           secure keyboard entry state and heuristics
  TerminalSessionView.swift         one pane: GhosttyTerminal surface + PTY bridge
  LocalPTYSession.swift             local shell process and PTY I/O
  SplitTree.swift                   nested NSSplitView pane tree per tab
  TerminalWindowController.swift    windows, native tabs, titles, close confirmation
  Dropdown.swift                    Carbon global hotkey + slide-down NSPanel
  LoginItemService.swift            guarded ServiceManagement login-item registration
  SettingsWindow.swift              toolbar-tab settings window (AppKit shell)
  SettingsPanes.swift               general, hotkey, and advanced SwiftUI panes
  ProfilesPane.swift                profile editor, colors, previews, imports
  KeyRecorder.swift                 keyboard shortcut capture
  Automation.swift                  IGHOSTTY_AUTOMATION=1 test channel
```

The terminal emulator and renderer live in `libghostty`. iGhostty owns the
application layer: profiles, settings, windowing, tabs/splits, global hotkey,
drop-down behavior, imports, and local shell process integration.

## Testing hook

Launch with `IGHOSTTY_AUTOMATION=1` and the app listens for
`iGhostty.automation` distributed notifications plus a temporary command file.
Supported commands include:

```text
type:<text>
splitV
splitH
newTab
newWindow
performAction:<ghostty-action>
secureInput:on|off|toggle
reportUpdater
quitCompletely
restartCompletely
toggleDropdown
openSettings:<tab>
setScheme:<name>
snap:<directory>
```

The automation channel is disabled unless the environment variable is set.

## Contributing

Contributions are welcome — bug fixes, parity improvements, and new app-layer
features. Start with [`CONTRIBUTING.md`](CONTRIBUTING.md) for setup, coding
guidelines, and the PR checklist.

- **Report a bug:** [bug report form](https://github.com/bandoracer/ighostty/issues/new?template=bug_report.yml)
- **Request a feature:** [feature request form](https://github.com/bandoracer/ighostty/issues/new?template=feature_request.yml)
  (check [`GHOSTTY_PARITY.md`](GHOSTTY_PARITY.md) first)
- **Report a security issue:** see [`SECURITY.md`](SECURITY.md) — please report
  privately, not as a public issue.
- **Release history:** [`CHANGELOG.md`](CHANGELOG.md).

## License & credits

iGhostty is MIT licensed. See `LICENSE`.

iGhostty depends on `GhosttyTerminal` and `GhosttyTheme` from
`libghostty-spm`, which wrap Ghostty's embeddable `libghostty` library and
theme catalog for Apple platforms. Built-in updates use Sparkle. See
`THIRD_PARTY_NOTICES.md` for dependency notices.

## Roadmap

- Session restore across launches
- Public AppleScript object model and Shortcuts/App Intents
- Triggers and smart selection
- tmux control mode
- More first-class Ghostty settings in the profile editor
