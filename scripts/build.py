#!/usr/bin/env python3
"""Build a native, universal macOS app. No package downloads are required."""
import argparse
from pathlib import Path
import os
import plistlib
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--arch", choices=["universal", "arm64", "x86_64"], default="universal")
args = parser.parse_args()
version = (root / "VERSION").read_text().strip()
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit("VERSION must be a three-part numeric version.")
build = root / "build"
build.mkdir(exist_ok=True)
work = Path(tempfile.mkdtemp(prefix="app-", dir=str(build)))
app = work / "Battery Alert.app"
contents = app / "Contents"
macos = contents / "MacOS"
macos.mkdir(parents=True)
resources = contents / "Resources"
shutil.copytree(root / "Resources", resources)
shutil.copy2(root / "Assets/Battery.icns", resources / "Battery.icns")
info = {
    "CFBundleIdentifier": "io.github.batteryalertmac",
    "CFBundleName": "Battery Alert", "CFBundleDisplayName": "Battery Alert",
    "CFBundleExecutable": "BatteryAlert", "CFBundleIconFile": "Battery.icns",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
    "CFBundleVersion": version, "CFBundleDevelopmentRegion": "en",
    "CFBundleLocalizations": ["en", "zh-Hans"], "LSMinimumSystemVersion": "13.0",
    "LSUIElement": True, "NSHighResolutionCapable": True,
    "NSHumanReadableCopyright": "Copyright © 2026 Battery Alert contributors. MIT License.",
}
with (contents / "Info.plist").open("wb") as stream:
    plistlib.dump(info, stream)
architectures = ["arm64", "x86_64"] if args.arch == "universal" else [args.arch]
binaries = []
for architecture in architectures:
    output = work / ("BatteryAlert-" + architecture)
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "5", "-O", "-target", architecture + "-apple-macosx13.0",
        "-module-cache-path", str(build / "ModuleCache"),
        str(root / "Sources/BatteryState.swift"), str(root / "Sources/main.swift"),
        "-framework", "AppKit", "-framework", "SwiftUI", "-framework", "IOKit",
        "-framework", "ServiceManagement", "-framework", "UserNotifications", "-o", str(output)
    ], check=True)
    binaries.append(output)
if len(binaries) == 2:
    subprocess.run(["lipo", "-create"] + [str(p) for p in binaries] + ["-output", str(macos / "BatteryAlert")], check=True)
else:
    shutil.copy2(binaries[0], macos / "BatteryAlert")
identity = os.environ.get("CODESIGN_IDENTITY", "-")
sign = ["codesign", "--force", "--sign", identity]
if identity != "-":
    sign += ["--options", "runtime", "--timestamp"]
else:
    # A stable designated requirement preserves the local notification identity on rebuild.
    sign += ["--requirements", '=designated => identifier "io.github.batteryalertmac"']
subprocess.run(sign + [str(app)], check=True)
subprocess.run(["codesign", "--verify", "--strict", str(app)], check=True)
subprocess.run(["lipo", "-archs", str(macos / "BatteryAlert")], check=True)
(build / "latest-app.txt").write_text(str(app) + "\n")
print("Built: " + str(app))
