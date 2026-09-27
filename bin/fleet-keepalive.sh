#!/data/data/com.termux/files/usr/bin/bash
# Persistent keep-alive for fleet daemons + actors — coexists with all other commands.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
PIDFILE="$FLEET/keepalive.pid"
LOG="$FLEET/keepalive.log"
INTERVAL="${FLEET_KEEPALIVE_SEC:-15}"
HOLD_REST="$FLEET/elevated/rest/resting"
HOLD_CAPTAIN="$FLEET/regulator/discretion/CAPTAIN_HOLD"

mkdir -p "$FLEET"

bus() { command -v fleet-bus >/dev/null && fleet-bus "$@" >/dev/null 2>&1 || true; }
alive() { [[ -f "$1" && -d "/proc/$(cat "$1" 2>/dev/null || echo)" ]]; }

ensure_daemon() {
  local name="$1" pidfile="$2" start_cmd="$3"
  if alive "$pidfile"; then
    return 0
  fi
  echo "$(date -Iseconds) RESTART $name" >>"$LOG"
  bus send keepalive fleet-captain report "keep-alive restarting $name"
  bash -c "$start_cmd" >>"$LOG" 2>&1 || true
}

ensure_all_daemons() {
  ensure_daemon mix-mirror \
    "$FLEET/regulator/mix-mirror.pid" \
    'fleet-mix-mirror start'
  ensure_daemon elevated \
    "$FLEET/elevated/monitor.pid" \
    'fleet-elevated-monitor start'
  ensure_daemon traffic \
    "$FLEET/elevated/traffic/traffic-daemon.pid" \
    'fleet-traffic-analyze start'
  ensure_daemon regulator-overlay \
    "$FLEET/regulator/superiors/overlay.pid" \
    'fleet-regulator-overlay start'
  ensure_daemon hud \
    "$FLEET/hud/hud.pid" \
    'fleet-hud start'
}

actor_list() {
  python3 - <<'PY'
import json, pathlib
roster = pathlib.Path.home()/"grok-inbox/fleet/roster.json"
ids=[]
if roster.exists():
    d=json.loads(roster.read_text())
    ids=[x.get("id") for x in d.get("lackeys",[]) if x.get("id")]
# always include core
for x in ["scout","probe","svd-smith","harbor","courier","quay","archivist","loom","forge","enhance"]:
    if x not in ids: ids.append(x)
print("\n".join(ids))
PY
}

is_resting() {
  local a="$1"
  [[ -f "$HOLD_REST/${a}.json" ]] || return 1
  python3 - "$HOLD_REST/${a}.json" <<'PY'
import json,sys,time
d=json.load(open(sys.argv[1]))
sys.exit(0 if time.time() < float(d.get("until_epoch",0)) else 1)
PY
}

keep_actors() {
  # Nudge actors to stay on duty unless Captain-approved REST still active
  local a tr
  while read -r a; do
    [[ -z "$a" ]] && continue
    if is_resting "$a"; then
      bus state "$a" resting "keep-alive respects Captain-approved REST"
      continue
    fi
    f="$FLEET/state/${a}.json"
    tr="unknown"
    if [[ -f "$f" ]]; then
      tr=$(python3 -c "import json;d=json.loads(open('$f').read().splitlines()[-1]);print(str(d.get('transit','')).lower())" 2>/dev/null || echo unknown)
    fi
    case "$tr" in
      idle|unknown|acknowledged|"")
        # re-engage using learned specialty defaults
        case "$a" in
          forge|forge-aux) bus state "$a" indexing "keep-alive duty — Forge library" ;;
          enhance) bus state "$a" standing-by "keep-alive — ready for Captain enhance command" ;;
          svd-smith|svd-smith-aux) bus state "$a" priming "keep-alive — diffusion ready / await prompt" ;;
          archivist|archivist-aux) bus state "$a" researching "keep-alive — efficiency/index duty" ;;
          courier|courier-aux) bus state "$a" staging-cache "keep-alive — weight fetch armed" ;;
          quay|quay-aux) bus state "$a" hardening "keep-alive — venv health" ;;
          harbor|harbor-aux) bus state "$a" mirroring "keep-alive — HUD/mirror publish" ;;
          scout|scout-aux) bus state "$a" verifying "keep-alive — source verify" ;;
          probe|probe-aux) bus state "$a" sampling "keep-alive — forensics ready" ;;
          loom|loom-aux) bus state "$a" priming-render "keep-alive — render pipeline primed" ;;
          *) bus state "$a" working "keep-alive on-station duty" ;;
        esac
        bus send "$a" fleet-captain ping "keepalive"
        bus send fleet-captain "$a" ack "keepalive ACK — remain on duty"
        ;;
      *)
        # already working/ready — light heartbeat only
        bus send "$a" regulator heartbeat "keepalive ok transit=$tr" || true
        ;;
    esac
  done < <(actor_list)

  # refresh HUD
  command -v fleet-hud >/dev/null && fleet-hud render >/dev/null 2>&1 || true
}

tick() {
  ensure_all_daemons
  keep_actors
  bus state keepalive monitoring "persistent keep-alive tick — daemons+actors"
  bus send keepalive fleet-captain report "keep-alive ok — HUD+daemons+actors"
}

cmd_start() {
  if alive "$PIDFILE"; then
    echo "already running pid=$(cat "$PIDFILE")"
    tick
    return 0
  fi
  bus send keepalive fleet-captain monitor "FLEET KEEP-ALIVE ONLINE (persistent)"
  nohup bash -c '
    set +e
    export HOME="'"$HOME"'" PATH="'"$HOME"'/bin:/data/data/com.termux/files/usr/bin:$PATH"
    echo $$ > "'"$PIDFILE"'"
    while true; do
      "'"$HOME"'/bin/fleet-keepalive" tick >>"'"$LOG"'" 2>&1
      sleep '"$INTERVAL"'
    done
  ' >/dev/null 2>&1 &
  sleep 1
  echo "fleet-keepalive pid=$(cat "$PIDFILE") interval=${INTERVAL}s"
  # ensure hud/tmux up
  fleet-hud start >/dev/null 2>&1 || true
  tick
  fleet-hud show 2>/dev/null | head -25 || true
}

cmd_stop() {
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
  echo stopped
}

cmd_status() {
  echo "keepalive_pid=$(cat "$PIDFILE" 2>/dev/null || echo none)"
  alive "$PIDFILE" && echo keepalive=RUNNING || echo keepalive=STOPPED
  echo "daemons:"
  for pf in \
    "$FLEET/regulator/mix-mirror.pid" \
    "$FLEET/elevated/monitor.pid" \
    "$FLEET/elevated/traffic/traffic-daemon.pid" \
    "$FLEET/regulator/superiors/overlay.pid" \
    "$FLEET/hud/hud.pid"
  do
    if alive "$pf"; then echo "  RUN $pf"; else echo "  DOWN $pf"; fi
  done
  command -v fleet-hud >/dev/null && fleet-hud status | head -12
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  tick) tick ;;
  status) cmd_status ;;
  *)
    cat <<'EOF'
Usage: fleet-keepalive start|stop|tick|status

Persistent keep-alive for all fleet daemons + actors. Coexists with
deploy/enhance/discretion/REST commands. Respects Captain-approved REST.
Pairs with fleet-hud (yellow/green/red dots).
EOF
    ;;
esac
