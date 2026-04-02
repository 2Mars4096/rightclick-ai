# Release Guide

This repo can now produce and package a native `RightClick AI.app` bundle, but there are still two different quality bars:

- local developer build and install
- signed, notarized release build

## Local Build And Install

Use the normal native path:

```bash
./scripts/build-native-app.sh
./scripts/install-native-app.sh
```

That gives you:

- a built `RightClickApp.app` under `./build/`
- an installed app at `~/Applications/RightClick AI.app`
- a shared runtime installed under `~/Library/Application Support/RightClickAI`
- a menu bar utility that opens Settings on first run if provider setup is incomplete
- a native launch-at-login toggle in Settings for keeping the menu bar app running across reboot and login
- a generic `RightClick AI` selected-text service plus direct built-in Services for `Add to Calendar`, `Draft Response`, `Explain`, `Extract Action Items`, `Polish Draft`, `Rewrite Friendly`, and `Summarize`

If a developer machine already has an older `RightClickCalendar` runtime, the native app still falls back to that path until the new runtime is installed.

## Release Preflight

Run:

```bash
./scripts/release-preflight.sh
```

What it checks:

- app bundle exists
- `Contents/Info.plist` is valid
- bundle name, identifier, executable, and selected-text service metadata exist
- app executable exists and is marked executable

Optional stricter checks:

```bash
RCA_REQUIRE_SIGNED=1 ./scripts/release-preflight.sh
RCA_REQUIRE_GATEKEEPER=1 ./scripts/release-preflight.sh
```

Those stricter checks only make sense on a machine where the app has actually been signed and assessed.

## Package A Release Zip

Run:

```bash
./scripts/package-native-release.sh
```

By default this:

- uses `./build/RightClickApp.app`
- runs preflight first
- writes a zip to `./dist/RightClickAI-macOS-<version>.zip`

Useful overrides:

```bash
RCA_APP_BUNDLE=/path/to/RightClickApp.app ./scripts/package-native-release.sh
RCA_RELEASE_DIR=/tmp/right-click-dist ./scripts/package-native-release.sh
RCA_REQUIRE_SIGNED=1 ./scripts/package-native-release.sh
```

## Signing And Notarization Boundary

This repo now has a real build, install, preflight, and packaging story, but signed distribution still requires a machine with:

- full Xcode
- Apple Developer signing identity
- notarization credentials/profile

That part is intentionally not faked in the repo. The current scripts stop at packaging and local verification so CI and contributor machines can still validate most of the product without access to release credentials.
