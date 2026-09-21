#!/usr/bin/env python3
"""Generate the tap cask from the latest published, checksum-verified DMG."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

REPO = "eladhayun/codex-widget"


def main():
    destination = Path(sys.argv[1])
    release = json.loads(subprocess.check_output([
        "gh", "release", "view", "--repo", REPO,
        "--json", "tagName,isDraft,isPrerelease,assets",
    ]))
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)\+build\.(\d+)", release["tagName"])
    if not match or release["isDraft"] or release["isPrerelease"]:
        raise SystemExit("Expected a published stable widget release")
    version, build = match.groups()
    name = f"Codex-Widget-{version}-build.{build}-macOS-arm64.dmg"
    asset = next(a for a in release["assets"] if a["name"] == name)
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run([
            "gh", "release", "download", release["tagName"], "--repo", REPO,
            "--pattern", name, "--pattern", "SHA256SUMS.txt", "--dir", directory,
        ], check=True)
        root = Path(directory)
        digest = hashlib.sha256((root / name).read_bytes()).hexdigest()
        expected = (root / "SHA256SUMS.txt").read_text().strip().split()
        if expected != [digest, name]:
            raise SystemExit("Published DMG checksum mismatch")
        if asset.get("digest") and asset["digest"] != f"sha256:{digest}":
            raise SystemExit("GitHub asset digest mismatch")
    content = f'''cask "codex-widget" do
  version "{version},{build}"
  sha256 "{digest}"

  url "https://github.com/eladhayun/codex-widget/releases/download/v#{{version.csv.first}}%2Bbuild.#{{version.csv.second}}/Codex-Widget-#{{version.csv.first}}-build.#{{version.csv.second}}-macOS-arm64.dmg"
  name "Codex Widget"
  desc "Menu bar monitor for Codex usage and plan quotas"
  homepage "https://github.com/eladhayun/codex-widget"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Codex Widget.app"

  zap trash: "~/Library/Preferences/com.eladhayun.codex-widget.plist"

  caveats <<~EOS
    Requires an existing signed-in Codex installation.
    This app is ad-hoc signed, not notarized. If macOS blocks it, use
    System Settings > Privacy & Security > Open Anyway if you trust it.
  EOS
end
'''
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(content)
    print(f"Updated {destination.name} to {version},{build} (SHA-256 verified)")


if __name__ == "__main__":
    main()
