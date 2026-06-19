# Strategic Region Control Rewards — Design & Implementation Notes

**Goal**: Make "fully controlling a strategic region" a *desirable, rewarding* achievement that elevates gameplay, creates meaningful objectives, and differentiates regions (some are worth bleeding for, others are nice-to-haves).

Modeled after (and expanding on):
- **HOI4**: Strategic regions for air superiority + weather. Controlling them matters for air wings, but limited direct "owner" rewards beyond the provinces inside. Supply areas give some throughput logic.
- **Victoria 3 / EU4**: States/regions as macro units with distinct economic, trade, or mission rewards. Full "state control" feels powerful.
- **Other inspirations**: Board wargames (control of key areas = VP or special rules), Terra Invicta (region control for boost categories), classic grand strategy where "the Ruhr", "the Mediterranean", "the Home Islands" have identity and asymmetric value.

## Current Implementation (as of this session)
- Adopted real names for the ~20 Europe theater strategic regions (British Isles, Low Countries, Western Germany, Scandinavia, Anatolia & Straits, etc.) into `data/provinces_full_europe/strategic_regions.json` and phase1 test copy. Province lists preserved.
- `ScenarioLoader` now stores full `strategic_regions` dict (id → {name, province_ids, notes}).
- `MapManager` exposes:
  - `get_strategic_region(id)`, `get_strategic_region_name(id)`, `get_all_strategic_regions()`
  - `get_fully_controlled_strategic_regions(tag)` — the key query: scans provinces and returns regions where *every* province's `owner_tag` matches.
  - `is_strategic_region_fully_controlled(rid, tag)`
  - `get_strategic_region_control_summary(tag)`
  - `get_active_regional_control_bonuses(tag)` — aggregates flavorful modifiers from `_regional_control_bonuses` table for all fully-controlled regions of that tag.
- **Live reward example**: In `SupplyManager._init_depot_states()`, if a depot province belongs to a region fully controlled by its owner, throughput_capacity gets a +12% bonus (visible in logistics game). This makes securing an entire "British Isles" or "Baltic Littoral" directly improve your supply network.
- Tooltip in `ProvinceInsight.build_inspector_conflict_section`: shows "Region: X [FULLY CONTROLLED] (+regional bonuses active)" when applicable.
- Data-driven bonus table in MapManager (easy to extend with more regions/bonuses as world map grows).

The system is lightweight, queryable from anywhere (AI, UI, combat preview, production, agents), and survives scenario overrides.

## Proposals to Elevate the Game (concrete, back-burner ready)
These turn regions into "strategic prizes" with personality. Different regions appeal for different playstyles (naval player wants the Approaches + Med; industrial wants the Ruhr + Silesia; expansionist wants Russia for depth).

1. **Asymmetric / Themed Bonuses (core proposal)**
   - Naval chokepoints (Anatolia & Straits, Atlantic Approaches, Danish Straits if added): +convoy efficiency, cheaper/faster sub or raider builds in-region, blockade strength multiplier, "Strait Mastery" spirit that reduces enemy amphibious success.
   - Industrial cores (Western/Central Germany, Low Countries, Poland & Silesia): factory output %, construction speed in region, "Economic Heartland" that gives extra civilian factories or research speed while held.
   - Resource regions (Scandinavia for iron/aluminum, Iberia tungsten, future Middle East/Persia oil): direct resource yield multipliers or "secured supply" that reduces convoy losses for that resource.
   - Defensive/terrain (Alpine & North Italy, Balkans, Scandinavia): defense bonuses, lower attrition for defenders, "Fortress Region" that increases entrenchment or org recovery for owner troops inside.
   - Prestige / Political (British Isles, Greece & Aegean): national morale/spirit gain, easier diplomacy or "influence" in adjacent areas, war support from holding "the cradle of..." .
   - Manpower/Depth (Western Russia, Central Russia Edge): +reinforcement rate, "Strategic Depth" that reduces effective combat width or increases recovery when fighting on home soil in/near the region.
   - Special flavor: "Control of the Mediterranean" (multiple regions) could unlock unique decisions, cheaper carriers, or permanent trade route buffs.

   Implementation: the existing `_regional_control_bonuses` + `get_active...` already supports this. Extend the table with 30-50 entries for world regions. Consumers (e.g. `ProductionManager`, `TradeManager`, `CombatResolver`, `SupplyManager`) read the keys they care about.

2. **Dynamic "Regional Spirit" or Temporary National Modifiers**
   - When you first achieve full control of a high-value region, grant a timed or permanent "National Spirit" (e.g. "Conqueror of the Low Countries" — small PP gain + construction bonus).
   - Losing full control removes or weakens it.
   - Integrate with existing `NationalSpiritManager` — treat full region control as an automatic "external spirit source".
   - Stackable but with diminishing returns or "overextension" if you hold too many distant ones.

3. **Victory / Score / Hidden Hand incentives**
   - Certain "key regions" (Home Isles, Western Germany, Anatolia, Western Russia) contribute heavily to victory points or "war score".
   - For the Hidden Hand / agent game: full control of a region gives massive detection or network strength bonuses inside it (harder for enemy agents to operate in your "secure" rear areas).
   - Peace conference: controlling a region at armistice gives negotiation leverage or claims on its resources/infra.

4. **AI & Player Psychology**
   - AI values full control of themed regions higher in planning (e.g. Japan cares about certain Pacific regions; Germany prioritizes contiguous Europe ones).
   - Player goals: "Secure the Baltic before Barbarossa", "Take the Isles to strangle convoys", "Grab Scandinavia for the resources before winter hits".
   - Creates natural "theaters" even before we have 1000+ provinces.

5. **Future World-Scale Polish**
   - When we define 60-80+ world strategic regions (using the chunked map + natural features from the raster layers), each gets 1-3 bespoke bonuses.
   - "Control of the Persian Gulf", "Dominance of the South China Sea", "Siberian Resources", "American Industrial Heartland" become late-game magnets.
   - Combine with weather/seasonal (full control of Arctic regions mitigates your own winter penalties).
   - Visual: on the map, fully controlled regions could get a very subtle overlay tint or icon (optional, toggleable like the veg layer) so you *see* your empire's "secure zones".

6. **Data & Tooling**
   - Move the bonus table out to `data/national/regional_control_bonuses.json` (per-region or per-name) for modders/designers.
   - Generation pipeline (map_generation) can suggest initial bonuses from real data (e.g. high iron provinces → resource bonus in the containing region).
   - In ProvinceEditor or debug: button "Highlight fully controlled regions for GER".

## Next Steps (prioritized)
- Extend the bonus table with 10-15 more Europe + early world examples.
- Hook bonuses into 1-2 more systems (e.g. Trade convoy efficiency, a combat width or org modifier in ProvinceEffects when fighting inside a fully-controlled friendly region).
- Add a simple "Regional Control" section to the TopInfoBar or a new ledger screen ("Empire Ledger" showing controlled regions + active bonuses).
- When doing the full world region definition pass, ensure every strategic region has at least one desirable bonus so no "dead" areas.
- Optional LOD: very large regions (future world) can have "core" sub-areas that are the real prize.

This system, combined with the real-world raster layers, named regions, chunked world map, and future inference of terrain from the data, will make the map feel alive and worth fighting over at every scale — from a single supply hub to "who controls the approaches to Europe?"

See also: `MapManager.gd` (bonuses + queries), `SupplyManager.gd` (example application), updated `strategic_regions.json`, `ProvinceInsight.gd` (UI), and the world chunks / REAL_WORLD_MAP_LAYERS.md for the broader map strategy.

## Development Scope Recommendation: Europe-First vs Full World

**Short answer:** Do focused Europe development and testing *now*. The full world is already captured as the consistent source of truth (rasters + chunks + river data). This will *not* cause major "province relations / distance / terrain shifting" problems later if done carefully.

**Why Europe-only testing is safe and recommended for velocity:**
- Province gameplay (ownership, adjacency, supply paths, combat, distances) is entirely driven by the loaded province set + its geometry/adjacency data. These are modular per `data/provinces_xxx/` and per scenario.
- When you load a Europe-only scenario, only those ~460 provinces exist in the graph. Pathfinding, distance costs (mostly graph-based with some pixel-space), relations, etc. are self-contained. No "leaking" from missing world provinces.
- The raster underlays (the pretty map image + hillshade + rivers) are purely visual. The authoritative positions are the province polygons in the JSON geometry. The chunks we generated from the full world raster use the same overall coordinate space (0,0 origin, pixel units), so when you later add provinces in other world chunks, the visual terrain will match the real geography without shifting.
- This matches the original design intent (Phase 1 = high-quality Europe grand theater first, then expand).
- You can iterate, balance region control rewards, naval play in the approaches, named strategic regions, pride bonuses, supply, etc. much faster on a coherent 460-prov theater than on a sparse world.

**When to bring in more world:**
- Once the Europe theater feels deep and fun.
- Add new provinces by extending the geometry (future pipeline work) while referencing the pre-generated world raster chunks or higher-zoom sub-extracts for visual fidelity.
- Global strategic regions can be defined in one master list; a scenario simply only activates the provinces (and thus the regions) it cares about.
- Naval/convoy paths and far resources will feel incomplete until you expand, but that's expected and can be stubbed or limited in Europe-focused scenarios.

**Risks of rushing the full world too early:**
- Authoring and balancing 1200-2000 provinces + their states/regions + special sites at once is a huge amount of work.
- Performance testing (picking, rendering, supply pathing) is much harder with a giant map.
- You lose focus on making the *core experience* excellent.

**Practical hybrid we have in place:**
- Full consistent world raster + chunks already generated and chunked to ~Europe canonical size.
- Europe high-detail (z=5, 5000x2000) as the primary working canvas.
- Named strategic regions + full control reward system (now including population pride) ready to scale.
- Debug chunk loader to experiment with "other parts of the world" visuals without breaking current work.

Keep rolling on Europe depth + the reward system. The world foundation is solid underneath.

## Update: Population / "Proud of Being United" Bonus (2026-06-13)
Per request, added explicit support for population pride when a region is fully controlled.

- New key in the regional control bonus table: `"regional_pride": 0.XX`
- This is consumed in `ProvinceEffects` (in addition to the general full-control bonuses).
- Effects when a province is inside a fully-controlled region of its owner:
  - Increased `reinforcement_speed` (troops reinforce faster because the local population is motivated and supportive).
  - Increased `manpower_recovery` / effective manpower contribution.
  - The inspector now calls out "Local population proud & united" for such regions.
- Themed values have been given to the current Europe regions (e.g. higher pride for island nations like British Isles and Greece & Aegean, hardy mountain folk in the Alps and Scandinavia, etc.).
- This makes "uniting the region under your flag" feel like it actually improves the human element of the war effort.

This is the start of making regions have distinct "souls". Future expansions can tie pride into stability, war support, agent detection risk, or even local construction speed.
