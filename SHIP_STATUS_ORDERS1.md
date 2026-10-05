# SHIP_STATUS — ORDERS-1 Halt / Hold / Withdraw

**Branch:** `cursor/orders1-halt-hold-withdraw-89c5`
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/76 (draft, HOLD)
**Base:** trusted main `b9425e338d0bedd2cdbe69453f4fea26396ce8a0`
**Merge:** HOLD for Play + Scott. ONE draft PR. Do not merge.

## Product

From Begin GER 1936: land unit → March → Halt; Hold and Withdraw on the card
do what the card says, with a visible card/bubble state change.

## Proven (not hunches)

1. **Halt already worked** on `b9425e33` (clear march, stay on hex, Halt gone).
   Live Play on `138a1f8a` **PASS** at screen (85, 744).
2. **Hold API was broken:** `set_land_battle_stance(..., "hold")` returned
   `ok: true, stance: "press"` because Array `in` rejected the string token.
   Fixed on `138a1f8a` (explicit equals).
3. **Withdraw pending worked** but the card/toast showed no withdrawing state.
   Fixed on `138a1f8a` (`Hold ●` / `Withdraw ●` / `Withdrawing · bounce tomorrow`).
4. **FIX #1 live MIXED `138a1f8a`:** Hold/Withdraw still failed in Play at
   **1280×740**. Stance row sat *below* Halt/Assign and clipped (dock
   `vp.y-252`). Fighting+marching put Withdraw beside Halt — clicks hit Halt
   or nothing. Hold toast used shared `next_hook` (`Unpause to fight · Press
   or Hold`) so API toasts did not prove Hold ●. Fix: raise dock
   (`UNIT_CARD_DOCK_RESERVE` 348 + `_dock_unit_card_in_viewport`); stance row
   **above** cmd with Press \| Hold \| Withdraw; Halt stays left on the lower
   row; toast **`Stance: Hold`**. Harness asserts card text + `att_stance`
   after click and 1280×740 visibility.

## Fence STOP

Did **not** need the first-session tip / TipDismiss / map release-fallthrough
path. Those files/handlers were not edited. No Grok Build rebase required
for this slice.

## Keep-green

See `docs/evidence/orders1/KEEP_GREEN.md`. Official `--quick` is pre-existing
red on trusted main (pick/chrome/living-loop greps). PR #73 readability,
unit-card assign, stance, bubble products **PASS**. ORDERS-1 hd+xvfb **PASS**.
CLOSE-1 leftover 11/11 **PASS**. CRASH-1 **PASS**. First-session readability hd **PASS**.

## Play recipe (1280×740 — do not raise the window)

`docs/evidence/orders1/CLICKS.md`

- **Hold** upper row ~(134, 649) screen — expect **Hold ●** + `Stance: Hold`
- **Withdraw** upper row ~(210, 649) screen — not Halt
- **Halt** lower-left ~(73, 681) screen — not Assign
