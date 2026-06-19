class_name PolicyLawScreen
extends Window

## Reusable, non-modal-ish Policy / Law Screen.
## Top-level tunable ongoing laws (complements Ascendancy Initiatives tree for big pushes).
## Live dynamic previews: Cohesion group impacts + time-to-effect from GameData helpers (based on current Asc/coh/agents).
## Direction header: Trust Erosion, non-citizen, loyalty multiplier, recruits (player always sees heading + levers).
## Direct change (pay capital + reaction) or Agent Lobby (long mission trade-off vs Tech/Intel/etc.).
## Category filters for clarity. Tooltips explain public/elite/institutional + Hidden Hand.
## Connects to GameData.policy_state_changed + TimeManager.game_month_advanced for live refresh.
## Persistent: stays open on changes; use Refresh or auto on month. Toggle from TopInfoBar / other UIs.
## Extracted from demo stub + TopInfoBar inline to proper reusable scene + manager.

@export var player_country_tag: String = "USA"

var _player_tag: String = "USA"
var _vbox: VBoxContainer
var _header_label: Label
var _policies_container: VBoxContainer
var _filter_row: HBoxContainer
var _current_filter: String = "all"  # all | demographic | economic | security | military

func _ready() -> void:
	title = "Policy / Law Screen"
	min_size = Vector2(760, 520)
	RetrowaveTheme.style_popup_root(self)

	_player_tag = player_country_tag.to_upper()
	if typeof(LeaderManager) != TYPE_NIL:
		_player_tag = LeaderManager.get_player_country_tag().to_upper()

	_build_ui()
	_refresh()

	# Live updates: month ticks (erosion) + explicit policy changes from anywhere (direct, agent resolve, etc.).
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_month_advanced.is_connected(_on_month_advanced):
			TimeManager.game_month_advanced.connect(_on_month_advanced)
	if typeof(GameData) != TYPE_NIL and GameData.has_signal("policy_state_changed"):
		if not GameData.policy_state_changed.is_connected(_on_policy_state_changed):
			GameData.policy_state_changed.connect(_on_policy_state_changed)

	popup_centered()
	if not close_requested.is_connected(_on_close):
		close_requested.connect(_on_close)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Policy / Law — Tunable National Direction (Agent Lobby = primary lever for most players)"
	RetrowaveTheme.style_title(title_lbl)
	_vbox.add_child(title_lbl)

	_header_label = Label.new()
	_header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(_header_label)
	_vbox.add_child(_header_label)

	# Filters (simple, high value for world-class clean UX without overcomplexity)
	_filter_row = HBoxContainer.new()
	_filter_row.add_theme_constant_override("separation", 4)
	_vbox.add_child(_filter_row)

	for f in ["all", "demographic", "economic", "security", "military"]:
		var fb := Button.new()
		fb.text = f.capitalize()
		fb.custom_minimum_size = Vector2(90, 22)
		RetrowaveTheme.style_secondary_button(fb)
		fb.pressed.connect(func(): _set_filter(f))
		_filter_row.add_child(fb)

	# Container for dynamic policy rows
	_policies_container = VBoxContainer.new()
	_policies_container.add_theme_constant_override("separation", 4)
	_vbox.add_child(_policies_container)

	# Note on agency
	var note := Label.new()
	note.text = "Direct Change: Immediate (costs Mandate/Ascendancy + possible Cohesion backlash). Agent Lobby: 6-12mo commitment (agent unavailable elsewhere) — main way to shift laws with less direct cost/backlash. Hidden Hand can counter. Time-to-effect dynamic (faster with high Ascendancy/Cohesion/agents)."
	RetrowaveTheme.style_body_label(note)
	_vbox.add_child(note)

	var actions := HBoxContainer.new()
	_vbox.add_child(actions)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh (live on month or policy change)"
	RetrowaveTheme.style_secondary_button(refresh_btn)
	refresh_btn.pressed.connect(_refresh)
	actions.add_child(refresh_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	RetrowaveTheme.style_secondary_button(close_btn)
	close_btn.pressed.connect(_on_close)
	actions.add_child(close_btn)

func _set_filter(f: String) -> void:
	_current_filter = f
	_refresh()

func _on_month_advanced(_y: int, _m: int) -> void:
	_refresh()

func _on_policy_state_changed(tag: String) -> void:
	if tag.to_upper() == _player_tag:
		_refresh()

func _refresh() -> void:
	if typeof(GameData) == TYPE_NIL:
		if _header_label:
			_header_label.text = "GameData not available"
		return

	var ps: Dictionary = GameData.get_peace_state()
	var policies: Dictionary = ps.get("demographic_policies", {}).get(_player_tag, {})
	var trust := int(ps.get("trust_erosion", {}).get(_player_tag, 0))
	var noncit := float(ps.get("non_citizen_ratio", {}).get(_player_tag, 0.0))
	var loy: float = 1.0
	var rec := 100
	if GameData.has_method("get_military_loyalty_multiplier"):
		loy = GameData.get_military_loyalty_multiplier(_player_tag)
	if GameData.has_method("get_available_recruits"):
		rec = GameData.get_available_recruits(_player_tag)

	_header_label.text = "Direction — %s | Trust Erosion: %d | Non-Citizen: %.0f%% | Mil Loyalty: %.2f | Recruits: %d\n(High erosion/non-cit/foreign troops = social inflation like printing: hits Ascendancy + production + public Cohesion. Pro-natal + fortified + sovereign/gold as counters. Agent time = real trade-off.)" % [_player_tag, trust, noncit * 100, loy, rec]

	# Clear old rows
	for c in _policies_container.get_children():
		c.queue_free()

	# Policy definitions (label, current getter, type for helpers, category, direct action, agent ptype)
	var defs: Array[Dictionary] = [
		{"label": "Pro-Natal Incentives (0-3)", "get": policies.get("pro_natal_level", 0), "ptype": "pro_natal", "cat": "demographic",
		 "direct": func(): GameData.apply_pro_natal_incentives(_player_tag, min(3, int(policies.get("pro_natal_level", 0)) + 1)),
		 "agent_ptype": "pro_natal",
		 "tip": "+Public long-term (native support, families feel future). -Elite short (subsidies). Slower than immigration but sustainable high-trust for Golden."},
		{"label": "Border Policy", "get": policies.get("border_policy", "open"), "ptype": "border", "cat": "demographic",
		 "direct": func(): GameData.apply_border_policy(_player_tag, "fortified" if policies.get("border_policy", "open") != "fortified" else "restricted"),
		 "agent_ptype": "border",
		 "tip": "Fortified/restricted: +Public (protect citizen jobs), Mandate cost, slower industrial. Open/guest: quick labor but long public drain + HH. 'You have to really want it'."},
		{"label": "Justice Mode", "get": policies.get("justice_mode", "egalitarian"), "ptype": "justice", "cat": "security",
		 "direct": func(): GameData.apply_justice_policy(_player_tag, "two_tier" if policies.get("justice_mode", "egalitarian") != "two_tier" else "egalitarian"),
		 "agent_ptype": "police",  # reuse flavor
		 "tip": "Two-tier: +Elite (historical royal/upper privilege), short Mandate. -Public resentment. Fuels Hidden Hand on public. Egalitarian: broader legitimacy."},
		{"label": "Conscription Level (0-2)", "get": policies.get("conscription_level", 0), "ptype": "conscription", "cat": "military",
		 "direct": func(): GameData.apply_conscription_law(_player_tag, min(2, int(policies.get("conscription_level", 0)) + 1)),
		 "agent_ptype": "conscription",
		 "tip": "-Public (draft resentment). Easier high military allocation %. Pairs dangerously with foreign troops (loyalty multiplier)."},
		{"label": "Women in Workforce/Military", "get": policies.get("women_workforce", "restricted"), "ptype": "women", "cat": "economic",
		 "direct": func(): GameData.apply_women_workforce_policy(_player_tag, "encouraged" if policies.get("women_workforce", "restricted") == "restricted" else "full"),
		 "agent_ptype": "women_workforce",
		 "tip": "Encouraged/full: +industrial_base (factories/war prod). Culture-dependent cohesion (traditional resistance vs modernizing elites)."},
		{"label": "Police Type", "get": policies.get("police_type", "local"), "ptype": "police", "cat": "security",
		 "direct": func(): GameData.apply_police_type(_player_tag, "secret" if policies.get("police_type", "local") != "secret" else "local"),
		 "agent_ptype": "police",
		 "tip": "Secret: +institutional / HH resistance, -public trust (fear). Foreign-controlled: strong control but loyalty/subversion risks."},
		{"label": "Money Supply (Fiat/Printing)", "get": policies.get("money_supply", "gold_standard"), "ptype": "fiat", "cat": "economic",
		 "direct": func(): GameData.apply_money_supply_policy(_player_tag, "expanded_fiat" if policies.get("money_supply", "gold_standard") != "expanded_fiat" else "gold_standard"),
		 "agent_ptype": "fiat",
		 "tip": "Expanded fiat: Short Mandate/industrial stimulus. Long Trust Erosion (Ascendancy hit + production efficiency loss + public pain). Weimar path or recovery."},
		{"label": "Sovereign Wealth / Gold Backing (0-2)", "get": policies.get("sovereign_wealth", 0), "ptype": "sovereign", "cat": "economic",
		 "direct": func(): GameData.apply_sovereign_wealth(_player_tag, min(2, int(policies.get("sovereign_wealth", 0)) + 1)),
		 "agent_ptype": "sovereign",
		 "tip": "+Mandate, strong counter to Trust Erosion. Major Hidden Hand target (real assets vs debasement/one-world agenda)."},
		{"label": "Social Services / Welfare Model", "get": policies.get("social_services", "traditional"), "ptype": "welfare", "cat": "security",
		 "direct": func(): GameData.apply_social_services_policy(_player_tag, "elite_optimization" if policies.get("social_services", "traditional") == "traditional" else "traditional"),
		 "agent_ptype": "social",
		 "tip": "Abstract controversial: elite pop control (cost savings), assisted suicide as welfare, expansive services (gender/health burden). Short elite/Mandate 'savings' vs long public drain, HH fuel, welfare_burden like social inflation. Disastrous but flavorful trade-offs; toasts first + dialogue for interactive balance."},
		{"label": "Governmental Public Education", "get": policies.get("education_policy", "mixed_public"), "ptype": "education", "cat": "economic",
		 "direct": func(): GameData.apply_governmental_education_policy(_player_tag, "public_indoctrination" if policies.get("education_policy", "mixed_public") != "public_indoctrination" else "traditional_classical"),
		 "agent_ptype": "education",
		 "tip": "Public: +short industrial (worker bees/conformity), but anti-critical thinking, HH vector, anti-family (bible removal, feminism push). Traditional/classical: +independent problem solvers, pro-sanctity/family, buffers HH but 'outlier' pressure. Low cohesion demands 'reform'."},
	]

	for d in defs:
		if _current_filter != "all" and d["cat"] != _current_filter:
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var lbl := Label.new()
		var coh_impact := ""
		var time_est := ""
		if GameData.has_method("get_policy_coh_impact"):
			coh_impact = GameData.get_policy_coh_impact(_player_tag, d["ptype"])
		if GameData.has_method("get_policy_time_to_effect"):
			time_est = GameData.get_policy_time_to_effect(_player_tag, d["ptype"])

		lbl.text = "%s: %s  |  %s  |  %s" % [d["label"], str(d["get"]), coh_impact, time_est]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		RetrowaveTheme.style_body_label(lbl)
		lbl.tooltip_text = d.get("tip", "Affects Cohesion groups (public/elite/institutional) and Hidden Hand. See DESIGN for full sandbox details.")
		row.add_child(lbl)

		var direct_btn := Button.new()
		direct_btn.text = "Direct Change"
		direct_btn.custom_minimum_size = Vector2(110, 22)
		RetrowaveTheme.style_secondary_button(direct_btn)
		direct_btn.pressed.connect(func():
			if d.has("direct"):
				d["direct"].call()
			_refresh()  # immediate local update; signal will also fire for other listeners
		)
		row.add_child(direct_btn)

		var agent_btn := Button.new()
		agent_btn.text = "Lobby w/ Agent (6-8mo)"
		agent_btn.custom_minimum_size = Vector2(130, 22)
		RetrowaveTheme.style_secondary_button(agent_btn)
		agent_btn.pressed.connect(func():
			if typeof(GameData) != TYPE_NIL:
				var ptype: String = d.get("agent_ptype", d["ptype"])
				GameData.allocate_agent_to_policy_influence("lobby_" + ptype, ptype, _player_tag, 6)
				# Simulate realistic outcome for demo (real path: assign real agent via AgentAssignment + Time advance -> signal -> resolve)
				GameData.resolve_agent_policy_mission("lobby_" + ptype, ptype, _player_tag, "success", 2)
				_refresh()
		)
		row.add_child(agent_btn)

		_policies_container.add_child(row)

func _on_close() -> void:
	hide()
	call_deferred("queue_free")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close()

func set_player_tag(tag: String) -> void:
	_player_tag = tag.to_upper()
	if is_inside_tree():
		_refresh()
