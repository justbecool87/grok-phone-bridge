#!/data/data/com.termux/files/usr/bin/bash
# Deploy FC-001 Lackeys briefing into live Grok Build (owner-authorized).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/FLEET-CAPTAIN-DIRECTIVES.md"
VIDEO_SRC='/sdcard/Movies/Messages/VID_20260927_105213.mp4'
STAGED="$HOME/grok-inbox/VID_20260927_105213.mp4"

export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"
mkdir -p "$HOME/grok-inbox/svd-work"

if [[ ! -f "$STAGED" && -f "$VIDEO_SRC" ]]; then
  grok-phone stage "$VIDEO_SRC"
fi

MSG=$(
  printf '%s\n' \
    '[FC-001 DEPLOY — 4 LACKEYS]' \
    'Directive from Termux Commander → Fleet Captain.' \
    'Lackeys: Scout | Probe | SVD Smith | Harbor' \
    'Protocol: Stable Video Diffusion (SVD) edit + enhance' \
    "Target: $VIDEO_SRC" \
    "Staged: $STAGED" \
    'Work: ~/grok-inbox/svd-work/  Exports: ~/grok-inbox/*-svd-enhanced.mp4' \
    '---' \
    "$(sed -n '1,55p' "$DOC")"
)

if command -v adb-to-grok >/dev/null; then
  adb-to-grok say "$MSG"
elif command -v grok-phone >/dev/null; then
  grok-phone say "$MSG"
else
  echo "$MSG"
  exit 1
fi
echo 'FC-001 Lackeys briefing injected.'
