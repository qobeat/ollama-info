# Reference result review

The supplied v1.10 run showed that all generation rows for six tested models returned HTTP 400, leaving FirstTTFT, WarmTTFT, visible speed, and context-pressure evidence unavailable. The root cause was invalid request payload typing for `think`. v1.10 still emitted recommendations and settings despite zero valid generation rows.

v1.11 repair policy:

- serialize `think=false` as JSON boolean false;
- capture API error body and root error;
- classify all-row API failures as `TOOL_FAILURE`;
- emit `NO_MODEL_RANKING` when no valid generation rows exist;
- suppress best-model recommendations unless `ranking_allowed=1`;
- mark settings confidence and context validation explicitly.
