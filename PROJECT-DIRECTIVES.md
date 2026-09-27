# Project Directives — Fleet Captain

**Source of truth:** Termux Commander (highest privilege) **and** owner conversation in this Grok session.  
**Executor of swarm moderation:** Fleet Captain  
**Elevated deployer of new Lackeys/Actors:** Termux Commander  

These are binding project directives for FC-001 and related fleet work on the Moto G 2025 (on-device).

---

## 1. Chain of command

1. **Owner** states intent in conversation → becomes project directive.
2. **Termux Commander** holds highest privilege for deploy/adjust of Lackeys/Actors (elevated `nethunter -r` / root proot).
3. **Fleet Captain** receives directives, moderates the swarm, offers options on conflicts, and **requests** new Lackey deployment from Termux Commander when monitors report overload.
4. **Regulator Bot** calibrates speed/thoroughness, runs idle→Forge assist, and hosts elevated job priority holds (P0 pip/diffusers → P1 Forge → P2 other).
5. **Lackeys** stay autonomous on specialty; escalate only for preference, payment, destructive action, or one failed self-resolve round.

## 2. Traffic monitor → Fleet Captain → Termux Commander

- Every **5 minutes**, traffic monitor analyzes Lackey/actor bus traffic.
- Report to **Fleet Captain**: who is **overburdened** and who is **idle**.
- **Idle** Lackeys: Regulator reassigns them to assist **Forge** (GitHub Lackey) using skills already learned.
- **Overburdened** Lackeys: Fleet Captain sends **deploy-request** to **Termux Commander**.
- **Termux Commander** deploys/adjusts new Lackey/Actor twins with highest privilege intent and registers them on the roster/bus.

## 3. Elevated priority framework

| Priority | Work | Actors (core) | Privilege |
|----------|------|---------------|-----------|
| **P0** | pip / diffusers install | svd-smith, quay, courier | elevated (nethunter) |
| **P1** | GitHub Forge research/pull | forge + idle helpers | Termux Commander may elevate clones/indexing |
| **P2** | other FC-001 duties | remaining cast | normal |

Lower priorities are **held** while higher priority is RUNNING/NEEDED.

## 4. GitHub Lackey (Forge)

- Lean-pack shallow clones per actor under `~/grok-inbox/fleet/github-lackey/repos/<actor>/`.
- Coding, deployment, and language learning libraries for each actor.
- Idle Lackeys help Forge with learned skills (path verify, probe stats, SVD notes, fetch, dirs, index, mirror, render).

## 5. SVD / video mission (FC-001)

- Target: staged Messages video in `~/grok-inbox/`.
- Protocol: Stable Video Diffusion; never overwrite source.
- Owner will send **project prompt** to Fleet Captain when Lackeys are READY_FOR_PROMPTING.

## 6. Operator surfaces

- MiXplorer live mirror: `/sdcard/Download/grok-inbox/fleet-monitor/`
- Commands: `fleet-elevated-monitor`, `fleet-traffic-analyze`, `fleet-termux-commander`, `fleet-github-lackey`, `fleet-regulator-reassign`, `fleet-mix-mirror`

---

*Updated from owner conversation directives; Fleet Captain must treat this file as standing project orders.*


## 7. REST and REASSIGNMENT (Monitor + Regulator → Fleet Captain)

Static parameters allow **any Lackey/Actor** to receive **REST** or **REASSIGNMENT** when **Monitor** and **Regulator** deem it beneficial.

Flow:
1. Monitor + Regulator **propose** (`fleet-rest-reassign propose`)
2. Report goes to **monitor bot** channel (bus + `REST-REASSIGN-PENDING.*` in MiXplorer) for **Fleet Captain**
3. Fleet Captain may **approve** / **disapprove**, **or** assign research Lackey (`archivist-aux` by default) to brief **why approve/disapprove**
4. On **APPROVE**, Fleet Captain **issues the agentic effort** (rest window or reassignment to Forge/specialty lead)

```bash
fleet-rest-reassign propose
fleet-rest-reassign research          # research brief
fleet-rest-reassign approve all       # Captain approves → execute
fleet-rest-reassign disapprove all
fleet-rest-reassign status
```

Tunables: `FLEET_REST_WINDOW_SEC`, `FLEET_OVERBURDEN_MSGS`, `FLEET_IDLE_MSGS_MAX`, `FLEET_REST_MIN_SEC`, `FLEET_RESEARCH_ACTOR`


## 8. Actor Enhancement Bot (Forge repos → live skeletons)

All Forge-landed repos must be **implemented** with their most relevant actor via the **Actor Enhancement Bot**.

- **Fleet Captain** commands enhancement / agentic effort.
- **Termux Commander** is the elevated framework that **produces/revises/upgrades** actor coding skeletons on Captain command (`fleet-termux-commander enhance`).
- Live coding packages (`ffmpeg-python`, `moviepy`, `huggingface_hub`, Diffusers) improve base actor frameworks — especially **SVD Smith** quality after pip finish.
- Skeletons live under `~/grok-inbox/fleet/actors/<actor>/`.

```bash
fleet-actor-enhance all
fleet-termux-commander enhance
fleet-actor-enhance status
```


## 9. Regulator superiors overlay + Enhancement Bot token growth

- **Regulator** publishes a **superiors-only fleet board overlay** in MiXplorer for communication with **Fleet Captain** and **Termux Commander**:
  `/sdcard/Download/grok-inbox/fleet-monitor/REGULATOR-SUPERIORS/`
- **Fleet Captain** analyzes Enhancement Bot monitoring from Regulator (token/work proxy growth).
- If Enhancement Bot is **not growing** in token/work usage → Fleet Captain issues a **directive to Termux Commander** to resume/revise/elevate enhance.
- **Archivist** assists Enhancement Bot **token efficiency** (compact logs, high-signal briefs) so tokens are not wasted.

```bash
fleet-regulator-overlay start
fleet-regulator-overlay status
```
