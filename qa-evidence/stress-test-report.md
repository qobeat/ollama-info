# Stress test report

| Stress case | Expected | Result |
|---|---|---|
| Payload typing | `think=false` must be JSON boolean | PASS |
| API 400 path | root error captured and surfaced | PASS |
| All-row failure path | `TOOL_FAILURE`, nonzero exit, no recommendations | PASS |
| Aggregate success path | aggregate scorecard and recommendations emitted from decision-grade rows | PASS |
| Package hygiene | no pycache, pyc, nested ZIPs, runtime runs | PASS |
