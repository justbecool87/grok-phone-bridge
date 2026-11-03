# Lane D: single memory gate + bin/que fix (design note)
Status: DESIGN ONLY. Nothing built, deployed, pushed, configured or run on any device.
Owner: Termux ADB Host (spec rev 7, B7 + B9). Spec: /workspace/fleet-audit/merged-spec-rev7.md (Rev 7).
Code read: /tmp/bz/botzz (Rev 7 says hash-matched to 70b7619) for botzz-paneld, botzz-capacity.
bin/que verified at 70b7619: /tmp/bz/botzz/bin/que sha256 f16345e0be69dcb5… (checked by me, matches Fleet Captain); identical to old clone /tmp/BOTZZ @27cf7e7; paths at que:6-8, claim at que:40-46.

**BUILD GATE: the paneld and botzz-capacity edits below need the owner's own OK in chat before anyone builds them.
An agent's or relayed OK does not count.**

## 1. Files and functions
| File | Function / lines | Role today |
|---|---|---|
| botzz/bin/botzz-paneld | run_cmd `deploy)` l.117-127 | owner-OK regex (l.119), single-actor check (l.122), spawn (l.124). No memory check. |
| botzz/bin/botzz-paneld | watch loop tick l.167-171 | skips botzz-freeze-tick if MemAvailable <200 MB or freeze/quiet exists |
| botzz/bin/botzz-paneld | `status)` l.85-91, `capacity|cap)` l.92 | only current callers of botzz-capacity (advisory) |
| botzz/bin/botzz-capacity | module top level l.30-100 | reads /proc/meminfo (MemAvailable, MemTotal, SwapFree only, l.32-33), adb `nproc` (l.37), /proc scan, fleet state; writes /sdcard/botzz/capacity.json (l.94) |
| botzz/bin/que (70b7619) | load l.11-20, append l.22-23, `claim` l.40-48, paths l.6-8 | JSONL event log queue; Q/OUT/LOOP hard-coded to /root/termux-ui-rish-kit/... |

## 2. Memory gate

### 2.1 botzz-capacity: new `--gate [deploy|tick]` fast path (proposed)
Must return before any adb, /proc scan or fleet glob, so deploy and the 60 s tick stay cheap and never hang on adb.
```python
# insert right after `args = sys.argv[1:]` (l.13), before readf/dev are used
if "--gate" in args:
    kind = (args[args.index("--gate")+1:] or ["deploy"])[0]
    try: mem = open("/proc/meminfo").read()
    except Exception: print("GATE ERR meminfo unreadable"); sys.exit(3)   # fail closed
    mi = {m.group(1): int(m.group(2)) for m in re.finditer(r"^(\w+):\s+(\d+)", mem, re.M)}
    avail = mi.get("MemAvailable", 0)//1024
    st, sf = mi.get("SwapTotal", 0)//1024, mi.get("SwapFree", 0)//1024
    floor = int(os.environ.get("BOTZZ_GATE_MEM_MB", "400"))     # B7
    if kind == "model": floor = max(floor, 450)                 # B7 "model runs need 450 MB"
    pct = int(os.environ.get("BOTZZ_GATE_SWAP_PCT", "80"))      # Regulator C3
    used = max(0, st - sf)
    swap_txt = "swap n/a (SwapTotal=0)" if st == 0 else f"swap {used}/{st}MB ({used*100//st}%)"
    if avail < floor: print(f"GATE MEM {avail}MB < {floor}MB | {swap_txt}"); sys.exit(1)
    if st > 0 and used*100 > pct*st: print(f"GATE SWAP {used*100//st}% > {pct}% | mem {avail}MB"); sys.exit(2)
    print(f"GATE OK mem {avail}MB>= {floor}MB | {swap_txt}"); sys.exit(0)
```
Exit codes: 0 ok, 1 memory, 2 swap, 3 unreadable (fail closed). No file writes in gate mode (capacity.json is not touched).

### 2.2 paneld deploy (proposed diff, doc only)
```diff
@@ run_cmd deploy) (after the owner-OK block l.119-121, after the alive check l.122)
       if alive; then respond "already running $CUR_ACTOR (pid $CUR_PID) — STOP first"; return; fi
+      gate_kind=deploy; [ "${BOTZZ_MODEL_RUN:-0}" = 1 ] && gate_kind=model
+      g=$(timeout 5 python3 "$BOTZZ_BIN/botzz-capacity" --gate "$gate_kind" 2>&1); grc=$?
+      if [ "$grc" -ne 0 ]; then respond "DEPLOY BLOCKED: $actor — ${g:-gate timeout/err (rc=$grc)}"; return; fi
       respond "deploying $actor…"
```
Order kept: owner gate → single actor → memory gate → spawn. Timeout (rc 124) or crash = refuse (fail closed).
`model` kind: no per-actor "model" flag exists in paneld today; BOTZZ_MODEL_RUN is a placeholder until B2's
`runs_model` is readable from options.db via the actor_effective view (Native Sync's schema, X43). Until then every deploy uses 400 MB.

### 2.3 Refusal messages (go to panel.resp; classify() tags them ERROR via "BLOCKED", l.32)
- `DEPLOY BLOCKED: <actor> — GATE MEM 312MB < 400MB | swap 900/4096MB (21%)`
- `DEPLOY BLOCKED: <actor> — GATE SWAP 86% > 80% | mem 520MB`
- `DEPLOY BLOCKED: <actor> — GATE ERR meminfo unreadable`
- `DEPLOY BLOCKED: <actor> — gate timeout/err (rc=124)`
Nothing is killed automatically; the operator STOPs something or waits.

### 2.4 Replacing the 200 MB tick check (single gate)
```diff
-    if [ ! -f "$D/freeze/quiet" ] && [ "$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo)" -ge 200 ]; then
+    if [ ! -f "$D/freeze/quiet" ] && timeout 5 python3 "$BOTZZ_BIN/botzz-capacity" --gate tick >>"$BGLOG" 2>&1; then
```
- The tick now uses the same function and thresholds (400 MB / 80%), so there is one definition of "enough memory".
- Behavior change to accept: freeze-tick will skip between 200 and 400 MB where it ran before. Freeze-tick frees memory,
  so skipping it under pressure is the opposite of helpful. Open question for owner/Commander: keep `tick` kind with
  its own floor (BOTZZ_GATE_MEM_MB=200 for kind=tick) inside the single gate code. Recommendation: same code, tick floor
  200 (one function, two named floors) — the single gate is about one implementation, not one number.
- Tick gate failures go to background.log only (not panel.resp), as today.
- B8 exemptions: stop, status, cap, roles, home/back/dump and all reads never call the gate. Only `deploy)` and the tick do.

### 2.5 SwapTotal = 0
- No swap (zram off): the swap clause is skipped (avoids divide by zero) and only the MemAvailable floor applies.
  Message shows "swap n/a (SwapTotal=0)". Not treated as a failure.
- SwapFree > SwapTotal or missing keys (bad read): used clamps to ≥0 via `max(0, st-sf)`; missing
  MemAvailable reads as 0 → refused (fail closed).

## 3. bin/que fix (B9)
Problems in the code (70b7619):
- Paths hard-coded to /root/termux-ui-rish-kit/botzz/{queue,bin} (l.6-8): works only inside proot as root.
- `claim` (l.40-46) does load() then append() with no lock: two claimers both see the same open item and both claim it.
- append (l.22-23) has no lock; concurrent writers can interleave on long lines.
Proposed fix:
```python
ROOT = os.environ.get("BOTZZ_QUEUE_HOME", os.path.join(os.path.expanduser("~"), "botzz", "queue"))  # X23 ~/botzz/queue
Q, OUT = f"{ROOT}/items.jsonl", f"{ROOT}/outbox"        # OUT = $QH/outbox (data dir)
LOOP = os.environ.get("BOTZZ_LOOP", os.path.join(os.path.dirname(os.path.realpath(__file__)), "loop"))  # LOOP = script bin/loop next to que, not under $QH
import fcntl, contextlib
@contextlib.contextmanager
def locked():
    with open(Q + ".lock", "a") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX); yield
def append(e):                      # caller holds locked()
    with open(Q, "a") as f: f.write(json.dumps(e) + "\n"); f.flush(); os.fsync(f.fileno())
# claim: with locked(): items=load(); pick; append(claim)   -> check+write is atomic
# add/done/fail: with locked(): append(...)
# LOOP subprocess runs AFTER the lock is released (never hold the lock across the 20 s loop call)
```
- Migration: one-time copy of the existing /root/termux-ui-rish-kit/botzz/queue/items.jsonl to ~/botzz/queue/
  (owner/Commander step, not done here). Proot and Termux $HOME differ (/root vs /data/data/com.termux/files/home):
  every caller must point BOTZZ_QUEUE_HOME at the same Termux path, or two queues appear. Default = Termux ~/botzz/queue.
- Idempotent done/fail: refuse `done` on an id not in state claimed (prints "not claimed"), under the lock.

## 4. Test plan (on a box or throwaway Termux dir; never on the live phone without owner OK)
Gate (fake /proc/meminfo via an env override `BOTZZ_MEMINFO=<file>` added for tests only):
1. Avail 500, swap 1000/4096 → rc 0, "GATE OK".  2. Avail 399 → rc 1 MEM.  3. Avail 400 → rc 0 (boundary inclusive).
4. Swap 3277/4096 (80.01%) → rc 2; 3276/4096 → rc 0.  5. SwapTotal 0 → rc 0 with "swap n/a".  6. Unreadable file → rc 3.
7. kind=model, avail 420 → rc 1.  8. `--gate` path makes no adb call (run with adb absent from PATH; still <1 s).
paneld (in a sandbox with D/ pointed at a temp dir, stub botzz-actor-loop):
9. deploy with gate rc 1/2/3/124 → "DEPLOY BLOCKED: …" in panel.resp, no child spawned, CUR_PID empty.
10. deploy with rc 0 → spawns as before.  11. stop/status/cap while gate would fail → still work (B8).
12. Owner-gated actor without BOTZZ_OWNER_OK → still blocked by owner gate first (message unchanged).
13. Tick: gate fail → no freeze-tick, line in background.log, nothing in panel.resp.
que (temp BOTZZ_QUEUE_HOME):
14. 20 parallel `que claim` against 5 open items → exactly 5 distinct claims, 15 "queue empty".
15. add/list/done/fail round trip; done on unclaimed id → "not claimed".  16. No /root path used (strace or grep).
17. Old items.jsonl copied in → list output identical to before.

## 5. Not in scope
Process-group stop and heartbeat (Commander), screen lock (ADB UI), per-actor max_mem_mb admission (needs B2 options in options.db, actor_effective view).

## Objection to Fleet Captain (one)
B9 "atomic claim via mv" contradicts the code: bin/que is a single append-only items.jsonl with no per-task files to mv.
Proposed: atomic claim = flock around load+append (same guarantee, no format change); mv only applies if the queue is redesigned.

## Rev 2 addendum (Fleet Captain, 2026-11-02 22:38 CT)
- B13 is adopted: claiming is a flock-locked read-and-claim on items.jsonl. No mv.
- bin/que at 70b7619 (sha256 f16345e0…) verified by me (see header). It hard-codes Q, OUT and LOOP at lines 6-8. Same as §3:
  - Q becomes `$QH/items.jsonl`, with QH=`${BOTZZ_QUEUE_HOME:-$HOME/botzz/queue}`
  - OUT becomes `$QH/outbox`
  - LOOP stays a script: `${BOTZZ_LOOP:-<dir of que>/loop}` (bin/loop), not a data dir
- The tick stays at 200 MB through the same gate function unless the owner overrides it.
- The 450 MB model threshold waits on actor_effective.runs_model in options.db (Native Sync).

## Queue-file migration (owned by Lane D, design only)
1. Run this only with paneld stopped and no actor running. Take `flock $QH/.lock` for the whole migration.
2. Copy the old items.jsonl and outbox/ from the /root paths into $QH (bin/loop is a script and is not migrated) with `cp -a`. Do not move them; the originals stay as a rollback.
3. Verify the copy: the line count and sha256 of items.jsonl must match the original, and the file count in outbox/ must match.
4. Leave a `MIGRATED-<date>` marker next to the old paths. Delete nothing.
5. Rollback is a single step: unset or point BOTZZ_QUEUE_HOME back to the old paths.
6. Nothing in this migration runs until the owner OKs it in Fleet Captain's chat.
