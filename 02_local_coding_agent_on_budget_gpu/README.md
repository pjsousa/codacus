# Local Coding Agent on a GTX 1070

This project prepares a reproducible, evidence-driven adaptation of **Build Powerful Local Coding Agent on Budget GPU with Llama.cpp and Pi**. It uses the existing CUDA/TurboQuant llama.cpp build, shared model storage, Pi Coding Agent, and the video's REAP/MoE, prefill, cache, and model-switching workflow.

It does **not** claim that the video has been reproduced. Large model downloads, Pi installation, server runs, benchmarks, long-context tests, and remote access require explicit operator decisions. Generated validation keeps unexecuted work as `NOT RUN`.

## Source Correction

The supplied description and transcript say the video uses an **RTX 3060 12 GB**. The kickoff's GTX 1060 statement belongs to the preceding video. This host's GTX 1070 has 8 GB, no tensor cores, and less VRAM, so the video's `1,142` prompt-processing tokens/s and roughly `40` decode tokens/s are reference values only.

## Reused Assets

- Build: `~/llama-low-vram-repro/llama-cpp-turboquant/build`
- Shared models: `~/llama-low-vram-repro/models`
- Existing control model: `Qwen3.6-35B-A3B-UD-Q4_K_S.gguf`
- Prior conventions: ordered strict-mode Bash scripts, quoted command arrays, UTC evidence IDs, checksums, and resource snapshots

New evidence is kept in this project's `logs/` and `results/`; it is not mixed with prior results. This project never recompiles llama.cpp or CUDA.

## Safe Quick Start

Run from this directory:

```bash
./scripts/00_preflight.sh
./scripts/01_verify_existing_llamacpp.sh
./scripts/03_download_models.sh --list
./scripts/07_validate_milestones.sh
```

These commands do not install packages, download models, start a server, or run inference. Inspect:

```bash
ls -1t logs/ results/
```

Optional local overrides:

```bash
cp configs/env.example configs/env.local
```

`configs/env.local` is executable shell configuration and is ignored by Git. Do not put access tokens in command-line arguments or tracked files.

## Model Selection

The strongest practical candidates are:

```bash
./scripts/03_download_models.sh --list
```

- `qwen-reap-q4km`: 17.26 GB. Uses the exact repository linked in the video description and selects the transcript's preferred Q4_K_M quant.
- `glm-reap-q4km`: 14.11 GB. Uses the exact repository linked in the video description and selects the transcript's preferred Q4_K_M quant.

The description identifies the repositories, but not the exact files, quant variants, revisions, or checksums used in the video. The script pins reproducible Q4_K_M selections and prints their revision, exact bytes, SHA-256, license, free space, and remaining ambiguity before requiring an exact confirmation. Example:

```bash
./scripts/03_download_models.sh glm-reap-q4km
# or non-interactively only after reviewing the displayed metadata:
CONFIRM=DOWNLOAD_glm-reap-q4km ./scripts/03_download_models.sh glm-reap-q4km
```

Downloads resume into `.part` files, validate size and checksum, then rename atomically. Mismatched final files are never overwritten.

## Pi Installation

The video tool is Pi Coding Agent with `pi-llama-cpp`. Current pinned versions are Pi `0.80.10` and extension `0.9.1`.

Pi requires Node `>=22.19.0`; the observed host Node 20 is too old. Select a user-local Node 22.19+ installation first. The script then uses official release lockfiles and a project-local npm prefix:

```bash
./scripts/02_install_pi.sh
```

It requires `INSTALL_PI_0.80.10` confirmation, writes packages under `.tools/`, and keeps Pi state under `.state/`. It does not use global npm. Pi and extensions execute with the launching user's permissions; there is no built-in sandbox.

## Server Profiles

List profiles:

```bash
source configs/model-profiles.example.sh
list_model_profiles
```

Profiles:

- `existing-control`: already-local prior model, useful only for stack regression testing.
- `qwen-reap-safe` and `glm-reap-safe`: 8K context, one slot, ubatch 256, all model expert blocks initially on CPU, K=`q8_0`, V=`turbo4`.
- `qwen-reap-video-intent` and `glm-reap-video-intent`: unmeasured hypotheses with larger context/ubatch, partial expert placement, and the transcript's K=`turbo4`, V=`turbo2`.

Start only after reviewing the resolved profile:

```bash
./scripts/04_start_model_server.sh start glm-reap-safe
./scripts/04_start_model_server.sh status
./scripts/04_start_model_server.sh stop
```

An exact `RUN_SERVER_<profile>` confirmation is required. The server defaults to `127.0.0.1:8088`, one slot, offline mode, no Web UI, Jinja tool handling, metrics, and a 12-minute readiness limit. Port 8080 was occupied during inspection and is intentionally not used.

For foreground operation:

```bash
./scripts/04_start_model_server.sh foreground glm-reap-safe
```

Do not bind beyond loopback merely to use Tailscale. See `ENVIRONMENT.md` and `TROUBLESHOOTING.md`.

## Pi Smoke Test

With a verified server running:

```bash
./scripts/05_run_pi_agent.sh
```

After `RUN_PI_SMOKE` confirmation, the script creates a disposable fixture, exposes only Pi's `read` tool, disables sessions and telemetry, requires a tool event plus exact marker response, proves the fixture hash is unchanged, and removes the workspace. Raw JSONL remains in `logs/`.

This is a compatibility smoke test, not a security sandbox or proof of coding quality.

For an interactive session after the smoke test passes:

```bash
PI_CODING_AGENT_DIR="$PWD/.state/pi" \
LLAMA_SERVER_URL="http://127.0.0.1:8088" \
"$PWD/.tools/pi-0.80.10/node_modules/.bin/pi"
```

Use `/models` to inspect or choose llama.cpp router models, `/model` for Pi's model picker, `/new` for a fresh session, and Ctrl+C or `/quit` to exit. Verify that Pi's displayed context matches the server profile. Local model reasoning labels, tool-call syntax, long-context behavior, and coding quality are model/quant/template dependent and require task-specific tests.

## Benchmarks

Run one bounded stage at a time:

```bash
./scripts/06_benchmark.sh smoke glm-reap-safe
./scripts/06_benchmark.sh threads glm-reap-safe
./scripts/06_benchmark.sh ubatch glm-reap-safe
./scripts/06_benchmark.sh kv glm-reap-safe
```

Each stage requires exact confirmation and has a 14-minute hard limit. It records machine-readable llama-bench output, stderr, before/after resources, and 500 ms GPU telemetry. The `kv` stage measures the selected profile; compare safe and video-intent profiles as separate runs rather than attributing placement changes solely to the codec.

Controlled placement comparison:

```bash
N_CPU_MOE_OVERRIDE=47 ./scripts/06_benchmark.sh smoke glm-reap-safe
N_CPU_MOE_OVERRIDE=46 ./scripts/06_benchmark.sh smoke glm-reap-safe
```

Controlled KV comparison at identical placement:

```bash
CACHE_TYPE_K_OVERRIDE=f16 CACHE_TYPE_V_OVERRIDE=f16 \
  ./scripts/06_benchmark.sh kv glm-reap-safe
CACHE_TYPE_K_OVERRIDE=q8_0 CACHE_TYPE_V_OVERRIDE=turbo4 \
  ./scripts/06_benchmark.sh kv glm-reap-safe
```

Then validate cache reuse and bounded context retrieval against the confirmed running server:

```bash
./scripts/08_validate_agent_features.sh cache-reuse
./scripts/08_validate_agent_features.sh context
```

The video progression is:

1. Select MoE and REAP-pruned Q4 models.
2. Tune CPU threads for decode without saturating all four cores.
3. Increase ubatch for agent-oriented prefill while monitoring VRAM.
4. Test TurboQuant K/V choices and use freed VRAM only after quality checks.
5. Connect Pi directly to llama.cpp.
6. Add one-at-a-time model presets and validate switching.
7. Optionally add authenticated Tailscale access.

See `PLAN.md` and `VALIDATION.md` for controlled variables and acceptance criteria.

## Validate Milestones

```bash
./scripts/07_validate_milestones.sh
VALIDATION_PROFILE=glm-reap-safe ./scripts/07_validate_milestones.sh
```

The validator writes JSON and Markdown ledgers. Set `VALIDATION_PROFILE` to bind all model, server, benchmark, Pi, cache, and context evidence to one profile; otherwise `MODEL_PROFILE` is used. Overall precedence is `FAIL`, `NOT RUN`, `WARN`, then `PASS`. Missing or cross-profile evidence cannot become success.

## Model Switching

`configs/models.ini.example` follows this build's `--models-preset` syntax and sets `load-on-startup=false`. After both model paths exist and the file is copied to an ignored local configuration, router mode can be run manually with:

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  --models-preset "$PWD/configs/models.ini.local" \
  --models-max 1 --host 127.0.0.1 --port 8088 \
  --cache-ram 4096 --offline --no-ui --metrics
```

This is intentionally not automatic. Loading two large candidates requires roughly 31.4 GB of disk and switching can stress RAM/VRAM. Validate A to B to A while the router PID remains unchanged, then use Pi's `/models` picker.

With the router PID verified:

```bash
ROUTER_PID=<PID> ./scripts/05_run_pi_agent.sh hot-swap
```

## Remote Access

The video installs Tailscale on the rig and laptop and points Pi at the rig's Tailscale address. Tailscale is not installed here, and installation, enrollment, ACL changes, Serve configuration, persistent daemon behavior, and API authentication are outside the automatic workflow.

Keep llama.cpp on loopback. If remote access is approved later, prefer authenticated Tailscale Serve to `127.0.0.1:8088`, use an API key file with mode `0600`, inspect tailnet ACLs, and never use Funnel. Remote latency must be reported separately from local prefill/decode speed.

## Safety

- Close GPU-heavy applications before inference, but do not let scripts kill unrelated processes.
- Keep at least 1 GiB practical VRAM headroom and 16 GiB available host RAM during tuning.
- Stop on CUDA OOM, swap growth, process death, thermal throttling, or desktop instability.
- `--mlock` is omitted because observed soft/hard memlock limits are 64 KiB. Raising them is a separate global change.
- Large contexts, soak tests, and benchmarks expected to exceed 15 minutes require separate confirmation and are not automated here.
- Model Q4 files exceed GTX 1070 VRAM. MoE reduces active compute, not total weight storage.

## Documentation Map

- `PLAN.md`: staged implementation and reversible optimizations
- `MILESTONES.md`: baseline status ledger
- `TRANSCRIPT_TRACEABILITY.md`: source-to-script matrix
- `ENVIRONMENT.md`: host assumptions and differences
- `MODELS.md`: artifact metadata and ambiguity
- `TROUBLESHOOTING.md`: operational failure recovery
- `VALIDATION.md`: metrics, fixtures, and acceptance
