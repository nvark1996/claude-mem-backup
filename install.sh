#!/bin/sh
# Installs the daily claude-mem backup: ~/.local/bin/claude-mem-backup.sh plus a LaunchAgent
# (local.claude-mem-backup) that runs it every day at 13:30 and at login.
# ./install.sh --uninstall removes the script and the agent (your backups are kept).
set -e
cd "$(dirname "$0")"
SCRIPT="$HOME/.local/bin/claude-mem-backup.sh"
PLIST="$HOME/Library/LaunchAgents/local.claude-mem-backup.plist"
launchctl bootout "gui/$(id -u)/local.claude-mem-backup" 2>/dev/null || true
if [ "$1" = "--uninstall" ]; then
  rm -f "$SCRIPT" "$PLIST"
  echo "claude-mem-backup removed (snapshots in ~/Library/Application Support/claude-mem-backups were kept)"
  exit 0
fi
mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp claude-mem-backup.sh "$SCRIPT"
chmod +x "$SCRIPT"
cat > "$PLIST" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.claude-mem-backup</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SCRIPT</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>13</integer><key>Minute</key><integer>30</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>5</integer>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/claude-mem-backup.err</string>
</dict>
</plist>
P
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "claude-mem-backup installed; first snapshot is running now. Check: tail ~/Library/Logs/claude-mem-backup.log"
