# REFLECTION v1.9

The package now better matches the user workflow. The user issued one multi-model command and expected one comparable evidence package; the wrapper now creates one aggregate archive with sub-runs rather than scattering per-model ZIPs. The default ADOS capability profile is also reported correctly: coding, essay, and internet-access rows are capability rows, not missing throughput rows.

The README is now an operating manual rather than a release note. It explains what each command does, when to use it, and how to interpret fields such as FirstReqLoad, WarmTTFT, Residency, Visible, Telemetry, VRAM, Power, PCIe, and sample states.

Compaction improved in two ways: package evidence now uses one current ledger and stable report filenames, and runtime output avoids scratch sidecars plus duplicate summary embedding. Raw API and telemetry files remain because they are necessary evidence rather than duplication.

Remaining limitations:

- The default three-prompt profile is a capability and operational smoke profile, not a full model-quality benchmark.
- The supplied results do not include concurrency, long-context perf profile, embedding, or JSON/tool-call reliability rows for every model.
- Real workload recommendations should be revisited after `--profile perf`, concurrency, and embedding runs are available for the same candidate set.
