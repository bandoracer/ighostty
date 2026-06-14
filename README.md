# iGhostty

**iTerm2-style terminal polish on libghostty.** A native macOS terminal built
with AppKit and Swift, backed by `GhosttyTerminal` / `libghostty` for terminal
emulation, rendering, input, selection, and Ghostty-compatible configuration.

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
- **Built-in schemes** - Codex-style scheme families including Codex, Ayu,
  Catppuccin, Dracula, Everforest, GitHub, Gruvbox, Linear, Material, Monokai,
  Night Owl, Nord, One, Rose Pine, Solarized, Tokyo Night, Vercel, Xcode, and
  Classic.
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
- **cwd inheritance without shell integration** - new tabs/splits can start in
  the previous session's directory via `libproc`; OSC 7 is also supported when
  the shell emits it.
- **Window titles that track the shell** - titles update live from the active
  process and working directory.
- **Find and terminal controls** - scrollback search, clear buffer, copy on
  select, per-session font zoom, visual/audible bell, transparency toggle,
  mouse reporting, and quit confirmation for active jobs.

## Build & run

```sh
make app      # builds dist/iGhostty.app (release) with generated icon
make dmg      # builds dist/iGhostty-<version>.dmg with app + Applications shortcut
make run      # build + open
swift build   # debug build through SwiftPM
```

Requires Xcode's Swift toolchain (Swift 5.9+ / macOS 13+). Dependencies resolve
through SwiftPM; the terminal surface comes from
[`libghostty-spm`](https://github.com/Lakr233/libghostty-spm).

## Download & install

Download the latest `iGhostty-<version>.dmg` from GitHub Releases, open it, and
drag `iGhostty.app` to `Applications`.

Local release builds are signed with the available Apple Development identity
when present. They are not Developer ID notarized unless you build with a
Developer ID Application certificate and submit the DMG for notarization.

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
| Clear buffer | `Cmd-K` |
| Scroll to top / end | `Cmd-Home` / `Cmd-End` |
| Font bigger / smaller / reset | `Cmd-+` / `Cmd--` / `Cmd-0` |
| Use transparency | `Cmd-U` |
| Full screen | `Cmd-Return` (also `Control-Cmd-F`) |
| Drop-down terminal | double-tap `Control` (configurable, global) |
| Open profiles | `Cmd-O` |
| Settings | `Cmd-,` |
| Close windows, keep background service | `Cmd-Q` |
| Quit completely | `Option-Cmd-Q` |

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
toggleDropdown
openSettings:<tab>
setScheme:<name>
snap:<directory>
```

The automation channel is disabled unless the environment variable is set.

## License & credits

iGhostty is MIT licensed. See `LICENSE`.

iGhostty depends on `GhosttyTerminal` from `libghostty-spm`, which wraps
Ghostty's embeddable `libghostty` library for Apple platforms. See
`THIRD_PARTY_NOTICES.md` for dependency notices.

## Roadmap

- Session restore across launches
- Triggers, smart selection, and shell-integration marks
- tmux control mode
- Deeper Ghostty configuration surfacing in the profile editor
