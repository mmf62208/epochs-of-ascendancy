# Maginot F5 play catalogue — 2026-09-17

Human + Grok Maginot GER 1936 (chip 710173 → Alsace 710739). Not M6 complete. This is the session log for **combat loop, stacks, orders, hang-class, map chrome**.

Companion: [`2026-09-16_maginot_combat_learnings.md`](2026-09-16_maginot_combat_learnings.md).

## Combat loop we kept (bones)

| Player action | Intended result |
|---------------|-----------------|
| Click land chip | Select. Gold ring. Unit card. |
| Click same chip / `[` `]` | Cycle stack (`1/3`). Card + NATO in place. |
| Click another stack | Select that stack. |
| Click adjacent own hex | Gold march **this** division only. |
| Shift-click adjacent own hex | Append waypoint from last stop. Then Shift-click adjacent enemy = planned attack. |
| Right-click / Ctrl-click occupied enemy | Red arrow. Fight card. Will-gate if not at war. |
| Second division into same fight | JOIN / 2v1. Does not rebuild the unit card. |
| Empty / post-break enemy hex | Occupy hop. No Fight box. Fill flips on walk-in. |
| Click own hex while this division has orders | Small **Cancel this division's orders?** Keep / Cancel. Click hex again = Keep. |
| Hover province | Name + controller only. |
| Click empty hex, nothing selected | Light glance (name, controller, terrain). |
| 1× | Org tick, occupy walk-in, sitting recovery. |

Odds: Likely / Tight / Bad (no %). Map fight chrome: small org plate only (NATO chips live on the Fight card). Country names shrink on zoom-in and slide toward the capital.

## Freeze catalogue (what actually died)

| RSS | Trigger | Real cost | Rule now |
|-----|---------|-----------|----------|
| 16–19 GB | Click Alsace | Inspector + 3520 supply | Command click never `show_info_panel` |
| ~20 GB | Linger hover | Tooltip / NUTS outline every frame | Once per hex; hover = name+owner |
| ~25 GB | 1× AI empty hexes | Occupation chain + composition | Occupy player-only; skip AI land battles |
| 13–25 GB | Mash stack | Rebuild UnitDetailPopup | Cycle patches text + NATO |
| 7–13 GB | Right-click fight + 1× | `CombatResolver` on `can_assault`; `composition_from_formation` daily | **Callee stubs** on F5 |
| ~10 GB | Shift-click | 80-hop GER BFS + inspector fallthrough | Adjacent waypoint only |
| 8–24 GB | Clicks, no 1× | Same resolver/TOE via missed callers | Stubs on the **API**, not MapRenderer |
| grey map | `has_method` on a class | GDScript class vs instance | Direct statics |
| “frozen” ~2 GB | Living title never closed | Overlay sat open | Auto-Begin GER 1936 |
| RSS tripwire silent | `int("1930516 kB")` → 0 | Parse `/proc` VmRSS | Parse first token; trip at 2.5 GB |

**Log tells:** `[AA] Defender AA` = CombatResolver still ran. `[DEMO COMBAT STOCK]` = TOE seed. `[pick] land unit` spam without cycle = card rebuild. `RSS tripwire` = 1× paused on purpose.

## UX misses we hit (and the fix)

| Miss | Why it felt broken | Fix |
|------|--------------------|-----|
| Stack not visible | One DemoUnitIcon per hex | Peeking plates + `1/3` badge (Node2D text, not Control Labels) |
| Cycle card, not map | Bind skipped `queue_redraw` | `_chip_set_text` + NATO path |
| Cycle didn't work | Chip click treated as neighbor hex | Distance-to-chip vs hex; other stack always selects |
| Div 0 attack bound div 5 | Arrow from hex centroid; dim never refreshed | Dim other arrows; skip dim in pick; refresh arrows on cycle |
| Can't order idle stack member | Chip steal + dim arrow steal | Adjacent hex if closer to that centroid |
| Fight card covered map | NATO pips on the map plate | Org plate only; chips on Fight card |
| Names huge / didn't scale | Labels not synced while paused; camera magnified Controls | Sync zoom while paused; `scale = 1/zoom`; slide toward capital |
| Own hex should halt | Halt existed only as a button | Confirm sheet: Keep / Cancel order |
| Ctrl-click froze stack | Still-click inspector / fight-from-chip | All Ctrl through deferred command |

## Stability architecture (skeptics, 2026-09-17)

| Option | Verdict |
|--------|---------|
| More `if light: return` at MapRenderer | **Veto.** Missed `_estimate_attack_power` repeatedly. |
| Combat on a worker thread | **Veto.** `CombatResolver` is a Node. |
| Watchdog only | **Veto as sole fix.** Click already allocated. |
| **Harden the callees** | **Shipped.** |

F5 stubs (`light_stub`):

- `CombatResolver.get_effective_combat_power`
- `LandCombatPower.composition_from_formation`
- `ProvinceInsight.get_battle_preview`
- `ProductionManager.get_division_final_combat_stats`

TimeManager: `_maybe_trip_rss_budget` every 45 frames; pause at **2.5 GB** VmRSS. Maginot still uses org × str × rdy, adjacent hops, occupy walk-in.

Machine greps: `living_unit_order_loop_product` `f5_callee_light_stub`, `f5_cheap_attack_estimate`.

## Headless vs F5

- Headless Maginot click-order: **will_gate → declare → start_battle PASS** (102 PASS before process died after fight open).
- `--quick` still has FAIL from hang-cuts (bubble no longer prints `CAS`/`ENC`; docked card stats; occupation ticks). Do not “fix” those by putting Control Labels back on the map.
- Graphical 1× after fight is **not** green. Treat occupy-after-win + 1× as still hang-class until RSS stays ~2 GB for a full Maginot break.

## Next combat loop (priority)

1. **Keep 1× under 2.5 GB** for a full Maginot break + occupy walk-in. If tripwire fires, log the last `[pick]` / `start_land_battle` and cut that callee.
2. **PlayLane extract** — one service owns click/tick combat so MapRenderer cannot grow new CombatResolver paths.
3. **JOINING** proven: second GER lists JOINING then ENGAGED (headless + F5).
4. **Taken card** after walk-in; then close.
5. **Per-unit occupy-after-win** — only `att_fids` that actually fought (already intended; watch GER_formation_4 auto-occupy).
6. Dual chips when GER occupy meets FRA retreat (optional later).
7. Notify scope UI (player / allies / all).

## How to play the next session

1. F5 GER 1936 **paused** (title auto-Begins).
2. Maginot chip → one right-click Alsace → Declare war if asked → red arrow.
3. `[` to the other division → click a **German** neighbor to march (should not join the fight).
4. Click own hex → **Keep orders** or **Cancel order**.
5. 1× until FRA breaks. If `RSS tripwire`, stop and paste the log.
6. Do not mash. One click, wait for toast.

## Files that landed this combat slice

Callee firewall: `CombatResolver.gd`, `LandCombatPower.gd`, `ProvinceInsight.gd`, `ProductionManager.gd`, `TimeManager.gd`, `LandBattleAttrition.gd`.

Orders / stacks: `MapRenderer.gd`, `OrderIntentLayer.gd`, `FormationMovement.gd`, `BattleManager.gd`.

Map chrome: `LandBattleBubbleLayer.gd`, `MapPoliticalLabelsLayer.gd`, `MapZoomLOD.gd`, `ProvinceHoverTooltip.gd`, `TestRunner.gd` (auto-Begin).
