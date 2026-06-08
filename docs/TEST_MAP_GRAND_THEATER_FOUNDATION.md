# Test Checklist: New Map Grand Theater Foundation (UK/Ireland + Scandinavia + Northern Russia)

**Context**: Expanded map scope for war in the west (Germany central visible). High-detail bg images (hills, swamps, rivers visible on zoom, fjords, full British Isles, long Norway coast, Finnish lakes, Kola/N Russian high north tundra+forest, + prior south NA/ME). Dynamic layers (infra roads/rails/cities/sites), data-driven object placement from gen + starter visual editor for "leveling", seasonal/damage/era variants in data, desert infra allowed sparsely, non-uniform regional snow, etc.

**Prep**:
- Run: `python3 tools/map_generation/scripts/generate_europe_phase1.py --output tools/map_generation/output/phase1_europe` (refreshes visual features/variants JSON with new GRAND THEATER scope + heavy north snow notes).
- Place final upscaled art in `assets/maps/europe_grand_theater_ultra_high.jpg`. **Current file on disk is a ~450 KB placeholder** — sufficient for wiring/QC, not for true close-zoom 8K detail. Replace when the master image is ready.
- Launch via F5 on `scenes/TestScenario.tscn` (default harness). Use Debug panel (F10) heavily.
- Have mouse wheel/middle-drag/WASD for camera, R/T/C/Y for infra layer toggles (from prior TestRunner).

## Visual / Background Image Tests (Core "the map")
1. On load: does a detailed parchment-style map image appear under the province polys/outlines (not just vector outlines)? "no map images our outline loads" regression?
2. Pan west (left) and north (up, smaller y): can you reveal extra geography painted for UK full (Ireland island, Scotland, England, Wales), Scandinavia (Norway fjords long, Sweden, Finland lakes), northern Russia (Kola, Murmansk-ish area, White Sea, high north)?
3. Zoom in (wheel) on a river area (any major river or tributary in UK/Scand/NRus or central): are river courses, bends, and some detail visible/sharp without immediate pixelation or blur? (High quality for "zoom to see details of a river etc.")
4. Zoom on coast/fjord (Norway or UK Scotland/Ireland): jagged coasts, islands, inlets visible?
5. Zoom on varied terrain: hills/mountains (ridges), swamp/marsh patches, forest vs open, desert (south if panned) — all differentiated?
6. No visible country borders or text/labels on the bg image itself.
7. Switch variants if available (Debug or TestRunner buttons for winter/damaged): does a heavy snow version appear for northern areas (deep in N Russia/Scand/Norway north, lighter UK north, none or minimal in south/NA/Egypt)? Non-uniform seasons working visually?
8. Damaged 1944 variant (if loadable): bomb damage cues visible in relevant areas (e.g. industrial UK/Germany, Leningrad approaches)?
9. Performance: zoom/pan around the larger image — no lockup, no massive resource spike, culling keeps node count reasonable (see prior throttle fixes). Test on the padded bg rect.
10. With current assets (pre-new-image): the underlay still covers at least the loaded polys cleanly (approx fit).

## Data / Python Tool + Layers Connection
11. After re-running the python script: inspect `tools/map_generation/output/phase1_europe/map_visual_features_variants_phase1.json` — "expanded_region" mentions full UK/Ireland + Scand + N Russia high north + south? Variants include winter (for north), desert_infra, etc.?
12. Load "Phase 1 Test Scenario" or "v3 as Playable" via Debug "Map Gen — Phase 1" section. Does it use ~180 or current provinces + apply the bg + spawn data-driven objects (cities as rects or proxies at gen positions inside polys on the bg)?
13. Infra sub-layers (R=roads, T=rails?, C=cities, Y=sites from TestRunner): toggle on/off. Do they draw on top of the new larger bg image? Can you see dynamic roads/rails following terrain hints in the image?
14. Special sites / ports / airfields from layers visible or buildable in northern or UK areas (even if no poly yet, or on existing)?
15. Naval/coastal: with UK/Ireland/Scand/NRus in scope (even visually), do coastal/chokepoint highlights or naval analysis in plan still make sense? (Future polys will enable.)

## Starter Map Visual Editor (Debug "Map Visual Editor (Starter)" section)
16. Toggle "Toggle Map Visual Editor" ON. Status label updates? (Editor ON allows LMB placement.)
17. With editor ON: pan to a desired spot on the (new scope) bg image (e.g. a UK river valley, Norwegian fjord coast, Finnish lake area, or desert south). LMB click: does a demo "city" proxy appear roughly at the click world location (tied to image)?
18. Use "Place Demo City at View Center", "Place Demo Airfield (terrain aware)": different visual (size/color) proxies appear? Airfield etc. "terrain aware" (e.g. different tint for hypothetical hills/swamp/desert)?
19. Place several (mix city/airfield). Then "Export Placements to JSON...": console shows data with positions, types, notes about terrain/desert/hills? JSON stub ready for roundtrip?
20. "Clear Demo Objects": removes the manual editor ones (data-driven spawns from city_layer may respawn on reload/bg re-apply).
21. Editor objects persist visually with bg + polys + infra layers? (under DataDrivenObjects node).
22. While editor ON, does LMB not interfere badly with UI buttons (Control input precedence)?

## Placement / Leveling / "Objects tied to areas on the map"
23. Data-driven spawns (from province_city_layer + terrain): on test load or bg apply, do proxy objects (cities etc.) appear at the positions from the layer JSON, inside the current province polys, on the bg image?
24. Terrain awareness in spawns: if any current or test provinces have hills/swamp/desert (from visual features or terrain_layer), do their spawned proxies use adjusted colors/sizes (sandier/smaller for desert, etc.)?
25. Can "level up" feel: place additional editor objects near/inside a province area on the image (e.g. add extra buildings, an airfield inside a poly bounds). They visually "belong" to that province's part of the map.
26. Future roundtrip: the export JSON format + python visual layer ready to ingest placements back into city_layer or to drive new Imagine prompts?

## Connections, Robustness, No Bugs/Regressions
27. Full launch: TestScenario or main loads without crashes, no infinite loops, no "locks the computer or uses a lot of resources". (Throttles, culling, preserve raster in clear, etc. still active.)
28. Debug panel: fully usable (scroll, drag, not cut off on sides, TopInfoBar compaction if any, all sections including the new visual editor + phase1 mapgen buttons). No missing handlers.
29. Camera: pan/zoom/wheel/middle drag/WASD work over the larger image area. Starting view reasonable (Germany/central visible, easy to pan to new UK/Scand/NRus parts of bg). No hard limits clipping the new scope.
30. Bg + vectors + overlays together: province polys (outlines/fills), labels, units (NATO if spawned), infra layers, data objects, editor objects, detail overlay, legend — all visible and layered correctly on the bg. No z-order or culling eating the image.
31. Variant / season notes in data: even if not all visual swaps wired yet, the python variants (heavy north snow, desert_infra styles, era/culture) are in the JSON and comments in code acknowledge non-uniform + bomb damage + culture/tech impact on architecture.
32. Desert handling (south if visible): can conceptually place (or see hints for) roads/buildings/rail/airfields/ports in desert areas of the image? (Sparser in spawns, sand styles in variants.)
33. UK/Scand/NRus specific: when panning there, the bg shows appropriate terrain (fjords for Norway ports/air, lakes for Finland, tundra/high north for Russia, full islands/coasts for UK/Ireland). No "missing map" in those directions.
34. Save/load or reload test scenario: bg, objects, layers, editor state (or lack) behave reasonably.
35. No new parse/runtime errors on launch or heavy use of debug/editor/map (the center-on-Province, load-new, inference fixes applied).
36. (Stretch) If you have a new gen image loaded: zoom deep into a river or small port in UK or Norway — detail holds up.

## Separate Terrain Layer (Clean View) + Editor Curation Tools (from user image feedback)
37. On first load (plain WorldMap or TestScenario): confirm HIGH QUALITY LARGER 8K+ print, and the upscaled grand theater stylized map (the one in user image left) is the FULL underlay (no grey/black world_map or small overlay in center or bottom-right). Pan/zoom shows it full scope.
38. Open Debug -> Map Visual Editor: "Toggle Terrain (clean view / no terrain)" button present with tooltip. Click it: high-res raster disappears, province fills become solid/opaque political colors (clean ownership view, no terrain clutter). Click again: raster returns, fills thin so image terrain visible.
39. With clean view (terrain OFF): does it help focus on strategy elements? (per HOI4/EU4 reviews: yes, many players prefer clean political 99% for borders/infra/ownership readability; detailed terrain loved for immersion but toggled when needed). Editor placements still visible.
40. Toggle back ON: detailed image returns as the terrain layer.
41. Editor improvements: with Visual Editor ON, LMB clicks place demo city precisely at mouse (high zoom on terrain features in image, using _screen_to_world camera inverse - no far/wrong pos). Pan + LMB to position exactly.
42. Place several via LMB + Place buttons (city/airfield/port/factory). "Placed Objects" list appears below in section, populated with type @ x,y entries + "Del" buttons per row.
43. Click Del on a list item: node removed from map, meta updated, list refreshes (no more entry).
44. "Refresh Placed List", "Export Placements to user:// JSON", "Load Placements (JSON roundtrip)": work? Export writes user://map_editor_placements.json with positions/types. Load reads it and re-spawns at exact stored coords (for python roundtrip curation of placements on the high-res image).
45. Clear + list: after clear, list goes empty or shows only live data-driven.
46. While editing at close zoom (max 12x), high-res holds detail, no old map bleeds through even after toggles/renders. Weather (snow tint on raster or veil, blackout) still functions (test Force Snow etc while terrain on/off).
47. Judgement recorded: separate terrain layer = YES, good design (see research in chat: HOI4 players/mods want clean political to avoid clutter; EU4 political popular vs default terrain; clean mode ideal for editor + strategy overview).

## Known Limitations / Next (for awareness during test)
- Current ~100 (or 180 merged) seed geometry has limited/no polys in new UK/Scand/NRus areas (names didn't match before). Visual bg + future subdivision or added base provinces will populate clickable provinces there. Test the *image* coverage + editor placement now.
- Image registration is artistic/approximate (new gens composed for the lat/lon, code uses padded rect + dynamic pixel scale). Exact province point coords may not perfectly land on "London" or "Murmansk" in the picture yet — that's for geometry work.
- Some overlays (roads detail, legend) are still from prior smaller images; they may look offset or low-res on a new grand bg.
- Full seasonal/bomb/era visual swapping (multiple bgs or shaders) and culture-specific building sprites are noted in data/variants but not fully wired in renderer yet (editor + layers are the immediate tools).
- Performance on very large image + deep zoom: watch VRAM/GPU (mipmaps help).

**Pass criteria**: Launch clean, see the expanded geography in the bg when panning, river/terrain zoom detail, editor lets you place objects on the new areas of the map, all prior infra/layer/editor connections still work, no major regressions or resource issues. Report any broken buttons, missing spawns, camera clips, or visual misalignments with exact repro.

Run the python, drop a new image if desired, launch, and work through the sections in Debug while panning the map. This exercises the full foundation (python -> data -> renderer bg+placement+editor -> layers -> camera -> debug UI).

Happy testing! If issues, share logs + screenshots of Debug + map view.
