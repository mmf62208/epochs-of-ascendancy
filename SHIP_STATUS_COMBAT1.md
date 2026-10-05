# COMBAT-1 — first-session fight loop visibility

**Base:** trusted main `b89a1679ee90eba9e496c8a9f62ef1b10612d589` (ORDERS-1 #76)
**Branch:** `cursor/combat1-fight-resolve-13b5`
**PR:** https://github.com/mmf62208/epochs-of-ascendancy/pull/77 (draft, HOLD)
**Merge:** HOLD (do not merge)
**Keep-green:** isolated **PASS** (ORDERS-1 / TipDismiss / CLOSE-1 leftover 11/11 / COMBAT-1 hd). Official `--quick` fill-toe hit-disk greps remain pre-existing red on main — not this slice.

## What changed

Existing combat only. Two shipped-path gaps:

1. **Resolve was invisible.** AAR toast lived inside `if open_n > 0` on
   `game_day_advanced`, which fires *before* `tick_open_land_battles` on F5
   and headless. Resolve day had `open_n=0`, so Took/Held never toasted.
   Defender hold also never refreshed the card/chips. Now
   `tick_open_land_battles` notifies `refresh_after_land_battle_day`: rebuild
   open card + selected chip, toast/print the existing AAR line.
2. **Open fight first-adjacent could be empty Haut-Rhin** (instant light
   capture). `_adjacent_enemy_province_id` now prefers a neighbor with
   `get_divisions_at_province` when one exists. Empty is fallback.

Fences kept: no chip draw-order / hit ranking, no TipDismiss, no ORDERS card
layout, no GameData rewrite, no world_full ID renumber, Godot via
`tools/run_godot.sh` only.

## Play recipe (1280×740 Absolute @(0,29), no Ctrl)

See `docs/evidence/combat1/CLICKS.md`.

- Inspector Close ~(670, 85) if needed
- Open fight (90, 564)
- Start battle ≈(205, 548) — not 525 (Power line)
- Hold ≈(157, 621) / Withdraw ≈(241, 621) — not y=662 (Assign)
- Halt march-only (90–93, 662) OK

Path: Begin GER → Tip × → Close inspector if needed → GER land chip →
Open fight → Start → unpause a few days → chips/card strength/Fill% +
`Took …` / `Held at …` toast. No new button within ~40 px of Assign/Halt.
