.PHONY: help build test check open

help:
	@echo "make build  Build a locally signed app in build/"
	@echo "make test   Run parser and connection tests"
	@echo "make check  Verify live Codex account access without model tasks"
	@echo "make open   Build and launch the menu bar app"

build:
	swift build -c release
	mkdir -p "build/Codex Widget.app/Contents/MacOS"
	cp .build/release/CodexWidget "build/Codex Widget.app/Contents/MacOS/CodexWidget"
	cp Resources/Info.plist "build/Codex Widget.app/Contents/Info.plist"
	codesign --force --sign - "build/Codex Widget.app"

test:
	swift test

check:
	swift run CodexWidget --check

open: build
	open "build/Codex Widget.app"
