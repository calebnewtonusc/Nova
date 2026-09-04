#!/usr/bin/env bash
# Schedule the Nova operator brief for 8:00am daily via launchd.
# It runs Claude headless against the /brief skill, which gathers the morning's
# state (nova brief) and triages + delivers it. Idempotent.
set -uo pipefail

NOVA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOUR="${1:-8}"
MIN="${2:-0}"
LABEL="ai.nova.brief"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.nova/brief.log"
CLAUDE="$(command -v claude || echo "$HOME/.nvm/versions/node/v22.20.0/bin/claude")"

mkdir -p "$HOME/.nova" "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>cd $NOVA_ROOT &amp;&amp; $CLAUDE -p "/brief" --dangerously-skip-permissions &gt;&gt; $LOG 2>&amp;1</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$HOUR</integer><key>Minute</key><integer>$MIN</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
PL

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

printf 'Scheduled the Nova brief for %02d:%02d daily.\n' "$HOUR" "$MIN"
echo "  plist: $PLIST"
echo "  log:   $LOG"
echo
echo "Test it now without waiting for morning:"
echo "  launchctl start $LABEL   # runs it immediately"
echo "  nova brief               # just the raw gather, no triage"
echo
echo "Remove it:"
echo "  launchctl unload $PLIST && rm $PLIST"
