#!/usr/bin/env python3
import argparse, csv, json, os, re, statistics, subprocess, textwrap
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--run-dir', required=True)
p.add_argument('--model', required=True)
p.add_argument('--role', default='generate')
p.add_argument('--base-url', default='http://127.0.0.1:11434')
p.add_argument('--profile', default='ados')
p.add_argument('--mode', default='diagnostic')
p.add_argument('--ctx', default='4096')
p.add_argument('--keep-alive', default='24h')
args=p.parse_args()
rd=Path(args.run_dir)
rows=[]
summary_csv=rd/'summary.csv'
if summary_csv.exists():
    with summary_csv.open(newline='', encoding='utf-8') as f:
        rows=list(csv.DictReader(f))

def fnum(v, default=None):
    try:
        if v in (None,'','None','N/A','NA'): return default
        return float(v)
    except Exception: return default

def inum(v, default=0):
    try: return int(float(v))
    except Exception: return default

ok_rows=[r for r in rows if r.get('result_state')=='PASS' and r.get('sample_status')=='OK']
visible_rows=[r for r in ok_rows if fnum(r.get('visible_answer_tps')) is not None]
warm_rows=[r for r in visible_rows if not r.get('test','').startswith('01_') and r.get('mode')!='empty-card']
first=rows[0] if rows else {}
first_ttft=fnum(first.get('ttft_any_ms'))
first_load=fnum(first.get('load_s'))
warm_ttfts=[fnum(r.get('ttft_answer_ms')) for r in warm_rows if fnum(r.get('ttft_answer_ms')) is not None]
visible_tps=[fnum(r.get('visible_answer_tps')) for r in visible_rows if fnum(r.get('visible_answer_tps')) is not None]
thinking_only=sum(1 for r in rows if r.get('thinking_only') in ('1','true','True'))
fail_visible=sum(1 for r in rows if r.get('sample_status')=='FAIL_VISIBLE_OUTPUT')
unsupported=sum(1 for r in rows if r.get('result_state')=='UNSUPPORTED')
errors=sum(1 for r in rows if r.get('result_state')=='FAIL')
skipped=sum(1 for r in rows if r.get('result_state')=='SKIPPED')

# GPU / VRAM from after snapshot CSV or nvidia-smi direct fallback.
vram_used=vram_total=vram_pct=None
nq=rd/'nvidia-smi-query-after.csv'
if nq.exists():
    txt=nq.read_text(errors='ignore').strip().splitlines()
    # Accept either headered or no-header CSV.
    if txt:
        line=txt[-1]
        parts=[x.strip() for x in line.split(',')]
        nums=[]
        for x in parts:
            m=re.search(r'([0-9.]+)', x)
            if m: nums.append(float(m.group(1)))
        if len(nums)>=2:
            # v1.10 writes memory.used,memory.total as fields 6/7 in noheader query; fallback last two plausible numbers >1000.
            candidates=[n for n in nums if n>1000]
            if len(candidates)>=2:
                vram_used, vram_total=candidates[-2], candidates[-1]
try:
    if vram_total is None:
        out=subprocess.check_output(['nvidia-smi','--query-gpu=memory.used,memory.total','--format=csv,noheader,nounits'], text=True, stderr=subprocess.DEVNULL, timeout=2).splitlines()[0]
        vram_used, vram_total=[float(x.strip()) for x in out.split(',')[:2]]
except Exception:
    pass
if vram_used is not None and vram_total:
    vram_pct=round(vram_used*100/vram_total,1)
else:
    vram_pct=None

# Residency from ollama ps after if available.
residency='unknown'
ps=(rd/'ollama-ps-after.txt')
if ps.exists():
    ps_txt=ps.read_text(errors='ignore')
    if '100% GPU' in ps_txt: residency='full_gpu'
    elif re.search(r'[0-9]+%/[0-9]+% CPU/GPU|CPU/GPU', ps_txt): residency='cpu_gpu_offload'

classifications=[]
if residency=='full_gpu': classifications.append('FULL_GPU_RESIDENT')
if residency=='cpu_gpu_offload': classifications.append('CPU_GPU_OFFLOAD_RISK')
if ((first_ttft and first_ttft>60000) or (first_load and first_load>60)) and warm_ttfts and statistics.mean(warm_ttfts)<1000:
    classifications += ['GOOD_WARM_BAD_COLD','RESIDENT_ONLY_RECOMMENDED']
if vram_pct is not None and vram_pct>97:
    classifications += ['VRAM_CRITICAL_HEADROOM','CONTEXT_INCREASE_NOT_RECOMMENDED']
elif vram_pct is not None and vram_pct>92:
    classifications += ['VRAM_WARN_HEADROOM']
if thinking_only or fail_visible:
    classifications.append('THINKING_ONLY_OUTPUT_RISK')
if unsupported:
    classifications.append('UNSUPPORTED_IN_GENERATION_TEST')

if errors:
    status='FAIL'
elif unsupported and not visible_rows:
    status='UNSUPPORTED'
elif fail_visible or thinking_only:
    status='PASS_WITH_REVIEW'
elif vram_pct is not None and vram_pct>92:
    status='PASS_WITH_WARNINGS'
elif skipped:
    status='PASS_WITH_SKIPS'
else:
    status='PASS' if rows else 'NO_ROWS'

# Recommended settings.
ctx_rec=int(float(args.ctx)) if str(args.ctx).isdigit() else 4096
max_loaded='1'
num_parallel='1'
keep_alive=args.keep_alive
flash='1'
kv='q8_0'
rationale=[]
if 'VRAM_CRITICAL_HEADROOM' in classifications:
    ctx_rec=min(ctx_rec,4096); rationale.append('VRAM >97%; keep context conservative and one model loaded')
elif vram_pct is not None and vram_pct<75:
    ctx_rec=max(ctx_rec,8192); rationale.append('VRAM headroom appears sufficient for larger context experiments')
else:
    rationale.append('balanced default for RTX 3090 WSL2')
if 'GOOD_WARM_BAD_COLD' in classifications:
    keep_alive='24h'; rationale.append('warm performance is good but cold load is slow; keep model resident')
if residency=='cpu_gpu_offload':
    ctx_rec=min(ctx_rec,4096); rationale.append('CPU/GPU offload detected; reduce context or model size')

settings_sh=rd/'performance-settings.sh'
settings_md=rd/'performance-settings.md'
settings_sh.write_text(f'''#!/usr/bin/env bash
# Apply Ollama performance settings for {args.model} on this WSL2/Linux host.
# Generated by ollama-info v1.10. Review before applying.
set -euo pipefail
sudo mkdir -p /etc/systemd/system/ollama.service.d
sudo tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF_OVERRIDE'
[Service]
Environment="OLLAMA_KEEP_ALIVE={keep_alive}"
Environment="OLLAMA_MAX_LOADED_MODELS={max_loaded}"
Environment="OLLAMA_NUM_PARALLEL={num_parallel}"
Environment="OLLAMA_FLASH_ATTENTION={flash}"
Environment="OLLAMA_CONTEXT_LENGTH={ctx_rec}"
Environment="OLLAMA_KV_CACHE_TYPE={kv}"
EOF_OVERRIDE
sudo systemctl daemon-reload
sudo systemctl restart ollama.service
ollama ps
''')
settings_sh.chmod(0o755)
settings_md.write_text(f'''# Performance settings recommendation

Model: `{args.model}`

Recommended WSL2/Linux Ollama service override:

```bash
{settings_sh.read_text()}
```

Rationale:

{chr(10).join('- '+x for x in rationale)}

Classification: `{', '.join(classifications) if classifications else 'NONE'}`

Notes:
- `OLLAMA_MAX_LOADED_MODELS=1` is preferred for a 24 GB RTX 3090 when large models are evaluated.
- `OLLAMA_NUM_PARALLEL=1` protects KV-cache VRAM headroom for large models; raise it only after a concurrency-specific test passes.
- `OLLAMA_CONTEXT_LENGTH={ctx_rec}` is the tested/safe recommendation from this run, not the model's theoretical metadata maximum.
''')

# scorecard
score=(rd/'model-scorecard.csv')
with score.open('w', newline='', encoding='utf-8') as f:
    w=csv.writer(f)
    w.writerow(['model','role','status','mode','residency','classifications','first_ttft_ms','first_load_s','warm_ttft_ms_avg','visible_tps_avg','vram_pct','recommended_context','keep_alive','max_loaded_models','num_parallel','flash_attention','kv_cache_type'])
    w.writerow([args.model,args.role,status,args.mode,residency,';'.join(classifications),
                '' if first_ttft is None else round(first_ttft,1),
                '' if first_load is None else round(first_load,2),
                '' if not warm_ttfts else round(statistics.mean(warm_ttfts),1),
                '' if not visible_tps else round(statistics.mean(visible_tps),2),
                '' if vram_pct is None else vram_pct,ctx_rec,keep_alive,max_loaded,num_parallel,flash,kv])

# recommendations
reco=rd/'recommendations.md'
def use_line(use):
    if args.role=='embedding': return 'Use only through `ollama embed-test` or `ollama bench`; not a generation model.'
    if 'CPU_GPU_OFFLOAD_RISK' in classifications: return 'Not recommended as default until offload is eliminated.'
    if use in ('OpenCode','Cursor'):
        if visible_tps and statistics.mean(visible_tps)>70 and fail_visible==0: return 'Recommended for fast coding loops if coding validator passes.'
        if 'RESIDENT_ONLY_RECOMMENDED' in classifications: return 'Use for heavier code reasoning only when preloaded/resident.'
        return 'Usable, but prefer a faster coder model for tight loops.'
    if use in ('Hermes','ADOS'):
        if 'RESIDENT_ONLY_RECOMMENDED' in classifications: return 'Recommended as heavy resident model; preload before work.'
        return 'Recommended if warm TTFT and VRAM headroom are acceptable.'
    return ''
reco.write_text(f'''# Model recommendations

Model: `{args.model}`

| Use case | Recommendation |
|---|---|
| OpenCode | {use_line('OpenCode')} |
| Cursor | {use_line('Cursor')} |
| Hermes | {use_line('Hermes')} |
| ADOS | {use_line('ADOS')} |

Main classification: `{', '.join(classifications) if classifications else 'NONE'}`

Primary setting artifact: `performance-settings.sh`.
''')

# summary md and terminal
warm_ttft_s = 'N/A' if not warm_ttfts else f"{statistics.mean(warm_ttfts):.0f} ms"
vis_s = 'N/A' if not visible_tps else f"{statistics.mean(visible_tps):.2f} tok/s"
first_s = 'N/A' if first_ttft is None else f"{first_ttft:.0f} ms"
load_s = 'N/A' if first_load is None else f"{first_load:.2f}s"
vram_s = 'N/A' if vram_pct is None else f"{vram_pct:.1f}%"
summary = f'''# RTX 3090 Ollama Test Summary

## Run metadata
- script_version: 1.10
- model: {args.model}
- role: {args.role}
- mode: {args.mode}
- profile: {args.profile}
- base_url: {args.base_url}
- status: {status}

## Decision-grade result
- FirstTTFT: {first_s}
- FirstReqLoad: {load_s}
- WarmTTFT: {warm_ttft_s}
- Visible answer speed: {vis_s}
- VRAM used: {vram_s}
- Residency: {residency}
- Classifications: {', '.join(classifications) if classifications else 'NONE'}

## Performance-tuned setting output
- Applyable config: `performance-settings.sh`
- Human explanation: `performance-settings.md`
- Scorecard: `model-scorecard.csv`
- Recommendations: `recommendations.md`
- Environment facts: `environment-summary.md`
- Runner/server facts: `runner-log-facts.md`

## Test results

| Test | Mode | Category | State | Sample | Ctx | Predict | Eval tok | Visible tok/s | TTFT answer ms | Response chars | Thinking chars |
|---|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|
'''
for r in rows:
    summary += f"| {r.get('test','')} | {r.get('mode','')} | {r.get('category','')} | {r.get('result_state','')} | {r.get('sample_status','')} | {r.get('ctx','')} | {r.get('predict','')} | {r.get('eval_tokens','')} | {r.get('visible_answer_tps','')} | {r.get('ttft_answer_ms','')} | {r.get('response_chars','')} | {r.get('thinking_chars','')} |\n"
(rd/'summary.md').write_text(summary)
term=f'''============================================================
RTX3090 OLLAMA TEST SUMMARY
Model   : {args.model}
Role    : {args.role}
Mode    : {args.mode}
Status  : {status}
FirstTTFT: {first_s}
FirstReqLoad: {load_s}
WarmTTFT: {warm_ttft_s}
Visible : {vis_s}
Residency: {residency}
VRAM    : {vram_s}
Class   : {', '.join(classifications) if classifications else 'NONE'}
Settings: {settings_sh}
Scorecard: {score}
============================================================
'''
(rd/'terminal-summary.txt').write_text(term)
print(term)
