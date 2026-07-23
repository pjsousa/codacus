# The Dyno Run: Fast-Tracking llama.cpp Tuning with llama-bench

*How to turn a weekend of knob-fiddling into an afternoon: one binary, fixed workloads, real standard deviations — and the discipline to know which number you're actually looking at.*

---

In the [previous post](BLOG.md) we tuned a 35B MoE model on an 8 GB GTX 1070 from ~12 to ~22 tokens per second. What we glossed over is how *slow* that loop was: every data point came from babysitting `llama-cli` — wait for a 21 GB model to load, generate 128 tokens, squint at one `[ Prompt: ... | Generation: ... ]` line in a log, write it down, change a flag, repeat. Each iteration costs minutes of model loading before it costs seconds of measuring.

llama.cpp ships a purpose-built dynamometer that collapses this loop: **llama-bench**. Same engine, no chat template, no sampler, no tokenization — just controlled workloads, repetitions, standard deviations, and entire parameter sweeps expressed as a single command line. If `llama-cli` is the road test, llama-bench is the dyno: you don't take a car on the highway to compare air filters.

This post is the fast track: how to run it, how to read what it tells you, and how to shape its synthetic "prompts" into workloads that actually resemble yours.

## What llama-bench actually measures

llama-bench runs exactly three kinds of test:

- **pp** — prompt processing: push N tokens through the model in batches (`-p N`). Parallel, compute-heavy, the workload that dominates a coding agent re-reading its system prompt.
- **tg** — token generation: generate N tokens, one at a time (`-n N`). Serial, memory-bandwidth-bound, the workload that dominates interactive chat feel.
- **pg** — prompt + generation: process a prompt, then generate, as one timed test (`-pg pp,tg`). The closest thing to a realistic request/response cycle.

Every test is preceded by a warmup run, then repeated `-r` times (default 5), and reported as **average tokens/second ± standard deviation**. Two details from the fine print matter more than they look:

1. **Tokenization and sampling are excluded.** llama-bench times raw model compute only. Its numbers will read slightly *higher* than what a chat session feels like — that's not a bug, it's the point. You're measuring the engine, not the dashboard.
2. **The workloads are synthetic.** There is no `--prompt` flag and there never will be. You don't hand llama-bench your prompt *text*; you hand it your prompt's *shape*. That's a feature — fixed shapes are what make two runs comparable — and we'll spend a whole section on shaping them well.

## Running it

llama-bench builds alongside the other binaries, so if you built llama.cpp you already have it. Our projects build exactly four targets:

```bash
cmake --build build --config Release \
  --target llama-cli llama-completion llama-bench llama-server
```

The first command worth running — the smoke test our automation uses before any sweep:

```bash
llama-bench \
  -m Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  -ngl 99 -ncmoe 40 -mmp 1 -fa auto \
  -t 4 -ub 512 \
  -p 512 -n 64 -r 2
```

Most flags mirror their `llama-server` counterparts, but the mapping has three traps:

| llama-bench | llama-server | Trap |
|---|---|---|
| `-ngl 99` | `-ngl all` | bench wants a *number*; 99 is the practical way to say "all layers eligible" on a 40-layer model |
| `-mmp 1` / `-mmp 0` | *(mmap default)* / `--no-mmap` | bench exposes mmap as a boolean, not an on/off flag pair |
| `-fa auto` | `--flash-attn auto` | same values (`on`/`off`/`auto`), shorter flag |
| `-ncmoe 40` | `--n-cpu-moe 40` | identical semantics |
| `-ctk q8_0 -ctv turbo3` | `--cache-type-k/v` | identical values |
| `-b` / `-ub` | `--batch-size` / `--ubatch-size` | defaults 2048/512 |

The golden rule: **benchmark the placement, not the file.** Every flag that changes where bytes live — `-ngl`, `-ncmoe`, `-mmp`, `-ctk/-ctv`, `-fa` — must match the configuration you're actually evaluating, or you're measuring a machine that doesn't exist. And kill your `llama-server` first; our project-02 automation hard-fails on exactly this, because two processes double-loading a 21 GB model measures nothing but your swap.

## Reading the results

Default output is a markdown table. A run at our tuned MoE placement produces rows in this shape (values illustrative, in the spirit of our measured runs):

| model | size | params | backend | ngl | ncmoe | test | t/s |
|---|---:|---:|---|---:|---:|---|---:|
| Qwen3.6-35B-A3B Q4_K_S | 19.46 GiB | 35 B | CUDA | 99 | 40 | pp512 | 51.10 ± 0.42 |
| Qwen3.6-35B-A3B Q4_K_S | 19.46 GiB | 35 B | CUDA | 99 | 40 | tg64 | 19.20 ± 0.11 |

Three things to train your eye on:

**The `test` column is two different sports.** `pp512` and `tg64` are not two scores of the same athlete — they're weightlifting and marathon. Prefill is parallel and compute-bound; decode is serial and bandwidth-bound. A knob that triples one can leave the other flat (ubatch does exactly this). Never compare a pp number against a tg number, never average them, and when someone quotes you "tokens per second," your first question is *which kind*.

**The ± is the honesty column.** That `± 0.11` is the standard deviation across repetitions. If config A reads `19.2 ± 0.3` and config B reads `19.5 ± 0.4`, you do not have a winner — you have overlapping noise. Our automation encodes this as a hard rule: **below 5% movement is not a result**. The fastest way to fool yourself in this hobby is to celebrate 2% "wins" that evaporate on rerun.

**The rows you *didn't* get are data.** Ask for `-t 1,2,3,4` with the default pp512/tg128 pair and you should receive 8 rows: 4 pp + 4 tg. Fewer rows than the full matrix means a configuration crashed — and llama-bench can still exit 0 with a CUDA OOM sitting in stderr. Check row completeness *and* grep stderr before trusting a table. A zero exit code is not a pass.

For anything beyond eyeballing, switch to machine-readable output (`-o jsonl`, or `-oe jsonl` to split it to stderr while watching progress on stdout). Each row carries the full test configuration plus `avg_ts`, `stddev_ts`, and `samples_ts` — the individual repetition values, so you can recompute medians yourself. The exact jq our project-03 pipeline uses to build comparison tables:

```bash
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -p 512 -n 128 -r 3 -o jsonl \
  | jq -r '[.model_filename,
            (if .n_prompt > 0 then "pp" + (.n_prompt|tostring)
             else "tg" + (.n_gen|tostring) end),
            .avg_ts, .stddev_ts] | @tsv'
```

The row-type test is worth stealing: `n_prompt > 0` = a pp row, `n_gen > 0` = a tg row. (There's also `-o sql`, which emits `INSERT` statements you can pipe straight into `sqlite3` — the beginnings of a personal results database, so next month's you can answer "didn't turbo4 used to be faster?" with a query instead of a shrug.)

## Shaping the "prompts": making synthetic workloads resemble yours

Since llama-bench takes shapes rather than text, the craft is choosing shapes that stand in for your real workload. You get four dimensions.

**Prompt length — `-p`, as lists and ranges.** Any scalar option takes comma-separated values, repeated flags, or ranges (`128-2048`, `128-2048+256`, `128-2048*2`). A length ladder shows you prefill scaling across the sizes you care about:

```bash
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -fa auto -t 4 \
  -p 128,512,2048,8192 -n 128 -r 3
```

**Combined cycles — `-pg pp,tg`.** One test that processes a prompt then generates, timed together. This is the RAG shape: a fat document in, a terse answer out:

```bash
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -fa auto -t 4 \
  -pg 8192,64 -r 3
```

**Context depth — `-d N`.** The sleeper feature. `-d` prefills the KV cache with N tokens *before* the timed test, so `pp512 @ d40960` measures prompt processing as it feels on turn 30 of a long conversation, not on a fresh session. This is the cheap way to learn what long context costs you — decode at depth is where compressed KV caches and flash attention earn their keep:

```bash
llama-bench -m model.gguf -ngl 99 -ncmoe 36 -fa auto -t 4 \
  -ctk q8_0 -ctv turbo3 -d 0,8192,32768,65536 -p 512 -n 128 -r 3
```

Watch tg fall as depth grows; that slope *is* your long-context tax, measured in an afternoon instead of discovered in production.

**Model identity — repeated `-m`.** Two models, one command, identical conditions — this is how our Bonsai-vs-Qwen shootout was wired:

```bash
llama-bench -m Bonsai-27B-Q1_0.gguf -m Qwen3.6-35B-A3B-UD-Q4_K_S.gguf \
  -ngl 99 -fa auto -t 4 -p 512 -n 128 -r 3 -o jsonl
```

(There's also `-hf user/repo:quant` to benchmark straight from Hugging Face — handy for a first look at a model you haven't committed disk to.)

A recipe card for common workloads:

| Your workload | Shape | What it tells you |
|---|---|---|
| Interactive chat | `-p 512 -n 128` | The baseline pair; tg is the "feel" number |
| Coding agent | `-p 2048,8192 -n 128 -ub 512,1024,2048` | Prefill dominates; find the ubatch knee |
| RAG / long-doc Q&A | `-pg 8192,64` | End-to-end cycle time at realistic proportions |
| Long-session degradation | `-d 0,8192,32768` | The KV-cache tax as conversation grows |
| Generation-only compare | `-p 0 -n 128,256,512` | Isolate decode; `-n 0` isolates prefill |

And the honest boundary: when you need to know how the model handles your *actual* prompt — the real system prompt with its real cache behavior — llama-bench is the wrong tool, and that's what `llama-cli --show-timings` with a fixed prompt and fixed seed is for. Bench for shape sweeps and knob hunting; CLI for verbatim truth. Our projects use exactly that division of labor.

## Sweeps: the whole matrix in one command

Every test parameter accepts lists, and llama-bench runs the **full Cartesian product**. This is the superpower and the footgun in one feature. The two sweeps at the heart of our tuning story, verbatim from the automation:

```bash
# Thread sweep: find the decode peak (spoiler on a 4-core box: it's usually cores − 1)
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -fa auto \
  -t 1,2,3,4 -ub 512 -p 512 -n 64 -r 3

# Ubatch sweep: find the prefill knee (big prompt so the batcher has work to do)
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -fa auto \
  -t 4 -ub 128,256,512,1024,2048 -p 2048 -n 64 -r 3
```

The product rule means `-t 1,2,3,4 -ub 128,256,512 -p 512,2048 -n 64,128` is not a quick check — it's 4×3×2×2 = 48 configurations, each warmed up and repeated `-r` times, on a model that takes real minutes to load per configuration. Keep matrices small and surgical; add `--delay 2` between tests if thermals matter to you (on a Pascal card in July, they do).

With that, the entire tuning arc of the previous post compresses into a five-command afternoon:

```bash
# 1. Smoke: does it load, does it run, what are the baseline pp/tg?
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -mmp 1 -fa auto -t 4 -ub 512 -p 512 -n 64 -r 2

# 2. Threads: where does decode peak?
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -fa auto -t 1,2,3,4 -p 512 -n 64 -r 3

# 3. Ubatch: where does prefill knee?
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -fa auto -t 4 -ub 128,256,512,1024,2048 -p 2048 -n 64 -r 3

# 4. Placement: how many experts can the GPU hold before OOM?
llama-bench -m model.gguf -ngl 99 -ncmoe 40,38,36,34,32,30,28 -fa auto -t 4 -p 512 -n 128 -r 3

# 5. KV cache: what does compression cost at depth?
llama-bench -m model.gguf -ngl 99 -ncmoe 36 -fa auto -t 4 -ctk q8_0 -ctv q8_0,turbo3,turbo4 -d 0,32768 -p 512 -n 128 -r 3
```

Step 4 is the sweep that took our GTX 1070 from "it works" to "it flies" — and its real measured results show exactly what to look for:

| `--n-cpu-moe` | 40 | 38 | 36 | 34 | 32 | 30 | 28 |
|---|---|---|---|---|---|---|---|
| Generation t/s | 7.9 | 19.9 | 20.3 | 21.1 | 21.5 | **22.3** | OOM |

Read it the llama-bench way: the jump from 40→38 is a mechanism (experts stopped churning over PCIe), 38→32 is a gentle frontier, and 28 is a wall — no graceful degradation, just a missing row and a CUDA OOM in stderr. The best config is the fastest one *with a row in the table and VRAM headroom to spare*.

## Interpreting like a professional: the pitfalls that invalidate everything

These are the checks our automation enforces, because each of them burned us once:

- **Stop the server first.** llama-bench loads its own copy of the model. Benchmarking next to a resident `llama-server` measures contention, not performance.
- **Exit 0 ≠ pass.** Grep stderr for `out of memory`, `cuda error`, `fatal`. A crashed configuration can leave a clean exit code and a quietly incomplete matrix.
- **Count your rows.** Missing rows are failed configurations, not missing data. Investigate before comparing.
- **Watch the machine, not just the table.** Run `nvidia-smi --query-gpu=timestamp,memory.used,utilization.gpu,pstate --format=csv,noheader -lms 500` to a file during the run. Less than ~512 MiB of VRAM headroom, or *any* swap growth, invalidates a latency number — you measured thrashing.
- **One variable family at a time.** Change `-ncmoe` and `-ctv` together and the OOM tells you nothing.
- **Don't cross the streams.** Never compare bench tg against `llama-cli` end-to-end task time (bench excludes tokenization and sampling), never compare a d0 run against a d32768 run and call it "KV cache overhead," never compare two models at different placements and call it a model comparison.
- **Keep the failures.** OOM rows define your frontier. The frontier is the map.

## Cheat sheet

```bash
# The 80% command: baseline pair, tuned placement, 3 reps, machine-readable
llama-bench -m model.gguf -ngl 99 -ncmoe 40 -mmp 1 -fa auto \
  -t 4 -ub 512 -p 512 -n 128 -r 3 -o jsonl

# Pretty-print any jsonl result
jq -r '[.model_filename,
        (if .n_prompt > 0 then "pp" + (.n_prompt|tostring)
         else "tg" + (.n_gen|tostring) end),
        .avg_ts, .stddev_ts] | @tsv' results.jsonl
```

Then the loop: smoke → threads → ubatch → placement → KV, one family at a time, 5% or it didn't happen, keep the OOMs.

The previous post was about which knobs matter. This one is about how to turn them at speed: llama-bench turns every tuning question from "start a server and vibe" into a one-line experiment with a standard deviation attached. The knobs were never the hard part — knowing, quickly and honestly, what each turn bought you is. Now you have the dyno. Go break your personal best.
