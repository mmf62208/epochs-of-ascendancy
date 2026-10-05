# ORDERS-1 isolated keep-green

Tip after this slice. xvfb / headless ≠ live Play. Never `EOA_SKIP_TITLE`.
`tools/run_godot.sh` only (Godot 4.7.1-rc2).

Official `tools/eoa_full_test_gates.sh --quick` is **already red on trusted
main `b9425e33`** (unit_pick / unit_chrome / fill-toe slice greps + living-loop
clock needles). Those failures are pre-existing FLEET-2-era function-slice
misses. ORDERS-1 did not edit pick / tip / hit-disk / Close / release paths.

| gate | kind | result | note |
|---|---|---|---|
| `test_first_session_readability_product` (PR #73) | py | PASS | tip strip + Fill%/TOE + empty-land hit-disk |
| `test_unit_card_assign_product` | py | PASS | halt + withdraw visible + assign |
| `test_land_battle_stance_product` | py | PASS | explicit Hold assign |
| `test_land_battle_bubble_product` | py | PASS | HOLD / WD labels |
| `HeadlessOrders1HaltHoldWithdrawTest` | hd+xvfb | PASS | Halt / Hold API+card ● / Withdrawing |
| `tools/eoa_orders1_guard.sh` | hd+xvfb | PASS | wrapper 1×+1× |
| `HeadlessCrash1HaltMarchPopupTest` | hd | PASS | CRASH-1 unedited |
| `HeadlessClose1StaleDragGuardTest` | hd | PASS | CLOSE-1/1b leftover 11/11 |
| `HeadlessFirstSessionReadabilityTest` | hd | PASS | PR #73 unedited |

Fences kept: first-session tip / TipDismiss / release-fallthrough **unedited**.
No new dual package. No Godot bump. No `world_full` ID renumber. PR #7 stays draft.
