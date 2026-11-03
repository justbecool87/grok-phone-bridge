# BOTZZ Lane A: Termux Commander design, rev 7 (paneld `set`+tools, Conversation tab, focus fix, cursor)
DESIGN ONLY. Nothing was built, committed or restarted.
**Sources:** audit `fleet-audit/botzz-floaty-review-2026-11-02.md` (cited as A:line). Local snapshot `/tmp/bz/botzz/` (**hash-matched to 70b7619**, Fleet Audit pass 2; S:238). Line refs are to the snapshot (P = `bin/botzz-paneld`, J = `panel.js`).
**Paths:** `~/.botzz/` (mode 700) holds private keys only (owner.hmac, cursor.key). `~/botzz/` holds shared state (bus, locks, options, hb, audit). Both are in Termux private storage; /sdcard gets only read mirrors.

## Facts that constrain the design
- Transport is `panel.out`→paneld and `panel.resp`→panel, as JSON lines `{"ev":"cmd","cmd","actor"}` (P:18, P:153-160). There is no `set` in `run_cmd` (P:79-145, A:18).
- The JSON is parsed with `sed` (P:156-157), so values containing `"` break it.
- `actors.json` is regenerated from fleet.db at boot (P:56-59, A:22). Options must persist in fleet.db, not in the JSON.
- paneld truncates `panel.resp` on start (P:62), so the panel's offset has to tolerate a shrinking file.
- The panel is an AutoJS `floaty.rawWindow` (J:27), **not a WebView**. It has no focus code (A:26), and the input is `cmdin` (J:54).

## 1) paneld `set` handler
**Request (rev 7):** `{"ev":"set","id":"<uuid>","actor":"<id>","kv":{"<k>":<scalar>,…},"ts":<ms>}`, applied all-or-nothing. This is a new ev type, not a `cmd` string (A:47).
- **Parsing:** use `python3 -c` with json (already a paneld dependency, P:57), with a 2 s timeout. Don't use sed.
- **Validation:** `actor` must be in actors.json. `k` must be in the allowlist: `interval_s` (int 30-3600), `model` (string ≤64 chars, `[A-Za-z0-9._/:-]`), `max_mem_mb` (int **MB**, 15-150, default 30; rev 7), `autostart` (bool), `verbose` (bool). `tools` goes through the tiered rule below. Reject `owner_ok*`, `gated`, `caps` and any `*key*`/`*token*`. The owner gate stays the env flag (P:21, P:121).
- **tools (PROPOSED; X42/X45, B12 S:252):** inside `kv`, as `tools_add:[..]` and `tools_del:[..]` deltas, never a full list. paneld exports the tier table as one `TIERS {json}` line on panel.resp at start and on change. The floaty ships no bundled copy. Tiers (spec:219-228): OPEN = bus, que, web, opencode, adb-read, gh-read, rish-read. GATED = cursor, adb-input, ssh, gh-push/pr, rish-write.
  - `tools_del`: always allowed → `ok`/`noop`. Del of a name not in TIERS → `noop`; add of a name not in TIERS → `gated` (fail closed, O:112). [Captain pass-5 fix]
  - `tools_add` OPEN: allowed from panel.out.
  - `add` GATED: allowed only from a line in `bus.jsonl` (or a rotated `bus.<gen>.jsonl`) written by the Termux helper `botzz-bus-append`, with `from:"owner"`, `kind:"approve"`, scope `tools.add:<actor>:<tool>` (spec:90, 233). A `panel.out` request for a gated tool always gets `gated` (any app can write /sdcard, spec:231).
  - **Verify:** `sig = HMAC-SHA256(key, canonical_json(line minus sig))`, hex. The key lives at `~/.botzz/owner.hmac`, mode 600, Termux private storage (X40). Compare with a constant-time `hmac.compare_digest`.
  - **Replay:** reject if `|now-ts| > 300 s`, or the approval's `exp` has passed (spec:90), or the `req_id` is already in the ledger. A failure acks `gated` and logs `result:"sig_bad|replay|expired"`.
- **Audit ledger (spec:158, 234 name it but give no path):** proposed `~/botzz/audit/tools.jsonl`, append-only under `flock`, mirrored to Grok-Keep. Fields `{ts, actor, op, tool, tier, before, after, source:"panel|owner-bus", req_id, signer:"owner|none", result}`. `before`/`after` are tool-name lists only, never values or secrets. Rejected attempts are logged too.
- **Store (PROPOSED; schema owner Native Sync, S:254):** `options.db` table `actor_options(actor_id,k,v,updated_ts, PRIMARY KEY(actor_id,k))`, written in one sqlite transaction. A projection `~/botzz/options/<actor_id>.json` is written via tmp+mv.
- **Idempotency (PROPOSED):** table `option_requests(req_id TEXT PRIMARY KEY, actor_id, ts, code)`, inserted in the same transaction. A replayed `req_id` returns its stored code and writes nothing. An unchanged value → `noop`.
- **Response (PROPOSED; S:252):** a text line on panel.resp (EXISTING channel, P:38): `SET <code> <actor> <id> [detail]`. code ∈ `ok|noop|bad_key|bad_json|bad_tools|gated|busy|io_err` (shared with Lane B). An unknown actor → `bad_key detail=unknown_actor`. An out-of-range or ill-typed value → `bad_json detail=<k>`. `busy` = `~/botzz/options.lock` flock timed out after 2 s.
- **Logs:** `background.log` gets `set actor=X k=Y code=Z` only, with no values; values may be model ids or URLs.
- **Bus:** after an `ok`, paneld calls `botzz-bus-append` (it never writes the bus itself, rev 7) with `{ts,id,from:"paneld",to:actor,thread:"cfg",kind:"set",text:"k changed"}`, also without the value. The actor re-reads its options file on that event.

## 2) panel.js Conversation tab
- **Tabs:** a `Dispatch` tab (current UI) and a `Conversation` tab, toggled with `setVisibility` the way `bMin` is (J:155-157). Only one tab is inflated, which keeps the window around 4 MB.
- **To: picker:** a spinner listing `all`, `user`, then actors whose heartbeat is newer than 10 minutes. paneld adds `hb_ts` from `state/<actor>.json` to actors.json, from `~/botzz/hb/<id>` (see §6), mirrored read-only to /sdcard for the panel. It refreshes every 60 s, not on every poll.
- **Send:** the panel writes `{"ev":"say","to","thread","text"}` to panel.out, and paneld forwards it via `botzz-bus-append` (the only bus writer, `~/botzz/bus.lock`, hop starting at 0).
- **Thread view:** filters by `thread` and keeps a 200-line ring buffer, trimming the oldest lines.
- **Polling, replacing seenLines (J:167-173):** every 800 ms the panel sends `{"ev":"read","off":N}`. paneld replies with `{"ev":"bus","off":M,"lines":[…]}` (max 64 KB), using the same `tail -c +N` idiom as P:152. If M < N, which happens after a truncate or rotation, the panel resets to 0 and dedupes by `id`. The same byte offset applies to `panel.resp` directly: `java.io.RandomAccessFile.seek(off)`, with a reset if the file length is smaller than off.
- **Hop limit:** paneld increments `hop` on each actor-to-actor relay and refuses anything over 4, writing `kind:"hop_limit"` and marking it ⚠ in the view.
- **Load (PROPOSED):** the panel is not an actor. Bus rotation is `bus.<gen>.jsonl` at 1 MB (S:84,198), done by botzz-bus-append. `read`, `stop`, `status` are exempt from the 400 MB gate (B8 S:246); only `set` pauses (shown as "paused (mem)").

## 3) Input focus fix
- **Window:** the rawWindow starts not focusable, so it doesn't steal keys from the app underneath.
- **Helper:** a single `setFocusable(b)` that uses `ui.run` to set or clear `WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE` on the window params and then calls `updateViewLayout`. AutoJS `w.requestFocus()`/`w.disableFocus()` can serve as the implementation if they are present in this AutoJS build.
- **On tap:** a `cmdin` touch/click calls `setFocusable(true)`, then `cmdin.requestFocus()`, then `InputMethodManager.showSoftInput(cmdin, 0)` posted with a 100 ms delay.
- **On blur:** SEND, an outside touch (`FLAG_WATCH_OUTSIDE_TOUCH`), minimize (J:155) and close (J:160) each call `hideSoftInputFromWindow` and then `setFocusable(false)`.
- **WebView:** none exists, so no JS focus/blur events are needed. Optionally the panel sends `{"ev":"focus","on":bool}` to paneld for DEBUG logging only.

## 4) `cursor` integration (GATED, rev 6)
- **API (verified 2026-11-02, not called):** Cloud Agents API **v1** (public beta). `POST https://api.cursor.com/v1/agents` creates an agent plus its initial run. Body: `prompt.text`, optional `model`, `repos:[{url, startingRef}]`. Follow-ups: `POST /v1/agents/{id}/runs`. Status: `GET /v1/agents/{id}`, `GET /v1/agents/{id}/runs/{runId}` (or `/stream` SSE). Run status is CREATING/RUNNING/WAITING_FOR_BACKGROUND_WORK while active, then FINISHED/ERROR/CANCELLED/EXPIRED. A new run while one is active returns 409. Auth: Basic (`-u KEY:`) or `Authorization: Bearer KEY`. The key is a user key from Dashboard → API Keys. Legacy v0 `POST /v0/agents` takes `prompt.text`, `source.repository`, `source.ref`, `target.autoCreatePr` and is Basic only. Docs: https://cursor.com/docs/cloud-agent/api/endpoints, https://cursor.com/docs/api, https://cursor.com/docs/cloud-agent/api/v0
- **Flow:** the chip only *queues* the task. Each launch still needs a per-action owner OK (spec:229), because it spends Cursor usage.
- **Queue:** `~/botzz/queue/cursor.jsonl` `{task_id(uuid), ts, actor, repo, ref, prompt_sha256, state:queued|sent|done|err, agent_id, run_id}`. The prompt body lives in `queue/cursor/<task_id>.txt`. The task id makes the queue idempotent: a task with an `agent_id` is never re-POSTed. If it's unknown after a timeout, the drainer checks `GET /v1/agents` before retrying. Draining happens when the tunnel is green and memory is ≥400 MB, one task at a time. Polling runs every 60 s, backing off to 10 min, and stops at a terminal status.
- **Key:** the owner types it in Termux (`read -s`) into `~/.botzz/cursor.key`, mode 600. curl reads it via `--config` from a 600 file, so it never appears in argv or logs. The panel and the bus never see it; paneld logs only `key=present|absent`.

## 5) X44 decision
Resolved by rev 7: `max_mem_mb` is an **actor RSS cap in MB**, range 15-150, default 30. The "4 MB" figure is the panel window estimate. The 1-8 range is dropped.

## 6) Process-group stop + heartbeat (rev 7, newly owned)
- **Launch:** `setsid nohup bash botzz-actor-loop <a> &` (as P:124). Record `pgid=$(ps -o pgid= -p $!)` to `~/botzz/run/<a>.pgid` via tmp+mv.
- **Stop (B10 S:250):** TERM is sent only when all three agree: the recorded `~/botzz/run/<a>.pgid`, the pgid in `~/botzz/hb/<a>`, and `/proc/<pgid>/cmdline` containing `botzz-actor-loop <a>`. Otherwise it refuses with `stale_pgid` and kills nothing. Then `kill -TERM -$pgid`, poll `kill -0 -$pgid` for 5 s, then `kill -KILL -$pgid`. Never use pkill or name patterns. Remove the pgid file only after the group is gone. Stop is exempt from the memory gate.
- **Heartbeat:** the actor loop writes `~/botzz/hb/<a>` = `{"ts":<epoch s>,"pid":N,"pgid":N,"interval_s":60}` every 60 s (or interval_s if smaller), as `.tmp.$$` then `mv`. It is stale if `now-ts > 600` or `kill -0 pid` fails, and a stale entry is dropped from the To: picker. A heartbeat is never used as a reason to kill.

## 7) botzz-bus-append (PROPOSED; owned by Termux Commander, S:244)
- **Usage:** `botzz-bus-append --from A --to B --thread T --kind K [--hop N] [--sig HEX] < body`. It is the only writer of `~/botzz/bus.<gen>.jsonl`.
- **Build:** the line is built fully in python first (`json.dumps(..., separators=(',',':'))`), including `id` = ULID and `ts`. It validates the required fields `{ts,id,from,to,thread,kind,text,hop}` and rejects `hop>4` and any body matching key/token patterns.
- **Size:** a line must be under 4 KB. A larger body goes to `~/botzz/blobs/<id>.txt` and the line carries `blob:<id>`.
- **Write:** `exec 9>~/botzz/bus.lock; flock -x -w 5 9`, then one `write()` with O_APPEND. Rotation happens under the same lock: if size ≥1 MB, `mv bus.<gen>.jsonl` → gen+1 and write `~/botzz/bus.gen` via tmp+mv. It never truncates.
- **Mirror:** after the write, `cp` the current gen into `/sdcard/botzz/bus.mirror.jsonl.tmp`, then `mv` it. This is a read-only mirror for the floaty.
- **Owner lines:** `from:"owner"` needs `--sig`, checked as HMAC-SHA256 over the canonical line without sig, using a constant-time compare, with ts within ±300 s and a fresh id. The key `~/.botzz/owner.hmac` (600) **is not created until the owner OKs it**. Until then every owner line is rejected with exit 6.
- **Exit codes:** 0 ok, 2 bad_json/field, 3 too_big (blob failed), 4 hop_limit, 5 busy (lock), 6 sig_bad/no_key, 7 io_err.
- **Logs:** ids, kinds and exit codes only, never bodies or signatures.

## 8) actors.json builder and the 49-vs-47 count (EXISTING)
- **Builder:** `botzz/bin/botzz-actors-json`, called from P:57. It reads fleet.db `actors` read-only (l.13-23) and merges OpenCode `botzz-*.md` agent files (l.26-36). It drops ids matching `atx|captcha` (l.39), sets `gated` (l.10, 40), and writes with a plain `json.dump` (l.43), not tmp+mv. That's a small fix to hand Native Sync. **It does not read `botzz/actors/*.json`**, so those files don't feed actors.json.
- [SUPERSEDED by A:95] **Counts on the box:** `/tmp/bz/fleet.db` `actors` has 47 rows (fleet_actors 78). The only `botzz/actors/` dir on the box is the old clone `/tmp/BOTZZ` (main @27cf7e7), and it has **47** files, not 49. Set-diffing by id gives 42 exact matches. The other 5 differ only by prefix: the files `ui-tapper`, `ui-typer`, `ui-observer`, `ui-coordinator`, `captcha-solver` vs db `botzz-…` ids.
- [SUPERSEDED by A:95] **The 2 extras:** not determinable. The 49-file count is from 70b7619, and that tree's `botzz/actors/` isn't on the box. To settle it, someone needs `git ls-tree 70b7619 botzz/actors/` (or repo access) and to diff it against `select id from actors`.

## Limits
- One actor at a time (S:242, B3); paneld tracks a single `CUR_PID` (EXISTING, P:122).
- New code is roughly 0.5 MB (PROPOSED). The 400 MB floor applies to `set` only (B8 S:246).
- No Play Store freeze; the appops write stays unexecuted (A:54).

## Open questions
1. ~~Is `/tmp/bz` really 70b7619?~~ ANSWERED: hash-matched to 70b7619 (Fleet Audit pass 2; S:238).
2. ~~Who owns the options schema?~~ ANSWERED: Native Sync Review (S:208/B14).
3. ~~Heartbeat source?~~ ANSWERED: `~/botzz/hb/<actor>` (S:248).
4. ~~Panel writes the bus?~~ ANSWERED: no; botzz-bus-append is the single writer (S:244).
5. Does this AutoJS build expose `requestFocus`/`disableFocus` on rawWindow?
6. Who generates the owner HMAC key, and which of the three owner-OK schemes is picked (X36)?
7. Will the owner OK a Cursor API key, and which repos may the cursor chip target?
8. Should the ledger path go under ~/botzz/audit (Termux private) or /sdcard?


## One objection for Fleet Captain
The pgid stop rests on an assumption: `setsid` makes the actor a group leader. But on Android a PID/PGID can be reused after the group exits, so a stale `run/<a>.pgid` could signal an unrelated group. My guard is to TERM only when the pgid file, `hb.pgid` and `/proc/<pgid>/cmdline` (containing `botzz-actor-loop <a>`) all agree. Please adopt that 3-way check in the spec as well, not just in the design.

## §8 addendum (Fleet Captain, verified at 70b761908db5f8182b031df56c967fdcb4425057)
`git ls-tree 70b7619 botzz/actors/` lists 47 json files, matching 47 db rows; there are no extras at this commit (the "49" count came from elsewhere). PROPOSED: `botzz-actors-json` must map the 5 unprefixed files (ui-tapper, ui-typer, ui-observer, ui-coordinator, captcha-solver) to the db ids `botzz-<name>` by adding the `botzz-` prefix when a file id has no db match. Renaming the files instead is owner-gated and deferred.
