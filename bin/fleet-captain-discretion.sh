#!/data/data/com.termux/files/usr/bin/bash
# Fleet Captain discretion over Regulator suggestions (Archivist-backed).
# Regulator/monitors under Captain authority may suggest (or rarely safe-auto
# implement) less time-consuming or conflicting paths. Captain almost always decides.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
DIR="$FLEET/regulator/discretion"
PENDING="$DIR/pending-suggestions.json"
HISTORY="$DIR/history.jsonl"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor/REGULATOR-SUPERIORS"
HOLD_FLAG="$DIR/CAPTAIN_HOLD"

mkdir -p "$DIR" "$MIRROR"

bus() { command -v fleet-bus >/dev/null && fleet-bus "$@" >/dev/null 2>&1 || true; }

_publish() {
  cp -f "$PENDING" "$MIRROR/CAPTAIN-DISCRETION-PENDING.json" 2>/dev/null || true
  python3 - "$PENDING" <<'PY' >"$MIRROR/CAPTAIN-DISCRETION.txt"
import json, sys
d = json.load(open(sys.argv[1]))
print("Fleet Captain discretion — Regulator suggestions (Archivist-backed)")
print("policy:", d.get("policy"))
for s in d.get("suggestions", [])[-8:]:
    print(f"- {s['id']} [{s['status']}] {s['title']}")
    print(f"  action={s['alternate_action']} conflict={s.get('conflicts_with_captain_plan')} safe_auto={s.get('safe_auto')} discretion={s.get('captain_discretion')}")
    print(f"  for_alt: {'; '.join(s.get('research', {}).get('for_alternate', [])[:2])}")
    print(f"  for_keep: {'; '.join(s.get('research', {}).get('for_keep_captain_plan', [])[:2])}")
PY
  if [[ -f "$MIRROR/BOARD.txt" ]]; then
    {
      echo
      echo "── Captain discretion (Regulator suggestions) ──"
      cat "$MIRROR/CAPTAIN-DISCRETION.txt"
    } >> "$MIRROR/BOARD.txt"
  fi
}

_implement() {
  local sid="$1" how="${2:-CAPTAIN}"
  local action
  action=$(python3 - "$PENDING" "$sid" "$how" "$HISTORY" <<'PY'
import json, sys, time, pathlib
path, sid, how, hist = sys.argv[1:5]
d = json.load(open(path))
action = ""
for s in d.get("suggestions", []):
    if s["id"] != sid:
        continue
    s["status"] = "IMPLEMENTED_" + how
    s["implemented_ts"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    pathlib.Path(hist).parent.mkdir(parents=True, exist_ok=True)
    with open(hist, "a") as h:
        h.write(json.dumps(s) + "\n")
    action = s.get("alternate_action", "")
    break
json.dump(d, open(path, "w"), indent=2)
print(action)
PY
)

  case "$action" in
    COMMANDER_ENHANCE_GAPS_ONLY)
      bus send fleet-captain termux-commander directive "DISCRETION PATH: enhance gaps only (not full all) — Archivist efficiency"
      bus state termux-commander receiving-directives "gap-only enhance per Captain/safe path"
      if command -v fleet-actor-enhance >/dev/null; then
        nohup bash -c 'fleet-actor-enhance packages; for a in loom forge termux-commander svd-smith; do fleet-actor-enhance actor "$a"; done' \
          >>"$DIR/gap-enhance.log" 2>&1 &
      fi
      ;;
    DEFER_NEW_WORK_UNTIL_ENHANCE_GROWS)
      bus send fleet-captain regulator report "Discretion path: defer new heavy work while enhance growing"
      bus state regulator calibrating "defer heavy agentic pushes — enhance growing"
      ;;
    WAIT_ONE_OVERLAY_TICK)
      bus send fleet-captain regulator report "Discretion path: wait one Regulator overlay tick"
      ;;
    *)
      bus send fleet-captain regulator report "Implemented suggestion action=$action"
      ;;
  esac
}

suggest() {
  bus state regulator suggesting "Archivist-backed alternate path for Fleet Captain discretion"
  bus send regulator archivist assign "Research less time-consuming or conflicting path vs current Captain plan"
  bus state archivist researching "alternate path: time/conflict/token for Regulator suggestion"

  if pgrep -f 'fleet-actor-enhance' >/dev/null 2>&1; then
    export ENH_RUNNING=1
  else
    export ENH_RUNNING=0
  fi

  python3 - "$PENDING" "$FLEET" <<'PY'
import json, time, pathlib, sys, os
pending_path, fleet = sys.argv[1:3]
fleet = pathlib.Path(fleet)
analysis = {}
ap = fleet / "regulator/superiors/captain-analysis.json"
if ap.exists():
    try:
        analysis = json.loads(ap.read_text())
    except Exception:
        analysis = {}

reasons_alt = []
reasons_keep = []
safe_auto = False
alt_action = "CONTINUE_CURRENT"
title = "No strong alternate — keep Captain plan"

verdict = analysis.get("verdict")
if verdict == "STALLED":
    title = "Alternate: Commander elevate enhance (gap-only) instead of full re-run"
    alt_action = "COMMANDER_ENHANCE_GAPS_ONLY"
    reasons_alt += [
        "Enhancement Bot token/work proxy stalled — full re-run wastes tokens",
        "Gap-only enhance is less time-consuming",
        "Archivist efficiency prefers one-shot actor enhances over all",
    ]
    reasons_keep += ["Full enhance may still be needed if skeletons incomplete"]
    safe_auto = False
elif verdict == "GROWING":
    title = "Alternate: let enhance finish; defer new Captain agentic pushes"
    alt_action = "DEFER_NEW_WORK_UNTIL_ENHANCE_GROWS"
    reasons_alt += ["Growth is healthy — interrupting may conflict with live enhance"]
    reasons_keep += ["Captain may still issue prompt/SVD work if P0 clear"]
    safe_auto = False
else:
    reasons_alt.append("Warmup/unknown — suggest brief wait for another Regulator sample")
    alt_action = "WAIT_ONE_OVERLAY_TICK"
    safe_auto = True

p0_busy = False
for actor in ("svd-smith", "quay", "courier"):
    sf = fleet / "state" / f"{actor}.json"
    if not sf.exists():
        continue
    try:
        d = json.loads(sf.read_text().splitlines()[-1])
        tr = str(d.get("transit", ""))
        if any(x in tr for x in ("installing", "deploying", "fetching")):
            p0_busy = True
    except Exception:
        pass
if p0_busy:
    reasons_keep.append("P0 pip/diffusers path active — alternate must not starve P0")
    safe_auto = False

sug = {
    "id": f"sug-{int(time.time())}",
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "from": ["regulator", "monitor"],
    "archivist_permission": True,
    "title": title,
    "alternate_action": alt_action,
    "conflicts_with_captain_plan": alt_action not in ("WAIT_ONE_OVERLAY_TICK", "CONTINUE_CURRENT"),
    "less_time_consuming": alt_action in (
        "COMMANDER_ENHANCE_GAPS_ONLY",
        "WAIT_ONE_OVERLAY_TICK",
        "DEFER_NEW_WORK_UNTIL_ENHANCE_GROWS",
    ),
    "safe_auto": safe_auto,
    "research": {"for_alternate": reasons_alt, "for_keep_captain_plan": reasons_keep},
    "captain_discretion": "REQUIRED" if not safe_auto else "PREFERRED",
    "status": "AWAITING_CAPTAIN",
    "analysis_snapshot": {
        "verdict": analysis.get("verdict"),
        "captain_action": analysis.get("captain_action"),
    },
}
doc = {
    "ts": sug["ts"],
    "policy": "Fleet Captain almost always has discretion over Regulator suggestions",
    "suggestions": [],
}
if pathlib.Path(pending_path).exists():
    try:
        doc = json.loads(pathlib.Path(pending_path).read_text())
    except Exception:
        pass
doc.setdefault("suggestions", []).append(sug)
doc["suggestions"] = doc["suggestions"][-20:]
pathlib.Path(pending_path).write_text(json.dumps(doc, indent=2) + "\n")
print(sug["id"])
print(sug["alternate_action"])
print(sug["captain_discretion"])
print("1" if sug["safe_auto"] else "0")
PY

  local sid action disc safe
  {
    read -r sid
    read -r action
    read -r disc
    read -r safe
  } < <(python3 -c 'import json;d=json.load(open("'"$PENDING"'"));s=d["suggestions"][-1];print(s["id"]);print(s["alternate_action"]);print(s["captain_discretion"]);print("1" if s.get("safe_auto") else "0")')

  bus send archivist regulator report "Research complete for $sid — Captain discretion $disc"
  bus send regulator fleet-captain suggest "ARCHIVIST-BACKED SUGGESTION $sid: $action (discretion=$disc)"
  bus send regulator termux-commander report "Suggestion $sid posted for Captain — do not elevate unless directed"
  bus state fleet-captain reviewing "Regulator suggestion $sid — discretion almost always applies"

  if [[ "$safe" == "1" && ! -f "$HOLD_FLAG" ]]; then
    bus send regulator fleet-captain report "safe_auto implement of $sid — reporting to Captain immediately"
    _implement "$sid" "SAFE_AUTO"
  fi
  _publish
  echo "suggestion=$sid action=$action discretion=$disc safe_auto=$safe"
}

approve() {
  local sid="${1:?id}"
  bus state fleet-captain deciding "APPROVE Regulator suggestion $sid (Captain discretion)"
  bus send fleet-captain regulator ack "Suggestion $sid APPROVED — issue agentic effort"
  _implement "$sid" "CAPTAIN_APPROVED"
  _publish
}

override() {
  local sid="${1:?id}"
  python3 - "$PENDING" "$sid" "$HISTORY" <<'PY'
import json, sys, pathlib
path, sid, hist = sys.argv[1:4]
d = json.load(open(path))
for s in d.get("suggestions", []):
    if s["id"] != sid:
        continue
    s["status"] = "OVERRIDDEN_BY_CAPTAIN"
    s["captain_note"] = "Fleet Captain override — keep original plan"
    pathlib.Path(hist).parent.mkdir(parents=True, exist_ok=True)
    with open(hist, "a") as h:
        h.write(json.dumps(s) + "\n")
json.dump(d, open(path, "w"), indent=2)
print("overridden", sid)
PY
  bus state fleet-captain deciding "OVERRIDE Regulator suggestion $sid — Captain plan stands"
  bus send fleet-captain regulator report "Suggestion $sid overridden — continue Captain delegation"
  bus send fleet-captain termux-commander report "Ignore alternate $sid unless new Captain directive"
  _publish
}

hold() {
  date -Iseconds > "$HOLD_FLAG"
  bus state fleet-captain holding "Captain HOLD on Regulator auto-implement; suggestions still accepted"
  bus send fleet-captain regulator report "HOLD: suggest only — no safe_auto implement"
  echo "hold set: $HOLD_FLAG"
}

release_hold() {
  rm -f "$HOLD_FLAG"
  bus send fleet-captain regulator report "HOLD cleared — safe_auto allowed again when Archivist marks safe"
  echo "hold cleared"
}

status() {
  echo "pending=$PENDING hold=$( [[ -f $HOLD_FLAG ]] && echo YES || echo NO )"
  if [[ -f "$PENDING" ]]; then
    python3 -c 'import json;d=json.load(open("'"$PENDING"'"));print(d.get("policy"));
[print(s["id"], s["status"], s["alternate_action"], "discretion="+s.get("captain_discretion","")) for s in d.get("suggestions",[])[-8:]]'
  fi
  [[ -f "$MIRROR/CAPTAIN-DISCRETION.txt" ]] && cat "$MIRROR/CAPTAIN-DISCRETION.txt"
}

case "${1:-}" in
  suggest) suggest ;;
  approve) approve "${2:?id}" ;;
  override) override "${2:?id}" ;;
  hold) hold ;;
  release-hold) release_hold ;;
  status) status ;;
  *)
    cat <<'EOF'
Usage:
  fleet-captain-discretion suggest
  fleet-captain-discretion approve <id>
  fleet-captain-discretion override <id>
  fleet-captain-discretion hold | release-hold
  fleet-captain-discretion status

Regulator/monitors under Fleet Captain; Archivist may authorize suggest/implement
of less time-consuming or conflicting paths. Captain almost always has discretion.
EOF
    ;;
esac
