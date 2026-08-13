# scripts/ui/NationalSpiritsScreen.gd
class_name NationalSpiritsScreen
extends DraggablePanel

@export var country_tag: String = "USA"

@onready var title_label: Label = $TitleBar/TitleLabel
@onready var close_button: Button = $TitleBar/CloseButton
@onready var spirits_count_label: Label = $MarginContainer/VBoxContainer/SummaryBar/SpiritsCountLabel
@onready var effects_count_label: Label = $MarginContainer/VBoxContainer/SummaryBar/EffectsCountLabel
@onready var view_filter: OptionButton = $MarginContainer/VBoxContainer/FilterRow/ViewFilter
@onready var category_filter: OptionButton = $MarginContainer/VBoxContainer/FilterRow/CategoryFilter
@onready var search_edit: LineEdit = $MarginContainer/VBoxContainer/FilterRow/SearchEdit
@onready var filter_status_label: Label = $MarginContainer/VBoxContainer/FilterStatusLabel
@onready var detail_label: Label = (
	$MarginContainer/VBoxContainer/DetailScroll/DetailPanel/DetailMargin/DetailLabel
)
@onready var detail_panel: PanelContainer = (
	$MarginContainer/VBoxContainer/DetailScroll/DetailPanel
)
@onready var detail_scroll: ScrollContainer = $MarginContainer/VBoxContainer/DetailScroll
@onready var permanent_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainScroll/MainVBox/PermanentList
)
@onready var temporary_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainScroll/MainVBox/TemporaryList
)

var current_data: NationalSpiritsScreenData
var _selected_entry_id: String = ""
var _view_filters_ready: bool = false

const FILTER_ALL := 0
const FILTER_PERMANENT := 1
const FILTER_TEMPORARY := 2
const FILTER_BUFFS := 3
const FILTER_DEBUFFS := 4


func _ready() -> void:
	add_to_group("national_spirits_screen")
	drag_handle = $TitleBar
	super._ready()
	close_button.pressed.connect(_on_close_pressed)
	_setup_filters()
	_apply_screen_theme()
	_connect_signals()
	refresh_screen()


func _setup_filters() -> void:
	if _view_filters_ready:
		return
	view_filter.clear()
	view_filter.add_item("All")
	view_filter.add_item("Permanent Spirits")
	view_filter.add_item("Temporary Effects")
	view_filter.add_item("Buffs Only")
	view_filter.add_item("Debuffs Only")
	view_filter.select(0)
	_view_filters_ready = true


func _apply_screen_theme() -> void:
	clip_contents = true
	# Recenter / size for modern HUD so content is not clipped.
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(920, 640)
	offset_left = -460.0
	offset_top = -340.0
	offset_right = 460.0
	offset_bottom = 340.0
	RetrowaveTheme.style_production_screen(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_secondary_button(close_button)
	RetrowaveTheme.style_summary_metric(spirits_count_label)
	RetrowaveTheme.style_summary_metric(effects_count_label, RetrowaveTheme.MAGENTA)
	RetrowaveTheme.style_filter_option(view_filter)
	RetrowaveTheme.style_filter_option(category_filter)
	RetrowaveTheme.style_search(search_edit)
	RetrowaveTheme.style_body_label(filter_status_label)
	filter_status_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	# Flat frame so L/R border + text are not clipped by 9-slice ornaments.
	RetrowaveTheme.style_detail_panel_flat(detail_panel)
	RetrowaveTheme.style_detail_label(detail_label)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_panel.clip_contents = false
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_margin := get_node_or_null(
		"MarginContainer/VBoxContainer/DetailScroll/DetailPanel/DetailMargin"
	) as MarginContainer
	if detail_margin != null:
		detail_margin.add_theme_constant_override("margin_left", 14)
		detail_margin.add_theme_constant_override("margin_right", 14)
		detail_margin.add_theme_constant_override("margin_top", 10)
		detail_margin.add_theme_constant_override("margin_bottom", 10)
		detail_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if detail_scroll != null:
		detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		detail_scroll.clip_contents = true
		detail_scroll.custom_minimum_size = Vector2(0, 140)
		detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_wrap(detail_label)
	_apply_wrap(filter_status_label)
	var footer := $MarginContainer/VBoxContainer/MainScroll/MainVBox/FooterLabel as Label
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainScroll/MainVBox/PermanentTitle,
	)
	RetrowaveTheme.style_title(
		$MarginContainer/VBoxContainer/MainScroll/MainVBox/TemporaryTitle,
		RetrowaveTheme.MAGENTA,
	)
	RetrowaveTheme.style_body_label(footer)
	_apply_wrap(footer)
	var main_scroll := $MarginContainer/VBoxContainer/MainScroll as ScrollContainer
	if main_scroll != null:
		main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		main_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		main_scroll.clip_contents = true
		main_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var main_vbox := $MarginContainer/VBoxContainer/MainScroll/MainVBox as VBoxContainer
	if main_vbox != null:
		main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.placeholder_text = "Search spirits and effects..."
	# Re-wrap detail after layout settles.
	call_deferred("_relayout_wrap")


func _connect_signals() -> void:
	view_filter.item_selected.connect(_on_filter_changed)
	category_filter.item_selected.connect(_on_filter_changed)
	search_edit.text_changed.connect(_on_filter_changed)
	view_filter.tooltip_text = "Filter which spirits and effects appear in the list."
	category_filter.tooltip_text = "Filter permanent spirits by category."
	search_edit.tooltip_text = "Search names, descriptions, sources, and modifiers."
	if typeof(NationalModifierManager) == TYPE_NIL:
		return
	if not NationalModifierManager.national_modifier_applied.is_connected(_on_modifiers_changed):
		NationalModifierManager.national_modifier_applied.connect(_on_modifiers_changed)
	if not NationalModifierManager.national_modifier_expired.is_connected(_on_modifiers_changed):
		NationalModifierManager.national_modifier_expired.connect(_on_modifiers_changed)


func _exit_tree() -> void:
	if typeof(NationalModifierManager) == TYPE_NIL:
		return
	if NationalModifierManager.national_modifier_applied.is_connected(_on_modifiers_changed):
		NationalModifierManager.national_modifier_applied.disconnect(_on_modifiers_changed)
	if NationalModifierManager.national_modifier_expired.is_connected(_on_modifiers_changed):
		NationalModifierManager.national_modifier_expired.disconnect(_on_modifiers_changed)


func _on_modifiers_changed(tag: String, _id: String = "") -> void:
	if tag == country_tag.strip_edges().to_upper() and is_inside_tree():
		refresh_screen()


func _on_filter_changed(_arg: Variant = null) -> void:
	_populate_lists()


func _on_close_pressed() -> void:
	queue_free()


func refresh_screen(_ignored: Variant = null) -> void:
	if typeof(NationalSpiritManager) == TYPE_NIL:
		return
	current_data = NationalSpiritManager.get_spirits_screen_data(country_tag)
	title_label.text = "National Spirits — %s" % country_tag
	spirits_count_label.text = "Spirits: %d" % current_data.permanent_spirit_count
	var debuff_count := _count_debuffs()
	effects_count_label.text = "Temporary: %d" % current_data.temporary_effect_count
	if debuff_count > 0:
		effects_count_label.text += " (%d debuffs)" % debuff_count
		effects_count_label.modulate = RetrowaveTheme.WARNING
	else:
		effects_count_label.modulate = Color.WHITE
	_sync_category_filter()
	_populate_lists()
	_update_filter_status()
	if _selected_entry_id.is_empty():
		detail_label.text = "Select a spirit or effect for details. Hover any card for a quick summary."


func _sync_category_filter() -> void:
	var previous := ""
	if category_filter.item_count > 0 and category_filter.selected >= 0:
		previous = category_filter.get_item_text(category_filter.selected)

	category_filter.clear()
	category_filter.add_item("All Categories")
	for cat in current_data.spirit_categories:
		category_filter.add_item(cat.capitalize())

	var pick := 0
	for i in range(category_filter.item_count):
		if category_filter.get_item_text(i) == previous:
			pick = i
			break
	category_filter.select(pick)
	category_filter.visible = current_data.spirit_categories.size() > 1


func _count_debuffs() -> int:
	var count := 0
	if current_data == null:
		return 0
	for effect in current_data.temporary_effects:
		if bool(effect.get("is_debuff", false)):
			count += 1
	return count


func _update_filter_status() -> void:
	if current_data == null:
		filter_status_label.text = ""
		return
	var perm_shown := _filtered_permanent_rows().size()
	var temp_shown := _filtered_temporary_rows().size()
	var perm_total := current_data.permanent_spirit_count
	var temp_total := current_data.temporary_effect_count
	var parts: PackedStringArray = [
		"Showing %d / %d spirits" % [perm_shown, perm_total],
		"%d / %d temporary effects" % [temp_shown, temp_total],
	]
	if _count_agent_mission_effects() > 0:
		parts.append("%d from agent operations" % _count_agent_mission_effects())
	filter_status_label.text = " · ".join(parts)


func _count_agent_mission_effects() -> int:
	var count := 0
	if current_data == null:
		return 0
	for effect in current_data.temporary_effects:
		if str(effect.get("source", "")) in ["agent_mission", "influence", "agent_influence"]:
			count += 1
	return count


func _populate_lists() -> void:
	var perm_title := $MarginContainer/VBoxContainer/MainScroll/MainVBox/PermanentTitle as Label
	var temp_title := $MarginContainer/VBoxContainer/MainScroll/MainVBox/TemporaryTitle as Label
	if perm_title != null:
		perm_title.visible = view_filter.selected != FILTER_TEMPORARY
	if temp_title != null:
		temp_title.visible = view_filter.selected != FILTER_PERMANENT
	_populate_permanent()
	_populate_temporary()


func _populate_permanent() -> void:
	for child in permanent_list.get_children():
		child.queue_free()

	var rows := _filtered_permanent_rows()
	if rows.is_empty():
		permanent_list.add_child(_empty_label(_empty_message_permanent()))
		return

	for spirit in rows:
		permanent_list.add_child(_create_entry_panel(spirit as Dictionary, false))


func _populate_temporary() -> void:
	for child in temporary_list.get_children():
		child.queue_free()

	if view_filter.selected == FILTER_PERMANENT:
		temporary_list.add_child(
			_empty_label("Temporary effects hidden by filter.")
		)
		return

	var rows := _filtered_temporary_rows()
	if rows.is_empty():
		temporary_list.add_child(_empty_label(_empty_message_temporary()))
		return

	for effect in rows:
		temporary_list.add_child(_create_entry_panel(effect as Dictionary, true))


func _filtered_permanent_rows() -> Array[Dictionary]:
	if view_filter.selected in [FILTER_TEMPORARY, FILTER_DEBUFFS]:
		return []

	var result: Array[Dictionary] = []
	var category_needle := _selected_category_filter()
	var search := search_edit.text.strip_edges().to_lower()

	for spirit in current_data.permanent_spirits:
		if typeof(spirit) != TYPE_DICTIONARY:
			continue
		var row := spirit as Dictionary
		if not category_needle.is_empty() and str(row.get("category", "")).to_lower() != category_needle:
			continue
		if not _matches_search(row, search, false):
			continue
		result.append(row)
	return result


func _filtered_temporary_rows() -> Array[Dictionary]:
	if view_filter.selected == FILTER_PERMANENT:
		return []

	var result: Array[Dictionary] = []
	var search := search_edit.text.strip_edges().to_lower()

	for effect in current_data.temporary_effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var row := effect as Dictionary
		if not _passes_view_filter(row):
			continue
		if not _matches_search(row, search, true):
			continue
		result.append(row)
	return result


func _passes_view_filter(row: Dictionary) -> bool:
	match view_filter.selected:
		FILTER_TEMPORARY:
			return true
		FILTER_BUFFS:
			return not bool(row.get("is_debuff", false))
		FILTER_DEBUFFS:
			return bool(row.get("is_debuff", false))
		FILTER_PERMANENT:
			return false
		_:
			return true


func _selected_category_filter() -> String:
	if category_filter.selected <= 0:
		return ""
	return category_filter.get_item_text(category_filter.selected).to_lower()


func _matches_search(row: Dictionary, needle: String, is_temporary: bool) -> bool:
	if needle.is_empty():
		return true
	var haystack := (
		"%s %s %s %s"
		% [
			str(row.get("name", "")),
			str(row.get("description", "")),
			str(row.get("source_label", "")),
			str(row.get("category", "")),
		]
	).to_lower()
	for line in row.get("modifier_lines", []) as Array:
		haystack += " " + str(line).to_lower()
	if is_temporary:
		haystack += " temporary effect"
	else:
		haystack += " national spirit"
	return needle in haystack


func _empty_message_permanent() -> String:
	if view_filter.selected == FILTER_TEMPORARY:
		return "Permanent spirits hidden — switch filter to All or Permanent."
	if not search_edit.text.strip_edges().is_empty():
		return "No spirits match your search."
	return "No national spirits defined for this country yet."


func _empty_message_temporary() -> String:
	if view_filter.selected == FILTER_PERMANENT:
		return "Temporary effects hidden by filter."
	if view_filter.selected == FILTER_BUFFS:
		return "No active buffs. Complete successful agent missions to add bonuses."
	if view_filter.selected == FILTER_DEBUFFS:
		return "No active debuffs."
	if not search_edit.text.strip_edges().is_empty():
		return "No temporary effects match your search."
	return "No temporary effects. Influence missions and events will appear here."


func _content_wrap_width() -> float:
	# Prefer live scroll width so cards wrap inside the panel; fall back to scene size.
	# Subtract enough for panel content margins + DetailMargin so text is not cut L/R.
	var scroll := get_node_or_null("MarginContainer/VBoxContainer/MainScroll") as Control
	if scroll != null and scroll.size.x > 80.0:
		return maxf(scroll.size.x - 36.0, 180.0)
	if detail_scroll != null and detail_scroll.size.x > 80.0:
		return maxf(detail_scroll.size.x - 48.0, 180.0)
	return maxf(size.x - 72.0, 180.0)


func _relayout_wrap() -> void:
	_apply_wrap(detail_label)
	_apply_wrap(filter_status_label)
	var footer := get_node_or_null("MarginContainer/VBoxContainer/MainScroll/MainVBox/FooterLabel") as Label
	_apply_wrap(footer)


func _apply_wrap(label: Label, width: float = -1.0) -> void:
	if label == null:
		return
	var w := width if width > 0.0 else _content_wrap_width()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(w, 0)


func _create_entry_panel(row: Dictionary, is_temporary: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel_flat(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = true
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var wrap_w := maxf(_content_wrap_width() - 28.0, 160.0)

	var entry_id := (
		str(row.get("effect_id", ""))
		if is_temporary
		else str(row.get("spirit_id", ""))
	)
	if entry_id == _selected_entry_id:
		panel.modulate = Color(0.88, 0.95, 1.0)
	elif is_temporary and bool(row.get("is_debuff", false)):
		panel.modulate = Color(1.0, 0.78, 0.72)

	panel.tooltip_text = str(row.get("tooltip_text", ""))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(header)

	var title := Label.new()
	if is_temporary:
		title.text = str(row.get("source_label", "Effect"))
	else:
		title.text = str(row.get("name", ""))
	_apply_wrap(title, maxf(wrap_w - 90.0, 120.0))
	RetrowaveTheme.style_body_label(title)
	if is_temporary:
		title.add_theme_color_override(
			"font_color",
			RetrowaveTheme.WARNING if bool(row.get("is_debuff", false)) else RetrowaveTheme.SUCCESS,
		)
	header.add_child(title)

	var badge := Label.new()
	if is_temporary:
		badge.text = "DEBUFF" if bool(row.get("is_debuff", false)) else "BUFF"
	else:
		badge.text = str(row.get("category", "")).capitalize()
	RetrowaveTheme.style_body_label(badge)
	badge.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(badge)

	if is_temporary:
		var duration_row := HBoxContainer.new()
		duration_row.add_theme_constant_override("separation", 8)
		duration_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(duration_row)

		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(120, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = 1.0
		bar.value = float(row.get("progress_ratio", 0.0))
		bar.show_percentage = false
		RetrowaveTheme.style_progress_bar(bar)
		duration_row.add_child(bar)

		var time_label := Label.new()
		var remaining := int(row.get("remaining_months", 0))
		var duration := int(row.get("duration_months", 0))
		time_label.text = "%d / %d mo" % [remaining, maxi(duration, remaining)]
		RetrowaveTheme.style_body_label(time_label)
		time_label.tooltip_text = "Months remaining before this effect expires."
		duration_row.add_child(time_label)
	else:
		var desc := Label.new()
		desc.text = str(row.get("description", ""))
		_apply_wrap(desc, wrap_w)
		RetrowaveTheme.style_body_label(desc)
		desc.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		box.add_child(desc)

	box.add_child(_create_modifier_grid(row, wrap_w))

	var select_btn := Button.new()
	select_btn.text = "Details"
	select_btn.tooltip_text = "Show full effect text in the panel above."
	RetrowaveTheme.style_secondary_button(select_btn)
	select_btn.pressed.connect(_on_entry_selected.bind(entry_id, row, is_temporary))
	box.add_child(select_btn)

	return panel


func _create_modifier_grid(row: Dictionary, wrap_w: float = -1.0) -> VBoxContainer:
	# Use a vertical list instead of a rigid 2-col grid so long labels wrap cleanly.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var w := wrap_w if wrap_w > 0.0 else _content_wrap_width()

	for detail in row.get("modifier_details", []) as Array:
		if typeof(detail) != TYPE_DICTIONARY:
			continue
		var d := detail as Dictionary
		var line := Label.new()
		var label_txt := str(d.get("label", ""))
		var value_txt := str(d.get("value_text", ""))
		line.text = "%s  %s" % [label_txt, value_txt]
		_apply_wrap(line, w)
		RetrowaveTheme.style_body_label(line)
		if bool(d.get("is_positive", true)):
			line.add_theme_color_override("font_color", RetrowaveTheme.SUCCESS)
		else:
			line.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
		line.tooltip_text = str(d.get("tooltip", ""))
		list.add_child(line)

	if list.get_child_count() == 0:
		for raw in row.get("modifier_lines", []) as Array:
			var fallback := Label.new()
			fallback.text = "• %s" % str(raw)
			_apply_wrap(fallback, w)
			RetrowaveTheme.style_body_label(fallback)
			fallback.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
			list.add_child(fallback)

	return list


func _on_entry_selected(entry_id: String, row: Dictionary, is_temporary: bool) -> void:
	_selected_entry_id = entry_id
	_apply_wrap(detail_label)
	detail_label.text = str(row.get("tooltip_text", "No details available."))
	if detail_scroll != null:
		detail_scroll.scroll_vertical = 0
	_populate_lists()


func _empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	_apply_wrap(label)
	RetrowaveTheme.style_body_label(label)
	label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	return label
