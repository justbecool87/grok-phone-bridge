#!/data/data/com.termux/files/usr/bin/bash
export PATH=$HOME/bin:$PREFIX/bin:$PATH
sleep 20; nohup codespace-ondemand up >$HOME/tmp/codespace-ondemand-up.log 2>&1 &
