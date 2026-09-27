#!/bin/bash
# Install/uninstall the analysis-watchdog LaunchAgent for the current user.
# Usage: ./install.sh [install|uninstall]
set -eu

LABEL="local.analysis-watchdog"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/Library/Application Support/analysis-watchdog"
SCRIPT="$DEST_DIR/analysis-watchdog.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/analysis-watchdog.log"
DOMAIN="gui/$(id -u)"

do_uninstall() {
    # bootout sends SIGTERM; the watchdog resumes the paused daemons on exit.
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$DEST_DIR"
    echo "uninstalled $LABEL (log kept at $LOG)"
}

do_install() {
    mkdir -p "$DEST_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    install -m 755 "$SRC_DIR/analysis-watchdog.sh" "$SCRIPT"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
        <string>run</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF
    plutil -lint "$PLIST" >/dev/null
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "installed $LABEL"
    echo "  script: $SCRIPT"
    echo "  agent:  $PLIST"
    echo "  log:    $LOG"
}

case "${1:-install}" in
    install) do_install ;;
    uninstall) do_uninstall ;;
    *) echo "usage: $0 [install|uninstall]" >&2; exit 2 ;;
esac
