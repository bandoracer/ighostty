# Security Policy

## Supported versions

iGhostty is distributed as a rolling release. Security fixes land in the latest
version, delivered through the built-in Sparkle updater and
[GitHub Releases](https://github.com/bandoracer/ighostty/releases).

| Version | Supported |
| --- | --- |
| Latest 1.0.x | ✅ |
| Older releases | ❌ |

Please update to the latest release before reporting an issue.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately through GitHub's
[private vulnerability reporting](https://github.com/bandoracer/ighostty/security/advisories/new)
(the **Security → Report a vulnerability** tab on the repository). This keeps the
report confidential until a fix is available.

When reporting, please include:

- A description of the issue and its impact.
- Steps to reproduce, ideally with a minimal example.
- The iGhostty version (`iGhostty` → *About*) and your macOS version.

You can expect an initial acknowledgement within a few days. We'll keep you
updated on remediation and coordinate disclosure timing with you.

## Scope and notes

Areas most relevant to iGhostty's security posture:

- **Auto-update channel.** Updates are delivered over HTTPS and verified with a
  Sparkle EdDSA (`ed25519`) signature; the public key is embedded in the app's
  `Info.plist`. Report anything that could bypass signature verification.
- **Secure Keyboard Entry.** iGhostty exposes a manual toggle plus an automatic
  password-prompt heuristic. Report cases where secure input fails to engage at
  a password prompt, or where the lock indicator misrepresents the active state.
- **PTY environment injection.** New sessions export Ghostty resource, terminfo,
  and shell-integration paths into the child shell's environment.
- **SSH terminfo helper.** `iGhostty +ssh` installs `xterm-ghostty` terminfo on
  remote hosts; report command-construction or escaping issues.

Issues in upstream dependencies (`libghostty` / `libghostty-spm`, Sparkle)
should also be reported to those projects, but feel free to flag them here so we
can track the impact on iGhostty.
