# ORDERS-1 Halt / Hold / Withdraw — proven causes

Headless `HeadlessOrders1HaltHoldWithdrawTest` on trusted main `b9425e33`.
Not live Play. Hunches labeled until the harness printed the return values.

## Halt (already worked)

Card **Halt march** calls `FormationMovement.clear_march`, drops `MarchPathLine`,
rebuilds the card without Halt, unit stays on the current hex. CRASH-1 covered
the crash/click-through; ORDERS-1 re-proved the play-loop state.

Harness Halt center on the docked card: **(92.5, 305)** with Assign **(245.0, 305)**
(6 px gap, same row). Live Play ~1680×960 docks the card lower; Halt sits near
**(97, 731)** with Assign immediately to its right. Click the **left** command
button labeled `Halt march`, not Assign.

## Hold (proven broken)

`BattleManager.set_land_battle_stance(fid, "hold")` returned
`{ok: true, stance: "press"}`. The card then kept **Press ●**.

Cause: `if st not in ["press", "hold", "withdraw"]` always treated the string
token as not-a-member (Godot 4 Array `in` is index membership here) and forced
`st = "press"`. Press/Hold buttons therefore never changed `att_stance`.

Fix: explicit `raw_st == "hold"` / `"press"` / `"withdraw"` assigns.

## Withdraw (pending worked; visible state did not)

Same-day `withdraw_from_land_battle` correctly sets `withdraw_pending=true`
(next daily tick bounces). The rebuilt card still showed plain **Withdraw**
and the same Fight line. Toast was `Withdraw · true`.

Fix: card body **Withdrawing · bounce tomorrow**, button **Withdraw ●**,
toast `Withdrawing · bounce tomorrow` / `Withdrew · fight ended`, bubble
label ` WD` (Hold paints ` HOLD`).

## Fence

Did **not** edit first-session tip strip, `TipDismiss`, or map release-fallthrough.
Those stay Mike's Grok Build lane.
