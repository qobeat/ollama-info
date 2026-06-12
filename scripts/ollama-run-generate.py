#!/usr/bin/env python3
import argparse, json, time, urllib.request, urllib.error, sys

p = argparse.ArgumentParser()
p.add_argument('--base-url', required=True)
p.add_argument('--payload', required=True)
p.add_argument('--raw', required=True)
p.add_argument('--metrics', required=True)
p.add_argument('--http-file', required=True)
p.add_argument('--stderr-file', required=True)
p.add_argument('--timeout', type=float, default=600)
args = p.parse_args()

with open(args.payload, 'rb') as f:
    data = f.read()
req = urllib.request.Request(args.base_url.rstrip('/') + '/api/generate', data=data, headers={'Content-Type':'application/json','Accept':'application/json'}, method='POST')
start = time.monotonic()
first_any = None
first_answer = None
first_thinking = None
response_chars = 0
thinking_chars = 0
chunks = 0
last = {}
http = 0
err = ''
error_body = ''
api_error = ''
try:
    with urllib.request.urlopen(req, timeout=args.timeout) as resp, open(args.raw, 'w', encoding='utf-8') as raw:
        http = getattr(resp, 'status', 200)
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
            raw.write(json.dumps({'t_rel_ms': round((now-start)*1000,3), 'chunk': obj}, ensure_ascii=False) + '\n')
            # Ollama /api/generate chunks commonly use response. Thinking models may emit thinking.
            ans = obj.get('response') or obj.get('message', {}).get('content') or ''
            th = obj.get('thinking') or obj.get('message', {}).get('thinking') or ''
            if ans:
                response_chars += len(ans)
                if first_answer is None:
                    first_answer = now
            if th:
                thinking_chars += len(th)
                if first_thinking is None:
                    first_thinking = now
            last = obj
except urllib.error.HTTPError as e:
    http = e.code
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
    with open(args.raw, 'w', encoding='utf-8') as raw:
        raw.write(body)
    err = str(e)
except Exception as e:
    err = repr(e)
end = time.monotonic()
with open(args.http_file, 'w') as f:
    f.write(str(http))
with open(args.stderr_file, 'w') as f:
    if err:
        f.write(err + '\n')

def ns_to_s(v):
    try: return float(v)/1e9
    except Exception: return 0.0

eval_count = int(last.get('eval_count') or 0)
eval_s = ns_to_s(last.get('eval_duration'))
prompt_eval_count = int(last.get('prompt_eval_count') or 0)
prompt_eval_s = ns_to_s(last.get('prompt_eval_duration'))
load_s = ns_to_s(last.get('load_duration'))
total_s = ns_to_s(last.get('total_duration')) or (end-start)
metrics = {
    'http_code': http,
    'chunks': chunks,
    'wall_s': end-start,
    'ttft_any_ms': None if first_any is None else (first_any-start)*1000,
    'ttft_answer_ms': None if first_answer is None else (first_answer-start)*1000,
    'ttft_thinking_ms': None if first_thinking is None else (first_thinking-start)*1000,
    'response_chars': response_chars,
    'thinking_chars': thinking_chars,
    'thinking_only': bool(response_chars == 0 and thinking_chars > 0),
    'prompt_eval_tokens': prompt_eval_count,
    'prompt_eval_s': prompt_eval_s,
    'prompt_eval_tps': (prompt_eval_count/prompt_eval_s) if prompt_eval_s > 0 else None,
    'eval_tokens': eval_count,
    'eval_s': eval_s,
    'decode_tps_raw': (eval_count/eval_s) if eval_s > 0 else None,
    'visible_answer_tps': ((eval_count/eval_s) if eval_s > 0 and response_chars > 0 else None),
    'load_s': load_s,
    'total_s': total_s,
    'done_reason': last.get('done_reason') or last.get('done') or '',
    'last': last,
    'error': err,
    'api_error': api_error,
    'error_body': error_body[:2000] if error_body else '',
}
with open(args.metrics, 'w', encoding='utf-8') as f:
    json.dump(metrics, f, indent=2, ensure_ascii=False)

sys.exit(0 if http and http < 400 and not err else 1)
