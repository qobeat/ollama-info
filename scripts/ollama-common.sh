#!/usr/bin/env bash
# Shared helpers for ollama-info v1.12 scripts. Source this file.

ollama_now_iso() { date -Is; }
ollama_log() { printf '%s %s\n' "$(ollama_now_iso)" "$*"; }
ollama_warn() { printf '%s WARN: %s\n' "$(ollama_now_iso)" "$*" >&2; }
ollama_die() { printf '%s ERROR: %s\n' "$(ollama_now_iso)" "$*" >&2; exit 2; }
ollama_need_cmd() { command -v "$1" >/dev/null 2>&1 || ollama_die "missing required command: $1"; }
ollama_require_arg_value() { local opt="$1" val="${2-}"; [[ -n "$val" && "$val" != --* ]] || ollama_die "$opt requires a value"; printf '%s\n' "$val"; }
ollama_timestamp_stream() { local line; while IFS= read -r line; do [[ "$line" =~ ^[0-9]{4}- ]] && printf '%s\n' "$line" || printf '%s %s\n' "$(ollama_now_iso)" "$line"; done; }
ollama_sanitize_name() { printf '%s' "${1:-unknown}" | sed -E 's#[/:[:space:]]+#_#g; s#[^A-Za-z0-9._-]#_#g; s#_+#_#g; s#^_+|_+$##g'; }
ollama_display_cmd() { local cmd="${1:-}"; [[ "$cmd" == */* ]] && printf '%s\n' "$cmd" || printf '%s\n' "$(basename "$cmd")"; }
ollama_bool01() { case "${1:-}" in 1|true|TRUE|yes|YES|on|ON) echo 1 ;; *) echo 0 ;; esac; }

ollama_api_ready() {
  local base_url="${1:-${BASE_URL:-http://127.0.0.1:11434}}" connect_timeout="${2:-3}"
  curl -fsS --connect-timeout "$connect_timeout" --max-time "$connect_timeout" "$base_url/api/version" >/dev/null 2>&1
}

ollama_get_json() {
  local url="$1" timeout="${2:-10}"
  curl -fsS --connect-timeout 5 --max-time "$timeout" "$url"
}

ollama_post_json_file() {
  local url="$1" payload="$2" out="$3" http_file="$4" err_file="$5" timeout="${6:-600}"
  curl -sS --connect-timeout 5 --max-time "$timeout" -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -d "@$payload" --output "$out" --write-out '%{http_code}' "$url" >"$http_file" 2>"$err_file"
}

ollama_status_short_common() {
  local base_url="${1:-${BASE_URL:-http://127.0.0.1:11434}}"
  echo "Ollama status:"
  if command -v systemctl >/dev/null 2>&1; then
    local load active enabled
    load="$(systemctl show -p LoadState --value ollama.service 2>/dev/null | head -1 || true)"
    active="$(systemctl show -p ActiveState --value ollama.service 2>/dev/null | head -1 || true)"
    enabled="$(systemctl is-enabled ollama.service 2>/dev/null || true)"
    echo "  service: system ollama.service load=${load:-unknown} active=${active:-unknown} enabled=${enabled:-unknown}"
  else
    echo "  service: systemctl unavailable"
  fi
  local ver
  ver="$(curl -fsS --connect-timeout 2 --max-time 2 "$base_url/api/version" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || true)"
  [[ -n "$ver" ]] && echo "  api:     RUNNING $base_url version=$ver" || echo "  api:     NOT READY $base_url"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null \
      | awk -F, 'NR==1{gsub(/^ +| +$/,"",$1); gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$3); gsub(/^ +| +$/,"",$4); gsub(/^ +| +$/,"",$5); printf "  gpu:     %s temp=%sC vram=%s/%sMiB util=%s%%\n",$1,$2,$3,$4,$5}'
  else
    echo "  gpu:     nvidia-smi unavailable"
  fi
}

ollama_tags_json() { local base_url="${1:-${BASE_URL:-http://127.0.0.1:11434}}"; ollama_get_json "$base_url/api/tags" 10; }

ollama_resolve_model() {
  local pattern="$1" base_url="${2:-${BASE_URL:-http://127.0.0.1:11434}}" tags names exact base matches
  tags="$(ollama_tags_json "$base_url" 2>/dev/null || true)"
  [[ -n "$tags" ]] || { printf '%s\n' "$pattern"; return 0; }
  names="$(printf '%s' "$tags" | jq -r '.models[]?.name' 2>/dev/null || true)"
  exact="$(printf '%s\n' "$names" | awk -v p="$pattern" '$0==p{print; exit}')"
  [[ -n "$exact" ]] && { printf '%s\n' "$exact"; return 0; }
  base="$(printf '%s\n' "$names" | awk -v p="$pattern" 'tolower($0) ~ "^"tolower(p)"(:|$)" {print}')"
  if [[ "$(printf '%s\n' "$base" | sed '/^$/d' | wc -l | tr -d ' ')" == "1" ]]; then printf '%s\n' "$base"; return 0; fi
  matches="$(printf '%s\n' "$names" | awk -v p="$pattern" 'index(tolower($0),tolower(p))>0{print}')"
  if [[ "$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')" == "1" ]]; then printf '%s\n' "$matches"; return 0; fi
  printf '%s\n' "$pattern"
}

ollama_show_json() {
  local model="$1" base_url="${2:-${BASE_URL:-http://127.0.0.1:11434}}" out
  jq -nc --arg model "$model" '{model:$model, verbose:false}' | curl -fsS --connect-timeout 5 --max-time 30 -H 'Content-Type: application/json' -d @- "$base_url/api/show"
}

ollama_role_from_show() {
  jq -r '
    def caps: [(.capabilities // [])[] | ascii_downcase];
    def has($x): (caps | index($x)) != null;
    def arch: ((.model_info["general.architecture"] // "") | ascii_downcase);
    def has_embedding_length: any(((.model_info // {}) | keys[]?); endswith(".embedding_length"));
    if ((has("embedding") or arch=="bert" or has_embedding_length) and ((has("completion") or has("generate") or has("chat"))|not)) then "embedding"
    elif (has("completion") or has("generate") or has("chat") or has("vision") or has("tools")) then "generate"
    else "generate" end
  ' 2>/dev/null
}

ollama_model_role() {
  local model="$1" base_url="${2:-${BASE_URL:-http://127.0.0.1:11434}}" show
  show="$(ollama_show_json "$model" "$base_url" 2>/dev/null || true)"
  [[ -n "$show" ]] && printf '%s' "$show" | ollama_role_from_show || echo "unknown"
}

ollama_model_metadata_slim() {
  local model="$1"
  jq --arg model "$model" '
    def anykey($suffix): first(((.model_info // {}) | to_entries[]? | select(.key|endswith($suffix)) | .value));
    {
      model: (.model // $model),
      capabilities: (.capabilities // []),
      details: (.details // {}),
      architecture: (.model_info["general.architecture"] // null),
      context_length: (anykey(".context_length") // null),
      embedding_length: (anykey(".embedding_length") // null),
      parameter_count: (.model_info["general.parameter_count"] // null),
      parameter_size: (.details.parameter_size // null),
      quantization_level: (.details.quantization_level // null),
      digest: (.digest // .model_info["general.file_type"] // null)
    }'
}

ollama_print_available_model_commands() {
  local base_url="${1:-${BASE_URL:-http://127.0.0.1:11434}}" cmd="${2:-ollama test}"
  local tags
  tags="$(ollama_tags_json "$base_url" 2>/dev/null || true)"
  [[ -n "$tags" ]] || { echo "No Ollama models listed."; return 0; }
  printf 'Available local Ollama models at %s:\n' "$base_url"
  printf '  %-34s %-10s %-8s %s\n' MODEL ROLE SIZE "SUGGESTED COMMAND"
  printf '  %-34s %-10s %-8s %s\n' ----- ---- ---- -----------------
  printf '%s' "$tags" | jq -r '.models[]? | [.name, (.size // 0)] | @tsv' | while IFS=$'\t' read -r name size; do
    local role size_gb
    role="$(ollama_model_role "$name" "$base_url" 2>/dev/null || echo unknown)"
    size_gb="$(awk -v s="$size" 'BEGIN{if(s>0) printf "%.1fGB", s/1000000000; else print "?"}')"
    printf '  %-34s %-10s %-8s %s %s\n' "$name" "$role" "$size_gb" "$cmd" "$name"
  done
}

ollama_capture_ollama_ps() {
  local base_url="${1:-${BASE_URL:-http://127.0.0.1:11434}}" out_json="$2" out_txt="$3"
  curl -fsS --connect-timeout 3 --max-time 5 "$base_url/api/ps" >"$out_json" 2>/dev/null || echo '{"models":[]}' >"$out_json"
  if command -v ollama >/dev/null 2>&1; then ollama ps >"$out_txt" 2>/dev/null || true; else jq -r '.models[]?.name' "$out_json" >"$out_txt" 2>/dev/null || true; fi
}

ollama_ps_model_names() { jq -r '.models[]?.name // empty' "$1" 2>/dev/null || true; }

ollama_unload_model() {
  local model="$1" role="${2:-generate}" base_url="${3:-${BASE_URL:-http://127.0.0.1:11434}}" tmpdir="${4:-/tmp}"
  mkdir -p "$tmpdir"
  if [[ "$role" == "embedding" ]]; then
    jq -nc --arg model "$model" '{model:$model,input:"",keep_alive:0}' >"$tmpdir/unload-$(ollama_sanitize_name "$model").json"
    curl -sS --connect-timeout 3 --max-time 20 -H 'Content-Type: application/json' -d @"$tmpdir/unload-$(ollama_sanitize_name "$model").json" "$base_url/api/embed" >/dev/null 2>&1 || true
  else
    jq -nc --arg model "$model" '{model:$model,prompt:"",stream:false,keep_alive:0}' >"$tmpdir/unload-$(ollama_sanitize_name "$model").json"
    curl -sS --connect-timeout 3 --max-time 20 -H 'Content-Type: application/json' -d @"$tmpdir/unload-$(ollama_sanitize_name "$model").json" "$base_url/api/generate" >/dev/null 2>&1 || true
  fi
}

ollama_unload_all_resident() {
  local base_url="${1:-${BASE_URL:-http://127.0.0.1:11434}}" run_dir="$2" ps_json names role
  mkdir -p "$run_dir"
  ps_json="$run_dir/ollama-api-ps-before-empty-card-check.json"
  ollama_capture_ollama_ps "$base_url" "$ps_json" "$run_dir/ollama-ps-before-empty-card-check.txt"
  names="$(ollama_ps_model_names "$ps_json")"
  if [[ -z "$names" ]]; then echo "none"; return 0; fi
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    role="$(ollama_model_role "$name" "$base_url" 2>/dev/null || echo generate)"
    ollama_unload_model "$name" "$role" "$base_url" "$run_dir"
  done <<< "$names"
  sleep 1
  echo "$names" | paste -sd ',' -
}

ollama_nvidia_query_one() {
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.limit,power.draw,memory.used,memory.total,utilization.gpu,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv,noheader,nounits 2>/dev/null | head -1
  fi
}

ollama_vram_pct_from_query() {
  awk -F, '{used=$6+0; total=$7+0; if(total>0) printf "%.1f", used*100/total; else printf "0"}'
}

ollama_capture_environment_summary() {
  local out="$1" run_dir="$2" model="${3:-}" base_url="${4:-${BASE_URL:-http://127.0.0.1:11434}}"
  mkdir -p "$run_dir"
  {
    echo "# Environment summary"
    echo
    echo "timestamp: $(ollama_now_iso)"
    echo "base_url: $base_url"
    echo "model: ${model:-none}"
    echo
    echo "## Ollama"
    echo "binary_path: $(command -v ollama 2>/dev/null || echo unavailable)"
    echo "cli_version: $(ollama --version 2>/dev/null | head -1 || echo unavailable)"
    echo "api_version: $(curl -fsS --connect-timeout 2 --max-time 3 "$base_url/api/version" 2>/dev/null | jq -r '.version // "unknown"' 2>/dev/null || echo unavailable)"
    if command -v systemctl >/dev/null 2>&1; then
      echo "service_fragment: $(systemctl show -p FragmentPath --value ollama.service 2>/dev/null | head -1 || true)"
      echo "service_environment: $(systemctl show -p Environment --value ollama.service 2>/dev/null | head -1 || true)"
    fi
    echo "OLLAMA_MODELS: ${OLLAMA_MODELS:-unset}"
    echo "OLLAMA_KEEP_ALIVE: ${OLLAMA_KEEP_ALIVE:-unset}"
    echo "OLLAMA_MAX_LOADED_MODELS: ${OLLAMA_MAX_LOADED_MODELS:-unset}"
    echo "OLLAMA_NUM_PARALLEL: ${OLLAMA_NUM_PARALLEL:-unset}"
    echo "OLLAMA_CONTEXT_LENGTH: ${OLLAMA_CONTEXT_LENGTH:-unset}"
    echo "OLLAMA_FLASH_ATTENTION: ${OLLAMA_FLASH_ATTENTION:-unset}"
    echo "OLLAMA_KV_CACHE_TYPE: ${OLLAMA_KV_CACHE_TYPE:-unset}"
    echo "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES:-unset}"
    echo
    echo "## Host"
    echo "uname: $(uname -a 2>/dev/null || true)"
    echo "wsl_version: $(grep -i '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"' || true)"
    echo "kernel: $(uname -r 2>/dev/null || true)"
    echo "system_ram: $(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || true)"
    echo "swap: $(free -h 2>/dev/null | awk '/Swap:/ {print $2}' || true)"
    echo "root_fs: $(df -h / 2>/dev/null | tail -1 || true)"
    if command -v findmnt >/dev/null 2>&1; then
      echo "root_mount: $(findmnt -no SOURCE,FSTYPE,OPTIONS / 2>/dev/null || true)"
      [[ -n "${OLLAMA_MODELS:-}" ]] && echo "model_mount: $(findmnt -no TARGET,SOURCE,FSTYPE,OPTIONS -T "$OLLAMA_MODELS" 2>/dev/null || true)"
    fi
    echo
    echo "## GPU"
    if command -v nvidia-smi >/dev/null 2>&1; then
      nvidia-smi --query-gpu=name,driver_version,cuda_version,persistence_mode,power.limit,memory.total,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv,noheader 2>/dev/null | head -1 || true
    else
      echo "nvidia-smi: unavailable"
    fi
    echo
    echo "## Model metadata"
    if [[ -n "$model" ]]; then
      ollama_show_json "$model" "$base_url" 2>/dev/null | tee "$run_dir/ollama-api-show-model-raw.json" | ollama_model_metadata_slim "$model" 2>/dev/null || echo "metadata unavailable"
    fi
  } >"$out"
}

ollama_parse_runner_log() {
  local log_file="$1" out="$2"
  {
    echo "# Runner/server log facts"
    echo
    echo "source: $log_file"
    echo "runner_start_s: $(grep -Eio 'runner started in [0-9.]+ seconds' "$log_file" 2>/dev/null | tail -1 | grep -Eo '[0-9.]+' | tail -1 || true)"
    echo "layers_offloaded: $(grep -Eio '[0-9]+/[0-9]+ layers? offloaded|offloaded.*[0-9]+/[0-9]+' "$log_file" 2>/dev/null | tail -1 || true)"
    echo "kv_cache_type: $(grep -Ei 'KvCacheType|KV cache type|kv cache' "$log_file" 2>/dev/null | tail -5 | sed 's/^/- /' || true)"
    echo "memory_facts:"
    grep -Ei 'model weights|kv cache|compute graph|total memory|required memory|layers|offload' "$log_file" 2>/dev/null | tail -20 | sed 's/^/- /' || true
  } >"$out"
}

ollama_make_perf_settings() {
  local out="$1" model="$2" ctx="$3" keep_alive="$4" max_loaded="$5" num_parallel="$6" flash="$7" kv="$8" rationale="$9"
  cat >"$out" <<EOF_SETTINGS
#!/usr/bin/env bash
# Performance-tuned Ollama systemd override for WSL2 / Linux.
# Generated by ollama-info v1.12 for model: $model
# Rationale: $rationale
set -euo pipefail
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF_OVERRIDE'
[Service]
Environment="OLLAMA_KEEP_ALIVE=$keep_alive"
Environment="OLLAMA_MAX_LOADED_MODELS=$max_loaded"
Environment="OLLAMA_NUM_PARALLEL=$num_parallel"
Environment="OLLAMA_FLASH_ATTENTION=$flash"
Environment="OLLAMA_CONTEXT_LENGTH=$ctx"
Environment="OLLAMA_KV_CACHE_TYPE=$kv"
EOF_OVERRIDE
sudo systemctl daemon-reload
sudo systemctl restart ollama.service
ollama ps
EOF_SETTINGS
  chmod +x "$out"
}
