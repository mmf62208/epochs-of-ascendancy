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
@onready var detail_label: Label = $MarginContainer/VBoxContainer/MainArea/DetailPanel/DetailLabel

var current_data: ProductionScreenData
var filtered_factories: Array[Dictionary] = []

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
const ROW_HEIGHT := 36


func _ready() -> void:
	add_to_group("production_screen")
	drag_handle = $TitleBar
	super._ready()
	close_button.pressed.connect(_on_close_pressed)
	_apply_screen_theme()
	_setup_filters()
	_setup_headers()
	status_filter.item_selected.connect(_on_filter_changed)
	type_filter.item_selected.connect(_on_filter_changed)
	search_edit.text_changed.connect(_on_filter_changed)
	if not ProductionManager.day_advanced.is_connected(_on_day_advanced):
		ProductionManager.day_advanced.connect(_on_day_advanced)
	refresh_screen()


func _exit_tree() -> void:
	if ProductionManager.day_advanced.is_connected(_on_day_advanced):
		ProductionManager.day_advanced.disconnect(_on_day_advanced)


func _on_close_pressed() -> void:
	queue_free()


func _apply_screen_theme() -> void:
	RetrowaveTheme.style_production_screen(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_secondary_button(close_button)
	RetrowaveTheme.style_summary_metric(total_factories_label)
	RetrowaveTheme.style_summary_metric(avg_efficiency_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_summary_metric(retooling_label, RetrowaveTheme.MAGENTA)
	RetrowaveTheme.style_summary_metric(daily_output_label)
	RetrowaveTheme.style_search(search_edit)
	search_edit.placeholder_text = "Search design or province..."
	RetrowaveTheme.style_filter_option(status_filter)
	RetrowaveTheme.style_filter_option(type_filter)
	RetrowaveTheme.style_detail_panel(detail_panel)
	RetrowaveTheme.style_detail_label(detail_label)


func _setup_headers() -> void:
	for child in header_row.get_children():
		child.queue_free()

	for spec in HEADER_SPECS:
		if bool(spec.get("expand", false)):
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header_row.add_child(spacer)
			continue

		var label := Label.new()
		label.text = str(spec.get("text", ""))
		var width := int(spec.get("width", 100))
		if width > 0:
			label.custom_minimum_size = Vector2(width, 0)
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

	total_factories_label.text = "Factories: %d" % current_data.total_factories
	avg_efficiency_label.text = "Avg Efficiency: %.1f%%" % (current_data.average_efficiency * 100.0)
	avg_efficiency_label.modulate = _efficiency_color(current_data.average_efficiency)

	retooling_label.text = "Retooling: %d" % current_data.factories_in_retooling
	if current_data.has_many_retooling:
		retooling_label.modulate = RetrowaveTheme.WARNING
	else:
		retooling_label.modulate = RetrowaveTheme.MAGENTA

	daily_output_label.text = "Daily Output: %.1f" % current_data.estimated_daily_output


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


func _create_factory_row(summary: Dictionary) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	hbox.add_theme_constant_override("separation", 8)

	hbox.add_child(_row_label(str(summary.get("province_id", "?")), 100))

	var design_text: String = summary.get("current_design", "")
	if design_text.is_empty():
		design_text = "(idle)"
	else:
		design_text = _format_design_label(design_text)
	hbox.add_child(_row_label(design_text, 200))

	var efficiency := float(summary.get("efficiency", 0.0))
	var eff_label := _row_label("%.1f%%" % (efficiency * 100.0), 90)
	eff_label.modulate = _efficiency_color(efficiency)
	hbox.add_child(eff_label)

	var retool_label := _row_label("Yes" if summary.get("is_retooling", false) else "No", 80)
	hbox.add_child(retool_label)

	hbox.add_child(_row_label("%.1f" % float(summary.get("daily_output_estimate", 0.0)), 90))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var change_btn := Button.new()
	change_btn.text = "Change"
	change_btn.custom_minimum_size = Vector2(90, 0)
	RetrowaveTheme.style_primary_button(change_btn)
	change_btn.pressed.connect(_on_change_pressed.bind(summary))
	hbox.add_child(change_btn)

	var details_btn := Button.new()
	details_btn.text = "Details"
	details_btn.custom_minimum_size = Vector2(90, 0)
	RetrowaveTheme.style_secondary_button(details_btn)
	details_btn.pressed.connect(_on_details_pressed.bind(summary))
	hbox.add_child(details_btn)

	return hbox


func _row_label(text: String, min_width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.clip_text = true
	RetrowaveTheme.style_row_label(label)
	return label


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
	var design: String = summary.get("current_design", "")
	if design.is_empty():
		design = "(idle)"

	var text := "Factory ID: %s\n" % summary.get("factory_id", "?")
	text += "Province: %s\n" % summary.get("province_id", "?")
	text += "Type: %s\n" % summary.get("factory_type", "unknown")
	text += "Status: %s\n" % summary.get("status", "unknown")
	if not design.is_empty() and design != "(idle)":
		design = _format_design_label(design)
	text += "Current Design: %s\n" % design
	if typeof(TechnologyManager) != TYPE_NIL and design != "(idle)":
		var avail: Dictionary = TechnologyManager.get_design_availability(
			country_tag,
			str(summary.get("current_design", "")),
		)
		if not bool(avail.get("available", true)):
			text += "%s\n" % avail.get("reason", "")
	text += "Efficiency: %.1f%%\n" % (float(summary.get("efficiency", 0.0)) * 100.0)
	text += "Retooling: %s\n" % ("Yes" if summary.get("is_retooling", false) else "No")
	text += "Lines: %d / %d\n" % [
		int(summary.get("assigned_lines", 0)),
		int(summary.get("max_lines", 1)),
	]
	text += "Daily Output: %.1f" % float(summary.get("daily_output_estimate", 0.0))
	# Layered prod per-line state + preview trades (speed/quality/cost etc)
	var line_layers: Dictionary = summary.get("line_layers", {})
	if line_layers.size() > 0:
		text += "
--- Production Layers (per line) ---
"
		for lid in line_layers:
			var lyr := str(line_layers[lid])
			text += "  Line %s: %s
" % [str(lid), lyr]
			# preview via PM if avail
			if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_line"):
				var ln = ProductionManager.get_line(str(lid))
				if ln and ln.has_method("get_layer_trades_preview"):
					var tr := ln.get_layer_trades_preview()
					text += "    trades: speed x%.2f qual x%.2f cost x%.2f retool x%.2f (%s)
" % [float(tr.get("speed",1)), float(tr.get("quality",1)), float(tr.get("cost",1)), float(tr.get("retool",1)), str(tr.get("desc",""))]
	detail_label.text = text

	# Add/Set layer buttons for live choice (re-uses assigned lines; minimal UI extension)
	_clear_layer_buttons()
	var owner := str(summary.get("owner_tag", ""))
	var avail: Array = []
	if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("get_available_production_layers"):
		avail = ProductionManager.get_available_production_layers(owner)
	var line_ids: Array = summary.get("assigned_line_ids", [])
	if line_ids.size() == 0:
		line_ids = summary.get("assigned_line_ids", [])
	for lyr in ["mass", "automated", "additive", "nano"]:
		var btn := Button.new()
		btn.text = "Set %s" % lyr
		btn.custom_minimum_size = Vector2(70, 22)
		if lyr in avail or lyr == "mass":
			RetrowaveTheme.style_primary_button(btn) if RetrowaveTheme else null
		else:
			btn.disabled = true
		btn.pressed.connect(func():
			if line_ids.size() > 0:
				var first_lid := str(line_ids[0])
				if typeof(ProductionManager) != TYPE_NIL and ProductionManager.has_method("set_line_production_layer"):
					var r := ProductionManager.set_line_production_layer(first_lid, lyr)
					if r.get("success", false):
						_toast_layer("Line %s set to %s (trades applied)" % [first_lid, lyr])
						refresh_screen()
					else:
						_toast_layer("Cannot set %s: %s" % [lyr, str(r.get("error", r))])
			else:
				_toast_layer("No lines on this factory to set layer")
		)
		# parent to detail panel area
		detail_panel.add_child(btn)
		if not has_meta("layer_btns"): set_meta("layer_btns", [])
		var btns: Array = get_meta("layer_btns")
		btns.append(btn)



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
		detail_label.text += "
" + msg

func _on_filter_changed(_value: Variant = null) -> void:
	_apply_filters()
