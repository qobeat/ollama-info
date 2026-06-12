#!/usr/bin/env python3
"""Summarize ollama-info generation diagnostics.

Final v1.11 policy:
- fail closed when all real generation rows fail;
- never rank models or mark settings as tested when required evidence is absent;
- separate preload/residency evidence from generation/context evidence;
- emit root API errors prominently.
"""
import argparse, csv, json, re, statistics, subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--run-dir', required=True)
p.add_argument('--model', required=True)
p.add_argument('--role', default='generate')
p.add_argument('--base-url', default='http://127.0.0.1:11434')
p.add_argument('--profile', default='ados')
p.add_argument('--mode', default='diagnostic')
p.add_argument('--ctx', default='4096')
p.add_argument('--keep-alive', default='24h')
args = p.parse_args()
rd = Path(args.run_dir)
summary_csv = rd / 'summary.csv'
rows = []
if summary_csv.exists():
    with summary_csv.open(newline='', encoding='utf-8') as f:
        rows = list(csv.DictReader(f))

def fnum(v, default=None):
    try:
        if v in (None, '', 'None', 'N/A', 'NA'):
            return default
        return float(v)
    except Exception:
        return default

def inum(v, default=0):
    try:
        return int(float(v))
    except Exception:
        return default

def mean(vals):
    vals = [v for v in vals if v is not None]
    return statistics.mean(vals) if vals else None

def fmt(v, nd=1, suffix=''):
    if v is None:
        return 'N/A'
    return f'{v:.{nd}f}{suffix}'

def read_text(path):
    try:
        return Path(path).read_text(encoding='utf-8', errors='ignore')
    except Exception:
        return ''

# Evidence partitions.
# Final v1.11 gates deliberately separate capability throughput from context-pressure proof.
# Context rows are never allowed to inflate visible_tps_avg, and one-token context rows
# cannot validate 8K/16K settings.
MIN_CONTEXT_EVAL_TOKENS = 128
MIN_CONTEXT_RESPONSE_CHARS = 120
non_skipped = [r for r in rows if r.get('result_state') != 'SKIPPED']
api_error_rows = [r for r in rows if r.get('result_state') == 'FAIL' or fnum(r.get('http'), 0) >= 400]
ok_rows = [r for r in rows if r.get('result_state') == 'PASS' and r.get('sample_status') == 'OK']

def is_context_row(r):
    return r.get('mode') == 'context-pressure' or r.get('category') == 'context'

def enough_visible(r, min_eval=8, min_chars=80):
    return (fnum(r.get('visible_answer_tps')) is not None
            and inum(r.get('response_chars')) >= min_chars
            and inum(r.get('eval_tokens')) >= min_eval)

def valid_context(r):
    return (is_context_row(r)
            and r.get('result_state') == 'PASS'
            and r.get('sample_status') == 'OK'
            and fnum(r.get('visible_answer_tps')) is not None
            and inum(r.get('response_chars')) >= MIN_CONTEXT_RESPONSE_CHARS
            and inum(r.get('eval_tokens')) >= MIN_CONTEXT_EVAL_TOKENS)

capability_rows = [r for r in ok_rows if (not is_context_row(r)) and r.get('category') in ('coding', 'essay', 'internet_access') and enough_visible(r)]
warm_rows = [r for r in capability_rows if r.get('mode') == 'resident-warm']
context_rows = [r for r in rows if valid_context(r)]
visible_rows = capability_rows
valid_generation_rows = len(capability_rows) + len(context_rows)
valid_capability_rows = len(capability_rows)
valid_context_rows = len(context_rows)
short_context_rows = sum(1 for r in rows if is_context_row(r) and r.get('sample_status') in ('SHORT_CONTEXT_SAMPLE','SHORT_SAMPLE') or (is_context_row(r) and fnum(r.get('http'),0) == 200 and inum(r.get('eval_tokens')) and inum(r.get('eval_tokens')) < MIN_CONTEXT_EVAL_TOKENS))
unsupported = sum(1 for r in rows if r.get('result_state') == 'UNSUPPORTED')
skipped = sum(1 for r in rows if r.get('result_state') == 'SKIPPED')
thinking_only = sum(1 for r in rows if r.get('thinking_only') in ('1', 'true', 'True'))
fail_visible = sum(1 for r in rows if r.get('sample_status') == 'FAIL_VISIBLE_OUTPUT')

# Pull first request metrics from the first non-skipped row, even if it failed.
first = next((r for r in rows if r.get('result_state') != 'SKIPPED'), rows[0] if rows else {})
first_ttft = fnum(first.get('ttft_any_ms'))
first_load = fnum(first.get('load_s'))
if first_load == 0 and fnum(first.get('http'), 0) >= 400:
    first_load = None
warm_ttft = mean([fnum(r.get('ttft_answer_ms')) for r in warm_rows])
visible_tps = mean([fnum(r.get('visible_answer_tps')) for r in warm_rows]) or mean([fnum(r.get('visible_answer_tps')) for r in capability_rows])

# Root API errors from row notes and metrics sidecars.
root_errors = []
for r in api_error_rows:
    note = r.get('notes') or ''
    m = re.search(r'api_error=([^|]+)$', note)
    if m:
        root_errors.append(m.group(1).strip())
for pth in sorted((rd / 'raw').glob('*.metrics.json')) if (rd / 'raw').exists() else []:
    try:
        obj = json.loads(pth.read_text(encoding='utf-8', errors='ignore'))
    except Exception:
        continue
    api_error = str(obj.get('api_error') or '').strip()
    if api_error:
        root_errors.append(api_error)
    elif obj.get('http_code', 0) and int(obj.get('http_code') or 0) >= 400:
        body = str(obj.get('error_body') or '').strip()
        if body:
            try:
                parsed = json.loads(body)
                root_errors.append(str(parsed.get('error') or parsed.get('message') or body)[:500])
            except Exception:
                root_errors.append(body[:500])
# stable unique
seen = set(); unique_root_errors = []
for e in root_errors:
    e = re.sub(r'\s+', ' ', e).strip()
    if e and e not in seen:
        unique_root_errors.append(e); seen.add(e)
root_error = unique_root_errors[0] if unique_root_errors else ''

# GPU / VRAM from after snapshot CSV or live fallback.
vram_used = vram_total = vram_pct = None
nq = rd / 'nvidia-smi-query-after.csv'
if nq.exists():
    txt = nq.read_text(errors='ignore').strip().splitlines()
    if txt:
        parts = [x.strip() for x in txt[-1].split(',')]
        nums = []
        for x in parts:
            m = re.search(r'([0-9.]+)', x)
            if m:
                nums.append(float(m.group(1)))
        candidates = [n for n in nums if n > 1000]
        if len(candidates) >= 2:
            vram_used, vram_total = candidates[-2], candidates[-1]
try:
    if vram_total is None:
        out = subprocess.check_output(
            ['nvidia-smi', '--query-gpu=memory.used,memory.total', '--format=csv,noheader,nounits'],
            text=True, stderr=subprocess.DEVNULL, timeout=2).splitlines()[0]
        vram_used, vram_total = [float(x.strip()) for x in out.split(',')[:2]]
except Exception:
    pass
if vram_used is not None and vram_total:
    vram_pct = round(vram_used * 100 / vram_total, 1)

# Residency from ollama ps after if available.
residency = 'unknown'
ps_txt = read_text(rd / 'ollama-ps-after.txt')
if '100% GPU' in ps_txt:
    residency = 'full_gpu'
elif re.search(r'[0-9]+%/[0-9]+% CPU/GPU|CPU/GPU', ps_txt):
    residency = 'cpu_gpu_offload'

classifications = []
if residency == 'full_gpu':
    classifications.append('FULL_GPU_RESIDENT')
if residency == 'cpu_gpu_offload':
    classifications.append('CPU_GPU_OFFLOAD_RISK')
if ((first_ttft and first_ttft > 60000) or (first_load and first_load > 60)) and warm_ttft is not None and warm_ttft < 1000:
    classifications += ['GOOD_WARM_BAD_COLD', 'RESIDENT_ONLY_RECOMMENDED']
if vram_pct is not None and vram_pct > 97:
    classifications += ['VRAM_CRITICAL_HEADROOM', 'CONTEXT_INCREASE_NOT_RECOMMENDED']
elif vram_pct is not None and vram_pct > 92:
    classifications.append('VRAM_WARN_HEADROOM')
if thinking_only or fail_visible:
    classifications.append('THINKING_ONLY_OUTPUT_RISK')
if unsupported:
    classifications.append('UNSUPPORTED_IN_GENERATION_TEST')
if short_context_rows:
    classifications.append('CONTEXT_PRESSURE_INCONCLUSIVE')
if api_error_rows and valid_generation_rows == 0:
    classifications += ['NO_VALID_GENERATION_ROWS', 'NO_MODEL_RANKING']

# Status and decision-grade gates.
if not rows:
    status = 'NO_ROWS'
elif unsupported and valid_generation_rows == 0 and not api_error_rows:
    status = 'UNSUPPORTED'
elif api_error_rows and valid_generation_rows == 0:
    status = 'TOOL_FAILURE'
elif api_error_rows and valid_generation_rows > 0:
    status = 'PARTIAL_FAIL_REVIEW'
elif fail_visible or thinking_only or short_context_rows:
    status = 'PASS_WITH_REVIEW'
elif vram_pct is not None and vram_pct > 92:
    status = 'PASS_WITH_WARNINGS'
elif skipped:
    status = 'PASS_WITH_SKIPS'
else:
    status = 'PASS'

decision_grade = status.startswith('PASS') and valid_capability_rows >= 1 and valid_generation_rows >= 1
context_validated = valid_context_rows > 0
ranking_allowed = decision_grade and valid_generation_rows > 0
settings_confidence = 'HIGH_CONFIRMED' if (decision_grade and context_validated and not api_error_rows and short_context_rows == 0) else ('MEDIUM_PARTIAL' if decision_grade else 'LOW_UNCONFIRMED')

# Settings policy: do not call a setting tested/safe unless supporting rows passed.
def int_ctx(x):
    try:
        return int(float(x))
    except Exception:
        return 4096
baseline_ctx = int_ctx(args.ctx)
if context_rows:
    ctx_rec = max(int_ctx(r.get('ctx')) for r in context_rows)
else:
    ctx_rec = baseline_ctx
if 'VRAM_CRITICAL_HEADROOM' in classifications or residency == 'cpu_gpu_offload':
    ctx_rec = min(ctx_rec, baseline_ctx, 4096)
max_loaded = '1'
num_parallel = '1'
keep_alive = args.keep_alive
flash = '1'
# Only mark q8_0 as active when the environment or runner facts actually expose it.
env_text = read_text(rd / 'environment-summary.md') + '\n' + read_text(rd / 'runner-log-facts.md') + '\n' + read_text(rd / 'runner-facts.txt')
kv_confirmed = bool(re.search(r'OLLAMA_KV_CACHE_TYPE[^\n]*q8_0|KvCacheType[^\n]*q8_0|kv_cache_type[^\n]*q8_0', env_text, re.I))
kv_value = 'q8_0' if kv_confirmed else 'unconfirmed_optional_q8_0'
rationale = []
if not decision_grade:
    rationale.append('No decision-grade generation evidence was produced; settings are a safe baseline, not confirmed best parameters.')
if context_validated:
    rationale.append(f'Context {ctx_rec} was supported by a passing context-pressure row with enough generated output.')
else:
    rationale.append(f'Context {ctx_rec} is a conservative baseline because no context-pressure row passed the minimum-output gate.')
if 'VRAM_CRITICAL_HEADROOM' in classifications:
    rationale.append('VRAM exceeded 97%; keep one model loaded, one parallel request, and conservative context.')
elif vram_pct is not None and vram_pct < 75 and context_validated:
    rationale.append('Observed VRAM headroom was below 75% and context-pressure evidence passed.')
if 'GOOD_WARM_BAD_COLD' in classifications:
    keep_alive = '24h'
    rationale.append('Warm performance was good but cold-load latency was high; keep the model resident.')
if residency == 'cpu_gpu_offload':
    rationale.append('CPU/GPU offload was detected; reduce context or choose a smaller model.')
if kv_confirmed:
    rationale.append('OLLAMA_KV_CACHE_TYPE=q8_0 appeared in service or runner evidence.')
else:
    rationale.append('KV cache q8_0 was not confirmed in this run, so it is left as an optional commented setting.')

# Main setting artifacts.
settings_conf = rd / 'recommended-ollama-env.conf'
settings_sh = rd / 'performance-settings.sh'
settings_md = rd / 'performance-settings.md'
conf_lines = [
    '[Service]',
    f'Environment="OLLAMA_KEEP_ALIVE={keep_alive}"',
    f'Environment="OLLAMA_MAX_LOADED_MODELS={max_loaded}"',
    f'Environment="OLLAMA_NUM_PARALLEL={num_parallel}"',
    f'Environment="OLLAMA_FLASH_ATTENTION={flash}"',
    f'Environment="OLLAMA_CONTEXT_LENGTH={ctx_rec}"',
]
if kv_confirmed:
    conf_lines.append('Environment="OLLAMA_KV_CACHE_TYPE=q8_0"')
else:
    conf_lines.append('# Optional after explicit validation: Environment="OLLAMA_KV_CACHE_TYPE=q8_0"')
settings_conf.write_text('\n'.join(conf_lines) + '\n', encoding='utf-8')
settings_sh.write_text(f'''#!/usr/bin/env bash
# Apply Ollama settings for {args.model} on this WSL2/Linux host.
# settings_confidence={settings_confidence}
# Generated by ollama-info v1.11. Review performance-settings.md before applying.
set -euo pipefail
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF_OVERRIDE'
{settings_conf.read_text()}EOF_OVERRIDE
sudo systemctl daemon-reload
sudo systemctl restart ollama.service
ollama ps
''', encoding='utf-8')
settings_sh.chmod(0o755)
settings_md.write_text(f'''# Performance settings recommendation

Model: `{args.model}`
Status: `{status}`
Decision-grade: `{decision_grade}`
Settings confidence: `{settings_confidence}`

## Applyable systemd override

`recommended-ollama-env.conf`:

```ini
{settings_conf.read_text()}```

Apply with:

```bash
./performance-settings.sh
```

## Rationale

{chr(10).join('- ' + x for x in rationale)}

## Safety notes

- Settings are confirmed only when generation rows and required context-pressure rows pass.
- Context-pressure validation requires at least 128 eval tokens and 120 response characters; shorter rows are inconclusive.
- `OLLAMA_MAX_LOADED_MODELS=1` is the safe RTX 3090 default for large-model evaluation.
- `OLLAMA_NUM_PARALLEL=1` protects KV-cache VRAM headroom until a concurrency-specific benchmark passes.
- `OLLAMA_CONTEXT_LENGTH={ctx_rec}` is marked confirmed only when `context_validated=true` in `model-scorecard.csv`.
''', encoding='utf-8')

# scorecard
score = rd / 'model-scorecard.csv'
score_cols = [
    'model','role','status','decision_grade','mode','residency','classifications',
    'valid_generation_rows','valid_capability_rows','valid_context_rows','api_error_rows','root_error',
    'first_ttft_ms','first_load_s','warm_ttft_ms_avg','visible_tps_avg','vram_pct',
    'recommended_context','context_validated','settings_confidence','keep_alive','max_loaded_models',
    'num_parallel','flash_attention','kv_cache_type','ranking_allowed'
]
with score.open('w', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=score_cols)
    w.writeheader()
    w.writerow({
        'model': args.model, 'role': args.role, 'status': status, 'decision_grade': int(decision_grade),
        'mode': args.mode, 'residency': residency, 'classifications': ';'.join(classifications),
        'valid_generation_rows': valid_generation_rows, 'valid_capability_rows': valid_capability_rows,
        'valid_context_rows': valid_context_rows, 'api_error_rows': len(api_error_rows), 'root_error': root_error,
        'first_ttft_ms': '' if first_ttft is None else round(first_ttft, 1),
        'first_load_s': '' if first_load is None else round(first_load, 2),
        'warm_ttft_ms_avg': '' if warm_ttft is None else round(warm_ttft, 1),
        'visible_tps_avg': '' if visible_tps is None else round(visible_tps, 2),
        'vram_pct': '' if vram_pct is None else vram_pct,
        'recommended_context': ctx_rec, 'context_validated': int(context_validated),
        'settings_confidence': settings_confidence, 'keep_alive': keep_alive,
        'max_loaded_models': max_loaded, 'num_parallel': num_parallel,
        'flash_attention': flash, 'kv_cache_type': kv_value, 'ranking_allowed': int(ranking_allowed)
    })

# Recommendations fail closed.
reco = rd / 'recommendations.md'
if not ranking_allowed:
    reco_text = f'''# Model recommendations

Model: `{args.model}`

## Verdict

No best-model recommendation is emitted for this run.

Reason: `{status}` with `{valid_generation_rows}` valid generation rows, `{valid_capability_rows}` valid capability rows, and `{valid_context_rows}` valid context rows.

Root error: `{root_error or 'none captured'}`

## Use-case table

| Use case | Recommendation |
|---|---|
| OpenCode | No recommendation from this run. |
| Cursor | No recommendation from this run. |
| Hermes | No recommendation from this run. |
| ADOS | No recommendation from this run. |

Repair the failing rows and rerun before selecting a winner or applying performance-tuned settings.
'''
else:
    def use_line(use):
        if args.role == 'embedding':
            return 'Use only through `ollama embed-test` or `ollama bench`; not a generation model.'
        if 'CPU_GPU_OFFLOAD_RISK' in classifications:
            return 'Not recommended as default until offload is eliminated.'
        if use in ('OpenCode', 'Cursor'):
            if visible_tps and visible_tps > 70 and fail_visible == 0:
                return 'Recommended for fast coding loops when coding validator rows pass.'
            if 'RESIDENT_ONLY_RECOMMENDED' in classifications:
                return 'Use for heavier code reasoning only when preloaded/resident.'
            return 'Usable, but compare against a faster coder model for tight loops.'
        if use in ('Hermes', 'ADOS'):
            if 'RESIDENT_ONLY_RECOMMENDED' in classifications:
                return 'Recommended as a heavy resident model; preload before work.'
            return 'Recommended if warm TTFT and VRAM headroom match your workload.'
        return ''
    reco_text = f'''# Model recommendations

Model: `{args.model}`

| Use case | Recommendation |
|---|---|
| OpenCode | {use_line('OpenCode')} |
| Cursor | {use_line('Cursor')} |
| Hermes | {use_line('Hermes')} |
| ADOS | {use_line('ADOS')} |

Main classification: `{', '.join(classifications) if classifications else 'NONE'}`

Primary setting artifact: `performance-settings.sh`.
'''
reco.write_text(reco_text, encoding='utf-8')

# Human summary.
warm_ttft_s = 'N/A' if warm_ttft is None else f'{warm_ttft:.0f} ms'
vis_s = 'N/A' if visible_tps is None else f'{visible_tps:.2f} tok/s'
first_s = 'N/A' if first_ttft is None else f'{first_ttft:.0f} ms'
load_s = 'N/A' if first_load is None else f'{first_load:.2f}s'
vram_s = 'N/A' if vram_pct is None else f'{vram_pct:.1f}%'
summary = f'''# RTX 3090 Ollama Test Summary

## Run metadata
- script_version: 1.11-final
- model: {args.model}
- role: {args.role}
- mode: {args.mode}
- profile: {args.profile}
- base_url: {args.base_url}
- status: {status}
- decision_grade: {decision_grade}

## Decision-grade result
- FirstTTFT: {first_s}
- FirstReqLoad: {load_s}
- WarmTTFT: {warm_ttft_s}
- Visible answer speed: {vis_s}
- VRAM used: {vram_s}
- Residency: {residency}
- Valid generation rows: {valid_generation_rows}
- Valid capability rows: {valid_capability_rows}
- Valid context rows: {valid_context_rows}
- Short/inconclusive context rows: {short_context_rows}
- API error rows: {len(api_error_rows)}
- Root error: {root_error or 'none captured'}
- Classifications: {', '.join(classifications) if classifications else 'NONE'}

## Performance setting output
- Applyable config script: `performance-settings.sh`
- Systemd override file: `recommended-ollama-env.conf`
- Human explanation: `performance-settings.md`
- Settings confidence: `{settings_confidence}`
- Scorecard: `model-scorecard.csv`
- Recommendations: `recommendations.md`
- Environment facts: `environment-summary.md`
- Runner/server facts: `runner-log-facts.md`

## Test results

| Test | Mode | Category | State | Sample | Ctx | Predict | Eval tok | Visible tok/s | TTFT answer ms | Response chars | Thinking chars | Notes |
|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|
'''
for r in rows:
    notes = (r.get('notes') or '').replace('|', '/')[:240]
    summary += f"| {r.get('test','')} | {r.get('mode','')} | {r.get('category','')} | {r.get('result_state','')} | {r.get('sample_status','')} | {r.get('ctx','')} | {r.get('predict','')} | {r.get('eval_tokens','')} | {r.get('visible_answer_tps','')} | {r.get('ttft_answer_ms','')} | {r.get('response_chars','')} | {r.get('thinking_chars','')} | {notes} |\n"
(rd / 'summary.md').write_text(summary, encoding='utf-8')
term = f'''============================================================
RTX3090 OLLAMA TEST SUMMARY
Model   : {args.model}
Role    : {args.role}
Mode    : {args.mode}
Status  : {status}
Decision: {'YES' if decision_grade else 'NO'}
FirstTTFT: {first_s}
FirstReqLoad: {load_s}
WarmTTFT: {warm_ttft_s}
Visible : {vis_s}
Residency: {residency}
VRAM    : {vram_s}
ValidRows: generation={valid_generation_rows} capability={valid_capability_rows} context={valid_context_rows} short_context={short_context_rows}
RootErr : {root_error or 'none captured'}
Class   : {', '.join(classifications) if classifications else 'NONE'}
Settings: {settings_sh} confidence={settings_confidence}
Scorecard: {score}
============================================================
'''
(rd / 'terminal-summary.txt').write_text(term, encoding='utf-8')
print(term)
