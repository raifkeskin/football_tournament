#!/bin/bash
# Gol kesiti MP4 betiğini Mac'e kurar: Python ortamı (Pillow), yt-dlp ve
# 10 dakikada bir çalışan launchd görevi. Tekrar çalıştırmak güvenlidir.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Library/Application Support/LigMasasi"
VENV="$APP/goal-clips-venv"
PLIST="$HOME/Library/LaunchAgents/com.ligmasasi.goal-clips.plist"
mkdir -p "$APP" "$HOME/Library/Logs"

command -v /opt/homebrew/bin/ffmpeg >/dev/null || brew install ffmpeg
command -v /opt/homebrew/bin/yt-dlp >/dev/null || brew install yt-dlp
[ -x "$VENV/bin/python" ] || /usr/bin/python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip pillow

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.ligmasasi.goal-clips</string>
  <key>ProgramArguments</key><array>
    <string>$VENV/bin/python</string><string>$DIR/goal_clips.py</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>StartInterval</key><integer>600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/ligmasasi-goal-clips.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/ligmasasi-goal-clips.log</string>
</dict></plist>
PL
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Kuruldu. Günlük: ~/Library/Logs/ligmasasi-goal-clips.log"
