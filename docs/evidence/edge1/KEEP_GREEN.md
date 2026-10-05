# EDGE-1 isolated keep-green

Off trusted main `251d26280bdc186c9db7cedf74ef98b6c051c5f5` (COMBAT-1 squash #77).
xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only
(Godot 4.7.1).

Fences kept: chip draw-order / hit ranking **unedited**. TipDismiss **unedited**.
ORDERS card layout **unedited**. Home framing **unedited**. No new camera system.

**Verdict:** fill after the isolated run (this file is the template; numbers
come from the keep-green pass on this branch).

Official `--quick` fill-toe / unit_pick greps stay red on main (pre-existing
FLEET-2-era; not this slice; do not touch hit ranking).

| gate | kind | result | note |
|---|---|---|---|
| `HeadlessEdge1CameraFeelTest` | hd | (run) | L/R/T/B + x=1270 + corner; Close-held; toast/rest |
| `HeadlessUi1LeadersEdgePanMarchTest` | hd | (run) | top-bar strip + (97,731) rest |
| `HeadlessClose1StaleDragGuardTest` | hd | (run) | CLOSE-1/1b leftover |
| `HeadlessFirstSessionReadabilityTest` | hd | (run) | PR #73 tip/hit-disk + TipDismiss × |
| `HeadlessOrders1HaltHoldWithdrawTest` | hd | (run) | ORDERS-1 |
| `HeadlessCombat1FightResolveTest` | hd | (run) | COMBAT-1 |
| `test_first_session_readability_product` | py | (run) | tip strip + Fill%/TOE |

Recipe: `docs/evidence/edge1/CLICKS.md`.
