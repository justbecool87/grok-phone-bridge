#!/data/data/com.termux/files/usr/bin/bash
# Inject Fleet Directors Manifesto into live Grok Build via adb-to-grok / grok-phone say.
# Run on-device in Termux with a live Grok Build TTY. Requires user authorization.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFESTO="${ROOT}/FLEET-DIRECTORS-MANIFESTO.md"
SAY_BIN=""

if command -v adb-to-grok >/dev/null 2>&1; then
  SAY_BIN="adb-to-grok"
elif command -v grok-phone >/dev/null 2>&1; then
  SAY_BIN="grok-phone"
else
  echo "error: neither adb-to-grok nor grok-phone found in PATH" >&2
  exit 1
fi

if [[ ! -f "$MANIFESTO" ]]; then
  echo "error: manifesto missing at $MANIFESTO" >&2
  exit 1
fi

MSG="$(
  printf '%s\n' \
    '[FLEET DIRECTORS MANIFESTO — EXECUTE]' \
    'Directors: Fleet Captain (Harbor Master of the Swarm), Termux Commander (The Terminal Director), Regulator Bot.' \
    'Lackeys are autonomous; Fleet Captain offers options; Regulator adjusts speed/thoroughness; Termux Commander owns ADB/bridge algorithm.' \
    '---' \
    "$(sed -n '1,60p' "$MANIFESTO")"
)"

echo "Injecting via: $SAY_BIN say …"
if [[ "$SAY_BIN" == "adb-to-grok" ]]; then
  adb-to-grok say "$MSG"
else
  grok-phone say "$MSG"
fi

echo "Inject requested. Confirm in the live Grok Build session."
