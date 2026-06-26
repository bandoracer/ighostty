# Releasing iGhostty

This repo publishes signed macOS builds through GitHub Releases and Sparkle.
Every pushed build must have version-specific release notes in `CHANGELOG.md`
before the release artifacts are generated.

## Release Notes

1. Keep user-facing changes under `## [Unreleased]` while developing.
2. Before building a release, bump `Support/Info.plist`:
   - `CFBundleShortVersionString`: marketing version, for example `1.0.5`.
   - `CFBundleVersion`: monotonically increasing Sparkle build number.
3. Move the relevant `Unreleased` entries into a dated section:

   ```md
   ## [1.0.5] - 2026-06-19

   ### Added

   - Short user-facing note about the feature.
   ```

4. Keep notes concise and user-facing. Mention operator-visible fixes, settings
   migrations, update behavior, and packaging changes when they affect users.
5. Update the compare links at the bottom of `CHANGELOG.md` so `[Unreleased]`
   compares from the new tag and the new version compares from the previous tag.

`scripts/make_appcast.sh` reads the current version from `Support/Info.plist`
and extracts the matching `## [version]` section from `CHANGELOG.md` into
`dist/sparkle-updates/iGhostty-<version>.md`. If that section is missing or
empty, `make appcast` and `make release` fail. This prevents publishing a build
with generic or stale Sparkle notes. `make appcast` also fails unless the
current DMG passes Gatekeeper as `Notarized Developer ID` and has a valid
stapled ticket.

`SPARKLE_RELEASE_NOTES=/path/to/notes.md make appcast` can override the
generated notes for an exceptional release, but the normal release path should
come from `CHANGELOG.md`.

## Build And Publish

1. Verify the tree only contains intended release changes:

   ```sh
   git status -sb
   git diff --check
   swift test
   ```

2. Build the notarized signed artifacts:

   ```sh
   make release
   ```

   `make release` builds the DMG, submits it to Apple notary service with the
   `ighostty-notary` keychain profile, staples the ticket, verifies Gatekeeper,
   and only then generates the Sparkle appcast. `make release-notarized` is kept
   as an explicit alias for the same notarized release path.

3. Verify signatures and Gatekeeper status:

   ```sh
   codesign --verify --deep --strict --verbose=2 dist/iGhostty.app
   codesign --verify --verbose=2 dist/iGhostty-<version>.dmg
   spctl -a -vvv -t open --context context:primary-signature dist/iGhostty-<version>.dmg
   xcrun stapler validate dist/iGhostty-<version>.dmg
   ```

4. Commit the version/changelog/procedure changes and tag the release:

   ```sh
   git add CHANGELOG.md Support/Info.plist scripts docs
   git commit -m "Release iGhostty <version>"
   git tag -a "v<version>" -m "Release iGhostty <version>"
   git push origin main
   git push origin "v<version>"
   ```

5. Create the GitHub release with every asset referenced by the appcast:

   ```sh
   gh release create "v<version>" \
     "dist/iGhostty-<version>.dmg" \
     dist/appcast.xml \
     "dist/sparkle-updates/iGhostty-<version>.md" \
     dist/sparkle-updates/*.delta \
     --title "iGhostty <version>" \
     --notes-file "dist/sparkle-updates/iGhostty-<version>.md"
   ```

   If there are no delta files for the release, omit the `*.delta` argument.

6. Mark the release as latest and validate Sparkle:

   ```sh
   gh release edit "v<version>" --latest
   curl -ILs https://github.com/bandoracer/ighostty/releases/latest/download/appcast.xml
   curl -fsSL https://github.com/bandoracer/ighostty/releases/latest/download/appcast.xml
   ```

   Confirm the redirect points at `v<version>` and the XML contains the new
   `sparkle:version`, `sparkle:shortVersionString`, DMG URL, release-notes URL,
   and any delta URLs.

If GitHub's `/releases/latest/download/appcast.xml` redirect temporarily lags
after publishing, upload the new `dist/appcast.xml` to the previous release with
`gh release upload <previous-tag> dist/appcast.xml --clobber`, then re-check the
latest URL until it redirects to the new tag.
