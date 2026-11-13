# Battery Alert

A small native macOS menu bar app that warns before your battery gets too low. The default threshold is **15%**, with a system notification banner and a low-battery icon.

**[Download the latest release](https://github.com/fi5/battery-alert-mac/releases/latest)** · [中文](README.md)

## Features

- Choose a threshold between 5% and 50%.
- Native notifications with an optional sound.
- One alert per low-battery episode; rearmed when power is connected or charge recovers.
- Menu bar controls for current charge, notification testing, and optional launch at login.
- Hide the menu bar icon and reopen the app from Applications to access settings.
- English and Simplified Chinese, following your system language.
- macOS 13 Ventura or later, Apple silicon and Intel.
- No network, account, telemetry, charging modifications, or third-party dependencies.

## Install

Open the DMG, drag **Battery Alert.app** into **Applications**, and launch it there. Click the menu bar battery icon, allow notifications, and send a test notification. Enable **Launch at login** if desired.

The initial build is ad-hoc signed and **not notarized by Apple**. If macOS blocks it, follow [Apple's instructions for opening an app from an unidentified developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). Do not disable Gatekeeper.

If a banner does not appear, enable Battery Alert in System Settings → Notifications, select Banners, and check Focus settings. An accepted notification request does not guarantee a visible banner. The app must remain running; it cannot notify while the Mac is asleep or off, and checks again on wake. If already below the threshold when notifications are enabled, it attempts an alert immediately.

This adds a separate warning and does not change Apple's built-in 10% notification.

## Build

Requires macOS and Xcode Command Line Tools.

```sh
python3 scripts/test.py
python3 scripts/build.py
python3 scripts/package.py
```

Build outputs are ignored by Git. The release includes a universal app in DMG and ZIP formats plus SHA-256 checksums. Packaging uses the macOS disk-image service to create the DMG. GitHub Actions builds and publishes releases when VERSION changes on main. See [release instructions](docs/RELEASING.md).

To uninstall, turn off Launch at login, quit, and move the app to Trash. Preferences remain in the `io.github.batteryalertmac` user defaults domain.

## Implementation

IOKit power-source events, a 60-second fallback check, and wake observation drive the monitor. UserNotifications delivers alerts, and ServiceManagement handles the login item. Core policy tests exercise threshold boundaries, retries, duplicate suppression, relaunch persistence, and recovery.

[MIT License](LICENSE).
