# iGhostty

`iGhostty` is an isolated libghostty port of Term3. It keeps the existing Term3
AppKit experience - profiles, tabs, splits, drop-down terminal, iTerm2 imports,
settings, broadcast input, and background hotkey behavior - while replacing the
terminal core with `GhosttyTerminal` / `libghostty`.

## Build & run

```sh
swift build
swift run iGhostty
```

Release app packaging is available with:

```sh
make app
```
