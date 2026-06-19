# scripts/ui/SpaceDesignPopup.gd
class_name SpaceDesignPopup
extends Control

# Dynamic popup for space designer.
# Unlocked via rule_flag "space_designer_unlocked" from tech like space_design_basic, orbital_shipyard_program.
# Allows designing Satellite, Space Station, Spaceship with module choices.
# Integrates with DesignManager for space domain, creates custom design on finalize.

var _current_tag: String = "USA"
var _base_types: Array[String] = ["satellite", "space_station", "spacecraft"]
var _selected_base: String = "spacecraft"
var _selected_modules: Dictionary = {}  # module_id -> count or true

@onready var _main_vbox: VBoxContainer = $MainVBox if has_node("MainVBox") else VBoxContainer.new()
@onready var _title_label: Label
@onready var _base_option: OptionButton
@onready var _modules_container: VBoxContainer
@onready var _stats_label: Label
@onready var _finalize_btn: Button
@onready var _close_btn: Button

func _ready() -> void:
	if not has_node("MainVBox"):
		_build_ui()
	_setup_ui()
	_refresh_modules()
	_update_stats()

func _build_ui() -> void:
	# Build dynamic UI if not in scene
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(600, 500)
	
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	
	_main_vbox = VBoxContainer.new()
	_main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_vbox.add_theme_constant_override("separation", 8)
	panel.add_child(_main_vbox)
	
	_title_label = Label.new()
	_title_label.text = "Space Asset Designer"
	_title_label.add_theme_font_size_override("font_size", 18)
	_main_vbox.add_child(_title_label)
	
	_base_option = OptionButton.new()
	for bt in _base_types:
		_base_option.add_item(bt.capitalize())
	_base_option.item_selected.connect(_on_base_selected)
	_main_vbox.add_child(_base_option)
	
	_modules_container = VBoxContainer.new()
	_main_vbox.add_child(_modules_container)
	
	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_main_vbox.add_child(_stats_label)
	
	var hbox := HBoxContainer.new()
	_finalize_btn = Button.new()
	_finalize_btn.text = "Finalize Design"
	_finalize_btn.pressed.connect(_on_finalize)
	hbox.add_child(_finalize_btn)
	
	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.pressed.connect(queue_free)
	hbox.add_child(_close_btn)
	_main_vbox.add_child(hbox)

func _setup_ui() -> void:
	if _base_option:
		_base_option.select(2)  # default spacecraft
		_selected_base = _base_types[2]
	if _title_label:
		_title_label.text = "Space Designer — Unlocked by Orbital Techs"

func _on_base_selected(idx: int) -> void:
	_selected_base = _base_types[idx]
	_selected_modules.clear()
	_refresh_modules()
	_update_stats()

func _refresh_modules() -> void:
	if not _modules_container:
		return
	for c in _modules_container.get_children():
		c.queue_free()
	
	# Get available space modules from DesignManager or data/modules filtered by space
	var dm = get_node_or_null("/root/DesignManager")
	var available: Array = []
	if dm and dm.has_method("get_available_modules_for_domain"):
		available = dm.call("get_available_modules_for_domain", "space")
	else:
		# Fallback: load some space modules
		available = ["nuclear_thermal_engine", "life_support_basic", "sensor_array", "solar_array", "railgun_space", "fuel_cell_electric"]
	
	for mod_id in available:
		var h := HBoxContainer.new()
		var chk := CheckBox.new()
		chk.text = mod_id.replace("_", " ").capitalize()
		chk.button_pressed = _selected_modules.has(mod_id)
		chk.toggled.connect(func(on: bool): 
			if on:
				_selected_modules[mod_id] = true
			else:
				_selected_modules.erase(mod_id)
			_update_stats()
		)
		h.add_child(chk)
		_modules_container.add_child(h)

func _update_stats() -> void:
	if not _stats_label:
		return
	var stats_text := "Base: %s\n" % _selected_base.capitalize()
	stats_text += "Modules: %d selected\n" % _selected_modules.size()
	# Simulate stats (in full, use DesignManager or SpaceDesignSystem to compute)
	var power := 50 + _selected_modules.size() * 10
	var mass := 100 - _selected_modules.size() * 5
	var cost := 200 + _selected_modules.size() * 30
	stats_text += "Est. Power: %d  Mass: %d  Cost: %d\n" % [power, mass, cost]
	stats_text += "\nTip: Select modules fitting your base. Propulsion for ships, sensors for sats."
	_stats_label.text = stats_text

func _on_finalize() -> void:
	if _selected_modules.is_empty():
		# default some
		_selected_modules["life_support_basic"] = true
		_selected_modules["sensor_array"] = true
	
	var design_id := "custom_%s_%s" % [_selected_base, str(Time.get_unix_time_from_system()).substr(0,8)]
	
	var dm = get_node_or_null("/root/DesignManager")
	if dm and dm.has_method("register_custom_design"):
		var design_data := {
			"id": design_id,
			"base_type": _selected_base,
			"modules": _selected_modules.keys(),
			"owner": _current_tag,
			"domain": "space"
		}
		dm.call("register_custom_design", _current_tag, design_data)
	
	if typeof(GameData) != TYPE_NIL and GameData.has_method("unlock_design"):
		GameData.call("unlock_design", _current_tag, design_id)
	
	# Toast and close
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("Space Design Finalized: %s (%s modules). Available in Production for space lines." % [design_id, _selected_modules.size()], 5.0, true)
	
	print("[SPACE DESIGNER] Finalized %s for %s with modules %s" % [design_id, _current_tag, _selected_modules.keys()])
	queue_free()

func set_player_tag(tag: String) -> void:
	_current_tag = tag.to_upper()

# Call with: var popup = preload("res://scripts/ui/SpaceDesignPopup.gd").new(); add_child(popup); popup.set_player_tag("USA")
