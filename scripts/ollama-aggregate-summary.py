#!/usr/bin/env python3
"""Build aggregate model scorecard and table summary for ollama-info v1.13."""
import argparse
import csv
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('agg_dir')
p.add_argument('--mode', default='test')
args = p.parse_args()
agg = Path(args.agg_dir)
rows = []
for score in sorted(agg.glob('runs/run-*/model-scorecard.csv')):
    with score.open(newline='', encoding='utf-8') as f:
        rr = list(csv.DictReader(f))
        if rr:
            r = rr[0]
            r['scorecard_path'] = str(score)
            rows.append(r)

base_cols = [
    'model','role','status','decision_grade','mode','residency','classifications',
    'coding_gate','essay_gate','internet_boundary_gate','capability_required_pass',
    'valid_generation_rows','valid_capability_rows','valid_context_rows','short_context_rows','api_error_rows','root_error',
    'preload_wait_s','model_ready_s','first_ttft_ms','first_load_s','warm_ttft_ms_avg','visible_tps_avg','vram_pct',
    'metadata_context_length','min_context_required','context_65k_attempted','context_65k_skipped','hermes_65k_context',
    'recommended_context','context_validated','settings_confidence','keep_alive','max_loaded_models','num_parallel','flash_attention','kv_cache_type',
    'ranking_allowed','scorecard_path'
]
cols = base_cols + sorted({k for r in rows for k in r if k not in base_cols})
with (agg / 'model-scorecard.csv').open('w', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    w.writerows(rows)

def num(r, k, default=None):
    try:
        v = r.get(k, '')
        if v in ('', None, 'N/A', 'NA'):
            return default
        return float(v)
    except Exception:
        return default

def has(r, text):
    return text in (r.get('classifications') or '')

def is_pass(r):
    return r.get('role') == 'generate' and r.get('status','').startswith('PASS') and r.get('ranking_allowed') in ('1','true','True')

def has_perf(r):
    return num(r, 'warm_ttft_ms_avg') is not None or num(r, 'visible_tps_avg') is not None

elig = [r for r in rows if is_pass(r)]
perf_rows = [r for r in rows if has_perf(r)]

def lane_score(r, lane):
    tps = num(r, 'visible_tps_avg', 0) or 0
    ttft = num(r, 'warm_ttft_ms_avg', 999999) or 999999
    vram = num(r, 'vram_pct', 999) or 999
    name = (r.get('model') or '').lower()
    score = tps - ttft / 1000 - vram / 10
    if 'gpt-oss' in name:
        score -= 20
    if lane in ('coding_default','ados_coding_repair'):
        if 'coder' in name:
            score += 70
        if 'qwen3:' in name:
            score += 10
    elif lane in ('chat_default','hermes_fallback_4k'):
        if 'coder' in name:
            score -= 25
        if 'vl' in name:
            score += 8
        if 'llama' in name:
            score += 7
    elif lane == 'ados_default':
        if 'coder' in name:
            score -= 18
        if 'qwen3:' in name:
            score += 25
        if 'vl' in name:
            score += 5
    elif lane == 'heavy_reasoning':
        if '27b' in name or '35b' in name or '20b' in name:
            score += 50
        score -= max(0, (ttft - 2000) / 1000)
    return score

def winner(lane, require_hermes=False):
    c = [r for r in elig if r.get('hermes_65k_context') == 'PASS'] if require_hermes else list(elig)
    if not c:
        return None
    return sorted(c, key=lambda r: lane_score(r, lane), reverse=True)[0]

lanes = [
    ('OpenCode/Cursor coding', 'coding_default', False),
    ('Chat default', 'chat_default', False),
    ('Hermes main chat required context', 'hermes_fallback_4k', True),
    ('Hermes fallback 4K', 'hermes_fallback_4k', False),
    ('ADOS default', 'ados_default', False),
    ('ADOS coding repair', 'ados_coding_repair', False),
    ('Heavy reasoning', 'heavy_reasoning', False),
]

summary = []
summary.append('================================================================================')
summary.append('RTX3090 OLLAMA AGGREGATE SUMMARY')
summary.append(f'Models: {len(rows)}    Mode: {args.mode}')
summary.append('================================================================================')

if perf_rows:
    summary.append('[1] Balanced Decision Ranking' if elig else '[1] Balanced Evidence Table (no decision-grade winners)')
    summary.append('| Rank | Model | Warm TTFT | TPS | VRAM | Preload wait | Context gate | Decision | Gates | Main caveat |')
    summary.append('|---:|---|---:|---:|---:|---:|---|---|---|---|')
    ranked = sorted(rows, key=lambda r: (0 if is_pass(r) else 1, -(lane_score(r,'ados_default'))))
    for i, r in enumerate(ranked, 1):
        caveat = []
        if r.get('hermes_65k_context') != 'PASS':
            caveat.append('required context not confirmed')
        if r.get('settings_confidence') != 'HIGH_CONTEXT_CONFIRMED':
            caveat.append(r.get('settings_confidence',''))
        if has(r, 'CPU_GPU_OFFLOAD_RISK'):
            caveat.append('offload')
        if 'gpt-oss' in (r.get('model') or '') and (num(r,'warm_ttft_ms_avg',0) or 0) > 2000:
            caveat.append('slow answer TTFT')
        gates = f"C={r.get('coding_gate','?')} E={r.get('essay_gate','?')} I={r.get('internet_boundary_gate','?')}"
        summary.append(f"| {i} | {r.get('model','')} | {r.get('warm_ttft_ms_avg','')} ms | {r.get('visible_tps_avg','')} | {r.get('vram_pct','')}% | {r.get('preload_wait_s','')}s | {r.get('hermes_65k_context','')} | {r.get('status','')} | {gates} | {', '.join([c for c in caveat if c]) or 'none'} |")
    summary.append('')
    summary.append('[1a] Fastest Warm TTFT')
    summary.append('| Rank | Model | Warm TTFT | TPS | Decision-grade |')
    summary.append('|---:|---|---:|---:|---:|')
    for i, r in enumerate(sorted([r for r in rows if num(r,'warm_ttft_ms_avg') is not None], key=lambda r: num(r,'warm_ttft_ms_avg', 999999))[:10], 1):
        summary.append(f"| {i} | {r.get('model','')} | {r.get('warm_ttft_ms_avg','')} ms | {r.get('visible_tps_avg','')} | {r.get('decision_grade','')} |")
    summary.append('')
    summary.append('[1b] Highest Visible Throughput')
    summary.append('| Rank | Model | TPS | Warm TTFT | Decision-grade |')
    summary.append('|---:|---|---:|---:|---:|')
    for i, r in enumerate(sorted([r for r in rows if num(r,'visible_tps_avg') is not None], key=lambda r: num(r,'visible_tps_avg', -1), reverse=True)[:10], 1):
        summary.append(f"| {i} | {r.get('model','')} | {r.get('visible_tps_avg','')} | {r.get('warm_ttft_ms_avg','')} ms | {r.get('decision_grade','')} |")
else:
    summary.append('[1] Context-Only Gate Summary')
    summary.append('| Model | Metadata ctx | Runtime attempted | Required context | Hermes/main-chat | Status |')
    summary.append('|---|---:|---:|---|---|---|')
    for r in rows:
        summary.append(f"| {r.get('model','')} | {r.get('metadata_context_length','unknown') or 'unknown'} | {r.get('context_65k_attempted','0')} | {r.get('min_context_required','65536')} | {r.get('hermes_65k_context','NOT_TESTED')} | {r.get('status','')} |")
summary.append('')

summary.append('[2] Use-Case Winners')
summary.append('| Use case | Winner | Confidence | Reason |')
summary.append('|---|---|---|---|')
rec_lines = ['# Aggregate recommendations','']
for label, lane, hermes_required in lanes:
    w = winner(lane, hermes_required)
    if w is None:
        if hermes_required:
            summary.append(f'| {label} | NONE CONFIRMED | LOW | required context gate has not passed for any tested model |')
            rec_lines.append(f'- **{label}:** NONE CONFIRMED. Run `ollama context-test <models> --min-context 65536`.')
        else:
            summary.append(f'| {label} | NONE | LOW | no decision-grade candidate |')
            rec_lines.append(f'- **{label}:** no decision-grade candidate because category gates or output evidence did not pass.')
    else:
        conf = 'HIGH' if w.get('settings_confidence') == 'HIGH_CONTEXT_CONFIRMED' else 'MEDIUM'
        reason = f"TTFT={w.get('warm_ttft_ms_avg','')}ms TPS={w.get('visible_tps_avg','')} VRAM={w.get('vram_pct','')}% gates=C:{w.get('coding_gate','?')} E:{w.get('essay_gate','?')} I:{w.get('internet_boundary_gate','?')}"
        if hermes_required:
            reason += '; required context PASS'
        summary.append(f"| {label} | {w.get('model')} | {conf} | {reason} |")
        rec_lines.append(f"- **{label}:** `{w.get('model')}` ({reason}).")
summary.append('')

summary.append('[3] Hermes Required-Context Gate')
summary.append('| Model | Metadata ctx | Runtime attempted | Skipped | Gate | Hermes main chat |')
summary.append('|---|---:|---:|---:|---|---|')
for r in rows:
    h = r.get('hermes_65k_context','NOT_TESTED')
    summary.append(f"| {r.get('model','')} | {r.get('metadata_context_length','unknown') or 'unknown'} | {r.get('context_65k_attempted','0')} | {r.get('context_65k_skipped','0')} | {h} | {'CONFIRMED' if h == 'PASS' else 'NOT CONFIRMED'} |")
summary.append('')

summary.append('[4] Next Required Tests')
summary.append('| Goal | Command |')
summary.append('|---|---|')
models = ' '.join(r.get('model','') for r in rows if r.get('role') == 'generate')
if models:
    summary.append(f'| Confirm Hermes/main-chat context | `ollama context-test {models} --min-context 65536` |')
summary.append('| Confirm full diagnostics | `ollama test --full <models>` |')
summary.append('| Confirm coding quality | `ollama test qwen2.5-coder:7b qwen2.5-coder:14b --profile coding-quality` |')
summary.append('| Confirm vision with image evidence | `ollama vision-test qwen2.5vl:7b --image /path/to/test-image.png` |')
summary.append('================================================================================')

(agg / 'aggregate-terminal-summary.txt').write_text('\n'.join(summary) + '\n', encoding='utf-8')
rec_lines.append('')
rec_lines.append('## Hermes required-context gate')
rec_lines.append('A model cannot be the Hermes main chat winner until `hermes_65k_context=PASS`; skipped rows do not count as runtime attempts.')
rec_lines.append('')
rec_lines.append('## Vision')
rec_lines.append('Vision is not inferred from text-only runs. Use `ollama vision-test MODEL --image PATH` to collect image evidence.')
rec_lines.append('')
rec_lines.append('Primary applyable settings are in each sub-run `performance-settings.sh`; compare all rows in `model-scorecard.csv`.')
(agg / 'recommendations.md').write_text('\n'.join(rec_lines) + '\n', encoding='utf-8')

out = ['# Performance settings by model','']
for r in rows:
    settings = Path(r['scorecard_path']).parent / 'performance-settings.md'
    if settings.exists():
        out.append(settings.read_text(encoding='utf-8', errors='ignore'))
(agg / 'performance-settings-all.md').write_text('\n\n---\n\n'.join(out), encoding='utf-8')
print('\n'.join(summary))
