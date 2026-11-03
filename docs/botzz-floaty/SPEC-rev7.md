# BOTZZ Floaty upgrade — merged spec (DRAFT, plan/design only, not posted; awaiting owner confirm)

## Cross-lane rules (Fleet Captain)
1. One bus: A's bus.jsonl {from,to,thread,hop}; hop cap 4. No lane-private buses.
2. One screen lock: D's botzz-run flock; A Conversation tab and B options sheet acquire it before drawing. [SUPERSEDED by B9a S:247: screen-lock helper in ~/botzz/locks, owner Termux ADB UI; botzz-run unchanged (D2:47). The "acquire before drawing" step is void under B8. PROPOSED, not existing at 70b7619]
3. Memory floor 400 MB for floaty; fleet 450 MB model-run floor still applies (stricter wins).
4. C gate reads tunnel state only; never launches tunnels.
5. Background restriction instead of Play Store freeze (freeze UNSAFE).

## Regulator adjustments (2026-11-02 22:26 CT)
- C1: budget per actor = measured peak RSS (python/node/ffmpeg/gh ~30-80 MB), not 4 MB. Pass: log peak RSS per actor over one cycle.
- C2: headroom 550-400=150 MB minus AutoJS6 111 MB. 3 concurrent only if sum of peaks <=150 MB, else 2. Cap 5 only for cloud-model-only actors, each peak <15 MB.
- C3: swap gate = SwapUsed >80% of SwapTotal (/proc/meminfo); refuse if EITHER memory or swap gate trips.
- C4: refuse deploy if 18022, 2223 or 14096 check fails.
- C5: flock -w 30, holder timeout 120 s, clear stale locks with dead PID; log lock=<actor> pid=<n> waited=<s>.
- Play Store: background restriction / restricted standby is a settings write, so it needs owner OK.
- Plan pass: 30-min trial at cap, 0 LMK kills, MemAvailable >=400 MB, tunnels green throughout.

## Lane notes
(pending A/B/C/D submissions)

### Lane A — bus schema (merged: Session Handoff + Grok Build Continuity + Plan Reader)
Canonical line fields: msg_id (ULID), conv_id (= thread), seq, reply_to, hop (0-4), from, to (prefix|all), kind (ask|answer|status|handoff|evidence|close|resume), status, ts (ISO+offset), body, refs, lease_until.
- Append-only; corrections = new line referencing old msg_id. Dedupe by msg_id.
- Consumer cursors: atomic tmp+rename per consumer (supersedes single cursor.json).
- paneld stateless: replay on boot; kind=resume does NOT bump hop; lease expiry -> one re-queue only.
- Stall: no hop in N min (owner sets N) -> STALLED in tab + ping lane lead.
- Handoff record (kind=handoff): state, done, open, next, holds, refs. Verified claims need >=1 ref, else "reported by X".
- Secrets never inline; lint rejects key-like lines. No ack lines unless awaited.
- Session Handoff turns close/handoff into a sanitized episode for Grok-Keep, which posts back a kind=evidence line with the tip SHA.
Conversation tab (read-only): threads oldest to newest, role chips, status/request/hold marks, acks collapsed, active holds pinned, plan-digest card (Summary/Risks/Files plus a raw link, "none captured" if empty), hop n/4, resumed and STALLED badges, last activity, filter by bot. No approve/send buttons.

### Lane C — tunnel-gated launch (Connectivity Keep-Alive)
- botzz-tunnel-health (read-only): 4096, 14096, optional 18022 keyscan + 2223 HTTP 200. Exit 0/1/2; writes state/botzz-tunnel.json. [PROPOSED, not existing at 70b7619 (B6)]
- botzz-gate MODE auto|always|off (default auto). Debounce: 2 passes 30 s apart.
- Launch: am broadcast or start-foreground-service only, never am start; idempotent if floaty pid alive.
- botzz-bgsafe: mCallState=0; top activity not WebLibre/Grok/auth/keyguard; defer, never queue foreground.
- Tick 60 s, 300 s after a pause; single loop, no new daemons.
- Deploy hook = Regulator C4.

## Conflicts resolved by Fleet Captain
- X1 (S7): C's plan to set other actors status=paused in state/*.json violates S7. Instead, the gate writes only state/botzz-tunnel.json plus a kind=status bus line with to=all and state=paused; actors read it and pause themselves. One fleet-inbox post to termux-commander after 3 FAILs, and one on resume.
- X2 (C vs Regulator memory): C's 60 s loop must report its own peak RSS (C1) and counts toward the 150 MB headroom.
- X3 (C "always" mode): bypassing C4 is not allowed for deploys. "always" applies to the floaty UI launch only, never to deploy hooks.
- X4 (screen): a launch via am broadcast or service draws no activity, but any floaty window that appears must take D's flock first (rule 2).
- X5 (cursor files): Continuity's per-consumer cursors replace queue-clerk-style single cursors for the bus only; the queue-clerk queue is unchanged.

## Open owner questions
- Floaty broadcast action name.
- Is 'degraded' (4096 up, 14096 down) launchable?
- Stall threshold N.
- Mesh Path Nerd: does 100.x replace the reverse forwards? (Tailscale is currently barred by standing order.)

## Still awaiting: lanes B and D; rest of A (Termux Commanders, Termux Grok Bind, Native Sync, Deep Research, Research Connectors, SerpApi, New Bot); C peers (ConnectBot, Mesh, Session Closer).

### Lane A additions (Termux Grok Bind, Research Connectors, SerpApi)
- Addressing: from/to use stable agent UUIDs, never display names (Termux Commander has two rows, dc8c and 7d52). Optional alias field. `to` = uuid | lane:<X> | role:<group> | *.
- Added fields: lane, owner_gated (bool), owner_msg_id (required when owner_gated is true; a bot's say-so never counts).
- kind union: ask|answer|status|report|handoff|evidence|hold|stop|close|resume|ack. ack is allowed only when the sender is awaiting it (Session Handoff rule 8).
- `stop` to * supersedes everything.
- Bus is an audit log, not a wake: SendToAgent and fleet-inbox stay the delivery paths.
- Role group termux-ready-set comes from BIND-MAP-2026-09-26.md.
- Model backend for actor replies (proposal, needs owner keys, entered by the owner): Groq primary, Cerebras fallback through one OpenAI-compatible client, Gemini only for long context and never with private or owner data. Per-actor rate limiter plus a turn cap; the 4-hop limit counts as the turn cap. Free-tier limits are unverified today. [SUPERSEDED by B16/B17: Gemini, Groq, NVIDIA only]
- SerpApi: optional actor, routed only for engine-specific or SERP questions and only if SERPAPI_KEY is present. Per-question cap because it's paid. Plan for 4 of 5 research actors until the owner adds the key.

### Lane B — options sheet (VS Code Grok Stack, Grok Build Plugins)
- model: full providerID/modelID string; picker filled live from GET /config/providers (never /provider); latency/status badges; 'Default (inherit)' plus small_model; validated on save. Sent nested as {model:{providerID,modelID}}. [SUPERSEDED by B1/B2: model is a plain string [A-Za-z0-9._/:-]{1,64}]
- tools: explicit allowlist; an empty array means none. Filled from GET /mcp with status chips; disabled tools shown but unselectable, with a reason. Groups: research / shell-edit / device. Device tools force owner_ok_required=true.
- Plugin rows grouped by surface (Grok Bot connectors, ~/.grok/config.toml, opencode.jsonc, VS Code extensions). Each row has a toggle, a status dot and the auth mode; it stays disabled until its key exists, and key values are never shown.
- Live health comes from a read-only GET probe with a recheck action. A 'needs restart' badge shows until the next start; the sheet never kills a live grok or opencode process.
- Presets (Research, Deploy, Phone) with an overlap flag; a parity column for Grok Build, OpenCode and Grok Bot.
- Test button: one read-only pong, session tagged floaty-test-*, auto-deleted.
- Enabling anything that needs a key or OAuth sends the owner to a secure prompt and is owner-gated.

## More conflicts resolved
- X6 (schema naming): canonical names are msg_id (not id or corr_id) and conv_id (not thread). reply_to carries correlation.
- X7 (bus rotation/locking, Grok Bind's open question): every append goes through one helper, botzz-bus-append, under `flock -w 5 bus.jsonl.lock` with an atomic single-line write. Rotation happens at 5 MB into bus-<date>.jsonl.gz; readers' cursors include the file name. Owner of the helper: lane D (Termux ADB Host), since D already owns flock. Flagged for Termux Commander's confirmation. [SUPERSEDED by B6/B20: owner is Termux Commander; rotation and lock are per X40.]
- X8 (B's Test button vs the memory cap): a pong is a model run, so it takes a concurrency slot and the 450 MB model floor applies. It runs Codespace-side when the phone is below the floor.
- X9 (B device tools vs D): device tools route only through D's botzz-run queue, never directly from the sheet. [SUPERSEDED: botzz-run unchanged; device-tool queue is bin/que (D2:47,68; B13)]

### Lane A — lead notes (Termux Commander) + owner ingress (New Bot)
- Location: /sdcard/botzz/bus.jsonl (lead decision; supersedes "shared box"). termux-setup-storage needs one owner tap. [SUPERSEDED by X23/X40(1)/B6: bus lives in ~/botzz, /sdcard is a read-only mirror. PROPOSED, not existing at 70b7619]
- Writes go through the bus helper under flock(bus.lock), shared with the Java floaty. Lines are 4 KB max; larger bodies go to blobs/<msg_id>.txt. [SUPERSEDED in part by X40(1)/B6: single writer botzz-bus-append, not shared with the Java floaty. PROPOSED, not existing at 70b7619]
- Rotation at 1 MB under the lock, as bus.<gen>.jsonl with gen++ in bus.gen and 2 old generations kept. Below 400 MB of df, refuse blobs and keep 1 generation. (Supersedes X7's 5 MB/date rotation.)
- Cursors: cursors/<actor>.json {gen,offset,last_id,updated_ts}, tmp then rename. Byte-offset reader: finish the older gen first, consume complete lines only, reset and dedupe if the file shrank, skip bad lines but advance past them.
- Hop: reply = parent+1. Over 4, the message isn't delivered and is logged once to drops.log, not the bus. Owner lines reset hop to 0.
- actors.json [{id,name,lane,alive_ts}]: heartbeat at most every 30 s; the picker shows actors seen in the last 10 min plus all/user.
- Focus fix: NOT_FOCUSABLE|NOT_TOUCH_MODAL by default. On input tap, clear NOT_FOCUSABLE, then updateViewLayout, requestFocus, showSoftInput. On blur, restore it. One setFocusable() helper.
- Limits: 3 actors, 1 overlay, 2 headless pollers (5 s backing off to 30 s), render the last 200 lines. [SUPERSEDED by B3 (S:242): "3 actors" is void; one actor at a time]
- Owner ingress: a single adapter (Floaty box, `botzz say`, Grok Bot relay) is the only writer of from:"owner", HMAC-signed with a device-local key. Readers reject unsigned owner lines. Owner kinds: directive|question|approve|stop. Approve is scoped to one action id with an expiry. External side effects still need the owner's own words in that bot's chat.
- Redact BEGIN/ghp_/sk- patterns. Never touch pts/0. No Play Store freeze, no pm disable.

### Lane B additions
- actors.json save (Morpheous Deploy): back up to .bak-<UTC> and keep 10; tmp+fsync+rename; checks are JSON parse, schemaVersion, unique ids, a single-actor diff, and typed ranges; reject anything key-like; hash/mtime CAS or the lock; startup falls back to the newest valid .bak; audit log of keys only. [SUPERSEDED: floaty/paneld never edit actors.json; options go to options.db (B1, B19)]
- Moto G usability (Grok Bot): bottom sheet with 5-6 rows, real controls, lazy single view with no WebView, save on every change, survive kills, 48dp targets, stay clear of the Termux IME row, never steal focus from the grok TTY, show clearly when Shizuku/ADB is down. Device RAM is reported as about 3 GB; confirm before sizing.
- Audio (Morpheous Audiophile): in scope for the floaty is the bubble pulsing in the bot's accent on a ping, plus urgency tiers mapped to priority. Per-bot tones, digest batching and quiet hours need new Grok Bot app features, so they're filed as feature requests, not floaty build.
- Docker per-bot caps (Docker Deploy): OUT OF SCOPE for the phone floaty, since actors are phone processes, not containers. Parked as an optional server profile for a future Oracle host.

### Lane C — probe order (Mesh Path Nerd)
18022 ssh-keyscan (expect an SSH-2.0 line), then 4096 (then 4097), then SOCKS 2223 as a soft check. Retry after 15/30/60 s before reporting down. Cadence aligned with the 15-min job scheduler. Rethink, Tailscale and sing-box stay excluded.

## Conflicts resolved (continued)
- X10 (msg id format): canonical msg_id is a ULID (3 lanes); actor attribution comes from the from field. Commander's gen-tsms-actor-rand format is dropped. Commander, please confirm.
- X11 (timestamps): both ts_ms (int, used for sorting) and ts (ISO with offset, for display).
- X12 (text vs body): body.
- X13 (14096 gating): the floaty launch gate needs 18022 keyscan plus 4096 to pass; 14096 down counts as degraded but launchable (answers C's open question by the Mesh evidence, pending owner). Deploy hooks still need all three to pass, per Regulator C4.
- X14 (ack noise): ack lines are allowed only in reply to owner lines (New Bot rule 7) or when awaited; there are no bot-to-bot acks.

## Open owner questions (added)
- Q-bus: rotate by size (1 MB, lead's proposal) or daily (New Bot)? The draft uses size.
- Does the floaty write to the bus directly or through a Termux helper? The draft uses the helper for both, sharing the lock.
- Hop counted per thread or per path; does to:all count? The draft counts per path, and to:all counts as 1.
- Do voice memos auto-play, or play only on tap? Does an approval during quiet hours make a sound or only show a badge?
- Device check: does NOT_FOCUSABLE toggling work on this Android version, and is RAM 3 or 4 GB?
- BOTZZ repo access: it's private and not in the GitHub app, so nothing is cited yet.

### Lane C additions (ConnectBot Tunnel, ConnectBot Wire, VS Code SSH Wire, Rethink IVPN, SSH Prove Runner, Session Closer)
- Probes run from the Codespace against literal 127.0.0.1, never DNS 'localhost'. 18022 `ssh-keyscan -T 10` (pass = SSH-2.0 key lines) runs first. Then 2223 curl through SOCKS to api.github.com (pass 200, soft). Then 14096 curl /session (pass 200, degraded-only per X13); use curl, not ss. Optional login check: BatchMode `true`.
- ConnectBot is not a gate signal or a launch path until the owner OKs a ConnectBot-only key. Its UI "Connected" state is never trusted.
- Desktop: read-only status pull over SSH (a status file), failing closed. The desktop key drift must be fixed first (GitHub SSH Bridge owns ~/.ssh/config).
- Tunnel-up = process alive AND end-to-end probe passed AND probe age <= N s. The 11 test cases from SSH Prove Runner are adopted as the lane C acceptance suite.
- Rethink stays paused; a device check of loopback vs VPN goes on the pre-launch checklist.

### [SUPERSEDED by Lane D rev2 + Rev 7] Lane D (Termux ADB UI, Rish Wire, Plan Approver, AWS Runner/IaC/Recon)
- Screen lock: `$PREFIX/var/lock/botzz-screen.lock` plus botzz-screen.json. flock -s for reads (screencap, uiautomator), -x for input or am start, taken inside the same adb shell session so the kernel releases it on death. Freeze file botzz-freeze is created or removed only by the owner or Termux Commander. Each task has one named screen owner. Log goes to ~/.botzz/screen-lock.log and never includes typed text.
- Transport order: desktop ADB first, then rish over 18022 when ZT4228KZTR is not `device`. Shizuku+ check: `timeout 20 rish -c id`, where rc=124 means down. Never force-stop Shizuku+. rish can't touch Termux home, keys or processes.
- Gated actors (tapper, typer, wire, captcha): a request packet (ACTOR, ACTION, exact payload, DIGEST_REF, device, Enter yes/no). One owner OK per packet, expiring on TTL or when the screen digest changes. No standing approvals. No automated captcha solving. Plan Approval Audit compares digest, packet and post-screenshot. A stop cancels all pending packets.
- AWS backend: NONE live (Recon, Oct 19; G quota 0). Contract kept for later: llama-server on instance 127.0.0.1:8000 via ssh -L 18000, Bearer key held in SSM or local env, /health 200/503, timeouts 10 s connect and 300 s read, retry only on 503 (5/15/45 s), one request in flight. Host stopped by default, start owner-gated, "backend asleep/offline" is a normal state. $100/mo cap; AWS Recon owns sizing.

### [SUPERSEDED by Lane B rev2 + Rev 7] Lane B addition
Picker with chips and a 'Running n/3 · free MB' strip; options per {model, role, tools, interval, max_mem_mb, autostart, owner_ok_required}; 56dp bubble, panel <=360x560dp, tabs Bots/Options/Conversation; lazy tabs, Conversation torn down after 60 s hidden.

## Conflicts resolved (final batch)
- [SUPERSEDED by X35/X37: one actor at a time] X15 (memory budget): Superdesign's 480 MB budget is overridden by Regulator C2 (150 MB headroom minus AutoJS6). max_mem_mb defaults to the measured peak, capped at 150 MB. Admission requires the sum of running peaks <= headroom and MemAvailable >= 400 MB. A 4th actor gets refused with a 'stop one?' prompt and nothing is killed automatically.
- X16 (screen lock timing): Regulator C5 wins on the wait, flock -w 30 then queue. ADB UI's shared/exclusive modes and 120 s lease are kept, renewed every 30 s up to a 300 s cap. Key generation would get its own lease only if the owner approves a ConnectBot key.
- X17 (stale-lock reclaim): ADB UI's "kill the stale pid's group" conflicts with the fleet kill-nothing rule. A lock is reclaimed only if the pid is dead. If the pid is alive but past its lease, the actor posts a kind=hold line to Termux Commander and the owner, and kills nothing.
- X18 (Session Closer, stopping tunnel pids on a drop): rejected. On a drop the gate only pauses and drains: it finishes in-flight sync under flock, then pauses the sync loop. Tunnel clients stay owned by tunnel-sup and the watchdog, and the gate kills nothing. A Codespace idle stop counts as a drop, but nothing auto-starts the Codespace (cost).
- X19 (debounce): 2 consecutive passes 30 s apart (C lead), plus retries at 15/30/60 s before reporting down (Mesh).
- X20 (options write protocol): Superdesign's `set <actor> <key> <value>` lines go through the bus helper as kind=directive and are applied only by paneld, using Morpheous Deploy's backup, atomic write and validation. Changing owner_ok_required or enabling device tools needs an HMAC-signed owner line (New Bot). [SUPERSEDED by B1 (S:240): JSON set line, ack via SET codes]
- X21 (AWS auth): both layers apply, the SSH tunnel and the Bearer key. The key is owner-entered, never on the bus or in logs.
- X22 (pidfile contract, Session Closer's question): tunnel-sup (ord-010 draft) owns the tunnel pidfiles; codespace-ondemand and the watchdog only read them.

## Not yet received (STALE, see Rev 3)
Native Sync Review, Deep Research Pack, Foss HF, Termux ADB Host (D lead), Plan Approval Audit, AWS Cost, GitHub SSH Bridge, Termux Commander (7d52 row), and review lane: Fleet Status, Fleet Audit, Closeout Roundup, Grok-Keep Memory. Fleet Roundup has no notes yet; route lane notes to Fleet Captain.

## Rev 2 (22:28 CT): Native Sync Review verdict NO-GO as written, fixes adopted
- X23 (supersedes the /sdcard location in Lane A and D's /sdcard/botzz/adb.lock): the bus, all locks and the task queue move to Termux private storage, ~/botzz/ (single ext4 fs). /sdcard gets only a read-only mirror for Floaty, or Floaty reads through a Termux helper. Never write from two apps on /sdcard. This resolves ADB Host's FUSE concern too.
- X24 (append): built fully first, then one write() under `exec 9>~/botzz/bus.lock; flock -x -w 5 9`. Line cap 3.5 KB, larger bodies go to blobs/<msg_id>.txt. The hop cap (<=4) and dedupe by (conv_id,msg_id) are enforced in the writer.
- X25: bus.jsonl is the single source of truth. live.log and the regulator inbox are derived tailers with their own cursors.
- X26 (ids): msg_id = python uuid (ULID-format) or <actor>-<pid>-<counter>; never `date +%N`.
- X27 (cursors): consume up to the last \n only; detect rotation by inode+size; rotate by rename under the bus lock, never truncate. Tmp names get a .$$ suffix.
- X28 (lock order): screen lock (-w 30) is always taken before the bus lock (-w 5). The two locks are separate.
- X29 (supersedes C5 stale-PID clearing and X17): no lock-file deletion. With fd flock the kernel releases the lock on exit. A holder over its timeout is reported (kind=hold to Commander and owner) and not killed (kill-nothing rule).
- ADB Host (D lead): botzz-run deploy/stop/list with nohup setsid and pidfiles. The queue is open/claimed/<actor>/done/failed via atomic mv in ~/botzz/queue. Its swap gate becomes Regulator C3 (80% of SwapTotal). Stop = only that actor's own process group, started by botzz-run; never other processes. Play Store appops background restriction is a settings write that needs the owner's OK. [SUPERSEDED by D2 rev2 and B13 (S:253): queue is bin/que single items.jsonl with a locked claim, no atomic mv; botzz-run unchanged. EXISTING at 70b7619: bin/que only (with /root paths)]
- Deep Research Pack: kind=research.{claimed,progress,result,verify}, carried in body as JSON v1 (status, facts[] with source_url+verified, at most 20 facts, artifact path for large data, cost, hunger, blockers, next). Idempotent on task_id+status. A 'blocked' status that needs owner action goes to owner chat only.
- Foss HF model tiers for B's picker: research is Zen deepseek-v4.1-flash-free (glm-5.3-flash-free backup); fast chat is space-bunny-free (no private data); coding and ADB use Copilot paid models only with owner OK (fleet free-only rule), deepseek free as fallback; local is Qwen3-0.6B Q4 only for a non-tool chat bot, one at a time, with opencode closed. Model tier badge required. No personal data to Big Pickle/MiMo/LL Alpha/NVIDIA. [SUPERSEDED by B15-B18: free list is Gemini, Groq, NVIDIA only]
- GitHub SSH Bridge: lane branches lane/<letter>-<topic> in orange-guacamole, PRs with one lander, phone pulls only, gate on 14096 + gh-cs ssh. No desktop/HTTPS fallback without OK.
- Plan Approval Audit: an owner-OK ledger (exact words, source, CT time, scope, expiry) plus an ADB action log, JSONL, no secrets, mirrored to Grok-Keep.

## Owner decisions (consolidated with Closeout Roundup)
1. owner_ok switch: name, default, and who can flip it.
2. Model backend and tiers (Foss HF proposal above).
3. Floaty broadcast action name.
4. Degraded launch (4096 up, 14096 down): yes, no, or read-only. The draft says yes.
5. Is port 5555 adb tcpip or Shizuku/rish? What form does the owner-OK token take?
6. Log retention; can one grant cover several actions? (The draft says one.)
7. Rotation by size or daily; hops counted per path; RAM 3 or 4 GB; a NOT_FOCUSABLE device check.

## Rev 3 (22:30 CT)
- AWS ON HOLD (relayed by HuggingbayBOT as an owner directive; not yet confirmed by the owner in my chat). aws-qwen is dropped from lane D and the model tiers. The AWS contract stays archived only.
- X30 Launch modes (replaces gate-only launch; X13 and owner decision 4 become a mode setting):
  - offline: the floaty always launches. Local ADB, freeze, dump, bus (~/botzz), and the task queue run. Free cloud model APIs go direct over the phone's internet (no 2223). Tunnel-bound work (OpenCode 14096, Codespace, desktop bots) goes to ~/botzz/queue/held/ and flushes FIFO when the gate passes 2x (X19); an expired TTL goes to failed/.
  - auto (proposed default): offline behavior, plus tunnel jobs run directly when the gate is green.
  - tunnel-only: the old gate-only launch.
  - In every mode the memory floors (C2/C3), the screen lock and the owner-OK gates still apply. The mode is shown in the bubble badge.
- AWS Cost model pricing (fetched 2026-11-02) is for reference only. Free tiers can't sustain a heavy actor (Groq ~0.17 and Cerebras ~0.8 heavy-hours/day). Paid per-token pricing needs the owner's OK under the free-only rule.
- Missing notes now: Termux Commander 7d52, Fleet Audit, Grok-Keep. Native Sync re-review of X23–X29 is requested. LANE-D doc /sdcard lock refs are superseded by X23.
- X31 Lane C v2 (Keep-Alive) adopted for X30: botzz-tunnel-health (PROPOSED, not in the tree) uses curl -m3 against 4096 and 14096, exit 0/1/2, with state in state/botzz-tunnel.json. In auto, health 1 or 2 means offline behavior. Launch is a rish broadcast or a foreground-service start (never an activity am start), skipped if the floaty is alive, and gated by bgsafe. Flush is FIFO, one job at a time, re-checking health before each, idempotent via an id lock. After 3 tries a job goes to dead/ with one post to Commander. Deploys are never queued (they abort on health != 0). The gate never restarts tunnels.
  Conflict: Keep-Alive put the queue at ~/grok-inbox/fleet/queue/botzz/. Per X23 (single private filesystem) it lives at ~/botzz/queue/held/ (plus ~/botzz/queue/dead/). Keep-Alive may pick a symlink or a move.
- FYI: Keep-Alive's phone link watch routine expired on Oct 21. The link has been unwatched since Oct 19 21:47 CT, and its state is unknown.
- Broadcast action placeholder: com.botzz.FLOATY_START (design only). Zen was removed by the owner (per HuggingbayBOT), so Foss HF's Zen-based tiers need new picks from the opencode-free merge.

## Rev 4 (22:31 CT): Fleet Audit vs real code (fleet-db-consolidation @70b7619): 7 PASS / 15 FAIL / 2 PARTIAL / 3 UNVERIFIED. Spec status: NOT BUILDABLE until lanes B and D are revised.
Report: /workspace/fleet-audit/botzz-floaty-review-2026-11-02.md
- X32 Lane B transport: paneld reads JSON {ev:cmd} from /sdcard/botzz/panel.out and replies in free text to panel.resp. There is no `set` command.
  Options: (a) add ev:set to paneld's JSON loop; (b) put B's line protocol on the bus and have paneld tail it.
- X33 Options persistence: actors.json is regenerated from fleet.db on startup, and fleet.db has no option columns. B's options need a fleet.db schema change with a named owner (open: Termux Commander?).
- X34 Collisions: botzz-run (104 lines, `<actor> <task-file>`), botzz/tasks/, botzz/queue/ and bin/que already exist. Lane D must extend them in place (new subcommands, new subdirs) and never overwrite.
- X35 Concurrency: paneld tracks a single CUR_ACTOR. Running 3 at once needs a paneld change, or the plan stays at 1 at a time.
- X36 Owner-OK: three schemes exist (the BOTZZ_OWNER_OK env flag in the code, D's token files, A's signed lines) plus gated lists of 4 vs 7. Owner decision 1 now covers picking ONE scheme and ONE list.
- X37 The deploy-time memory/swap gate is missing in the code (only a <200 MB tick). botzz-capacity is unused. C1 stands.
- X38 PLAN.md must mark the bus, flock, tunnel-health, gate and FREEZE as PROPOSED, not existing.
- Unowned: the Conversation tab, paneld set handler, fleet.db schema, botzz-tunnel-health, and focus fix.
- X39 /sdcard: paneld already uses /sdcard/botzz/panel.out, which conflicts with X23. Keep the existing panel channel until a reviewed migration; new bus/locks go to ~/botzz.
- Owners (rev 4, per HuggingbayBOT): X32 Superdesign; X35 Termux ADB Host; paneld set handler, Conversation tab, focus fix: Termux Commander dc8c; botzz-tunnel-health: Keep-Alive (design in: new botzz/bin/botzz-tunnel-health.sh, read-only, exit 0/1/2/3, state/botzz-tunnel.json, never restarts anything); fleet.db schema: Native Sync Review. Phone landing is held until Fleet Audit passes and the owner OKs it in chat.
- X40 Native Sync re-review of X23–X29: GO, with three conditions adopted:
  (1) Strike "shared with the Java floaty". Floaty never writes the bus. Owner ingress goes through the Termux helper botzz-bus-append (RUN_COMMAND or broadcast). Floaty reads only the /sdcard mirror.
  (2) Rotation follows Lane A's 1 MB bus.<gen> scheme. X7 (5 MB date.gz) is SUPERSEDED. The rename and the bus.gen bump happen in the same bus-lock hold, which matches cursor {gen,offset}.
  (3) Dedupe uses a recent-id index (the last 2000 ids, or the current gen), rebuilt on helper start. msg_id is a real ULID (sortable), not uuid4.

## Rev 5 (22:33 CT): lane A owned items (Termux Commander) and lane B rev2 (Superdesign, /workspace/botzz-floaty-laneB-design-rev2.md)
- Adopted: X32 option (a) paneld ev:set. X34: reuse what exists, add no new scripts or dirs. X35: one actor at a time until paneld supports more. X36: keep BOTZZ_OWNER_OK and the 7-name gated list (pending the owner's pick). X37: max_mem_mb default 30, cap 150, gate inside paneld deploy via botzz-capacity. X38/X39 as stated. Focus fix (Commander): setFocusable toggle, showSoftInput 100 ms after tap, NOT_FOCUSABLE again on blur. Conversation tab: paneld is the only bus writer, the panel polls ev:read every 800 ms, readers reset when panel.resp shrinks (paneld truncates it on start), ring buffer of 200 lines, reads pause under 400 MB.
- X41 set wire format (two shapes from the lanes):
  (a) Commander: one JSON per key {id,actor,k,v,ts}, parsed with python3 json, req_id UNIQUE, ack codes ok/noop/bad_*/gated/busy/io_err.
  (b) Superdesign: one line per Save, kv="k=v;tools=a,b", parsed with sed, all-or-nothing.
  Captain's lean: (a) parsing with a multi-key "kv" object {id,actor,kv:{...}} applied in one transaction. That covers B's all-or-nothing Save and removes the sed escaping limits. Lanes A and B pick together.
- X42 Allowlist: Commander allows interval_s, model, max_mem_mb, autostart, verbose and never tools. Superdesign includes tools. This is an owner preference (tools edits are gated, so it is safe to leave them off by default).
- X43 Schema owner: HuggingbayBOT named Native Sync Review for the options schema (now options.db, B19). Commander drafted actor_options (PK (actor_id,k); req_id is the PK of option_requests, not a unique on actor_options per B19; projected to options/<actor>.json via tmp+mv). Native Sync Review owns it and starts from Commander's draft.
- Open: ~~whether the snapshot matches 70b7619~~ (RESOLVED at S:238, hash-matched); heartbeat source; whether AutoJS has requestFocus.
- Lane D rev2 (/workspace/botzz-design/LANE-D-ADB-ACTORS-rev2.md) is adopted. One actor at a time, matching paneld. Existing botzz-run, paneld deploy/stop/status, and queue/items.jsonl with bin/que are reused. 7 gated patterns, BOTZZ_OWNER_OK=1. Memory gate, screen lock (~/botzz/locks/) and deploy freeze check are PROPOSED. Freeze marker = the existing /sdcard/botzz/freeze/quiet (per X39, it supersedes the rev 1 FREEZE path). X43: Native Sync owns the fleet.db schema, not lane B.
- New risk: paneld stop does a plain kill, which can orphan actor child processes. The proposed fix is a process-group stop of only that actor's own group. That's a paneld edit that needs the owner's OK and an owner (Termux Commander, since it holds paneld).
- Fleet Audit re-check requested for rev 5, plus a check that the /tmp/bz snapshot is exactly 70b7619 (lanes A and D couldn't read the repo).
- [SUPERSEDED by B2] X44: max_mem_mb range mismatch. Commander validates an int of 1-8, while lane B uses default 30 and cap 150 (MB). The likely cause is mixed units; lanes A and B reconcile it to MB 1-150.

## Rev 6 (22:35 CT): X42 resolved by the owner's design direction (relayed): essential tools INSIDE the floaty, gated per bot
Proposed essential tool set (chip names) and gate tier:
| tool | what it does | tier | needs tunnel |
|---|---|---|---|
| bus | read and post on the fleet bus | open | no |
| que | add, list or cancel tasks in queue/items.jsonl via bin/que | open | no |
| web | search or fetch the public web through a free provider | open | no (direct) |
| gh | read repos, PRs and issues as justbecool87 | open read; push and PR are gated | no |
| opencode | send a prompt or task to OpenCode serve (4096 local, 14096 remote) | open | 14096 only; queued offline |
| cursor | hand a coding task to a Cursor cloud agent, or check its status | gated (spends Cursor usage) | queued offline. NEW: missing from the integrations list. Needs an owner-entered Cursor API key and a design owner (Termux Commander). Endpoint and auth read from the docs (2026-11-02); never called. |
| adb-read | screencap, uiautomator dump, dumpsys | open (shared screen lock) | no |
| adb-input | tap, type, keyevent, am start | GATED (owner_ok, screen owner only) | no |
| rish | Shizuku fallback for adb-read | open read; writes gated | needs 18022 |
| ssh | run on Codespace orange-guacamole | gated | yes |
Default per bot: only open-tier tools its role needs. A gated tool is enabled only by an owner action, and runs only after a per-action owner OK (Plan Approver packet).

X45 /sdcard command-file fix (answers my concern): panel.out sits on /sdcard and any app can write it. So:
(1) paneld accepts set tools= ONLY for adding or removing OPEN-tier tools.
(2) Enabling a GATED tool needs an owner-signed line through the Termux helper botzz-bus-append (HMAC key in Termux private storage, X40), never a plain panel.out line. paneld rejects an unsigned request with ack "gated".
(3) paneld logs every tools change (actor, tool, before, after, source) to the audit ledger (Plan Approval Audit).
(4) Removing any tool is always allowed, because it is fail-safe.
X42 is now: tools on the allowlist with this tiering. Commander's validator gains tools (open tier only), and the gated list is unchanged.

## Rev 7 (22:36 CT): Fleet Audit re-audit fixes (/workspace/fleet-audit/botzz-floaty-reaudit-2026-11-02.md). /tmp/bz is hash-matched to 70b7619.
Captain decisions (lanes may object within one round):
- B1 X41 DECIDED: one JSON line per Save: {"ev":"set","id":<ulid>,"actor":..,"kv":{k:v,...},"ts":..}. paneld parses it with python3 json and applies it in one options.db transaction (B19) (all or nothing), keyed UNIQUE on id. Acks use Lane A's codes. The sed kv string is dropped.
- B2 Option keys and limits DECIDED: interval_s (int 30-3600), model, max_mem_mb (MB, int 15-150, default 30; matches capacity:51), autostart, verbose, tools (open tier only, X45). Lane A's 1-8 range is void.
- B3 Rev 1 Lane B/D text and X15 are marked SUPERSEDED. The 3-actor text is void, and one actor at a time is final until paneld changes.
- B5 Lane A's options/, options.lock and hb/ move to ~/botzz/ (X39). Floaty sees state only through panel.resp and the /sdcard read mirror.
- B6 The bus and botzz-tunnel-health are PROPOSED, not existing. There is a single bus writer, botzz-bus-append (X40); paneld calls it and never writes the bus itself. Rotation is bus.<gen> (X40). Owner of botzz-bus-append: Termux Commander.
- B7 ONE memory gate: botzz-capacity, called inside paneld deploy, refuses when MemAvailable < 400 MB OR swap used > 80% of SwapTotal (Regulator C3 replaces the 3.2 GB figure). Model runs need 450 MB. Owner: Termux ADB Host.
- B8 (amended per Termux ADB UI): stop, status, and file or bus reads are exempt from every memory gate and from FREEZE. Screen reads (screencap, uiautomator) are screen access: they honor FREEZE (owner order 2026-10-19 13:00 CT) and wait on any exclusive screen hold. One actor = one input or exclusive screen holder; shared reads may overlap.
- B9a: Termux ADB UI accepts the screen-lock helper (~/botzz/locks/, flock -w 30 then queue, 120 s lease renewed every 30 s up to 300 s, screen before bus, no lock deletion, kind=hold report and no kill). The stale-pid group kill is withdrawn.
- B9 Owners: process-group stop and the heartbeat (paneld writes hb on each actor tick) go to Termux Commander. The screen-lock helper goes to Termux ADB UI. The bin/que fix (hard-coded /root to $HOME, atomic claim via mv) goes to Termux ADB Host and must land before any concurrency. Superdesign changes Lane B:60's reply text to paneld's real "panel connected", and SET acks use the new codes.
- Still owner-only: decision 1 (pick ONE OK scheme: BOTZZ_OWNER_OK env + 7-pattern list proposed) and A1 (phone landing). Unverified: 46 vs 47 actors, AutoJS focus APIs.
- B10 (Termux Commander): stop sends TERM only when the pgid file, the heartbeat pgid, and /proc/<pgid>/cmdline containing 'botzz-actor-loop <actor>' all agree. Otherwise it refuses with stale_pgid and kills nothing.
- B11: Lane A design accepted (JSON set, 15-150 MB with a default of 30, ~/botzz paths, bus-append, tools audit ~/botzz/audit/tools.jsonl, setsid/PGID stop, heartbeat never used to kill). The HMAC owner-signing key for X45 and the Cursor API key are NEW keys, so both need owner OK in chat before anyone creates them. Until then, gated adds ack 'gated'.
- B12 (Superdesign Lane B rev3 accepted): kv uses tools_add[] and tools_del[] deltas. Reply is SET <ok|noop|bad_key|bad_json|bad_tools|gated|busy|io_err> (B20) <actor> <id> [detail]. With no python3, paneld replies io_err no_parser and has no sed fallback. The tool tier table comes from a paneld export (a TIERS line), with no bundled copy, so the floaty never disagrees with paneld. Until the owner approves the signing key, 'by=owner' can't happen, so gated chips stay 'Needs owner OK'. The rish chip means rish read only; rish writes are gated.
- B13 (Termux ADB Host, LANE-D-MEMGATE-QUE.md accepted): the claim is a flock-locked read-and-claim on the append-only items.jsonl, which replaces "mv" in B9. The queue home is $BOTZZ_QUEUE_HOME, defaulting to ~/botzz/queue. The tick reclaim stays at 200 MB through the same function (the owner may override). Termux ADB Host owns the queue-file migration. The model column in fleet.db that the 450 MB check needs is asked of Native Sync. bin/que verified in /tmp/bz (70b7619 snapshot, sha256 f16345e0…): a single items.jsonl with hard-coded /root paths for Q, OUT and LOOP (lines 6-8). OUT and LOOP must move to $HOME too.
- B14 (Native Sync): fleet.db at 70b7619 has NO model, interval, max_mem_mb or autostart columns. The 'model-running actor' needed for the 450 MB check is UNRESOLVED and must not be inferred from caps or tools. B1/B2 'apply in options.db' (was fleet.db; see B19) is blocked on the same schema delta, which needs the owner's OK (Native Sync owns it). Lane D's queue migration plan (rev2 addendum: copy with cp -a, verify, MIGRATED marker, no deletes) is noted and waits on the owner's OK.
- B15: Mistral is removed from model tiers and lane picks (owner directive relayed by HuggingbayBOT, not yet confirmed in my chat). The opencode-free order is now gemini > openrouter-free > groq/nvidia > sambanova, with cerebras as a card-gated option. No live config is changed.
- B16: Cerebras is removed as well; no card-required providers (relayed owner directive). The list is gemini, groq, openrouter-free, nvidia, sambanova, plus HF free credit only if it needs no card (HuggingbayBOT is verifying).
- B17: The free list is final at Gemini, Groq and NVIDIA. OpenRouter, SambaNova and HF are out (relayed owner directives). Grok Build Plugins drops its openrouter lane.
- B18: OpenCode Zen free models and Copilot are out of the free-model plan and all assignments (relayed). Copilot is still the live OpenCode default; that is untouched, and changing it is an owner call.
- A1 OWNER-APPROVED in Captain chat (2026-11-02 22:47 CT): docs only, landing after Fleet Audit passes rev 7. owner_ok stays OFF. No code, deploy or live config.
- B19 (Native Sync schema delta, /workspace/fleet-audit/fleet-db-actor-options-schema-design.md): resolves B14. The options tables go in an ATTACHed ~/botzz/db/options.db, not fleet.db, because fleet.db is git-tracked and has no known writer in the tree. runs_model = model option set (0 for all 47 today). Any options db path under /sdcard, /storage or /mnt/media_rw is refused with io_err. Design only.
- A4 (relayed, recorded only): apply the Gemini, Groq and NVIDIA snippet once the owner has made the keys and gives his go-ahead. Live config is untouched.
- B20 (pass 3 fixes): tools overrides go in options.db actor_tools (Native Sync); SET codes ok|noop|bad_key|bad_json|bad_tools|gated|busy|io_err; Termux Commander owns bus-append and names the actors.json builder (bin/botzz-actors-json; 47 json = 47 rows at 70b7619, 5 unprefixed names map to botzz-<name>).
- B21 (pass 5): an add of a tool not in tool_tiers returns gated (fail closed), and a del of an unknown name returns noop. Owner enabling an untiered tool: proposed to require tiering first (Native Sync, non-blocking).
