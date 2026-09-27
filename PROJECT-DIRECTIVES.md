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
