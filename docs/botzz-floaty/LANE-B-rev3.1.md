# BOTZZ Floaty — Lane B design rev3.1 (Fleet Audit pass 3 fixes; spec Rev 7+) (options sheet: tiered tools, Cursor, X44) — DESIGN ONLY
2026-11-02 ~22:40 CT. Builds on rev2 (/workspace/botzz-floaty-laneB-design-rev2.md). rev3 §1 REPLACES rev2 §3 (wire format, acks, `caps: set`, `txn`) and the rev2 §6 X32 row; rev3 §2/§3 replace rev2 §2. rev2 §1/§4/§5 stay as context.
Status labels: EXISTING = in repo @70b7619; PROPOSED = design only (paneld ev:set handler, SET acks, TIERS line, CURSOR line, options.db, botzz-bus-append, signing key).
Inputs: merged-spec-draft.md Rev 5 (X41–X44) and Rev 6 (tool tier table, X45); fleet-audit/botzz-lanea-termux-commander-design.md:15;
fleet-audit/botzz-floaty-reaudit-2026-11-02.md:60 (C2). Repo facts unchanged from rev2 (@70b7619). Nothing built.

## 1. Wire format (X41 / Rev 7 B1, DECIDED)
One JSON line per Save appended to /sdcard/botzz/panel.out via the existing panel.js `send()`; `kv` is a JSON **object**:
```
{"ev":"set","id":"01JBX…ULID","actor":"botzz-que","ts":1730608800000,
 "kv":{"model":"…","interval_s":300,"max_mem_mb":30,"autostart":false,"verbose":false,
       "tools_add":["web"],"tools_del":["ssh"]}}
```
- Field name is `id` (ULID, UNIQUE in options.db actor_options per B1/X43/B19). The parent's example used `txn`; rev3 uses `id` to match Rev 7 B1. `txn` is not sent.
- Values are native JSON types (int, bool, string, string arrays). No `;`/`=` escaping rules; the rev2 sed `kv` string is dropped.
- paneld: python3 `json.loads` on the line, allowlist check, one transaction on ~/botzz/db/options.db, ATTACHed by paneld (B19; fleet.db is never written), dedupe on `id`.
- Tools: `tools_add` / `tools_del` arrays (delta form), never a full `tools` list, so removal is explicit and fail-safe (X45(4)).
  If Captain insists on `"tools":[..]` (full list), paneld must diff against current state and treat any gated tool newly in the list as a request (`gated`).
- Acks (PROPOSED, one text line in panel.resp): `SET <code> <actor> <id> [detail]`. One code list shared with Lane A; no `bad_<key>` templating (the key goes in detail):
| code | meaning | floaty UI |
|---|---|---|
| ok | applied in one options.db transaction | fields ✓, chips → on/off as sent, reload options snapshot |
| noop | valid, nothing changed (dup id or same value) | same as ok, no reload |
| bad_json | line not parseable JSON / wrong types / missing id·actor·kv | whole Save reverted, banner "panel sent a malformed request (bug)", log locally; never auto-resend |
| bad_key | key not on allowlist; detail = key | that field reverted + inline error; rest of Save not applied (all-or-nothing) |
| bad_key detail=bad_value | out of range / regex fail (field key also in detail) | that field red with the range hint; Save not applied |
| bad_key detail=unknown_actor | actor not in actors.json/options.db | whole Save reverts; banner 'actor unknown, refresh list'; picker reloads |

Unified code set: ok, noop, bad_key, bad_json, bad_tools, gated, busy, io_err. There is no separate bad_value code; the UI branches on the bad_key detail.
| bad_tools | a name in both add and del, or non-array | tools section reverted to last ack'd state, offending chip red with detail |
| gated | gated tool add, add of a tool name not in TIERS (fail closed), or gated key: recorded as pending, not applied; detail `await_owner` | chip → "Needs owner OK" (§2.3) |
| busy | paneld locked/applying | one retry after 2 s with same id, then revert + "busy" |
| io_err | db/path error (incl. options db under /sdcard → refused) | revert + "paneld storage error"; removals stay red "not confirmed" (§2.4) |
- Floaty only writes panel.out (X39, B5); it never writes the bus (B6).

### 1.1 Fix to rev2 line 60 (Rev 7 B9)
rev2 said "on console_launch, paneld v3 replies `caps: set`". Wrong: paneld:162 replies the literal text **`panel connected`** (classified DEBUG, so it
reaches panel.resp only when verbose.on exists). Revised rule: the floaty does NOT gate Save on a console_launch reply. Save is enabled; if the first
ev:set gets no `SET …` line within 5 s, the floaty shows "paneld has no set handler (old version?)" and keeps edits unsent locally (in memory only).

### 1.2 Parser risk (sed vs nested object)
- Today paneld extracts `cmd`/`actor` with `sed 's/.*"cmd":"\([^"]*\)".*/'` (paneld:156-157). That cannot parse a nested `kv` object. Real risk if the handler copied the sed pattern.
- jq: not in Termux base; it is `pkg install jq`, and no BOTZZ script at 70b7619 uses it (not verified on device). Unverified dependency.
- python3: already a hard dependency of paneld (paneld:57-58 runs botzz-actors-json and json.load; `roles` uses an inline python heredoc). So B1's python3 json choice adds **no new dependency**.
- Note: paneld's dispatch `case *'"ev":"cmd"'*` is substring-based. JSON from `JSON.stringify` has no spaces, so `*'"ev":"set"'*` matches. But a `"ev":"cmd"` string inside a kv value (e.g. a model name) could misroute. Mitigation: the set handler runs before the cmd arm and re-checks `ev` after json.loads.
- Verdict: no objection to the nested object as long as it is parsed with python3, not sed or jq. Concern text for Fleet Captain is in §7.

## 2. Tools: chips in two groups (Rev 6 table)
Options tab → "Tools" section, two labelled groups. Each chip = name + tunnel tag + state.
| chip | group | tunnel tag shown on chip | notes |
|---|---|---|---|
| bus | Open | — | |
| que | Open | — | via bin/que |
| web | Open | direct | |
| gh | Open (read) | — | push/PR gated as actions, not as a chip; chip tooltip says "push/PR need per-action owner OK" |
| opencode | Open | ⇄14096 (remote) · local 4096 none | greyed/"queued" when 14096 down and target=remote |
| adb-read | Open | — | uses shared screen lock |
| rish | Open — **rish read-only** (chip = read only; no rish write chip exists) | ⇄18022 | rish writes are not offered in the floaty |
| adb-input | **Gated 🔒** | — | owner_ok + screen owner only |
| ssh | **Gated 🔒** | ⇄ required | Codespace orange-guacamole |
| cursor | **Gated 🔒** | queued offline | new; see §4 |
- Group order: Open first (enabled chips filled, available ones outlined), then Gated with lock icon on every chip regardless of state.
- Default per bot: only open-tier tools its role needs (pre-ticked from actors.tools/caps); no gated chip on by default.
- Tier table comes ONLY from the paneld TIERS export (B12; PROPOSED, owner Termux Commander): a `TIERS <json>` line in panel.resp on `status`/panel open, cached in memory for the session. No bundled copy. Until a TIERS line arrives, the Tools section shows "tiers unavailable" and all chips are read-only (removal still allowed via `tools_del`). Unknown tool → Gated.

### 2.1 Chip states
`off` → `on` (open) · `off` → `pending` → `on` | `off` (gated) · `on` → `off` (any, instant) · overlay `unavailable` (greyed, §4).

### 2.2 Adding an Open chip
Chip goes `saving…` (spinner ring), sent in next Save as `tools_add`; on `SET ok`/`noop` → `on`; on `bad_tools`/`io_err` → revert to off + inline error; no ack in 5 s → revert + "paneld not responding".

### 2.3 Adding a Gated chip → "Needs owner OK"
- Floaty sends an ev:set with `tools_add:["cursor"]` as a **request** (sent immediately, own `id`, not batched).
- Per X45(2) paneld will never enable a gated tool from panel.out; it replies `SET gated <actor> <id> await_owner` and records a pending request (actor, tool, id) for the owner's signed line via botzz-bus-append (HMAC, X40/Plan Approver packet).
- Chip shows amber `Needs owner OK` with lock + clock; tap = details (who must approve, request id, age); long-press = cancel request (sends `tools_del` for that tool, which also clears the pending).
- Resolution:
  - `SET ok … by=owner` is IMPOSSIBLE today: the owner-signed path needs a signing key the owner has not approved (X40). Until the owner approves it, gated chips stay "Needs owner OK" indefinitely; the floaty shows "owner signing not set up" in the chip detail. Once approved: `SET ok <actor> <orig id> tool=<t> by=owner` → chip `on`.
  - `SET gated … denied` or owner rejects → chip `off`, toast-free inline "owner declined".
  - `bad_tools` / `io_err` → `off` + error text.
  - **Timeout:** no first ack in 5 s → `off`, "paneld offline — request not recorded". After `gated await_owner`, pending is kept across panel restarts (re-derived from paneld `status` / options snapshot, never stored only in the floaty). After 24 h without decision the chip shows "stale — re-request?" (still pending, not off); floaty never auto-resends.
  - `busy` → retry once after 2 s with the same `id` (idempotent), then `off` + "busy".
- No floaty path flips a gated chip to `on` without a paneld ok ack.

### 2.4 Removing any chip (instant, fail-safe, X45(4))
- UI flips to `off` immediately (optimistic) and sends `{"ev":"set","id":…,"actor":…,"kv":{"tools_del":["ssh"]}}` right away (not waiting for Save).
- `tools_del` accepted for open and gated tools without owner OK; paneld logs to the audit ledger (X45(3)).
- On `ok`/`noop` → stays off. On `io_err`/timeout → chip shows red "removal not confirmed — retry" and the tool is listed as **still possibly enabled** (safety over cosmetics); auto-retry same `id` up to 3× (1 s, 2 s, 4 s).
- Removing a `pending` gated chip = cancel request.
- Wire rule: `tools_add` and `tools_del` are lists of chip names `[a-z0-9-]+`; a name in both in one request → `bad_tools`. Replace-whole-list (`tools=`) is not used.

## 3. Other fields (changes from rev2)
| key | control | validation | default |
|---|---|---|---|
| model | dropdown + custom, tier badge from the B15–B18 free list (Gemini, Groq, NVIDIA) | `[A-Za-z0-9._/:-]{1,64}` | fleet default |
| interval_s | stepper | int 30–3600 (Commander) — rev2's 0/5–86400 dropped | 300 |
| max_mem_mb | stepper + "MB" suffix | **int 15–150, unit MB** (Rev 7 B2 supersedes X44's 1–150) | 30 |
| autostart | toggle | bool | false |
| verbose | toggle (new, Commander allowlist) | bool | false |
| owner_ok_required | read-only lock display | not settable from floaty (Commander rejects owner_ok*) | from actors.owner_approval_required / gated regex |
| role | read-only | — | actors.role (fleet.db; not on allowlist) |
- max_mem_mb below 15 cannot be selected (floor = botzz-capacity:51 minimum). The deploy memory gate (B7: MemAvailable < 400 MB or swap > 80%) is in paneld; the floaty only shows it. Stop/status are never gated (B8).

## 4. Cursor integration (gated)
- Chip `cursor` (Gated 🔒), action buttons in Conversation/Options: "Send coding task", "Check status".
- Preconditions shown on chip: owner-entered Cursor API key present (key never in floaty, bus, logs — floaty only sees `cursor_key=present|missing`), tool enabled for this bot, per-action owner OK.
- States and how the floaty learns them (no new floaty network calls; floaty only reads paneld output):
  - **offline / queued**: paneld (or the Keep-Alive botzz-tunnel-health, PROPOSED) reports reachability. Floaty reads, in order: (1) `SET`-independent status line `CURSOR <state> q=<n>` that paneld emits on `status` cmd and on change (state ∈ online|offline|queued|nokey); (2) actors.json/options snapshot field `integrations.cursor` if exported; (3) else `unknown` (treated as greyed).
  - Greyed when `offline`, `queued` (shows "queued n"), `nokey`, or `unknown`; chip still removable.
  - Floaty refreshes on panel open, on Options tab show, and every 30 s while that tab is visible (lazy; no polling when collapsed).
- Endpoint/auth unverified; design owner Termux Commander (Rev 6). Until defined, chip renders but "Send" is disabled with "integration not configured".

## 5. X44 reconciliation (now settled by Rev 7 B2)
- Final: max_mem_mb is in MB, int **15–150**, default 30. X44's "1–150" is superseded by B2 (floor 15 = capacity:51). Lane A's 1–8 is void.
- Conflicting wording found in the workspace:
  1. fleet-audit/botzz-lanea-termux-commander-design.md:15 has Commander's validator as `max_mem_mb (int 1-8)`. Now void; the doc needs an edit by Commander.
  2. merged-spec-draft.md:213 (X44) says "reconcile to MB 1-150". Superseded by :241 (B2, 15–150). The X44 line should be marked SUPERSEDED.
  3. Lane B rev2 had 15..150, which agrees with B2. rev3's earlier 1–150 draft was reverted.
  4. Interval: Commander's `interval_s` 30–3600 is adopted. rev2's `interval` 0/5–86400 is dropped.

## 6. Open questions / risks
- Delta `tools_add/tools_del` vs a full `tools` list: needs Captain's confirmation (B1 shows only generic kv).
- X45 vs the requested "adding a gated chip sends ev:set": reconciled as request-only; the enable itself needs the owner-signed bus line. Needs paneld to support a pending record + `gated await_owner` ack + later `ok … by=owner` (Commander); blocked until the owner approves the signing key.
- Cursor status source (paneld CURSOR line) is a new paneld output — owner Termux Commander; tunnel-health is PROPOSED (Keep-Alive).
- Tier table: decided, paneld TIERS line only (B12, Termux Commander). Risk: if paneld lacks it, the tools section is read-only.
- panel.resp is truncated at paneld start: pending gated state must be re-derived from paneld, not panel.resp history.

## 7. Concern for Fleet Captain (draft, not sent)
"X41/B1: no objection to nested kv, with one condition. paneld's current field extraction is sed (paneld:156-157) and cannot read a nested object.
The set handler must parse with python3 json, which is already a paneld dependency (paneld:57-58), not sed, and not jq (not in Termux base, not used anywhere in BOTZZ).
Tradeoff: about 30-60 ms of python start-up per Save vs sed's correctness limits. Saves are rare, so this is acceptable.
Fallback if python3 is missing at runtime: paneld replies `SET io_err <actor> <id> no_parser` and changes nothing. No sed fallback for set.
Also requested: tools as delta arrays tools_add/tools_del (removal always allowed, gated adds → `gated`). Superdesign / Lane B."
