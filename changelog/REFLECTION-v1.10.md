# Reflection v1.10

v1.10 is a correction and capability expansion release. It prioritizes decision utility: model selection and applyable performance settings. The implementation front-loads reversible diagnostics and only produces applyable settings as a script the user can review before execution. It avoids claiming that measured load duration is disk-cold load; it treats first-request load as an operational metric and recommends resident workflows when warm latency is strong but first load is slow.

Known limitation: live RTX 3090 throughput is not measured inside the build sandbox. Behavior verification uses a deterministic fake Ollama/NVIDIA harness. The actual performance recommendations are produced by running the package on the user's host.
