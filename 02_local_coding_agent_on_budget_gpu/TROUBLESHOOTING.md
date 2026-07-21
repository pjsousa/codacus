# Troubleshooting

| Symptom | Likely cause | Evidence to inspect | Recovery |
|---|---|---|---|
| Port health returns 404/wrong JSON | Another service owns the port | Preflight `ss` section, exact `/health` body | Set another `SERVER_PORT`; never kill an unrelated listener |
| CUDA OOM during load | Too many GPU experts, context, or ubatch | Server log and GPU telemetry | Increase `n-cpu-moe`, reduce context/ubatch, return to safe KV profile |
| Host becomes unresponsive | `--no-mmap`, concurrent models, or context pressure | `free`, swap, process RSS | Stop owned server, keep mmap enabled, use one router model, reduce context |
| Decode falls at four threads | Scheduler/GPU management has no spare core | Thread benchmark rows | Select the stable 2-3 thread result; do not use all logical CPUs blindly |
| Prefill does not improve with ubatch | Pascal kernel or bandwidth limit; noisy run | Machine JSONL and VRAM telemetry | Repeat under idle conditions; retain smaller ubatch if gain is below noise |
| TurboQuant model/context fails | Unsupported head geometry or CUDA path | Startup context/KV messages | Restore q8_0/turbo4 or f16; parser support alone is insufficient |
| Tool calls are malformed | Model template, quantization, or aggressive KV loss | Pi JSONL and server tool-parser log | Verify `--jinja`, use safer KV, smaller context, and exact model template |
| Pi installer rejects Node | Node is below 22.19 | `node --version` | Select user-local Node 22.19+; do not replace system Node automatically |
| Pi connects but lists no model | Wrong root URL or no loaded model | `/v1/models`; Pi `llamaServerUrl` | Use root `http://127.0.0.1:8088`, not `/v1`, for `pi-llama-cpp` |
| Pi reports model load timeout | Large router load exceeds extension monitor | `/models` status and server log | Poll status before retrying; do not launch duplicate loads |
| `--mlock` locks only KiB | Host memlock limit is 64 KiB | `/proc/PID/status` `VmLck`, `ulimit` | Omit mlock. Any limit change needs separate approval and login restart |
| Benchmark says success but lacks metrics | Output schema/version mismatch | Raw JSONL and stderr | Mark `FAIL`; update parser only after inspecting the exact build output |
| Download restarts or fails hash | Proxy/range behavior, interrupted transfer, wrong revision | `.part` size and curl error | Partial files resume. If a complete `.part` has the wrong hash, move it aside manually after review, then rerun |
| Existing target has wrong hash | Unrelated/corrupt artifact | `sha256sum` | Move it aside manually after review; script refuses overwrite |
| Server PID file is stale | Prior crash or manual process termination | `.state/llama-server.*`, `/proc/PID/exe` | `status` will not trust a mismatched executable; remove stale state only after inspection |

## Performance Interpretation

- `pp` is prompt processing/prefill; `tg` is token generation/decode. Do not compare one to the other.
- A first Pi turn may process the complete system prompt. Later turns can reuse prompt cache.
- `cache-reuse=256` targets middle-of-context changes and TTFT; it does not increase raw processing throughput.
- `--no-mmap` can help some offloaded workloads but increases committed host memory. It is an experiment, not a default.
- A faster KV-compressed profile with changed expert placement does not prove the codec itself is faster.
- Video results on RTX 3060 cannot be used as GTX 1070 pass thresholds.

## Safe Shutdown

```bash
./scripts/04_start_model_server.sh status
./scripts/04_start_model_server.sh stop
```

The script signals only its recorded PID after checking `/proc/PID/exe`. It never uses `pkill` or process-name matching.

## Tailscale

Do not resolve remote access problems by binding llama.cpp to `0.0.0.0`. Keep loopback, separately approve Tailscale installation/enrollment, inspect ACLs, use authenticated Serve, and avoid Funnel. Capture existing Serve state before adding a route and remove only the route created for this project.
