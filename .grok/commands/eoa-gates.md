---
description: Run EOA full-test machine gates (world_accurate board, HOI matrix, pick/assault, save)
---

# /eoa-gates

Run the Epochs of Ascendancy full-test gate script and report results.

## Do this now

1. From the repo root `/home/mikef/Projects/epochs-of-ascendancy` (or the current workspace root if it is this repo), run:

```bash
tools/eoa_full_test_gates.sh --log /tmp/eoa-gates-run
```

If Godot is unavailable or the user asked for a quick check:

```bash
tools/eoa_full_test_gates.sh --quick --log /tmp/eoa-gates-run
```

2. Read the command exit code and any `FAIL` lines.
3. If failures occurred, open the matching log under `/tmp/eoa-gates-run/` (or the `--log` dir), fix the **shipped** product/test, re-run until green.
4. Summarize for the user: which steps passed, which failed, and next fix if any.

Constraints: never renumber `world_full` IDs; soft 30fps FAIL is not a gate; M6 human notes are not automated.
