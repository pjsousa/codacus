# Qwen3.6 35B-A3B on a GTX 1070

This is a chapter-aligned reproduction package for the video **Running a 35B AI Model on 6GB VRAM, FAST (llama.cpp Guide)**. Commands were prepared for this host on 2026-07-21. Run them from this repository.

## 1. Executive overview

The video runs the 35B-total, 3B-active Qwen3.6-35B-A3B mixture-of-experts model with `llama.cpp`. Most model weights remain in system RAM while selected non-expert tensors and some expert blocks use the GPU. The sequence is a deliberately slow layer-split baseline, CPU placement for expert tensors, eager model loading, selective expert movement back to the GPU, compressed KV cache, and locked host memory.

This works because every generated token activates only 8 routed experts plus one shared expert rather than all 35B parameters. It does **not** make the 35B weight file fit in VRAM. It depends on enough system RAM and CPU memory bandwidth, and it can become limited by CPU computation or PCIe transfers.

This host is materially better than the video host in GPU memory and system RAM:

| Resource | Video | This host | Consequence |
|---|---:|---:|---|
| GPU | GTX 1060 6 GB | GTX 1070 8 GB, compute 6.1 | More expert weights or KV cache may fit; Pascal limitations remain |
| CPU | i3-8100, 4C/4T | i7-6700, 4C/8T | Similar core count, older architecture; benchmark rather than assume faster |
| RAM | 24 GB | 62 GiB | Comfortable for a 20.9 GB GGUF, `--no-mmap`, and runtime buffers |
| Disk free | not stated | 141 GiB | Enough for one quant, source, and builds; not a full quant collection |
| Driver/toolkit | not stated | R535.309.01, no `nvcc` | Runtime works; install a CUDA 12 toolkit before native build |

The largest risks are an unvalidated TurboQuant CUDA path on Pascal, an OOM from over-aggressive placement, low model quality from an overly small weight quant, long context allocation time, and false confidence in `--mlock` when the process limit is still 64 KiB. The video’s 17 tok/s is a useful comparison point, not a guaranteed acceptance criterion: its complete model quant, prompt, build, and benchmark procedure were not published.

## 2. Source handling

### Local primary evidence

`running_a_35b_ai_model_on_6GB_vram_llamacpp_guide.txt` supplied the spoken progression, hardware, flags, throughput figures, memory observations, and failed speculative-decoding experiment. `description.txt` supplied chapter boundaries, the Proxmox/LXC/Docker stack, exact spellings for `--no-mmap` and `--mlock`, and links to the base model and TurboQuant fork.

Directly supported local claims include:

- Baseline `-ngl 20` at about 3 tok/s.
- `--n-cpu-moe 41` at about 10 tok/s.
- `--no-mmap` at about 13.5 tok/s.
- Tuning to `--n-cpu-moe 35` at about 17 tok/s and 5.5 GB VRAM.
- TurboQuant key/value settings described as Turbo4/Turbo3, reaching 128K, then 256K after changing CPU-MoE placement to 36.
- `--mlock`, container IPC-lock permission, and an increase from 12 KiB to about 16 GB locked.
- A Qwen3.5 800M speculative draft reducing throughput from 17 to 11 tok/s at about 65% acceptance.

### External verification

Live official and upstream sources were used to verify facts omitted or changed since the video:

- The Qwen model exists, has 40 layers, 256 experts, 8 routed plus 1 shared expert, 35B total/3B active parameters, and native 262,144-token context.
- The base `Qwen/Qwen3.6-35B-A3B` repository is Safetensors, not a directly runnable GGUF.
- The pinned Unsloth GGUF is `20,893,015,008` bytes with a published SHA-256 and matches the video’s roughly 20 GB statement.
- Current `llama.cpp` uses `-ngl`/`--n-gpu-layers`, `--n-cpu-moe`, `--no-mmap`, `--mlock`, `-c`, and `--cache-type-k/v` as used here.
- Current `--n-cpu-moe N` selects expert tensors in the **first** N layers. On a 40-layer model, 35 leaves five expert blocks eligible for GPU placement, not six as the transcript states.
- Full TurboQuant cache types remain in `TheTom/llama-cpp-turboquant`, not upstream `llama.cpp`.
- The current fork advises keeping K at higher precision than V. Its recommended default is K=`q8_0`, V=`turbo3`; the video’s K=`turbo4`, V=`turbo3` remains available but is now discouraged without quality testing.
- CUDA 12.9.1 is the final toolkit supporting Pascal compilation. CUDA 13 cannot target GTX 1070. CUDA 12.2 is the conservative match for this host and driver.

### Inferences

The video never prints its full Docker command, GGUF filename, weight quant, exact context integers, final `-ngl`, or benchmark prompt. This package infers binary and model choices needed for an executable implementation. Inferred choices are pinned and visible in `config.env.example`; they are not represented as exact video facts.

## 3. Host assumptions

Observed on this host:

| Item | Observation | Status |
|---|---|---|
| OS | Ubuntu 22.04.5 LTS, Linux 5.15 | Suitable |
| GPU | GTX 1070, 8192 MiB, compute capability 6.1 | Suitable with Pascal-specific build |
| Display use | About 349 MiB during inspection | Leave headroom; close Steam and GPU-heavy apps |
| NVIDIA driver | 535.309.01, reports CUDA 12.2 capability | Suitable for CUDA 12.x minor compatibility with real `sm_61` code |
| CUDA compiler | `nvcc` missing | Must install toolkit or build in a custom container |
| Build tools | CMake 3.22.1, GCC 11.4, Git 2.34 | Suitable for CUDA 12.2 |
| CPU | Intel i7-6700, 4 cores/8 threads, AVX2 | Suitable, likely CPU/memory-bandwidth limited |
| RAM | 62 GiB, about 50 GiB available at inspection | Suitable |
| Swap | 2 GiB | Keep unused; swapping invalidates stable latency |
| Disk | 141 GiB free | Suitable for selected model and build |
| Docker | Docker 29.5 and NVIDIA Container Toolkit 1.18 | GPU passthrough tested successfully |
| Memlock | Soft and hard limit both 64 KiB | Not suitable for `--mlock` until changed |
| Permissions | `sudo` is assumed for APT and limit configuration | Verify before dependency setup |

Native compilation is primary because a `61-real` binary avoids runtime PTX JIT. The stock `ghcr.io/ggml-org/llama.cpp:full-cuda` currently uses CUDA 12.8 and its broad build can leave Pascal as PTX; newer PTX is outside NVIDIA’s compatibility guarantee on R535. Docker is still useful when building a local image explicitly for `61-real` with CUDA 12.2.

The PCIe generation/link width and RAM channel configuration were not reliably queried. Both affect this workload and must be treated as host-dependent.

## 4. Chapter-by-chapter replication guide

### 4.1 00:00 - This shouldn't work

**Objective:** establish that the model cannot reside wholly in 8 GB VRAM but can run through CPU/GPU hybrid placement.

**Technical change:** none. Confirm the host, selected 20.9 GB model, and required toolchain.

**Command:**

```bash
./scripts/00_host_check.sh
```

**Expected observation:** GTX 1070 with 8192 MiB and compute 6.1; about 62 GiB RAM; Docker GPU check passes; `nvcc` is initially reported missing; memlock is 64 KiB.

**Validation:** save the output and confirm the GGUF size will exceed VRAM. The script does not alter system configuration, but Docker may cache the small `ubuntu:22.04` probe image.

**Likely failures:** no NVIDIA device, Docker daemon permission failure, insufficient free disk, or a non-Pascal-compatible CUDA choice.

**GTX 1070 note:** 8 GB provides about 2 GB more placement space than the video’s GTX 1060, but 349 MiB was already used by the desktop. Do not treat all 8192 MiB as available.

### 4.2 00:27 - Setup

**Objective:** install dependencies, build the pinned TurboQuant fork, and download a known GGUF.

**Technical change:** install build tools and CUDA 12.2, compile real `sm_61` device code, then fetch and hash-check `UD-Q4_K_S`.

**Commands:**

```bash
./scripts/01_install_deps.sh
INSTALL_CUDA=1 ./scripts/01_install_deps.sh
./scripts/02_build_llamacpp.sh
./scripts/03_get_model.sh
```

The first dependency run is optional if the second is used. `INSTALL_CUDA=1` installs the toolkit-only `cuda-toolkit-12-2` package after showing APT's simulation; it does not request a driver meta-package.

**Expected observation:** `llama-cli --version` identifies revision `c26cbdff...`; `--list-devices` lists CUDA0; the model SHA-256 is `a8138f...47b949c`; file size is about 20.9 GB decimal.

**Validation:**

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-cli --version
sha256sum $HOME/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf
```

**Likely failures:** NVIDIA repository unavailable, `nvcc` not in `/usr/local/cuda-12.2/bin`, source revision changed locally, interrupted 20.9 GB download, or too little disk space.

**GTX 1070 note:** never substitute CUDA 13. The build uses `-DCMAKE_CUDA_ARCHITECTURES=61-real`; retain this setting.

### 4.3 01:46 - Why it's slow by default

**Objective:** reproduce the video's naive layer split before applying MoE-aware placement.

**Technical change:** explicitly disable automatic fitting and request 20 GPU layers with ordinary mmap behavior.

**Command:**

```bash
./scripts/04_run_baseline.sh
```

Equivalent core command:

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-cli \
  -m $HOME/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  --no-mmproj --fit off -ngl 20 -c 4096 -t 4 -tb 8 \
  --flash-attn auto --seed 42 --single-turn --show-timings -n 128 \
  -p "Explain in five concise points why mixture-of-experts inference can use less compute than a dense model."
```

**Expected observation:** the video reports about 3 tok/s and noticeable per-token stalls. This host may be faster, or `-ngl 20` may OOM because the selected GGUF is now explicit while the video's quant was not.

**Validation:** read the pinned CLI's `[ Prompt: ... | Generation: ... ]` timing summary in `baseline_*.log`; `Generation` is token-generation speed. Record model-load success, maximum resident set size, and before/after VRAM snapshots.

**Likely failures:** CUDA OOM during model load. If that happens, preserve the failed log, reduce `BASELINE_NGL` in `config.env`, and label the run an adapted baseline rather than claiming exact reproduction.

**GTX 1070 note:** extra VRAM may make the naive split faster than the video's GTX 1060, reducing the apparent optimization ratio.

> needed to reduce `BASELINE_NGL` from 20 to 15
> 🔥 Observed: [ Prompt: 32.6 t/s | Generation: 11.9 t/s ]

### 4.4 02:52 - MoE breakthrough

**Objective:** keep all expert tensors in CPU memory while making all other layers GPU-eligible.

**Technical change:** use `-ngl all --n-cpu-moe 41`. Current llama.cpp accepts 41 even though the model has 40 layers; all 40 expert blocks match CPU overrides.

**Command:**

```bash
./scripts/05_run_moe_cpu.sh
```

**Expected observation:** the video reports about 10 tok/s, up from 3. The log should show CPU buffers for expert tensors and CUDA placement for smaller non-expert tensors.

**Validation:** compare the `Generation:` tokens/second against the baseline using exactly the same prompt, context, output length, threads, and seed.

**Likely failures:** older binaries rejecting `--n-cpu-moe`, automatic fitting changing placement, or GPU OOM from a projector. The pinned command uses `--fit off` and `--no-mmproj` to prevent those confounders.

**GTX 1070 note:** with 8 GB, `-ngl all` should have more headroom for non-expert tensors. This does not mean all model weights are on GPU.

> 🔥 Observed: [ Prompt: 51.1 t/s | Generation: 19.2 t/s ]

### 4.5 04:33 - Fixing memory bottlenecks

**Objective:** test whether eager host allocation removes page-fault and storage-related latency variance.

**Technical change:** add `--no-mmap`, causing llama.cpp to read model data into allocated memory rather than use file-backed mappings.

**Command:**

```bash
./scripts/06_run_no_mmap.sh
```

**Expected observation:** slower startup and higher committed/resident RAM, but steadier generation. The video reports 10 to 13.5 tok/s and about 4 GB GPU use.

**Validation:** run baseline and no-mmap at least three times, including after dropping neither caches nor rebooting. Compare generation t/s and variance, not only the fastest run. `/usr/bin/time -v` in each log records maximum RSS.

**Likely failures:** insufficient host RAM, process killed by the OOM killer, or no measurable speed difference because the file is already warm in the Linux page cache.

**GTX 1070 note:** this optimization is primarily host-memory/storage behavior; the different GPU does not guarantee a gain.

> 🔥 Observed : [ Prompt: 51.6 t/s | Generation: 18.9 t/s ]

### 4.6 05:32 - Hitting 17 tok/s

**Objective:** move a controlled number of expert blocks from CPU to GPU and locate the throughput/VRAM frontier.

**Technical change:** test decreasing `--n-cpu-moe` values. A lower value leaves more final-layer experts GPU-eligible. Current semantics make `35` keep layers 0-34 on CPU and leave layers 35-39 eligible for GPU.

**Command:**

```bash
MOE_VALUES="40 38 36 35 34 32 30 28 26 24 22 20 18" ./scripts/07_tune_layers.sh
```

**Expected observation:** generation throughput should rise as expert transfers fall, until VRAM is exhausted. The video reports 13.5 to 17 tok/s and 4 to 5.5 GB VRAM at 35.

**Validation:** select the lowest successful `n-cpu-moe` whose repeated generation rate improves and whose peak VRAM retains at least 512-1024 MiB for the intended context. The script keeps every OOM log rather than stopping at the first failure.

**Likely failures:** immediate OOM, no speed gain because CPU compute dominates, or context allocation later failing despite a short-context layer test passing.

**GTX 1070 note:** begin with the video's 35, then test 34 and 32. The extra 2 GB may accept more expert weights, but this is empirical. Do not assume layer weights are uniform.

> Observed: 40 [ Prompt: 12.4 t/s | Generation: 7.9 t/s ]
> Observed: 38 [ Prompt: 54.6 t/s | Generation: 19.9 t/s ]
> Observed: 36 [ Prompt: 55.3 t/s | Generation: 20.3 t/s ]
> Observed: 34 [ Prompt: 61.1 t/s | Generation: 21.1 t/s ]
> Observed: 32 [ Prompt: 63.7 t/s | Generation: 21.5 t/s ]
> Observed: 30 [ Prompt: 62.2 t/s | Generation: 22.3 t/s ]
> Observed: 28 OOM
> Observed: 26 OOM
> Observed: 24 OOM
> Observed: 22 OOM
> Observed: 20 OOM
> Observed: 18 OOM

### 4.7 06:40 - 4x context trick

**Objective:** allocate 64K, 128K, and 256K contexts with compressed KV cache and identify the largest stable allocation.

**Technical change:** add TurboQuant cache types and increase `-c`. Three profiles make upstream changes explicit:

| Profile | K cache | V cache | Purpose |
|---|---|---|---|
| `video` | `turbo4` | `turbo3` | Closest reconstruction of spoken settings; now discouraged without quality testing |
| `safe` | `q8_0` | `turbo3` | Current fork's recommended asymmetric default |
| `upstream` | `q8_0` | `q8_0` | No fork-only codec; useful control |

**Commands:**

```bash
CACHE_PROFILE=video ./scripts/08_test_context.sh
CACHE_PROFILE=safe ./scripts/08_test_context.sh
CACHE_PROFILE=upstream CONTEXTS="65536 131072" ./scripts/08_test_context.sh
RUN_RETRIEVAL=1 CACHE_PROFILE=safe CONTEXTS="65536 131072 262144" ./scripts/08_test_context.sh
```

**Expected observation:** the video reports 128K at 5.3 GB VRAM, 256K OOM with 35, and 256K success at 5.9/6 GB with 36 while retaining 17 tok/s. This host has 8 GB, so 256K may fit more comfortably, but current model/cache behavior can differ.

**Validation:** the default run proves allocation and short generation only. `RUN_RETRIEVAL=1` additionally creates a deterministic prompt at approximately 80% of each context, puts key `31415` at 75% prompt depth, runs `llama-completion`, and fails if the key is absent. Exact token count is tokenizer-dependent, so inspect the prompt-processing count in each retrieval log. Compare `video` and `safe` profiles with the same generated prompt.

**Likely failures:** CUDA OOM, host allocation failure, TurboQuant kernel failure on Pascal, or coherent short output but degraded long-context retrieval.

**GTX 1070 note:** use the 8 GB to retain higher K precision. Prefer `safe`; only retain the video profile if quality and stability tests pass.

Current upstream correction: Qwen3.6 has native 262,144 context. The trick expands the video's tested runtime configuration from 64K to 256K; it is not four times the model's official training context.

> 🔥 Observed: They all passed (took forever though...)

### 4.8 09:23 - Stability fix

**Objective:** prove that CPU-resident model pages are locked and remain resident under controlled memory pressure.

**Technical change:** raise `RLIMIT_MEMLOCK`, add `--mlock`, then inspect the running process rather than trusting startup text.

Native login configuration:

```bash
sudo tee /etc/security/limits.d/99-llama-memlock.conf >/dev/null <<EOF
$USER soft memlock unlimited
$USER hard memlock unlimited
EOF
```

Fully log out and back in. A new terminal inside the old login session is insufficient. Then run:

```bash
ulimit -Sl
ulimit -Hl
./scripts/09_stability_mlock.sh
STABILITY_SECONDS=86400 STABILITY_INTERVAL=300 ./scripts/09_stability_mlock.sh
```

For a systemd service, add `LimitMEMLOCK=infinity` under `[Service]`. For Docker, use both controls:

```bash
--cap-add IPC_LOCK --ulimit memlock=-1:-1
```

**Expected observation:** `VmLck` in `/proc/PID/status` is measured in KiB and should be many GiB, not 12 or 64 KiB. The script also sends a chat-completion request before stopping the server.

**Validation:** inspect `mlock_*_proc_status.txt`, `/proc/PID/limits`, and the generation response. The immediate test fails below 1 GiB locked. The second command performs a 24-hour soak, sends a request every five minutes, and records RSS, locked memory, process swap, cumulative major faults, and VRAM in `mlock_*_telemetry.csv`. Deliberate host-memory pressure is not automated because it can kill desktop workloads; if used, add it only after establishing a no-pressure control.

**Likely failures:** hard limit still 64 KiB, PAM limits not applied, missing Docker `IPC_LOCK`, process lacking available RAM, or locking more memory than intended.

**GTX 1070 note:** no direct GPU effect. With 62 GiB host RAM, locking a roughly 21 GB model is practical, but leave at least 16 GiB for the OS and other processes.

### 4.9 11:04 - What failed

**Objective:** document the video's dead end without accidentally treating it as an optimization milestone.

**Technical change:** none in the default package. The video adds a Qwen3.5 800M draft model, drafts eight tokens, reaches about 65% acceptance, and regresses from 17 to 11 tok/s.

**Commands:** download a pinned, inferred Qwen3.5 0.8B Q4_K_M draft and run an eight-token external draft window:

```bash
DOWNLOAD_DRAFT=1 ./scripts/03_get_model.sh

$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-cli \
  -m $HOME/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  --no-mmproj --fit off -ngl all --n-cpu-moe 35 --no-mmap -c 4096 \
  --spec-type draft-simple \
  --spec-draft-model $HOME/llama-low-vram-repro/models/Qwen3.5-0.8B-Q4_K_M.gguf \
  --spec-draft-ngl all --spec-draft-n-max 8 \
  -t 4 -tb 8 --single-turn --show-timings --verbose --seed 42 -n 128 \
  -p "Explain in five concise points why mixture-of-experts inference can use less compute than a dense model."
```

The draft repository, revision, quant, and SHA are external reconstruction choices because the video omits them. This command tests the described mechanism but cannot establish that its draft artifact is byte-identical to the author's. `--verbose` exposes informational speculative-decoding statistics; compare both accepted/drafted tokens and the final `Generation:` rate with the matching non-speculative run.

Current llama.cpp has both ordinary draft-model and Qwen3.6 MTP paths, but Qwen3.6's native MTP is a different experiment from the video's Qwen3.5 800M external draft. Establish the non-speculative result first. If testing later, use a separate benchmark row and require both acceptance and end-to-end t/s to improve.

**Expected observation:** if the video path is faithfully reconstructed, acceptance can look reasonable while throughput declines due to extra draft work, hybrid recurrent state, and MoE expert access.

**Validation:** compare identical target-model placement, prompt, output length, and seed with and without speculation. A failed reproduction is any claim of speedup based only on acceptance rate.

**Likely failures:** tokenizer mismatch, draft/target incompatibility, higher VRAM use, lower throughput, or unsupported hybrid-state verification.

**GTX 1070 note:** Pascal has no tensor cores and limited spare VRAM; a draft model is less likely to be free. Keep this path disabled in final configurations unless measured otherwise.

### 4.10 13:32 - The 5 flags

**Objective:** assemble and understand the video's five-option optimization set.

Closest reconstruction:

```text
--n-cpu-moe 36
--no-mmap
--cache-type-k turbo4
--cache-type-v turbo3
--mlock
```

Placement still requires `-ngl all`, and reproducing the final context requires `-c 262144`; those are operational controls beyond the video's “five flags” count.

**Command:** use the “Closest to the video” command in section 8 only after chapters 1-8 pass.

**Expected observation:** stable generation with substantial locked RAM, near-full but non-OOM VRAM, and 256K context allocation. The video's 17 tok/s and 5.9 GB values apply to its GTX 1060 stack, not automatically to this host.

**Validation:** run `10_benchmark.sh`, then a 24-hour server stability test and a long-context retrieval test. Record the exact source/model revisions from the logs.

**Likely failures:** silent lack of memory locking, quality loss from TurboQuant K, or an OOM hidden by changing more than one variable at a time.

**GTX 1070 note:** the final recommended default is not the literal five-flag set. The current safer K/V policy and this card's extra 2 GB justify a higher-precision K cache.

## 5. Reproduction plan

Run the stages in order and do not advance after an unexplained failure:

1. Run `00_host_check.sh` and archive output.
2. Close Steam and GPU-heavy desktop applications. Record idle VRAM.
3. Run `01_install_deps.sh`, then rerun with `INSTALL_CUDA=1` if native CUDA 12.2 is absent.
4. Build pinned fork revision `c26cbdff...` with `02_build_llamacpp.sh`.
5. Download and verify pinned `UD-Q4_K_S` with `03_get_model.sh`.
6. Run `04_run_baseline.sh`; preserve OOM as evidence and adapt only `BASELINE_NGL` if required.
7. Run `05_run_moe_cpu.sh`; compare generation t/s with the baseline.
8. Run `06_run_no_mmap.sh`; compare repeated-run variance and RSS.
9. Run `07_tune_layers.sh`; choose the fastest placement with adequate VRAM margin.
10. Run `08_test_context.sh` with `safe`, then `video`, then the upstream control.
11. Raise memlock limits and run `09_stability_mlock.sh`.
12. Run `10_benchmark.sh` under otherwise idle conditions.
13. Repeat benchmark phases three times after a reboot and report median token-generation t/s.
14. Start the selected final server command and run context retrieval plus 8-24 hour stability checks.

### Docker path

Docker GPU passthrough works on this host, but build a Pascal-specific local image rather than relying on the stock broad-architecture image. From a clean checkout at the pinned fork revision:

```bash
docker build \
  --build-arg UBUNTU_VERSION=22.04 \
  --build-arg CUDA_VERSION=12.2.2 \
  --build-arg GCC_VERSION=11 \
  --build-arg CUDA_DOCKER_ARCH=61-real \
  --target light \
  -f .devops/cuda.Dockerfile \
  -t local/llama-turboquant:cuda12.2-sm61 .
```

Representative invocation:

```bash
docker run --rm -it --gpus all \
  --cap-add IPC_LOCK --ulimit memlock=-1:-1 \
  -v "$HOME/llama-low-vram-repro/models:/models:ro" \
  --entrypoint /app/llama-cli \
  local/llama-turboquant:cuda12.2-sm61 \
  -m /models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf --no-mmproj \
  -ngl all --n-cpu-moe 36 --no-mmap --mlock \
  --cache-type-k q8_0 --cache-type-v turbo3 -c 131072 -n 128
```

The video used Proxmox to LXC to Docker. This host appears to be native Ubuntu, so LXC configuration is unnecessary. If moved into LXC, the container must itself be permitted to lock memory and pass the NVIDIA devices through before Docker's capability and ulimit can work.

## 6. Scripts

The requested script progression is retained. `_common.sh` was added only to centralize pinned revisions, paths, logging, and identical benchmark arguments.

| Script | Chapter | Function | Writes results |
|---|---|---|---|
| `00_host_check.sh` | 00:00/00:27 | Read-only suitability check | stdout |
| `01_install_deps.sh` | 00:27 | Build dependencies, HF CLI, optional CUDA 12.2 | system packages and tool venv |
| `02_build_llamacpp.sh` | 00:27 | Pinned TurboQuant CUDA build for `61-real` | `$WORK_DIR/llama-cpp-turboquant` |
| `03_get_model.sh` | 00:27/11:04 | Pinned target GGUF; optional pinned draft with `DOWNLOAD_DRAFT=1` | `$MODEL_DIR` |
| `04_run_baseline.sh` | 01:46 | `-ngl 20` baseline | phase log/snapshots |
| `05_run_moe_cpu.sh` | 02:52 | all experts on CPU | phase log/snapshots |
| `06_run_no_mmap.sh` | 04:33 | eager model load | phase log/snapshots |
| `07_tune_layers.sh` | 05:32 | CPU-MoE placement sweep | one directory per sweep |
| `08_test_context.sh` | 06:40 | 64K/128K/256K allocation; optional filled-context retrieval | one directory per profile |
| `09_stability_mlock.sh` | 09:23 | lock proof, API request, optional timed soak | log, proc status, responses, telemetry |
| `10_benchmark.sh` | 13:32 | repeatable `llama-bench` phase matrix | logs, GPU telemetry, summary |

Override defaults by creating `config.env` from `config.env.example`. Every run script also forwards additional CLI arguments, for example:

```bash
./scripts/04_run_baseline.sh --verbose
CONTEXTS="65536 131072" CACHE_PROFILE=safe ./scripts/08_test_context.sh
```

Do not point `SOURCE_DIR` at a checkout containing unrelated work. The build script refuses to switch revisions when its dedicated checkout has uncommitted changes.

## 7. Validation and benchmarks

### Metrics

| Metric | Capture method | Success criterion | Failed reproduction |
|---|---|---|---|
| Token generation t/s | `Generation:` from pinned `llama-cli`; `tg128` from `llama-bench` | Median improves at the claimed phase without changed workload | Comparing prompt t/s (`pp`) to generation t/s (`tg`) or one cherry-picked run |
| Prompt processing t/s | `pp128` from `llama-bench` | Reported separately; no required video target | Conflated with decode speed |
| Host RAM | `/usr/bin/time -v`, `free -b`, process status | `--no-mmap` fits with at least 16 GiB host headroom | OOM kill, swap growth, or unexplained major faults |
| VRAM | phase snapshots and 500 ms `nvidia-smi` telemetry | No CUDA OOM and at least 512 MiB practical margin | Peak reaches limit or desktop becomes unstable |
| Context allocation | `08_test_context.sh` process exit and log | Requested `-c` allocates and generates tokens | Load-only success, OOM, or silent context reduction |
| Context behavior | passkey/retrieval prompt near target length | Correct retrieval at 64K/128K/256K for chosen cache profile | Coherent short prompts but failed long retrieval |
| Locked memory | `VmLck` and process limit | Many GiB locked and stable over time | 12/64 KiB, limit mismatch, or swap activity |
| Stability | repeated fixed prompt over 8-24 hours | No crash, OOM, t/s collapse, or growing faults | Any sustained regression not explained by thermal throttling/load |

### Benchmark controls

- Reboot before the final series or explicitly report warm page cache.
- Close Steam and GPU-heavy applications.
- Keep model file, source revision, prompt tokens, generated tokens, context, threads, and sampling fixed.
- Run each phase at least three times and report median plus range.
- Record GPU temperature, clock/pstate, and VRAM.
- Never compare a 4K-context baseline against a 256K optimized run as a pure placement benchmark.
- Test output quality before accepting more aggressive KV compression.

### Expected comparison table

Fill measured columns from generated logs; video values are references, not pass/fail guarantees.

| Phase | Key change | Video generation t/s | This host t/s | Video VRAM | This host peak VRAM | Context |
|---|---|---:|---:|---:|---:|---:|
| Baseline | `-ngl 20` | ~3 | TBD | not stated | TBD | test 4K |
| MoE CPU | `--n-cpu-moe 41` | ~10 | TBD | not stated | TBD | test 4K |
| Eager load | `--no-mmap` | ~13.5 | TBD | ~4 GB | TBD | test 4K |
| Tuned placement | `--n-cpu-moe 35` | ~17 | TBD | ~5.5 GB | TBD | ~64K video claim |
| TurboQuant 128K | Turbo4/Turbo3 | ~17 | TBD | ~5.3 GB | TBD | 128K |
| TurboQuant 256K | CPU-MoE 36 | ~17 | TBD | ~5.9 GB | TBD | 256K |
| Mlock stability | `--mlock` | ~17 | TBD | unchanged | TBD | selected |
| External draft | Qwen3.5 800M | ~11 | not default | not stated | not tested | not stated |

The closest milestone criterion is directional reproduction: MoE-aware placement must materially beat the naive split, eager loading must improve or stabilize decode latency, and a tuned placement must outperform all-experts-on-CPU without OOM. Reaching exactly 17 tok/s is not required to prove those mechanisms on different hardware and a now-explicit model quant.

## 8. Final recommended configurations

All native commands assume `ulimit -Sl` and `ulimit -Hl` report `unlimited`. Omit `--mlock` until that is true.

### Closest to the video

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  -m $HOME/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  --no-mmproj --fit off -ngl all --n-cpu-moe 36 \
  --no-mmap --cache-type-k turbo4 --cache-type-v turbo3 --mlock \
  -c 262144 -t 4 -tb 8 --flash-attn auto \
  --host 127.0.0.1 --port 8080
```

Rationale: reproduces the inferred five flags, final CPU-MoE value, and binary 256K context.

Tradeoffs: aggressive K compression conflicts with current fork guidance; 256K allocation has the highest Pascal stability/OOM risk; exact video quant remains unknown.

### Safer / lower risk

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  -m $HOME/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  --no-mmproj --fit off -ngl all --n-cpu-moe 40 \
  --no-mmap --cache-type-k q8_0 --cache-type-v turbo4 --mlock \
  -c 65536 -t 4 -tb 8 --flash-attn auto \
  --host 127.0.0.1 --port 8080
```

Rationale: almost all experts remain on CPU, context is moderate, K is near-lossless Q8, and V uses the fork's lightest TurboQuant tier.

Tradeoffs: lower throughput than a tuned GPU placement and only 64K runtime context.

### Best effort for GTX 1070

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  -m $HOME/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  --no-mmproj --fit off -ngl all --n-cpu-moe 34 \
  --no-mmap --cache-type-k q8_0 --cache-type-v turbo3 --mlock \
  -c 131072 -t 4 -tb 8 --flash-attn auto \
  --host 127.0.0.1 --port 8080
```

Rationale: spends the GTX 1070's extra 2 GB on more GPU-eligible expert weights while retaining the current recommended asymmetric cache and a substantial 128K context.

Tradeoffs: `34` is a starting hypothesis, not a measured optimum. Replace it with the best value from `07_tune_layers.sh`; increase to 35/36 if VRAM margin is below 512 MiB or long context OOMs.

## 9. Uncertainties and gaps

### Directly supported by local files

- Video hardware, broad stack, progression, stated flags, reported t/s, reported VRAM/context changes, mlock observations, and failed external-draft result.
- The author describes `--n-cpu-moe 41`, then 35, then 36.
- The author describes Turbo4 for keys and Turbo3 for values.

### Externally verified

- Exact Qwen3.6 architecture, native context, base repository, and current GGUF options.
- Exact current CLI semantics and aliases.
- TurboQuant fork status and changed K/V safety recommendation.
- CUDA/Pascal lifecycle and this host's need for a CUDA 12 `sm_61` build.
- Docker GPU passthrough on this host.

### Inferred

- `UD-Q4_K_S` as the practical roughly-20-GB video analogue.
- `-ngl all` in MoE-aware phases because the transcript says non-expert work goes to GPU but does not print final placement.
- Binary-style `131072` and `262144` context values rather than decimal 128000/256000.
- Fixed prompt, output length, thread counts, and benchmark process.
- TurboQuant fork revision and local path layout.

### Host-dependent empirical items

- Largest successful `-ngl` baseline.
- Optimal `--n-cpu-moe` for 8 GB.
- Whether TurboQuant CUDA kernels are correct and beneficial on GTX 1070.
- Actual generation speed and whether 17 tok/s is feasible.
- Exact VRAM at 64K/128K/256K.
- Long-context retrieval quality under each KV profile.
- PCIe link speed, host RAM bandwidth, thermals, and sustained clocks.
- Whether `--no-mmap` improves a warm-cache workload.

The transcript's “six layers moved back” conflicts with current 40-layer, first-N semantics at `--n-cpu-moe 35`; current implementation leaves five expert blocks eligible. The model's official 262,144 native context also conflicts with the claim that 256K is four times its training context. Both discrepancies are retained as source differences, not silently corrected into video facts.

## 10. Appendix

### Glossary

| Term/flag | Meaning |
|---|---|
| GGUF | llama.cpp model container; distinct from the official Safetensors repository |
| MoE | Mixture of Experts; only a routed subset of expert FFNs activates per token |
| `-ngl N` | Maximum model layers eligible for GPU storage; current aliases include `--n-gpu-layers` |
| `-ngl all` | Make all layers GPU-eligible, subject to explicit tensor CPU overrides |
| `--n-cpu-moe N` | Keep MoE expert tensors for the first N layers on CPU |
| `--cpu-moe` | Keep all MoE expert tensors on CPU; `--n-cpu-moe` is used here to reproduce numeric tuning |
| mmap | File-backed model mapping managed by the OS page cache |
| `--no-mmap` | Read model data into allocations rather than retaining file-backed mappings |
| `--mlock` | Ask the OS to lock model memory; requires a sufficient process limit/capability |
| KV cache | Attention keys and values retained for prior tokens; grows with attention context |
| `--cache-type-k/v` | Select K and V cache storage types independently |
| TurboQuant | Fork-only rotated low-bit KV codec family in this package |
| `-c N` | Runtime context allocation in tokens; Qwen3.6 natively supports 262,144 |
| `--fit off` | Disable current automatic memory fitting so a phase's requested placement remains controlled |
| `--no-mmproj` | Skip the roughly 0.9 GB vision projector for this text-only reproduction |
| pp/tg | Prompt-processing and token-generation benchmark rates; do not compare them interchangeably |

### Upstream links

- Video: https://www.youtube.com/watch?v=8F_5pdcD3HY
- Official model: https://huggingface.co/Qwen/Qwen3.6-35B-A3B
- Pinned GGUF repository: https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/tree/a483e9e6cbd595906af30beda3187c2663a1118c
- TurboQuant llama.cpp fork: https://github.com/TheTom/llama-cpp-turboquant/tree/c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea
- TurboQuant+ codec documentation: https://github.com/TheTom/turboquant_plus
- Upstream llama.cpp: https://github.com/ggml-org/llama.cpp/tree/2beefef68825aed8de05f0d89981bf5d05266a3c
- llama.cpp CUDA build guide: https://github.com/ggml-org/llama.cpp/blob/2beefef68825aed8de05f0d89981bf5d05266a3c/docs/build.md#cuda
- llama.cpp Docker guide: https://github.com/ggml-org/llama.cpp/blob/2beefef68825aed8de05f0d89981bf5d05266a3c/docs/docker.md
- NVIDIA CUDA compatibility: https://docs.nvidia.com/deploy/cuda-compatibility/minor-version-compatibility.html
- CUDA 12.9.1 Pascal deprecation notice: https://docs.nvidia.com/cuda/archive/12.9.1/cuda-toolkit-release-notes/index.html#deprecated-architectures
- CUDA 13 Pascal removal notice: https://docs.nvidia.com/cuda/archive/13.0.0/cuda-toolkit-release-notes/index.html#deprecated-architectures
- Linux `RLIMIT_MEMLOCK`: https://man7.org/linux/man-pages/man2/getrlimit.2.html

### End-to-end checklist

- [ ] Host check archived.
- [ ] CUDA 12.x `nvcc` available; CUDA 13 not used.
- [ ] Fork and model revisions match `config.env.example`.
- [ ] Model SHA-256 passes.
- [ ] Baseline result or OOM preserved.
- [ ] CPU-MoE phase beats or explains divergence from baseline.
- [ ] No-mmap repeated runs measured.
- [ ] Best CPU-MoE value selected with VRAM margin.
- [ ] 64K and 128K allocation plus retrieval pass.
- [ ] 256K result recorded, whether pass or OOM.
- [ ] Safe and video cache profiles quality-compared.
- [ ] `VmLck` proves GiB, not KiB, are locked.
- [ ] Final benchmark repeated at least three times.
- [ ] 8-24 hour stability test passes before unattended use.
