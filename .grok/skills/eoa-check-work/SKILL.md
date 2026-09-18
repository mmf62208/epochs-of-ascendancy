---
name: eoa-check-work
description: >
  Adversarial verify the last EOA change on the shipped path. Use after a
  feature, Maginot/UI/save/map fix, or when the user runs /check-work or
  /eoa-check-work. Run --quick, the relevant headless harness, and a local
  review. Greps alone are not ready.
---

# EOA check-work

Prove the last change on **shipped** code. Do not add a dual package to make a gate green.

## Do this now

1. Read `docs/GAME_STATUS_SNAPSHOT.md` (one screen). If the change disagrees with SNAPSHOT, SNAPSHOT wins or the doc must be updated because truth changed.
2. Identify the **one** product/test that must fail if this work is reverted. Prefer `tools/map_generation/lib/*_product.py` + `tools/map_generation/tests/test_*.py`.
3. Iterate:

```bash
tools/eoa_full_test_gates.sh --quick
```

4. If the change touches pick, march, assault, occupy, save, or F5 input, also run the matching headless (always `tools/run_godot.sh`):

```bash
# living unit loop
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateUnitOrderLoopTest.gd

# multi-front assault
tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessWorldAccurateMultiFrontAssaultTest.gd
```

Claim ready only on **`RESULT=PASS`** / **`PASS (failures=0)`**, not product greps.

5. Hunt regressions on the Maginot path: GER `710173` → FRA `710739`; `start_land_battle` on click (never `execute_province_assault`); hang-class (no 3520 BFS on G/L; no full inspector rebuild on pick).
6. Summarize: what ran, what passed, what was not verified (graphical F5, M6 notes, 30fps).

Soft 30fps FAIL is honest, not a gate. M6 human notes are not automated.
