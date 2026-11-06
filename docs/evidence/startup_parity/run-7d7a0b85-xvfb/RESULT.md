# STARTUP-PARITY one-run result — PARK

**MERGE: HOLD.** Test-only. **Not** a product fix. **Not** live-startup PASS.
Does **not** touch PR **#164** or PR **#165**.

## Identity

| Item | Value |
|------|--------|
| Trusted main (base) | `7d7a0b856efba61c04364f123b6a7f37c3e310c8` |
| Branch | `cursor/startup-parity-41a4` |
| Guard | `WindowedStartupParityTest` on `LivingTitleBoot.handle_live_begin` |
| Empty-board | `HeadlessStartupParityGarrisonTest` via `CampaignLoopTestBoot` |
| Seed | `EOA_PERF4_SEED_ONLY=1` `HeadlessPerf4LiveMultiAiDayTest` |
| Host | cloud xvfb + **xfwm4** (not live desktop / not laptop Play) |

## Reproducible command

```bash
EOA_STARTUP_PARITY_OUT=/tmp/eoa-startup-parity tools/eoa_startup_parity.sh
```

| Runtime | Observed |
|---------|----------|
| Engine binary | `/home/ubuntu/Applications/Godot-4.7.1/godot` |
| `--version` | `4.7.1.stable.official.a13da4feb` |
| Launch | `tools/run_godot.sh --path . --resolution 1280x800 --position 0,0 --maximized -s res://scripts/core/WindowedStartupParityTest.gd` |
| Display | Xvfb `:91` `-screen 0 1280x800x24` + `xfwm4 --replace --compositor=off --sm-client-disable` |
| Renderer | Vulkan surface missing → OpenGL 3 / `llvmpipe (LLVM 20.1.2)` (Mesa 25.2.8) |
| Flags | `EOA_SMOKE_AUTO_BEGIN=0`, `EOA_SMOKE_ADVANCE_PAST_PLUS6=0`, `EOA_SKIP_TITLE` unset |
| Windowed | `RESULT=COMPLETED`, `VIEWPORT_PARITY=PASS` |

## Labels

| Label | Value |
|-------|-------|
| `DATA_INVARIANT` | **PASS** |
| `GARRISON_SKIP` | **PASS** |
| `VIEWPORT_PARITY` | **PASS** |
| `PRESENTATION` | DIAGNOSTIC |
| `LIVE_BLANK` | **NOT_REPRODUCED** |
| `FIXTURE` | **PASS** |
| `LIVE_STARTUP` | **NOT_CLAIMED** |

## Parity 1 — 535 vs 575

**Same board data: YES.** Empty-board seed and live TestScenario (living title → Begin, GER 1936) share 3596 province IDs, Berlin `710300` GER, and `seed_1936_start_garrisons` **targets=575**. Live **places 535** because 40 OOB land hexes already hold scenario formations (`ensure_playable_front_chips` Maginot park + HOI deploy on capitals/borders). Identity `placed + skipped = targets` holds: **535 + 40 = 575**.

| Path | provinces | Berlin 710300 | formations | garrison_1936 | stockpile_fp | notes |
|------|-----------|---------------|------------|---------------|--------------|-------|
| Empty-board `CampaignLoopTestBoot` + `seed(..., true)` | 3596 | GER | 575 (garrisons only) | **575** placed / 0 skip / 575 targets | n/a (no ScenarioLoader stockpiles) | `HeadlessStartupParityGarrisonTest` |
| Empty-board + one GER division at Berlin | 3596 | GER | | **574** + skip 1 = 575 | | skip class proof |
| Live TestScenario title → Begin | 3596 | GER | **828** (`828:636003609`) | **535** / skip 40 / targets **575** | `3210958319` | steel 12000, coal 8000, aluminum 4000, fuel 4000, rubber 2000; unit icons 259 |

Live skip by tag (targets / skipped / placed):

| Tag | targets | skipped | placed |
|-----|---------|---------|--------|
| GER | 98 | 3 | 95 |
| FRA | 121 | 4 | 117 |
| ENG | 187 | 5 | 182 |
| SOV | 34 | 7 | 27 |
| ITA | 29 | 5 | 24 |
| JAP | 14 | 5 | 9 |
| USA | 40 | 6 | 34 |
| POL | 33 | 2 | 31 |
| CZE | 19 | 3 | 16 |
| **sum** | **575** | **40** | **535** |

Sample occupiers: Maginot GER `710173` ← `GER_formation_5`; FRA `710739` ← `FRA_formation_1`; ENG capital `711414` ← `ENG_formation_0`. These are scenario OOB / front-chip parks, not a second dataset.

Seed recomputed (official method, `EOA_PERF4_SEED_ONLY=1`):

`grep -o 'HeadlessPerf4LiveMultiAiDayTest: multi_ai_decisions=.*'` md5 = **`20fe9063de285f19d4f9b8a105abfd31`** (prefix `20fe9063`). Unchanged. Do not retarget.

Static board SHA-256 (no Godot): see `inventory.json`. Province IDs 3596, Berlin present.

## Parity 2 — viewport shrink took effect

Launch flags match the live pair: `--resolution 1280x800 --position 0,0 --maximized`. Title sets ALWAYS_ON_TOP on; teardown clears it. After overlay-gone the harness sets **window + `root.size`** to 860×550 (PR #165 only called `DisplayServer.window_set_size`, so `get_visible_rect` stayed 1280×800).

| Phase | win size | mode | ALWAYS_ON_TOP | `get_visible_rect` | `root.size` |
|-------|----------|------|---------------|--------------------|-------------|
| launch | 1280×800 | maximized | false | **1280×800** | 1280×800 |
| pre_begin (title up) | 1280×776 | maximized | **true** | **1280×776** | 1280×776 |
| post_dismiss | 1280×800 | **windowed** | **false** | **1280×800** | 1280×800 |
| shrink applied | **860×550** | windowed | false | **860×550** | 860×550 |
| post_resize | **860×550** | windowed | false | **860×550** | 860×550 |

WM/flags: Xvfb 1280×800 + **xfwm4** (compositor off) + dbus-launch. `--maximized` reported `mode=maximized`. Title AOT true→false. Clearing AOT dropped mode to `windowed` on this WM (size stayed 1280 because the X screen is already 1280×800). Controlled shrink then changed **both** `DisplayServer.window_get_size` **and** `get_viewport().get_visible_rect().size` 1280×800 → 860×550.

At 860×550, `layout_hides_below_1280=true` (resource chips hide). That is chrome layout, not a stockpile wipe.

## LIVE_BLANK

**NOT_REPRODUCED** after both parities held. Post-dismiss and post-resize PNGs still show a varied political Europe field, unit chips, Berlin owner GER. Sampled RGB is not a pixel oracle (`looks_varied_color=true`).

**Coverage limits (plain):** xvfb + xfwm4 + OpenGL/llvmpipe after Vulkan `VK_KHR_surface` missing ≠ live desktop GPU/WM. One run. Trusted main only.

**No product fix.** Isolated Begin + real viewport shrink did not blank the map. Pair desktop blank remains outside this recipe.

## Gates vs main

`tools/eoa_full_test_gates.sh --quick` on this tip: **ALL PASSED (quick) rc=0**.

map_qc NE **0.9853**. `HeadlessGarrison1Test` OK (empty-board 575). New `TestStartupParityInventory` 3/3 in `unit_board_play_path`. Seed `20fe9063` unedited.

First cloud `--quick` on this VM failed the numpy/Pillow import check and `map_qc` because Pillow was not installed; every other step (including all Godot `--quick` tests) was already OK. After user-pip Pillow, `--quick` is green. That env miss is **not** a code red vs main.

## Cited artifacts

This directory, also `/opt/cursor/artifacts/startup-parity/`.

Logs are stored as `.txt` (repo gitignores `*.log`). Seed md5 is `seed_hash.txt`; the Godot seed run transcript is `seed_hash_run.txt`.
