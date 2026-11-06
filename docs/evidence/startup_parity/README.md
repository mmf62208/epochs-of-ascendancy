# STARTUP-PARITY harness

Test-only. Not a product fix. Never claims live-startup PASS.

## Run

```bash
EOA_STARTUP_PARITY_OUT=/tmp/eoa-startup-parity tools/eoa_startup_parity.sh
```

Launch Godot only via `tools/run_godot.sh` (4.7.1). Needs xvfb + xfwm4. Output goes to `$EOA_STARTUP_PARITY_OUT` (default `/tmp/eoa-startup-parity`).

`--quick` does **not** run the windowed wrapper. It does run `test_startup_parity_inventory` (static 3596 / Berlin `710300` file hashes).

## What it checks

1. **Inventory (no Godot).** Shipped `world_accurate` files: 3596 province IDs, Berlin `710300` present, SHA-256 of the five key JSONs.
2. **Empty-board garrisons (headless).** `CampaignLoopTestBoot` + `seed_1936_start_garrisons`: **targets 575 = placed + skipped_occupied**. Empty board places 575 / skip 0. One occupied Berlin hex skips 1.
3. **Seed-only (headless).** `EOA_PERF4_SEED_ONLY=1` on `HeadlessPerf4LiveMultiAiDayTest` recomputes md5 of the `multi_ai_decisions=` line. Expect prefix `20fe9063`. If the hash moved, stop — do not retarget the seed.
4. **Live fixture (windowed).** TestScenario living title → `LivingTitleBoot.handle_live_begin` (GER 1936). Same board as (2); live placed count is below 575 when OOB land already occupies border/capital hexes. Identity is still **targets = placed + skipped_occupied**.
5. **Viewport shrink.** Launch `--resolution 1280x800 --position 0,0 --maximized`. After Begin, harness sets **window + `root.size`** to 860×550 and requires `get_viewport().get_visible_rect().size` to change (`VIEWPORT_PARITY=PASS`). Title ALWAYS_ON_TOP is observed from product code (on while the title is up, off at teardown).
6. **Post-Begin blank.** Scored only after (4) and (5) hold. Diagnostic; xvfb + xfwm4 + llvmpipe is not live desktop GPU/WM.

Windowed run is not on the official `--quick` gate.

## STARTUP-BLANK (pointer vs Enter)

Extends this same harness (`WindowedStartupParityTest.gd` + this wrapper). Default path above is unchanged.

```bash
# pointer-Begin + Enter-Begin + pointer mutant (Xvfb 1920×1200, un-maximize to 1280×800)
EOA_STARTUP_BLANK=1 EOA_STARTUP_PARITY_OUT=/tmp/eoa-startup-blank tools/eoa_startup_parity.sh
# same:
tools/eoa_startup_blank.sh
```

`EOA_STARTUP_BLANK_BEGIN=pointer|enter` runs one variant. Mutant: `EOA_STARTUP_BLANK_MUTANT=1`. Soak: `EOA_STARTUP_BLANK_SOAK_S` (wrapper default 120s). See `docs/evidence/startup_blank/`.
