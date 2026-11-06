# STARTUP-PARITY — test-only Begin→viewport diagnostic

**MERGE: HOLD.** Test / harness / this note only. **Not** a product fix.
Does **not** touch PR **#164** or PR **#165**.

## What this is

A **new** branch (not `cursor/startup-guard-1-5dbe`) that makes two
previously unverified gaps measurable:

1. **Fixture/baseline parity.** Why a prior xvfb guard saw **535** `garrison_1936`
   chips against the required empty-board **575**. Same `world_accurate` files
   (3596 IDs, Berlin `710300`) on both the empty-board seed and the live
   TestScenario living-title → Begin path. Occupied OOB land hexes are skipped.
2. **True viewport parity.** Live launch flags `--resolution 1280x800
   --position 0,0 --maximized`, title ALWAYS_ON_TOP, then a post-Begin shrink
   that actually changes `get_viewport().get_visible_rect().size` (not only
   `DisplayServer.window_get_size`). Xvfb **+ xfwm4**.

Only after both hold does the harness classify post-Begin blank.

It **never** claims live-startup **PASS**.

## Reproducible command

```bash
EOA_STARTUP_PARITY_OUT=/tmp/eoa-startup-parity tools/eoa_startup_parity.sh
```

## Cited run

`docs/evidence/startup_parity/run-7d7a0b85-xvfb/` (also `/opt/cursor/artifacts/startup-parity/`).

| Label | Value |
|-------|-------|
| `DATA_INVARIANT` | PASS |
| `GARRISON_SKIP` | PASS (live 535 + skip 40 = empty-board **575** targets) |
| `VIEWPORT_PARITY` | PASS (visible_rect 1280×800 → **860×550**) |
| `LIVE_BLANK` | **NOT_REPRODUCED** |
| `LIVE_STARTUP` | **NOT_CLAIMED** |

Seed md5 **`20fe9063de285f19d4f9b8a105abfd31`**. Engine `4.7.1.stable.official.a13da4feb`. xvfb + xfwm4; Vulkan missing → OpenGL/llvmpipe.

**No live-startup PASS. No product fix.** Full numbers in `run-7d7a0b85-xvfb/RESULT.md`.

`--quick` on this tip: **ALL PASSED**. map_qc NE **0.9853**.
