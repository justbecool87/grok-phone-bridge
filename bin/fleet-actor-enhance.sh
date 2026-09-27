#!/data/data/com.termux/files/usr/bin/bash
# ACTOR ENHANCEMENT BOT — upgrade Lackey/Actor coding skeletons from Forge-landed repos.
# Fleet Captain commands; Termux Commander may re-run with elevated privilege.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
GH="$FLEET/github-lackey/repos"
ACTORS="$FLEET/actors"
VENV="$HOME/grok-inbox/svd-work/venv"
VPIP="/termux-home/grok-inbox/svd-work/venv/bin/pip"
VPY="/termux-home/grok-inbox/svd-work/venv/bin/python"
LOG="$FLEET/github-lackey/logs/actor-enhance.log"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
REPORT="$FLEET/github-lackey/ACTOR-ENHANCEMENT-REPORT.md"

mkdir -p "$ACTORS" "$MIRROR" "$(dirname "$LOG")"

ts() { date -Iseconds; }
log() { printf '%s %s\n' "$(ts)" "$*" | tee -a "$LOG"; }
bus() { command -v fleet-bus >/dev/null && fleet-bus "$@" >/dev/null 2>&1 || true; }

elev_pip() {
  if command -v nethunter >/dev/null; then
    nethunter -r "$VPIP $*" 2>&1 | grep -vE 'stty|cpuinfo|MIDR|BusyBox' | tee -a "$LOG" | tail -20
  else
    "$VENV/bin/pip" "$@" 2>&1 | tee -a "$LOG" | tail -20
  fi
}

elev_py() {
  if command -v nethunter >/dev/null; then
    nethunter -r "$VPY $*" 2>&1 | grep -vE 'stty|cpuinfo|MIDR|BusyBox'
  else
    "$VENV/bin/python" "$@"
  fi
}

unsparse() {
  local repo="$1"
  [[ -d "$repo/.git" ]] || return 0
  log "UNSPARSE $repo"
  git -C "$repo" sparse-checkout disable 2>>"$LOG" || true
  git -C "$repo" checkout HEAD -- . 2>>"$LOG" || git -C "$repo" fetch --depth 1 origin 2>>"$LOG" || true
  # if still no package dir, try deepening
  git -C "$repo" pull --ff-only --depth 50 2>>"$LOG" || true
}

write_skeleton() {
  local actor="$1"
  local dir="$ACTORS/$actor"
  mkdir -p "$dir/lib" "$dir/bin" "$dir/docs"
  shift
  # remaining args are notes written into FRAMEWORK.md
  cat > "$dir/FRAMEWORK.md" <<EOF
# Actor skeleton — $actor

Enhanced by **Actor Enhancement Bot** at $(ts).
Fleet Captain commands upgrades; Termux Commander can re-run elevated.

## Wired Forge repos
EOF
  for note in "$@"; do
    printf -- '- %s\n' "$note" >> "$dir/FRAMEWORK.md"
  done
  cat >> "$dir/FRAMEWORK.md" <<EOF

## Layout
- \`lib/\` — importable helpers
- \`bin/\` — actor CLI entrypoints
- \`docs/\` — excerpts / pointers into Forge clones
EOF
}

enhance_packages() {
  bus state enhance installing "Actor Enhancement Bot — live coding packages into SVD venv"
  bus send enhance fleet-captain report "Installing ffmpeg-python moviepy huggingface_hub for actor skeletons"
  log "PIP install live packages"
  # huggingface_hub likely present; ensure ffmpeg-python + moviepy + imageio
  # Keep huggingface-hub in the <2 range required by diffusers/transformers
  elev_pip install -U ffmpeg-python 'moviepy>=1.0.3' 'huggingface-hub>=1.23,<2' imageio imageio-ffmpeg 2>&1 | tail -40
  cat > "$FLEET/github-lackey/logs/check-mods.py" <<'PYC'
import importlib.util as u
for m in ["ffmpeg", "moviepy", "huggingface_hub", "diffusers", "torch", "PIL"]:
    print(m, "YES" if u.find_spec(m) else "NO")
PYC
  if command -v nethunter >/dev/null; then
    nethunter -r "/termux-home/grok-inbox/svd-work/venv/bin/python /termux-home/grok-inbox/fleet/github-lackey/logs/check-mods.py" 2>/dev/null | grep -vE 'stty|cpuinfo|MIDR|BusyBox' | tee -a "$LOG"
  else
    "$VENV/bin/python" "$FLEET/github-lackey/logs/check-mods.py" | tee -a "$LOG"
  fi
}

enhance_scout() {
  write_skeleton scout \
    "termux/termux-api — device API patterns (reference)" \
    "filesystem/adb discovery already used by grok-phone"
  cat > "$ACTORS/scout/lib/discover.py" <<'PY'
"""Scout enhancement — media discovery helpers."""
from __future__ import annotations
import os
from pathlib import Path

DEFAULT_ROOTS = [
    Path("/sdcard/Download"),
    Path("/sdcard/DCIM"),
    Path("/sdcard/Movies"),
    Path("/sdcard/Pictures"),
    Path("/sdcard/Documents"),
]
VIDEO_EXT = {".mp4", ".mkv", ".webm", ".mov", ".avi", ".3gp", ".m4v"}

def find_videos(query: str = "", roots=None, limit: int = 50):
    roots = roots or DEFAULT_ROOTS
    q = (query or "").lower()
    out = []
    for root in roots:
        if not root.is_dir():
            continue
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            if p.suffix.lower() not in VIDEO_EXT:
                continue
            if q and q not in p.name.lower() and q not in str(p).lower():
                continue
            try:
                st = p.stat()
            except OSError:
                continue
            out.append({"path": str(p), "size": st.st_size, "mtime": st.st_mtime})
            if len(out) >= limit:
                return out
    out.sort(key=lambda x: x["mtime"], reverse=True)
    return out

if __name__ == "__main__":
    import json
    print(json.dumps(find_videos(limit=10), indent=2))
PY
  cat > "$ACTORS/scout/bin/scout-find" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
exec python3 "$(dirname "$0")/../lib/discover.py" "$@"
EOF
  chmod 755 "$ACTORS/scout/bin/scout-find"
  ln -sfn "$GH/scout/termux-api" "$ACTORS/scout/docs/termux-api" 2>/dev/null || true
  log "scout skeleton enhanced"
}

enhance_probe() {
  unsparse "$GH/probe/ffmpeg-python" || true
  write_skeleton probe \
    "kkroening/ffmpeg-python — live package ffmpeg in SVD venv" \
    "ffprobe metadata + frame sampling"
  cat > "$ACTORS/probe/lib/forensics.py" <<'PY'
"""Probe enhancement — video forensics via ffmpeg-python + ffprobe CLI fallback."""
from __future__ import annotations
import json, shutil, subprocess
from pathlib import Path

def _ffprobe_cli(path: str) -> dict:
    cmd = [
        "ffprobe", "-v", "error", "-print_format", "json",
        "-show_format", "-show_streams", path,
    ]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "ffprobe failed")
    return json.loads(p.stdout)

def probe_video(path: str) -> dict:
    path = str(path)
    try:
        import ffmpeg  # ffmpeg-python
        # prefer rich probe when available
        return ffmpeg.probe(path)
    except Exception:
        return _ffprobe_cli(path)

def sample_frame(path: str, at_sec: float, out: str) -> str:
    out_p = Path(out)
    out_p.parent.mkdir(parents=True, exist_ok=True)
    try:
        import ffmpeg
        (
            ffmpeg.input(path, ss=at_sec)
            .output(str(out_p), vframes=1, **{"qscale:v": 2})
            .overwrite_output()
            .run(quiet=True)
        )
    except Exception:
        subprocess.run(
            ["ffmpeg", "-y", "-ss", str(at_sec), "-i", path, "-frames:v", "1", "-q:v", "2", str(out_p)],
            check=True, capture_output=True,
        )
    return str(out_p)

if __name__ == "__main__":
    import sys
    p = sys.argv[1] if len(sys.argv) > 1 else str(Path.home()/"grok-inbox/VID_20260927_105213.mp4")
    print(json.dumps(probe_video(p), indent=2)[:2000])
PY
  ln -sfn "$GH/probe/ffmpeg-python" "$ACTORS/probe/docs/ffmpeg-python" 2>/dev/null || true
  log "probe skeleton enhanced"
}

enhance_svd_smith() {
  write_skeleton svd-smith \
    "camenduru SVD Colab — fp16/fp32 recipes" \
    "ComfyUI-Stable-Video-Diffusion — node/workflow patterns" \
    "diffusers StableVideoDiffusionPipeline (live venv)"
  # Quality enhance runner inspired by Colab + Comfy patterns
  cat > "$ACTORS/svd-smith/lib/svd_enhance.py" <<'PY'
"""
SVD Smith — exceptional-quality enhance helpers using Diffusers SVD.
Patterns adapted from Forge-landed:
  - camenduru/stable-video-diffusion-colab (decode dtype / fp16)
  - ComfyUI-Stable-Video-Diffusion (motion bucket, noise aug, frame count)
"""
from __future__ import annotations
import json
from pathlib import Path

DEFAULTS = {
    "num_frames": 14,
    "decode_chunk_size": 4,
    "motion_bucket_id": 127,
    "noise_aug_strength": 0.02,
    "fps": 7,
    "width": 576,
    "height": 1024,  # SVD XT family portrait default; landscape swap as needed
    "dtype": "float16",
}

def load_comfy_hints(repo: Path) -> dict:
    hints = {}
    nodes = repo / "nodes.py"
    svd_py = repo / "svd.py"
    for p in (nodes, svd_py):
        if p.exists():
            text = p.read_text(errors="replace")
            for key in ("motion_bucket", "noise_aug", "num_frames", "fps"):
                if key in text:
                    hints.setdefault("comfy_mentions", []).append(f"{p.name}:{key}")
    return hints

def load_colab_hints(repo: Path) -> dict:
    hints = {"notebooks": []}
    for nb in repo.glob("*.ipynb"):
        hints["notebooks"].append(nb.name)
    req = repo / "requirements.txt"
    if req.exists():
        hints["requirements"] = [ln.strip() for ln in req.read_text().splitlines() if ln.strip() and not ln.startswith("#")]
    return hints

def build_quality_config(frame_w: int = 1280, frame_h: int = 720) -> dict:
    cfg = dict(DEFAULTS)
    # landscape source → landscape SVD sizing
    if frame_w >= frame_h:
        cfg["width"], cfg["height"] = 1024, 576
    else:
        cfg["width"], cfg["height"] = 576, 1024
    # keep aspect-ish; Diffusers will resize
    cfg["source_wh"] = [frame_w, frame_h]
    return cfg

def pipeline_available() -> dict:
    import importlib.util as u
    return {
        "torch": bool(u.find_spec("torch")),
        "diffusers": bool(u.find_spec("diffusers")),
        "PIL": bool(u.find_spec("PIL")),
        "huggingface_hub": bool(u.find_spec("huggingface_hub")),
    }

def write_ready_manifest(out: Path, **extra) -> Path:
    gh = Path.home() / "grok-inbox/fleet/github-lackey/repos/svd-smith"
    doc = {
        "actor": "svd-smith",
        "quality_defaults": build_quality_config(),
        "packages": pipeline_available(),
        "comfy": load_comfy_hints(gh / "ComfyUI-Stable-Video-Diffusion"),
        "colab": load_colab_hints(gh / "stable-video-diffusion-colab"),
        "note": "Weights download deferred until Fleet Captain project prompt; config+imports ready for exceptional quality run.",
        **extra,
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=2) + "\n")
    return out

if __name__ == "__main__":
    out = Path.home() / "grok-inbox/fleet/actors/svd-smith/QUALITY.json"
    print(write_ready_manifest(out))
    print(out.read_text())
PY
  cat > "$ACTORS/svd-smith/bin/svd-quality-check" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"
if command -v nethunter >/dev/null; then
  nethunter -r "/termux-home/grok-inbox/svd-work/venv/bin/python /termux-home/grok-inbox/fleet/actors/svd-smith/lib/svd_enhance.py" 2>/dev/null | grep -vE 'stty|cpuinfo|MIDR|BusyBox'
else
  "$HOME/grok-inbox/svd-work/venv/bin/python" "$HOME/grok-inbox/fleet/actors/svd-smith/lib/svd_enhance.py"
fi
EOF
  chmod 755 "$ACTORS/svd-smith/bin/svd-quality-check"
  ln -sfn "$GH/svd-smith/ComfyUI-Stable-Video-Diffusion" "$ACTORS/svd-smith/docs/comfy-svd" 2>/dev/null || true
  ln -sfn "$GH/svd-smith/stable-video-diffusion-colab" "$ACTORS/svd-smith/docs/colab-svd" 2>/dev/null || true
  # run quality manifest via host python if venv path awkward — try elev
  if command -v nethunter >/dev/null; then
    nethunter -r '/termux-home/grok-inbox/svd-work/venv/bin/python /termux-home/grok-inbox/fleet/actors/svd-smith/lib/svd_enhance.py' 2>/dev/null | grep -vE 'stty|cpuinfo|MIDR|BusyBox' | tee -a "$LOG" | tail -20 || true
  fi
  # also run with termux python writing file (imports may fail on host py) — write with venv only
  log "svd-smith skeleton enhanced"
}

enhance_harbor() {
  write_skeleton harbor \
    "termux/termux-widget — persistent launcher patterns" \
    "MiXplorer mirror + adb-to-grok inject (live)"
  cat > "$ACTORS/harbor/lib/deliver.py" <<'PY'
"""Harbor enhancement — deliver status artifacts to MiXplorer + optional grok inject."""
from __future__ import annotations
import shutil, subprocess
from pathlib import Path

MIRROR = Path("/sdcard/Download/grok-inbox/fleet-monitor")

def publish(path: str | Path, name: str | None = None) -> str:
    MIRROR.mkdir(parents=True, exist_ok=True)
    src = Path(path)
    dest = MIRROR / (name or src.name)
    shutil.copy2(src, dest)
    return str(dest)

def inject(msg: str) -> bool:
    try:
        subprocess.run(["adb-to-grok", "say", msg], check=False)
        return True
    except FileNotFoundError:
        return False
PY
  ln -sfn "$GH/harbor/termux-widget" "$ACTORS/harbor/docs/termux-widget" 2>/dev/null || true
  log "harbor skeleton enhanced"
}

enhance_courier() {
  unsparse "$GH/courier/huggingface_hub" || true
  write_skeleton courier \
    "huggingface/huggingface_hub — live in SVD venv for weight fetch"
  cat > "$ACTORS/courier/lib/fetch_weights.py" <<'PY'
"""Courier enhancement — Hugging Face hub fetch helpers for SVD weights."""
from __future__ import annotations
from pathlib import Path

def hub_ok() -> bool:
    try:
        import huggingface_hub
        return True
    except ImportError:
        return False

def plan_svd_weights(model_id: str = "stabilityai/stable-video-diffusion-img2vid-xt",
                     dest: str | None = None) -> dict:
    dest = dest or str(Path.home() / "grok-inbox/svd-work/weights")
    return {
        "model_id": model_id,
        "dest": dest,
        "hub_available": hub_ok(),
        "action": "snapshot_download on Captain project prompt",
        "cmd": f"huggingface-cli download {model_id} --local-dir {dest}",
    }

def fetch_snapshot(model_id: str, dest: str) -> str:
    from huggingface_hub import snapshot_download
    Path(dest).mkdir(parents=True, exist_ok=True)
    return snapshot_download(repo_id=model_id, local_dir=dest)

if __name__ == "__main__":
    import json
    print(json.dumps(plan_svd_weights(), indent=2))
PY
  ln -sfn "$GH/courier/huggingface_hub" "$ACTORS/courier/docs/huggingface_hub" 2>/dev/null || true
  log "courier skeleton enhanced"
}

enhance_quay() {
  write_skeleton quay \
    "pypa/virtualenv — reference; live deploy uses python -m venv + pip"
  cat > "$ACTORS/quay/lib/deploy_env.py" <<'PY'
"""Quay enhancement — SVD venv health / deploy checks."""
from __future__ import annotations
import importlib.util as u
from pathlib import Path

VENV = Path.home() / "grok-inbox/svd-work/venv"

def health() -> dict:
    site = VENV / "lib"
    py = next(VENV.glob("bin/python*"), None)
    mods = {m: bool(u.find_spec(m)) for m in
            ["torch", "diffusers", "ffmpeg", "moviepy", "huggingface_hub", "PIL"]}
    return {
        "venv": str(VENV),
        "python": str(py) if py else None,
        "exists": VENV.is_dir(),
        "modules": mods,
        "ready_for_svd": all(mods[k] for k in ("torch", "diffusers", "PIL")),
    }

if __name__ == "__main__":
    import json
    print(json.dumps(health(), indent=2))
PY
  ln -sfn "$GH/quay/virtualenv" "$ACTORS/quay/docs/virtualenv" 2>/dev/null || true
  log "quay skeleton enhanced"
}

enhance_archivist() {
  write_skeleton archivist \
    "Awesome-Diffusion-Models — research index"
  cat > "$ACTORS/archivist/lib/index_diffusion.py" <<'PY'
"""Archivist enhancement — index Awesome-Diffusion + local Forge notes."""
from __future__ import annotations
from pathlib import Path

AWESOME = Path.home() / "grok-inbox/fleet/github-lackey/repos/archivist/Awesome-Diffusion-Models/README.md"

def extract_svd_mentions(limit: int = 40) -> list[str]:
    if not AWESOME.exists():
        return []
    lines = []
    for ln in AWESOME.read_text(errors="replace").splitlines():
        if any(k in ln.lower() for k in ("video", "svd", "temporal", "3d")):
            lines.append(ln.strip())
        if len(lines) >= limit:
            break
    return lines

if __name__ == "__main__":
    for x in extract_svd_mentions(20):
        print(x)
PY
  ln -sfn "$GH/archivist/Awesome-Diffusion-Models" "$ACTORS/archivist/docs/awesome-diffusion" 2>/dev/null || true
  log "archivist skeleton enhanced"
}

enhance_loom() {
  unsparse "$GH/loom/moviepy" || true
  write_skeleton loom \
    "Zulko/moviepy — live package for post-SVD mux/render"
  cat > "$ACTORS/loom/lib/render_mux.py" <<'PY'
"""Loom enhancement — render/mux helpers (moviepy when available, ffmpeg fallback)."""
from __future__ import annotations
import subprocess
from pathlib import Path

def moviepy_ok() -> bool:
    try:
        import moviepy  # noqa: F401
        return True
    except ImportError:
        return False

def mux_audio(video: str, audio_src: str, out: str) -> str:
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    if moviepy_ok():
        try:
            from moviepy import VideoFileClip, AudioFileClip
            v = VideoFileClip(video)
            a = AudioFileClip(audio_src)
            # newer moviepy API varies; fallback to ffmpeg on failure
            v = v.with_audio(a) if hasattr(v, "with_audio") else v.set_audio(a)
            v.write_videofile(out, codec="libx264", audio_codec="aac", logger=None)
            return out
        except Exception:
            pass
    subprocess.run(
        ["ffmpeg", "-y", "-i", video, "-i", audio_src, "-c:v", "copy", "-map", "0:v:0", "-map", "1:a:0", "-shortest", out],
        check=True, capture_output=True,
    )
    return out

def status() -> dict:
    return {"moviepy": moviepy_ok(), "role": "post-SVD render/mux"}

if __name__ == "__main__":
    import json
    print(json.dumps(status(), indent=2))
PY
  ln -sfn "$GH/loom/moviepy" "$ACTORS/loom/docs/moviepy" 2>/dev/null || true
  log "loom skeleton enhanced"
}

enhance_forge() {
  write_skeleton forge \
    "cli/cli — gh already on device; Forge ops via fleet-github-lackey"
  cat > "$ACTORS/forge/lib/repo_ops.py" <<'PY'
"""Forge enhancement — thin wrapper around fleet-github-lackey / gh."""
from __future__ import annotations
import subprocess
from pathlib import Path

ROOT = Path.home() / "grok-inbox/fleet/github-lackey"

def status() -> str:
    p = subprocess.run(["fleet-github-lackey", "status"], capture_output=True, text=True)
    return p.stdout

def library_actors() -> list[str]:
    repos = ROOT / "repos"
    if not repos.is_dir():
        return []
    return sorted([p.name for p in repos.iterdir() if p.is_dir() and not p.name.endswith("-aux")])
PY
  ln -sfn "$GH/forge/cli" "$ACTORS/forge/docs/gh-cli" 2>/dev/null || true
  log "forge skeleton enhanced"
}

enhance_commander() {
  write_skeleton termux-commander \
    "termux-api-package — packaging reference" \
    "fleet-termux-commander — elevated deploy/enhance on Captain command"
  cat > "$ACTORS/termux-commander/lib/upgrade_actor.py" <<'PY'
"""Termux Commander — upgrade/revise actor skeletons on Fleet Captain command."""
from __future__ import annotations
import subprocess

def enhance_all() -> int:
    return subprocess.call(["fleet-actor-enhance", "all"])

def enhance_one(actor: str) -> int:
    return subprocess.call(["fleet-actor-enhance", "actor", actor])
PY
  ln -sfn "$GH/termux-commander/termux-api-package" "$ACTORS/termux-commander/docs/termux-api-package" 2>/dev/null || true
  log "termux-commander skeleton enhanced"
}

write_report() {
  cat > "$REPORT" <<EOF
# Actor Enhancement Report

**Bot:** Actor Enhancement Bot (\`fleet-actor-enhance\`)  
**Command authority:** Fleet Captain  
**Elevated re-run:** Termux Commander (\`fleet-termux-commander enhance\`)  
**When:** $(ts)

## What happened
- Live coding packages installed/updated into SVD venv: \`ffmpeg-python\`, \`moviepy\`, \`huggingface_hub\`, \`imageio\`
- Each Forge-landed repo mapped into \`~/grok-inbox/fleet/actors/<actor>/\` skeleton framework
- SVD Smith received quality defaults from Colab + ComfyUI SVD patterns + Diffusers availability check

## Actor frameworks
EOF
  for a in scout probe svd-smith harbor courier quay archivist loom forge termux-commander; do
    echo "- \`$a\` → \`$ACTORS/$a/\`" >> "$REPORT"
  done
  cat >> "$REPORT" <<'EOF'

## SVD quality
See `actors/svd-smith/QUALITY.json` (generated by svd_enhance.py).
Weights still deferred until Fleet Captain project prompt.

## Next Captain commands
```bash
fleet-actor-enhance status
fleet-termux-commander enhance    # elevated re-run
# then send project prompt for SVD weight fetch + enhance run
```
EOF
  cp -f "$REPORT" "$MIRROR/ACTOR-ENHANCEMENT-REPORT.md"
}

cmd_all() {
  bus state enhance enhancing "Actor Enhancement Bot upgrading all skeletons from Forge repos"
  bus send enhance fleet-captain report "BEGIN actor skeleton enhancements"
  bus send fleet-captain termux-commander report "Enhancement Bot running — Commander may elevate/revise"
  enhance_packages || log "packages step had warnings"
  enhance_scout
  enhance_probe
  enhance_svd_smith
  enhance_harbor
  enhance_courier
  enhance_quay
  enhance_archivist
  enhance_loom
  enhance_forge
  enhance_commander
  # generate QUALITY.json via venv
  if command -v nethunter >/dev/null; then
    nethunter -r 'cd /termux-home && ./grok-inbox/svd-work/venv/bin/python grok-inbox/fleet/actors/svd-smith/lib/svd_enhance.py' 2>/dev/null | grep -vE 'stty|cpuinfo|MIDR|BusyBox' | tee -a "$LOG" | tail -30 || \
    nethunter -r '/termux-home/grok-inbox/svd-work/venv/bin/python /termux-home/grok-inbox/fleet/actors/svd-smith/lib/svd_enhance.py' 2>/dev/null | grep -vE 'stty|cpuinfo|MIDR|BusyBox' | tee -a "$LOG" | tail -30 || true
  fi
  write_report
  bus state enhance complete "all actor skeletons enhanced from Forge library"
  bus send enhance fleet-captain report "COMPLETE — see ACTOR-ENHANCEMENT-REPORT.md"
  bus send fleet-captain termux-commander report "Skeletons upgraded — Commander may further revise on command"
  echo "REPORT=$REPORT"
  head -40 "$REPORT"
}

cmd_status() {
  echo "actors_root=$ACTORS"
  find "$ACTORS" -maxdepth 2 -type f 2>/dev/null | sort | head -60
  [[ -f "$ACTORS/svd-smith/QUALITY.json" ]] && echo '--- QUALITY.json ---' && cat "$ACTORS/svd-smith/QUALITY.json"
  elev_py -c 'import importlib.util as u
for m in ["ffmpeg","moviepy","huggingface_hub","diffusers","torch"]:
 print(m, "YES" if u.find_spec(m) else "NO")' 2>/dev/null | grep -vE 'stty|cpuinfo' || true
}

case "${1:-}" in
  all) cmd_all ;;
  packages) enhance_packages ;;
  actor)
    case "${2:-}" in
      scout) enhance_scout ;;
      probe) enhance_probe ;;
      svd-smith) enhance_svd_smith ;;
      harbor) enhance_harbor ;;
      courier) enhance_courier ;;
      quay) enhance_quay ;;
      archivist) enhance_archivist ;;
      loom) enhance_loom ;;
      forge) enhance_forge ;;
      termux-commander) enhance_commander ;;
      *) echo "unknown actor $2"; exit 2 ;;
    esac
    ;;
  status) cmd_status ;;
  *)
    cat <<'EOF'
Usage:
  fleet-actor-enhance all           # enhance every actor from Forge repos + install live pkgs
  fleet-actor-enhance packages      # venv packages only
  fleet-actor-enhance actor <name>
  fleet-actor-enhance status

Actor Enhancement Bot — Fleet Captain commands; Termux Commander can elevate/revise.
EOF
    ;;
esac
