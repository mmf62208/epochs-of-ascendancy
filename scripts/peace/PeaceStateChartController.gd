# scripts/peace/PeaceStateChartController.gd
# Controller for the visual Godot State Charts example for the peace treaty phases.
# Attach to the StateChart node in the scene.
# It syncs with GameData.peace_state, sends events based on conference resolution / year advance,
# and can launch dialogues or trigger continuation on entering certain states.
# This is the "build the visual state chart nodes" implementation.

extends Node  # Will be attached to StateChart in .tscn

@onready var state_chart: StateChart = get_parent() as StateChart  # The StateChart node this script controls

var _current_peace_tag: String = "GER"  # or from LeaderManager

func _ready() -> void:
	if not state_chart:
		push_error("PeaceStateChartController must be child of a StateChart node.")
		return

	# Connect to state chart signals for feedback
	state_chart.state_entered.connect(_on_state_entered)
	state_chart.state_exited.connect(_on_state_exited)
	state_chart.transition_taken.connect(_on_transition_taken)

	# Initial sync
	_sync_from_peace_state()

	# Example: Listen for peace events (in full game, connect from GameData or TimeManager)
	# For demo, buttons or external calls will send events.

	print("Peace State Chart Controller ready. Use send_peace_event('resolve_conference') etc. from demo or resolver.")

func _sync_from_peace_state() -> void:
	if typeof(GameData) == TYPE_NIL:
		return
	var ps: Dictionary = GameData.get_peace_state()
	var grievance: float = float(ps.get("grievance", {}).get(_current_peace_tag, 0))
	var terms: Dictionary = ps.get("term_choices", {})

	# Set properties on the chart so ExpressionGuards can read them (the plugin supports context)
	# In practice, guards use expression like "grievance > 30" and the chart provides context.
	# For simplicity, we can set on the chart or use a context object.
	if state_chart.has_method("set_property"):  # If supported, or use variables
		# The plugin evaluates expressions in context of the state and chart.
		# We'll drive via events mostly, and guards on properties if exposed.
		pass

	# If conference done and no initial state set, send initial
	if ps.get("conference_1918_completed", false) and state_chart.active_state and "PreConference" in str(state_chart.active_state.name):
		send_peace_event("resolve_conference")

func send_peace_event(event_name: StringName) -> void:
	if state_chart:
		state_chart.send_event(event_name)
		print("PeaceStateChart: Sent event '%s'. Current active: %s" % [event_name, state_chart.active_state.name if state_chart.active_state else "none"])

func _on_state_entered(state: StateChartState) -> void:
	print("Peace Phase entered: ", state.name)
	# React to key states with pillar updates, dialogues, factory shifts, asymmetrical agency.
	var state_name := str(state.name)
	var ps := {}
	if typeof(GameData) != TYPE_NIL:
		ps = GameData.get_peace_state()

	if "Crisis1923" in state_name or "Crisis" in state_name:
		if typeof(GameData) != TYPE_NIL:
			var leverage: int = GameData.get_inclusion_leverage(_current_peace_tag)
			var crisis_terms: Dictionary = ps.get("term_choices", {})
			GameData.start_1923_crisis_dialogue(_current_peace_tag, leverage, crisis_terms)

	if "Integration" in state_name or "Occupation" in state_name:
		if typeof(GameData) != TYPE_NIL:
			ps = GameData.get_peace_state()
			var prior: Dictionary = ps.get("term_choices", {})
			var res: int = int(ps.get("grievance", {}).get(_current_peace_tag, 50))
			GameData.launch_victory_dialogue_if_needed(_current_peace_tag)  # Wires costs, resistance calc, agent asymmetrical (extract talent, special ops), international reactions based on justification/claims.
			# Simulate factory shift: low Cohesion forces higher military_allocation (unified base means more absolute military capacity).
			var coh: int = GameData.get_pillar(_current_peace_tag, "cohesion")
			GameData.set_military_allocation(_current_peace_tag, 0.6 + ( (100 - coh) / 500.0 ), "integration_resistance")
			# Puppets/annex/core process: costs in pillars, convert to core with claims/acceptance (high Ascendancy for prosperity pull in failed states).
			GameData.start_territory_integration("example_territory", "hybrid", {"ancestral": 10, "population": 5})

	if "SeparatistUnrest" in state_name or "CivilWar" in state_name:
		if typeof(GameData) != TYPE_NIL:
			GameData.check_separatism_risk(_current_peace_tag)  # Low public (riots from food/rights shortages breaking Cohesion) or elite/institutional -> separatism/civil war (Alberta/Greenland, Russian Reds/Whites; Hidden Hand foments via group erosion for divide-and-conquer).
			# Failed state openness: Low Cohesion groups make populations look to high Ascendancy neighbors for better systems (e.g., pressure for capitalist models, separatism to prosper under successful ownership).

	if "GoldenAge" in state_name or "GoldenAgeSpecial" in state_name:
		if typeof(GameData) != TYPE_NIL:
			GameData.trigger_golden_age(_current_peace_tag)  # Ascendancy maxing payoff – players feel the impact of building the stat through surges and perks.
			# Golden specials (renaissance, tech vanguard, economic miracle, hegemonic) are launched from demo/tree when high Ascendancy; controller ensures the surge + logs the "payoff" feel.

	if "CulturalShift" in state_name or "Demographic" in state_name:
		if typeof(GameData) != TYPE_NIL:
			# Launch the immigration/culture dialogue for macro sphere choices (Western/Islamic/African/Sinic etc.), policy (open/guest/assimilation), short cheap labor vs long public jobs/crime/cohesion friction, Hidden Hand, affinity.
			var immigration_res: DialogueResource = load("res://data/peace/immigration_culture_events.dialogue")
			if immigration_res:
				DialogueManager.show_dialogue_balloon(immigration_res, "start_immigration_choice")
			GameData.check_separatism_risk(_current_peace_tag)
			_log_event("Cultural/Demographic shift state: Immigration or assimilation initiative resolved. Macro culture friction (affinity), Cohesion group splits (public pays most, elite profits), Hidden Hand exploitation, separatism risk. Part of the Ascendancy Initiatives sandbox for where you take your nation.")

	if "Subversion" in state_name:
		if typeof(GameData) != TYPE_NIL:
			GameData.check_subversion_risk(_current_peace_tag)  # Low Ascendancy makes prone to Hidden Hand overthrow/subjugation. Ebb/flow: Not death spiral, but real risk with recovery paths.

	if "TradeErosion" in state_name:
		if typeof(GameData) != TYPE_NIL:
			# Simulate cheap exports erosion (short Cohesion, long industrial loss) – makes trade a meaningful, visible choice.
			GameData.accept_cheap_exports_deal("trade_envoy", "AsiaPartner")
			_log_event("Trade erosion state: Cheap goods boosted public Cohesion short-term but factories eroding. Narrative trade-offs make industry/Cohesion building fun and tense.")
			# Wire real dialogue for player choice on the trade-off.
			var trade_res: DialogueResource = load("res://data/peace/cheap_goods_aid_events.dialogue")
			if trade_res:
				DialogueManager.show_dialogue_balloon(trade_res, "cheap_exports_choice")

	if "AidCorruption" in state_name:
		if typeof(GameData) != TYPE_NIL:
			GameData.send_country_aid("aid_agent", "FailedState", 10)  # Aid waste feeding Hidden Hand – corruption narrative makes 'helping' impactful with risks.
			# Wire real dialogue for the aid corruption choice.
			var aid_res: DialogueResource = load("res://data/peace/cheap_goods_aid_events.dialogue")
			if aid_res:
				DialogueManager.show_dialogue_balloon(aid_res, "aid_corruption_choice")

	if "Backlash" in state_name:
		if typeof(GameData) != TYPE_NIL:
			GameData.apply_pillar_shift(_current_peace_tag, "ascendancy", -15, "international_backlash")
			# Hidden Hand erodes Cohesion groups (public/elite) on low Cohesion.
			if _current_peace_tag in ps.get("cohesion", {}):
				GameData.apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -5, "public")
				GameData.apply_agent_pillar_influence("HIDDEN_HAND", "cohesion", -5, "elite")

	if "Collapsed" in state_name or "Partition" in state_name:
		if typeof(GameData) != TYPE_NIL:
			GameData.trigger_national_defeat_or_continuation(_current_peace_tag, "Peace chart entered collapsed state")
			# Successor switch with stash (agents can pre-craft Mandate/Ascendancy for new tag).

	if "FactoryReallocation" in state_name or "IndustrialShift" in state_name:
		if typeof(GameData) != TYPE_NIL:
			var factory_coh: int = GameData.get_pillar(_current_peace_tag, "cohesion")
			# Larger industrial_base (economy + Cohesion) = greater capacity. Allocation driven by Cohesion, gov (authoritarian easier), agents.
			GameData.set_military_allocation(_current_peace_tag, 0.5 + ((100 - factory_coh) / 400.0), "chart_industrial_state")

func _on_state_exited(state: StateChartState) -> void:
	print("Peace Phase exited: ", state.name)

func _on_transition_taken(transition: Transition, source: StateChartState) -> void:
	print("Peace transition: %s -> %s" % [source.name, transition.resolve_target().name if transition.resolve_target() else "unknown"])

func _log_event(text: String) -> void:
	# Lightweight for controller reactions (full log lives in phases demo or future event UI).
	print("[PeaceStateChartController] " + text)

# Public API for the rest of the game (called from PeaceConferenceWindow resolve, phases demo, TimeManager follow-ons)
func on_conference_resolved() -> void:
	send_peace_event("resolve_conference")

func on_advance_to_1919() -> void:
	send_peace_event("advance_1919")

func on_trigger_1923_crisis() -> void:
	send_peace_event("trigger_1923_crisis")

func on_grievance_spike() -> void:
	# Could send an event that a guard reacts to, or directly
	send_peace_event("grievance_spike")

# In full integration, ExpressionGuards on transitions can check GameData.peace_state directly
# e.g. a guard with expression "GameData.get_peace_state().grievance.get(tag,0) > 30"
# The plugin's expression evaluation supports context from the chart and passed objects.