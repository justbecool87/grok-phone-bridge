#!/data/data/com.termux/files/usr/bin/bash
# Regulator Bot — live transit monitor for all Lackeys
set -euo pipefail
FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
LIVE="$FLEET/live.log"
OUT="$FLEET/regulator/live-board.txt"
mkdir -p "$FLEET/regulator"
export PATH="$HOME/bin:$PATH"

rounds="${1:-8}"
interval="${2:-2}"

fleet-bus send regulator fleet-captain monitor "Regulator Bot online — watching Lackey transits for FC-001"

for ((i=1; i<=rounds; i++)); do
  {
    echo "╔══ REGULATOR LIVE BOARD  $(date -Iseconds)  round $i/$rounds ══╗"
    fleet-bus board
    echo
    echo "── recent bus ──"
    fleet-bus clips 6
    echo "╚══════════════════════════════════════════════════════════╝"
  } | tee "$OUT"
  # Regulator adjustment heartbeat
  fleet-bus send regulator fleet-captain heartbeat "round=$i speed=nominal thoroughness=high"
  sleep "$interval"
done

fleet-bus send regulator fleet-captain monitor "Regulator watch cycle complete"
echo "Regulator board saved: $OUT"
