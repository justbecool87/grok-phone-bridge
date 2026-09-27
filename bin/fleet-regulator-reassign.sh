#!/data/data/com.termux/files/usr/bin/bash
# Regulator Bot — if a Lackey is idle, reassign them to help GitHub Lackey (Forge)
# using skills they have already learned on FC-001.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
STATE="$FLEET/state"
GH_ROOT="${FLEET_GH_ROOT:-$FLEET/github-lackey}"
REPOS="$GH_ROOT/repos"
HELP_LOG="$GH_ROOT/logs/regulator-help-$(date +%Y%m%d).log"
mkdir -p "$STATE" "$REPOS" "$GH_ROOT/logs" "$GH_ROOT/help"

ts() { date -Iseconds; }
log() { printf '%s %s\n' "$(ts)" "$*" | tee -a "$HELP_LOG"; }

is_idle() {
  local actor="$1"
  local f="$STATE/${actor}.json"
  [[ -f "$f" ]] || return 0
  python3 - "$f" <<'PY'
import json,sys
raw=open(sys.argv[1]).read().strip().splitlines()
d=json.loads(raw[-1])
t=(d.get("transit") or "").lower()
detail=(d.get("detail") or "").lower()
idle = t == "idle" or "on-station" in detail
if t in {"acknowledged"} and "on-station" in detail:
    idle = True
if t == "pinging" and "mix-mirror" in detail:
    idle = True
# never treat installing/deploying/fetching/assisting-forge as idle
if t in {"installing","deploying","fetching","assisting-forge","researching","mirroring","sampling","verifying","priming","priming-render","coordinating","indexing","hardening","staging-cache","bootstrapping"}:
    idle = False
sys.exit(0 if idle else 1)
PY
}

# Learned-skill helpers → assist Forge
help_scout() {
  # learned: locate/verify media paths on device storage
  local out="$GH_ROOT/help/scout-verify-paths.txt"
  {
    echo "# Scout → Forge assist $(ts)"
    echo "Verify GitHub library paths exist and are readable."
    find "$REPOS" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort
    echo "--- disk ---"
    du -sh "$REPOS"/* 2>/dev/null || true
  } > "$out"
  fleet-bus state scout assisting-forge "verify clone paths for Forge library" >/dev/null 2>&1 || true
  fleet-bus send scout forge report "paths verified → $out" >/dev/null 2>&1 || true
  fleet-bus state scout assisting-forge "path audit complete" >/dev/null 2>&1 || true
  log "scout assisted forge paths"
}

help_probe() {
  # learned: probe files/metadata
  local out="$GH_ROOT/help/probe-repo-stats.txt"
  {
    echo "# Probe → Forge assist $(ts)"
    echo "Repo tree stats (file counts / README presence)."
    find "$REPOS" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | while read -r d; do
      n=$(find "$d" -type f ! -path '*/.git/*' 2>/dev/null | wc -l)
      r=no; [[ -f "$d/README.md" || -f "$d/readme.md" ]] && r=yes
      echo "$n files  README=$r  $d"
    done
  } > "$out"
  fleet-bus state probe assisting-forge "stat cloned repos for Forge" >/dev/null 2>&1 || true
  fleet-bus send probe forge report "repo stats → $out" >/dev/null 2>&1 || true
  fleet-bus state probe assisting-forge "repo probe complete" >/dev/null 2>&1 || true
  log "probe assisted forge stats"
}

help_svd_smith() {
  # learned: SVD protocol / requirements awareness
  local out="$GH_ROOT/help/svd-smith-notes.txt"
  {
    echo "# SVD Smith → Forge assist $(ts)"
    echo "Flag SVD-related clones and requirements.txt / environment hints."
    find "$REPOS/svd-smith" -maxdepth 3 \( -iname 'requirements*.txt' -o -iname '*.ipynb' -o -iname 'README*' \) 2>/dev/null | head -40
  } > "$out"
  fleet-bus state svd-smith assisting-forge "annotate SVD repos for Forge" >/dev/null 2>&1 || true
  fleet-bus send svd-smith forge report "SVD notes → $out" >/dev/null 2>&1 || true
  fleet-bus state svd-smith assisting-forge "SVD repo annotation done" >/dev/null 2>&1 || true
  log "svd-smith assisted forge"
}

help_harbor() {
  # learned: mirror/inject into MiXplorer + grok inbox
  local out="$GH_ROOT/help/harbor-mirror.txt"
  mkdir -p /sdcard/Download/grok-inbox/fleet-monitor
  {
    echo "# Harbor → Forge assist $(ts)"
    echo "Mirror Forge status into MiXplorer folder."
    fleet-github-lackey status 2>/dev/null || true
  } > "$out"
  cp -f "$out" /sdcard/Download/grok-inbox/fleet-monitor/FORGE-STATUS.txt 2>/dev/null || true
  [[ -f "$GH_ROOT/README.md" ]] && cp -f "$GH_ROOT/README.md" /sdcard/Download/grok-inbox/fleet-monitor/FORGE-README.md 2>/dev/null || true
  fleet-bus state harbor assisting-forge "mirror Forge status to MiXplorer" >/dev/null 2>&1 || true
  fleet-bus send harbor forge report "mirrored Forge status to sdcard fleet-monitor" >/dev/null 2>&1 || true
  fleet-bus state harbor assisting-forge "Forge mirror published" >/dev/null 2>&1 || true
  log "harbor assisted forge mirror"
}

help_courier() {
  # learned: fetch artifacts — help Forge clone remaining
  fleet-bus state courier assisting-forge "fetch remaining GitHub lean-pack repos" >/dev/null 2>&1 || true
  fleet-bus send courier forge report "helping Forge pull lean pack" >/dev/null 2>&1 || true
  # non-blocking nudge: if pull not running, kick a status/readme refresh; full pull may already run
  if ! pgrep -f 'fleet-github-lackey pull' >/dev/null 2>&1; then
    fleet-github-lackey readme >/dev/null 2>&1 || true
    # pull only missing shallow clones via status gap — call pull (idempotent updates)
    nohup fleet-github-lackey pull >>"$GH_ROOT/logs/courier-help-pull.log" 2>&1 &
  fi
  fleet-bus state courier assisting-forge "Forge fetch assist active" >/dev/null 2>&1 || true
  log "courier assisted forge fetch"
}

help_quay() {
  # learned: deploy/venv/dirs
  local out="$GH_ROOT/help/quay-deploy-check.txt"
  {
    echo "# Quay → Forge assist $(ts)"
    echo "Ensure actor repo dirs + permissions for Forge library."
    mkdir -p "$REPOS"/{scout,probe,svd-smith,harbor,courier,quay,archivist,loom,termux-commander,forge}
    ls -la "$REPOS"
    df -h "$HOME" 2>/dev/null | tail -1
  } > "$out"
  fleet-bus state quay assisting-forge "prepare Forge library deploy dirs" >/dev/null 2>&1 || true
  fleet-bus send quay forge report "deploy dirs ready → $out" >/dev/null 2>&1 || true
  fleet-bus state quay assisting-forge "Forge dirs hardened" >/dev/null 2>&1 || true
  log "quay assisted forge dirs"
}

help_archivist() {
  # learned: research/index protocols
  local out="$GH_ROOT/help/archivist-index.md"
  {
    echo "# Archivist → Forge learning index ($(ts))"
    echo
    for actor in scout probe svd-smith harbor courier quay archivist loom termux-commander forge; do
      echo "## $actor"
      find "$REPOS/$actor" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r d; do
        why=""; [[ -f "$d/FLEET-WHY.txt" ]] && why=$(head -1 "$d/FLEET-WHY.txt")
        echo "- $(basename "$d"): ${why:-pulled}"
      done
      echo
    done
  } > "$out"
  cp -f "$out" "$GH_ROOT/LEARNING-INDEX.md" 2>/dev/null || true
  fleet-bus state archivist assisting-forge "index Forge repos into learning map" >/dev/null 2>&1 || true
  fleet-bus send archivist forge report "learning index → $out" >/dev/null 2>&1 || true
  fleet-bus state archivist assisting-forge "Forge index updated" >/dev/null 2>&1 || true
  log "archivist assisted forge index"
}

help_loom() {
  # learned: render/summarize outputs
  local out="$GH_ROOT/help/loom-repo-render.txt"
  {
    echo "# Loom → Forge assist $(ts)"
    echo "Rendered tree summary for MiXplorer/Forge consumers."
    find "$REPOS" -mindepth 2 -maxdepth 3 \( -name README.md -o -name FLEET-WHY.txt \) 2>/dev/null | sort | head -80
  } > "$out"
  cp -f "$out" /sdcard/Download/grok-inbox/fleet-monitor/FORGE-TREE.txt 2>/dev/null || true
  fleet-bus state loom assisting-forge "render Forge repo tree summary" >/dev/null 2>&1 || true
  fleet-bus send loom forge report "tree render → $out" >/dev/null 2>&1 || true
  fleet-bus state loom assisting-forge "Forge tree rendered" >/dev/null 2>&1 || true
  log "loom assisted forge render"
}

help_forge() {
  fleet-bus state forge fetching "primary GitHub lean-pack pull" >/dev/null 2>&1 || true
  fleet-bus send forge fleet-captain report "Forge continuing lean pack; accepting idle-Lackey helpers" >/dev/null 2>&1 || true
  fleet-bus state forge coordinating "directing idle Lackeys onto GitHub assist duties" >/dev/null 2>&1 || true
}

reassign_one() {
  local actor="$1"
  case "$actor" in
    scout) help_scout ;;
    probe) help_probe ;;
    svd-smith) help_svd_smith ;;
    harbor) help_harbor ;;
    courier) help_courier ;;
    quay) help_quay ;;
    archivist) help_archivist ;;
    loom) help_loom ;;
    forge) help_forge ;;
    *) log "no helper mapping for $actor" ;;
  esac
  fleet-bus send regulator fleet-captain heartbeat "reassigned idle $actor → assist Forge" >/dev/null 2>&1 || true
}

cmd_scan() {
  local actors=(scout probe svd-smith harbor courier quay archivist loom forge)
  local idle_list=()
  fleet-bus state regulator monitoring "scan for idle Lackeys → Forge assist" >/dev/null 2>&1 || true
  for a in "${actors[@]}"; do
    if is_idle "$a"; then
      idle_list+=("$a")
    fi
  done
  if [[ ${#idle_list[@]} -eq 0 ]]; then
    log "no idle lackeys"
    fleet-bus send regulator fleet-captain heartbeat "no idle Lackeys — Forge helpers not needed" >/dev/null 2>&1 || true
    echo "idle: none"
    return 0
  fi
  echo "idle: ${idle_list[*]}"
  fleet-bus send regulator forge assign "IDLE helpers: ${idle_list[*]} — use learned skills to assist GitHub pull/index/mirror" >/dev/null 2>&1 || true
  help_forge
  for a in "${idle_list[@]}"; do
    log "REASSIGN $a → assist forge"
    reassign_one "$a"
  done
}

case "${1:-scan}" in
  scan) cmd_scan ;;
  help) reassign_one "${2:?actor}" ;;
  *) echo "Usage: fleet-regulator-reassign scan|help <actor>" >&2; exit 2 ;;
esac
