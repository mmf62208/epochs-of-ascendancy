# STARTUP-GUARD — test-only Begin→post-dismiss diagnostic

**MERGE: HOLD.** Test / harness / this note only. **Not** a product fix.
**Not** a fourth tooltip slice. Does **not** touch `grok/tooltip-p1` or PR **#164**.

## What this is

A **separate** windowed guard that makes GER 1936 **Begin → overlay gone →
optional controlled resize** measurable. It records monotonic timestamps,
window/viewport size+mode, data identities, presentation diagnostics, and
actual viewport PNGs with metadata.

It **never** claims live-startup **PASS**. Visual zeros / mesh counts are
**not** pixel proof. A title-still-visible frame is **not** labeled
`post_dismiss`.

## Base / branch

| Item | Value |
|------|--------|
| Trusted main (base) | `7d7a0b856efba61c04364f123b6a7f37c3e310c8` |
| Branch | `cursor/startup-guard-1-5dbe` (distinct from `grok/tooltip-p1`) |
| Scope | `scripts/core/WindowedStartupGuardTest.gd`, `tools/eoa_startup_guard.sh`, inventory product+unittest, this doc |
| Gates | **Not** added to `tools/eoa_full_test_gates.sh` / `project.godot` |

## Reproducible command (cloud, one run)

```bash
# Isolated XDG + saves are created under $EOA_STARTUP_GUARD_OUT/xdg
# Import is a separate headless process (timeout 1500s), then ONE windowed
# xvfb process (timeout 600s). Launch only via tools/run_godot.sh.
# Prefer engine 4.7.1.stable.official.a13da4feb.

EOA_STARTUP_GUARD_OUT=/tmp/eoa-startup-guard tools/eoa_startup_guard.sh
```

Runtime flags the wrapper sets:

- `EOA_SMOKE_AUTO_BEGIN=0` — real `handle_live_begin`, not the smoke hatch
- `EOA_SMOKE_ADVANCE_PAST_PLUS6=0`
- `EOA_SKIP_TITLE` unset
- `--resolution 1280x800 --position 0,0` **without** `--maximized`
- xvfb `-screen 0 1280x800x24`
- After overlay-gone: controlled `window_set_size(860,550)` **inside the same process**

## Labels (do not collapse)

| Label | Meaning |
|-------|---------|
| `DATA_INVARIANT=PASS/FAIL` | Player/date/province/unit identities/stockpile through real Begin |
| `PRESENTATION=DIAGNOSTIC` | Camera, mesh/in-view counts, chips, window, PNG observations |
| `LIVE_BLANK=REPRODUCED/NOT_REPRODUCED/INCOMPLETE` | Whether this fixture’s post-dismiss **image** looked uniformly light after a varied setup |
| `FIXTURE=PASS/FAIL` | Harness completed and did not mislabel a title-up shot as post-dismiss |
| `LIVE_STARTUP=NOT_CLAIMED` | **Always.** xvfb ≠ live desktop pair |

## Coverage the pair had that this run does not

- Live ComputerUse / desktop WM (pair started 1280×800 **maximized** and later ~860×550)
- PR tip `26797ec9` (this guard is on trusted main only)
- Seed-hash suite `20fe9063…` (not rerun; inventory is static board files only)

If the blank view does not appear here, the honest result is
**NOT REPRODUCED** or **INCOMPLETE**, never live-startup PASS.

## Static inventory (no extra Godot)

```bash
python3 -m unittest tools.map_generation.tests.test_startup_guard_inventory -v
```

Reports SHA-256 of shipped `world_accurate` key files and confirms **3596**
province IDs including Berlin `710300`. Garrison **575** is runtime-only
(`seed_1936_start_garrisons`).
