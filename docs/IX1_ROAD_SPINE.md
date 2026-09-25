# IX-1 Road Spine — Layer 2 first interconnect vertical

**Status:** theater proof + Mandate front-door PASS + day-tick FIX (draft; **HOLD merge** for Scott/Play).  
**Slice name:** **IX-1 Road Spine** (not Dig2, not G polyline, not Maginot combat).  
**Layer:** Mike Layer 2 — player actions must **show** on the map and **change play**.

## Before / after

| | Before (tip `eb4371d`) | After (this slice) |
|--|------------------------|--------------------|
| Player order | Invest raises an infra **number** + construction ring. F10 Invest is debug. | Inspector **Build Road Spine** on the corridor starts a real Invest-style project (ETA / bar / ring). |
| Road edges | `Province.built_road_neighbors` + `MapManager.build_road_connection` existed but were not a front-door order. | Complete calls `build_road_connection` on the corridor edges. |
| Look | RoadLayer Line2D existed; political / F1 hid it; F10 / Infra mapmode only. | Explicit spine Line2D stays visible at playable mid-zoom (`z > 0.10`) without F10. |
| Impact | `get_movement_cost()` used infra only. | Infra +1 **and** a `built_road_neighbors` discount. Spine move/supply cost is **strictly less** than pre-build and cheaper than off-spine Essen at the same starting infra. |

## Theater (one corridor)

Home Europe, GER-owned at 1918 / 1936 start. **Rhineland / west-German city spine**, not Maginot combat hexes.

| ID | Name | Role |
|----|------|------|
| **710417** | Köln, Kreisfreie Stadt | Hub — one order builds both edges |
| **710416** | Bonn, Kreisfreie Stadt | South endpoint |
| **710418** | Leverkusen, Kreisfreie Stadt | North endpoint |
| 710403 | Essen, Kreisfreie Stadt | Off-spine **control** (same starting infra, no road) |

Edges: `710417–710416`, `710417–710418`. Three adjacent owned plains cells. Spec: `data/infrastructure/ix1_road_spine.json`.

## Mandate front door (FIX)

Fresh **Begin · Germany · 1936** has Mandate **0** (`peace_state.mandate` map empty). Generic Köln Invest is still **73** and stays gated. The IX-1 order uses a **first-session starter grant** (`first_session_mandate_cost` **0** in `data/infrastructure/ix1_road_spine.json` / `get_ix1_road_spine_mandate_cost`). No F10 / debug cheat. Headless: `ix1_day0_mandate_can_start("GER")` and `HeadlessIx1RoadSpineMandateGateTest.gd`.

## Day-tick FIX (clock + spine progress)

An active spine used to stall the F5 clock (~7 Jan 20:00 @ 4× / ~9 Jan 20:00 @ 1×, spine ~17–20%) while Godot stayed hot. Cause: `advance_daily_projects` only runs the full-board `ai_consider_daily_invests` (3520×N) when **any** project is live, and each progress notify rebuilt the inspector. F5 already budgets 1 AI infra start/day — the continent consider is skipped under `is_interactive_light_sim` **and** any graphical DisplayServer (editor/export Play / softpipe). Budgeted AI pick is capital/neighbors only (never `get_provinces_by_owner`). Remote AI starts do not toast/notify. Day-emit no longer walks 3520 feature rings.

After that +2 fix held, live F5 still froze ~6–7 Jan (+5/+6d) at ~10GB RSS: calendar `save_game_detailed` on elapsed%7==0 plus a 3520 harvest walk on day +5. Live F5 / `is_live_f5_play_path()` now **skips** automatic 7d + quit autosave (Ctrl+S unchanged; autosave JSON is compact). Harvest is player-owned only (cap 96). Hierarchy dump and network pulse stay off on that path.

Spine-pin CA `36485b9` then **regressed live clock vs `5732d34`**: Play stuck at **1 Jan 1936 00:00** (~272% CPU) while headless day-tick still PASS. Cause class: `is_live_f5_play_path()` deferred to `is_interactive_light_sim()` (headless-only equiv flag papered over windowed DisplayServer); MapRenderer day_emit / feature rings were light-sim-only; live-equiv gate called `advance_days` and never the TopInfoBar `advance_real_time` hour path; Search leftover focus swallowed Space. Fix: any windowed DisplayServer is live F5; day_emit + ring walk gate on `is_live_f5_play_path`; reveal re-entrancy (no second inner layout); Begin releases Search focus; TopInfoBar `_input` Space + 00:00 watchdog; `advance_live_f5_equivalent_hours` + `past_hour_plus6`. Search Go + Build Road Spine chrome pin **kept**. Headless: `simulate_ix1_spine_days` + `simulate_live_f5_day_advance` (**hours past +6** then **+8d past +6**, consider=0, autosave gathers=0) in `HeadlessIx1RoadSpineDayTickTest.gd`. Mandate front door unchanged.

## Player path (smoke)

1. Default F5 GER, Home Europe. Type **Köln** / **Cologne** / **Koln** / **Koeln** in the live Search **LineEdit** and click **Go** (or press Enter) — the button `pressed` / `text_submitted` signals call `open_province_inspector_from_search` (not a dead control after living title / +6d). Province inspector opens with **Build Road Spine** pinned on the chrome next to Settle (and as the first facility Build row) — not buried under Heavy Water / Kiel Canal construction rows, not Garrison, not silent. Miss toasts if resolve fails. Soft pan only (no tactical 2.4). Alt-click or empty-terrain on **Infra / Build** is the backup path. Esc / Close on Garrison restores the inspector; idle Esc still opens Command Center (Search focus is released, not a swallow).
2. Inspector **Build Road Spine** (not F10). Day-0 Mandate **0** is enough. Construction ring + ETA bar while the project ticks.
3. On complete: toast / news **Road spine complete**; RoadLayer paints the brown spine at Home zoom; inspector refresh.
4. Move / supply on the corridor is cheaper than the same province pre-build and cheaper than Essen control.

## Shipped APIs (reused, not reinvented)

- `Province.built_road_neighbors` + `MapManager.build_road_connection`
- `InfrastructureOverlayLayer` RoadLayer Line2D
- `InfrastructureDevelopmentManager` Invest projects / construction rings
- `Province.get_movement_cost()` + `SupplyPathfinder` (already consumes movement cost)
- `FormationMovement._infra_unit` uses the same road bonus so hops on-spine are cheaper

New front door: `InfrastructureDevelopmentManager.try_start_road_spine` / `link_ix1_road_spine_edges`.

## PASS criteria

1. SCRIPT_ERROR **0**. Esc → Command Center **HARD PASS** unchanged.
2. **Look:** readable road line on Bonn–Köln–Leverkusen at playable zoom (not F10-only).
3. **Impact:** spine `get_movement_cost` **strictly less** than pre-build; cheaper than off-spine Essen control.
4. Thin unittest `test_ix1_road_spine_product` green (edges present + cost delta + GER 1936 day-0 Mandate gate).
5. Tyrrhenian / Ligurian / Flanders / SE England / pale-map / Fill%·TOE **untouched**.

## PARKED (do not open from this PR)

- Dig2 pan / old G polyline dig / Maginot combat — IX-1 is a **new** named slice
- Rail network vertical (IX-2)
- Industry placement vertical (IX-3)
- Hampshire land residual
- Continent-wide road mesh
- Channel / Italy / SE England land rewrite
- Godot version bump
- `world_full` / play-board ID renumber
- Dual packages

## HOLD merge

Draft PR only. Do **not** merge until Scott unlocks a Play SHA.
