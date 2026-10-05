# COMBAT-1 isolated keep-green

Off trusted main `b89a1679` (ORDERS-1 squash #76). xvfb / headless ≠ live Play.
Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

Fences kept: chip draw-order / hit ranking **unedited**. TipDismiss **unedited**.
ORDERS card layout **unedited**. No new combat system.

| gate | kind | note |
|---|---|---|
| `test_land_battle_aar_product` | py | AAR after tick + prefer defended neighbor |
| `test_unit_card_assign_product` | py | Halt / Hold ● / Withdraw ● / Open fight latch |
| `test_first_session_readability_product` | py | tip strip + Fill%/TOE + empty-land hit-disk |
| `test_land_battle_stance_product` | py | explicit Hold assign |
| `HeadlessCombat1FightResolveTest` | hd | defended neighbor + Start opened + Took/Held toast |
| `HeadlessOrders1HaltHoldWithdrawTest` | hd | ORDERS-1 keep-green |
| `HeadlessFirstSessionReadabilityTest` | hd | TipDismiss × |
| `HeadlessClose1StaleDragGuardTest` | hd | CLOSE-1/1b leftover |

Recipe: `docs/evidence/combat1/CLICKS.md`.
