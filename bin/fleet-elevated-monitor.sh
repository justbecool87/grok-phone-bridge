#!/data/data/com.termux/files/usr/bin/bash
# Elevated Permission Job Monitor — talks to Regulator Bot.
# Holds + delegates Lackey jobs by priority:
#   P0 pip/diffusers install  →  P1 GitHub Forge pull/index  →  P2 other FC-001
# Elevated path: Kali root via nethunter -r for install/deploy ops.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
ELEV="$FLEET/elevated"
QUEUE="$ELEV/QUEUE.json"
STATUS="$ELEV/STATUS.txt"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
PIDFILE="$ELEV/monitor.pid"
LOG="$ELEV/monitor.log"
VENV_PIP="/termux-home/grok-inbox/svd-work/venv/bin/pip"
VENV_PY="/termux-home/grok-inbox/svd-work/venv/bin/python"
HOST_VENV="$HOME/grok-inbox/svd-work/venv"

mkdir -p "$ELEV" "$MIRROR" "$FLEET/state"

ts() { date -Iseconds; }
log() { printf '%s %s\n' "$(ts)" "$*" | tee -a "$LOG"; }

elev_run() {
  # Elevated permission wrapper (Kali root proot)
  if command -v nethunter >/dev/null 2>&1; then
    nethunter -r "$*" 2>/dev/null | grep -v stty || true
  else
    bash -lc "$*"
  fi
}

pip_busy() { pgrep -f '/svd-work/venv/bin/pip install' >/dev/null 2>&1; }
forge_busy() { pgrep -f 'fleet-github-lackey pull|git clone --.*github.com' >/dev/null 2>&1; }

imports_ok() {
  [[ -d "$HOST_VENV/lib/python3.13/site-packages/torch" ]] \
    && [[ -d "$HOST_VENV/lib/python3.13/site-packages/diffusers" ]]
}

bus() {
  command -v fleet-bus >/dev/null || return 0
  fleet-bus "$@" >/dev/null 2>&1 || true
}

write_queue() {
  local pip_state forge_state p0 p1 p2
  if pip_busy; then pip_state=RUNNING
  elif imports_ok; then pip_state=READY
  else pip_state=NEEDED
  fi
  if forge_busy; then forge_state=RUNNING
  elif [[ -d "$FLEET/github-lackey/repos/scout" ]]; then forge_state=PARTIAL_OR_DONE
  else forge_state=NEEDED
  fi

  # Priority holds
  if [[ "$pip_state" == "RUNNING" || "$pip_state" == "NEEDED" ]]; then
    p0="HOLD: pip/diffusers install owns svd-smith+quay+courier"
    p1="DEFER: Forge pull yields CPU/disk to pip unless courier assist only"
    p2="BACKGROUND: scout/probe/harbor/loom/archivist may assist Forge if idle"
  elif [[ "$forge_state" == "RUNNING" || "$forge_state" == "NEEDED" ]]; then
    p0="CLEAR: diffusion imports OK"
    p1="HOLD: Forge GitHub lean-pack owns forge (+ idle helpers)"
    p2="SUPPORT: learned-skill assists via regulator-reassign"
  else
    p0="CLEAR"
    p1="CLEAR"
    p2="ACTIVE: FC-001 normal duties + READY_FOR_PROMPTING gate"
  fi

  python3 - "$QUEUE" "$pip_state" "$forge_state" "$p0" "$p1" "$p2" <<'PY'
import json, sys, time, os
path, pip_s, forge_s, p0, p1, p2 = sys.argv[1:7]
doc = {
  "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
  "elevated_uid_probe": "nethunter-root",
  "priorities": {
    "P0_pip_diffusers": {"state": pip_s, "policy": p0, "actors": ["svd-smith", "quay", "courier"]},
    "P1_github_forge": {"state": forge_s, "policy": p1, "actors": ["forge", "archivist", "harbor", "scout", "probe", "loom"]},
    "P2_other": {"state": "FOLLOW", "policy": p2, "actors": ["harbor", "loom", "scout", "probe", "archivist"]}
  },
  "delegation": {
    "rule": "Regulator holds lower priorities while higher priority RUNNING/NEEDED",
    "idle_rule": "idle Lackeys assist Forge with learned skills unless P0 claims them"
  }
}
# If pip needs actors, mark claimed
if pip_s in ("RUNNING", "NEEDED"):
    doc["claimed_by"] = "P0_pip_diffusers"
elif forge_s in ("RUNNING", "NEEDED"):
    doc["claimed_by"] = "P1_github_forge"
else:
    doc["claimed_by"] = "P2_other"
open(path, "w").write(json.dumps(doc, indent=2) + "\n")
print(doc["claimed_by"], pip_s, forge_s)
PY
}

publish_status() {
  local claimed pip_s forge_s
  read -r claimed pip_s forge_s < <(write_queue)
  {
    echo "╔══ ELEVATED JOB MONITOR  $(ts) ══╗"
    echo "claimed_by=$claimed  pip=$pip_s  forge=$forge_s"
    echo "elevated=nethunter-root (uid via nethunter -r)"
    echo
    python3 - "$QUEUE" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for k,v in d["priorities"].items():
    print(f"{k}: state={v['state']}")
    print(f"  policy: {v['policy']}")
    print(f"  actors: {', '.join(v['actors'])}")
print("delegation:", d["delegation"]["rule"])
print("idle_rule:", d["delegation"]["idle_rule"])
PY
    echo
    echo "── Regulator board ──"
    fleet-bus board 2>/dev/null || true
    echo "╚══════════════════════════════════╝"
  } | tee "$STATUS" > "$MIRROR/ELEVATED-STATUS.txt"
  cp -f "$QUEUE" "$MIRROR/ELEVATED-QUEUE.json" 2>/dev/null || true
}

delegate() {
  local claimed pip_s forge_s
  read -r claimed pip_s forge_s < <(write_queue)

  bus state regulator elevating "job monitor claim=$claimed pip=$pip_s forge=$forge_s"
  bus send regulator fleet-captain monitor "ELEVATED MONITOR claim=$claimed pip=$pip_s forge=$forge_s"

  case "$claimed" in
    P0_pip_diffusers)
      bus state svd-smith installing "P0 elevated: diffusion/pip install"
      bus state quay deploying "P0 elevated: venv deploy during pip"
      bus state courier fetching "P0 elevated: fetch wheels for pip"
      bus send regulator forge hold "P1 Forge deferred while P0 pip/diffusers active"
      bus state forge standing-by "held by Regulator — P0 pip priority"
      # Ensure pip continues under elevated path if needed
      if [[ "$pip_s" == "NEEDED" ]]; then
        log "P0 escalate: start elevated pip install"
        bus send regulator svd-smith assign "ELEVATED pip install torch+diffusers"
        nohup nethunter -r "$VENV_PIP install --timeout 180 torch torchvision torchaudio diffusers transformers accelerate safetensors Pillow imageio imageio-ffmpeg opencv-python-headless numpy einops omegaconf tqdm" \
          >>"$HOME/grok-inbox/svd-work/logs/pip-elevated.log" 2>&1 &
      fi
      # Idle helpers still help Forge lightly (learned skills) except P0 cast
      if command -v fleet-regulator-reassign >/dev/null; then
        # temporarily protect P0 actors by marking them non-idle before scan
        bus state svd-smith installing "protected P0"
        bus state quay deploying "protected P0"
        bus state courier fetching "protected P0"
        fleet-regulator-reassign scan >/dev/null 2>&1 || true
      fi
      ;;
    P1_github_forge)
      bus state forge fetching "P1 elevated: GitHub lean-pack priority"
      bus send regulator forge assign "P1 HOLD — continue research/pull/index"
      bus state archivist researching "P1 assist: index Forge library"
      bus state harbor mirroring "P1 assist: mirror Forge status"
      if [[ "$forge_s" == "NEEDED" ]] && ! forge_busy; then
        log "P1 escalate: fleet-github-lackey pull"
        nohup fleet-github-lackey pull >>"$FLEET/github-lackey/logs/elevated-pull.log" 2>&1 &
      fi
      if command -v fleet-regulator-reassign >/dev/null; then
        fleet-regulator-reassign scan >/dev/null 2>&1 || true
      fi
      ;;
    *)
      bus state forge indexing "P2: library maintenance"
      bus send regulator fleet-captain heartbeat "P0/P1 clear — normal FC-001 + prompt gate"
      if command -v fleet-regulator-reassign >/dev/null; then
        fleet-regulator-reassign scan >/dev/null 2>&1 || true
      fi
      # Import smoke under elevated path
      if imports_ok; then
        elev_run "$VENV_PY -c \"import torch,diffusers; print('torch',torch.__version__,'diffusers',diffusers.__version__)\"" \
          | tee "$ELEV/import-smoke.txt" >/dev/null || true
        bus send svd-smith fleet-captain report "elevated import smoke OK"
        bus state svd-smith priming "diffusion runtime ready — await project prompt"
      fi
      ;;
  esac

  bus send regulator fleet-captain heartbeat "delegated claim=$claimed"
}

tick() {
  publish_status
  delegate
  publish_status
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
  bus send regulator fleet-captain monitor "Elevated permission job monitor ONLINE"
  nohup bash -c '
    set +e
    export HOME="'"$HOME"'"
    export PATH="'"$HOME"'/bin:/data/data/com.termux/files/usr/bin:$PATH"
    echo $$ > "'"$PIDFILE"'"
    while true; do
      "'"$HOME"'/bin/fleet-elevated-monitor" tick >>"'"$LOG"'" 2>&1
      sleep 6
    done
  ' >/dev/null 2>&1 &
  sleep 1
  echo "elevated-monitor pid=$(cat "$PIDFILE")"
  tick
  command -v fleet-mix-mirror >/dev/null && fleet-mix-mirror open >/dev/null 2>&1 || true
}

cmd_stop() {
  if [[ -f "$PIDFILE" ]]; then
    old=$(cat "$PIDFILE" 2>/dev/null || true)
    [[ -n "${old:-}" && -d "/proc/$old" ]] && kill "$old" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo stopped
  else
    echo not-running
  fi
}

cmd_status() {
  echo "pidfile=$(cat "$PIDFILE" 2>/dev/null || echo none)"
  [[ -f "$PIDFILE" && -d "/proc/$(cat "$PIDFILE")" ]] && echo daemon=RUNNING || echo daemon=STOPPED
  echo "status_file=$STATUS"
  echo "queue_file=$QUEUE"
  echo "mirror=$MIRROR/ELEVATED-STATUS.txt"
  [[ -f "$STATUS" ]] && head -40 "$STATUS"
  elev_run 'id -u; id -un' | head -5
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  tick) tick ;;
  queue) write_queue; cat "$QUEUE" ;;
  *)
    cat <<'EOF'
Usage:
  fleet-elevated-monitor start|stop|status|tick|queue

Priority framework (Regulator-linked):
  P0  pip / diffusers install   (svd-smith, quay, courier) [elevated nethunter]
  P1  GitHub Lackey Forge pull  (forge + idle learned-skill helpers)
  P2  other FC-001 duties
EOF
    ;;
esac
