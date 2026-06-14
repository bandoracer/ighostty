# Third-Party Notices

iGhostty depends on Swift Package Manager packages and prebuilt binary artifacts
that are distributed separately from this repository.

## Components

### libghostty-spm / GhosttyTerminal

Repository: https://github.com/Lakr233/libghostty-spm

iGhostty uses the `GhosttyTerminal` product from `libghostty-spm` for the native
terminal surface, input handling, display link integration, and configuration
bridge to `libghostty`.

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

### MSDisplayLink

Repository: https://github.com/Lakr233/MSDisplayLink

`MSDisplayLink` is a transitive dependency of `GhosttyTerminal` and provides
display-link scheduling on Apple platforms.

License: MIT

```text
Copyright (c) 2024 Lakr Aream
```

## MIT License Text

The components above are distributed under the MIT License:

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
