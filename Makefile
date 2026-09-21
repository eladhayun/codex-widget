.PHONY: help build test check open assets dmg-tools dmg screenshots

DMG_PATH ?= build/Codex-Widget.dmg
DMGBUILD ?= build/dmg-tools/bin/dmgbuild

help:
	@echo "make build  Build a locally signed app in build/"
	@echo "make test   Run parser and connection tests"
	@echo "make check  Verify live Codex account access without model tasks"
	@echo "make open   Build and launch the menu bar app"
	@echo "make dmg-tools  Install pinned DMG packaging tools into build/"
	@echo "make dmg    Build a drag-to-Applications disk image"
	@echo "make assets Regenerate the app icon and DMG artwork"
	@echo "make screenshots  Refresh sample-data README screenshots"

build:
	swift build -c release
	mkdir -p "build/Codex Widget.app/Contents/MacOS"
	cp .build/release/CodexWidget "build/Codex Widget.app/Contents/MacOS/CodexWidget"
	cp Resources/Info.plist "build/Codex Widget.app/Contents/Info.plist"
	mkdir -p "build/Codex Widget.app/Contents/Resources"
	cp LICENSE "build/Codex Widget.app/Contents/Resources/LICENSE"
	cp Resources/AppIcon.icns "build/Codex Widget.app/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "build/Codex Widget.app"

test:
	swift test

check:
	swift run CodexWidget --check

open: build
	open "build/Codex Widget.app"

assets:
	swift scripts/render-assets.swift
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

dmg-tools:
	python3 -m venv build/dmg-tools
	build/dmg-tools/bin/python -m pip install -r scripts/dmg-requirements.txt

dmg: build
	bash scripts/package-dmg.sh "build/Codex Widget.app" "$(DMG_PATH)" "$(DMGBUILD)"

screenshots:
	TZ=UTC swift test --filter PanelRenderTests
	mkdir -p docs/screenshots
	cp .build/previews/panel-usage-dark.png docs/screenshots/usage.png
	cp .build/previews/panel-stats-dark.png docs/screenshots/stats.png
	cp .build/previews/panel-status-dark.png docs/screenshots/status.png
	cp .build/previews/settings.png docs/screenshots/settings.png
