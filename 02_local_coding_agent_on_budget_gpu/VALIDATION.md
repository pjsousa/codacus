# Validation

## Evidence Layout

- `logs/`: raw commands, binary help/version output, stdout/stderr, API evidence, and telemetry.
- `results/`: concise JSON/Markdown status records.
- `scripts/07_validate_milestones.sh`: aggregates only generated evidence; missing work stays `NOT RUN`.

Use `VALIDATION_PROFILE=glm-reap-safe` (or the selected Qwen profile) so evidence from different models cannot be combined.

Run IDs include UTC nanoseconds and PID to avoid same-second collisions.

## Core Metrics

| Metric | Capture | Acceptance |
|---|---|---|
| Model load | Server start to exact health JSON | Process alive; `.status == "ok"`; no OOM/fatal output |
| Prefill | llama-bench prompt rows | Positive finite rates, repeated samples, controlled workload |
| Decode | llama-bench generation rows | Positive finite rates, repeated samples, same model/placement |
| VRAM | 500 ms `nvidia-smi` samples | Prefer >=1 GiB headroom; <256 MiB is unsafe failure territory |
| Host RAM | Before/after resources and process evidence | Prefer >=16 GiB available; <8 GiB or swap growth fails selected profile |
| Stability | Process life, logs, repeated requests | No crash, OOM, fatal CUDA errors, or sustained degradation |
| Pi tools | Pi JSONL plus immutable fixture | Required tool event, correct output, no unintended changes |
| Context | Tokenized fill and retrieval | No truncation; deterministic keys retrieved; no unsafe pressure |

## Short Benchmark Commands

```bash
./scripts/06_benchmark.sh smoke glm-reap-safe
./scripts/06_benchmark.sh threads glm-reap-safe
./scripts/06_benchmark.sh ubatch glm-reap-safe
./scripts/06_benchmark.sh kv glm-reap-safe
./scripts/08_validate_agent_features.sh cache-reuse
./scripts/08_validate_agent_features.sh context
```

Each command is capped at 840 seconds and requires a stage/profile-specific confirmation. A timeout is `FAIL`, not partial success.

## Controls

- Keep model revision, model file, placement, context, batch, seed/workload, and cache profile fixed when comparing one variable.
- Benchmark under idle conditions and report warm/cold cache state.
- Run selected final profiles at least three times; report median and range.
- Treat movement below 5% or twice relative median absolute deviation as `WARN`, not a proven gain.
- Scan stderr for OOM, fatal, CUDA error, and segmentation fault even if exit status appears successful.
- Keep telemetry gaps visible; do not convert `N/A` to zero.

## Agent Fixtures

The automated Pi smoke exposes only `read` and verifies an unchanged marker file. A later coding/edit fixture should be run in a container or VM with only the disposable workspace mounted, no host credentials, no network, and an independent test command. Pi's working directory and tool list are not a security boundary.

## Cache Reuse Fixture

Use one slot, native `/completion`, `cache_prompt=true`, a fixed cache key, and `n_predict=1`:

1. A: stable agent-style system prompt and repository context.
2. B: A plus a short suffix.
3. C: A with one 256+ token middle chunk changed.

The automated fixture verifies the managed server was launched with `cache-reuse=256`, then parses cached/evaluated token counts. Pass requires the middle edit to reuse chunks beyond the unchanged prefix and evaluate materially less than the remaining prompt. Wall-clock speed alone is insufficient. A separate `cache-reuse=0` control remains useful when comparing TTFT.

Run it only against a confirmed managed server; it does not start or restart one.

## Context Progression

1. 8K allocation and 60% fill.
2. 16K deterministic retrieval.
3. 32K only when predicted prompt duration remains inside the approved bound.
4. 64K and above only with explicit long-run confirmation.

Use `/tokenize` to count tokens. Put deterministic keys near 25%, 60%, and 85% depth and generate only 8-16 answer tokens at temperature zero. Allocation success without retrieval is not a context pass.

## Hot-Swap Acceptance

With both model files and `models-max=1`:

1. Record router PID and load A.
2. Poll `/models` until A is loaded, then infer with A.
3. Load B, prove A is unloaded, then infer with B.
4. Load A again and infer.
5. Confirm router PID is unchanged and VRAM was released/reacquired.
6. Confirm Pi discovers the same IDs through `/models`.

An accepted load request or Pi progress dialog is not readiness evidence.

## Status Rules

- `PASS`: attempted, parsed, and met all mandatory criteria.
- `WARN`: completed with measurable caveats, unsafe margin, noise, or unresolved quality.
- `FAIL`: attempted mandatory behavior was wrong, incomplete, timed out, or unsafe.
- `NOT RUN`: no attempt because prerequisites, relevance, safety boundary, or confirmation were absent.

Required overall precedence is `FAIL > NOT RUN > WARN > PASS`. Optional Tailscale access does not block local-stack validation, but its status must remain visible.
