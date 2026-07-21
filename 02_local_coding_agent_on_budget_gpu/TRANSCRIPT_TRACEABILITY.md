# Transcript Traceability

The transcript is a single long line, so references use topic order plus chapter timestamps from `description.txt`. Classification:

- **Direct**: stated in transcript or description.
- **Adaptation**: conservative GTX 1070 or current-tool change.
- **Gap**: missing or contradictory source detail.

## Chapter Matrix

| Chapter | Source milestone | Class | Guide/implementation | Prerequisites | Expected observable output | Validation | Rollback/cleanup |
|---|---|---|---|---|---|---|---|
| 00:00 Cold Open | Agent workloads repeatedly process large prompts; target 1,142 pp/s and about 40 tg/s | Direct | `README.md`, `MILESTONES.md` | None | Reference goals are labeled video-only | Generated ledger must not use these as GTX 1070 thresholds | None |
| 00:58 Hardware | Full VRAM residency is fastest; larger models require CPU/RAM offload | Direct | `ENVIRONMENT.md`, `00_preflight.sh` | Host access | GPU, RAM, CPU, and disk report | Preflight report and resource evidence | None |
| 00:58 Hardware | DDR4/RAM/PCI/CPU can limit expert transfer; video uses RTX 3060 12 GB and four-core CPU | Direct | `ENVIRONMENT.md` | None | RTX 3060-to-GTX 1070 difference recorded | Compare current preflight, not kickoff's GTX 1060 claim | None |
| 00:58 Hardware | Offload less to RAM and leave enough CPU capacity | Direct intent | Safe profiles and thread stage in `PLAN.md` | Model load | Stable expert placement and thread sweep | `06_benchmark.sh threads` plus telemetry | Restore safe `n-cpu-moe`/threads |
| 03:30 Models | MoE uses active experts rather than all weights every token | Direct | `MODELS.md` | Model metadata | Total and active parameters reported separately | Artifact metadata and runtime load | Remove selected model manually if unwanted |
| 03:30 Models | REAP removes poorly used experts, with HumanEval 95.1 versus 94.5 claim | Direct with gap | `MODELS.md` | Published cards | Pruning ratio discrepancy remains visible | No benchmark claim without matching harness | None |
| 03:30 Models | Use Qwen3.6 REAP and GLM-4.7-Flash-REAP-23B | Description-linked repositories, exact artifact gap | `MODELS.md`, `03_download_models.sh` | Disk and confirmation | Pinned Q4_K_M selection | Exact bytes/SHA-256 | Retain `hf` local cache; no automatic deletion |
| 03:30 Models | Prefer Q4_K_M or Unsloth Dynamic Q4; avoid sub-Q4 quality loss | Direct | Download profiles | Model choice | Q4 candidate selected | Hash plus later tool/retrieval quality | Switch to alternate Q4 candidate |
| 03:30 Models | Practical mid-frontier range is about 20B-40B; two complementary models | Direct claim | `README.md`, router preset example | Both downloads for switching | One model loaded at a time | A-to-B-to-A test | Stop router and use direct profile |
| 07:35 Optimization | Agent bottleneck is prefill, not decode alone | Direct | `VALIDATION.md`, `06_benchmark.sh` | Local model | Separate PP and TG rows | Machine-readable positive rates | None |
| 07:35 Optimization | Prompt cache helps later turns; middle edits need 256-token cache reuse | Direct intent, flag gap | `PLAN.md`, `VALIDATION.md`, server profiles | Stable server | Reduced evaluated tokens for controlled middle edit | A/B/C cache fixture | Set `cache-reuse=0` |
| 07:35 Optimization | Tune threads and ubatch with llama-bench | Direct | `06_benchmark.sh threads|ubatch` | Safe smoke passes | Per-value PP/TG evidence | Repeated rows and noise threshold | Restore prior selected values |
| 07:35 Optimization | Video Qwen thread results: 28 at 1, 39.5 at 3, 22 at 4 | Direct | `MILESTONES.md` reference | Comparable video unavailable | Host sweep may differ | Select host median, not exact 39.5 | Restore threads 3 baseline |
| 07:35 Optimization | Video GLM thread results: 45.77 at 3 and 27 at 4 | Direct | `MILESTONES.md` reference | GLM candidate | Host values recorded independently | Same profile/workload across values | Restore threads 3 baseline |
| 07:35 Optimization | Qwen ubatch 256 gives about 300 pp/s and 2048 gives 1,142; TG stays flat | Direct | `06_benchmark.sh ubatch` | Thread selection | PP rises or a host limit is documented | VRAM-safe gain beyond noise | Restore ubatch 256 |
| 07:35 Optimization | GLM prefill rises 446 to 863; production ubatch 1024 gives about 870 | Direct with missing endpoint sizes | Video-intent profile uses ubatch 1024 | GLM load | Host measurement, not copied value | Fixed-placement ubatch sweep | Safe profile ubatch 256 |
| 07:35 Optimization | TurboQuant uses K turbo4 and V turbo2 | Direct | Video-intent profiles | Parser and context compatibility | Context creates and inference succeeds | Benchmark, retrieval, and tool quality | K q8_0/V turbo4 or f16 |
| 07:35 Optimization | GLM changes +12% decode/-25% prefill; Qwen +4%/+5% | Direct video claim | `VALIDATION.md` comparison guidance | Both exact profiles | Host deltas reported with placement controls | Same placement before retuning experts | Restore safe KV types |
| 07:35 Optimization | Full displayed llama-server command | Gap: absent from transcript | `04_start_model_server.sh`, verified current flags | Capability report | Resolved command logged | Exact health JSON and model list | Owned PID shutdown |
| 11:48 Pi | Install `pi-llama-cpp` and point settings at llama server | Direct | `02_install_pi.sh`, Pi config example | Node >=22.19, confirmation | Pinned Pi and extension in local directories | Version/state evidence | Manually remove `.tools/`/`.state/` after review |
| 11:48 Pi | First turn processes full system prompt; later turns process deltas, around 1,000 pp/s | Direct claim | `05_run_pi_agent.sh`, cache fixture | Pi and server | Read tool call and correct marker | JSONL event plus unchanged hash | Stop server, remove disposable state if desired |
| 11:48 Pi | `models.ini`, llama router presets, `/models`, automatic unload/load | Direct intent, syntax omitted | `configs/models.ini.example`, README router section | Both models | Pi discovers IDs; one model loaded | A-to-B-to-A, same router PID | Stop router; return to direct profile |
| 13:55 Tailscale | Install Tailscale on rig/laptop and use rig address remotely | Direct | README remote section, troubleshooting | Explicit install/enrollment/security approval | Authenticated remote endpoint | ACL, API auth, direct/relay latency evidence | Remove exact Serve route only |
| 16:19 Final | Consumer GPU, REAP Q4, tuned llama.cpp, Pi, optional remote access | Direct | `07_validate_milestones.sh` | All applicable stages | Every required local milestone is PASS | Generated evidence-linked ledger | Stop server; retain evidence |

## Exact Source Gaps

- The full llama-server command shown in the video is absent from the transcript.
- The description supplies both repository links, but no exact GGUF file, quant variant, revision, or checksum used in the video.
- The GLM model is strongly identifiable, but Q4_K_M versus UD-Q4_K_XL is unresolved.
- Complete llama-bench commands, model placement, context, run count, and raw tables are absent.
- The spoken `models.ini` syntax and server router flag are absent; this project uses the verified current build syntax.
- Tailscale installation, ACL, authentication, bind, and TLS details are absent.
- The five promised “things” are not explicitly enumerated. This project maps them to hardware/offload, REAP Q4 models, llama.cpp tuning, Pi, and optional remote access.

## Conflicts Preserved

- Video source: RTX 3060 12 GB. Kickoff objective: GTX 1060. The source wins; GTX 1070 is adapted from RTX 3060.
- Transcript generalizes REAP as 20%; the identified GLM card says 25% expert pruning.
- “Chat starts with zero prefill” conflicts with ordinary prompt evaluation and the later first-turn explanation. This project treats first-turn prefill as required.
- “No API keys” means no cloud-provider credential. A remotely exposed local API should still be authenticated, and Pi's OpenAI client may use a non-secret placeholder locally.
