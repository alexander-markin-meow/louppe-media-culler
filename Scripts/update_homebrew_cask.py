#!/usr/bin/env python3
"""Pin the Homebrew cask to the latest stable, published GitHub ZIP."""

import hashlib
import json
import plistlib
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

REPOSITORY = "murlexander/louppe-media-culler"
ROOT = Path(__file__).resolve().parents[1]


def render_cask(release, archive, current):
    tag = release["tag_name"]
    if release["draft"] or release["prerelease"] or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Expected a published stable vX.Y.Z release")
    version = tag[1:]
    assets = [asset for asset in release["assets"] if asset["name"] == "Louppe.zip"]
    if len(assets) != 1 or assets[0]["state"] != "uploaded":
        raise ValueError("Release must contain one fully uploaded Louppe.zip")
    asset = assets[0]
    expected_url = f"https://github.com/{REPOSITORY}/releases/download/{tag}/Louppe.zip"
    if asset["browser_download_url"] != expected_url:
        raise ValueError("Unexpected release archive URL")
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    if asset.get("digest") != f"sha256:{checksum}" or asset["size"] != archive.stat().st_size:
        raise ValueError("Downloaded archive does not match GitHub's digest and size")
    with zipfile.ZipFile(archive) as bundle:
        info = plistlib.loads(bundle.read("Louppe.app/Contents/Info.plist"))
        if info["CFBundleIdentifier"] != "com.alexandermarkin.louppe" or info["CFBundleShortVersionString"] != version:
            raise ValueError("Archive app identity/version does not match release")
        if info.get("LSMinimumSystemVersion") != "14.0":
            raise ValueError("Minimum macOS changed; review the cask's compatibility requirement")
        if "SUFeedURL" not in info:
            raise ValueError("Homebrew requires the direct-download build with its updater")
        executable = bundle.read("Louppe.app/Contents/MacOS/Louppe")
        if executable[:8] != bytes.fromhex("cffaedfe0c000001"):
            raise ValueError("App architecture changed; review the cask's arm64 requirement")
    result, count = re.subn(r'^  version "[^"\n]+"$', f'  version "{version}"', current, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("Expected exactly one cask version")
    result, count = re.subn(r'^  sha256 "[0-9a-f]{64}"$', f'  sha256 "{checksum}"', result, flags=re.MULTILINE)
    if count != 1:
        raise ValueError("Expected exactly one cask checksum")
    return result


def main():
    release = json.loads(subprocess.check_output(
        ["gh", "api", f"repos/{REPOSITORY}/releases/latest"], text=True))
    with tempfile.TemporaryDirectory(prefix="louppe-homebrew-") as directory:
        subprocess.run(["gh", "release", "download", release["tag_name"],
                        "--repo", REPOSITORY, "--pattern", "Louppe.zip", "--dir", directory], check=True)
        cask = ROOT / "Casks/louppe.rb"
        current = cask.read_text()
        updated = render_cask(release, Path(directory) / "Louppe.zip", current)
        if updated != current:
            cask.write_text(updated)
            print(f"Updated Homebrew cask to {release['tag_name']}")
        else:
            print(f"Homebrew cask already matches {release['tag_name']}")


if __name__ == "__main__":
    main()
