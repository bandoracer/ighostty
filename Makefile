.PHONY: build app dmg appcast notarize release release-notarized run clean icon notary-profile-help sparkle-key-help

build:
	swift build

app:
	bash scripts/make_app.sh

dmg:
	bash scripts/make_dmg.sh

appcast: dmg
	bash scripts/make_appcast.sh

release: appcast

notarize:
	bash scripts/notarize_dmg.sh

release-notarized: dmg notarize appcast

notary-profile-help:
	@echo 'Create the default notary profile with:'
	@echo '  xcrun notarytool store-credentials ighostty-notary --apple-id YOUR_APPLE_ID --team-id JEJ96LFJF7'
	@echo 'Use the app-specific password generated at https://account.apple.com when prompted.'

sparkle-key-help:
	@echo 'Sparkle key account: dev.ighostty.app'
	@echo 'Public key embedded in Support/Info.plist:'
	@echo '  7PMeZ7MFzaxgU0X4OOkHZFx4Q6foClp9eaY9E38L/yk='
	@echo 'Print or generate the local private signing key with:'
	@echo '  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.ighostty.app'
	@echo 'Export it for CI only if needed with:'
	@echo '  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account dev.ighostty.app -x sparkle-private-key.txt'

run: app
	open dist/iGhostty.app

icon:
	rm -f Support/AppIcon.icns
	bash -c 'ICONSET=$$(mktemp -d)/AppIcon.iconset && swift scripts/gen_icon.swift "$$ICONSET" && iconutil -c icns "$$ICONSET" -o Support/AppIcon.icns'

clean:
	rm -rf .build dist
