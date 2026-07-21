# Models

## Source Ambiguity

The video description explicitly links the Qwen and GLM repositories below. The transcript recommends Q4_K_M and Unsloth Dynamic Q4, but neither source identifies the exact file, quant variant, revision, or checksum used in the video. The profiles therefore pin reproducible Q4_K_M selections without claiming that their exact artifacts were used in the video.

## Download Profiles

| Profile | Repository and revision | Filename | Bytes | SHA-256 | License/status |
|---|---|---|---:|---|---|
| `qwen-reap-q4km` | `barozp/Qwen3.6-28B-REAP20-A3B-GGUF@e3aeb816...` | `Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf` | 17,264,580,480 | `dcd137ca7984ebdaa041ef80281322773bc1a9911ef639b7e698a20979953a00` | Apache-2.0, public; description-linked repository, selected Q4_K_M artifact |
| `glm-reap-q4km` | `unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF@983a65c6...` | `GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf` | 14,113,838,816 | `038e930ee1e050dca7732a7a2c768a4b0f83f5655add1acb6c7380852b9eef68` | MIT, public; description-linked repository, selected Q4_K_M artifact |

URLs:

- <https://huggingface.co/barozp/Qwen3.6-28B-REAP20-A3B-GGUF>
- <https://huggingface.co/unsloth/GLM-4.7-Flash-REAP-23B-A3B-GGUF>

These Q4_K_M candidates are single-file GGUFs. No shard joining is needed. The Dynamic Q4 GLM artifact remains documented as an unresolved alternative rather than a selectable profile because it has not been assigned a complete runtime/validation profile.

## Architecture

| Model | Total/active | Experts/layers | Context metadata | Notes |
|---|---|---|---:|---|
| Qwen3.6-28B-REAP20-A3B | About 28B/3B | 205 routed experts, 8 active; 40 layers | 262,144 | Pruned derivative; repository linked in description, exact video artifact unresolved |
| GLM-4.7-Flash-REAP-23B-A3B | About 23B/3B | 48 routed experts, 4 plus shared active; 47 layers | 202,752 | Published card says 25% pruning, conflicting with transcript's 20% generalization |
| Existing Qwen3.6-35B control | About 35B/3B | 256 routed experts, 8 plus shared active; 40 layers | 262,144 | Prior-video model only, not a REAP replacement |

Architectural maximum context does not establish usable context on this GPU.

## Memory Implications

- Qwen Q4_K_M is about 16.08 GiB and exceeds 8 GiB VRAM by at least 8.08 GiB before KV/compute buffers.
- GLM Q4_K_M is about 13.14 GiB and exceeds VRAM by at least 5.14 GiB before buffers.
- Both selected Q4 files require about 31.38 GB decimal disk combined.
- MoE reduces active per-token compute. All expert weights still need storage in RAM/VRAM.
- Large ubatch and context allocations compete with GPU-resident model tensors.
- Sub-Q4 files may be smaller, but conflict with the video's quality recommendation and are not default profiles.

## Existing Control

`~/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf` is 20,893,015,008 bytes with SHA-256 `a8138f183e3993f12cdc23afd2babb8cdb084e64088ce4a256d49101d47b949c`. It can verify the stack without another download, but results must be labeled control-model results.

## Download Procedure

```bash
./scripts/03_download_models.sh --list
hf auth login
./scripts/03_download_models.sh glm-reap-q4km
```

The script uses the `hf` CLI with a pinned revision and local model directory. The CLI automatically uses `HF_TOKEN` or credentials configured by `hf auth login`, selects the available Hub transfer backend (including Xet), and retains its local download cache for interrupted-transfer resumption. Authentication can avoid anonymous rate limits, but it does not guarantee higher transfer bandwidth. Never embed Hugging Face tokens in project config, commands, or logs.
