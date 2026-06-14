.PHONY: build app dmg release run clean icon

build:
	swift build

app:
	bash scripts/make_app.sh

dmg:
	bash scripts/make_dmg.sh

release: dmg

run: app
	open dist/iGhostty.app

icon:
	rm -f Support/AppIcon.icns
	bash -c 'ICONSET=$$(mktemp -d)/AppIcon.iconset && swift scripts/gen_icon.swift "$$ICONSET" && iconutil -c icns "$$ICONSET" -o Support/AppIcon.icns'

clean:
	rm -rf .build dist
