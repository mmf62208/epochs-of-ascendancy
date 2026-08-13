# scripts/ui/ProductionAssignmentScreen.gd
class_name ProductionAssignmentScreen
extends DraggablePanel

@export var country_tag: String = "GER"

@onready var title_label: Label = $TitleBar/TitleLabel
@onready var close_button: Button = $TitleBar/CloseButton

@onready var total_factories_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/TotalFactoriesLabel
)
@onready var avg_efficiency_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/AverageEfficiencyLabel
)
@onready var retooling_label: Label = $MarginContainer/VBoxContainer/TopSummaryBar/RetoolingLabel
@onready var daily_output_label: Label = (
	$MarginContainer/VBoxContainer/TopSummaryBar/DailyOutputLabel
)

@onready var status_filter: OptionButton = $MarginContainer/VBoxContainer/FilterBar/StatusFilter
@onready var type_filter: OptionButton = $MarginContainer/VBoxContainer/FilterBar/TypeFilter
@onready var search_edit: LineEdit = $MarginContainer/VBoxContainer/FilterBar/SearchEdit

@onready var header_row: HBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/FactoryColumn/HeaderRow
)
@onready var factory_list: VBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/FactoryColumn/FactoryList/FactoryListContent
)
@onready var detail_panel: PanelContainer = $MarginContainer/VBoxContainer/MainArea/DetailPanel
@onready var detail_title: Label = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailVBox/DetailTitle
)
@onready var detail_headline: Label = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailVBox/DetailHeadline
)
@onready var detail_scroll: ScrollContainer = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailVBox/DetailScroll
)
@onready var detail_label: Label = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailVBox/DetailScroll/DetailLabel
)
@onready var layer_button_row: HBoxContainer = (
	$MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin/DetailVBox/LayerButtonRow
)

var current_data: ProductionScreenData
var filtered_factories: Array[Dictionary] = []
var _selected_factory_id: String = ""

const HEADER_SPECS: Array[Dictionary] = [
	{"text": "Province", "width": 100},
	{"text": "Current Design", "width": 200},
	{"text": "Efficiency", "width": 90},
	{"text": "Retooling", "width": 80},
	{"text": "Daily Output", "width": 90},
	{"text": "", "width": 0, "expand": true},
	{"text": "Change", "width": 90},
	{"text": "Details", "width": 90},
]
const ROW_HEIGHT := 56


func _ready() -> void:
	add_to_group("production_screen")
	drag_handle = $TitleBar
	super._ready()
	z_index = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(_on_close_pressed)
	_apply_screen_theme()
	_setup_filters()
	_setup_headers()
	status_filter.item_selected.connect(_on_filter_changed)
	type_filter.item_selected.connect(_on_filter_changed)
	search_edit.text_changed.connect(_on_filter_changed)
	if not ProductionManager.day_advanced.is_connected(_on_day_advanced):
		ProductionManager.day_advanced.connect(_on_day_advanced)
	_center_on_viewport()
	refresh_screen()
	call_deferred("_center_on_viewport")


func _center_on_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var sz: Vector2 = vp.get_visible_rect().size
	var panel_sz := size
	if panel_sz.x < 8.0 or panel_sz.y < 8.0:
		panel_sz = Vector2(1280, 760)
		custom_minimum_size = panel_sz
		size = panel_sz
	global_position = (sz - panel_sz) * 0.5
	global_position.x = maxf(8.0, global_position.x)
	global_position.y = maxf(56.0, global_position.y)


func _exit_tree() -> void:
	if ProductionManager.day_advanced.is_connected(_on_day_advanced):
		ProductionManager.day_advanced.disconnect(_on_day_advanced)


func _on_close_pressed() -> void:
	queue_free()


func _apply_screen_theme() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin != null:
		margin.add_theme_constant_override("margin_left", 26)
		margin.add_theme_constant_override("margin_top", 16)
		margin.add_theme_constant_override("margin_right", 22)
		margin.add_theme_constant_override("margin_bottom", 14)
	RetrowaveTheme.style_production_screen(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	title_label.text = "Production — %s" % country_tag
	RetrowaveTheme.style_secondary_button(close_button)
	RetrowaveTheme.style_summary_metric(total_factories_label)
	RetrowaveTheme.style_summary_metric(avg_efficiency_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_summary_metric(retooling_label, RetrowaveTheme.MAGENTA)
	RetrowaveTheme.style_summary_metric(daily_output_label)
	RetrowaveTheme.style_search(search_edit)
	search_edit.placeholder_text = "Search design or province..."
	# Multi-domain designer duties (always available) + space-gated specialty popup
	var filter_bar: HBoxContainer = $MarginContainer/VBoxContainer/FilterBar
	if filter_bar.get_node_or_null("DomainDesignBtn") == null:
		var domain_btn := Button.new()
		domain_btn.name = "DomainDesignBtn"
		domain_btn.text = "Design (All Domains)"
		domain_btn.pressed.connect(func():
			var scr = load("res://scripts/ui/DomainDesignPopup.gd")
			if scr == null:
				return
			var pop = scr.new()
			get_tree().root.add_child(pop)
			var tag := "USA"
			if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
				tag = str(LeaderManager.get_player_country_tag())
			if pop.has_method("set_player_tag"):
				pop.set_player_tag(tag)
			if pop.has_method("popup_centered"):
				pop.popup_centered()
		)
		RetrowaveTheme.style_secondary_button(domain_btn)
		filter_bar.add_child(domain_btn)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("has_rule_flag") and GameData.call("has_rule_flag", "player", "space_designer_unlocked"):
		if filter_bar.get_node_or_null("SpaceDesignBtn") == null:
			var space_btn := Button.new()
			space_btn.name = "SpaceDesignBtn"
			space_btn.text = "🛸 Design Space"
			space_btn.pressed.connect(func():
				var pop := preload("res://scripts/ui/SpaceDesignPopup.gd").new()
				get_tree().root.add_child(pop)
				var tag2 := "USA"
				if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
					tag2 = str(LeaderManager.get_player_country_tag())
				pop.set_player_tag(tag2)
			)
			RetrowaveTheme.style_secondary_button(space_btn)
			filter_bar.add_child(space_btn)
	## Pack E — OOB 60/100d honesty board (real GameData APIs only)
	_ensure_oob_honesty_board($MarginContainer/VBoxContainer)
	RetrowaveTheme.style_filter_option(status_filter)
	RetrowaveTheme.style_filter_option(type_filter)
	RetrowaveTheme.style_detail_panel_flat(detail_panel)
	# Factory Detail block: nudge title/content down ~2–3px (not buttons).
	var detail_margin := get_node_or_null(
		"MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailMargin"
	) as MarginContainer
	if detail_margin != null:
		detail_margin.add_theme_constant_override("margin_left", 14)
		detail_margin.add_theme_constant_override("margin_right", 12)
		detail_margin.add_theme_constant_override("margin_top", 15)
		detail_margin.add_theme_constant_override("margin_bottom", 12)
	if detail_title != null:
		RetrowaveTheme.style_detail_label(detail_title)
		detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if detail_headline != null:
		RetrowaveTheme.style_body_label(detail_headline)
		detail_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail_headline.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	if detail_scroll != null:
		detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		detail_scroll.clip_contents = true
	RetrowaveTheme.style_body_label(detail_label)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	call_deferred("_relayout_detail_wrap")


## Pack E (P1): show 60d/100d medium OOB using apply_oob_horizon_* / apply_medium_tank_oob_product.
func _ensure_oob_honesty_board(parent: VBoxContainer) -> void:
	if parent == null:
		return
	if parent.get_node_or_null("OobHonestyBoard") != null:
		return
	var box := VBoxContainer.new()
	box.name = "OobHonestyBoard"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "OOB honesty (60d / 100d) — live APIs"
	title.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	box.add_child(title)
	var summary := Label.new()
	summary.name = "OobSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.text = _format_oob_summary()
	box.add_child(summary)
	var row := HBoxContainer.new()
	var b60 := Button.new()
	b60.text = "Prove 60d"
	b60.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_oob_horizon_60d"):
			var r: Dictionary = GameData.apply_oob_horizon_60d(1)
			summary.text = "60d: %s" % str(r.get("summary", r.get("plain", r)))
		refresh_screen()
	)
	row.add_child(b60)
	var b100 := Button.new()
	b100.text = "Prove 100d"
	b100.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_oob_horizon_100d"):
			var r: Dictionary = GameData.apply_oob_horizon_100d(1)
			summary.text = "100d: %s" % str(r.get("summary", r.get("plain", r)))
		refresh_screen()
	)
	row.add_child(b100)
	var bprod := Button.new()
	bprod.text = "Medium tank OOB"
	bprod.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_medium_tank_oob_product"):
			var r: Dictionary = GameData.apply_medium_tank_oob_product(1)
			summary.text = "OOB: %s" % str(r.get("summary", r.get("plain", r)))
		refresh_screen()
	)
	row.add_child(bprod)
	box.add_child(row)
	## Insert after TopSummaryBar if present
	var insert_at := mini(2, parent.get_child_count())
	parent.add_child(box)
	parent.move_child(box, insert_at)


func _format_oob_summary() -> String:
	if typeof(GameData) != TYPE_NIL and GameData.has_method("format_medium_tank_oob_product_plain"):
		var t := str(GameData.format_medium_tank_oob_product_plain(1)).strip_edges()
		if not t.is_empty():
			return t.split("\n")[0]
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("medium_tank_oob_product_for_province"):
		var d: Dictionary = MapManager.medium_tank_oob_product_for_province(1)
		return str(d.get("summary", "OOB board ready — use Prove 60d / 100d"))
	return "OOB board ready — use Prove 60d / 100d (real apply_oob_horizon_* APIs)"


func _setup_headers() -> void:
	for child in header_row.get_children():
		child.queue_free()
	# Card list no longer needs multi-column headers — one readable title row.
	var label := Label.new()
	label.text = "Factory roster  ·  name + design  ·  efficiency / output  ·  actions"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_column_header(label)
	header_row.add_child(label)


func _setup_filters() -> void:
	status_filter.clear()
	status_filter.add_item("All")
	status_filter.add_item("producing")
	status_filter.add_item("retooling")
	status_filter.add_item("idle")
	status_filter.add_item("low_efficiency")

	type_filter.clear()
	type_filter.add_item("All")
	type_filter.add_item("shipyard")
	type_filter.add_item("tank_factory")
	type_filter.add_item("aircraft_factory")
	type_filter.add_item("general_factory")


func _on_day_advanced(_report: Dictionary) -> void:
	refresh_screen()


func refresh_screen() -> void:
	_clear_layer_buttons()
	current_data = ProductionManager.get_production_screen_data(country_tag, false)
	_update_summary_bar()
	_apply_filters()


func _update_summary_bar() -> void:
	if current_data == null:
		return

	total_factories_label.text = "Factories  %d" % current_data.total_factories
	avg_efficiency_label.text = "Avg eff.  %.0f%%" % (current_data.average_efficiency * 100.0)
	avg_efficiency_label.modulate = _efficiency_color(current_data.average_efficiency)

	retooling_label.text = "Retooling  %d" % current_data.factories_in_retooling
	if current_data.has_many_retooling:
		retooling_label.modulate = RetrowaveTheme.WARNING
	else:
		retooling_label.modulate = RetrowaveTheme.MAGENTA

	daily_output_label.text = "Daily out  %.1f" % current_data.estimated_daily_output


func _apply_filters() -> void:
	filtered_factories.clear()
	if current_data == null:
		_populate_factory_list()
		return

	var status_filter_text := status_filter.get_item_text(status_filter.selected)
	var type_filter_text := type_filter.get_item_text(type_filter.selected)
	var search_text := search_edit.text.strip_edges().to_lower()

	for factory in current_data.factories:
		if not _matches_status_filter(factory, status_filter_text):
			continue
		if not _matches_type_filter(factory, type_filter_text):
			continue
		if not search_text.is_empty() and not _matches_search(factory, search_text):
			continue
		filtered_factories.append(factory)

	_populate_factory_list()


func _matches_status_filter(factory: Dictionary, status_filter_text: String) -> bool:
	if status_filter_text == "All":
		return true
	if status_filter_text == "low_efficiency":
		return float(factory.get("efficiency", 1.0)) < 0.4
	return factory.get("status", "") == status_filter_text


func _matches_type_filter(factory: Dictionary, type_filter_text: String) -> bool:
	if type_filter_text == "All":
		return true
	return factory.get("factory_type", "") == type_filter_text


func _matches_search(factory: Dictionary, search_text: String) -> bool:
	var design := str(factory.get("current_design", "")).to_lower()
	var province := str(factory.get("province_id", ""))
	return search_text in design or search_text in province


func _populate_factory_list() -> void:
	for child in factory_list.get_children():
		child.queue_free()

	for summary in filtered_factories:
		factory_list.add_child(_create_factory_row(summary))


func _create_factory_row(summary: Dictionary) -> PanelContainer:
	# Card layout: headline (province + design) + metrics line + actions.
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel_flat(panel)
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fid := str(summary.get("factory_id", ""))
	if fid == _selected_factory_id:
		panel.modulate = Color(0.9, 0.97, 1.05)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(box)

	# Info text only: nudge ~4px right (not buttons).
	var text_margin := MarginContainer.new()
	text_margin.add_theme_constant_override("margin_left", 4)
	text_margin.add_theme_constant_override("margin_right", 0)
	text_margin.add_theme_constant_override("margin_top", 0)
	text_margin.add_theme_constant_override("margin_bottom", 0)
	text_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text_margin)

	var text_box := VBoxContainer.new()
	text_box.add_theme_constant_override("separation", 2)
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_margin.add_child(text_box)

	var design_text: String = str(summary.get("current_design", ""))
	if design_text.is_empty():
		design_text = "(idle)"
	else:
		design_text = _format_design_label(design_text)
	var prov := str(summary.get("province_id", "?"))
	var ftype := str(summary.get("factory_type", "factory")).replace("_", " ")
	var status := str(summary.get("status", "")).replace("_", " ")

	var title := Label.new()
	title.text = "Prov %s  ·  %s" % [prov, design_text]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_detail_label(title)
	text_box.add_child(title)

	var efficiency := float(summary.get("efficiency", 0.0))
	var daily := float(summary.get("daily_output_estimate", 0.0))
	var retool := bool(summary.get("is_retooling", false))
	var metrics := Label.new()
	metrics.text = "%s  ·  %s  ·  eff %.0f%%  ·  out %.1f/day%s" % [
		ftype.capitalize(),
		status.capitalize() if not status.is_empty() else "—",
		efficiency * 100.0,
		daily,
		"  ·  retooling" if retool else "",
	]
	metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_body_label(metrics)
	metrics.add_theme_color_override("font_color", _efficiency_color(efficiency))
	text_box.add_child(metrics)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	box.add_child(hbox)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var change_btn := Button.new()
	change_btn.text = "Change design"
	change_btn.custom_minimum_size = Vector2(110, 28)
	change_btn.tooltip_text = "Pick a new design for this factory line."
	RetrowaveTheme.style_primary_button(change_btn)
	change_btn.pressed.connect(_on_change_pressed.bind(summary))
	hbox.add_child(change_btn)

	var details_btn := Button.new()
	details_btn.text = "Details"
	details_btn.custom_minimum_size = Vector2(90, 28)
	details_btn.tooltip_text = "Show full factory stats and production layers."
	RetrowaveTheme.style_secondary_button(details_btn)
	details_btn.pressed.connect(_on_details_pressed.bind(summary))
	hbox.add_child(details_btn)

	return panel


func _row_label(text: String, min_width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.clip_text = true
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	RetrowaveTheme.style_row_label(label)
	return label


func _relayout_detail_wrap() -> void:
	if detail_label == null:
		return
	var w := 280.0
	if detail_scroll != null and detail_scroll.size.x > 40.0:
		w = maxf(detail_scroll.size.x - 12.0, 160.0)
	elif detail_panel != null and detail_panel.size.x > 40.0:
		w = maxf(detail_panel.size.x - 48.0, 160.0)
	detail_label.custom_minimum_size = Vector2(w, 0)
	if detail_title != null:
		detail_title.custom_minimum_size = Vector2(w, 0)
	if detail_headline != null:
		detail_headline.custom_minimum_size = Vector2(w, 0)


func _format_design_label(design_id: String) -> String:
	if typeof(TechnologyManager) == TYPE_NIL:
		return design_id
	var availability: Dictionary = TechnologyManager.get_design_availability(country_tag, design_id)
	if bool(availability.get("available", true)):
		return design_id
	return "%s 🔒" % design_id


func _efficiency_color(efficiency: float) -> Color:
	if efficiency >= 0.8:
		return RetrowaveTheme.SUCCESS
	if efficiency >= 0.5:
		return Color(1.0, 0.9, 0.2)
	return RetrowaveTheme.WARNING


func _on_details_pressed(summary: Dictionary) -> void:
	_selected_factory_id = str(summary.get("factory_id", ""))
	var design: String = str(summary.get("current_design", ""))
	if design.is_empty():
		design = "(idle)"
	var design_disp := design
	if design != "(idle)":
		design_disp = _format_design_label(design)

	if detail_title != null:
		detail_title.text = "Factory %s" % str(summary.get("factory_id", "?"))
	if detail_headline != null:
		detail_headline.text = "Prov %s  ·  %s  ·  %.0f%% eff  ·  %.1f/day" % [
			str(summary.get("province_id", "?")),
			design_disp,
			float(summary.get("efficiency", 0.0)) * 100.0,
			float(summary.get("daily_output_estimate", 0.0)),
		]

	var lines: PackedStringArray = []
	lines.append("Type: %s" % str(summary.get("factory_type", "unknown")).replace("_", " "))
	lines.append("Status: %s" % str(summary.get("status", "unknown")).replace("_", " "))
	lines.append("Design: %s" % design_disp)
	if typeof(TechnologyManager) != TYPE_NIL and design != "(idle)":
		var tech_avail: Dictionary = TechnologyManager.get_design_availability(
			country_tag,
			str(summary.get("current_design", "")),
		)
		if not bool(tech_avail.get("available", true)):
			lines.append(str(tech_avail.get("reason", "Design locked by tech")))
	lines.append(
		"Efficiency: %.1f%%   |   Retooling: %s"
		% [
			float(summary.get("efficiency", 0.0)) * 100.0,
			"Yes" if summary.get("is_retooling", false) else "No",
		]
	)
	lines.append(
		"Lines: %d / %d   |   Daily output: %.1f"
		% [
			int(summary.get("assigned_lines", 0)),
			int(summary.get("max_lines", 1)),
			float(summary.get("daily_output_estimate", 0.0)),
		]
	)
	var line_layers: Dictionary = summary.get("line_layers", {})
	if line_layers.size() > 0:
		lines.append("")
		lines.append("— Production layers —")
		for lid in line_layers:
			var lyr := str(line_layers[lid])
			lines.append("  Line %s: %s" % [str(lid), lyr])
			if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_line"):
				var ln = ProductionManager.get_line(str(lid))
				if ln and ln.has_method("get_layer_trades_preview"):
					var tr := ln.get_layer_trades_preview()
					lines.append(
						"    trades  speed×%.2f  qual×%.2f  cost×%.2f  retool×%.2f"
						% [
							float(tr.get("speed", 1)),
							float(tr.get("quality", 1)),
							float(tr.get("cost", 1)),
							float(tr.get("retool", 1)),
						]
					)
					var desc := str(tr.get("desc", "")).strip_edges()
					if not desc.is_empty():
						lines.append("    %s" % desc)
	detail_label.text = "\n".join(lines)
	if detail_scroll != null:
		detail_scroll.scroll_vertical = 0
	call_deferred("_relayout_detail_wrap")

	# Layer buttons in dedicated row (not stacked over the label).
	_clear_layer_buttons()
	var owner := str(summary.get("owner_tag", country_tag))
	var layer_avail: Array = []
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_available_production_layers"):
		layer_avail = ProductionManager.get_available_production_layers(owner)
	var line_ids: Array = summary.get("assigned_line_ids", [])
	var host: Node = layer_button_row if layer_button_row != null else detail_panel
	for lyr in ["mass", "automated", "additive", "nano"]:
		var btn := Button.new()
		btn.text = lyr.capitalize()
		btn.custom_minimum_size = Vector2(78, 28)
		btn.tooltip_text = "Set first production line to %s layer." % lyr
		if lyr in layer_avail or lyr == "mass":
			RetrowaveTheme.style_primary_button(btn)
		else:
			btn.disabled = true
		btn.pressed.connect(func():
			if line_ids.size() > 0:
				var first_lid := str(line_ids[0])
				if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("set_line_production_layer"):
					var r := ProductionManager.set_line_production_layer(first_lid, lyr)
					if r.get("success", false):
						_toast_layer("Line %s → %s" % [first_lid, lyr])
						refresh_screen()
						_on_details_pressed(summary)
					else:
						_toast_layer("Cannot set %s: %s" % [lyr, str(r.get("error", r))])
			else:
				_toast_layer("No lines on this factory to set layer")
		)
		host.add_child(btn)
		if not has_meta("layer_btns"):
			set_meta("layer_btns", [])
		var btns: Array = get_meta("layer_btns")
		btns.append(btn)
	_populate_factory_list()



func _on_change_pressed(summary: Dictionary) -> void:
	var picker_scene: PackedScene = load("res://scenes/ui/DesignPickerPopup.tscn")
	if picker_scene == null:
		push_warning("DesignPickerPopup.tscn not found")
		return

	var picker: DesignPickerPopup = picker_scene.instantiate() as DesignPickerPopup
	if picker == null:
		return

	picker.factory_id = int(summary.get("factory_id", 0))
	picker.country_tag = country_tag
	get_tree().root.add_child(picker)
	picker.popup_centered()



func _clear_layer_buttons():
	if has_meta("layer_btns"):
		for b in get_meta("layer_btns"):
			if is_instance_valid(b): b.queue_free()
		set_meta("layer_btns", [])

func _toast_layer(msg: String):
	print("[LAYER UI] ", msg)
	if detail_label:
		detail_label.text += "\n" + msg
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(msg)

func _on_filter_changed(_value: Variant = null) -> void:
	_apply_filters()
