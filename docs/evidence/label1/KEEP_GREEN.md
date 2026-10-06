# LABEL-1 isolated keep-green

Off trusted main `d008ca42094bcb6df58872d0bd421f08a87c76b0` (EDGE-1 #79).
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1-rc2). **HOLD merge.**

Fences kept: FacilityIconLayer **unedited**. Pick ranking / draw-order /
hit-test **unedited**. TipDismiss **unedited**. ORDERS **unedited**. Camera /
edge-pan **unedited**. MapRenderer fill-line (PR #80) **unedited**. MapRenderer
pause / detail-refresh skip **unedited**. PR #7 stays draft. `world_full` IDs
**untouched**.

Paused first-session: `PoliticalLabelsLayer` recomputes its visible box from the
live MapCamera in `_process` (Home ≥43 names; Far-East pan 6). Fade 0.82–0.98
holds mid on-screen size (18.9 ≥ 18.6) and fades `modulate.a=0.48` (outline
included).

| gate | kind | result | note |
|---|---|---|---|
| `HeadlessLabel1NationZoomTest` | hd | PASS | Europe 0.0322 · mid 0.0259 · fade 0.0263 / modulate.a=0.48 · close hidden; paused Home 43 · Far East 6 |
| `HeadlessLabel1NationZoomTest` | xvfb | PASS | same bands; shots under `/tmp/eoa-label1/` |
| `tools/eoa_label1_guard.sh` | hd+xvfb | PASS | rss 1210.4 / 1374.2 |
| `test_map_nation_label_landmass_product` | py | PASS | landmass + LABEL-1 bands + fade holds mid |
| `HeadlessRt1RoadTierForEdgeTest` | hd | PASS | Köln/Bonn/Leverkusen still at 1.50 / 1.80 |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS | TipDismiss / Fill% / hit-disk |
| `test_rx1_rhine_crossing_product` | py | PASS | `CLOSE_HIDE_ZOOM` still present |
| `map_accuracy_qc` | py | PASS | NE hit 0.9853 (Pillow installed) |

Official `--quick` `unit_board_play_path` still reports **14 pre-existing FAIL**
on this host (same class as main `d008ca42` / EDGE-1 KEEP_GREEN “stay red”):

- `living_unit_order_loop` 4
- `unit_card_fill_toe` 3
- `unit_centric_pick` 3
- `unit_counter_chrome` 2
- `se_england_shire` 1
- `first_session_play_surface` 1

**No new FAIL** in the nation-label tests. `unit_save_path` / `map_qc` /
`hoi_matrix_product` **OK**.

Recipe: `docs/evidence/label1/CLICKS.md`.
