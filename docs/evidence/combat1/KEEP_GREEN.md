# COMBAT-1 isolated keep-green

Off trusted main `b89a1679` (ORDERS-1 squash #76). xvfb / headless ≠ live Play.
Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

Fences kept: chip draw-order / hit ranking **unedited**. TipDismiss **unedited**.
ORDERS card layout **unedited**. No new combat system.

**Verdict: isolated keep-green PASS** (required slice). Official `--quick` fill-toe /
unit_pick greps stay red on main (pre-existing FLEET-2-era; not this slice; do
not touch hit ranking).

| gate | kind | result | note |
|---|---|---|---|
| `test_land_battle_aar_product` | py | PASS | AAR after tick + prefer defended neighbor |
| `test_unit_card_assign_product` | py | PASS | Halt / Hold ● / Withdraw ● / Open fight latch |
| `test_first_session_readability_product` | py | PASS | tip strip + Fill%/TOE |
| `test_land_battle_stance_product` | py | PASS | explicit Hold assign |
| `HeadlessCombat1FightResolveTest` | hd | PASS | defended Bas-Rhin · Start opened · str 1.00→0.71 Fill 45% · toast `Battle ended at Bas-Rhin` |
| `HeadlessOrders1HaltHoldWithdrawTest` | hd | PASS | Halt/Hold/Withdraw + Open fight Start |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS | TipDismiss × did not open air wing |
| `HeadlessClose1StaleDragGuardTest` | hd | PASS | CLOSE-1/1b leftover **11/11** |

Recipe: `docs/evidence/combat1/CLICKS.md`.
