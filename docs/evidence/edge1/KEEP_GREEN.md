# EDGE-1 isolated keep-green

Off trusted main `251d26280bdc186c9db7cedf74ef98b6c051c5f5` (COMBAT-1 squash #77).
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1-rc2).

Fences kept: chip draw-order / hit ranking **unedited**. TipDismiss **unedited**.
ORDERS card layout **unedited**. Home framing **unedited**. No new camera system.

**Verdict: isolated keep-green PASS** (required slice). Official `--quick`
`unit_board_play_path` (living-unit wiring + fill-toe / unit_pick greps) and
`map_qc` (Pillow missing in this env) stay red on main — pre-existing
FLEET-2-era / env; not this slice; do not touch hit ranking.

| gate | kind | result | note |
|---|---|---|---|
| `HeadlessEdge1CameraFeelTest` | hd+xvfb | PASS | L/R/T/B + x=1270 + corner; same step 53.05; Close-held; toast/rest. Guard **1208.1 / 1369.3** |
| `HeadlessUi1LeadersEdgePanMarchTest` | hd | PASS | top-bar strip + (97,731) rest + toast block |
| `HeadlessClose1StaleDragGuardTest` | hd | PASS | leftover **11/11**; first edge dy=−209.4; clamp cy=1156.2 |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS | PR #73 tip/hit-disk; TipDismiss × did not open air wing |
| `HeadlessOrders1HaltHoldWithdrawTest` | hd | PASS | Halt/Hold ● / Withdraw ● / Open fight Start |
| `HeadlessCombat1FightResolveTest` | hd | PASS | defended Bas-Rhin + Took/Held toast |
| `test_first_session_readability_product` | py | PASS | tip strip + Fill%/TOE |
| `test_land_battle_aar_product` | py | PASS | AAR after tick |
| `test_unit_card_assign_product` | py | PASS | Halt / Hold / Withdraw / Open fight |
| `test_land_battle_stance_product` | py | PASS | explicit Hold assign |

Recipe: `docs/evidence/edge1/CLICKS.md`.
