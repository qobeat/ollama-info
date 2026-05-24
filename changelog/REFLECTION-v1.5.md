# REFLECTION v1.5

The most important usability change is display separation: timestamped collector progress first, then a plain final summary. This preserves incident-review chronology without making the human summary noisy.

The package is still Bash-first and tool-light, but it now has a stricter Bash 5.2+ contract and more shared helpers. A larger future refactor could split the long test runner into smaller sourced modules, but v1.5 intentionally keeps changes bounded to avoid destabilizing the benchmark path.
