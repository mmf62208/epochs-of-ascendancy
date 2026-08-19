# scripts/ui/DomainDesignPopup.gd
## Multi-domain designer duties UI: land / naval / air / space.
extends Window

const DOMAINS: Array[String] = ["land", "naval", "air", "space"]

var _current_tag: String = "USA"
var _domain: String = "land"
var _selected_base: String = ""
var _selected_modules: Dictionary = {}
var _doctrine_key: String = "rugged_redundancy"

var _domain_option: OptionButton
var _base_option: OptionButton
var _doctrine_option: OptionButton
var _modules_container: VBoxContainer
var _stats_label: Label

const DOMAIN_BASES := {
	"land": ["chassis_medium_tank", "chassis_light_tank", "chassis_heavy_tank", "infantry_kit"],
	"naval": ["hull_destroyer", "hull_cruiser", "hull_submarine", "hull_carrier"],
	"air": ["airframe_fighter", "airframe_bomber", "airframe_cas", "airframe_recon"],
	"space": ["bus_satellite", "bus_station", "bus_corvette", "bus_launch"],
}

const DOMAIN_MODULES := {
	"land": ["main_gun_medium", "engine_diesel", "radio_set", "armor_skirts", "coax_mg", "optics_basic"],
	"naval": ["naval_gun_main", "torpedo_tubes", "sonar_array", "aa_battery", "engine_steam", "damage_control"],
	"air": ["cannon_wing", "engine_radial", "radar_set", "bomb_racks", "self_sealing_tanks", "drop_tanks"],
	"space": ["solar_array", "sensor_array", "life_support_basic", "nuclear_thermal_engine", "railgun_space", "fuel_cell_electric"],
}

const DOMAIN_DOCTRINES := {
	"land": "rugged_redundancy",
	"naval": "compartmentalized_survivability",
	"air": "lightweight_performance",
	"space": "lightweight_performance",
}


func _ready() -> void:
	title = "Domain Designer"
	size = Vector2i(520, 640)
	transient = true
	exclusive = true
	close_requested.connect(queue_free)
	_build_ui()
	_refresh_for_domain()


func set_player_tag(tag: String) -> void:
	_current_tag = tag.strip_edges().to_upper()
	if _current_tag.is_empty():
		_current_tag = "USA"


func set_domain(domain: String) -> void:
	var d := domain.strip_edges().to_lower()
	if DOMAINS.has(d):
		_domain = d
		if _domain_option:
			var idx := DOMAINS.find(d)
			if idx >= 0:
				_domain_option.select(idx)
		_refresh_for_domain()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var hdr := Label.new()
	hdr.text = "Full designer duties: catalog, compose, freeze, register"
	hdr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hdr)

	var row_dom := HBoxContainer.new()
	row_dom.add_child(_make_lbl("Domain:"))
	_domain_option = OptionButton.new()
	for d in DOMAINS:
		_domain_option.add_item(str(d).capitalize())
	_domain_option.select(0)
	_domain_option.item_selected.connect(_on_domain_selected)
	row_dom.add_child(_domain_option)
	col.add_child(row_dom)

	var row_base := HBoxContainer.new()
	row_base.add_child(_make_lbl("Base:"))
	_base_option = OptionButton.new()
	_base_option.item_selected.connect(_on_base_selected)
	row_base.add_child(_base_option)
	col.add_child(row_base)

	var row_doc := HBoxContainer.new()
	row_doc.add_child(_make_lbl("Doctrine:"))
	_doctrine_option = OptionButton.new()
	_doctrine_option.add_item("Rugged Redundancy")
	_doctrine_option.set_item_metadata(0, "rugged_redundancy")
	_doctrine_option.add_item("Lightweight Performance")
	_doctrine_option.set_item_metadata(1, "lightweight_performance")
	_doctrine_option.add_item("Compartmentalized Survivability")
	_doctrine_option.set_item_metadata(2, "compartmentalized_survivability")
	_doctrine_option.item_selected.connect(_on_doctrine_selected)
	row_doc.add_child(_doctrine_option)
	col.add_child(row_doc)

	var mod_hdr := Label.new()
	mod_hdr.text = "Modules"
	col.add_child(mod_hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 220)
	col.add_child(scroll)
	_modules_container = VBoxContainer.new()
	_modules_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_modules_container)

	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_stats_label)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(queue_free)
	btns.add_child(cancel)
	var finalize_btn := Button.new()
	finalize_btn.text = "Freeze & Register"
	finalize_btn.pressed.connect(_on_finalize)
	btns.add_child(finalize_btn)
	col.add_child(btns)


func _on_domain_selected(i: int) -> void:
	if i >= 0 and i < DOMAINS.size():
		set_domain(DOMAINS[i])


func _on_base_selected(i: int) -> void:
	if _base_option:
		_selected_base = _base_option.get_item_text(i)
		_update_stats()


func _on_doctrine_selected(i: int) -> void:
	if _doctrine_option:
		_doctrine_key = str(_doctrine_option.get_item_metadata(i))
		_update_stats()


func _make_lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _refresh_for_domain() -> void:
	_selected_modules.clear()
	_doctrine_key = str(DOMAIN_DOCTRINES.get(_domain, "rugged_redundancy"))
	if _base_option:
		_base_option.clear()
		var bases: Array = DOMAIN_BASES.get(_domain, ["default_base"]) as Array
		for b in bases:
			_base_option.add_item(str(b))
		if bases.size() > 0:
			_selected_base = str(bases[0])
		else:
			_selected_base = "default_base"
	if _modules_container:
		for c in _modules_container.get_children():
			c.queue_free()
		var mods: Array = DOMAIN_MODULES.get(_domain, []) as Array
		for mod_id in mods:
			var h := HBoxContainer.new()
			var chk := CheckBox.new()
			var mid := str(mod_id)
			chk.text = mid.replace("_", " ").capitalize()
			chk.toggled.connect(_make_module_toggler(mid))
			h.add_child(chk)
			_modules_container.add_child(h)
	if _doctrine_option:
		for i in range(_doctrine_option.item_count):
			if str(_doctrine_option.get_item_metadata(i)) == _doctrine_key:
				_doctrine_option.select(i)
				break
	title = "Domain Designer - %s (%s)" % [_domain.capitalize(), _current_tag]
	_update_stats()


func _make_module_toggler(mid: String) -> Callable:
	return func(on: bool) -> void:
		if on:
			_selected_modules[mid] = true
		else:
			_selected_modules.erase(mid)
		_update_stats()


func _update_stats() -> void:
	if not _stats_label:
		return
	var n := _selected_modules.size()
	var power := 50 + n * 10
	var mass := 100 - n * 5
	var cost := 200 + n * 30
	var rel := clampf(0.86 + float(n) * 0.02, 0.5, 0.98)
	var text := "Domain: %s\nBase: %s\nDoctrine: %s\nModules: %d selected\n" % [
		_domain, _selected_base, _doctrine_key, n,
	]
	text += "Est. Power: %d  Mass: %d  Cost: %d  Rel: %.0f%%\n" % [power, mass, cost, rel * 100.0]
	text += "\nFreeze registers a custom design for production seed."
	_stats_label.text = text


func _on_finalize() -> void:
	if _selected_modules.is_empty():
		var mods: Array = DOMAIN_MODULES.get(_domain, []) as Array
		if mods.size() >= 2:
			_selected_modules[str(mods[0])] = true
			_selected_modules[str(mods[1])] = true
		elif mods.size() == 1:
			_selected_modules[str(mods[0])] = true

	var design_id := "custom_%s_%s_%d" % [_current_tag.to_lower(), _domain, int(Time.get_ticks_msec()) % 100000]
	var design_data := {
		"id": design_id,
		"design_id": design_id,
		"base_type": _selected_base,
		"modules": _selected_modules.keys(),
		"owner": _current_tag,
		"domain": _domain,
		"doctrine": _doctrine_key,
		"frozen": true,
	}

	var reg_ok := false
	if typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("register_custom_design"):
		var res: Dictionary = DesignManager.register_custom_design(_current_tag, design_data)
		reg_ok = bool(res.get("ok", false))
		if reg_ok:
			design_id = str(res.get("design_id", design_id))

	if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_designer_duties_live"):
		GameData.apply_designer_duties_live("register", 1, _domain, _current_tag, design_id)

	var fielded_fid := ""
	if reg_ok and typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("field_design_on_map"):
		var field_pid := 710173 if _current_tag.to_upper() == "GER" else -1
		if field_pid < 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			for pv in MapManager.get_provinces_by_owner(_current_tag):
				var pp = MapManager.get_province(int(pv)) if MapManager.has_method("get_province") else null
				if pp != null and not bool(pp.is_sea):
					field_pid = int(pp.id)
					break
		if field_pid > 0:
			var fielded: Dictionary = DesignManager.field_design_on_map(
				_current_tag, design_id, field_pid, _domain
			)
			if bool(fielded.get("ok", false)):
				fielded_fid = str(fielded.get("formation_id", ""))
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		var suffix := " - registered" if reg_ok else " - saved locally"
		if not fielded_fid.is_empty():
			suffix += " · fielded on map · click chip to order"
		LeaderEventUI.show_toast(
			"Design finalized: %s (%s, %d modules)%s" % [design_id, _domain, _selected_modules.size(), suffix],
			5.0,
			true,
		)
	print("[DOMAIN DESIGNER] Finalized %s for %s domain=%s fielded=%s" % [design_id, _current_tag, _domain, fielded_fid])
	queue_free()
