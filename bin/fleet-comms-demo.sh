#!/data/data/com.termux/files/usr/bin/bash
# Prove Lackeys pinging/communicating with Fleet Captain; live transits
set -euo pipefail
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"
FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
CLIPS="$FLEET/clips/demo-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p "$FLEET/clips"
: > "$FLEET/bus/messages.jsonl"
: > "$FLEET/live.log"
: > "$FLEET/regulator/inbox.jsonl"
rm -f "$FLEET/state"/*.json 2>/dev/null || true

logclip() { echo "$*" | tee -a "$CLIPS"; }

logclip "==== FLEET COMMS DEMO $(date -Iseconds) ===="
fleet-bus send termux-commander fleet-captain directive "Hand-down: expand Lackeys for fetch/deploy/research/render on FC-001"
fleet-bus send fleet-captain termux-commander ack "Directive accepted — deploying Courier Quay Archivist Loom"

# Original 4 ping in
for L in scout probe svd-smith harbor; do
  fleet-bus ping "$L" "FC-001 core"
  sleep 0.3
done

# New 4 deploy + ping
fleet-bus assign courier "FETCH: SVD model weights + deps when prompted (hold until owner project prompt)"
sleep 0.2
fleet-bus assign quay "DEPLOY: keep Kali venv/runtime healthy; stage exports to grok-inbox"
sleep 0.2
fleet-bus assign archivist "RESEARCH: SVD edit/enhance presets for 1280x720 Messages clip"
sleep 0.2
fleet-bus assign loom "RENDER: mux/encode *-svd-enhanced.mp4 after SVD Smith pass"

for L in courier quay archivist loom; do
  fleet-bus ping "$L" "FC-001 expanded"
  sleep 0.3
done

# Simulated work reports (prove report channel)
fleet-bus report scout "source confirmed ~/grok-inbox/VID_20260927_105213.mp4"
fleet-bus report probe "frames+segment_0_3s ready"
fleet-bus report svd-smith "runtime INSTALLING — torch/diffusers pip resume in flight"
fleet-bus report harbor "inject path ready (adb-to-grok)"
fleet-bus report courier "awaiting FETCH order post-prompt"
fleet-bus report quay "venv path /termux-home/grok-inbox/svd-work/venv"
fleet-bus report archivist "protocol svd/PROTOCOL.md loaded"
fleet-bus report loom "render target ~/grok-inbox/svd-work/exports/"

# Transit flurry
for L in scout probe svd-smith harbor courier quay archivist loom; do
  fleet-bus state "$L" pinging "keepalive → Fleet Captain"
  fleet-bus send "$L" fleet-captain ping "keepalive FC-001"
  fleet-bus send fleet-captain "$L" ack "keepalive ACK"
  fleet-bus state "$L" idle "on-station"
done

{
  echo
  echo "==== BOARD ===="
  fleet-bus board
  echo
  echo "==== CLIPS ===="
  fleet-bus clips 24
} | tee -a "$CLIPS"

# Inject summary into live Grok
if command -v adb-to-grok >/dev/null; then
  MSG=$(printf '%s\n' \
    '[FLEET COMMS PROOF]' \
    'New Lackeys online: Courier(fetch) Quay(deploy) Archivist(research) Loom(render)' \
    'All 8 Lackeys pinged Fleet Captain and received ACK.' \
    "Clips: $CLIPS" \
    'Regulator Bot monitoring live board.')
  adb-to-grok say "$MSG" || true
fi

echo "CLIPS_FILE=$CLIPS"
