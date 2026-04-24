#!/bin/bash
# One-shot installer for Music Format Switcher.
# Builds the app, removes the legacy daemon, installs to ~/Applications.

set -euo pipefail
cd "$(dirname "$0")"

BUNDLE="MusicFormatSwitcher.app"
INSTALL="$HOME/Applications/$BUNDLE"
AGENT="$HOME/Library/LaunchAgents/com.user.music-format-daemon.plist"

echo "==> Building…"
swift build -c release

echo "==> Creating app bundle…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/MusicFormatSwitcher "$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE/Contents/"
strip -rSTx "$BUNDLE/Contents/MacOS/MusicFormatSwitcher"
codesign --sign - --force "$BUNDLE"

echo "==> Removing legacy daemon (if present)…"
if [ -f "$AGENT" ]; then
    launchctl unload "$AGENT" 2>/dev/null || true
    rm "$AGENT"
    echo "    Removed $AGENT"
fi

echo "==> Installing to ~/Applications…"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALL"
cp -r "$BUNDLE" "$INSTALL"

echo "==> Launching…"
open "$INSTALL"

echo ""
echo "Done. Music Format Switcher is now in your menu bar."
echo "Open it once and grant Automation access for Apple Music when prompted."
