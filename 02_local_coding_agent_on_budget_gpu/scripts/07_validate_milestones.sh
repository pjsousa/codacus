#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

id="$(run_id)"
json_result="$RESULTS_DIR/milestone-validation-$id.json"
md_result="$RESULTS_DIR/milestone-validation-$id.md"

python3 - "$PROJECT_DIR" "$RESULTS_DIR" "$MODEL_DIR" "$json_result" "$md_result" "${VALIDATION_PROFILE:-$MODEL_PROFILE}" <<'PY'
import glob
import hashlib
import json
import pathlib
import sys
from datetime import datetime, timezone

project, results, models, json_output, md_output, validation_profile = sys.argv[1:]
results_path = pathlib.Path(results)
models_path = pathlib.Path(models)

def latest(pattern):
    candidates = []
    for path in glob.glob(str(results_path / pattern)):
        try:
            data = json.loads(pathlib.Path(path).read_text())
            timestamp = data.get("timestamp", "")
        except (OSError, json.JSONDecodeError):
            timestamp = ""
        candidates.append((timestamp, pathlib.Path(path).stat().st_mtime_ns, path))
    return max(candidates)[2] if candidates else None

def status_from(pattern, missing_message, profile=None):
    paths = glob.glob(str(results_path / pattern))
    parsed = []
    if profile is not None:
        for path in paths:
            try:
                data = json.loads(pathlib.Path(path).read_text())
                if data.get("profile") == profile:
                    parsed.append((data.get("timestamp", ""), pathlib.Path(path).stat().st_mtime_ns, path, data))
            except (OSError, json.JSONDecodeError):
                pass
    else:
        for path in paths:
            try:
                data = json.loads(pathlib.Path(path).read_text())
                parsed.append((data.get("timestamp", ""), pathlib.Path(path).stat().st_mtime_ns, path, data))
            except (OSError, json.JSONDecodeError):
                pass
    if not parsed:
        return "NOT RUN", missing_message, None
    _, _, path, data = max(parsed)
    return data.get("status", "WARN"), data.get("message", "See evidence"), path

milestones = []
def add(name, source, status, criterion, message, evidence=None):
    milestones.append({
        "name": name,
        "source": source,
        "status": status,
        "criterion": criterion,
        "message": message,
        "evidence": evidence,
    })

s, m, e = status_from("preflight_*.json", "Run scripts/00_preflight.sh")
add("Host preflight", "Hardware, 00:58", s, "GPU/build/utilities recorded", m, e)
s, m, e = status_from("llamacpp_capabilities_*.json", "Run scripts/01_verify_existing_llamacpp.sh")
add("llama.cpp capabilities", "Optimization, 07:35", s, "CUDA and exact required flags verified", m, e)

profile_model = {
    "qwen-reap-safe": ("Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf", "qwen-reap-q4km", 17264580480, "dcd137ca7984ebdaa041ef80281322773bc1a9911ef639b7e698a20979953a00"),
    "qwen-reap-video-intent": ("Qwen3.6-28B-REAP20-A3B-Q4_K_M.gguf", "qwen-reap-q4km", 17264580480, "dcd137ca7984ebdaa041ef80281322773bc1a9911ef639b7e698a20979953a00"),
    "glm-reap-safe": ("GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf", "glm-reap-q4km", 14113838816, "038e930ee1e050dca7732a7a2c768a4b0f83f5655add1acb6c7380852b9eef68"),
    "glm-reap-video-intent": ("GLM-4.7-Flash-REAP-23B-A3B-Q4_K_M.gguf", "glm-reap-q4km", 14113838816, "038e930ee1e050dca7732a7a2c768a4b0f83f5655add1acb6c7380852b9eef68"),
}.get(validation_profile)
selected_model = models_path / profile_model[0] if profile_model else None
download_evidence = latest(f"model-download-{profile_model[1]}-*.json") if profile_model else None
current_model_valid = False
if selected_model and selected_model.is_file() and selected_model.stat().st_size == profile_model[2]:
    digest = hashlib.sha256()
    with selected_model.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    current_model_valid = digest.hexdigest() == profile_model[3]
if download_evidence:
    try:
        download_data = json.loads(pathlib.Path(download_evidence).read_text())
        status = download_data.get("status", "WARN") if current_model_valid else "FAIL"
        message = download_data.get("message", "See evidence") if current_model_valid else "Historical download evidence exists, but the current selected artifact is missing or has the wrong size/hash"
        add("REAP Q4 model available", "Models, 03:30", status, "Pinned size and hash validated", message, download_evidence)
    except (OSError, json.JSONDecodeError):
        add("REAP Q4 model available", "Models, 03:30", "WARN", "Pinned size and hash validated", "Download evidence could not be parsed", download_evidence)
elif current_model_valid:
    add("REAP Q4 model available", "Models, 03:30", "WARN", "Pinned size and hash validated", f"File exists but run download script to produce validation evidence: {selected_model.name}")
elif not profile_model:
    add("REAP Q4 model available", "Models, 03:30", "NOT RUN", "Pinned size and hash validated", f"Selected validation profile {validation_profile} is not a video-aligned REAP profile")
else:
    add("REAP Q4 model available", "Models, 03:30", "NOT RUN", "Pinned size and hash validated", "No video-aligned REAP model downloaded")

for key, label, source, criterion in (
    ("smoke", "Base inference", "Optimization, 07:35", "Valid prompt and generation rates"),
    ("threads", "Thread tuning", "Optimization, 07:35", "Stable host-specific decode optimum"),
    ("ubatch", "Micro-batch prefill tuning", "Optimization, 07:35", "Measured prefill gain without unsafe resource use"),
):
    s, m, e = status_from(f"benchmark-{key}-{validation_profile}-*.json", f"Run scripts/06_benchmark.sh {key} {validation_profile}", validation_profile)
    add(label, source, s, criterion, m, e)

kv_runs = []
for path in sorted(glob.glob(str(results_path / "benchmark-kv-*.json"))):
    try:
        data = json.loads(pathlib.Path(path).read_text())
        config = data.get("configuration", {})
        cache_pair = (config.get("cache_type_k"), config.get("cache_type_v"))
        safe_telemetry = isinstance(data.get("minimum_vram_free_mib"), (int, float)) and data["minimum_vram_free_mib"] >= 768
        safe_swap = data.get("swap_before_bytes") is not None and data.get("swap_after_bytes") is not None and data["swap_after_bytes"] <= data["swap_before_bytes"] + 64 * 1024 * 1024
        if data.get("profile") == validation_profile and data.get("status") in ("PASS", "WARN") and all(cache_pair) and data.get("matrix_complete") and safe_telemetry and safe_swap:
            invariants = tuple(sorted((key, json.dumps(value, sort_keys=True)) for key, value in config.items() if key not in ("cache_type_k", "cache_type_v")))
            kv_runs.append((cache_pair, invariants, config, path))
    except (OSError, json.JSONDecodeError):
        pass
distinct_kv = {item[0] for item in kv_runs}
context_evidence = None
for path in glob.glob(str(results_path / "context-*.json")):
    try:
        data = json.loads(pathlib.Path(path).read_text())
        if data.get("profile") == validation_profile:
            if context_evidence is None or data.get("timestamp", "") > context_evidence[0]:
                context_evidence = (data.get("timestamp", ""), path, data)
    except (OSError, json.JSONDecodeError):
        pass
context_pass = False
context_path = context_evidence[1] if context_evidence else None
context_data = context_evidence[2] if context_evidence else {}
if context_data.get("status") == "PASS":
    context_config = context_data.get("configuration", {})
    context_pair = (context_config.get("cache_type_k"), context_config.get("cache_type_v"))
    context_invariants = (context_config.get("n_cpu_moe"), context_config.get("ubatch_size"))
    same_invariants = {item[1] for item in kv_runs}
    matching_config = next((item[2] for item in kv_runs if item[0] == context_pair), {})
    context_pass = (
        context_pair in distinct_kv and len(same_invariants) == 1
        and matching_config.get("n_cpu_moe") == context_config.get("n_cpu_moe")
        and matching_config.get("ubatch_size") == context_config.get("ubatch_size")
        and matching_config.get("model_sha256") == context_config.get("model_sha256")
    )
if len(distinct_kv) >= 2 and context_pass and len({item[1] for item in kv_runs}) == 1:
    add("TurboQuant comparison", "Optimization, 07:35", "PASS", "KV profiles measured and retrieval quality checked", f"Compared {sorted(distinct_kv)} with invariant controls and matching context retrieval", ", ".join(path for _, _, _, path in kv_runs[-2:]) + f", {context_path}")
elif kv_runs:
    add("TurboQuant comparison", "Optimization, 07:35", "WARN", "KV profiles measured and retrieval quality checked", "Need two safe KV measurements with invariant controls plus matching context retrieval", ", ".join(path for _, _, _, path in kv_runs[-2:]))
else:
    add("TurboQuant comparison", "Optimization, 07:35", "NOT RUN", "KV profiles measured and retrieval quality checked", "Run two kv benchmarks with distinct CACHE_TYPE_K/V_OVERRIDE values, then context validation")

placement_runs = []
for path in sorted(glob.glob(str(results_path / "benchmark-smoke-*.json"))):
    try:
        data = json.loads(pathlib.Path(path).read_text())
        config = data.get("configuration", {})
        rate = data.get("token_generation", {}).get("median_tokens_per_second")
        n_cpu_moe = config.get("n_cpu_moe")
        if data.get("profile") == validation_profile and data.get("status") in ("PASS", "WARN") and isinstance(rate, (int, float)) and isinstance(n_cpu_moe, int):
            controls = tuple(sorted((key, json.dumps(value, sort_keys=True)) for key, value in config.items() if key != "n_cpu_moe"))
            placement_runs.append((data.get("profile"), n_cpu_moe, float(rate), data.get("minimum_vram_free_mib"), controls, path))
    except (OSError, json.JSONDecodeError):
        pass

placement_result = None
for profile_name in [validation_profile]:
    candidates = [item for item in placement_runs if item[0] == profile_name]
    comparable = None
    for controls in {item[4] for item in candidates}:
        group = sorted((item for item in candidates if item[4] == controls), key=lambda item: item[1], reverse=True)
        distinct = []
        for item in group:
            if not any(existing[1] == item[1] for existing in distinct):
                distinct.append(item)
        if len(distinct) >= 2:
            comparable = (distinct[0], distinct[-1])
            break
    if comparable is None:
        continue
    baseline, candidate = comparable
    gain = candidate[2] / baseline[2] - 1 if baseline[2] else 0
    margin = candidate[3]
    evidence = f"{baseline[5]}, {candidate[5]}"
    if gain > 0.05 and margin is not None and margin >= 768:
        placement_result = ("PASS", f"{profile_name}: n-cpu-moe {baseline[1]} to {candidate[1]} improved decode by {gain:.1%} with {margin:.0f} MiB minimum VRAM headroom", evidence)
    else:
        placement_result = ("WARN", f"{profile_name}: placement comparison did not prove >5% gain with >=768 MiB headroom", evidence)
    break

if placement_result:
    s, m, e = placement_result
else:
    s, m, e = "NOT RUN", "Run two smoke benchmarks for one profile with distinct N_CPU_MOE_OVERRIDE values", None
add("Expert placement tuning", "Optimization, 07:35", s, "Measured gain with safe VRAM margin", m, e)
s, m, e = status_from("cache-reuse-*.json", "Run the A/B/C cache-reuse fixture in VALIDATION.md", validation_profile)
add("Prompt cache reuse", "Optimization, 07:35", s, "Middle edit reuses chunks beyond the unchanged prefix", m, e)

s, m, e = status_from(f"server-{validation_profile}-*.json", "Start a confirmed local server with scripts/04_start_model_server.sh", validation_profile)
if e and profile_model:
    try:
        server_data = json.loads(pathlib.Path(e).read_text())
        if server_data.get("configuration", {}).get("model_sha256") != profile_model[3]:
            s, m = "FAIL", "Server evidence used a model digest different from the selected pinned artifact"
    except (OSError, json.JSONDecodeError):
        s, m = "FAIL", "Server evidence could not be parsed"
add("Local server/API", "Pi setup, 11:48", s, "Loopback health and inference succeed", m, e)
s, m, e = status_from("pi-smoke-*.json", "Install Pi, start the server, and run scripts/05_run_pi_agent.sh", validation_profile)
add("Pi agent smoke", "Pi setup, 11:48", s, "Read-only tool call succeeds in disposable workspace", m, e)
s, m, e = status_from("hot-swap-*.json", "Requires both REAP models and the A-to-B-to-A procedure in VALIDATION.md")
add("Model hot swap", "Pi setup, 11:48", s, "A to B to A with one router PID and inference after each load", m, e)
add("Tailscale remote access", "Remote access, 13:55", "NOT RUN", "Authenticated, least-privilege remote access validated", "Optional global install/enrollment requires explicit confirmation")
s, m, e = status_from("context-*.json", "Long context can exceed 15 minutes; follow the confirmed procedure in VALIDATION.md", validation_profile)
add("Long-context reliability", "Final build, 16:19", s, "Retrieval and stability pass at selected context", m, e)

required = [item for item in milestones if item["name"] != "Tailscale remote access"]
if any(item["status"] == "FAIL" for item in required):
    overall = "FAIL"
elif any(item["status"] == "NOT RUN" for item in required):
    overall = "NOT RUN"
elif any(item["status"] == "WARN" for item in required):
    overall = "WARN"
else:
    overall = "PASS"

data = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "overall": overall,
    "reproduced": overall == "PASS",
    "validation_profile": validation_profile,
    "milestones": milestones,
}
pathlib.Path(json_output).write_text(json.dumps(data, indent=2) + "\n")

lines = [
    "# Milestone Validation",
    "",
    f"Overall: **{overall}**",
    "",
    "The video is reproduced only when every applicable required milestone is `PASS`.",
    "",
    "| Milestone | Source | Status | Criterion | Observation | Evidence |",
    "|---|---|---|---|---|---|",
]
for item in milestones:
    evidence = item["evidence"] or "-"
    values = [item["name"], item["source"], item["status"], item["criterion"], item["message"], evidence]
    lines.append("| " + " | ".join(str(value).replace("|", "\\|") for value in values) + " |")
pathlib.Path(md_output).write_text("\n".join(lines) + "\n")
PY

overall="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["overall"])' "$json_result")"
status_line "$overall" "Milestone validation complete"
printf 'JSON: %s\nMarkdown: %s\n' "$json_result" "$md_result"
[[ "$overall" != "FAIL" ]]
