# Task

Use the local transcript and video description as the primary sources, and use internet access whenever needed to fill gaps, verify current implementation details, or resolve changes in upstream tooling.

## Local Source Files

The following files already exist locally and should be used first:

- `running_a_35b_ai_model_on_6GB_vram_llamacpp_guide.txt` — video transcript
- `description.txt` — video description

## Optional External Sources

You may fetch content from the internet if needed, especially to verify or update:
- `llama.cpp` build steps,
- CLI flags and syntax,
- CUDA build details,
- TurboQuant support or fork status,
- model download locations,
- any implementation details that may have changed since the video.

Use external sources to **verify**, not replace, the local transcript and description.

## Objective

I want to reproduce, on **this host**, each phase and milestone demonstrated in the video.

The video is:

- **Running a 35B AI Model on 6GB VRAM, FAST (llama.cpp Guide)**
- YouTube: [https://www.youtube.com/watch?v=8F_5pdcD3HY](https://www.youtube.com/watch?v=8F_5pdcD3HY)

The video’s core claim is that the author ran **Qwen 3.6 35B-A3B** on a **GTX 1060 6GB** using **llama.cpp**, with layers offloaded into RAM, then improved speed, stability, and context window using a sequence of optimizations.

My GPU is a **GTX 1070**, so adapt recommendations accordingly where that materially changes the outcome.

## Required chapter alignment

Your deliverable must be organized to follow the video’s chapter progression as closely as possible.

Use these chapters as the backbone of the guide:

1. **00:00 — This shouldn’t work**
2. **00:27 — Setup**
3. **01:46 — Why it’s slow by default**
4. **02:52 — MoE breakthrough**
5. **04:33 — Fixing memory bottlenecks**
6. **05:32 — Hitting 17 tok/s**
7. **06:40 — 4× context trick**
8. **09:23 — Stability fix**
9. **11:04 — What failed**
10. **13:32 — The 5 flags**

Your scripts, guide sections, validation steps, and milestone checks should map to these chapters explicitly.

## Deliverables

Produce:

1. **A structured Markdown guide**
2. **Shell scripts and/or Python scripts**
3. **Config files if helpful**
4. **Validation and benchmark steps**
5. **A chapter-by-chapter reproduction plan tied to the video**

This should be something I can actually execute on the host, not just a conceptual summary.

## Required Output Structure

Return the answer in the following order:

### 1. Executive overview
Briefly explain:
- what the video is doing,
- why it can work on low VRAM,
- what is likely to differ on a GTX 1070,
- the biggest constraints and risks.

### 2. Source handling
Explain how you used:
- the local transcript file,
- the local description file,
- any external internet sources.

Clearly distinguish:
- what comes directly from the local files,
- what was verified externally,
- what is inferred.

### 3. Host assumptions
State the assumptions needed to make the guide practical:
- OS,
- NVIDIA drivers,
- CUDA/toolchain,
- Docker vs native build choice,
- RAM,
- disk,
- expected permissions,
- whether this host seems suitable.

If host facts are missing, say so clearly and proceed with labeled assumptions.

### 4. Chapter-by-chapter replication guide
Create one section per chapter:

1. This shouldn’t work  
2. Setup  
3. Why it’s slow by default  
4. MoE breakthrough  
5. Fixing memory bottlenecks  
6. Hitting 17 tok/s  
7. 4× context trick  
8. Stability fix  
9. What failed  
10. The 5 flags  

For each chapter include:
- chapter objective,
- what changes technically,
- exact commands,
- expected outputs or observations,
- validation method,
- likely failure modes,
- GTX 1070-specific notes.

### 5. Reproduction plan
Provide a clean staged plan from zero to final optimized setup:
- dependency install,
- repo/fork selection,
- build,
- model acquisition,
- baseline run,
- each optimization in sequence,
- context tests,
- stability tests,
- final recommended working commands.

### 6. Scripts
Generate practical scripts, preferably small and modular.

Use this script plan unless you have a strong reason to improve it:

- `00_host_check.sh`
- `01_install_deps.sh`
- `02_build_llamacpp.sh`
- `03_get_model.sh`
- `04_run_baseline.sh`
- `05_run_moe_cpu.sh`
- `06_run_no_mmap.sh`
- `07_tune_layers.sh`
- `08_test_context.sh`
- `09_stability_mlock.sh`
- `10_benchmark.sh`

If you change the script plan, explain why and keep it aligned to the chapter flow.

Script requirements:
- shell scripts should use `set -euo pipefail`,
- parameterize obvious values,
- keep them readable,
- avoid hardcoded paths unless labeled as defaults,
- explain dependencies on specific `llama.cpp` forks or features.

### 7. Validation and benchmarks
For each major milestone define:
- what metric to capture,
- how to capture it,
- expected success criteria,
- what would count as a failed reproduction.

Include:
- tokens/sec,
- RAM/VRAM behavior,
- context-length behavior,
- stability over time,
- a comparison table of baseline vs optimized phases.

### 8. Final recommended configurations
Provide three final configurations:

- **Closest to the video**
- **Safer / lower risk**
- **Best effort for GTX 1070**

For each include:
- full command,
- rationale,
- expected tradeoffs.

### 9. Uncertainties and gaps
Separate:
- directly supported by transcript/description,
- externally verified,
- inferred,
- host-dependent items that must be tested empirically.

### 10. Appendix
Include:
- glossary of key flags and concepts,
- upstream links,
- short end-to-end checklist.

## Reproducibility requirements

- Prefer **Linux-first**, unless the host clearly indicates otherwise.
- Use the local transcript and description as the **primary evidence base**.
- Use the internet when needed for verification or updated syntax.
- Be explicit when modern upstream behavior differs from the video.
- Prefer **copy-pasteable commands**.
- Provide both **Docker** and **native** paths if both are meaningfully relevant.
- Do not assume the exact same hardware stack as the video beyond what is explicitly stated.
- Adapt guidance where the GTX 1070 may permit different `-ngl`, context, or stability settings.

## Validation standard

Do not merely summarize the video. I want a host-specific implementation and verification package that lets me confirm, chapter by chapter, whether I reproduced the author’s claims, including:

- slow baseline,
- MoE offload improvement,
- memory bottleneck fixes,
- tuned layer offload,
- reaching the claimed speed range if feasible,
- context expansion,
- stability improvements,
- failed paths or dead ends discussed in the video,
- final “5 flags” understanding and validation.

## Quality bar

Write this like an engineering handoff:
- concrete,
- structured,
- operational,
- explicit about assumptions,
- skeptical where necessary,
- low on fluff.

If something is missing, do not stop. Produce the best possible guide anyway, and clearly label unknowns.

