# Maginot combat playtest — learnings and next build (2026-09-16)

Human F5 Maginot (GER 710173 → FRA 710739) plus headless click-order. Not M6 complete.

## What we learned (keep)

| Lesson | Keep |
|--------|------|
| Chip is the order | Click/right-click hex; no extra “Start battle” sheet when at war |
| Gold vs red | Gold = friendly march. Red = hostile (fight or occupy) |
| Fight box only if someone is there | Empty hex / post-break walk-in = red arrow, **no** Fight card |
| Fill waits for the boot | FRA breaks → hex stays FRA → GER auto-walks in → then GER red |
| War is a gate | **Not at war** → Declare war / Negotiate / Cancel (full-width stack) |
| Odds are words | Likely / Tight / Bad + bar. Never a % |
| Fog the enemy | Maginot **fortified** is public; org/TOE/commander stay fuzzy |
| Staff one-liner | Short, trait-colored (“A few more tanks…”) |
| One fight, one click | Debounce ~0.8s. Don’t spam right-click |
| F5 must stay cheap | No 8-nation `day_ai`, no 7-day 2MB autosave, no inspector on command clicks |
| Toasts | Default **player nation only** (GER). USA–MEX was the USA stub tag |

## Hangs we hit (do not regress)

- Province inspector on Alsace click (~16–19 GB)
- Hover tooltip rebuilt every frame while paused (~20 GB)
- AI empty-hex occupation chain `lb_2`…`lb_7` (~25 GB)
- `LandCombatPower` composition on a second attack
- `FormationMovement.has_method` on the class → grey map
- Instant capture teleport + leftover FRA chip
- Player tag stub **USA** → Mexico capture toasts

## Next build (priority)

1. **JOINING** — second GER marching to the fight lists JOINING then ENGAGED (headless + F5).
2. **Taken card** — after walk-in, one line “Took Haut-Rhin · they broke” then close (not a stale Press).
3. **Notify settings stub** — `capture_notify_scope`: player (default) / allies / all. Menu later.
4. **Yellow band** — keep Tight yellow; don’t collapse to 51/50 green-red.
5. **Chip vs NUTS size** — mainland Europe hex must fit a NATO plate (Malta/Gibraltar can clip). Separate map track.
6. **Recon later** — un-fog enemy org/TOE with time-on-border / CAS / agents. Not this slice.

## Retreat / air (2026-09-17)

Guidelines from HOI4 + WWII withdrawal studies (Dupuy / CSI):

- **Organized withdrawal** (org still above ~0.22): hop ~1 day, light gear loss, air often rebases with crews.
- **Rout** (org collapsed): faster hop (~0.45 day), heavy abandoned guns/trucks (occupier harvest), air loses readiness ~45% — planes/pilots more likely out, ground crews and spares not.
- **Where they run (adjacent friendly only):** capital/VP > urban/factory/port/depot > not overcrowded. Never into a hex with **enemy land**. Not into empty enemy land (no unit-level recon yet).
- **Air on a lost airfield:** rebase to the same retreat hex; flying missions implied by being assigned. Era later (2026) can lift more; 1936 is trucks and trains — not modeled as a second sim yet.
- **White arrow:** retreat path (organized ~1d hop, rout ~0.45d). Click prefers **player** chip if two units share a hex.
- **Remnant:** organized keeps ~88% strength / org ~0.32 / ~18% gear loss. Rout keeps ~55% strength / org 0.12 / ~65% gear abandoned. No legal hex = overrun (existing station=-1).

## Machine while human is out

- Occupy-after-win: hex FRA after break, GER after `tick_all_marches` (headless).
- Command click never opens inspector (`unhandled_input` included).
- Don’t re-enable F5 `day_ai` / calendar autosave until Maginot 1× is stable for 30+ days.
