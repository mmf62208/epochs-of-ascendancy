# LABEL-1 isolated keep-green

Off trusted main `d008ca42094bcb6df58872d0bd421f08a87c76b0` (EDGE-1 #79).
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1-rc2). **HOLD merge.**

Fences kept: FacilityIconLayer **unedited**. Pick ranking / draw-order /
hit-test **unedited**. TipDismiss **unedited**. ORDERS **unedited**. Camera /
edge-pan **unedited**. MapRenderer fill-line (PR #80) **unedited**. PR #7 stays
draft. `world_full` IDs **untouched**.

| gate | kind | result | note |
|---|---|---|---|
| `HeadlessLabel1NationZoomTest` | hd | PASS | Europe ratio 0.0322 · mid 0.0259 · close hidden; scale=1; not magnified |
| `HeadlessLabel1NationZoomTest` | xvfb | PASS | same bands; shots under `/opt/cursor/artifacts/label1/` |
| `test_map_nation_label_landmass_product` | py | PASS | landmass + LABEL-1 bands |
| `HeadlessRt1RoadTierForEdgeTest` | hd | PASS | Köln/Bonn/Leverkusen still at 1.50 / 1.80 |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS | TipDismiss / Fill% / hit-disk |
| `test_rx1_rhine_crossing_product` | py | PASS | `CLOSE_HIDE_ZOOM` still present |
| `map_accuracy_qc` | py | PASS | NE hit 0.9853 (Pillow was missing on the first `--quick` pass) |

Official `--quick` `unit_board_play_path` still reports **14 pre-existing FAIL** on this
host (unit pick / chrome / Fill-TOE / living-loop greps + first-session composer).
Same class as EDGE-1 KEEP_GREEN “stay red on main”. **No new FAIL in the
nation-label tests.** `map_qc` on the first `--quick` pass was Pillow-missing;
re-run **PASS**.

Recipe: `docs/evidence/label1/CLICKS.md`.
