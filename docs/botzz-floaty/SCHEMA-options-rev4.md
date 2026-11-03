# options.db schema (rev 4, B19 + tools, fail-closed gate) — DESIGN ONLY, owner: Native Sync Review
Base: fleet.db at 70b7619 (snapshot /tmp/bz/fleet.db, read-only inspection). Nothing built, no db or binary edits.

## Facts from the snapshot
- `actors` (47 rows) carries `meta.built_at`, but no script at 70b7619 writes fleet.db, and its writer is unknown (see Rules: Builder). It has no model, interval, max_mem_mb, autostart or verbose columns.
- So options must live outside fleet.db, where an unknown writer can't drop or rewrite them. An FK with ON DELETE CASCADE to `actors` would wipe options on every rebuild, so there's no cascading FK.

## B19 placement (rev 2)
- Options live in a separate `~/botzz/db/options.db` (Termux private ext4), NOT in fleet.db. fleet.db stays read-only and git-tracked at `$BOTZZ_REPO/botzz/db/fleet.db`, and no runtime write ever touches it.
- Runtime connection: open options.db read-write, run `PRAGMA foreign_keys=ON` and `PRAGMA busy_timeout=2000` (per connection; refuse with io_err if `PRAGMA foreign_keys` doesn't read back 1), then `ATTACH 'file:<fleet.db>?mode=ro' AS fleet` (uri=1). The tables below are created in options.db (main). The view is a TEMP view created after ATTACH on each connection.
- Startup path check: realpath() both db paths; if either resolves under /sdcard, /storage or /mnt/media_rw, refuse with io_err and write nothing.

## Delta (all in options.db)
```sql
PRAGMA foreign_keys=ON;   -- REQUIRED on every connection (sqlite default is OFF)
-- 1. Allowlist and types (one row per settable key; seeded, read-only to paneld)
CREATE TABLE IF NOT EXISTS option_keys (
  k          TEXT PRIMARY KEY,           -- interval_s | model | max_mem_mb | autostart | verbose
  type       TEXT NOT NULL CHECK (type IN ('int','bool','str')),
  min_i      INTEGER, max_i INTEGER,     -- int bounds
  pattern    TEXT,                       -- str regex (checked in paneld python)
  default_v  TEXT,                       -- JSON scalar
  gated      INTEGER NOT NULL DEFAULT 0  -- 1 = never settable from panel.out
);
-- seed: ('interval_s','int',30,3600,NULL,'300',0)
--       ('model','str',NULL,NULL,'^[A-Za-z0-9._/:-]{1,64}$','null',0)
--       ('max_mem_mb','int',15,150,NULL,'30',0)
--       ('autostart','bool',NULL,NULL,NULL,'false',0)
--       ('verbose','bool',NULL,NULL,NULL,'false',0)
-- tools are NOT option keys; they use actor_tools below. owner_ok*, gated, caps, *key*, *token* are never keys.

-- 2. Current values (EAV, per Commander's draft)
CREATE TABLE IF NOT EXISTS actor_options (
  actor_id   TEXT NOT NULL,              -- soft ref to actors.id (no FK: survives rebuild)
  k          TEXT NOT NULL REFERENCES option_keys(k),
  v          TEXT NOT NULL,              -- JSON scalar, validated against option_keys
  updated_ts INTEGER NOT NULL,           -- ms epoch
  req_id     TEXT NOT NULL,              -- the set request that wrote it
  PRIMARY KEY (actor_id, k)
);
-- 3. Idempotency/history (req_id UNIQUE here, not on actor_options, since one req may set several keys)
CREATE TABLE IF NOT EXISTS option_requests (
  req_id     TEXT PRIMARY KEY,
  actor_id   TEXT NOT NULL,
  ts         INTEGER NOT NULL,
  source     TEXT NOT NULL CHECK (source IN ('panel','owner-bus')),
  code       TEXT NOT NULL,              -- ok|noop|bad_key|bad_json|bad_tools|gated|busy|io_err
  keys_json  TEXT NOT NULL               -- key names only, never values
);
-- 4. B13 answer: which actor runs a model
CREATE TEMP VIEW IF NOT EXISTS actor_effective AS  -- after ATTACH fleet
SELECT a.id AS actor_id,
       json_extract(COALESCE(m.v,'null'),'$')            AS model,
       CASE WHEN m.v IS NOT NULL AND m.v <> 'null' THEN 1 ELSE 0 END AS runs_model,
       CAST(COALESCE(x.v,'30')  AS INTEGER)              AS max_mem_mb,
       CAST(COALESCE(i.v,'300') AS INTEGER)              AS interval_s,
       COALESCE(s.v,'false') = 'true'                   AS autostart,
       (SELECT json_group_array(t.tool) FROM actor_tools_effective t WHERE t.actor_id=a.id) AS tools
FROM fleet.actors a
LEFT JOIN actor_options m ON m.actor_id=a.id AND m.k='model'
LEFT JOIN actor_options x ON x.actor_id=a.id AND x.k='max_mem_mb'
LEFT JOIN actor_options i ON i.actor_id=a.id AND i.k='interval_s'
LEFT JOIN actor_options s ON s.actor_id=a.id AND s.k='autostart';
-- 5. Tool tiers (seeded from spec tier table; read-only to paneld)
CREATE TABLE IF NOT EXISTS tool_tiers (
  tool  TEXT PRIMARY KEY,
  tier  TEXT NOT NULL CHECK (tier IN ('open','gated'))
);
INSERT OR IGNORE INTO tool_tiers(tool,tier) VALUES
 ('bus','open'),('que','open'),('web','open'),('opencode','open'),
 ('adb-read','open'),('gh-read','open'),('rish-read','open'),
 ('cursor','gated'),('adb-input','gated'),('ssh','gated'),
 ('gh-push','gated'),('gh-pr','gated'),('rish-write','gated');

-- 6. Per-actor tool overrides on top of read-only fleet.actors.tools
CREATE TABLE IF NOT EXISTS actor_tools (
  actor_id   TEXT NOT NULL,              -- soft ref, no FK
  tool       TEXT NOT NULL,              -- unknown tools are allowed in the row but gated by the trigger
  enabled    INTEGER NOT NULL CHECK (enabled IN (0,1)),  -- 1 add, 0 remove (override)
  updated_ts INTEGER NOT NULL,
  req_id     TEXT NOT NULL REFERENCES option_requests(req_id),
  PRIMARY KEY (actor_id, tool)
);
-- Enforce: enabling a gated tool needs a request whose source is owner-bus.
-- option_requests row is inserted first in the same transaction.
CREATE TRIGGER IF NOT EXISTS actor_tools_gate_ins BEFORE INSERT ON actor_tools
WHEN NEW.enabled=1
 AND COALESCE((SELECT tier FROM tool_tiers WHERE tool=NEW.tool),'gated')='gated'  -- fail closed
 AND COALESCE((SELECT source FROM option_requests WHERE req_id=NEW.req_id),'')<>'owner-bus'
BEGIN SELECT RAISE(ABORT,'gated'); END;
CREATE TRIGGER IF NOT EXISTS actor_tools_gate_upd BEFORE UPDATE ON actor_tools
WHEN NEW.enabled=1
 AND COALESCE((SELECT tier FROM tool_tiers WHERE tool=NEW.tool),'gated')='gated'  -- fail closed
 AND COALESCE((SELECT source FROM option_requests WHERE req_id=NEW.req_id),'')<>'owner-bus'
BEGIN SELECT RAISE(ABORT,'gated'); END;

-- 7. Effective tools (TEMP, after ATTACH): base ∪ enabled overrides − disabled overrides
CREATE TEMP VIEW IF NOT EXISTS actor_tools_effective AS
SELECT a.id AS actor_id, b.value AS tool
FROM fleet.actors a, json_each(COALESCE(a.tools,'[]')) b
WHERE NOT EXISTS (SELECT 1 FROM actor_tools o
                  WHERE o.actor_id=a.id AND o.tool=b.value AND o.enabled=0)
UNION
SELECT o.actor_id, o.tool FROM actor_tools o WHERE o.enabled=1;

CREATE TABLE IF NOT EXISTS options_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT OR REPLACE INTO options_meta VALUES('options_schema_version','4');
-- fleet.meta is not written.
```

## Rules
- Ack codes (unified, O:46): ok|noop|bad_key|bad_json|bad_tools|gated|busy|io_err. Mapping: an unknown key or bad value gives bad_key, and an unknown actor gives bad_key with detail=unknown_actor (confirmed by Fleet Captain) so the UI can tell them apart. A malformed tools_add[]/tools_del[] (not an array of strings, an empty name, or a tool that matches the pattern but fails the regex) gives bad_tools. Adding a tool that isn't in tool_tiers is fail-closed and gives gated. The trigger's RAISE 'gated' gives gated, and the whole transaction rolls back.
- Tools: a request carries arrays `tools_add[]` and `tools_del[]` (matching lanes A, B and S), applied all-or-nothing in one transaction. Each entry upserts actor_tools (add=1, del=0), never fleet.actors. If any add is gated, the whole request rolls back with gated. Removal is always allowed. Adding an open tool is allowed from panel. Adding a gated tool is allowed only when option_requests.source='owner-bus' (an HMAC-verified owner line); paneld checks this and the trigger enforces it again. The audit/tools.jsonl ledger is unchanged (key names only).
- Trust of owner-bus: source='owner-bus' is written only after paneld verifies the owner HMAC signature (X45). That key doesn't exist yet and needs the owner's OK. Until then paneld never writes source='owner-bus', so every gated add returns gated.
- Base tools that aren't in tool_tiers (for example python3, pandas, curl from fleet.actors.tools) pass through to the effective set unchanged. Removing them is allowed; adding one as an override is gated (fail closed) until it's seeded.
- B13: the 450 MB model-run floor applies when `actor_effective.runs_model = 1`. Default for all 47 today is 0 (no model set). Don't infer it from caps or tools.
- Writes: one sqlite transaction (BEGIN IMMEDIATE) that upserts actor_options rows and inserts option_requests. A replayed req_id returns the stored code and writes nothing. Run with `PRAGMA busy_timeout=2000`, so a timeout means `busy`.
- Builder: no script at 70b7619 writes fleet.db (actors-json opens it read-only), and the writer is unknown. Separating options.db makes options independent of how fleet.db gets rebuilt.
- Orphans: options whose actor_id isn't in actors are kept and listed by `actor_effective` absence; nothing is auto-deleted.
- Projection: `~/botzz/options/<actor>.json` is generated from actor_effective via tmp+mv under ~/botzz (not /sdcard, per X23/X39, which resolves re-audit C3).
- No secrets: str values are matched against `pattern`, and a key-like lint rejects ghp_/sk-/BEGIN. Logs carry key names only.
- Migration: a new file only, and fleet.db is untouched. Rollback is to delete options.db (options revert to defaults).
- Git: ~/botzz is outside $BOTZZ_REPO, so runtime state never dirties the tracked tree.

## Resolved
- Q1 (B19): options are in an ATTACHed options.db.
- Q2: the fleet.db default path is private ext4 (from code, not device-verified), backed by the startup /sdcard check.
