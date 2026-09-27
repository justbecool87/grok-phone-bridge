#!/data/data/com.termux/files/usr/bin/bash
# REST + REASSIGNMENT proposals from Monitor + Regulator → Fleet Captain approval.
# Optional: research Lackey briefs approve/disapprove rationale before Captain decides.
# After APPROVE, Fleet Captain issues agentic effort (execute rest or reassignment).
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
DIR="$FLEET/elevated/rest"
PENDING="$DIR/pending-proposals.json"
HISTORY="$DIR/history.jsonl"
RESEARCH="$DIR/research"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
STATE="$FLEET/state"
BUS="$FLEET/bus/messages.jsonl"
ROSTER="$FLEET/roster.json"
# Static parameters (tunable)
WINDOW_SEC="${FLEET_REST_WINDOW_SEC:-300}"
OVERBURDEN_MSGS="${FLEET_OVERBURDEN_MSGS:-12}"
IDLE_MSGS_MAX="${FLEET_IDLE_MSGS_MAX:-2}"
REST_MIN_SEC="${FLEET_REST_MIN_SEC:-300}"   # default 5 minutes rest
RESEARCHER="${FLEET_RESEARCH_ACTOR:-archivist-aux}"  # or archivist / counsel

mkdir -p "$DIR" "$RESEARCH" "$MIRROR" "$STATE"

ts() { date -Iseconds; }
bus() { command -v fleet-bus >/dev/null && fleet-bus "$@" >/dev/null 2>&1 || true; }

ensure_researcher() {
  # Ensure research actor exists on roster (Termux Commander privilege path optional)
  python3 - "$ROSTER" "$RESEARCHER" <<'PY'
import json, pathlib, sys
path, rid = sys.argv[1:3]
p = pathlib.Path(path)
d = json.loads(p.read_text()) if p.exists() else {"directors": [], "lackeys": [], "directive": "FC-001"}
lackeys = d.setdefault("lackeys", [])
if not any(x.get("id") == rid for x in lackeys):
    lackeys.append({
        "id": rid,
        "name": rid,
        "specialty": "approve/disapprove research briefs for Fleet Captain",
        "deployed_by": "termux-commander",
        "privilege": "elevated"
    })
    p.write_text(json.dumps(d, indent=2) + "\n")
    print("added", rid)
else:
    print("exists", rid)
PY
}

propose() {
  # Monitor + Regulator joint recommendation engine
  ensure_researcher
  bus state regulator calibrating "REST/REASSIGN static params window=${WINDOW_SEC}s overburden>=${OVERBURDEN_MSGS}"
  bus send regulator fleet-captain monitor "Evaluating REST/REASSIGN benefit for Lackeys"

  python3 - "$BUS" "$STATE" "$PENDING" "$WINDOW_SEC" "$OVERBURDEN_MSGS" "$IDLE_MSGS_MAX" "$REST_MIN_SEC" "$RESEARCHER" <<'PY'
import json, time, pathlib, collections, sys
from datetime import datetime

bus_path, state_dir, pending_path, window, ob_msgs, idle_max, rest_sec, researcher = sys.argv[1:9]
window, ob_msgs, idle_max, rest_sec = map(int, (window, ob_msgs, idle_max, rest_sec))
now = time.time()
cutoff = now - window
actors = [
    "scout","probe","svd-smith","harbor","courier","quay","archivist","loom","forge",
    "scout-aux","probe-aux","harbor-aux","quay-aux","archivist-aux","loom-aux","forge-aux"
]
# strip unknown researcher from target list for proposals about themselves optionally
counts = collections.Counter()
if pathlib.Path(bus_path).exists():
    for line in open(bus_path, errors="replace"):
        line=line.strip()
        if not line: continue
        try: m=json.loads(line)
        except Exception: continue
        try: epoch=datetime.fromisoformat(m.get("ts","")).timestamp()
        except Exception: continue
        if epoch < cutoff: continue
        frm=m.get("from")
        if frm in actors: counts[frm]+=1

transits, details = {}, {}
for a in actors:
    f=pathlib.Path(state_dir)/f"{a}.json"
    if not f.exists():
        transits[a]="unknown"; details[a]=""; continue
    try:
        d=json.loads(f.read_text().strip().splitlines()[-1])
    except Exception:
        transits[a]="unknown"; details[a]=""; continue
    transits[a]=d.get("transit","unknown")
    details[a]=str(d.get("detail",""))

BUSY = {"installing","deploying","fetching","assisting-forge","researching","mirroring",
        "sampling","verifying","priming","priming-render","coordinating","indexing",
        "hardening","staging-cache","bootstrapping","assisting-primary","elevating"}
proposals=[]

for a in actors:
    c=counts[a]
    tr=(transits.get(a) or "").lower()
    det=(details.get(a) or "").lower()
    busy = any(x in tr for x in BUSY) or "protected p0" in det
    idle = tr in {"idle","acknowledged","resting","unknown"} or "on-station" in det

    # REST: overburdened / sustained busy with high traffic → benefit from rest
    if busy and c >= ob_msgs:
        proposals.append({
            "id": f"rest-{a}-{int(now)}",
            "action": "REST",
            "actor": a,
            "benefit": "reduce thrash/overburden; restore quality before next agentic push",
            "msgs_window": c,
            "transit": transits.get(a),
            "detail": details.get(a),
            "params": {"rest_sec": rest_sec, "window_sec": window},
            "status": "PENDING_CAPTAIN",
            "recommended_by": ["monitor","regulator"],
            "researcher": researcher,
            "research_status": "NEEDED",
            "captain_decision": None,
            "research_verdict": None,
            "research_why": None,
        })
    # REASSIGN: idle (or resting finished) with spare capacity → benefit from reassignment
    elif idle and c <= idle_max:
        # Prefer Forge assist unless actor is forge itself → help P0/P1 support
        target = "forge" if a != "forge" and not a.startswith("forge") else "svd-smith"
        if a.startswith("forge"):
            target = "courier"  # help fetch/weights
        proposals.append({
            "id": f"reassign-{a}-{int(now)}",
            "action": "REASSIGN",
            "actor": a,
            "to": target,
            "benefit": f"idle capacity → assist {target} with learned skills",
            "msgs_window": c,
            "transit": transits.get(a),
            "detail": details.get(a),
            "params": {"window_sec": window},
            "status": "PENDING_CAPTAIN",
            "recommended_by": ["monitor","regulator"],
            "researcher": researcher,
            "research_status": "NEEDED",
            "captain_decision": None,
            "research_verdict": None,
            "research_why": None,
        })

doc={
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "static_params": {
        "window_sec": window,
        "overburden_msgs": ob_msgs,
        "idle_msgs_max": idle_max,
        "rest_min_sec": rest_sec,
        "researcher": researcher,
        "policy": "Monitor+Regulator may recommend REST or REASSIGN when beneficial; Fleet Captain approves/disapproves (optionally after research brief); then Captain issues agentic effort"
    },
    "proposals": proposals,
}
pathlib.Path(pending_path).write_text(json.dumps(doc, indent=2)+"\n")
print(len(proposals))
PY

  local n
  n=$(python3 -c 'import json;print(len(json.load(open("'"$PENDING"'")).get("proposals",[])))')
  bus send regulator fleet-captain report "REST/REASSIGN proposals=$n sent to Monitor for Fleet Captain"
  # "monitor bot" channel = elevated/rest + MiXplorer mirror + bus to fleet-captain
  bus send monitor fleet-captain report "MONITOR BOT: $n REST/REASSIGN proposals awaiting Captain approve/disapprove or research"
  bus state fleet-captain reviewing "REST/REASSIGN proposals=$n — approve|disapprove|research"
  cp -f "$PENDING" "$MIRROR/REST-REASSIGN-PENDING.json" 2>/dev/null || true
  python3 - "$PENDING" <<'PY' >"$DIR/pending-summary.txt"
import json,sys
d=json.load(open(sys.argv[1]))
print(f"ts={d['ts']} proposals={len(d['proposals'])}")
print("params=", d.get("static_params"))
for p in d["proposals"]:
    extra = f" → {p.get('to')}" if p['action']=='REASSIGN' else f" rest_sec={p['params'].get('rest_sec')}"
    print(f"- {p['id']}: {p['action']} {p['actor']}{extra} | {p['benefit']} | msgs={p['msgs_window']} transit={p['transit']}")
PY
  cp -f "$DIR/pending-summary.txt" "$MIRROR/REST-REASSIGN-PENDING.txt" 2>/dev/null || true
  echo "proposals=$n"
  cat "$DIR/pending-summary.txt"
}

research_one() {
  local pid="${1:-}"
  [[ -f "$PENDING" ]] || { echo "no pending"; exit 1; }
  ensure_researcher
  python3 - "$PENDING" "$RESEARCH" "$RESEARCHER" "$pid" <<'PY'
import json, pathlib, sys, time
pending_path, research_dir, researcher, want = sys.argv[1:5]
d=json.load(open(pending_path))
props=d.get("proposals",[])
targets=[p for p in props if (not want or p["id"]==want) and p.get("status")=="PENDING_CAPTAIN"]
if not targets:
    print("nothing_to_research")
    raise SystemExit(0)
for p in targets:
    # Heuristic research brief (Lackey research role)
    action=p["action"]; actor=p["actor"]; msgs=p.get("msgs_window",0)
    tr=str(p.get("transit",""))
    reasons_for=[]
    reasons_against=[]
    if action=="REST":
        if msgs >= 12: reasons_for.append(f"high bus traffic ({msgs} msgs in window)")
        if any(x in tr for x in ("installing","deploying","fetching","mirroring","assisting")):
            reasons_for.append(f"sustained busy transit={tr}")
        reasons_for.append("rest can improve later agentic quality")
        if actor in ("svd-smith","courier","quay") and "install" in tr:
            reasons_against.append("P0 pip/diffusers critical path — rest may delay install")
        if actor=="forge" and "fetch" in tr:
            reasons_against.append("GitHub pull mid-flight — rest may stall lean pack")
        verdict="APPROVE" if len(reasons_for) > len(reasons_against) else "DISAPPROVE"
        if actor in ("svd-smith","quay","courier") and msgs < 20:
            # protect P0 lightly
            verdict="DISAPPROVE"
            reasons_against.append("static policy: protect P0 cast unless extreme overburden (msgs>=20)")
            if msgs >= 20:
                verdict="APPROVE"
                reasons_for.append("extreme overburden overrides P0 protect")
    else:  # REASSIGN
        reasons_for.append(f"idle/low traffic ({msgs}) — spare capacity")
        reasons_for.append(f"reassign to {p.get('to')} uses learned skills")
        if tr not in ("idle","acknowledged","resting","unknown") and "on-station" not in str(p.get("detail","")).lower():
            reasons_against.append(f"transit={tr} may not be truly idle")
        verdict="APPROVE" if len(reasons_for) >= len(reasons_against) else "DISAPPROVE"

    why = {
        "for": reasons_for,
        "against": reasons_against,
        "summary": f"{researcher} recommends {verdict} on {action} for {actor}"
    }
    p["research_status"]="DONE"
    p["research_verdict"]=verdict
    p["research_why"]=why
    p["status"]="RESEARCHED_AWAITING_CAPTAIN"
    out=pathlib.Path(research_dir)/f"{p['id']}.json"
    out.write_text(json.dumps({"proposal": p, "researcher": researcher, "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z")}, indent=2)+"\n")
    print(p["id"], verdict)
json.dump(d, open(pending_path,"w"), indent=2)
print("updated", pending_path)
PY

  bus state "$RESEARCHER" researching "REST/REASSIGN approve-disapprove briefs for Fleet Captain"
  bus send "$RESEARCHER" fleet-captain report "Research briefs ready — Captain may approve/disapprove with rationale on file"
  bus state fleet-captain reviewing "research briefs available for REST/REASSIGN proposals"
  cp -f "$PENDING" "$MIRROR/REST-REASSIGN-PENDING.json" 2>/dev/null || true
  # summary
  python3 - "$PENDING" <<'PY' | tee "$DIR/research-summary.txt"
import json,sys
d=json.load(open(sys.argv[1]))
for p in d.get("proposals",[]):
    if p.get("research_status")!="DONE":
        continue
    print(f"{p['id']}: research={p.get('research_verdict')} | {p.get('research_why',{}).get('summary')}")
    print("  for:", "; ".join(p.get("research_why",{}).get("for",[])))
    print("  against:", "; ".join(p.get("research_why",{}).get("against",[]) ) or "(none)")
PY
  cp -f "$DIR/research-summary.txt" "$MIRROR/REST-REASSIGN-RESEARCH.txt" 2>/dev/null || true
}

decide() {
  local decision="$1" pid="${2:-}"  # approve|disapprove [proposal-id|all]
  [[ -f "$PENDING" ]] || { echo "no pending"; exit 1; }
  python3 - "$PENDING" "$HISTORY" "$decision" "$pid" <<'PY'
import json, sys, time, pathlib
pending_path, history_path, decision, want = sys.argv[1:5]
decision=decision.upper()
assert decision in ("APPROVE","DISAPPROVE")
d=json.load(open(pending_path))
changed=0
for p in d.get("proposals",[]):
    if want not in ("", "all") and p["id"] != want:
        continue
    if p.get("status") not in ("PENDING_CAPTAIN","RESEARCHED_AWAITING_CAPTAIN"):
        continue
    p["captain_decision"]=decision
    p["captain_ts"]=time.strftime("%Y-%m-%dT%H:%M:%S%z")
    p["status"]="APPROVED" if decision=="APPROVE" else "DISAPPROVED"
    pathlib.Path(history_path).parent.mkdir(parents=True, exist_ok=True)
    with open(history_path,"a") as h:
        h.write(json.dumps(p)+"\n")
    changed += 1
    print(p["id"], decision)
open(pending_path,"w").write(json.dumps(d, indent=2)+"\n")
print("changed", changed)
PY
  bus state fleet-captain deciding "Captain $decision on REST/REASSIGN ($pid)"
  bus send fleet-captain regulator report "Captain decision=$decision proposal=${pid:-all}"
  if [[ "$decision" == "APPROVE" ]]; then
    execute_approved
  else
    bus send fleet-captain monitor report "DISAPPROVED — no agentic REST/REASSIGN effort issued"
  fi
  cp -f "$PENDING" "$MIRROR/REST-REASSIGN-PENDING.json" 2>/dev/null || true
}

execute_approved() {
  # Fleet Captain issues agentic effort for APPROVED proposals
  [[ -f "$PENDING" ]] || return 0
  python3 - "$PENDING" <<'PY' >"$DIR/execute-plan.txt"
import json,sys
d=json.load(open(sys.argv[1]))
for p in d.get("proposals",[]):
    if p.get("status")!="APPROVED":
        continue
    if p["action"]=="REST":
        print(f"REST\t{p['actor']}\t{p['params'].get('rest_sec',300)}\t{p['id']}")
    else:
        print(f"REASSIGN\t{p['actor']}\t{p.get('to','forge')}\t{p['id']}")
PY
  if [[ ! -s "$DIR/execute-plan.txt" ]]; then
    echo "no approved proposals to execute"
    return 0
  fi
  bus send fleet-captain termux-commander report "Issuing agentic REST/REASSIGN effort for approved proposals"
  while IFS=$'\t' read -r action actor arg pid; do
    [[ -z "${action:-}" ]] && continue
    if [[ "$action" == "REST" ]]; then
      bus state "$actor" resting "Captain-approved REST ${arg}s — Monitor/Regulator benefit"
      bus send "$actor" fleet-captain report "RESTING per Captain approval ($pid)"
      bus send fleet-captain "$actor" ack "Rest granted — resume after ${arg}s or next assignment"
      # schedule wake mark file
      mkdir -p "$DIR/resting"
      echo "{\"actor\":\"$actor\",\"until_epoch\":$(( $(date +%s) + arg )),\"proposal\":\"$pid\"}" > "$DIR/resting/${actor}.json"
      log_exec "REST $actor ${arg}s"
    else
      # REASSIGN agentic effort
      case "$arg" in
        forge)
          if command -v fleet-regulator-reassign >/dev/null; then
            fleet-regulator-reassign help "$actor" >/dev/null 2>&1 || true
          fi
          bus state "$actor" assisting-forge "Captain-approved REASSIGN → forge ($pid)"
          ;;
        *)
          bus state "$actor" assisting-primary "Captain-approved REASSIGN → $arg ($pid)"
          bus send "$actor" "$arg" report "Assisting $arg under Captain agentic effort"
          ;;
      esac
      bus send fleet-captain "$actor" assign "REASSIGN approved — work with $arg"
      log_exec "REASSIGN $actor → $arg"
    fi
    # mark executed
    python3 - "$PENDING" "$pid" <<'PY'
import json,sys
path, pid=sys.argv[1:3]
d=json.load(open(path))
for p in d.get("proposals",[]):
    if p.get("id")==pid:
        p["status"]="EXECUTED"
json.dump(d, open(path,"w"), indent=2)
PY
  done < "$DIR/execute-plan.txt"
  bus state fleet-captain commanding "agentic REST/REASSIGN effort issued"
  cp -f "$PENDING" "$MIRROR/REST-REASSIGN-PENDING.json" 2>/dev/null || true
  fleet-bus board 2>/dev/null | head -40 || true
}

log_exec() { printf '%s %s\n' "$(ts)" "$*" >> "$DIR/execute.log"; }

status() {
  echo "pending=$PENDING"
  [[ -f "$PENDING" ]] && python3 -c 'import json;d=json.load(open("'"$PENDING"'"));
print("proposals",len(d.get("proposals",[])));
print("params",d.get("static_params"));
[print(p.get("status"), p.get("action"), p.get("actor"), p.get("research_verdict"), p.get("captain_decision")) for p in d.get("proposals",[])]'
  echo "mirror=$MIRROR/REST-REASSIGN-PENDING.txt"
  ls "$DIR/resting" 2>/dev/null | head || true
}

case "${1:-}" in
  propose|recommend) propose ;;
  research) research_one "${2:-}" ;;
  approve) decide APPROVE "${2:-all}" ;;
  disapprove) decide DISAPPROVE "${2:-all}" ;;
  execute) execute_approved ;;
  status) status ;;
  *)
    cat <<'EOF'
Usage:
  fleet-rest-reassign propose              # Monitor+Regulator recommendations
  fleet-rest-reassign research [id]        # research Lackey briefs approve/disapprove + why
  fleet-rest-reassign approve [id|all]     # Fleet Captain APPROVE → issues agentic effort
  fleet-rest-reassign disapprove [id|all]  # Fleet Captain DISAPPROVE
  fleet-rest-reassign status

Static params (env): FLEET_REST_WINDOW_SEC FLEET_OVERBURDEN_MSGS FLEET_IDLE_MSGS_MAX
                     FLEET_REST_MIN_SEC FLEET_RESEARCH_ACTOR
EOF
    ;;
esac
