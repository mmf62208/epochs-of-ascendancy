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
2. **Hold was broken:** `set_land_battle_stance(..., "hold")` returned
   `ok: true, stance: "press"` because Array `in` rejected the string token.
3. **Withdraw pending worked** but the card/toast showed no withdrawing state.

## Fence STOP

Did **not** need the first-session tip / TipDismiss / map release-fallthrough
path. Those files/handlers were not edited. No Grok Build rebase required
for this slice.

## Keep-green

See `docs/evidence/orders1/KEEP_GREEN.md`. Official `--quick` is pre-existing
red on trusted main (pick/chrome/living-loop greps). PR #73 readability,
unit-card assign, stance, bubble products **PASS**. ORDERS-1 hd+xvfb **PASS**.
CLOSE-1 leftover 11/11 **PASS**. CRASH-1 **PASS**. First-session readability hd **PASS**.

## Play recipe

`docs/evidence/orders1/CLICKS.md` — Halt is the **left** command button;
Assign is 6 px to its right. Live Play Halt ≈ **(97, 731)**.
