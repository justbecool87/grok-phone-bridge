#!/data/data/com.termux/files/usr/bin/bash
# Run a command with the FC-001 SVD venv Python (Kali proot).
set -euo pipefail
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"
VENV_PY="/termux-home/grok-inbox/svd-work/venv/bin/python"
if [[ $# -eq 0 ]]; then
  exec nethunter -r "$VENV_PY -V"
fi
# Pass remaining args as a single python invocation
quoted=
for a in "$@"; do
  quoted+=$(printf '%q ' "$a")
done
exec nethunter -r "$VENV_PY $quoted"
