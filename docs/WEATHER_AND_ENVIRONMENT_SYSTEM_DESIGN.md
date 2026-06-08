# Weather, Seasons, Extreme Events & Environment System Design
## For Epochs of Ascendancy (Grand Strategy Map + Combat + Economy)

**Goals (from user spec)**:
- Robust but **lightweight / non-laggy** (no per-frame heavy sim for 400+ provinces).
- **Visual snow/rain/fog/storm layers** on the map (mostly hidden or toggleable "weather layer" like R/T/C/Y infra).
- **Progressing snow** (earlier in year further north + mountains; storms move it; comes south slowly).
- **Historical + predictive**: 1918-today averages per area (lat/terrain/climate), modulated by solar min/max cycles for "future" estimates.
- **Manipulation**: Hidden hands, real-history examples (US Vietnam cloud seeding/Operation Popeye), tech/focus tree items that can force or bias weather in a province, nation, or larger scale.
- **Combat / ops tie-ins** (not just flavor):
  - Rain -> prolonged mud: divisions + armor movement heavily penalized.
  - Freeze: ground hardens, allows armor to cross swamps/mud that were impassable.
  - Extreme cold: higher equipment failure (if not "winterized" via tech/equip).
  - Desert: sand everywhere (even with "normal" gear); day high / night low temp swings stress troops/equip.
  - Blizzards / sandstorms / heavy rain + wind / lightning: visibility down, travel time up, org/ effectiveness down (no proper training/equip). Air missions prohibitive (Battle of the Bulge no air cover example).
  - Amphibious landings: sea state can delay (waves, wind at sea).
  - Extreme events (typhoons, EF1+ tornados, 7+ quakes, volcanoes, monsoons, droughts, ice storms, hail, hurricanes): multi-million $ (or equiv) infra damage, possible direct damage to units/ships/planes/armies in affected provinces/sea zones. Rare but high impact.
  - Slight day/night + high/low temp fluctuations have effects.
- **Altitude within province**: high ground can have snow while low does not. Do not punish the *whole* province — use % territory / fraction system so only portion of a unit is affected (e.g. 30% high-ground = averaged or partial penalty).
- **Player info**: viewable (tooltip, weather layer, province inspector, strategic weather summary) but most detail hidden (intel layer or recon required for precise % impacts, hidden hands actions).
- **Other effects**: winter snow/ice damages roads/infra over time. Severe heat/cold spikes energy demand (heating/cooling structures in developed provinces).
- **Solar flares** (X-class + geomagnetic): yes, model as rare global events — comms/radio blackouts (supply, air, intel, command), power grid stress (energy spike), aurora flavor. Can be "manipulated" at extreme tech levels?
- **Integration**: with existing TimeManager (daily ticks), Province (add weather state or query manager), MapRenderer + overlay layers (visuals), InfrastructureDevelopmentManager (wear), Supply/Combat/Air/Amphib systems (penalties), Economy (energy), Focus/Tech trees, "Hidden Hands" (secret project/event system).

**Core Principles for Lightness**:
- **Data driven + layered like existing province layers** (province_terrain, city, economy, visual_features_variants).
- Tick **daily or every few days** (tied to TimeManager day advance), not per frame or per hour.
- **Coarse simulation**: many effects at strategic_region or climate_zone level + per-province overrides/modifiers. Only "interesting" provinces (player owned, front line, event targets) get full per-province state.
- **State machine for ground + conditions**, not full physics.
- **Visuals**: cheap overlays (modulated sprites, simple _draw or shader params on bg, culling like infra layer). No thousands of particles.
- **Effects as multipliers / flat mods** returned by queries (get_movement_factor(pid), get_air_effectiveness(pid), get_infra_wear_rate(pid), get_energy_demand_mod(pid), ...). Systems call these at decision time.
- Signals only on *significant* changes (mud <-> frozen, storm starts, event hits) so UI/AI react without constant polling.
- **% impact for sub-province** (altitude, partial snow, event footprint): penalties = base * coverage_fraction (0-1). Unit "suffers as if X% of its elements are in bad micro-terrain".
- Hidden by default: weather layer off, detailed numbers in inspector only on demand or with intel.

## Recommended Architecture (Phased Implementation)

### 1. Data
- New (or extend existing): `data/provinces/weather_climate_layer.json` or `province_weather_baselines.json`.
  - Per province or (better for scale) per climate_zone + overrides:
    - base_avg_temp_c (monthly or annual curve)
    - precip_mm_avg (seasonal)
    - wind_avg, storm_freq
    - terrain_mods (mountains: +snow_persistence, desert: sand, swamp: mud prone)
    - high_ground_fraction: 0.0-1.0 (for altitude snow/ cold without punishing all)
    - coastal_sea_influence, etc.
- Historical table: `data/historical/weather_averages_1918_2026.json` (by lat band or region tags; user supplies real data or we approximate).
- Solar cycle: global scalar (sin wave 11yr or daily noise + cycle var). Affects temp/ storminess averages.
- Event defs: rare event templates (hurricane, ef3_tornado, 7.2_quake, volcano, monsoon, x_flare_geomagnetic) with prob, season, duration_days, damage_profile (infra_pct, unit_attrition, air/sea/land malus), affected (coastal / lat_band / random provinces in region).

Phase 1 data can be generated/extended from the python map tool (add to visual features or new weather layer output).

### 2. WeatherManager (core sim, lightweight)
- Autoload or persistent node (like TimeManager, InfrastructureDevelopmentManager).
- State:
  - Global: current_solar_phase, season_progress (0-1), global_mods (from hidden hands / events).
  - Per province (or cached): 
    - current_temp, precip (0-1 intensity + type: rain/snow/sleet), wind, visibility, storm_severity.
    - ground_state: enum {DRY, MUD, FROZEN, SNOW_COVERED, ICE, SAND_BLOWN, ...}
    - snow_depth or snow_coverage (0-1, progresses with latitude + mountains + days_below_freezing + storms).
    - days_in_condition, last_event.
    - modifiers_stack (from tech/focus/manipulation).
  - Active events list (global or regional with affected_pids or lat range).
- Tick (on TimeManager day_tick signal, throttled):
  - Update season + solar.
  - For each active region or "interesting" province: 
    - Baseline from data + season + solar + noise.
    - Storm / front movement (simple: a "snow_line_lat" that drifts south in fall/winter with random storms pushing it; mountains get + bias).
    - Precip accumulation -> mud or snow.
    - Temp cross 0 -> freeze/thaw ground state machine (with hysteresis to avoid flip-flopping).
    - Event rolls (rare).
  - Apply manipulation biases (e.g. "cloud_seeding" focus reduces storm prob in owned provinces by 30%, or forces "clear skies" for air ops).
  - Compute derived: movement_factor, org_factor, air_mission_factor, infra_wear, energy_demand_mod, amphib_sea_state, etc.
  - On significant change: emit signal weather_changed(pid, changes_dict) or regional.
- API (query heavy, mutate light):
  - get_current_conditions(pid) -> dict or struct (temp, "Blizzard - visibility 200m", ground="deep mud", coverage_notes="40% high ground snow").
  - get_movement_multiplier(pid, unit_type) -> float (armor in mud 0.4, infantry 0.7; frozen swamp bonus 1.2 if tracked; blizzard 0.3).
  - get_air_mission_effectiveness(pid) -> float (0.1 in heavy storm/lightning; Battle of Bulge example).
  - get_amphib_delay_or_cancel_chance(sea_zone or coastal_pids).
  - get_infra_damage_rate(pid) (winter freeze-thaw cycles + ice storms erode roads/rails).
  - get_energy_demand_mod(pid) (cold snap *1.4 for heating; heat wave for cooling in urban).
  - apply_manipulation(tag, strength, target_provinces or nation) — hidden hands / event hook.
  - force_event(event_id, pids) for scripts/foci.
- Persistence: save/load the runtime state (or re-sim from seed + current date on load for determinism).
- Perf: only simulate provinces in player view + fronts + event zones. Others use regional averages + light update. Cache queries.

### 3. Visuals (WeatherOverlayLayer + integration with map bg)
- New `scripts/map/WeatherOverlayLayer.gd` (modeled exactly on InfrastructureOverlayLayer: culling, rebuild on signals, toggleable).
  - Added in MapRenderer (like _setup_infrastructure_overlay_layer, called from render + phase1 apply).
  - Visual elements (cheap):
    - Snow: semi-transparent white/blue overlay sprite(s) or shader on the WorldBackground (or a child overlay Sprite2D the size of the theater rect). Opacity per "zone" or modulate whole + a noise mask for patchy.
    - For altitude: if province high_ground_fraction >0, draw a "cap" or use province poly clip + higher opacity snow only on upper portion (or simply a global snow line + local mountain bias; for exact % use a second masked layer or tint the vector fill lightly).
    - Rain / storm: animated simple lines or alpha "wet" tint on bg or over provinces (cull heavy rain to visible area).
    - Fog / low vis: vignette or alpha veil over area.
    - Event icons / particles (very sparse): lightning flash (one-shot), dust devil, etc. Only for severe active events.
    - Ground state tint: mud brown overlay, frozen blue-white crust, sand haze.
  - Toggle: map hotkey or Debug "Weather Layer (W)", DebugOverlay button. Default off or low for "clean" 1936 view; player turns on for intel.
  - Progressing snow visual: the snow opacity / coverage texture updates on weather tick / season change. Snow line can be a simple horizontal gradient + mountain masks (pre-baked or from terrain data).
  - Tie to existing: when phase1 grand bg applied, the weather layer sits above it (z order) but below or blended with vector polys/outlines/infra. Use same preserve-raster logic.
  - Player "see the pattern": weather layer shows snow advancing south over weeks, storm cells as moving dark patches, etc.

- Province / inspector / tooltip: show summarized "Current: Light snow, muddy in valleys (high ground frozen). Movement -25% armor. Air -15%."
- Strategic: new "Weather" tab or top bar icon with map-wide summary ("Snow line at 52N; 3 active storms in north; energy demand +18% in cold zones").

### 4. Manipulation & Hidden Hands
- Tech / focus tree unlocks "weather_mod" effects: e.g. "Arctic training" reduces cold penalties for your units; "Cloud seeding project" (costly, hidden or overt) applies persistent -storm bias to a region or owned provinces.
- "Hidden hands" system (future or existing intrigue/black ops): actions that spend resources to "induce rain" on enemy front (mud for their armor), "clear for bombing", or even trigger minor event. Vietnam-style: persistent op that increases precip in target area for X days.
- Scale: province (local ops), nation (large projects), theater (super weapons / late game).

### 5. Extreme Events Implementation
- Separate or inside WeatherManager: EventSimulator.
- On certain day ticks (or season start): roll for each vulnerable zone (coastal for hurricane/typhoon, plains for tornado, fault lines for quake, volcanic zones, etc.).
- On hit: 
  - Apply direct damage (call infra damage, unit attrition in province, possible ship damage if fleet present, airbase degradation).
  - Set temporary weather state (typhoon = extreme wind + rain + flood mud for duration).
  - Notify player (log + map flash on weather layer).
  - Large events can affect multiple provinces or sea zones.
- Thresholds: tornados EF1+, quakes 7.0+, hurricanes cat 1+, etc. Only "extreme instances" for drought/hail/ice as user said (not every season).

### 6. Integration Points (tie-ins)
- TimeManager.day_tick -> WeatherManager.on_day_tick().
- Movement / pathfinding / division update: query weather for factor.
- Combat resolution: apply org/attack/defense mods from conditions.
- Air / mission planner: effectiveness and abort chance.
- Amphib / naval: sea_weather_state.
- InfrastructureDevelopmentManager + projects: weather can slow construction or damage during build; winter damage passive attrits built roads/rails.
- Supply: mud/snow slows convoys, blizzards disrupt.
- Economy / power: energy demand mod applied to national or provincial consumption.
- Province data: can store "last_weather" or just query live.
- AI / decisions: AI can prefer clear weather windows or avoid mud offensives.
- Save / scenario: weather state + current events serializable.

### 7. Player Experience & "Hidden"
- Default: weather affects sim silently (you see results in slower advances in mud, failed air ops in storm, higher winter attrition if unprepared).
- Weather layer (toggle): visual drama (snow creeping, storm icons) + basic labels ("Mud", "Blizzard").
- Detailed: province click or dedicated intel screen shows numbers, forecasts (sim next 5 days), % high-ground impact explanation ("40% of this province is alpine — armor crossing the high passes will suffer full freeze bonus but infantry in valleys is in mud").
- Hidden hands actions appear in black ops / special projects menu (with risk of discovery).
- Logs / notifications for big events ("Typhoon X hits Kyushu coast — 2 divisions disorganized, port heavily damaged").

### Phasing Recommendation (to stay agile)
1. **Core loop + visuals MVP** (1-2 weeks): Season + basic temp/precip per province (or region), snow_line progression (lat + mountain bias + random push), ground state (mud/freeze), snow visual layer (simple overlay opacity + tint), basic movement + air penalties, weather tooltip. Tie to Time. Toggle in debug + map.
2. **Events + manipulation**: Add roll system for extremes, infra/attrition damage on hit, focus/tech hooks that bias rolls or force states, hidden hands example action.
3. **Fine details**: Day/night swing, desert specifics, % high-ground scaling, amphib/sea, energy demand, solar cycle, historical data loader, full player intel views, winter road wear.
4. **Polish / scale**: Culling/perf, better visuals (shader snow on bg?), prediction for player, AI use, save/load, more event variety (volcano visuals rare).

This is **not** a full physics sim — it's a wargame abstraction layer on top of the beautiful map. It makes the map "come alive" with decisions (build winter gear? time the offensive for freeze? seed clouds before D-Day equivalent? prepare for monsoon in Burma/India theater?) and gives realistic asymmetric impacts without uniform map-wide punishment.

**Solar flares**: Absolutely yes — perfect rare global "hidden hand" or natural event. X1+ with geomagnetic storm: temporary global malus to radio-dependent systems (air coordination, long-range supply, intel, perhaps some unit command), power demand spike or blackout risk in developed areas, beautiful aurora as flavor text/event card. Can be "amplified" or defended against with late tech.

**Winter infra + energy**: Tracked in the wear and demand mods above. Snow/ice cycles chew roads (small daily infra level drain or extra project cost to maintain). Cold snap: +energy for civilian + military heating in northern/urban provinces.

## Stubs to Get Started (already partially connected via this doc + prior map work)
See new files:
- `scripts/weather/WeatherManager.gd` (core, hooks into TimeManager, exposes query API, basic snow progression + sample effects).
- `scripts/map/WeatherOverlayLayer.gd` (visuals stub, added to MapRenderer setup like infra; toggleable, uses culling, can draw simple snow for now).
- MapRenderer will call a setup_weather_layer() in render/phase1 paths (lightweight).
- Debug can get a "Toggle Weather Layer" + "Force Snow Advance" button in future.
- Python tool can be extended later to output initial weather baselines from the same terrain/region data.

This system will feel deep for players who care (winter war on the Eastern/Northern fronts, desert logistics, carrier ops in typhoon season, etc.) while the map remains gorgeous and the sim stays fast.

Next steps after this design: implement the stubs + wire one or two real penalties (mud + freeze + basic air), add the layer toggle, test with the grand theater map (snow on the new northern areas should look great on the high-detail bg).

The fixes below address the exact errors you saw on Menu -> Debug and the missing grand image (with .jpg fallback + exists guards to keep console clean). The higher alpha + explicit hide should reduce the "transparent over old grey/black" (the old world_map.png or generated ProvinceMap raster). We can fully strip the base grey texture from the tscn or force it invisible in phase1 path if it still leaks.

Test the fixed debug toggle and map apply first, then we can expand the weather stubs.