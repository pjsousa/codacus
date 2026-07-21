
--- PARAMS ---
TRANSCRIPT_FILE = `04_local_ai_stack_chat_rag_agent_automation.txt`
VIDEO_TITLE = `Build Your Own Fully Private, Local AI Stack (Chat, RAG, Coding Agent, Automation)`
VIDEO_URL = `https://www.youtube.com/watch?v=oh50KFF8A_0&t=67s`



# Objective

Turn the supplied video transcript and description into an executable, host-specific reproduction package following the same conventions and quality level as:

`../01_running_a_35b_ai_model_on_6GB_vram_llamacpp/`

The result must be an engineering handoff, not a video summary. Another person should be able to execute the guide chapter by chapter, capture evidence, and determine whether each claim was reproduced.

Assume that host preparation was completed during the reference project. Do not rebuild the host environment for this project. Reuse the custom CUDA-enabled `llama.cpp` TurboQuant build created by project 01.

# Inputs

Primary local sources:

- Transcript: `<TRANSCRIPT_FILE>`
- Video description: `description.txt`
- Known-good structural reference: `../01_running_a_35b_ai_model_on_6GB_vram_llamacpp/`
- Existing custom `llama.cpp` build: `~/llama-low-vram-repro/llama-cpp-turboquant/build`

Video metadata:

- Title: `<VIDEO_TITLE>`
- URL: `<VIDEO_URL>`

Target adaptation, if any:

- If not specified, inspect the current host and adapt conservatively.

Read the complete transcript and description before designing the deliverables. Inspect the complete reference project, including `GUIDE.md`, `config.env.example`, `config.env` when present, `scripts/_common.sh`, and every numbered script. Use its configured paths to verify the actual existing source, build, binary, model, and results locations instead of guessing them.

# Existing Runtime Requirement

The existing custom build from project 01 is the default and required `llama.cpp` runtime:

`~/llama-low-vram-repro/llama-cpp-turboquant/build`

Before designing runtime commands:

1. Inspect project 01's configuration and scripts.
2. Locate the actual existing `llama-cli`, `llama-server`, `llama-bench`, and other relevant binaries under that build.
3. Record the build's version or Git revision.
4. Inspect the binaries' `--help`, `--version`, and device output as applicable.
5. Verify every proposed flag against these exact binaries.

Do not clone, rebuild, update, replace, or modify this `llama.cpp` checkout or build. Do not switch it to another revision merely because the video used a different version. Adapt the reproduction to the capabilities of the existing build and clearly document any resulting difference.

If a video milestone requires a feature absent from the existing build:

- do not install or compile an alternative automatically,
- identify the exact missing capability,
- preserve the intended milestone in the guide,
- mark it `BLOCKED` or `NOT RUN`,
- describe the smallest optional user-approved remedy separately.

The absence of an optional feature must not prevent completion of the rest of the guide and scripts.

# Source Policy

Treat sources in this order:

1. Local transcript and description for the video's sequence, intent, commands, claims, and reported results.
2. Official documentation and upstream repositories for current syntax and implementation details.
3. Reputable secondary sources only when primary sources are insufficient.
4. Explicitly labeled inference when the required operational detail cannot be established.

External research may verify or complete the local material, but must not silently replace or rewrite what the video claimed.

Clearly distinguish:

- directly stated by the video,
- externally verified,
- inferred for reproducibility,
- adapted for this host,
- still requiring empirical validation.

If the transcript conflicts with current software, preserve the original claim, explain the conflict, and implement the smallest verified modern equivalent.

# Required Workflow

1. Inspect the reference project and infer its conventions.
2. Read and analyze the full transcript and description.
3. Extract:
   - chapters and timestamps,
   - setup steps,
   - commands and flags,
   - dependencies and artifacts,
   - baseline behavior,
   - each incremental optimization,
   - benchmarks and claimed results,
   - failures and dead ends,
   - final recommended configuration.
4. Inspect the current host using read-only commands where relevant:
   - OS and kernel,
   - CPU and instruction set,
   - RAM and swap,
   - disk availability,
   - GPU, VRAM, driver, and compute capability,
   - installed toolchain,
   - container runtime,
   - relevant process limits.
5. Research current upstream behavior and resolve missing operational details.
6. Reuse the existing custom `llama.cpp` revision; pin model or other artifact revisions, filenames, and checksums whenever possible.
7. Build a chapter-aligned implementation in which each script represents one setup phase, experiment, or technical change.
8. Create all deliverables directly in the current project directory.
9. Perform safe static validation of generated scripts.
10. Do not stop after analysis or return only proposed file contents.

# Required Project Shape

Keep the project deliberately compact:

```text
<current-project>/
|-- <TRANSCRIPT_FILE>
|-- description.txt
|-- kickoff.prompt.md
|-- GUIDE.md
|-- config.env.example
`-- scripts/
    |-- _common.sh
    |-- 00_host_check.sh
    |-- 01_<first-setup-step>.sh
    |-- 02_<next-step>.sh
    |-- ...
    `-- NN_<final-validation-or-benchmark>.sh
```

The exact numbered scripts must be inferred from the new video.

Follow these ordering conventions when applicable:

1. Host/preflight check.
2. Verification of the existing project-01 `llama.cpp` build and its capabilities.
3. Verification or explicit acquisition of required artifacts/models.
4. Baseline run.
5. One script per incremental optimization or milestone.
6. Parameter sweeps or tuning.
7. Context, correctness, or integration tests.
8. Stability validation.
9. Final repeatable benchmark.

Do not create a `llama.cpp` dependency-installation or build script. This project must consume the existing build rather than reproduce project 01's host setup.

Do not create separate `README.md`, `PLAN.md`, `MILESTONES.md`, `VALIDATION.md`, or similar documentation unless the subject genuinely cannot be handled clearly in `GUIDE.md`. The desired output is one authoritative guide plus modular scripts.

Do not create or overwrite `config.env`. Only create `config.env.example`; an existing `config.env` is a user-owned local override.

# GUIDE.md Requirements

Use this section structure unless the source material makes a section irrelevant:

1. Executive overview
2. Source handling
3. Host assumptions and observed environment
4. Chapter-by-chapter replication guide
5. Reproduction plan
6. Script reference
7. Validation and benchmarks
8. Final recommended configurations
9. Uncertainties and gaps
10. Appendix

For every video chapter or operational milestone include:

- timestamp and chapter title,
- objective,
- technical change from the preceding phase,
- prerequisites,
- exact command or script invocation,
- expected output or observation,
- validation method,
- success and failure criteria,
- likely failure modes,
- host-specific adaptation,
- reversal or recovery instructions where relevant.

Also include:

- a script-to-chapter mapping table,
- a baseline-versus-optimized results table,
- metrics and capture methods,
- an ordered quick execution sequence,
- failed approaches described in the video,
- final commands for:
  - closest practical reproduction of the video,
  - safer/lower-risk configuration,
  - best effort for the detected host,
- glossary,
- pinned upstream links,
- end-to-end checklist.

Use copy-pasteable commands. Do not hide essential commands behind prose.

# Script Standards

Every Bash script must:

- start with `#!/usr/bin/env bash`,
- use `set -euo pipefail`,
- resolve its own directory safely,
- source `scripts/_common.sh`,
- quote paths and expansions,
- fail with actionable error messages,
- be safe to rerun where practical,
- accept configuration through environment variables,
- forward additional CLI arguments where useful,
- log the fully resolved command,
- preserve logs from failed experiments,
- avoid silently installing, deleting, or replacing unrelated software.

Use `_common.sh` to centralize:

- project and work paths,
- configurable defaults,
- pinned repositories and revisions,
- artifact filenames and checksums,
- executable paths,
- common runtime arguments,
- timestamped result paths,
- prerequisite checks,
- host/RAM/GPU snapshots,
- command logging helpers.

Default the `llama.cpp` source and build paths to the existing project-01 locations. Allow path overrides through `config.env`, but do not silently fall back to downloading or compiling another copy when the existing build is missing.

Use `config.env.example` for all machine-dependent or experiment-dependent values. Defaults should work for the detected host when reasonably possible.

Separate optional project-local tool setup, downloads, runtime experiments, and benchmarks. A normal run script must never unexpectedly trigger an installation, large download, or build.

For tuning scripts:

- test a configurable list of values,
- continue after an individual OOM or failed candidate when safe,
- retain each candidate's logs,
- capture RAM and GPU telemetry where applicable,
- print a concise comparison summary,
- fail only when no candidate succeeds.

# Reproducibility Requirements

- Prefer pinned immutable revisions over moving branches or `latest` tags.
- Record exact artifact filenames and SHA-256 checksums when available.
- Record the verification date for upstream facts.
- Verify flags against the selected software revision.
- Do not present unsupported or obsolete flags as runnable.
- Keep baseline and optimized workloads comparable.
- Change one important variable per experimental phase whenever possible.
- Use fixed prompts, seeds, workloads, durations, and output lengths for comparisons.
- Distinguish prompt-processing speed from generation speed.
- Capture relevant RAM, VRAM, CPU, latency, throughput, context, correctness, and stability evidence.
- Treat the video's reported numbers as references, not guaranteed acceptance thresholds on different hardware.
- Do not claim an optimization works on this host until it has been measured here.
- Mark unexecuted results as `TBD` or `NOT RUN`; never fabricate observations.
- Label adaptations and inferred commands explicitly.

# Safety and Execution Boundaries

You may run read-only host inspection and lightweight static checks.

The agent must not make host-level changes. This is a firm execution constraint, not merely an action requiring confirmation. Do not change the host on the assumption that a fresh environment is needed; project 01 already established the runtime environment.

Do not:

- install system packages,
- change drivers or global system configuration,
- install or change the CUDA toolkit,
- alter users, groups, permissions, login limits, services, or container configuration,
- clone, update, reconfigure, or rebuild `llama.cpp`,
- modify the existing project-01 source, build, models, configuration, or results,
- write outside the current project directory, except for output paths explicitly configured by the user,
- delete or overwrite existing user data.

Without explicit user approval, also do not:

- download multi-gigabyte artifacts,
- start persistent services,
- run long benchmarks or soak tests,
- expose services beyond `127.0.0.1`.

Prefer existing commands and tools already available on the host. If an additional tool is essential, use a project-local, isolated, reversible installation only when it does not alter the host environment and the user has approved it. Otherwise, document the missing prerequisite and continue producing the rest of the package.

These boundaries must not prevent you from creating complete scripts and documentation. Generate non-destructive implementations, document blocked requirements, and identify optional executions requiring approval. Do not create scripts whose normal purpose is to modify the host.

# Validation Before Completion

At minimum:

- run `bash -n` on every generated Bash script,
- run `shellcheck` if already installed,
- verify that every guide command references an existing script or defined path,
- verify that every script variable has a default or documented requirement,
- verify chapter-to-script coverage,
- verify script numbering and execution order,
- verify that unsupported claims are labeled,
- inspect the final directory for unnecessary files.

# Acceptance Criteria

The task is complete only when:

- `GUIDE.md` is the single authoritative operator guide,
- the guide follows the video's chapter progression,
- every practical milestone maps to an executable script or exact command,
- scripts share one configuration and logging implementation,
- all `llama.cpp` commands use the verified custom build from project 01 by default,
- no script installs, rebuilds, updates, or modifies the host or the existing custom build,
- current upstream behavior has been verified,
- host-specific differences are explicit,
- benchmarks have objective validation criteria,
- unknowns and unexecuted actions are not represented as facts,
- generated scripts pass available static checks,
- the final project resembles the reference project in structure and operating style without copying its video-specific technical content.

Finish with a concise report containing:

- files created or changed,
- static checks performed,
- actions intentionally not executed,
- unresolved source gaps,
- the first command the operator should run.
