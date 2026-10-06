# LABEL-1 isolated keep-green

Off trusted main `d008ca42094bcb6df58872d0bd421f08a87c76b0` (EDGE-1 #79).
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1-rc2). **HOLD merge.**

Fences kept: FacilityIconLayer **unedited**. Pick ranking / draw-order /
hit-test **unedited**. TipDismiss **unedited**. ORDERS **unedited**. Camera /
edge-pan **unedited**. MapRenderer fill-line (PR #80) **unedited**. MapRenderer
pause / detail-refresh skip **unedited**. PR #7 stays draft. `world_full` IDs
**untouched**.

FIX #2 pan cost (all in `MapPoliticalLabelsLayer.gd`): visibility-only on
position moves; 5% view dead zone; `sync_viewport` does not reset idle;
`force_nation_label_at` fades via modulate.

| metric | before (e1d4f8b5) | after hd | after xvfb |
|---|---|---|---|
| political pan-frame | 2.5–2.7 ms | **0.114 ms** | **0.170 ms** |
| states pan-frame | 5.4–7.2 ms | **0.093 ms** | **0.089 ms** |
| idle `_process` box | 0.57 ms | **0.002 ms** | **0.002 ms** |

| gate | kind | result | note |
|---|---|---|---|
| `HeadlessLabel1NationZoomTest` | hd | PASS | fade holds mid; paused Home 43 · Far East 6; pan 0.101 / idle 0.002 / states 0.123 |
| `HeadlessLabel1NationZoomTest` | xvfb | PASS | `tools/eoa_label1_guard.sh` |
| `tools/eoa_label1_guard.sh` | hd+xvfb | PASS | rss 1210.8 / 1341.3 |
| `test_map_nation_label_landmass_product` | py | PASS | landmass + LABEL-1 needles |
| `HeadlessRt1RoadTierForEdgeTest` | hd | PASS | Köln/Bonn/Leverkusen still at 1.50 / 1.80 |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS | TipDismiss / Fill% / hit-disk |
| `map_accuracy_qc` | py | PASS | NE hit 0.9853 |

Official `--quick` `unit_board_play_path` still reports **14 pre-existing FAIL**
on this host (same class as main `d008ca42`):

- `living_unit_order_loop` 4
- `unit_card_fill_toe` 3
- `unit_centric_pick` 3
- `unit_counter_chrome` 2
- `se_england_shire` 1
- `first_session_play_surface` 1

**No new FAIL.** `unit_save_path` / `map_qc` / `hoi_matrix_product` **OK**.

Recipe: `docs/evidence/label1/CLICKS.md`.
