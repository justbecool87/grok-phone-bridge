#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"
LOG="$HOME/tmp/cs-r2223-socks2080.log"
PIDF="$HOME/tmp/cs-r2223-socks2080.pid"
CS="${CODESPACE_NAME:-orange-guacamole-69wg645vq95p356j}"
REMOTE=2223
LOCAL=2080
export CS REMOTE LOCAL LOG PIDF

python3 - <<'PY'
import os, signal
needle = f"{os.environ['REMOTE']}:127.0.0.1:{os.environ['LOCAL']}".encode()
for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    try:
        raw = open(f'/proc/{pid}/cmdline', 'rb').read()
    except Exception:
        continue
    if needle in raw and b'start-r2223' not in raw:
        try:
            os.kill(int(pid), signal.SIGTERM)
            print('stopped', pid)
        except Exception as e:
            print('skip', pid, e)
PY
sleep 1

if ! (echo >/dev/tcp/127.0.0.1/"$LOCAL") 2>/dev/null; then
  echo "local :$LOCAL closed" >&2
  exit 1
fi

nohup gh cs ssh -c "$CS" -- \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -N -R "${REMOTE}:127.0.0.1:${LOCAL}" \
  >"$LOG" 2>&1 &
echo $! >"$PIDF"
sleep 12
echo "pid=$(cat "$PIDF")"
echo '---- log ----'
tail -50 "$LOG" || true
python3 - <<'PY'
import os
needle = f"{os.environ['REMOTE']}:127.0.0.1:{os.environ['LOCAL']}"
for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    try:
        cmd = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode('utf-8', 'replace')
    except Exception:
        continue
    if needle in cmd:
        print('alive', pid, cmd[:260])
PY

gh cs ssh -c "$CS" -- "ss -ltn | grep -E ':${REMOTE}\\b' || netstat -ltn 2>/dev/null | grep -E ':${REMOTE}\\b' || echo MISSING_${REMOTE}" </dev/null
