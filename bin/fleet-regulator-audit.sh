#!/data/data/com.termux/files/usr/bin/bash
# Regulator audit — query every actor for errors, missing/corrupt/truncated files,
# and conflicts; summarize for Archivist support/resolutions + Fleet Captain.
set -euo pipefail
export HOME="${HOME:-/data/data/com.termux/files/home}"
export PATH="$HOME/bin:/data/data/com.termux/files/usr/bin:$PATH"

FLEET="${FLEET_HOME:-$HOME/grok-inbox/fleet}"
ACTORS="$FLEET/actors"
GH="$FLEET/github-lackey/repos"
STATE="$FLEET/state"
OUTDIR="$FLEET/regulator/audit"
MIRROR="/sdcard/Download/grok-inbox/fleet-monitor"
REPORT_JSON="$OUTDIR/last-audit.json"
REPORT_MD="$OUTDIR/last-audit.md"
ARCHIVIST_BRIEF="$OUTDIR/archivist-resolutions.md"

mkdir -p "$OUTDIR" "$MIRROR"

bus() { command -v fleet-bus >/dev/null && fleet-bus "$@" >/dev/null 2>&1 || true; }

run_audit() {
  bus state regulator auditing "query all actors — errors/missing/corrupt/truncated + conflicts"
  bus send regulator fleet-captain report "AUDIT START — integrity/errors/conflicts across actors"
  bus send regulator archivist assign "Prepare resolution brief from Regulator audit"

  python3 - "$FLEET" "$REPORT_JSON" "$REPORT_MD" "$ARCHIVIST_BRIEF" <<'PY'
import json, os, pathlib, sys, time, hashlib, collections

fleet, out_json, out_md, out_arch = map(pathlib.Path, sys.argv[1:5])
actors_root = fleet / "actors"
repos_root = fleet / "github-lackey" / "repos"
state_dir = fleet / "state"
svd = pathlib.Path.home() / "grok-inbox" / "svd-work"
video = pathlib.Path.home() / "grok-inbox" / "VID_20260927_105213.mp4"
venv = svd / "venv"

EXPECTED = {
    "scout": ["lib/discover.py", "FRAMEWORK.md"],
    "probe": ["lib/forensics.py", "FRAMEWORK.md"],
    "svd-smith": ["lib/svd_enhance.py", "FRAMEWORK.md", "QUALITY.json"],
    "harbor": ["lib/deliver.py", "FRAMEWORK.md"],
    "courier": ["lib/fetch_weights.py", "FRAMEWORK.md"],
    "quay": ["lib/deploy_env.py", "FRAMEWORK.md"],
    "archivist": ["lib/index_diffusion.py", "FRAMEWORK.md"],
    "loom": ["lib/render_mux.py", "FRAMEWORK.md"],
    "forge": ["lib/repo_ops.py", "FRAMEWORK.md"],
    "termux-commander": ["lib/upgrade_actor.py", "FRAMEWORK.md"],
}

REPO_MAP = {
    "scout": ["scout/termux-api"],
    "probe": ["probe/ffmpeg-python"],
    "svd-smith": ["svd-smith/ComfyUI-Stable-Video-Diffusion", "svd-smith/stable-video-diffusion-colab"],
    "harbor": ["harbor/termux-widget"],
    "courier": ["courier/huggingface_hub"],
    "quay": ["quay/virtualenv"],
    "archivist": ["archivist/Awesome-Diffusion-Models"],
    "loom": ["loom/moviepy"],
    "forge": ["forge/cli"],
    "termux-commander": ["termux-commander/termux-api-package"],
}

def file_issue(path: pathlib.Path):
    if not path.exists():
        return "missing"
    try:
        st = path.stat()
    except OSError:
        return "unreadable"
    if st.st_size == 0:
        return "empty/corrupt"
    # truncated heuristic: .py/.md/.json unexpectedly tiny
    if path.suffix in {".py", ".md", ".json"} and st.st_size < 20:
        return "truncated"
    if path.suffix == ".json":
        try:
            json.loads(path.read_text())
        except Exception:
            return "corrupt-json"
    if path.suffix == ".py":
        txt = path.read_text(errors="replace")
        if "def " not in txt and "class " not in txt and path.name != "__init__.py":
            # may still be ok scripts
            if len(txt) < 40:
                return "truncated"
    return None

findings = []
conflicts = []
errors = []
enhancement = {"actors_present": [], "libs_ok": [], "libs_missing": [], "dramatic_score": 0}

# --- per-actor integrity ---
actor_dirs = sorted([p for p in actors_root.iterdir() if p.is_dir()]) if actors_root.is_dir() else []
for ad in actor_dirs:
    actor = ad.name
    enhancement["actors_present"].append(actor)
    expected = EXPECTED.get(actor, ["FRAMEWORK.md"])
    for rel in expected:
        p = ad / rel
        iss = file_issue(p)
        if iss:
            findings.append({"actor": actor, "path": str(p), "issue": iss, "class": "skeleton"})
            errors.append({"actor": actor, "error": f"{iss}: {rel}"})
        else:
            enhancement["libs_ok"].append(f"{actor}:{rel}")

    # docs symlink / repo presence
    for rel in REPO_MAP.get(actor, []):
        rp = repos_root / rel
        if not rp.exists():
            findings.append({"actor": actor, "path": str(rp), "issue": "missing-repo", "class": "forge-repo"})
            errors.append({"actor": actor, "error": f"missing forge repo {rel}"})
        else:
            nfiles = sum(1 for _ in rp.rglob("*") if _.is_file() and ".git" not in _.parts)
            if nfiles < 3:
                findings.append({"actor": actor, "path": str(rp), "issue": "truncated-sparse-repo", "class": "forge-repo", "files": nfiles})
            # sparse source conflict: packaging-only trees
            has_pkg = any(p.is_dir() and p.name not in {".git"} and any(p.rglob("*.py")) for p in rp.iterdir() if p.is_dir())
            if actor in ("probe", "loom", "courier") and not has_pkg and nfiles < 30:
                conflicts.append({
                    "type": "sparse_vs_live_package",
                    "actor": actor,
                    "detail": f"Forge clone {rel} looks sparse/top-level only ({nfiles} files) while actor lib expects live pip module",
                    "resolution": "Prefer venv pip package; deepen clone only if source reading required",
                })

# --- state conflicts ---
transits = {}
for sf in state_dir.glob("*.json"):
    try:
        d = json.loads(sf.read_text().strip().splitlines()[-1])
    except Exception as e:
        errors.append({"actor": sf.stem, "error": f"corrupt state json: {e}"})
        findings.append({"actor": sf.stem, "path": str(sf), "issue": "corrupt-state", "class": "state"})
        continue
    aid = d.get("actor") or sf.stem
    transits[aid] = {"transit": d.get("transit"), "detail": d.get("detail")}

# P0 vs REST / idle conflicts
p0 = ["svd-smith", "quay", "courier"]
for a in p0:
    t = (transits.get(a) or {}).get("transit", "")
    if str(t).lower() in ("idle", "resting") and a == "svd-smith":
        # ready-idle may be ok if awaiting prompt
        det = str((transits.get(a) or {}).get("detail", "")).lower()
        if "await" not in det and "ready" not in det and "priming" not in str(t).lower():
            conflicts.append({
                "type": "p0_idle_conflict",
                "actor": a,
                "detail": f"P0 actor transit={t} while SVD project unfinished",
                "resolution": "Keepalive or Captain assign priming/fetch; or REST only if approved",
            })

# duplicate twin vs primary both claiming same duty overload
for base in ["scout", "probe", "harbor", "forge", "loom", "quay", "archivist", "courier", "svd-smith"]:
    aux = f"{base}-aux"
    if base in transits and aux in transits:
        bt = str(transits[base].get("transit", "")).lower()
        at = str(transits[aux].get("transit", "")).lower()
        if bt == "idle" and "assisting" in at:
            conflicts.append({
                "type": "twin_primary_imbalance",
                "actor": base,
                "detail": f"{aux} assisting while {base} idle",
                "resolution": "Reassign load to primary or REST aux; Archivist index twin roles",
            })

# --- SVD project readiness probes ---
readiness = {
    "video_staged": video.exists() and video.stat().st_size > 1000,
    "video_path": str(video),
    "video_bytes": video.stat().st_size if video.exists() else 0,
    "venv_exists": venv.is_dir(),
    "frames_dir": (svd / "frames").is_dir(),
    "clips_dir": (svd / "clips").is_dir(),
    "exports_dir": (svd / "exports").is_dir(),
    "weights_dir": (svd / "weights").is_dir(),
    "weights_present": False,
}
if readiness["weights_dir"]:
    readiness["weights_present"] = any((svd / "weights").rglob("*"))
if not readiness["video_staged"]:
    errors.append({"actor": "scout", "error": "project video missing/truncated in grok-inbox"})
    findings.append({"actor": "scout", "path": str(video), "issue": "missing-or-tiny-video", "class": "project"})
if not readiness["weights_present"]:
    findings.append({"actor": "courier", "path": str(svd / "weights"), "issue": "missing-svd-weights", "class": "project"})
    errors.append({"actor": "courier", "error": "SVD HF weights not downloaded yet"})
    conflicts.append({
        "type": "ready_runtime_vs_missing_weights",
        "actor": "svd-smith",
        "detail": "Diffusers/torch may be installed but weights absent — cannot finish video enhance",
        "resolution": "Captain project prompt → Courier snapshot_download SVD model; need multi-GB free disk + long CPU run",
    })

# dramatic enhancement score 0-10
score = 0
score += min(4, len(enhancement["actors_present"]) // 2)  # up to 4
score += 2 if (actors_root / "svd-smith" / "lib" / "svd_enhance.py").exists() else 0
score += 1 if (actors_root / "probe" / "lib" / "forensics.py").exists() else 0
score += 1 if (actors_root / "loom" / "lib" / "render_mux.py").exists() else 0
score += 1 if readiness["venv_exists"] else 0
# subtract for gaps
gap = len([f for f in findings if f["class"] == "skeleton"])
score -= min(3, gap)
score = max(0, min(10, score))
enhancement["dramatic_score"] = score
enhancement["dramatic_label"] = (
    "transformational" if score >= 8 else
    "substantial" if score >= 6 else
    "moderate" if score >= 4 else
    "incremental" if score >= 2 else
    "minimal"
)

# package expectations (filled later by shell if present)
pkg_file = fleet / "github-lackey" / "logs" / "readiness-check.out.json"
packages = {}
if pkg_file.exists():
    try:
        packages = json.loads(pkg_file.read_text())
    except Exception:
        packages = {"error": "unreadable readiness-check.out.json"}

doc = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "enhancement_effectiveness": enhancement,
    "findings": findings,
    "errors": errors,
    "conflicts": conflicts,
    "readiness": readiness,
    "packages": packages,
    "counts": {
        "findings": len(findings),
        "errors": len(errors),
        "conflicts": len(conflicts),
        "actors_scanned": len(actor_dirs),
    },
}
out_json.write_text(json.dumps(doc, indent=2) + "\n")

# Markdown report
lines = []
lines.append(f"# Regulator Audit — integrity / errors / conflicts\n")
lines.append(f"**When:** {doc['ts']}\n")
lines.append(f"## Enhancement effectiveness\n")
lines.append(f"- Actors with skeletons: **{len(enhancement['actors_present'])}** ({', '.join(enhancement['actors_present'])})\n")
lines.append(f"- Dramatic score: **{score}/10 ({enhancement['dramatic_label']})**\n")
lines.append(f"- Skeleton file issues: **{gap}**\n")
lines.append(f"\n## Counts\n- findings: {len(findings)}\n- errors: {len(errors)}\n- conflicts: {len(conflicts)}\n")
lines.append(f"\n## Project readiness (local video SVD)\n")
for k, v in readiness.items():
    lines.append(f"- `{k}`: **{v}**\n")
lines.append(f"\n## Packages\n```json\n{json.dumps(packages, indent=2)}\n```\n")
lines.append(f"\n## Errors\n")
if not errors:
    lines.append("- (none)\n")
else:
    for e in errors:
        lines.append(f"- **{e['actor']}**: {e['error']}\n")
lines.append(f"\n## Missing / corrupt / truncated\n")
if not findings:
    lines.append("- (none)\n")
else:
    for f in findings:
        lines.append(f"- [{f['class']}] **{f['actor']}** `{f['path']}` → {f['issue']}\n")
lines.append(f"\n## Conflicts\n")
if not conflicts:
    lines.append("- (none)\n")
else:
    for c in conflicts:
        lines.append(f"- **{c['type']}** ({c.get('actor','?')}): {c['detail']}\n  - resolution: {c['resolution']}\n")
out_md.write_text("".join(lines))

# Archivist resolutions
ares = []
ares.append(f"# Archivist resolutions — from Regulator audit\n\n**When:** {doc['ts']}\n\n")
ares.append("## Priority resolutions\n")
if not readiness.get("weights_present"):
    ares.append("1. **Courier + Captain prompt**: download SVD weights (`stabilityai/stable-video-diffusion-img2vid-xt`) into `~/grok-inbox/svd-work/weights/` — blocking finish.\n")
ares.append("2. **Quay**: verify disk ≥ model size + working set before fetch.\n")
ares.append("3. **Probe/Loom**: rely on venv `ffmpeg-python`/`moviepy` (YES preferred) over sparse Forge trees.\n")
ares.append("4. **Enhance**: gap-only fixes for any missing skeleton files listed below.\n")
ares.append("5. **Keepalive/Captain discretion**: clear twin imbalance / idle P0 conflicts without token-wasteful full re-enhance.\n")
ares.append("\n## Ticket list\n")
for i, f in enumerate(findings, 1):
    ares.append(f"{i}. Fix `{f['issue']}` for **{f['actor']}** @ `{f['path']}`\n")
for i, c in enumerate(conflicts, 1):
    ares.append(f"C{i}. {c['type']}: {c['resolution']}\n")
if not findings and not conflicts:
    ares.append("- No file integrity tickets; project blocked only on weights/prompt/runtime policy.\n")
out_arch.write_text("".join(ares))
print(json.dumps({"findings": len(findings), "errors": len(errors), "conflicts": len(conflicts), "score": score, "label": enhancement["dramatic_label"]}))
PY

  # attach package readiness if produced
  if [[ -f "$FLEET/github-lackey/logs/readiness-check.out.json" ]]; then
    python3 - <<'PY'
import json, pathlib
fleet = pathlib.Path.home()/"grok-inbox/fleet"
audit = json.loads((fleet/"regulator/audit/last-audit.json").read_text())
pkg = json.loads((fleet/"github-lackey/logs/readiness-check.out.json").read_text())
audit["packages"] = pkg
# update markdown packages section lightly
(fleet/"regulator/audit/last-audit.json").write_text(json.dumps(audit, indent=2)+"\n")
PY
  fi

  cp -f "$REPORT_JSON" "$MIRROR/REGULATOR-AUDIT.json"
  cp -f "$REPORT_MD" "$MIRROR/REGULATOR-AUDIT.md"
  cp -f "$ARCHIVIST_BRIEF" "$MIRROR/ARCHIVIST-RESOLUTIONS.md"
  # also superiors overlay
  mkdir -p "$MIRROR/REGULATOR-SUPERIORS"
  cp -f "$REPORT_MD" "$MIRROR/REGULATOR-SUPERIORS/REGULATOR-AUDIT.md"
  cp -f "$ARCHIVIST_BRIEF" "$MIRROR/REGULATOR-SUPERIORS/ARCHIVIST-RESOLUTIONS.md"

  bus state archivist researching "resolutions from Regulator audit"
  bus send archivist fleet-captain report "Archivist resolution brief ready — REGULATOR-AUDIT + ARCHIVIST-RESOLUTIONS"
  bus send regulator fleet-captain report "AUDIT COMPLETE — see REGULATOR-AUDIT.md (errors/conflicts/integrity)"
  bus state regulator monitoring "audit published for Captain/Archivist"

  echo "REPORT=$REPORT_MD"
  echo "ARCHIVIST=$ARCHIVIST_BRIEF"
}

case "${1:-run}" in
  run|once) run_audit; echo '---'; head -80 "$REPORT_MD"; echo '---'; head -40 "$ARCHIVIST_BRIEF" ;;
  status) [[ -f "$REPORT_MD" ]] && head -60 "$REPORT_MD" || echo "no audit yet" ;;
  *) echo "Usage: fleet-regulator-audit run|status" ;;
esac
