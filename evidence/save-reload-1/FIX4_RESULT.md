# SAVE-RELOAD-1 FIX #4 — title Command Center close / swallow

**Merge HOLD. Draft. Play on 041d9104 was MIXED (FIX #3 items pass; this is the new FAIL).**

Branch `grok/save-reload-1` on top of FIX3 `041d9104`. Regular commits, no force-push.

| | SHA |
|---|---|
| Code / gate tip | `a46db747ac6cf4d0f5ee348ec515e3ce1f3519d9` |
| Title CC close + swallow + SHOULD items | `f8c389841df1d7bead28e5cfb232e7293356271b` |
| No class-level `CapitulationDomain.has_method` | `af0eca5b53e38bf425275fcbc3147cae8ace26ed` |
| Off-tree camera paint skip | `2cc1dc3750cb7548478312813c6e745946b5b75a` |
| Ix1 leftover-CC isolate | `548565ee18f3b5174444aaeb2f1a854de77178e6` |
| UI-guard leftover-CC dismiss | `a46db747ac6cf4d0f5ee348ec515e3ce1f3519d9` |

Godot via `tools/run_godot.sh` only (`4.7.1.rc2.official.d6096250e`). `EOA_EVIDENCE_DIR=/tmp/eoa_sr1_evidence`.

## Bug 1 vs main `d00dc8ed`

**Reproduced on main.** `LivingTitleBoot.handle_live_escape` was sticky open-only. `MainMenu._input` refused `_force_close` while the living title was up. Title pointer routing still ran, so one click could hit Command Center **Exit to Desktop** and a title save row. Not unique to SR1 title-list work; fixed here because title-opened CC must close and must swallow.

## Product

1. **MUST — close + swallow.** First Esc / title CC button opens Command Center. A later Esc, ×, or Return to Title closes it. While it is up, `handle_live_pointer` returns `cc_block` for the whole screen: title save rows, Begin, and Exit underneath do not fire. `eoa_cc_open_latch` covers only the opening Esc.
2. **SHOULD — confirm pad.** `ConfirmMargin` top 32 px so “will be lost” sits below the frame art.
3. **SHOULD — one damaged toast.** 400 ms debounce in `_show_damaged_save_message`.
4. **SHOULD — title ≠ map.** Title-up release is handled; `_try_open_land_chip_from_input` returns false while the title is up.
5. **SHOULD — session time.** “Unsaved progress since …” uses `SaveLoadManager.session_wall_time` (last successful save or load this session).
6. **SHOULD — v1 migrate log.** `_migrate_save_data(..., from_v1_file)` prints only for a real v1 file. Fresh v2 still has body `save_version == 1` (`SAVE_VERSION` const stays 1); that is not a v1 file. Corrupt’s fine v1 still logs `Migrating save from v1 to v2`.
7. **SHOULD — camera.** `map_ui` stores camera pos/zoom. `restore_view_after_load` restores it, or centres the player capital.

`world_full` IDs not renumbered. No GameData rewrite. No Godot bump. No `/home` paths. Seed `20fe9063` unedited.

## Per-test (this tip)

| Test | PASS | FAIL | SCRIPT ERROR | RESULT |
|---|---:|---:|---:|---|
| `WindowedSaveReload1TitleCcTest` | 5 | 0 | 0 | **PASS** |
| `HeadlessSaveReload1TitleListTest` | 16 | 0 | 0 | **PASS** |
| `WindowedSaveReload1UiGuard` | 32 | 0 | 0 | **PASS** |
| `HeadlessIx1LivingTitleEscBeginTest` | 13 | 0 | 0 | **PASS** |
| `HeadlessBegin1TitleReleaseFallthroughTest` | 17 | 0 | 0 | **PASS** |
| `HeadlessSaveReload1CorruptTest` | 17 | 0 | 0 | **PASS** |

Title-CC windowed evidence:

- title CC button opened Command Center
- save-row / Begin / Exit-underneath clicks are `cc_block` (no load, no quit, title stays)
- Esc closes
- × closes
- Return to Title closes CC and leaves the title up

Title-list SHOULD extras on this tip: confirm top margin **32**; session-wall confirm; camera restore (not Brazil); fresh v2 is not treated as v1; 20 centres never CC.

`--quick`: exactly the 14 known `unit_board_play_path` reds. map_qc NE **0.9853 (3148/3195)**. Seed path unedited (`20fe9063`). 0 SCRIPT ERROR on the SR1 `-s` tests.
