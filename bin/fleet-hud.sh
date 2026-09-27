#!/data/data/com.termux/files/usr/bin/bash
# Fleet HUD — Termux terminal + ADB/MiXplorer permission overlay.
# Dots: working=YELLOW  ready=GREEN  idle/overburdened=RED  + counts
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
STATE="$FLEET/state"
OUT_ANSI="$FLEET/hud/HUD.ansi"
OUT_TXT="$FLEET/hud/HUD.txt"
OUT_JSON="$FLEET/hud/HUD.json"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
PIDFILE="$FLEET/hud/hud.pid"
INTERVAL="${FLEET_HUD_SEC:-3}"

# ANSI colors
Y=$'\033[33m'  # yellow working
G=$'\033[32m'  # green ready
R=$'\033[31m'  # red idle/overburdened
Z=$'\033[0m'
BOLD=$'\033[1m'

mkdir -p "$FLEET/hud" "$MIRROR"

render() {
  python3 - "$STATE" "$OUT_JSON" "$OUT_TXT" <<'PY'
import json, pathlib, sys, time, collections
state_dir, out_json, out_txt = map(pathlib.Path, sys.argv[1:4])

WORKING = {
    "installing","deploying","fetching","assisting-forge","researching","mirroring",
    "sampling","verifying","priming","priming-render","coordinating","indexing",
    "hardening","staging-cache","bootstrapping","assisting-primary","enhancing",
    "elevating","analyzing","suggesting","reviewing","commanding","monitoring",
    "calibrating","receiving-directives","deploying-actors","adjusting","pinging",
    "reporting","accept","assign","heartbeat","complete","growing",
}
READY = {"ready","priming","standing-by","acknowledged","resting","idle-ready"}
# note: priming counted working above — for svd-smith "priming" with await prompt => ready-ish
READY_DETAIL = ("await project prompt", "ready", "awaiting captain", "on-station ready")
OVERBURDEN_HINT = ("overburden", "protected p0", "high_traffic")

actors = []
for f in sorted(state_dir.glob("*.json")):
    try:
        d = json.loads(f.read_text().strip().splitlines()[-1])
    except Exception:
        continue
    a = d.get("actor") or f.stem
    if a in ("fleet-captain", "termux-commander", "regulator", "monitor"):
        # include directors in HUD too but mark role
        role = "director"
    else:
        role = "actor"
    tr = str(d.get("transit", "unknown")).lower()
    det = str(d.get("detail", "")).lower()
    # classify
    bucket = "idle"
    if any(h in det for h in OVERBURDEN_HINT) or tr == "overburdened":
        bucket = "overburdened"
    elif tr in WORKING or any(tr.startswith(w) for w in WORKING):
        # special: priming + await prompt => ready
        if "await" in det and "prompt" in det:
            bucket = "ready"
        else:
            bucket = "working"
    elif tr in READY or any(x in det for x in READY_DETAIL):
        bucket = "ready"
    elif tr in ("idle", "unknown", "acknowledged") or "on-station" in det:
        bucket = "idle"
    else:
        # default busy-looking transits
        if tr not in ("idle",):
            bucket = "working"
    actors.append({"id": a, "role": role, "transit": d.get("transit"), "detail": d.get("detail",""), "bucket": bucket})

counts = collections.Counter(a["bucket"] for a in actors)
doc = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "counts": {
        "working": counts.get("working", 0),
        "ready": counts.get("ready", 0),
        "idle": counts.get("idle", 0) + counts.get("overburdened", 0),
        "overburdened": counts.get("overburdened", 0),
        "total": len(actors),
    },
    "legend": {"working": "yellow", "ready": "green", "idle/overburdened": "red"},
    "actors": actors,
}
out_json.write_text(json.dumps(doc, indent=2) + "\n")
# plain text with emoji dots for MiXplorer / non-ANSI
lines = [
    f"FLEET HUD {doc['ts']}",
    f"🟡 WORKING {doc['counts']['working']}   🟢 READY {doc['counts']['ready']}   🔴 IDLE/OVER {doc['counts']['idle']}   Σ{doc['counts']['total']}",
    "—" * 48,
]
for a in actors:
    dot = {"working": "🟡", "ready": "🟢", "idle": "🔴", "overburdened": "🔴"}.get(a["bucket"], "⚪")
    lines.append(f"{dot} {a['id']:<18} {str(a['transit']):<16} {str(a['detail'])[:42]}")
out_txt.write_text("\n".join(lines) + "\n")
print(doc["counts"]["working"], doc["counts"]["ready"], doc["counts"]["idle"], doc["counts"]["total"])
PY

  # ANSI overlay for Termux terminal
  local w r i ttot
  read -r w r i ttot < <(python3 -c 'import json;d=json.load(open("'"$OUT_JSON"'"));c=d["counts"];print(c["working"],c["ready"],c["idle"],c["total"])')
  {
    printf '%s' "${BOLD}FLEET HUD${Z}  "
    printf '%s●%s%s%d%s  ' "$Y" "$Z" "$Y" "$w" "$Z"
    printf '%s●%s%s%d%s  ' "$G" "$Z" "$G" "$r" "$Z"
    printf '%s●%s%s%d%s  ' "$R" "$Z" "$R" "$i" "$Z"
    printf 'Σ%d\n' "$ttot"
    printf '%s\n' "  ${Y}working${Z}  ${G}ready${Z}  ${R}idle/overburdened${Z}"
    python3 - "$OUT_JSON" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
color={"working":"\033[33m","ready":"\033[32m","idle":"\033[31m","overburdened":"\033[31m"}
Z="\033[0m"
for a in d["actors"]:
    c=color.get(a["bucket"],"\033[37m")
    print(f"  {c}●{Z} {a['id']:<18} {str(a['transit']):<16} {str(a['detail'])[:40]}")
PY
  } > "$OUT_ANSI"

  cp -f "$OUT_TXT" "$MIRROR/FLEET-HUD.txt"
  cp -f "$OUT_JSON" "$MIRROR/FLEET-HUD.json"
  cp -f "$OUT_ANSI" "$MIRROR/FLEET-HUD.ansi"
  # permission overlay stub for Grok/ADB consumers
  printf '%s\n' "fleet-hud permission=granted source=termux-overlay adb=allowed" > "$FLEET/hud/PERMISSION.overlay"
  cp -f "$FLEET/hud/PERMISSION.overlay" "$MIRROR/FLEET-HUD.PERMISSION"
}

show() {
  render
  # clear-line friendly dump
  if [[ -t 1 ]]; then
    printf '\033[2J\033[H'  # optional clear — only if tty
  fi
  cat "$OUT_ANSI"
}

watch_loop() {
  while true; do
    if [[ -t 1 ]]; then
      printf '\033[2J\033[H'
    fi
    render
    cat "$OUT_ANSI"
    sleep "$INTERVAL"
  done
}

cmd_start() {
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [[ -n "${old:-}" && -d "/proc/$old" ]]; then
      echo "hud daemon already pid=$old"
      render
      return 0
    fi
  fi
  nohup bash -c '
    set +e
    export HOME="'"$HOME"'" PATH="'"$HOME"'/bin:/data/data/com.termux/files/usr/bin:$PATH"
    echo $$ > "'"$PIDFILE"'"
    while true; do
      "'"$HOME"'/bin/fleet-hud" render >/dev/null 2>&1
      sleep '"$INTERVAL"'
    done
  ' >/dev/null 2>&1 &
  sleep 1
  echo "fleet-hud daemon pid=$(cat "$PIDFILE") interval=${INTERVAL}s"
  # tmux HUD session if tmux exists
  if command -v tmux >/dev/null; then
    if ! tmux has-session -t fleet-hud 2>/dev/null; then
      tmux new-session -d -s fleet-hud "export PATH=$HOME/bin:/data/data/com.termux/files/usr/bin:\$PATH; fleet-hud watch"
      echo "tmux session: fleet-hud (attach: tmux attach -t fleet-hud)"
    else
      echo "tmux session fleet-hud already exists"
    fi
  fi
  # one-shot inject into grok if available (permission overlay ping)
  if command -v adb-to-grok >/dev/null; then
    render
    line=$(head -2 "$OUT_TXT" | tr '\n' ' ')
    adb-to-grok say "[FLEET HUD] $line" >/dev/null 2>&1 || true
  fi
  show | head -20
}

cmd_stop() {
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    [[ -n "${old:-}" && -d "/proc/$old" ]] && kill "$old" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  tmux kill-session -t fleet-hud 2>/dev/null || true
  echo stopped
}

case "${1:-show}" in
  render) render ;;
  show) show ;;
  watch) watch_loop ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  status)
    echo "pid=$(cat "$PIDFILE" 2>/dev/null || echo none)"
    [[ -f "$OUT_TXT" ]] && head -15 "$OUT_TXT"
    ;;
  *)
    cat <<'EOF'
Usage: fleet-hud show|watch|start|stop|status|render

Dots:  yellow=working  green=ready  red=idle/overburdened  + counts
Termux: tmux attach -t fleet-hud
MiXplorer: /sdcard/Download/grok-inbox/fleet-monitor/FLEET-HUD.txt
EOF
    ;;
esac
