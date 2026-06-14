.PHONY: build app dmg notarize release release-notarized run clean icon notary-profile-help

build:
	swift build

app:
	bash scripts/make_app.sh

dmg:
	bash scripts/make_dmg.sh

release: dmg

notarize:
	bash scripts/notarize_dmg.sh

release-notarized: dmg notarize

notary-profile-help:
	@echo 'Create the default notary profile with:'
	@echo '  xcrun notarytool store-credentials ighostty-notary --apple-id YOUR_APPLE_ID --team-id JEJ96LFJF7'
	@echo 'Use the app-specific password generated at https://account.apple.com when prompted.'

run: app
	open dist/iGhostty.app

icon:
	rm -f Support/AppIcon.icns
	bash -c 'ICONSET=$$(mktemp -d)/AppIcon.iconset && swift scripts/gen_icon.swift "$$ICONSET" && iconutil -c icns "$$ICONSET" -o Support/AppIcon.icns'

clean:
	rm -rf .build dist
