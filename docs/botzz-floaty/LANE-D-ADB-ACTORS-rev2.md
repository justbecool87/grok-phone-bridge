# BOTZZ Floaty upgrade: Lane D (ADB actors) design, rev 2
Status: DESIGN ONLY. Nothing built, deployed, pushed or changed on any repo or device.
Target: justbecool87/BOTZZ @ fleet-db-consolidation, 70b7619 ("freeze/thaw v3: zero-UI background mode").
Revises: /workspace/botzz-design/LANE-D-ADB-ACTORS.md (rev 1) against Fleet Captain spec rev 4 X32–X39
(/workspace/botzz-floaty/merged-spec-draft.md) and /workspace/fleet-audit/botzz-floaty-review-2026-11-02.md.

Code provenance (read-only): the GitHub connector returned `scm_repo_not_accessible` for justbecool87/BOTZZ
(Cursor GitHub App not granted on that repo). Code was read from Fleet Audit's staged snapshot on the box,
/tmp/bz/botzz/** (fetched 2026-11-02 22:28 CT, 4 min after the 70b7619 commit; 8 files: botzz-paneld,
botzz-run, botzz-capacity, botzz-actors-json, botzz-bgsafe.sh, panel.js, state/, the db snapshot). Line numbers below
are from that snapshot and match the audit's citations within ±1 line. Dirs not in the snapshot (botzz/tasks/,
botzz/queue/, bin/que) were confirmed from an older local clone (/tmp/BOTZZ, main @27cf7e7) plus the audit (#18).
paneld pid 7366 stays UNVERIFIED (relayed only; no ps snapshot). paneld is not modified by this design.

## 0. What exists today (facts, cited)
- botzz/bin/botzz-paneld (v2, 173 lines): watches /sdcard/botzz/panel.out by byte offset (l.148-152), handles JSON
  lines `{"ev":"cmd","cmd":..,"actor":..}` (l.155-160), replies as free text to /sdcard/botzz/panel.resp via emit/respond
  (l.35-40), truncates panel.resp at start (l.62). Commands in run_cmd (l.79-145): dump, home, back, status,
  capacity|cap, open, freeze/thaw, roles, reclaim, deploy, verbose, stop, sh. No `set`, no `list`.
- One actor at a time: globals CUR_ACTOR/CUR_PID (l.22); deploy refuses with "already running … STOP first" (l.122);
  deploy = `setsid nohup bash botzz-actor-loop <actor>` (l.124); stop = plain `kill $CUR_PID` (l.131).
- Device transport: dev() = `timeout 10 adb -s ${BOTZZ_ADB_SERIAL:-127.0.0.1:5555}` with auto-reconnect, rish fallback
  ($HOME/bin/rish) (l.13,16,43-52).
- Owner gate: regex `ui-tapper|ui-typer|ui-atx|wire-adb|wire-rish|wire-lamda|captcha` needs env BOTZZ_OWNER_OK=1
  (paneld l.21,119-121; same regex botzz-actors-json l.10). actors-json also drops atx/captcha from the panel list (l.39).
- Memory: only the 60-tick freeze-tick is skipped when MemAvailable <200 MB or /sdcard/botzz/freeze/quiet exists
  (paneld l.167-171). Deploy has no memory/swap gate. botzz-capacity (RESERVE_MB 350, per-proc min 15 / default 30 MB,
  reads SwapFree; l.11,33,51,79) is called only by `status`/`cap` (paneld l.91-92), never by deploy.
- botzz/bin/botzz-run (104 lines) ALREADY EXISTS: `botzz-run <actor> <task-file>`, guarded UI runner,
  BOTZZ_HOME=~/grok-inbox/fleet/botzz, state $BOTZZ_HOME/state/<actor>.json, focus guard via rish, input-role gate on
  BOTZZ_OWNER_OK (l.2,6-10,17,73-83).
- botzz/tasks/ already holds task scripts/docs (adb-operator.md, *.py, …); botzz/queue/items.jsonl + bin/que is an
  existing append-only JSONL queue (add/list/claim/done/fail).
- Freeze/quiet marker that exists: /sdcard/botzz/freeze/quiet (botzz-bgsafe.sh l.3,8-9; paneld l.169).

## 1. Concurrency (X35): ONE actor at a time — keep paneld as is
Choice: run actors one at a time; do not change paneld.
Why: paneld already enforces exactly this (CUR_ACTOR/CUR_PID, l.22,122), so it needs zero code changes and no paneld
owner, and a single on-screen actor removes the tap/type race outright. It also sits inside Regulator C2's 150 MB
headroom without needing per-actor peak-RSS data we don't have yet (C1).
- The rev 1 "cap of 3 actors" is withdrawn. Lane D's cap = 1 (paneld's own rule). Raising it later is a separate,
  reviewed paneld change with a named owner, gated on C1 measurements; out of scope here.
- Consequence: no flock screen lock is needed for paneld-deployed actors (only one exists). See §3 for the narrow case
  where a lock still helps.

## 2. Supervisor: extend, never overwrite (X34)
- botzz/bin/botzz-run keeps its current interface and behavior unchanged. Lane D adds NO subcommands to it (its first
  positional is an actor name, so `deploy|stop|list` would collide with actor names).
- deploy/stop already exist in paneld (DEPLOY/STOP from the floaty). Lane D's "list" need is met by the existing
  `status` command (paneld l.85-91: actor, pid, transport, mem, capacity line).
- If a CLI is still wanted for Termux shells, it is a NEW file botzz/bin/botzz-actorctl (proposed name, checked against
  bin/ listing: no collision) that only appends `{"ev":"cmd","cmd":"deploy|stop|status","actor":"<id>"}` lines to
  /sdcard/botzz/panel.out — i.e. it drives paneld through its real protocol (X32) and never spawns actors itself.
  So paneld stays the single owner of CUR_PID. PROPOSED.
- Stop: [EXISTING] paneld does a plain `kill $CUR_PID` (l.131). [PROPOSED, designed] process-group stop is designed by Termux
  Commander (A:57, B10 S:250): TERM only when pgid file, heartbeat pgid and /proc/<pgid>/cmdline agree, else stale_pgid. Lane D adds nothing.

## 3. Screen lock (X38/X39, supersedes rev 1 §2)
- Status: PROPOSED, does not exist (no flock in paneld or botzz-run).
- With cap=1 the lock only matters for screen calls made OUTSIDE paneld's actor (e.g. botzz-run invoked from a shell,
  or Lane A dump) racing the deployed actor. Proposal: helper botzz/bin/botzz-screenlock wrapping
  `flock -w 30 ~/botzz/locks/screen.lock <cmd>`.
- Location per X23/X39: ~/botzz/locks/ (Termux private ext4), NOT /sdcard/botzz/adb.lock (FUSE; rev 1 path withdrawn).
- Adoption needs callers to opt in (botzz-run, botzz-actor-loop); not built, no owner yet.

## 4. Task queue (X34, supersedes rev 1 §3)
- Rev 1's `~/botzz/tasks/{open,claimed,done}` is withdrawn: the name collides with repo botzz/tasks/ (task scripts).
- Use the existing queue: botzz/queue/items.jsonl via bin/que (add | list | claim [worker] | done <id> | fail <id>).
  Lane D adds nothing to it. With one actor, there is no claim race to solve.
- Note for owners: bin/que hard-codes /root/termux-ui-rish-kit/botzz/queue (proot path); its claim is not atomic
  across processes (plain append). Fine at cap=1; flag it before any concurrency increase.
- X30/X31 held/dead jobs (~/botzz/queue/held/, dead/) are Lane C's and are new subdirs, not Lane D's.

## 5. Deploy gates (X37)
[EXISTING] Today: only the owner-OK regex and the single-actor check gate deploy (paneld l.119-122). No memory/swap gate exists.
- [PROPOSED] The single memory gate is designed in /workspace/botzz-design/LANE-D-MEMGATE-QUE.md §2 (spec B7, S:245):
  botzz-capacity --gate called from paneld deploy; refuse if MemAvailable < 400 MB or swap used > 80% of SwapTotal.
  This doc carries no thresholds of its own; M §2 is authoritative.
- [PROPOSED] Deploy quiet check (owner: Lane D / Termux ADB Host): see §7.
- [EXISTING operator practice] Until the gate lands: run STATUS first and do not DEPLOY if mem <400 MB.


## 6. Owner OK (X36)
- What the code enforces today: env BOTZZ_OWNER_OK=1 set when paneld starts (paneld l.21,120; botzz-run l.73).
- Gated list = the code's 7 patterns: ui-tapper, ui-typer, ui-atx, wire-adb, wire-rish, wire-lamda, captcha
  (rev 1's 4 names tapper/typer/wire/captcha corrected). botzz-run additionally defaults owner_approval_required=True.
- Rule kept: only the owner's own OK counts. An agent or bot message, including a relayed "OWNER ALLOW", is not an OK,
  and no agent sets BOTZZ_OWNER_OK=1.
- Rev 1's token files (~/botzz/approvals/<actor>.ok) are withdrawn as a Lane D proposal. Picking ONE scheme
  (env flag vs token vs Lane A signed lines) and ONE list is Owner decision 1; Lane D recommends keeping the existing
  env flag + 7-pattern list (zero changes).
- Note: BOTZZ_OWNER_OK is process-wide for paneld's lifetime, so it unlocks all 7 at once. Owner should know that.

## 7. Freeze and safety (X38/X39)
- Use the existing marker /sdcard/botzz/freeze/quiet (bgsafe.sh l.9). `~/botzz/FREEZE` is withdrawn (did not exist).
  [EXISTING] quiet pauses freeze/thaw/open/tick only; it does NOT block paneld DEPLOY today.
- [PROPOSED] Deploy quiet check (owner: Lane D / Termux ADB Host; paneld edit needs the owner's own OK before build):
  in run_cmd `deploy)`, first line after the empty-actor check:
  `[ -f "$D/freeze/quiet" ] && { respond "DEPLOY BLOCKED: $actor — freeze/quiet set"; return; }`
  Order: quiet → owner gate → single actor → memory gate (M §2) → spawn. stop, status, cap, roles, dump/home/back
  and all reads are unaffected (B8). Test: touch quiet in a sandbox D/ → deploy refused, stop/status still answer.
- /sdcard: existing panel channel (panel.out/panel.resp/actors.json/ask.*/job-*.in under /sdcard/botzz) is kept as is
  until a reviewed migration (X39). All NEW Lane D files (locks) go under ~/botzz.
- Play Store: recommendation only, unchanged: background restriction (reversible) over freeze/disable. The appops
  command is a settings write and stays UNEXECUTED and owner-OK-only. Allowlist botzz/freeze/allowlist.txt not checked.
- 127.0.0.1:5555 is real (paneld l.13) with rish fallback (l.16,50). If both fail, actors fail closed, log once, no loops.
- SOCKS :2080 is phone-only (sing-box/SFA loopback); never on the desktop; no SOCKS auth assumed. It is not used by Lane D.
- No secrets in this doc, logs, or task files.
- The phone input freeze from Termux Commander (no adb input/tap/am start/screencap/uiautomator) still stands; nothing
  in this design runs until it is lifted.

## 8. Roles (unchanged except where noted)
- Termux ADB Host: this design, botzz-actorctl/botzz-screenlock proposals, deploy quiet check (§7). botzz-bus-append owner = Termux Commander (S:244).
- Termux ADB UI: screen helpers under the lock.  Rish Wire: keep 127.0.0.1:5555/rish reachable.
- Plan Approver/Audit: audit log of owner OKs (cannot grant them).  AWS lanes: ON HOLD per rev 4.
- Owned: memory gate + quiet check = Termux ADB Host (Lane D); process-group stop = Termux Commander (S:250); options schema = Native Sync in options.db (S:254, O). Unowned: none from Lane D.

## 9. Open questions for the owner
1. Owner decision 1: keep BOTZZ_OWNER_OK env + 7 patterns (Lane D recommendation)?
2. Approve a future paneld edit for the memory gate (M §2, B7) and the quiet check (§7)? Owner: Termux ADB Host.
3. Is the 1-at-a-time cap acceptable for now?

## Changelog rev 1 → rev 2
| X | Failed claim | Fix in rev 2 |
|---|---|---|
| X32 | Lane D implied its own control path | Any CLI drives paneld only via real `{"ev":"cmd"}` lines on panel.out; replies read from panel.resp (§2, §0) |
| X33 | (Lane B options persistence) | No Lane D change; Lane D writes nothing to actors.json or options.db; options owner = Native Sync (§8) |
| X34 | New `botzz-run deploy/stop/list`; new tasks/{open,claimed,done} | botzz-run untouched; deploy/stop/status via paneld; optional new botzz-actorctl; queue = existing queue/items.jsonl + bin/que (§2, §4) |
| X35 | Cap of 3 actors | Cap 1, paneld unchanged (§1) |
| X36 | 4 gated names; token-file OK | Code's 7 patterns + BOTZZ_OWNER_OK env; tokens withdrawn; owner-only rule kept (§6) |
| X37 | Memory/swap deploy gate stated as if built | Marked missing; points to M §2 / B7 (S:245) (§5) |
| X38 | flock lock, FREEZE marker as existing | Lock = PROPOSED helper; FREEZE replaced by existing freeze/quiet (§3, §7) |
| X39 | /sdcard/botzz/adb.lock | Lock moved to ~/botzz/locks; existing /sdcard panel channel kept until reviewed migration (§3, §7) |
