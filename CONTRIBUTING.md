# Contributing to iGhostty

Thanks for your interest in improving iGhostty! This is a native macOS terminal
that wraps [`libghostty`](https://github.com/ghostty-org/ghostty) (via
[`libghostty-spm`](https://github.com/Lakr233/libghostty-spm)) with an
iTerm2-style application layer. Contributions of all sizes are welcome.

## Ways to contribute

- **Report bugs** — open a [bug report](https://github.com/bandoracer/ighostty/issues/new?template=bug_report.yml).
- **Request features** — open a [feature request](https://github.com/bandoracer/ighostty/issues/new?template=feature_request.yml).
  Please check [`GHOSTTY_PARITY.md`](GHOSTTY_PARITY.md) first — some items are
  already tracked, planned, or intentional non-goals.
- **Improve docs** — README, parity matrix, and inline comments.
- **Send pull requests** — bug fixes, parity improvements, and new app-layer
  features.

## Development setup

Requirements:

- macOS 13 (Ventura) or newer
- Xcode's Swift toolchain (Swift 5.9+) — install Xcode or the Command Line Tools

Dependencies resolve automatically through Swift Package Manager. The terminal
surface and theme catalog come from `libghostty-spm`; auto-update uses Sparkle.

```sh
git clone https://github.com/bandoracer/ighostty.git
cd ighostty
swift build      # debug build
swift test       # Ghostty parity unit tests
```

To run the full app bundle (with the generated icon and bundled Ghostty
resources):

```sh
make app         # builds dist/iGhostty.app (release)
make run         # build + open
```

Other useful targets: `make dmg`, `make appcast`, `make icon`, `make clean`.
See the [Makefile](Makefile) and the README's *Build & run* section for details.

## Project layout

The application layer lives in `Sources/iGhostty/`. The README's *Architecture*
section maps each file to its responsibility. The emulator and renderer live in
`libghostty` and are not part of this repository.

## Coding guidelines

- **Match the surrounding style.** This is idiomatic AppKit + Swift; follow the
  conventions, naming, and comment density already in the file you're editing.
- **Keep the app layer in its lane.** Terminal emulation, rendering, input, and
  selection belong to `libghostty`. iGhostty owns profiles, settings,
  windowing, tabs/splits, the global hotkey, drop-down behavior, imports, and
  local shell process integration.
- **Avoid new dependencies** unless there's a clear reason; raise it in an issue
  first.
- **Update the parity matrix.** If you change Ghostty or iTerm2 compatibility,
  reflect it in [`GHOSTTY_PARITY.md`](GHOSTTY_PARITY.md).
- **No secrets.** Never commit signing private keys, notarization credentials,
  or build artifacts (`dist/` and `.build/` are gitignored).

## Tests

Run `swift test` before opening a PR. The suite in
`Tests/iGhosttyTests/GhosttyParityTests.swift` covers shell-integration
environment setup, the Ghostty config override parser, bundled-resource
validation, the theme catalog, and settings migration. Please add or update
tests when you change that behavior — the *Tests To Keep Current* section of the
parity matrix lists the areas worth covering.

## Pull request checklist

- [ ] `swift build` and `swift test` pass locally.
- [ ] New behavior has tests where practical.
- [ ] Docs updated (README and/or `GHOSTTY_PARITY.md`) when behavior changes.
- [ ] The change is focused; unrelated cleanups go in a separate PR.
- [ ] No build artifacts, secrets, or personal paths are included.

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
