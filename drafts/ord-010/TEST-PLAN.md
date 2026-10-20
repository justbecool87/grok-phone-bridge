# ord-010 test plan (run only after owner OK to install)

After **each** step, rish-wire-aux takes a read-only snapshot (no kills, no settings):
`ps -A -o pid,ppid,pgid,sid,args | grep -E 'gh cs ssh|ssh -i|ncat|opencode serve|proot|tunnel-sup' > out/rish-wire-aux/ps-<step>.txt`,
plus a Codespace-side `ss -ltn | grep -E ':18022|:2223|:14096'`.

Pass = 18022 and 2223 listening on the Codespace, and both tunnel-sup sids differ from every shell/serve sid.

| # | step | expected |
|---|---|---|
| 1 | serve restart #1 via 20-opencode-serve.sh (setsid) | tunnels untouched; check log shows `present` |
| 2 | serve restart #2 | same |
| 3 | serve restart #3, from the owner's interactive shell | same (tunnels no longer in that shell's session) |
| 4 | exit the interactive Termux shell (session hangup) | tunnels survive |
| 5 | phone reboot | Termux:Boot 10-tunnels brings both forwards back within 120 s |
| 6 | memory-kill recovery: lmkd/OOM kills a tunnel-sup child (observe it, don't force it) | supervisor reconnects with a 15/30/60 s backoff; if a whole supervisor dies, tunnel-watch-job restarts it within 15 min |

## Next steps (owner OK needed, not done)
- Add Termux (and Termux:Boot) to the Android Doze/battery-optimization whitelist.
- Install the drafts (drop `.draft`, chmod +x), schedule tunnel-watch-job, clear stale `codespace-ondemand up` 23467, and retire the ondemand tunnel path / `start-r2223.sh`, which kills existing 2223 forwards.

Note: `~/fleet-resume.sh` does not exist on the phone, so nothing was reused from it.
