# scripts/ui/LeaderAssignmentScreen.gd
class_name LeaderAssignmentScreen
extends DraggablePanel

@export var country_tag: String = "GER"

@onready var title_label: Label = $TitleBar/TitleLabel
@onready var close_button: Button = $TitleBar/CloseButton

@onready var total_leaders_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/TotalLeadersLabel
)
@onready var available_leaders_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/AvailableLeadersLabel
)
@onready var injured_leaders_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/InjuredLeadersLabel
)
@onready var captured_leaders_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/CapturedLeadersLabel
)

@onready var national_positions_container: HBoxContainer = (
	$MarginContainer/VBoxContainer/NationalPositionsSection/PositionsContainer
)
@onready var available_header_row: HBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/ListsColumn/AvailableLeadersColumn/AvailableHeaderRow
)
@onready var available_leaders_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/ListsColumn/AvailableLeadersColumn/AvailableLeadersList/AvailableLeadersContent
)
@onready var formations_content: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/ListsColumn/FormationsWithoutLeader/FormationsList/FormationsContent
)
@onready var detail_panel: PanelContainer = $MarginContainer/VBoxContainer/MainArea/DetailPanel
@onready var detail_label: Label = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailScroll/DetailVBox/DetailLabel
)

var current_data: LeaderScreenData
var _detail_traits_box: VBoxContainer
var _selected_leader_id: String = ""
var _pending_replacements_button: Button
var _national_spirits_button: Button

const NATIONAL_POSITIONS: Array[Dictionary] = [
	{"key": LeaderManager.POSITION_CHIEF_OF_ARMY, "label": "Chief of Army"},
	{"key": LeaderManager.POSITION_CHIEF_OF_NAVY, "label": "Chief of Navy"},
	{"key": LeaderManager.POSITION_CHIEF_OF_AIR_FORCE, "label": "Chief of Air Force"},
	{"key": LeaderManager.POSITION_CHIEF_OF_SPACE_FORCE, "label": "Chief of Space Force"},
]

const HEADER_SPECS: Array[Dictionary] = [
	{"text": "", "width": 28},  # portrait icon col
	{"text": "Name", "width": 140},
	{"text": "Status", "width": 88},
	{"text": "Type", "width": 72},
	{"text": "Skills", "width": 128},
	{"text": "Traits", "width": 150},
	{"text": "XP", "width": 48},
	{"text": "", "width": 0, "expand": true},
	{"text": "Assign", "width": 80},
	{"text": "Details", "width": 80},
]
const ROW_HEIGHT := 36


func _ready() -> void:
	add_to_group("leader_screen")
	drag_handle = $TitleBar
	super._ready()
	_apply_content_margins()
	_setup_detail_panel()
	_apply_screen_theme()
	_setup_headers()
	close_button.pressed.connect(_on_close_pressed)
	_setup_pending_replacements_badge()
	_setup_national_spirits_button()
	_connect_leader_replacement_signals()
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
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_secondary_button(close_button)
	_apply_screen_title()
	RetrowaveTheme.style_summary_metric(total_leaders_label)
	RetrowaveTheme.style_summary_metric(available_leaders_label, RetrowaveTheme.SUCCESS)
	RetrowaveTheme.style_summary_metric(injured_leaders_label, RetrowaveTheme.WARNING)
	RetrowaveTheme.style_summary_metric(captured_leaders_label, RetrowaveTheme.MAGENTA)
	RetrowaveTheme.style_title($MarginContainer/VBoxContainer/NationalPositionsSection/SectionTitle)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/ListsColumn/AvailableLeadersColumn/AvailableLeadersTitle,
	)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainArea/ListsColumn/FormationsWithoutLeader/FormationsTitle,
	)
	RetrowaveTheme.style_detail_panel(detail_panel)
	RetrowaveTheme.style_detail_label(detail_label)


func _setup_detail_panel() -> void:
	_detail_traits_box = (
		detail_panel.get_node_or_null("DetailMargin/DetailScroll/DetailVBox/DetailTraitsVBox")
		as VBoxContainer
	)
	if _detail_traits_box == null:
		push_warning("LeaderAssignmentScreen: DetailTraitsVBox missing from scene")


func _setup_headers() -> void:
	if available_header_row == null:
		available_header_row = get_node_or_null(
			"MarginContainer/VBoxContainer/MainArea/ListsColumn/AvailableLeadersColumn/AvailableHeaderRow"
		) as HBoxContainer
	if available_header_row == null:
		push_warning("LeaderAssignmentScreen: AvailableHeaderRow not found")
		return

	for child in available_header_row.get_children():
		child.queue_free()

	for spec in HEADER_SPECS:
		if bool(spec.get("expand", false)):
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			available_header_row.add_child(spacer)
			continue

		var label := Label.new()
		label.text = str(spec.get("text", ""))
		var width := int(spec.get("width", 100))
		if width > 0:
			label.custom_minimum_size = Vector2(width, 0)
		RetrowaveTheme.style_column_header(label)
		available_header_row.add_child(label)


func refresh_screen() -> void:
	current_data = LeaderManager.get_leader_screen_data(country_tag, false)
	_update_summary_bar()
	_update_pending_replacements_badge()
	_populate_national_positions()
	_populate_available_leaders()
	_populate_unassigned_formations()


func _setup_national_spirits_button() -> void:
	var summary_bar := total_leaders_label.get_parent() as HBoxContainer
	if summary_bar == null:
		return

	_national_spirits_button = Button.new()
	_national_spirits_button.text = "National Spirits"
	_national_spirits_button.tooltip_text = "View national spirits and temporary modifiers."
	RetrowaveTheme.style_secondary_button(_national_spirits_button)
	_national_spirits_button.pressed.connect(_on_national_spirits_pressed)
	summary_bar.add_child(_national_spirits_button)


func _on_national_spirits_pressed() -> void:
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


func _setup_pending_replacements_badge() -> void:
	var summary_bar := total_leaders_label.get_parent() as HBoxContainer
	if summary_bar == null:
		return

	_pending_replacements_button = Button.new()
	_pending_replacements_button.visible = false
	_pending_replacements_button.text = "Replacements (0)"
	_pending_replacements_button.tooltip_text = (
		"Command vacancies awaiting your decision. Click to resolve the next one."
	)
	RetrowaveTheme.style_primary_button(_pending_replacements_button)
	_pending_replacements_button.pressed.connect(_on_pending_replacements_pressed)
	summary_bar.add_child(_pending_replacements_button)


func _connect_leader_replacement_signals() -> void:
	if typeof(LeaderManager) == TYPE_NIL:
		return
	if not LeaderManager.leader_replacement_needed.is_connected(_on_leader_replacement_queue_changed):
		LeaderManager.leader_replacement_needed.connect(_on_leader_replacement_queue_changed)
	if not LeaderManager.leader_replacement_resolved.is_connected(_on_leader_replacement_queue_changed):
		LeaderManager.leader_replacement_resolved.connect(_on_leader_replacement_queue_changed)


func _exit_tree() -> void:
	if typeof(LeaderManager) == TYPE_NIL:
		return
	if LeaderManager.leader_replacement_needed.is_connected(_on_leader_replacement_queue_changed):
		LeaderManager.leader_replacement_needed.disconnect(_on_leader_replacement_queue_changed)
	if LeaderManager.leader_replacement_resolved.is_connected(_on_leader_replacement_queue_changed):
		LeaderManager.leader_replacement_resolved.disconnect(_on_leader_replacement_queue_changed)


func _on_leader_replacement_queue_changed(
	_arg1: Variant = null,
	_arg2: Variant = null,
	_arg3: Variant = null,
) -> void:
	if not is_inside_tree():
		return
	var event_country := ""
	if _arg1 is Dictionary:
		event_country = str((_arg1 as Dictionary).get("country_tag", ""))
	if event_country.is_empty() or event_country == country_tag:
		_update_pending_replacements_badge()


func _update_pending_replacements_badge() -> void:
	if _pending_replacements_button == null:
		return
	if not LeaderManager.is_player_country(country_tag):
		_pending_replacements_button.visible = false
		_apply_screen_title()
		return

	var pending_count := LeaderManager.get_pending_replacement_count(country_tag)
	_pending_replacements_button.visible = pending_count > 0
	if pending_count > 0:
		_pending_replacements_button.text = "Replacements (%d)" % pending_count
		_pending_replacements_button.modulate = RetrowaveTheme.WARNING
	else:
		_pending_replacements_button.modulate = Color.WHITE
	_apply_screen_title()


func _apply_screen_title() -> void:
	var base := "Leader Assignment — %s" % country_tag
	if (
		LeaderManager.is_player_country(country_tag)
		and LeaderManager.get_pending_replacement_count(country_tag) > 0
	):
		title_label.text = "%s  •  %d replacement(s) pending" % [
			base,
			LeaderManager.get_pending_replacement_count(country_tag),
		]
		title_label.modulate = RetrowaveTheme.WARNING
	else:
		title_label.text = base
		title_label.modulate = Color.WHITE


func _on_pending_replacements_pressed() -> void:
	var pending := LeaderManager.get_pending_leader_replacements(country_tag)
	if pending.is_empty():
		_update_pending_replacements_badge()
		return
	var request_id := str(pending[0].get("request_id", ""))
	if request_id.is_empty():
		return
	LeaderReplacementPickerPopup.open_for_request(request_id)


func _update_summary_bar() -> void:
	if current_data == null:
		return

	total_leaders_label.text = "Total Leaders: %d" % current_data.total_leaders
	available_leaders_label.text = "Available: %d" % current_data.available_leaders
	injured_leaders_label.text = "Injured: %d" % current_data.injured_leaders
	captured_leaders_label.text = "Captured: %d" % current_data.captured_leaders

	if current_data.injured_leaders > 0:
		injured_leaders_label.modulate = (
			RetrowaveTheme.WARNING if current_data.has_many_injured else Color(1.0, 0.9, 0.2)
		)
	else:
		injured_leaders_label.modulate = Color.WHITE


# =====================
# NATIONAL POSITIONS
# =====================

func _populate_national_positions() -> void:
	for child in national_positions_container.get_children():
		child.queue_free()

	for entry in NATIONAL_POSITIONS:
		var position_key: String = str(entry.get("key", ""))
		var display_name: String = str(entry.get("label", position_key))
		var leader: Leader = LeaderManager.get_country_position_leader(country_tag, position_key)
		var card: Control = _create_national_position_card(display_name, position_key, leader)
		national_positions_container.add_child(card)

	var officer_training_card := _create_officer_training_card()
	national_positions_container.add_child(officer_training_card)


func _create_officer_training_card() -> Control:
	var training_leader := LeaderManager.get_officer_training_leader(country_tag)
	# Auto-clean bad/unavailable mentor (retired, deceased, captured, or otherwise unavailable) so card shows clean "Vacant"/"Assign"
	# like national position cards. Brand-new leaders are intentionally allowed (even if is_available_for_command is edge false during intro).
	if training_leader != null and not _leader_valid_for_officer_training(training_leader):
		LeaderManager.clear_officer_training_leader(country_tag)
		training_leader = null

	var quality_info := LeaderManager.get_officer_training_quality_display(country_tag)
	var debuff_months := LeaderManager.get_officer_training_debuff_months(country_tag)
	var cadet_cost := LeaderManager.get_officer_training_cadet_prestige_cost()

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(185, 155)  # Increased height to fit debuff info
	RetrowaveTheme.style_detail_panel(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Officer Training"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	RetrowaveTheme.style_column_header(title)
	vbox.add_child(title)

	var is_vacant := training_leader == null or (training_leader != null and not _leader_valid_for_officer_training(training_leader))
	var leader_name := Label.new()
	leader_name.text = "Vacant" if is_vacant else training_leader.name
	leader_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_vacant:
		leader_name.modulate = RetrowaveTheme.WARNING
	leader_name.add_theme_font_size_override("font_size", 13)
	RetrowaveTheme.style_row_label(leader_name)
	vbox.add_child(leader_name)

	var quality_label := Label.new()
	quality_label.text = str(quality_info.get("text", "Poor (0%)"))
	quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quality_label.add_theme_font_size_override("font_size", 12)
	quality_label.modulate = quality_info.get("color", Color.WHITE)
	vbox.add_child(quality_label)

	var status_label := Label.new()
	status_label.text = LeaderManager.get_officer_training_status_text(country_tag)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 10)

	# Highlight status in warning color when recovering from mentor change
	if debuff_months > 0:
		status_label.modulate = RetrowaveTheme.WARNING
	else:
		status_label.modulate = Color(0.65, 0.65, 0.65)
	vbox.add_child(status_label)

	# Show temporary debuff / recovery state prominently
	if debuff_months > 0:
		var debuff_label := Label.new()
		debuff_label.text = "Recovering from mentor change (%d mo)" % debuff_months
		debuff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		debuff_label.add_theme_font_size_override("font_size", 9)
		debuff_label.modulate = RetrowaveTheme.WARNING
		vbox.add_child(debuff_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 6)

	var change_btn := Button.new()
	change_btn.text = "Assign" if is_vacant else "Change"
	change_btn.custom_minimum_size = Vector2(70, 24)
	RetrowaveTheme.style_secondary_button(change_btn)
	change_btn.pressed.connect(_on_assign_officer_training_pressed)
	hbox.add_child(change_btn)

	var generate_btn := Button.new()
	# Show the Prestige cost directly on the button
	generate_btn.text = "Generate Cadet (-%d Prestige)" % int(cadet_cost)
	generate_btn.custom_minimum_size = Vector2(140, 24)
	RetrowaveTheme.style_primary_button(generate_btn)
	generate_btn.pressed.connect(_on_generate_cadet_pressed)
	hbox.add_child(generate_btn)

	vbox.add_child(hbox)

	return panel


func _on_generate_cadet_pressed() -> void:
	# Use the proper entry point so per-cadet Prestige cost is applied
	var new_leader := LeaderManager.generate_and_register_leader_from_training(country_tag)
	if new_leader == null:
		return

	if typeof(LeaderEventUI) != TYPE_NIL:
		var branch_label := new_leader.leader_type.replace("_", " ").capitalize()
		LeaderEventUI.post_news(
			"Officer Graduated",
			"%s joined the roster as %s." % [new_leader.name, branch_label],
			"military",
		)
	refresh_screen()


func _on_assign_officer_training_pressed() -> void:
	LeaderPickerPopup.open_picker(
		func(picker: LeaderPickerPopup) -> void:
			picker.country_tag = country_tag
			picker.position_key = LeaderManager.POSITION_OFFICER_TRAINING
			picker.dialog_title = "Assign Officer Training Command",
	)


func _create_national_position_card(
	display_name: String,
	position_key: String,
	leader: Leader,
) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 96)
	RetrowaveTheme.style_detail_panel(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetrowaveTheme.style_column_header(title)
	vbox.add_child(title)

	var is_vacant := leader == null or (leader != null and (leader.is_retired or leader.is_deceased or not leader.is_available_for_command()))
	var leader_name := Label.new()
	leader_name.text = "Vacant" if is_vacant else leader.name
	leader_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_vacant and position_key == LeaderManager.POSITION_CHIEF_OF_ARMY:
		leader_name.modulate = RetrowaveTheme.WARNING
	RetrowaveTheme.style_row_label(leader_name)
	vbox.add_child(leader_name)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var change_btn := Button.new()
	change_btn.text = "Assign" if is_vacant else "Change"
	RetrowaveTheme.style_secondary_button(change_btn)
	change_btn.pressed.connect(_on_change_national_position.bind(position_key))
	btn_row.add_child(change_btn)

	if leader != null:
		var details_btn := Button.new()
		details_btn.text = "Details"
		RetrowaveTheme.style_secondary_button(details_btn)
		details_btn.pressed.connect(
			_on_national_position_details_pressed.bind(leader.leader_id)
		)
		btn_row.add_child(details_btn)

	vbox.add_child(btn_row)

	return panel


func _on_national_position_details_pressed(leader_id: String) -> void:
	var summary := LeaderManager.get_leader_summary(leader_id)
	if summary.is_empty():
		return
	_open_leader_detail_screen(summary)


func _on_change_national_position(position_key: String) -> void:
	var display_name := _position_display_name(position_key)
	LeaderPickerPopup.open_picker(
		func(picker: LeaderPickerPopup) -> void:
			picker.country_tag = country_tag
			picker.position_key = position_key
			picker.dialog_title = "Assign %s" % display_name,
	)

## Local validity for officer training mentor display/assignment (mirrors can_assign + brand-new exception).
## Used to show "Vacant"/"Assign" cleanly and auto-clear bad state so user can assign a fresh/new leader (e.g. cadet) without seeing stale "retiring" mentor.
func _leader_valid_for_officer_training(leader: Leader) -> bool:
	if leader == null:
		return false
	if leader.is_injured or leader.is_captured or leader.is_retired or leader.is_deceased:
		return false
	# Brand new (recent start_year, e.g. Patton in 1936 start) are allowed as mentors even during intro window.
	# (Duplicate lightweight check to avoid calling private; mirrors LeaderManager._is_brand_new + popup logic.)
	if leader.start_year > 0 and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_current_year"):
		var cy: int = LeaderManager.get_current_year()
		if cy - leader.start_year < 2:
			return true
	if not leader.is_available_for_command():
		# Non-brand-new unavailable are invalid for mentor.
		return false
	return true


# =====================
# AVAILABLE LEADERS
# =====================

func _populate_available_leaders() -> void:
	for child in available_leaders_list.get_children():
		child.queue_free()

	if current_data == null:
		return

	for leader_summary in current_data.leaders:
		if bool(leader_summary.get("is_captured", false)):
			continue
		if bool(leader_summary.get("is_injured", false)):
			continue
		available_leaders_list.add_child(_create_leader_row(leader_summary))


func _populate_unassigned_formations() -> void:
	for child in formations_content.get_children():
		child.queue_free()

	var available_formations: Array[Dictionary] = LeaderManager.get_available_formations(country_tag)
	if available_formations.is_empty():
		var note := Label.new()
		note.text = "No formations without a leader."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(note)
		formations_content.add_child(note)
		return

	for formation in available_formations:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)

		var name_label := Label.new()
		name_label.text = str(formation.get("name", formation.get("formation_id", "")))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		RetrowaveTheme.style_row_label(name_label)
		row.add_child(name_label)

		var type_label := Label.new()
		type_label.text = str(formation.get("type", "division"))
		RetrowaveTheme.style_body_label(type_label)
		row.add_child(type_label)

		formations_content.add_child(row)


func _create_leader_row(summary: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	hbox.add_theme_constant_override("separation", 4)

	# Portrait icon (new leader portraits support in list UIs)
	var p_rect := TextureRect.new()
	p_rect.custom_minimum_size = Vector2(24, 24)
	p_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	p_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var ppath := str(summary.get("portrait_path", ""))
	if ppath != "" and ResourceLoader.exists(ppath):
		var tex := load(ppath) as Texture2D
		if tex:
			p_rect.texture = tex
	p_rect.visible = p_rect.texture != null
	hbox.add_child(p_rect)

	var name_btn := Button.new()
	var leader_name := str(summary.get("name", "Unknown"))
	if _leader_has_level_up_option(summary):
		leader_name += " ▲"
	name_btn.text = leader_name
	name_btn.flat = true
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.custom_minimum_size = Vector2(140, 0)
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.clip_text = true
	_style_leader_name_button(name_btn)
	name_btn.pressed.connect(_on_leader_name_pressed.bind(summary))
	hbox.add_child(name_btn)

	hbox.add_child(_row_label(_format_leader_status(summary), 88))

	var type_name: String = str(summary.get("leader_type_name", summary.get("leader_type", "")))
	hbox.add_child(_row_label(type_name.capitalize(), 72))
	hbox.add_child(
		_row_label(
			"A:%d  D:%d  L:%d  P:%d" % [
				int(summary.get("attack_skill", 0)),
				int(summary.get("defense_skill", 0)),
				int(summary.get("logistics_skill", 0)),
				int(summary.get("planning_skill", 0)),
			],
			128,
		)
	)
	hbox.add_child(_row_label(_format_traits_row(summary), 150))

	var xp_label := Label.new()
	xp_label.text = str(int(summary.get("experience", 0)))
	xp_label.custom_minimum_size = Vector2(48, 0)
	xp_label.clip_text = true
	xp_label.add_theme_color_override("font_color", RetrowaveTheme.SUCCESS)
	RetrowaveTheme.style_row_label(xp_label)
	hbox.add_child(xp_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var assign_btn := Button.new()
	assign_btn.text = "Assign"
	assign_btn.custom_minimum_size = Vector2(80, 0)
	RetrowaveTheme.style_primary_button(assign_btn)
	var is_assigned := not str(summary.get("assigned_army_id", "")).is_empty()
	assign_btn.disabled = is_assigned
	if is_assigned:
		assign_btn.text = "Assigned"
	assign_btn.pressed.connect(_on_assign_pressed.bind(summary))
	hbox.add_child(assign_btn)

	var details_btn := Button.new()
	details_btn.text = "Details"
	details_btn.custom_minimum_size = Vector2(80, 0)
	RetrowaveTheme.style_secondary_button(details_btn)
	details_btn.pressed.connect(_on_details_pressed.bind(summary))
	hbox.add_child(details_btn)

	return hbox


func _style_leader_name_button(button: Button) -> void:
	button.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	button.add_theme_color_override("font_hover_color", RetrowaveTheme.MAGENTA)
	button.add_theme_color_override("font_pressed_color", RetrowaveTheme.MAGENTA)
	button.add_theme_font_size_override("font_size", 14)
	button.focus_mode = Control.FOCUS_NONE


func _leader_has_level_up_option(summary: Dictionary) -> bool:
	for entry in summary.get("trait_display", []) as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if bool((entry as Dictionary).get("can_level_up", false)):
			return true
	return false


func _on_leader_name_pressed(summary: Dictionary) -> void:
	_open_leader_detail_screen(summary)


func _open_leader_detail_screen(summary: Dictionary) -> void:
	var leader_id := str(summary.get("leader_id", ""))
	if leader_id.is_empty():
		return
	_selected_leader_id = leader_id
	var tree := get_tree()
	if tree != null and tree.root != null:
		LeaderDetailScreen.open(tree.root, leader_id)
	else:
		LeaderDetailScreen.open(self, leader_id)


func _row_label(text: String, min_width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.clip_text = true
	RetrowaveTheme.style_row_label(label)
	return label


func _format_leader_status(summary: Dictionary) -> String:
	var leader_id := str(summary.get("leader_id", ""))
	if leader_id.is_empty():
		return "—"
	for entry in NATIONAL_POSITIONS:
		var position_key: String = str(entry.get("key", ""))
		var posted: Leader = LeaderManager.get_country_position_leader(country_tag, position_key)
		if posted != null and posted.leader_id == leader_id:
			return "National"
	var assigned := str(summary.get("assigned_army_id", ""))
	if not assigned.is_empty():
		return "Army"
	return "Free"


func _format_traits_row(summary: Dictionary) -> String:
	var display: Array = summary.get("trait_display", []) as Array
	if not display.is_empty():
		var parts: PackedStringArray = []
		for entry in display:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var row := entry as Dictionary
			var roman: String = str(row.get("roman", ""))
			var suffix := " %s" % roman if not roman.is_empty() else ""
			parts.append("%s%s" % [row.get("name", row.get("id", "")), suffix])
		return ", ".join(parts)

	var traits: Array = summary.get("traits", []) as Array
	return ", ".join(traits)


func _on_details_pressed(summary: Dictionary) -> void:
	_open_leader_detail_screen(summary)
	detail_label.text = "Name: %s\n(Character sheet opened.)" % summary.get("name", "")
	_populate_trait_detail(summary)


func _populate_trait_detail(summary: Dictionary) -> void:
	if _detail_traits_box == null:
		return
	for child in _detail_traits_box.get_children():
		child.queue_free()

	var display: Array = summary.get("trait_display", []) as Array
	if display.is_empty():
		var note := Label.new()
		note.text = "No traits."
		RetrowaveTheme.style_body_label(note)
		_detail_traits_box.add_child(note)
		return

	var leader_xp := int(summary.get("experience", 0))
	for entry in display:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row := entry as Dictionary
		var trait_row := VBoxContainer.new()
		trait_row.add_theme_constant_override("separation", 2)

		var title := Label.new()
		var level := int(row.get("level", 1))
		var max_level := int(row.get("max_level", 1))
		var roman: String = str(row.get("roman", ""))
		title.text = "%s %s (%d/%d)" % [row.get("name", ""), roman, level, max_level]
		RetrowaveTheme.style_column_header(title)
		trait_row.add_child(title)

		var desc := str(row.get("description", ""))
		var effects_text := str(row.get("effects_text", ""))
		if not desc.is_empty() or not effects_text.is_empty():
			var body := Label.new()
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.text = desc
			if not effects_text.is_empty():
				body.text += "\n" + effects_text if not desc.is_empty() else effects_text
			RetrowaveTheme.style_body_label(body)
			trait_row.add_child(body)

		if bool(row.get("can_level_up", false)):
			var cost := int(row.get("level_up_cost", 0))
			var level_btn := Button.new()
			level_btn.text = "Level Up (%d XP)" % cost
			RetrowaveTheme.style_primary_button(level_btn)
			level_btn.disabled = leader_xp < cost
			var trait_id: String = str(row.get("id", ""))
			level_btn.pressed.connect(_on_level_trait_pressed.bind(trait_id))
			trait_row.add_child(level_btn)

		_detail_traits_box.add_child(trait_row)


func _on_level_trait_pressed(trait_id: String) -> void:
	if _selected_leader_id.is_empty():
		return
	var result: Dictionary = LeaderManager.spend_xp_on_trait(_selected_leader_id, trait_id)
	if not bool(result.get("success", false)):
		push_warning("Could not level trait %s: %s" % [trait_id, result.get("reason", "")])
		return
	refresh_screen()
	var leader_summary := LeaderManager.get_leader_summary(_selected_leader_id)
	if not leader_summary.is_empty():
		_on_details_pressed(leader_summary)


func _on_assign_pressed(summary: Dictionary) -> void:
	var leader_id: String = str(summary.get("leader_id", ""))
	if leader_id.is_empty():
		return

	var picker_scene: PackedScene = load("res://scenes/ui/FormationPickerPopup.tscn")
	if picker_scene == null:
		push_warning("FormationPickerPopup.tscn not found")
		return

	var picker: FormationPickerPopup = picker_scene.instantiate() as FormationPickerPopup
	if picker == null:
		return

	picker.leader_id = leader_id
	picker.country_tag = country_tag
	picker.leader_name = str(summary.get("name", ""))
	var tree := get_tree()
	if tree != null and tree.root != null:
		tree.root.add_child(picker)


func _position_display_name(position_key: String) -> String:
	for entry in NATIONAL_POSITIONS:
		if str(entry.get("key", "")) == position_key:
			return str(entry.get("label", position_key))
	return position_key
