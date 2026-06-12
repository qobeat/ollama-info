# v1.11 final reference test review

The new v1.11 test run proved that typed `think:false` fixed the earlier HTTP 400 defect, but exposed a final measurement-integrity defect: context-pressure rows with `eval_tokens=1` were counted as valid and produced impossible visible speed values around 1,000,000 tok/s.

Final v1.11 fixes this by requiring context-pressure rows to meet minimum output gates before they validate context settings:

```text
eval_tokens >= 128
response_chars >= 120
```

Rows below the gate are classified as `SHORT_CONTEXT_SAMPLE` / `CONTEXT_PRESSURE_INCONCLUSIVE`, are excluded from visible speed averages, cannot set `context_validated=1`, and cannot produce `HIGH_CONFIRMED` settings.
