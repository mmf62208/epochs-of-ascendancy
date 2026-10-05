# ORDERS-1 isolated keep-green

Tip after rebase onto main `f4282acd` (PR #75 TipDismiss). xvfb / headless ≠ live Play.
Never `EOA_SKIP_TITLE`. `tools/run_godot.sh` only (Godot 4.7.1-rc2).

Official `tools/eoa_full_test_gates.sh --quick` is **already red on trusted
main `b9425e33`** (unit_pick / unit_chrome / fill-toe slice greps + living-loop
clock needles). Those failures are pre-existing FLEET-2-era function-slice
misses. ORDERS-1 did not edit pick / tip / hit-disk / Close / release paths.

| gate | kind | result | note |
|---|---|---|---|
| `test_first_session_readability_product` (PR #73) | py | PASS | tip strip + Fill%/TOE + empty-land hit-disk |
| `test_unit_card_assign_product` | py | PASS | halt + withdraw visible + 1280×740 dock + Stance: Hold |
| `test_land_battle_stance_product` | py | PASS | explicit Hold assign |
| `test_land_battle_bubble_product` | py | PASS | HOLD / WD labels |
| `HeadlessOrders1HaltHoldWithdrawTest` | hd after rebase | PASS | Hold ● / Withdraw ● · PLAY_CLICKS Halt=(92,675) Hold=(159,633) Withdraw=(246,633) **unchanged** |
| `tools/eoa_orders1_guard.sh` | hd+xvfb (pre-rebase) | PASS | wrapper 1×+1× `--resolution 1280x740` |
| `HeadlessCrash1HaltMarchPopupTest` | hd+xvfb (pre-rebase) | PASS | CRASH-1 unedited (repeats=1) |
| `HeadlessClose1StaleDragGuardTest` | hd after rebase | PASS | CLOSE-1/1b leftover **11/11** |
| `HeadlessFirstSessionReadabilityTest` | hd after rebase | PASS | TipDismiss × did not open air wing; map pick works after × release |

Fences kept: first-session tip / TipDismiss / release-fallthrough **unedited**.
No new dual package. No Godot bump. No `world_full` ID renumber. PR #7 stays draft.
