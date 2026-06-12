# Review v1.11 final

The previous v1.11 run fixed the fatal HTTP 400 issue but exposed a scoring defect: context-pressure rows with `eval=1` were counted as valid and produced impossible visible speeds such as 1,000,000 tok/s. Those rows proved only that the request returned HTTP 200; they did not validate usable context length, throughput, or settings.

This final v1.11 repair gates context-pressure evidence by minimum output and separates context proof from visible throughput/ranking.
