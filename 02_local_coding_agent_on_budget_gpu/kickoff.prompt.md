# Objective

Reproduce, on this host, every practical setup phase, optimization, and validated milestone from the YouTube video **“Build Powerful Local Coding Agent on Budget GPU with Llama.cpp and Pi.”**

The target system has an NVIDIA GTX 1070. The video reportedly runs REAP/GGUF MoE coding models—such as `Qwen3.6-28B-REAP20-A3B` and `GLM-4.7-Flash-REAP-23B-A3B-GGUF`—on a GTX 1060 by combining limited GPU layer offload with system RAM and llama.cpp optimizations. Adapt all recommendations conservatively for the GTX 1070 while preserving the video’s intended milestones.

# Inputs and Existing Assets

Use these local files as primary sources:

- Video transcript: `02_local_coding_agent_on_budget_gpu.txt`
- Video description: `description.txt`
- Reference implementation from the preceding video: `01_running_a_35b_ai_model_on_6GB_vram_llamacpp/`
- Existing custom CUDA-enabled llama.cpp TurboQuant build: `~/llama-low-vram-repro/llama-cpp-turboquant/build`

Do not recompile CUDA Toolkit or llama.cpp. Do not alter global system configuration, drivers, or existing installations unless explicitly required and justified. Prefer isolated project-local files, virtual environments, and reversible actions.

You may use web research to verify model availability, exact model filenames, current llama.cpp flags, Pi requirements, and any video-linked resources. Treat the transcript and description as the authority for reproducing the video; use external sources only to fill in missing operational details or confirm commands.

# Required Workflow

1. **Inspect the prior project first**
   - Examine `01_running_a_35b_ai_model_on_6GB_vram_llamacpp/` before planning the new project.
   - Infer and document its conventions: directory layout, script naming, environment variables, logging format, validation style, model storage locations, and expected outputs.
   - Reuse these conventions in `02_local_coding_agent_on_budget_gpu/` unless the new video requires a deliberate deviation.

2. **Analyze the source material**
   - Read the full transcript and description.
   - Identify every distinct video chapter, phase, command, installation, download, configuration change, benchmark, optimization, troubleshooting action, and claimed result.
   - Build a traceability matrix mapping each transcript milestone to:
     - the corresponding guide section,
     - the script(s) that implement it,
     - prerequisites,
     - expected output,
     - validation command or acceptance criterion,
     - rollback or cleanup guidance where applicable.
   - Clearly distinguish:
     - directly stated video steps,
     - reasonable adaptations for the GTX 1070,
     - assumptions or gaps requiring user confirmation.

3. **Delegate research and review**
   - Use sub-agents aggressively for independent workstreams, including:
     - transcript chapter extraction and milestone mapping,
     - comparison against the previous project’s structure,
     - model/download verification,
     - llama.cpp flag and low-VRAM optimization research,
     - Pi installation and integration research,
     - validation/benchmark design,
     - safety and reproducibility review.
   - Consolidate sub-agent findings. Resolve conflicts in favor of transcript evidence, reproducibility, and non-destructive execution.

4. **Create a reproducible project**
   - Create or update a project directory named `02_local_coding_agent_on_budget_gpu/`.
   - Keep all deliverables under this directory, except model files if the previous project establishes a shared model directory.
   - Make scripts idempotent: safe to rerun, clear about already-completed work, and avoid duplicate downloads or destructive overwrites.
   - Use `set -euo pipefail` in Bash scripts where appropriate, provide helpful error messages, and quote paths safely.
   - Never download large models automatically without a separate explicit download script and a displayed size estimate/confirmation step.

# Required Deliverables

Create the following, adapting names only if the prior project establishes a stronger convention:

```text
02_local_coding_agent_on_budget_gpu/
├── README.md
├── PLAN.md
├── MILESTONES.md
├── TRANSCRIPT_TRACEABILITY.md
├── ENVIRONMENT.md
├── MODELS.md
├── TROUBLESHOOTING.md
├── VALIDATION.md
├── scripts/
│   ├── 00_preflight.sh
│   ├── 01_verify_existing_llamacpp.sh
│   ├── 02_install_pi.sh
│   ├── 03_download_models.sh
│   ├── 04_start_model_server.sh
│   ├── 05_run_pi_agent.sh
│   ├── 06_benchmark.sh
│   ├── 07_validate_milestones.sh
│   └── lib/
│       └── common.sh
├── configs/
│   ├── env.example
│   ├── model-profiles.example.sh
│   └── pi-config.example.*
├── logs/
│   └── .gitkeep
└── results/
    └── .gitkeep
```

If a different structure from the preceding project is more appropriate, follow it consistently and explain the difference in `README.md`.

# Script Requirements

## Preflight and hardware verification

`00_preflight.sh` must:

- Detect OS, shell, CPU, installed RAM, available disk space, NVIDIA driver, CUDA visibility, and GPU name/VRAM.
- Confirm that the detected GPU is compatible with the expected GTX 1070 target, while warning rather than failing if hardware differs.
- Verify that the existing llama.cpp build directory exists and identify usable binaries, especially `llama-server` and `llama-cli`.
- Detect whether the build exposes CUDA support and record version/help output.
- Check required utilities such as `curl`, `wget`, `git`, `python3`, `node`, `npm`, and `nvidia-smi`, without silently installing system packages.
- Write a timestamped environment report to `logs/` and print a concise pass/warn/fail summary.

## Existing llama.cpp verification

`01_verify_existing_llamacpp.sh` must:

- Use `~/llama-low-vram-repro/llama-cpp-turboquant/build` as the default build path, configurable through an environment variable.
- Locate actual binary paths instead of assuming a specific CMake output layout.
- Capture `--help` output and identify supported flags relevant to:
  - model selection,
  - GPU layer offload,
  - context length,
  - parallel slots,
  - KV-cache quantization,
  - Flash Attention,
  - CPU thread settings,
  - memory mapping/locking,
  - server/API configuration.
- Avoid presenting unsupported flags as available. If a transcript command uses a changed or unsupported option, document a compatible equivalent only when verified.
- Produce a machine-readable capability report in `results/`.

## Model handling

`03_download_models.sh` and `MODELS.md` must:

- Identify the exact models, quantizations, and repositories used or linked by the video.
- If exact files cannot be established, present clearly labeled candidates rather than guessing.
- Include model size, architecture/MoE characteristics where relevant, required storage, source URL, filename, checksum if available, license or gated-access requirements, and expected RAM/VRAM implications.
- Require the user to select a model profile and confirm before downloading.
- Support resumable downloads and integrity validation where possible.
- Store models according to the preceding project’s convention.
- Never embed access tokens in files, logs, or commands.

## llama.cpp server profiles

`04_start_model_server.sh` plus `configs/model-profiles.example.sh` must:

- Provide named, editable profiles for each model and stage of the video.
- Start the existing llama.cpp server with the model path, host, port, GPU-layer count, context window, KV-cache types, attention settings, threads, batch settings, and any video-specific options.
- Make all potentially machine-specific values configurable through environment variables or named profiles.
- Include conservative defaults for a GTX 1070 and stepwise profiles that mirror the video’s progression.
- Explain the expected trade-offs: VRAM, RAM, prompt processing speed, generation speed, context length, stability, and quality.
- Log the complete resolved command line and server startup output.
- Detect server readiness with a local health/API request before declaring success.
- Provide a safe shutdown method and prevent accidental exposure to the local network by default.

## Pi setup and agent integration

`02_install_pi.sh`, `05_run_pi_agent.sh`, and the Pi guide must:

- Determine the precise “Pi” coding-agent tool referenced in the transcript/description; do not assume a package solely from its name.
- Install it in an isolated, reproducible way consistent with the previous project and the host.
- Configure Pi to use the local llama.cpp OpenAI-compatible endpoint.
- Preserve API keys and credentials outside version-controlled files.
- Include a minimal non-destructive coding-agent smoke test using a disposable test workspace.
- Explain any limitations of local model tool use, context handling, reasoning behavior, coding quality, and model-specific compatibility.

## Performance and context optimization

Represent each video optimization as a separate, reproducible stage. For every stage, document:

- The exact goal and video reference.
- Prerequisites.
- Changed parameters.
- Why the change should help.
- Expected resource impact.
- A test command.
- Pass/fail or acceptable-range criteria.
- Reversal instructions.

Address, where relevant and supported by the existing build/model:

- Partial GPU offload and selecting a stable layer count.
- System-RAM offload behavior and its performance consequences.
- Context-window tuning.
- KV-cache quantization.
- Flash Attention compatibility.
- Batch size and micro-batch tuning.
- CPU thread tuning.
- Memory mapping, memory locking, and cache behavior.
- Parallel requests/slots only when appropriate.
- Prompt ingestion versus token-generation performance.
- MoE-specific implications.
- Long-context reliability and failure recovery.

Do not claim that a setting improves performance unless it is measured on this host or explicitly stated as a hypothesis to test.

# Validation and Benchmarking

`06_benchmark.sh`, `07_validate_milestones.sh`, `VALIDATION.md`, and `MILESTONES.md` must validate the reproduction rather than merely start services.

For each milestone in the video, provide:

- Setup/profile used.
- Exact command.
- Input prompt or test fixture.
- Expected observable output.
- Required log evidence.
- Resource checks: GPU VRAM, system RAM, CPU utilization, disk usage where relevant.
- Performance metrics: model load time, prompt-processing speed, generation speed, and stability over a defined test duration where feasible.
- A clear status format: `PASS`, `WARN`, `FAIL`, or `NOT RUN`.
- A concise explanation for deviations from the video caused by hardware, software version, unavailable model artifacts, or transcript ambiguity.

Use non-destructive test prompts and a disposable working directory for agent tests. Save timestamped raw logs and concise result summaries under `logs/` and `results/`.

# Documentation Standards

`README.md` must be the main operator guide and include:

1. What this project reproduces.
2. Hardware and software assumptions.
3. What is reused from the prior project.
4. Quick-start sequence.
5. Model-selection and download instructions.
6. The progression through video chapters.
7. How to launch, use, stop, and troubleshoot the server and Pi agent.
8. How to run benchmarks and validate milestones.
9. Known differences from the video and GTX 1060-to-GTX 1070 adaptations.
10. Safety, disk-space, RAM-pressure, and network-exposure notes.

All Markdown guides must use clear headings, copy-paste-ready commands, explicit placeholders, and explanations of expected output. Do not fabricate successful results; label unexecuted steps as planned and provide the exact command the user should run.

# Execution Boundaries

- First inspect and report the repository/file structure and source-material findings before making changes.
- Do not compile or modify the existing custom CUDA Toolkit or llama.cpp build.
- Do not perform destructive operations, modify global configuration, install system-wide dependencies, or delete files.
- Do not automatically download multi-gigabyte models, start persistent services, or run long benchmarks without explicit confirmation.
- Do not expose the llama.cpp server beyond `127.0.0.1` unless explicitly requested.
- Before any action that consumes more than 5 GB of disk space, substantially changes user files, or may run longer than 15 minutes, stop and ask for confirmation.
- If transcript details conflict with current software behavior, preserve the video’s intent, document the mismatch, and propose the smallest verified adaptation.

# Final Response Format

After completing inspection and preparing the deliverables:

1. Give a concise status report of files inspected and deliverables created or planned.
2. Provide the recommended execution order.
3. List every action requiring user confirmation, especially large model downloads, package installations, persistent server startup, or benchmarks.
4. State any blocked items, uncertainties, or transcript gaps.
5. Include exact next commands for the user to run.

Do not claim the video has been reproduced until every applicable milestone has been executed and validated on this host.

