# Third-Party Notices

iGhostty depends on Swift Package Manager packages and prebuilt binary artifacts
that are distributed separately from this repository.

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
`Support/GhosttyResources`. The upstream snapshot is recorded in
`Support/GhosttyResources/UPSTREAM.txt`.

License: MIT, except where preserved file headers say otherwise.

```text
Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors
```

The zsh and bash Ghostty shell integration files preserve upstream GPLv3 headers
because those portions are based on Kitty shell integration:

```text
Support/GhosttyResources/share/ghostty/shell-integration/zsh/ghostty-integration
Support/GhosttyResources/share/ghostty/shell-integration/bash/ghostty.bash
```

Those files are distributed under the GNU General Public License version 3 or
later, as stated in their headers. The GPL text is available from the Free
Software Foundation at https://www.gnu.org/licenses/gpl-3.0.txt.

The bundled `bash-preexec.sh` file is copied from Ghostty's shell integration
tree and retains its upstream attribution header.

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

License: MIT/BSD-style licenses; see Sparkle's bundled `LICENSE` for the full
third-party license text included with its distribution.

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
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
