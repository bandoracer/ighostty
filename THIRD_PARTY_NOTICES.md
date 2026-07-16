# Third-Party Notices

iGhostty depends on Swift Package Manager packages and redistributes prebuilt
binary artifacts and selected upstream runtime resources. Complete license
texts that are required alongside the distribution live under `LICENSES/` and
are copied into the application bundle and release DMG.

## Components

### libghostty-spm / GhosttyTerminal

Repository: https://github.com/Lakr233/libghostty-spm

iGhostty uses the `GhosttyTerminal` and `GhosttyTheme` products from
`libghostty-spm` for the native terminal surface, input handling, display link
integration, configuration bridge to `libghostty`, and generated Ghostty theme
catalog.

License: MIT

```text
Copyright (c) 2026 @Lakr233
```

### Ghostty / libghostty

Repository: https://github.com/ghostty-org/ghostty

The `libghostty` binary distributed through `libghostty-spm` is built from the
Ghostty terminal project.

License: MIT

```text
Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors
```

### Bundled Ghostty runtime resources

Repository: https://github.com/ghostty-org/ghostty

iGhostty bundles a snapshot of Ghostty shell integration resources, terminfo
source, compiled local terminfo entries, and a small `ghostty` command shim under
`Support/GhosttyResources`. The upstream snapshot and the locally modified
files are recorded in `Support/GhosttyResources/UPSTREAM.txt`.

License: MIT, except where preserved file headers say otherwise.

```text
Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors
```

The following Ghostty shell integration files preserve upstream GPLv3-or-later
headers because those portions are based on Kitty shell integration:

```text
Support/GhosttyResources/share/ghostty/shell-integration/zsh/ghostty-integration
Support/GhosttyResources/share/ghostty/shell-integration/zsh/.zshenv
Support/GhosttyResources/share/ghostty/shell-integration/bash/ghostty.bash
```

Those files are distributed under the GNU General Public License version 3 or
later, as stated in their headers. A complete copy is included at
`LICENSES/GPL-3.0.txt`. The zsh integration and `ghostty.bash` contain local
changes made on 2026-06-15; their file headers and
`Support/GhosttyResources/UPSTREAM.txt` describe those changes.

### bash-preexec

Repository: https://github.com/rcaloras/bash-preexec

The bundled `bash-preexec.sh` file is copied from Ghostty's shell integration
tree and originates from the bash-preexec project.

License: MIT

```text
Copyright (c) 2017 Ryan Caloras and contributors
```

The complete license is included at `LICENSES/bash-preexec-MIT.txt`.

### MSDisplayLink

Repository: https://github.com/Lakr233/MSDisplayLink

`MSDisplayLink` is a transitive dependency of `GhosttyTerminal` and provides
display-link scheduling on Apple platforms.

License: MIT

```text
Copyright (c) 2024 Lakr Aream
```

### Sparkle

Repository: https://github.com/sparkle-project/Sparkle

iGhostty embeds Sparkle 2 for built-in macOS update checking and installation.
Sparkle is distributed as a binary Swift Package artifact and includes helper
tools for signing update archives and generating appcasts.

License: MIT/BSD-style licenses. Sparkle's complete license and external
third-party notices are included at `LICENSES/Sparkle.txt`.

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
```

## MIT License Text

The MIT-licensed components above are distributed under the MIT License:

```text
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Product Names

iTerm2, Ghostty, xterm, macOS, and Apple product names are referenced for
compatibility, comparison, or implementation context. iGhostty is not
affiliated with those projects or companies.
