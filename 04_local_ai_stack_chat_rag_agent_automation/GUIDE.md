# Build Your Own Fully Private, Local AI Stack (Chat, RAG, Coding Agent, Automation)

This is a chapter-aligned reproduction package for the YouTube video **Build Your Own Fully Private, Local AI Stack (Chat, RAG, Coding Agent, Automation)**. Commands were prepared for this host on 2026-07-21. Run them from this repository.

## 1. Executive overview

The video wires up a complete local AI stack using a single `llama.cpp` inference engine as an OpenAI-compatible endpoint, then attaches four tool layers: a chat UI (AnythingLLM), a private RAG knowledge base (AnythingLLM's built-in system), a coding agent (Pi), and automation workflows (n8n). The key insight is that every tool connects to the same `http://localhost:8080/v1` endpoint, making the stack greater than the sum of its parts.

This package reuses the existing `llama.cpp` TurboQuant build from project 01 (`~/llama-low-vram-repro/llama-cpp-turboquant/build`). No new `llama.cpp` compilation or host-level changes are needed. The video did not specify a particular model; this guide uses whichever GGUF is already present in the model directory.

This host has a GTX 1070 (8 GB VRAM), 62 GiB RAM, Docker with NVIDIA passthrough, and Node.js 22 — matching the video's prerequisites. The largest risk is that large Docker image pulls (AnythingLLM, n8n) require user approval and bandwidth. The second risk is that the video's UI-based configuration steps (AnythingLLM settings, n8n credential setup) cannot be fully automated; they are documented as manual steps.

## 2. Source handling

### Local primary evidence

`04_local_ai_stack_chat_rag_agent_automation.txt` supplied the full spoken progression: why local AI matters, the tree metaphor for the stack (engine seed → hardware roots → server trunk → tool branches), the setup of llama-server/router, deploying AnythingLLM via Docker, configuring RAG inside AnythingLLM, installing Pi for coding, deploying n8n for automation, and the homelab bonus tips. `description.txt` supplied chapter boundaries, exact tool names (AnythingLLM, Open WebUI, Pi, OpenCode, n8n), and URLs.

Directly supported claims include:

- llama.cpp exposes an OpenAI-compatible REST endpoint at `/v1`.
- AnythingLLM can be deployed via Docker with `network_mode: host` to reach local services.
- RAG is configured inside AnythingLLM using its built-in LanceDB vector database.
- Pi is installed via `npm install -g @earendil-works/pi-coding-agent`.
- Pi has a llama.cpp plugin that connects to the local endpoint.
- n8n is deployed via Docker and configured with an OpenAI-compatible credential pointing at the local endpoint.
- n8n agents can automate email triage using the local LLM.
- Bonus tips: dedicated machine, BIOS power-on after power loss, container manager (Portainer/Arcane), Tailscale.

### External verification

- AnythingLLM Docker deployment: verified at https://anythingllm.com and the official MintplexLabs Docker Hub image (`mintplexlabs/anythingllm`).
- Pi coding agent: verified at https://pi.dev — npm package `@earendil-works/pi-coding-agent`, config file at `~/.pi/config.json`.
- n8n Docker deployment: verified at https://n8n.io — official image `n8nio/n8n`, health endpoint at `/healthz`.
- llama-swap alternative router: verified at https://github.com/mostlygeek/llama-swap — Go binary with YAML config, also available as Docker image.
- The existing `llama.cpp` build (revision `c26cbdffc`, version 9971) supports `--models-preset` for built-in router mode and the full OpenAI-compatible API.

### Inferences

The video never prints its full Docker Compose content, exact model used, or Pi config file contents. This package infers:
- The default model (`Qwen3.6-35B-A3B-UD-Q4_K_S.gguf` from the existing model directory) as the served model.
- A reasonable Docker Compose structure for AnythingLLM and n8n with `network_mode: host`.
- Pi's configuration format and the `llamacpp` provider key.

### Host-specific adaptations

- The video used `network_mode: host` for AnythingLLM. This is preserved.
- The video installed Pi via npm. This host has Node.js 22, so npm installation works directly.
- The host has the TurboQuant `llama.cpp` build already. Standard flags are used.
- NVIDIA GPU passthrough for Docker is verified working.

## 3. Host assumptions and observed environment

| Item | Observation | Status |
|---|---|---|
| OS | Ubuntu 22.04.5 LTS | Suitable |
| GPU | GTX 1070, 8192 MiB, compute 6.1 | Suitable |
| NVIDIA driver | 535.309.01 | Suitable |
| CPU | Intel i7-6700, 4C/8T, AVX2 | Suitable |
| RAM | 62 GiB | Suitable |
| Disk | Sufficient for models and Docker images | Suitable |
| Docker | 29.5, compose plugin v5.1.3, GPU passthrough tested | Suitable |
| Node.js | v22.19.0, npm 10+ | Suitable for Pi |
| Existing `llama.cpp` build | `~/llama-low-vram-repro/llama-cpp-turboquant/build`, revision `c26cbdffc`, version 9971 | Ready |
| Available models | Qwen3.6-35B-A3B, Qwen3.6-28B-A3B, GLM-4.7-Flash-23B-A3B (all GGUF) | Ready |

The video's Proxmox/LXC/Docker stack is not reproduced because this host runs natively. The `network_mode: host` Docker configuration matches the video's approach.

## 4. Chapter-by-chapter replication guide

### 4.1 0:00 — Why local AI isn't optional

**Objective:** understand the motivation for a self-hosted AI stack — ownership, privacy, no subscription dependency.

**Technical change:** none. Conceptual only.

**Commands:** none.

**Expected observation:** the video argues that even if human intelligence remains superior, we can't deploy our brains 24/7. Renting AI (API subscriptions) creates dependency; owning the stack gives control.

**Validation:** read the transcript section 0:00-1:08.

### 4.2 1:08 — The engine — llama.cpp + the router

**Objective:** establish the inference engine and OpenAI-compatible endpoint that the rest of the stack connects to.

**Technical change:** run llama-server (or llama-swap) as a router serving one or more models over an OpenAI-compatible REST API.

**Prerequisites:** existing `llama.cpp` build at `~/llama-low-vram-repro/llama-cpp-turboquant/build`, at least one GGUF model file.

**Commands:**

```bash
# Verify the existing build
./scripts/00_host_check.sh

# Confirm the build works and the server starts
./scripts/01_verify_llamacpp.sh

# Start the server in serve mode (runs until killed)
./scripts/02_serve_model.sh
```

**Expected observation:** llama-server starts on port 8080, `/health` returns OK, `/v1/models` lists the loaded model, and `/v1/chat/completions` responds to a test prompt.

**Validation:** `01_verify_llamacpp.sh` performs all three checks automatically.

**Likely failures:** missing `MODEL_FILE` in `config.env`, model not found, port 8080 already in use, or CUDA OOM if the model is too large for the GPU and system RAM. See the adaptation note below.

**Host-specific adaptation:** If port 8080 is in use, override: `LLAMA_PORT=8081 ./scripts/02_serve_model.sh`. If the model OOMs, try a smaller model such as `MODEL_FILE=Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf ./scripts/02_serve_model.sh`. Default GPU layers are `-ngl 99`; reduce with `-ngl 20` at the end of the CLI_ARGS in `config.env`.

**Reversal:** stop the server with `kill $(cat $RESULTS_DIR/*.pid)`.

> **Router alternatives (llama-swap):** The video mentions llama-swap as an alternative to llama-server's built-in router. See Section 10 for details. This guide uses llama-server directly because it is already built and available.

### 4.3 2:55 — Chat UI — AnythingLLM

**Objective:** deploy a chat interface that connects to the local LLM endpoint.

**Technical change:** deploy AnythingLLM via Docker with `network_mode: host` so it can reach `localhost:8080`.

**Prerequisites:** Docker running, `llama-server` from 4.2 operational.

**Commands:**

```bash
./scripts/03_docker_stack.sh up
```

**Expected observation:** AnythingLLM becomes available at `http://localhost:3001`.

**Validation:** visit `http://localhost:3001` in a browser, create an account, then:

1. Go to **Settings → LLM Preference** (or **Providers → LLM** in newer versions).
2. Select **OpenAI** or **Generic OpenAI** as the LLM provider.
3. Set **Base URL** to `http://localhost:8080/v1` (the llama-server endpoint).
4. Leave the API key blank or use any dummy value.
5. Select the model from the dropdown (it auto-populates from `/v1/models`).
6. Set **Max Tokens** (e.g., 4096) and **Context Length** (e.g., 4096 or the model's max).
7. Save settings and start chatting.

**Likely failures:** Docker daemon not running, port 3001 in use, AnythingLLM image not pulled (first pull ~1 GB), or `network_mode: host` preventing port mapping display (the service is still accessible at localhost:3001 despite `docker ps` showing no mapped port).

**Reversal:** `./scripts/03_docker_stack.sh stop`.

### 4.4 4:49 — RAG — chat with your own documents

**Objective:** enable retrieval-augmented generation so the LLM answers from your own PDFs and documents.

**Technical change:** configure AnythingLLM's built-in vector database and embedder, then upload documents.

**Prerequisites:** AnythingLLM running and connected to the local LLM.

**Validation:** this is entirely UI-based. No script automates it.

**Steps:**

1. In AnythingLLM, create a **Workspace** (e.g., "Research" or "My Docs").
2. Go to **Settings → Vector Database** — leave the default **LanceDB** (local, no external service needed).
3. Go to **Settings → Embedder** — leave the default (AnythingLLM uses a local embedding model by default).
4. In the workspace, click the **Upload** button (paperclip icon or document upload in the workspace header).
5. Drop in PDFs, text files, or other documents. AnythingLLM chunks and embeds them locally.
6. Once processed, change the workspace **Chat Mode** from "Agent" to **Chat** (in workspace settings).
7. Ask questions about the uploaded documents. Responses will cite source documents.

**Expected observation:** the LLM answers from document content rather than general knowledge. AnythingLLM shows which document each answer came from.

**Likely failures:** no documents uploaded, embedder not configured, chat mode still set to "Agent" instead of "Chat", or the LLM ignoring retrieved context (very short context window).

**Host-specific adaptation:** the default embedder runs locally and uses CPU. For large document collections this may be slow. This is expected for a fully local setup.

**Reversal:** delete the workspace or remove uploaded documents from the workspace settings.

### 4.5 7:08 — Local coding agent — Pi

**Objective:** install and configure a local coding agent (Pi) that uses the private LLM endpoint.

**Technical change:** install Pi via npm and configure it to use the local llama.cpp endpoint.

**Prerequisites:** Node.js/npm, `llama-server` running.

**Commands:**

```bash
# Install Pi and configure it for the local endpoint
./scripts/04_setup_coding_agent.sh install

# Verify the setup
./scripts/04_setup_coding_agent.sh verify
```

**Expected observation:** Pi is installed globally and configured with `provider: "llamacpp"` and `url: "http://localhost:8080/v1"`. The verify step checks that the endpoint is reachable.

**Validation:**

```bash
# List available models through Pi
pi /models

# Ask Pi a coding question (it uses the local LLM)
pi "List all files in the current directory and explain what each one does"

# Run in interactive mode
pi
```

**Likely failures:** npm permissions, missing llama-server endpoint, or Pi not finding the config file.

**Host-specific adaptation:** Pi's default model is inferred from llama-server's `/v1/models` list. If no model is set in `~/.pi/config.json`, Pi picks the first available. To set a specific model, edit `~/.pi/config.json` and add `"model": "model-name"`.

**Reversal:** `npm uninstall -g @earendil-works/pi-coding-agent`.

> **Alt: OpenCode.** The video mentions OpenCode as an alternative coding agent. OpenCode is available at https://opencode.ai. It was not installed or tested in this reproduction package.

### 4.6 9:05 — Automation — n8n agents that run 24/7

**Objective:** deploy n8n for AI-powered automation workflows that trigger on schedules, emails, or other events — all using the local LLM.

**Technical change:** deploy n8n via Docker, create an OpenAI-compatible credential pointing at the local endpoint, build a workflow.

**Prerequisites:** Docker running, `llama-server` operational.

**Commands:**

```bash
# n8n is included in the Docker stack — it starts alongside AnythingLLM
./scripts/03_docker_stack.sh up
```

**Expected observation:** n8n becomes available at `http://localhost:5678`.

**Validation:** visit `http://localhost:5678` in a browser, create an account, then:

1. Go to **Settings → Credentials**.
2. Click **Add Credential** and select **OpenAI**.
3. Set **API Key** to any dummy value (e.g., `local-llm-key`).
4. Click the **Options** dropdown and set **Base URL** to `http://host.docker.internal:8080/v1`.
5. Save the credential.

Then create a workflow (example — email triage):

1. Add a **Trigger** node: **Schedule** (e.g., "Every Hour") or **Gmail Trigger** (watch for new emails).
2. Add an **AI Agent** node:
   - Set **Chat Model** to the OpenAI credential you created.
   - **Uncheck "Response API"** (the video notes this is important — the newer API format may not work with llama.cpp).
   - In the **System Message**, instruct the agent: "Analyze the email subject and body. If the email is important, mark it with the 'Important' label."
   - Attach a **Tool** node: **Gmail → Message → Add Label**.
   - Connect the email trigger content to the agent's input.
3. Activate the workflow.

**Likely failures:** Port 5678 in use, first n8n pull (~300 MB), credential base URL wrong (`host.docker.internal` may not work on Linux — use `localhost` or the actual host IP with `network_mode: host`), or "Responses API" checked (prevents local endpoint compatibility).

**Reversal:** `./scripts/03_docker_stack.sh stop`.

### 4.7 12:38 — Bonus — homelab tips for an always-on rig

**Objective:** turn the weekend project into a reliable always-on homelab.

**Technical change:** four infrastructure recommendations:

1. **Dedicated machine** — a box that does nothing but run AI. Keeps the stack from competing with desktop workloads.
2. **BIOS power-on after power loss** — the machine boots automatically after a power outage. Typically in BIOS → Power Management → "Restore on AC Power Loss" → set to **Power On**.
3. **Container manager** — Portainer or Arcane provides a web dashboard for container management instead of CLI-only. Deploy with:
   ```bash
   docker run -d --restart=always -p 9000:9000 \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v portainer_data:/data \
     --name portainer \
     portainer/portainer-ce:latest
   ```
4. **Tailscale** — puts the machine on a private mesh network accessible from anywhere. Install and authenticate:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
   After authentication, the AI stack is reachable at the Tailscale IP from any device on the tailnet.

**Validation:** for each step: (1) verify the machine stays up, (2) pull the power cord, restore it, and confirm auto-boot, (3) open the Portainer dashboard at `http://localhost:9000`, (4) `tailscale status` shows the machine connected.

### 4.8 13:54 — The full stack — taking back control

**Objective:** verify the entire stack works end-to-end.

**Commands:**

```bash
./scripts/05_verify_stack.sh
```

**Expected observation:** the script checks llama-server health, `/v1/models`, the AnythingLLM landing page, the n8n health endpoint, and Pi installation. All should report `[OK]`.

**Validation:** the script exits 0 when all services respond.

## 5. Reproduction plan

Run the stages in order. Do not advance after an unexplained failure.

1. Run `00_host_check.sh` to verify host readiness.
2. Ensure `config.env` contains a valid `MODEL_FILE` (copy from `config.env.example`).
3. Run `01_verify_llamacpp.sh` to confirm the build works and can start the server.
4. Run `02_serve_model.sh` to start llama-server in the background.
5. Run `03_docker_stack.sh up` to deploy AnythingLLM and n8n.
6. Configure AnythingLLM's LLM provider in the web UI (manual step — see 4.3).
7. Upload documents and enable RAG in AnythingLLM (manual step — see 4.4).
8. Run `04_setup_coding_agent.sh install && verify` to install and configure Pi.
9. Configure n8n with OpenAI-compatible credential (manual step — see 4.6).
10. Create n8n workflows (manual step — see 4.6).
11. Run `05_verify_stack.sh` to confirm everything is reachable.
12. [Optional] Apply the homelab tips from 4.7.

### Quick execution sequence (copy-paste)

```bash
# 1. Check host
./scripts/00_host_check.sh

# 2. Edit config.env — set MODEL_FILE to an existing .gguf
cp config.env.example config.env
# edit config.env

# 3. Verify build and start server
./scripts/01_verify_llamacpp.sh
./scripts/02_serve_model.sh

# 4. Deploy Docker stack (AnythingLLM + n8n) — requires user approval
./scripts/03_docker_stack.sh up

# 5. Install Pi coding agent
./scripts/04_setup_coding_agent.sh install

# 6. Verify everything
./scripts/05_verify_stack.sh
```

## 6. Script reference

| Script | Video chapter | Function | Writes results |
|---|---|---|---|
| `00_host_check.sh` | 0:00 / 1:08 | Read-only host and tool suitability check | stdout |
| `01_verify_llamacpp.sh` | 1:08 | Test llama-server startup, health, OpenAI endpoint | `$RESULTS_DIR/server_test_*.log` |
| `02_serve_model.sh` | 1:08 | Start llama-server daemon on configured port | PID file, snapshot logs |
| `03_docker_stack.sh` | 2:55 / 9:05 | Deploy/stop AnythingLLM and n8n via Docker Compose | Compose file, container logs |
| `04_setup_coding_agent.sh` | 7:08 | Install Pi and configure local endpoint | `~/.pi/config.json` |
| `05_verify_stack.sh` | 13:54 | End-to-end reachability check for all services | stdout |

## 7. Validation and benchmarks

### Metrics

| Service | Verification method | Success criterion |
|---|---|---|
| llama-server | `curl /health`, `curl /v1/models` | HTTP 200, model list returned |
| OpenAI API | `curl /v1/chat/completions` with test message | Valid JSON response with `choices[0].message.content` |
| AnythingLLM | HTTP reachable on port 3001 | Landing page loads |
| n8n | `curl /healthz` | HTTP 200 |
| Pi | `pi --version`, config file inspection | Binary found, config has correct endpoint |

### Expected comparison table

Not applicable — this video demonstrates wiring tools together, not optimizing a single model's throughput. No baseline-vs-optimized token-rate comparison is relevant. Quality metrics (RAG correctness, automation reliability, coding agent accuracy) are subjective and workload-dependent.

### What was NOT benchmarked

- Token generation speed: the existing model's throughput depends on its size and the hardware. See project 01 for model-tuning benchmarks.
- RAG retrieval accuracy: varies by document type, chunk strategy, and embedding model.
- n8n workflow reliability: depends on the specific automation logic.

## 8. Final recommended configurations

### Closest to the video

```bash
# Terminal 1: Start llama-server with the model
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  -m "$HOME/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf" \
  --no-mmproj -ngl 99 -t 4 -tb 8 -c 4096 --flash-attn auto \
  --host 127.0.0.1 --port 8080

# Terminal 2: Deploy anything-llm + n8n
docker compose -f "$WORK_DIR/docker-stack/docker-compose.yml" up -d

# Install Pi
npm install -g --ignore-scripts @earendil-works/pi-coding-agent
mkdir -p ~/.pi
cat >~/.pi/config.json <<'EOF'
{
  "provider": "llamacpp",
  "llamacpp": { "url": "http://localhost:8080/v1" },
  "model": null,
  "theme": "dark"
}
EOF
```

### Safer / lower-risk

- Use a smaller model (e.g., `Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf` at about 16 GB) if 20 GB is too tight on host RAM.
- Use `-ngl 20` instead of `-ngl 99` to keep more layers on CPU and reduce VRAM pressure.
- Start services one at a time and verify each before proceeding.

### Best effort for this host (GTX 1070, 62 GiB RAM)

```bash
# Use the largest available model
export MODEL_FILE="Qwen3.6-35B-A3B-UD-Q4_K_S.gguf"

# Start server with all available GPU layers
./scripts/02_serve_model.sh

# Then deploy the rest of the stack
./scripts/03_docker_stack.sh up
./scripts/04_setup_coding_agent.sh install
./scripts/05_verify_stack.sh
```

## 9. Uncertainties and gaps

### Directly supported by local files

- Full stack architecture: engine → server/router → chat UI → RAG → coding agent → automation.
- Exact tool names, deployment methods (Docker for AnythingLLM and n8n, npm for Pi, Tailscale for remote access).
- The `network_mode: host` Docker setting for AnythingLLM.
- The n8n "Response API" incompatibility note (uncheck for local endpoints).

### Externally verified

- Docker images exist for AnythingLLM (`mintplexlabs/anythingllm`) and n8n (`n8nio/n8n`).
- Pi's npm package name and config format were confirmed at pi.dev.
- llama-swap exists as an alternative router with Docker support.
- The existing llama.cpp build version 9971 supports the required API endpoints.

### Inferred

- The exact Docker Compose content (the video never shows the full YAML).
- Pi's config structure (`provider: "llamacpp"`) — inferred from Pi's documentation for custom providers.
- The model to serve — the video does not specify a model. This guide uses whichever GGUF is set in `config.env`.
- The chat template — llama.cpp auto-detects the template from the model metadata.

### Host-dependent empirical items

- Time to download Docker images on first pull.
- Whether `network_mode: host` causes port display issues in `docker ps`.
- Whether Pi's llama.cpp plugin resolves models correctly from `/v1/models`.
- n8n workflow execution speed with different models.
- Whether `host.docker.internal` resolves to localhost on this Docker setup.

### Items not reproduced

- **Proxmox/LXC setup**: the video used Proxmox VMs and LXC containers. This host runs natively on Ubuntu. The Docker services are equivalent.
- **llama-swap**: the video mentions it as an alternative router. This guide uses llama-server's built-in router. llama-swap can be deployed separately if desired (see Section 10).
- **Open WebUI**: the video offers it as an alternative to AnythingLLM. Not deployed here.
- **OpenCode**: the video offers it as an alternative to Pi. Not installed here.

## 10. Appendix

### Glossary

| Term | Meaning |
|---|---|
| OpenAI-compatible endpoint | REST API at `/v1/chat/completions` that accepts the same JSON format as OpenAI's API |
| llama-server | Built-in HTTP server in llama.cpp that exposes an OpenAI-compatible API |
| llama-swap | Standalone Go-based router that manages multiple model backends and swaps between them |
| Router | A service that directs API requests to the correct model backend |
| RAG | Retrieval Augmented Generation: retrieve relevant document chunks, then generate an answer grounded in them |
| LanceDB | Embedded vector database used by AnythingLLM for local RAG |
| Embedder | Model that converts text chunks into vector embeddings for semantic search |
| n8n | Workflow automation platform (open-source alternative to Zapier) |
| Pi | Minimal coding agent harness that connects to various LLM providers |
| Tailscale | WireGuard-based mesh VPN for private network access |

### llama-swap alternative

The video mentions llama-swap as an alternative to llama-server's built-in router. To use it:

```bash
# Pull the unified Docker image (CUDA)
docker pull ghcr.io/mostlygeek/llama-swap:unified-cuda

# Create config
mkdir -p "$WORK_DIR/llama-swap"
cat >"$WORK_DIR/llama-swap/config.yaml" <<'EOF'
models:
  qwen35-35b:
    cmd: /app/llama-server --port ${PORT} -m /models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf -ngl 99 -t 4
  qwen35-28b:
    cmd: /app/llama-server --port ${PORT} -m /models/Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf -ngl 99 -t 4
EOF

# Run
docker run -d --restart=always --gpus all -p 9292:8080 \
  -v "$MODEL_DIR:/models" \
  -v "$WORK_DIR/llama-swap/config.yaml:/etc/llama-swap/config/config.yaml" \
  ghcr.io/mostlygeek/llama-swap:unified-cuda
```

### Upstream links

- Video: https://www.youtube.com/watch?v=oh50KFF8A_0
- llama.cpp: https://github.com/ggml-org/llama.cpp
- llama-swap: https://github.com/mostlygeek/llama-swap
- AnythingLLM: https://anythingllm.com — Docker: `mintplexlabs/anythingllm`
- Pi coding agent: https://pi.dev — npm: `@earendil-works/pi-coding-agent`
- OpenCode: https://opencode.ai
- n8n: https://n8n.io — Docker: `n8nio/n8n`
- Portainer: https://www.portainer.io
- Tailscale: https://tailscale.com
- Existing build revision: `c26cbdffc` (TurboQuant fork at https://github.com/TheTom/llama-cpp-turboquant)

### End-to-end checklist

- [ ] `00_host_check.sh` passes all checks.
- [ ] At least one GGUF model file exists in `$MODEL_DIR`.
- [ ] `config.env` has `MODEL_FILE` set to an existing file.
- [ ] `01_verify_llamacpp.sh` confirms the server starts and responds.
- [ ] `02_serve_model.sh` keeps llama-server running.
- [ ] `03_docker_stack.sh up` starts both containers.
- [ ] AnythingLLM LLM provider configured to `http://localhost:8080/v1` (manual).
- [ ] Documents uploaded and RAG working in AnythingLLM (manual).
- [ ] `04_setup_coding_agent.sh install` completes without error.
- [ ] `pi /models` lists the served model.
- [ ] n8n running on port 5678 (manual credential setup done).
- [ ] `05_verify_stack.sh` reports all `[OK]`.
- [ ] (Optional) Tailscale installed and machine accessible remotely.
- [ ] (Optional) BIOS power-on-after-loss configured.
