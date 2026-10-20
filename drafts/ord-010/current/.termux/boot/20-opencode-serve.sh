#!/data/data/com.termux/files/usr/bin/bash
export PATH=$HOME/bin:$PREFIX/bin:$PATH
(echo >/dev/tcp/127.0.0.1/4096) 2>/dev/null && exit 0
if command -v opencode >/dev/null; then nohup opencode serve --hostname 127.0.0.1 --port 4096 >$HOME/tmp/opencode-serve.log 2>&1 &
else nohup proot-distro login ubuntu -- bash -lc 'opencode serve --hostname 127.0.0.1 --port 4096' >$HOME/tmp/opencode-serve.log 2>&1 & fi
