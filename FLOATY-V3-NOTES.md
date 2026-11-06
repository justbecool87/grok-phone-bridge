# Floaty v3 — hy-memory recovered & superseded (2026-11-06)

This repo's floaty lineage (ses_e61a17ce… "Hy-Memory BOTZZ ADB deployment plan",
distilled in /sdcard/botzz/SESSION-NOTES.md) was recovered via ghgrab and
re-implemented as **floaty v3**. Canonical source is now:

- **justbecool87/porsh-wire** → `autojs6/floaty.js` (dispatcher: picker 47 actors,
  owner-only comms box w/ IME+Enter, executable DEPLOY/STOP/RECLAIM actor-loop,
  DUMP fleet-status, matrix theme, ui-observer watchdog + owner gates)
- Deploy/run: `botzz-sync floaty` (porsh-wire `bin/`) via Porter ADB (porsh.dex)
  + AutoJS6 RunIntentActivity — background only, no visible automation.
- Protocol unchanged from this repo's notes: panel.out/panel.resp/ask.out/ask.resp/
  job-<actor>.in/actors.json, ESSENTIAL-ONLY filter.
- Watchdogs: quay (queue) + courier (delivery/tunnels) → forge/inbox/regulator-*.jsonl;
  regulator → fleet-captain escalation = suggestions only (FLEET-CAPTAIN-DIRECTIVES.md).
- loom/lean-scribe/scout/probe/harbor/svd-smith remain **grok SVD-video roles**
  (fleet-roster.json); anti-hunger duty (feeding idle actors) is implemented as
  BOTZZ queue tasks, not new video actors.

One-edge tunnel rule (owner 2026-11-06): ONE cloudflared → :49375; BOTZZ window =
loopback :49376; everything else multiplexes over sing-box SOCKS :2080.
