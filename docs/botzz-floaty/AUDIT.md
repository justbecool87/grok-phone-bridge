# BOTZZ Floaty pass 5 (read-only), 2026-11-02 ~23:05 CT
Inputs (mtimes 22:55-22:57 CT): S 262 lines, A 95, D2 133, M 145, O rev 4 127, B rev3.1 132. Scratch only: /tmp/opt5.db with the copy /tmp/fleetcopy.db ATTACHed mode=ro.

## VERDICT: FAIL, one remaining contradiction (2 one-line edits, §4). Everything else is landing-ready.

## 1. The 14 pass-4 items
| # | Status | Evidence |
|---|---|---|
| 1 D2 advisory/3.2 GB | FIXED | D2:74-81 points to M §2/B7 S:245, "carries no thresholds of its own". D2:120 has no 3.2 GB; there's no "advisory" or "3.2 GB" anywhere in D2 |
| 2 D2:56 pgroup | FIXED | D2:55-56 "designed by Termux Commander (A:57, B10 S:250)" |
| 3 D2 bus-append owner | FIXED | D2:113 "= Termux Commander (S:244)" |
| 4 D2 unowned | FIXED | D2:116 "Unowned: none from Lane D". Quiet check owned by Termux ADB Host (D2:79, 97) |
| 5 M:3 | FIXED | M:3 cites fleet-audit/merged-spec-rev7.md |
| 6 M:5 | FIXED | M:5 que verified at 70b7619, sha256 f16345e0…; M:132 |
| 7 M outbox/LOOP | FIXED | M:90-91 `$QH/outbox` with LOOP as the script, = M:134-135, M:141 |
| 8 S:252 codes | FIXED | 8 codes (B20) |
| 9 S:262 | FIXED | "47 json = 47 rows… 5 unprefixed map to botzz-<name>" |
| 10 A:20 / A:26 | FIXED | A:20 "bus.jsonl (or a rotated bus.<gen>.jsonl)"; A:26 `bad_key detail=unknown_actor` |
| 11 A:72-73 | FIXED | both tagged [SUPERSEDED by A:95] |
| 12 O:5 vs O:114 | FIXED | O:5 "no script at 70b7619 writes fleet.db, and its writer is unknown" = O:118 |
| 13 O arrays | FIXED | O:113 arrays, all-or-nothing |
| 14 O FK/seeds/trigger | FIXED | O:10, O:15 foreign_keys=ON plus a read-back check. O:69-72 has 13 real seed INSERTs (7 open, 6 gated; the count is verified). O:88, 93 `COALESCE(tier,'gated')` |

## 2. Rev 4 SQL run and gate attacks
DDL OK. foreign_keys reads 1. tool_tiers has 13 rows. actor_effective → 47 rows, runs_model sum 0. A write to fleet.actors fails ("attempt to write a readonly database").
| Attack | Result | Intended? |
|---|---|---|
| unknown tool 'zzz', panel add | blocked `gated` | yes (fail closed) |
| unknown tool 'zzz', owner-bus add | ALLOWED | per O:74-76 design (the tool FK was dropped on purpose; unknown counts as gated, owner may add). See §4 |
| unseeded gated (deleted gh-push tier), owner add | ALLOWED (owner) | yes |
| unseeded gated, panel add, even on a FK-OFF connection | blocked `gated` | yes. The trigger alone fails closed |
| bad req_id 'nope', open tool | blocked FOREIGN KEY constraint failed | yes |
| bad req_id, gated tool | blocked `gated` | yes |
| gated add via panel | blocked `gated` | yes |
| gated UPDATE enabled 0→1 via panel req | blocked `gated` | yes |
| gated del via panel | allowed | yes (removal always allowed) |
| owner-bus gated add (cursor) | allowed | yes |
Effective tools after the run: `["bus","cursor","gh-push","pandas","python3","zzz"]`. Base pass-through works.

## 3. Sweep for new contradictions
- Line shifts: A is still 95 lines (no shift). D2 grew to 133; its internal refs (§7, M §2) are by section, OK. O refs to O:46 are still valid (the code list is in option_requests). S:244/245/250/252/254/262 refs in D2, M and A all resolve correctly.
- Codes: all 8 codes match in S:252, S:262, A:26, B:29, O:46, O:112.
- Paths: ~/botzz/db/options.db, ~/botzz/queue (M:89), bus.<gen>.jsonl, and the /sdcard read mirror are consistent.
- Owners: bus-append = Termux Commander (S:244, S:77 tag, A:60, D2:113). pgroup stop = Commander (S:250, D2:116). Mem gate and quiet check = Termux ADB Host (M:3, D2:116). Schema = Native Sync (O:1, S:254). Consistent.
- **NEW contradiction (from the item-14 change):** O:112 "Adding a tool that isn't in tool_tiers … gives **gated**", while A:18 "A name not in TIERS → **bad_tools**" and B:30 "bad_tools | **unknown tool name** …". An owner-signed add of an unknown tool also succeeds at the DB layer (§2 row 2), whereas A/B would reject it.

## 4. Exact edits for PASS
1. Pick one code for an unknown tool name. Recommended: keep O's fail-closed `gated` (safer, and it can't be bypassed by a misspelled seed). Then edit:
   - A:18 → "A name not in TIERS → `gated` on add (fail closed); `tools_del` of an unknown name → `noop`."
   - B:30 → drop "unknown tool name" from bad_tools (keep "name in both add and del, or non-array"), and add it to the `gated` row.
   - Alternative: change O:112 to bad_tools and have paneld reject unknown names before the DB. The trigger stays as a backstop.
2. Optional, same decision: state whether an owner may enable a tool not in tool_tiers (O:74-76 allows it). If not, require a tool_tiers row and reject otherwise.
With 1 applied: PASS for docs-only landing.
