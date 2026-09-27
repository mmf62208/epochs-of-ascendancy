# RX-1 Rhine Crossing — Phase B first river vertical

**Status:** theater proof + edge rules + Build Bridge on the IX-1 calendar tick (draft; **HOLD merge** for Play).  
**Slice name:** **RX-1 Rhine Crossing** (not Dig2, not Maginot combat, not hills/relief, not road tiers).  
**Layer:** Mike Layer 2 — the river must **read** on the map and **change play**.

## Before / after

| | Before (tip `1d092a14`) | After (this slice) |
|--|-------------------------|--------------------|
| Rhine look | Raster river bake; stored `rivers_world.json` Rhine 321 Y is mercator (~1781–1864), so it does **not** sit on NUTS3 Köln. Play MIXED `9750f3d`: vector sat at z=7 under DemoUnitIcon z=28. Play MIXED `816cdc9`: z=36 still sat under nation Labels (z=40) and `draw_line` 2.8 was world-space (sub-pixel at mid zoom). | Vector polyline, invert mercator-Y then `lonlat_to_canvas`. Köln d≈0.05, Bonn 0.45, Düsseldorf 0.36, Duisburg 1.36; Essen 7.03 **off**. `_draw` only — no rebuild on zoom. **FIX2 (scope change):** course × `THEATER_SCALE` 1.728; screen-space `RIVER_SCREEN_PX=7` / halo 14; **units stay on top** (labels 18 < river 22 / roads 21 < DemoUnitIcon 28). Nation names fade/hide at close zoom so they do not bury the river. Gold `ROAD_EXPLICIT_COLOR` for the built spine. View-only **Units** HUD + **U**. |
| Crossings | `has_river_border` + flat **0.97** per-province. `province_adjacency.json` is shared-edge + kNN (non-touching pairs). | Six **GISCO shared-border** edges the Rhine actually sits on. Guard fails if a listed edge is not a real shared border. Köln–Essen is **not** a crossing. |
| Bridges | None as a named 1936 fact. | Historical road bridges at the cities. Neuss–Mettmann left **unbridged** so Build Bridge has a target. |
| Player order | Invest / IX-1 spine only. | One **Build Bridge** order on the IX-1 IDM project + FIX3 `_tick_live_construction_on_calendar_day`. |
| Rules | Flat 0.97 on any river hex. | Edge-level named constants. Stacks with the IX-1 road hop discount. |

## Theater (never renumber)

`provinces_pilot_europe_nuts3`, `id_base` **710000**.

| ID | Name | Role |
|----|------|------|
| **710417** | Köln, Kreisfreie Stadt | On the river (centroid left/west). Bridged to Leverkusen + RBK. |
| **710416** | Bonn, Kreisfreie Stadt | On the river. Bridged to Rhein-Sieg (1898). |
| **710401** | Düsseldorf, Kreisfreie Stadt | On the river. Bridged to Neuss (Oberkasseler 1898). |
| **710402** | Duisburg, Kreisfreie Stadt | On the river. Bridged to Wesel (F-Ebert 1907). |
| **710403** | Essen, Kreisfreie Stadt | **Off-river control.** |
| **710413** | Rhein-Kreis Neuss | Left/west. Unbridged to Mettmann — **Build Bridge** target. |
| **710412** | Mettmann | Right/east. Unbridged to Neuss. |
| 710418 | Leverkusen | Bridged to Köln (Deutz 1915 / Mülheim 1929). |
| 710424 | Rheinisch-Bergischer Kreis | Bridged to Köln. |
| 710425 | Rhein-Sieg-Kreis | Bridged to Bonn. |
| 710415 | Wesel | Bridged to Duisburg. |

Spec: `data/map/rx1_rhine_crossings.json`. Generator: `tools/map_generation/scripts/generate_rx1_rhine_crossings.py`.

## Face-bank convention

The Rhine flows **north** on this stretch. Bank sign is the 2D cross product of the downstream tangent with the vector from the nearest Rhine point to the NUTS3 centroid. Negative = left/west, positive = right/east. Cities that span both banks use their **centroid bank** — never a dual-bank special case. A listed crossing is opposite center-banks plus a real GISCO shared border that sits on the Rhine.

## Tunable constants (single place)

Mirrored in the JSON spec and `Rx1RhineCrossing.gd`:

| Constant | Draft value |
|----------|-------------|
| `RHINE_UNBRIDGED_MOVE_MULT` | **2.0** |
| `RHINE_BRIDGED_MOVE_MULT` | **1.15** |
| `RHINE_UNBRIDGED_ATTACK_MALUS` | **0.30** |
| `RHINE_BRIDGED_ATTACK_MALUS` | **0.10** |
| `first_session_mandate_cost` | **0** (same class as IX-1 spine starter) |

Applied at **edge** level in `FormationMovement._hop_cost_into`, `SupplyPathfinder._edge_cost`, `CombatResolver.resolve_combat`, and `BattleManager` preview/log. The theater skips the old flat 0.97 / 1.05 river hex multipliers.

## Build Bridge

Reuses IX-1: `ProvincialProject.build_rhine_bridge` + `bridge_edge`, Mandate-0 first-session grant, visual states **queued / construction / built**, progress via `_tick_live_construction_on_calendar_day`. Complete calls `Rx1RhineCrossing.set_bridged`. Inspector shows `Rhine crossing: bridged` / `Rhine crossing: no bridge` plus hop × and attack −%. Blow/capture is **OUT**.

## Alignment evidence

Stored Rhine 321 canvas Y ~1781–1864 is the world_full mercator bake (`use_mercator_y=True`). NUTS3 uses `ne_full_geometry_align.lonlat_to_canvas` (equirectangular, WORLD_BBOX=(-180,-56,180,83), 8192×4096). Invert via `pixel_to_lonlat_merc`, reproject. Distances after that (canvas units): Köln 0.051, Bonn 0.446, Düsseldorf 0.355, Duisburg 1.361, Essen 7.033.

## Guards

| Guard | What it proves |
|-------|----------------|
| `test_rx1_rhine_crossing_product` | Alignment, GISCO shared-border, constants, IX-1 APIs still present, shipped needles. |
| `HeadlessRx1RhineCrossingTest` | Edge penalties, bridged vs unbridged, no Köln–Essen, Build Bridge complete. |
| `HeadlessRx1RhineLiveStayAliveTickTest` | Real `advance_real_time` under stay-alive: 0% → >0 in ~5d → COMPLETE. |
| `tools/eoa_rx1_bridge_live_progress_guard.sh` | Windowed smoke: viewport mouse on Build Bridge. **Not the product.** |
| `HeadlessRx1RhineVisibilityTest` | Units on top: labels 18 < river/road < DemoUnitIcon 28; screen-space widths; gold spine; U + BtnUnitsView; spine chrome absent on Neuss 710413; `run_godot.sh` import-if-needed. |
| `HeadlessRx1RhinePanelStateTest` | Köln never re-offers Build Road Spine after built; bridge chrome only on Neuss 710413 / Mettmann 710412. |
| `tools/eoa_rx1_pixel_guard.sh` | **WINDOWED** (xvfb) live `TestScenario` captures. Units OFF: Rhine + gold spine at mid/close. Units ON: counter pixels win over the river. U hide/restore, sim unchanged. Real PNGs, not mocks. Smoke harness is **not** the product. |

Must **FAIL** on `816cdc9` (pixels + Köln re-offer + bridge leak) and **PASS** on this tip. IX-1 headless + python stay green. The FIX1 z-order check alone is not evidence — Play MIXED `816cdc9` passed it while the screen stayed empty.

## FIX2 (Play MIXED `816cdc9`)

Root cause of the empty screen:

1. Spec course points are **8192-space**; the live `world_accurate` board is × `THEATER_SCALE` 1.728, so the polyline sat near 4254,944 while Köln is 7351,1631 — off the framed Rhineland.
2. `draw_line` / Line2D widths were **world units**, so at mid Camera2D.zoom a 2.8u stroke is ~1 screen pixel.
3. `MapPoliticalLabelsLayer` nation Labels use `z_as_relative=false` **z=40**, which paints over Rhine z=36 and RoadLayer z=32 — "Netherlands" / "Belgium" / "Luxembourg" bury Köln at close zoom.

FIX1's z-order guard only compared 36>28, so it passed while the pixels failed. A first windowed capture also stayed on Europe Home until the guard locked MapCamera (TestRunner deferred `center_europe_in_world_view`).

Köln after `state=built` re-offered **Build Road Spine** because `should_show_road_spine_button` ignored built edges and `_ix1_should_show_spine_button` fell through after a false. The Köln panel also kept Neuss's `Rhine bridge 100% · ETA 0 days` because `_update_rhine_bridge_button` returned early without hiding `_label_rx1_progress`.

### Scope change (units on top + view-only U)

Owner: undo the FIX1 raise that put Rhine z=90 / roads z=88 above DemoUnitIcon z=28. Map layers sit **below** units. Keep theater-scale, screen-space widths, close-zoom label hide, Köln built state, and status-leak scoping.

- z stack: nation Labels **18** < RoadLayer / spine **21** < Rhine **22** < DemoUnitIcon **28**
- **U** = show/hide unit counters + stack chips / selection rings / pin pulse / battle bubbles. Default **shown**. View-only — no sim, selection, orders, or save data. Search LineEdit focus swallows U. **Shift+U** is supply/sealane flow (was plain U).
- HUD `BtnUnitsView` on the time-speed strip stays in sync with the hotkey.
- Built spine uses gold `ROAD_EXPLICIT_COLOR` (0.92, 0.62, 0.08) so the pixel sample cannot pass on tan land.

### Windowed pixel guard (real captures, not mocks)

`tools/eoa_rx1_pixel_guard.sh` — xvfb + `tools/run_godot.sh` + live `TestScenario` (`world_accurate`). Never `EOA_SKIP_TITLE`. Smoke harness is **not** the product.

**816cdc9 has no Units toggle.** The guard hides `DemoUnitIcon_*`, `StackBadge`, `PinFocusPulse`, `LandBattleBubbleLayer`, and `SelectedFrame` by walking the tree (`_hide_unit_nodes_direct`) so units-OFF river/road samples are not covered by chips. Tip uses `set_unit_counters_visible` (view-only API).

Guard table (filled after xvfb runs):

| Check | `816cdc9` | tip |
|-------|-----------|-----|
| mid river, units OFF (need ≥0.18) | pending xvfb | pending xvfb |
| close river, units OFF | pending xvfb | pending xvfb |
| gold spine, units OFF (need ≥0.20) | pending xvfb | pending xvfb |
| units ON: counter pixels win over river | pending xvfb | pending xvfb |
| U hide → U restore, sim unchanged | pending xvfb | pending xvfb |
| Köln offers Build Road Spine after built | **true FAIL** (prior) | **false PASS** (prior) |
| Köln shows built state | **false FAIL** (prior) | **true PASS** (prior) |

PNGs go to `/tmp/eoa-rx1-pixel-816cdc9/` and `/tmp/eoa-rx1-pixel-tip/` (also `/opt/cursor/artifacts/rx1-pixel/`).

## Fresh checkout (FIX1)

Stale `.godot/global_script_class_cache.cfg` (gitignored) used to parse-fail GameData (`Identifier Rx1RhineCrossing not declared`) and blank the map. `tools/run_godot.sh` runs a one-time `--headless --import` when the cache is missing or lacks `Rx1RhineCrossing`. Autoloads (GameData / MapManager / IDM) **preload** `res://scripts/map/Rx1RhineCrossing.gd` so they do not depend on class_name at parse. Smoke wrappers already `exec` `run_godot.sh`.

## Later (not this slice)

Move ETA **preview UI** — there is no preview today; inspector hop × / attack −% is the living copy. Do not invent a preview here.

## Parked

Bridge blow/capture · rail / pontoon · Mosel / Main / Ruhr / Sieg · hills/relief RL-1 · road tiers · Dig2 / Maginot / Hampshire · unit LOD.
