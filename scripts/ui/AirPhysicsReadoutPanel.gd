# scripts/ui/AirPhysicsReadoutPanel.gd
## Read-only P1 air-physics readout. Never writes designs, templates, stockpiles or saves.
## No Apply button. Opened from DomainDesignPopup when domain == air.
extends Window

const _CalcScript = preload("res://scripts/units/DesignCalculator.gd")

var _calc: RefCounted
var _preset_opt: OptionButton
var _loadout_opt: OptionButton
var _role_opt: OptionButton
var _body: RichTextLabel
var _close_btn: Button


func _ready() -> void:
	title = "Air physics readout (P1)"
	size = Vector2i(600, 480)
	transient = true
	unresizable = true
	close_requested.connect(_on_close)
	_calc = _CalcScript.new()
	if _calc.has_method("load_presets"):
		_calc.call("load_presets")
	_build_ui()
	_clamp_to_viewport()
	_refresh()


## Fit a 1280×800 Play viewport so Close stays on-screen.
## Use the root/DisplayServer size, not this Window's own 1×1 sub-viewport.
func _clamp_to_viewport() -> void:
	var vh := 800
	var vw := 1280
	var ds := DisplayServer.window_get_size()
	if ds.x >= 200 and ds.y >= 200:
		vw = ds.x
		vh = ds.y
	else:
		var t := get_tree()
		if t != null and t.root != null:
			var r := t.root.get_visible_rect()
			if r.size.x >= 200.0 and r.size.y >= 200.0:
				vw = int(r.size.x)
				vh = int(r.size.y)
	var max_h: int = maxi(vh - 48, 360)
	size = Vector2i(mini(600, maxi(vw - 40, 360)), mini(480, max_h))


func close_button() -> Button:
	return _close_btn


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pad.add_child(col)
	var note := Label.new()
	note.text = "Read-only physics. Abstract combat stats stay authoritative. Nothing is applied."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	row.add_child(_lbl("Preset"))
	_preset_opt = OptionButton.new()
	_preset_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_presets()
	_preset_opt.item_selected.connect(_on_preset)
	row.add_child(_preset_opt)
	var row2 := HBoxContainer.new()
	col.add_child(row2)
	row2.add_child(_lbl("Loadout"))
	_loadout_opt = OptionButton.new()
	_loadout_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_opt.item_selected.connect(_on_loadout)
	row2.add_child(_loadout_opt)
	var row3 := HBoxContainer.new()
	col.add_child(row3)
	row3.add_child(_lbl("Role (f)"))
	_role_opt = OptionButton.new()
	_role_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for pair in [
		["escort", "Escort / intercept  0.40"],
		["intercept", "Intercept  0.40"],
		["strike_heavy", "Strike heavy  0.35"],
		["strike_light", "Strike light / bay  0.45"],
		["patrol", "Patrol  0.25"],
		["ferry", "Ferry  1.00"],
		["missile", "Missile  1.00"],
	]:
		_role_opt.add_item(str(pair[1]))
		_role_opt.set_item_metadata(_role_opt.item_count - 1, str(pair[0]))
	_role_opt.item_selected.connect(func(_i: int) -> void: _refresh())
	row3.add_child(_role_opt)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0, 120)
	col.add_child(_body)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	_close_btn = Button.new()
	_close_btn.name = "CloseBtn"
	_close_btn.text = "Close"
	_close_btn.pressed.connect(_on_close)
	btns.add_child(_close_btn)
	col.add_child(btns)
	_rebuild_loadouts()


func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(70, 0)
	return l


func _fill_presets() -> void:
	if _preset_opt == null or _calc == null:
		return
	_preset_opt.clear()
	var ids: PackedStringArray = _calc.call("preset_ids") as PackedStringArray
	for pid in ids:
		var block: Dictionary = _calc.call("get_preset", pid) as Dictionary
		var label := "%s  (%s)" % [str(block.get("display_name", pid)), pid]
		_preset_opt.add_item(label)
		_preset_opt.set_item_metadata(_preset_opt.item_count - 1, pid)
	if _preset_opt.item_count > 0:
		var idx := _index_of_meta(_preset_opt, "me262_a1a")
		_preset_opt.select(idx if idx >= 0 else 0)


func _rebuild_loadouts() -> void:
	if _loadout_opt == null or _calc == null:
		return
	_loadout_opt.clear()
	var block: Dictionary = _current_block()
	var los: Array = _calc.call("default_loadouts", block) as Array
	for lo in los:
		if lo is Dictionary:
			var d: Dictionary = lo as Dictionary
			_loadout_opt.add_item(str(d.get("label", d.get("id", ""))))
			_loadout_opt.set_item_metadata(_loadout_opt.item_count - 1, str(d.get("id", "clean")))
	if _loadout_opt.item_count > 0:
		_loadout_opt.select(0)
	_sync_role_from_loadout()


func _sync_role_from_loadout() -> void:
	var block: Dictionary = _current_block()
	var lo: Dictionary = _calc.call("loadout_by_id", block, _current_loadout_id()) as Dictionary
	var want := str(lo.get("default_role", "escort"))
	var idx := _index_of_meta(_role_opt, want)
	if idx >= 0:
		_role_opt.select(idx)


func _index_of_meta(opt: OptionButton, value: String) -> int:
	if opt == null:
		return -1
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == value:
			return i
	return -1


func _current_preset_id() -> String:
	if _preset_opt == null or _preset_opt.item_count <= 0:
		return "me262_a1a"
	return str(_preset_opt.get_item_metadata(_preset_opt.selected))


func _current_loadout_id() -> String:
	if _loadout_opt == null or _loadout_opt.item_count <= 0:
		return "clean"
	return str(_loadout_opt.get_item_metadata(_loadout_opt.selected))


func _current_role() -> String:
	if _role_opt == null or _role_opt.item_count <= 0:
		return "escort"
	return str(_role_opt.get_item_metadata(_role_opt.selected))


func _current_block() -> Dictionary:
	return _calc.call("get_preset", _current_preset_id()) as Dictionary


func current_evaluation() -> Dictionary:
	return _calc.call("evaluate_ids", _current_preset_id(), _current_loadout_id(), _current_role()) as Dictionary


func set_preset(preset_id: String) -> void:
	var idx := _index_of_meta(_preset_opt, preset_id)
	if idx >= 0:
		_preset_opt.select(idx)
		_rebuild_loadouts()
		_refresh()


func set_loadout(loadout_id: String) -> void:
	var idx := _index_of_meta(_loadout_opt, loadout_id)
	if idx >= 0:
		_loadout_opt.select(idx)
		_sync_role_from_loadout()
		_refresh()


func set_role(role: String) -> void:
	var idx := _index_of_meta(_role_opt, role)
	if idx >= 0:
		_role_opt.select(idx)
		_refresh()


func _on_preset(_i: int) -> void:
	_rebuild_loadouts()
	_refresh()


func _on_loadout(_i: int) -> void:
	_sync_role_from_loadout()
	_refresh()


func _refresh() -> void:
	if _body == null or _calc == null:
		return
	var block: Dictionary = _current_block()
	var ev: Dictionary = current_evaluation()
	var text: String = str(_calc.call("format_readout", ev, block))
	var frac: float = float(ev.get("mtow_frac", 0.0))
	var color := "lime_green"
	if bool(ev.get("over_mtow", false)):
		color = "red"
	elif frac >= 0.95:
		color = "gold"
	_body.clear()
	_body.append_text("[color=%s]%s[/color]" % [color, text])


func _on_close() -> void:
	hide()
	queue_free()
