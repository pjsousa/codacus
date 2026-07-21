# Reproduction Plan

## Boundaries

- Reuse and verify the existing llama.cpp build; never compile it.
- Keep new evidence project-local and model files in the established shared directory.
- Require confirmation for package installation, model downloads, model loading, agent execution, and benchmarks.
- Keep networking on `127.0.0.1` and leave Tailscale `NOT RUN` by default.
- Change one performance variable family at a time and retain failed evidence.

## Stages

| Stage | Goal | Prerequisites | Changed parameters | Expected impact | Test | Acceptance | Reversal |
|---|---|---|---|---|---|---|---|
| 0. Inspect | Establish host/build facts | None | None | No runtime load | `00_preflight.sh`, `01_verify_existing_llamacpp.sh` | GTX 1070 adaptation and exact capabilities recorded | None |
| 1. Model | Obtain one pinned REAP Q4 artifact | Disk and explicit confirmation | Model file only | 14-17 GB disk; no VRAM yet | `03_download_models.sh PROFILE` | Exact size and SHA-256 pass | Retain or manually remove only the selected verified file |
| 2. Safe load | Prove model/API compatibility | Model and verified build | 8K context, ubatch 256, one slot, conservative KV | High host RAM, bounded VRAM | `04_start_model_server.sh start PROFILE` | Exact health JSON, model ID, process remains alive | `04_start_model_server.sh stop` |
| 3. Base metrics | Separate prefill from decode | Safe profile loads | Fixed pp512/tg64 workload | Short heavy inference | `06_benchmark.sh smoke PROFILE` | Positive machine-readable PP/TG rows, no fatal log | Stop server if running; no config mutation |
| 4. Threads | Find decode-friendly CPU count | Base metrics | Threads 1,2,3,4; fixed placement/ubatch | May improve decode; all cores may regress | `06_benchmark.sh threads PROFILE` | Repeated stable optimum beyond noise | Restore `THREADS=3` or prior measured value |
| 5. Ubatch | Improve agent prefill | Selected threads | Ubatch 128-2048; fixed placement/KV | Higher pp/s and VRAM pressure; decode should stay similar | `06_benchmark.sh ubatch PROFILE` | PP gain beyond noise with safe VRAM/RAM | Restore ubatch 256 |
| 6. KV | Reduce context memory | Stable placement/threads/ubatch | Safe q8_0/turbo4, then video turbo4/turbo2 | May free VRAM; can reduce quality or Pascal speed | Benchmark both named profiles and run retrieval/tool tests | Allocation plus retrieval and tool-call quality pass | Restore q8_0/turbo4 or f16 |
| 7. Placement | Move expert blocks toward GPU | Stable short-context profile | Decrease `n-cpu-moe` one step per run | Faster decode until VRAM OOM; less context headroom | Create local profile variants, rerun smoke | Fastest repeatable value with >=1 GiB VRAM margin | Increase `n-cpu-moe` |
| 8. Context | Find reliable agent context | Selected placement/KV | 8K, 16K, 32K, then confirmed larger tiers | KV and prompt time grow with context | `08_validate_agent_features.sh context` | No truncation/OOM/swap and deterministic key retrieval | Return to last passing context |
| 9. Pi | Validate local tool use | Pi installed and server healthy | Local endpoint and model ID | First turn performs full prefill; later turns may reuse cache | `05_run_pi_agent.sh` | Read tool event, exact result, unchanged fixture | Remove `.tools/` and `.state/` manually if no longer wanted |
| 10. Cache reuse | Validate agent-like prompt deltas | Stable single-slot server | `cache-reuse=256` | Lower TTFT for middle changes, not higher raw pp/s | `08_validate_agent_features.sh cache-reuse` | Middle edit reuses chunks beyond the unchanged prefix | Set `cache-reuse=0` |
| 11. Hot swap | Switch Qwen/GLM without router restart | Both models, Pi, and local presets | Router, `models-max=1` | Sequential load latency and transient RAM pressure | `ROUTER_PID=<PID> 05_run_pi_agent.sh hot-swap` | Pi discovers both; same router PID; one loaded model; all completions work | Stop router and return to direct profile |
| 12. Remote | Optional private access | Separate approval and security review | Tailscale Serve and API auth | Network latency changes TTFT, not intrinsic pp/s | Local versus remote request comparison | Least-privilege authenticated path; no public exposure | Remove only the exact Serve route |

## Measurement Order

1. Use an otherwise idle host and record idle VRAM.
2. Establish safe load and smoke evidence.
3. Tune threads while ubatch and placement stay fixed.
4. Tune ubatch using the selected threads.
5. Compare KV codecs at identical placement.
6. Retune expert placement only after codec comparison.
7. Validate retrieval and Pi tool calls before accepting aggressive compression.
8. Repeat final short benchmarks at least three times and report median plus range.

Video numbers are not pass thresholds. A claimed host improvement must exceed the larger of 5% or twice the relative median absolute deviation of the compared runs.
