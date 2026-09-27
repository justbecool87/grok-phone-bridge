#!/data/data/com.termux/files/usr/bin/bash
# Mirror Fleet LIVE feed into MiXplorer-readable sdcard files + open via ADB.
# Primary viewer: com.mixplorer.beta ContentViewerActivity (HTML auto-refresh).
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
REG="$FLEET/regulator"
SRC_LIVE="$REG/LIVE.txt"
SRC_FEED="$REG/FEED.txt"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
PIDFILE="$REG/mix-mirror.pid"
MIX_PKG="com.mixplorer.beta"
MIX_VIEW="com.mixplorer.beta/com.mixplorer.activities.ContentViewerActivity"
MIX_CODE="com.mixplorer.beta/com.mixplorer.activities.CodeEditorActivity"
HTML="$MIRROR/index.html"
LACKETS=(scout probe svd-smith harbor courier quay archivist loom)

mkdir -p "$REG" "$MIRROR" "$FLEET/bus" "$FLEET/state"
touch "$SRC_LIVE" "$SRC_FEED"

usage() {
  cat <<'EOF'
fleet-mix-mirror — MiXplorer live mirror via ADB (or SSH same paths)

  fleet-mix-mirror start     # daemon: write FEED/LIVE/index.html + keep bus warm
  fleet-mix-mirror stop
  fleet-mix-mirror status
  fleet-mix-mirror open      # adb → MiXplorer ContentViewer (HTML live)
  fleet-mix-mirror open-feed # adb → MiXplorer CodeEditor on FEED.txt
  fleet-mix-mirror reload    # re-fire VIEW intent (force refresh)
  fleet-mix-mirror once      # single publish pass
  fleet-mix-mirror ssh-hint  # print SSH one-liners for remote open

Files:
  /sdcard/Download/grok-inbox/fleet-monitor/index.html
  /sdcard/Download/grok-inbox/fleet-monitor/LIVE.txt
  /sdcard/Download/grok-inbox/fleet-monitor/FEED.txt
EOF
}

ts() { date -Iseconds; }

html_escape() {
  python3 -c 'import sys,html; print(html.escape(sys.stdin.read()), end="")'
}

publish() {
  # Ensure source feed has a heartbeat line
  if command -v fleet-bus >/dev/null 2>&1; then
    L="${LACKETS[$(( $(date +%s) % ${#LACKETS[@]} ))]}"
    fleet-bus state "$L" pinging "mix-mirror" >/dev/null 2>&1 || true
    fleet-bus send "$L" fleet-captain ping "mix-mirror" >/dev/null 2>&1 || true
    fleet-bus send fleet-captain "$L" ack "mix-mirror ACK" >/dev/null 2>&1 || true
    fleet-bus state "$L" idle "on-station" >/dev/null 2>&1 || true
    {
      echo "╔══ FLEET PROJECT MONITOR  $(ts)  mix-mirror ══╗"
      fleet-bus board 2>/dev/null || true
      echo
      fleet-bus clips 8 2>/dev/null || true
      echo "╚══════════════════════════════════════════════╝"
    } > "$SRC_LIVE"
  fi

  printf '%s\n' "[$(ts)] mix-mirror publish uid=$(id -u)" >> "$SRC_FEED"
  if [[ -f "$FLEET/bus/messages.jsonl" ]]; then
    python3 - "$FLEET/bus/messages.jsonl" "$SRC_FEED" <<'PYF' 2>/dev/null || true
import json, sys
path, out = sys.argv[1], sys.argv[2]
try:
    lines = open(path).read().splitlines()[-2:]
except FileNotFoundError:
    lines = []
with open(out, "a") as f:
    for row in lines:
        row = row.strip()
        if not row:
            continue
        m = json.loads(row)
        f.write(f"[{m['ts']}] {m['from']} → {m['to']} | {m['kind']}: {m['body'][:100]}\n")
PYF
  fi
  # bound feed
  if [[ $(wc -l < "$SRC_FEED" 2>/dev/null || echo 0) -gt 500 ]]; then
    tail -n 400 "$SRC_FEED" > "$SRC_FEED.tmp" && mv "$SRC_FEED.tmp" "$SRC_FEED"
  fi

  cp -f "$SRC_LIVE" "$MIRROR/LIVE.txt"
  cp -f "$SRC_FEED" "$MIRROR/FEED.txt"
  chmod 664 "$MIRROR/LIVE.txt" "$MIRROR/FEED.txt" 2>/dev/null || true

  # Self-contained HTML (inlined) for MiXplorer ContentViewer auto-refresh
  python3 - "$SRC_LIVE" "$SRC_FEED" "$HTML" <<'PYH'
import html, pathlib, sys, time, os
live, feed, out = map(pathlib.Path, sys.argv[1:4])
live_txt = live.read_text(errors="replace") if live.exists() else ""
feed_txt = feed.read_text(errors="replace") if feed.exists() else ""
# keep HTML smaller
feed_tail = "\n".join(feed_txt.splitlines()[-120:])
ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
uid = os.getuid()
doc = f"""<!DOCTYPE html>
<html><head>
<meta charset=\"utf-8\"/>
<meta http-equiv=\"refresh\" content=\"4\"/>
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>
<title>Fleet LIVE · MiXplorer</title>
<style>
body{{font-family:ui-monospace,monospace;background:#0b0f14;color:#e5eef7;margin:0;padding:12px}}
h1{{font-size:18px;color:#7dd3fc;margin:0 0 6px}}
.meta{{color:#94a3b8;font-size:12px;margin-bottom:12px}}
h2{{font-size:14px;color:#a5b4fc;margin:16px 0 6px}}
pre{{white-space:pre-wrap;word-break:break-word;background:#111827;border:1px solid #1f2937;
padding:10px;border-radius:10px;line-height:1.35;font-size:12px}}
</style>
</head><body>
<h1>Fleet Project Monitor</h1>
<p class=\"meta\">MiXplorer mirror · auto-refresh 4s · {html.escape(ts)} · uid={uid}</p>
<h2>LIVE board</h2>
<pre>{html.escape(live_txt)}</pre>
<h2>FEED (tail)</h2>
<pre>{html.escape(feed_tail)}</pre>
</body></html>
"""
out.write_text(doc)
PYH
  chmod 664 "$HTML" 2>/dev/null || true
}

adb_open() {
  local target="${1:-html}"
  command -v adb >/dev/null || { echo "adb missing" >&2; exit 1; }
  local serial
  serial=$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1; exit}')
  [[ -n "$serial" ]] || { echo "no adb device" >&2; exit 1; }

  if [[ "$target" == "feed" ]]; then
    adb -s "$serial" shell am start -W \
      -a android.intent.action.VIEW -t text/plain \
      -d "file://$MIRROR/FEED.txt" \
      -n "$MIX_CODE" >/dev/null
    echo "opened FEED.txt in MiXplorer CodeEditor ($serial)"
  else
    adb -s "$serial" shell am start -W \
      -a android.intent.action.VIEW -t text/html \
      -d "file://$MIRROR/index.html" \
      -n "$MIX_VIEW" >/dev/null
    echo "opened index.html in MiXplorer ContentViewer ($serial)"
  fi
}

cmd_start() {
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [[ -n "${old:-}" && -d "/proc/$old" ]]; then
      echo "already running pid=$old"
      publish
      adb_open html || true
      return 0
    fi
  fi
  if [[ -f "$REG/watch.pid" ]]; then
    w=$(cat "$REG/watch.pid" 2>/dev/null || true)
    if [[ -n "${w:-}" && -d "/proc/$w" ]]; then kill "$w" 2>/dev/null || true; fi
  fi

  publish
  DAEMON_BIN="$HOME/bin/fleet-mix-mirror"
  nohup bash -c '
    set +e
    export HOME="'"$HOME"'"
    export PATH="'"$HOME"'/bin:/data/data/com.termux/files/usr/bin:$PATH"
    FLEET_HOME="'"$FLEET"'"
    PIDFILE="'"$PIDFILE"'"
    echo $$ > "$PIDFILE"
    command -v fleet-bus >/dev/null && fleet-bus send regulator fleet-captain monitor "MiXplorer ADB mirror daemon online"
    while true; do
      "'"$DAEMON_BIN"'" once >/dev/null 2>&1
      sleep 4
    done
  ' >>"$REG/mix-mirror.log" 2>&1 &
  sleep 1
  echo "mix-mirror daemon pid=$(cat "$PIDFILE" 2>/dev/null || echo unknown)"
  adb_open html || true
}

cmd_stop() {
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [[ -n "${old:-}" && -d "/proc/$old" ]]; then
      kill "$old" 2>/dev/null || true
      echo "stopped $old"
    fi
    rm -f "$PIDFILE"
  else
    echo "not running"
  fi
}

cmd_status() {
  local st=stopped
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [[ -n "${old:-}" && -d "/proc/$old" ]]; then st="running pid=$old"; fi
  fi
  echo "daemon: $st"
  echo "mirror: $MIRROR"
  ls -la "$MIRROR" 2>/dev/null || true
  adb devices -l 2>/dev/null | head -5
}

cmd_ssh_hint() {
  cat <<EOF
# Same-device paths (Termux SSHD or ConnectBot → localhost):
# After SSH in, republish + open via adb locally:

fleet-mix-mirror once
fleet-mix-mirror open

# From a remote PC over SSH (if phone SSHD listens), then use phone-local adb:
ssh phone 'export PATH=\$HOME/bin:\$PATH; fleet-mix-mirror once && fleet-mix-mirror open'

# Or scp the mirror tree (usually unnecessary — already on /sdcard):
# scp -r phone:/sdcard/Download/grok-inbox/fleet-monitor ./
EOF
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  open) publish; adb_open html ;;
  open-feed) publish; adb_open feed ;;
  reload) adb_open html ;;
  once) publish; echo "published $(ts)" ;;
  ssh-hint) cmd_ssh_hint ;;
  -h|--help|help|"") usage ;;
  *) usage; exit 2 ;;
esac
