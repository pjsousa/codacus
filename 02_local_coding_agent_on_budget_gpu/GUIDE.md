# Local Coding Agent on a Budget GPU (GTX 1070)

This is an executable, chapter-aligned reproduction package for **Build Powerful Local Coding Agent on Budget GPU with Llama.cpp and Pi**. It was prepared for this host on 2026-07-21. Run commands from this project directory. It uses the existing CUDA/TurboQuant llama.cpp build, shared model storage, Pi Coding Agent, and the video's REAP/MoE, prefill, cache, and model-switching workflow.

It does **not** claim that the video has been reproduced. Large model downloads, Pi installation, server runs, benchmarks, long-context tests, and remote access require explicit operator decisions. Generated validation keeps unexecuted work as `NOT RUN`.

## 1. Executive overview

The video demonstrates running coding-agent-capable REAP (Redundant Expert Activation Pruning) Mixture-of-Experts models—Qwen3.6-28B-REAP20-A3B and GLM-4.7-Flash-REAP-23B-A3B—on a budget RTX 3060 12 GB by combining llama.cpp partial GPU offload, MoE-aware CPU expert placement, TurboQuant KV compression, ubatch tuning, prompt cache reuse, and model hot-swapping through the router. It integrates Pi Coding Agent as the agent front-end, with optional Tailscale remote access.

This host adapts the RTX 3060 stack to a GTX 1070 8 GB:

| Resource | Video | This host | Consequence |
|---|---|---|---:|---|
| GPU | RTX 3060 12 GB, tensor cores | GTX 1070 8 GB, compute 6.1 | 4 GB less VRAM; no tensor cores; all placement assumptions tightened |
| CPU | 4-core, unspecified | i7-6700, 4C/8T, AVX2 | Tune 1-4 physical-core-oriented counts; do not assume 8 threads is best |
| RAM | not stated | ~62 GiB total, ~53 GiB available | Enough for one Q4 model plus runtime buffers |
| Disk free | not stated | ~111 GiB during inspection | Enough for one or two REAP Q4 artifacts |
| Port 8080 | not stated | Occupied by another HTTP service | Project defaults to 8088 |

The video's reported 1,142 prompt-processing tokens/s and roughly 40 decode tokens/s are RTX 3060 references, not GTX 1070 pass thresholds.

The largest risks are Pascal-specific TurboQuant kernel compatibility, OOM from over-aggressive expert placement or ubatch, selecting a quant variant without quality testing, Pi model discovery failures at the wrong root URL, and false confidence in remote access without authentication.

## 2. Source handling

### Local primary evidence

`02_local_coding_agent_on_budget_gpu.txt` and `description.txt` supplied the spoken progression, hardware, models, optimization claims, Pi integration, Tailscale access, and final stack. `01_running_a_35b_ai_model_on_6GB_vram_llamacpp/` supplied conventions, the required llama.cpp TurboQuant build, the shared model directory, and a prior control model.

Directly supported local claims include:

- REAP prunes poorly-used MoE experts, reportedly retaining 95.1% HumanEval versus the original 94.5%.
- The video links to the Qwen3.6-28B-REAP20-A3B and GLM-4.7-Flash-REAP-23B-A3B GGUF repositories.
- Q4_K_M is the recommended quant quality floor.
- Practical mid-frontier is 20B-40B total parameters with roughly 3B active per token.
- Agent bottleneck is prefill, not just decode; prompt cache helps later turns; middle-edits benefit from 256-token cache reuse.
- llama.cpp supports ubatch, threads, TurboQuant K/V, Flash Attention, MoE placement, router/`models.ini`, and prompt cache.
- Video thread tuning values: Qwen 28 at 1, 39.5 at 3, 22 at 4; GLM 45.77 at 3, 27 at 4 tokens/s decode.
- Video ubatch tuning: Qwen prefill rises from ~300 (ubatch 256) to 1,142 (ubatch 2048), decode stays flat.
- TurboQuant standard pair for this video: K `turbo4`, V `turbo2`.
- Pi version `0.80.10` and extension `pi-llama-cpp` `0.9.1`.
- Router and `/models` endpoint allow one-loaded-at-a-time hot switching.
- Tailscale for authenticated remote access with ACL controls.

### External verification

Official and upstream sources were checked on 2026-07-21:

- The Qwen REAP repository at `barozp/Qwen3.6-28B-REAP20-A3B-GGUF` revision `e3aeb816...` exists and the Q4_K_M artifact has SHA-256 `dcd137ca...`.
- The GLM REAP repository at `unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF` revision `983a65c6...` exists and the Q4_K_M artifact has SHA-256 `038e930e...`.
- Qwen3.6-28B-REAP20-A3B has approximately 28B total / 3B active, 205 routed experts, 8 active per token, 40 layers, and native 262,144-token context.
- GLM-4.7-Flash-REAP-23B-A3B has approximately 23B total / 3B active, 48 routed experts, 4 plus one shared active per token, 47 layers, and native 202,752-token context. Published card says 25% expert pruning (transcript generalizes 20%).
- The existing Qwen3.6-35B-A3B-UD-Q4_K_S control has 35B total/3B active, 256 routed experts, 8 plus one shared active, 40 layers, 262,144 native context, 20.9 GB.
- Current llama.cpp flags verified: `--n-gpu-layers`, `--n-cpu-moe`, `--ctx-size`, `--parallel`, `--cache-type-k/v`, `--flash-attn`, `--threads`, `--batch-size`, `--ubatch-size`, `--mmap`/`--no-mmap`, `--mlock`, `--cache-reuse`, `--fit off`, `--jinja`, `--metrics`, `--offline`, `--no-ui`, `--models-preset`, `--models-max`.
- TurboQuant `turbo2`/`turbo3`/`turbo4` KV types are present in the existing build.
- Pi `0.80.10` requires Node >=22.19.0; this host has Node 20. A user-local Node upgrade is needed.
- Pi's `pi-llama-cpp` extension uses the root server URL (not `/v1`) for the llama.cpp router integration.
- The build at `~/llama-low-vram-repro/llama-cpp-turboquant/build` is revision `c26cbdffc`, CUDA `61-real`, build 9971.

### Inferences and adaptations

- The video description links repositories but does not specify the exact file, quant variant, revision, or checksum used. This package pins reproducible Q4_K_M selections and labels them as candidate artifacts, not proven video equivalents.
- The video's full `llama-server` command, `llama-bench` command, `models.ini` syntax, and Tailscale flags are absent from the transcript. This package uses verified current build syntax and explicitly documents each adaptation.
- The video's "five things" (never explicitly enumerated) are mapped to: hardware/offload adaptation, REAP Q4 model selection, llama.cpp tuning (threads/ubatch/KV/cache/placement), Pi integration, and optional remote access.
- Video source: RTX 3060 12 GB. Kickoff objective described GTX 1060. Local source wins; GTX 1070 is adapted from RTX 3060.
- Start profiles use 8K context, one slot, ubatch 256, all experts on CPU, K=`q8_0`, V=`turbo4`. Video-intent profiles are unmeasured hypotheses with larger context/ubatch, partial expert placement, and the video's K=`turbo4`, V=`turbo2`.
- Cache-reuse is set to 256 to target the video's middle-edit benchmark; it does not increase raw pp/s.

## 3. Host assumptions and observed environment

Read-only inspection on 2026-07-21 found:

| Item | Observation | Status |
|---|---|---|
| OS | Ubuntu 22.04 lineage, Linux 5.15 | Suitable |
| GPU | GTX 1070, 8192 MiB, compute 6.1 | 4 GB less VRAM than video; no tensor cores |
| NVIDIA driver | 535.309.01 | Existing CUDA 12.2 build is the validated path |
| CUDA compiler | Present via existing build | Never rebuild |
| Build tools | CMake 3.22, GCC 11.4, Git 2.34 | Suitable |
| CPU | i7-6700, 4C/8T, AVX2 | Tune 1-4 physical-core-oriented threads |
| RAM | ~62 GiB total, ~53 GiB available | Suitable for one Q4 model plus buffers |
| Swap | 2 GiB, unused | Any benchmark swap growth is warning/failure |
| Disk | ~111 GiB free during inspection | Recheck before every download |
| llama.cpp | TurboQuant build 9971, revision `c26cbdffc`, CUDA `61-real` | Reuse only; do not rebuild |
| Node/npm | Node 20.20.1, npm 10.8.2 | Pi needs Node >=22.19.0 |
| Port 8080 | Occupied by another HTTP service | Project defaults to 8088 |
| Memlock | Soft/hard 64 KiB | Do not use `--mlock` without separately approved system changes |
| Tailscale | Not installed | Remote milestone remains opt-in and `NOT RUN` |
| Docker | Not required | Build already native; Docker path not exercised |

Native execution is primary because the existing build already targets `61-real` CUDA code. Docker is not used in this project.

## 4. Chapter-by-chapter replication guide

### 4.1 00:00 - Cold Open

**Objective:** establish that agent workloads repeatedly process large prompts and that prefill is the primary bottleneck.

**Technical change:** none. Reference the video's RTX 3060 goals (1,142 pp/s, ~40 tg/s) as video-only values, not GTX 1070 pass thresholds.

**Command:**

```bash
./scripts/00_preflight.sh
./scripts/01_verify_existing_llamacpp.sh
```

**Expected observation:** GTX 1070 with 8192 MiB and compute 6.1; llama.cpp revision `c26cbdffc`; CUDA device visible; required flags present; Node 20 is too old for Pi (warn, not fail).

**Validation:** inspect `logs/preflight_*.log` and `results/llamacpp_capabilities_*.json`. The preflight report records host facts; the capability report lists every supported flag.

**Likely failures:** no NVIDIA device, missing build directory, or binaries not found under the expected path.

**GTX 1070 note:** the video's pp/tg values are RTX 3060 references. Do not treat them as expected results.

### 4.2 00:58 - Hardware

**Objective:** document the host differences from the video's RTX 3060 and adapt all assumptions conservatively.

**Technical change:** none beyond preflight. This chapter maps to `ENVIRONMENT.md` and the safe profile defaults.

**Command:**

```bash
./scripts/00_preflight.sh
```

**Expected observation:** GTX 1070 confirmed, 8 GB VRAM, ~53 GB available RAM, 64 KiB memlock, port 8080 occupied, Tailscale not installed.

**Validation:** preflight JSON and log contain all hardware facts.

**Host adaptation:** use 8K context initially, one slot, ubatch 256, all experts on CPU, K=`q8_0`, V=`turbo4`, preserve >=1 GiB VRAM margin, no `--mlock`.

### 4.3 03:30 - Models

**Objective:** verify the existing build, identify candidate REAP Q4 models, and acquire one pinned artifact.

**Technical change:** add the selected model file; no server or benchmark yet.

**Prerequisites:** verified build from 4.1, disk space confirmed, explicit download confirmation.

**Commands:**

```bash
./scripts/03_download_models.sh --list
./scripts/03_download_models.sh glm-reap-q4km
# or for Qwen:
./scripts/03_download_models.sh qwen-reap-q4km
```

**Expected observation:** download script prints repository, revision, filename, size, SHA-256, license, free disk, and exact download confirmation requirement. The download uses the `hf` CLI with resumable transfers. On success: exact byte count and checksum pass.

**Validation:** script writes a `results/model-download-*.json` result and exits zero. The file exists at `$MODEL_DIR` with the pinned SHA-256.

**Likely failures:** insufficient disk, interrupted download, checksum mismatch, `hf` CLI not authenticated.

**Model metadata:**

| Profile | Repository | Filename | Size | SHA-256 |
|---|---|---|---:|---|
| `qwen-reap-q4km` | `barozp/Qwen3.6-28B-REAP20-A3B-GGUF@e3aeb816` | `Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf` | 17,264,580,480 | `dcd137ca...` |
| `glm-reap-q4km` | `unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF@983a65c6` | `GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf` | 14,113,838,816 | `038e930e...` |

Both Q4_K_M files exceed 8 GB VRAM by at least 5-8 GiB before KV/compute buffers. MoE reduces active per-token compute but all weights still need storage.

### 4.4 07:35 - Optimization (prefill, threads, ubatch, TurboQuant, cache, placement)

This is the core technical chapter covering six interconnected optimizations. Each optimization stage has its own script. Run them in the order below. The video progression is: select MoE/REAP Q4 models, tune threads, increase ubatch, test TurboQuant, validate cache reuse, then tune expert placement.

#### 4.4.1 Safe model load and base metrics

**Objective:** start the server with the safe profile and measure baseline pp/tg.

**Technical change:** load the selected profile with conservative settings.

**Prerequisites:** model downloaded, server port available.

**Commands:**

```bash
./scripts/04_start_model_server.sh start glm-reap-safe
# or for Qwen:
./scripts/04_start_model_server.sh start qwen-reap-safe
```

**Expected observation:** server reaches health, model identity matches, inference with one token succeeds. Logs show the resolved command line.

**Validation:** `./scripts/04_start_model_server.sh status` returns PASS and a healthy PID.

**Baseline metrics:**

```bash
./scripts/06_benchmark.sh smoke glm-reap-safe
```

**Expected observation:** llama-bench runs pp512/tg64 at the profile's placement, threads, ubatch, and KV types. Positive pp and tg rates are recorded.

**Stop the server when done:**

```bash
./scripts/04_start_model_server.sh stop
```

#### 4.4.2 Thread tuning

**Objective:** find the decode-friendly CPU thread count. Video reference: 3 threads was optimal on the video host.

**Technical change:** sweep threads 1, 2, 3, 4 with identical placement, ubatch, and KV.

**Prerequisites:** smoke benchmark passes.

**Command:**

```bash
./scripts/06_benchmark.sh threads glm-reap-safe
```

**Expected observation:** llama-bench runs each thread count three times. Decode rates rise up to a point and may fall when all cores are saturated.

**Validation:** the script records median tg per thread count. Selection criterion: stable optimum beyond noise, not a fixed value from the video. The video's 39.5 at 3 threads is reference only.

**GTX 1070 note:** 4 physical cores / 8 threads. 3 generation threads (with one for GPU management) often works best. Do not assume 8 threads improves anything.

#### 4.4.3 Ubatch (micro-batch) prefill tuning

**Objective:** improve prompt processing speed by increasing ubatch size while monitoring VRAM.

**Technical change:** sweep ubatch 128, 256, 512, 1024, 2048 with selected threads, fixed placement and KV.

**Prerequisites:** thread sweep completed.

**Command:**

```bash
./scripts/06_benchmark.sh ubatch glm-reap-safe
```

**Expected observation:** prefill (pp) rises as ubatch increases until a host limit (Pascal kernel or memory bandwidth). Decode (tg) should stay flat or degrade gradually.

**Validation:** the script records pp gain relative to ubatch 128 and tg ratio. Video reported Qwen went from ~300 (ubatch 256) to 1,142 (ubatch 2048) pp/s.

**GTX 1070 note:** Pascal has no tensor cores. Large ubatch may hit VRAM or compute limits faster than on RTX 3060. Start from the safe profile's ubatch 256 and increase only while VRAM stays above 1 GiB margin.

#### 4.4.4 TurboQuant KV comparison

**Objective:** reduce context memory through compressed K/V cache. Test safe and video-intent profiles.

**Technical change:** run two or more KV benchmarks at identical non-KV settings.

**Prerequisites:** selected threads and ubatch.

**Commands:**

```bash
# Default safe profile (K=q8_0, V=turbo4):
./scripts/06_benchmark.sh kv glm-reap-safe

# Video-intent profile (K=turbo4, V=turbo2):
CACHE_TYPE_K_OVERRIDE=turbo4 CACHE_TYPE_V_OVERRIDE=turbo2 \
  ./scripts/06_benchmark.sh kv glm-reap-video-intent

# Upstream control (K=q8_0, V=q8_0):
CACHE_TYPE_K_OVERRIDE=q8_0 CACHE_TYPE_V_OVERRIDE=q8_0 \
  ./scripts/06_benchmark.sh kv glm-reap-safe
```

**Expected observation:** each run creates machine-readable JSONL with pp/tg rates, VRAM telemetry, and resource capture.

**Validation:** compare rates and VRAM at identical placement. The video reports GLM +12% decode / -25% prefill and Qwen +4% / +5% with TurboQuant. Host deltas will differ.

**GTX 1070 note:** prefer `q8_0` for K (near-lossless) and `turbo4` for V before trying the video's aggressive `turbo4`/`turbo2`. Quality testing with retrieval is required before adopting aggressive compression.

#### 4.4.5 Prompt cache reuse validation

**Objective:** prove that middle-edit prompt changes reuse cached tokens beyond the unchanged prefix.

**Technical change:** send three prompts (A: prefix+original+middle+suffix, B: A + short suffix, C: prefix+changed+middle+suffix) against a server started with `--cache-reuse 256`.

**Prerequisites:** server running with the managed profile (cache-reuse 256 is the default for safe profiles).

**Command:**

```bash
./scripts/08_validate_agent_features.sh cache-reuse
```

**Expected observation:** the fixture parses `tokens_cached` and `tokens_evaluated` from the C response. Pass requires the middle edit to reuse chunks beyond the unchanged prefix and evaluate materially less than the full prompt.

**Validation:** script exits PASS if `tokens_cached > prefix_tokens` and `tokens_evaluated < total_tokens - prefix_tokens`.

**Likely failures:** server started without `--cache-reuse 256`, context too small, or the model/tokenizer does not reuse as expected.

#### 4.4.6 Expert placement (CPU-MoE) tuning

**Objective:** move some expert blocks from CPU to GPU, finding the throughput/VRAM frontier.

**Technical change:** decrease `--n-cpu-moe` one step at a time. A lower value leaves more final-layer experts eligible for GPU placement.

**Prerequisites:** safe profile server stopped (benchmark uses llama-bench directly).

**Commands:**

```bash
N_CPU_MOE_OVERRIDE=47 ./scripts/06_benchmark.sh smoke glm-reap-safe
N_CPU_MOE_OVERRIDE=46 ./scripts/06_benchmark.sh smoke glm-reap-safe
# Continue lowering until OOM or no further gain
```

On a 47-layer GLM model, 47 means all experts on CPU. The video does not publish exact GLM placement values. For the 40-layer Qwen REAP, start at 40 and decrease.

**Expected observation:** generation (tg) improves as more expert blocks move to GPU until VRAM is exhausted. Video's Qwen (35B, not REAP) improvement was from about 10 to 17 tok/s.

**Validation:** keep all other settings identical. Record VRAM telemetry. Select the lowest `n-cpu-moe` that stays >=1 GiB VRAM headroom at the intended context.

**GTX 1070 note:** start conservative and test decreasing values one at a time. The extra 2 GB versus GTX 1060 may allow a few more expert layers, but this is empirical.

### 4.5 11:48 - Pi Coding Agent integration

**Objective:** install Pi Coding Agent, point it at the local llama.cpp server, and run a read-only smoke test.

#### 4.5.1 Pi installation

**Prerequisites:** Node >=22.19.0 available (install user-local if needed).

**Command:**

```bash
./scripts/02_install_pi.sh
```

**Expected observation:** downloads pinned release packages, verifies their checksums, runs `npm ci` with `--ignore-scripts`, installs `pi-llama-cpp` extension, creates `settings.json` pointing at `127.0.0.1:8088`.

**Validation:** `PI_CODING_AGENT_DIR="$PWD/.state/pi" "$PWD/.tools/pi-0.80.10/node_modules/.bin/pi" --version` reports `0.80.10`.

**Likely failures:** Node <22.19.0, missing npm, package checksum mismatch, network failure.

#### 4.5.2 Pi read-only smoke test

**Prerequisites:** verified server running with a loaded model, Pi installed.

**Command:**

```bash
./scripts/05_run_pi_agent.sh
```

**Expected observation:** the script creates a disposable workspace with a marker file, runs Pi with only the `read` tool, verifies the tool was called and the exact marker was returned, and checks that the workspace is unchanged.

**Validation:** exit PASS, writes `results/pi-smoke-*.json`.

**Likely failures:** Pi cannot discover the model, wrong root URL, server not ready, Pi extension not installed.

**Pi integration notes:**

- Pi's `pi-llama-cpp` extension uses the root server URL (`http://127.0.0.1:8088`), not `/v1`.
- First Pi turn processes the full system prompt. Later turns reuse prompt cache.
- Model reasoning labels, tool-call syntax, and coding quality are model/quant/template dependent.
- Pi executes with the launching user's permissions; there is no built-in sandbox.

#### 4.5.3 Interactive Pi session

After the smoke test passes:

```bash
PI_CODING_AGENT_DIR="$PWD/.state/pi" \
LLAMA_SERVER_URL="http://127.0.0.1:8088" \
"$PWD/.tools/pi-0.80.10/node_modules/.bin/pi"
```

Use `/models` to inspect router models, `/model` for Pi's picker, `/new` for a fresh session, Ctrl+C or `/quit` to exit.

#### 4.5.4 Model hot swapping

**Prerequisites:** both Qwen and GLM REAP models downloaded, `configs/models.ini.local` created from `configs/models.ini.example`, router started manually.

**Start router manually:**

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  --models-preset "$PWD/configs/models.ini.local" \
  --models-max 1 --host 127.0.0.1 --port 8088 \
  --cache-ram 4096 --offline --no-ui --metrics
```

**Run hot-swap validation:**

```bash
ROUTER_PID=<PID> ./scripts/05_run_pi_agent.sh hot-swap
```

**Expected observation:** script loads model A, infers, loads model B, infers, loads model A again, infers. Router PID stays unchanged. Pi discovers both models through `/models`. VRAM returns to within 256 MiB of initial load after returning to A.

**Validation:** A-to-B-to-A all pass inference, one model loaded at a time, same router PID, Pi discovers both model IDs.

### 4.6 13:55 - Tailscale remote access

**Objective:** optional authenticated remote access.

**Status:** `NOT RUN` by default. Tailscale is not installed. The video installs Tailscale on rig and laptop, configures ACLs, and uses authenticated Tailscale Serve to expose the llama.cpp endpoint.

**Technical change:** none by default. This milestone is opt-in.

**If approved later:**

1. Install Tailscale and authenticate to the tailnet.
2. Keep llama.cpp bound to `127.0.0.1`.
3. Use `tailscale serve --bg --http 80 http://127.0.0.1:8088`.
4. Do not use Funnel.
5. Configure an API key file with mode 0600 for llama.cpp `--api-key-file`.
6. Record local versus remote latency separately.

**Safety:** never bind llama.cpp to `0.0.0.0`. Prefer authenticated Tailscale Serve. Inspect ACLs before adding routes. Capture existing Serve state before changes.

### 4.7 16:19 - Final stack and validation

**Objective:** all applicable local milestones pass; validation script confirms the state.

**Command:**

```bash
VALIDATION_PROFILE=glm-reap-safe ./scripts/07_validate_milestones.sh
```

**Expected observation:** JSON and Markdown ledgers written to `results/`. Overall precedence: `FAIL > NOT RUN > WARN > PASS`. Tailscale is expected `NOT RUN` and does not block.

**Validation:** the script reads only generated evidence. Unexecuted milestones remain `NOT RUN`.

## 5. Reproduction plan

### Quick sequence

```bash
# 0. Inspect
./scripts/00_preflight.sh | tee "preflight_$(date -u +%Y%m%dT%H%M%S).log"
./scripts/01_verify_existing_llamacpp.sh

# 1. Install Pi (requires Node >=22.19.0)
./scripts/02_install_pi.sh

# 2. Download model (review metadata first)
./scripts/03_download_models.sh --list
./scripts/03_download_models.sh glm-reap-q4km

# 3. Safe server load and baseline
./scripts/04_start_model_server.sh start glm-reap-safe
./scripts/06_benchmark.sh smoke glm-reap-safe
./scripts/04_start_model_server.sh stop

# 4. Thread tuning
./scripts/06_benchmark.sh threads glm-reap-safe

# 5. Ubatch tuning
./scripts/06_benchmark.sh ubatch glm-reap-safe

# 6. KV comparison (safe then video-intent)
./scripts/06_benchmark.sh kv glm-reap-safe
CACHE_TYPE_K_OVERRIDE=turbo4 CACHE_TYPE_V_OVERRIDE=turbo2 \
  ./scripts/06_benchmark.sh kv glm-reap-video-intent

# 7. Expert placement sweep
N_CPU_MOE_OVERRIDE=47 ./scripts/06_benchmark.sh smoke glm-reap-safe
N_CPU_MOE_OVERRIDE=46 ./scripts/06_benchmark.sh smoke glm-reap-safe

# 8. Cache reuse (requires active server)
./scripts/04_start_model_server.sh start glm-reap-safe
./scripts/08_validate_agent_features.sh cache-reuse

# 9. Context retrieval
./scripts/08_validate_agent_features.sh context

# 10. Pi smoke
./scripts/05_run_pi_agent.sh

# 11. Validate all
VALIDATION_PROFILE=glm-reap-safe ./scripts/07_validate_milestones.sh
```

### Execution rules

1. Archive preflight output before any change.
2. Do not download a model without reviewing its displayed metadata first.
3. Change one performance variable family at a time (threads, then ubatch, then KV, then placement).
4. Keep failed logs; do not overwrite evidence.
5. Do not advance after an unexplained failure.
6. Run benchmarks on an otherwise idle host.
7. Final profiles: repeat at least three times and report median plus range.

### Docker path

Not used in this project. The existing native CUDA build is the required runtime. Docker is documented in project 01 if needed.

## 6. Script reference

All scripts use `scripts/lib/common.sh` for paths, logging, resource capture, and managed-server identity. They accept `--help` via environment variable overrides. Create `configs/env.local` from `configs/env.example` for defaults.

| Script | Chapter | Purpose | Side effects |
|---|---|---|---|
| `00_preflight.sh` | 00:00, 00:58 | Read-only OS/CPU/RAM/disk/GPU/limit/build inventory | Writes `logs/preflight_*` and `results/preflight_*.json` |
| `01_verify_existing_llamacpp.sh` | 07:35 | Binary hashes, flags, CUDA device, TurboQuant K/V types | Writes `results/llamacpp_capabilities_*.json` |
| `02_install_pi.sh` | 11:48 | Pinned Pi and pi-llama-cpp install, checksum-verified | Creates `.tools/pi-*` and `.state/pi/` |
| `03_download_models.sh` | 03:30 | List or download; SHA-256 verification; resumable | Writes model to `$MODEL_DIR` |
| `04_start_model_server.sh` | 07:35, 11:48 | Start/stop/status managed server by profile | Starts background `llama-server` with owned PID tracking |
| `05_run_pi_agent.sh` | 11:48 | Read-only Pi smoke or hot-swap validation | Creates disposable workspace; removed on exit |
| `06_benchmark.sh` | 07:35 | llama-bench sweep: smoke, threads, ubatch, KV | Writes logs, telemetry, JSON result |
| `07_validate_milestones.sh` | 16:19 | Aggregate evidence into JSON/Markdown ledger | Writes `results/milestone-validation-*` |
| `08_validate_agent_features.sh` | 07:35 | Cache-reuse or context retrieval fixture | Writes logs and JSON result; requires active server |

Each benchmark script stage requires explicit `BENCHMARK_<stage>_<profile>` confirmation. All run scripts accept `CONFIRM=<value>` for non-interactive use after reviewing the scope.

## 7. Validation and benchmarks

### Core metrics

| Metric | Capture method | Acceptance |
|---|---|---|
| Model load | Server health JSON + `/v1/models` | Process alive, `.status == "ok"`, model ID matches |
| Prefill (pp) | llama-bench prompt rows | Positive finite rates, repeated samples |
| Decode (tg) | llama-bench generation rows | Positive finite rates, same model/placement |
| VRAM | 500 ms `nvidia-smi` telemetry | >=1 GiB headroom preferred; <256 MiB is failure |
| Host RAM | Before/after resource snapshots | >=16 GiB available; <8 GiB or swap growth fails |
| Stability | Process life, logs, repeated requests | No crash, OOM, fatal CUDA errors |
| Pi tools | Pi JSONL plus immutable fixture | Tool event, exact marker, workspace unchanged |
| Context retrieval | Tokenized fill and key retrieval | Deterministic keys returned; no truncation |
| Cache reuse | A/B/C prompt fixture | Middle edit reuses chunks beyond prefix |

### Benchmark controls

- Keep model revision, checksum, placement, context, batch, workload, seed, threads, and cache profile fixed when comparing one variable.
- Benchmark under idle conditions.
- Report median plus range from at least three repetitions.
- Movement below 5% or twice the relative median absolute deviation is `WARN`, not a proven gain.
- Scan stderr for OOM, fatal, CUDA error, and segmentation fault even if exit status is zero.

### Validation statuses

| Status | Meaning |
|---|---|
| `PASS` | Attempted, parsed, met all mandatory criteria |
| `WARN` | Completed with measurable caveats, unsafe margin, or noise |
| `FAIL` | Attempted required behavior was wrong, incomplete, or unsafe |
| `NOT RUN` | No attempt because prerequisites, safety boundary, or confirmation were absent |

Overall precedence: `FAIL > NOT RUN > WARN > PASS`. Tailscale remote access does not block local stack validation.

## 8. Final recommended configurations

All server commands bind only to `127.0.0.1`. Do not add `--mlock` while the process limit is 64 KiB. Do not use non-loopback bind without separate security review.

### Safe default (glm-reap-safe)

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  --model "$HOME/llama-low-vram-repro/models/GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf" \
  --alias "glm-4.7-flash-reap-23b-a3b-q4km" \
  --host 127.0.0.1 --port 8088 \
  --n-gpu-layers all --n-cpu-moe 47 \
  --ctx-size 8192 --parallel 1 \
  --threads 3 --threads-batch 4 \
  --batch-size 1024 --ubatch-size 256 \
  --cache-type-k q8_0 --cache-type-v turbo4 \
  --flash-attn on --cache-reuse 256 \
  --cache-ram 4096 --fit off \
  --jinja --metrics --offline --no-ui
```

Rationale: all experts on CPU, moderate context, safe KV profile, one slot. Suitable for first agent experiments and baseline measurements.

### Qwen safe alternative

Replace `--model` and `--alias` with the Qwen REAP artifact and use `--n-cpu-moe 40`.

### Video-intent hypothesis (unmeasured)

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  --model "$HOME/llama-low-vram-repro/models/GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf" \
  --alias "glm-4.7-flash-reap-23b-a3b-q4km" \
  --host 127.0.0.1 --port 8088 \
  --n-gpu-layers all --n-cpu-moe 41 \
  --ctx-size 32768 --parallel 1 \
  --threads 3 --threads-batch 4 \
  --batch-size 2048 --ubatch-size 1024 \
  --cache-type-k turbo4 --cache-type-v turbo2 \
  --flash-attn on --cache-reuse 256 \
  --cache-ram 4096 --fit off \
  --jinja --metrics --offline --no-ui
```

Rationale: matches the video's TurboQuant pair, larger context and ubatch, partial expert placement. These values are hypotheses for the GTX 1070, not measured optima. Replace `--n-cpu-moe` with the best value from the expert placement sweep.

### Best effort for GTX 1070

Combine the safe KV profile (`q8_0`/`turbo4`) with the most aggressive `--n-cpu-moe` value that leaves at least 1 GiB VRAM headroom at the intended context size. The recommended starting heuristic is the safe default. After completing the tuning stages (threads, ubatch, KV, placement), replace the default values with the host-specific optima.

## 9. Uncertainties and gaps

### Directly supported by local files

- Video hardware (RTX 3060 12 GB), REAP model repositories, Pi version, optimization progression, and Tailscale reference.
- Qwen target pp/s and tg/s values; GLM thread and ubatch tuning values.
- TurboQuant pair K=`turbo4`, V=`turbo2`.
- Router and models.ini approach.

### Externally verified

- Exact Qwen and GLM REAP repository revisions and Q4_K_M checksums.
- Current llama.cpp flags and TurboQuant KV types in the existing build.
- Pi version, pi-llama-cpp version, and Node requirement.
- GTX 1070 adaptation: no tensor cores, 8 GB VRAM, compute 6.1.

### Inferred

- The description-linked repositories are correct but the exact file, quant, revision, and checksum used in the video are unknown. Q4_K_M was selected as the safest consistent recommendation matching the transcript.
- The video's full `llama-server` command, `llama-bench` invocation, and `models.ini` syntax are absent. Current build syntax is used.
- GLM expert layer counts (47 layers, --n-cpu-moe 47 for all-CPU) are calculated from the published model architecture.
- pi-llama-cpp root URL behavior was verified from extension documentation.

### Host-dependent empirical items

- Optimal thread count and ubatch size for GTX 1070.
- Whether TurboQuant CUDA kernels work correctly and provide benefit on Pascal.
- Largest safe `--n-cpu-moe` reduction before OOM at the intended context.
- Actual pp/s and tg/s for each REAP model and profile.
- Long-context retrieval quality at each TurboQuant profile.
- Whether prompt cache reuse measurably improves agent turn TTFT.
- Model hot-swap VRAM behavior with two REAP Q4 artifacts.

### Transcript conflicts preserved

- Video source: RTX 3060 12 GB. Kickoff objective: GTX 1060. Source wins; adaptation is from RTX 3060.
- Transcript generalizes REAP pruning to 20%; GLM published card says 25%.
- "Chat starts with zero prefill" conflicts with ordinary prompt evaluation. This project treats first-turn prefill as required.
- "No API keys" means no cloud credential. A remotely exposed local API should still be authenticated.

## 10. Appendix

### Glossary

| Term | Meaning |
|---|---|
| REAP | Redundant Expert Activation Pruning; removes poorly-used MoE experts while retaining quality |
| MoE | Mixture of Experts; only a routed subset of expert FFNs activates per token |
| GGUF | llama.cpp model container format |
| Q4_K_M | K-quant Q4 medium; the transcript's recommended quality floor |
| pp | Prompt processing / prefill tokens per second |
| tg | Token generation / decode tokens per second |
| ubatch | Micro-batch size for prefill; larger values improve throughput but increase VRAM |
| `--n-cpu-moe N` | Keep MoE expert tensors in the first N layers on CPU; lower = more GPU-eligible |
| TurboQuant | Fork-only rotated low-bit KV codec family |
| `--cache-reuse N` | Enable prompt cache reuse with N-token chunk granularity |
| Pi | Coding agent tool with llama.cpp backend via `pi-llama-cpp` extension |
| Router | llama.cpp router mode (`--models-preset`) for multi-model hot swapping |
| Hot swap | Loading one model at a time through the router, unloading the previous |
| Tailscale Serve | Tailscale's reverse-proxy feature for authenticated local-network service exposure |

### Pinned links

- Video: https://www.youtube.com/watch?v=8ZJY_Nmhx1w
- Qwen REAP repository: https://huggingface.co/barozp/Qwen3.6-28B-REAP20-A3B-GGUF
- GLM REAP repository: https://huggingface.co/unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF
- Existing Qwen control repository: https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF
- Required llama.cpp build: https://github.com/TheTom/llama-cpp-turboquant/tree/c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea
- Upstream llama.cpp: https://github.com/ggml-org/llama.cpp
- Pi Coding Agent: https://github.com/earendil-works/pi
- pi-llama-cpp extension: https://github.com/earendil-works/pi-llama-cpp

### End-to-end checklist

- [ ] Preflight archived (GPU, RAM, disk, memlock, port, tools).
- [ ] Existing llama.cpp build verified (revision, CUDA, flags, KV types).
- [ ] Node >=22.19.0 available for Pi (install user-local if needed).
- [ ] Pi installed with checksum-verified release packages.
- [ ] Selected REAP Q4 model downloaded, size/SHA-256 pass.
- [ ] Safe server load passes health, model identity, inference, VRAM/RAM safety.
- [ ] Smoke benchmark produces positive pp and tg rates.
- [ ] Thread sweep records stable optimal decode value.
- [ ] Ubatch sweep shows measured prefill gain with safe VRAM margin.
- [ ] Two or more KV profiles compared at identical placement.
- [ ] Context retrieval at 50% of configured context with deterministic keys.
- [ ] Prompt cache-reuse fixture passes (middle-edit chunk reuse).
- [ ] Expert placement sweep finds fastest value with >=1 GiB VRAM headroom.
- [ ] Pi smoke test passes (read-only tool, exact marker, fixture unchanged).
- [ ] Model hot swap passes (A-to-B-to-A, one router PID, Pi discovery).
- [ ] Final benchmark repeated at least three times; median and range reported.
- [ ] Tailscale milestone acknowledged as opt-in / `NOT RUN`.
- [ ] Validation ledger shows all applicable milestones at `PASS`.
