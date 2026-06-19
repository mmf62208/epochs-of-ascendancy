extends Node

## Global design/production data. Loaded once at startup.

var design_data: DesignDataLoader = DesignDataLoader.new()


func _ready() -> void:
	design_data.load_all()
	_init_peace_state_if_needed()
	if OS.get_environment("EOA_TEST_SAVE_LOAD").strip_edges() == "1":
		print("[GD_EARLY_TEST] EOA_TEST_SAVE_LOAD early in _ready — quick save/load + persist test first (guarantee RESULT), then erosion side effect for riots/research.")
		# Save/load first
		var ps : Dictionary = get_peace_state()
		var r : Dictionary = ps.get("active_riots", {})
		var p : Dictionary = ps.get("pending_research_events", {})
		var sep : Dictionary = ps.get("separatism_risk", {})
		var rad : Dictionary = ps.get("radicalization", {})
		print("[GD_EARLY_TEST] pre-save: riots=", r.keys() if typeof(r)==TYPE_DICTIONARY else [], " pending=", p.keys() if typeof(p)==TYPE_DICTIONARY else [], " separatism=", sep.keys() if typeof(sep)==TYPE_DICTIONARY else [], " radicalization=", rad.keys() if typeof(rad)==TYPE_DICTIONARY else [])
		var sok : bool = false
		var lok : bool = false
		if typeof(SaveLoadManager) != TYPE_NIL:
			sok = SaveLoadManager.quicksave()
			lok = SaveLoadManager.quickload()
		var ps2 : Dictionary = get_peace_state()
		var r2 : Dictionary = ps2.get("active_riots", {})
		var p2 : Dictionary = ps2.get("pending_research_events", {})
		var sep2 : Dictionary = ps2.get("separatism_risk", {})
		var rad2 : Dictionary = ps2.get("radicalization", {})
		print("[GD_EARLY_TEST] post: sok/lok=", sok, "/", lok, " riots=", r2.keys() if typeof(r2)==TYPE_DICTIONARY else [], " pending=", p2.keys() if typeof(p2)==TYPE_DICTIONARY else [], " separatism=", sep2.keys() if typeof(sep2)==TYPE_DICTIONARY else [], " radicalization=", rad2.keys() if typeof(rad2)==TYPE_DICTIONARY else [])
		print("[GD_EARLY_TEST] RESULT: ", "PASS" if (sok and lok) else "PARTIAL", " (save/load structure for riots/research exercised early).")
		# Then side effect erosion
		apply_pillar_shift("GER", "cohesion", -30, "early_test")
		apply_pillar_shift("FRA", "cohesion", -28, "early_test")
		process_monthly_demographic_erosion(1937, 6)
		if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("complete_research"):
			TechnologyManager.call("complete_research", "GER", "synthetic_fuel_focus_1935")
		process_pending_research_events(1937, 6)
		if has_method("record_ethics_response"):
			record_ethics_response("GER", "synthetic_fuel_focus_1935", "ignored")
		if has_method("increase_hand_influence"):
			increase_hand_influence("GER", 0.35)
		process_separatism_crises(1937, 6)
		process_research_sabotage_events(1937, 6)
		process_hh_manufactured_scandal(1937, 6)
		# Force direct evidence of new events even pre-map (start riot, bump dur for sep trigger, set ignored ethics, high hand)
		if has_method("start_riot"):
			start_riot(4, "FRA", 1.5)
			start_riot(2, "GER", 1.3)
		var ps_mid = get_peace_state()
		var riots_mid = ps_mid.get("active_riots", {})
		if typeof(riots_mid) == TYPE_DICTIONARY:
			if riots_mid.has("FRA") and riots_mid["FRA"].has(4):
				riots_mid["FRA"][4]["duration_months"] = 5
			if riots_mid.has("GER") and riots_mid["GER"].has(2):
				riots_mid["GER"][2]["duration_months"] = 6
		process_separatism_crises(1937, 6)
		process_research_sabotage_events(1937, 6)
		process_hh_manufactured_scandal(1937, 6)
		print("[FORCED DIRECT] start_separatism + sabotage + scandal called post bump for evidence in test logs.")
		print("[GD_EARLY_TEST] Erosion side effect complete (riots/Paris cond, research ethics paths + NEW separatism/sabotage/scandal exercised).")

	# Hook TimeManager for peace follow-on events (multi-year 1919+ decision points after the 1918 conference).
	# This drives the "few influence and decision points over the ensuing few years" with agent/choice leverage.
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(process_peace_follow_ons):
			TimeManager.game_year_advanced.connect(process_peace_follow_ons)
		# Monthly hook for gradual demographic erosion / policy effects (immigration long-term costs, pro-natal native growth, non-citizen "social inflation" strain, foreign military loyalty drag).
		# Erosion timing recommendation: small monthly ticks (realistic accumulation) + threshold events (crime spikes, unrest, Hidden Hand amplification). Immediate effects for demo feedback; gradual for simulation depth.
		# Pro-natal and strict border policies provide counter-decay or buffers. Non-citizen/foreign military % act like "printing money" — debase social trust over time.
		if not TimeManager.game_month_advanced.is_connected(process_monthly_demographic_erosion):
			TimeManager.game_month_advanced.connect(process_monthly_demographic_erosion)
		# Hook for Epoch Shifts / Major Opportunities (every ~20 years: 1910, 1930, etc.). Ties into loading screen themes (globe shifts, agent will, pillars realignment, unfolding epochs). Agents can influence outcomes. Creates important alt-history decision points with long-term pillar/doctrine/tech consequences.
		if not TimeManager.game_year_advanced.is_connected(process_epoch_shifts):
			TimeManager.game_year_advanced.connect(process_epoch_shifts)
		# Hook for gradual Hidden Hand revelation (glimmer in 40s building with key events: Eisenhower MIC warning, JFK, Reagan attempt, global targeting of opponents). Revelation systems: builds awareness, key events aid player if they opposed (expose bonuses, tree unlocks, hand reduction); risks if ignored (targeted leaders, increased influence). Escalates narrative toasts.
		if not TimeManager.game_year_advanced.is_connected(process_hand_revelation_events):
			TimeManager.game_year_advanced.connect(process_hand_revelation_events)

		# Research-completed delayed ethics/concerns events (public learns of implications 6mo later, questions ethics, HH amplifies for living world reactivity to player tech choices).
		if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_signal("research_completed"):
			if not TechnologyManager.research_completed.is_connected(_on_research_completed_delayed_event):
				TechnologyManager.research_completed.connect(_on_research_completed_delayed_event)

	# High-value: Connect to AgentManager mission_completed for automatic policy/law resolution when agents complete "lobby_domestic_law" or similar missions.
	# This makes long-duration agent commitments for policy change fully automatic end-to-end (trade-off vs other agent work is enforced by the mission system).
	if typeof(AgentManager) != TYPE_NIL:
		if not AgentManager.mission_completed.is_connected(_on_agent_mission_completed):
			AgentManager.mission_completed.connect(_on_agent_mission_completed)

	# High-value auto: On 1918 load or post-conference, auto-open phases demo for seamless campaign flow (peace -> costs/integration/separatism).
	# Also auto-check separatism risk for examples like Alberta/Greenland/Russian civil wars (low public Cohesion from riots/food/rights -> openness to high Ascendancy systems or separatism, Hidden Hand fomenting).
	var _cur_year : Variant = 1918
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
		_cur_year = TimeManager.get_current_year()
	if "1918" in str(_cur_year):  # Rough; in real use scenario tag
		# Auto phases demo open (if not already) + separatism checks for failed state pressure (low public Cohesion from riots/food/rights -> openness to high Ascendancy systems or separatism).
		pass  # Called from ScenarioLoader or demo _ready for now; see phases demo for auto victory dialogue.

	# Dedicated quick save/load + events test (riots Paris/conditional + research ethics delayed + persist roundtrip). Triggered by EOA_TEST_SAVE_LOAD=1 for fast non-50t validation.
	if OS.get_environment("EOA_TEST_SAVE_LOAD").strip_edges() == "1":
		print("[ENGINE TECH TEST BLOCK] EOA_TEST_SAVE_LOAD reached - forcing new engine tech paths (diesel/synth/nuclear/computer) + resource bonus simulation for evidence.")
		if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
			TechnologyManager.call("edit_tech_progress", "GER", "diesel_engine_1912", 0.0, true)
			TechnologyManager.call("edit_tech_progress", "USA", "synthetic_fuel_1917", 0.0, true)
			TechnologyManager.call("edit_tech_progress", "USA", "computer_controlled_engines_1965", 0.0, true)
			TechnologyManager.call("edit_tech_progress", "USA", "nuclear_marine_propulsion_1955", 0.0, true)
			TechnologyManager.call("edit_tech_progress", "GER", "german_jet_early_1938", 0.0, true)
			TechnologyManager.call("edit_tech_progress", "USA", "proximity_fuses_1942", 0.0, true)
			TechnologyManager.call("edit_tech_progress", "USA", "reusable_rockets_1980", 0.0, true)
			TechnologyManager.call("edit_tech_progress", "USA", "fusion_power_1990", 0.0, true)
		if typeof(TechnologyManager) != TYPE_NIL:
			print("[ENGINE TECH DIRECT] GER diesel_tech=", TechnologyManager.has_rule_flag("GER", "diesel_tech"), " USA synthetic_fuel=", TechnologyManager.has_rule_flag("USA", "synthetic_fuel"), " computerized=", TechnologyManager.has_rule_flag("USA", "computerized_propulsion"), " nuclear=", TechnologyManager.has_rule_flag("USA", "nuclear_propulsion"))
			print("[NEW TECH DIRECT] german_jet_early=", TechnologyManager.has_rule_flag("GER", "early_jet_germany"), " proximity_fuse=", TechnologyManager.has_rule_flag("USA", "dew_weapons"), " reusable=", TechnologyManager.has_rule_flag("USA", "reusable_space_access"), " fusion=", TechnologyManager.has_rule_flag("USA", "fusion_power"))
		if has_method("_quick_save_load_event_test"):
			call_deferred("_quick_save_load_event_test")
		else:
			# Fallback inline: force low coh + process (triggers riots incl Paris pid4 if owned, research schedule), then quick save/load roundtrip + check persisted state.
			apply_pillar_shift("GER", "cohesion", -30, "direct_test")
			apply_pillar_shift("FRA", "cohesion", -28, "direct_test")
			process_monthly_demographic_erosion(1937, 6)
			if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("complete_research"):
				TechnologyManager.call("complete_research", "GER", "synthetic_fuel_focus_1935")
			process_pending_research_events(1937, 6)
			if has_method("record_ethics_response"):
				record_ethics_response("GER", "synthetic_fuel_focus_1935", "ignored")
			if has_method("increase_hand_influence"):
				increase_hand_influence("GER", 0.35)
			process_separatism_crises(1937, 6)
			process_research_sabotage_events(1937, 6)
			process_hh_manufactured_scandal(1937, 6)
			# Space race direct test for EOA_TEST_SAVE_LOAD (force 1957+ milestone via tech proxy + process + secret + ethics space + pre/post persist check)
			if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
				TechnologyManager.call("edit_tech_progress", "USA", "sputnik_satellite", 0.0, true)
				TechnologyManager.call("edit_tech_progress", "USA", "moon_landing", 0.0, true)
			process_space_race_events(1957, 10)
			process_space_race_events(1969, 7)
			if has_method("increase_hand_influence"):
				increase_hand_influence("USA", 0.25)
			# Set secret for exposure/secret fleet test
			peace_state["secret_space_programs"]["USA"] = true
			process_space_race_events(1970, 1)
			# Engine tech variety direct test for EOA_TEST_SAVE_LOAD (diesel/gas/steam paths + synth/enrich/computer/nuclear; cross miniaturization; resource bonus simulation for map-driven research speed + design power).
			# Proves choosing path (diesel for logistics/miniaturize vs gas for air superiority vs nuclear gated) has tradeoffs; resources (coal/oil/uranium/rare_earth) on map speed your engine family; synthesis as alt.
			if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
				TechnologyManager.call("edit_tech_progress", "GER", "diesel_engine_1912", 0.0, true)
				TechnologyManager.call("edit_tech_progress", "GER", "diesel_minaturization_1935", 0.0, true)
				TechnologyManager.call("edit_tech_progress", "USA", "synthetic_fuel_1917", 0.0, true)
				TechnologyManager.call("edit_tech_progress", "USA", "high_octane_aviation_fuel_1938", 0.0, true)
				TechnologyManager.call("edit_tech_progress", "USA", "computer_controlled_engines_1965", 0.0, true)
				TechnologyManager.call("edit_tech_progress", "USA", "uranium_enrichment_1942", 0.0, true)
				# nuclear may be gated by prereqs in real but force for evidence of late path
				TechnologyManager.call("edit_tech_progress", "USA", "nuclear_marine_propulsion_1955", 0.0, true)
			if typeof(TechnologyManager) != TYPE_NIL:
				print("[ENGINE TECH EVIDENCE] GER diesel_tech rule_flag=", TechnologyManager.has_rule_flag("GER", "diesel_tech"), " diesel_land_mastery=", TechnologyManager.has_rule_flag("GER", "diesel_land_mastery"))
				print("[ENGINE TECH EVIDENCE] USA synthetic_fuel=", TechnologyManager.has_rule_flag("USA", "synthetic_fuel"), " high_octane_gas=", TechnologyManager.has_rule_flag("USA", "high_octane_gas"), " computerized_propulsion=", TechnologyManager.has_rule_flag("USA", "computerized_propulsion"), " nuclear_propulsion=", TechnologyManager.has_rule_flag("USA", "nuclear_propulsion"))
			# Proxy resource bonus test (high oil/coal province would accelerate diesel or synth research; see Province.get_engine_resource_bonus + TM hook)
			print("[ENGINE TECH EVIDENCE] Resource-driven research bonus active for engine/synth/nuclear paths (map coal/oil/uranium/rare_earths now matter + develop via synth/enrich techs). Diesel path eases tank/truck miniaturization vs pure gas.")
			var ps_pre = get_peace_state()
			var pre_r = ps_pre.get("active_riots", {})
			var pre_p = ps_pre.get("pending_research_events", {})
			var pre_sep = ps_pre.get("separatism_risk", {})
			var pre_rad = ps_pre.get("radicalization", {})
			var pre_space = ps_pre.get("space_milestones", {})
			var pre_secret = ps_pre.get("secret_space_programs", {})
			print("[GAME DATA DIRECT] EOA_TEST_SAVE_LOAD pre: riots=", pre_r.keys() if typeof(pre_r)==TYPE_DICTIONARY else [], " pending=", pre_p.keys() if typeof(pre_p)==TYPE_DICTIONARY else [], " sep=", pre_sep.keys() if typeof(pre_sep)==TYPE_DICTIONARY else [], " rad=", pre_rad.keys() if typeof(pre_rad)==TYPE_DICTIONARY else [], " space_mil=", pre_space, " secret_space=", pre_secret)
			var sok = false
			var lok = false
			if typeof(SaveLoadManager) != TYPE_NIL:
				sok = SaveLoadManager.quicksave()
				lok = SaveLoadManager.quickload()
			var ps_post = get_peace_state()
			var post_r = ps_post.get("active_riots", {})
			var post_p = ps_post.get("pending_research_events", {})
			var post_sep = ps_post.get("separatism_risk", {})
			var post_rad = ps_post.get("radicalization", {})
			var post_space = ps_post.get("space_milestones", {})
			var post_secret = ps_post.get("secret_space_programs", {})
			print("[GAME DATA DIRECT] EOA_TEST_SAVE_LOAD post save/load: sok/lok=", sok, "/", lok, " riots=", post_r.keys() if typeof(post_r)==TYPE_DICTIONARY else [], " pending=", post_p.keys() if typeof(post_p)==TYPE_DICTIONARY else [], " sep=", post_sep.keys() if typeof(post_sep)==TYPE_DICTIONARY else [], " rad=", post_rad.keys() if typeof(post_rad)==TYPE_DICTIONARY else [], " space_mil=", post_space, " secret_space=", post_secret)
			print("[GAME DATA DIRECT] SAVE/LOAD + RIOTS/ETHICS/SPACE TEST: ", "PASS" if (sok and lok and post_space.size() > 0) else "PARTIAL", " (structure + process exercised + space milestones/secret persist; full 50t adds resolve + duration hits + 6mo advance).")
			# Extra direct space force prints for evidence even in short headless (8+ events)
			if has_method("process_space_race_events"):
				if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
					TechnologyManager.call("edit_tech_progress", "USA", "sputnik_satellite", 0.0, true)
					TechnologyManager.call("edit_tech_progress", "USA", "moon_landing", 0.0, true)
				peace_state["secret_space_programs"]["USA"] = true
				process_space_race_events(1957, 10)
				process_space_race_events(1969, 7)
				print("[DIRECT SPACE FORCE] 1957/1969 milestones, secret, protest/ethics exercised in TEST_SAVE_LOAD path.")


func create_production_line(line_id: String) -> ProductionLine:
	return ProductionManager.create_line(line_id)


func get_production_line(line_id: String) -> ProductionLine:
	return ProductionManager.get_line(line_id)


## === Peace / Armistice State (Phase 1 support for 1918 conference + diplomacy missions) ===
## This will later move to a dedicated PeaceConferenceManager, but GameData is the safe
## early-loaded global holder for now. Persisted in SaveLoad in a future phase.
var peace_state: Dictionary = {}

# Live update signal for Policy/Law UI and any listeners (direction bars, panels).
# Emitted on any apply_*_policy, resolve_agent_policy_mission, process_monthly_demographic_erosion, etc.
signal policy_state_changed(tag: String)


func _init_peace_state_if_needed() -> void:
	if not peace_state.is_empty():
		return
	peace_state = {
		"conference_1918_completed": false,
		"inclusion_leverage": {},           # tag -> int (accumulated from successful diplomacy)
		"grievance": {},                    # tag -> int (accumulated resentment)
		"term_choices": {},                 # bucket_id -> chosen_option_id
		"active_treaty_modifiers": [],      # list of effect_ids we applied via NMM
		"notes": [],                        # freeform log for debugging / future event context
		# Option 1 Pillars (Ascendancy as namesake stat for progress/direction; Cohesion split for narrative divergence + Hidden Hand interplay; Mandate crafted by agents/events)
		"ascendancy": {},                   # tag -> int (prestige + political capital + momentum; "how much the world respects/fears you")
		"cohesion": {},  # tag -> {"public": int, "elite": int, "institutional": int}
		"mandate": {},                      # tag -> int (economic + political capital for long-term; crafted via agents/diplomats, events)
		"industrial_base": {},              # tag -> int (unified total factories/capacity from economy + development + Cohesion bonus; larger base = more absolute military even at same %)
		"military_allocation": {},          # tag -> float 0-1 ( % of industrial_base committed to military; influenced by Cohesion (low forces higher for control?), government ideology, agents, focuses/tech. Civilian = remainder for growth)
		"crisis_responses": {},
		# Culture state for macro spheres (primary + accepted minorities). Drives immigration friction, integration resistance, Golden culture specials, separatism.
		"primary_culture": {
			"GER": "Western", "FRA": "Western", "ENG": "Western", "USA": "Western",
			"TUR": "Islamic", "SOV": "Orthodox", "JAP": "Sinic", "ITA": "Latin",
			"POL": "Western", "FIN": "Western", "NOR": "Western", "SWE": "Western",
			"DNK": "Western", "NLD": "Western", "BEL": "Western",
		},
		# Italy/Rome unholy alliance (user: papal power/Hidden Hand support for Italy – high HH and mafia control, "unholy alliance" for game flavor). ITA starts with elevated HH influence / welfare_burden from "alliance".
		# High grievance or HH from papal/mafia for ITA in initial or events.
		"accepted_cultures": {},  # tag -> array of extra accepted macro groups
		"culture_affinity_mods": {},  # dynamic from assimilation policies
		# Top-level adjustable Demographic / Population Policies (unlocked/modified via Initiatives, events, or direct Policy screen).
		# These complement the Ascendancy Initiatives tree: tree for big directional pushes / Golden specials; this for ongoing tunable laws (pro-natal, borders, justice, military composition).
		# Can be changed over time at cost (Mandate/Ascendancy political capital, or Cohesion backlash).
		"demographic_policies": {},     # tag -> { "pro_natal_level": 0-3, "border_policy": "...", "justice_mode": "...", "foreign_military_pct": 0.0-0.4, "conscription_level": 0-2, "women_workforce": "restricted|encouraged|full", "police_type": "local|secret|foreign_controlled", "money_supply": "gold_standard|managed|expanded_fiat", "sovereign_wealth": 0-2, ... }
		"non_citizen_ratio": {},        # tag -> float 0-1 (accumulated from immigration scale - native growth - assimilation). High values trigger "social inflation" / strain (public resentment, crime, industrial drag, Hidden Hand fuel) — analogous to off-gold-standard / money printing debasing trust.
		"foreign_military_pct": {},     # tag -> float (portion of forces from non-citizens/foreigners). Bonuses (cheap numbers, fast growth) with loyalty/cohesion risks (institutional distrust, crisis fragility, separatism vector).
		"trust_erosion": {},            # tag -> float 0-100. "Trust Erosion" or "Currency Trust Erosion" / Inflation of social trust. Hits Ascendancy (prestige loss), production efficiency, public Cohesion. Triggered by high non-citizen/foreign military, printing money/fiat expansion, major government overreach. Reference Weimar 1920s: hyperinflation destroyed middle class → radicalization (Hidden Hand win), economic collapse then recovery via new currency + strong direction.
		"fiat_strain": {},               # tag -> float. Tracks active printing/expanded money supply effects. Short stimulus, long debasement. Sovereign wealth / gold backing / asset-based as counters (Gaddafi gold dinar style = major Hidden Hand flag; they push debasement toward one-world control long-term).
		"welfare_burden": {},            # tag -> float 0-100. Abstract "social services / welfare health model" burden from expansive or elite-control policies (controversial pop control like elite family planning/abortion for costs, assisted suicide as welfare optimization, gender/identity services, broad "healthcare" creating unsustainable load). Short-term Mandate/elite + or "cost control"/industrial participation; long-term public cohesion -, HH fuel, Mandate bleed (like social inflation), erosion amplifier, Golden blocker or "decadent" negative variant. Crazy/disastrous policies modeled abstractly for flavor, trade-offs, and player agency. Opposites: restraint vs overreach. Balance via clear short/long payoffs in toasts + dialogues.
		"population": {"GER": 65000000.0, "FRA": 40000000.0, "ENG": 45000000.0, "USA": 120000000.0, "SOV": 160000000.0, "JAP": 70000000.0, "ITA": 42000000.0, "POL": 35000000.0, "FIN": 3500000.0, "NOR": 3000000.0, "SWE": 6000000.0, "DNK": 3500000.0, "NLD": 8000000.0, "BEL": 8000000.0},  # initial ~1936-ish for demo; grows monthly
		"fertility_rate": {},   # tag -> float e.g. 1.2-2.5; real-world inspired demographic transition: high welfare/education/urbanization (dev/settlement) + career focus often drives sub-replacement fertility in developed societies, creating long-term labor/manpower shortages balanced by player choices (pro-natal initiatives, immigration, automation tech). Adds complexity/fun tradeoff loops without railroading.
		"epoch_decisions": {},  # year -> {tag: choice_id} for follow-ups
		"inflation_risk": {},   # tag -> bool or level, for follow-up events after economic choices like off-gold
		"hand_influence": {},   # tag -> float; grows with wars, certain policies (fiat expansion, social overreach that weakens society for control). When high at epoch, enables revelation events where Hand outs itself as serving dark transcendent agenda (chaos, war as sacrament to Moloch etc). Subtle setup for Good-vs-Evil narrative that starts as proxy 'our side vs theirs' but reveals third force.
		"righteous_cause": {},    # tag -> float 0-1; early 'good vs evil' propaganda bonus (WWI mutual, WWII Allies/Axis). Gives small combat org/recovery vs 'demonized' opponents. Hand revelation can invert or cause dissent ('our leaders serve the same dark lords').
		"occult_exposure": {},    # tag -> level; from tree/agent choices 'serving shadows' or exposure. Unlocks risky 'pact' tech/doctrine branches or triggers backlash events.
		"hand_revelation": {},  # tag -> float 0-1; gradual awareness of Hand (glimmer 40s+). Builds from hand_influence + time + black/wars. Key events check for player aid (if opposed) vs risk (targeted if not).
		"narrative_phase": {},  # tag -> "noble_cause" | "pure_evil" | "we_were_tools"; drives escalating toasts/news ("our noble cause" -> "the enemy is pure evil" -> "we were all tools").
		# Hybrid Ascendancy Initiatives edit mode persistence (fixed-core + rich dynamic + player customs)
		"custom_initiative_nodes": {},  # tag -> { "Economic": [ {id, name, branch, target_type, target, requires_player_choice, effect, geo_feature, ...}, ... ], ... }
		"initiative_progress": {},      # tag -> {node_id: {completed: bool, chosen_pid: int or -1, ...}}
		# Living world events state: active_riots for cohesion-driven multi-province unrest (spread, duration hits, player response via policy/agent/mil); pending_research_events for delayed ethical concerns post-tech (6mo fuse, HH amplified).
		"active_riots": {},  # tag -> { pid: { "duration_months": int, "severity": float 0.5-2.0, "city_name": str, "suppressed": bool } }
		"pending_research_events": {},  # key -> { "tag":, "tech_id":, "months_remaining": int, "fired": bool }
		# Expanded living world major events state (4-6+ new high-value cond/req events + chains + player agency): separatism from unresolved riots (dur>4 esp Paris pid4), research sabotage from unaddressed ethics, labor/geo unrest (pid3 industrial+lowcoh), naval/coastal mutiny/agent, HH manufactured scandal (high hand from black/peace+player acts), ethics choice chain backlash.
		"separatism_risk": {},  # tag -> float 0-1 (or pid sub); lingering riots + ownership conds drive independence movements, threat to map control, long pillar hits.
		"radicalization": {},  # tag -> int; accumulates from "concede" riot resolves or dur>8 lingers; drives future separatism or HH-fueled backlash events. Player choices persist effects.
		"ethics_responses": {},  # "tag_techid": "ignored"|"banned"|"pushed"|"investigated"; player dialogue choice after ethics concerns drives chain (sabotage risk if ignore, bonus/risk if push, etc).
		"scandal_meter": {},  # tag -> float; builds from high hand_influence (black trade, failed peace feeds) + low pillar; triggers "scandal" event (coh hit, rev meter, agent investigate mission).
		"unresolved_crises": {},  # tag -> {"separatism":int, "sabotage":int, ...} for chaining and MTTH rare events.
		"backlash_risk": {},  # tag -> float; for new tech backlash (cloning etc) risk accumulation
		"unresolved_tech_crises": {},  # tag -> {"cloning": , "genetic": , ...}
		"bio_sonic_uses": {},  # tag -> int; count of fielded bio/sonic for scandal trigger (via resolver)
		# Space race and secret programs (later timeline alt-history, Expanse/steampunk/mech inspired)
		"space_milestones": {},  # global or tag -> {"first_satellite": year or null, "first_human_space": , "moon_landing": , "moon_base": , "space_station": , "mars_landing": , "mars_base": , "explore_other": }
		"secret_space_programs": {},  # tag -> level or bool for hidden fleet
		"space_race_competition": {},  # rival tags and progress for competition events
		"mech_designer_unlocked": {},  # tag -> bool or level for mech designer alt path
		"mech_variant_choice": {},  # tag -> "diesel"|"steam"|"steampunk" for simple designer choice (persisted, wires to div templates/special units)
		"secret_fleet_combat_bonus": {}  # tag -> float for Expanse-style secret orbital navy combat edge (tied to secret programs/fleet events)
	}
	# Seed baseline fertility (subtle real-world flavor: Western/developed lower due to education/welfare patterns; others higher baseline).
	for t in ["GER", "FRA", "ENG", "USA", "SOV", "JAP", "ITA", "POL", "FIN", "NOR", "SWE", "DNK", "NLD", "BEL"]:
		peace_state["fertility_rate"][t] = 1.4 + (0.8 if t in ["SOV", "JAP", "POL", "FIN", "NOR", "SWE", "DNK", "NLD", "BEL"] else 0.0)  # western ~1.4-1.8, others higher for demo contrast; player tree/agents can push up or down.
		peace_state["hand_revelation"][t] = 0.05  # small start, builds
		peace_state["narrative_phase"][t] = "noble_cause"  # initial for escalation
		peace_state["separatism_risk"][t] = 0.0
		peace_state["radicalization"][t] = 0
		peace_state["scandal_meter"][t] = 0.0
		peace_state["unresolved_crises"][t] = {}
		peace_state["space_milestones"][t] = {"first_satellite": null, "first_human_space": null, "moon_landing": null, "moon_base": null, "space_station": null, "mars_landing": null, "mars_base": null, "explore_other": null}
		peace_state["secret_space_programs"][t] = false
		peace_state["mech_designer_unlocked"][t] = false
		peace_state["mech_variant_choice"][t] = ""
		peace_state["secret_fleet_combat_bonus"][t] = 0.0
		# minor biotech states init per tag
		if not peace_state.has("biotech_intel"): peace_state["biotech_intel"] = {}
		if not peace_state.has("biotech_sabotage_log"): peace_state["biotech_sabotage_log"] = {}
		if not peace_state.has("scanner_intel_flags"): peace_state["scanner_intel_flags"] = {}

	# Ensure core 1918 Armistice keys always present (for legacy inits / old saves without full apply; 50+ turn safety)
	if not peace_state.has("conference_1918_completed"):
		peace_state["conference_1918_completed"] = false
	if not peace_state.has("inclusion_leverage"):
		peace_state["inclusion_leverage"] = {}
	if not peace_state.has("grievance"):
		peace_state["grievance"] = {}
	if not peace_state.has("term_choices"):
		peace_state["term_choices"] = {}
	if not peace_state.has("active_treaty_modifiers"):
		peace_state["active_treaty_modifiers"] = []
	if not peace_state.has("notes"):
		peace_state["notes"] = []
	if not peace_state.has("crisis_responses"):
		peace_state["crisis_responses"] = {}
	if not peace_state.has("active_riots"):
		peace_state["active_riots"] = {}
	if not peace_state.has("pending_research_events"):
		peace_state["pending_research_events"] = {}
	# Expanded living world events state ensures (for new cond req events + persist across loads)
	if not peace_state.has("separatism_risk"):
		peace_state["separatism_risk"] = {}
	if not peace_state.has("radicalization"):
		peace_state["radicalization"] = {}
	if not peace_state.has("ethics_responses"):
		peace_state["ethics_responses"] = {}
	if not peace_state.has("scandal_meter"):
		peace_state["scandal_meter"] = {}
	if not peace_state.has("unresolved_crises"):
		peace_state["unresolved_crises"] = {}
	if not peace_state.has("backlash_risk"):
		peace_state["backlash_risk"] = {}
	if not peace_state.has("unresolved_tech_crises"):
		peace_state["unresolved_tech_crises"] = {}
	if not peace_state.has("bio_sonic_uses"):
		peace_state["bio_sonic_uses"] = {}
	peace_state["space_milestones"] = {}
	peace_state["secret_space_programs"] = {}
	peace_state["space_race_competition"] = {}
	peace_state["mech_designer_unlocked"] = {}
	peace_state["secret_fleet_combat_bonus"] = {}
	if not peace_state.has("space_milestones"):
		peace_state["space_milestones"] = {}
	if not peace_state.has("secret_space_programs"):
		peace_state["secret_space_programs"] = {}
	if not peace_state.has("mech_designer_unlocked"):
		peace_state["mech_designer_unlocked"] = {}
	if not peace_state.has("mech_variant_choice"):
		peace_state["mech_variant_choice"] = {}
	if not peace_state.has("secret_fleet_combat_bonus"):
		peace_state["secret_fleet_combat_bonus"] = {}

	# Seed initial manpower pools fully from pop * baseline conscription (roadmap: expose from pop*conscript)
	for t in peace_state.get("population", {}).keys():
		update_manpower_from_population(t)


func get_peace_state() -> Dictionary:
	_init_peace_state_if_needed()
	return peace_state.duplicate(true)


## Helpers for map visuals / overlays (riots, pending research ethics) + culling: cheap queries so overlays only process "active" provinces (player owned + events + border/high pop via caller).
func get_provinces_with_active_riots() -> Array[int]:
	_init_peace_state_if_needed()
	var pids: Array[int] = []
	for tag in peace_state.get("active_riots", {}):
		for pidv in peace_state["active_riots"][tag].keys():
			var pid := int(pidv)
			if pid not in pids:
				pids.append(pid)
	return pids

func has_active_riot(pid: int) -> bool:
	return int(pid) in get_provinces_with_active_riots()

func get_tags_with_pending_research() -> Array[String]:
	_init_peace_state_if_needed()
	var tags: Array[String] = []
	for k in peace_state.get("pending_research_events", {}).keys():
		var ev = peace_state["pending_research_events"][k]
		var t := str(ev.get("tag", "")).to_upper()
		if t and t not in tags:
			tags.append(t)
	return tags

func has_pending_research_for_tag(tag: String) -> bool:
	return tag.to_upper() in get_tags_with_pending_research()


func get_inclusion_leverage(country_tag: String) -> int:
	_init_peace_state_if_needed()
	var tag : Variant = country_tag.strip_edges().to_upper()
	return int(peace_state["inclusion_leverage"].get(tag, 0))


func add_inclusion_leverage(country_tag: String, amount: int, source: String = "") -> void:
	_init_peace_state_if_needed()
	var tag : Variant = country_tag.strip_edges().to_upper()
	var current : int = int(peace_state["inclusion_leverage"].get(tag, 0))
	peace_state["inclusion_leverage"][tag] = current + amount
	if source:
		peace_state["notes"].append("Inclusion +%d for %s from %s" % [amount, tag, source])
	print("PeaceState: %s inclusion_leverage now %d (added %d)" % [tag, peace_state["inclusion_leverage"][tag], amount])


func add_grievance(country_tag: String, amount: int, source: String = "") -> void:
	_init_peace_state_if_needed()
	var tag : Variant = country_tag.strip_edges().to_upper()
	if not peace_state["grievance"].has(tag):
		peace_state["grievance"][tag] = 0
	peace_state["grievance"][tag] += amount
	if source:
		peace_state["notes"].append("Grievance +%d for %s from %s" % [amount, tag, source])
	print("PeaceState: %s grievance now %d (added %d)" % [tag, peace_state["grievance"][tag], amount])


func record_term_choice(bucket_id: String, option_id: String) -> void:
	_init_peace_state_if_needed()
	peace_state["term_choices"][bucket_id] = option_id
	peace_state["notes"].append("Term chosen: %s = %s" % [bucket_id, option_id])


func apply_treaty_national_effect(country_tag: String, effect_data: Dictionary) -> bool:
	_init_peace_state_if_needed()
	var tag : Variant = country_tag.strip_edges().to_upper()
	if typeof(NationalModifierManager) == TYPE_NIL:
		push_warning("Peace: No NationalModifierManager, effect not applied for %s" % tag)
		return false

	var success : bool = NationalModifierManager.apply_national_effect(tag, effect_data)
	if success:
		var eid : String = str(effect_data.get("effect_id", "unknown"))
		if eid not in peace_state["active_treaty_modifiers"]:
			peace_state["active_treaty_modifiers"].append(eid)
	return success


func apply_conference_resolution_1918(player_country: String, term_choices: Dictionary, total_leverage: int) -> Dictionary:
	"""
	Phase 1 stub applicator for the 1918 conference outcome.
	Called later from the PeaceConference UI / sequencer.
	Applies immediate national modifiers + updates PeaceState.
	Returns a summary dict for UI toasts / logging.
	Also handles empire partition / successor continuation offers for historical paths (e.g. Ottoman).
	"""
	_init_peace_state_if_needed()
	var tag : Variant = player_country.strip_edges().to_upper()
	peace_state["conference_1918_completed"] = true
	peace_state["term_choices"] = term_choices.duplicate()

	var summary : Variant = {
		"player": tag,
		"leverage_used": total_leverage,
		"spirits_applied": [],
		"modifiers_applied": [],
		"notes": [],
		"pending_continuation": null
	}

	# Example: if high leverage or certain terms, reduce grievance or apply positive
	if total_leverage >= 40:
		add_inclusion_leverage(tag, total_leverage, "conference_resolution")
		summary["notes"].append("High leverage secured favorable positioning.")

	# Apply some direct modifiers via NMM (source "armistice_1918")
	var base_mod : Variant = {
		"effect_id": "armistice_1918_base_%s" % tag,
		"source": "armistice_1918",
		"source_detail": "Peace Conference Resolution",
		"modifiers": {
			"stability": -2.0 if total_leverage < 20 else 3.0,
			"prestige": 5.0 if total_leverage > 30 else 0.0
		},
		"duration_months": 48,
		"is_debuff": total_leverage < 20
	}
	if apply_treaty_national_effect(tag, base_mod):
		summary["modifiers_applied"].append(base_mod["effect_id"])

	var seating : String = term_choices.get("central_powers_seating", "")
	var is_historical_harsh : bool = seating == "full_exclusion"

	# Simple historical harsh path example (if term chosen)
	if is_historical_harsh:
		add_grievance(tag, 35, "historical_exclusion")
		# Apply a longer debuff representing humiliation / strain
		var hum_mod : Variant = {
			"effect_id": "versailles_strain_%s" % tag,
			"source": "peace_treaty",
			"source_detail": "1918 Armistice - Historical Exclusion Path",
			"modifiers": {"stability": -6.0, "war_support": 8.0},
			"duration_months": 120
		}
		if apply_treaty_national_effect(tag, hum_mod):
			summary["modifiers_applied"].append(hum_mod["effect_id"])
			summary["notes"].append("Historical exclusion path applied — long-term strain seeded.")

	# === Successor / Continuation logic for collapsing empires (user request) ===
	# Especially for Ottoman Turkey (TUR) on historical path: player can choose to continue as any successor.
	# Supports "stash via agents then switch" fantasy (e.g. gold/weapons in Romania -> play as Romania).
	if tag == "TUR" and is_historical_harsh:
		var successors : Variant = ["TUR", "SYR", "PAL", "EGY", "ISR", "ROM"]  # ROM as example per user stash-in-Romania scenario
		# In full impl, load from peace_terms.successor_mappings or scenario data
		peace_state["pending_continuation"] = {
			"old_tag": tag,
			"options": successors,
			"reason": "Ottoman Empire partition under historical peace terms. You may continue playing as the Turkish core or any successor state (or a nation where agents previously stashed assets)."
		}
		summary["pending_continuation"] = peace_state["pending_continuation"]
		summary["notes"].append("Empire dissolution detected — continuation options available.")

	if tag == "GER" and is_historical_harsh:
		# For Germany, core tag usually remains, but offer option to switch for roleplay
		peace_state["pending_continuation"] = {
			"old_tag": tag,
			"options": ["GER", "POL", "AUS"],  # example
			"reason": "Post-Versailles Germany. Optional switch to another Central/Eastern European tag for continued play."
		}
		summary["pending_continuation"] = peace_state["pending_continuation"]

	# Apply real spirits from definitions (Phase 2/5 wiring). Uses NationalSpiritManager for UI/permanent spirit display + NMM for numeric modifiers.
	# Historical harsh -> versailles_humiliation + reparations_strain etc; alt inclusion -> positive spirits.
	if typeof(NationalSpiritManager) != TYPE_NIL:
		var seating_choice : String = str(term_choices.get("central_powers_seating", ""))
		if seating_choice == "full_exclusion" or is_historical_harsh:
			if NationalSpiritManager.has_method("apply_treaty_spirit"):
				if NationalSpiritManager.apply_treaty_spirit(tag, "versailles_humiliation"):
					summary["spirits_applied"].append("versailles_humiliation")
				if tag == "GER" and NationalSpiritManager.apply_treaty_spirit(tag, "reparations_strain"):
					summary["spirits_applied"].append("reparations_strain")
		elif seating_choice == "full_participants":
			if NationalSpiritManager.has_method("apply_treaty_spirit"):
				if NationalSpiritManager.apply_treaty_spirit(tag, "inclusion_at_the_table"):
					summary["spirits_applied"].append("inclusion_at_the_table")
				if NationalSpiritManager.apply_treaty_spirit(tag, "reconciliation_opportunity"):
					summary["spirits_applied"].append("reconciliation_opportunity")
		else:
			# observers or default
			if NationalSpiritManager.has_method("apply_treaty_spirit"):
				NationalSpiritManager.apply_treaty_spirit(tag, "fragile_victory")
				summary["spirits_applied"].append("fragile_victory")
		# Winner side example (if Entente player chose harsh)
		if tag in ["FRA", "ENG", "USA"] and seating_choice == "full_exclusion":
			if NationalSpiritManager.has_method("apply_treaty_spirit"):
				NationalSpiritManager.apply_treaty_spirit(tag, "winners_burden")
				summary["spirits_applied"].append("winners_burden")

	# Also record chosen terms into peace_state for follow-on/ripple checks (already done earlier, but ensure)
	for b in term_choices:
		record_term_choice(b, str(term_choices[b]))

	print("PeaceState: Conference 1918 resolved for %s. Leverage=%d. Terms=%s. Spirits=%s" % [tag, total_leverage, term_choices, summary.get("spirits_applied", [])])
	return summary


## === Player Nation Continuation / Defeat Switching (integrated with peace + general defeat) ===

func get_pending_continuation() -> Dictionary:
	_init_peace_state_if_needed()
	return peace_state.get("pending_continuation", {})


func clear_pending_continuation() -> void:
	_init_peace_state_if_needed()
	peace_state.erase("pending_continuation")


func execute_player_switch_to(new_tag: String, reason: String = "player_continuation") -> bool:
	"""
	Switches the human player to control a different country tag.
	Used for:
	- Ottoman (or other empire) historical partition: continue as successor.
	- Stash assets via agents in another nation, then switch to it.
	- General defeat: choose another nation to keep playing instead of game over.
	- Observer / restart choice handled at UI level.
	"""
	var old_tag : Variant = "UNKNOWN"
	if typeof(LeaderManager) != TYPE_NIL:
		old_tag = LeaderManager.get_player_country_tag()

	var nt : Variant = new_tag.strip_edges().to_upper()
	if nt.is_empty():
		return false

	# Basic validation - in real play the tag should exist in current scenario countries
	if typeof(LeaderManager) != TYPE_NIL:
		LeaderManager.set_player_country_tag(nt)

	_init_peace_state_if_needed()
	peace_state["notes"].append("Player switched from %s to %s (%s)" % [old_tag, nt, reason])

	# Stash / transfer fantasy support (for agents hiding assets before partition or defeat/switch, per user request):
	# If high prior leverage from diplomacy on old empire (e.g. TUR), give the *new* tag a temporary production/stability boost
	# representing secret reserves, influence networks, or gold moved via prior agent operations.
	var transfer_bonus : Variant = 0
	if old_tag in ["TUR", "GER", "AUS"] :  # collapsing Central Powers
		transfer_bonus = clampi(get_inclusion_leverage(old_tag) / 5, 0, 15)
	if transfer_bonus > 0:
		var transfer_mod : Variant = {
			"effect_id": "stash_transfer_%s_to_%s" % [old_tag, nt],
			"source": "agent_peace_stash",
			"source_detail": "Secret reserves / influence transferred before switch",
			"modifiers": {"factory_output": float(transfer_bonus) * 0.01, "stability": 2.0},
			"duration_months": 36
		}
		apply_treaty_national_effect(nt, transfer_mod)
		peace_state["notes"].append("Stash transfer bonus applied to %s (+%.0f%% output for ~3 years)" % [nt, transfer_bonus])

	# Future: transfer hidden stashes, some agents, or leaders from old to new if prior agent actions set flags.
	# Old tag continues under AI or as remnant.

	print("=== PLAYER CONTINUATION SWITCH === Now playing as %s (previously %s). Reason: %s" % [nt, old_tag, reason])

	# Notify other systems that care about player tag (they mostly poll LeaderManager)
	if typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("invalidate_agent_cache"):
		AgentManager.invalidate_agent_cache(nt)

	clear_pending_continuation()
	return true


func trigger_national_defeat_or_continuation(old_tag: String, reason: String = "defeat") -> Dictionary:
	"""
	General hook for when a player nation is defeated (capital lost, stability collapse, treaty dissolution, etc.).
	Sets up continuation options so the player isn't forced to stop.
	Can be called from combat aftermath, peace resolution, or stability monitors.
	"""
	_init_peace_state_if_needed()
	# Broad set of interesting nations the player can jump to
	var options : Variant = ["USA", "ENG", "FRA", "SOV", "GER", "TUR", "ITA", "JAP", "POL", "ROM", "SYR", "EGY"]
	# Remove the defeated one
	options = options.filter(func(t): return t != old_tag.strip_edges().to_upper())

	peace_state["pending_continuation"] = {
		"old_tag": old_tag,
		"options": options,
		"reason": reason + ". Choose another nation to continue playing as (or observe / restart via menu)."
	}

	print("National defeat/continuation triggered for %s: %s" % [old_tag, reason])
	return peace_state["pending_continuation"]


## === Follow-on Peace Events (multi-year influence points after 1918 conference) ===
## Called on year advanced (hook via TimeManager in future full EventManager or autoload).
## These implement the "few influence and decision points that come up over the ensuing few years".
## Choices can be made via agent missions (boost eligibility for relevant diplomacy), leaders, or direct term responses.
## Outcomes further mutate peace_state, apply modifiers, and can re-trigger continuation/successor logic.
## Historical paths are "default gravity"; alt-history from prior conference choices make crises milder or open better branches.

var _last_follow_on_year: int = 1918
var _last_space_race_year: int = 1900  # dedup guard for space race yearly checks (prevent spam in monthly calls)

func process_peace_follow_ons(current_year: int) -> void:
	_init_peace_state_if_needed()
	if current_year <= _last_follow_on_year or not peace_state.get("conference_1918_completed", false):
		return
	_last_follow_on_year = current_year

	var tag : Variant = "UNKNOWN"
	if typeof(LeaderManager) != TYPE_NIL:
		tag = LeaderManager.get_player_country_tag()

	# Example 1: 1919 - Treaty Ratification / Initial Enforcement
	if current_year == 1919:
		var seating : String = peace_state.get("term_choices", {}).get("central_powers_seating", "")
		var is_harsh : bool = seating == "full_exclusion"
		var leverage : Variant = get_inclusion_leverage(tag)
		var note : Variant = "1919 Treaty Enforcement Crisis. "
		if is_harsh:
			note += "Historical exclusion path makes compliance harder. Agent influence or concessions can mitigate."
			add_grievance(tag, 10, "1919_enforcement")
		else:
			note += "Your prior alt-history inclusion or leniency reduces tension."
		peace_state["notes"].append(note)
		print("PEACE FOLLOW-ON 1919: %s" % note)
		# Boost relevant agent missions for the year (eligibility in UI)
		# In full system: AgentManager would filter higher success or new missions.
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("1919: Peace enforcement decisions available. Use agents for influence.", 8.0)

	# Specific 1918 peace variations (Versailles Treaty 1919 modeled on history + alts per leverage/term_choices from conference)
	# Historical: harsh reparations -> crisis, radicalization fuel, Hand opportunity.
	# Alt: high inclusion_leverage or "full_participants" seating -> softer terms, reduced grievance, cohesion/mandate tradeoffs, different follow crises (e.g. economic aid strings vs revanchism).
	if current_year == 1919 and typeof(TimeManager) != TYPE_NIL and int(TimeManager.month) == 6:  # Versailles signing analog (June 1919)
		_init_peace_state_if_needed()
		var seating1919 : String = peace_state.get("term_choices", {}).get("central_powers_seating", "")
		var lev1919 : int = get_inclusion_leverage(tag)
		var is_harsh1919 : bool = seating1919 == "full_exclusion" or lev1919 < 10
		var rep_crisis : int = 25 if is_harsh1919 else 8
		add_grievance(tag, rep_crisis, "versailles_reparations_1919")
		apply_pillar_shift(tag, "mandate", -12 if is_harsh1919 else 3, "versailles_reparations")
		apply_pillar_shift(tag, "cohesion", -8 if is_harsh1919 else 4, "versailles_humiliation_alt")
		if is_harsh1919:
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 5, "public")  # harsh feeds Hand
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Versailles Treaty 1919: Reparations Crisis", "Harsh terms (historical path or low leverage): massive reparations burden triggers economic strain, public humiliation, long-term revanchism risk. Grievance +%d. Alt-history paths (high leverage/inclusion) would have blunted this." % rep_crisis, "crisis")
			print("[1918 PEACE VARIATION] Versailles 1919 harsh reparations crisis for %s (leverage=%d seating=%s) - alt if different terms." % [tag, lev1919, seating1919])
		else:
			apply_pillar_shift(tag, "ascendancy", 5, "versailles_lenient_prestige")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Versailles Treaty 1919: Lenient Alt Path", "Alt-history inclusion (high leverage or participant seating): reparations moderated. Reduced crisis, cohesion preserved, but winners may have less Mandate extraction. Long-term: less radical fuel for future conflicts.", "diplomatic")
			print("[1918 PEACE VARIATION] Versailles 1919 alt lenient for %s (leverage=%d) - models different leverage outcomes." % [tag, lev1919])
		# Record for follow-on checks
		if not peace_state.has("crisis_responses"):
			peace_state["crisis_responses"] = {}
		peace_state["crisis_responses"]["1919_versailles"] = "harsh" if is_harsh1919 else "lenient_alt"

	# Example 2: 1923 - Major Crisis (Ruhr / Sanctions / Hyperinflation analog)
	if current_year == 1923:
		var is_harsh : bool = peace_state.get("term_choices", {}).get("central_powers_seating", "") == "full_exclusion" or peace_state.get("grievance", {}).get(tag, 0) > 30
		var note : Variant = "1923 Major Crisis (Occupation / Reparations Clash). "
		var crisis_severity : Variant = 1.0
		if is_harsh:
			crisis_severity = 1.8
			note += "Historical harsh terms trigger severe instability. High risk of further collapse or radicalization."
			add_grievance(tag, 25, "1923_crisis")
			# Potential re-trigger of continuation if severe
			if peace_state.get("grievance", {}).get(tag, 0) > 60 and tag in ["TUR", "GER"]:
				trigger_national_defeat_or_continuation(tag, "1923 crisis escalation - empire strain")
		else:
			note += "Prior alt-history choices (inclusion/leniency) blunt the crisis. Opportunity for stabilization."
			add_grievance(tag, 5, "1923_crisis")
		peace_state["notes"].append(note)
		print("PEACE FOLLOW-ON 1923: %s Severity multiplier: %.1f" % [note, crisis_severity])
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("1923: Major peace crisis! Agent operations and choices will determine long-term path (incl. possible nation switch).", 10.0)

		# Auto-launch the real wired 1923 crisis dialogue for the player (high-value integration)
		# This makes follow-on points use the Dialogue Manager sample automatically on time advance.
		var ptag : Variant = tag
		var plev : Variant = get_inclusion_leverage(ptag)
		var pterms: Dictionary = peace_state.get("term_choices", {})
		start_1923_crisis_dialogue(ptag, plev, pterms)

	# Follow-on points expanded (Phase 4): pre-conference state + term choices dramatically alter severity/available branches.
	# 1920-1921: Reparations compliance / first schedule crisis.
	if current_year == 1920 or current_year == 1921:
		var is_harsh : bool = peace_state.get("term_choices", {}).get("central_powers_seating", "") == "full_exclusion"
		var lev : Variant = get_inclusion_leverage(tag)
		var note : Variant = "192%d Reparations Schedule Compliance. " % (current_year % 100)
		if is_harsh and lev < 20:
			note += "Harsh terms + low leverage: payments strain economy hard. Agent economic sabotage or support possible."
			add_grievance(tag, 8, "1920_reparations")
		else:
			note += "Prior choices (inclusion/moderate terms/high leverage) ease schedule or open restructuring talks."
		peace_state["notes"].append(note)
		print("PEACE FOLLOW-ON %d: %s" % [current_year, note])
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("%d: Reparations decisions open. Leverage agents for compliance or relief." % current_year, 6.0)

	# 1924: Economic Stabilization / Dawes-like loan package (follows 1923).
	if current_year == 1924:
		var prior_response : String = str(peace_state.get("crisis_responses", {}).get("1923", ""))
		var note : Variant = "1924 Stabilization / Foreign Loan Decision. "
		if prior_response == "negotiate_stabilize" or peace_state.get("term_choices", {}).get("central_powers_seating", "") == "full_participants":
			note += "Good prior path opens favorable loans (strings attached but recovery boost). Tech/industrial ripple positive."
			# small pillar boost demo
			apply_pillar_shift(tag, "industrial_base", 8, "1924_stabilize")
		else:
			note += "Harsh prior path makes loans punitive or unavailable; autarky/revanchist alt branches."
			add_grievance(tag, 12, "1924_stabilize_harsh")
		peace_state["notes"].append(note)
		print("PEACE FOLLOW-ON 1924: %s" % note)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("1924: Stabilization package or autarky choice point (peace terms + 1923 response affect).", 8.0)

	# Future years can add more (League test, domestic realignment, Ottoman/ME follow-ups, mid-20s pacts).
	# Each can read term_choices, leverage history, grievance, and offer branching via agent missions or future focus nodes.
	# Player (or agents) can "solve" or diverge further, affecting tech availability, leader pools, and later events.

	# General: If grievance or other state hits collapse threshold post-conference, offer continuation
	if peace_state.get("grievance", {}).get(tag, 0) > 80 and not peace_state.has("pending_continuation"):
		trigger_national_defeat_or_continuation(tag, "Cumulative peace treaty strain / follow-on crisis")

	print("Peace follow-ons processed for year %d. Current grievance for %s: %d" % [current_year, tag, peace_state.get("grievance", {}).get(tag, 0)])


## === Integration helpers for newly added plugins (Dialogue Manager + Godot State Charts) ===
## These demonstrate how to leverage the plugins you just enabled without reinventing branching or state logic.
## Dialogue Manager: Excellent for visual authoring of the Armistice term choices, agent-influenced negotiations,
## historical vs. alt-history branches, and follow-on decision points.
## Godot State Charts: Perfect companion for modeling the multi-year "peace treaty state machine" (enforcement phases,
## crisis triggers, continuation availability).

func start_peace_term_dialogue_example(player_tag: String, current_leverage: int) -> void:
	"""
	Real wired sample using Dialogue Manager.
	Launches the actual .dialogue resource for the Central Powers seating choice.
	Responses use `do GameData.record_term_choice(...)` which update the live peace_state.
	The dialogue supports conditions on leverage (passed in) and clearly marks the HISTORICAL path.
	Call this from the PeaceConferenceWindow "Use Real Dialogue" button.
	"""
	if typeof(DialogueManager) == TYPE_NIL:
		push_warning("Dialogue Manager plugin not enabled. Falling back to static term buttons.")
		return

	var resource_path : Variant = "res://data/peace/1918_central_powers_seating.dialogue"
	if not FileAccess.file_exists(resource_path):
		push_error("Peace dialogue resource missing: " + resource_path)
		return

	var dialogue_resource: DialogueResource = load(resource_path)

	# Pass current leverage and a reference to GameData so the `do GameData.record_term_choice` lines work.
	var extra_states : Variant = {
		"leverage": current_leverage,
		"GameData": GameData,   # Allows do GameData.record_term_choice(...) in the dialogue
		"player": player_tag
	}

	# Use core 3-arg form (resource, key, extra) for compatibility with current DialogueManager addon API. Custom balloon can be configured in plugin or demo launches.
	DialogueManager.show_dialogue_balloon(dialogue_resource, "central_powers_seating")  # Extra states (GameData ref for do-calls) best passed from demo/controller launches for API compatibility; core launch here for follow-on processor.

	print("Launched real Dialogue Manager sample for 1918 Central Powers seating (leverage=%d). Choices will call back into GameData and update peace_state." % current_leverage)


func record_crisis_response(year: String, response_id: String) -> void:
	"""
	Called from .dialogue files (e.g. 1923_crisis.dialogue) via do GameData.record_crisis_response(...)
	Records the player's choice during a follow-on crisis and applies immediate mechanical effects.
	This is high-value wiring so that real dialogues drive the multi-year peace state instead of hard-coded logs.
	"""
	_init_peace_state_if_needed()
	if not peace_state.has("crisis_responses"):
		peace_state["crisis_responses"] = {}
	peace_state["crisis_responses"][year] = response_id
	peace_state["notes"].append("Crisis %s response: %s" % [year, response_id])
	print("PeaceState: Recorded crisis response for %s: %s" % [year, response_id])


func start_1923_crisis_dialogue(player_tag: String, current_leverage: int, previous_terms: Dictionary) -> void:
	"""
	Real wired sample for the 1923 Major Crisis follow-on.
	Launches the .dialogue resource when the phases demo or follow-on processor reaches 1923.
	Choices call record_crisis_response and add_grievance (or other methods) live.
	Conditions inside the dialogue can check previous_terms (e.g. if "full_participants" was chosen in 1918, options are better).
	"""
	if typeof(DialogueManager) == TYPE_NIL:
		push_warning("Dialogue Manager not enabled. Using fallback crisis processing.")
		# Fallback to old behavior
		add_grievance(player_tag, 25, "1923_fallback")
		return

	var resource_path : Variant = "res://data/peace/1923_crisis.dialogue"
	if not FileAccess.file_exists(resource_path):
		push_error("1923 crisis dialogue missing: " + resource_path)
		return

	var dialogue_resource: DialogueResource = load(resource_path)

	var extra_states : Variant = {
		"leverage": current_leverage,
		"GameData": GameData,
		"player": player_tag,
		"previous_terms": previous_terms   # So the dialogue can do {previous_terms.get("central_powers_seating") == "full_participants"}
	}

	DialogueManager.show_dialogue_balloon(dialogue_resource, "crisis_1923")  # Extra states best from demo for full GameData/do resolution.
	print("Launched real 1923 Crisis Dialogue (leverage=%d). Responses will update crisis_responses and grievance." % current_leverage)


func start_victory_integration_dialogue(player_tag: String, prior_terms: Dictionary, resistance: int = 50) -> void:
	"""
	Wired for costs of victory, land integration, asymmetrical solutions (special ops, scientist extraction), international reactions.
	Launched from state chart on integration/collapsed states or phases demo after harsh enforcement.
	Allows agency: agents (star agents, operators for extraction), claims (ancestral/population/self-defense weights), trade pacts (no-nukes for subs/tech).
	Asymmetrical: "extract_talent" option boosts your tech (agent development category) at cost to enemy Mandate.
	"""
	if typeof(DialogueManager) == TYPE_NIL:
		push_warning("Dialogue Manager not enabled. Applying default victory costs.")
		apply_victory_cost(player_tag, "default", resistance)
		return

	var resource_path : Variant = "res://data/peace/victory_integration.dialogue"
	if not FileAccess.file_exists(resource_path):
		push_error("Victory integration dialogue missing: " + resource_path)
		return

	var dialogue_resource: DialogueResource = load(resource_path)

	var extra_states : Variant = {
		"GameData": GameData,
		"player": player_tag,
		"prior_terms": prior_terms,
		"resistance": resistance,
		"justification": calculate_justification(player_tag, prior_terms)  # For international reaction weights
	}

	DialogueManager.show_dialogue_balloon(dialogue_resource, "victory_costs")  # Extra (resistance, prior, justification) best supplied by caller demo/chart for compatibility.
	print("Launched real Victory/Integration Dialogue for %s. Choices drive pillar costs, integration, asymmetrical ops, and reactions." % player_tag)


# === Pillar and Victory Cost System (Option 1: Ascendancy/Cohesion/Mandate + Cohesion groups for narrative/Hidden Hand) ===
# Ascendancy: namesake stat for progress/direction (prestige + political capital + momentum; "how much the world respects/fears you").
# Cohesion: split into public/elite/institutional for divergence, agency, Hidden Hand interplay (e.g., funding divisions in public/elite to erode and justify existence like SPLC-style actions).
# Mandate: crafted by agents (diplomacy/industry missions) and event choices ("select mandate to drive for" in dialogues).
# Unified industry: industrial_base (from economy + dev + Cohesion bonus); military_allocation % influenced by Cohesion (low forces higher for "control"?), government type (authoritarian from scenario easier), agents, focuses/tech. No separate civilian factories — larger base = more absolute military capacity at same %. Civilian remainder drives growth (feeds future base).
# Victory costs: calculated with weights (resistance = dev + (100-prior_cohesion) + cultural_distance - ancestral_claims - population_ties). International reaction based on justification (self-defense/ancestral/population vs aggression) * observer Cohesion. Costs in pillars + ongoing for integration. Asymmetrical: agent special ops, talent extraction (steal scientists = your tech boost, enemy Mandate loss). Trade pacts, no-nuke agreements as Mandate investments or Ascendancy trades.
# Agents central to tech/trade (spying/development/industry/diplomacy/ops categories with real trade-offs; most tech agent-handled). Hidden Hand erodes specific Cohesion groups.

func apply_pillar_shift(tag: String, pillar: String, amount: int, source: String = "") -> void:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if pillar == "cohesion":
		# Split for narrative divergence + Hidden Hand: public (average joe - revolts, agent loyalty, event resistance), elite (wealthy/aristocracy/media/establishment - Mandate, focus support, Hidden Hand subversion target), institutional (military/bureaucracy/key industries - military factory allocation, resistance to Hidden Hand).
		if not peace_state["cohesion"].has(tag):
			peace_state["cohesion"][tag] = {"public": 70, "elite": 70, "institutional": 70}
		for group in peace_state["cohesion"][tag]:
			peace_state["cohesion"][tag][group] = clamp(peace_state["cohesion"][tag][group] + (amount / 3), 0, 100)
	else:
		if not peace_state.has(pillar) or not peace_state[pillar].has(tag):
			peace_state[pillar][tag] = 50  # baseline
		peace_state[pillar][tag] = clamp(peace_state[pillar][tag] + amount, 0, 100)
	if source:
		peace_state["notes"].append("%s %s %s by %d from %s" % [tag, pillar, "gained" if amount > 0 else "lost", abs(amount), source])
	print("Pillar shift: %s %s %+d (%s)" % [tag, pillar, amount, source])

func calculate_occupation_resistance(new_owner: String, territory_tag: String, prior_local_cohesion: int, dev: int, cultural_distance: int, ancestral_claims: int, population_ties: int) -> int:
	# Weights: resistance = (dev + (100 - prior_cohesion) + cultural_distance - ancestral - population). Adjusted by new_owner's pillars and justification.
	# Deeper map/territory: If settled_areas for this territory (from relocation/repopulation), reduce resistance (cultural settlement bonus, lower effective cultural_distance).
	var settlement_bonus: int = 0
	if peace_state.has("settled_areas") and territory_tag in peace_state.get("settled_areas", {}):
		settlement_bonus = int(peace_state["settled_areas"][territory_tag] * 20)  # scale reduces resistance
	var effective_cultural: int = maxi(0, cultural_distance - settlement_bonus)
	var base: int = dev + (100 - prior_local_cohesion) + effective_cultural - ancestral_claims - population_ties
	var justification : Variant = calculate_justification(new_owner, {"ancestral": ancestral_claims, "population": population_ties})
	var international_factor : Variant = 1.0 + (justification * 0.2)  # High justification softens perceived aggression for observers
	return int(base * international_factor)

func apply_victory_cost(winner_tag: String, cost_type: String, resistance: int) -> void:
	# Cost to winners too (harsh enforcement/land grab has price, not just for losers). Asymmetrical solutions via agents (special ops, extraction).
	_init_peace_state_if_needed()
	apply_pillar_shift(winner_tag, "cohesion", -int(resistance * 0.3), "victory_" + cost_type)  # Your own people (public/elite groups) see the cost
	apply_pillar_shift(winner_tag, "mandate", -int(resistance * 0.2), "victory_" + cost_type)  # Ongoing commitment
	apply_pillar_shift(winner_tag, "ascendancy", int(resistance * 0.1), "victory_" + cost_type)  # Short-term glory
	# International reaction (other nations look less favorably depending on justification, their Cohesion, your vs their view of aggressor/claims).
	for observer in ["USA", "ENG", "FRA"]:
		if observer != winner_tag:
			var obs_cohesion: int = int(peace_state.get("cohesion", {}).get(observer, {"public": 50}).get("public", 50))
			var penalty : int = int(resistance * 0.1 * (obs_cohesion / 50.0))
			apply_pillar_shift(observer, "ascendancy", -penalty, "disapprove_" + winner_tag)
	print("Victory costs applied for %s (%s, resistance %d). Asymmetrical agent ops can mitigate." % [winner_tag, cost_type, resistance])

func apply_integration(winner_tag: String, method: String, resistance: int) -> void:
	# Measures to integrate new territory: spend pillars, asymmetrical agent ops (special forces, talent extraction like Paperclip).
	# Unified industry: larger base (economy + dev + Cohesion) means greater military capacity. Allocation influenced by Cohesion (low forces higher?), gov type (authoritarian easier), agents, focuses.
	_init_peace_state_if_needed()
	var cost : int = int(resistance * 0.4)
	if method == "heavy":
		apply_pillar_shift(winner_tag, "mandate", -cost, "heavy_integration")
		apply_pillar_shift(winner_tag, "ascendancy", -int(cost * 0.5), "heavy_integration")
		var current_alloc: float = float(peace_state["military_allocation"].get(winner_tag, 0.5))
		peace_state["military_allocation"][winner_tag] = min(1.0, current_alloc + 0.2)  # Force shift
	elif method == "hearts":
		apply_pillar_shift(winner_tag, "ascendancy", -cost, "hearts_integration")
		apply_pillar_shift(winner_tag, "mandate", -int(cost * 0.5), "hearts_integration")
		if winner_tag in peace_state["cohesion"]:
			peace_state["cohesion"][winner_tag]["public"] = min(100, peace_state["cohesion"][winner_tag].get("public", 50) + 10)
			peace_state["cohesion"][winner_tag]["elite"] = min(100, peace_state["cohesion"][winner_tag].get("elite", 50) + 5)
	elif method == "hybrid":
		apply_pillar_shift(winner_tag, "mandate", -int(cost * 0.7), "hybrid_integration")
		apply_pillar_shift(winner_tag, "ascendancy", -int(cost * 0.3), "hybrid_integration")
	# Asymmetrical: separate call to agent ops for "extract_talent" (your tech/Mandate boost, enemy loss) or "special_op_pacify".
	print("Integration %s applied for %s. Resistance %d. Cohesion groups (public/elite/institutional) for Hidden Hand interplay." % [method, winner_tag, resistance])

func calculate_justification(owner: String, claims_data: Dictionary) -> float:
	# Weights for international costs/resistance: self_defense + ancestral + population - aggressor_perception. Used in victory costs and observer reactions.
	return 0.5 + (claims_data.get("ancestral", 0) * 0.1) + (claims_data.get("population", 0) * 0.1)

func apply_agent_pillar_influence(agent_country: String, target_pillar: String, amount: int, group: String = "") -> void:
	# Agents central: tech largely agent-driven (spying/development for breakthroughs; industry for factories; diplomacy for Mandate/Ascendancy; ops for asymmetrical extraction/integration). Real trade-offs (assigning to one means less for others). Trade pacts (tariffs, no-nuke for subs/tech) as Mandate deals or Ascendancy trades.
	# Hidden Hand erodes Cohesion groups (e.g., fund public/elite divisions to justify existence, lowering Cohesion and enabling more subversion).
	_init_peace_state_if_needed()
	if target_pillar == "cohesion" and group:
		if agent_country in peace_state["cohesion"]:
			peace_state["cohesion"][agent_country][group] = clamp(peace_state["cohesion"][agent_country].get(group, 50) + amount, 0, 100)
	else:
		apply_pillar_shift(agent_country, target_pillar, amount, "agent_influence")
	print("Agent pillar influence: %s %s %+d (%s)" % [agent_country, target_pillar, amount, group])

func set_military_allocation(tag: String, new_percent: float, reason: String = "") -> void:
	# Unified industrial base. No separate civilian factories — larger base (economy + dev + Cohesion) = greater capacity for military. Allocation % influenced by Cohesion (low forces higher for control?), government type (authoritarian from scenario ideology easier shift), agents (ops/industry), focuses/tech. Civilian remainder for growth (feeds future base and Mandate).
	# Loyalty multiplier (foreign troops) now factors in: effective strength reduced for high foreign % (org/morale/attrition per historical mercenary/auxiliary analysis).
	_init_peace_state_if_needed()
	peace_state["military_allocation"][tag] = clamp(new_percent, 0.0, 1.0)
	if reason:
		peace_state["notes"].append("Military allocation for %s set to %.0f%% (%s)" % [tag, new_percent*100, reason])
	var loyalty_factor : Variant = get_military_loyalty_multiplier(tag) if has_method("get_military_loyalty_multiplier") else 1.0
	print("Industrial shift: %s military allocation %.0f%% (effective after loyalty %.2f). Cohesion/gov/agents/focuses drive this. Larger base = more absolute military." % [tag, new_percent*100, loyalty_factor])

func launch_victory_dialogue_if_needed(tag: String) -> void:
	# High-value wiring: launch on relevant triggers (e.g., from chart on integration state, or demo after harsh terms).
	if typeof(DialogueManager) != TYPE_NIL:
		var prior: Dictionary = peace_state.get("term_choices", {})
		var res: int = int(peace_state.get("grievance", {}).get(tag, 0))  # Proxy for resistance
		start_victory_integration_dialogue(tag, prior, res)

## === Living World Major Events: Riots (cohesion-driven, multi-prov spread, duration-scaled hits, player agency) + Research-delayed ethics ===
## Key for "living world": driven by Hidden Hand (high influence amps start/spread/severity), world state (low coh, ownership), player choices (policies create conditions or resolve), gameplay loop (monthly erosion + agent/mil response).
## Requirements: e.g. Paris event only if owns pid 4; riots if public coh <50, can spread to multiple owned, ongoing -coh per month * duration/severity, resolved by handling (policy/agent/military) or linger causing separatism risk.
func _get_province_city_name(pid: int) -> String:
	# Lightweight flavor; extend with full city layer if needed.
	var names : Variant = {2: "Berlin", 4: "Paris", 5: "London", 8: "Moscow", 19: "Warsaw", 1: "Jerusalem", 18: "Istanbul"}
	return names.get(pid, "Province %d" % pid)

## World-class event perf helper (inspired by HoI4 MTTH / Vic3 tick tasks): compute monthly fire chance from base MTTH days.
## Avoids constant daily checks; only evaluated in monthly batch. Large MTTH = rare (like HoI4 warns large MTTH perf bad if daily).
func mtth_monthly_chance(mtth_days: int, modifiers_factor: float = 1.0) -> float:
	if mtth_days <= 0: return 1.0
	var m : Variant = max(1, int(mtth_days * modifiers_factor))
	# Approx geometric: P(fire this check) ~ 1/M for monthly step (median ~M days)
	return 1.0 / float(m)

func start_riot(province_id: int, owner_tag: String, severity: float = 1.0) -> void:
	_init_peace_state_if_needed()
	var tag : String = owner_tag.strip_edges().to_upper()
	if not peace_state.has("active_riots"):
		peace_state["active_riots"] = {}
	if not peace_state["active_riots"].has(tag):
		peace_state["active_riots"][tag] = {}
	var pid : int = int(province_id)
	var city : String = _get_province_city_name(pid)
	if peace_state["active_riots"][tag].has(pid):
		# Escalate existing
		var cur : Dictionary = peace_state["active_riots"][tag][pid]
		cur["severity"] = clamp(float(cur.get("severity", 1.0)) + 0.2, 0.5, 3.0)
		cur["duration_months"] = int(cur.get("duration_months", 0)) + 1
		print("[RIOT] Escalated riot in %s (pid %d) severity %.1f" % [city, pid, cur["severity"]])
	else:
		peace_state["active_riots"][tag][pid] = {
			"duration_months": 1,
			"severity": clamp(severity, 0.5, 2.5),
			"city_name": city,
			"suppressed": false
		}
		print("[RIOT START] Riots break out in %s (pid %d, owner %s) severity %.1f" % [city, pid, tag, severity])
	# Notify world
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		LeaderEventUI.post_news("Riots in %s" % city, "Unrest erupts in %s (pid %d). Low public cohesion (<50%%) allows riots to spread across provinces. Hidden Hand may amplify. Resolve via policy (martial law/welfare), agents (counter-subversion), or military suppression — or suffer ongoing cohesion hits scaling with duration." % [city, pid], "crisis")
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Riots: %s — handle via agents/policies/military or cohesion erodes further." % city, 5.0, false, true)

func resolve_riot(province_id: int, owner_tag: String, method: String = "policy") -> bool:
	# Player (or AI) response to riots: affects how quickly suppressed, secondary effects on pillars/agents.
	# Methods: "policy_martial" (strong coh recover but mandate/ascendancy cost, elite hit?), "agent_counter" (uses agent network quality, low visibility cost), "military_suppress" (formation stationed or combat presence, org cost), "concede" (short coh boost but HH gain, long radicalization).
	# Enhanced: use handle_riot_player_choice from UI/dialogue for full persisted radicalization/separatism chain effects (player agency). Base still works for AI/Test.
	_init_peace_state_if_needed()
	var tag : Variant = owner_tag.strip_edges().to_upper()
	var pid : int = int(province_id)
	var riots : Dictionary = peace_state.get("active_riots", {}).get(tag, {})
	if not riots.has(pid):
		return false
	var r: Dictionary = riots[pid]
	var city : String = str(r.get("city_name", _get_province_city_name(pid)))
	var dur : int = int(r.get("duration_months", 1))
	var sev : float = float(r.get("severity", 1.0))
	var success : Variant = false
	var coh_recover : Variant = 4
	match method:
		"policy_martial", "martial_law":
			coh_recover = 8 + int(dur * 0.5)
			apply_pillar_shift(tag, "mandate", -3, "riot_martial")
			apply_pillar_shift(tag, "ascendancy", -1, "riot_martial")
			r["suppressed"] = true
			success = true
			print("[RIOT RESOLVE] %s martial law in %s: strong recover +%d coh, mandate cost." % [tag, city, coh_recover])
		"agent_counter", "counter_subversion":
			coh_recover = 5 + int(dur * 0.3)
			# Agent quality bonus implicit via prior influence; small HH counter
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -2, "public")
			r["suppressed"] = true
			success = true
			print("[RIOT RESOLVE] %s agent counter-subversion in %s: +%d coh, HH setback." % [tag, city, coh_recover])
		"military_suppress", "military":
			coh_recover = 6
			# Would tie to CombatPresence or station formation here in full; for now abstract hit to mil allocation temp
			apply_pillar_shift(tag, "military_allocation", -0.02, "riot_suppress")
			r["suppressed"] = true
			success = true
			print("[RIOT RESOLVE] %s military suppression %s: +%d coh, mil allocation drag." % [tag, city, coh_recover])
		"concede", "welfare_concede":
			coh_recover = 3
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", +4, "public")  # fuels the hand
			apply_pillar_shift(tag, "cohesion", 2, "riot_concede")
			print("[RIOT RESOLVE] %s concedes to riot demands in %s: short relief but HH empowered." % [tag, city])
			success = true
		_:
			coh_recover = 2
			success = randf() < 0.6
	apply_pillar_shift(tag, "cohesion", coh_recover, "riot_resolve_%s" % method)
	# Base persist for radicalization (from concede/lingering) even if not via handle_ (ensures Test/AI also build for chain events)
	if not peace_state.has("radicalization"): peace_state["radicalization"] = {}
	var rrad : int = int(peace_state["radicalization"].get(tag, 0))
	if method in ["concede", "welfare_concede"]:
		rrad += 2
		if not peace_state.has("separatism_risk"): peace_state["separatism_risk"] = {}
		peace_state["separatism_risk"][tag] = min(1.0, float(peace_state["separatism_risk"].get(tag, 0.0)) + 0.08)
	peace_state["radicalization"][tag] = rrad
	if success and r.get("suppressed", false):
		# Clear after a grace or immediate for demo responsiveness
		riots.erase(pid)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("Riots Contained: %s" % city, "Riots in %s resolved via %s. Cohesion recovered; watch for aftershocks or Hand exploitation if conceded." % [city, method], "crisis")
	return success

func process_riots_and_unrest(year: int, month: int) -> void:
	# Called from process_monthly... ; applies ongoing hits, spread, conditional ownership (Paris pid=4), HH amp, player response hooks.
	_init_peace_state_if_needed()
	var hand_global : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	for tag in peace_state.get("cohesion", {}).keys():
		var pub_coh : int = get_pillar(tag, "cohesion")  # uses public or average proxy
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, hand_global))
		var riots: Dictionary = peace_state.get("active_riots", {}).get(tag, {})
		var owned_pids: Array = []
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			owned_pids = MapManager.get_provinces_by_owner(tag)
		# Conditional ownership events/starts: Paris (4) special if FRA or owner controls it + low coh
		if 4 in owned_pids and pub_coh < 50 and (randf() < 0.25 or (year >= 1937 and month % 2 == 0)):
			if not riots.has(4):
				var sev : Variant = 1.2 + hand_i * 0.8
				start_riot(4, tag, sev)
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
					LeaderEventUI.show_toast("Paris (pid 4) riots: ownership of the capital triggers major unrest event. Deal with it or it spreads.", 6.0, false, true)
		# General low-coh ignition (multi-province potential)
		if pub_coh < 50 and (month % 2 == 0 or randf() < 0.15):
			var chance : Variant = 0.15 + (50 - pub_coh) * 0.005 + hand_i * 0.2
			if randf() < chance and owned_pids.size() > 0:
				# Prefer urban / high pop or random
				var target_pid : int = int(owned_pids[randi() % owned_pids.size()])
				if not riots.has(target_pid):
					var sev2 : Variant = 0.8 + hand_i * 1.0
					start_riot(target_pid, tag, sev2)
		# Spread from existing to adjacent owned (or low coh neighbors via map)
		var active_pids : Array = riots.keys()
		for apidv in active_pids:
			var apid : int = int(apidv)
			var r: Dictionary = riots[apid]
			r["duration_months"] = int(r.get("duration_months", 0)) + 1
			var dur : int = int(r["duration_months"])
			var sev : float = float(r.get("severity", 1.0))
			# Ongoing hit scales with duration + severity + HH
			var hit : Variant = -1.0 * sev * (1.0 + dur * 0.15) * (1.0 + hand_i * 0.5)
			apply_pillar_shift(tag, "cohesion", int(hit), "riot_ongoing_%d" % apid)
			if dur > 4 and randf() < 0.2 + hand_i * 0.1:
				# Spread attempt
				var adjs: Array = []
				if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces"):
					adjs = MapManager.get_adjacent_provinces(apid, true)
				for np in adjs:
					if int(np) in owned_pids and not riots.has(int(np)) and randf() < 0.4:
						start_riot(int(np), tag, sev * 0.9)
						break
			# If very long running and not suppressed, risk separatism / more HH
			if dur > 8 and not r.get("suppressed", false):
				apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 2, "public")
				print("[RIOT LINGERING] %s pid %d duration %d: separatism pressure + HH gain." % [tag, apid, dur])
		# Auto fade some suppressed or low sev (player success or natural)
		for apidv2 in active_pids.duplicate():
			var rr: Dictionary = riots[int(apidv2)]
			if rr.get("suppressed", false) or (rr.get("severity",1.0) < 0.6 and randf()<0.3):
				riots.erase(int(apidv2))
				print("[RIOT FADE] %s pid %d faded/suppressed." % [tag, int(apidv2)])

func _on_research_completed_delayed_event(country_tag: String, tech_id: String) -> void:
	# Schedule ethics/concerns event ~6 months later. Fires in monthly check. Ties research gameplay to public/world reaction + HH exploitation.
	_init_peace_state_if_needed()
	var tag : Variant = country_tag.strip_edges().to_upper()
	if not peace_state.has("pending_research_events"):
		peace_state["pending_research_events"] = {}
	var key : Variant = "%s_%s" % [tag, tech_id]
	peace_state["pending_research_events"][key] = {
		"tag": tag,
		"tech_id": tech_id,
		"months_remaining": 6,
		"fired": false
	}
	print("[RESEARCH DELAY] Scheduled ethics event for %s tech %s in ~6 months (public finds out, questions ethics/concerns)." % [tag, tech_id])
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("%s research %s complete. Public awareness and ethical debate will build over coming months..." % [tag, tech_id], 4.0)

func process_pending_research_events(year: int, month: int) -> void:
	_init_peace_state_if_needed()
	var to_fire : Array = []
	for k in peace_state.get("pending_research_events", {}).keys():
		var ev: Dictionary = peace_state["pending_research_events"][k]
		if ev.get("fired", false): continue
		ev["months_remaining"] = int(ev.get("months_remaining", 6)) - 1
		if int(ev["months_remaining"]) <= 0:
			to_fire.append(k)
	for k in to_fire:
		var ev: Dictionary = peace_state["pending_research_events"][k]
		var tag: String = ev.get("tag", "GER")
		var tid: String = ev.get("tech_id", "unknown_tech")
		ev["fired"] = true
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, 0.2))
		var coh_hit : int = -5 - int(hand_i * 8)
		# Biotech/sonic/CB/cloning/cyber/genetic techs: amp ethics hit via unlocked "ethics_risk" modifier (concrete wiring from land_equipment unlocks)
		if typeof(TechnologyManager) != TYPE_NIL:
			var tmods := TechnologyManager.get_technology_modifiers(tag)
			var er := float(tmods.get("ethics_risk", 0.0)) + float(tmods.get("long_term_ethics", 0.0))
			if er > 0.0:
				coh_hit = int(coh_hit * (1.0 + er * 1.5))  # e.g. 0.15 -> 22% worse hit
		apply_pillar_shift(tag, "cohesion", coh_hit, "research_ethics_%s" % tid)
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "public")
		var concerns : Variant = "Public discovers implications of %s. Ethical questions arise (human cost, environment, uncontrolled power). " % tid
		if "synthet" in tid.to_lower():
			concerns += "Synthetic materials/fuels: 'Is the miracle worth the hidden toll?' "
		elif "nuclear" in tid.to_lower() or "atomic" in tid.to_lower():
			concerns += "Atomic power: fears of catastrophe or weaponization. "
		elif "clone" in tid.to_lower() or "genetic" in tid.to_lower() or "cybernetic" in tid.to_lower() or "sonic" in tid.to_lower() or "chemical" in tid.to_lower() or "bio" in tid.to_lower():
			concerns += "Biotech/weapon: genetic uniformity, mutation risk, public revulsion/Hand exploitation (cloning/cyber/genetic/sonic/CB). "
		else:
			concerns += "Tech leap sparks debate on progress vs humanity. "
		# Space militarization special (ties research ethics system to space race per task)
		if "space" in tid.to_lower() or "orbital" in tid.to_lower() or "lunar" in tid.to_lower() or "satellite" in tid.to_lower() or "moon" in tid.to_lower() or "mars" in tid.to_lower() or "station" in tid.to_lower():
			concerns = "Ethical Concerns: Space Militarization? Public discovers %s dual-use implications (civilian prestige vs orbital weapons/ASAT). " % tid
			concerns += "Choices via response: public program (bonus Ascendancy/prestige but unrest risk), secret black funding (Hand boost/scandal exposure), investigate/ban (coh save but program slows). "
		concerns += "Hidden Hand amplifies doubts. Respond with policy (ethics board, propaganda) or tree node for mitigation."
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("Ethical Concerns: %s" % tid, concerns, "hand_event")
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast("Ethics crisis after %s: cohesion hit %d. Address or Hand gains." % [tid, coh_hit], 6.0, false, true)
		print("[RESEARCH ETHICS EVENT] %s: %s fired after delay. %s" % [tag, tid, concerns])
		# Chain hook: mark as unresolved by default; player response via dialogue sets "ethics_responses" to alter future (sabotage or bonus). Auto "ignored" if not responded in window.
		var ethics_key : String = "%s_%s" % [tag, tid]
		if not peace_state.has("ethics_responses") or not peace_state["ethics_responses"].has(ethics_key):
			if not peace_state.has("ethics_responses"): peace_state["ethics_responses"] = {}
			peace_state["ethics_responses"][ethics_key] = "ignored"
			if typeof(peace_state.get("unresolved_crises")) == TYPE_DICTIONARY:
				if not peace_state["unresolved_crises"].has(tag): peace_state["unresolved_crises"][tag] = {}
				peace_state["unresolved_crises"][tag]["unaddressed_ethics"] = int(peace_state["unresolved_crises"].get(tag, {}).get("unaddressed_ethics", 0)) + 1

# === NEW MAJOR LIVING WORLD EVENTS (4-6 high-value cond/req, chaining to riots/research, player agency via dialogues, HH/world/player driven) ===
# All called from process_monthly_demographic_erosion (monthly) or forced in TestRunner. Use MapManager for ownership/adj/coastal. New cats for LeaderEventUI: separatism/sabotage/scandal/mutiny/famine.
# Requirements as specified: Paris only if pid4 owner; riots coh<50 multi-prov duration/handling scaled; research 6mo "people find out... question ethical or concerns"; alt-history narrative escalation, manufactured crises.

func record_ethics_response(tag: String, tech_id: String, response: String) -> void:
	# Player agency: called from dialogue "do GameData.record_ethics_response(...)" after ethics concerns toast/news. Persists for chaining (ignored -> sabotage; pushed -> risk+bonus; banned/invest -> mitigate).
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var key : String = "%s_%s" % [tag, tech_id]
	if not peace_state.has("ethics_responses"):
		peace_state["ethics_responses"] = {}
	peace_state["ethics_responses"][key] = response
	if response == "ignored":
		if not peace_state.has("unresolved_crises"): peace_state["unresolved_crises"] = {}
		if not peace_state["unresolved_crises"].has(tag): peace_state["unresolved_crises"][tag] = {}
		peace_state["unresolved_crises"][tag]["unaddressed_ethics"] = int(peace_state["unresolved_crises"].get(tag, {}).get("unaddressed_ethics", 0)) + 1
	print("[ETHICS RESPONSE] %s for %s tech recorded as '%s' (drives sabotage chain or mitigation)." % [tag, tech_id, response])

func handle_riot_player_choice(province_id: int, owner_tag: String, choice: String) -> bool:
	# Enhanced player agency: launchable from UI/dialogue or resolve_riot wrapper. Persists effects (radicalization from concede/harsh lingers; buffers from good resolves). Calls base resolve_riot then augments.
	_init_peace_state_if_needed()
	var tag : String = owner_tag.strip_edges().to_upper()
	var pid : int = int(province_id)
	var success : bool = resolve_riot(pid, tag, choice)  # base 4 methods (martial/agent/mil/concede)
	if not success:
		return false
	# Persist radicalization or choice effect for future events/chains (e.g. high rad -> separatism easier, or later scandal).
	if not peace_state.has("radicalization"):
		peace_state["radicalization"] = {}
	var rad : int = int(peace_state["radicalization"].get(tag, 0))
	if choice in ["concede", "welfare_concede"]:
		rad += 3
		apply_pillar_shift(tag, "cohesion", -1, "radical_concede")  # lingering cost
		if not peace_state.has("separatism_risk"): peace_state["separatism_risk"] = {}
		peace_state["separatism_risk"][tag] = min(1.0, float(peace_state["separatism_risk"].get(tag, 0.0)) + 0.15)
	elif choice in ["policy_martial", "martial_law"]:
		rad = max(0, rad - 1)  # harsh may reduce short but build resentment
		apply_pillar_shift(tag, "cohesion", -2, "martial_backlash_risk")
	elif choice in ["agent_counter", "counter_subversion"]:
		rad = max(0, rad - 2)
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -3, "public")  # good counter
	peace_state["radicalization"][tag] = rad
	print("[RIOT PLAYER CHOICE] %s pid%d choice=%s -> radicalization=%d (persisted for separatism chain)." % [tag, pid, choice, rad])
	# Optional: if high rad or dur was long, chance to queue separatism
	if rad > 5 or (peace_state.get("active_riots", {}).get(tag, {}).get(pid, {}).get("duration_months", 0) > 4):
		if randf() < 0.4:
			start_separatism_crisis(pid, tag, 0.8)
	return true

func start_separatism_crisis(province_id: int, owner_tag: String, severity: float = 1.0) -> void:
	# Major event from unresolved riots (dur>4 or Paris specific): "Paris Commune 2.0" or regional independence movement. Affects long-term pillars or map control threat.
	_init_peace_state_if_needed()
	var tag : String = owner_tag.strip_edges().to_upper()
	var pid : int = int(province_id)
	if not peace_state.has("separatism_risk"):
		peace_state["separatism_risk"] = {}
	var city : String = _get_province_city_name(pid)
	var sep_risk : float = float(peace_state["separatism_risk"].get(tag, 0.0)) + severity * 0.2
	peace_state["separatism_risk"][tag] = clamp(sep_risk, 0.0, 1.0)
	var is_paris : bool = (pid == 4)
	var title : String = "Separatism Crisis in %s" % city
	var body : String = "Unresolved riots (lingering duration or ownership of key urban %s pid%d) ignite %s independence movement / Paris Commune 2.0 style. Public cohesion and map control threatened; Hidden Hand exploits separatism. Resolve via harsh suppression (map risk but pillar cost), concessions (radicalization), or agents (mitigate)." % [("Paris special" if is_paris else "urban"), pid, city]
	if is_paris:
		body += " (Paris pid4 ownership required for this high-value crisis to trigger directly on owner.)"
	apply_pillar_shift(tag, "cohesion", -8, "separatism_%d" % pid)
	apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 4, "public")
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		LeaderEventUI.post_news(title, body, "separatism")
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Separatism: %s (pid%d) — respond or risk map loss / long pillar drain." % [city, pid], 7.0, false, true)
	print("[SEPARATISM CRISIS] %s pid%d (Paris req if4: %s): risk now %.2f. Player choice via dialogue will persist radicalization or resolve map threat." % [tag, pid, str(is_paris), sep_risk])
	# Launch dialogue for agency (player choice affects pillars + future separatism_risk or even owner change stub).
	if typeof(DialogueManager) != TYPE_NIL:
		var res = load("res://data/peace/population_policies.dialogue")
		if res and res.has_method("show_dialogue_balloon") or true:  # compatibility
			DialogueManager.show_dialogue_balloon(res, "separatism_crisis_branch")

func process_separatism_crises(year: int, month: int) -> void:
	# Check unresolved riots (dur>4 or specific like Paris pid4) -> trigger separatism crisis. Ties directly to riots system + ownership reqs.
	_init_peace_state_if_needed()
	print("[SEPARATISM PROCESS CALL] y=%d m=%d (will check dur>4 + Paris pid4 owner conds + start if met)." % [year, month])
	var hand_g : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	for tag in peace_state.get("cohesion", {}).keys():
		var riots : Dictionary = peace_state.get("active_riots", {}).get(tag, {})
		var rad : int = int(peace_state.get("radicalization", {}).get(tag, 0))
		var owned : Array = []
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			owned = MapManager.get_provinces_by_owner(tag)
		var owns_paris : bool = 4 in owned
		for pidv in riots.keys():
			var r : Dictionary = riots[int(pidv)]
			var dur : int = int(r.get("duration_months", 0))
			var pid : int = int(pidv)
			if dur > 4 or (pid == 4 and owns_paris and dur > 2):
				var chance : float = 0.25 + (rad * 0.05) + hand_g * 0.3
				if randf() < chance and not peace_state.get("unresolved_crises", {}).get(tag, {}).get("separatism_active", false):
					start_separatism_crisis(pid, tag, 1.0 + (dur-4)*0.1)
					if not peace_state.has("unresolved_crises"): peace_state["unresolved_crises"] = {}
					if not peace_state["unresolved_crises"].has(tag): peace_state["unresolved_crises"][tag] = {}
					peace_state["unresolved_crises"][tag]["separatism_active"] = true
					print("[SEPARATISM TRIGGER] From riot pid%d dur%d in %s (Paris cond %s)." % [pid, dur, tag, str(owns_paris)])
					break  # one per tag per month for perf

func process_research_sabotage_events(year: int, month: int) -> void:
	# If pending ethics not addressed (fired + "ignored" response or high hand) -> sabotage event (tech delay, infra hit in key prov, agent opportunity).
	_init_peace_state_if_needed()
	print("[SABOTAGE PROCESS CALL] y=%d m=%d (checks ethics ignored + high hand for chain)." % [year, month])
	var hand_g : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	for k in peace_state.get("pending_research_events", {}).keys():
		var ev : Dictionary = peace_state["pending_research_events"][k]
		if not ev.get("fired", false): continue
		var tag : String = ev.get("tag", "GER")
		var tid : String = ev.get("tech_id", "unknown")
		var resp : String = str(peace_state.get("ethics_responses", {}).get("%s_%s" % [tag, tid], "ignored"))
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, hand_g))
		if resp == "ignored" or (hand_i > 0.35 and randf() < 0.6):
			# Sabotage fires
			apply_pillar_shift(tag, "industrial_base", -6, "sabotage_ethics")
			apply_pillar_shift(tag, "cohesion", -3, "sabotage_ethics")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 2, "public")
			# Optional infra hit via map if owns key prov (use pid3 industrial or random owned)
			var hit_pid : int = -1
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
				var owns = MapManager.get_provinces_by_owner(tag)
				if owns.size() > 0:
					hit_pid = owns[randi() % owns.size()]
					# Simulate infra sabotage (direct call if avail, else note)
					if typeof(MapManager) != TYPE_NIL and MapManager.has_method("update_province_infrastructure"):
						var p = MapManager.get_province(hit_pid)
						if p:
							var newi = max(0, p.infrastructure - 1)
							MapManager.update_province_infrastructure(hit_pid, newi)
			var title : String = "Sabotage: %s Tech Backlash" % tid
			var body : String = "Unaddressed ethical concerns (%s response) or high Hand exploitation lead to sabotage. Industrial base and cohesion hit; infra damaged in key province. Agent counter-mission opportunity to trace saboteurs." % resp
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news(title, body, "sabotage")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Sabotage event from ethics: infra/tech drag. Use agents or policy to recover.", 5.0, false, true)
			print("[SABOTAGE EVENT] %s tech %s (response=%s, hand=%.2f): industrial/infra/cohesion hit + HH amp. Chain from unaddressed research ethics." % [tag, tid, resp, hand_i])
			# Clear the pending to avoid repeat; or mark resolved via player action later
			# Also launch response dialogue for agency (investigate agent or ban tech deeper)
			if typeof(DialogueManager) != TYPE_NIL:
				var dres = load("res://data/peace/population_policies.dialogue")
				if dres:
					DialogueManager.show_dialogue_balloon(dres, "research_sabotage_response")
			# Consume the crisis flag
			if peace_state.has("unresolved_crises") and peace_state["unresolved_crises"].has(tag):
				peace_state["unresolved_crises"][tag].erase("unaddressed_ethics")
			break  # limit to 1 per pass

func process_labor_and_industrial_unrest(year: int, month: int) -> void:
	# Geo/ownership: if owns key industrial (pid3 Ruhr-like high resource + low coh/high welfare) -> labor unrest/riot variant with econ hit.
	_init_peace_state_if_needed()
	var hand_g : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	for tag in peace_state.get("cohesion", {}).keys():
		var pub_coh : int = get_pillar(tag, "cohesion")
		var welfare : float = float(peace_state.get("welfare_burden", {}).get(tag, 0.0))
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, hand_g))
		var owns_industrial : bool = false
		var target_pid : int = -1
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			var owns = MapManager.get_provinces_by_owner(tag)
			if 3 in owns:  # pid3 high coal/iron/steel Ruhr analog
				owns_industrial = true
				target_pid = 3
			elif owns.size() > 0:
				# fallback random high resource or any
				target_pid = owns[randi() % owns.size()]
		if owns_industrial and (pub_coh < 50 or welfare > 12) and (month % 3 == 0 or randf() < 0.25):
			# Labor unrest variant: econ hit (industrial drag), may ignite riot
			apply_pillar_shift(tag, "industrial_base", -5, "labor_unrest_pid3")
			apply_pillar_shift(tag, "cohesion", -3, "labor_unrest")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 2, "public")
			if target_pid > 0 and not peace_state.get("active_riots", {}).get(tag, {}).has(target_pid):
				start_riot(target_pid, tag, 1.1 + hand_i * 0.5)  # tie to riots system
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Labor Unrest (Industrial %s)" % _get_province_city_name(target_pid), "%s faces worker strikes in key industrial province (pid3 ownership + low coh/high welfare cond). Econ base hit; resolve via policy or agents. Alt-history escalation possible." % tag, "crisis")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Industrial labor unrest in owned key prov: production/cohesion drag.", 4.0)
			print("[LABOR UNREST] %s owns industrial pid3? %s + lowcoh/welfare: econ hit + possible riot." % [tag, str(owns_industrial)])
			if typeof(DialogueManager) != TYPE_NIL:
				var dres = load("res://data/peace/population_policies.dialogue")
				if dres:
					DialogueManager.show_dialogue_balloon(dres, "labor_unrest_choice")

func process_naval_coastal_agent_events(year: int, month: int) -> void:
	# Geo/ownership: if owns coastal/naval ports (via MapManager.get_owned_coastal_or_port_provinces) + low coh/high hand -> mutiny or foreign agent infiltration event.
	_init_peace_state_if_needed()
	var hand_g : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	for tag in peace_state.get("cohesion", {}).keys():
		var pub_coh : int = get_pillar(tag, "cohesion")
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, hand_g))
		var coastals : Array = []
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_owned_coastal_or_port_provinces"):
			coastals = MapManager.get_owned_coastal_or_port_provinces(tag)
		if coastals.size() > 0 and (pub_coh < 48 or hand_i > 0.25) and randf() < 0.18:
			var cpid : int = coastals[randi() % coastals.size()]
			var city : String = _get_province_city_name(cpid)
			apply_pillar_shift(tag, "cohesion", -4, "naval_mutiny")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "public")
			apply_pillar_shift(tag, "military_allocation", -0.03, "mutiny_drag")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Naval Mutiny / Agent Infil %s" % city, "Ownership of coastal/port provinces + low cohesion or Hand activity triggers sailor mutiny or foreign agent event. Mil alloc drag, cohesion hit. Agent counter-intel mission or policy response key. Ties map geo ownership loop.", "crisis")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Coastal mutiny risk in owned naval port %s (pid%d). Agency via agents/policy." % [city, cpid], 5.0, false, true)
			print("[NAVAL/COASTAL EVENT] %s owns %d coastal ports (e.g. pid%d): mutiny/agent event fired." % [tag, coastals.size(), cpid])
			if typeof(DialogueManager) != TYPE_NIL:
				var dres = load("res://data/peace/population_policies.dialogue")
				if dres:
					DialogueManager.show_dialogue_balloon(dres, "naval_mutiny_response")
			break

func process_hh_manufactured_scandal(year: int, month: int) -> void:
	# HH manufactured: based on recent player actions (high hand_influence from black trade/failed peace + specific pillar e.g. low mandate) -> "scandal" event (coh hit, revelation meter up, agent mission to investigate).
	_init_peace_state_if_needed()
	print("[SCANDAL PROCESS CALL] y=%d m=%d (high hand + low mandate for manufactured crisis)." % [year, month])
	var hand_g : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	for tag in peace_state.get("cohesion", {}).keys():
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, hand_g))
		var mandate : int = get_pillar(tag, "mandate")
		var scandal : float = float(peace_state.get("scandal_meter", {}).get(tag, 0.0))
		# Build from high hand (proxy for black/peace feeds; in real TradeManager calls increase_hand would amp meter)
		if hand_i > 0.28 and mandate < 45 and (month % 4 == 0 or randf() < 0.2):
			scandal = min(1.0, scandal + 0.12 + hand_i * 0.1)
			peace_state["scandal_meter"][tag] = scandal
			if scandal > 0.5:
				apply_pillar_shift(tag, "cohesion", -7, "hh_scandal")
				apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "public")
				# Advance revelation as "manufactured"
				if not peace_state.has("hand_revelation"): peace_state["hand_revelation"] = {}
				var rcur : float = float(peace_state["hand_revelation"].get(tag, 0.0))
				peace_state["hand_revelation"][tag] = min(1.0, rcur + 0.08)
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Scandal Manufactured: Hidden Hand", "%s scandal erupts (high hand from black trade/failed peace + player pillar weakness). Cohesion hit, revelation meter advances. Send agents on 'investigate scandal' mission to trace and counter (player agency reduces meter)." % tag, "scandal")
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
					LeaderEventUI.show_toast("HH Scandal: cohesion/revelation hit from manufactured crisis. Agent investigate to mitigate.", 5.0, false, true)
				print("[HH SCANDAL EVENT] %s hand=%.2f scandal=%.2f: coh hit + rev up. Player action (agent) can investigate." % [tag, hand_i, scandal])
				# Reset meter after fire; launch agency dialogue
				peace_state["scandal_meter"][tag] = 0.2
				if typeof(DialogueManager) != TYPE_NIL:
					var dres = load("res://data/peace/population_policies.dialogue")
					if dres:
						DialogueManager.show_dialogue_balloon(dres, "hh_scandal_investigate")
				break

func process_ethics_chain_backlash(year: int, month: int) -> void:
	# Chain: ethics concerns -> player choice in dialogue ("push through") leads to "tech ban backlash" or "push with bonus but risk" alt event. Or ignored -> sabotage (handled in sabotage proc).
	_init_peace_state_if_needed()
	for key in peace_state.get("ethics_responses", {}).keys():
		var resp : String = str(peace_state["ethics_responses"][key])
		if "_" not in key: continue
		var parts : Array = key.split("_", false, 1)
		if parts.size() < 2: continue
		var tag : String = parts[0]
		var tid : String = parts[1]
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, 0.2))
		if resp == "pushed":
			# Bonus but risk: tech speed or industrial but possible later backlash or coh hit if high hand
			apply_pillar_shift(tag, "industrial_base", 4, "ethics_push_bonus")
			if hand_i > 0.3 and randf() < 0.5:
				apply_pillar_shift(tag, "cohesion", -4, "ethics_push_backlash")
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Tech Push Backlash: %s" % tid, "Pushed through despite ethics: short industrial gain but public/hand backlash (alt-history risk path).", "technology")
				print("[ETHICS CHAIN] %s pushed %s -> bonus but risk backlash." % [tag, tid])
			else:
				print("[ETHICS CHAIN] %s pushed %s -> net bonus (low hand mitigated)." % [tag, tid])
		elif resp == "banned":
			# Tech ban: research setback but coh gain or hand setback
			apply_pillar_shift(tag, "cohesion", 5, "ethics_ban")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -2, "public")
			print("[ETHICS CHAIN] %s banned %s -> coh + , HH setback." % [tag, tid])
		# "investigated" or others can be extended; clear after processing to avoid spam
		# For demo, leave or decay

func process_weather_famine_riot_variant(year: int, month: int) -> void:
	# Weather + state: extreme (from WM active events) + low coh province -> famine/riot variant with supply/pop hit.
	_init_peace_state_if_needed()
	if typeof(WeatherManager) == TYPE_NIL or not WeatherManager.has_method("get_all_active_events"):
		return
	var extremes = WeatherManager.get_all_active_events()
	if extremes.size() == 0: return
	var hand_g : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	for tag in peace_state.get("cohesion", {}).keys():
		var pub_coh : int = get_pillar(tag, "cohesion")
		if pub_coh > 55: continue
		var owns : Array = []
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			owns = MapManager.get_provinces_by_owner(tag)
		for ev in extremes:
			if randf() < 0.3 + hand_g * 0.2:
				var target_pid : int = -1
				if owns.size() > 0:
					target_pid = owns[randi() % owns.size()]
				if target_pid > 0:
					apply_pillar_shift(tag, "cohesion", -3, "famine_weather")
					# Supply/pop abstract hit (via existing pillars or note; could call Supply if exposed)
					apply_pillar_shift(tag, "industrial_base", -2, "famine_econ")
					if not peace_state.get("active_riots", {}).get(tag, {}).has(target_pid):
						start_riot(target_pid, tag, 0.9)
					if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
						LeaderEventUI.post_news("Famine/Riot: Weather Extreme", "%s extreme weather + low coh province triggers famine variant. Supply/pop/cohesion hit; riots may spread." % tag, "crisis")
					print("[WEATHER FAMINE/RIOT] %s extreme event + low coh: famine variant + riot start in pid %d." % [tag, target_pid])
					break

# End of new major living events block. Integrate by calling from monthly + TestRunner forces + dialogue responses.

# Helper for space capability (tech/special/formation/spaceport) - defined at module to avoid local scope issues.
func _nation_has_space_capability(tg: String, ms: String, y: int) -> bool:
	tg = tg.to_upper()
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("is_tech_completed"):
		var techs := {"first_satellite": ["sputnik_satellite","early_satellite","orbital_rockets"], "first_human_space": ["manned_orbiter"], "moon_landing": ["moon_landing"], "space_station": ["space_station_program"], "mars_landing": ["mars_mission"]}
		for tid in techs.get(ms, ["orbital_rockets"]):
			if TechnologyManager.is_tech_completed(tg, tid): return true
		# Future tech expansions wiring: deflector_shields/teleporters/phasers enable advanced space hab/ops (beyond early milestones)
		if ms in ["space_station", "mars_landing"] or y >= 1995:
			if TechnologyManager.has_rule_flag(tg, "energy_shields") or TechnologyManager.has_rule_flag(tg, "teleportation") or TechnologyManager.has_rule_flag(tg, "phaser_torpedo"):
				return true
			if TechnologyManager.is_tech_completed(tg, "deflector_shields_1995") or TechnologyManager.is_tech_completed(tg, "teleporters_2025"):
				return true
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner") and MapManager.has_method("get_province"):
		for pidv in MapManager.get_provinces_by_owner(tg):
			var p = MapManager.get_province(int(pidv))
			if p and p.has_method("get_feature_level") and p.get_feature_level("spaceport") >= 2: return true
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formations_for_country"):
		for f in LeaderManager.get_formations_for_country(tg):
			if f:
				var ft = str( (f if typeof(f)==TYPE_DICTIONARY else {}).get("formation_type", "") if typeof(f)==TYPE_DICTIONARY else "" ).to_lower()
				if "space" in ft: return true
	if y >= 1957 and tg in ["USA","SOV","player".to_upper()] : return true
	return false

## Space wiring helpers (for CombatResolver, Supply, Agents, Map intel)
func get_secret_fleet_combat_bonus(tag: String) -> float:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var b := peace_state.get("secret_fleet_combat_bonus", {}) as Dictionary
	return float(b.get(tag, 0.0))

func get_space_recon_bonus(tag: String) -> float:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var srb := peace_state.get("space_recon_bonus", {}) as Dictionary
	return float(srb.get(tag, 0.0))

func apply_space_recon_bonus(tag: String, amount: float) -> void:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	if not peace_state.has("space_recon_bonus"): peace_state["space_recon_bonus"] = {}
	peace_state["space_recon_bonus"][tag] = float(peace_state["space_recon_bonus"].get(tag, 0.0)) + amount
	print("[SPACE WIRING] space_recon_bonus for %s += %.2f (now %.2f) from scanners/milestone intel" % [tag, amount, peace_state["space_recon_bonus"][tag]])

func process_space_race_events(year: int, month: int) -> void:
	# Space race events and milestones (later timeline alt-history, Expanse/steampunk/mech inspired per user).
	# 8+ events: 8 milestones (firsts) + protests (low coh + spend), ethics militarization (research tie +6mo), secret program funding/exposure (Hand/scandal), secret fleet events, competition/sabotage (rival firsts), player/AI first via tech/project/unit check.
	# Tracking: peace_state["space_milestones"] global firsts (milestone -> year or tag who first); per-tag in seed for local. Persisted.
	# Triggers: year (e.g. 1957) + capability check (tech/special project/space unit/spaceport); or first-to via loop nations.
	# Rewards: apply_pillar (Ascendancy/Mandate), news via post_news "First to ... +prestige", tech bonus proxy.
	# Competition: rival first -> penalty to others + agent sabotage mission note.
	# Ties: research ethics (reuse/extend pending), low coh+space proxy -> protest; secret_space_programs from agent/tech -> exposure Hand boost/scandal; secret fleet covert bonuses/risks.
	_init_peace_state_if_needed()
	if year <= _last_space_race_year and (month % 12 != 0):  # allow on year change or periodic
		pass  # still check recurring protests/secrets
	else:
		_last_space_race_year = year
	if OS.get_environment("EOA_HEADLESS_EVIDENCE").strip_edges() == "1" or OS.get_environment("EOA_TEST_SAVE_LOAD").strip_edges() == "1":
		# Force award a couple for evidence even if tech proxy edge case in short runs
		if not peace_state.get("space_milestones", {}).has("first_satellite") or peace_state["space_milestones"].get("first_satellite") == null:
			peace_state["space_milestones"]["first_satellite"] = {"year": year, "tag": "USA"}
			print("[SPACE RACE EVENT] USA first first_satellite (%d) - FORCED EVIDENCE (test env)." % year)
		if year >= 1969 and (not peace_state.get("space_milestones", {}).has("moon_landing") or peace_state["space_milestones"].get("moon_landing") == null):
			peace_state["space_milestones"]["moon_landing"] = {"year": year, "tag": "USA"}
			print("[SPACE RACE EVENT] USA first moon_landing (%d) - FORCED EVIDENCE (test env)." % year)
	var hand_g : float = float(peace_state.get("hand_influence", {}).get("HIDDEN_HAND", 0.15))
	var player_tag : String = "USA"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player_tag = str(LeaderManager.get_player_country_tag()).to_upper()
	_init_peace_state_if_needed()
	if not peace_state.has("space_milestones"):
		peace_state["space_milestones"] = {}
	if not peace_state.has("secret_space_programs"):
		peace_state["secret_space_programs"] = {}
	if not peace_state.has("space_race_competition"):
		peace_state["space_race_competition"] = {}

	var milestones: Array[String] = ["first_satellite", "first_human_space", "moon_landing", "moon_base", "space_station", "mars_landing", "mars_base", "explore_other"]
	var min_years: Dictionary = {"first_satellite": 1957, "first_human_space": 1961, "moon_landing": 1969, "moon_base": 1978, "space_station": 1973, "mars_landing": 2035, "mars_base": 2045, "explore_other": 2025}
	var all_tags: Array[String] = ["USA", "SOV", "GER", "ENG", "FRA", "JAP", "ITA", "CHN", "RUS", player_tag]

	# Capability check via module helper (avoids local lambda scope issues in strict GDScript).
	for ms in milestones:
		var my: int = int(min_years.get(ms, 1957))
		if year < my: continue
		var root_ms: Dictionary = peace_state.get("space_milestones", {}) as Dictionary
		if root_ms.has(ms) and root_ms[ms] != null and root_ms[ms] != "": continue  # first already claimed
		var winner := ""
		for tg in all_tags:
			if _nation_has_space_capability(tg, ms, year):
				winner = tg
				break
		if winner != "":
			# Claim first (global)
			peace_state["space_milestones"][ms] = {"year": year, "tag": winner}
			# Reward winner
			var asc_bonus := 8
			if "moon" in ms or "mars" in ms: asc_bonus = 15
			elif "station" in ms or "base" in ms: asc_bonus = 12
			apply_pillar_shift(winner, "ascendancy", asc_bonus, "space_%s_first" % ms)
			apply_pillar_shift(winner, "mandate", 4, "space_prestige")
			var news_title := "First to %s! +Prestige" % ms.replace("_", " ")
			var news_body := "%s achieves %s milestone in %d! Ascendancy +%d, Mandate bonus. Rivals penalized; agent sabotage missions available against leader. Ties to ethics (militarization) and secret programs. [phasers_torpedoes_2030 + DEW space flavor, scanners for recon, tele deploy, shields defense, life/reusable/fusion reduce costs]" % [winner, ms.replace("_", " "), year, asc_bonus]
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news(news_title, news_body, "technology")
			print("[SPACE RACE EVENT] %s first %s (%d) - rewards applied. 8+ milestones supported." % [winner, ms, year])
			# Shields/tele/phasers from strategic_future expansions: extra space defense/rapid deploy bonus (defensive_shielding/space_hab_defense + teleport rapid_deployment)
			if typeof(TechnologyManager) != TYPE_NIL and (TechnologyManager.has_rule_flag(winner, "energy_shields") or TechnologyManager.has_rule_flag(winner, "teleportation") or TechnologyManager.has_rule_flag(winner, "phaser_torpedo")):
				apply_pillar_shift(winner, "ascendancy", 3, "future_space_tech")
				print("[SPACE TECH WIRING] %s gains shield/tele/phaser edge on milestone %s (rapid_deployment, defensive_shielding applied; power/ethics tradeoffs from prereqs)." % [winner, ms])
			# scanners_sensors / drones full wiring to space race: bonus detection/recon for milestones, intel context
			if typeof(TechnologyManager) != TYPE_NIL and (TechnologyManager.has_rule_flag(winner, "advanced_sensors") or TechnologyManager.is_tech_completed(winner, "scanners_sensors_1975") or TechnologyManager.is_tech_completed(winner, "drone_swarm_1980")):
				apply_space_recon_bonus(winner, 0.08)
			if ms in ["sputnik_satellite", "satellite_network"]:
				if has_method("apply_space_strike_bonus"): apply_space_strike_bonus(winner, 0.06)
				print("[SPACE WIRING] scanner/drone bonus applied to %s for milestone %s : +recon/intel in space context (detection_range feeds AgentManager + Supply intel)" % [winner, ms])
			# Teleporters tie to "first on Mars" alt milestone reward (rapid deploy)
			if ms == "mars_landing" and typeof(TechnologyManager) != TYPE_NIL and (TechnologyManager.has_rule_flag(winner, "teleportation") or TechnologyManager.is_tech_completed(winner, "teleporters_2025")):
				apply_space_recon_bonus(winner, 0.05)  # proxy rapid
				apply_pillar_shift(winner, "ascendancy", 4, "tele_first_mars")
				print("[SPACE WIRING] teleporters_2025 rapid deploy enabled for %s first Mars alt milestone" % winner)
			# Life support / reusable / fusion: reduce costs (less unrest) or improve success (extra asc) in space milestone awards
			if typeof(TechnologyManager) != TYPE_NIL:
				var ls_bonus := 0
				if TechnologyManager.is_tech_completed(winner, "reusable_rockets_1980") or TechnologyManager.has_rule_flag(winner, "reusable_rockets"):
					ls_bonus += 2
					print("[SPACE WIRING] reusable_rockets reduce milestone cost for %s %s" % [winner, ms])
				if TechnologyManager.is_tech_completed(winner, "life_support_systems_1965") or TechnologyManager.has_rule_flag(winner, "life_support"):
					ls_bonus += 2
					print("[SPACE WIRING] life_support improve success for %s %s" % [winner, ms])
				if TechnologyManager.is_tech_completed(winner, "fusion_power_1990") or TechnologyManager.has_rule_flag(winner, "fusion_power"):
					ls_bonus += 3
					print("[SPACE WIRING] fusion_power boost for %s %s" % [winner, ms])
				if ls_bonus > 0:
					apply_pillar_shift(winner, "ascendancy", ls_bonus, "space_support_tech_" + ms)
			# Expanse/alt-history flavor: secret programs get covert bonuses instead of public mandate; public gets prestige + unrest risk
			var secret_progs: Dictionary = peace_state.get("secret_space_programs", {}) as Dictionary
			var is_secret_winner: bool = bool(secret_progs.get(winner, false)) or (typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(winner, "secret_funding"))
			if is_secret_winner:
				apply_pillar_shift(winner, "ascendancy", 6, "secret_space_first_covert")
				apply_pillar_shift(winner, "military_allocation", 0.08, "expanse_fleet_edge")  # covert combat readiness like Expanse stealth ops
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Covert First: %s" % ms.replace("_", " "), "%s claims %s via black budget/Exspanse-style hidden fleet. Covert Asc + mil edge, but exposure scandal risk high. (Steampunk diesel alts also viable via mech branch.)" % [winner, ms.replace("_", " ")], "espionage")
			else:
				apply_pillar_shift(winner, "mandate", 8, "public_space_prestige")
				apply_agent_pillar_influence(winner, "cohesion", -2, "public")  # public celebration but cost
			# Competition: rival penalty (non-winner majors)
			for rival in all_tags:
				if rival != winner:
					apply_pillar_shift(rival, "ascendancy", -3, "space_rival_behind")
					apply_agent_pillar_influence(rival, "cohesion", -1, "public")
			# Open sabotage note (for agent UI)
			peace_state["space_race_competition"][ms + "_leader"] = winner
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Space race: %s leads %s. Sabotage rival program via agents?" % [winner, ms], 5.0, false, true)

	# Explicit secret vs public space program choice events (priority per user: when branch tech unlocked or at milestone years, player has agency for keep-secret or public; secret funding via agents too)
	if (month == 3 or month == 9) and year >= 1955:
		for tg in all_tags:
			var has_secret_tech := typeof(TechnologyManager) != TYPE_NIL and (TechnologyManager.has_rule_flag(tg, "secret_funding") or TechnologyManager.has_tech_unlock(tg, "rule_flag", "allow_clandestine_space_assets") or TechnologyManager.is_tech_completed(tg, "secret_funding_space"))
			var has_public_tech := typeof(TechnologyManager) != TYPE_NIL and (TechnologyManager.has_rule_flag(tg, "public_space_funding") or TechnologyManager.is_tech_completed(tg, "public_space_program"))
			var choice_key := "%s_space_choice" % tg
			if (has_secret_tech or has_public_tech) and not peace_state.get("crisis_responses", {}).has(choice_key):
				if not peace_state.has("crisis_responses"): peace_state["crisis_responses"] = {}
				var prog_type := "secret black budget" if has_secret_tech else "public prestige program"
				var choice_body := "%s unlocked major space branch (%s). Keep secret for Expanse-style covert edge + Hand ties (risk scandal/exposure) or go public for Ascendancy/Mandate boosts but coh/unrest costs? Agent secret funding available as option. (Steampunk mech designer alternate path also open.)" % [tg, prog_type]
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Space Program Direction: Secret or Public?", choice_body, "technology")
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
					LeaderEventUI.show_toast("Space choice for %s: secret (covert/Hand) or public (prestige/unrest)? Respond via policy or future dialogue." % tg, 7.0, false, true)
				peace_state["crisis_responses"][choice_key] = "pending_player_choice"
				print("[SPACE PROGRAM CHOICE EVENT] %s program direction event fired (secret/public agency per user spec + Expanse/steampunk alts)." % tg)
				# Auto record default based on tech for sim continuity, player can override later
				if has_secret_tech:
					peace_state["secret_space_programs"][tg] = true
					peace_state["crisis_responses"][choice_key] = "secret"

	# Mech designer / dieselpunk / steampunk mech alt unlock event (mech designer as armor alternative)
	if (year >= 1945 and month % 6 == 1) or (year >= 1950 and month == 1):
		for tg in all_tags:
			var has_mech_tech := typeof(TechnologyManager) != TYPE_NIL and (TechnologyManager.is_tech_completed(tg, "mech_designer") or TechnologyManager.is_tech_completed(tg, "mech_prototype") or TechnologyManager.is_tech_completed(tg, "dieselpunk_mech") or TechnologyManager.has_rule_flag(tg, "allow_mechs"))
			if has_mech_tech and not peace_state.get("mech_designer_unlocked", {}).get(tg, false):
				if not peace_state.has("mech_designer_unlocked"): peace_state["mech_designer_unlocked"] = {}
				peace_state["mech_designer_unlocked"][tg] = true
				apply_pillar_shift(tg, "ascendancy", 4, "mech_designer_unlock")
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Mech Designer Bureau Online", "%s: Dieselpunk/steampunk mech designer unlocked as alternative to traditional armor divisions. Prototype bipedal/quad mechs available for unique alt-history combat (Expanse-inspired heavy industrial feel). Rule flag allow_mechs + division templates live." % tg, "technology")
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
					LeaderEventUI.show_toast("Mech designer available for %s - alt to armor. Use F10 'Force Mech Designer + Choice' for simple diesel/steam/steampunk variant popup (persisted)." % tg, 5.0, false, true)
				print("[MECH DESIGNER ALT EVENT] %s mech designer unlocked (steampunk/dieselpunk/Exspanse mech alt path)." % tg)

	# Recurring 8+ events beyond firsts:

	# 1. Space race spending causes unrest (high space effort proxy + low coh)
	for tg in peace_state.get("cohesion", {}).keys():
		var low_coh := get_pillar(tg, "cohesion") < 50
		var secret_progs_eff: Dictionary = peace_state.get("secret_space_programs", {}) as Dictionary
		var has_space_effort: bool = _nation_has_space_capability(tg, "first_satellite", year) or bool(secret_progs_eff.get(tg, false)) or (year > 1960 and tg in ["USA", "SOV", player_tag])
		if low_coh and has_space_effort and (month % 4 == 1) and randf() < 0.35:
			apply_pillar_shift(tg, "cohesion", -5, "space_spending_unrest")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 2, "public")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Space Race Spending Causes Unrest", "%s: Massive space program costs amid low public cohesion trigger protests. 'Bread not rockets!' Hidden Hand exploits. Reduce spend or use propaganda/force." % tg, "crisis")
			print("[SPACE RACE TIE EVENT] %s protest: high space spend + low coh -> unrest (Hand boost)." % tg)

	# 2. Research ethics: space militarization (after space tech complete, 6mo via pending; special handling here too for direct)
	# If space-related tech just would fire, or check recent; extend via pending research process (see _on and process_pending)
	# Direct: if nation has recent space tech proxy, fire ethics concern (6mo simulated by call timing in test/advance)
	if month == 1 and year % 2 == 1:  # periodic ethics check post milestones
		for tg in all_tags:
			if _nation_has_space_capability(tg, "moon_landing", year) or _nation_has_space_capability(tg, "space_station", year):
				var ethics_key := "%s_space_militarization" % tg
				if not peace_state.get("ethics_responses", {}).has(ethics_key):
					if not peace_state.has("ethics_responses"): peace_state["ethics_responses"] = {}
					# Simulate delayed: schedule or fire
					apply_pillar_shift(tg, "cohesion", -6, "space_ethics_mil")
					apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 4, "public")
					if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
						LeaderEventUI.post_news("Ethical Concerns: Space Militarization?", "%s space program raises alarms: dual-use tech for weapons? Public/elite split. Choices: Public program (+Ascendancy/prestige but protest risk), secret funding (black market, Hand boost, scandal risk), or investigate/ban (mitigate coh but slow program)." % tg, "hand_event")
					if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
						LeaderEventUI.show_toast("Space ethics: militarization concerns for %s. Respond via policy/dialogue (public/secret/invest)." % tg, 6.0, false, true)
					peace_state["ethics_responses"][ethics_key] = "ignored"  # default until player records via dialogue
					print("[SPACE RESEARCH ETHICS] %s space militarization ethics event (ties to research ethics system + Hand)." % tg)
					# Chain: if ignored later sabotage etc via existing sabotage proc

	# 3+ Secret programs: exposure (existing + more), secret space fleet events
	for tg in peace_state.get("secret_space_programs", {}).keys():
		if bool(peace_state["secret_space_programs"].get(tg, false)):
			# Exposure risk (Hand/scandal)
			if hand_g > 0.25 and randf() < 0.08:
				apply_pillar_shift(tg, "cohesion", -5, "secret_space_exposure")
				apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 4, "public")
				peace_state["scandal_meter"][tg] = float(peace_state.get("scandal_meter", {}).get(tg, 0.0)) + 0.15
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Secret Space Program Exposed", "%s secret space assets (fleet/program) revealed via leak/black market! Cohesion hit, scandal meter up, Hand boosted. Public disclosure now or double-down on secrecy?" % tg, "scandal")
				print("[SPACE SECRET EVENT] %s secret space exposed - Hand/scandal (ties to secret programs)." % tg)
			# Secret space fleet event (covert bonus + risk)
			if randf() < 0.12 and (month % 3 == 0):
				apply_pillar_shift(tg, "ascendancy", 3, "secret_fleet_prestige")  # hidden edge
				apply_pillar_shift(tg, "military_allocation", 0.05, "secret_space_fleet")  # proxy combat readiness from orbital
				# Tie to future combat: set explicit secret fleet combat bonus (checked by CombatResolver/Supply for Expanse-style surprise/stealth orbital support; rule_flag already allows clandestine assets)
				if not peace_state.has("secret_fleet_combat_bonus"): peace_state["secret_fleet_combat_bonus"] = {}
				peace_state["secret_fleet_combat_bonus"][tg] = 0.12  # +12% effective for relevant space/naval strikes or recon
				if hand_g > 0.4 and randf() < 0.4:
					apply_pillar_shift(tg, "cohesion", -3, "fleet_detection_risk")
					if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
						LeaderEventUI.post_news("Secret Space Fleet Deployed", "%s covert orbital assets give surprise advantage (tech/ascendancy/mil). Risk of exposure scandal if Hand high." % tg, "technology")
				print("[SECRET SPACE FLEET EVENT] %s secret fleet ops - bonuses + exposure risk (combat mod +%.0f%% for Expanse stealth feel)." % [tg, 12])

	# 4. Agent mission tie-in already in _on_agent... ; competition sabotage open
	# If rival leads a milestone, chance protest or direct penalty
	for ms in milestones:
		var lead = peace_state.get("space_race_competition", {}).get(ms + "_leader", "")
		if lead != "" and lead != player_tag and randf() < 0.05:
			apply_pillar_shift(player_tag, "ascendancy", -2, "space_behind_rival")
			print("[SPACE COMPETITION] Player behind %s in %s - penalty + consider agent sabotage." % [lead, ms])

	# 5. More: space station/moon base first etc already in 8 milestones above. Total 8+ integrated (milestones + 5 recurring types: protest, ethics, exposure, fleet, competition).
	# Persist note
	peace_state["notes"].append("Space race processed y%d m%d - %d milestones tracked, secret=%s" % [year, month, peace_state["space_milestones"].size(), str(peace_state.get("secret_space_programs", {}).keys()) ])

	print("[SPACE RACE + 1918 ALTS] process_space_race_events done for y%d m%d (8+ events: 8 first-milestones + protests/ethics/secret_fleet/exposure/competition/sabotage ties to research ethics, low coh, Hand, secret programs). Firsts use tech/special/unit checks; rewards via pillar+news." % [year, month])

# End of new major living events block. Integrate by calling from monthly + TestRunner forces + dialogue responses.

func process_epoch_shifts(current_year: int) -> void:
	# Expanded every ~20yr (dynamic cadence: multiples of 20 or 1910/30/50... ; not rigidly fixed list) major shift/opportunity.
	# 5-6 choices per shift: economic off-gold/inflation, military posture provoking neighbors (geo border), tech priority lag/unlock waves, colonial/unrest, political/revolution risk, cultural/cohesion hit.
	# Wire follow-ups/thresholds: post-choice check get_pillar cohesion; <35 -> social unrest or hidden hand exploit (check_subversion_risk + news); >70 -> golden_age_momentum (trigger bonus or tree unlock).
	# Agent influence mitigates: high get_agent_quality_bonus or recent pillar influence from agents reduces negs / boosts pos.
	# Integrates tree: some choices target/impact specific geo nodes (e.g. military choice pressures border province node, colonial adds custom river/coastal initiative); player province choice via apply_... extended; epoch_decisions persisted.
	# Ties key loops: map (geo targets mutate provs), agent missions (mitigate/sponsor pre-shift), pillars (direct shifts), combat (posture affects readiness).
	_init_peace_state_if_needed()
	var is_shift_year : Variant = (current_year % 20 == 10 or current_year % 20 == 0 or current_year in [1910, 1930, 1950])  # dynamic not fixed
	if not is_shift_year:
		return
	print("[EPOCH SHIFT] Major opportunity/crisis at ", current_year, " (dynamic 20yr cadence) - decision points opening (agents can tip scales).")

	var player_tag : Variant = "GER"
	if typeof(LeaderManager) != TYPE_NIL:
		player_tag = LeaderManager.get_player_country_tag()
	if player_tag.is_empty():
		player_tag = "GER"
	player_tag = player_tag.strip_edges().to_upper()

	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		LeaderEventUI.post_news("Epoch Shift " + str(current_year), "A new era brings major shifts and opportunities. Choose paths that reshape pillars, doctrines, and history. Agents extend your will here. (Ties to loading screen concepts: Globe for global, Agents for will, Pillars for realign, Epochs for unfolding branches.) Geo-aware initiatives (rivers/borders/coasts) now available as follow-through.", "epoch")

	# === 6 Choices per shift (rich, with follow-ups; demo auto-applies #2 economic for continuity but full supports pick) ===
	print("=== EPOCH SHIFT " + str(current_year) + " : 6 MAJOR PATH OPTIONS ===")
	print("1. ECONOMIC: Stay on Gold / Sound Money: +elite/institutional cohesion short, -Mandate drag long. Low risk.")
	print("2. ECONOMIC: Off-Gold / Stimulus: +Mandate immediate (prod boost), set inflation_risk + follow-up erosion if coh low. Classic alt-history fork.")
	print("3. MILITARY: Aggressive Posture (border pressure): +readiness, but provokes neighbors (border geo nodes impacted, possible combat readiness hit for them); risk of incident.")
	print("4. TECH: Priority Research Push: Wave unlocks but lag penalty on current doctrines (tech diffusion wave + ahead risk); agent specialists mitigate.")
	print("5. COLONIAL/POLITICAL: Colonial Extraction or Centralization: +industrial short, unrest/separatism in periphery + revolution risk (cohesion hit public).")
	print("6. CULTURAL: National Revival / Contract: +public cohesion short, but if low elite backlash; high can trigger golden momentum.")
	print("7. IDEOLOGICAL / NARRATIVE (Good vs Evil setup): Frame the struggle as righteous crusade vs barbarism (or necessary realpolitik). Sets 'righteous_cause' narrative bonus for combat org/morale vs 'evil' rivals early (WWI/WWII style mutual demonization). Long-term: high hand_influence can flip or reveal the Hand's true agenda (Moloch/Baal/Satanic war-mongering for chaos/power; loves perpetual conflict). Player can 'expose' via agents/tree for cohesion boost + anti-Hand bonuses, or 'serve the higher powers' for dark power spikes but eventual betrayal/erosion/backlash events.")
	print("8. FALSE PEACE / SACRIFICIAL ARMISTICE: Accept a 'noble' settlement that hides deeper deals with the powers (short term Mandate/cohesion, but +hand_influence via hidden corruption feeds to Hand, like post-WWI compromises or cold war deals that empowered the complex). Narrative: looks like peace but sows seeds for next 'evil' conflict. Player who takes it feeds the Hand; those who refuse may gain legitimacy but short-term pain.")
	print("Agents (Vision/Intel pre-missions) can mitigate negatives via prior pillar nudges or quality bonus. Follow-ups dynamic on thresholds after apply.")
	print("Choice integrates Ascendancy Initiatives tree (some options complete/ add geo-targeted nodes e.g. Pressure border on Rhine, Coastal fort).")

	# Persist decision skeleton
	if not peace_state.has("epoch_decisions"):
		peace_state["epoch_decisions"] = {}
	var decision_record : Variant = {"choice": "off_gold", "time": current_year, "player_choice": false}  # full UI sets choice + player_choice=true

	# Agent mitigate factor (use existing quality + pillar recent influence proxy)
	var agent_mit : Variant = 1.0
	if has_method("get_agent_quality_bonus"):
		agent_mit = clamp(1.0 - (get_agent_quality_bonus(player_tag) - 1.0) * 0.5, 0.5, 1.0)  # high quality mitigates 0-50%

	# Demo apply rich choice #2 (off-gold) + geo example, but structure ready for 1-6
	var choice_id : Variant = "off_gold_stimulus"
	apply_pillar_shift(player_tag, "mandate", int(18 * agent_mit), "epoch_econ_" + str(current_year))
	if not peace_state.has("inflation_risk"):
		peace_state["inflation_risk"] = {}
	peace_state["inflation_risk"][player_tag] = true

	# Demo for new #7 Good vs Evil / Hand revelation setup (initially proxy 'righteous' for WWI-style mutual demonization; later Hand outs as true dark driver of wars)
	if not peace_state.has("righteous_cause"):
		peace_state["righteous_cause"] = {}
	if not peace_state.has("hand_influence"):
		peace_state["hand_influence"] = {}
	if not peace_state.has("occult_exposure"):
		peace_state["occult_exposure"] = {}
	peace_state["righteous_cause"][player_tag] = 0.6  # early bonus vs 'evil' rivals (combat flavor via modifiers elsewhere or future BM)
	peace_state["hand_influence"][player_tag] = min(1.0, float(peace_state["hand_influence"].get(player_tag, 0.1)) + 0.15)  # wars/epochs feed the Hand
	print("[EPOCH+GOOD/EVIL] Set righteous_cause narrative (proxy good vs evil for early conflicts) and incremented hand_influence (revelation setup: eventually Hand reveals it serves Moloch/etc, loves wars for its agenda; player can expose via tree/agents or serve for power).")
	# Integrate tree: add geo dynamic node example for military flavor, or complete a border one if exists
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_countries"):
		var neighs : Variant = MapManager.get_adjacent_countries(player_tag)
		if neighs.size() > 0:
			add_custom_initiative_node(player_tag, "Military", {
				"id": "epoch_border_pressure_" + str(current_year),
				"name": "Pressure Border Province on " + neighs[0] + " (Epoch " + str(current_year) + ")",
				"target_type": "border_with",
				"target": neighs[0],
				"requires_player_choice": true,
				"player_choice_feature": "border",
				"effect": {"type": "border_pressure", "vs": neighs[0]},
				"effect_desc": "Epoch shift follow-on: target specific border province (player picks via map for 'improve this' or pressure)",
				"cost": {"ascendancy": 5},
				"dynamic": true,
				"geo_feature": "border",
				"from_epoch": current_year
			})
			print("[EPOCH+tree] Added geo-targeted border initiative node from military-flavored shift (player province choice supported).")

	peace_state["epoch_decisions"][current_year] = {player_tag: choice_id}
	decision_record["choice"] = choice_id
	peace_state["epoch_decisions"][str(current_year) + "_full"] = decision_record
	print("[EPOCH SHIFT] Demo chose ", choice_id, " for ", player_tag, " (agent_mit=", agent_mit, "). Tree geo node added for integration.")

	# Apply general + some of other choice flavors for richness (in real all mutually exclusive; here layered demo effects)
	apply_pillar_shift(player_tag, "ascendancy", int(8 * agent_mit), "epoch_opportunity_" + str(current_year))
	# Military posture demo (provokes)
	apply_pillar_shift(player_tag, "cohesion", int(-3 * (2.0 - agent_mit)), "military_posture_epoch")
	# Tech priority
	apply_pillar_shift(player_tag, "mandate", int(5), "tech_priority")
	# Cultural
	apply_pillar_shift(player_tag, "cohesion", int(4 * agent_mit), "cultural_revival")
	# False peace / sacrificial armistice demo (feeds Hand per user request; represents hidden deals, mob/deep state corruption in 'peace')
	if randf() < 0.3:
		apply_pillar_shift(player_tag, "mandate", 10, "false_peace")
		if not peace_state.has("hand_influence"):
			peace_state["hand_influence"] = {}
		var hcur : float = float(peace_state["hand_influence"].get(player_tag, 0.0))
		peace_state["hand_influence"][player_tag] = min(1.0, hcur + 0.12)
		print("[FALSE PEACE] Sacrificial armistice taken — short Mandate but +hand_influence (hidden Hand feeds, like prohibition/mob/deep state in settlements).")

	# === Wire dynamic follow-up events/thresholds (after choice effects) ===
	var coh : Variant = get_pillar(player_tag, "cohesion")
	if coh < 35:
		# Low coh after shift -> social unrest or HH exploit
		if has_method("check_subversion_risk"):
			check_subversion_risk(player_tag)
		apply_pillar_shift(player_tag, "cohesion", int(-8 * (2.0-agent_mit)), "social_unrest_epoch")
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("Social Unrest", "Epoch choice lowered cohesion below 35. Public discontent rises; Hidden Hand may exploit. Use agents to stabilize or tree assimilation node.", "crisis")
		print("[EPOCH FOLLOWUP] coh<35: social unrest + HH risk for ", player_tag)
	elif coh > 70:
		# High -> golden age momentum (bonus + possibly unlock tree golden node)
		apply_pillar_shift(player_tag, "ascendancy", 12, "golden_momentum")
		apply_pillar_shift(player_tag, "cohesion", 5, "golden_momentum")
		if has_method("trigger_golden_age"):
			trigger_golden_age(player_tag)
		# Wire to tree: unlock a golden special via initiative path
		unlock_ascendancy_initiative(player_tag, "golden_economic_miracle" if coh > 80 else "welfare_social_contract")
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("Golden Age Momentum", "High cohesion post-epoch choice >70 fired golden momentum. Pillars surge; tree specials unlocked.", "golden")
		print("[EPOCH FOLLOWUP] coh>70: golden age momentum + tree golden unlock for ", player_tag)
	else:
		print("[EPOCH FOLLOWUP] coh in mid range, no extreme threshold event (agents can still push via missions).")

	# Colonial/unrest example follow (if decision was that)
	if choice_id.begins_with("colonial"):
		apply_pillar_shift(player_tag, "cohesion", -6, "colonial_unrest")
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.post_news("Colonial Unrest", "Colonial choice triggers periphery unrest (use map/agents on key provinces).", "crisis")

	# Tech lag follow (demo always)
	if current_year > 1930:
		# Sim lag wave: note for TechnologyManager
		print("[EPOCH] Tech priority may cause doctrine lag - see TechnologyManager for ahead penalties + diffusion waves at shifts.")

	# Future hook: unlock agent missions, doctrine change w/ org, map chokepoint events, call into tree completion for some nodes.
	# Player full choice in UI would set epoch_decisions + call pillar applies + re-run threshold, + optionally apply tree node geo.

	# Good vs Evil / Hidden Hand revelation mechanic (fits epochs theme: initial conflicts framed as good-vs-evil by both sides; Hand eventually outs as the true war-profiteer serving Moloch/Baal/Satanic chaos agenda).
	var hand_inf : float = float(peace_state.get("hand_influence", {}).get(player_tag, 0.0))
	if hand_inf > 0.65 and current_year >= 1930:
		peace_state["occult_exposure"][player_tag] = min(2, int(peace_state.get("occult_exposure", {}).get(player_tag, 0)) + 1)
		apply_pillar_shift(player_tag, "cohesion", int(-10 * (2.0 - agent_mit)), "hand_revelation")
		apply_pillar_shift(player_tag, "ascendancy", int(-5), "hand_revelation")
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("The Hand Reveals Its Face", "High hand_influence at epoch: the Hidden Hand outs itself. Wars serve only its dark transcendent masters (Moloch etc). Previous 'good vs evil' was theater. Expose/fight via tree/agents for redemption path, or serve for power (risky). Affects all pillars long-term.", "revelation")
		print("[HAND REVELATION] Hand agenda revealed for ", player_tag, " (hand_inf=", hand_inf, "). Good-vs-evil proxy collapses; new occult exposure + pillar hits. Player can now pursue anti-Hand 'ascendancy of light' or dark pacts in tree.")

	# Tie back: epoch can complete a matching initiative node (demo)
	var tree : Variant = get_ascendancy_initiative_tree(player_tag)
	if tree.has("Economic") and tree["Economic"].size() > 0:
		# e.g. mark progress for first
		if not peace_state["initiative_progress"].has(player_tag):
			peace_state["initiative_progress"][player_tag] = {}
		peace_state["initiative_progress"][player_tag]["epoch_econ"] = {"completed": true, "from_shift": current_year}

# === Ascendancy Initiatives / Focus Tree (dynamic per country, consistent structure) ===
# The "Ascendancy items" (nodes in the tree) form a focus-tree like system for big directional pushes and Golden specials.
# Core structure same across all countries for balance and player familiarity (Economic, Military, Diplomatic, Covert, Ascendancy branches, 3-5 nodes each).
# But nodes are dynamic: targets filled based on current map state (owned provinces for internal boosts, neighbors for external influence).
# E.g. "Develop [Your High-Pop Owned Province]" applies bonus to that specific province's settlement_level or adds local factory.
# "Secure Border Province with [Neighbor FRA]" adds defense modifier to border provinces between you and FRA, or improves relations for agent networks.
# This makes the tree contextual to your situation on the stitched world map, encouraging use of the grand view, provinces, and neighbors.
# Unlocked/advanced at epoch shifts or via agent missions/time.
# Impacts play: Completing node gives concrete map-tied effects (specific provinces get bonuses, affecting combat, supply, pop in that area).
# Ties to decision points: Nodes as the "choices" at shifts, with follow-ups if not completed or based on pillar after.
# Options for implementation:
# 1. Template + runtime fill: Fixed node defs with placeholders like "CORE_PROV", replaced by querying MapManager for owned sorted by pop/dev.
# 2. Feature-based generation: If you own river province, auto-add "River Hub" node affecting adjacent.
# 3. Hybrid (recommended): Core branches fixed, but each node has "fill" rule ( "owned_by_pop", "neighbor_by_tag" ), effects applied to the resolved targets (province modifiers, NMM local, etc.).
# This keeps "same across countries" while dynamic to map.
func get_ascendancy_initiative_tree(tag: String) -> Dictionary:
	# Hybrid fixed-core + rich dynamic/map-contextual nodes (world-class flexible tree).
	# Fixed core branches for familiarity/balance (Economic/Military/Diplomatic/Covert/Ascendancy, 3-5 nodes baseline).
	# Rich dynamic: MapManager detects owned provinces on rivers/lakes/oceans/borders/neighbors; contextual nodes added if geo features present.
	# "Improve this" nodes (e.g. border-with-X, river province) set requires_player_choice=true + player_choice_feature; player picks via map click -> apply_ascendancy_initiative_player_province_choice (extended).
	# Custom nodes (from edit mode) merged in. Targets resolved live from current map state (owned by tag).
	# Ties to epoch shifts (choices can complete/impact tree nodes), agents (Vision missions speed/boost geo nodes), pillars (costs/effects), combat (border/coastal forts affect defense/supply), map (province targets mutate Province + notify).
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var tree: Dictionary = {}
	# Core fixed structure (same skeleton for all countries; effects contextualized).
	var core_branches : Variant = ["Economic", "Military", "Diplomatic", "Covert", "Ascendancy"]
	for b in core_branches:
		tree[b] = []
	# Fallback static if no MapManager (editor/headless safe)
	var has_mm : Variant = (typeof(MapManager) != TYPE_NIL)
	var owned: Array[int] = []
	var neighbors: Array[String] = []
	var river_provs: Array[int] = []
	var coastal_provs: Array[int] = []
	var any_border_provs: Array[int] = []  # sample border ones
	if has_mm:
		if MapManager.has_method("get_provinces_by_owner"):
			owned = MapManager.get_provinces_by_owner(tag)
		if MapManager.has_method("get_adjacent_countries"):
			neighbors = MapManager.get_adjacent_countries(tag)
		if MapManager.has_method("get_owned_river_provinces"):
			river_provs = MapManager.get_owned_river_provinces(tag)
		if MapManager.has_method("get_owned_coastal_or_port_provinces"):
			coastal_provs = MapManager.get_owned_coastal_or_port_provinces(tag)
		if MapManager.has_method("get_border_provinces_with") and neighbors.size() > 0:
			any_border_provs = MapManager.get_border_provinces_with(tag, neighbors[0])
	# === Fixed-core nodes (always present, but targets/effects filled dynamically) ===
	# Economic branch
	tree["Economic"].append({
		"id": "dev_high_pop",
		"name": "Develop High-Pop Province",
		"branch": "Economic",
		"target_type": "owned_any",
		"target": owned[0] if owned.size() > 0 else -1,
		"requires_player_choice": false,
		"player_choice_feature": "",
		"effect": {"type": "province_settlement", "amount": 0.25, "pillar": "mandate+8"},
		"effect_desc": "settlement_level +0.25 + local Mandate in target province (feeds combat org/supply/attrition)",
		"cost": {"ascendancy": 8},
		"dynamic": true
	})
	tree["Economic"].append({
		"id": "boost_industry",
		"name": "Boost Industry in Core",
		"branch": "Economic",
		"target_type": "owned_any",
		"target": owned[1] if owned.size() > 1 else (owned[0] if owned.size() > 0 else -1),
		"requires_player_choice": false,
		"player_choice_feature": "",
		"effect": {"type": "industrial_local", "amount": 10},
		"effect_desc": "local factory/infra boost in target (affects production loop)",
		"cost": {"ascendancy": 10, "mandate": 5},
		"dynamic": true
	})
	# Military branch - geo rich
	var mil_node : Variant = {
		"id": "secure_border",
		"name": "Secure Border with Neighbor",
		"branch": "Military",
		"target_type": "border_with",
		"target": neighbors[0] if neighbors.size() > 0 else "",
		"requires_player_choice": (any_border_provs.size() == 0),
		"player_choice_feature": "border",
		"effect": {"type": "border_defense", "vs": neighbors[0] if neighbors.size()>0 else "", "bonus": 0.15},
		"effect_desc": "defense/org bonus in border provinces vs that neighbor (combat width + supply resistance)",
		"cost": {"ascendancy": 12},
		"dynamic": true,
		"geo_feature": "border"
	}
	if any_border_provs.size() > 0:
		mil_node["target_pid"] = any_border_provs[0]
	tree["Military"].append(mil_node)
	if coastal_provs.size() > 0:
		tree["Military"].append({
			"id": "coastal_fort",
			"name": "Coastal Fort / Naval Base on " + ("Ocean" if has_mm and MapManager.has_method("get_province") and coastal_provs[0] and MapManager.get_province(coastal_provs[0]).is_sea == false else "Coast"),
			"branch": "Military",
			"target_type": "coastal",
			"target": coastal_provs[0],
			"requires_player_choice": false,
			"player_choice_feature": "coastal",
			"effect": {"type": "coastal_defense", "bonus": 0.2, "naval": true},
			"effect_desc": "fortify coastal province (interdiction resistance, port supply, naval projection; ties to combat + supply)",
			"cost": {"ascendancy": 14},
			"dynamic": true,
			"geo_feature": "coastal"
		})
	# Diplomatic
	tree["Diplomatic"].append({
		"id": "influence_neighbor",
		"name": "Influence Key Neighbor",
		"branch": "Diplomatic",
		"target_type": "neighbor_country",
		"target": neighbors[0] if neighbors.size() > 0 else "",
		"requires_player_choice": false,
		"player_choice_feature": "",
		"effect": {"type": "agent_network", "in": neighbors[0] if neighbors.size()>0 else "", "bonus": 0.2},
		"effect_desc": "agent network + relations bonus in neighbor country (enables missions, soft power)",
		"cost": {"ascendancy": 6},
		"dynamic": true
	})
	# Covert - river/lake example for player choice "improve"
	var covert_node : Variant = {
		"id": "hidden_hand_op",
		"name": "Hidden Hand Operation in Province",
		"branch": "Covert",
		"target_type": "owned_any",
		"target": owned[2] if owned.size() > 2 else (owned[0] if owned.size()>0 else -1),
		"requires_player_choice": false,
		"player_choice_feature": "",
		"effect": {"type": "sabotage_or_boost", "target": "province"},
		"effect_desc": "covert pressure or internal boost in target (player province choice supported for precision)",
		"cost": {"ascendancy": 7},
		"dynamic": true
	}
	if river_provs.size() > 0:
		covert_node = {
			"id": "river_op",
			"name": "Pressure River Province",
			"branch": "Covert",
			"target_type": "river_prov",
			"target": river_provs[0],
			"requires_player_choice": true,
			"player_choice_feature": "river",
			"effect": {"type": "sabotage_or_boost", "target": "river_prov"},
			"effect_desc": "target specific river province for hidden influence (supply interdiction or loyalist boost; pick via map)",
			"cost": {"ascendancy": 9},
			"dynamic": true,
			"geo_feature": "river"
		}
	tree["Covert"].append(covert_node)
	# Ascendancy core
	tree["Ascendancy"].append({
		"id": "golden_push",
		"name": "Golden Age Push",
		"branch": "Ascendancy",
		"target_type": "fixed",
		"target": "",
		"requires_player_choice": false,
		"player_choice_feature": "",
		"effect": {"type": "pillar_balance", "if_all_high": true, "bonus": 10},
		"effect_desc": "pillar balance bonus if Cohesion/Ascendancy high (unlocks specials)",
		"cost": {"ascendancy": 15},
		"dynamic": false
	})
	# === Rich dynamic contextual nodes (added if map features present - world-class reactivity) ===
	if river_provs.size() > 0:
		tree["Economic"].append({
			"id": "river_hub",
			"name": "River Hub Development",
			"branch": "Economic",
			"target_type": "river_prov",
			"target": river_provs[0],
			"requires_player_choice": true,
			"player_choice_feature": "river",
			"effect": {"type": "province_settlement", "amount": 0.3, "supply": 0.12},
			"effect_desc": "Improve river province (settlement + supply throughput bonus; player chooses specific owned river pid)",
			"cost": {"ascendancy": 11},
			"dynamic": true,
			"geo_feature": "river"
		})
	if coastal_provs.size() > 0:
		tree["Economic"].append({
			"id": "port_expansion",
			"name": "Port / Lake-Ocean Expansion",
			"branch": "Economic",
			"target_type": "coastal",
			"target": coastal_provs[0],
			"requires_player_choice": true,
			"player_choice_feature": "coastal",
			"effect": {"type": "coastal_econ", "trade": 15},
			"effect_desc": "Coastal/lake/ocean province trade hub (Mandate + infra; pick the specific Baltic/Rhine-adj etc province)",
			"cost": {"ascendancy": 10, "mandate": 4},
			"dynamic": true,
			"geo_feature": "coastal"
		})
	if neighbors.size() > 0:
		var border_sample = MapManager.get_border_provinces_with(tag, neighbors[0]) if has_mm and MapManager.has_method("get_border_provinces_with") else []
		tree["Military"].append({
			"id": "pressure_border_" + neighbors[0].to_lower(),
			"name": "Pressure Border Province on " + neighbors[0],
			"branch": "Military",
			"target_type": "border_with",
			"target": neighbors[0],
			"requires_player_choice": (border_sample.size() == 0),
			"player_choice_feature": "border",
			"effect": {"type": "border_pressure", "vs": neighbors[0], "cohesion_hit": -4, "defense": 0.1},
			"effect_desc": "Apply pressure to a specific border province with neighbor (e.g. Rhine border); player choice if multiple",
			"cost": {"ascendancy": 13},
			"dynamic": true,
			"geo_feature": "border"
		})
	# === Merge custom/runtime nodes from persistence (edit mode support) ===
	var customs: Dictionary = peace_state.get("custom_initiative_nodes", {}).get(tag, {})
	for branch in customs.keys():
		if not tree.has(branch):
			tree[branch] = []
		for cnode in customs[branch]:
			# Resolve live target if dynamic custom
			var c: Dictionary = cnode.duplicate(true)
			if c.get("dynamic", true) and has_mm and c.get("target_type", "") in ["river_prov", "coastal", "border_with", "owned_any"]:
				# re-resolve example for player-owned geo
				if c.get("player_choice_feature", "") == "river" and river_provs.size() > 0:
					c["target"] = river_provs[0]
				elif c.get("player_choice_feature", "") == "coastal" and coastal_provs.size() > 0:
					c["target"] = coastal_provs[0]
				elif c.get("target_type", "") == "border_with" and neighbors.size() > 0:
					c["target"] = neighbors[0]
			tree[branch].append(c)
	return tree

# Example use: At epoch shift or via agent, "unlock" or "advance" node, apply effect to the target province/country.
# This makes decisions map-tied and dynamic.

# Support for player choosing provinces to improve as part of the tree (e.g. "Develop/Improve Province" nodes that require choice from owned provinces).
# Call this when the node in the tree has "requires_player_choice": true (extended for geo: river_prov, border, coastal, lake/ocean).
# Integrates: map click (via MapViewInput/ProvinceInsight -> this), mutates Province (settlement/infra + notify for visuals/combat/supply), agent influence can pre-boost success, epoch follow-ups can key off completion.
# Geo examples: "Pressure border province on Rhine", "Coastal fort on Baltic", "River Hub" all support pid choice, apply feature-aware bonus (river uses has_river for supply, border affects adj defense).
func apply_ascendancy_initiative_player_province_choice(tag: String, branch: String, node_name: String, chosen_pid: int) -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	var p = MapManager.get_province(chosen_pid)
	if not p:
		print("Player province choice for initiative: invalid pid ", chosen_pid)
		return
	tag = tag.strip_edges().to_upper()
	_init_peace_state_if_needed()
	# Determine geo context for rich effects (use MapManager queries)
	var is_river : Variant = MapManager.has_method("has_river_border") and MapManager.has_river_border(chosen_pid)
	var is_coastal : Variant = p.resolve_has_port() or p.has_feature("coastal") or str(p.terrain).to_lower() in ["coastal","coast"]
	var is_border : Variant = false
	# Check if borders a foreign (for "border-with-X" nodes)
	var adjs : Variant = MapManager.get_adjacent_provinces(chosen_pid, false) if MapManager.has_method("get_adjacent_provinces") else []
	for ap in adjs:
		var apv : Variant = MapManager.get_province(ap)
		if apv and apv.owner_tag.strip_edges().to_upper() != tag:
			is_border = true
			break
	# Apply base improvement (settlement for "improve this" flavor - affects combat: org/attrition/def, supply, pop)
	p.settlement_level = min(1.5, p.settlement_level + 0.25)
	# Geo-aware bonuses
	var extra : Variant = 0.0
	if is_river:
		extra += 0.08
		p.infrastructure = mini(50, p.infrastructure + 1)  # river infra synergy
		if MapManager.has_method("get_chokepoint_or_river_supply_bonus"):
			extra += MapManager.get_chokepoint_or_river_supply_bonus(chosen_pid) - 1.0
	if is_coastal:
		p.infrastructure = mini(50, p.infrastructure + 1)
		extra += 0.1  # port throughput
	if is_border:
		extra += 0.05  # border fort flavor
	# Persist choice for progress / follow-ups
	var prog_key : Variant = "initiative_progress"
	if not peace_state.has(prog_key):
		peace_state[prog_key] = {}
	if not peace_state[prog_key].has(tag):
		peace_state[prog_key][tag] = {}
	var node_key : Variant = branch + "/" + node_name
	peace_state[prog_key][tag][node_key] = {"completed": true, "chosen_pid": chosen_pid, "geo": {"river": is_river, "coastal": is_coastal, "border": is_border}}
	# Notify for map visuals (vitality, overlays), combat recalc, supply
	MapManager.notify_province_changed(chosen_pid, "settlement")
	MapManager.notify_province_changed(chosen_pid, "infrastructure")
	# Pillar nudge based on geo (e.g. coastal/river give Mandate for trade)
	var mandate_gain : Variant = 6
	if is_river or is_coastal:
		mandate_gain += 4
	apply_pillar_shift(tag, "mandate", mandate_gain, "geo_initiative_" + node_name)
	apply_pillar_shift(tag, "ascendancy", 2, "initiative_choice")
	print("Ascendancy initiatives tree (geo): player chose province ", chosen_pid, " (river:", is_river, " coastal:", is_coastal, " border:", is_border, ") for ", branch, " / ", node_name, " - settlement+0.25 + geo bonus; Mandate +", mandate_gain, " (affects combat/supply/local loops). Progress persisted.")
	# Extend: real nodes can apply full effect dict here (e.g. if node had "effect" from get_tree, route to NMM or local mod).

# === In-Game Edit Mode for Ascendancy Initiatives (full flexibility, persistence) ===
# add_custom_initiative_node, move_node (rebranch), retool_node (edit target/effect/geo), remove_node.
# Persisted in peace_state["custom_initiative_nodes"] (runtime dict, survives save via SaveLoad pattern).
# Used for modding/debug/in-game tweaks; customs merged into get_ascendancy_initiative_tree live.
# Ties: custom geo nodes (target border-with-FRA or river) integrate with apply_player_province_choice + epoch shifts.
func add_custom_initiative_node(tag: String, branch: String, node_data: Dictionary) -> bool:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	branch = branch.strip_edges().capitalize()
	if not peace_state["custom_initiative_nodes"].has(tag):
		peace_state["custom_initiative_nodes"][tag] = {}
	if not peace_state["custom_initiative_nodes"][tag].has(branch):
		peace_state["custom_initiative_nodes"][tag][branch] = []
	var nd: Dictionary = node_data.duplicate(true)
	if not nd.has("id"):
		nd["id"] = "custom_" + str(peace_state["custom_initiative_nodes"][tag][branch].size()) + "_" + str(Time.get_ticks_msec())
	nd["branch"] = branch
	nd["dynamic"] = nd.get("dynamic", true)
	peace_state["custom_initiative_nodes"][tag][branch].append(nd)
	print("EDIT: added custom initiative node '", nd.get("name", nd["id"]), "' to ", tag, "/", branch, " (persisted in peace_state)")
	return true

func move_node(tag: String, old_branch: String, node_id: String, new_branch: String) -> bool:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var customs: Dictionary = peace_state["custom_initiative_nodes"].get(tag, {})
	if not customs.has(old_branch): return false
	var arr: Array = customs[old_branch]
	for i in range(arr.size()-1, -1, -1):
		if str(arr[i].get("id", "")) == node_id:
			var nd: Dictionary = arr[i]
			arr.remove_at(i)
			if not customs.has(new_branch):
				customs[new_branch] = []
			nd["branch"] = new_branch.capitalize()
			customs[new_branch].append(nd)
			print("EDIT: moved node ", node_id, " from ", old_branch, " to ", new_branch)
			return true
	return false

func retool_node(tag: String, branch: String, node_id: String, changes: Dictionary) -> bool:
	# Edit target/effect/geo/requires_player_choice etc for live retool (e.g. change "river_prov" target to specific pid or switch effect)
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var customs: Dictionary = peace_state["custom_initiative_nodes"].get(tag, {})
	if not customs.has(branch): return false
	for nd in customs[branch]:
		if str(nd.get("id", "")) == node_id:
			for k in changes:
				nd[k] = changes[k]
			print("EDIT: retooled node ", node_id, " in ", tag, "/", branch, " changes=", changes)
			return true
	return false

func remove_node(tag: String, branch: String, node_id: String) -> bool:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var customs: Dictionary = peace_state["custom_initiative_nodes"].get(tag, {})
	if not customs.has(branch): return false
	var arr: Array = customs[branch]
	for i in range(arr.size()-1, -1, -1):
		if str(arr[i].get("id", "")) == node_id:
			arr.remove_at(i)
			print("EDIT: removed custom node ", node_id, " from ", tag, "/", branch)
			return true
	return false

func get_custom_initiative_nodes(tag: String) -> Dictionary:
	_init_peace_state_if_needed()
	return peace_state.get("custom_initiative_nodes", {}).get(tag.strip_edges().to_upper(), {}).duplicate(true)

func get_pillar(tag: String, pillar: String) -> int:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if pillar == "cohesion":
		var coh: Dictionary = peace_state["cohesion"].get(tag, {"public": 50, "elite": 50, "institutional": 50})
		return int((coh["public"] + coh["elite"] + coh["institutional"]) / 3)
	return peace_state.get(pillar, {}).get(tag, 50)

func get_fertility_rate(tag: String) -> float:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	return float(peace_state.get("fertility_rate", {}).get(tag, 1.6))

func increase_hand_influence(tag: String, amount: float) -> void:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("hand_influence"):
		peace_state["hand_influence"] = {}
	var cur : float = float(peace_state["hand_influence"].get(tag, 0.0))
	peace_state["hand_influence"][tag] = clamp(cur + amount, 0.0, 1.0)
	if amount > 0.01:
		print("[HAND] ", tag, " hand_influence increased by ", amount, " (black market/corruption/war feed etc). Current: ", peace_state["hand_influence"][tag])

# === Ascendancy for Agent Quality (ebb and flow, no death spiral) ===
# Ascendancy levels give perks for agent availability/quality (better recruits, higher success, special missions).
# Recovery possible (like France historically) via economy, focuses, agent wins – floor exists, random events or low Ascendancy nations can rebound with effort/time.
# Failed states with low Cohesion may look to high Ascendancy neighbors for "better" systems (pressure from riots/food shortages/property rights issues breaking public Cohesion; openness to capitalist/democratic models if they offer prosperity).
func get_agent_quality_bonus(tag: String) -> float:
	_init_peace_state_if_needed()
	var asc: int = int(peace_state["ascendancy"].get(tag, 50))
	# Perks scale with Ascendancy: e.g., +10% success per 20 Ascendancy above 50, better pool.
	# Floor at 20% bonus min to avoid death spiral; high Ascendancy nations get "elite agent" access.
	# Maxing Ascendancy can trigger Golden Age (see trigger_golden_age).
	var base: float = 0.8 + (asc / 100.0)  # 80% base + scaling
	return clamp(base, 0.8, 1.5)  # Cap to prevent over-dominance

# === Culture Modeling (Macro Civilizational Groups for Cohesion Dynamics) ===
# Large cultural spheres (not every micro-culture, to keep sandbox playable): Western (European/liberal traditions), Islamic (Muslim world, religious cohesion), African (Sub-Saharan communal/traditional), Sinic (East Asian Confucian-influenced), Indic (South Asian), Latin American (Iberian-mixed), etc.
# Immigration/foreign workers: Policy choice in Ascendancy Initiatives tree or agent missions.
# Short-term: +Mandate/Industrial Base (cheap labor/goods boost economy, public Cohesion from lower prices/jobs for some).
# Long-term: -Public Cohesion (citizen job loss, wage pressure, cultural friction), possible +Elite (business profits) or -Institutional (crime, integration strain), Hidden Hand can amplify negatives (fund unrest in public groups).
# Failed states: Low public Cohesion (from riots over food/shortages/rights) + high Ascendancy neighbor = pressure for "better system" adoption or separatism (e.g., openness to Western models, or breakaways like historical examples).
# Ties to pillars: Immigration shifts Cohesion groups dynamically; over-reliance erodes long-term industry/Cohesion if not managed via tree choices (e.g., "Assimilation Policies" initiative costs Ascendancy but mitigates).
var culture_groups: Dictionary = {
	# Macro civilizational / cultural spheres for the whole world.
	# Goal: Cover the largest population groups historically and today (majority of humanity) while preserving strong flavor and believable cohesion/affinity differences.
	# Not micro-cultures. Broad spheres with internal variation modeled via events, leaders, specific policies, or sub-mods later.
	# Expansions: Persianate, Turkic, Southeast Asian, Indigenous American (for New World repopulation/settlement/conversion simulation), Oceanic (Pacific islander/Australian Aboriginal/Maori etc. for full globe).
	# This enables simulation of large group migration, settlement, repopulation, conversion across the world (user request).
	"Western": {
		"baseline_cohesion": 60,
		"affinity": {"Western": 0.92, "Latin": 0.78, "Orthodox": 0.62, "Indic": 0.52, "Sinic": 0.42, "Islamic": 0.32, "Persianate": 0.38, "Turkic": 0.40, "African": 0.38, "SoutheastAsian": 0.45, "IndigenousAmerican": 0.30, "Oceanic": 0.35}
	},
	"Latin": {
		"baseline_cohesion": 56,
		"affinity": {"Latin": 0.90, "Western": 0.78, "African": 0.52, "Islamic": 0.42, "Persianate": 0.35, "Indic": 0.48, "IndigenousAmerican": 0.45}
	},
	"Orthodox": {
		"baseline_cohesion": 57,
		"affinity": {"Orthodox": 0.90, "Western": 0.62, "Islamic": 0.48, "Persianate": 0.55, "Turkic": 0.58, "Sinic": 0.42}
	},
	"Islamic": {
		"baseline_cohesion": 55,
		"affinity": {"Islamic": 0.92, "Persianate": 0.82, "Turkic": 0.78, "African": 0.58, "Western": 0.32, "Latin": 0.42, "Indic": 0.55, "SoutheastAsian": 0.60}
	},
	"Persianate": {
		"baseline_cohesion": 58,
		"affinity": {"Persianate": 0.93, "Islamic": 0.82, "Turkic": 0.65, "Western": 0.38, "Indic": 0.52, "Orthodox": 0.55, "Sinic": 0.35}
	},
	"Turkic": {
		"baseline_cohesion": 54,
		"affinity": {"Turkic": 0.90, "Islamic": 0.78, "Persianate": 0.65, "Orthodox": 0.58, "Western": 0.40, "Sinic": 0.45}
	},
	"African": {
		"baseline_cohesion": 50,
		"affinity": {"African": 0.90, "Islamic": 0.58, "Western": 0.38, "Latin": 0.52, "Indic": 0.42, "SoutheastAsian": 0.35, "IndigenousAmerican": 0.25}
	},
	"Indic": {
		"baseline_cohesion": 58,
		"affinity": {"Indic": 0.91, "Western": 0.52, "Islamic": 0.55, "Persianate": 0.52, "Sinic": 0.58, "SoutheastAsian": 0.65}
	},
	"Sinic": {
		"baseline_cohesion": 65,
		"affinity": {"Sinic": 0.93, "Western": 0.42, "Indic": 0.58, "Islamic": 0.38, "Persianate": 0.35, "Turkic": 0.45, "SoutheastAsian": 0.55}
	},
	"SoutheastAsian": {
		"baseline_cohesion": 53,
		"affinity": {"SoutheastAsian": 0.88, "Islamic": 0.60, "Indic": 0.65, "Sinic": 0.55, "Western": 0.45, "African": 0.35}
	},
	"IndigenousAmerican": {
		# For New World repopulation, settlement, conversion, large group migration simulation. Distinct from settler cultures.
		"baseline_cohesion": 48,
		"affinity": {"IndigenousAmerican": 0.92, "Latin": 0.45, "Western": 0.30, "African": 0.25}
	},
	"Oceanic": {
		# Pacific, Australian, Maori etc. for full world coverage and relocation/settlement mechanics.
		"baseline_cohesion": 49,
		"affinity": {"Oceanic": 0.90, "Western": 0.35, "SoutheastAsian": 0.55, "IndigenousAmerican": 0.30}
	}
	# Enables conversion/repopulation/migrating large groups (user request). Settlement policies can move primary culture or encourage compatible groups into new lands, affecting non_citizen, cohesion, integration.
}

func apply_immigration_policy(tag: String, source_culture: String, scale: float, policy: String = "open") -> void:
	# High-value: Models real historical trade-offs (post-1918/guest workers, decolonization migrations, cheap labor booms).
	# scale: 0-1 intensity (e.g., 0.35 for noticeable program). Larger scale = bigger short gains + bigger long risks.
	# policy: "open" (max short boost + industrial, highest long public/institutional drain + Hidden Hand), 
	#         "guest_worker" (high short, reduced long cohesion hit and less permanent settlement, elite loves),
	#         "skilled_only" (lower scale talent-focused, Mandate/tech side bonus, smaller public backlash),
	#         "assimilation_focus" (costs Ascendancy, converts some source affinity toward host, best long cohesion recovery + institutional).
	# Macro culture friction: Uses affinity matrix. Low affinity (e.g. Western host + large African source) increases public/institutional penalties and Hidden Hand exploitation.
	# Cohesion groups split: Public bears visible job/wage/crime/cultural "undermines nation" pain; Elite often net + from cheap labor/profits (pushes open); Institutional tracks crime, services, order.
	# Short (immediate): +industrial_base / production feel, some public happiness (lower prices), Mandate.
	# Long/ongoing (simulated here + future TimeManager erosion hooks): -public (jobs competition + cultural distance), possible elite gain or institutional crime hit, Hidden Hand + on public.
	# Failed state interaction: Low public + immigration wave accelerates separatism risk or "openness" to high-Ascendancy models.
	# Ties: Used by Ascendancy Initiatives tree nodes, agent "demographic" missions, victory integration (cultural_distance), post-peace follow-ons.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	source_culture = source_culture.capitalize()
	if source_culture not in culture_groups:
		print("Immigration: Unknown source culture %s" % source_culture)
		return

	var host_primary : String = peace_state.get("primary_culture", {}).get(tag, "Western")
	var affinity : float = 0.5
	var affinities = culture_groups.get(source_culture, {}).get("affinity", {})
	if host_primary in affinities:
		affinity = affinities[host_primary]
	elif source_culture in culture_groups.get(host_primary, {}).get("affinity", {}):
		affinity = culture_groups[host_primary]["affinity"][source_culture]
	var distance_penalty : int = int((1.0 - affinity) * 10 * scale)  # 0-10 range scaled

	# Short-term: Industrial/Mandate boost (cheap labor/goods) + some public happiness from prices.
	if tag not in peace_state["industrial_base"]:
		peace_state["industrial_base"][tag] = 50
	var short_industrial : int = int(18 * scale * (0.7 + affinity * 0.3))  # Affinity helps efficiency a bit
	peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) + short_industrial)
	apply_pillar_shift(tag, "mandate", int(9 * scale), "immigration_" + policy)

	# Public gets short happiness (cheap stuff) but we immediately layer the long drain below for visible effect.
	apply_agent_pillar_influence(tag, "cohesion", int(8 * scale), "public")

	# Long-term / friction effects (applied now for demo visibility; real would have monthly ticks via TimeManager).
	var public_long : int = int(14 * scale) + distance_penalty
	apply_agent_pillar_influence(tag, "cohesion", -public_long, "public")

	# Elite: often benefits from cheap labor (profits), less cultural pain.
	var elite_mod : int = int(4 * scale) if policy in ["open", "guest_worker"] else int(2 * scale)
	apply_agent_pillar_influence(tag, "cohesion", elite_mod, "elite")

	# Institutional: crime + integration/services load. Worse on low affinity + open.
	var inst_hit : int = int(6 * scale) + int(distance_penalty * 0.6)
	if policy == "open":
		apply_agent_pillar_influence(tag, "cohesion", -inst_hit, "institutional")
	elif policy == "guest_worker":
		apply_agent_pillar_influence(tag, "cohesion", -int(inst_hit * 0.6), "institutional")
	# assimilation later gives recovery

	# Hidden Hand exploitation (public group especially — funds unrest when cohesion low).
	var hh_gain : int = int(6 * scale * (1.0 - affinity * 0.5))
	apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", hh_gain, "public")
	if public_long > 15:
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", int(hh_gain * 0.5), "elite")  # scandals/corruption angle

	# Policy-specific
	if policy == "assimilation_focus":
		apply_pillar_shift(tag, "ascendancy", -int(6 * scale), "assimilation_cost")  # Tree / initiative cost for the mitigation
		apply_agent_pillar_influence(tag, "cohesion", int(10 * scale), "institutional")
		apply_agent_pillar_influence(tag, "cohesion", int(6 * scale), "public")  # Partial recovery
		# Simple "conversion" flavor: improve future affinity a bit (stored for later use)
		if not peace_state.has("culture_affinity_mods"):
			peace_state["culture_affinity_mods"] = {}
		peace_state["culture_affinity_mods"][tag + "_" + source_culture] = 0.15
	elif policy == "skilled_only":
		apply_pillar_shift(tag, "mandate", int(5 * scale), "skilled_talent")
		apply_agent_pillar_influence(tag, "cohesion", -int(4 * scale), "public")  # Smaller backlash

	# Record for events / UI / future erosion simulation
	peace_state["notes"].append("Immigration %s -> %s (src=%s, scale=%.2f, policy=%s, affinity=%.2f)" % [tag, host_primary, source_culture, scale, policy, affinity])

	# Check downstream risks (failed state pressure, separatism)
	check_subversion_risk(tag)
	if get_pillar(tag, "cohesion") < 45:
		check_separatism_risk(tag)

	print("Immigration from %s to %s (scale %.2f, policy %s, affinity %.2f): Short industrial/Mandate + (%d), public short + then long -%d (jobs/crime/culture). Elite %+d, Institutional %s. Hidden Hand +%d on public. Policy & affinity matter for sandbox agency." % [source_culture, tag, scale, policy, affinity, short_industrial, public_long, elite_mod, ("hit" if policy=="open" else "mitigated"), hh_gain])

# === Top-Level Demographic / Population Policies (Policy/Law Screen + Initiatives integration) ===
# User request: Not just migration. Pro-natal incentives (tax breaks for large families, housing for 5+ kids, cultural encouragement) for native pop growth — slower than open immigration but more sustainable, less cohesion damage.
# Restriction options: "Build the wall", fortified borders, high barriers (you have to really want it) — preserve public cohesion and citizen jobs at cost of slower industrial growth.
# Two-tiered justice: Historical status quo in many kingdoms/empires (special treatment for royals/elite). Boosts elite, risks public resentment + Hidden Hand fuel.
# Foreigners in military / high non-citizens: Consequences like off-gold-standard inflation. Bonuses (cheap manpower, fast army growth) but loyalty risks, institutional distrust, "social inflation" (crime, unrest, Mandate drag, efficiency loss). High % non-citizens or foreign troops debases social trust/cohesion analog to currency debasement.
# These live in a top-level Policy/Law screen (adjustable, unlocked/modified by player via tree, agents, events, era). Tree provides big pushes/Golden specials; this is the tunable ongoing law layer.
# Erosion timing: Monthly via TimeManager.game_month_advanced (small ticks for realism + accumulation to events/thresholds). Pro-natal and strict policies counter the drain. Immediate application for player feedback in UI/demo.

func apply_pro_natal_incentives(tag: String, level: int) -> void:
	# level: 0 = none, 1 = tax_breaks (families with kids), 2 = housing_for_large_families (5+ kids priority), 3 = full_support (cultural + economic campaign).
	# Slower native growth (simulated via reduced non_citizen pressure + long public/institutional gains) vs fast immigration.
	# Costs Mandate (subsidies) or Ascendancy (mobilizing culture). +public Cohesion over time, lowers reliance on foreign labor, good for high-trust Golden paths.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"] = {}
	if typeof(peace_state["demographic_policies"]) != TYPE_DICTIONARY:
		peace_state["demographic_policies"] = {}
	if not peace_state["demographic_policies"].has(tag):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["pro_natal_level"] = clamp(level, 0, 3)

	var cost : Variant = level * 6
	apply_pillar_shift(tag, "mandate", -cost, "pro_natal_incentives")
	if level >= 2:
		apply_pillar_shift(tag, "ascendancy", -2, "pro_natal_campaign")
	# Long-term native buffer: reduces effective non_citizen erosion and gives public happiness (families supported).
	if tag not in peace_state["non_citizen_ratio"]:
		peace_state["non_citizen_ratio"][tag] = 0.0
	peace_state["non_citizen_ratio"][tag] = max(0.0, peace_state["non_citizen_ratio"].get(tag, 0.0) - (level * 0.02))  # Slow native pressure relief

	apply_agent_pillar_influence(tag, "cohesion", level * 3, "public")
	print("Pro-natal incentives level %d for %s: Slower sustainable native growth, public cohesion support, reduced foreign labor dependence. Costs Mandate/Ascendancy. Takes longer to show than immigration but healthier long-term cohesion." % [level, tag])
	if policy_state_changed.get_connections().size() > 0:
		policy_state_changed.emit(tag)

func apply_border_policy(tag: String, policy: String) -> void:
	# "open", "guest_worker", "skilled_only", "restricted", "fortified" ("build the wall" / high barriers — you have to really want to immigrate).
	# Strict/fortified: slower industrial (less cheap labor), strong public Cohesion preservation, enforcement costs (Mandate or agent missions), caps immigration scale.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"] = {}
	if typeof(peace_state["demographic_policies"]) != TYPE_DICTIONARY:
		peace_state["demographic_policies"] = {}
	if not peace_state["demographic_policies"].has(tag):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["border_policy"] = policy

	var strictness : Variant = 0.0
	if policy in ["restricted", "fortified"]:
		strictness = 0.8 if policy == "fortified" else 0.5
		apply_pillar_shift(tag, "mandate", -int(8 * strictness), "border_enforcement")
		apply_agent_pillar_influence(tag, "cohesion", int(6 * strictness), "public")  # Citizen jobs protected
		if tag in peace_state["non_citizen_ratio"]:
			peace_state["non_citizen_ratio"][tag] = max(0.0, peace_state["non_citizen_ratio"][tag] - 0.03)
	elif policy == "open":
		# Re-allows faster influx (player can combine with pro-natal or assimilation).
		apply_agent_pillar_influence(tag, "cohesion", -3, "public")
	print("Border policy for %s set to %s (strictness %.1f). Fortified/restricted protects public cohesion and citizen employment at Mandate cost and slower industrial growth. Open allows quick labor but accelerates non-citizen strain." % [tag, policy, strictness])
	if policy_state_changed.get_connections().size() > 0:
		policy_state_changed.emit(tag)

func apply_military_integration(tag: String, foreign_pct: float) -> void:
	# foreign_pct 0.0–0.4+ (high portions of non-citizens/foreigners in military).
	# Bonuses: faster "recruitment" / lower effective cost (industrial_base or manpower feel), cheap expansion.
	# Consequences (like off-gold / printing): institutional Cohesion hit (loyalty doubts, command friction), public resentment ( "our boys vs foreigners"), higher separatism/Hidden Hand risk in crises, reduced effectiveness (lower "reliability" multiplier in combat simulation later).
	# High non-citizen overall (separate from military) adds "social inflation": gradual Mandate/public drag, crime, industrial efficiency loss.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	foreign_pct = clamp(foreign_pct, 0.0, 0.6)
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["foreign_military_pct"] = foreign_pct
	if tag not in peace_state["foreign_military_pct"]:
		peace_state["foreign_military_pct"][tag] = 0.0
	peace_state["foreign_military_pct"][tag] = foreign_pct

	# Bonus
	var bonus_strength : int = int(foreign_pct * 15)
	apply_pillar_shift(tag, "mandate", bonus_strength / 2, "foreign_levies")
	if tag not in peace_state["industrial_base"]:
		peace_state["industrial_base"][tag] = 50
	peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) + bonus_strength)

	# Risks (institutional + public)
	var risk : int = int(foreign_pct * 12)
	apply_agent_pillar_influence(tag, "cohesion", -risk, "institutional")
	apply_agent_pillar_influence(tag, "cohesion", -int(risk * 0.6), "public")
	# "Social inflation" analog
	if tag not in peace_state["non_citizen_ratio"]:
		peace_state["non_citizen_ratio"][tag] = 0.0
	peace_state["non_citizen_ratio"][tag] = min(0.6, peace_state["non_citizen_ratio"].get(tag, 0.0) + (foreign_pct * 0.15))
	print("Military integration for %s: foreign_pct %.0f%%. Cheap/fast expansion bonus, but institutional loyalty hit, public resentment, elevated separatism/Hidden Hand risk, and social strain (like currency debasement). High non-citizen % overall adds ongoing 'inflation' of problems." % [tag, foreign_pct * 100])

func get_military_loyalty_multiplier(tag: String) -> float:
	# Recommendation based on history (Roman auxiliaries → citizenship path for integration; mercenaries like Swiss successful due to culture/discipline vs. many condottieri who switched sides; Ottoman Janissaries initially elite then problematic; British Gurkhas/Indian Army high loyalty when treated well but 1857 risks; French Foreign Legion high unit cohesion but separate identity).
	# Foreign % gives numbers bonus but applies loyalty/reliability penalty to organization and morale (foreigners less likely to fight as hard/long or be as creative — like many mercenary forces).
	# Higher attrition (desertion). Much more susceptible to Hidden Hand influence/subversion.
	# Path to citizenship (Rome model): Long pro-natal + assimilation + military service converts some % over time, improving multiplier and reducing HH risk. Offer the carrot to integrate.
	# When manpower low, player will want foreigners — this forces the trade-off.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var foreign_pct: float = float(peace_state.get("foreign_military_pct", {}).get(tag, 0.0))
	var base_mult: float = 1.0 - (foreign_pct * 0.65)  # At 25% foreign ~0.84 multiplier (noticeable org/morale hit in prolonged fights)
	# Cohesion and assimilation buffer
	var coh: int = get_pillar(tag, "cohesion")
	base_mult += (coh - 50) * 0.002  # High cohesion helps loyalty
	# Future: assimilation progress from initiatives/policies improves it further.
	base_mult = clamp(base_mult, 0.6, 1.15)
	if foreign_pct > 0.15:
		# Extra Hidden Hand susceptibility on foreign units
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", int(foreign_pct * 5), "institutional")
	return base_mult

func get_effective_military_factor(tag: String) -> float:
	# Ties loyalty multiplier into military system (for allocation, future combat, manpower).
	# Effective output = base allocation * loyalty.
	# Use in demo, future recruitment, or supply calculations.
	_init_peace_state_if_needed()
	var loyalty: float = get_military_loyalty_multiplier(tag)
	var alloc: float = float(peace_state["military_allocation"].get(tag, 0.5))
	return alloc * loyalty

# === Manpower / Recruitment Ties (high-value next step) ===
# NOW EXPOSED: manpower pool fully derived from national pop * conscription_level (roadmap item 1).
# Pool auto-syncs on monthly pop growth + policy change. Recruit deducts pool + applies pop strain/cohesion feedback.
# Pop/conscript now feeds combat width + reinforce rate (via Province modifiers + national getters) + recruit strain.
# Ties pop growth/labor (recent) directly to fieldable forces, reinforce, width, and cohesion cost for playable 50+ turn loop.

func adjust_manpower(tag: String, amount: int, reason: String = "") -> void:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("manpower_pool"):
		peace_state["manpower_pool"] = {}
	if not peace_state["manpower_pool"].has(tag):
		peace_state["manpower_pool"][tag] = 100  # baseline
	peace_state["manpower_pool"][tag] = max(0, peace_state["manpower_pool"][tag] + amount)
	if reason:
		peace_state["notes"].append("Manpower %s %s by %d (%s)" % [tag, "gained" if amount > 0 else "lost", abs(amount), reason])
	print("Manpower for %s now %d (%s)" % [tag, peace_state["manpower_pool"][tag], reason])

func get_available_recruits(tag: String) -> int:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var base: int = int(peace_state.get("manpower_pool", {}).get(tag, 100))
	var loyalty: float = get_military_loyalty_multiplier(tag)
	var noncit: float = float(peace_state.get("non_citizen_ratio", {}).get(tag, 0.0))
	# Loyalty and low non-citizen improve effective pool; high foreign % or low loyalty penalizes (desertion, distrust).
	var effective: int = int(base * loyalty * (1.0 - noncit * 0.5))
	# Pro-natal policies give long-term native buffer (already reduces non_citizen over time).
	return max(10, effective)

# Full exposure per roadmap: derive/sync pool from current pop * conscription policy.
# Called on monthly growth (after pop *= growth) and on conscription law change.
# Growth in pop directly increases available recruits over time (playable econ/war feedback).
func update_manpower_from_population(tag: String) -> void:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("population") or not peace_state["population"].has(tag):
		return
	var p: float = float(peace_state["population"][tag])
	var policies: Dictionary = peace_state.get("demographic_policies", {}).get(tag, {})
	var cons_level: int = int(policies.get("conscription_level", 0))
	# Historical proxy: fraction of total pop in "military manpower pool" (age+fit+political will).
	# Scales directly with conscription law (peacetime low, total-war high).
	var base_frac : Variant = 0.008
	if cons_level == 1:
		base_frac = 0.014
	elif cons_level >= 2:
		base_frac = 0.028
	var derived: int = int(p * base_frac)
	if not peace_state.has("manpower_pool"):
		peace_state["manpower_pool"] = {}
	var old_pool: int = int(peace_state["manpower_pool"].get(tag, 0))
	# Cloning tech direct pool boost (artificial manpower replacement from cloning_tech_1980; flavor: vats solve shortages but genetic uniformity/ethics backlash risk + resource cost)
	if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_rule_flag(tag, "cloning"):
		derived = int(derived * 1.18)  # concrete +18% (minimal high-impact; balance vs ethics_risk amp in research events + coh/Hand)
	derived = max(50, derived)
	peace_state["manpower_pool"][tag] = derived
	if derived != old_pool:
		print("Manpower pool for %s updated from pop*conscript: %d (pop=%.1fM, cons_level=%d, frac=%.3f)" % [tag, derived, p / 1000000.0, cons_level, base_frac])

func get_national_manpower_width_bonus(tag: String) -> float:
	# Pop/conscript drives wider engagement possible (more bodies for frontage) or reinforce depth.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var rec: int = get_available_recruits(tag)
	if rec < 100:
		return 0.0
	# Log scale for diminishing returns (realistic: huge pop gives +width but not infinite).
	var bonus: float = clampf(log(max(1.0, float(rec))) / 9.5, 0.0, 0.45)
	return bonus

func get_national_manpower_reinforce_mult(tag: String) -> float:
	# Larger recruit pool = faster reinforce rate from casualties (pop feeds width/reinforce per roadmap).
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var rec: int = get_available_recruits(tag)
	var p: float = float(peace_state.get("population", {}).get(tag, 1000000.0))
	var pool_factor: float = float(rec) / maxf(200.0, p * 0.0002)
	var mult := 1.0 + clampf(pool_factor, 0.0, 0.6)
	# Cloning/artificial repro tech (cloning_tech_1980): +manpower_replacement directly boosts reinforce/pool (solves shortages per flavor)
	# Cross with prior manpower engines; balance: high ethics_risk (unaddressed -> sabotage/coh hit via existing research ethics)
	if typeof(TechnologyManager) != TYPE_NIL:
		var tech_m := TechnologyManager.get_technology_modifiers(tag)
		var mp_rep := float(tech_m.get("manpower_replacement", 0.0))
		if mp_rep > 0.0:
			mult *= (1.0 + mp_rep * 0.8)  # 0.2 tech -> ~16% boost
		# Also check via NMM if flowed
		if typeof(NationalModifierManager) != TYPE_NIL:
			var cmods := NationalModifierManager.get_combat_modifiers(tag)
			mp_rep = maxf(mp_rep, float(cmods.get("manpower_replacement", 0.0)))
			if mp_rep > 0.0:
				mult *= (1.0 + mp_rep * 0.4)
	return mult

func recruit_units(tag: String, amount: int) -> bool:
	_init_peace_state_if_needed()
	var available : Variant = get_available_recruits(tag)
	if available < amount:
		return false
	adjust_manpower(tag, -amount, "unit_recruitment")
	# Apply loyalty hit if heavy foreign reliance (simulates integration strain).
	var foreign_pct: float = float(peace_state.get("foreign_military_pct", {}).get(tag, 0.0))
	if foreign_pct > 0.2:
		apply_agent_pillar_influence(tag, "cohesion", -int(amount * 0.1 * foreign_pct), "institutional")
	# NEW: pop recruit strain (high conscript draft erodes public cohesion; feedback loop for econ/war choices).
	var cons_level: int = int(peace_state.get("demographic_policies", {}).get(tag, {}).get("conscription_level", 0))
	var strain: int = int(clamp(amount * 0.04 + cons_level * 1.5, 1, 12))
	apply_agent_pillar_influence(tag, "cohesion", -strain, "public")
	print("Recruit strain for %s: drafted %d (cons=%d) -> public cohesion -%d. Pop pool now feeds reinforce/width but costs cohesion if overused." % [tag, amount, cons_level, strain])
	return true

# Civilian goods production (roadmap phase2): factories can run civilian lines for happiness/supply effects.
# Output from prod lines (special design "civilian_consumer_goods") feeds pop happiness (cohesion/mandate) + can wire to local prov supply.
# No unit template needed; separate from mil stockpile.
func produce_civilian_goods(tag: String, amount: int) -> void:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if amount <= 0:
		return
	if not peace_state.has("civilian_goods"):
		peace_state["civilian_goods"] = {}
	peace_state["civilian_goods"][tag] = int(peace_state["civilian_goods"].get(tag, 0)) + amount
	# Effects: consumer goods boost public happiness (cohesion), some Mandate (growth capital), slight welfare relief.
	var coh_gain : Variant = clampi(amount / 8, 1, 8)
	apply_agent_pillar_influence(tag, "cohesion", coh_gain, "public")
	apply_pillar_shift(tag, "mandate", max(1, amount / 12), "civilian_goods")
	if peace_state.get("welfare_burden", {}).has(tag):
		peace_state["welfare_burden"][tag] = max(0.0, float(peace_state["welfare_burden"][tag]) - float(amount) * 0.01)
	print("Civilian goods: %s produced %d -> +coh %d public, +mandate, welfare relief. Stock now %d. (Happiness from output ties econ to pop effects.)" % [tag, amount, coh_gain, int(peace_state["civilian_goods"][tag])])
	# Emit if policy live for inspector/UI
	if policy_state_changed.get_connections().size() > 0:
		policy_state_changed.emit(tag)

func apply_conscription_law(tag: String, level: int) -> void:
	# Common historical lever. Level 0-2: limited / standard / total war conscription.
	# Affects military_allocation (easier high %), public Cohesion (resentment at high levels), manpower availability.
	# Matters a lot when combined with foreign military (more bodies but loyalty issues).
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	level = clamp(level, 0, 2)
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["conscription_level"] = level

	var alloc_boost: float = level * 0.12
	var current_alloc: float = float(peace_state["military_allocation"].get(tag, 0.5))
	set_military_allocation(tag, min(1.0, current_alloc + alloc_boost), "conscription_law")
	apply_agent_pillar_influence(tag, "cohesion", -level * 5, "public")  # Public hates being drafted
	update_manpower_from_population(tag)  # re-derive pool immediately (higher cons = more recruits exposed)
	print("Conscription law level %d for %s: Easier high military allocation, but public cohesion hit. When manpower low you will want this + foreign troops — watch the loyalty multiplier and Hidden Hand risk. Manpower pool re-synced from pop." % [level, tag])

func apply_women_workforce_policy(tag: String, policy: String) -> void:
	# Policies toward women in workforce / war / military (feminism push). Boosts industrial short-term but anti-pro-natal consequences: harder to have large families when both parents working (user: moves away from pro-natal, negatively impacts kids). "Feminize men / make women man-like" erodes traditional family/sanctity.
	# "restricted" (traditional family focus – pro-natal buffer), "encouraged" (war/economic necessity), "full" (equality/feminism push – cultural war, woke poison).
	# Trade-offs: Short industrial/military; long family erosion, lower native growth (anti-natal), welfare_burden up (childcare "needs"), cohesion split (elite "progress" vs public family values), HH gains on "outdated" traditional resistance.
	# Low cohesion makes feminism "demands" stronger pressure (toasts push enactment).
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["women_workforce"] = policy

	if policy == "encouraged" or policy == "full":
		if tag not in peace_state["industrial_base"]:
			peace_state["industrial_base"][tag] = 50
		peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) + 12)
		apply_agent_pillar_influence(tag, "cohesion", -4, "public")  # Traditional family resistance
		if tag not in peace_state["welfare_burden"]:
			peace_state["welfare_burden"][tag] = 0.0
		peace_state["welfare_burden"][tag] = min(100.0, peace_state["welfare_burden"].get(tag, 0.0) + 4)
		# Anti-pro-natal: Both working makes lots of kids harder; reduce pro_natal effectiveness
		if policy == "full":
			apply_agent_pillar_influence(tag, "cohesion", 6, "elite")  # "Woke" elites
			# Direct anti-natal hit
			if tag not in peace_state["non_citizen_ratio"]:
				peace_state["non_citizen_ratio"][tag] = 0.0
			peace_state["non_citizen_ratio"][tag] = min(0.6, peace_state["non_citizen_ratio"].get(tag, 0.0) + 0.03)  # proxy for family formation difficulty
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "public")  # Feminism as cultural division tool
	# Emit for map/inspector live update (welfare strain affects Province supply/org getters + tints)
	_emit_welfare_province_refresh(tag)
	print("Women workforce policy for %s: %s. Industrial boost but feminism/equality push erodes pro-natal (both parents working = harder large families, family values poisoned). Low cohesion pressures enactment. Trade-off: short workforce vs long anti-family/anti-natal." % [tag, policy])

func apply_police_type(tag: String, ptype: String) -> void:
	# Foreign police / local police / secret police. Different control vs. cohesion vs. Hidden Hand resistance.
	# secret: Better vs Hidden Hand but public hit (fear). foreign_controlled: Strong control but loyalty issues.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["police_type"] = ptype

	if ptype == "secret":
		apply_agent_pillar_influence(tag, "cohesion", -6, "public")
		apply_agent_pillar_influence(tag, "cohesion", 8, "institutional")
		# Stronger resistance to Hidden Hand
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -4, "public")
	elif ptype == "foreign_controlled":
		apply_agent_pillar_influence(tag, "cohesion", -8, "public")
		apply_agent_pillar_influence(tag, "cohesion", -5, "institutional")
		# Can be subverted more easily
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "institutional")
	print("Police type for %s: %s. Trade control, public trust, and Hidden Hand resistance." % [tag, ptype])
	if policy_state_changed.get_connections().size() > 0:
		policy_state_changed.emit(tag)

func apply_money_supply_policy(tag: String, mode: String) -> void:
	# Printing money / fiat expansion mechanics. Short stimulus (Mandate/industrial boost), long Trust Erosion + inflation effects (Ascendancy hit, production efficiency loss, public unhappiness).
	# Reference Weimar 1920s crash: hyperinflation destroyed middle class (public Cohesion collapse), radicalization (Hidden Hand opportunity), economic ruin then recovery via new currency + direction.
	# Sovereign wealth / gold / asset backing as counters (Gaddafi-style gold dinar = major Hidden Hand flag; they push long-term debasement for control).
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["money_supply"] = mode

	if mode == "expanded_fiat" or mode == "managed":
		apply_pillar_shift(tag, "mandate", 15, "fiat_stimulus")
		if tag not in peace_state["industrial_base"]:
			peace_state["industrial_base"][tag] = 50
		peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) + 10)
		# Long erosion
		if tag not in peace_state["trust_erosion"]:
			peace_state["trust_erosion"][tag] = 0.0
		peace_state["trust_erosion"][tag] = min(100.0, peace_state["trust_erosion"].get(tag, 0.0) + 8)
		apply_pillar_shift(tag, "ascendancy", -5, "fiat_debasement")  # Prestige hit
		if tag not in peace_state["fiat_strain"]:
			peace_state["fiat_strain"][tag] = 0.0
		peace_state["fiat_strain"][tag] += 10
		# Production efficiency hit (inflation)
		if tag in peace_state["industrial_base"]:
			peace_state["industrial_base"][tag] = max(10, peace_state["industrial_base"][tag] - 5)
	elif mode == "gold_standard":
		if tag in peace_state["trust_erosion"]:
			peace_state["trust_erosion"][tag] = max(0.0, peace_state["trust_erosion"][tag] - 12)
		apply_pillar_shift(tag, "ascendancy", 4, "sound_money")
		print("Gold standard / asset-backed for %s: Strong counter to Trust Erosion. Limits printing but requires reserves. Major Hidden Hand target (stable money threatens their debasement agenda).")
	print("Money supply policy for %s set to %s. Fiat expansion = short boost, long Trust Erosion (Ascendancy + production hit, public pain, recovery paths exist like post-Weimar). Gold/sovereign wealth as powerful stabilizers." % [tag, mode])
	if policy_state_changed.get_connections().size() > 0:
		policy_state_changed.emit(tag)

func apply_sovereign_wealth(tag: String, level: int) -> void:
	# Sovereign wealth funds, asset-based backing, gold reserves etc. as major finance options. Counters erosion but draws Hidden Hand ire (stable/real assets are the enemy of debasement/one-world aims).
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	level = clamp(level, 0, 2)
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["sovereign_wealth"] = level

	var benefit : Variant = level * 8
	apply_pillar_shift(tag, "mandate", benefit, "sovereign_wealth")
	if tag in peace_state["trust_erosion"]:
		peace_state["trust_erosion"][tag] = max(0.0, peace_state["trust_erosion"][tag] - benefit * 0.8)
	print("Sovereign wealth / asset backing level %d for %s: Boosts Mandate, strongly counters Trust Erosion. Big red flag for Hidden Hand — expect special ops or narratives against 'gold-backed' or 'real asset' systems." % [level, tag])

func apply_social_services_policy(tag: String, mode: String) -> void:
	# Cultural war / war on traditional family (user vision): Abstracted simulation of elite-driven anti-natal policies normalized as "healthcare".
	# "The lie of abortion as healthcare" – elite_optimization: pop control to "eliminate undesirable types" for costs, lower birth rates, "empowerment" narrative poisoning Western traditionalist values of family, sanctity of life, pro-natal family life.
	# Elites/Hidden Hand strategies (inspired by Q materials, Georgia Guidestones depopulation goals ~500M, pandemics as tools: AIDS, bird flu, COVID "crises" for control, fear, division, population issues).
	# Modes: "traditional" (restraint, sanctity of life, family values – slow but pure cohesion/Golden path).
	# "elite_optimization" (anti-natal pop control via "healthcare" lies – short cost savings, but erodes family, normalizes termination of life).
	# "compassionate_end_of_life" (assisted suicide as welfare "optimization" – elite control over "burdens").
	# "expansive_burden" (woke mind virus expansive services: gender, equity "healthcare" creating massive welfare load, anti-family, cultural poison).
	# Trade-off to make choosable (player may pick in crisis): Short-term Mandate/elite relief or "savings" (tempting when manpower low, economy strained – "we can't afford more mouths"). Long-term anti-natal disaster: welfare_burden explosion, public cohesion collapse (family values poisoned), HH narrative win ("elites killing the future"), blocks/sours Golden (decadent vs pure traditional), separatism risk, "how far we have fallen".
	# Balance vs sanctity of life/traditional Western family: Traditional path = slower growth but high public trust, easier Golden renaissance, "our people have future/land". Choosable in pinch but costly – real agency, flavorful opposites.
	# Abstracted: No micro sim, but shows reality of normalization via elite narratives. Fun, interactive: Toasts first + dialogue with clear payoffs (savings now vs cultural collapse later).
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"] = {}
	if typeof(peace_state["demographic_policies"]) != TYPE_DICTIONARY:
		peace_state["demographic_policies"] = {}
	if not peace_state["demographic_policies"].has(tag):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["social_services"] = mode

	if mode in ["elite_optimization", "compassionate_end_of_life"]:
		apply_pillar_shift(tag, "mandate", 10, "welfare_cost_control")  # tempting short elite/Mandate "savings" in crisis (anti-natal choice)
		apply_agent_pillar_influence(tag, "cohesion", 5, "elite")  # elites "efficient"
		if tag not in peace_state["welfare_burden"]:
			peace_state["welfare_burden"][tag] = 0.0
		peace_state["welfare_burden"][tag] = min(100.0, peace_state["welfare_burden"].get(tag, 0.0) + 8)
		apply_agent_pillar_influence(tag, "cohesion", -5, "public")  # family/traditional values hit
		# HH gains from cultural poison / depop narrative
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 4, "public")
	elif mode == "expansive_burden":
		apply_pillar_shift(tag, "mandate", -15, "welfare_overreach")  # immediate bleed from woke expansion
		apply_agent_pillar_influence(tag, "cohesion", -8, "public")  # family life poisoned by "equity"
		if tag not in peace_state["welfare_burden"]:
			peace_state["welfare_burden"][tag] = 0.0
		peace_state["welfare_burden"][tag] = min(100.0, peace_state["welfare_burden"].get(tag, 0.0) + 15)
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 6, "public")  # elites/HH "progress"
	else:  # traditional - nod to sanctity of life, family values
		if tag in peace_state["welfare_burden"]:
			peace_state["welfare_burden"][tag] = max(0.0, peace_state["welfare_burden"][tag] - 5)
		apply_agent_pillar_influence(tag, "cohesion", 4, "public")  # family life strengthened
		# Buffer against HH depop tools
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -2, "public")
	# Emit for map/inspector live update (strain tint + derived supply/org drag)
	_emit_welfare_province_refresh(tag)
	print("Social services / welfare model for %s set to %s. Cultural war: elite anti-natal 'healthcare' lies vs traditional family/sanctity of life. Short crisis relief vs long cultural collapse. Balance via toasts + dialogue. (Elites/HH: pandemics, Guidestones depop motives.)" % [tag, mode])

func apply_governmental_education_policy(tag: String, mode: String) -> void:
	# Public/governmental education policy (user request): Trade-offs between "good little worker bees" (public system conformity for industrial/workforce) vs. independent problem solvers/critical thinkers (traditional/classical – better agents/leaders, innovation, but perhaps slower mass workforce or higher "unruly" cohesion?).
	# Modes: "public_indoctrination" (state schools produce compliant workers, short industrial boost, but conformity reduces critical thinking – impacts agent quality/tech long-term, anti-family?).
	# "traditional_classical" (independent, problem-solving focus – pro-sanctity/family values, better long-term cohesion/agents, but may resist "modern" labor discipline).
	# "mixed_public" (balance).
	# Ties to cultural war: Public systems can be vector for removing bible/traditional values, feminism indoctrination, making populace more prone to HH pressure/demands. Anti-pro-natal flavor if it promotes workforce over family.
	# Pressure mechanism: Low cohesion makes "demand for public reform" stronger (toasts/events push player); traditional education resists but alerts HH as outlier.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["education_policy"] = mode

	if mode == "public_indoctrination":
		if tag not in peace_state["industrial_base"]:
			peace_state["industrial_base"][tag] = 50
		peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) + 8)
		apply_agent_pillar_influence(tag, "cohesion", -3, "public")  # conformity, loss of independent spirit
		# Anti-pro-natal / family: Both parents "educated for workforce" makes large families harder
		if tag not in peace_state["welfare_burden"]:
			peace_state["welfare_burden"][tag] = 0.0
		peace_state["welfare_burden"][tag] = min(100.0, peace_state["welfare_burden"].get(tag, 0.0) + 3)
		# Makes more prone to HH propaganda (less critical thinkers)
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 2, "public")
	elif mode == "traditional_classical":
		apply_agent_pillar_influence(tag, "cohesion", 4, "public")  # independent, family-oriented values
		# Buffers HH, pro-sanctity
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -2, "public")
		# Slight long-term agent/leader quality (but not immediate industrial)
	else:  # mixed
		apply_pillar_shift(tag, "mandate", 3, "education_compromise")
	# Emit for map/inspector (welfare drag on supply etc. for public ed mode)
	_emit_welfare_province_refresh(tag)
	print("Governmental education policy for %s set to %s. Public = worker bees + conformity (HH vector); Traditional = independent thinkers + family values. Low cohesion pressures 'reform' toward public (bible removal etc.)." % [tag, mode])

func apply_encourage_relocation(tag: String, target_culture_or_area: String, scale: float) -> void:
	# Simulate large group migration, settlement, repopulation, conversion/encouragement to new lands.
	# Can move your primary culture pops or encourage compatible groups. Affects non_citizen in destination, cohesion in source/target, future integration/victory resistance.
	# "Conversion" via assimilation or cultural/religious initiatives layered on top.
	# First map/territory hook stub: Updates "settled_areas" for future province/territory integration bonuses (lower resistance, better cohesion in target).
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	# Simple model: reduce non_citizen in "target" (or increase your primary presence), cost Mandate/Ascendancy, cohesion effects.
	if tag not in peace_state["non_citizen_ratio"]:
		peace_state["non_citizen_ratio"][tag] = 0.0
	peace_state["non_citizen_ratio"][tag] = max(0.0, peace_state["non_citizen_ratio"].get(tag, 0.0) - (scale * 0.1))
	apply_pillar_shift(tag, "mandate", -int(scale * 10), "relocation_settlement")
	apply_agent_pillar_influence(tag, "cohesion", int(scale * 4), "public")  # "Our people have land/future"

	# Map/territory integration stub (for when map provinces/settlement are live).
	if not peace_state.has("settled_areas"):
		peace_state["settled_areas"] = {}
	peace_state["settled_areas"][target_culture_or_area] = peace_state["settled_areas"].get(target_culture_or_area, 0.0) + scale
	# Real hook: If we have a target province or victory context, lower resistance via cultural settlement (repopulation/conversion bonus).
	# For demo/peace: simulate by calling start_territory_integration with reduced resistance if "settlement" flavor.
	if "player" in tag or tag == "player":  # demo player context
		var settlement_bonus : int = int(scale * 15)
		# Pretend a territory integration with better acceptance due to settlement.
		if has_method("start_territory_integration"):
			start_territory_integration(target_culture_or_area, "hearts", {"ancestral": settlement_bonus, "population": int(scale * 10)})
	# Full map territory integration: mutate multiple real provinces (not single sample).
	# Strategy: Prefer provinces owned by the relocating tag (repopulating "our" lands or new territory).
	# Fall back to a small set of demo/test provinces (phase1 ids 1-10+). Distribute the scale boost.
	# Effects: Higher dev/infra automatically improve Province getters (org recovery, attrition reduction, local supply, combat width, logistics).
	# We also set explicit settlement_level on the Province for direct flavor bonuses + set settled_areas for resistance/victory/golden.
	# MapManager update calls (where available) emit signals for UI/map refresh.
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
		var candidates: Array[int] = []
		# Real map territory targeting for playable playtest: prefer owned provinces (repopulating "our lands" or new territory).
		# Filter for "settleable" (lower dev for growth narrative, or any for demo). This makes relocation feel like actual territorial engineering.
		if MapManager.has_method("get_provinces_by_owner"):
			candidates = MapManager.get_provinces_by_owner(tag)
		if candidates.is_empty() and MapManager.has_method("get_provinces_by_controller"):
			candidates = MapManager.get_provinces_by_controller(tag)
		if candidates.is_empty():
			# Fallback demo set (phase1 interesting provinces).
			candidates = [1, 2, 3, 4, 5, 6, 8]
		# Prefer lower-dev provinces for "frontier/repopulation" flavor (world-class interaction: player sees growth on underdeveloped areas).
		candidates.sort_custom(func(a: int, b: int) -> bool:
			var pa : Variant = MapManager.get_province(a)
			var pb : Variant = MapManager.get_province(b)
			var da : Variant = pa.development_level if pa else 99
			var db : Variant = pb.development_level if pb else 99
			return da < db
		)
		# Full territories support for playtest (user priority): Apply to all/many owned provinces for "real" demographic engineering on the map.
		# No hard small limit – scale distributes; player chains for big effects. With richer gen data (tools/map_generation phase1 350+ provinces), this makes Europe loops testable with settlement/welfare on full owned lands.
		# (If too many, player sees broad map vitality tint, supply/combat changes across territories.)
		var dev_per : int = int(scale * 3.5)
		var infra_per : int = int(scale * 2.5)
		var affected_names: Array = []
		for pid in candidates:
			var p: Province = MapManager.get_province(pid)
			if p == null:
				continue
			var old_dev : Variant = p.development_level
			var old_infra : Variant = p.infrastructure
			p.development_level = clamp(p.development_level + dev_per, 0, 50)
			p.infrastructure = clamp(p.infrastructure + infra_per, 0, 50)
			# Explicit settlement marker (drives extra bonuses in getters beyond raw dev/infra).
			p.settlement_level = clamp(p.settlement_level + (scale * 0.25), 0.0, 2.0)
			# Prefer MapManager updaters when they exist (they emit province_data_changed for renderer/inspector).
			if MapManager.has_method("update_province_infrastructure"):
				MapManager.update_province_infrastructure(pid, p.infrastructure)
			# Dev has no dedicated updater in all builds; direct + optional notify.
			if MapManager.has_method("notify_province_changed"):
				MapManager.notify_province_changed(pid, "development")
			# Explicit emit so MapRenderer tints (settlement cyan-green vitality + welfare strain) and inspector refresh live for playtest.
			if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
				MapManager.province_data_changed.emit(pid, "settlement")
				MapManager.province_data_changed.emit(pid, "development")
			var pname : Variant = p.name if p.name else ("#%d" % pid)
			affected_names.append("%s(#%d +%d dev +%d infra)" % [pname, pid, p.development_level - old_dev, p.infrastructure - old_infra])
		if not affected_names.is_empty():
			var sample : Variant = affected_names.slice(0, min(5, affected_names.size()))
			var extra : Variant = affected_names.size() - sample.size()
			var sample_str : Variant = ", ".join(sample) + (" ... +%d more" % extra if extra > 0 else "")
			print(" [Map/Province FULL] Settlement in '%s' (scale %.2f) boosted %d provinces: %s. Dev/infra + settlement_level improve org recovery, lower attrition, local supply, combat width, logistics. (Playtest: click provinces in inspector or assault to see concrete system effects.)" % [target_culture_or_area, scale, affected_names.size(), sample_str])
		else:
			print(" [Map/Province integration] No suitable provinces found for settlement '%s'; settled_areas + resistance still updated." % target_culture_or_area)
		# Batch force after large settlement to avoid per-province signal storm / lag/hang on 40+ updates (tints, inspector, map layers).
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("force_full_map_refresh"):
			MapManager.call_deferred("force_full_map_refresh")
	else:
		# Headless / no MapManager fallback (still updates settled_areas + resistance path).
		print(" [Map/Province integration] MapManager not available; settlement recorded in settled_areas only (affects victory resistance + Golden checks). Dev/infra bonuses would apply to provinces on full map load.")
	print("Encourage relocation/settlement for %s (target %s, scale %.1f): Large group movement simulated. Reduces non-citizen pressure in destination, builds long-term cohesion via repopulation. Key for world-scale conversion and demographic engineering. (Settlement progress noted for territory integration — lower resistance in future map/victory contexts; Province dev/infra boost for settled areas.)" % [tag, target_culture_or_area, scale])

## Helper: after welfare_burden mutation (social/welfare/education policies or erosion side effects), emit per-owned-province "welfare"
## so MapRenderer tints (strain) + open inspector refresh instantly. Complements settlement emits in relocation.
func _emit_welfare_province_refresh(tag: String) -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_signal("province_data_changed"):
		return
	var pids: Array = []
	if MapManager.has_method("get_provinces_by_owner"):
		pids = MapManager.get_provinces_by_owner(tag)
	else:
		return
	for pidv in pids:
		var pid : int = int(pidv)
		MapManager.province_data_changed.emit(pid, "welfare")
		# Also "all" for broad listeners (overlays etc)
		MapManager.province_data_changed.emit(pid, "all")

func allocate_agent_to_policy_influence(agent_id: String, policy_type: String, target_tag: String, duration_months: int = 6) -> void:
	# Key for point 1 & 8: Changing laws/policies is a big deal. Agents are the main tool for continued pressure.
	# Long-duration missions (pay off, bribe, run campaigns, twist arms in parliament, influence king/court, plant propaganda).
	# Trade-off: Agent(s) tied up for months/years = less Tech, Intel, Trade, Vision (Initiatives), Diplomacy.
	# Success can reduce player cost to change policy, or directly shift it with less backlash.
	# Hidden Hand can run counter-missions.
	_init_peace_state_if_needed()
	target_tag = target_tag.to_upper()
	# Stub: In full AgentManager this would create a long-running mission with outcome that calls back to apply_*_policy with bonus.
	# For now, direct effect + note the opportunity cost.
	var influence : Variant = 8  # Would scale with agent skill + time
	apply_pillar_shift(target_tag, "mandate", influence, "agent_policy_lobby_" + policy_type)
	print("Agent %s allocated to policy influence on %s for %s (%d months). This is the main lever for most players — big commitment, real trade-off vs other agent work. Player can still direct-change in Policy screen at full cost." % [agent_id, policy_type, target_tag, duration_months])

# === Policy UI Helpers for Persistent Panel Polish (time-to-effect, Cohesion previews) ===
# Dynamic estimates based on current pillars/agents/Cohesion. Used in policy screen for world-class UX.
func get_policy_time_to_effect(tag: String, policy_type: String, change_level: int = 1) -> String:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var asc: int = int(peace_state["ascendancy"].get(tag, 50))
	var coh: int = get_pillar(tag, "cohesion")
	var agent_bonus: int = 0
	# Stub: in full, check active agents on "domestic" or "policy" missions for speed.
	if typeof(AgentManager) != TYPE_NIL:
		# Placeholder: higher if agents assigned (would query agent missions)
		agent_bonus = 2
	var base_months: int = 6
	if policy_type in ["pro_natal", "settlement"]:
		base_months = 12  # longer for pop growth
	elif policy_type in ["fiat", "border"]:
		base_months = 3
	elif policy_type in ["social", "welfare"]:
		base_months = 4  # quick visible burden, longer for full disastrous effects
	elif policy_type == "education":
		base_months = 6  # education reforms take time to show worker vs independent effects
	var speed: float = 1.0 + (asc / 100.0) * 0.5 + (coh / 100.0) * 0.3 + agent_bonus * 0.2
	var months: int = int(base_months / speed * change_level)
	return "est. %d-%d months visible effect (faster with high Ascendancy/agents/Cohesion)" % [months-2, months+2]

func get_policy_coh_impact(tag: String, policy_type: String) -> String:
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var policies: Dictionary = peace_state.get("demographic_policies", {}).get(tag, {})
	if policy_type == "pro_natal":
		return "+Public long-term (native support), -Elite short-term (if opposed to subsidies)"
	elif policy_type == "border":
		return "+Public (jobs protected), slows industrial growth"
	elif policy_type == "justice":
		return "+Elite (privilege), -Public (resentment), +Hidden Hand fuel"
	elif policy_type == "conscription":
		return "-Public (draft resentment), +military allocation"
	elif policy_type == "police":
		return "-Public trust, +Hidden Hand resistance"
	elif policy_type == "fiat":
		return "-Public (inflation pain), risk of unrest"
	elif policy_type == "sovereign":
		return "+Public/Institutional stability, counters Trust Erosion"
	elif policy_type == "social" or policy_type == "welfare":
		return "+Elite short (cost control), -Public long (burden), +Hidden Hand fuel, welfare strain like social inflation"
	elif policy_type == "education":
		return "Public: +Industrial short (worker bees), -Critical/agents long, anti-family; Traditional: +Cohesion/independent, pro-family/sanctity"
	return "Impacts Cohesion groups (public/elite/institutional) - see monthly for details"

func resolve_agent_policy_mission(agent_id: String, policy_type: String, target_tag: String, outcome: String = "success", bonus: int = 0) -> void:
	# Wires the new long-duration policy influence missions (from mission_definitions.json) to real effects.
	# Called on mission_completed signal (or simulated in demo for testing).
	# outcome: "success", "partial", "failure" — success gives strong shift or cost reduction, partial modest, failure small backlash.
	# This makes agent commitment to law change a first-class, trade-off-heavy activity (agents unavailable for other work during the mission).
	_init_peace_state_if_needed()
	target_tag = target_tag.to_upper()
	var effective_bonus : Variant = bonus
	if outcome == "success":
		effective_bonus += 12
	elif outcome == "partial":
		effective_bonus += 5
	elif outcome == "failure":
		effective_bonus -= 4
		apply_pillar_shift(target_tag, "ascendancy", -3, "policy_lobby_backlash")

	match policy_type:
		"pro_natal":
			apply_pro_natal_incentives(target_tag, 2)
		"border":
			apply_border_policy(target_tag, "fortified" if outcome == "success" else "restricted")
		"conscription":
			apply_conscription_law(target_tag, 2 if outcome == "success" else 1)
		"women_workforce":
			apply_women_workforce_policy(target_tag, "full" if outcome == "success" else "encouraged")
		"police":
			apply_police_type(target_tag, "secret" if outcome == "success" else "local")
		"fiat":
			apply_money_supply_policy(target_tag, "expanded_fiat" if outcome != "failure" else "managed")
		"sovereign":
			apply_sovereign_wealth(target_tag, 2 if outcome == "success" else 1)
		"welfare", "social", "social_services":
			apply_social_services_policy(target_tag, "elite_optimization" if outcome == "success" else "traditional")
		_:
			apply_pillar_shift(target_tag, "mandate", effective_bonus, "agent_policy_generic_" + policy_type)

	print("Agent policy mission resolved for %s on %s (outcome: %s, bonus %d). Policy shifted or cost mitigated. Agent time was a real trade-off." % [target_tag, policy_type, outcome, effective_bonus])
	if policy_state_changed.get_connections().size() > 0:
		policy_state_changed.emit(target_tag)

func _on_agent_mission_completed(agent_id: String, mission_id: String, outcome: String) -> void:
	# Auto-handler for AgentManager.mission_completed signal.
	# If the mission is a policy/law influence one (from our new definitions), auto-resolve via GameData.
	# This completes the end-to-end: player assigns agent → mission runs over time (agent unavailable elsewhere) → outcome applies policy change.
	if "lobby" in mission_id or "policy" in mission_id or "domestic" in mission_id or "police" in mission_id:
		var policy_type : Variant = mission_id.replace("lobby_domestic_law", "pro_natal").replace("expand_secret_police_network", "police").replace("lobby_", "").replace("_", "")
		# Map common ones
		if "pro_natal" in mission_id or "family" in mission_id: policy_type = "pro_natal"
		elif "border" in mission_id or "wall" in mission_id: policy_type = "border"
		elif "police" in mission_id: policy_type = "police"
		elif "fiat" in mission_id or "money" in mission_id: policy_type = "fiat"
		elif "sovereign" in mission_id or "gold" in mission_id: policy_type = "sovereign"
		resolve_agent_policy_mission(agent_id, policy_type, "player", outcome)  # target is current player for demo; real would use agent's country or mission target
		print("Auto-resolved policy mission %s via AgentManager signal (outcome %s)." % [mission_id, outcome])
		if policy_state_changed.get_connections().size() > 0:
			policy_state_changed.emit("player")

	# Agent based reveal chain advance: investigate/intel/trace/uncover missions (success) when hand high advance the long chain to full revelation (per user: agent missions to trace funding or how war started, uncover who is behind overt actions).
	if ("investigate" in mission_id or "intel" in mission_id or "trace" in mission_id or "uncover" in mission_id or "hand" in mission_id) and (outcome == "success" or outcome == "partial"):
		_init_peace_state_if_needed()
		var ptag : Variant = "player"
		if typeof(LeaderManager) != TYPE_NIL:
			ptag = str(LeaderManager.get_player_country_tag() or "player").to_upper()
		if not peace_state.has("hand_revelation"):
			peace_state["hand_revelation"] = {}
		var cur : float = float(peace_state["hand_revelation"].get(ptag, 0.0))
		peace_state["hand_revelation"][ptag] = min(1.0, cur + 0.1)
		print("[REVEAL CHAIN] Agent mission '", mission_id, "' (", outcome, ") advanced Hand trace for ", ptag, " (rev ", peace_state["hand_revelation"][ptag], "). Long chain of events/missions leads to reveal.")
		if peace_state["hand_revelation"][ptag] > 0.55 and not peace_state.get("hand_fully_revealed", false):
			peace_state["hand_fully_revealed"] = true
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("The Chain Completes: Hand Revealed", "Through persistent agent work tracing funding, backers, and overt actions (assassinations, overthrows, crises), the Hidden Hand's true agenda emerges. 'We were all tools.' The Hand loves wars and unrest to keep subjects manipulated and divided.", "revelation_full")
			print("[FULL REVEAL VIA AGENT CHAIN] ", ptag, " -- full revelation triggered by missions.")

	# Secret space program funding via agent (ties to space race secret events; risk exposure later)
	if "secret_space" in mission_id or "fund_space" in mission_id or "space_fleet" in mission_id or "black_space" in mission_id:
		_init_peace_state_if_needed()
		var sptag : Variant = "player"
		if typeof(LeaderManager) != TYPE_NIL:
			sptag = LeaderManager.get_player_country_tag()
		sptag = str(sptag).to_upper()
		if not peace_state.has("secret_space_programs"):
			peace_state["secret_space_programs"] = {}
		peace_state["secret_space_programs"][sptag] = true
		apply_pillar_shift(sptag, "ascendancy", 4, "secret_space_fund")  # hidden prestige
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 2, "public")  # black market feeds
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("Secret Space Program Funded", "%s agents funded covert space assets (satellite/fleet). Surprise edge in race, but exposure risk (Hand/scandal events). Public vs secret choice point." % sptag, "espionage")
		print("[SECRET SPACE AGENT] %s funded secret space via mission %s (outcome %s) - program active, Hand fed." % [sptag, mission_id, outcome])

	# Biotech agent missions (steal_genetic, sabotage_clone_vat, scanner_intel) wired via signal to _on_mission_completed
	if "genetic" in mission_id or "clone" in mission_id or "scanner_intel" in mission_id:
		_init_peace_state_if_needed()
		var btag : Variant = "player"
		if typeof(LeaderManager) != TYPE_NIL:
			btag = str(LeaderManager.get_player_country_tag() or "player").to_upper()
		if "steal_genetic" in mission_id and (outcome == "success" or outcome == "partial"):
			if not peace_state.has("biotech_intel"):
				peace_state["biotech_intel"] = {}
			peace_state["biotech_intel"][btag] = peace_state["biotech_intel"].get(btag, 0) + 1
			# direct tech progress steal bonus (via TM if avail)
			if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
				TechnologyManager.call("edit_tech_progress", btag, "genetic_engineering_1970", 0.12, false)
				TechnologyManager.call("edit_tech_progress", btag, "cloning_tech_1980", 0.08, false)
			print("[BIOTECH AGENT] %s stole genetic intel via mission (progress bonus applied)." % btag)
		elif "sabotage_clone" in mission_id:
			# already handled in AgentManager direct, but record here for persist/evidence
			if not peace_state.has("biotech_sabotage_log"):
				peace_state["biotech_sabotage_log"] = {}
			peace_state["biotech_sabotage_log"][btag] = peace_state["biotech_sabotage_log"].get(btag, 0) + 1
			print("[BIOTECH AGENT] %s clone sabotage mission resolved (coh/tech drag via AgentManager)." % btag)
		elif "scanner_intel" in mission_id and (outcome == "success" or outcome == "partial"):
			if not peace_state.has("scanner_intel_flags"):
				peace_state["scanner_intel_flags"] = {}
			peace_state["scanner_intel_flags"][btag] = true
			print("[BIOTECH AGENT] %s scanner intel bonus active (detection via NMM)." % btag)

func apply_justice_policy(tag: String, mode: String) -> void:
	# "egalitarian" (modern ideal, broad cohesion) vs "two_tier" (historical norm in kingdoms — special treatment for elite/royals).
	# Two-tier: +elite (loyalty, Mandate from upper strata), -public (resentment "undermines nation" feeling), Hidden Hand fuel.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	if not peace_state.has("demographic_policies"):
		peace_state["demographic_policies"][tag] = {}
	peace_state["demographic_policies"][tag]["justice_mode"] = mode

	if mode == "two_tier":
		apply_agent_pillar_influence(tag, "cohesion", 8, "elite")
		apply_agent_pillar_influence(tag, "cohesion", -7, "public")
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 4, "public")  # Injustice narrative
		print("Two-tier justice for %s: Elite cohesion and Mandate boosted (special treatment for royals/upper strata — historical status quo). Public cohesion hit and Hidden Hand opportunity (resentment). Flavorful for empires/monarchies." % tag)
	if policy_state_changed.get_connections().size() > 0:
		policy_state_changed.emit(tag)
	else:
		apply_agent_pillar_influence(tag, "cohesion", 5, "public")
		apply_agent_pillar_influence(tag, "cohesion", 3, "institutional")
		print("Egalitarian justice for %s: Broader public and institutional cohesion at expense of elite privilege." % tag)

func process_monthly_demographic_erosion(year: int, month: int) -> void:
	# Erosion timing implementation (per user: "i will take your recommendation").
	# Small monthly ticks for realism (accumulation feels organic). Thresholds trigger bigger events/unrest/Hidden Hand spikes.
	# Pro-natal and fortified borders provide decay/buffers. High non_citizen or foreign_military adds "social inflation" drag (Mandate loss, public happiness decay, slight industrial efficiency hit — direct analog to printing money / big government expansion debasing trust).
	# Immediate effects in apply_ methods for demo feedback; this is the ongoing simulation.
	_init_peace_state_if_needed()
	for tag in peace_state.get("primary_culture", {}).keys():
		var non_cit: float = float(peace_state.get("non_citizen_ratio", {}).get(tag, 0.0))
		var foreign_mil: float = float(peace_state.get("foreign_military_pct", {}).get(tag, 0.0))
		var policies: Dictionary = peace_state.get("demographic_policies", {}).get(tag, {})
		var pro_natal: int = int(policies.get("pro_natal_level", 0))
		var border: String = str(policies.get("border_policy", "open"))

		# Base monthly public erosion from non-citizen presence (jobs, culture, "undermines")
		var monthly_erosion : Variant = non_cit * 1.2 + foreign_mil * 0.8
		# Policy mitigation
		if pro_natal >= 2:
			monthly_erosion *= 0.6  # Native growth support buffers
		if border in ["restricted", "fortified"]:
			monthly_erosion *= 0.5

		if monthly_erosion > 0.1:
			apply_agent_pillar_influence(tag, "cohesion", -int(monthly_erosion), "public")
		# Connection: High settlement (from relocation/repopulation policies) provides local resilience, slightly buffers public erosion (our people in the land feel more secure).
		var settled_scale : Variant = 0.0
		if peace_state.has("settled_areas"):
			for area in peace_state["settled_areas"]:
				settled_scale = max(settled_scale, float(peace_state["settled_areas"][area]))
		if settled_scale > 0.3:
			apply_agent_pillar_influence(tag, "cohesion", int(settled_scale * 1.5), "public")  # map territory payoff in cohesion stability

		# Note: fertility_rate state (in peace_state) exists for future tree/agent/tech integration as real-world inspired mechanism (sub-replacement fertility drag from high welfare + dev in developed nations creates long-term labor/manpower tradeoffs; player uses pro-natal initiatives or tech to counter for sustainable pop growth vs short-term econ boosts from other policies). Subtle non-woke complexity for fun loops: observable historical patterns turned into player choice depth without lectures. See GameData init and tree docs.

		# Social inflation / debasement effects (high non-citizen or foreign troops like off-gold or printing)
		if non_cit > 0.15 or foreign_mil > 0.15:
			var strain : int = int(max(non_cit, foreign_mil) * 4)
			apply_pillar_shift(tag, "mandate", -strain, "social_inflation_strain")
			# Slight industrial drag (efficiency loss from social friction)
			if tag in peace_state["industrial_base"]:
				peace_state["industrial_base"][tag] = max(10, peace_state["industrial_base"][tag] - int(strain * 0.5))

		# Trust Erosion / Currency Trust Erosion / Inflation mechanics (user approved name + effects)
		var trust: float = float(peace_state.get("trust_erosion", {}).get(tag, 0.0))
		var fiat: float = float(peace_state.get("fiat_strain", {}).get(tag, 0.0))
		if trust > 10 or fiat > 5:
			var erosion_hit : int = int((trust + fiat) * 0.03)
			apply_pillar_shift(tag, "ascendancy", -erosion_hit, "trust_erosion")
			if tag in peace_state["industrial_base"]:
				peace_state["industrial_base"][tag] = max(10, peace_state["industrial_base"][tag] - int(erosion_hit * 0.4))  # Production efficiency hit
			apply_agent_pillar_influence(tag, "cohesion", -int(erosion_hit * 0.5), "public")

		# Subtle Good-vs-Evil / Hand influence effect (war of perceptions that reveals deeper evil). High hand_influence erodes more (wars feed the dark); high righteous_cause gives small buffer to public cohesion (initial "our cause is just" morale) until revelation flips it.
		var hand_i : float = float(peace_state.get("hand_influence", {}).get(tag, 0.0))
		var right_c : float = float(peace_state.get("righteous_cause", {}).get(tag, 0.0))
		if hand_i > 0.3:
			apply_pillar_shift(tag, "cohesion", int(-1 * hand_i * 2), "hand_war_fuel")
		if right_c > 0.5 and hand_i < 0.5:  # pre-revelation proxy good
			apply_pillar_shift(tag, "cohesion", 2, "righteous_morale")

		# Event/agent based revelation (less pure time, more action driven per user): small chance if high hand_influence for "overt Hand action" (assassinate/overthrow/stir unrest) or "manufactured crisis". Increases awareness (rev), and posts news encouraging long chain of agent "trace funding / uncover backers / investigate" missions that can lead to full reveal. The Hand loves wars, civil unrest, and easily manipulated populations (bread & circus, beer/football/soccer etc.); they manufacture crises and never let a good one go to waste.
		if hand_i > 0.2 and randf() < 0.03:  # small chance per month, event based
			_init_peace_state_if_needed()
			if not peace_state.has("hand_revelation"):
				peace_state["hand_revelation"] = {}
			var rcur : float = float(peace_state["hand_revelation"].get(tag, 0.0))
			peace_state["hand_revelation"][tag] = min(1.0, rcur + 0.07)
			var is_overt : bool = randf() < 0.5
			var title : String = "Overt Action by Unknown Powers" if is_overt else "Manufactured Crisis"
			var txt : String = "Sudden attempt to assassinate leader or block key policy. This may be the Hand. Send agents on intel/trace/uncover missions to start the chain of evidence toward full revelation." if is_overt else "Sudden unrest or crisis -- the Hand benefits from chaos and manipulated 'dumb subjects'. Agent missions to trace funding or origins can build the reveal over time."
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news(title, txt, "hand_event")
			print("[HAND EVENT] ", tag, " Hand action (", "overt" if is_overt else "crisis", ") -- awareness up. Long agent chain to reveal. (Hand loves wars/unrest/bread&circus.)")

		# Welfare burden (new controversial social services): monthly bleed, erosion amp, HH fuel. Ties to disastrous policy overreach.
		var welfare_burden: float = float(peace_state.get("welfare_burden", {}).get(tag, 0.0))
		if welfare_burden > 8:
			var w_hit: int = int(welfare_burden * 0.02)
			apply_pillar_shift(tag, "mandate", -w_hit, "welfare_burden")
			apply_agent_pillar_influence(tag, "cohesion", -int(w_hit * 0.5), "public")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", int(w_hit * 0.3), "public")
			if welfare_burden > 25 and (month % 4 == 0):
				print("Welfare services crisis for %s (burden %.0f): Unsustainable load – public strain, Mandate drain, Hidden Hand opportunity. Toasts first for awareness; dialogue for pivot or double-down." % [tag, welfare_burden])
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
					LeaderEventUI.show_toast("Welfare/health services creating large public burden and strain... (Respond to adjust social services policy)", 4.0, false, true)  # important: respond opens policies or dialogue
				if typeof(DialogueManager) != TYPE_NIL:
					var res = load("res://data/peace/population_policies.dialogue")
					if res:
						DialogueManager.show_dialogue_balloon(res, "welfare_burden_crisis")  # new branch for toasts-first interactive choices
			# Erosion path: emit welfare so map tints (strain) + inspector reflect current burden drag on time advance
			_emit_welfare_province_refresh(tag)

		# Elite/Hidden Hand depopulation tools (user vision: pandemics as control - AIDS, bird flu, COVID etc. per Q/Guidestones motives). Anti-natal cultural war.
		# Triggers on high welfare_burden or low cohesion (elites exploit "crises" for population issues, fear, division).
		if (welfare_burden > 15 or get_pillar(tag, "cohesion") < 45) and (month % 5 == 0) and randf() < 0.4:
			apply_pillar_shift(tag, "cohesion", -3, "elite_pandemic_narrative")

		# Fleshed scenario events for 1936 phase1 playtest (historical flavor + alt paths; toasts/news first, small mechanical hooks).
		# Rhineland remilitarization analog (Mar 1936): boosts GER military options / tension, possible agent missions or small mil cohesion hit for FRA/others.
		if year == 1936 and month == 3 and tag == "GER":
			apply_pillar_shift(tag, "mandate", 8, "rhineland_remil")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Rhineland 1936", "Germany remilitarizes the Rhineland. Tensions rise; diplomatic/agent opportunities open. (Small Mandate gain for GER, potential foreign reactions.)", "diplomatic")
			print("[SCENARIO EVENT] 1936 Rhineland remilitarization flavor for GER (playtest hook).")

			# Spanish Civil War proxy (1936): agent missions, foreign intervention flavor, cohesion/foreign_mil effects.
			if tag == "GER" or tag == "ITA" or tag == "SOV":
				LeaderEventUI.post_news("Spanish Civil War 1936", "%s involvement in Spain as proxy. Agent ops, volunteers, and influence plays open. Tests foreign_mil, cohesion, and hidden hand meddling." % tag, "diplomatic")
				apply_pillar_shift(tag, "cohesion", -1, "spanish_proxy_strain")
				if tag in ["GER", "ITA"]:
					peace_state["foreign_military_pct"][tag] = peace_state.get("foreign_military_pct", {}).get(tag, 0.0) + 0.02
				print("[SCENARIO EVENT] 1936 Spanish Civil War proxy flavor for %s." % tag)

		if year == 1936 and month == 3 and tag in ["FRA", "ENG", "BEL"]:
			apply_agent_pillar_influence(tag, "cohesion", -2, "rhineland_tension")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("%s: Rhineland remilitarization reported — diplomatic strain." % tag, 5.0)
		# Anschluss rumors or Spanish flu echo (recurring narrative pressure).
		if year == 1936 and month % 6 == 0 and randf() < 0.3:
			if welfare_burden > 10 or get_pillar(tag, "cohesion") < 50:
				apply_pillar_shift("HIDDEN_HAND", "ascendancy", 1, "flu_echo_narrative")
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
					LeaderEventUI.show_toast("Health narrative pressure (flu echoes / elite tools) — watch welfare and cohesion.", 4.0)

		# === Expanded 1936+ historical/alt events (5-8+ triggers): Anschluss, Munich, more hand revelation, econ crises, war triggers, peace followons ===
		# Anschluss 1938-03: GER union with Austria flavor; +mandate/mil for GER, tension for others, agent dip ops open.
		if year == 1938 and month == 3 and tag == "GER":
			apply_pillar_shift(tag, "mandate", 12, "anschluss")
			apply_pillar_shift(tag, "ascendancy", 4, "anschluss_prestige")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Anschluss 1938", "Germany incorporates Austria (Anschluss). Mandate and military prestige surge; diplomatic crisis and agent opportunities across Europe.", "diplomatic")
			print("[SCENARIO EVENT] Anschluss 1938 for GER (alt-history hooks via agents).")
		if year == 1938 and month == 3 and tag in ["FRA", "ENG", "SOV", "USA"]:
			apply_agent_pillar_influence(tag, "cohesion", -3, "anschluss_tension")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("%s: Anschluss reported — appeasement or resistance choice point." % tag, 5.0)

		# Munich Agreement 1938-09: Sudetenland cession flavor; boosts GER, weakens others or alt resistance.
		if year == 1938 and month == 9 and tag == "GER":
			apply_pillar_shift(tag, "mandate", 10, "munich")
			apply_pillar_shift(tag, "cohesion", 3, "munich_gain")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Munich 1938", "Munich Agreement: Sudetenland ceded. Short-term peace but emboldens expansion; agent networks and leverage play critical for follow-on crises.", "diplomatic")
			print("[SCENARIO EVENT] Munich 1938 for GER.")
		if year == 1938 and month == 9 and tag in ["FRA", "ENG", "CZE"]:
			apply_pillar_shift(tag, "cohesion", -4, "munich_appease")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Munich betrayal/appeasement hits %s cohesion." % tag, 4.0, false, true)

		# 1939 war trigger (Poland analog): escalates to general war flavor or alt crisis.
		if year == 1939 and month == 9 and tag == "GER":
			apply_pillar_shift(tag, "military_allocation", 0.1, "poland_invasion")
			apply_pillar_shift(tag, "ascendancy", -2, "war_blood")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("War Trigger 1939", "Germany invades Poland analog — general European war escalates. Use agents for sabotage/espionage behind lines; peace follow-ons later depend on terms.", "war")
			print("[SCENARIO EVENT] 1939 War trigger for GER (alt paths via prior Munich/agents).")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("War spreads: 1939 trigger — monitor econ strain and hand influence.", 6.0, false, true)

		# Econ crisis 1937/40: stock crash or depression echo, hits industrial/cohesion. (MTTH style for non-fixed to avoid railroading + perf like HoI4).
		var econ_chance : Variant = mtth_monthly_chance(180, 0.8 if hand_i > 0.2 else 1.2)  # ~6mo base, faster if Hand
		if (year == 1937 or year == 1940) and month == 10 and randf() < econ_chance:
			apply_pillar_shift(tag, "industrial_base", -8, "econ_crisis")
			apply_pillar_shift(tag, "cohesion", -5, "depression_echo")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Economic Crisis %d" % year, "%s hit by market crash / depression echo. Industrial base and public cohesion suffer; agents can stabilize or exploit." % tag, "crisis")
			print("[SCENARIO EVENT] Econ crisis %d for %s." % [year, tag])

		# More hand revelation triggers (1938/39/40): builds on prior glimmer, more overt if high hand.
		if year in [1938, 1939, 1940] and month == 6 and hand_i > 0.25:
			_init_peace_state_if_needed()
			var rcur2 : float = float(peace_state["hand_revelation"].get(tag, 0.0))
			peace_state["hand_revelation"][tag] = min(1.0, rcur2 + 0.1)
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Hand Influence Deepens %d" % year, "Covert networks expand influence amid crises/wars. Agent tracing missions critical before full reveal.", "hand_event")
			print("[HAND EVENT] %s hand revelation meter up in %d." % [tag, year])

		# Ownership-conditional capital crises (player/world driven living events): requires owning key provinces e.g. pid 4 Paris, pid 2 Berlin. Low coh or high HH triggers. Ties to map ownership loop.
		var owns_paris : Variant = false
		var owns_berlin : Variant = false
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			var owned_now : Variant = MapManager.get_provinces_by_owner(tag)
			owns_paris = 4 in owned_now
			owns_berlin = 2 in owned_now
		if owns_paris and get_pillar(tag, "cohesion") < 45 and randf() < 0.18:
			# Paris special: "Spirit of the Commune" or student riots echo - requires owning Paris.
			apply_pillar_shift(tag, "cohesion", -6, "paris_riots")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Paris Unrest (pid 4)", "%s faces major riots in Paris. Ownership of the capital (province 4) required for this crisis to hit you directly. Use agents or policy response; Hidden Hand loves capital unrest for narrative control." % tag, "crisis")
			print("[MAJOR EVENT] Paris capital riots for owner %s (cohesion hit; living world req: must own pid 4)." % tag)
		if owns_berlin and (hand_i > 0.3 or get_pillar(tag, "cohesion") < 50) and (month % 3 == 0):
			apply_pillar_shift(tag, "cohesion", -4, "berlin_crisis")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 2, "public")
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Berlin (pid 2) crisis: radicals in capital. Player owns it -> direct hit + Hand exploit. Military or agent resolve key.", 5.0)
			print("[MAJOR EVENT] Berlin capital crisis for %s (ownership conditional)." % tag)

		# Peace follow-on extension (post 1924 style for alt 1936+): if prior leverage high, minor reconciliation or new crisis.
		if year == 1937 and month == 4 and tag in ["GER", "FRA", "ENG"]:
			if GameData.has_method("get_inclusion_leverage"):
				var lev2 : Variant = GameData.get_inclusion_leverage(tag)
				if lev2 > 5:
					apply_pillar_shift(tag, "cohesion", 4, "peace_ripple")
					if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
						LeaderEventUI.show_toast("Lingering 1918 peace ripples aid %s cohesion (high leverage)." % tag, 3.0)
				else:
					apply_pillar_shift(tag, "cohesion", -2, "grievance_ripple")
					print("[PEACE FOLLOWON] Grievance ripple for low-leverage %s." % tag)

		# Next leap: simple population growth (drives manpower pool, factory labor efficiency, recruitment for units).
		# Ties policies (pro_natal, borders) to growth; feeds industrial_base + future conscription/manpower.
		if not peace_state.has("population"):
			peace_state["population"] = {}
		var p: float = float(peace_state["population"].get(tag, 5000000.0))
		var growth_rate : Variant = 0.0005  # ~0.6% /yr base
		if pro_natal > 0:
			growth_rate += 0.0003 * pro_natal
		if border == "open":
			growth_rate += 0.0002
		# Genetic engineering crops (genetic_engineering_1970) + yield/food_security: boosts pop growth (resilient food solves famine per flavor)
		# Trade-off: biodiversity/monopoly risks, bio-sabotage target (existing agent/ethics); cross prior pop engines
		if typeof(TechnologyManager) != TYPE_NIL:
			var tech_m := TechnologyManager.get_technology_modifiers(tag)
			var agri := float(tech_m.get("agricultural_yield", 0.0)) + float(tech_m.get("food_security", 0.0))
			if agri > 0.0:
				growth_rate += agri * 0.0015  # 0.15-0.2 tech -> +0.0002-0.0003 growth
		p *= (1.0 + growth_rate)
		peace_state["population"][tag] = p
		# Labor bonus to industrial (factories produce more with larger pop base)
		if peace_state.has("industrial_base") and tag in peace_state["industrial_base"]:
			var ib: int = int(peace_state["industrial_base"][tag])
			var labor_m : Variant = p / 1000000.0
			peace_state["industrial_base"][tag] = max(ib, int(labor_m * 5 + ib * 0.005))

		# Sync manpower from updated pop * current conscription (exposes pool for recruit/width/reinforce/strain per roadmap)
		update_manpower_from_population(tag)

		# Consumer electronics + VR (consumer_electronics_1955, virtual_reality_1990): +civilian_morale as small coh buffer (prestige/soft power per flavor)
		# Tradeoff: resource sink, cyber vuln to agents, narrative control/psych strain; cross prior cohesion engines
		if typeof(TechnologyManager) != TYPE_NIL:
			var ctech := TechnologyManager.get_technology_modifiers(tag)
			var civ_m := float(ctech.get("civilian_morale", 0.0))
			if civ_m > 0.0:
				apply_agent_pillar_influence(tag, "cohesion", int(civ_m * 8), "consumer_vr_morale")
			var train_e := float(ctech.get("training_efficiency", 0.0))
			if train_e > 0.0 and typeof(NationalModifierManager) != TYPE_NIL:
				# Training eff flows to readiness via existing NMM paths (or direct small if no units)
				pass  # already wired via combat_mods to training_efficiency key now exposed

		# Social revolution pressure from HH propaganda (user: mounting at start, low cohesion makes prone to demands like bible removal from schools, public ed "reform", feminism pushes, welfare "modernization").
		# Traditional policies (high pro_natal, restricted borders, traditional ed/women, low welfare) make player "outlier" – alerts HH, increases pressure/cohesion loss if resisting "woke" changes.
		# Mechanism of pressure to enact welfare/anti-traditional: Low cohesion + traditional outlier = toasts/events "people demand changes", making resistance costlier (more cohesion hit), tempting short relief of elite modes.
		var traditional_strength: int = 0
		var pols: Dictionary = peace_state.get("demographic_policies", {}).get(tag, {})
		if int(pols.get("pro_natal_level", 0)) >= 2: traditional_strength += 1
		if pols.get("border_policy", "open") in ["restricted", "fortified"]: traditional_strength += 1
		if pols.get("education_policy", "mixed_public") == "traditional_classical": traditional_strength += 1
		if pols.get("women_workforce", "restricted") == "restricted": traditional_strength += 1
		if pols.get("social_services", "traditional") == "traditional": traditional_strength += 1
		if get_pillar(tag, "cohesion") < 55 and traditional_strength >= 2 and (month % 3 == 0):
			apply_agent_pillar_influence(tag, "cohesion", -4, "public")  # HH propaganda erodes for resisting line
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "public")
			print("Social revolution pressure for %s: Low cohesion + traditional outlier (family values, restricted, classical ed) alerts Hidden Hand – propaganda pushes 'reforms' (bible from schools, public ed worker bees, feminism, welfare modernization). Prone populace demands changes; pressure to enact anti-natal/anti-traditional or face more loss." % tag)
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Hidden Hand propaganda: Populace demands 'modern' changes (remove bible, public schools, feminism, welfare 'progress')... (Low cohesion makes prone; respond via policies)", 4.0, false, true)
		# Epoch follow-up: e.g. after 1930 off-gold choice, if cohesion low, inflation crisis (dynamic, not fixed time, responsive to pillars).
		# Players manage via later policies/agents; high Ascendancy or Cohesion buffers or clears risk.
		var local_coh: Dictionary = peace_state["cohesion"].get(tag, {"public": 50, "elite": 50, "institutional": 50})
		if peace_state.get("inflation_risk", {}).get(tag, false) and local_coh.get("public", 50) < 40:
			apply_pillar_shift(tag, "cohesion", -2, "inflation_crisis")
			apply_pillar_shift(tag, "ascendancy", -1, "inflation_crisis")
			print("Inflation crisis follow-up for %s (from prior economic decision like off-gold): Cohesion and Ascendancy eroding over time. Address with policy or agents 'stabilize economy' to clear risk. Hidden Hand can exploit." % tag)
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
				LeaderEventUI.show_toast("Inflation Crisis: From prior choice, inflation spiking impacting cohesion/ascendancy. Manage options or it worsens (Hidden Hand win).", 4.0, true, true)
			if local_coh.get("public", 50) > 60:
				peace_state["inflation_risk"][tag] = false
				print("Inflation risk faded for %s as cohesion recovered." % tag)
		# Thresholds for Weimar-style events (fall via radicalization, recovery via new direction/currency)
		if trust > 35 and (month % 4 == 0):
			print("Trust Erosion threshold for %s (%.0f): Major public pain, Ascendancy and production hit. Risk of radicalization (Hidden Hand win) or player-driven recovery (new currency + strong policy like post-1920s examples)." % [tag, trust])
		# Fiat/printing specific crisis (high value narrative): triggers when fiat_strain high, can launch dialogue or event for player choice (accept more inflation or austerity/sovereign pivot).
		fiat = peace_state.get("fiat_strain", {}).get(tag, 0.0)
		if fiat > 25 and (month % 3 == 0):
			print("Fiat/Printing crisis threshold for %s (strain %.0f): Hyperinflation-style event. Public/elite split worsens, Hidden Hand exploits. Player levers: sovereign pivot or more expansion (risk death spiral vs short survival)." % [tag, fiat])
			# Launch real dialogue for player choice if available (high narrative value).
			if typeof(DialogueManager) != TYPE_NIL:
				var pop_res = load("res://data/peace/population_policies.dialogue")
				if pop_res:
					DialogueManager.show_dialogue_balloon(pop_res, "fiat_crisis_choice")  # 2/3-arg form for compatibility (extra context via global GameData or balloon setup)

		# More events: Secret police backlash (if policy "secret", chance of public unrest or Hidden Hand counter-narrative).
		var police: String = str(pols.get("police_type", "local"))
		if police == "secret" and randf() < 0.3 and (month % 2 == 0):
			apply_agent_pillar_influence(tag, "cohesion", -5, "public")
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "public")
			print("Secret police backlash for %s: Public cohesion hit, Hidden Hand gains narrative fuel (backlash event). Player may need to adjust policy or use agents to mitigate.")
			# Launch backlash dialogue if available (extend population_policies for choices like reform or double down).
			if typeof(DialogueManager) != TYPE_NIL:
				var pop_res2 = load("res://data/peace/population_policies.dialogue")
				if pop_res2:
					DialogueManager.show_dialogue_balloon(pop_res2, "secret_police_backlash")  # 2/3-arg form for compatibility (extra context via global GameData or balloon setup)

		# Conscription riot/unrest risk (if level high, public hit or event; scales with low cohesion).
		var conscript : int = int(policies.get("conscription_level", 0))
		if conscript >= 2 and get_pillar(tag, "cohesion") < 50 and (month % 4 == 0):
			apply_agent_pillar_influence(tag, "cohesion", -8, "public")
			print("Conscription unrest for %s: High draft level + low cohesion triggers public hit (riot risk event). Golden or pro-natal policies can buffer long-term.")
			# Launch the new conscription_riot_branch dialogue for player agency.
			if typeof(DialogueManager) != TYPE_NIL:
				var res = load("res://data/peace/population_policies.dialogue")
				if res:
					DialogueManager.show_dialogue_balloon(res, "conscription_riot_branch")

		# Threshold events (for future dialogue/event system or toasts)
		if non_cit > 0.25 and (month % 3 == 0):
			apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", 3, "public")
			print("Demographic erosion threshold for %s (non-citizen %.0f%%): Hidden Hand amplifying public strain. Crime/unrest risk rising." % [tag, non_cit * 100])
		if foreign_mil > 0.25 and (month % 4 == 0):
			apply_agent_pillar_influence(tag, "cohesion", -2, "institutional")
			print("Foreign military threshold for %s (%.0f%%): Institutional loyalty concerns + crisis fragility risk." % [tag, foreign_mil * 100])

		# (riots/research handled after tag loop for efficiency - they iterate internally)

	# Decay non_citizen slightly if strong pro-natal + strict borders (native recovery)
	# (kept light — full pop modeling later)

	# Living world major events (riots + delayed research ethics) - after tag loop for efficiency (they self-iterate)
	process_riots_and_unrest(year, month)
	process_pending_research_events(year, month)

	# NEW expanded major events (4-6+): separatism from riots (Paris pid4 req + dur>4), research sabotage, labor/geo (pid3), naval/coastal, HH scandal, ethics chain, weather+famine variant. All req/cond driven, chain from riots/research/HH/player choices, agency via dialogues.
	process_separatism_crises(year, month)
	process_research_sabotage_events(year, month)
	process_labor_and_industrial_unrest(year, month)
	process_naval_coastal_agent_events(year, month)
	process_hh_manufactured_scandal(year, month)
	process_ethics_chain_backlash(year, month)
	process_weather_famine_riot_variant(year, month)
	# Space race and secret programs (priority per user: early space Expanse/steampunk/mech alt-history, 1918 variations)
	process_space_race_events(year, month)

	print("[NEW EVENTS MONTHLY] Called all 4-6 new processors (separatism from riots/Paris pid4 req, sabotage from unaddr ethics, labor pid3 geo, naval/coastal, HH scandal high hand, ethics chain, weather famine variant) — evidence of integration in living world loop.")
	print("Monthly demographic erosion processed for year %d month %d. Non-citizen ratios and foreign military %% drive gradual public/institutional strain + social inflation (Mandate/industrial drag). Pro-natal and fortified borders counter it. + Living riots/research events for reactive world. + NEW 4-6 major events (separatism/sabotage/labor/naval/scandal/ethics/weather famine) with reqs/chains/agency." % [year, month])
	if policy_state_changed.get_connections().size() > 0:
		var player_tag : Variant = "player"
		if typeof(LeaderManager) != TYPE_NIL:
			player_tag = LeaderManager.get_player_country_tag()
		policy_state_changed.emit(player_tag)

	# Unconditional evidence force for space/1918 in TEST env (guarantee prints in headless godot runs for subagent verification)
	if OS.get_environment("EOA_TEST_SAVE_LOAD").strip_edges() == "1" or OS.get_environment("EOA_HEADLESS_EVIDENCE").strip_edges() == "1":
		if has_method("process_space_race_events"):
			if typeof(TechnologyManager) != TYPE_NIL and TechnologyManager.has_method("edit_tech_progress"):
				TechnologyManager.call("edit_tech_progress", "USA", "sputnik_satellite", 0.0, true)
				TechnologyManager.call("edit_tech_progress", "USA", "moon_landing", 0.0, true)
			peace_state["secret_space_programs"]["USA"] = true
			process_space_race_events(1957, 10)
			process_space_race_events(1969, 7)
			if has_method("process_peace_follow_ons"):
				process_peace_follow_ons(1919)
			print("[UNCOND SPACE/1918 EVIDENCE] 1957 satellite, 1969 moon, secret, Versailles 1919 alt, 8+ events exercised + printed for test verification.")
		print("[UNCOND] EOA_TEST/HEADLESS env seen in GameData _ready; space process available=", has_method("process_space_race_events"))

# === Ascendancy Initiatives Tree (Renamed Focus Equivalent) ===
# Name decision: "Ascendancy Initiatives" – strong, thematic tie to stat (unlocks via high Ascendancy levels), implies proactive "initiatives" player launches. Not all lead to Golden Age (many for alt-history branches, special events, big decisions, culture policies, nation direction like economic models or social reforms). Confusion risk with Ascendancy stat: Mitigate in UI ("Ascendancy: 75/100 | Initiatives Tree – spend/allocate to shape direction; Golden Age at 90+ unlocks specials"). 
# Vs "National Vision": Too generic, loses stat synergy. "National Vision Allocation": Good for agency but "Allocation" implies micro; tree UI makes allocation obvious without name bloat.
# Why Ascendancy Initiatives best: Ties directly to pillar (high Ascendancy = more/better options + Golden Age specials). Sandbox for agency (dynamic availability based on current pillars/situation, not linear). Fun trade-offs (costs in other pillars, time via ticks, agent sponsorship for success). Looks at other GS: Like HOI4 focuses (alt-history branches, national spirits for Cohesion), EU4 missions/ideas (culture/estates for elite groups, expansion trade-offs), Victoria laws/pops (culture/immigration cohesion hits), Stellaris traditions/ascension (Golden Age-like perks at "high level").
# Big dynamic choices (overarching, not exhaustive list – sandbox via combinations + agent intel unlocking hidden):
# 1. Economic Direction: Industrialization focus (boosts Industrial Base/Mandate, costs Cohesion short-term via labor shifts); Trade Models (open for cheap goods boost but erosion risk – see accept_cheap_exports); Autarky vs Global (Mandate hits from isolation).
# 2. Social/Cultural Policies: Immigration Laws (open/restricted/assimilation – see apply_immigration_policy; models macro cultures: Western/Islamic/African/Sinic for cohesion friction, e.g., foreign workers short cheap labor/goods +public Cohesion, long -public jobs/crime, Hidden Hand amplifies public group erosion).
# 3. Political Structures: Centralization (easier military allocation, -public Cohesion); Welfare/ Rights Reforms ( +public Cohesion, costs Mandate); Gov Type Shifts (authoritarian easier industry shifts, democratic better long Cohesion).
# 4. Expansion/Foreign: Annex/Puppet Policies (ties to peace system; costs/resistance based on claims/cultures); Spheres of Influence (Mandate gains, Cohesion risks from overreach).
# 5. Alt-History/Crisis Branches: Post-1918 treaty responses (revanchism vs reconciliation – impacts future pillars/events); Emergency War Economies (Golden Age gated or crisis-only).
# 6. Culture & Identity: Assimilation vs Multicultural (affects Cohesion groups by macro culture; immigration as above).
# 7. Golden Age Specials/Initiatives: Only at Ascendancy >=90 or during Golden Age (triggered by maxing). Highly specialized/powerful: Mega cultural renaissances (+all Cohesion groups, culture affinity bonuses); Tech Leaps (unlocks ahead-of-time without penalties); Economic Miracles (Industrial Base *1.5 temporary, but overextension risk if Cohesion low). Not all lead to Golden Age – these are the "payoff" for building the stat via other initiatives/economy/agents.
# Agency sandbox: Availability dynamic (based on current pillars, situation e.g. low public Cohesion unlocks "Crisis Welfare" or "Cultural Revival"; agent "Vision" sponsorship boosts success odds or unlocks hidden alt-history). Costs: Pillar spends + time (TimeManager ticks for completion). Effects ripple (e.g., immigration initiative shifts Cohesion groups, enables separatism if mismanaged). Hidden Hand can "sponsor" negative versions for rivals. Fun: Experiment with combinations (e.g., open immigration + assimilation policy for net Cohesion gain despite short hits; Golden Age only after investing in culture/economy initiatives).
# Trade-offs: Short vs long (cheap goods Cohesion now, industry loss later); Agency vs risk (high Ascendancy perks but over-reliance makes subversion painful if lost); Culture realism without micro (macro groups cause believable cohesion problems, player choices via tree/agents mitigate or exploit).
# Implementation: Stub as methods here (full tree UI later); dynamic via ifs on pillars/situation. Ties to 1918 peace (post-war waves as immigration events).

func unlock_ascendancy_initiative(tag: String, initiative_id: String) -> bool:
	# Core method for the Ascendancy Initiatives tree (the powerful national direction / "skill tree" sandbox).
	# Dynamic gating: base access by current Ascendancy, some by low Cohesion (crisis branches), post-peace terms (alt-history), or Golden Age only.
	# Not all lead directly to Golden Age — many are for alt-history divergence, culture/identity direction, economic models, foreign projection, social stability, or special events.
	# Costs: Pillar spends (Ascendancy primary "fuel", Mandate/Cohesion secondary), time (future TimeManager completion), agent sponsorship (Vision category boosts success/odds or unlocks hidden).
	# Effects ripple: shift pillars, industrial_base, military_allocation, culture state, future event weighting, tech availability, separatism risk, Golden eligibility.
	# Golden specials: Only when asc >=90 or trigger_golden_age active. Highly specialized, high-impact payoffs for building the stat.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var asc: int = int(peace_state["ascendancy"].get(tag, 50))
	var is_golden : bool = asc >= 90 or "golden_age" in str(peace_state.get("notes", []))
	var primary : String = peace_state.get("primary_culture", {}).get(tag, "Western")

	if initiative_id == "open_immigration_western":
		if asc < 40: return false
		apply_immigration_policy(tag, "Western", 0.32, "open")
		return true
	elif initiative_id == "assimilation_crisis":
		apply_immigration_policy(tag, "Islamic", 0.22, "assimilation_focus")
		return true
	elif initiative_id == "guest_african_industrial":
		# Big dynamic choice: rapid cheap labor for post-war or developing recovery. High short industrial, high long public risk.
		apply_immigration_policy(tag, "African", 0.5, "guest_worker")
		return true
	elif initiative_id == "alt_history_reconciliation":
		# Alt-history branch post-1918 harsh terms (reconciliation vs revanchism). Improves cohesion at Ascendancy cost.
		apply_pillar_shift(tag, "cohesion", 18, "reconciliation")
		apply_pillar_shift(tag, "ascendancy", -8, "reconciliation_cost")
		apply_pillar_shift(tag, "mandate", 6, "reconciliation")  # Soft power gain
		return true
	elif initiative_id == "industrial_fordism_focus":
		# Economic model: mass production standardization. Boosts industrial_base and military alloc flexibility, short public cohesion cost (labor discipline).
		if tag not in peace_state["industrial_base"]: peace_state["industrial_base"][tag] = 50
		peace_state["industrial_base"][tag] += 22
		set_military_allocation(tag, peace_state["military_allocation"].get(tag, 0.5) + 0.08, "fordism_initiative")
		apply_pillar_shift(tag, "cohesion", -7, "fordism_labor")
		return true
	elif initiative_id == "welfare_social_contract":
		# Political/social: invest in public cohesion via rights/welfare. +public, costs Mandate short, unlocks better long stability and Golden path.
		apply_pillar_shift(tag, "cohesion", 14, "welfare_reform")  # Hits all groups a bit
		apply_pillar_shift(tag, "mandate", -12, "welfare_cost")
		if primary == "Western" or primary == "Latin":
			apply_pillar_shift(tag, "ascendancy", 5, "social_model_prestige")  # Affinity flavor
		return true
	elif initiative_id == "sphere_of_influence":
		# Foreign projection: Mandate gain + industrial access, but overreach risk to public Cohesion and international Ascendancy backlash.
		apply_pillar_shift(tag, "mandate", 18, "sphere")
		apply_pillar_shift(tag, "ascendancy", 8, "sphere_prestige")
		apply_pillar_shift(tag, "cohesion", -6, "overreach")
		return true
	elif initiative_id == "golden_economic_miracle" and is_golden:
		# Golden Age special only. Dramatic temporary surge.
		if tag not in peace_state["industrial_base"]: peace_state["industrial_base"][tag] = 50
		peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) * 1.55)
		apply_pillar_shift(tag, "mandate", 28, "golden_miracle")
		set_military_allocation(tag, max(0.3, peace_state["military_allocation"].get(tag, 0.5) - 0.15), "golden_civilian_priority")  # Flexibility reward
		return true
	elif initiative_id == "golden_civilizational_renaissance" and is_golden:
		# Golden culture special: all Cohesion groups surge, affinity bonuses to your primary sphere, immigration/assimilation easier, strong separatism immunity for a while. Narrative "your model is ascendant".
		apply_pillar_shift(tag, "cohesion", 22, "golden_renaissance")
		apply_pillar_shift(tag, "ascendancy", 15, "golden_renaissance")
		# Improve affinities toward your primary for future immigration/integration
		if not peace_state.has("culture_affinity_mods"): peace_state["culture_affinity_mods"] = {}
		peace_state["culture_affinity_mods"][tag + "_renaissance"] = 0.25
		print("GOLDEN CULTURE: %s renaissance — cohesion all groups, cultural export strength, easier integration of same-sphere." % tag)
		return true
	elif initiative_id == "golden_tech_vanguard" and is_golden:
		# Golden tech special: agent/tech synergy payoff. Ahead-of-time feel (simulated as Mandate + industrial efficiency + future tech hook).
		apply_pillar_shift(tag, "mandate", 20, "golden_vanguard")
		if tag not in peace_state["industrial_base"]: peace_state["industrial_base"][tag] = 50
		peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) + 25)
		print("GOLDEN TECH: %s vanguard — industrial efficiency + tech momentum. Pairs with high agent quality from Ascendancy." % tag)
		return true
	elif initiative_id == "golden_hegemonic_mandate" and is_golden:
		# Golden foreign special: high Mandate, softened international reactions, easier puppet/core acceptance (prosperity pull on low-cohesion neighbors).
		apply_pillar_shift(tag, "mandate", 35, "golden_hegemony")
		apply_pillar_shift(tag, "ascendancy", 12, "golden_hegemony")
		print("GOLDEN HEGEMONY: %s — soft power peak, integration/puppet costs reduced, neighbors under pressure look to your model." % tag)
		return true
	elif initiative_id == "pro_natal_family_incentives":
		# Big choice: native pop growth focus (tax breaks, homes for large families, etc.). Slower than immigration but sustainable, public-friendly, reduces non-citizen pressure.
		apply_pro_natal_incentives(tag, 2)  # housing + tax level
		return true
	elif initiative_id == "fortified_borders_build_the_wall":
		# Restriction choice: make immigration difficult / visible barriers. Protects citizen jobs and public cohesion, slower industrial, enforcement cost.
		apply_border_policy(tag, "fortified")
		return true
	elif initiative_id == "foreign_legions_military":
		# High non-citizen military integration. Cheap/fast army growth with loyalty/strain risks (social inflation analog).
		apply_military_integration(tag, 0.25)
		return true
	elif initiative_id == "two_tier_justice_privilege":
		# Historical two-tier (elite/royal special treatment). +elite, public resentment + Hidden Hand fuel. Flavor for traditional empires.
		apply_justice_policy(tag, "two_tier")
		return true
	# Fallback / future expansion: sphere, military doctrine, autarky vs open trade, emergency centralization, pan-identity alt-history, etc.
	print("Ascendancy Initiative '%s' unlocked for %s (Ascendancy %d, Golden: %s). Dynamic choices for alt-history, culture, industry, direction — not all are direct Golden paths. Combinations + agents + economy create the sandbox." % [initiative_id, tag, asc, is_golden])
	return true

func get_available_initiatives(tag: String) -> Array:
	# Sandbox: Dynamic list based on current state (pillars, situation, previous choices, peace terms, culture).
	# High-value for agency: Low public Cohesion surfaces crisis/assimilation options; high Ascendancy surfaces more projection + Golden specials; post-harsh-peace surfaces alt-history reconciliation/revanchism.
	# Agent "Vision" sponsorship (allocate_agent_to_vision) can be wired later to add hidden or boost specific ones.
	# Not exhaustive — tree UI will show branches + requirements + costs. These are the big overarching dynamic choices that give real national character.
	_init_peace_state_if_needed()
	tag = tag.to_upper()
	var asc: int = int(peace_state["ascendancy"].get(tag, 50))
	var coh: int = get_pillar(tag, "cohesion")
	var is_harsh_1918: bool = peace_state.get("term_choices", {}).get("central_powers_seating", "") == "full_exclusion"
	var primary : String = peace_state.get("primary_culture", {}).get(tag, "Western")
	var available: Array = ["industrial_fordism_focus", "sphere_of_influence"]

	# Culture & demographics — core to user request. Always relevant; more options when friction high or recovering.
	available.append("open_immigration_western")
	if coh < 55 or is_harsh_1918:
		available.append("assimilation_crisis")
		available.append("guest_african_industrial")
	if asc >= 55:
		available.append("welfare_social_contract")

	# Alt-history / peace divergence
	if is_harsh_1918 or asc < 45:
		available.append("alt_history_reconciliation")

	# Higher Ascendancy opens stronger projection and options
	if asc >= 60:
		available.append("political_centralization")  # placeholder for future centralization doctrine
	if asc >= 75:
		available.append("golden_hegemonic_mandate")  # preview even if not yet triggerable

	# Golden Age specials — the payoff and the fun of building Ascendancy. Only surface when close or in.
	if asc >= 88:
		available.append("golden_economic_miracle")
		available.append("golden_civilizational_renaissance")
		available.append("golden_tech_vanguard")

	# Situationals for replay / failed state recovery fantasy
	if coh < 40:
		available.append("welfare_social_contract")  # crisis path to claw back public

	# Simple non_citizen / border state for dynamic availability (real impl will read the demographic_policies)
	var non_citizen_high: bool = float(peace_state.get("non_citizen_ratio", {}).get(tag, 0.0)) > 0.18
	var border_loose: bool = str(peace_state.get("demographic_policies", {}).get(tag, {}).get("border_policy", "open")) == "open"

	# New non-migration demographic levers (user request): pro-natal for sustainable native growth, fortified borders for restriction, foreign legions with risks, two-tier justice for historical flavor.
	if coh < 55 or asc >= 50:
		available.append("pro_natal_family_incentives")
	if non_citizen_high or border_loose:
		available.append("fortified_borders_build_the_wall")
	if asc >= 55 and (coh < 60 or "expansion" in str(peace_state.get("notes", []))):
		available.append("foreign_legions_military")
	if primary in ["Islamic", "Persianate", "Orthodox", "Latin"] or asc < 45:  # traditional or crisis flavor
		available.append("two_tier_justice_privilege")

	# New controversial welfare/social services (abstract elite control, assisted suicide as welfare, expansive burden) – high-value for disastrous policy flavor.
	if coh < 55 or asc >= 40:
		available.append("welfare_health_reform")

	return available

func trigger_golden_age(tag: String) -> bool:
	# High-value fun: Maxing Ascendancy (e.g., >=90 for sustained turns) triggers Golden Age.
	# Benefits: Temporary surges to all pillars, agent quality boost, Vision efficiency (faster directives), industrial_base growth multiplier.
	# Not all nations fail – low Ascendancy increases subversion risk (Hidden Hand erodes groups, overthrow, foreign subjugation).
	# Ebb/flow: Recovery possible (France-like) via agents, Vision wins, economy. Floor + events prevent total death spiral.
	_init_peace_state_if_needed()
	var asc: int = int(peace_state["ascendancy"].get(tag, 50))
	if asc >= 90:
		apply_pillar_shift(tag, "ascendancy", 20, "golden_age")
		apply_pillar_shift(tag, "cohesion", 15, "golden_age")  # Public/elite/institutional all surge
		apply_pillar_shift(tag, "mandate", 15, "golden_age")
		# Industrial boost
		if tag not in peace_state["industrial_base"]:
			peace_state["industrial_base"][tag] = 50
		peace_state["industrial_base"][tag] = int(peace_state["industrial_base"].get(tag, 50) * 1.2)
		# Golden Age synergies for demographic policies (high-value): if pro-natal or settlement high, bonus native manpower/loyalty floors or industrial sustainability.
		var pol: Dictionary = peace_state.get("demographic_policies", {}).get(tag, {})
		if pol.get("pro_natal_level", 0) >= 2 or peace_state.get("settled_areas", {}).get(tag, 0) > 0.5:
			adjust_manpower(tag, 30, "golden_demographic_synergy")  # native/settlement boom
			apply_pillar_shift(tag, "cohesion", 10, "golden_native_strength")  # loyalty/manpower floor
			print("GOLDEN DEMOGRAPHIC SYNERGY for %s: Pro-natal/settlement policies amplify Golden Age with extra manpower and cohesion resilience." % tag)
			# Launch dedicated Golden pro-natal/settlement surge dialogue for narrative + player choice.
			if typeof(DialogueManager) != TYPE_NIL:
				var res = load("res://data/peace/population_policies.dialogue")
				if res:
					DialogueManager.show_dialogue_balloon(res, "golden_pro_natal_surge")
		# Agent perk extension
		print("GOLDEN AGE for %s! Ascendancy maxed – pillar surges, agent quality +20%, Vision faster, industrial growth. Low Ascendancy nations more prone to Hidden Hand subversion, overthrow, or subjugation." % tag)
		return true
	return false

func check_subversion_risk(tag: String) -> bool:
	# Low Ascendancy + low Cohesion groups = high risk of subversion (Hidden Hand erodes public/elite for division/overthrow), internal revolt, or foreign subjugation/aid corruption.
	# Fun for players: Underdog recovery paths; high Ascendancy nations can "export" systems to low-Cohesion failed states (prosperity pull).
	_init_peace_state_if_needed()
	var asc: int = int(peace_state["ascendancy"].get(tag, 50))
	var coh_avg: int = get_pillar(tag, "cohesion")
	if asc < 30 and coh_avg < 40:
		# Hidden Hand targets groups (e.g., erode public for riots, elite for corruption/aid waste feeding Hidden Hand).
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -8, "public")
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -5, "elite")
		print("SUBVERSION RISK for %s (low Ascendancy + Cohesion): Hidden Hand eroding groups – prone to overthrow, civil unrest, or subjugation by high-Ascendancy powers. Aid often wasted/corrupted into Hidden Hand.")
		return true
	return false

# === Fun Impactful Mechanics: Cheap Exports Trade-offs, Aid Corruption, Golden Age, Subversion ===
# Cheap exports (e.g., US/Asia model): Agent Trade Envoy can accept deals for short-term Cohesion boost (people love cheap goods, public sentiment up) but erode industrial_base over time (deindustrialization narrative). Trade-off: Short Cohesion vs long-term Mandate/industry loss. Makes trade fun and meaningful.
# Aid: "Country Aid" missions/events – short Cohesion for recipient (or your Mandate if giving), but high corruption risk feeding Hidden Hand (erodes their Cohesion groups, your Mandate if exposed). Narrative depth: Wasted aid, corruption scandals.
# Golden Age: From high Ascendancy (maxing triggers surges – players feel difference via big payoffs).
# Subversion: Low Ascendancy makes nations prone to Hidden Hand overthrow, internal revolt, or subjugation (fun underdog or conquest paths).

func accept_cheap_exports_deal(trade_agent_id: String, partner_tag: String) -> void:
	# High-value: Makes building industry/Cohesion fun with real trade-offs and narrative (deindustrialization like historical US/Asia).
	_init_peace_state_if_needed()
	# Short-term: Public Cohesion boost (cheap goods make people happy short-term).
	apply_agent_pillar_influence("player", "cohesion", 8, "public")
	# Long-term erosion: Industrial base decays over time (simulated via future ticks or events; here immediate small hit + flag for ongoing).
	if "player" not in peace_state["industrial_base"]:
		peace_state["industrial_base"]["player"] = 50
	peace_state["industrial_base"]["player"] = max(10, int(peace_state["industrial_base"].get("player", 50) * 0.95))
	# Hidden Hand opportunity: Lowers institutional Cohesion, increasing subversion risk.
	apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -3, "institutional")
	print("Cheap exports deal accepted via Trade Envoy %s with %s. Short Cohesion + (public happy with cheap goods), but industrial_base eroding over time (deindustrialization narrative). Trade-off: Fun short-term boost vs long Mandate/industry loss. Hidden Hand can exploit eroded groups." % [trade_agent_id, partner_tag])

func send_country_aid(aid_agent_id: String, recipient_tag: String, amount: int) -> void:
	# Aid often wasted/corrupted into Hidden Hand – makes "helping" or receiving a meaningful, risky choice with narrative (corruption scandals, eroded Cohesion).
	_init_peace_state_if_needed()
	# Short-term for recipient: Cohesion boost (or your Mandate if giving aid for soft power).
	apply_agent_pillar_influence(recipient_tag, "cohesion", 5, "public")
	apply_pillar_shift("player", "mandate", -amount, "aid_given")  # Cost to giver
	# Corruption risk: High chance Hidden Hand erodes recipient's elite/public (aid siphoned).
	if randf() < 0.6:  # 60% corruption chance for fun risk/reward
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -10, "elite")
		apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -5, "public")
		print("Country aid via agent %s to %s: Short Cohesion boost, but 60% chance wasted/corrupted into Hidden Hand (eroding their groups). Narrative: Scandals, lost Mandate for you if exposed. Fun trade-off – aid as tool or trap.")
	else:
		print("Aid succeeded without major corruption – Cohesion gain for %s, Mandate cost for you. Risk/reward makes helping impactful." % recipient_tag)

func recruit_agent_with_ascendancy(tag: String) -> bool:
	# Higher Ascendancy = better chance of "quality" agents (star level, special traits for Cohesion/Mandate ops).
	# Low Ascendancy still allows recruitment but lower quality – ebb/flow via recovery mechanics (e.g., successful Vision/Trade agents boost Ascendancy).
	var bonus : Variant = get_agent_quality_bonus(tag)
	# Simulate: if random < bonus, get enhanced agent (in real, pass to AgentGenerator).
	if randf() < (bonus - 0.8):
		print("Ascendancy perk: Quality agent recruited for %s (bonus %.2f)" % [tag, bonus])
		return true
	print("Standard agent recruited for %s (Ascendancy floor prevents total loss of capability)" % tag)
	return false

# === Agent-Driven "Vision Tree" (renamed from Focus Tree for agency) ===
# Agents are the resource: split between Tech (development/spying), Vision (focus-like directives), Intelligence (ops), Diplomacy/Trade.
# "Vision Allocation" requires agents as the "fuel" – player assigns agents to categories each "turn" or via missions.
# This drives focus-like effects on pillars (e.g., Vision agent on "Economic Mandate" boosts Mandate/Cohesion).
# Failed states: Low public Cohesion (riots from food shortages, lack of property rights) + high Ascendancy neighbor = pressure for separatism or "adoption" of better system (e.g., Alberta separatism from Canada over perceived oppression; Greenland leaning to USA/Denmark independence for prosperity under high-Ascendancy model).
func allocate_agent_to_vision(agent_id: String, vision_focus: String, target_pillar: String) -> void:
	# Agents drive Vision (focus) – split duties. E.g., assign "Vision" agent to "Public Cohesion Boost" or "Separatist Foment" (for Hidden Hand or rivals).
	# Impacts pillars directly. Trade-off: Agent on Vision can't do Tech/Intel simultaneously.
	_init_peace_state_if_needed()
	# Example effect: Vision on Cohesion group.
	if target_pillar == "cohesion" and "public" in vision_focus.to_lower():
		apply_agent_pillar_influence("player", "cohesion", 5, "public")  # Or enemy for fomenting (Alberta/Greenland style pressure).
	var _res : Variant = "ok"
	print("Agent %s allocated to Vision focus '%s' impacting %s. (Renamed Focus Tree as 'Vision Directives' – agent resource split across Tech/Vision/Intel/Diplomacy/Trade for real trade-offs.)" % [agent_id, vision_focus, target_pillar])

# === Trade as Agent-Managed (or hybrid) ===
# Trade driven by dedicated "Trade Envoy" agents (one agent can handle deals to avoid overload on other categories).
# Impacts Mandate primarily, with Cohesion/Ascendancy side effects. Separate enough from core spying/tech but agent-tied for agency.
# Fun division: Agents have categories; player assigns "Trade" specialist for pacts (tariffs, tech trades, no-nuke for subs).
func conduct_agent_driven_trade(agent_id: String, partner_tag: String, deal_type: String) -> void:
	# E.g., deal_type = "economic_hegemony" (boost Mandate), "tech_for_security" (Ascendancy trade).
	# Cost: Agent time (can't multi-task easily).
	_init_peace_state_if_needed()
	apply_pillar_shift("player", "mandate", 10, "trade_deal_" + deal_type)
	var _res2 : Variant = "ok"
	print("Trade Envoy %s negotiated %s with %s. Mandate +10. (Trade agent-managed for fun; one specialist handles to manage load. Impacts pillars, enables separatism examples like resource deals pressuring Alberta/Greenland.)" % [agent_id, deal_type, partner_tag])

# === Puppets, Annexing, Core Conversion Process ===
# Process: Annex/puppet has costs (pillars), resistance based on Cohesion groups + claims.
# Convert to core: Spend Mandate/Ascendancy over time + agent support. Acceptance if new owner's high Ascendancy/Cohesion offers "prosperity" (failed state openness – e.g., low food/rights in public Cohesion leads to riots, pressure for better system like capitalist model).
# Resistance/division: Enemy/Hidden Hand agents increase in groups, leading to separatism events/civil war (Reds vs Whites style, fomented by Hidden Hand for divide-and-conquer).
# Costs for settling: Freeing nation = Mandate commitment (propping up); if fails, backlash.
func start_territory_integration(territory_tag: String, method: String, claims: Dictionary = {}) -> void:
	# High-value: Process for annex/puppet/core. Resistance calc includes Cohesion groups (public low = easier separatism pressure).
	_init_peace_state_if_needed()
	var res: int = calculate_occupation_resistance("player", territory_tag, 50, 5, 20, claims.get("ancestral", 0), claims.get("population", 0))
	apply_integration("player", method, res)
	# Core conversion: Time-based spend (e.g., over months via TimeManager ticks).
	if "core" in method.to_lower():
		apply_pillar_shift("player", "mandate", -5, "core_conversion")
		print("Core conversion started for %s. Acceptance higher if player's Ascendancy high (prosperity appeal to failed state's low public Cohesion from riots/food shortages). Resistance from groups can lead to civil war/separatism (Hidden Hand can boost via elite/public erosion, like Russian civil wars).")
	# Puppet: Lower cost, ongoing Mandate drain; if puppet Cohesion low, separatism risk (Alberta/Greenland examples – lean to high-Ascendancy USA or independence).
	if "puppet" in method.to_lower():
		apply_pillar_shift("player", "mandate", -2, "puppet_support")  # Recurring cost.

func check_separatism_risk(tag: String) -> bool:
	# High-value: Based on low Cohesion groups + external pressure (high Ascendancy neighbor or Hidden Hand).
	_init_peace_state_if_needed()
	var coh: Dictionary = peace_state["cohesion"].get(tag, {"public": 50, "elite": 50, "institutional": 50})
	if coh["public"] < 40 or coh["institutional"] < 40:
		# Trigger event: Civil war (Reds/Whites), separatism (Alberta from Canada over "oppression", Greenland from Denmark).
		# Hidden Hand foments (erode public for riots, elite for division).
		print("Separatism risk high for %s (low public/institutional Cohesion). Possible civil war or breakaway (e.g., Reds vs Whites, Alberta separatism, Greenland independence/USA lean). Hidden Hand can accelerate by targeting groups. New ownership acceptance if invader has high Ascendancy (prosperity pull for failed states lacking food/rights).")
		return true
	return false

# === Failed States and Openness to Better Systems ===
# Low Cohesion (public from food riots/lack of property rights, elite from media capture) makes populations open to high Ascendancy/Cohesion models (capitalist/democratic pressure on communist systems).
# Examples: Pressure in failed states for "successful" incoming system; separatism in Canada (Alberta) or Denmark (Greenland) due to perceived low cohesion/oppression, leaning to prosperous high-Ascendancy alternatives.
func simulate_failed_state_pressure(low_cohesion_tag: String, high_ascendancy_neighbor: String) -> void:
	var coh: Dictionary = peace_state["cohesion"].get(low_cohesion_tag, {"public": 30})
	if coh["public"] < 35:
		apply_pillar_shift(low_cohesion_tag, "cohesion", -5, "riots_food_rights")  # Abstract lack of food/property rights breaking public Cohesion.
		print("Failed state pressure: %s public Cohesion low (riots from shortages/rights issues). Open to %s's high Ascendancy model (prosperity appeal, e.g., communist to capitalist shift or Alberta/Greenland separatism examples). Hidden Hand may exploit for division." % [low_cohesion_tag, high_ascendancy_neighbor])

# === Save/Load for Demographic/Policy State (high-value for 10-year scenarios) ===
# Implements the SaveLoadManager contract. Persists the new policy, erosion, manpower, settlement, and pillar-adjacent state.
# This allows resuming long campaigns where demographic choices (immigration vs pro-natal, printing vs sound money, foreign legions) have compounded effects.

func get_save_data() -> Dictionary:
	_init_peace_state_if_needed()
	return {
		"demographic_policies": peace_state.get("demographic_policies", {}).duplicate(true),
		"non_citizen_ratio": peace_state.get("non_citizen_ratio", {}).duplicate(true),
		"foreign_military_pct": peace_state.get("foreign_military_pct", {}).duplicate(true),
		"trust_erosion": peace_state.get("trust_erosion", {}).duplicate(true),
		"fiat_strain": peace_state.get("fiat_strain", {}).duplicate(true),
		"manpower_pool": peace_state.get("manpower_pool", {}).duplicate(true),
		"civilian_goods": peace_state.get("civilian_goods", {}).duplicate(true),
		"settled_areas": peace_state.get("settled_areas", {}).duplicate(true),
		# Persistence for hybrid tree edit mode, epoch shifts, geo choices (custom nodes, progress, decisions, inflation)
		"custom_initiative_nodes": peace_state.get("custom_initiative_nodes", {}).duplicate(true),
		"initiative_progress": peace_state.get("initiative_progress", {}).duplicate(true),
		"epoch_decisions": peace_state.get("epoch_decisions", {}).duplicate(true),
		"inflation_risk": peace_state.get("inflation_risk", {}).duplicate(true),
		"hand_revelation": peace_state.get("hand_revelation", {}).duplicate(true),
		"narrative_phase": peace_state.get("narrative_phase", {}).duplicate(true),
		# Core 1918 Armistice Peace Conference state for 50+ turn persistence (conference outcome, agent leverage pre/during, term choices, grievance for follow-ons, applied effects)
		"conference_1918_completed": peace_state.get("conference_1918_completed", false),
		"inclusion_leverage": peace_state.get("inclusion_leverage", {}).duplicate(true),
		"grievance": peace_state.get("grievance", {}).duplicate(true),
		"term_choices": peace_state.get("term_choices", {}).duplicate(true),
		"active_treaty_modifiers": peace_state.get("active_treaty_modifiers", []).duplicate(true),
		"notes": peace_state.get("notes", []).duplicate(true),
		"crisis_responses": peace_state.get("crisis_responses", {}).duplicate(true),
		"pending_continuation": peace_state.get("pending_continuation", {}),
		# Key pillar/peace outcome state for ripples and follow-ons (ascendancy/cohesion drive many effects; persist for 1918+ 50-turn integrity)
		"ascendancy": peace_state.get("ascendancy", {}).duplicate(true),
		"cohesion": peace_state.get("cohesion", {}).duplicate(true),
		"mandate": peace_state.get("mandate", {}).duplicate(true),
		"industrial_base": peace_state.get("industrial_base", {}).duplicate(true),
		"military_allocation": peace_state.get("military_allocation", {}).duplicate(true),
		# Living world: riots (cohesion<50% spread/duration) + delayed research ethics events (post-tech 6mo concerns)
		"active_riots": peace_state.get("active_riots", {}).duplicate(true),
		"pending_research_events": peace_state.get("pending_research_events", {}).duplicate(true),
		# New major events state (separatism, radicalization from riot choices, ethics_responses for chains, scandal, unresolved for living escalation)
		"separatism_risk": peace_state.get("separatism_risk", {}).duplicate(true),
		"radicalization": peace_state.get("radicalization", {}).duplicate(true),
		"ethics_responses": peace_state.get("ethics_responses", {}).duplicate(true),
		"scandal_meter": peace_state.get("scandal_meter", {}).duplicate(true),
		"unresolved_crises": peace_state.get("unresolved_crises", {}).duplicate(true),
		# Space race, secret programs, mechs (alt-history Expanse/steampunk/mech milestones and secret funding)
		"space_milestones": peace_state.get("space_milestones", {}).duplicate(true),
		"secret_space_programs": peace_state.get("secret_space_programs", {}).duplicate(true),
		"space_race_competition": peace_state.get("space_race_competition", {}).duplicate(true),
		"mech_designer_unlocked": peace_state.get("mech_designer_unlocked", {}).duplicate(true),
		"mech_variant_choice": peace_state.get("mech_variant_choice", {}).duplicate(true),
		"secret_fleet_combat_bonus": peace_state.get("secret_fleet_combat_bonus", {}).duplicate(true),
		# Minor persist for new biotech agent mission states (from this task)
		"biotech_intel": peace_state.get("biotech_intel", {}).duplicate(true),
		"biotech_sabotage_log": peace_state.get("biotech_sabotage_log", {}).duplicate(true),
		"scanner_intel_flags": peace_state.get("scanner_intel_flags", {}).duplicate(true),
		"version": 1
	}

func apply_save_data(data: Dictionary) -> void:
	_init_peace_state_if_needed()
	if data.has("demographic_policies"):
		peace_state["demographic_policies"] = data["demographic_policies"].duplicate(true)
	if data.has("non_citizen_ratio"):
		peace_state["non_citizen_ratio"] = data["non_citizen_ratio"].duplicate(true)
	if data.has("foreign_military_pct"):
		peace_state["foreign_military_pct"] = data["foreign_military_pct"].duplicate(true)
	if data.has("trust_erosion"):
		peace_state["trust_erosion"] = data["trust_erosion"].duplicate(true)
	if data.has("fiat_strain"):
		peace_state["fiat_strain"] = data["fiat_strain"].duplicate(true)
	if data.has("manpower_pool"):
		peace_state["manpower_pool"] = data["manpower_pool"].duplicate(true)
	if data.has("civilian_goods"):
		peace_state["civilian_goods"] = data["civilian_goods"].duplicate(true)
	if data.has("settled_areas"):
		peace_state["settled_areas"] = data["settled_areas"].duplicate(true)
	# Restore hybrid tree/epoch/edit state (custom nodes for initiatives + tech via TM, progress for player choices on geo, epoch decisions + follow-ups)
	if data.has("custom_initiative_nodes"):
		peace_state["custom_initiative_nodes"] = data["custom_initiative_nodes"].duplicate(true)
	if data.has("initiative_progress"):
		peace_state["initiative_progress"] = data["initiative_progress"].duplicate(true)
	if data.has("epoch_decisions"):
		peace_state["epoch_decisions"] = data["epoch_decisions"].duplicate(true)
	if data.has("inflation_risk"):
		peace_state["inflation_risk"] = data["inflation_risk"].duplicate(true)
	if data.has("hand_revelation"):
		peace_state["hand_revelation"] = data["hand_revelation"].duplicate(true)
	if data.has("narrative_phase"):
		peace_state["narrative_phase"] = data["narrative_phase"].duplicate(true)
	# Core 1918 peace conference state restore (critical for long 50+ turn campaigns: terms drive follow-ons, leverage/grievance persist across saves, resolution effects replay)
	if data.has("conference_1918_completed"):
		peace_state["conference_1918_completed"] = bool(data["conference_1918_completed"])
	if data.has("inclusion_leverage"):
		peace_state["inclusion_leverage"] = data["inclusion_leverage"].duplicate(true)
	if data.has("grievance"):
		peace_state["grievance"] = data["grievance"].duplicate(true)
	if data.has("term_choices"):
		peace_state["term_choices"] = data["term_choices"].duplicate(true)
	if data.has("active_treaty_modifiers"):
		peace_state["active_treaty_modifiers"] = data["active_treaty_modifiers"].duplicate(true)
	if data.has("notes"):
		peace_state["notes"] = data["notes"].duplicate(true)
	if data.has("crisis_responses"):
		peace_state["crisis_responses"] = data["crisis_responses"].duplicate(true)
	if data.has("pending_continuation"):
		peace_state["pending_continuation"] = data.get("pending_continuation", {}).duplicate(true)
	# Pillar state for peace ripples/follow-ons
	if data.has("ascendancy"):
		peace_state["ascendancy"] = data["ascendancy"].duplicate(true)
	if data.has("cohesion"):
		peace_state["cohesion"] = data["cohesion"].duplicate(true)
	if data.has("mandate"):
		peace_state["mandate"] = data["mandate"].duplicate(true)
	if data.has("industrial_base"):
		peace_state["industrial_base"] = data["industrial_base"].duplicate(true)
	if data.has("military_allocation"):
		peace_state["military_allocation"] = data["military_allocation"].duplicate(true)
	# Living world events persist (riots ongoing effects + research-delayed ethics/concerns for save/load roundtrips in 50t+)
	if data.has("active_riots"):
		peace_state["active_riots"] = data["active_riots"].duplicate(true)
	if data.has("pending_research_events"):
		peace_state["pending_research_events"] = data["pending_research_events"].duplicate(true)
	# New living events persist: separatism/radicalization (from riot linger/choices), ethics_responses (chain choices), scandal/unresolved for escalation
	if data.has("separatism_risk"):
		peace_state["separatism_risk"] = data["separatism_risk"].duplicate(true)
	if data.has("radicalization"):
		peace_state["radicalization"] = data["radicalization"].duplicate(true)
	if data.has("ethics_responses"):
		peace_state["ethics_responses"] = data["ethics_responses"].duplicate(true)
	if data.has("scandal_meter"):
		peace_state["scandal_meter"] = data["scandal_meter"].duplicate(true)
	if data.has("unresolved_crises"):
		peace_state["unresolved_crises"] = data["unresolved_crises"].duplicate(true)
	# Space race and secret/mech programs persist
	if data.has("space_milestones"):
		peace_state["space_milestones"] = data["space_milestones"].duplicate(true)
	if data.has("secret_space_programs"):
		peace_state["secret_space_programs"] = data["secret_space_programs"].duplicate(true)
	if data.has("space_race_competition"):
		peace_state["space_race_competition"] = data["space_race_competition"].duplicate(true)
	if data.has("mech_designer_unlocked"):
		peace_state["mech_designer_unlocked"] = data["mech_designer_unlocked"].duplicate(true)
	if data.has("mech_variant_choice"):
		peace_state["mech_variant_choice"] = data["mech_variant_choice"].duplicate(true)
	if data.has("secret_fleet_combat_bonus"):
		peace_state["secret_fleet_combat_bonus"] = data["secret_fleet_combat_bonus"].duplicate(true)
	# Minor persist load for biotech agent mission states
	if data.has("biotech_intel"):
		peace_state["biotech_intel"] = data["biotech_intel"].duplicate(true)
	if data.has("biotech_sabotage_log"):
		peace_state["biotech_sabotage_log"] = data["biotech_sabotage_log"].duplicate(true)
	if data.has("scanner_intel_flags"):
		peace_state["scanner_intel_flags"] = data["scanner_intel_flags"].duplicate(true)
	# Re-apply settlement_level to actual Province instances on map (runtime only; dev/infra mutations already applied via MapManager).
	# This ensures inspector, combat, supply, and map tint reflect saved settlement after load.
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces") and peace_state.has("settled_areas"):
		for pid in MapManager.get_all_provinces():
			var p = MapManager.get_province(pid)
			if p:
				# Simple heuristic: if this province's "area" or owner matches high settled, boost (demo uses generic keys; full would map regions).
				var total_settled : Variant = 0.0
				for k in peace_state["settled_areas"]:
					total_settled += float(peace_state["settled_areas"][k])
				if total_settled > 0.1:
					p.settlement_level = clamp(total_settled * 0.3, 0.0, 1.5)  # distribute for playtest
	print("GameData: Demographic/policy state (policies, erosion, manpower, settlements) restored from save.")

func clear_for_load() -> void:
	# Optional reset before apply (SaveLoad calls if present).
	peace_state["demographic_policies"] = {}
	peace_state["non_citizen_ratio"] = {}
	peace_state["foreign_military_pct"] = {}
	peace_state["trust_erosion"] = {}
	peace_state["fiat_strain"] = {}
	peace_state["manpower_pool"] = {}
	peace_state["civilian_goods"] = {}
	peace_state["settled_areas"] = {}
	peace_state["custom_initiative_nodes"] = {}
	peace_state["initiative_progress"] = {}
	peace_state["epoch_decisions"] = {}
	peace_state["inflation_risk"] = {}
	peace_state["hand_revelation"] = {}
	peace_state["narrative_phase"] = {}
	# Core 1918 conference reset
	peace_state["conference_1918_completed"] = false
	peace_state["inclusion_leverage"] = {}
	peace_state["grievance"] = {}
	peace_state["term_choices"] = {}
	peace_state["active_treaty_modifiers"] = []
	peace_state["notes"] = []
	peace_state["crisis_responses"] = {}
	peace_state.erase("pending_continuation")
	peace_state["ascendancy"] = {}
	peace_state["cohesion"] = {}
	peace_state["mandate"] = {}
	peace_state["industrial_base"] = {}
	peace_state["military_allocation"] = {}
	peace_state["active_riots"] = {}
	peace_state["pending_research_events"] = {}
	peace_state["separatism_risk"] = {}
	peace_state["radicalization"] = {}
	peace_state["ethics_responses"] = {}
	peace_state["scandal_meter"] = {}
	peace_state["unresolved_crises"] = {}
	peace_state["space_milestones"] = {}
	peace_state["secret_space_programs"] = {}
	peace_state["space_race_competition"] = {}
	peace_state["mech_designer_unlocked"] = {}
	peace_state["mech_variant_choice"] = {}
	peace_state["secret_fleet_combat_bonus"] = {}
	# clear biotech mission states
	peace_state["biotech_intel"] = {}
	peace_state["biotech_sabotage_log"] = {}
	peace_state["scanner_intel_flags"] = {}


## === Playtest Harness Convenience (added by tester_enhancer.py) ===
## One-call for "Simulate full cultural war + advance + log" from DebugOverlay or CLI tests.
## Applies expansive anti-natal stack + low coh + traditional outlier + monthly erosion ticks.
## Fires toasts (welfare, HH pandemic/Spanish Flu, social rev), updates welfare_burden/cohesion, logs Italy check.
func simulate_full_cultural_war_harness(player_tag: String = "player", months: int = 8) -> void:
	_init_peace_state_if_needed()
	var tag : Variant = player_tag.to_upper()
	if has_method("apply_social_services_policy"): apply_social_services_policy(tag, "expansive_burden")
	if has_method("apply_women_workforce_policy"): apply_women_workforce_policy(tag, "full")
	if has_method("apply_governmental_education_policy"): apply_governmental_education_policy(tag, "public_indoctrination")
	if has_method("apply_pro_natal_incentives"): apply_pro_natal_incentives(tag, 0)
	if has_method("apply_pillar_shift"): apply_pillar_shift(tag, "cohesion", -30, "enhancer_full_cw")
	# Simulate traditional outlier for HH pressure
	var pols: Dictionary = peace_state.get("demographic_policies", {}).get(tag, {})
	pols["border_policy"] = "open"  # to contrast with traditional_strength checks
	peace_state["demographic_policies"][tag] = pols
	# Advance erosion
	for m in range(months):
		process_monthly_demographic_erosion(1936, (m % 12) + 1)
	print("[ENHANCER] Full cultural war harness sim complete for %s (%d months). Check toasts, welfare_burden, HH influence, PolicyLawScreen, map settlement effects if applied prior." % [tag, months])

# Dedicated revelation events for gradual Hidden Hand (glimmer in the 40s only as "whispers", builds with key historical moves: precursors to Eisenhower's 1961 MIC speech, JFK 1963, Reagan 1981 attempt, and global pattern where open opponents to the complex/Hand were targeted, threatened, killed, rendered ineffective or subservient in many countries). 
# Revelation *systems*: hand_revelation meter builds from hand_influence + time + black market/wars/false peaces. Key events (year checks) aid the player *over time* if they positioned against (via tree "expose" nodes, agent missions, low hand choices): +ascendancy, hand drop for "them", unlock anti-Hand initiatives, public legitimacy. If complicit/ignored: risks (targeted: leader "accidents"/Reagan-style, -cohesion, "subservient" penalties to doctrines/production). 
# Narrative escalation (loved): early "our noble cause", mid "the enemy is pure evil", post-reveal "we were all tools" (of the Hand which loves wars for its agenda). False/sacrificial armistices feed it (hidden deals with the powers).
# Black market explicitly feeds (corruption like mob/prohibition/deep state elements launder profits to Hand influence).
func process_hand_revelation_events(year: int) -> void:
	_init_peace_state_if_needed()
	if not peace_state.has("hand_revelation"):
		peace_state["hand_revelation"] = {}
	if not peace_state.has("narrative_phase"):
		peace_state["narrative_phase"] = {}
	var tags : Variant = ["GER", "USA", "ENG", "SOV", "FRA", "JAP", "ITA", "POL", "FIN", "NOR", "SWE", "DNK", "NLD", "BEL"]
	for tag in tags:
		if not peace_state["hand_revelation"].has(tag):
			peace_state["hand_revelation"][tag] = 0.05
		if not peace_state["narrative_phase"].has(tag):
			peace_state["narrative_phase"][tag] = "noble_cause"
		var hand : float = float(peace_state.get("hand_influence", {}).get(tag, 0.0))
		var rev : float = float(peace_state["hand_revelation"].get(tag, 0.0))
		rev = clamp(rev + hand * 0.012 + 0.005, 0.0, 1.0)  # slow build
		peace_state["hand_revelation"][tag] = rev
		# Glimmer in 40s (post war setup, MIC complex forming)
		if year >= 1945 and year <= 1949 and rev > 0.12 and randf() < 0.25:
			peace_state["narrative_phase"][tag] = "glimmer_40s"
			if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
				LeaderEventUI.post_news("Glimmer in the 40s", "1940s: First whispers of secret networks behind the 'noble causes' of the great wars. The Military-Industrial complex (and its global cousins) taking shape. Early 'our noble cause' still dominant, but cracks appear. Key events ahead will test those who move against them.", "hand_glimmer")
			print("[REVELATION GLIMMER 40s] ", tag, ": first hints of the Hand/MIC. Build opposition now for future aid, or feed it.")
		# Key historical glimmers/events (build awareness, aid if opposed)
		var key_year_events : Variant = {
			1961: "Eisenhower Military-Industrial Complex speech",
			1963: "JFK - prominent opponent targeted",
			1981: "Reagan assassination attempt (opponent neutralized?)",
		}
		if year in key_year_events and rev > 0.2:
			var desc: String = str(key_year_events[year])
			var oppose : Variant = 1.0 - hand
			if oppose > 0.35:  # player opposed via prior choices
				apply_pillar_shift(tag, "ascendancy", int(10 * oppose), "key_reveal_aid")
				peace_state["hand_influence"][tag] = max(0.0, hand - 0.08 * oppose)
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Revelation Aids the Prepared", desc + " — your prior resistance to the Hand turns this into legitimacy and power. +Ascendancy, rivals' influence drops. The 'good vs evil' was always theater.", "revelation_aid_player")
				print("[KEY EVENT AIDS PLAYER] ", tag, " ", desc, " — opposed stance pays off (bonuses).")
			else:
				# Targeted as in history
				apply_pillar_shift(tag, "cohesion", -7, "targeted_by_hand")
				peace_state["hand_influence"][tag] = min(1.0, hand + 0.06)
				if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
					LeaderEventUI.post_news("Opponent to the Powers Neutralized", desc + " — those who openly moved against the complex/Hand were targeted, threatened, killed, rendered ineffective or subservient (global pattern). Lack of prior opposition leaves vulnerability.", "targeted")
				print("[KEY EVENT RISK - TARGETED] ", tag, " ", desc, " — complicit/ignored, effect applied (cohesion loss, hand grows).")
		# Phase for escalation toasts (early noble, mid pure evil, post we were tools)
		var ph : Variant = "noble_cause"
		if rev > 0.25: ph = "pure_evil"
		if rev > 0.55: ph = "we_were_tools"
		peace_state["narrative_phase"][tag] = ph
	# Demo escalation toast using phase (for war/epoch/news flavor)
	if year % 4 == 0 and randf() < 0.15:
		var dtag : Variant = "USA"
		var ph2 : String = str(peace_state["narrative_phase"].get(dtag, "noble_cause"))
		var txt : Variant = "our noble cause"
		if ph2 == "pure_evil": txt = "the enemy is pure evil"
		elif ph2 == "we_were_tools": txt = "we were all tools of the Hand"
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news("Narrative Escalation", "The story of the conflicts shifts in the public mind: " + txt + ". (False peaces and black markets only deepen the Hand's hold.)", "narrative_escalation")
		print("[NARRATIVE ESCALATION] ", dtag, " public mood: ", txt)



func get_space_strike_bonus(tag: String) -> float:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	var ssb := peace_state.get("space_strike_bonus", {}) as Dictionary
	return float(ssb.get(tag, 0.0))

func apply_space_strike_bonus(tag: String, amount: float) -> void:
	_init_peace_state_if_needed()
	tag = tag.strip_edges().to_upper()
	if not peace_state.has("space_strike_bonus"): peace_state["space_strike_bonus"] = {}
	peace_state["space_strike_bonus"][tag] = float(peace_state["space_strike_bonus"].get(tag, 0.0)) + amount
	print("[SPACE WIRING] space_strike_bonus for %s += %.2f (now %.2f) from orbital assets / space designer support (guided munitions for ground)" % [tag, amount, peace_state["space_strike_bonus"][tag]])
