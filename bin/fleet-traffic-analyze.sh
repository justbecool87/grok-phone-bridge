#!/data/data/com.termux/files/usr/bin/bash
# Every 5 minutes (or on demand): analyze Lackey/actor bus traffic.
# Inform Fleet Captain of overburdened + idle actors.
# Fleet Captain → Termux Commander for new Lackey deployment when overburdened.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
BUS="$FLEET/bus/messages.jsonl"
STATE="$FLEET/state"
OUTDIR="$FLEET/elevated/traffic"
REPORT="$OUTDIR/last-report.json"
TEXT="$OUTDIR/last-report.txt"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
WINDOW_SEC="${FLEET_TRAFFIC_WINDOW_SEC:-300}"  # 5 minutes
mkdir -p "$OUTDIR" "$MIRROR" "$STATE"

ts() { date -Iseconds; }

bus() {
  command -v fleet-bus >/dev/null || return 0
  fleet-bus "$@" >/dev/null 2>&1 || true
}

analyze() {
  python3 - "$BUS" "$STATE" "$REPORT" "$TEXT" "$WINDOW_SEC" <<'PY'
import json, time, pathlib, sys, collections, os

bus_path, state_dir, report_path, text_path, window = sys.argv[1:6]
window = int(window)
now = time.time()
cutoff = now - window

actors = [
    "scout","probe","svd-smith","harbor","courier","quay",
    "archivist","loom","forge"
]
# directors excluded from idle/overburden counts but shown
directors = ["fleet-captain","termux-commander","regulator"]

counts = collections.Counter()
kinds = collections.defaultdict(collections.Counter)
if pathlib.Path(bus_path).exists():
    for line in open(bus_path, errors="replace"):
        line=line.strip()
        if not line:
            continue
        try:
            m=json.loads(line)
        except Exception:
            continue
        # parse ts
        tss=m.get("ts") or ""
        try:
            # 2026-09-27T14:43:37-04:00
            from datetime import datetime
            dt=datetime.fromisoformat(tss)
            epoch=dt.timestamp()
        except Exception:
            continue
        if epoch < cutoff:
            continue
        frm=m.get("from")
        if frm in actors or frm in directors:
            counts[frm]+=1
            kinds[frm][m.get("kind","?") ] += 1

# current transits
transits={}
details={}
for a in actors+directors:
    f=pathlib.Path(state_dir)/f"{a}.json"
    if not f.exists():
        transits[a]="unknown"
        details[a]=""
        continue
    raw=f.read_text().strip().splitlines()
    try:
        d=json.loads(raw[-1])
    except Exception:
        transits[a]="unknown"; details[a]=""; continue
    transits[a]=d.get("transit","unknown")
    details[a]=str(d.get("detail",""))[:120]

# classify
OVERBURDEN_TRANSITS = {
    "installing","deploying","fetching","assisting-forge","researching",
    "mirroring","sampling","verifying","priming","priming-render",
    "coordinating","indexing","hardening","staging-cache","bootstrapping",
    "elevating","protected"
}
IDLE_TRANSITS = {"idle","acknowledged"}
idle_detail_marks = ("on-station",)

overburdened=[]
idle=[]
for a in actors:
    c=counts[a]
    tr=(transits.get(a) or "").lower()
    det=(details.get(a) or "").lower()
    # traffic hot
    hot = c >= 12  # many msgs in 5m window
    busy_transit = any(tr.startswith(x) or x in tr for x in OVERBURDEN_TRANSITS) or "protected p0" in det
    if hot or (busy_transit and c >= 6):
        overburdened.append({
            "actor": a,
            "msgs_5m": c,
            "transit": transits.get(a),
            "detail": details.get(a),
            "reason": "high_traffic" if hot else "busy_transit+traffic",
            "suggested_new_lackey": {
                "scout": "scout-aux (media path auditor)",
                "probe": "probe-aux (metadata sampler)",
                "svd-smith": "svd-smith-aux (diffusion install twin)",
                "harbor": "harbor-aux (mirror/inject twin)",
                "courier": "courier-aux (wheel/fetch twin)",
                "quay": "quay-aux (venv deploy twin)",
                "archivist": "archivist-aux (index twin)",
                "loom": "loom-aux (render twin)",
                "forge": "forge-aux (github clone twin)",
            }.get(a, f"{a}-aux")
        })
    is_idle = tr in IDLE_TRANSITS or any(x in det for x in idle_detail_marks) or tr=="unknown"
    if tr == "pinging" and "mix-mirror" in det:
        is_idle = True
    if is_idle and a not in [o["actor"] for o in overburdened]:
        idle.append({
            "actor": a,
            "msgs_5m": c,
            "transit": transits.get(a),
            "detail": details.get(a),
            "action": "assist_forge_learned_skills"
        })

doc={
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "window_sec": window,
    "message_counts_5m": dict(counts),
    "transits": transits,
    "overburdened": overburdened,
    "idle": idle,
    "fleet_captain_actions": [],
}
actions=doc["fleet_captain_actions"]
if overburdened:
    actions.append({
        "to": "fleet-captain",
        "kind": "overburden_alert",
        "body": f"{len(overburdened)} Lackey(s) overburdened in last {window}s"
    })
    actions.append({
        "to": "termux-commander",
        "via": "fleet-captain",
        "kind": "deploy_request",
        "body": "Deploy new Lackey/Actor twin(s) for: " + ", ".join(
            f"{o['actor']}→{o['suggested_new_lackey']}" for o in overburdened
        )
    })
if idle:
    actions.append({
        "to": "fleet-captain",
        "kind": "idle_alert",
        "body": f"{len(idle)} Lackey(s) idle — reassign to assist Forge with learned skills"
    })
if not overburdened and not idle:
    actions.append({
        "to": "fleet-captain",
        "kind": "traffic_ok",
        "body": "No overburdened or idle Lackeys in window"
    })

pathlib.Path(report_path).write_text(json.dumps(doc, indent=2)+"\n")
lines=["=== FLEET TRAFFIC REPORT %s (window=%ss) ===" % (doc["ts"], window)]
lines.append("counts_5m: " + ", ".join(f"{k}={v}" for k,v in sorted(counts.items()) if k in actors))
lines.append("")
lines.append("OVERBURDENED:")
if not overburdened:
    lines.append("  (none)")
else:
    for o in overburdened:
        lines.append(f"  - {o['actor']}: msgs={o['msgs_5m']} transit={o['transit']} → propose {o['suggested_new_lackey']}")
lines.append("IDLE:")
if not idle:
    lines.append("  (none)")
else:
    for i in idle:
        lines.append(f"  - {i['actor']}: msgs={i['msgs_5m']} transit={i['transit']} → {i['action']}")
lines.append("")
lines.append("ACTIONS FOR FLEET CAPTAIN:")
for a in actions:
    lines.append(f"  - {a['kind']}: {a['body']}")
pathlib.Path(text_path).write_text("\n".join(lines)+"\n")
print(text_path)
print("overburdened", len(overburdened), "idle", len(idle))
PY
}

notify_captain() {
  [[ -f "$REPORT" ]] || return 0
  python3 - "$REPORT" <<'PY' >"$OUTDIR/notify-plan.txt"
import json,sys
d=json.load(open(sys.argv[1]))
for a in d.get("fleet_captain_actions",[]):
    print(a.get("kind"), "|", a.get("body",""))
for o in d.get("overburdened",[]):
    print("DEPLOY", o["actor"], "→", o["suggested_new_lackey"])
for i in d.get("idle",[]):
    print("IDLE", i["actor"], "→", i["action"])
PY

  local ob_n id_n
  ob_n=$(python3 -c 'import json;d=json.load(open("'"$REPORT"'"));print(len(d.get("overburdened",[])))')
  id_n=$(python3 -c 'import json;d=json.load(open("'"$REPORT"'"));print(len(d.get("idle",[])))')

  bus state regulator analyzing "5m traffic scan overburdened=$ob_n idle=$id_n"
  bus send regulator fleet-captain report "TRAFFIC 5m: overburdened=$ob_n idle=$id_n — see elevated/traffic/last-report.txt"

  # Fleet Captain receives analysis
  bus send fleet-captain regulator ack "Traffic analysis received"
  bus state fleet-captain reviewing "Lackey load report overburdened=$ob_n idle=$id_n"

  if [[ "$ob_n" -gt 0 ]]; then
    local deploy_body
    deploy_body=$(python3 -c 'import json;d=json.load(open("'"$REPORT"'"));print("; ".join(f"{o[\"actor\"]}=>{o[\"suggested_new_lackey\"]}" for o in d["overburdened"]))')
    # Fleet Captain duty: send Termux Commander for new Lackey/Actor deployment
    bus send fleet-captain termux-commander deploy-request "OVERBURDENED — deploy new Lackey/Actor twin(s): $deploy_body"
    bus state fleet-captain requesting-deploy "Termux Commander: $deploy_body"
    bus send termux-commander fleet-captain ack "Deploy request accepted — queueing new Lackey/Actor twin(s)"
    bus state termux-commander deploying-actors "new Lackey twins: $deploy_body"
    # Record pending deployments for commander
    python3 - "$REPORT" "$OUTDIR/pending-deployments.json" <<'PY'
import json,sys,time
src, dst = sys.argv[1:3]
d=json.load(open(src))
pending={
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "requested_by": "fleet-captain",
  "executor": "termux-commander",
  "twins": [
    {"for": o["actor"], "new_id": o["suggested_new_lackey"].split()[0], "label": o["suggested_new_lackey"], "reason": o["reason"], "msgs_5m": o["msgs_5m"]}
    for o in d.get("overburdened",[])
  ]
}
json.dump(pending, open(dst,"w"), indent=2)
print(dst)
PY
  fi


  # Termux Commander executes deployments with highest privilege
  if [[ "$ob_n" -gt 0 ]] && command -v fleet-termux-commander >/dev/null; then
    fleet-termux-commander deploy-pending >>"$OUTDIR/commander-auto-deploy.log" 2>&1 || true
  fi

  if [[ "$id_n" -gt 0 ]]; then
    bus send fleet-captain regulator assign "Reassign idle Lackeys to assist Forge using learned skills"
    if command -v fleet-regulator-reassign >/dev/null; then
      fleet-regulator-reassign scan >/dev/null 2>&1 || true
    fi
  fi

  cp -f "$TEXT" "$MIRROR/TRAFFIC-REPORT.txt" 2>/dev/null || true
  cp -f "$REPORT" "$MIRROR/TRAFFIC-REPORT.json" 2>/dev/null || true
  [[ -f "$OUTDIR/pending-deployments.json" ]] && cp -f "$OUTDIR/pending-deployments.json" "$MIRROR/PENDING-DEPLOYMENTS.json" 2>/dev/null || true

  # Optional inject brief to live Grok
  if command -v adb-to-grok >/dev/null; then
    adb-to-grok say "[TRAFFIC 5m] overburdened=$ob_n idle=$id_n — Fleet Captain notified; Termux Commander deploy queue updated if needed." >/dev/null 2>&1 || true
  fi
}

cmd_once() {
  analyze
  notify_captain
  echo "report=$TEXT"
  cat "$TEXT"
}

cmd_daemon() {
  local pidfile="$OUTDIR/traffic-daemon.pid"
  if [[ -f "$pidfile" ]]; then
    old=$(cat "$pidfile" 2>/dev/null || true)
    if [[ -n "${old:-}" && -d "/proc/$old" ]]; then
      echo "already running pid=$old"
      exit 0
    fi
  fi
  nohup bash -c '
    set +e
    export HOME="'"$HOME"'"
    export PATH="'"$HOME"'/bin:/data/data/com.termux/files/usr/bin:$PATH"
    echo $$ > "'"$pidfile"'"
    while true; do
      "'"$HOME"'/bin/fleet-traffic-analyze" once >>"'"$OUTDIR"'/daemon.log" 2>&1
      sleep 300
    done
  ' >/dev/null 2>&1 &
  sleep 1
  echo "traffic-analyze daemon pid=$(cat "$pidfile") interval=300s"
  # run first report immediately
  cmd_once
}

cmd_stop() {
  local pidfile="$OUTDIR/traffic-daemon.pid"
  if [[ -f "$pidfile" ]]; then
    old=$(cat "$pidfile" 2>/dev/null || true)
    [[ -n "${old:-}" && -d "/proc/$old" ]] && kill "$old" 2>/dev/null || true
    rm -f "$pidfile"
    echo stopped
  else
    echo not-running
  fi
}

case "${1:-once}" in
  once) cmd_once ;;
  start|daemon) cmd_daemon ;;
  stop) cmd_stop ;;
  status)
    echo "report=$TEXT"
    [[ -f "$TEXT" ]] && cat "$TEXT" || echo "no report yet"
    pf="$OUTDIR/traffic-daemon.pid"
    echo "daemon_pid=$(cat "$pf" 2>/dev/null || echo none)"
    [[ -f "$pf" && -d "/proc/$(cat "$pf")" ]] && echo daemon=RUNNING || echo daemon=STOPPED
    ;;
  *) echo "Usage: fleet-traffic-analyze once|start|stop|status" >&2; exit 2 ;;
esac
