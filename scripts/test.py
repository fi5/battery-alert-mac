#!/usr/bin/env python3
"""Run the battery policy tests without launching an app or sending notifications."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
build = root / "build"
build.mkdir(exist_ok=True)
output = Path(tempfile.mkdtemp(prefix="tests-", dir=str(build))) / "policy-tests"
subprocess.run([
    "xcrun", "swiftc", "-swift-version", "5", "-module-cache-path", str(build / "ModuleCache"),
    str(root / "Sources/BatteryState.swift"), str(root / "Tests/main.swift"), "-o", str(output)
], check=True)
subprocess.run([str(output)], check=True)
