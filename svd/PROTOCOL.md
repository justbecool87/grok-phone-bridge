# Stable Video Diffusion (SVD) protocol — Lackey contract

**Directive:** FC-001  
**Owners:** SVD Smith (execute), Probe (validate), Harbor (deliver), Scout (ingest)  
**Device:** Termux on Moto G 2025 (CPU/Vulkan path; no CUDA)

## Ready-for-prompting gate

Lackeys are **READY FOR PROMPTING** when all of these are true:

1. `ffmpeg` / `ffprobe` on PATH  
2. SVD venv exists at `~/grok-inbox/svd-work/venv` with importable `torch` + `diffusers`  
3. Target clip staged at `~/grok-inbox/VID_20260927_105213.mp4`  
4. Work dirs exist: `~/grok-inbox/svd-work/{frames,clips,exports,logs}`  
5. `bin/svd-status.sh` exits 0  

Until then status is **INSTALLING** or **BLOCKED**.

When READY, Fleet Captain waits for the owner’s **project prompt**. Do not start a heavy SVD generate until that prompt arrives.

## Pipeline

```text
Scout  → stage source MP4
Probe  → ffprobe + keyframe sample
Owner  → project prompt to Fleet Captain
SVD Smith → normalize segment → SVD img2vid / vid refine → mux audio
Harbor → export *-svd-enhanced.mp4 + adb-to-grok say
```

## Defaults (overridable by project prompt)

| Knob | Default |
|------|---------|
| Segment | first 2–4 s (or owner-selected timecode) |
| Resolve | 576×1024 or 1024×576 (SVD XT family) |
| Frames | 14–25 |
| Motion bucket | 127 |
| Noise aug | 0.02 |
| Device | `cpu` (or `vulkan` if torch build supports) |
| Audio | re-mux from source segment when present |

## Layout

```text
~/grok-inbox/
  VID_20260927_105213.mp4          # staged source
  svd-work/
    venv/                          # Python 3.11/3.12 + torch + diffusers
    frames/                        # Probe samples
    clips/                         # normalized SVD inputs
    exports/                       # enhanced outputs
    logs/
    requirements.txt
```
