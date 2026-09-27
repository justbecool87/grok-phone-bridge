#!/data/data/com.termux/files/usr/bin/bash
# GitHub Lackey ("Forge") — research + shallow-pull assist repos per Fleet actor.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

ROOT="${FLEET_GH_ROOT:-$HOME/grok-inbox/fleet/github-lackey}"
REPOS="$ROOT/repos"
MANIFEST="$ROOT/manifests/lean-pack.json"
LOG="$ROOT/logs/forge-$(date +%Y%m%d).log"
mkdir -p "$REPOS" "$ROOT/manifests" "$ROOT/logs"

ts() { date -Iseconds; }
log() { printf '%s %s\n' "$(ts)" "$*" | tee -a "$LOG"; }

# Lean pack: actor -> repo (coding / deploy / learning)
# Keep clones shallow; prefer small or markdown-heavy trees.
write_manifest() {
  cat > "$MANIFEST" <<'EOF'
{
  "lackey": "forge",
  "title": "GitHub Lackey",
  "pack": "lean",
  "actors": {
    "scout": [
      {"repo": "termux/termux-api", "why": "on-device media/storage intents; coding Termux host access"}
    ],
    "probe": [
      {"repo": "kkroening/ffmpeg-python", "why": "ffprobe/ffmpeg Python bindings for video forensics"}
    ],
    "svd-smith": [
      {"repo": "camenduru/stable-video-diffusion-colab", "why": "SVD learning recipes / launch patterns"},
      {"repo": "thecooltechguy/ComfyUI-Stable-Video-Diffusion", "why": "SVD node patterns for edit/enhance protocol"}
    ],
    "harbor": [
      {"repo": "termux/termux-widget", "why": "Termux GUI/widget launch patterns for persistent monitors"}
    ],
    "courier": [
      {"repo": "huggingface/huggingface_hub", "why": "fetch/auth/download weights and model cards"}
    ],
    "quay": [
      {"repo": "pypa/virtualenv", "why": "venv deploy/hardening patterns for Kali SVD runtime"}
    ],
    "archivist": [
      {"repo": "diff-usion/Awesome-Diffusion-Models", "why": "curated diffusion/SVD learning index"}
    ],
    "loom": [
      {"repo": "Zulko/moviepy", "why": "render/mux/edit pipelines post-SVD"}
    ],
    "termux-commander": [
      {"repo": "termux/termux-api-package", "why": "Termux package/API deploy reference"}
    ],
    "forge": [
      {"repo": "cli/cli", "why": "gh CLI language/learning for GitHub Lackey ops"}
    ]
  }
}
EOF
}

bus_active() {
  command -v fleet-bus >/dev/null || return 0
  fleet-bus state forge "$1" "$2" >/dev/null 2>&1 || true
  fleet-bus send forge fleet-captain report "$2" >/dev/null 2>&1 || true
  fleet-bus state forge "$1" "continue: $2" >/dev/null 2>&1 || true
}

clone_one() {
  local actor="$1" repo="$2" why="$3"
  local dest="$REPOS/$actor/$(basename "$repo")"
  mkdir -p "$REPOS/$actor"
  if [[ -d "$dest/.git" ]]; then
    log "UPDATE $actor $repo"
    bus_active researching "UPDATE $repo for $actor"
    git -C "$dest" pull --ff-only --depth 1 2>>"$LOG" || git -C "$dest" fetch --depth 1 2>>"$LOG" || true
    return 0
  fi
  log "CLONE $actor $repo :: $why"
  bus_active fetching "clone $repo → $dest"
  # blobless shallow clone when supported; fallback depth-1
  if git clone --filter=blob:none --sparse --depth 1 "https://github.com/${repo}.git" "$dest" >>"$LOG" 2>&1; then
    :
  else
    rm -rf "$dest"
    git clone --depth 1 "https://github.com/${repo}.git" "$dest" >>"$LOG" 2>&1
  fi
  # write why sidecar
  printf '%s\n' "$why" > "$dest/FLEET-WHY.txt"
  bus_active deploying "pulled $repo for $actor"
}

cmd_research() {
  write_manifest
  bus_active researching "lean pack manifest written"
  log "manifest $MANIFEST"
  python3 - <<'PY'
import json, pathlib
m=json.loads(pathlib.Path.home().joinpath('grok-inbox/fleet/github-lackey/manifests/lean-pack.json').read_text())
for actor, items in m['actors'].items():
    for it in items:
        print(f"{actor:16} {it['repo']:48} {it['why']}")
PY
}

cmd_pull() {
  write_manifest
  command -v git >/dev/null || { echo "git missing" >&2; exit 1; }
  bus_active deploying "GitHub Lackey pull lean pack"
  python3 - <<'PY' >"$ROOT/logs/pull-plan.txt"
import json, pathlib
m=json.loads(pathlib.Path.home().joinpath('grok-inbox/fleet/github-lackey/manifests/lean-pack.json').read_text())
for actor, items in m['actors'].items():
    for it in items:
        print(f"{actor}\t{it['repo']}\t{it['why']}")
PY
  while IFS=$'\t' read -r actor repo why; do
    [[ -z "${actor:-}" ]] && continue
    clone_one "$actor" "$repo" "$why" || log "FAIL $actor $repo"
  done < "$ROOT/logs/pull-plan.txt"
  bus_active indexing "lean pack pull complete"
  cmd_status
}

cmd_status() {
  echo "=== GitHub Lackey (Forge) library ==="
  echo "root=$ROOT"
  [[ -f "$MANIFEST" ]] && echo "manifest=$MANIFEST"
  du -sh "$REPOS" 2>/dev/null || true
  find "$REPOS" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort | sed 's|^|  |'
  echo "log=$LOG"
}

cmd_readme() {
  local out="$ROOT/README.md"
  write_manifest
  python3 - "$out" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
m = json.loads(pathlib.Path.home().joinpath('grok-inbox/fleet/github-lackey/manifests/lean-pack.json').read_text())
lines = ["# GitHub Lackey (Forge) — lean assist library\n",
         "Shallow-cloned repos mapped to Fleet actors for coding, deploy, and language learning.\n"]
for actor, items in m["actors"].items():
    lines.append(f"\n## {actor}\n")
    for it in items:
        lines.append(f"- `{it['repo']}` — {it['why']}\n")
out.write_text("".join(lines))
print(out)
PY
}

case "${1:-}" in
  research) cmd_research ;;
  pull) cmd_pull ;;
  status) cmd_status ;;
  readme) cmd_readme ;;
  *)
    cat <<'EOF'
Usage:
  fleet-github-lackey research   # write lean manifest + print map
  fleet-github-lackey pull       # shallow-clone/update repos per actor
  fleet-github-lackey status
  fleet-github-lackey readme
EOF
    ;;
esac
