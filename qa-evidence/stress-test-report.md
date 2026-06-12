# Stress test report v1.11 final

Stress condition: context-pressure rows return HTTP 200 but only one generated token.

Expected behavior:

- row is not valid context proof;
- visible_tps_avg excludes the row;
- context_validated remains 0;
- settings confidence is not HIGH_CONFIRMED;
- aggregate rankings cannot be inflated by one-token context throughput.

Observed in simulation: PASS.
