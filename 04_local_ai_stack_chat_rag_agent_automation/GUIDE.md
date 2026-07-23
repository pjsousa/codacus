# Fully Private Local AI Stack (Chat, RAG, Coding Agent, Automation)

This is a chapter-aligned reproduction package for the video **Build Your Own Fully Private, Local AI Stack (Chat, RAG, Coding Agent, Automation)**. Commands were prepared for this host on 2026-07-22. Run them from this repository.

The package wires every layer of the video's stack onto one local OpenAI-compatible endpoint served by the existing project-01 `llama.cpp` TurboQuant build. It does not rebuild the host or the engine; it consumes them read-only.

## 1. Executive overview

The video builds a tree: llama.cpp is the seed, the hardware is the roots, and a model server with a router distributes the model to every branch — chat UI (AnythingLLM), RAG over private documents (LanceDB inside AnythingLLM), a coding agent (Pi with the pi-llama-cpp extension), and 24/7 automation (n8n). The closing chapter adds always-on homelab practices (dedicated machine, BIOS power-on after power loss, a container manager, Tailscale).

The single integration fact that makes the stack work: **llama-server exposes an OpenAI-compatible REST endpoint, and every tool in the video can point at such an endpoint.** This package makes that endpoint concrete, pinned, and testable on this host, then validates each layer against it.

Host-specific headline adaptations (details in section 3):

| Item | Video | This host | Adaptation |
|---|---|---|---|
| Engine | llama.cpp, version unstated | Existing project-01 fork build, b9971 (`c26cbdff`), CUDA `sm_61` | Reused read-only; verified against `--help` |
| Router | llama-server model preset mode | Same, supported by this build | `--models-preset` with one named preset |
| Engine port | 8080 | **8080 is already bound** by an existing Dify container | Router on `127.0.0.1:8088` |
| Model | "the model" from the previous video | `Qwen3.6-35B-A3B-UD-Q4_K_S.gguf` (20.9 GB, already local) | Pinned by filename + SHA-256 from project 01 |
| Engine tuning | Covered by the previous video | Project 01 measured this host | Defaults = project 01 safer profile (`--n-cpu-moe 40`, `q8_0`/`turbo4` KV, 64K context) |
| Container manager | Arcane dashboard | Plain Docker 29.5 + Compose v5.1 | Project-local compose files |
| Bind exposure | UIs on LAN, engine implied LAN-reachable | Engine loopback-only; UIs on host networking (LAN) like the video | Safety default; alternatives documented |

Largest risks: the two UI containers expose ports 3001/5678 on all interfaces when using the video's host-networking mode; Pi's npm ecosystem moves fast (pinned, but the extension is third-party); Gmail OAuth and n8n workflow construction are manual UI steps that cannot be fully scripted; and a 21 GB model plus two always-on containers leaves this 62 GiB host comfortable but not unlimited RAM.

## 2. Source handling

### Local primary evidence

`04_local_ai_stack_chat_rag_agent_automation.txt` (full transcript) supplied the sequence, the tree metaphor, the tool choices, and every UI-level instruction. `description.txt` supplied chapter boundaries/timestamps and the tool list with URLs.

Directly supported video claims and instructions:

- llama-server has a built-in router when started in "model preset mode"; some people have reported issues with it and it is "still early, still experimental"; llama-swap is the alternative and works off a single config file.
- Model serving exposes an OpenAI-compatible REST endpoint; that is what lets every later tool plug in.
- AnythingLLM (recommended; Open WebUI alternative) runs via Docker: grab the Docker Compose content from the GitHub page, let Docker manage the volume, strip the embedding/model-selection settings, set network to host mode, open the server's IP + port.
- AnythingLLM provider setup: Settings -> providers -> LLM -> "generic OpenAI"; base URL = machine IP + llama-server port (8080 in the video); models auto-listed; set context-window and max-token limits; "say hi, and it responds".
- RAG: vector database default LanceDB kept; embedder defaults kept; upload documents via the workspace upload button; switch workspace chat mode to "chat"; asking "What is a Swin Transformer?" answers from the document and shows the citation.
- Pi: install via the npm option from pi.dev; install "the llama.cpp Pi plugin"; configure the llama.cpp URL in Pi's global settings file as `<server-ip>:8080/v1`-style address; run `/models` to pick any model configured in llama-server. Demonstrated analyzing an old codebase (architecture, caching layers, websockets) and fixing a 6-year-old Angular project's build errors autonomously.
- n8n: same Docker Compose method; create an OpenAI credential but change the base URL to the local server; any API key value works; workflow = hourly email trigger -> AI agent (subject+body as user message, instructions as system message) -> OpenAI chat model node -> Gmail "add a label" tool; **uncheck the responses API** so it falls back to the standard OpenAI-compatible method; personal emails never touch a cloud AI.
- Bonus: dedicated always-on machine; BIOS auto power-on after power loss; container manager (Portainer, or Arcane which the author uses); Tailscale for private remote access.

### External verification (all checked 2026-07-22)

- This build's `llama-server --help` confirms router mode: `--models-dir`, `--models-preset`, `--models-max` (default 4), `--models-autoload` (default enabled), `--sleep-idle-seconds`. The fork's `tools/server/README.md` documents preset INI syntax, `POST /models/load`, `POST /models/unload`, and routing by the request's `model` field.
- Empirically on this build: a `version = 1` preamble line in the preset INI registers a bogus extra preset named `default` (parser maps the nameless preamble section to a default preset). This package therefore generates preset files that start directly with the named section — verified with a live router on a throwaway port.
- The video's "uncheck the responses API" is a compatibility choice, not a hard requirement here: this build also serves `/v1/responses`.
- AnythingLLM: current docs image `mintplexlabs/anythingllm`, port 3001, persistent storage at `/app/server/storage` with `STORAGE_DIR` env, `cap_add: SYS_ADMIN`; version tag `1.15.0` exists (docs banner calls v1.15.0 current). "Generic OpenAI" provider exists in docs. Default vector DB is LanceDB; default embedder is the built-in AnythingLLM embedder.
- Pi: pi.dev npm install is `npm install -g --ignore-scripts @earendil-works/pi-coding-agent` (current `0.81.1`). The video's "llama.cpp Pi plugin" is the third-party extension `pi-llama-cpp` (current `0.9.1`), installed with `pi install npm:pi-llama-cpp`; it reads `llamaServerUrl` from `~/.pi/agent/settings.json` (or `.pi/settings.json`, or `LLAMA_SERVER_URL`) and provides the `/models` command — matching the video exactly. Pi's core model picker is `/model` (singular).
- llama-swap: latest release `v241` (published 2026-07-22); minimal config is `models: <id>: cmd: llama-server --port ${PORT} --model ...`; listens via `--listen host:port`; Linux amd64 tarball SHA-256 recorded in `config.env.example`.
- n8n: official image `docker.n8n.io/n8nio/n8n`, port 5678, volume at `/home/node/.n8n`, `/healthz` endpoint; docs listed `2.29.8` as current stable on 2026-07-22 (the registry already carries newer tags; the docs-verified pin is kept).
- Swin Transformer paper (arXiv 2103.14030) fetched once to pin the sample document's SHA-256; arXiv can regenerate PDFs, so a checksum drift is treated as a warning, not a failure.

### Inferences and adaptations (labeled, not video facts)

- Engine port `8088` on `127.0.0.1` (8080 occupied; loopback safety). The video's tools use host networking, so `http://127.0.0.1:8088` works everywhere the video used `http://<machine-ip>:8080`.
- Model alias `local-chat` as the single stable model id every client requests.
- Engine placement/cache arguments from project 01's measured profiles (the video delegates engine tuning to the previous video).
- Project-local compose files instead of the Arcane UI; named volumes preserved.
- The Swin Transformer PDF as the fixed RAG sample (the video used the author's private papers but named this exact example question).
- n8n pin `2.29.8`; AnythingLLM pin `1.15.0`; Pi pin `0.81.1`; pi-llama-cpp pin `0.9.1`; llama-swap pin `v241`.

## 3. Host assumptions and observed environment

Observed on this host (2026-07-22, via `scripts/00_host_check.sh`):

| Item | Observation | Status |
|---|---|---|
| OS | Ubuntu 22.04.5 LTS, Linux 5.15 | Suitable |
| CPU | Intel i7-6700, 4 cores/8 threads, AVX2 | Suitable; engine tuned to 4/8 threads in project 01 |
| RAM | 62 GiB, ~53 GiB available | Comfortable for the 21 GB model + two containers |
| Swap | 2 GiB, unused | Keep unused |
| Disk | 78 GiB free on `/` | Enough for images (~3-4 GB) and logs; no new multi-GB models |
| GPU | GTX 1070 8 GB, compute 6.1, driver 535.309.01 | Suitable; containers need no GPU (engine runs natively) |
| Engine build | `~/llama-low-vram-repro/llama-cpp-turboquant` @ `c26cbdff`, b9971, clean checkout | Verified by `01_verify_engine.sh` |
| Models present | Qwen3.6-35B-A3B-UD-Q4_K_S (20.9 GB, SHA matches project 01), plus Qwen3.6-28B-REAP20 and GLM-4.7-Flash-REAP-23B quants | First is the default; others optional extra presets |
| Docker | 29.5.0 + Compose v5.1.3, 23 containers running (incl. Dify and Watercrawl stacks) | Suitable; do not disturb existing stacks |
| Node | v22.19.0 (nvm), npm 10.9.3 | Suitable for Pi |
| **Port 8080** | **Bound on 127.0.0.1 by the existing Dify nginx** | Engine moved to 8088 |
| Ports 8088/3001/5678/8089 | Free | Used by this stack |
| memlock | soft=hard=64 KiB | `ENGINE_MLOCK=1` blocked until limits are raised (host change; operator action) |

Consequences:

1. **No GPU passthrough is needed** — unlike project 01, containers here are CPU-only applications; the GPU is used only by the native engine.
2. The video's `8080` cannot be reused without disturbing the user's Dify deployment; every command and checklist uses `8088`.
3. Two extra GGUFs already on disk can be added as presets later (guide section 8 note), but `--models-max 1` is the default because a 62 GiB host should not keep two 14-21 GB models resident without an explicit decision.

## 4. Chapter-by-chapter replication guide

### 4.0 0:00 - Why local AI isn't optional

**Objective:** frame the build; no commands in the video. Here it maps to proving the host can hold the whole stack.

**Technical change:** none. Read-only inspection.

**Command:**

```bash
./scripts/00_host_check.sh
```

**Expected observation:** the table in section 3 — in particular port 8080 reported IN USE, ports 8088/3001/5678 free, memlock 64 KiB, engine build and models found.

**Validation:** archive stdout (`./scripts/00_host_check.sh | tee host_check_$(date -u +%Y%m%d).txt`); confirm no FAIL lines.

**Success/failure:** success = docker, node, curl, jq, ss present; engine binaries exist; target ports free. Failure = any missing prerequisite -> resolve before continuing (the script never installs anything).

**Likely failure modes:** docker daemon permission denied (user not in `docker` group); ports taken by other workloads.

**Host adaptation / reversal:** none; read-only.

### 4.1 1:08 - The engine: llama.cpp + the router

**Objective:** serve the local model through an OpenAI-compatible endpoint with the built-in router ("model preset mode"), the layer every later chapter plugs into.

**Technical change:** from "a model exists on disk" to "a router process answers `/v1/models`, `/v1/chat/completions`, `/models/load`, `/models/unload` on loopback".

**Prerequisites:** chapter 4.0 passed.

**Commands:**

```bash
./scripts/01_verify_engine.sh          # read-only: revision, flags, devices, model size
VERIFY_SHA256=1 ./scripts/01_verify_engine.sh   # optional deep integrity check (~1-2 min)
./scripts/02_start_engine.sh           # generates the preset, starts the router, loads the model, smoke-tests it
```

The generated preset (`stack/presets/models.ini`, regenerated each run):

```ini
[local-chat]
model = /home/pedro/llama-low-vram-repro/models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf
no-mmproj = true
fit = off
n-gpu-layers = all
n-cpu-moe = 40
cache-type-k = q8_0
cache-type-v = turbo4
ctx-size = 65536
threads = 4
threads-batch = 8
flash-attn = auto
no-mmap = true
```

Equivalent core router command (what the script launches):

```bash
$HOME/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server \
  --host 127.0.0.1 --port 8088 \
  --models-preset stack/presets/models.ini --models-max 1
```

**Expected observation:** `01` prints PASS lines including router flags and turbo cache types. `02` prints the preset path, waits for the router, requests the load (first load reads ~21 GB; expect roughly a minute on this host), then a smoke response `local engine online`, plus usage/timings JSON. RAM usage grows by ~21 GB; VRAM by the non-expert tensors (~2-3 GB by project 01 measurements).

**Validation:** the script itself performs the validation — model status reaches `loaded`, HTTP 200 chat completion, fixed prompt/seed, evidence saved as `results/engine_*_smoke.json` with before/after RAM+VRAM snapshots. Manual re-check at any time:

```bash
curl -s http://127.0.0.1:8088/v1/models | jq '.data[].id'
curl -s http://127.0.0.1:8088/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"local-chat","messages":[{"role":"user","content":"Reply with exactly: local engine online"}],"max_tokens":32,"temperature":0,"seed":42}' | jq -r '.choices[0].message.content'
```

**Success/failure:** success = `loaded` status + HTTP 200 + non-empty content. Failure = timeout (inspect `results/engine_*.log`), CUDA OOM (reduce `ENGINE_NGL`/`ENGINE_CPU_MOE`... in practice raise `ENGINE_CPU_MOE` toward 40/41 or lower `ENGINE_CTX`), or port conflict (change `ROUTER_PORT`).

**Likely failure modes:** stale PID file after a crash (rerun `02`; it refuses to double-start; `09` cleans up); another service grabbing 8088; RAM pressure from the existing 23 containers slowing the eager `--no-mmap` load.

**Host adaptations:** port 8088 (not 8080); loopback bind (video implies LAN); `--models-max 1`; engine args from project 01's safer profile; `--mlock` off because memlock limits are 64 KiB.

**Alternative router (video's llama-swap, optional):**

```bash
./scripts/03_llama_swap_alt.sh   # downloads pinned v241 binary, writes config, serves 127.0.0.1:8089
```

It wraps the exact same binary and placement args, and its first chat request triggers the model load through llama-swap. Use **either** `02` **or** `03` as the endpoint; point clients at the one you started. The video presents llama-swap as the fallback for router bugs, not as an additional always-on layer.

**Reversal:** `./scripts/09_stop_stack.sh` stops engine and llama-swap; preset/config files remain under `stack/` and logs under `results/`.

### 4.2 2:55 - Chat UI: AnythingLLM

**Objective:** browser chat against the local engine (video: "say hi, and it responds").

**Technical change:** adds the first consumer of the endpoint — a pinned `mintplexlabs/anythingllm:1.15.0` container with host networking and a named volume.

**Prerequisites:** engine running (`02`); port 3001 free.

**Command:**

```bash
./scripts/04_setup_anythingllm.sh
```

The script writes `stack/anythingllm/docker-compose.yml` (host networking, `cap_add: SYS_ADMIN`, `STORAGE_DIR=/app/server/storage`, `SERVER_PORT=3001`, `restart: unless-stopped`), pulls the pinned image, starts it, and waits for HTTP on 3001.

**Expected observation:** compose pull (~1-2 GB image on first run), container `anythingllm` up, script prints the UI checklist.

**UI steps (from the video, adapted values in bold):** Settings -> AI Providers -> LLM -> **Generic OpenAI**; Base URL = **`http://127.0.0.1:8088`** (video: machine IP + 8080); API Key = any non-empty value; Chat Model = **`local-chat`** (auto-listed from the engine); token context window = **`65536`**; max output tokens ~1024. Save, open the default workspace, send "hi".

**Validation:** scripted — container answering HTTP 200 on 3001 (also re-checked by `08`). UI checkpoint — the reply must come from the local engine: watch new requests appear in `results/engine_*.log`, and `nvidia-smi`/RAM stay on this machine.

**Success/failure:** success = chat reply in the UI + matching engine-side request log. Failure = "failed to fetch"/provider error in the UI.

**Likely failure modes:** wrong base URL (inside host networking, `127.0.0.1:8088` is correct; `localhost` inside bridge networking would not be); empty model dropdown = engine down or wrong URL; first-token latency after idle while the 21 GB model reloads.

**Host adaptations:** image pinned to `1.15.0` (video used latest); host networking kept from the video so the container reaches the loopback engine — this exposes the UI on LAN exactly like the video's setup. Safer variant: bridge networking with `ports: ["127.0.0.1:3001:3001"]` and base URL `http://host.docker.internal:8088` **requires** the engine to bind beyond loopback, so it is documented but not default.

**Reversal:** `./scripts/09_stop_stack.sh` (volume preserved); `PURGE_VOLUMES=1` also deletes AnythingLLM's data.

### 4.3 4:49 - RAG: chat with your own documents

**Objective:** grounded answers from a private document with a visible citation — the video asks "What is a Swin Transformer?" and gets an answer sourced from the uploaded paper.

**Technical change:** adds a document corpus + embeddings + LanceDB retrieval in front of the same chat endpoint. No new services: vector DB and embedder live inside AnythingLLM.

**Prerequisites:** chapter 4.2 done (provider configured).

**Command:**

```bash
./scripts/05_setup_rag.sh
```

The script downloads the pinned Swin Transformer paper (arXiv 2103.14030, ~1.4 MB, SHA-256 pinned) into `stack/rag-docs/` and prints the UI checklist.

**UI steps (from the video):** keep **LanceDB** (Settings -> Vector Database); keep the **default embedder** (first use downloads a small embedding model inside the container); upload `stack/rag-docs/Swin-Transformer-arXiv-2103.14030.pdf` via the workspace upload button; wait for embedding; move it into the workspace; set workspace chat mode to **chat** (video switched modes; use `query` for stricter document-only answers); ask **"What is a Swin Transformer?"**.

**Validation:** success = the answer describes a hierarchical vision Transformer with shifted windows **and the UI cites the uploaded PDF** as the source. Failure = generic answer with no citation (document not embedded/moved), or embedding error (check container logs; the built-in embedder download needs outbound network once).

**Success/failure criteria:** citation present + content matches the paper. Not reproducible = answer with no document citation treated as grounded.

**Likely failure modes:** document uploaded but not moved into the workspace; chat mode left on agent/default; embedder model download blocked offline; provider pointing at the wrong base URL so nothing works.

**Host adaptations:** pinned public sample document instead of the author's private papers; everything else identical to the video.

**Reversal:** delete the document from the workspace in the UI; `stack/rag-docs/` is local-only staging.

### 4.4 7:08 - Local coding agent: Pi

**Objective:** a terminal coding agent running entirely on the local endpoint (video: Pi analyzed an old codebase's full architecture and fixed a 6-year-old Angular project's build autonomously).

**Technical change:** adds a third consumer type — an agent harness that lists and loads engine models via the pi-llama-cpp extension.

**Prerequisites:** engine running; node/npm present.

**Commands:**

```bash
./scripts/06_setup_pi.sh                                  # dry run: prints pinned commands + settings snippet
INSTALL_PI=1 WRITE_PI_CONFIG=1 ./scripts/06_setup_pi.sh   # performs the installs and writes ~/.pi/agent/settings.json
```

Exact pinned commands (what `INSTALL_PI=1` runs):

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.81.1
pi install npm:pi-llama-cpp@0.9.1
```

Required global settings (`~/.pi/agent/settings.json`; the script merges with backup, or prints this for manual entry):

```json
{ "llamaServerUrl": "http://127.0.0.1:8088" }
```

**Expected observation:** `pi --version` prints 0.81.x; inside `pi`, the `/models` command (provided by the extension — the video's exact command) lists `local-chat` with a loaded/unloaded indicator; selecting it loads/switches on the engine.

**Validation:** scripted best-effort — version check plus `pi --list-models` when the engine is up. Interactive checkpoints: `/models` shows `local-chat`; ask Pi to map a small repository's architecture and confirm the engine log shows the requests.

**Success/failure:** success = Pi completes an agentic task (file reads/edits) with all inference hitting `127.0.0.1:8088`. Failure = `/models` empty or unauthorized.

**Likely failure modes:** `llamaServerUrl` written to the wrong file (project `.pi/settings.json` overrides global); extension install from an unpinned newer version behaving differently (pin via config); first request after idle paying the 21 GB reload; the extension's 60-second load-progress timeout firing during cold load while the engine keeps loading in the background — retry via `/models`.

**Host adaptations:** package scope is `@earendil-works/...` (the older `@mariozechner/...` namespace is superseded — verified on pi.dev); URL without `/v1` suffix because the extension appends it (the video's `/v1` wording matches its generic-URL phrasing; the extension's documented setting is the bare server URL); installs are opt-in (`INSTALL_PI=1`) and user-level via nvm, and the settings write is opt-in (`WRITE_PI_CONFIG=1`) because it is outside the project directory.

**Reversal:** `npm uninstall -g @earendil-works/pi-coding-agent`; remove the extension via Pi's package management (`pi install --help` shows the current removal command); restore `settings.json.bak.*` or remove `~/.pi`.

### 4.5 9:05 - Automation: n8n agents that run 24/7

**Objective:** an always-on workflow engine whose AI agent node calls the local endpoint — the video's hourly email triage that labels important mail without any email content touching a cloud AI.

**Technical change:** adds a pinned `docker.n8n.io/n8nio/n8n:2.29.8` container with host networking and a named volume.

**Prerequisites:** engine running; port 5678 free.

**Command:**

```bash
./scripts/07_setup_n8n.sh
```

**Expected observation:** image pull (~0.5-1 GB), container `n8n` up, `/healthz` answering, checklist printed.

**UI steps (from the video, with the one safety-critical toggle):**

1. Open `http://127.0.0.1:5678`, create the owner account.
2. Credentials -> New -> **OpenAI**: Base URL `http://127.0.0.1:8088/v1`, API Key any value (video: "you can put any value in for the key").
3. Workflow: **Gmail Trigger** (hourly poll) -> **AI Agent** node (system message = triage instructions; user message = subject + body expressions from the trigger) -> **OpenAI Chat Model** subnode using the credential and model `local-chat` -> **Gmail "add a label" tool** wired to the trigger's message ID, with a clear tool description.
4. **Uncheck "Use Responses API"** where offered (video instruction; this build also serves `/v1/responses`, but the standard chat-completions path is the verified one for tool-calling here).

**Validation without Gmail (recommended first):** replace the trigger with a Manual Trigger, paste a sample email subject/body, execute — the agent's classification must appear in the execution log and the engine log must show the request. Then wire Gmail OAuth (manual, Google-side) and confirm a real email gets labeled.

**Success/failure:** success = workflow execution green + label applied + all model calls visible in the local engine log. Failure = credential test error (wrong base URL — must end in `/v1`), or model/tool-calling errors in the execution view.

**Likely failure modes:** missing `/v1` suffix; Responses API left enabled against tool-calling flows; Gmail OAuth consent not completed; engine cold-load making the first hourly run slow (harmless); n8n's owner-account setup skipped.

**Host adaptations:** pinned `2.29.8` (docs "current stable" on 2026-07-22); host networking like the video (exposes the editor on LAN — restrict with a firewall rule or switch to `ports: ["127.0.0.1:5678:5678"]` bridge + engine on a LAN/docker-reachable bind if unwanted); `GENERIC_TIMEZONE` defaults to UTC — set your zone in `config.env` (host shows WEST).

**Reversal:** `./scripts/09_stop_stack.sh`; workflows/credentials persist in the `n8n_data` volume unless `PURGE_VOLUMES=1`.

### 4.6 12:38 - Bonus: homelab tips for an always-on rig

**Objective:** raise the weekend project to a reliable always-on setup. **No scripts** — these are deliberate manual/hardware steps, recorded here so the checklist is complete.

| Video tip | State on this host | Action |
|---|---|---|
| Dedicated always-on machine | This desktop already runs 23 containers | Operator decision; NOT RUN |
| BIOS auto power-on after power loss | Firmware setting, unverifiable from OS | Manual; NOT RUN |
| Container manager (Portainer/Arcane) | Plain Docker + project-local compose used instead | Optional manual install; NOT RUN |
| Tailscale private access | Not installed | Optional manual install; NOT RUN |

What this package *does* automate toward the same goal: both compose files set `restart: unless-stopped`, and `08_validate_stack.sh` verifies those restart policies. For reboot persistence of the engine itself, an optional user-approved systemd unit is the smallest remedy (template below — **not installed by any script**):

```ini
# /etc/systemd/system/local-ai-engine.service (TEMPLATE - install manually if approved)
[Service]
Type=simple
User=%i
ExecStart=%h/llama-low-vram-repro/llama-cpp-turboquant/build/bin/llama-server --host 127.0.0.1 --port 8088 --models-preset %h/Dev/codacus/04_local_ai_stack_chat_rag_agent_automation/stack/presets/models.ini --models-max 1
Restart=on-failure
[Install]
WantedBy=multi-user.target
```

**Reversal:** `sudo systemctl disable --now local-ai-engine` and remove the unit, if ever installed.

### 4.7 13:54 - The full stack: taking back control

**Objective:** prove every layer hangs off the one endpoint simultaneously.

**Technical change:** none new; integration validation.

**Command:**

```bash
./scripts/08_validate_stack.sh
# optional unattended proof (e.g. 8 hours, one probe every 5 minutes):
SOAK_SECONDS=28800 SOAK_INTERVAL=300 ./scripts/08_validate_stack.sh
```

**Expected observation:** PASS lines for the engine listing + routed chat (with response time), AnythingLLM and n8n health and restart policies (SKIP if not yet created), engine process RSS/Lock/Swap numbers; a markdown report in `results/stack_validation_*.md`.

**Validation:** the script hard-fails on any engine-layer problem and on created-but-unhealthy UI containers; the soak variant fails on any failed probe over the whole window and records `*_telemetry.csv`.

**Success/failure:** success = zero FAIL lines; for the soak, zero failed probes and flat RSS/VRAM telemetry (no growth = no leak/swap).

**Likely failure modes:** engine OOM-killed under combined load (check `dmesg`/journal); desktop load skewing response times; containers stopped by another operator action.

**Reversal:** `./scripts/09_stop_stack.sh` stops everything this package started.

## 5. Reproduction plan

Ordered quick execution sequence (do not advance after an unexplained failure):

1. `./scripts/00_host_check.sh` — archive output.
2. `./scripts/01_verify_engine.sh` — optionally with `VERIFY_SHA256=1`.
3. `./scripts/02_start_engine.sh` — engine + router + smoke test (or `03` for llama-swap).
4. `./scripts/04_setup_anythingllm.sh` — then the printed UI checklist; send "hi".
5. `./scripts/05_setup_rag.sh` — upload the staged PDF in the UI; ask "What is a Swin Transformer?"; confirm citation.
6. `INSTALL_PI=1 WRITE_PI_CONFIG=1 ./scripts/06_setup_pi.sh` — then `pi`, `/models`, pick `local-chat`, run one small agentic task.
7. `./scripts/07_setup_n8n.sh` — credential with base URL `http://127.0.0.1:8088/v1`; build the workflow with a Manual Trigger first; then Gmail.
8. `./scripts/08_validate_stack.sh` — full integration pass; optional soak.
9. Homelab items (BIOS, Tailscale, manager, systemd unit) only with explicit operator approval.
10. Teardown when needed: `./scripts/09_stop_stack.sh`.

## 6. Script reference

| Script | Video chapter | Function | Writes |
|---|---|---|---|
| `00_host_check.sh` | 0:00 | Read-only host/tool/port/build inventory | stdout |
| `01_verify_engine.sh` | 1:08 | Verify pinned build revision, router flags, devices, model size (+optional SHA-256) | stdout |
| `02_start_engine.sh` | 1:08 | Generate router preset, start llama-server router, load model, fixed smoke test | `stack/presets/`, `results/engine_*` |
| `03_llama_swap_alt.sh` | 1:08 (alternative) | OPTIONAL: pinned llama-swap download + config + routed smoke test | `stack/llama-swap/`, `results/llama_swap_*` |
| `04_setup_anythingllm.sh` | 2:55 | Compose up for AnythingLLM (pinned image, host net, named volume) + UI checklist | `stack/anythingllm/`, docker volume |
| `05_setup_rag.sh` | 4:49 | Stage pinned Swin Transformer PDF + RAG UI checklist | `stack/rag-docs/` |
| `06_setup_pi.sh` | 7:08 | Pi + pi-llama-cpp pinned installs (opt-in), settings write (opt-in), validation | user-level npm, `~/.pi` (opt-in only) |
| `07_setup_n8n.sh` | 9:05 | Compose up for n8n (pinned image, host net, named volume) + workflow checklist | `stack/n8n/`, docker volume |
| `08_validate_stack.sh` | 13:54 | End-to-end checks + restart policies + optional soak telemetry | `results/stack_validation_*` |
| `09_stop_stack.sh` | all | Stop engine/llama-swap/containers; volumes preserved unless `PURGE_VOLUMES=1` | stdout |

All scripts source `scripts/_common.sh` (paths, pins, ports, helpers), honor `config.env` overrides (copy from `config.env.example`), and pass `bash -n`. Runtime scripts log the fully resolved command into their result logs and keep failed-run logs.

## 7. Validation and benchmarks

### Metrics and capture methods

| Metric | Capture method | Success criterion | Failed reproduction |
|---|---|---|---|
| Router readiness | `GET /v1/models` poll in `02` | HTTP 200 within 60 s | Timeout / exit |
| Model load | `/v1/models` status field, `POST /models/load` | status `loaded` within 900 s | `unloaded`/`loading` forever, process exit |
| Chat correctness | Fixed prompt + seed, `max_tokens=32` | HTTP 200, non-empty content | Non-200, empty content |
| Endpoint latency | `curl -w %{time_total}` in `02`/`08` | Recorded; no fixed threshold (hardware-bound) | Comparing across unlike configs |
| Engine RAM/VRAM | `capture_snapshot` before/after, `/proc` status | ~21 GB RSS growth; VRAM consistent with project 01 | OOM kill, swap growth |
| UI availability | HTTP probe on 3001, `/healthz` on 5678 | 200 (or 302) | Container up but unhealthy |
| Restart policy | `docker inspect` in `08` | `unless-stopped` | `no` policy |
| RAG grounding | UI citation of the pinned PDF | Answer + citation | Answer without citation |
| Agent integration | `/models` in Pi; engine-side request log | Model listed; agentic task completes | Empty list / unauthorized |
| Automation integration | n8n execution green + engine log | Workflow success, local-only inference | Credential/execution error |
| Stability | `SOAK_SECONDS` probes + telemetry CSV | Zero failed probes; flat RSS/VRAM | Any failed probe or monotonic growth |

### Baseline-versus-optimized results table

Unlike project 01, this video has no throughput claims; the meaningful comparison is the router path versus a plain single-model server, plus per-layer integration. **All cells TBD/NOT RUN until executed on this host** — run `02` (router) and, optionally, a single-model control, then fill in.

| Layer | Configuration | Load time | Smoke latency | Status on this host |
|---|---|---:|---:|---|
| Engine, single-model server (control) | `llama-server -m <gguf> <args>` | TBD | TBD | NOT RUN |
| Engine, built-in router (`02`) | `--models-preset`, `--models-max 1` | TBD | TBD | NOT RUN |
| Engine, llama-swap (`03`, optional) | pinned v241 wrapper | TBD | TBD | NOT RUN |
| AnythingLLM chat | via UI, provider Generic OpenAI | - | TBD | NOT RUN |
| RAG answer w/ citation | pinned PDF embedded | - | TBD | NOT RUN |
| Pi agent task | `/models` -> `local-chat` | - | TBD | NOT RUN |
| n8n workflow run | manual trigger test | - | TBD | NOT RUN |
| 8 h soak | `SOAK_SECONDS=28800` | - | TBD | NOT RUN |

Benchmark controls: fixed smoke prompt/seed across every layer; measure on an otherwise idle machine; record engine revision (`c26cbdff`) in every report (`08` does this automatically).

## 8. Final recommended configurations

### Closest practical reproduction of the video

- Engine: `./scripts/02_start_engine.sh` defaults (router, preset `local-chat`).
- AnythingLLM with host networking, Generic OpenAI provider, base URL `http://<machine-LAN-IP>:8088` — matches the video's "IP of your machine" once the engine binds LAN: set `ROUTER_HOST=0.0.0.0` in `config.env` (conscious exposure; the video's setup implies it).
- RAG: LanceDB + default embedder + uploaded PDFs + chat mode.
- Pi + pi-llama-cpp with `llamaServerUrl` set; `/models` to pick the model.
- n8n hourly Gmail trigger -> AI Agent -> OpenAI Chat Model (Responses API unchecked) -> Gmail add-label tool.
- Homelab: BIOS power-on, container manager, Tailscale (all manual).

### Safer / lower-risk configuration (package defaults)

- `ROUTER_HOST=127.0.0.1`, `ROUTER_PORT=8088`: engine loopback-only; UIs reach it via host networking; LAN can reach the UIs but **not** the inference endpoint.
- Engine: `ENGINE_CPU_MOE=40`, `ENGINE_CACHE_K=q8_0`, `ENGINE_CACHE_V=turbo4`, `ENGINE_CTX=65536` — project 01's measured low-risk profile; `--mlock` off (limits are 64 KiB).
- Images pinned (`1.15.0`, `2.29.8`), npm pins (`0.81.1`, `0.9.1`), llama-swap pinned (`v241`).
- `LLAMA_API_KEY` set in `config.env` adds a bearer key to the endpoint (all clients then need the key).

### Best effort for this host

- Keep safer networking; enable `SLEEP_IDLE_SECONDS=900` to free RAM/VRAM when idle (first request after sleep pays reload — acceptable on an hourly automation cadence, annoying in interactive chat; measure both).
- Add the two on-disk REAP quants as extra presets only with `MODELS_MAX=1` kept (swap, not coexist):

```ini
[coder-fast]
model = /home/pedro/llama-low-vram-repro/models/GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf
; ...same placement keys as local-chat
```

- If memlock limits are ever raised (host change per project 01's guide), set `ENGINE_MLOCK=1` for stable long-run latency.
- 8 h soak pass (`08` with `SOAK_SECONDS=28800`) before trusting 24/7 automation.

## 9. Uncertainties and gaps

### Directly supported by local files

- Tool choices, chapter order, UI-level steps, the `/models` command wording, the "any API key value" and "uncheck responses API" n8n details, host-mode networking for AnythingLLM, LanceDB + default embedder choice, the Swin Transformer example, and the four homelab tips.

### Externally verified

- Router preset mode + INI syntax + load/unload endpoints on this exact binary; the `version = 1` preamble quirk (empirical); `/v1/responses` existing on this build; all image/package versions and the llama-swap checksum; AnythingLLM storage/port conventions; pi-llama-cpp's `llamaServerUrl` setting and `/models` command; n8n `/healthz`, volume path, and stable tag.

### Inferred

- Port 8088, alias `local-chat`, `--models-max 1`, project-local compose layout, pinned sample PDF, engine placement/cache defaults (from project 01), and every version pin.

### Still requiring empirical validation on this host (NOT RUN)

- First-load wall time through the router; smoke latency per layer; AnythingLLM model-dropdown behavior against this router; embedder download size; Pi `--list-models` non-interactive behavior with the extension; n8n 2.29.8's exact Responses-API toggle label/location; Gmail OAuth flow; soak stability; LAN-exposure behavior of the two UI containers.

### Known source gaps and conflicts

- The video never shows its compose file contents, llama-server version, engine flags, model identity, or Pi's exact settings file — all reconstructed and labeled above.
- The video's n8n version is unstated; UI labels may differ slightly at pin `2.29.8`.
- AnythingLLM's repo compose builds from source (dev-oriented); this package uses the published image, matching the docs' local-docker path and the video's "let Docker manage the volume" behavior.
- The transcript's "switch the chat mode from agent to chat" maps to current AnythingLLM's chat/query workspace modes; exact legacy label unverifiable.

## 10. Appendix

### Glossary

| Term | Meaning |
|---|---|
| Engine | llama.cpp inference process driving the model |
| Router mode | llama-server started without a model; loads/unloads presets on demand (`--models-preset`/`--models-dir`) |
| Preset | Named INI section mapping CLI-style keys to a model; requested by name in API calls |
| OpenAI-compatible endpoint | `/v1/chat/completions`, `/v1/models` (+`/v1/responses` here) spoken by every layer |
| llama-swap | Single-binary alternative router/proxy from the video (optional path `03`) |
| AnythingLLM | Chat UI + RAG container (Generic OpenAI provider, LanceDB, built-in embedder) |
| RAG | Retrieval-augmented generation: chunk -> embed -> vector search -> grounded answer |
| LanceDB | Default embedded vector database inside AnythingLLM |
| Embedder | Model turning document chunks into searchable vectors (AnythingLLM built-in default) |
| Pi | Minimal terminal coding agent (`@earendil-works/pi-coding-agent`) |
| pi-llama-cpp | Third-party Pi extension adding llama.cpp browsing/loading via `/models` |
| n8n | Workflow automation container; AI Agent node + OpenAI credential with base-URL override |
| Host networking | Docker mode sharing the host's network namespace (video's choice; reaches loopback services) |
| `local-chat` | This package's stable model alias requested by all clients |
| Soak | Repeated fixed probes over hours to prove stability (`08` optional mode) |

### Pinned upstream links (verified 2026-07-22)

- Video: https://www.youtube.com/watch?v=oh50KFF8A_0
- Engine build (project 01, reused read-only): https://github.com/TheTom/llama-cpp-turboquant/tree/c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea
- Router/preset docs (same revision): `tools/server/README.md` in that tree
- llama-swap v241: https://github.com/mostlygeek/llama-swap/releases/tag/v241
- AnythingLLM: https://github.com/Mintplex-Labs/anything-llm + https://docs.anythingllm.com/installation-docker/local-docker (image `mintplexlabs/anythingllm:1.15.0`)
- Pi: https://pi.dev + https://www.npmjs.com/package/@earendil-works/pi-coding-agent (`0.81.1`)
- pi-llama-cpp: https://github.com/gsanhueza/pi-llama-cpp (`0.9.1`)
- n8n: https://docs.n8n.io/deploy/host-n8n/install-options/install-with-docker/ (image `docker.n8n.io/n8nio/n8n:2.29.8`)
- Open WebUI (video's mentioned alternative UI): https://openwebui.com
- OpenCode (video's mentioned alternative agent): https://opencode.ai
- Sample RAG document: https://arxiv.org/abs/2103.14030
- Homelab tools: https://www.portainer.io , https://tailscale.com

### End-to-end checklist

- [ ] `00` archived; ports 8088/3001/5678 free; 8080 conflict understood.
- [ ] `01` all PASS; optional SHA-256 verified.
- [ ] `02` router up; `local-chat` loaded; fixed smoke response recorded.
- [ ] AnythingLLM provider saved; "hi" answered; engine log shows the request.
- [ ] Swin PDF embedded; "What is a Swin Transformer?" answered **with citation**.
- [ ] `pi --version` = 0.81.x; `/models` lists `local-chat`; one agentic task completed locally.
- [ ] n8n credential test green; manual-trigger workflow green; Responses API unchecked; Gmail labeling verified (or consciously deferred).
- [ ] `08` zero FAIL lines; restart policies `unless-stopped`.
- [ ] Optional soak: zero failed probes; flat RSS/VRAM.
- [ ] Exposure decision recorded (loopback engine vs `ROUTER_HOST=0.0.0.0`; LAN-reachable UIs).
- [ ] Homelab items (BIOS, manager, Tailscale, systemd unit) done manually or deferred explicitly.
- [ ] Teardown path tested at least once: `09` stops everything; volumes preserved.
