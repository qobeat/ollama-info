# Semantic replay report

| Replay case | Expected behavior | Observed |
|---|---|---|
| User runs valid generation model | Payload uses typed JSON; decision-grade summary can recommend model | PASS under fake success harness |
| User hits API/tool failure | Tool reports root error and suppresses winner/settings-best claims | PASS under fake failure harness |
| User compares multiple models | Aggregate recommendations use only `ranking_allowed=1` scorecards | PASS under fake aggregate harness |
| User reads README | Goal, objectives, commands, modes, settings confidence, and troubleshooting are explained | PASS by documentation review |
