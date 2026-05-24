#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="0.8.0"
SCRIPT_SIGNATURE="OLLAMA_DOWNLOAD_SCRIPT_SIGNATURE=v0.8.0-resumable-gguf-import"

METHOD="${METHOD:-auto}"
REPO_ID="${REPO_ID:-}"
GGUF_FILE="${GGUF_FILE:-}"
REVISION="${REVISION:-main}"
URL="${URL:-}"
LOCAL_FILE="${LOCAL_FILE:-}"
MODEL_NAME="${MODEL_NAME:-}"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://localhost:11434}}"
BASE_OUT_DIR="${BASE_OUT_DIR:-$HOME/models/gguf}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-}"
LOG_ROOT="${LOG_ROOT:-$HOME/log/ollama-download}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RETRY_WAIT="${RETRY_WAIT:-30}"
MAX_TRIES="${MAX_TRIES:-0}"
TIMEOUT_SEC="${TIMEOUT_SEC:-60}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-30}"
SPLIT="${SPLIT:-4}"
CONNECTIONS="${CONNECTIONS:-4}"
MIN_SPLIT_SIZE="${MIN_SPLIT_SIZE:-64M}"
SUMMARY_INTERVAL="${SUMMARY_INTERVAL:-30}"
CHECKSUM_SHA256="${CHECKSUM_SHA256:-}"
CREATE_MODE="${CREATE_MODE:-auto}"
ENSURE_SERVER="${ENSURE_SERVER:-1}"
DISABLE_XET="${DISABLE_XET:-1}"
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
PRINT_PATH="${PRINT_PATH:-0}"
MODFILE="${MODFILE:-}"

RUN_DIR="$LOG_ROOT/run-$RUN_ID"
ERRORS_FILE="$RUN_DIR/errors.log"
SUMMARY_FILE="$RUN_DIR/summary.txt"
META_FILE="$RUN_DIR/meta.txt"
DOWNLOAD_LOG="$RUN_DIR/download.log"
SHA256_FILE="$RUN_DIR/sha256.txt"
ARIA2_INPUT_FILE=""
CURL_CONFIG_FILE=""

PARAMS=()

usage() {
  cat <<EOF_USAGE
ollama-download.sh v$VERSION
$SCRIPT_SIGNATURE

Resumable GGUF downloader/importer for WSL2 + Ollama.

Primary workflow:
  download GGUF with resume/retry -> verify local file -> generate Modelfile -> ollama create

Usage:
  ./ollama-download.sh --repo REPO_ID --file FILE.gguf --name LOCAL_MODEL [options]
  ./ollama-download.sh --url URL --file FILE.gguf --name LOCAL_MODEL [options]
  ./ollama-download.sh --local-file /path/model.gguf --name LOCAL_MODEL [options]

Examples:
  # Public Hugging Face GGUF, explicit aria2 resume semantics
  ./ollama-download.sh \\
    --method aria2 \\
    --repo bartowski/Qwen3-32B-GGUF \\
    --file Qwen3-32B-Q4_K_M.gguf \\
    --name qwen3-32b-q4km \\
    --num-ctx 8192

  # Hugging Face CLI path; good for gated/private repos after: hf auth login
  ./ollama-download.sh \\
    --method hf \\
    --repo org/private-model-GGUF \\
    --file model-Q4_K_M.gguf \\
    --name private-model-q4km

  # Download only, no Ollama import
  ./ollama-download.sh --repo REPO_ID --file FILE.gguf --no-create

Source options:
  --repo ID               Hugging Face repo id, e.g. bartowski/Qwen3-32B-GGUF
  --file PATH             GGUF file path inside repo, or output filename for --url
  --revision REV          Hugging Face revision/branch/commit (default: $REVISION)
  --url URL               Direct download URL; supports resumable aria2/curl paths
  --local-file PATH       Skip download and import an existing local GGUF

Download options:
  --method NAME           auto|hf|aria2|curl (default: $METHOD)
  --out-dir DIR           Directory for the local GGUF file
  --base-out-dir DIR      Base dir when --out-dir is omitted (default: $BASE_OUT_DIR)
  --retry-wait SEC        Wait before retrying failed attempts (default: $RETRY_WAIT)
  --max-tries N           Attempts per transfer command; 0 means retry forever (default: $MAX_TRIES)
  --timeout-sec N         Network idle timeout / HF timeout seconds (default: $TIMEOUT_SEC)
  --connect-timeout-sec N Connect timeout seconds (default: $CONNECT_TIMEOUT_SEC)
  --split N               aria2 split count (default: $SPLIT)
  --connections N         aria2 max connections per server (default: $CONNECTIONS)
  --min-split-size SIZE   aria2 min split size (default: $MIN_SPLIT_SIZE)
  --sha256 HEX            Expected SHA256; fail if actual hash differs
  --force                 Remove existing destination file and .aria2 state before download

Ollama import options:
  --name NAME             Ollama model name to create. If omitted, script downloads only.
  --create                Force ollama create; requires --name
  --no-create             Download/verify only
  --base-url URL          Ollama API URL for readiness checks (default: $BASE_URL)
  --ensure-server         Start/check Ollama before create (default)
  --no-ensure-server      Do not start/check Ollama before create
  --modelfile PATH        Modelfile path to write/use (default: run log dir)
  --param KEY=VALUE       Add raw PARAMETER line to generated Modelfile; repeatable
  --num-ctx N             Shortcut for --param num_ctx=N

Operational options:
  --log-root DIR          Run log root (default: $LOG_ROOT)
  --run-id ID             Override run id (default: timestamp)
  --dry-run               Print plan only
  --print-path            Also print final GGUF path on success
  -h, --help              Show help

Auth:
  For private/gated Hugging Face repos, prefer: hf auth login
  aria2/curl modes also read HF_TOKEN or HUGGING_FACE_HUB_TOKEN without putting it in argv.

Exit codes:
  0 success; 2 usage; 3 missing dependency; 4 download failed; 5 verification failed; 6 ollama create failed
EOF_USAGE
}

log() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; printf '%s WARN: %s\n' "$(date -Is)" "$*" >>"$ERRORS_FILE" 2>/dev/null || true; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || { printf 'ERROR: missing command: %s\n' "$1" >&2; exit 3; }; }
is_uint() { [[ "${1:-}" =~ ^[0-9]+$ ]]; }
script_dir() { cd -- "$(dirname -- "$(realpath "${BASH_SOURCE[0]}")")" && pwd; }

cleanup() {
  [[ -n "$ARIA2_INPUT_FILE" && -f "$ARIA2_INPUT_FILE" ]] && rm -f -- "$ARIA2_INPUT_FILE"
  [[ -n "$CURL_CONFIG_FILE" && -f "$CURL_CONFIG_FILE" ]] && rm -f -- "$CURL_CONFIG_FILE"
  return 0
}
trap cleanup EXIT

sanitize_name() {
  local s="$1"
  s="${s//\//__}"
  s="${s//:/_}"
  s="${s// /_}"
  printf '%s' "$s"
}

file_basename_from_url() {
  local no_query path
  no_query="${1%%\?*}"
  path="${no_query%/}"
  basename -- "$path"
}

human_size() {
  local path="$1"
  if command -v numfmt >/dev/null 2>&1; then
    stat -c '%s' "$path" | numfmt --to=iec-i --suffix=B
  else
    stat -c '%s bytes' "$path"
  fi
}

abs_path() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath -- "$p"
  else
    case "$p" in /*) printf '%s\n' "$p" ;; *) printf '%s/%s\n' "$(pwd)" "$p" ;; esac
  fi
}

build_hf_url() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$REPO_ID" "$REVISION" "$GGUF_FILE" <<'PY'
import sys
from urllib.parse import quote
repo, rev, path = sys.argv[1], sys.argv[2], sys.argv[3]
repo_q = "/".join(quote(part, safe="") for part in repo.split("/"))
path_q = "/".join(quote(part, safe="") for part in path.split("/"))
print(f"https://huggingface.co/{repo_q}/resolve/{quote(rev, safe='')}/{path_q}?download=true")
PY
  else
    printf 'https://huggingface.co/%s/resolve/%s/%s?download=true\n' "$REPO_ID" "$REVISION" "$GGUF_FILE"
  fi
}

run_with_retries() {
  local attempt=1 rc=0
  while true; do
    if "$@"; then
      return 0
    fi
    rc=$?
    if [[ "$MAX_TRIES" != "0" && "$attempt" -ge "$MAX_TRIES" ]]; then
      return "$rc"
    fi
    warn "attempt $attempt failed with rc=$rc; retrying in $RETRY_WAIT seconds"
    sleep "$RETRY_WAIT"
    attempt=$((attempt + 1))
  done
}

find_hf_cli() {
  if command -v hf >/dev/null 2>&1; then
    printf 'hf\n'
  elif command -v huggingface-cli >/dev/null 2>&1; then
    printf 'huggingface-cli\n'
  else
    return 1
  fi
}

ensure_ollama_server() {
  [[ "$ENSURE_SERVER" == "1" ]] || return 0
  need_cmd curl
  if curl -fsS --connect-timeout 5 "$BASE_URL/api/tags" >/dev/null 2>&1; then
    return 0
  fi

  local sd start_script
  sd="$(script_dir)"
  start_script="$sd/ollama-start"
  if [[ -x "$start_script" ]]; then
    BASE_URL="$BASE_URL" "$start_script" >/dev/null || true
  elif command -v ollama >/dev/null 2>&1; then
    mkdir -p "$HOME/log"
    nohup ollama serve >"$HOME/log/ollama-serve.log" 2>&1 &
    sleep 3
  fi

  curl -fsS --connect-timeout 5 "$BASE_URL/api/tags" >/dev/null 2>&1 || {
    printf 'ERROR: Ollama server is not reachable at %s\n' "$BASE_URL" >&2
    exit 6
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) REPO_ID="${2:-}"; shift 2 ;;
      --file) GGUF_FILE="${2:-}"; shift 2 ;;
      --revision) REVISION="${2:-}"; shift 2 ;;
      --url) URL="${2:-}"; shift 2 ;;
      --local-file) LOCAL_FILE="${2:-}"; shift 2 ;;
      --method) METHOD="${2:-}"; shift 2 ;;
      --out-dir) DOWNLOAD_DIR="${2:-}"; shift 2 ;;
      --base-out-dir) BASE_OUT_DIR="${2:-}"; shift 2 ;;
      --retry-wait) RETRY_WAIT="${2:-}"; shift 2 ;;
      --max-tries) MAX_TRIES="${2:-}"; shift 2 ;;
      --timeout-sec) TIMEOUT_SEC="${2:-}"; shift 2 ;;
      --connect-timeout-sec) CONNECT_TIMEOUT_SEC="${2:-}"; shift 2 ;;
      --split) SPLIT="${2:-}"; shift 2 ;;
      --connections) CONNECTIONS="${2:-}"; shift 2 ;;
      --min-split-size) MIN_SPLIT_SIZE="${2:-}"; shift 2 ;;
      --sha256) CHECKSUM_SHA256="${2:-}"; shift 2 ;;
      --force) FORCE=1; shift ;;
      --name) MODEL_NAME="${2:-}"; shift 2 ;;
      --create) CREATE_MODE=1; shift ;;
      --no-create) CREATE_MODE=0; shift ;;
      --base-url) BASE_URL="${2:-}"; shift 2 ;;
      --ensure-server) ENSURE_SERVER=1; shift ;;
      --no-ensure-server) ENSURE_SERVER=0; shift ;;
      --modelfile) MODFILE="${2:-}"; shift 2 ;;
      --param) PARAMS+=("${2:-}"); shift 2 ;;
      --num-ctx) PARAMS+=("num_ctx=${2:-}"); shift 2 ;;
      --log-root) LOG_ROOT="${2:-}"; RUN_DIR="$LOG_ROOT/run-$RUN_ID"; ERRORS_FILE="$RUN_DIR/errors.log"; SUMMARY_FILE="$RUN_DIR/summary.txt"; META_FILE="$RUN_DIR/meta.txt"; DOWNLOAD_LOG="$RUN_DIR/download.log"; SHA256_FILE="$RUN_DIR/sha256.txt"; shift 2 ;;
      --run-id) RUN_ID="${2:-}"; RUN_DIR="$LOG_ROOT/run-$RUN_ID"; ERRORS_FILE="$RUN_DIR/errors.log"; SUMMARY_FILE="$RUN_DIR/summary.txt"; META_FILE="$RUN_DIR/meta.txt"; DOWNLOAD_LOG="$RUN_DIR/download.log"; SHA256_FILE="$RUN_DIR/sha256.txt"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      --print-path) PRINT_PATH=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
  done
}

validate_args() {
  case "$METHOD" in auto|hf|aria2|curl) ;; *) printf 'ERROR: --method must be auto, hf, aria2, or curl\n' >&2; exit 2 ;; esac
  is_uint "$RETRY_WAIT" || { printf 'ERROR: --retry-wait must be an integer\n' >&2; exit 2; }
  is_uint "$MAX_TRIES" || { printf 'ERROR: --max-tries must be an integer\n' >&2; exit 2; }
  is_uint "$TIMEOUT_SEC" || { printf 'ERROR: --timeout-sec must be an integer\n' >&2; exit 2; }
  is_uint "$CONNECT_TIMEOUT_SEC" || { printf 'ERROR: --connect-timeout-sec must be an integer\n' >&2; exit 2; }
  is_uint "$SPLIT" || { printf 'ERROR: --split must be an integer\n' >&2; exit 2; }
  is_uint "$CONNECTIONS" || { printf 'ERROR: --connections must be an integer\n' >&2; exit 2; }
  [[ "$RETRY_WAIT" -ge 0 ]] || { printf 'ERROR: --retry-wait must be >= 0\n' >&2; exit 2; }
  [[ "$TIMEOUT_SEC" -ge 1 ]] || { printf 'ERROR: --timeout-sec must be >= 1\n' >&2; exit 2; }
  [[ "$CONNECT_TIMEOUT_SEC" -ge 1 ]] || { printf 'ERROR: --connect-timeout-sec must be >= 1\n' >&2; exit 2; }
  [[ "$SPLIT" -ge 1 ]] || SPLIT=1
  [[ "$CONNECTIONS" -ge 1 ]] || CONNECTIONS=1

  if [[ -n "$LOCAL_FILE" ]]; then
    [[ -f "$LOCAL_FILE" ]] || { printf 'ERROR: --local-file does not exist: %s\n' "$LOCAL_FILE" >&2; exit 2; }
  elif [[ -n "$URL" ]]; then
    [[ -n "$GGUF_FILE" ]] || GGUF_FILE="$(file_basename_from_url "$URL")"
    [[ -n "$GGUF_FILE" && "$GGUF_FILE" != "." ]] || { printf 'ERROR: cannot infer filename from --url; pass --file FILE.gguf\n' >&2; exit 2; }
  else
    [[ -n "$REPO_ID" ]] || { printf 'ERROR: pass --repo REPO_ID or --url URL or --local-file PATH\n' >&2; exit 2; }
    [[ -n "$GGUF_FILE" ]] || { printf 'ERROR: pass --file FILE.gguf\n' >&2; exit 2; }
  fi

  if [[ "$CREATE_MODE" == "1" && -z "$MODEL_NAME" ]]; then
    printf 'ERROR: --create requires --name MODEL_NAME\n' >&2
    exit 2
  fi

  for p in "${PARAMS[@]}"; do
    [[ "$p" == *=* ]] || { printf 'ERROR: --param must use KEY=VALUE syntax: %s\n' "$p" >&2; exit 2; }
    local key="${p%%=*}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { printf 'ERROR: invalid PARAMETER key: %s\n' "$key" >&2; exit 2; }
  done
}

resolve_download_dir() {
  if [[ -n "$DOWNLOAD_DIR" ]]; then
    printf '%s\n' "$DOWNLOAD_DIR"
    return 0
  fi
  if [[ -n "$REPO_ID" ]]; then
    printf '%s/%s\n' "$BASE_OUT_DIR" "$(sanitize_name "$REPO_ID")"
  else
    printf '%s/direct\n' "$BASE_OUT_DIR"
  fi
}

final_file_path() {
  local dir="$1"
  if [[ -n "$LOCAL_FILE" ]]; then
    abs_path "$LOCAL_FILE"
  else
    printf '%s/%s\n' "$dir" "$GGUF_FILE"
  fi
}

should_create_model() {
  if [[ "$CREATE_MODE" == "1" ]]; then return 0; fi
  if [[ "$CREATE_MODE" == "0" ]]; then return 1; fi
  [[ -n "$MODEL_NAME" ]]
}

download_hf() {
  local dest_dir="$1" hf_cli
  hf_cli="$(find_hf_cli)" || { printf 'ERROR: missing hf CLI. Install with: python3 -m pip install -U huggingface_hub\n' >&2; exit 3; }
  mkdir -p "$dest_dir"
  export HF_HUB_DOWNLOAD_TIMEOUT="$TIMEOUT_SEC"
  if [[ "$DISABLE_XET" == "1" ]]; then export HF_HUB_DISABLE_XET=1; fi

  log "download method: hf CLI ($hf_cli)"
  log "destination: $dest_dir"
  run_with_retries "$hf_cli" download "$REPO_ID" "$GGUF_FILE" --revision "$REVISION" --local-dir "$dest_dir"
}

download_aria2() {
  local dest_dir="$1" download_url out_dir out_name token
  need_cmd aria2c
  if [[ -n "$URL" ]]; then download_url="$URL"; else download_url="$(build_hf_url)"; fi

  out_dir="$dest_dir"
  out_name="$GGUF_FILE"
  if [[ "$GGUF_FILE" == */* ]]; then
    out_dir="$dest_dir/$(dirname -- "$GGUF_FILE")"
    out_name="$(basename -- "$GGUF_FILE")"
  fi
  mkdir -p "$out_dir"

  ARIA2_INPUT_FILE="$(mktemp "$RUN_DIR/aria2-input.XXXXXX")"
  chmod 600 "$ARIA2_INPUT_FILE"
  {
    printf '%s\n' "$download_url"
    printf '  dir=%s\n' "$out_dir"
    printf '  out=%s\n' "$out_name"
    token="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
    if [[ -n "$token" ]]; then
      printf '  header=Authorization: Bearer %s\n' "$token"
    fi
  } >"$ARIA2_INPUT_FILE"

  log "download method: aria2c"
  log "destination: $out_dir/$out_name"
  run_with_retries aria2c \
    --input-file="$ARIA2_INPUT_FILE" \
    --continue=true \
    --auto-file-renaming=false \
    --allow-overwrite=false \
    --max-tries="$MAX_TRIES" \
    --retry-wait="$RETRY_WAIT" \
    --timeout="$TIMEOUT_SEC" \
    --connect-timeout="$CONNECT_TIMEOUT_SEC" \
    --max-connection-per-server="$CONNECTIONS" \
    --split="$SPLIT" \
    --min-split-size="$MIN_SPLIT_SIZE" \
    --summary-interval="$SUMMARY_INTERVAL" \
    --file-allocation=none \
    --check-certificate=true
}

download_curl() {
  local dest_dir="$1" download_url out_dir out_name token
  need_cmd curl
  if [[ -n "$URL" ]]; then download_url="$URL"; else download_url="$(build_hf_url)"; fi

  out_dir="$dest_dir"
  out_name="$GGUF_FILE"
  if [[ "$GGUF_FILE" == */* ]]; then
    out_dir="$dest_dir/$(dirname -- "$GGUF_FILE")"
    out_name="$(basename -- "$GGUF_FILE")"
  fi
  mkdir -p "$out_dir"

  CURL_CONFIG_FILE="$(mktemp "$RUN_DIR/curl-config.XXXXXX")"
  chmod 600 "$CURL_CONFIG_FILE"
  {
    printf 'url = "%s"\n' "$download_url"
    printf 'output = "%s"\n' "$out_dir/$out_name"
    printf 'location\nfail\ncontinue-at = -\n'
    printf 'connect-timeout = %s\n' "$CONNECT_TIMEOUT_SEC"
    printf 'speed-limit = 1\nspeed-time = %s\n' "$TIMEOUT_SEC"
    token="${HF_TOKEN:-${HUGGING_FACE_HUB_TOKEN:-}}"
    if [[ -n "$token" ]]; then
      printf 'header = "Authorization: Bearer %s"\n' "$token"
    fi
  } >"$CURL_CONFIG_FILE"

  log "download method: curl"
  log "destination: $out_dir/$out_name"
  run_with_retries curl --config "$CURL_CONFIG_FILE"
}

choose_auto_method() {
  if [[ -n "$LOCAL_FILE" ]]; then printf 'local\n'; return 0; fi
  if [[ -n "$REPO_ID" && -n "$GGUF_FILE" ]] && find_hf_cli >/dev/null 2>&1; then printf 'hf\n'; return 0; fi
  if command -v aria2c >/dev/null 2>&1; then printf 'aria2\n'; return 0; fi
  if command -v curl >/dev/null 2>&1; then printf 'curl\n'; return 0; fi
  return 1
}

remove_existing_if_forced() {
  local f="$1"
  [[ "$FORCE" == "1" ]] || return 0
  [[ -n "$LOCAL_FILE" ]] && return 0
  rm -f -- "$f" "$f.aria2"
}

verify_file() {
  local f="$1" actual expected prefix
  [[ -f "$f" ]] || { printf 'ERROR: expected file not found: %s\n' "$f" >&2; exit 5; }
  [[ -s "$f" ]] || { printf 'ERROR: file is empty: %s\n' "$f" >&2; exit 5; }

  prefix="$(head -c 4 "$f" 2>/dev/null || true)"
  if [[ "$prefix" != "GGUF" ]]; then
    warn "file does not start with GGUF magic bytes; verify that this is a real .gguf model: $f"
  fi

  if [[ -n "$CHECKSUM_SHA256" ]]; then
    need_cmd sha256sum
    actual="$(sha256sum "$f" | awk '{print tolower($1)}')"
    expected="$(printf '%s' "$CHECKSUM_SHA256" | tr '[:upper:]' '[:lower:]')"
    if [[ "$actual" != "$expected" ]]; then
      printf 'ERROR: SHA256 mismatch\nexpected: %s\nactual:   %s\nfile:     %s\n' "$expected" "$actual" "$f" >&2
      exit 5
    fi
    printf '%s  %s\n' "$actual" "$f" >"$SHA256_FILE"
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" >"$SHA256_FILE"
  fi
}

write_modelfile() {
  local gguf_path="$1" modfile="$2" p key value
  mkdir -p "$(dirname -- "$modfile")"
  {
    printf 'FROM %s\n' "$gguf_path"
    for p in "${PARAMS[@]}"; do
      key="${p%%=*}"
      value="${p#*=}"
      printf 'PARAMETER %s %s\n' "$key" "$value"
    done
  } >"$modfile"
}

create_ollama_model() {
  local gguf_path="$1" model="$2" modfile="$3"
  need_cmd ollama
  ensure_ollama_server
  write_modelfile "$gguf_path" "$modfile"
  log "ollama create: $model"
  if ! ollama create "$model" -f "$modfile"; then
    printf 'ERROR: ollama create failed for model: %s\n' "$model" >&2
    exit 6
  fi
  ollama show "$model" >/dev/null 2>&1 || warn "ollama show did not confirm model metadata for $model"
}

write_meta() {
  local dest_dir="$1" method_used="$2" final_file="$3" create_flag="$4"
  {
    printf 'ollama-download.sh v%s\n' "$VERSION"
    printf '%s\n' "$SCRIPT_SIGNATURE"
    printf 'generated_at=%s\n' "$(date -Is)"
    printf 'method=%s\n' "$method_used"
    printf 'repo_id=%s\n' "$REPO_ID"
    printf 'file=%s\n' "$GGUF_FILE"
    printf 'revision=%s\n' "$REVISION"
    printf 'url=%s\n' "${URL:+<provided>}"
    printf 'local_file=%s\n' "$LOCAL_FILE"
    printf 'download_dir=%s\n' "$dest_dir"
    printf 'final_file=%s\n' "$final_file"
    printf 'model_name=%s\n' "$MODEL_NAME"
    printf 'create=%s\n' "$create_flag"
    printf 'base_url=%s\n' "$BASE_URL"
    printf 'retry_wait=%s\n' "$RETRY_WAIT"
    printf 'max_tries=%s\n' "$MAX_TRIES"
    printf 'timeout_sec=%s\n' "$TIMEOUT_SEC"
    printf 'connect_timeout_sec=%s\n' "$CONNECT_TIMEOUT_SEC"
    printf 'split=%s\n' "$SPLIT"
    printf 'connections=%s\n' "$CONNECTIONS"
  } >"$META_FILE"
}

print_summary() {
  local final_file="$1" model_created="$2" modfile="$3"
  {
    printf 'ollama-download.sh v%s complete\n' "$VERSION"
    printf 'file: %s\n' "$final_file"
    printf 'size: %s\n' "$(human_size "$final_file")"
    if [[ -f "$SHA256_FILE" ]]; then
      printf 'sha256: %s\n' "$(awk '{print $1; exit}' "$SHA256_FILE")"
    fi
    if [[ "$model_created" == "1" ]]; then
      printf 'ollama_model: %s\n' "$MODEL_NAME"
      printf 'modelfile: %s\n' "$modfile"
    else
      printf 'ollama_model: not created\n'
    fi
    printf 'log_dir: %s\n' "$RUN_DIR"
  } | tee "$SUMMARY_FILE"
}

main() {
  parse_args "$@"
  validate_args
  mkdir -p "$RUN_DIR" "$TMP_DIR"
  : >"$ERRORS_FILE"
  : >"$DOWNLOAD_LOG"

  local dest_dir final_file method_used create_flag modfile model_created
  dest_dir="$(resolve_download_dir)"
  final_file="$(final_file_path "$dest_dir")"
  method_used="$METHOD"
  if [[ "$METHOD" == "auto" ]]; then
    method_used="$(choose_auto_method)" || { printf 'ERROR: no downloader available; install huggingface_hub, aria2, or curl\n' >&2; exit 3; }
  fi

  create_flag=0
  if should_create_model; then create_flag=1; fi

  if [[ "$DRY_RUN" == "1" ]]; then
    write_meta "$dest_dir" "$method_used" "$final_file" "$create_flag"
    log "dry_run: true"
    log "method: $method_used"
    log "destination: $final_file"
    log "create: $create_flag"
    [[ "$create_flag" == "1" ]] && log "model: $MODEL_NAME"
    exit 0
  fi

  remove_existing_if_forced "$final_file"

  case "$method_used" in
    local) log "download method: local-file; skipping download" ;;
    hf) download_hf "$dest_dir" 2>&1 | tee -a "$DOWNLOAD_LOG" ;;
    aria2) download_aria2 "$dest_dir" 2>&1 | tee -a "$DOWNLOAD_LOG" ;;
    curl) download_curl "$dest_dir" 2>&1 | tee -a "$DOWNLOAD_LOG" ;;
    *) printf 'ERROR: internal invalid method: %s\n' "$method_used" >&2; exit 2 ;;
  esac || { printf 'ERROR: download failed\n' >&2; exit 4; }

  final_file="$(final_file_path "$dest_dir")"
  final_file="$(abs_path "$final_file")"
  verify_file "$final_file"

  model_created=0
  modfile=""
  if [[ "$create_flag" == "1" ]]; then
    if [[ -z "$MODFILE" ]]; then
      modfile="$RUN_DIR/Modelfile.$(sanitize_name "$MODEL_NAME")"
    else
      modfile="$MODFILE"
    fi
    create_ollama_model "$final_file" "$MODEL_NAME" "$modfile"
    model_created=1
  fi

  write_meta "$dest_dir" "$method_used" "$final_file" "$create_flag"
  print_summary "$final_file" "$model_created" "$modfile"
  if [[ "$PRINT_PATH" == "1" ]]; then printf '%s\n' "$final_file"; fi
}

main "$@"
