#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/ollama-common.sh"
VERSION="1.12.0"
SCRIPT_SIGNATURE="OLLAMA_TEST_AND_MONITOR_RTX3090_SCRIPT_SIGNATURE=v1.12-summary-context-hermes-usecase"
BASE_URL="${BASE_URL:-${OLLAMA_URL:-http://127.0.0.1:11434}}"
OUT_DIR="${OUT_DIR:-$HOME/log/ollama-test-and-monitor-RTX3090}"
TMP_DIR="${TMP_DIR:-$HOME/tmp}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
MODEL_PATTERN=""
ZIP_ON_EXIT=1
ROUTE_ONLY=0
PASS_ARGS=()
usage(){ cat <<EOF_USAGE
ollama-test-and-monitor-RTX3090.sh v$VERSION
Run model diagnostic plus RTX 3090 boundary snapshots and one combined ZIP.
Usage: ollama-test-and-monitor-RTX3090.sh MODEL [test options]
EOF_USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_PATTERN="$(ollama_require_arg_value "$1" "${2-}")"; PASS_ARGS+=("$1" "$2"); shift 2;;
    --base-url) BASE_URL="$(ollama_require_arg_value "$1" "${2-}")"; PASS_ARGS+=("$1" "$2"); shift 2;;
    --out-dir) OUT_DIR="$(ollama_require_arg_value "$1" "${2-}")"; shift 2;;
    --run-id) RUN_ID="$(ollama_require_arg_value "$1" "${2-}")"; shift 2;;
    --route-only|--dry-run) ROUTE_ONLY=1; PASS_ARGS+=("$1"); shift;;
    --zip) ZIP_ON_EXIT=1; shift;;
    --no-zip) ZIP_ON_EXIT=0; shift;;
    -h|--help) usage; exit 0;;
    --*) PASS_ARGS+=("$1"); if [[ $# -ge 2 && "$2" != --* ]]; then PASS_ARGS+=("$2"); shift 2; else shift; fi;;
    *) if [[ -z "$MODEL_PATTERN" ]]; then MODEL_PATTERN="$1"; PASS_ARGS+=("$1"); else PASS_ARGS+=("$1"); fi; shift;;
  esac
done
[[ -n "$MODEL_PATTERN" ]] || { usage; echo; ollama_print_available_model_commands "$BASE_URL" "ollama test"; exit 0; }
MODEL="$(ollama_resolve_model "$MODEL_PATTERN" "$BASE_URL")"
ROLE="$(ollama_model_role "$MODEL" "$BASE_URL" 2>/dev/null || echo unknown)"
if [[ "$ROUTE_ONLY" -eq 1 ]]; then echo "model=$MODEL role=$ROLE route=ollama-test-and-monitor"; exit 0; fi
MODEL_SAFE="$(ollama_sanitize_name "$MODEL")"
RUN_DIR="$OUT_DIR/run-$RUN_ID"
HW_DIR="$RUN_DIR/hardware"
mkdir -p "$RUN_DIR" "$HW_DIR" "$TMP_DIR"
ollama_log "ollama-test-and-monitor-RTX3090.sh v$VERSION"
ollama_log "$SCRIPT_SIGNATURE"
ollama_log "Run dir: $RUN_DIR"
ollama_log "Plan: requested_model=$MODEL_PATTERN resolved_model=$MODEL role=$ROLE"
ollama_status_short_common "$BASE_URL" | ollama_timestamp_stream || true
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi >"$HW_DIR/nvidia-smi-start.txt" 2>/dev/null || true
  nvidia-smi -q >"$HW_DIR/nvidia-smi-q-start.txt" 2>/dev/null || true
  nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv,noheader,nounits >"$HW_DIR/nvidia-smi-query-start.csv" 2>/dev/null || true
fi
TEST_RUN_ID="$RUN_ID-test"
TEST_OUT_DIR="$RUN_DIR/test"
mkdir -p "$TEST_OUT_DIR"
set +e
RUN_ID="$TEST_RUN_ID" OUT_DIR="$TEST_OUT_DIR" BASE_URL="$BASE_URL" TMP_DIR="$TMP_DIR" "$SCRIPT_DIR/ollama-test-RTX3090.sh" "${PASS_ARGS[@]}" --no-zip >"$RUN_DIR/test.console.log" 2>&1
TEST_EXIT=$?
set -e
cat "$RUN_DIR/test.console.log"
TEST_DIR="$TEST_OUT_DIR/run-$TEST_RUN_ID"
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi >"$HW_DIR/nvidia-smi-end.txt" 2>/dev/null || true
  nvidia-smi -q >"$HW_DIR/nvidia-smi-q-end.txt" 2>/dev/null || true
  nvidia-smi --query-gpu=name,driver_version,temperature.gpu,power.draw,power.limit,memory.used,memory.total,utilization.gpu,pcie.link.gen.current,pcie.link.width.current,pcie.link.width.max --format=csv,noheader,nounits >"$HW_DIR/nvidia-smi-query-end.csv" 2>/dev/null || true
fi
# Copy main decision artifacts to top-level for easier review.
for f in summary.md terminal-summary.txt model-scorecard.csv recommendations.md recommended-ollama-env.conf performance-settings.md performance-settings.sh environment-summary.md runner-log-facts.md capability-analysis.md context-summary.csv context-summary.md hermes-compatibility.md; do
  [[ -f "$TEST_DIR/$f" ]] && cp -f "$TEST_DIR/$f" "$RUN_DIR/$f"
done
cat >"$RUN_DIR/orchestrator-summary.md" <<EOF_SUM
# RTX 3090 Ollama Test + Monitor Summary

- script_version: $VERSION
- signature: $SCRIPT_SIGNATURE
- run_id: $RUN_ID
- requested_model: $MODEL_PATTERN
- resolved_model: $MODEL
- role: $ROLE
- base_url: $BASE_URL
- test_exit_code: $TEST_EXIT

Main artifacts:
- terminal summary: terminal-summary.txt
- model scorecard: model-scorecard.csv
- recommendations: recommendations.md
- applyable settings: performance-settings.sh
- settings rationale: performance-settings.md
- environment facts: environment-summary.md
- runner/server facts: runner-log-facts.md
- raw test folder: test/run-$TEST_RUN_ID
- hardware snapshots: hardware/
EOF_SUM
if [[ "$ZIP_ON_EXIT" -eq 1 ]]; then
  ARCHIVE_PATH="$TMP_DIR/ollama-test-and-monitor-RTX3090-${MODEL_SAFE}-${RUN_ID}.zip"
  (cd "$(dirname "$RUN_DIR")" && zip -qr "$ARCHIVE_PATH" "$(basename "$RUN_DIR")")
  echo "$ARCHIVE_PATH" >"$RUN_DIR/archive.path"
  ollama_log "zip: $ARCHIVE_PATH"
fi
exit "$TEST_EXIT"
