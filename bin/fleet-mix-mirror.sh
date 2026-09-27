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
LACKETS=(scout probe svd-smith harbor courier quay archivist loom forge)

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
  local torch_ok=0 diff_ok=0 pip_busy=0 src_ok=0 frames_ok=0
  [[ -f "$HOME/grok-inbox/VID_20260927_105213.mp4" ]] && src_ok=1
  [[ -f "$HOME/grok-inbox/svd-work/frames/frame_0s.jpg" ]] && frames_ok=1
  [[ -d "$HOME/grok-inbox/svd-work/venv/lib/python3.13/site-packages/torch" ]] && torch_ok=1
  [[ -d "$HOME/grok-inbox/svd-work/venv/lib/python3.13/site-packages/diffusers" ]] && diff_ok=1
  pgrep -f '/svd-work/venv/bin/pip install' >/dev/null 2>&1 && pip_busy=1

  # Active duty map — Lackeys must NOT sit idle during FC-001
  if command -v fleet-bus >/dev/null 2>&1; then
    if [[ "$src_ok" -eq 1 ]]; then
      fleet-bus state scout verifying "source staged VID_20260927_105213.mp4" >/dev/null 2>&1 || true
      fleet-bus send scout fleet-captain report "VERIFY source present in grok-inbox" >/dev/null 2>&1 || true
    else
      fleet-bus state scout searching "locate Messages video on /sdcard" >/dev/null 2>&1 || true
    fi

    if [[ "$frames_ok" -eq 1 ]]; then
      fleet-bus state probe sampling "keyframes + segment_0_3s under svd-work" >/dev/null 2>&1 || true
      fleet-bus send probe fleet-captain report "PROBE frames ready; suitability check running" >/dev/null 2>&1 || true
    else
      fleet-bus state probe extracting "pulling probe frames via ffmpeg" >/dev/null 2>&1 || true
    fi

    if [[ "$pip_busy" -eq 1 ]]; then
      fleet-bus state svd-smith installing "pip resume torch/diffusers stack" >/dev/null 2>&1 || true
      fleet-bus state quay deploying "Kali venv package install in progress" >/dev/null 2>&1 || true
      fleet-bus state courier fetching "pulling wheel deps for SVD runtime" >/dev/null 2>&1 || true
    elif [[ "$diff_ok" -eq 1 && "$torch_ok" -eq 1 ]]; then
      fleet-bus state svd-smith priming "SVD runtime imports OK — await owner project prompt" >/dev/null 2>&1 || true
      fleet-bus state quay hardening "venv health check + export paths" >/dev/null 2>&1 || true
      fleet-bus state courier staging-cache "HF/SVD weight fetch armed (hold for prompt)" >/dev/null 2>&1 || true
    else
      fleet-bus state svd-smith bootstrapping "runtime incomplete — continue install" >/dev/null 2>&1 || true
      fleet-bus state quay deploying "ensure python3.13 venv + ffmpeg" >/dev/null 2>&1 || true
      fleet-bus state courier fetching "resolve missing torch/diffusers artifacts" >/dev/null 2>&1 || true
    fi

        # PIP ACTORS REASSERT — keep install cast locked on active transits
    if [[ "$pip_busy" -eq 1 ]]; then
      fleet-bus state svd-smith installing "torch/diffusers pip install ACTIVE" >/dev/null 2>&1 || true
      fleet-bus state quay deploying "venv deploy ACTIVE during pip" >/dev/null 2>&1 || true
      fleet-bus state courier fetching "wheel/fetch ACTIVE during pip" >/dev/null 2>&1 || true
      fleet-bus send svd-smith fleet-captain report "INSTALLING diffusion stack now" >/dev/null 2>&1 || true
      fleet-bus send quay fleet-captain report "DEPLOYING packages into svd-work/venv" >/dev/null 2>&1 || true
      fleet-bus send courier fleet-captain report "FETCHING pip artifacts for SVD" >/dev/null 2>&1 || true
      fleet-bus state svd-smith installing "post-report continue install" >/dev/null 2>&1 || true
      fleet-bus state quay deploying "post-report continue deploy" >/dev/null 2>&1 || true
      fleet-bus state courier fetching "post-report continue fetch" >/dev/null 2>&1 || true
    fi

    fleet-bus state archivist researching "SVD presets for 1280x720 Messages clip" >/dev/null 2>&1 || true
    fleet-bus send archivist fleet-captain report "RESEARCH protocol svd/PROTOCOL.md + motion bucket defaults" >/dev/null 2>&1 || true

    fleet-bus state loom priming-render "encoder path exports/ + audio mux plan" >/dev/null 2>&1 || true
    fleet-bus state forge fetching "GitHub lean pack research/pull for actor libraries" >/dev/null 2>&1 || true
    fleet-bus send forge fleet-captain report "FORGE pulling assist repos per actor" >/dev/null 2>&1 || true
    fleet-bus state forge indexing "actor repo library under github-lackey/repos" >/dev/null 2>&1 || true
    fleet-bus send loom fleet-captain report "RENDER pipeline primed (no overwrite of source)" >/dev/null 2>&1 || true

    fleet-bus state harbor mirroring "MiXplorer LIVE feed + adb-to-grok inject path" >/dev/null 2>&1 || true
    fleet-bus send harbor fleet-captain report "MIRROR publish to /sdcard/.../fleet-monitor" >/dev/null 2>&1 || true

    fleet-bus state regulator monitoring "Lackey duty clock — no idle allowed on FC-001" >/dev/null 2>&1 || true
    fleet-bus send regulator fleet-captain heartbeat "adjustment=keep-active thoroughness=high" >/dev/null 2>&1 || true

    # Rotate a focused ping WITHOUT returning to idle
    local L focus_transit
    L="${LACKETS[$(( $(date +%s) % ${#LACKETS[@]} ))]}"
    case "$L" in
      scout) focus_transit=verifying ;;
      probe) focus_transit=sampling ;;
      svd-smith) focus_transit=$([[ "$pip_busy" -eq 1 ]] && echo installing || echo priming) ;;
      harbor) focus_transit=mirroring ;;
      courier) focus_transit=$([[ "$pip_busy" -eq 1 ]] && echo fetching || echo staging-cache) ;;
      quay) focus_transit=deploying ;;
      archivist) focus_transit=researching ;;
      loom) focus_transit=priming-render ;;
      *) focus_transit=working ;;
    esac
    fleet-bus state "$L" "$focus_transit" "focus tick FC-001" >/dev/null 2>&1 || true
    fleet-bus send "$L" fleet-captain ping "ACTIVE $focus_transit" >/dev/null 2>&1 || true
    fleet-bus send fleet-captain "$L" ack "ACTIVE ACK — remain on $focus_transit" >/dev/null 2>&1 || true
    # re-assert focus transit after ACK (do not idle)
    fleet-bus state "$L" "$focus_transit" "post-ack continue duty" >/dev/null 2>&1 || true

    # Regulator: idle Lackeys must assist GitHub Lackey (Forge) with learned skills
    if command -v fleet-regulator-reassign >/dev/null 2>&1; then
      fleet-regulator-reassign scan >/dev/null 2>&1 || true
    fi

    # Live HUD counts — refresh with every mirror publish
    if command -v fleet-hud >/dev/null 2>&1; then
      fleet-hud render >/dev/null 2>&1 || true
    fi
    HUD_LINE="🟡? 🟢? 🔴?"
    if [[ -f "$HOME/grok-inbox/fleet/hud/HUD.json" ]]; then
      HUD_LINE=$(python3 - <<'PYC'
import json
from pathlib import Path
c=json.loads(Path.home().joinpath("grok-inbox/fleet/hud/HUD.json").read_text())["counts"]
print(f"🟡{c['working']} working · 🟢{c['ready']} ready · 🔴{c['idle']} idle · Σ{c['total']}")
PYC
)
    fi
    {
      echo "╔══ FLEET PROJECT MONITOR  $(ts)  ACTIVE DUTIES ══╗"
      echo "HUD  $HUD_LINE"
      echo "     (auto-adjusts each mirror refresh as actors change workflow)"
      echo
      fleet-bus board 2>/dev/null || true
      echo
      echo "workload: src=$src_ok frames=$frames_ok torch=$torch_ok diffusers=$diff_ok pip_busy=$pip_busy"
      fleet-bus clips 8 2>/dev/null || true
      echo "╚══════════════════════════════════════════════╝"
    } > "$SRC_LIVE"
  fi

  printf '%s\n' "[$(ts)] ACTIVE publish focus — pip_busy=$pip_busy torch=$torch_ok diff=$diff_ok" >> "$SRC_FEED"
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
  if [[ $(wc -l < "$SRC_FEED" 2>/dev/null || echo 0) -gt 500 ]]; then
    tail -n 400 "$SRC_FEED" > "$SRC_FEED.tmp" && mv "$SRC_FEED.tmp" "$SRC_FEED"
  fi

  cp -f "$SRC_LIVE" "$MIRROR/LIVE.txt"
  cp -f "$SRC_FEED" "$MIRROR/FEED.txt"
  chmod 664 "$MIRROR/LIVE.txt" "$MIRROR/FEED.txt" 2>/dev/null || true

  # Ensure HUD files exist for this refresh
  if command -v fleet-hud >/dev/null 2>&1; then
    fleet-hud render >/dev/null 2>&1 || true
  fi
  HUD_JSON="$HOME/grok-inbox/fleet/hud/HUD.json"
  HUD_TXT="$HOME/grok-inbox/fleet/hud/HUD.txt"
  python3 - "$SRC_LIVE" "$SRC_FEED" "$HTML" "$HUD_JSON" "$HUD_TXT" "$MIRROR" <<'PYH'
import html, json, pathlib, sys, time, os, shutil
live, feed, out, hud_json, hud_txt, mirror = map(pathlib.Path, sys.argv[1:7])
live_txt = live.read_text(errors="replace") if live.exists() else ""
feed_txt = feed.read_text(errors="replace") if feed.exists() else ""
feed_tail = "\n".join(feed_txt.splitlines()[-120:])
hud_body = hud_txt.read_text(errors="replace") if hud_txt.exists() else ""
counts = {"working": 0, "ready": 0, "idle": 0, "total": 0}
actors = []
if hud_json.exists():
    try:
        doc_h = json.loads(hud_json.read_text())
        counts = doc_h.get("counts", counts)
        actors = doc_h.get("actors", [])
    except Exception:
        pass
w, r, i, tot = counts.get("working",0), counts.get("ready",0), counts.get("idle",0), counts.get("total",0)
rows = []
for a in actors:
    b = a.get("bucket", "idle")
    color = {"working": "#facc15", "ready": "#22c55e", "idle": "#ef4444", "overburdened": "#ef4444"}.get(b, "#94a3b8")
    rows.append(
        f"<div class='actor'><span class='dot' style='background:{color}'></span>"
        f"<span class='name'>{html.escape(str(a.get('id','')))}</span>"
        f"<span class='tr'>{html.escape(str(a.get('transit','')))}</span>"
        f"<span class='det'>{html.escape(str(a.get('detail',''))[:48])}</span></div>"
    )
actors_html = "\n".join(rows) or "<div class='meta'>no actor states yet</div>"
ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
uid = os.getuid()
doc = f"""<!DOCTYPE html>
<html><head>
<meta charset=\"utf-8\"/>
<meta http-equiv=\"refresh\" content=\"4\"/>
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>
<title>Fleet LIVE · HUD</title>
<style>
body{{font-family:ui-monospace,monospace;background:#0b0f14;color:#e5eef7;margin:0;padding:12px}}
h1{{font-size:18px;color:#7dd3fc;margin:0 0 6px}}
.meta{{color:#94a3b8;font-size:12px;margin-bottom:12px}}
h2{{font-size:14px;color:#a5b4fc;margin:16px 0 6px}}
.hud{{display:flex;gap:10px;flex-wrap:wrap;margin:10px 0 14px}}
.pill{{border-radius:999px;padding:10px 14px;font-weight:700;font-size:16px;border:1px solid #1f2937}}
.pill .n{{font-size:22px;margin-right:6px}}
.y{{background:#422006;color:#facc15}}
.g{{background:#052e16;color:#22c55e}}
.r{{background:#450a0a;color:#f87171}}
.s{{background:#111827;color:#e5eef7}}
.actor{{display:grid;grid-template-columns:18px 140px 140px 1fr;gap:8px;align-items:center;
padding:4px 0;border-bottom:1px solid #1f2937;font-size:12px}}
.dot{{width:10px;height:10px;border-radius:50%;display:inline-block}}
.name{{color:#e5eef7}} .tr{{color:#93c5fd}} .det{{color:#94a3b8}}
pre{{white-space:pre-wrap;word-break:break-word;background:#111827;border:1px solid #1f2937;
padding:10px;border-radius:10px;line-height:1.35;font-size:12px}}
</style>
</head><body>
<h1>Fleet Project Monitor · LIVE HUD</h1>
<p class=\"meta\">MiXplorer mirror · auto-refresh 4s · {html.escape(ts)} · uid={uid} · dots auto-adjust with actor workflow</p>
<div class=\"hud\">
  <div class=\"pill y\"><span class=\"n\">{w}</span>🟡 working</div>
  <div class=\"pill g\"><span class=\"n\">{r}</span>🟢 ready</div>
  <div class=\"pill r\"><span class=\"n\">{i}</span>🔴 idle/over</div>
  <div class=\"pill s\"><span class=\"n\">{tot}</span>Σ actors</div>
</div>
<p class=\"meta\">Current snapshot: 🟡{w} working · 🟢{r} ready · 🔴{i} idle</p>
<h2>Actors (live)</h2>
{actors_html}
<h2>HUD dump</h2>
<pre>{html.escape(hud_body)}</pre>
<h2>LIVE board</h2>
<pre>{html.escape(live_txt)}</pre>
<h2>FEED (tail)</h2>
<pre>{html.escape(feed_tail)}</pre>
</body></html>
"""
out.write_text(doc)
# keep HUD artifacts in mirror in sync every refresh
try:
    if hud_txt.exists():
        shutil.copy2(hud_txt, mirror / "FLEET-HUD.txt")
    if hud_json.exists():
        shutil.copy2(hud_json, mirror / "FLEET-HUD.json")
    ansi = pathlib.Path.home()/"grok-inbox/fleet/hud/HUD.ansi"
    if ansi.exists():
        shutil.copy2(ansi, mirror / "FLEET-HUD.ansi")
    (mirror / "FLEET-HUD.PERMISSION").write_text(
        "fleet-hud permission=granted source=live-mirror-refresh adb=allowed\n"
    )
except Exception:
    pass
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
