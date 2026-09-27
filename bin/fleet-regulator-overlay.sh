#!/data/data/com.termux/files/usr/bin/bash
# Regulator superiors overlay — MiXplorer board ONLY for Fleet Captain + Termux Commander.
# Also monitors Enhancement Bot token/work growth; Fleet Captain analyzes and may
# directive Commander when growth stalls. Archivist assists token efficiency.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
REG="$FLEET/regulator"
OVER="$REG/superiors"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor/REGULATOR-SUPERIORS"
STATE="$FLEET/state"
BUS="$FLEET/bus/messages.jsonl"
ENH_LOG="$FLEET/github-lackey/logs/actor-enhance.log"
TOKEN_HIST="$OVER/enhance-token-history.jsonl"
ANALYSIS="$OVER/captain-analysis.json"
EFFICIENCY="$OVER/archivist-token-efficiency.md"
PIDFILE="$OVER/overlay.pid"
INTERVAL="${FLEET_REGULATOR_OVERLAY_SEC:-60}"

mkdir -p "$OVER" "$MIRROR" "$REG"

ts() { date -Iseconds; }
bus() { command -v fleet-bus >/dev/null && fleet-bus "$@" >/dev/null 2>&1 || true; }

# Proxy "token usage" for Enhancement Bot: bus msgs from enhance + log bytes + actor tree bytes.
# Real LLM tokens are not exposed here; growth of these proxies = productive agentic work.
measure_enhance() {
  python3 - "$BUS" "$ENH_LOG" "$FLEET/actors" "$TOKEN_HIST" <<'PY'
import json, time, pathlib, collections, sys
bus_path, log_path, actors_path, hist_path = sys.argv[1:5]
now = time.time()
# count enhance-related bus messages (last 10 min)
cutoff = now - 600
enh_msgs = 0
if pathlib.Path(bus_path).exists():
    from datetime import datetime
    for line in open(bus_path, errors="replace"):
        line=line.strip()
        if not line: continue
        try: m=json.loads(line)
        except Exception: continue
        try: epoch=datetime.fromisoformat(m.get("ts","")).timestamp()
        except Exception: continue
        if epoch < cutoff: continue
        blob = json.dumps(m).lower()
        if m.get("from")=="enhance" or m.get("to")=="enhance" or "enhance" in blob:
            enh_msgs += 1

log_bytes = pathlib.Path(log_path).stat().st_size if pathlib.Path(log_path).exists() else 0
actor_files = 0
actor_bytes = 0
ap = pathlib.Path(actors_path)
if ap.is_dir():
    for p in ap.rglob("*"):
        if p.is_file():
            actor_files += 1
            try: actor_bytes += p.stat().st_size
            except OSError: pass

# composite growth score (weighted)
score = enh_msgs * 50 + (log_bytes // 200) + (actor_files * 10) + (actor_bytes // 500)

sample = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "epoch": now,
    "enhance_bus_msgs_10m": enh_msgs,
    "enhance_log_bytes": log_bytes,
    "actor_files": actor_files,
    "actor_bytes": actor_bytes,
    "token_proxy_score": score,
}
pathlib.Path(hist_path).parent.mkdir(parents=True, exist_ok=True)
with open(hist_path, "a") as h:
    h.write(json.dumps(sample) + "\n")
print(json.dumps(sample))
PY
}

growth_analysis() {
  # Compare last samples — if score not growing, Captain must directive Commander
  python3 - "$TOKEN_HIST" "$ANALYSIS" <<'PY'
import json, pathlib, sys, time
hist_path, out_path = sys.argv[1:3]
lines=[]
if pathlib.Path(hist_path).exists():
    lines=[json.loads(x) for x in open(hist_path) if x.strip()]
if len(lines) < 2:
    doc={
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "verdict": "WARMUP",
        "reason": "need >=2 samples to judge Enhancement Bot token/work growth",
        "samples": len(lines),
        "captain_action": "WAIT",
        "commander_directive": None,
    }
else:
    a, b = lines[-2], lines[-1]
    delta = b["token_proxy_score"] - a["token_proxy_score"]
    # also require some time gap
    growing = delta > 0
    stalled = delta <= 0
    if growing:
        doc={
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "verdict": "GROWING",
            "reason": f"token_proxy_score {a['token_proxy_score']} → {b['token_proxy_score']} (Δ{delta})",
            "latest": b,
            "previous": a,
            "captain_action": "CONTINUE",
            "commander_directive": None,
        }
    else:
        doc={
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "verdict": "STALLED",
            "reason": f"Enhancement Bot token/work proxy not growing (Δ{delta}). Commander needs Fleet Captain directive.",
            "latest": b,
            "previous": a,
            "captain_action": "DIRECTIVE_TO_COMMANDER",
            "commander_directive": "RESUME/REVISE Actor Enhancement Bot: unsparse remaining Forge repos, finish live package installs (ffmpeg-python/moviepy), complete missing actor skeletons (loom/forge/commander), regenerate SVD QUALITY.json, publish ACTOR-ENHANCEMENT-REPORT — Archivist must compact logs to save tokens.",
        }
pathlib.Path(out_path).write_text(json.dumps(doc, indent=2)+"\n")
print(doc["verdict"])
print(doc.get("captain_action"))
PY
}

archivist_efficiency() {
  # Archivist assists Enhancement Bot token efficiency — compact noise, keep signal
  bus state archivist assisting-enhance "token usage efficiency for Enhancement Bot"
  python3 - "$ENH_LOG" "$BUS" "$EFFICIENCY" "$FLEET/actors" <<'PY'
import json, pathlib, sys, time, collections, re
log_path, bus_path, out_path, actors_path = sys.argv[1:5]
log_lines = pathlib.Path(log_path).read_text(errors="replace").splitlines() if pathlib.Path(log_path).exists() else []
# dedupe consecutive identical lines
compact=[]
prev=None
dup=0
for ln in log_lines:
    if ln == prev:
        dup += 1
        continue
    if dup:
        compact.append(f"… repeated prior line x{dup}")
        dup=0
    compact.append(ln)
    prev=ln
if dup:
    compact.append(f"… repeated prior line x{dup}")

# keep only high-signal enhance bus msgs last 200 matching enhance
sig=[]
if pathlib.Path(bus_path).exists():
    for line in open(bus_path, errors="replace"):
        if "enhance" in line.lower():
            try:
                m=json.loads(line)
            except Exception:
                continue
            sig.append(f"{m.get('ts')} {m.get('from')}→{m.get('to')} {m.get('kind')}: {str(m.get('body',''))[:100]}")
sig = sig[-40:]

actors = sorted([p.name for p in pathlib.Path(actors_path).iterdir()]) if pathlib.Path(actors_path).is_dir() else []
saved = max(0, len(log_lines) - len(compact))
md = []
md.append(f"# Archivist — Enhancement Bot token efficiency\n")
md.append(f"**When:** {time.strftime('%Y-%m-%dT%H:%M:%S%z')}\n")
md.append("## Goal\nPrevent wasted tokens: compact enhance logs, prefer skeleton diffs over full repo dumps, summarize for Fleet Captain/Commander.\n")
md.append(f"## Log compaction\n- raw lines: {len(log_lines)}\n- compact lines: {len(compact)}\n- removed duplicate noise: {saved}\n")
md.append("## High-signal enhance bus (tail)\n")
md.extend([f"- {s}" for s in sig] or ["- (none)"])
md.append("\n## Actor skeletons present\n")
md.extend([f"- `{a}`" for a in actors] or ["- (none yet)"])
md.append("\n## Efficiency rules for Enhancement Bot\n")
md.append("1. Do not re-pip packages already YES in venv.\n")
md.append("2. Prefer `actor` one-shots over full `all` when only gaps remain.\n")
md.append("3. Unsparse only repos needed for live coding (probe/loom/courier).\n")
md.append("4. Captain/Commander reports use this efficiency brief — not full logs.\n")
pathlib.Path(out_path).write_text("\n".join(md) + "\n")
# write compact log sidecar
pathlib.Path(log_path + ".compact").write_text("\n".join(compact[-200:]) + "\n")
print(out_path)
print("saved_dup_lines", saved)
PY
  bus send archivist enhance report "Token efficiency brief ready — use compact log + efficiency md"
  bus send archivist fleet-captain report "Archivist efficiency assist for Enhancement Bot published"
  bus state archivist researching "maintain enhance token efficiency overlay"
}

publish_overlay() {
  local sample verdict action
  sample=$(measure_enhance)
  verdict_action=$(growth_analysis)
  verdict=$(echo "$verdict_action" | head -1)
  action=$(echo "$verdict_action" | tail -1)

  # superiors-only board (Fleet Captain + Termux Commander + Regulator)
  {
    echo "╔══ REGULATOR SUPERIORS OVERLAY  $(ts) ══╗"
    echo "Audience: Fleet Captain + Termux Commander ONLY"
    echo "Purpose: Enhancement Bot monitoring + directives"
    echo
    echo "── Regulator → Superiors ──"
    for a in regulator fleet-captain termux-commander enhance archivist; do
      f="$STATE/${a}.json"
      if [[ -f "$f" ]]; then
        python3 -c "import json;d=json.loads(open('$f').read().splitlines()[-1]);print(f\"{d.get('actor','?'):<18} {d.get('transit','?'):<16} {str(d.get('detail',''))[:70]}\")"
      fi
    done
    echo
    echo "── Enhancement Bot token/work proxy ──"
    echo "$sample" | python3 -c 'import json,sys;d=json.loads(sys.stdin.read());print(json.dumps(d,indent=2))'
    echo
    echo "── Fleet Captain analysis (from Regulator) ──"
    [[ -f "$ANALYSIS" ]] && cat "$ANALYSIS"
    echo
    echo "── Archivist token efficiency ──"
    [[ -f "$EFFICIENCY" ]] && head -40 "$EFFICIENCY"
    echo "╚════════════════════════════════════════════╝"
  } | tee "$OVER/BOARD.txt" > "$MIRROR/BOARD.txt"

  cp -f "$ANALYSIS" "$MIRROR/CAPTAIN-ANALYSIS.json" 2>/dev/null || true
  cp -f "$EFFICIENCY" "$MIRROR/ARCHIVIST-TOKEN-EFFICIENCY.md" 2>/dev/null || true
  cp -f "$TOKEN_HIST" "$MIRROR/ENHANCE-TOKEN-HISTORY.jsonl" 2>/dev/null || true
  # HTML overlay for MiXplorer ContentViewer
  python3 - "$OVER/BOARD.txt" "$MIRROR/index.html" <<'PY'
import html, pathlib, sys, time
board, out = map(pathlib.Path, sys.argv[1:3])
text = board.read_text(errors="replace") if board.exists() else ""
doc = f"""<!DOCTYPE html><html><head><meta charset=utf-8>
<meta http-equiv=refresh content=30>
<title>Regulator Superiors Overlay</title>
<style>body{{background:#0b0f14;color:#e5eef7;font-family:ui-monospace,monospace;padding:12px}}
h1{{color:#fbbf24}} pre{{white-space:pre-wrap;background:#111827;padding:10px;border-radius:10px}}</style>
</head><body>
<h1>Regulator → Fleet Captain / Termux Commander</h1>
<p>Enhancement Bot monitor · auto-refresh 30s · {html.escape(time.strftime('%Y-%m-%dT%H:%M:%S'))}</p>
<pre>{html.escape(text)}</pre>
</body></html>"""
out.write_text(doc)
PY

  bus state regulator monitoring "superiors overlay published verdict=$verdict"
  bus send regulator fleet-captain report "SUPERIORS OVERLAY: enhance verdict=$verdict action=$action"
  bus send regulator termux-commander report "SUPERIORS OVERLAY: enhance verdict=$verdict"

  # Fleet Captain analyzes and may issue Commander directive
  if [[ "$action" == "DIRECTIVE_TO_COMMANDER" ]]; then
    local directive
    directive=$(python3 -c 'import json;print(json.load(open("'"$ANALYSIS"'")).get("commander_directive") or "")')
    bus state fleet-captain analyzing "Enhancement Bot token growth STALLED — issuing Commander directive"
    bus send fleet-captain termux-commander directive "ENHANCE STALLED: $directive"
    bus state termux-commander receiving-directives "Captain directive: resume/revise Enhancement Bot"
    bus send termux-commander fleet-captain ack "Directive received — will elevate enhance/revise"
    # optional auto-kick if commander tool present and enhance not running
    if ! pgrep -f 'fleet-actor-enhance all' >/dev/null 2>&1; then
      if command -v fleet-termux-commander >/dev/null; then
        nohup fleet-termux-commander enhance >>"$OVER/commander-enhance-kick.log" 2>&1 &
        bus send termux-commander fleet-captain report "Kicked elevated enhance per Captain directive"
      fi
    fi
  else
    bus state fleet-captain reviewing "Enhancement Bot growth=$verdict — no Commander kick needed"
  fi
}

tick() {
  archivist_efficiency
  publish_overlay
}

cmd_start() {
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    if [[ -n "${old:-}" && -d "/proc/$old" ]]; then
      echo "already running pid=$old"
      tick
      return 0
    fi
  fi
  bus send regulator fleet-captain monitor "Regulator superiors overlay ONLINE (Captain+Commander channel)"
  nohup bash -c '
    set +e
    export HOME="'"$HOME"'" PATH="'"$HOME"'/bin:/data/data/com.termux/files/usr/bin:$PATH"
    echo $$ > "'"$PIDFILE"'"
    while true; do
      "'"$HOME"'/bin/fleet-regulator-overlay" tick >>"'"$OVER"'/daemon.log" 2>&1
      sleep '"$INTERVAL"'
    done
  ' >/dev/null 2>&1 &
  sleep 1
  echo "regulator-overlay pid=$(cat "$PIDFILE") interval=${INTERVAL}s"
  tick
  # open MiXplorer on superiors overlay if possible
  if command -v adb >/dev/null; then
    adb shell am start -W -a android.intent.action.VIEW -t text/html \
      -d "file://$MIRROR/index.html" \
      -n com.mixplorer.beta/com.mixplorer.activities.ContentViewerActivity >/dev/null 2>&1 || true
  fi
}

cmd_stop() {
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    [[ -n "${old:-}" && -d "/proc/$old" ]] && kill "$old" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo stopped
  else echo not-running; fi
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  tick) tick ;;
  status)
    echo "mirror=$MIRROR"
    echo "pid=$(cat "$PIDFILE" 2>/dev/null || echo none)"
    [[ -f "$ANALYSIS" ]] && cat "$ANALYSIS"
    head -30 "$OVER/BOARD.txt" 2>/dev/null || true
    ;;
  *)
    cat <<'EOF'
Usage: fleet-regulator-overlay start|stop|tick|status

Regulator superiors overlay (MiXplorer):
  /sdcard/Download/grok-inbox/fleet-monitor/REGULATOR-SUPERIORS/

Fleet Captain analyzes Enhancement Bot token/work growth from Regulator.
If not growing → Captain directives Termux Commander to resume/revise enhance.
Archivist publishes token-efficiency assists to reduce waste.
EOF
    ;;
esac
