#!/bin/bash
set -euo pipefail

app=${1:?Usage: package-dmg.sh APP OUTPUT [DMGBUILD]}
output=${2:?Usage: package-dmg.sh APP OUTPUT [DMGBUILD]}
dmgbuild=${3:-build/dmg-tools/bin/dmgbuild}
root=$(cd "$(dirname "$0")/.." && pwd)

if [[ ! -x "$dmgbuild" ]]; then
    echo 'DMG tools are missing. Run: make dmg-tools' >&2
    exit 1
fi
codesign --verify --strict "$app"
test -f "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$(dirname "$output")"
"$dmgbuild" -s "$root/scripts/dmg-settings.py" -D "app=$app" -D "root=$root" 'Codex Widget' "$output"
hdiutil verify "$output"

# Verify the distributed bundle, Applications shortcut, artwork, and release tag.
mount_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-widget-dmg.XXXXXX")
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        hdiutil detach "$mount_dir" -quiet
    fi
    rmdir "$mount_dir"
}
trap cleanup EXIT
hdiutil attach "$output" -mountpoint "$mount_dir" -readonly -nobrowse -quiet
mounted=true
codesign --verify --strict "$mount_dir/Codex Widget.app"
test "$(readlink "$mount_dir/Applications")" = /Applications
test -f "$mount_dir/.DS_Store"
cmp "$app/Contents/Resources/AppIcon.icns" "$mount_dir/Codex Widget.app/Contents/Resources/AppIcon.icns"
cmp "$app/Contents/Resources/LICENSE" "$mount_dir/Codex Widget.app/Contents/Resources/LICENSE"
if [[ -n "${RELEASE_TAG:-}" ]]; then
    test "$(/usr/libexec/PlistBuddy -c 'Print :CodexReleaseTag' "$mount_dir/Codex Widget.app/Contents/Info.plist")" = "$RELEASE_TAG"
fi
