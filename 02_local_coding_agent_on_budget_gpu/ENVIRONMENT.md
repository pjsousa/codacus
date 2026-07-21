# Environment

## Observed During Inspection

| Item | Observation | Consequence |
|---|---|---|
| OS | Ubuntu 22.04 lineage, Linux host | Existing binaries are native Linux x86-64 |
| GPU | NVIDIA GTX 1070, 8,192 MiB, compute 6.1 | 4 GB less VRAM than video; no tensor cores |
| Driver | 535.309.01 | Existing CUDA 12.2 build is the validated path |
| CPU | Intel i7-6700, 4 cores/8 threads | Tune 1-4 physical-core-oriented counts; do not assume 8 is best |
| RAM | About 62 GiB total, roughly 53 GiB available during inspection | One Q4 model plus runtime buffers is practical |
| Swap | 2 GiB, unused | Any benchmark swap growth is a warning/failure signal |
| Disk | About 111 GiB free during inspection | Recheck immediately before every model download |
| llama.cpp | TurboQuant build 9971, revision `c26cbdffc`, CUDA `61-real` | Reuse only; do not rebuild |
| Node/npm | Node 20.20.1, npm 10.8.2 | Current Pi needs Node >=22.19.0 |
| Port 8080 | Occupied by another HTTP service | Project defaults to 8088 and validates JSON identity |
| Memlock | Soft/hard 64 KiB | Do not use `--mlock` without separately approved system changes |
| Tailscale | Not installed | Remote milestone remains opt-in and `NOT RUN` |

Run `scripts/00_preflight.sh` for current values. The table is historical context and must not replace fresh evidence.

## Verified Build Features

- `llama-server`, `llama-cli`, and `llama-bench`
- CUDA device visibility and Pascal-targeted build
- `--n-gpu-layers`, `--n-cpu-moe`, `--ctx-size`, and `--parallel`
- `--batch-size`, `--ubatch-size`, `--threads`, and `--threads-batch`
- K/V cache types including `turbo2`, `turbo3`, and `turbo4`
- `--flash-attn on|off|auto`; this build requires an explicit value
- mmap/mlock, fit controls, cache reuse, metrics, API, and model-router presets

Parser support is not model compatibility. Every model/KV combination must pass actual context creation and inference.

## GTX 1070 Adaptation

The video system is RTX 3060 12 GB. Conservative changes are:

- Start at 8K context instead of assuming the video's context.
- Use one parallel slot, not the server's router default of four models.
- Start ubatch at 256 and sweep upward with telemetry.
- Keep all expert blocks on CPU initially, then decrease `n-cpu-moe` empirically.
- Prefer K=`q8_0`, V=`turbo4` before the video's aggressive K=`turbo4`, V=`turbo2`.
- Preserve at least 1 GiB practical VRAM margin for context and desktop use.
- Treat Flash Attention and TurboQuant speedups as hypotheses on Pascal.

## Environment Overrides

Copy `configs/env.example` to ignored `configs/env.local`. The file is sourced as shell and therefore executable code. It must be a regular file not writable by group/others. Prefer paths and non-secret tuning values only.

The server rejects non-loopback binding unless `ALLOW_REMOTE_BIND=YES`; setting that variable is an explicit operator override, not a Tailscale setup recommendation.
