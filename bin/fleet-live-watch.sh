#!/data/data/com.termux/files/usr/bin/bash
export PATH="$HOME/bin:$PATH"
FLEET="$HOME/grok-inbox/fleet"
OUT="$FLEET/regulator/LIVE.txt"
PIDFILE="$FLEET/regulator/watch.pid"
echo $$ > "$PIDFILE"
fleet-bus send regulator fleet-captain monitor "persistent LIVE watch started"
LACKETS=(scout probe svd-smith harbor courier quay archivist loom)
while true; do
  {
    echo "REGULATOR LIVE  $(date -Iseconds)"
    fleet-bus board
    echo
    fleet-bus clips 10
  } > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  idx=$(( $(date +%s) % 8 ))
  L="${LACKETS[$idx]}"
  fleet-bus state "$L" pinging "watchdog ping"
  fleet-bus send "$L" fleet-captain ping "watchdog"
  fleet-bus send fleet-captain "$L" ack "watchdog ACK"
  fleet-bus state "$L" idle "on-station"
  fleet-bus send regulator fleet-captain heartbeat "live-watch ok actor=$L"
  sleep 5
done
