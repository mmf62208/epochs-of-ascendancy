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

## FIX #1 live MIXED `138a1f8a` (1280×740)

Halt **PASS** live at screen (85, 744). Hold ● / Withdraw **FAIL**.

Proven layout (not hunches):
1. Dock `vp.y - 252` + stance row *below* cmd left Press/Hold off-screen
   at 1280×740 (Play needed ~800 height to see them).
2. Fighting+marching put **Withdraw** on the same row as **Halt**. Clicks
   aimed at Withdraw hit Halt (`March halted`) or nothing.
3. Hold toast used `next_hook` (`Unpause to fight · Press or Hold`) — same
   string as Press — so stance API toasts ×3 did not prove Hold ●.

Fix: `UNIT_CARD_DOCK_RESERVE` 348 + `_dock_unit_card_in_viewport` after
layout; stance row **above** cmd with Press | Hold | Withdraw; Halt stays
left on the lower row; toast **`Stance: Hold`**. Harness asserts card text
+ `att_stance` after click and that buttons sit inside 1280×740.

## Fence

Did **not** edit first-session tip strip, `TipDismiss`, or map release-fallthrough.
Those stay Mike's Grok Build lane.
