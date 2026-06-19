# scripts/ui/AgentAssignmentScreen.gd
class_name AgentAssignmentScreen
extends DraggablePanel

@export var country_tag: String = "USA"

@onready var title_label: Label = $TitleBar/TitleLabel
@onready var close_button: Button = $TitleBar/CloseButton

@onready var total_agents_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/TotalAgentsLabel
)
@onready var available_agents_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/AvailableAgentsLabel
)
@onready var on_mission_label: Label = $MarginContainer/VBoxContainer/TopSummaryBar/OnMissionLabel
@onready var compromised_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/CompromisedLabel
)
@onready var inactive_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/InactiveLabel
)
@onready var recruit_button: Button = $MarginContainer/VBoxContainer/TopSummaryBar/RecruitButton
@onready var feedback_hint: Label = $MarginContainer/VBoxContainer/FeedbackHint

@onready var roster_filter: OptionButton = (
	$MarginContainer/VBoxContainer/MainArea/ListsColumn/AgentsColumn/RosterFilterRow/RosterFilter
)
@onready var agents_header_row: HBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/ListsColumn/AgentsColumn/AgentsHeaderRow
)
@onready var agents_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/ListsColumn/AgentsColumn/AgentsList/AgentsContent
)
@onready var targets_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/ListsColumn/TargetsColumn/TargetsList/TargetsContent
)
@onready var intel_reports_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/IntelColumn/IntelReportsList/IntelReportsContent
)
@onready var national_effects_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/IntelColumn/NationalEffectsList
)
@onready var recent_operations_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/IntelColumn/RecentOperationsList/RecentOperationsContent
)

@onready var agent_state_banner: PanelContainer = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/AgentStateBanner
)
@onready var agent_state_label: Label = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/AgentStateBanner/AgentStateMargin/AgentStateLabel
)
@onready var detail_label: Label = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/DetailLabel
)
@onready var history_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/HistoryList
)
@onready var mission_category_filter: OptionButton = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/MissionFilterRow/MissionCategoryFilter
)
@onready var missions_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/MissionsList
)
@onready var assign_mission_button: Button = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/AssignMissionButton
)
@onready var open_technology_button: Button = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/OpenTechnologyButton
)

var current_data: AgentScreenData
var _selected_agent_id: String = ""
var _selected_target_tag: String = ""
var _roster_filters_initialized: bool = false
var _mission_filters_initialized: bool = false
var _detail_progress_row: HBoxContainer
var _highlight_ops_pulse: bool = false

const AGENT_HEADER_SPECS: Array[Dictionary] = [
	{"text": "Name", "width": 130},
	{"text": "Status", "width": 120},
	{"text": "Lvl", "width": 32},
	{"text": "Skills", "width": 150},
	{"text": "Mission", "width": 110},
	{"text": "", "width": 0, "expand": true},
]
const ROW_HEIGHT := 34

const ROSTER_FILTER_ALL := 0
const ROSTER_FILTER_AVAILABLE := 1
const ROSTER_FILTER_ON_MISSION := 2
const ROSTER_FILTER_COMPROMISED := 3
const ROSTER_FILTER_INACTIVE := 4

const STATUS_SORT_ORDER := {
	"compromised": 0,
	"on_mission": 1,
	"available": 2,
	"inactive": 3,
}


func _ready() -> void:
	add_to_group("agent_screen")
	drag_handle = $TitleBar
	super._ready()
	_apply_content_margins()
	_apply_screen_theme()
	_setup_agent_headers()
	_setup_roster_filter()
	close_button.pressed.connect(_on_close_pressed)
	recruit_button.pressed.connect(_on_recruit_pressed)
	recruit_button.tooltip_text = "Recruit a new operative into your intelligence service."
	assign_mission_button.pressed.connect(_on_assign_mission_pressed)
	assign_mission_button.tooltip_text = "Open the mission picker for the selected agent and target."
	open_technology_button.pressed.connect(_on_open_technology_pressed)
	open_technology_button.tooltip_text = "Review research trees, theft targets, and compromised projects."
	RetrowaveTheme.style_secondary_button(open_technology_button)
	roster_filter.item_selected.connect(_on_roster_filter_changed)
	mission_category_filter.item_selected.connect(_on_mission_category_changed)
	_connect_agent_signals()
	refresh_screen()


func _apply_content_margins() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin == null:
		return
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)


func _on_close_pressed() -> void:
	queue_free()


func _apply_screen_theme() -> void:
	RetrowaveTheme.style_production_screen(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.MAGENTA)
	RetrowaveTheme.style_secondary_button(close_button)
	title_label.text = "Agents — %s" % country_tag
	RetrowaveTheme.style_summary_metric(total_agents_label)
	RetrowaveTheme.style_summary_metric(available_agents_label, RetrowaveTheme.SUCCESS)
	RetrowaveTheme.style_summary_metric(on_mission_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_summary_metric(compromised_label, RetrowaveTheme.WARNING)
	RetrowaveTheme.style_summary_metric(inactive_label, RetrowaveTheme.TEXT_DIM)
	RetrowaveTheme.style_primary_button(recruit_button)
	RetrowaveTheme.style_filter_option(roster_filter)
	RetrowaveTheme.style_filter_option(mission_category_filter)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/ListsColumn/AgentsColumn/AgentsTitle,
	)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/ListsColumn/TargetsColumn/TargetsTitle,
	)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/IntelColumn/IntelTitle,
		RetrowaveTheme.CYAN,
	)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/IntelColumn/NationalEffectsTitle,
		RetrowaveTheme.WARNING,
	)
	var national_effects_title := $MarginContainer/VBoxContainer/MainArea/IntelColumn/NationalEffectsTitle
	if national_effects_title is Label:
		(national_effects_title as Label).tooltip_text = (
			"Temporary modifiers from agent missions. Open National Spirits for the full list."
		)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/IntelColumn/RecentOpsTitle,
		RetrowaveTheme.MAGENTA,
	)
	RetrowaveTheme.style_detail_panel(agent_state_banner)
	RetrowaveTheme.style_body_label(agent_state_label)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/HistoryTitle,
	)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/MissionsTitle,
	)
	RetrowaveTheme.style_detail_panel($MarginContainer/VBoxContainer/MainArea/DetailPanel)
	RetrowaveTheme.style_detail_label(detail_label)
	RetrowaveTheme.style_primary_button(assign_mission_button)
	RetrowaveTheme.style_body_label(feedback_hint)
	feedback_hint.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)


func _setup_roster_filter() -> void:
	if _roster_filters_initialized:
		return
	roster_filter.clear()
	roster_filter.add_item("All Agents")
	roster_filter.add_item("Available")
	roster_filter.add_item("On Mission")
	roster_filter.add_item("Compromised")
	roster_filter.add_item("Lost / Inactive")
	_roster_filters_initialized = true


func _setup_agent_headers() -> void:
	for child in agents_header_row.get_children():
		child.queue_free()
	for spec in AGENT_HEADER_SPECS:
		if bool(spec.get("expand", false)):
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			agents_header_row.add_child(spacer)
			continue
		var label := Label.new()
		label.text = str(spec.get("text", ""))
		var width := int(spec.get("width", 100))
		if width > 0:
			label.custom_minimum_size = Vector2(width, 0)
		RetrowaveTheme.style_column_header(label)
		agents_header_row.add_child(label)


func _connect_agent_signals() -> void:
	if typeof(AgentManager) == TYPE_NIL:
		return
	for sig_name in [
		"agent_recruited",
		"agent_assigned_to_mission",
		"mission_completed",
		"agent_captured",
		"agent_killed",
	]:
		if AgentManager.has_signal(sig_name) and not AgentManager.is_connected(
			sig_name, _on_agent_state_changed
		):
			AgentManager.connect(sig_name, _on_agent_state_changed)


func _exit_tree() -> void:
	if typeof(AgentManager) == TYPE_NIL:
		return
	for sig_name in [
		"agent_recruited",
		"agent_assigned_to_mission",
		"mission_completed",
		"agent_captured",
		"agent_killed",
	]:
		if AgentManager.is_connected(sig_name, _on_agent_state_changed):
			AgentManager.disconnect(sig_name, _on_agent_state_changed)


func _on_agent_state_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	if is_inside_tree():
		_highlight_ops_pulse = true
		refresh_screen()


func _on_roster_filter_changed(_index: int) -> void:
	_populate_agents()


func _on_mission_category_changed(_index: int) -> void:
	_update_detail_panel()


func refresh_screen() -> void:
	if typeof(AgentManager) == TYPE_NIL:
		return
	current_data = AgentManager.get_agent_screen_data(country_tag, false)
	_sync_mission_category_filter()
	_update_summary_bar()
	_update_feedback_hint()
	_apply_title_attention()
	_populate_agents()
	_populate_targets()
	_populate_intel_reports()
	_populate_national_effects()
	_populate_recent_operations()
	_highlight_ops_pulse = false
	_update_detail_panel()


func _sync_mission_category_filter() -> void:
	if current_data == null:
		return
	var previous := ""
	if mission_category_filter.item_count > 0 and mission_category_filter.selected >= 0:
		previous = mission_category_filter.get_item_text(mission_category_filter.selected)

	mission_category_filter.clear()
	mission_category_filter.add_item("All Categories")
	for cat in current_data.mission_categories:
		mission_category_filter.add_item(cat.capitalize())

	if not _mission_filters_initialized:
		mission_category_filter.select(0)
		_mission_filters_initialized = true
		return

	var pick := 0
	for i in range(mission_category_filter.item_count):
		if mission_category_filter.get_item_text(i) == previous:
			pick = i
			break
	mission_category_filter.select(pick)


func _selected_mission_category_filter() -> String:
	if mission_category_filter.selected <= 0:
		return ""
	var label := mission_category_filter.get_item_text(mission_category_filter.selected)
	return label.to_lower()


func _update_summary_bar() -> void:
	if current_data == null:
		return
	total_agents_label.text = "Total Agents: %d" % current_data.total_agents
	available_agents_label.text = "Available: %d" % current_data.available_agents
	on_mission_label.text = "On Mission: %d" % current_data.on_mission_agents
	compromised_label.text = "Compromised: %d" % current_data.compromised_agents
	inactive_label.text = "Lost: %d" % current_data.inactive_agents

	if current_data.compromised_agents > 0:
		compromised_label.modulate = RetrowaveTheme.WARNING
	else:
		compromised_label.modulate = Color.WHITE
	if current_data.inactive_agents > 0:
		inactive_label.modulate = RetrowaveTheme.TEXT_DIM
	else:
		inactive_label.modulate = Color.WHITE


func _update_feedback_hint() -> void:
	if current_data == null:
		feedback_hint.text = ""
		return

	var parts: PackedStringArray = []
	if current_data.total_agents == 0:
		feedback_hint.text = "Recruit your first agent to begin intelligence operations."
		return

	if current_data.on_mission_agents > 0:
		parts.append("%d deployed" % current_data.on_mission_agents)
	if current_data.compromised_agents > 0:
		parts.append("%d compromised" % current_data.compromised_agents)
	if current_data.inactive_agents > 0:
		parts.append("%d lost" % current_data.inactive_agents)

	var flow := "Select an agent and target to assign a mission."
	if not _selected_agent_id.is_empty() and not _selected_target_tag.is_empty():
		flow = "Review missions below, then assign when ready."
	elif not _selected_agent_id.is_empty():
		flow = "Choose a target country to see eligible missions."

	if parts.is_empty():
		feedback_hint.text = "%s  •  %d available." % [flow, current_data.available_agents]
	else:
		feedback_hint.text = "%s  •  %s." % [" · ".join(parts), flow]


func _apply_title_attention() -> void:
	var base := "Agents — %s" % country_tag
	if current_data == null:
		title_label.text = base
		title_label.modulate = Color.WHITE
		return
	if current_data.compromised_agents > 0:
		title_label.text = "%s  •  %d agent(s) compromised" % [base, current_data.compromised_agents]
		title_label.modulate = RetrowaveTheme.WARNING
	elif current_data.on_mission_agents > 0:
		title_label.text = "%s  •  %d operation(s) active" % [base, current_data.on_mission_agents]
		title_label.modulate = RetrowaveTheme.CYAN
	else:
		title_label.text = base
		title_label.modulate = Color.WHITE


func _populate_agents() -> void:
	for child in agents_content.get_children():
		child.queue_free()

	if current_data == null or current_data.agents.is_empty():
		var empty := Label.new()
		empty.text = "No agents recruited. Use Recruit Agent to build your network."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(empty)
		agents_content.add_child(empty)
		_selected_agent_id = ""
		return

	var rows: Array[Dictionary] = []
	for summary in current_data.agents:
		if typeof(summary) != TYPE_DICTIONARY:
			continue
		var entry := summary as Dictionary
		if not _passes_roster_filter(entry):
			continue
		rows.append(entry)

	rows.sort_custom(_compare_agent_summaries)

	if rows.is_empty():
		var filtered_empty := Label.new()
		filtered_empty.text = "No agents match this filter."
		RetrowaveTheme.style_body_label(filtered_empty)
		agents_content.add_child(filtered_empty)
		return

	for summary in rows:
		agents_content.add_child(_create_agent_row(summary))


func _compare_agent_summaries(a: Dictionary, b: Dictionary) -> bool:
	var group_a := str(a.get("status_group", ""))
	var group_b := str(b.get("status_group", ""))
	var order_a := int(STATUS_SORT_ORDER.get(group_a, 9))
	var order_b := int(STATUS_SORT_ORDER.get(group_b, 9))
	if order_a != order_b:
		return order_a < order_b
	return str(a.get("name", "")) < str(b.get("name", ""))


func _passes_roster_filter(summary: Dictionary) -> bool:
	var group := str(summary.get("status_group", ""))
	match roster_filter.selected:
		ROSTER_FILTER_AVAILABLE:
			return group == "available"
		ROSTER_FILTER_ON_MISSION:
			return group == "on_mission"
		ROSTER_FILTER_COMPROMISED:
			return group == "compromised"
		ROSTER_FILTER_INACTIVE:
			return group == "inactive"
		_:
			return true


func _create_agent_row(summary: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var group := str(summary.get("status_group", ""))
	var on_mission := group == "on_mission"
	panel.custom_minimum_size = Vector2(0, 44 if on_mission else ROW_HEIGHT)
	RetrowaveTheme.style_detail_panel(panel)

	var agent_id := str(summary.get("agent_id", ""))
	var selected := agent_id == _selected_agent_id
	panel.tooltip_text = _build_agent_row_tooltip(summary)

	if selected:
		panel.modulate = Color(0.85, 0.95, 1.0)
	elif group == "compromised" or bool(summary.get("is_compromised", false)):
		panel.modulate = Color(1.0, 0.72, 0.55)
	elif group == "inactive" or bool(summary.get("is_inactive", false)):
		panel.modulate = Color(0.55, 0.55, 0.6)
	elif group == "on_mission":
		panel.modulate = Color(0.78, 0.92, 1.0)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	panel.add_child(outer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	outer.add_child(row)

	# Agent portrait (new support; agent_male/female from generator + save hardened)
	var ap_rect := TextureRect.new()
	ap_rect.custom_minimum_size = Vector2(22, 22)
	ap_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	ap_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var apath := str(summary.get("portrait_path", ""))
	if apath != "" and ResourceLoader.exists(apath):
		var atex := load(apath) as Texture2D
		if atex: ap_rect.texture = atex
	ap_rect.visible = ap_rect.texture != null
	row.add_child(ap_rect)

	var badge := str(summary.get("status_badge", ""))
	if not badge.is_empty():
		row.add_child(_badge_label(badge, group))
	var status_text := str(summary.get("status_detail", _format_status(summary)))
	row.add_child(_row_label(str(summary.get("name", "")), 110))
	row.add_child(_status_label(status_text, 112, group))
	row.add_child(_row_label(str(summary.get("level", 1)), 32))
	row.add_child(_row_label(str(summary.get("skills_text", "")), 150))

	var mission_text := "—"
	if not str(summary.get("mission_name", "")).is_empty():
		mission_text = str(summary.get("mission_name", ""))
		if float(summary.get("mission_progress", 0.0)) > 0.0:
			mission_text += " (%d%%)" % int(float(summary.get("mission_progress", 0.0)) * 100.0)
	row.add_child(_row_label(mission_text, 110))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var select_btn := Button.new()
	select_btn.text = "Select"
	select_btn.tooltip_text = "View missions and history for this agent."
	RetrowaveTheme.style_secondary_button(select_btn)
	select_btn.pressed.connect(_on_agent_selected.bind(agent_id))
	row.add_child(select_btn)

	if on_mission:
		var progress_row := HBoxContainer.new()
		progress_row.add_theme_constant_override("separation", 6)
		outer.add_child(progress_row)

		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 1.0
		bar.value = float(summary.get("mission_progress", 0.0))
		bar.show_percentage = false
		progress_row.add_child(bar)

		var pct_label := Label.new()
		pct_label.text = "%d%% mission complete" % int(float(summary.get("mission_progress", 0.0)) * 100.0)
		RetrowaveTheme.style_body_label(pct_label)
		pct_label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
		progress_row.add_child(pct_label)

	return panel


func _badge_label(badge: String, group: String) -> Label:
	var label := Label.new()
	label.text = badge
	label.custom_minimum_size = Vector2(72, 0)
	label.clip_text = true
	RetrowaveTheme.style_row_label(label)
	match group:
		"compromised":
			label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
		"inactive":
			label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
		"on_mission":
			label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
		_:
			label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	return label


func _status_label(text: String, min_width: int, group: String) -> Label:
	var label := _row_label(text, min_width)
	if group == "compromised":
		label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
	elif group == "inactive":
		label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	elif group == "on_mission":
		label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	return label


func _format_status(summary: Dictionary) -> String:
	return str(summary.get("status_detail", str(summary.get("status", "available")).capitalize()))


func _populate_targets() -> void:
	for child in targets_content.get_children():
		child.queue_free()

	if current_data == null:
		return

	for target_tag in current_data.target_countries:
		var btn := Button.new()
		btn.text = target_tag
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if target_tag == _selected_target_tag:
			RetrowaveTheme.style_primary_button(btn)
		else:
			RetrowaveTheme.style_secondary_button(btn)
		btn.tooltip_text = "Set %s as the mission target. Eligible missions appear in the detail panel." % target_tag
		btn.pressed.connect(_on_target_selected.bind(target_tag))
		targets_content.add_child(btn)


func _update_intel_column_titles() -> void:
	var intel_title := $MarginContainer/VBoxContainer/MainArea/IntelColumn/IntelTitle as Label
	var effects_title := $MarginContainer/VBoxContainer/MainArea/IntelColumn/NationalEffectsTitle as Label
	var ops_title := $MarginContainer/VBoxContainer/MainArea/IntelColumn/RecentOpsTitle as Label
	if intel_title != null:
		var n := current_data.intel_reports.size() if current_data else 0
		intel_title.text = "Intel Reports (%d)" % n if n > 0 else "Intel Reports"
	if effects_title != null:
		var e := current_data.national_effects.size() if current_data else 0
		effects_title.text = "National Effects (%d)" % e if e > 0 else "National Effects"
	if ops_title != null:
		var o := current_data.recent_operations.size() if current_data else 0
		ops_title.text = "Recent Operations (%d)" % o if o > 0 else "Recent Operations"


func _populate_intel_reports() -> void:
	for child in intel_reports_content.get_children():
		child.queue_free()

	if current_data == null:
		return

	_update_intel_column_titles()

	if current_data.intel_reports.is_empty():
		var empty := Label.new()
		empty.text = "No intelligence gathered yet.\nComplete intel-category missions to populate reports."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(empty)
		intel_reports_content.add_child(empty)
		return

	for report in current_data.intel_reports:
		if typeof(report) != TYPE_DICTIONARY:
			continue
		intel_reports_content.add_child(_create_intel_report_row(report as Dictionary))


func _create_intel_report_row(report: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	panel.tooltip_text = (
		"%s intelligence: %d (%s tier).\nGathered by successful intel-category agent missions."
		% [report.get("label", ""), int(report.get("value", 0)), report.get("tier", "")]
	)

	var title := Label.new()
	title.text = "%s — %s" % [report.get("label", ""), report.get("tier", "")]
	RetrowaveTheme.style_body_label(title)

	var tier := str(report.get("tier", ""))
	if tier == "High":
		title.add_theme_color_override("font_color", RetrowaveTheme.SUCCESS)
	elif tier == "Moderate":
		title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)

	var value_label := Label.new()
	value_label.text = "Intel strength: %d" % int(report.get("value", 0))
	RetrowaveTheme.style_body_label(value_label)
	value_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	box.add_child(title)
	box.add_child(value_label)
	return panel


func _populate_national_effects() -> void:
	for child in national_effects_list.get_children():
		child.queue_free()

	if current_data == null:
		return

	if current_data.national_effects.is_empty():
		var empty := Label.new()
		empty.text = "No active national modifiers."
		RetrowaveTheme.style_body_label(empty)
		empty.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		national_effects_list.add_child(empty)
	else:
		for effect in current_data.national_effects:
			if typeof(effect) != TYPE_DICTIONARY:
				continue
			national_effects_list.add_child(_create_national_effect_chip(effect as Dictionary))

	var spirits_btn := Button.new()
	spirits_btn.text = "Open National Spirits…"
	spirits_btn.tooltip_text = "Full national spirits list, filters, and modifier tooltips."
	RetrowaveTheme.style_secondary_button(spirits_btn)
	spirits_btn.pressed.connect(_on_open_national_spirits_pressed)
	national_effects_list.add_child(spirits_btn)


func _on_open_national_spirits_pressed() -> void:
	_open_national_spirits_screen()


func _open_national_spirits_screen() -> void:
	var existing := get_tree().root.get_node_or_null("NationalSpiritsScreen")
	if existing != null:
		existing.queue_free()
		return

	var packed: PackedScene = load("res://scenes/ui/NationalSpiritsScreen.tscn")
	if packed == null:
		return
	var screen: NationalSpiritsScreen = packed.instantiate() as NationalSpiritsScreen
	if screen == null:
		return
	screen.country_tag = country_tag
	screen.name = "NationalSpiritsScreen"
	get_tree().root.add_child(screen)


func _populate_recent_operations() -> void:
	for child in recent_operations_content.get_children():
		child.queue_free()

	if current_data == null:
		return

	if current_data.recent_operations.is_empty():
		var empty := Label.new()
		empty.text = "No operations yet. Deploy agents to build the log."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(empty)
		empty.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		recent_operations_content.add_child(empty)
		return

	for op in current_data.recent_operations:
		if typeof(op) != TYPE_DICTIONARY:
			continue
		recent_operations_content.add_child(_create_operation_log_row(op as Dictionary))


func _create_national_effect_chip(row: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(panel)
	panel.tooltip_text = str(row.get("tooltip_text", ""))
	if bool(row.get("is_debuff", false)):
		panel.modulate = Color(1.0, 0.82, 0.75)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var text := Label.new()
	var mod_lines: Array = row.get("modifier_lines", [])
	var mod_text := str(mod_lines[0]) if mod_lines.size() > 0 else "Active"
	var months := int(row.get("remaining_months", 0))
	text.text = "%s · %s (%d mo)" % [row.get("source_label", "Effect"), mod_text, months]
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(text)
	if bool(row.get("is_debuff", false)):
		text.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
	else:
		text.add_theme_color_override("font_color", RetrowaveTheme.SUCCESS)
	box.add_child(text)

	return panel


func _create_operation_log_row(op: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(panel)
	panel.tooltip_text = _build_operation_tooltip(op)

	if _highlight_ops_pulse and str(op.get("outcome", "")) == "in_progress":
		panel.modulate = Color(1.1, 1.15, 1.2)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)

	var outcome := str(op.get("outcome", ""))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)

	var headline := Label.new()
	var agent_name := str(op.get("agent_name", "Agent"))
	var mission_name := str(op.get("mission_name", "Operation"))
	var target := str(op.get("target_tag", "—"))

	if outcome == "in_progress":
		headline.text = "▶ %s — %s vs %s" % [agent_name, mission_name, target]
		headline.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	else:
		var status_line := str(op.get("status_line", outcome.capitalize()))
		headline.text = "%d · %s — %s" % [int(op.get("year", 0)), agent_name, status_line]
		_colorize_outcome_label(headline, outcome)

	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(headline)
	header.add_child(headline)

	if outcome != "in_progress":
		header.add_child(_outcome_badge(outcome))

	var impact := str(op.get("impact_text", "")).strip_edges()
	if not impact.is_empty():
		var impact_label := Label.new()
		if outcome == "in_progress":
			impact_label.text = impact
		else:
			impact_label.text = "Impact: %s" % impact
		impact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(impact_label)
		impact_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		box.add_child(impact_label)

	if outcome == "in_progress":
		var progress := float(op.get("progress", 0.0))
		var bar_row := HBoxContainer.new()
		bar_row.add_theme_constant_override("separation", 6)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(80, 10)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 1.0
		bar.value = progress
		bar.show_percentage = false
		bar_row.add_child(bar)
		var pct := Label.new()
		pct.text = "%d%%" % int(progress * 100.0)
		RetrowaveTheme.style_body_label(pct)
		pct.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
		bar_row.add_child(pct)
		box.add_child(bar_row)

	var agent_id := _resolve_agent_id_from_op(op)
	if not agent_id.is_empty():
		var view_btn := Button.new()
		view_btn.text = "View Agent"
		RetrowaveTheme.style_secondary_button(view_btn)
		view_btn.pressed.connect(_on_agent_selected.bind(agent_id))
		box.add_child(view_btn)

	return panel


func _resolve_agent_id_from_op(op: Dictionary) -> String:
	var agent_id := str(op.get("agent_id", ""))
	if not agent_id.is_empty():
		return agent_id
	return _find_agent_id_by_name(str(op.get("agent_name", "")))


func _find_agent_id_by_name(agent_name: String) -> String:
	if current_data == null or agent_name.is_empty():
		return ""
	for summary in current_data.agents:
		if typeof(summary) != TYPE_DICTIONARY:
			continue
		if str(summary.get("name", "")) == agent_name:
			return str(summary.get("agent_id", ""))
	return ""


func _outcome_badge(outcome: String) -> Label:
	var badge := Label.new()
	match outcome:
		"success":
			badge.text = "SUCCESS"
			badge.add_theme_color_override("font_color", RetrowaveTheme.SUCCESS)
		"partial":
			badge.text = "PARTIAL"
			badge.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
		"failure":
			badge.text = "FAILURE"
			badge.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
		_:
			badge.text = outcome.capitalize()
	RetrowaveTheme.style_body_label(badge)
	return badge


func _update_detail_panel() -> void:
	for child in missions_list.get_children():
		child.queue_free()
	for child in history_list.get_children():
		child.queue_free()

	if _selected_agent_id.is_empty():
		agent_state_banner.visible = false
		detail_label.text = "Select an agent from the roster."
		assign_mission_button.disabled = true
		return

	var summary := AgentManager.get_agent_summary(_selected_agent_id)
	if summary.is_empty():
		agent_state_banner.visible = false
		detail_label.text = "Agent not found."
		assign_mission_button.disabled = true
		return

	_update_agent_state_banner(summary)
	_clear_detail_progress_bar()
	_populate_mission_history(summary)

	if str(summary.get("status_group", "")) == "on_mission":
		_add_detail_mission_progress(summary)

	var lines: PackedStringArray = [
		summary.get("name", ""),
		"Level %d  •  XP %d  •  %d / %d missions successful" % [
			int(summary.get("level", 1)),
			int(summary.get("experience", 0)),
			int(summary.get("successful_missions", 0)),
			int(summary.get("missions_completed", 0)),
		],
		str(summary.get("skills_text", "")),
	]
	if not str(summary.get("mission_name", "")).is_empty():
		lines.append(
			"Active: %s vs %s (%d%%)"
			% [
				summary.get("mission_name", ""),
				summary.get("assigned_target_tag", ""),
				int(float(summary.get("mission_progress", 0.0)) * 100.0),
			]
		)
		var expected := str(summary.get("active_mission_impact", "")).strip_edges()
		if not expected.is_empty():
			lines.append("On success: %s" % expected)
	detail_label.text = "\n".join(lines)

	if _selected_target_tag.is_empty():
		detail_label.text += "\n\nSelect a target country to view missions."
		assign_mission_button.disabled = true
		return

	detail_label.text += "\n\nTarget: %s" % _selected_target_tag
	if not str(summary.get("assigned_target_tech_name", "")).is_empty():
		detail_label.text += "\nTech target: %s" % summary.get("assigned_target_tech_name", "")
	if typeof(TechnologyManager) != TYPE_NIL:
		var tech_sum: Dictionary = TechnologyManager.get_agent_tech_summary(country_tag)
		if int(tech_sum.get("compromised_tech_count", 0)) > 0:
			detail_label.text += "\nNational compromised tech: %d" % int(
				tech_sum.get("compromised_tech_count", 0)
			)

	if not bool(summary.get("can_assign_mission", false)):
		var note := Label.new()
		note.text = _unavailable_mission_message(summary)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(note)
		if bool(summary.get("is_compromised", false)) or bool(summary.get("is_inactive", false)):
			note.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
		missions_list.add_child(note)
		assign_mission_button.disabled = true
		return

	var category_filter := _selected_mission_category_filter()
	var missions := AgentManager.get_eligible_missions_for_agent(_selected_agent_id, category_filter)
	if missions.is_empty():
		var empty := Label.new()
		if category_filter.is_empty():
			empty.text = "No missions available (skill requirements not met)."
		else:
			empty.text = "No %s missions available for this agent." % category_filter.capitalize()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(empty)
		missions_list.add_child(empty)
		assign_mission_button.disabled = true
		return

	for mission_row in missions:
		if typeof(mission_row) != TYPE_DICTIONARY:
			continue
		missions_list.add_child(_create_mission_preview(mission_row as Dictionary))

	assign_mission_button.disabled = false
	assign_mission_button.text = "Assign Mission to %s..." % _selected_target_tag


func _clear_detail_progress_bar() -> void:
	if _detail_progress_row != null and is_instance_valid(_detail_progress_row):
		_detail_progress_row.queue_free()
	_detail_progress_row = null


func _add_detail_mission_progress(summary: Dictionary) -> void:
	var scroll_vbox := $MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox
	_detail_progress_row = HBoxContainer.new()
	_detail_progress_row.add_theme_constant_override("separation", 8)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 1.0
	bar.value = float(summary.get("mission_progress", 0.0))
	bar.show_percentage = false
	_detail_progress_row.add_child(bar)
	var label := Label.new()
	var pct := int(float(summary.get("mission_progress", 0.0)) * 100.0)
	label.text = "Mission progress: %d%%" % pct
	RetrowaveTheme.style_body_label(label)
	label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	_detail_progress_row.add_child(label)
	var insert_idx: int = detail_label.get_index() + 1
	scroll_vbox.add_child(_detail_progress_row)
	scroll_vbox.move_child(_detail_progress_row, insert_idx)


func _populate_mission_history(summary: Dictionary) -> void:
	var history: Variant = summary.get("mission_history", [])
	if typeof(history) != TYPE_ARRAY or (history as Array).is_empty():
		var empty := Label.new()
		empty.text = "No completed operations on record."
		RetrowaveTheme.style_body_label(empty)
		empty.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		history_list.add_child(empty)
		return

	for entry in history as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		history_list.add_child(_create_history_row(entry as Dictionary))


func _update_agent_state_banner(summary: Dictionary) -> void:
	var group := str(summary.get("status_group", ""))
	if group in ["available"]:
		agent_state_banner.visible = false
		agent_state_label.text = ""
		return

	agent_state_banner.visible = true
	var text := ""

	match group:
		"compromised":
			var until_year := int(summary.get("compromised_until_year", 0))
			var years_left := int(summary.get("recovery_years_remaining", 0))
			text = (
				"COVER BLOWN\n"
				+ "%s is in hiding and cannot run operations."
				% summary.get("name", "Agent")
			)
			if until_year > 0:
				text += "\nExpected return to duty: %d (%d yr remaining)." % [until_year, years_left]
		"inactive":
			var kind := str(summary.get("inactive_kind", ""))
			if kind == "killed":
				text = (
					"KILLED IN ACTION\n"
					+ "%s was lost during a detected operation. They remain on the roster as a record of service."
					% summary.get("name", "Agent")
				)
			elif kind == "captured":
				text = (
					"CAPTURED\n"
					+ "%s was taken by the enemy. All active links to this asset are severed."
					% summary.get("name", "Agent")
				)
			else:
				text = "This agent is no longer available for operations."
		"on_mission":
			text = (
				"DEPLOYED\n"
				+ "%s is in the field. Outcomes will appear in Recent Operations when the mission resolves."
				% summary.get("name", "Agent")
			)
		_:
			text = str(summary.get("status_detail", ""))

	agent_state_label.text = text
	if group == "compromised" or group == "inactive":
		agent_state_label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
	elif group == "on_mission":
		agent_state_label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	else:
		agent_state_label.remove_theme_color_override("font_color")


func _unavailable_mission_message(summary: Dictionary) -> String:
	if bool(summary.get("is_compromised", false)):
		var years := int(summary.get("recovery_years_remaining", 0))
		if years > 0:
			return "Agent is compromised — %d year(s) until they can be deployed again." % years
		return "Agent is compromised and cannot be deployed until recovery completes."
	if bool(summary.get("is_inactive", false)):
		match str(summary.get("inactive_kind", "")):
			"killed":
				return "This agent was killed in action and cannot be assigned missions."
			"captured":
				return "This agent was captured and is no longer operational."
		return "This agent is no longer available for operations."
	return "This agent cannot start a new mission right now."


func _create_history_row(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var outcome := str(entry.get("outcome", "?"))
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	box.add_child(header)

	var headline := Label.new()
	headline.text = "%d · %s vs %s" % [
		int(entry.get("year", 0)),
		entry.get("mission_name", ""),
		entry.get("target_tag", "—"),
	]
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(headline)
	_colorize_outcome_label(headline, outcome)
	header.add_child(headline)
	header.add_child(_outcome_badge(outcome))

	var impact := str(entry.get("impact_text", "")).strip_edges()
	if not impact.is_empty():
		var impact_label := Label.new()
		impact_label.text = impact
		impact_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(impact_label)
		impact_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		box.add_child(impact_label)

	return panel


func _build_agent_row_tooltip(summary: Dictionary) -> String:
	var lines: PackedStringArray = [
		str(summary.get("name", "Agent")),
		str(summary.get("status_detail", "")),
		"Level %d · %d missions (%d successful)" % [
			int(summary.get("level", 1)),
			int(summary.get("missions_completed", 0)),
			int(summary.get("successful_missions", 0)),
		],
		str(summary.get("skills_text", "")),
	]
	if not str(summary.get("mission_name", "")).is_empty():
		lines.append(
			"Active: %s vs %s"
			% [summary.get("mission_name", ""), summary.get("assigned_target_tag", "")]
		)
	return "\n".join(lines)


func _build_operation_tooltip(op: Dictionary) -> String:
	var lines: PackedStringArray = [
		str(op.get("mission_name", "Operation")),
		"Agent: %s" % op.get("agent_name", ""),
		"Target: %s" % op.get("target_tag", "—"),
	]
	var impact := str(op.get("impact_text", "")).strip_edges()
	if not impact.is_empty():
		lines.append("")
		lines.append(impact)
	var fate := str(op.get("agent_fate", ""))
	if not fate.is_empty():
		lines.append("Agent fate: %s" % fate.capitalize())
	return "\n".join(lines)


func _create_mission_preview(mission_row: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(panel)
	var preview: Dictionary = mission_row.get("impact_preview", {})
	if not preview.is_empty():
		panel.tooltip_text = AgentMissionImpact.format_compact_preview(preview)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var chance_pct := int(float(mission_row.get("success_chance", 0.0)) * 100.0)
	var detection := float(mission_row.get("detection_risk", 0.0))
	var risk_label := _detection_risk_label(detection)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	var title := Label.new()
	title.text = "%s (%s) — %d%% success · %d mo" % [
		mission_row.get("name", ""),
		mission_row.get("category", ""),
		chance_pct,
		int(mission_row.get("duration_months", 0)),
	]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(title)
	header.add_child(title)
	header.add_child(risk_label)

	for outcome_key in ["success", "partial", "failure"]:
		var impact_key := "impact_%s" % outcome_key
		var line_text := str(mission_row.get(impact_key, "")).strip_edges()
		if line_text.is_empty():
			continue
		var prefix := "✓" if outcome_key == "success" else ("◐" if outcome_key == "partial" else "✗")
		var line := Label.new()
		line.text = "%s %s" % [prefix, line_text]
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(line)
		line.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		box.add_child(line)

	return panel


func _detection_risk_label(risk: float) -> Label:
	var label := Label.new()
	if risk >= 0.4:
		label.text = "HIGH RISK"
		label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
	elif risk >= 0.25:
		label.text = "MED RISK"
		label.add_theme_color_override("font_color", RetrowaveTheme.MAGENTA)
	else:
		label.text = "LOW RISK"
		label.add_theme_color_override("font_color", RetrowaveTheme.SUCCESS)
	RetrowaveTheme.style_body_label(label)
	return label


func _colorize_outcome_label(label: Label, outcome: String) -> void:
	match outcome:
		"success":
			label.add_theme_color_override("font_color", RetrowaveTheme.SUCCESS)
		"failure":
			label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
		"partial":
			label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
		"in_progress":
			label.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
		_:
			label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)


func _on_agent_selected(agent_id: String) -> void:
	_selected_agent_id = agent_id
	refresh_screen()


func _on_target_selected(target_tag: String) -> void:
	_selected_target_tag = target_tag
	_populate_targets()
	_update_detail_panel()


func _on_recruit_pressed() -> void:
	if typeof(AgentManager) == TYPE_NIL:
		return
	var agent := AgentManager.recruit_agent(country_tag)
	if agent == null:
		return
	_selected_agent_id = agent.agent_id
	if typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.post_news(
			"Agent Recruited",
			"%s has joined the %s intelligence service." % [agent.name, country_tag],
			"espionage",
		)
	refresh_screen()


func _on_open_technology_pressed() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("technology_screen"):
		node.queue_free()
	var scene: PackedScene = load("res://scenes/ui/TechnologyScreen.tscn")
	if scene == null:
		return
	var screen: TechnologyScreen = scene.instantiate() as TechnologyScreen
	if screen == null:
		return
	screen.country_tag = country_tag
	screen.z_index = z_index
	tree.root.add_child(screen)
	screen.refresh_screen()


func _on_assign_mission_pressed() -> void:
	if _selected_agent_id.is_empty() or _selected_target_tag.is_empty():
		return
	var category_filter := _selected_mission_category_filter()
	MissionPickerPopup.open_picker(
		func(picker: MissionPickerPopup) -> void:
			picker.country_tag = country_tag
			picker.agent_id = _selected_agent_id
			picker.target_tag = _selected_target_tag
			picker.category_filter = category_filter
			picker.dialog_title = "Assign Mission — %s" % _selected_target_tag,
	)


func _row_label(text: String, min_width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.clip_text = true
	RetrowaveTheme.style_row_label(label)
	return label
