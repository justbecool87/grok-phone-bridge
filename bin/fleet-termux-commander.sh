#!/data/data/com.termux/files/usr/bin/bash
# Termux Commander — highest privilege Lackey/Actor deployment & adjustment.
# Receives deploy-requests from Fleet Captain (via traffic monitor / conversation directives).
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
PENDING="$FLEET/elevated/traffic/pending-deployments.json"
ROSTER="$FLEET/roster.json"
DEPLOYED="$FLEET/elevated/traffic/deployed.jsonl"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
LOG="$FLEET/elevated/traffic/commander-deploy.log"
mkdir -p "$FLEET/elevated/traffic" "$FLEET/state" "$MIRROR"

ts() { date -Iseconds; }
log() { printf '%s %s\n' "$(ts)" "$*" | tee -a "$LOG"; }

bus() {
  command -v fleet-bus >/dev/null || return 0
  fleet-bus "$@" >/dev/null 2>&1 || true
}

elev_run() {
  if command -v nethunter >/dev/null 2>&1; then
    nethunter -r "$*" 2>/dev/null | grep -v stty || true
  else
    bash -lc "$*"
  fi
}

ensure_roster() {
  if [[ ! -f "$ROSTER" ]]; then
    cat > "$ROSTER" <<'EOF'
{"directors":[], "lackeys":[], "directive":"FC-001"}
EOF
  fi
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-' | sed 's/^-//;s/-$//'
}

deploy_twin() {
  local for_actor="$1" new_id="$2" label="$3" reason="$4"
  new_id=$(slugify "$new_id")
  [[ -n "$new_id" ]] || return 1

  ensure_roster
  bus state termux-commander deploying-actors "elevated deploy $new_id for $for_actor ($reason)"
  bus send termux-commander fleet-captain report "DEPLOYING $new_id to relieve $for_actor"

  # Highest privilege intent: ensure dirs + roster under elevated shell when possible
  elev_run "mkdir -p /termux-home/grok-inbox/fleet/github-lackey/repos/${new_id} /termux-home/grok-inbox/fleet/state && id -u"

  python3 - "$ROSTER" "$new_id" "$label" "$for_actor" "$reason" <<'PY'
import json, sys, pathlib
roster_path, new_id, label, for_actor, reason = sys.argv[1:6]
p = pathlib.Path(roster_path)
d = json.loads(p.read_text()) if p.exists() else {"directors": [], "lackeys": [], "directive": "FC-001"}
lackeys = d.setdefault("lackeys", [])
if not any(x.get("id") == new_id for x in lackeys):
    lackeys.append({
        "id": new_id,
        "name": label.split("(")[0].strip() if label else new_id,
        "specialty": f"twin of {for_actor}",
        "relieves": for_actor,
        "reason": reason,
        "deployed_by": "termux-commander",
        "privilege": "elevated"
    })
    p.write_text(json.dumps(d, indent=2) + "\n")
    print("roster_added", new_id)
else:
    print("roster_exists", new_id)
PY

  # Register on bus as active assisting twin
  bus state "$new_id" deploying "Termux Commander elevated deploy — twin of $for_actor"
  bus send "$new_id" fleet-captain accept "ONLINE twin of $for_actor — ready for delegated load"
  bus send fleet-captain "$new_id" assign "Absorb overflow from $for_actor; coordinate with specialty lead"
  bus state "$new_id" assisting-primary "relieving $for_actor under Commander privilege"

  # Seed github library folder + why
  mkdir -p "$FLEET/github-lackey/repos/$new_id"
  printf 'Twin of %s deployed by Termux Commander (%s). Reason: %s\n' "$for_actor" "$(ts)" "$reason" \
    > "$FLEET/github-lackey/repos/$new_id/FLEET-WHY.txt"

  printf '%s\n' "{\"ts\":\"$(ts)\",\"new_id\":\"$new_id\",\"for\":\"$for_actor\",\"label\":\"$label\",\"reason\":\"$reason\"}" >> "$DEPLOYED"
  log "DEPLOYED $new_id for $for_actor reason=$reason"
  bus send termux-commander fleet-captain report "DEPLOYED $new_id (twin of $for_actor)"
}

cmd_deploy_pending() {
  if [[ ! -f "$PENDING" ]]; then
    echo "no pending-deployments.json — run fleet-traffic-analyze once first"
    bus state termux-commander standing-by "no pending deploy requests"
    return 0
  fi
  bus state termux-commander deploying-actors "processing Fleet Captain deploy-request (elevated)"
  local n
  n=$(python3 -c 'import json;print(len(json.load(open("'"$PENDING"'")).get("twins",[])))')
  if [[ "$n" -eq 0 ]]; then
    echo "pending twins empty"
    return 0
  fi
  python3 - "$PENDING" <<'PY' >"$FLEET/elevated/traffic/deploy-plan.txt"
import json,sys
d=json.load(open(sys.argv[1]))
for t in d.get("twins",[]):
    print(f"{t['for']}\t{t['new_id']}\t{t.get('label',t['new_id'])}\t{t.get('reason','overburdened')}")
PY
  while IFS=$'\t' read -r for_actor new_id label reason; do
    [[ -z "${for_actor:-}" ]] && continue
    deploy_twin "$for_actor" "$new_id" "$label" "$reason"
  done < "$FLEET/elevated/traffic/deploy-plan.txt"

  # Clear pending after deploy (archive)
  mv -f "$PENDING" "$FLEET/elevated/traffic/pending-deployments.done.$(date +%Y%m%d%H%M%S).json"
  bus state termux-commander adjusting "twins deployed; adjusting fleet under project directives"
  bus send termux-commander fleet-captain report "Deploy batch complete — Fleet Captain may rebalance load"
  cp -f "$ROSTER" "$MIRROR/ROSTER.json" 2>/dev/null || true
  cp -f "$HOME/grok-phone-bridge/PROJECT-DIRECTIVES.md" "$MIRROR/PROJECT-DIRECTIVES.md" 2>/dev/null || true
  echo "deploy complete; roster=$ROSTER"
  command -v fleet-bus >/dev/null && fleet-bus board || true
}

cmd_status() {
  echo "commander=termux-commander privilege=highest"
  echo "pending=$PENDING"
  [[ -f "$PENDING" ]] && python3 -c 'import json;d=json.load(open("'"$PENDING"'"));print("twins",len(d.get("twins",[])));
[print(" ",t) for t in d.get("twins",[])]' || echo "no pending"
  echo "roster=$ROSTER"
  python3 -c 'import json;d=json.load(open("'"$ROSTER"'"));print("lackeys",len(d.get("lackeys",[])));
[print(" ",x.get("id"),x.get("specialty","")) for x in d.get("lackeys",[])]' 2>/dev/null || true
  elev_run 'id -u; id -un' | head -3
}


cmd_enhance() {
  bus state termux-commander enhancing "elevated Actor Enhancement Bot — revise/upgrade skeletons"
  bus send termux-commander fleet-captain report "Commander elevating actor skeleton upgrades from Forge repos"
  if command -v fleet-actor-enhance >/dev/null; then
    fleet-actor-enhance all
  else
    echo "fleet-actor-enhance missing" >&2
    exit 1
  fi
  bus state termux-commander adjusting "actor frameworks upgraded under Commander privilege"
  bus send termux-commander fleet-captain report "Enhance complete — Captain may issue further agentic effort"
}

cmd_apply_directives() {
  # Hand project directives to Fleet Captain from Termux Commander + conversation file
  local doc="$HOME/grok-phone-bridge/PROJECT-DIRECTIVES.md"
  [[ -f "$doc" ]] || doc="$HOME/PROJECT-DIRECTIVES.md"
  bus send termux-commander fleet-captain directive "PROJECT DIRECTIVES in force — conversation + Commander privilege. See PROJECT-DIRECTIVES.md"
  bus state fleet-captain receiving-directives "standing project orders from Termux Commander + owner conversation"
  bus send fleet-captain termux-commander ack "Project directives accepted — swarm will follow"
  if [[ -f "$doc" ]]; then
    cp -f "$doc" "$MIRROR/PROJECT-DIRECTIVES.md" 2>/dev/null || true
    head -40 "$doc"
  fi
}

case "${1:-}" in
  deploy-pending|deploy) cmd_deploy_pending ;;
  status) cmd_status ;;
  apply-directives) cmd_apply_directives ;;
  enhance|upgrade|revise) cmd_enhance ;;
  *)
    cat <<'EOF'
Usage:
  fleet-termux-commander apply-directives   # push PROJECT-DIRECTIVES to Fleet Captain
  fleet-termux-commander deploy-pending     # elevated deploy of twins from traffic report
  fleet-termux-commander enhance            # elevated Actor Enhancement Bot (Forge→skeletons)
  fleet-termux-commander status

Termux Commander has highest privilege to deploy/adjust Lackeys/Actors.
Fleet Captain requests; Commander executes.
EOF
    ;;
esac
