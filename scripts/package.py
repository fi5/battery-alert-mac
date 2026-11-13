#!/usr/bin/env python3
"""Package the latest app as a drag-to-Applications DMG and a ZIP fallback."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--app", type=Path)
parser.add_argument("--output", type=Path, default=root / "dist")
args = parser.parse_args()
version = (root / "VERSION").read_text().strip()
app = args.app or Path((root / "build/latest-app.txt").read_text().strip())
if not (app / "Contents/MacOS/BatteryAlert").is_file():
    raise SystemExit("Build the app first: python3 scripts/build.py")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
architectures = subprocess.check_output(["lipo", "-archs", str(app / "Contents/MacOS/BatteryAlert")], text=True).split()
architecture = "universal" if {"arm64", "x86_64"}.issubset(architectures) else "-".join(architectures)
name = "Battery-Alert-" + version + "-" + architecture
dmg = output / (name + ".dmg")
archive = output / (name + ".zip")
if dmg.exists() or archive.exists():
    raise SystemExit("Release artifacts already exist. Choose a fresh --output directory or change VERSION.")
staging = Path(tempfile.mkdtemp(prefix="dmg-", dir=str(root / "build")))
shutil.copytree(app, staging / app.name, symlinks=True)
(staging / "Applications").symlink_to("/Applications", target_is_directory=True)
shutil.copy2(root / "INSTALL.txt", staging / "Read Me - 安装说明.txt")
subprocess.run(["ditto", "-c", "-k", "--keepParent", str(app), str(archive)], check=True)
# Write a filesystem image directly, then compress it to a normal UDIF DMG.
# This avoids mounting a temporary volume or depending on virtual disk devices.
raw = staging.parent / (staging.name + "-raw.dmg")
subprocess.run(["hdiutil", "makehybrid", "-hfs", "-hfs-volume-name", "Battery Alert", "-o", str(raw), str(staging)], check=True)
subprocess.run(["hdiutil", "convert", str(raw), "-format", "UDZO", "-o", str(dmg)], check=True)
subprocess.run(["hdiutil", "verify", str(dmg)], check=True)
with (output / "SHA256SUMS.txt").open("x") as stream:
    for artifact in (dmg, archive):
        stream.write(hashlib.sha256(artifact.read_bytes()).hexdigest() + "  " + artifact.name + "\n")
print("Release files: " + str(output))
