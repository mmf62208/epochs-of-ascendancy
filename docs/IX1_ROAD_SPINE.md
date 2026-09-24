# IX-1 Road Spine — Layer 2 first interconnect vertical

**Status:** theater proof on tip `eb4371d` (draft; **HOLD merge** for Scott/Play).  
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

## Player path (smoke)

1. Default F5 GER, Home Europe. Pick **Köln** `710417` (or Bonn / Leverkusen).
2. Inspector **Build Road Spine** (not F10). Construction ring + ETA bar while the project ticks.
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
4. Thin unittest `test_ix1_road_spine_product` green (edges present + cost delta).
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
