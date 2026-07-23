# Every Knob That Matters: Running a 35B Model on an 8GB GPU with llama.cpp

*What we learned tuning llama.cpp and llama-server across three real projects: MoE placement, KV cache compression, prefill tuning, and the one "optimization" that actually made things slower.*

---

There's a particular kind of satisfaction in watching a 20.9 GB model generate tokens on a GPU with 8 GB of VRAM. Not crawling — *flowing*, at 20+ tokens per second, with a 256K context window that would make a datacenter GPU sweat.

Over the course of three projects — running a 35B Mixture-of-Experts model on a GTX 1070, building a local coding agent on that same budget card, and wiring the whole thing into a private chat/RAG/automation stack — we turned just about every knob llama.cpp exposes. Some knobs are transformative. Some are subtle. One of them, despite sounding like free speed, reliably made things *worse*.

This post is the full tour: the mental model that makes it all click, then every parameter worth knowing, what it does, what we measured, and where we'd start.

## The mental model: why this works at all

Everything below follows from three facts.

**1. MoE models separate storage from compute.** Qwen3.6-35B-A3B has 35B total parameters, but every generated token only activates 8 routed experts plus one shared expert — about 3B active parameters. The model file still needs ~21 GB of *somewhere* to live, but the per-token compute is that of a 3B model. That asymmetry is the entire opportunity: the weights can sit in cheap, abundant system RAM while the GPU does the latency-sensitive work.

**2. Prompt processing and token generation are different workloads.** Prefill (`pp`) is parallel, compute-heavy, and loves big batches. Decode (`tg`) is serial, memory-bandwidth-bound, and happens one token at a time. A knob that triples prefill can leave decode completely flat. llama.cpp reports both — never compare one project's `pp` number against another's `tg` number and call it a win.

**3. The memory hierarchy is the spec sheet.** VRAM is fast and scarce. RAM is slower but plentiful. Disk (even via mmap) is the wildcard — fine when warm, a stutter machine when cold. Most of the art of llama.cpp tuning is deciding *which bytes live where*, and making sure they don't move.

The results arc, for context. The reference video (GTX 1060 6GB) went from ~3 tok/s with naive settings to ~17 tok/s tuned. On our GTX 1070 8GB, the same progression took generation from ~12 tok/s to ~22 tok/s — and the naive baseline OOM'd until we reduced it. Your numbers will differ; the *direction* of each knob is what transfers.

Now, the knobs.

---

## Part 1: Placement knobs — deciding where the weights live

### `-ngl` / `--n-gpu-layers` — the blunt instrument

The classic offload flag: how many model layers are eligible for GPU storage. The naive approach is to pick a number that "should fit" — and that's exactly the trap. We ran `-ngl 20` as a baseline and got the video's ~3 tok/s experience (12 on our card): layers split awkwardly, experts churning over PCIe every token, per-token stalls.

`-ngl all` is the right starting point on modern llama.cpp — but with a crucial caveat: it makes layers GPU-*eligible*, not GPU-*resident*. Eligibility is what lets the next knob do its job.

### `--n-cpu-moe N` — the star of the show

This is the single most important flag for running MoE models on small GPUs, and it's the one that took us from 12 to 19 tok/s in one step.

`--n-cpu-moe N` keeps the **expert tensors of the first N layers on the CPU**. Everything else — attention, embeddings, the shared expert, non-expert tensors — stays GPU-eligible. Why is this magic? Because expert FFN weights are the vast bulk of an MoE model's bytes, but only a thin slice of them is read per token. Reading that slice over PCIe from RAM turns out to be far cheaper than the naive layer split's constant shuffling.

The tuning loop is empirical and simple: **lower N = more expert blocks move to GPU = faster, until you OOM.**

Our sweep on the 40-layer model (higher N = more on CPU):

| `--n-cpu-moe` | 40 | 38 | 36 | 34 | 32 | 30 | 28 |
|---|---|---|---|---|---|---|---|
| Generation t/s | 7.9 | 19.9 | 20.3 | 21.1 | 21.5 | **22.3** | OOM |

Note the cliff: 28 layers' worth of experts on GPU doesn't fit, and there's no graceful degradation — just a CUDA OOM. Two practical rules:

- Sweep one value at a time and keep every OOM log; the frontier is sharp.
- Stop when you have **512 MiB–1 GiB of VRAM headroom** at your *intended context size* — a placement that fits at 4K context can OOM at 128K, because the KV cache grows.

(`--cpu-moe` pins *all* experts to CPU — it's the same idea without the numeric tuning.)

### `--fit off` and `--no-mmproj` — keeping the experiment honest

Modern llama.cpp has automatic memory fitting, which is helpful in production and poison for benchmarking: it silently changes your placement when memory gets tight. `--fit off` disables it so the placement you asked for is the placement you measured. And `--no-mmproj` skips the ~0.9 GB multimodal projector when you're doing text-only work — free VRAM for something useful.

---

## Part 2: Memory behavior knobs — keeping bytes still

### `--no-mmap` — pay the cost upfront

By default, llama.cpp mmaps the model file and lets the OS page cache manage it. Elegant, but page faults mid-generation cause latency variance, and on a cold cache you're effectively benchmarking your disk. `--no-mmap` reads the model into allocated memory at load time: slower startup, higher committed RAM, steadier tokens.

Honest measurement from our host: this took us from 19.2 to 18.9 t/s — a wash, because our file was already warm in the page cache with 62 GiB of RAM. The video saw 10 → 13.5 t/s. The lesson isn't "always use it"; it's that this knob attacks **variance and cold-cache behavior**, not steady-state speed. If you have the RAM headroom, take the stability. If your box is tight on memory, mmap is doing you a favor.

### `--mlock` — the knob that lies to you

`--mlock` asks the OS to guarantee model pages never get swapped out. The trap: on a default Linux install, `RLIMIT_MEMLOCK` is **64 KiB**, llama.cpp starts happily anyway, and the startup log gives you false confidence while nothing is actually locked. The video's locked memory went from 12 KiB to ~16 GB after fixing limits.

Do it properly:

```bash
# /etc/security/limits.d/99-llama-memlock.conf, then FULLY log out and back in
$USER soft memlock unlimited
$USER hard memlock unlimited
```

Then verify the *process*, not the logs: `grep VmLck /proc/<pid>/status` should show many GiB, not KiB. Running in Docker you need both `--cap-add IPC_LOCK` and `--ulimit memlock=-1:-1`; under systemd, `LimitMEMLOCK=infinity`. And keep swap at zero usage — a swapping inference server has already lost.

---

## Part 3: Context knobs — the KV cache is a second model

Set `-c 262144` and you've allocated a key/value cache for 262K tokens — on a 35B model that's a multi-gigabyte structure that often rivals the weights in VRAM pressure. Three knobs control it.

### `-c` / `--ctx-size` — you pay for what you allocate

Context is allocated upfront and costs memory whether or not you use it. The progression that worked: prove 64K, then 128K, then 256K, and at each step run an actual *retrieval* test (hide a key at 75% depth and ask for it back), not just "it allocated and generated." Coherent short answers say nothing about long-context behavior.

### `--cache-type-k` / `--cache-type-v` — compressing the cache

This is how 256K context fits on 8 GB: quantize the KV cache itself. Upstream llama.cpp offers `q8_0` (near-lossless) and below; the TurboQuant fork we used adds aggressive rotated low-bit codecs `turbo4`, `turbo3`, `turbo2`.

The key insight from the fork's current guidance: **K and V are not equally sensitive.** Keys drive attention scoring; compress them too hard and retrieval quality degrades. Values tolerate much more. So the recommended pattern is asymmetric — keep K at `q8_0`, push V down to `turbo3` or `turbo4`:

| Profile | K | V | Verdict |
|---|---|---|---|
| Conservative | `q8_0` | `q8_0` | Upstream-only control |
| **Recommended** | `q8_0` | `turbo3`/`turbo4` | Big savings, near-lossless K |
| Video-aggressive | `turbo4` | `turbo2`/`turbo3` | Works, but test retrieval quality first |

The practical workflow: allocate your target context with the safe profile, run the retrieval test, then step V down and re-test. Treat any profile that fails retrieval as failed no matter how good the VRAM number looks.

### `--flash-attn` — just turn it on

`--flash-attn auto` (or `on`) reduces attention memory traffic and is effectively required for long contexts to be tractable. There's no interesting tradeoff to discuss here, which is exactly why it gets one paragraph.

---

## Part 4: Compute knobs — and why prefill is the real bottleneck

For interactive chat, decode speed dominates. For a *coding agent* — where every turn reprocesses a huge system prompt plus repo context — **prefill is the bottleneck**, and these are the knobs that matter.

### `-t` / `--threads` — less than you think

Counterintuitive and consistently reproduced: decode speed peaks at a thread count around your **physical core count minus one**, then falls off a cliff. The video's numbers on a 4-core box: 28 t/s at 1 thread, **39.5 at 3**, 22 at 4. Hyperthreads don't help a bandwidth-bound workload; they fight over the same memory controllers. Start at `physical cores − 1`, sweep 1–4, and never assume 8 threads beats 3. (`-tb` / `--threads-batch` separately controls prefill threads, where more parallelism *can* help.)

### `--ubatch-size` — the prefill superpower

The micro-batch size is the biggest prefill lever we found. The video's RTX 3060 numbers: ~300 prompt t/s at ubatch 256, **1,142 prompt t/s at ubatch 2048** — nearly 4x — with decode speed flat. Cost: VRAM for the compute buffer. On a no-tensor-core Pascal card the ceiling comes earlier, so sweep 256 → 512 → 1024 → 2048 while watching VRAM, and keep your 1 GiB margin. Pair it with `--batch-size` (total batch, ≥ ubatch) rather than touching it alone.

### `--parallel` — slots for concurrency

One sequence slot is right for a single-user box. More slots mean the KV cache gets subdivided per slot — on an 8 GB card, `--parallel 1` with a big context beats `--parallel 4` with cramped contexts almost every time.

---

## Part 5: Serving knobs — llama-server as infrastructure

Once the model runs well, the next project is keeping it running well as a *service*.

### `--cache-reuse N` — the agent's best friend

With `--cache-reuse 256`, the server retains evaluated prompt chunks and reuses them when a new prompt shares a prefix — and crucially, in 256-token granularity, so a **middle edit** still reuses both the unchanged prefix *and* the unchanged suffix chunks after it. For a coding agent editing files mid-conversation, this is the difference between re-prefilling 30K tokens per turn and reusing most of them. Validate it by watching `tokens_cached` vs `tokens_evaluated` in responses. Note it doesn't raise raw pp/s — it avoids doing the work at all.

### Router mode: `--models-preset`, `--models-max`, `--models-autoload`

Run `llama-server` *without* a model and it becomes a router: an INI file of named presets, loaded on demand, addressed by the `model` field of any OpenAI-compatible request:

```ini
[local-chat]
model = /models/Qwen3.6-35B-A3B-UD-Q4_K_S.gguf
n-gpu-layers = all
n-cpu-moe = 40
cache-type-k = q8_0
cache-type-v = turbo4
ctx-size = 65536
```

```bash
llama-server --host 127.0.0.1 --port 8088 \
  --models-preset stack/presets/models.ini --models-max 1
```

Every client — chat UI, RAG, coding agent, n8n automation — then speaks plain OpenAI API to one endpoint, and you get **model hot-swapping for free**: request `glm-...` then `qwen-...` and the router unloads and loads behind the same URL. `--models-max 1` matters on a 62 GiB host — you do not want two 14–21 GB models resident because of an ambiguous request. (Practical gotcha we hit: a `version = 1` preamble line in the INI registers a bogus preset named `default` on current builds — start the file directly with your named section.) If the router misbehaves, llama-swap is a fine single-config alternative proxying the same binary.

### `--sleep-idle-seconds` — let it nap

`--sleep-idle-seconds 900` unloads the model after idle time, freeing ~21 GB of RAM and the VRAM. Perfect for an hourly automation; mildly annoying for interactive chat (first request pays the reload). Choose per workload.

### The boring-but-critical flags

- `--host 127.0.0.1` until you have a reason and an auth story — never `0.0.0.0` on a home network by default. If you must expose it, `--api-key` / `--api-key-file` (mode 0600), or Tailscale Serve in front.
- `--jinja` enables proper chat-template/tool-call handling — needed for agent clients.
- `--metrics`, `--offline`, `--no-ui`: Prometheus metrics, no network calls, no web UI — the production trinity for a headless box.
- `--cache-ram` keeps prompt cache in RAM across swaps, so a hot-swapped model returns with its context warm.

---

## Part 6: The knobs you turn before llama-server starts

**Quantization is a knob.** `Q4_K_M` is the accepted quality floor for serious work; `Q4_K_S` shaves ~15% more size for a small quality cost. On a bandwidth-bound setup, smaller quants are also *faster* quants — fewer bytes per token over the bus. Pick deliberately, verify the SHA-256, and don't benchmark two quants against each other mid-tuning.

**REAP models are a bigger, better knob.** Redundant Expert Activation Pruning removes the experts a model barely uses: the REAP-20 variant of Qwen3.6-28B reportedly keeps 95.1% HumanEval versus the original's 94.5% — *pruning made it smaller and no worse*. A 23B REAP model at Q4_K_M is ~14 GB instead of 21 GB. Same tuning playbook, more headroom everywhere.

**Even your build is a knob.** On Pascal, compile with `-DCMAKE_CUDA_ARCHITECTURES=61-real` on CUDA 12.x — otherwise you may ship PTX that JIT-compiles (or outright fails) at runtime. CUDA 13 dropped Pascal entirely.

---

## Part 7: The knob that didn't work — speculative decoding

Every optimization list needs an honest failure, and ours is a great one. Speculative decoding — a tiny draft model guesses 8 tokens, the big model verifies them in parallel — sounds perfect for a slow-decoding setup. We wired up an 800M Qwen draft: **65% acceptance rate** (looks great!) and throughput dropped from 17 to **11 tok/s** (is terrible).

The mechanism matters: our decode is *memory-bandwidth*-bound, not compute-bound. Verifying drafts still touches all the same weights, and the draft's own expert/state churn adds traffic on an already saturated bus. Acceptance rate is a vanity metric — end-to-end tokens per second is the only score. On this class of hybrid CPU/GPU MoE setup, leave speculation off unless your own benchmark says otherwise.

---

## The method behind the knobs

The tuning loop that made all of this trustworthy:

1. **One variable family at a time.** Threads, then ubatch, then KV types, then placement. Change two things and an OOM tells you nothing.
2. **Median of three, report the range.** Sub-5% movement is noise, not a win.
3. **Idle machine, fixed prompt, fixed seed, fixed context.** Never compare a 4K-context baseline against a 256K optimized run and call it placement tuning.
4. **Keep the failures.** OOM logs define your frontier; the best config is the fastest one with 512 MiB–1 GiB of VRAM to spare at your *real* context size.
5. **Verify behavior, not logs.** `VmLck` for locking, retrieval tests for KV compression, engine-side request logs for "is my chat UI really hitting the local model."

## Where to start: the cheat sheet

```bash
llama-server \
  -m Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  --no-mmproj --fit off \
  -ngl all --n-cpu-moe 40 \        # sweep down from all-CPU until OOM, back off one step
  --no-mmap --mlock \              # after fixing RLIMIT_MEMLOCK
  --cache-type-k q8_0 --cache-type-v turbo4 \
  -c 65536 --flash-attn auto \
  -t 3 -tb 8 --ubatch-size 512 --parallel 1 \
  --cache-reuse 256 --jinja --metrics --offline \
  --host 127.0.0.1 --port 8088
```

Then sweep `--n-cpu-moe` downward, grow `-c` as far as your retrieval tests allow, and grow `--ubatch-size` as far as your VRAM allows — in that order.

The big lesson across all three projects: llama.cpp performance on budget hardware isn't about finding a magic flag. It's about understanding that you're running a *hybrid* system — GPU for the small hot tensors, RAM for the big cold ones, compressed cache for the long memory — and then spending your scarce VRAM exactly where it buys tokens. The knobs are just how you make those trades explicit.

Now go make your 8 GB card punch above its weight class.
