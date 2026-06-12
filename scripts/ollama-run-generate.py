#!/usr/bin/env python3
"""Run one Ollama /api/generate request and materialize stream evidence.

v1.13 writes both raw NDJSON and joined answer/thinking text so downstream
capability checks do not depend on line-oriented stream chunks.
"""
import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--base-url', required=True)
p.add_argument('--payload', required=True)
p.add_argument('--raw', required=True)
p.add_argument('--metrics', required=True)
p.add_argument('--http-file', required=True)
p.add_argument('--stderr-file', required=True)
p.add_argument('--answer-file')
p.add_argument('--thinking-file')
p.add_argument('--answer-preview-file')
p.add_argument('--timeout', type=float, default=600)
args = p.parse_args()

with open(args.payload, 'rb') as f:
    data = f.read()

req = urllib.request.Request(
    args.base_url.rstrip('/') + '/api/generate',
    data=data,
    headers={'Content-Type': 'application/json', 'Accept': 'application/json'},
    method='POST',
)
start = time.monotonic()
first_any = None
first_answer = None
first_thinking = None
answer_parts = []
thinking_parts = []
chunks = 0
last = {}
http = 0
err = ''
error_body = ''
api_error = ''

def _message_text(obj, key):
    msg = obj.get('message') if isinstance(obj.get('message'), dict) else {}
    return obj.get(key) or msg.get('content' if key == 'response' else key) or ''

try:
    with urllib.request.urlopen(req, timeout=args.timeout) as resp, open(args.raw, 'w', encoding='utf-8') as raw:
        http = int(getattr(resp, 'status', 200) or 200)
        for bline in resp:
            now = time.monotonic()
            line = bline.decode('utf-8', errors='replace').strip()
            if not line:
                continue
            chunks += 1
            if first_any is None:
                first_any = now
            try:
                obj = json.loads(line)
            except Exception:
                obj = {'_parse_error': True, 'raw': line}
            raw.write(json.dumps({'t_rel_ms': round((now - start) * 1000, 3), 'chunk': obj}, ensure_ascii=False) + '\n')
            ans = _message_text(obj, 'response')
            th = _message_text(obj, 'thinking')
            if ans:
                answer_parts.append(str(ans))
                if first_answer is None:
                    first_answer = now
            if th:
                thinking_parts.append(str(th))
                if first_thinking is None:
                    first_thinking = now
            last = obj
except urllib.error.HTTPError as e:
    http = int(e.code or 0)
    try:
        body = e.read().decode('utf-8', errors='replace')
    except Exception:
        body = ''
    error_body = body
    try:
        parsed = json.loads(body) if body else {}
        api_error = str(parsed.get('error') or parsed.get('message') or '')
    except Exception:
        api_error = body.strip()[:500]
    Path(args.raw).write_text(body, encoding='utf-8', errors='ignore')
    err = str(e)
except Exception as e:  # network/timeout/serialization failure
    err = repr(e)

end = time.monotonic()
answer_text = ''.join(answer_parts)
thinking_text = ''.join(thinking_parts)

for path, text in ((args.answer_file, answer_text), (args.thinking_file, thinking_text)):
    if path:
        Path(path).write_text(text, encoding='utf-8', errors='ignore')
if args.answer_preview_file:
    preview = answer_text if len(answer_text) <= 4000 else answer_text[:4000] + '\n\n[truncated preview]\n'
    Path(args.answer_preview_file).write_text(preview, encoding='utf-8', errors='ignore')

Path(args.http_file).write_text(str(http), encoding='utf-8')
if err:
    Path(args.stderr_file).write_text(err + '\n', encoding='utf-8')
else:
    Path(args.stderr_file).write_text('', encoding='utf-8')

def ns_to_s(v):
    try:
        return float(v) / 1e9
    except Exception:
        return 0.0

try:
    eval_count = int(last.get('eval_count') or 0)
except Exception:
    eval_count = 0
eval_s = ns_to_s(last.get('eval_duration'))
try:
    prompt_eval_count = int(last.get('prompt_eval_count') or 0)
except Exception:
    prompt_eval_count = 0
prompt_eval_s = ns_to_s(last.get('prompt_eval_duration'))
load_s = ns_to_s(last.get('load_duration'))
total_s = ns_to_s(last.get('total_duration')) or (end - start)
response_chars = len(answer_text)
thinking_chars = len(thinking_text)
metrics = {
    'http_code': http,
    'chunks': chunks,
    'wall_s': end - start,
    'ttft_any_ms': None if first_any is None else (first_any - start) * 1000,
    'ttft_answer_ms': None if first_answer is None else (first_answer - start) * 1000,
    'ttft_thinking_ms': None if first_thinking is None else (first_thinking - start) * 1000,
    'response_chars': response_chars,
    'thinking_chars': thinking_chars,
    'thinking_only': bool(response_chars == 0 and thinking_chars > 0),
    'prompt_eval_tokens': prompt_eval_count,
    'prompt_eval_s': prompt_eval_s,
    'prompt_eval_tps': (prompt_eval_count / prompt_eval_s) if prompt_eval_s > 0 else None,
    'eval_tokens': eval_count,
    'eval_s': eval_s,
    'decode_tps_raw': (eval_count / eval_s) if eval_s > 0 else None,
    'visible_answer_tps': (eval_count / eval_s) if eval_s > 0 and response_chars > 0 else None,
    'load_s': load_s,
    'total_s': total_s,
    'done_reason': last.get('done_reason') or last.get('done') or '',
    'last': last,
    'error': err,
    'api_error': api_error,
    'error_body': error_body[:2000] if error_body else '',
    'answer_file': args.answer_file or '',
    'thinking_file': args.thinking_file or '',
}
Path(args.metrics).write_text(json.dumps(metrics, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

sys.exit(0 if http and http < 400 and not err else 1)
