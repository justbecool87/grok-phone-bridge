# Fleet Captain Directives

**Handed down by:** Termux Commander (The Terminal Director)  
**Moderated by:** Fleet Captain (Harbor Master of the Swarm)  
**Calibrated by:** Regulator Bot  
**Owner:** justbecool87  
**Device:** Moto G 2025 (on-device only)

---

## Directive FC-001 — Locate & enhance phone video (SVD)

**Status:** ACTIVE  
**Issued:** 2026-09-27  
**Target media:** `/sdcard/Movies/Messages/VID_20260927_105213.mp4`  
**Staged path:** `~/grok-inbox/VID_20260927_105213.mp4` (~43.4 MB)  
**Enhancement protocol:** **Stable Video Diffusion (SVD)**

### Mission

Four Lackeys find (confirm) the owner-selected Messages video on the phone, prepare it for edit, run Stable Video Diffusion enhancement/editing protocol, and return artifacts to the Grok inbox without leaving the Android device.

### Deployed Lackeys

| # | Lackey callsign | Specialty | Duty under this directive |
|---|-----------------|-----------|---------------------------|
| 1 | **Scout** | Media discovery | Confirm path via `grok-phone search` / filesystem; stage with `grok-phone stage` / `upload`; report size + location |
| 2 | **Probe** | Video forensics | Read container metadata (ffprobe when available); sample frames; note resolution, fps, duration, codec; flag SVD suitability |
| 3 | **SVD Smith** | Stable Video Diffusion | Own the SVD protocol for edit + enhance (img2vid / vid2vid / frame-condition flows); keep intermediate tensors/clips under `~/grok-inbox/svd-work/` |
| 4 | **Harbor** | Delivery & inject | Export final clip(s) to `~/grok-inbox/` + `/sdcard/Download/grok-inbox/`; `adb-to-grok say` status lines so Fleet Captain can brief the owner |

### Stable Video Diffusion protocol (Lackey contract)

Lackeys **must** be able to handle SVD video editing and enhancements. Minimum protocol surface:

1. **Ingest** — accept staged MP4/WebM from Scout; Probe validates.
2. **Normalize** — resize/crop/fps policy for SVD (document chosen preset before run).
3. **Condition** — keyframe / first-frame / clip conditioning as required by the SVD build in use.
4. **Diffuse** — run SVD generate or enhance pass (edit strength, motion bucket, noise aug — log values).
5. **Refine** — optional second pass (face/detail / temporal consistency) without abandoning SVD as the primary motion model.
6. **Mux** — re-attach/replace audio from source when present; write `*-svd-enhanced.mp4`.
7. **Report** — Harbor injects a short status + paths into the live Grok TUI.

If SVD weights/runtime are not yet installed on-device, SVD Smith reports **BLOCKED: runtime** with a Termux/Kali install option list; Scout/Probe work continues; Harbor does not claim enhancement success.

### Governance (Fleet Captain)

- Offer 2–4 options when Lackeys conflict (e.g. enhance vs restyle vs extend duration).
- Do not commandeer a Lackey’s specialty.
- Regulator Bot may publish speed/thoroughness adjustments (numbered).
- Escalate to owner only for preference, payment, destructive overwrite of the original, or after one failed self-resolve round.
- **Never overwrite** the source Messages file; write siblings under `grok-inbox`.

### Termux Commander elevated path

```bash
grok-phone status
grok-phone stage '/sdcard/Movies/Messages/VID_20260927_105213.mp4'
# after SVD work:
adb-to-grok say 'FC-001 Harbor: SVD export ready in ~/grok-inbox/'
```



### Expanded Lackeys (FC-001 workload — fetch / deploy / research / render)

| # | Lackey callsign | Specialty | Duty |
|---|-----------------|-----------|------|
| 5 | **Courier** | Fetch | Pull SVD weights, HF assets, deps when ordered; never overwrite source media |
| 6 | **Quay** | Deploy | Keep Kali SVD venv healthy; publish exports into `~/grok-inbox/` + sdcard mirror |
| 7 | **Archivist** | Research | SVD protocol notes, preset research, cite PROTOCOL.md before runs |
| 8 | **Loom** | Render | Post-SVD encode/mux/audio attach → `*-svd-enhanced.mp4` |

**Comms:** all Lackeys ping Fleet Captain via `fleet-bus`; Regulator Bot monitors `~/grok-inbox/fleet/regulator/`.

```bash
fleet-comms-demo          # prove ping/assign/ACK
fleet-regulator-monitor 6 2
fleet-bus board
fleet-bus clips 20
```

### Acceptance

- [x] Target video identified and staged  
- [ ] Probe metadata captured  
- [ ] SVD runtime available or BLOCKED reported with install options  
- [ ] Enhanced export in `~/grok-inbox/`  
- [ ] Harbor inject confirms paths to live Grok session  
