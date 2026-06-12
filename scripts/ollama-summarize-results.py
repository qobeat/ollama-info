#!/usr/bin/env python3
"""Summarize ollama-info generation diagnostics.

v1.12 policy:
- terminal summaries use tables and separate execution, performance, context, settings, and recommendations;
- context rows only pass when they have meaningful prompt/eval evidence;
- Hermes main chat is not confirmed unless >=65K context passes;
- preload/model-ready wait is a first-class metric;
- settings are confidence-scoped rather than overclaimed.
"""
import argparse, csv, json, re, statistics, subprocess
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--run-dir', required=True)
p.add_argument('--model', required=True)
p.add_argument('--role', default='generate')
p.add_argument('--base-url', default='http://127.0.0.1:11434')
p.add_argument('--profile', default='ados')
p.add_argument('--mode', default='resident-warm')
p.add_argument('--ctx', default='4096')
p.add_argument('--keep-alive', default='24h')
p.add_argument('--min-context', default='65536')
p.add_argument('--min-context-eval', default='128')
p.add_argument('--min-context-chars', default='500')
p.add_argument('--min-context-fill', default='0.65')
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

def fmt_ms(v):
    return 'N/A' if v is None else f'{v:.0f} ms'

def fmt_s(v):
    return 'N/A' if v is None else f'{v:.2f}s'

def fmt_tps(v):
    return 'N/A' if v is None else f'{v:.2f}'

def read_text(path):
    try:
        return Path(path).read_text(encoding='utf-8', errors='ignore')
    except Exception:
        return ''

def read_kv(path):
    out = {}
    for line in read_text(path).splitlines():
        if '=' in line:
            k,v = line.split('=',1); out[k.strip()] = v.strip()
    return out

def parse_context_length_from_show():
    raw = rd / 'ollama-api-show-model-raw.json'
    if not raw.exists():
        return None
    try:
        obj = json.loads(raw.read_text(encoding='utf-8', errors='ignore'))
    except Exception:
        return None
    mi = obj.get('model_info') or {}
    vals = []
    for k,v in mi.items():
        if str(k).endswith('.context_length'):
            try: vals.append(int(float(v)))
            except Exception: pass
    return max(vals) if vals else None

def effective_context_for_step(step):
    p = rd / f'ollama-api-ps-after-context-{step}.json'
    if not p.exists(): return None
    try: obj = json.loads(p.read_text(encoding='utf-8', errors='ignore'))
    except Exception: return None
    for m in obj.get('models', []):
        if m.get('name') == args.model or m.get('model') == args.model:
            for key in ('context_length','context','num_ctx'):
                if key in m:
                    try: return int(float(m[key]))
                    except Exception: pass
            # Some Ollama versions put details in size_vram or no context at all.
    return None

# Evidence partitions.
api_error_rows = [r for r in rows if r.get('result_state') == 'FAIL' or (fnum(r.get('http'), 0) or 0) >= 400]
# Only rows with OK sample and visible content count for main speed. Context rows are excluded from visible average.
ok_rows = [r for r in rows if r.get('result_state') == 'PASS' and r.get('sample_status') == 'OK']
visible_non_context_rows = [r for r in ok_rows if r.get('category') != 'context' and fnum(r.get('visible_answer_tps')) is not None and inum(r.get('response_chars')) > 0]
warm_rows = [r for r in visible_non_context_rows if r.get('mode') == 'resident-warm']
capability_rows = [r for r in visible_non_context_rows if r.get('category') in ('coding', 'essay', 'internet_access')]
context_all_rows = [r for r in rows if r.get('category') == 'context' or r.get('mode') == 'context-pressure']
min_context_eval = inum(args.min_context_eval, 128)
min_context_chars = inum(args.min_context_chars, 500)
min_context_fill = fnum(args.min_context_fill, 0.65) or 0.65
context_valid_rows = []
context_short_rows = []
for r in context_all_rows:
    http = inum(r.get('http'))
    eval_tokens = inum(r.get('eval_tokens'))
    resp_chars = inum(r.get('response_chars'))
    prompt_tokens = inum(r.get('prompt_tokens'))
    ctx = inum(r.get('ctx'))
    if r.get('result_state') == 'PASS' and r.get('sample_status') == 'OK' and http < 400 and eval_tokens >= min_context_eval and resp_chars >= min_context_chars and prompt_tokens >= max(1, int(ctx*min_context_fill)):
        context_valid_rows.append(r)
    elif r.get('result_state') != 'SKIPPED':
        context_short_rows.append(r)
valid_generation_rows = len(visible_non_context_rows)
valid_capability_rows = len(capability_rows)
valid_context_rows = len(context_valid_rows)
unsupported = sum(1 for r in rows if r.get('result_state') == 'UNSUPPORTED')
skipped = sum(1 for r in rows if r.get('result_state') == 'SKIPPED')
thinking_only = sum(1 for r in rows if r.get('thinking_only') in ('1', 'true', 'True'))
fail_visible = sum(1 for r in rows if r.get('sample_status') == 'FAIL_VISIBLE_OUTPUT')

first = next((r for r in rows if r.get('result_state') != 'SKIPPED'), rows[0] if rows else {})
first_ttft = fnum(first.get('ttft_any_ms'))
first_load = fnum(first.get('load_s'))
if first_load == 0 and (fnum(first.get('http'), 0) or 0) >= 400:
    first_load = None
warm_ttft = mean([fnum(r.get('ttft_answer_ms')) for r in warm_rows])
visible_tps = mean([fnum(r.get('visible_answer_tps')) for r in visible_non_context_rows])
preload_kv = read_kv(rd / 'preload-state.txt')
preload_wait = fnum(preload_kv.get('preload_wait_s'))
model_ready = (preload_wait or 0) + (first_load or 0) if (preload_wait is not None or first_load is not None) else None

# Root API errors from row notes and metrics sidecars.
root_errors = []
for r in api_error_rows:
    note = r.get('notes') or ''
    m = re.search(r'api_error=([^|]+)$', note)
    if m: root_errors.append(m.group(1).strip())
for pth in sorted((rd / 'raw').glob('*.metrics.json')) if (rd / 'raw').exists() else []:
    try: obj = json.loads(pth.read_text(encoding='utf-8', errors='ignore'))
    except Exception: continue
    api_error = str(obj.get('api_error') or '').strip()
    if api_error: root_errors.append(api_error)
    elif obj.get('http_code', 0) and int(obj.get('http_code') or 0) >= 400:
        body = str(obj.get('error_body') or '').strip()
        if body:
            try:
                parsed = json.loads(body); root_errors.append(str(parsed.get('error') or parsed.get('message') or body)[:500])
            except Exception: root_errors.append(body[:500])
seen=set(); unique=[]
for e in root_errors:
    e = re.sub(r'\s+', ' ', e).strip()
    if e and e not in seen:
        unique.append(e); seen.add(e)
root_error = unique[0] if unique else ''

# VRAM.
vram_used = vram_total = vram_pct = None
nq = rd / 'nvidia-smi-query-after.csv'
if nq.exists():
    txt = nq.read_text(errors='ignore').strip().splitlines()
    if txt:
        parts = [x.strip() for x in txt[-1].split(',')]
        nums=[]
        for x in parts:
            m=re.search(r'([0-9.]+)', x)
            if m: nums.append(float(m.group(1)))
        candidates=[n for n in nums if n>1000]
        if len(candidates)>=2: vram_used, vram_total = candidates[-2], candidates[-1]
try:
    if vram_total is None:
        out=subprocess.check_output(['nvidia-smi','--query-gpu=memory.used,memory.total','--format=csv,noheader,nounits'], text=True, stderr=subprocess.DEVNULL, timeout=2).splitlines()[0]
        vram_used, vram_total = [float(x.strip()) for x in out.split(',')[:2]]
except Exception: pass
if vram_used is not None and vram_total: vram_pct = round(vram_used*100/vram_total,1)

# Residency.
residency='unknown'
ps_txt=read_text(rd/'ollama-ps-after.txt')
if '100% GPU' in ps_txt: residency='full_gpu'
elif re.search(r'[0-9]+%/[0-9]+% CPU/GPU|CPU/GPU', ps_txt): residency='cpu_gpu_offload'

metadata_context = parse_context_length_from_show()
hermes_min = inum(args.min_context, 65536)
hermes_65k_context = 'PASS' if any(inum(r.get('ctx')) >= hermes_min for r in context_valid_rows) else ('FAIL' if any(inum(r.get('ctx')) >= hermes_min for r in context_all_rows) else 'NOT_TESTED')

classifications=[]
if residency == 'full_gpu': classifications.append('FULL_GPU_RESIDENT')
if residency == 'cpu_gpu_offload': classifications.append('CPU_GPU_OFFLOAD_RISK')
if ((preload_wait and preload_wait > 60) or (first_ttft and first_ttft > 60000) or (first_load and first_load > 60)) and warm_ttft is not None and warm_ttft < 1000:
    classifications += ['GOOD_WARM_BAD_COLD','RESIDENT_ONLY_RECOMMENDED']
if vram_pct is not None and vram_pct > 97: classifications += ['VRAM_CRITICAL_HEADROOM','CONTEXT_INCREASE_NOT_RECOMMENDED']
elif vram_pct is not None and vram_pct > 92: classifications.append('VRAM_WARN_HEADROOM')
if thinking_only or fail_visible: classifications.append('THINKING_ONLY_OUTPUT_RISK')
if unsupported: classifications.append('UNSUPPORTED_IN_GENERATION_TEST')
if api_error_rows and valid_generation_rows == 0: classifications += ['NO_VALID_GENERATION_ROWS','NO_MODEL_RANKING']
if hermes_65k_context != 'PASS': classifications.append('HERMES_65K_NOT_CONFIRMED')

if not rows: status='NO_ROWS'
elif unsupported and valid_generation_rows == 0 and not api_error_rows: status='UNSUPPORTED'
elif api_error_rows and valid_generation_rows == 0: status='TOOL_FAILURE'
elif api_error_rows and valid_generation_rows > 0: status='PARTIAL_FAIL_REVIEW'
elif fail_visible or thinking_only: status='PASS_WITH_REVIEW'
elif vram_pct is not None and vram_pct > 92: status='PASS_WITH_WARNINGS'
elif skipped: status='PASS_WITH_SKIPS'
else: status='PASS'

context_validated = valid_context_rows > 0
decision_grade = (status.startswith('PASS') and valid_capability_rows >= 1 and valid_generation_rows >= 1) or (args.mode == 'context-pressure' and context_validated)
ranking_allowed = status.startswith('PASS') and valid_generation_rows > 0 and valid_capability_rows >= 1
settings_confidence = 'HIGH_CONTEXT_CONFIRMED' if (context_validated and any(inum(r.get('ctx')) >= hermes_min for r in context_valid_rows) and not api_error_rows) else ('MEDIUM_CONTEXT_PARTIAL' if context_validated and decision_grade else ('MEDIUM_WARM_ONLY' if decision_grade else 'LOW_UNCONFIRMED'))

baseline_ctx = inum(args.ctx, 4096)
ctx_rec = max([inum(r.get('ctx')) for r in context_valid_rows], default=baseline_ctx)
if 'VRAM_CRITICAL_HEADROOM' in classifications or residency == 'cpu_gpu_offload': ctx_rec = min(ctx_rec, baseline_ctx, 4096)
max_loaded='1'; num_parallel='1'; keep_alive=args.keep_alive; flash='1'
env_text=read_text(rd/'environment-summary.md')+'\n'+read_text(rd/'runner-log-facts.md')+'\n'+read_text(rd/'runner-facts.txt')
kv_confirmed=bool(re.search(r'OLLAMA_KV_CACHE_TYPE[^\n]*q8_0|KvCacheType[^\n]*q8_0|kv_cache_type[^\n]*q8_0', env_text, re.I))
kv_value='q8_0' if kv_confirmed else 'unconfirmed_optional_q8_0'

# Context summary artifacts.
context_cols=['model','metadata_context_length','requested_context','effective_context','prompt_eval_tokens','context_fill_pct','eval_tokens','response_chars','ttft_answer_ms','visible_tps','http','sample_status','verdict']
context_out=[]
for r in context_all_rows:
    ctx=inum(r.get('ctx'))
    eff=effective_context_for_step(ctx)
    prompt=inum(r.get('prompt_tokens'))
    fill=(prompt/ctx*100) if ctx else None
    http=inum(r.get('http'))
    eval_tokens=inum(r.get('eval_tokens'))
    chars=inum(r.get('response_chars'))
    if metadata_context and metadata_context < ctx:
        verdict='CONTEXT_METADATA_UNSUPPORTED'
    elif http >= 400:
        verdict='CONTEXT_RUNTIME_REJECTED'
    elif eval_tokens < min_context_eval or chars < min_context_chars:
        verdict='CONTEXT_ACCEPTED_SHORT_OUTPUT'
    elif prompt < int(ctx*min_context_fill):
        verdict='CONTEXT_UNDERFILLED'
    elif residency == 'cpu_gpu_offload':
        verdict='CONTEXT_ACCEPTED_OFFLOADED'
    elif vram_pct is not None and vram_pct > 97:
        verdict='CONTEXT_ACCEPTED_VRAM_CRITICAL'
    elif ctx >= hermes_min:
        verdict='CONTEXT_PASS_HERMES_MAIN_CHAT'
    else:
        verdict='CONTEXT_PASS_WARM_ONLY'
    context_out.append({
        'model': args.model,'metadata_context_length': metadata_context or '', 'requested_context': ctx,
        'effective_context': eff or '', 'prompt_eval_tokens': prompt,
        'context_fill_pct': '' if fill is None else round(fill,1), 'eval_tokens': eval_tokens,
        'response_chars': chars, 'ttft_answer_ms': r.get('ttft_answer_ms',''), 'visible_tps': r.get('visible_answer_tps',''),
        'http': http, 'sample_status': r.get('sample_status',''), 'verdict': verdict})
with (rd/'context-summary.csv').open('w', newline='', encoding='utf-8') as f:
    w=csv.DictWriter(f, fieldnames=context_cols); w.writeheader(); w.writerows(context_out)
ctx_md=['# Context window summary','',f'Model: `{args.model}`',f'Metadata context length: `{metadata_context or "unknown"}`',f'Hermes 65K context: `{hermes_65k_context}`','', '| Requested | Effective | Prompt tokens | Fill % | Eval | Chars | HTTP | Verdict |','|---:|---:|---:|---:|---:|---:|---:|---|']
if context_out:
    for r in context_out:
        ctx_md.append(f"| {r['requested_context']} | {r['effective_context'] or 'unknown'} | {r['prompt_eval_tokens']} | {r['context_fill_pct']} | {r['eval_tokens']} | {r['response_chars']} | {r['http']} | {r['verdict']} |")
else:
    ctx_md.append('| - | - | - | - | - | - | - | NOT_TESTED |')
(rd/'context-summary.md').write_text('\n'.join(ctx_md)+'\n', encoding='utf-8')
(rd/'hermes-compatibility.md').write_text(f'''# Hermes compatibility

Model: `{args.model}`

| Gate | Result | Evidence |
|---|---|---|
| 65K context required | yes | user requirement |
| Metadata context >=65K | {'YES' if metadata_context and metadata_context>=hermes_min else 'UNKNOWN/NO'} | metadata_context_length={metadata_context or 'unknown'} |
| Runtime 65K tested | {'YES' if any(inum(r.get('ctx'))>=hermes_min for r in context_all_rows) else 'NO'} | context-summary.csv |
| 65K usable | {hermes_65k_context} | context-summary.csv |
| Hermes main-chat recommendation | {'CONFIRMED' if hermes_65k_context=='PASS' else 'NOT CONFIRMED'} | requires passing 65K context row |
''', encoding='utf-8')

# Settings artifacts.
rationale=[]
if not decision_grade: rationale.append('No decision-grade generation evidence was produced; settings are a safe baseline, not confirmed best parameters.')
if context_validated: rationale.append(f'Context {ctx_rec} was supported by a passing context-pressure row.')
else: rationale.append(f'Context {ctx_rec} is a warm-inference baseline; no context-pressure row passed.')
if hermes_65k_context != 'PASS': rationale.append('Hermes main chat is not confirmed because 65K context did not pass or was not tested.')
if preload_wait and preload_wait > 30: rationale.append(f'Preload/model-ready wait was {preload_wait:.1f}s; use keep_alive/preload workflow for this model.')
if 'VRAM_CRITICAL_HEADROOM' in classifications: rationale.append('VRAM exceeded 97%; keep one model loaded, one parallel request, and conservative context.')
if residency == 'cpu_gpu_offload': rationale.append('CPU/GPU offload was detected; reduce context or choose a smaller model.')
if kv_confirmed: rationale.append('OLLAMA_KV_CACHE_TYPE=q8_0 appeared in service or runner evidence.')
else: rationale.append('KV cache q8_0 was not confirmed in this run, so it is left as an optional commented setting.')
settings_conf=rd/'recommended-ollama-env.conf'; settings_sh=rd/'performance-settings.sh'; settings_md=rd/'performance-settings.md'
conf_lines=['[Service]',f'Environment="OLLAMA_KEEP_ALIVE={keep_alive}"',f'Environment="OLLAMA_MAX_LOADED_MODELS={max_loaded}"',f'Environment="OLLAMA_NUM_PARALLEL={num_parallel}"',f'Environment="OLLAMA_FLASH_ATTENTION={flash}"',f'Environment="OLLAMA_CONTEXT_LENGTH={ctx_rec}"']
conf_lines.append('Environment="OLLAMA_KV_CACHE_TYPE=q8_0"' if kv_confirmed else '# Optional after explicit validation: Environment="OLLAMA_KV_CACHE_TYPE=q8_0"')
settings_conf.write_text('\n'.join(conf_lines)+'\n', encoding='utf-8')
settings_sh.write_text(f'''#!/usr/bin/env bash
# Apply Ollama settings for {args.model} on this WSL2/Linux host.
# settings_confidence={settings_confidence}
# Generated by ollama-info v1.12. Review performance-settings.md before applying.
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
Hermes 65K context: `{hermes_65k_context}`

## Applyable systemd override

```ini
{settings_conf.read_text()}```

Apply with:

```bash
./performance-settings.sh
```

## Rationale

{chr(10).join('- '+x for x in rationale)}

## Safety notes

- `HIGH_CONTEXT_CONFIRMED` requires a passing context-pressure row.
- `MEDIUM_WARM_ONLY` means warm inference was measured, but larger context was not confirmed.
- Hermes main chat requires a passing 65K context row; otherwise it is not confirmed.
''', encoding='utf-8')

score_cols=['model','role','status','decision_grade','mode','residency','classifications','valid_generation_rows','valid_capability_rows','valid_context_rows','short_context_rows','api_error_rows','root_error','preload_wait_s','model_ready_s','first_ttft_ms','first_load_s','warm_ttft_ms_avg','visible_tps_avg','vram_pct','metadata_context_length','min_context_required','hermes_65k_context','recommended_context','context_validated','settings_confidence','keep_alive','max_loaded_models','num_parallel','flash_attention','kv_cache_type','ranking_allowed']
with (rd/'model-scorecard.csv').open('w', newline='', encoding='utf-8') as f:
    w=csv.DictWriter(f, fieldnames=score_cols); w.writeheader(); w.writerow({
        'model':args.model,'role':args.role,'status':status,'decision_grade':int(decision_grade),'mode':args.mode,'residency':residency,'classifications':';'.join(classifications),'valid_generation_rows':valid_generation_rows,'valid_capability_rows':valid_capability_rows,'valid_context_rows':valid_context_rows,'short_context_rows':len(context_short_rows),'api_error_rows':len(api_error_rows),'root_error':root_error,'preload_wait_s':'' if preload_wait is None else round(preload_wait,2),'model_ready_s':'' if model_ready is None else round(model_ready,2),'first_ttft_ms':'' if first_ttft is None else round(first_ttft,1),'first_load_s':'' if first_load is None else round(first_load,2),'warm_ttft_ms_avg':'' if warm_ttft is None else round(warm_ttft,1),'visible_tps_avg':'' if visible_tps is None else round(visible_tps,2),'vram_pct':'' if vram_pct is None else vram_pct,'metadata_context_length':metadata_context or '','min_context_required':hermes_min,'hermes_65k_context':hermes_65k_context,'recommended_context':ctx_rec,'context_validated':int(context_validated),'settings_confidence':settings_confidence,'keep_alive':keep_alive,'max_loaded_models':max_loaded,'num_parallel':num_parallel,'flash_attention':flash,'kv_cache_type':kv_value,'ranking_allowed':int(ranking_allowed)})

# Recommendation text.
reco=rd/'recommendations.md'
if not ranking_allowed:
    reco_text=f'''# Model recommendations

Model: `{args.model}`

No best-model recommendation is emitted for this run.

Reason: `{status}` with `{valid_generation_rows}` valid generation rows, `{valid_capability_rows}` valid capability rows, and `{valid_context_rows}` valid context rows.

Root error: `{root_error or 'none captured'}`
'''
else:
    caveat = 'Hermes main chat is NOT CONFIRMED because 65K context did not pass.' if hermes_65k_context!='PASS' else 'Hermes main chat context gate passed.'
    reco_text=f'''# Model recommendations

Model: `{args.model}`

| Use case | Recommendation |
|---|---|
| OpenCode/Cursor coding | Candidate if coding quality gates pass; compare against coder-specialist models. |
| Fast chat | Candidate if warm TTFT and VRAM are acceptable. |
| Hermes main chat | {'CONFIRMED candidate' if hermes_65k_context=='PASS' else 'NOT CONFIRMED'} |
| ADOS runtime | Candidate if internet-boundary and structured-output gates pass. |
| Heavy reasoning | {'Resident-only candidate' if 'RESIDENT_ONLY_RECOMMENDED' in classifications else 'Not specifically identified as heavy-reasoning winner.'} |

Caveat: {caveat}

Primary setting artifact: `performance-settings.sh`.
'''
reco.write_text(reco_text, encoding='utf-8')

# Markdown summary.
summary_lines=[
'# RTX 3090 Ollama Test Summary','',
'## Execution state','',
'| Field | Value |','|---|---|',
f'| Model | `{args.model}` |',f'| Role | `{args.role}` |',f'| Mode | `{args.mode}` |',f'| Status | `{status}` |',f'| Decision-grade | `{decision_grade}` |',f'| Preload wait | `{fmt_s(preload_wait)}` |',f'| First request load | `{fmt_s(first_load)}` |',f'| Total model-ready cost | `{fmt_s(model_ready)}` |',f'| Residency | `{residency}` |',f'| Peak VRAM | `{"N/A" if vram_pct is None else str(vram_pct)+"%"}` |','',
'## Performance','',
'| Metric | Value |','|---|---:|',f'| First TTFT | {fmt_ms(first_ttft)} |',f'| Warm TTFT avg | {fmt_ms(warm_ttft)} |',f'| Visible output speed | {fmt_tps(visible_tps)} tok/s |','',
'## Capability rows','',
'| Row | Category | HTTP | Eval tokens | TTFT answer | Visible TPS | Sample |','|---|---|---:|---:|---:|---:|---|']
for r in rows:
    if r.get('category') in ('coding','essay','internet_access'):
        summary_lines.append(f"| {r.get('test','')} | {r.get('category','')} | {r.get('http','')} | {r.get('eval_tokens','')} | {r.get('ttft_answer_ms','')} | {r.get('visible_answer_tps','')} | {r.get('sample_status','')} |")
summary_lines += ['', '## Context window', '', '| Target | Tested | Result | Reason |','|---:|---|---|---|']
if context_out:
    for c in context_out:
        summary_lines.append(f"| {c['requested_context']} | yes | {c['verdict']} | eval={c['eval_tokens']}; chars={c['response_chars']}; fill={c['context_fill_pct']}% |")
else:
    summary_lines.append(f'| {baseline_ctx} | resident-warm only | BASELINE_USED | generation ran with ctx={baseline_ctx} |')
    summary_lines.append(f'| {hermes_min} | no | HERMES_NOT_TESTED | run `ollama context-test {args.model} --min-context {hermes_min}` |')
summary_lines += ['', '## Settings confidence', '', '| Setting | Value | Confidence |','|---|---:|---|',f'| OLLAMA_CONTEXT_LENGTH | {ctx_rec} | {settings_confidence} |',f'| Hermes 65K context | {hermes_65k_context} | {"HIGH" if hermes_65k_context=="PASS" else "NOT_CONFIRMED"} |',f'| OLLAMA_KV_CACHE_TYPE | {kv_value} | {"CONFIRMED" if kv_confirmed else "OPTIONAL"} |','', '## Full row table','', '| Test | Mode | Category | State | Sample | Ctx | Predict | Eval | Visible TPS | TTFT answer | Notes |','|---|---|---|---|---|---:|---:|---:|---:|---:|---|']
for r in rows:
    notes=(r.get('notes') or '').replace('|','/')[:180]
    summary_lines.append(f"| {r.get('test','')} | {r.get('mode','')} | {r.get('category','')} | {r.get('result_state','')} | {r.get('sample_status','')} | {r.get('ctx','')} | {r.get('predict','')} | {r.get('eval_tokens','')} | {r.get('visible_answer_tps','')} | {r.get('ttft_answer_ms','')} | {notes} |")
(rd/'summary.md').write_text('\n'.join(summary_lines)+'\n', encoding='utf-8')

term=f'''================================================================================
RTX3090 OLLAMA MODEL SUMMARY
Model: {args.model}    Role: {args.role}    Mode: {args.mode}
Status: {status}    Decision-grade: {'YES' if decision_grade else 'NO'}
================================================================================
[1] Execution State
| Field | Value |
|---|---:|
| Preload wait | {fmt_s(preload_wait)} |
| First request load | {fmt_s(first_load)} |
| Total model-ready cost | {fmt_s(model_ready)} |
| Residency | {residency} |
| Peak VRAM | {'N/A' if vram_pct is None else str(vram_pct)+'%'} |

[2] Performance
| Metric | Value |
|---|---:|
| First TTFT | {fmt_ms(first_ttft)} |
| Warm TTFT avg | {fmt_ms(warm_ttft)} |
| Visible output speed | {fmt_tps(visible_tps)} tok/s |

[3] Context Window
| Target | Tested | Result |
|---:|---|---|
| {baseline_ctx} | yes | baseline warm inference |
| {hermes_min} | {'yes' if any(inum(r.get('ctx'))>=hermes_min for r in context_all_rows) else 'no'} | {hermes_65k_context} |

[4] Settings
| Field | Value |
|---|---|
| settings_confidence | {settings_confidence} |
| recommended_context | {ctx_rec} |
| kv_cache_type | {kv_value} |

[5] Use-Case Recommendation
| Use case | Verdict | Reason |
|---|---|---|
| Coding | {'Candidate' if any(r.get('category')=='coding' for r in capability_rows) else 'Needs review'} | coding row evidence |
| Chat | {'Candidate' if warm_ttft is not None and warm_ttft < 1000 else 'Not low-latency'} | warm TTFT {fmt_ms(warm_ttft)} |
| Hermes main chat | {'CONFIRMED' if hermes_65k_context=='PASS' else 'NOT CONFIRMED'} | requires {hermes_min} context PASS |
| ADOS runtime | {'Candidate' if decision_grade else 'Not ranked'} | decision_grade={decision_grade} |
| Heavy reasoning | {'Resident candidate' if 'RESIDENT_ONLY_RECOMMENDED' in classifications else 'Not indicated'} | {', '.join(classifications) if classifications else 'no special class'} |

Artifacts: summary.md, model-scorecard.csv, recommendations.md, context-summary.md, hermes-compatibility.md, performance-settings.sh
================================================================================
'''
(rd/'terminal-summary.txt').write_text(term, encoding='utf-8')
print(term)
