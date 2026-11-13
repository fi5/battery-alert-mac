#!/usr/bin/env python3
"""Package the latest app as a drag-to-Applications DMG and a ZIP fallback."""
import argparse
import hashlib
import plistlib
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
subprocess.run([
    "hdiutil", "create", "-volname", "Battery Alert", "-srcfolder", str(staging),
    "-fs", "HFS+", "-format", "UDZO", str(dmg)
], check=True)
subprocess.run(["hdiutil", "verify", str(dmg)], check=True)
mount = Path(tempfile.mkdtemp(prefix="verify-mount-", dir=str(root / "build")))
subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(dmg)], check=True, stdout=subprocess.DEVNULL)
try:
    installed_app = mount / app.name
    metadata = plistlib.loads((installed_app / "Contents/Info.plist").read_bytes())
    if metadata["CFBundleShortVersionString"] != version or not (mount / "Applications").is_symlink():
        raise SystemExit("The DMG installation contents do not match this release.")
    subprocess.run(["codesign", "--verify", "--strict", str(installed_app)], check=True)
finally:
    subprocess.run(["hdiutil", "detach", str(mount)], check=True, stdout=subprocess.DEVNULL)
with (output / "SHA256SUMS.txt").open("a") as stream:
    for artifact in (dmg, archive):
        stream.write(hashlib.sha256(artifact.read_bytes()).hexdigest() + "  " + artifact.name + "\n")
print("Release files: " + str(output))
