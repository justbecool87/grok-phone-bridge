#!/data/data/com.termux/files/usr/bin/bash
# FC-001 ready-for-prompting gate (Termux host + Kali SVD venv)
set -euo pipefail
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

WORK="${SVD_WORK:-$HOME/grok-inbox/svd-work}"
SRC="${SVD_SOURCE:-$HOME/grok-inbox/VID_20260927_105213.mp4}"
ready=1

ok() { printf 'OK   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; ready=0; }

echo "=== FC-001 SVD status ==="
if command -v ffprobe >/dev/null; then ok "ffprobe $(ffprobe -version 2>&1 | head -1)"; else bad "ffprobe missing"; fi
if command -v ffmpeg >/dev/null; then ok "ffmpeg present"; else bad "ffmpeg missing"; fi
if [[ -f "$SRC" ]]; then ok "source $SRC ($(wc -c <"$SRC") bytes)"; else bad "source missing: $SRC"; fi
for d in frames clips exports logs; do
  if [[ -d "$WORK/$d" ]]; then ok "dir $WORK/$d"; else bad "dir missing $WORK/$d"; fi
done
if [[ -f "$WORK/frames/frame_0s.jpg" ]]; then ok "probe frames present"; else bad "probe frames missing"; fi
if [[ -f "$WORK/clips/segment_0_3s.mp4" ]]; then ok "normalize clip segment_0_3s.mp4"; else bad "normalize clip missing"; fi

if [[ -e "$WORK/venv/bin/python" ]]; then
  if command -v nethunter >/dev/null; then
    if nethunter -r '/termux-home/grok-inbox/svd-work/venv/bin/python - <<"PY"
import importlib.util
mods = ["torch", "diffusers", "transformers", "PIL"]
missing = [m for m in mods if importlib.util.find_spec(m) is None]
if missing:
    raise SystemExit("missing:" + ",".join(missing))
import torch, diffusers
print(f"torch {torch.__version__} cuda={torch.cuda.is_available()}")
print(f"diffusers {diffusers.__version__}")
PY' 2>/dev/null | grep -v stty
    then
      ok "venv imports torch+diffusers (via Kali proot)"
    else
      bad "venv present but imports failed (pip still running?)"
    fi
  else
    bad "nethunter missing; cannot enter Kali SVD venv"
  fi
else
  bad "venv missing at $WORK/venv"
fi

echo "---"
if [[ "$ready" -eq 1 ]]; then
  echo "STATUS=READY_FOR_PROMPTING"
  echo "Fleet Captain is waiting for your project prompt."
  exit 0
fi
echo "STATUS=INSTALLING_OR_BLOCKED"
exit 1
