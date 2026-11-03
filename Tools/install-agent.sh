#!/bin/sh
# Installs Flying Toasters as a login agent that owns the top-right hot corner.
#
#   Tools/install-agent.sh              build, install, start, and disable the
#                                       system top-right hot corner
#   Tools/install-agent.sh --uninstall  stop, remove, and restore the system
#                                       top-right hot corner to "Start Screen Saver"
set -eu

LABEL=com.faucherd.flyingtoasters
DEST="$HOME/Library/Application Support/FlyingToasters"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

stop_agent() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    pkill -f "Application Support/FlyingToasters/FlyingToasters" 2>/dev/null || true
}

if [ "${1:-}" = "--uninstall" ]; then
    stop_agent
    rm -f "$PLIST"
    rm -rf "$DEST"
    defaults write com.apple.dock wvous-tr-corner -int 5   # Start Screen Saver
    defaults write com.apple.dock wvous-tr-modifier -int 0
    killall Dock
    echo "Uninstalled. Top-right hot corner restored to Start Screen Saver."
    exit 0
fi

echo "==> Building release"
(cd "$ROOT" && swift build -c release 2>&1 | tail -3)

echo "==> Installing binary"
stop_agent
mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
cp "$ROOT/.build/release/FlyingToasters" "$DEST/FlyingToasters"

echo "==> Writing LaunchAgent"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$DEST/FlyingToasters</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
PLISTEOF

echo "==> Disabling the system top-right hot corner"
defaults write com.apple.dock wvous-tr-corner -int 1       # disabled
defaults write com.apple.dock wvous-tr-modifier -int 0
killall Dock

echo "==> Starting agent"
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Done. Rest the pointer in the top-right corner to start Flying Toasters."
