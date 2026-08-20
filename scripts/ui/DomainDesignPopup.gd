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
var _symbol_option: OptionButton
var _strength_slider: HSlider
var _org_slider: HSlider
var _preview: TextureRect
var _modules_container: VBoxContainer
var _stats_label: Label
var _symbol_id: String = "medium_tank"
var _strength_v: float = 1.0
var _org_v: float = 1.0
var _mode_existing: OptionButton
var _template_option: OptionButton
var _template_row: HBoxContainer
var _count_spin: SpinBox
var _priority_option: OptionButton
var _deploy_option: OptionButton
var _refit_check: CheckBox

const DOMAIN_SYMBOLS := {
	"land": ["infantry", "light_tank", "medium_tank", "heavy_tank", "artillery"],
	"naval": ["destroyer", "cruiser", "submarine", "carrier"],
	"air": ["fighter", "bomber"],
	"space": ["rocket"],
}

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
	title = "Unit Designer"
	size = Vector2i(560, 880)
	transient = true
	exclusive = true
	close_requested.connect(queue_free)
	_build_ui()
	_refresh_for_domain()


func set_player_tag(tag: String) -> void:
	_current_tag = tag.strip_edges().to_upper()
	if _current_tag.is_empty():
		_current_tag = "USA"
	_refresh_organize_options()


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
	hdr.text = "Use an existing template or create a new one. New units train over days; existing templates send equipment to the field (org/readiness/strength dip until ready). Deploy on a core province."
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

	var row_sym := HBoxContainer.new()
	row_sym.add_child(_make_lbl("Symbol:"))
	_symbol_option = OptionButton.new()
	_symbol_option.item_selected.connect(_on_symbol_selected)
	row_sym.add_child(_symbol_option)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(40, 40)
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row_sym.add_child(_preview)
	col.add_child(row_sym)

	var row_str := HBoxContainer.new()
	row_str.add_child(_make_lbl("Strength:"))
	_strength_slider = HSlider.new()
	_strength_slider.min_value = 0.4
	_strength_slider.max_value = 1.0
	_strength_slider.step = 0.05
	_strength_slider.value = 1.0
	_strength_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strength_slider.value_changed.connect(_on_strength_changed)
	row_str.add_child(_strength_slider)
	col.add_child(row_str)

	var row_org := HBoxContainer.new()
	row_org.add_child(_make_lbl("Org:"))
	_org_slider = HSlider.new()
	_org_slider.min_value = 0.4
	_org_slider.max_value = 1.0
	_org_slider.step = 0.05
	_org_slider.value = 1.0
	_org_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_org_slider.value_changed.connect(_on_org_changed)
	row_org.add_child(_org_slider)
	col.add_child(row_org)

	var org_hdr := Label.new()
	org_hdr.text = "Organize / recruit"
	col.add_child(org_hdr)

	var row_mode := HBoxContainer.new()
	row_mode.add_child(_make_lbl("Template:"))
	_mode_existing = OptionButton.new()
	_mode_existing.add_item("New template")
	_mode_existing.add_item("Existing template")
	_mode_existing.select(0)
	_mode_existing.item_selected.connect(_on_mode_selected)
	row_mode.add_child(_mode_existing)
	col.add_child(row_mode)

	_template_row = HBoxContainer.new()
	_template_row.add_child(_make_lbl("Existing:"))
	_template_option = OptionButton.new()
	_template_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_template_row.add_child(_template_option)
	_template_row.visible = false
	col.add_child(_template_row)

	var row_cnt := HBoxContainer.new()
	row_cnt.add_child(_make_lbl("Count:"))
	_count_spin = SpinBox.new()
	_count_spin.min_value = 1
	_count_spin.max_value = 8
	_count_spin.step = 1
	_count_spin.value = 1
	row_cnt.add_child(_count_spin)
	col.add_child(row_cnt)

	var row_pri := HBoxContainer.new()
	row_pri.add_child(_make_lbl("Priority:"))
	_priority_option = OptionButton.new()
	_priority_option.add_item("Field units first")
	_priority_option.set_item_metadata(0, "field")
	_priority_option.add_item("New units first")
	_priority_option.set_item_metadata(1, "new")
	_priority_option.select(0)
	row_pri.add_child(_priority_option)
	col.add_child(row_pri)

	var row_dep := HBoxContainer.new()
	row_dep.add_child(_make_lbl("Deploy:"))
	_deploy_option = OptionButton.new()
	_deploy_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_dep.add_child(_deploy_option)
	col.add_child(row_dep)

	_refit_check = CheckBox.new()
	_refit_check.text = "Also refit fielded units (equipment in transit)"
	_refit_check.visible = false
	col.add_child(_refit_check)

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
	finalize_btn.text = "Field on map"
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


func _on_symbol_selected(i: int) -> void:
	if _symbol_option:
		_symbol_id = str(_symbol_option.get_item_metadata(i))
		_refresh_symbol_preview()
		_update_stats()


func _on_strength_changed(v: float) -> void:
	_strength_v = clampf(v, 0.4, 1.0)
	_update_stats()


func _on_org_changed(v: float) -> void:
	_org_v = clampf(v, 0.4, 1.0)
	_update_stats()


func _on_mode_selected(i: int) -> void:
	var existing := i == 1
	if _template_row:
		_template_row.visible = existing
	if _refit_check:
		_refit_check.visible = existing
	_update_stats()


func _refresh_organize_options() -> void:
	if _template_option:
		_template_option.clear()
		var ids: Array = []
		if typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("get_active_designs"):
			ids = DesignManager.get_active_designs(_current_tag, _domain)
		if ids.is_empty() and typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("get_custom_design_ids"):
			ids = DesignManager.get_custom_design_ids(_current_tag, _domain)
		if ids.is_empty():
			match _domain:
				"naval":
					ids = ["hull_destroyer"]
				"air":
					ids = ["airframe_fighter"]
				"space":
					ids = ["bus_satellite"]
				_:
					ids = ["panzer_iii_j_medium", "infantry_kit"]
		for did in ids:
			var sid := str(did)
			_template_option.add_item(sid.replace("_", " "))
			_template_option.set_item_metadata(_template_option.item_count - 1, sid)
		if _template_option.item_count > 0:
			_template_option.select(0)
	if _deploy_option:
		_deploy_option.clear()
		var cores: Array = []
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("list_core_deploy_pids"):
			cores = LeaderManager.list_core_deploy_pids(_current_tag)
		if cores.is_empty() and _current_tag.to_upper() == "GER":
			cores = [710173, 710300]
		for pid_v in cores:
			var pid := int(pid_v)
			var label := str(pid)
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
				var p = MapManager.get_province(pid)
				if p != null:
					var nm := str(p.name) if "name" in p else ""
					if not nm.is_empty():
						label = "%s (%d)" % [nm, pid]
			_deploy_option.add_item(label)
			_deploy_option.set_item_metadata(_deploy_option.item_count - 1, pid)
		if _deploy_option.item_count > 0:
			_deploy_option.select(0)


func _refresh_symbol_preview() -> void:
	if _preview == null:
		return
	var path := "res://assets/graphics/units/nato/ww2/%s_32.png" % _symbol_id
	if ResourceLoader.exists(path):
		_preview.texture = load(path) as Texture2D
	else:
		_preview.texture = null


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
	if _symbol_option:
		_symbol_option.clear()
		var syms: Array = DOMAIN_SYMBOLS.get(_domain, ["infantry"]) as Array
		for s in syms:
			var sid := str(s)
			_symbol_option.add_item(sid.replace("_", " ").capitalize())
			_symbol_option.set_item_metadata(_symbol_option.item_count - 1, sid)
		if not syms.is_empty():
			_symbol_id = str(syms[0])
			_symbol_option.select(0)
		_refresh_symbol_preview()
	title = "Unit Designer - %s (%s)" % [_domain.capitalize(), _current_tag]
	_refresh_organize_options()
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
	text += "Symbol: %s  Strength: %.0f%%  Org: %.0f%%\n" % [_symbol_id, _strength_v * 100.0, _org_v * 100.0]
	text += "Est. Power: %d  Mass: %d  Cost: %d  Rel: %.0f%%\n" % [power, mass, cost, rel * 100.0]
	var existing := _mode_existing != null and _mode_existing.selected == 1
	var n_u := int(_count_spin.value) if _count_spin else 1
	var days := 10 if existing else 14
	text += "Organize: %d unit(s) · %d train days · %s first.\n" % [
		n_u, days, "field" if (_priority_option == null or _priority_option.selected == 0) else "new",
	]
	text += "\nField on map places a selectable chip you can march and assault with once trained."
	_stats_label.text = text


func _on_finalize() -> void:
	if _selected_modules.is_empty():
		var mods: Array = DOMAIN_MODULES.get(_domain, []) as Array
		if mods.size() >= 2:
			_selected_modules[str(mods[0])] = true
			_selected_modules[str(mods[1])] = true
		elif mods.size() == 1:
			_selected_modules[str(mods[0])] = true

	var existing := _mode_existing != null and _mode_existing.selected == 1
	var design_id := "custom_%s_%s_%d" % [_current_tag.to_lower(), _domain, int(Time.get_ticks_msec()) % 100000]
	if existing and _template_option and _template_option.item_count > 0:
		design_id = str(_template_option.get_item_metadata(_template_option.selected))
	var design_data := {
		"id": design_id,
		"design_id": design_id,
		"base_type": _selected_base,
		"modules": _selected_modules.keys(),
		"owner": _current_tag,
		"domain": _domain,
		"doctrine": _doctrine_key,
		"frozen": true,
		"visual_archetype": _symbol_id,
		"strength": _strength_v,
		"organization": _org_v,
	}

	var reg_ok := existing
	if not existing and typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("register_custom_design"):
		var res: Dictionary = DesignManager.register_custom_design(_current_tag, design_data)
		reg_ok = bool(res.get("ok", false))
		if reg_ok:
			design_id = str(res.get("design_id", design_id))

	if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_designer_duties_live"):
		GameData.apply_designer_duties_live("register", 1, _domain, _current_tag, design_id)

	var deploy_pid := 710173 if _current_tag.to_upper() == "GER" else -1
	if _deploy_option and _deploy_option.item_count > 0:
		deploy_pid = int(_deploy_option.get_item_metadata(_deploy_option.selected))
	if deploy_pid <= 0 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
		for pv in MapManager.get_provinces_by_owner(_current_tag):
			var pp = MapManager.get_province(int(pv)) if MapManager.has_method("get_province") else null
			if pp != null and not bool(pp.is_sea):
				deploy_pid = int(pp.id)
				break

	var count := clampi(int(_count_spin.value) if _count_spin else 1, 1, 8)
	var pri := "field"
	if _priority_option and _priority_option.item_count > 0:
		pri = str(_priority_option.get_item_metadata(_priority_option.selected))
	var plan := {
		"country_tag": _current_tag,
		"mode": "existing" if existing else "new",
		"template_id": design_id,
		"design_id": design_id,
		"count": count,
		"deploy_pid": deploy_pid,
		"priority": pri,
		"domain": _domain,
		"refit_fielded": existing and _refit_check != null and _refit_check.button_pressed,
		"extras": {
			"visual_archetype": _symbol_id,
			"strength": _strength_v,
			"organization": _org_v,
			"force_new": true,
		},
	}

	var fielded_fid := ""
	var orged: Dictionary = {}
	if typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("enqueue_organize_on_map"):
		orged = DesignManager.enqueue_organize_on_map(plan)
	elif typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("enqueue_organize"):
		orged = LeaderManager.enqueue_organize(plan)
	elif reg_ok and typeof(DesignManager) != TYPE_NIL and DesignManager.has_method("field_design_on_map") and deploy_pid > 0:
		orged = DesignManager.field_design_on_map(
			_current_tag, design_id, deploy_pid, _domain,
			{"strength": 0.50, "organization": 0.40, "visual_archetype": _symbol_id, "force_new": true},
		)
	if bool(orged.get("ok", false)):
		var jobs: Array = orged.get("jobs", []) as Array
		if not jobs.is_empty() and jobs[0] is Dictionary:
			fielded_fid = str((jobs[0] as Dictionary).get("formation_id", orged.get("formation_id", "")))
		else:
			fielded_fid = str(orged.get("formation_id", ""))
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		var suffix := " - registered" if reg_ok else " - saved locally"
		if not fielded_fid.is_empty():
			suffix += " · organizing %d · %d days · click chip when trained" % [
				int(orged.get("count", count)), int(orged.get("train_days", 14)),
			]
		elif str(orged.get("error", "")) == "not_core":
			suffix += " · deploy must be a core province"
		LeaderEventUI.show_toast(
			"Design finalized: %s (%s, %d modules)%s" % [design_id, _domain, _selected_modules.size(), suffix],
			5.0,
			true,
		)
	print("[DOMAIN DESIGNER] Finalized %s for %s domain=%s fielded=%s orged=%s" % [
		design_id, _current_tag, _domain, fielded_fid, str(orged.get("ok", false)),
	])
	queue_free()
