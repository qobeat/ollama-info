# REFLECTION v1.7.1

v1.7 implemented the main plan, but real user results exposed an important distinction that the original acceptance tests did not cover: a model can be absent before a run while another large model is already resident, and the tested model can end up partially offloaded. Treating that as verified cold/full-GPU execution is wrong.

v1.7.1 fixes the evidence semantics instead of changing the benchmark shape. This preserves the v1.7 feature set while making reports safer for ADOS-style decision-making. The main remaining gap is workload coverage: the attached tests are generation-only and concurrency=1, so they validate single-request local model behavior but not MCP/agentic tail latency, RAG embedding throughput, or JSON/tool-call robustness.
