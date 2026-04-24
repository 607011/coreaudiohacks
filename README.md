# Music Format Switcher

A macOS menu bar app that automatically switches your USB DAC's sample rate and bit depth to match the currently playing Apple Music track — no more manual adjustments in Audio MIDI Setup.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## How it works

Apple Music broadcasts a notification whenever a track starts playing. Music Format Switcher listens for these notifications, queries the track's native sample rate via AppleScript, and sets the CoreAudio physical format of your DAC accordingly — sample rate and bit depth in one step, with (mostly) no audible interruption.

If the sample rate isn't available immediately (common with streamed tracks), the app retries with exponential back-off until the information is ready.

## Features

- **Automatic switching** — reacts instantly on every track change
- **Device picker** — choose your DAC from a dropdown or type a name fragment
- **Launch at Login** — toggle straight from the menu bar
- **No Dock icon** — lives quietly in the menu bar only
- **No dependencies** — pure Swift, CoreAudio, and standard macOS frameworks

## Requirements

- macOS 13 Ventura or later
- Apple Music with Lossless or Hi-Res Lossless enabled
- A USB DAC (tested with Topping D10s)

## Installation

Download the latest **DMG** or **PKG** from the [Releases](../../releases) page.

> **Gatekeeper notice:** The app is not notarized. macOS 15 and later no longer allow bypassing this warning with a simple right-click → Open. Use one of the options below.

**Option A — remove the quarantine flag before opening (easiest):**
```bash
xattr -cr ~/Downloads/MusicFormatSwitcher-*.dmg
```
Then open the DMG normally.

**Option B — allow it after the fact:**
After macOS blocks the app, open **System Settings → Privacy & Security**, scroll down to the blocked-app notice, and click **Open Anyway**.

### DMG

1. Remove the quarantine flag (see above) or be prepared to visit Privacy & Security
2. Open the DMG
3. Drag **MusicFormatSwitcher** into the _Applications_ folder

### PKG

1. Remove the quarantine flag (see above) or be prepared to visit Privacy & Security
2. Open the PKG and follow the installer

On first run the app will ask for permission to control Apple Music via AppleScript — click **Allow**.

## Configuration

The target device is configured directly in the menu bar popover. The setting is saved to `UserDefaults` and persists across relaunches. The device name is matched case-insensitively as a substring, so `D10s` matches `Topping D10s `.

## Building from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/olaublau/coreaudiohacks.git
cd coreaudiohacks
make install          # builds and copies to ~/Applications
```

Other targets:

```bash
make bundle           # build app bundle only
make dmg              # build distributable DMG
make pkg              # build distributable PKG
make release          # build both DMG and PKG
make clean
```

Releasing a new version:

```bash
git tag v1.1
git push origin v1.1  # triggers GitHub Actions → publishes DMG + PKG automatically
```

## Legacy CLI daemon

The original command-line daemon (`music-format-daemon.swift`) and one-shot helper scripts (`sync-samplerate.swift`, `sync-format.swift`) are kept in the repository for reference. The menu bar app supersedes them.

## License

MIT
