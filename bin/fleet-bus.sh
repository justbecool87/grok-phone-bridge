#!/data/data/com.termux/files/usr/bin/bash
# Fleet message bus — Lackeys ↔ Fleet Captain (+ Regulator mirror)
set -euo pipefail
FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
BUS="$FLEET/bus"
LIVE="$FLEET/live.log"
STATE="$FLEET/state"
mkdir -p "$BUS" "$STATE" "$FLEET/clips" "$FLEET/regulator"

ts() { date -Iseconds; }
uuid() { date +%s%N; }

cmd="${1:-help}"
shift || true

case "$cmd" in
  send)
    # fleet-bus send <from> <to> <kind> <body...>
    # Does NOT overwrite duty transit for Lackeys — use `state` for that.
    from="$1"; to="$2"; kind="$3"; shift 3
    body="$*"
    id="$(uuid)"
    body_json=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    line=$(printf '{"ts":"%s","id":"%s","from":"%s","to":"%s","kind":"%s","body":%s}' \
      "$(ts)" "$id" "$from" "$to" "$kind" "$body_json")
    printf '%s\n' "$line" >> "$BUS/messages.jsonl"
    printf '%s\n' "$line" >> "$LIVE"
    printf '%s\n' "$line" >> "$FLEET/regulator/inbox.jsonl"
    # Directors may show last speech act; Lackeys keep prior duty transit
    case "$from" in
      fleet-captain|termux-commander|regulator)
        printf '{"ts":"%s","actor":"%s","transit":"%s","peer":"%s","detail":%s}\n' \
          "$(ts)" "$from" "$kind" "$to" "$body_json" > "$STATE/${from}.json"
        ;;
    esac
    printf '%s\n' "$line"
    ;;

  state)
    actor="$1"; transit="$2"; shift 2
    detail="${*:-}"
    detail_json=$(printf '%s' "$detail" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
    line=$(printf '{"ts":"%s","actor":"%s","transit":"%s","detail":%s}'       "$(ts)" "$actor" "$transit" "$detail_json")
    printf '%s\n' "$line" > "$STATE/${actor}.json.tmp"
    mv -f "$STATE/${actor}.json.tmp" "$STATE/${actor}.json"
    printf '%s\n' "$line" >> "$LIVE"
    ;;
  ping)
    # fleet-bus ping <lackey> — does not force idle; caller owns duty transit
    lackey="$1"
    assignment="${2:-FC-001 active}"
    "$0" state "$lackey" pinging "ping Fleet Captain"
    "$0" send "$lackey" fleet-captain ping "PING assignment=$assignment"
    "$0" send fleet-captain "$lackey" ack "ACK — continue active duty"
    "$0" state "$lackey" working "assignment=$assignment"
    ;;
  assign)
    lackey="$1"; shift
    task="$*"
    "$0" send fleet-captain "$lackey" assign "$task"
    "$0" state "$lackey" assigned "$task"
    "$0" send "$lackey" fleet-captain accept "ACCEPT: $task"
    "$0" state "$lackey" deploying "starting: $task"
    ;;
  report)
    lackey="$1"; shift
    "$0" send "$lackey" fleet-captain report "$*"
    "$0" state "$lackey" reporting "$*"
    "$0" send fleet-captain "$lackey" ack "REPORT logged"
    ;;
  board)
    echo "=== FLEET LIVE BOARD $(ts) ==="
    printf '%-14s %-14s %s\n' "ACTOR" "TRANSIT" "DETAIL"
    for f in "$STATE"/*.json; do
      [ -f "$f" ] || continue
      python3 - "$f" <<'PY'
import json,sys
raw=open(sys.argv[1]).read().strip().splitlines()
d=json.loads(raw[-1])
print(f"{d.get('actor','?'):<14} {d.get('transit','?'):<14} {d.get('detail','')[:80]}")
PY
    done
    ;;
  clips)
    n="${1:-12}"
    echo "=== COMM CLIPS (last $n) ==="
    python3 - "$n" "$BUS/messages.jsonl" <<'PYC'
import sys, json
n = int(sys.argv[1])
path = sys.argv[2]
try:
    lines = open(path).read().splitlines()
except FileNotFoundError:
    lines = []
for line in lines[-n:]:
    line = line.strip()
    if not line:
        continue
    m = json.loads(line)
    print(f"[{m['ts']}] {m['from']} → {m['to']} | {m['kind']}: {m['body'][:120]}")
PYC
    ;;

  help|*)
    cat <<'H'
Usage:
  fleet-bus send <from> <to> <kind> <body...>
  fleet-bus state <actor> <transit> [detail]
  fleet-bus ping <lackey> [assignment]
  fleet-bus assign <lackey> <task...>
  fleet-bus report <lackey> <status...>
  fleet-bus board
  fleet-bus clips [n]
H
    ;;
esac
