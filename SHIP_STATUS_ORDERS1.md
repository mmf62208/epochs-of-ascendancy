# SHIP_STATUS — ORDERS-1 Halt / Hold / Withdraw

**Branch:** `cursor/orders1-halt-hold-withdraw-89c5`
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/76 (draft, HOLD)
**Base:** main `f4282acdd4f911259636253303730d8467595ab4` (PR #75 TipDismiss squash; parent of first ORDERS-1 commit)
**Merge:** Play **PASS → KEEP** tip `333a1285`. Draft until Ship squash-merges onto main `f4282acd`. Do not merge from this tip. No rebase needed.

**Rebase:** replayed 4 ORDERS-1 commits onto `f4282acd`. **0 conflicts.** TipDismiss swallow / deferred free / release-block kept from main; unit-card dock + Press|Hold|Withdraw upper row + Halt|Assign lower + `Stance: Hold` kept from ORDERS-1. `git diff origin/main -- MapRenderer.gd` has no TipDismiss hunks.

## Product

From Begin GER 1936: land unit → March → Halt; **Open fight → Start battle**
(no Ctrl) then Hold and Withdraw on the card do what the card says, with a
visible card/bubble state change.

## Proven (not hunches)

1. **Halt already worked** on `b9425e33` (clear march, stay on hex, Halt gone).
   Live Play on `aa6a08d4` **PASS ×2** at screen (93, 662) march-only.
2. **Hold API was broken:** `set_land_battle_stance(..., "hold")` returned
   `ok: true, stance: "press"` because Array `in` rejected the string token.
   Fixed on `138a1f8a` (explicit equals).
3. **Withdraw pending worked** but the card/toast showed no withdrawing state.
   Fixed on `138a1f8a` (`Hold ●` / `Withdraw ●` / `Withdrawing · bounce tomorrow`).
4. **FIX #1 live MIXED `138a1f8a`:** Hold/Withdraw still failed in Play at
   **1280×740**. Stance row sat *below* Halt/Assign and clipped (dock
   `vp.y-252`). Fighting+marching put Withdraw beside Halt. Raise dock;
   stance row **above** cmd; toast **`Stance: Hold`**.
5. **FIX #2 live FAIL `aa6a08d4`:** Halt PASS; Hold/Withdraw never banked
   because Play never opened a fight. Ctrl+xdotool intermittent (plain
   select / inspector). Inspector / National Spirits covered the left dock.
   Open fight press freed the card with no CRASH-1 latch. Start treated
   empty-hex `success` as a fight (no stance row). **Product:** latch Open
   fight; hide inspector while the card is up; Start only when
   `start_land_battle` **opened**; prefer adjacent enemy (Maginot fallback
   kept). **Recipe:** Close @(670, 85) then Open fight → Start (no Ctrl).
   Harness `_test_open_fight_start_no_ctrl` banks Hold ● / Withdraw ●.
6. **Play PASS `333a1285`:** Halt / Hold ● + `Stance: Hold` / Withdraw ● /
   Open fight → Start (`opened=true` Maginot) all live. Recipe coords below
   are the live hits (Start y≈548, Hold/Withdraw y≈621). Soft OK: first Open
   fight hit empty Haut-Rhin — prefer defended neighbor later (not COMBAT-1).

## Fence STOP

ORDERS-1 commits did **not** edit first-session tip / TipDismiss / map
release-fallthrough. After rebase we **inherit** PR #75 TipDismiss from main.
Both products kept. COMBAT-1 not started.

## Keep-green

See `docs/evidence/orders1/KEEP_GREEN.md`. FIX #2:
ORDERS-1 hd **PASS** (Hold ● / Withdraw ●; Open fight → Start no Ctrl).
FSR/TipDismiss hd **PASS** (× did not open air wing; map pick after release).
CLOSE-1 leftover **11/11 PASS**. Official `--quick` still pre-existing red
on trusted main.

## Play recipe (1280×740 — do not raise the window)

`docs/evidence/orders1/CLICKS.md` — Absolute @(0, 29). No Ctrl.
Live-proven Play PASS `333a1285` (harness fixture centers are not this table).

| Button | Client | Screen |
|---|---|---|
| Inspector Close | ~(670, 56) | **~(670, 85)** |
| Open fight | **(90, 535)** | **(90, 564)** |
| Start battle | **≈(205, 519)** | **≈(205, 548)** |
| Hold | **≈(157, 592)** | **≈(157, 621)** |
| Withdraw | **≈(241, 592)** | **≈(241, 621)** |
| Halt march-only | **(90–93, 633)** | **(90–93, 662)** |
