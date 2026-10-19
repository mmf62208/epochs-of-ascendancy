# SAVE-RELOAD-1 FIX #3 — timezone bias + CC steal

**Merge HOLD. Draft. No Play verdict.**

Branch `grok/save-reload-1` on top of FIX2 `49a181aa`. Regular commits, no force-push.

| | SHA |
|---|---|
| Code / gate tip (tests below) | `7ecaf833b5929e2bc00ba2a2d4efdacfa1179ab1` |
| Timezone bias + CC hit-test + title-list sweep | `1584cc121bbb8c42fda7aa1c075c87d773a59909` |
| Do not touch a freed title after load | `7ecaf833b5929e2bc00ba2a2d4efdacfa1179ab1` |
| This RESULT file | later docs-only commit |

Godot via `tools/run_godot.sh` only (`4.7.1.rc2.official.d6096250e`). `EOA_EVIDENCE_DIR=/tmp/eoa_sr1_evidence`.

## Box-gate bugs this fixes

1. **MUST — local time.** `format_wall_time_local` now adds `Time.get_time_zone_from_system().bias` (minutes east of UTC, DST as the OS reports it) to the stored UTC unix time, then formats with `utc=true` so the zone is not applied twice. Pre-1970 campaign stamps stay valid (unix is negative). Injected bias −240 maps `1936-06-15T08:00:00` → `1936-06-15T04:00:00`; +240 → `12:00:00`. Title rows, the in-game Load list, and “Unsaved progress since…” all call this helper.
2. **MUST — Command Center steal.** Visible save-row ink is classified before the CC grow pad. `_cc_grow_rect` clips the +28 px grow so it cannot enter the save-scroll rect (list bottom was y 512; CC grow started at y 492). `HeadlessSaveReload1TitleListTest` clicks every visible row centre with `handle_live_pointer` at five scroll positions and asserts load or the damaged message — never `action=cc`. This run: **20 centres, 0 CC**.
3. **MUST — no button fallback.** The title-list guard no longer calls `pressed.emit()` when the pointer misses. A pointer miss fails the test.

`world_full` IDs not renumbered. No GameData rewrite. No Godot bump. No `/home` paths.

## Per-test

| Test | PASS | FAIL | SCRIPT ERROR | RESULT |
|---|---:|---:|---:|---|
| `HeadlessSaveReload1TitleListTest` (bias + 20 centres + load) | 12 | 0 | 0 | **PASS** |
| `WindowedSaveReload1UiGuard` | 32 | 0 | 0 | **PASS** |
| `HeadlessSaveReload1CorruptTest` | 17 | 0 | 0 | **PASS** |
| `HeadlessIx1LivingTitleEscBeginTest` | — | 0 | 0 | **PASS** |
| `HeadlessBegin1TitleReleaseFallthroughTest` | — | 0 | 0 | **PASS** |

Title-list evidence on this tip:

- injected bias −240 → `1936-06-15T04:00:00`; +240 → `1936-06-15T12:00:00`
- system bias 0 matches the injected call
- panel height **760** (≤ 800)
- Begin rect `(45, 553) 545×72` on-screen
- save scroll min height **168**
- all 12 written saves listed
- damaged row greyed; pointer click shows `Save file is damaged and can't be loaded` (action=save, not cc)
- **20** visible row centres across 5 scroll positions; never CC
- pointer click on `sr1fix2_00` loaded it (no `pressed.emit` fallback)

`--quick`: exactly the 14 known `unit_board_play_path` reds. map_qc NE **0.9853 (3148/3195)**. Seed path unedited (`20fe9063`). Determinism / seed 3/3 were already PASS on `49a181aa`; this slice does not touch `GameData` or the save body.
