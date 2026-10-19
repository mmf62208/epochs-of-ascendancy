# SAVE-RELOAD-1 FIX #2 — Play MIXED follow-up

**Merge HOLD. Draft. No Play verdict.**

Branch `grok/save-reload-1` on top of FIX1 `bf683048`. Regular commits, no force-push.

| | SHA |
|---|---|
| Code / gate tip (tests below) | `2d9d12d15ea102849b2bef8284dda37c8a1b3cc0` |
| Cap list + damaged/toast UX | `1f666942282affdbdeb0624bb299ade0031d969e` |
| Clip save hits to the visible scroll | `28a6ccbde0728f0b4d5c2592c16ed001b6941e84` |
| Title-list test clicks a visible row | `2d9d12d15ea102849b2bef8284dda37c8a1b3cc0` |
| This RESULT file | later docs-only commit |

Godot via `tools/run_godot.sh` only. `EOA_EVIDENCE_DIR=/tmp/eoa_sr1_evidence`.

## Play notes that this fixes

1. **MUST — 7+ title save rows.** The load list is a `ScrollContainer` capped at 168 px. The panel is clamped to 760 px so Begin stays on 1280×800. Title rows are clickable on the live pointer path. Hits are clipped to the **visible** scroll so overflow row rects cannot steal Begin (that was the freeze / dead-click class).
2. **MUST — damaged save.** Selecting a truncated/damaged file shows `Save file is damaged and can't be loaded`, not `Select a save`. Title lists damaged files as greyed rows, same as the in-game dialog. They do not load.
3. **SHOULD — local time.** `wall_time` is still stored UTC. Lists show `SaveLoadManager.format_wall_time_local`.
4. **SHOULD — confirm overflow.** The “will be lost” label wraps and the confirm frame grows to fit.
5. **SHOULD — toasts.** Ctrl+S is one `Saved <slot>` toast (`save_game_detailed` only). Ctrl+L shows `Loaded <name>` from `load_game_detailed`. Dialog toasts sit on layer 140 while the save/load dialog is open.

`world_full` IDs not renumbered. No GameData rewrite. No Godot bump. No `/home` paths.

## Per-test

| Test | PASS | FAIL | SCRIPT ERROR | RESULT |
|---|---:|---:|---:|---|
| `HeadlessSaveReload1TitleListTest` (12 saves, 1280×800) | 8 | 0 | 0 | **PASS** |
| `WindowedSaveReload1UiGuard` | 32 | 0 | 0 | **PASS** |
| `HeadlessSaveReload1CorruptTest` | 17 | 0 | 0 | **PASS** |
| `HeadlessIx1LivingTitleEscBeginTest` | — | 0 | 0 | **PASS** |
| `HeadlessBegin1TitleReleaseFallthroughTest` | — | 0 | 0 | **PASS** |

Title-list evidence on this tip:

- panel height **760** (≤ 800)
- Begin rect `(45, 553) 549×72` on-screen
- save scroll min height **168**
- all 12 written saves listed
- damaged row greyed and refuses the load
- clicking `sr1fix2_00` loaded it

`--quick`: exactly the 14 known `unit_board_play_path` reds. map_qc NE **0.9853 (3148/3195)**. Seed path unedited (`20fe9063`).
