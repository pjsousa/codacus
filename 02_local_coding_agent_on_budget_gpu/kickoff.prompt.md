```markdown
# Objective

Create a **plan-only, approval-gated project** that reproduces the workflow and milestones from the YouTube video **“Build Powerful Local Coding Agent on Budget GPU with Llama.cpp and Pi”** on this machine, using the provided local video materials and existing custom llama.cpp build.

Do **not** make system-wide changes, compile llama.cpp, rebuild CUDA, download large model files, or start implementation until I explicitly approve the plan.

# Source Materials

Use these local files as the primary source of truth:

- Video transcript: `02_local_coding_agent_on_budget_gpu.txt`
- Video description: `description.txt`
- Prior related experiment: `01_running_a_35b_ai_model_on_6GB_vram_llamacpp/`
- Existing custom TurboQuant-compatible llama.cpp build: `~/llama-low-vram-repro/llama-cpp-turboquant/build/`

You may use internet research only to resolve gaps, verify official installation procedures, identify model artifacts, or confirm tool flags and compatibility. Prefer authoritative sources: the video, linked repositories, llama.cpp documentation, official Pi Coding Agent documentation, Tailscale documentation, and Hugging Face model cards.

# Target Environment

The host has an NVIDIA GTX 1070. The video used a different GPU, so do not assume that its layer-offload settings, context size, throughput, RAM requirements, or benchmark results will transfer directly.

The intended approach is to run the REAP GGUF models through the supplied TurboQuant llama.cpp build, using CPU RAM plus partial GPU offload as needed:

- `Qwen3.6-28B-REAP20-A3B-GGUF`
- `GLM-4.7-Flash-REAP-23B-A3B-GGUF`

Treat model quantization choice, context length, GPU-layer count, KV-cache settings, and memory allocation as host-specific parameters to be discovered and validated safely.

# Mandatory Constraints

- Reuse `~/llama-low-vram-repro/llama-cpp-turboquant/build/`; do not compile, modify, replace, or delete it.
- Do not install or upgrade CUDA, NVIDIA drivers, system packages, or other global dependencies without explicit approval.
- Do not download models or other large artifacts before approval.
- Do not alter files in `01_running_a_35b_ai_model_on_6GB_vram_llamacpp/`.
- Create the new project only under `02_local_coding_agent_on_budget_gpu/`.
- Preserve the prior project’s conventions for directory layout, script style, configuration management, logging, benchmarking, validation, and documentation wherever practical.
- Prefer reversible, idempotent scripts with clear prerequisites, explicit paths, failure handling, and dry-run or inspection modes where useful.
- Never expose credentials, tokens, private paths beyond what is necessary, or make a remote service publicly accessible by default.
- Treat Tailscale and remote access as optional and isolated from the core local inference setup.
- Clearly distinguish: confirmed facts from supplied materials, verified external facts, assumptions, unknowns, and host-specific values that must be measured.

# Delegation Requirements

Delegate aggressively to sub-agents where available. At minimum, use separate sub-agents for:

1. **Prior-project analysis**  
   Inspect `01_running_a_35b_ai_model_on_6GB_vram_llamacpp/` and report its directory structure, scripts, conventions, dependencies, validation strategy, and patterns that should be reused.

2. **Transcript and milestone analysis**  
   Extract every meaningful video chapter, setup step, command, configuration choice, optimization, expected outcome, benchmark claim, and validation point from the transcript and description.

3. **Technical feasibility and compatibility**  
   Verify the relevant model files and quantizations, required llama.cpp/TurboQuant capabilities and flags, Pi Coding Agent integration requirements, and likely constraints for a GTX 1070. Identify compatibility risks rather than assuming support.

4. **Implementation-plan review**  
   Independently review the proposed plan for safety, missing dependencies, reproducibility, validation quality, rollback paths, and deviations from the video caused by hardware differences.

Consolidate the sub-agent findings into one coherent plan. Resolve discrepancies explicitly.

# Required Deliverable: Plan for Approval

Before changing anything, produce a single Markdown planning document suitable for approval. It must include the following sections.

## 1. Scope and Success Criteria

Define:

- What “replicating the video” means in practical terms.
- Which milestones can be reproduced exactly and which must be adapted for GTX 1070 limitations.
- Concrete success criteria for model loading, inference, API availability, Pi integration, performance measurements, context-window testing, and optional remote access.
- Clear non-goals and safety boundaries.

## 2. Evidence and Assumptions

Provide a table with:

| Item | Source | Status | Notes |
|---|---|---|---|

Use the statuses:

- Confirmed from local transcript/description
- Verified externally
- Assumption requiring validation
- Unknown or blocked

Do not present unverified video claims as guaranteed outcomes.

## 3. Prior-Project Reuse

Describe the existing project’s structure and conventions, then state precisely:

- Which structure and patterns will be reused.
- The proposed directory tree for `02_local_coding_agent_on_budget_gpu/`.
- Which scripts, configuration files, guides, log locations, benchmark outputs, and validation artifacts will be created.
- How the new project remains self-contained without modifying the old one.

## 4. Prerequisite Audit

List every prerequisite to inspect before implementation, including:

- Operating system and shell environment.
- CPU model, total RAM, free disk space, swap policy, and storage location.
- GTX 1070 driver/CUDA visibility and available VRAM.
- Existing llama.cpp executables and supported flags in the supplied build.
- Node.js/npm or other Pi Coding Agent runtime requirements.
- Existing Python, Hugging Face CLI, Git, Tailscale, and network availability where applicable.
- Model download access and disk-space estimates.

For each prerequisite, specify the exact read-only inspection command, expected result, failure interpretation, and remediation options. Do not execute installation or remediation automatically.

## 5. Video-to-Project Milestones

Create a phase-by-phase table mapped to the video chapters. For each phase include:

| Phase | Video chapter/topic | Goal | Inputs | Planned scripts/guides | Commands to run later | Measurements | Pass criteria | Risks/adaptations for GTX 1070 |
|---|---|---|---|---|---|---|---|---|

Cover at least:

- Hardware and resource baseline.
- Model-selection and quantization decision.
- Model acquisition and integrity verification.
- Basic local llama.cpp inference.
- Partial GPU offload and CPU/RAM fallback tuning.
- TurboQuant and KV-cache/context-window optimization.
- llama-server OpenAI-compatible API setup.
- Pi Coding Agent installation and configuration.
- Model switching or role-specific configuration if shown in the video.
- Coding-agent functional tests.
- Performance benchmark methodology, separating prompt processing/prefill from token generation/decode.
- Optional Tailscale remote-access setup and secure validation.
- Final end-to-end reproducibility test.

## 6. Configuration Strategy

Define a configuration-driven design rather than hard-coding machine-specific settings.

Include proposed configuration fields for:

- llama.cpp binary path.
- Model directory and selected GGUF filename.
- GPU layers/offload value.
- Context size.
- Batch and micro-batch settings.
- CPU threads.
- KV-cache/TurboQuant options.
- Host/port and API binding.
- Logging and output directories.
- Pi endpoint and model identifiers.

Explain which values are defaults, which are derived from inspection, and which are determined through controlled benchmarks.

## 7. Model Decision Framework

Provide a decision matrix for the two target models and candidate GGUF quantizations. Include:

- Approximate disk/RAM/VRAM implications.
- Expected trade-offs between quality, context capacity, prompt processing speed, and decode speed.
- How to choose a feasible quantization for a GTX 1070 system without assuming the available system RAM.
- A staged download plan: smallest viable test artifact first, then the preferred production artifact only after validation.
- Integrity verification and licensing checks.

Do not recommend a model file until the host RAM, disk space, and compatibility are audited.

## 8. Validation and Benchmarks

Specify reproducible validation procedures and artifacts for each milestone.

Include:

- Smoke tests for each executable and service.
- Model-load verification.
- A deterministic or versioned prompt suite.
- API health and chat-completions tests.
- Pi Coding Agent test tasks with objective acceptance checks.
- Context-window progression tests.
- Measurements for time-to-first-token/prompt processing, decode speed, peak RAM, peak VRAM, CPU utilization, failures, and stability.
- How logs and benchmark results will be stored in the project folder.
- A clear comparison between video-reported figures and locally measured figures, with the hardware caveat.

## 9. Risks, Rollback, and Stop Conditions

List foreseeable failure modes, including insufficient RAM/VRAM/disk, unsupported TurboQuant flags, model incompatibility, instability at large context, poor coding-agent behavior, and security risks from remote access.

For each risk, state:

- Detection method.
- Safe fallback.
- Rollback method.
- Conditions that require stopping and requesting approval before proceeding.

## 10. Exact Approval Gates

Break implementation into explicit approval gates:

1. Read-only host and prior-project audit.
2. Create only the project scaffolding, scripts, configs, and guides.
3. Install user-space dependencies if needed.
4. Download selected model artifact(s).
5. Run local model and tuning benchmarks.
6. Configure and validate Pi Coding Agent.
7. Configure optional Tailscale remote access.

For every gate, state the actions, expected disk/network/system impact, deliverables, and validation required before the next gate.

## 11. Questions and Decisions Needed

Ask only essential questions that cannot be safely inferred, prioritizing:

- Available RAM and free disk space.
- Whether model downloads are allowed and any download/storage limits.
- Whether Node.js/Pi and Tailscale may be installed if absent.
- Whether remote access is desired.
- Whether the goal prioritizes quality, usable context length, or responsiveness.

# Required Output Rules

- Return the planning document only; do not perform implementation.
- Do not create files, execute mutating commands, install packages, download artifacts, start servers, or change configuration.
- Use exact paths where known and clearly label placeholders.
- Include copy-paste-ready commands only when they are planned for a later approved phase; label them `Planned command — do not run yet`.
- Favor concise but operationally complete guidance.
- End by requesting explicit approval for **Gate 1: read-only audit and project-plan finalization**.
```

