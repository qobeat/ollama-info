# REFLECTION v1.4

The package needed a UX reset: the command should be short, safe, and production-like by default. Moving concurrency out of the default path makes the baseline clearer and avoids conflating health checks with stress testing on a 24 GB RTX 3090 running large models.
