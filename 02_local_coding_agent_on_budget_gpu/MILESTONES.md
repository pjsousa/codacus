# Milestones

This checked-in ledger records preparation status, not generated runtime status. Run `scripts/07_validate_milestones.sh` for evidence-linked current results.

| Milestone | Initial status | Video reference | Host acceptance |
|---|---|---|---|
| Source and prior-project inspection | PASS | Chapters/source established | Direct claims, adaptations, and gaps documented |
| GTX 1070 preflight | NOT RUN | Video RTX 3060 12 GB | Timestamped hardware report has no unexplained failure |
| Existing CUDA llama.cpp verified | NOT RUN | llama.cpp stack | Binary hashes, revision, CUDA device, and exact flags recorded |
| REAP Q4 artifact downloaded | NOT RUN | Qwen/GLM REAP Q4 | Pinned size and SHA-256 pass |
| Safe model load | NOT RUN | 20B-40B MoE range | Loopback server healthy without OOM/swap growth |
| Base PP/TG metrics | NOT RUN | PP is agent bottleneck | Parseable prompt/decode rows and telemetry |
| Thread tuning | NOT RUN | Qwen 39.5 at 3 threads; GLM 45.77 at 3 | Host-specific stable optimum; video value is reference only |
| Ubatch tuning | NOT RUN | Qwen 300 to 1,142 pp/s; GLM 446 to 863 | Measured gain without unsafe VRAM or TG regression |
| TurboQuant | NOT RUN | K turbo4, V turbo2 | Context/tool quality and resource behavior pass |
| Pi read-only smoke | NOT RUN | About 1,000 pp/s after first turn | Tool event, exact output, fixture unchanged |
| Cache reuse | NOT RUN | 256-token chunks | `08_validate_agent_features.sh cache-reuse` proves middle-chunk reuse |
| Model hot swap | NOT RUN | `/models`, one model at a time | A to B to A with same router PID and successful inference |
| Long-context reliability | NOT RUN | Agent documents/files | Token-counted retrieval and stability pass |
| Tailscale | NOT RUN | Remote use | Optional authenticated least-privilege route validated |
| Full reproduction | NOT RUN | Final stack | Every applicable required milestone is `PASS` |

Statuses mean:

- `PASS`: executed, evidence parsed, criterion met.
- `WARN`: executed with a caveat or unproven optimization.
- `FAIL`: attempted required behavior failed.
- `NOT RUN`: unexecuted, blocked, inapplicable, or awaiting confirmation.
