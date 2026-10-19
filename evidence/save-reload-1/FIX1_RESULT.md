# SAVE-RELOAD-1 FIX1 — box-gate result

**Merge HOLD. Draft. No Play verdict.**

Branch `grok/save-reload-1` after a **normal merge** of `origin/main` (`d00dc8ed`, #113 CL1 + #114). No longer stacked on #113. No force-push.

| | SHA |
|---|---|
| Code / gate tip (tests below) | `63ea80e9da131f85da9928a3a850814ce67a75b8` |
| Merge `origin/main` | `9486f8ad2dce6afea317a213dbb6d38e522b9f63` |
| Portable fixtures + evidence paths | `aafd35803908ac2c86db7dafd5f578cc42a7718b` |
| CL1 war-declare fixtures (tests only) | `63ea80e9da131f85da9928a3a850814ce67a75b8` |
| This RESULT file | later docs-only commit on the same branch |

Godot via `tools/run_godot.sh` only (`4.7.1.rc2.official.d6096250e`). `EOA_EVIDENCE_DIR=/tmp/eoa_sr1_evidence`.

## What FIX1 changed

1. **v1 fixture in-tree.** `res://tests/fixtures/save_reload_1/sr1test_v1_day0.json` (1477 bytes, md5 `68114569758e6690fa514ba9a393a06a`). Tests load it from `res://` via `SaveReload1Io.V1_DAY0`. It is a slim, pinned v1 `<slot>.json` body (`save_version` 1, day 0, one GER hex `710173`, empty wars). `SaveFormat.migrate` / `validate` accept it. Apply of one pid does not wipe the booted board.
2. **Portable evidence.** GDScript writes to `EOA_EVIDENCE_DIR` or `user://sr1_evidence/` (`SaveReload1Io.evidence_dir` / `evidence_file`). Shell wrappers default to `/tmp/eoa_sr1_evidence` when the env is unset and export it so Godot matches. Repo-wide grep for `/home/featherstone` and `featherstone` in tests/scripts: **0 hits**.
3. **CL1 at-war fixtures (separate tests-only commit).** The five `HeadlessWorldFullPostCapturePostLoad*` tests and `HeadlessWorldAccurateUnitOrderLoopTest` declare GER–FRA (Chain / SecondFlip also GER–BEL; UnitOrderLoop also JAP–CHI) through `WarStateDomain.declare_war` (`Cl1WarFixture.gd`). They do **not** disable the campaign loop. `BattleManager` and the war rule are unchanged.

`world_full` IDs not renumbered. No new residual dual package. No GameData rewrite. No Godot bump.

## How to regenerate `sr1test_v1_day0.json`

Preferred (pure, no Godot, byte-identical):

```bash
python3 tools/generate_sr1_v1_fixture.py
```

Pinned timestamps (`1936-01-01T00:00:00`), `json.dumps(..., indent=2, sort_keys=True)` plus a trailing newline. Re-running on this tip left the file `git` clean.

Optional Godot path (same slim shape after `CampaignLoopTestBoot`, not a host dump):

```bash
EOA_CAMPAIGN_LOOP=1 EOA_SCENARIO_EARLY_WARS=0 EOA_CALENDAR_AUTOSAVE=0 \
  tools/run_godot.sh --headless --path . -s res://scripts/core/SaveReload1V1FixtureExport.gd
```

## Per-test pass / fail

Assertion counts are `[PASS]` / `[FAIL]` lines from the Godot harness. `SCRIPT ERROR` is a grep of that log.

### SR1 (must be green)

| Test | PASS | FAIL | SCRIPT ERROR | RESULT |
|---|---:|---:|---:|---|
| `HeadlessSaveReload1RoundTripTest` | 8 | 0 | 0 | **PASS** |
| `HeadlessSaveReload1MidWarTest` | 8 | 0 | 0 | **PASS** |
| `HeadlessSaveReload1CorruptTest` | 17 | 0 | 0 | **PASS** (fine v1 loaded) |
| `HeadlessSaveReload1DeterminismTest` wrapper | 4/4 child modes | 0 | 0 | **PASS** |
| `WindowedSaveReload1UiGuard` (Xvfb `:24`, 1280×800) | 32 | 0 | 0 | **PASS** |

Determinism wrapper (`tools/eoa_save_reload1_determinism.sh`):

- `SEED_MD5 20fe9063de285f19d4f9b8a105abfd31`
- two-process traces match `0a625e185f3f9b882d18294252b8a6b7`
- child logs `sr1_det_ref`, `sr1_det_load`, `sr1_det_inproc`, `sr1_det_autosave` all `RESULT=PASS`, 0 `SCRIPT ERROR`

UI screenshots landed under `$EOA_EVIDENCE_DIR` (not a `/home` path): `save_dialog.png`, `overwrite_confirm.png`, `load_list.png`, `load_damaged_row.png` (1280×800 PNG).

### PostLoad + UnitOrderLoop (CL1 war declare)

These also reproduced on main without SR1 when the fixtures did not declare war. After `WarStateDomain.declare_war`:

| Test | PASS | FAIL | SCRIPT ERROR | RESULT |
|---|---:|---:|---:|---|
| `HeadlessWorldFullPostCapturePostLoadPlayabilityTest` | 5 | 0 | 0 | **PASS** |
| `HeadlessWorldFullPostCapturePostLoadConquestLoopTest` | 5 | 0 | 0 | **PASS** |
| `HeadlessWorldFullPostCapturePostLoadChainAssaultTest` | 5 | 0 | 0 | **PASS** |
| `HeadlessWorldFullPostCapturePostLoadSecondProvinceFlipTest` | 5 | 0 | 0 | **PASS** |
| `HeadlessWorldFullPostCapturePostLoadSlotSaveLoadTest` | 5 | 0 | 0 | **PASS** |
| `HeadlessWorldAccurateUnitOrderLoopTest` | 119 | 1 | 0 | **FAIL** |

The leftover UnitOrderLoop red is **not** the war-goal / assault class:

- `[FAIL] no DemoUnitIcon on Channel fleet 950001` (pre-existing on this board; not an SR1 save miss)
- `[PASS] living declare at_war GER-FRA via WarStateDomain`
- `[PASS] start_land_battle opened=true`
- `[PASS] CHI-JAP start_land_battle opened`
- `[PASS] AI opened CHI-JAP start_land_battle to=902598`

`--check-only` against `TestScenario.tscn` is not a reliable compile gate here (it hung loading the main scene). Compile evidence is the `-s` tests above: **0 SCRIPT ERROR**.

## `--quick` and seed

`tools/eoa_full_test_gates.sh --quick` (log `/tmp/eoa_sr1_fix1/quick3.log`):

- `unit_board_play_path` **FAILED (failures=14)** — same 14 names as main `d00dc8ed`
- `unit_save_path` OK
- `map_qc` OK — NE land hit **0.9853 (3148/3195)**
- `hoi_matrix_product` OK
- `air_physics_p1` OK

The 14 known reds:

- `test_living_unit_order_loop_product`: integrity, playtest_clock (ai_starts + occupation_ticks), product_wiring
- `test_unit_card_fill_toe_visibility_product`: integrity, product_ok, renderer_source_lock
- `test_unit_centric_pick_product`: integrity, product_wiring, renderer_integrity_strings
- `test_unit_counter_chrome_product`: integrity, product_wiring
- `test_se_england_shire_land_uniformity_product`: prior_feed_products_and_fill_toe_still_pass
- `test_first_session_play_surface_product`: real_builder_ands_shipped_children

Seed `multi_ai_decisions` md5 stayed **`20fe9063de285f19d4f9b8a105abfd31`**.
