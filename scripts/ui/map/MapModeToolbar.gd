# scripts/ui/map/MapModeToolbar.gd
## Player-facing map mode toolbar (Political, Strain, Vitality, Development, Supply, Loyalty, Infra, Naval).
extends PanelContainer

const _HudIcons = preload("res://scripts/ui/HudIconLibrary.gd")
const _WxIcons = preload("res://scripts/ui/WeatherIconLibrary.gd")

signal mode_changed(mode: String)
signal layout_changed()

const MODES: Array[String] = [
	"political", "strain", "vitality", "development", "supply", "munitions", "loyalty", "infra", "naval", "weather", "resources", "states", "terrain"
]

const MODE_LABELS: Dictionary = {
	"political": "Political",
	"strain": "Strain",
	"vitality": "Vitality",
	"development": "Development",
	"supply": "Supply",
	"munitions": "Munitions",
	"loyalty": "Loyalty",
	"infra": "Infra",
	"naval": "Naval",
	"weather": "Weather",
	"resources": "Resources",
	"states": "States",
	"terrain": "Terrain",
}

const MODE_HINTS: Dictionary = {
	"political": "Clean country colors (default)",
	"strain": "Welfare / cultural strain (red-gray)",
	"vitality": "Settlement vitality (cyan-green)",
	"development": "Development level lighten",
	"supply": "Supply routes overlay",
	"munitions": "Per-depot munitions stockpile heatmap (blue full → red empty)",
	"loyalty": "Foreign military loyalty tint",
	"infra": "Roads, rails, built infrastructure",
	"naval": "Sea-zone theaters, chokepoints, coastal rims",
	"weather": "Ground state: dry / mud / snow / storm fills",
	"resources": "Strategic goods: oil / rubber / steel / coal (F9)",
	"states": "V3-style state fills from hierarchy membership (Shift+F9)",
	"terrain": "Clean terrain fills: plains / forest / mountains / desert (Ctrl+F9)",
}

## Weather legend hint appended for naval/supply mapmodes (weather expand surface).
const WEATHER_LEGEND_HINT := "Weather: dry·mud·snow/storm affect move/supply/spot (see inspector chip)"

## Pass 14/15: one-click mapmode preset bundles (mode + optional stack flags).
## stack flags: "supply" force supply overlay, "weather" force weather particles, "naval" secondary tint note.
const PRESETS: Array[Dictionary] = [
	{"id": "overview", "label": "Overview", "mode": "political", "stack": [], "hint": "Clean political colors"},
	{"id": "logistics", "label": "Logistics", "mode": "supply", "stack": [], "hint": "Supply routes + depots"},
	{"id": "corridor", "label": "Corridor", "mode": "supply", "stack": [], "hint": "Capital→front corridor (select province, press G)"},
	{"id": "fronts", "label": "Fronts", "mode": "political", "stack": ["live_fronts"], "hint": "Live multi-front border assault targets (press B)"},
	{"id": "war_loop", "label": "WarLoop", "mode": "political", "stack": ["war_loop"], "hint": "First-session war path: flow+fronts+assault brief (Shift+I)"},
	{"id": "theater", "label": "Theater", "mode": "naval", "stack": [], "hint": "Sea zones + chokepoints"},
	{"id": "climate", "label": "Climate", "mode": "weather", "stack": [], "hint": "Ground weather + particles"},
	{"id": "build", "label": "Build", "mode": "infra", "stack": [], "hint": "Roads / rails / infra density"},
	{"id": "resources", "label": "Resources", "mode": "resources", "stack": [], "hint": "Oil / rubber / steel / coal strategic map"},
	{"id": "states", "label": "States", "mode": "states", "stack": [], "hint": "V3-style state membership fills"},
	{"id": "terrain", "label": "Terrain", "mode": "terrain", "stack": [], "hint": "Clean plains/forest/mountain terrain view"},
	# Pass 15 multi-mode stacks
	{"id": "warpath", "label": "Warpath", "mode": "naval", "stack": ["supply"], "hint": "Naval theater + supply routes"},
	{"id": "stormops", "label": "StormOps", "mode": "weather", "stack": ["supply"], "hint": "Weather fills + supply overlay"},
	{"id": "buildnet", "label": "BuildNet", "mode": "infra", "stack": ["supply"], "hint": "Infra density + supply routes"},
	# Pass 16
	{"id": "society", "label": "Society", "mode": "vitality", "stack": ["strain"], "hint": "Settlement vitality + welfare strain"},
	{"id": "sealanes", "label": "SeaLanes", "mode": "supply", "stack": ["convoy_minimap", "naval"], "hint": "Supply routes + convoy minimap pips"},
	# Pass 17 multi-secondary
	{"id": "home_front", "label": "HomeFront", "mode": "vitality", "stack": ["strain", "loyalty"], "hint": "Vitality + strain + loyalty secondaries"},
	{"id": "econ_pulse", "label": "EconPulse", "mode": "development", "stack": ["strain", "vitality"], "hint": "Development + strain + vitality"},
	# Pass 22
	{"id": "ammo", "label": "Ammo", "mode": "munitions", "stack": ["supply"], "hint": "Depot munitions heatmap + supply routes"},
	{"id": "repair_ops", "label": "RepairOps", "mode": "infra", "stack": ["supply"], "hint": "Infra view + supply (use Repair queue chip)"},
	# Pass 28 munitions pack variants
	{"id": "ammo_occ", "label": "AmmoOcc", "mode": "munitions", "stack": ["supply", "munitions_occupied"], "hint": "Munitions focus: occupied depots only + supply"},
	{"id": "ammo_mine", "label": "AmmoMine", "mode": "munitions", "stack": ["supply", "munitions_mine"], "hint": "Munitions focus: player-controlled depots + supply"},
	{"id": "ammo_pack", "label": "AmmoPack", "mode": "munitions", "stack": ["supply", "convoy_minimap", "munitions_all"], "hint": "Full munitions pack: heatmap + supply + convoy pips"},
]

const COLLAPSED_HEIGHT := 28.0
const EXPANDED_HEIGHT := 56.0
## Pass 9: slightly taller when weather icon strip is shown.
const EXPANDED_HEIGHT_WX := 72.0
const EXPANDED_HEIGHT_PRESETS := 88.0

var _map_renderer: Node = null
var _buttons: Dictionary = {}
var _legend: Label = null
var _body: VBoxContainer = null
var _collapse_btn: Button = null
var _wx_row: HBoxContainer = null
var _wx_filter_btns: Dictionary = {}  # key -> Button
var _wx_filter_key: String = ""
var _preset_row: HBoxContainer = null
## Pass 18: chips showing active secondary mapmode tints from stacked presets.
var _secondary_row: HBoxContainer = null
var _current_mode: String = "political"
var _collapsed: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func bind_map_renderer(renderer: Node) -> void:
	_map_renderer = renderer
	set_mode("political", false)


func get_panel_height() -> float:
	if _collapsed:
		return COLLAPSED_HEIGHT
	if _wx_row != null and _wx_row.visible:
		return EXPANDED_HEIGHT_PRESETS
	return EXPANDED_HEIGHT_PRESETS if _preset_row != null else EXPANDED_HEIGHT


func _build_ui() -> void:
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	_collapse_btn = Button.new()
	_collapse_btn.text = "▾"
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.custom_minimum_size = Vector2(28, 24)
	_collapse_btn.pressed.connect(_toggle_collapsed)
	outer.add_child(_collapse_btn)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 2)
	outer.add_child(_body)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	_body.add_child(title_row)

	var title := Label.new()
	title.text = "Map Mode"
	title.add_theme_font_size_override("font_size", 12)
	title_row.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_body.add_child(row)

	for mode in MODES:
		var btn := Button.new()
		btn.text = MODE_LABELS.get(mode, mode.capitalize())
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 28)
		btn.tooltip_text = str(MODE_HINTS.get(mode, mode))
		# Retrowave map-mode icons (HudIconLibrary)
		var mode_tex: Texture2D = _HudIcons.map_mode_icon(mode, 32)
		if mode_tex != null:
			_HudIcons.apply_button_icon(btn, mode_tex, true)
		var mode_id: String = str(mode)
		btn.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_on_mode_pressed(mode_id)
		)
		row.add_child(btn)
		_buttons[mode] = btn

	# Pass 14: quick mapmode presets.
	_preset_row = HBoxContainer.new()
	_preset_row.add_theme_constant_override("separation", 4)
	_body.add_child(_preset_row)
	_build_preset_row()

	# Pass 18: active secondary tint legend chips.
	_secondary_row = HBoxContainer.new()
	_secondary_row.add_theme_constant_override("separation", 4)
	_secondary_row.visible = false
	_body.add_child(_secondary_row)

	# Pass 9: weather icon legend strip (dry / mud / snow / storm).
	_wx_row = HBoxContainer.new()
	_wx_row.add_theme_constant_override("separation", 10)
	_wx_row.visible = false
	_body.add_child(_wx_row)
	_build_weather_icon_legend()

	_legend = Label.new()
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.add_theme_font_size_override("font_size", 10)
	_legend.modulate = Color(0.85, 0.9, 1.0, 0.85)
	_body.add_child(_legend)
	_update_legend("political")


func _build_preset_row() -> void:
	if _preset_row == null:
		return
	for c in _preset_row.get_children():
		c.queue_free()
	var cap := Label.new()
	cap.text = "Preset"
	cap.add_theme_font_size_override("font_size", 10)
	cap.modulate = Color(0.7, 0.85, 1.0, 0.9)
	_preset_row.add_child(cap)
	for p in PRESETS:
		var label: String = str(p.get("label", p.get("id", "Preset")))
		var mode: String = str(p.get("mode", "political"))
		var hint: String = str(p.get("hint", mode))
		var stack: Array = p.get("stack", []) as Array if p.get("stack") is Array else []
		var btn := Button.new()
		btn.text = label
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 22)
		btn.add_theme_font_size_override("font_size", 10)
		var stack_s := ""
		if not stack.is_empty():
			var parts: PackedStringArray = PackedStringArray()
			for sx in stack:
				parts.append(str(sx))
			stack_s = " + " + "+".join(parts)
		btn.tooltip_text = "%s → %s%s" % [label, hint, stack_s]
		var m: String = mode
		var lbl: String = label
		var st: Array = stack.duplicate()
		btn.pressed.connect(func() -> void:
			_apply_preset(m, lbl, st)
		)
		# Icon: prefer preset id (fronts / war_loop), then base mapmode stem.
		var preset_id: String = str(p.get("id", "")).strip_edges().to_lower()
		var mode_tex: Texture2D = _HudIcons.map_mode_icon(preset_id, 32) if not preset_id.is_empty() else null
		if mode_tex == null:
			mode_tex = _HudIcons.map_mode_icon(mode, 32)
		if mode_tex != null:
			btn.icon = mode_tex
			btn.expand_icon = true
		# Stacked presets get a subtle warm tint so they read as composite.
		if not stack.is_empty():
			btn.modulate = Color(1.08, 0.95, 1.05, 1.0)
		_preset_row.add_child(btn)


func _apply_preset(mode: String, label: String = "", stack: Array = []) -> void:
	set_mode(mode, true)
	# Stream 2: WarLoop — first-session flow + fronts + assault brief (Shift+I).
	var wants_war_loop := false
	for sxw in stack:
		if str(sxw).strip_edges().to_lower() == "war_loop":
			wants_war_loop = true
			break
	if wants_war_loop and _map_renderer != null and _map_renderer.has_method("show_first_session_war_path"):
		var wr: Dictionary = _map_renderer.call("show_first_session_war_path")
		if _legend != null:
			_legend.text = str(wr.get("toast", "WarLoop · Shift+I"))
		return
	# Phase C: Fronts preset opens live border assault surface (same as KEY_B).
	var wants_fronts := false
	for sx0 in stack:
		if str(sx0).strip_edges().to_lower() == "live_fronts":
			wants_fronts = true
			break
	if wants_fronts and _map_renderer != null and _map_renderer.has_method("show_live_border_fronts"):
		var fr: Dictionary = _map_renderer.call("show_live_border_fronts")
		if _legend != null:
			_legend.text = str(fr.get("toast", "Fronts · B"))
		# Still apply residual stack flags without re-entering fronts loop.
		var rest: Array = []
		for sx1 in stack:
			if str(sx1).strip_edges().to_lower() != "live_fronts":
				rest.append(sx1)
		if _map_renderer.has_method("apply_mapmode_preset_stack") and not rest.is_empty():
			_map_renderer.call("apply_mapmode_preset_stack", mode, rest)
		return
	# Pass 15: apply stack flags on MapRenderer (supply overlay / weather particles).
	if _map_renderer != null and _map_renderer.has_method("apply_mapmode_preset_stack"):
		_map_renderer.call("apply_mapmode_preset_stack", mode, stack)
	else:
		_apply_stack_fallback(stack)
	_rebuild_secondary_tint_chips(stack, mode)
	if _legend != null and not label.is_empty():
		var extra := ""
		if not stack.is_empty():
			var parts2: PackedStringArray = PackedStringArray()
			for sx2 in stack:
				parts2.append(str(sx2))
			extra = " +" + "+".join(parts2)
		_legend.text = "Preset: %s → %s%s" % [label, MODE_LABELS.get(mode, mode), extra]


## Phase C: legend text from MapRenderer.show_live_border_fronts list.
func set_fronts_legend(text: String) -> void:
	if _legend == null:
		return
	_legend.text = str(text)
	_legend.visible = true


## Pass 18: show chips for active secondary tint modes (strain/vitality/loyalty/development).
func _rebuild_secondary_tint_chips(stack: Array, primary_mode: String = "") -> void:
	if _secondary_row == null:
		return
	for c in _secondary_row.get_children():
		c.queue_free()
	var pm := primary_mode.strip_edges().to_lower()
	var secs: Array = []
	for s in stack:
		var sk := str(s).strip_edges().to_lower()
		if sk in ["strain", "vitality", "development", "loyalty"] and sk != pm:
			if sk not in secs:
				secs.append(sk)
	# Also read live secondaries from renderer if present.
	if _map_renderer != null and "debug_tint_mode_secondaries" in _map_renderer:
		var live = _map_renderer.debug_tint_mode_secondaries
		if live is Array:
			for sk2 in live:
				var k2 := str(sk2).strip_edges().to_lower()
				if k2 in ["strain", "vitality", "development", "loyalty"] and k2 not in secs:
					secs.append(k2)
	# Pass 22: show intensity presets when primary is intensity-linked even with no secondaries.
	var primary_ix := pm in ["strain", "vitality", "development", "loyalty", "munitions"]
	if secs.is_empty() and not primary_ix:
		_secondary_row.visible = false
		layout_changed.emit()
		return
	_secondary_row.visible = true
	var cap := Label.new()
	cap.text = "2nd" if not secs.is_empty() else "Ix"
	cap.add_theme_font_size_override("font_size", 10)
	cap.modulate = Color(0.75, 0.85, 1.0, 0.9)
	_secondary_row.add_child(cap)
	# Pass 21/22: intensity presets (Soft / Med / Hard / Max) for secondaries + primary.
	var preset_cell := VBoxContainer.new()
	preset_cell.add_theme_constant_override("separation", 1)
	var preset_lbl := Label.new()
	preset_lbl.text = "Ix"
	preset_lbl.add_theme_font_size_override("font_size", 9)
	preset_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preset_lbl.modulate = Color(0.75, 0.85, 1.0, 0.85)
	preset_cell.add_child(preset_lbl)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 2)
	preset_cell.add_child(preset_row)
	for pdef in [
		{"id": "soft", "label": "S", "hint": "Soft 0.5"},
		{"id": "med", "label": "M", "hint": "Med 1.0"},
		{"id": "hard", "label": "H", "hint": "Hard 1.5"},
		{"id": "max", "label": "X", "hint": "Max 2.0"},
	]:
		var pb := Button.new()
		pb.text = str(pdef["label"])
		pb.focus_mode = Control.FOCUS_NONE
		pb.custom_minimum_size = Vector2(20, 18)
		pb.add_theme_font_size_override("font_size", 9)
		pb.tooltip_text = "Set secondary + primary intensities · %s" % str(pdef["hint"])
		var pid: String = str(pdef["id"])
		pb.pressed.connect(func() -> void:
			_on_intensity_preset(pid, secs)
		)
		preset_row.add_child(pb)
	_secondary_row.add_child(preset_cell)
	for sk3 in secs:
		# Pass 19/20: toggle chip + intensity slider.
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		var chip := Button.new()
		chip.toggle_mode = true
		chip.button_pressed = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.text = MODE_LABELS.get(str(sk3), str(sk3).capitalize())
		chip.add_theme_font_size_override("font_size", 10)
		chip.custom_minimum_size = Vector2(72, 20)
		var key_s: String = str(sk3)
		chip.tooltip_text = "Secondary map tint: %s\nClick to toggle. Slider = intensity." % MODE_HINTS.get(key_s, key_s)
		chip.modulate = _secondary_chip_color(key_s)
		chip.toggled.connect(func(on: bool) -> void:
			_on_secondary_chip_toggled(key_s, on)
		)
		cell.add_child(chip)
		var slider := HSlider.new()
		slider.min_value = 0.25
		slider.max_value = 2.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(72, 14)
		var cur := 1.0
		if _map_renderer != null and _map_renderer.has_method("get_secondary_tint_intensity"):
			cur = float(_map_renderer.call("get_secondary_tint_intensity", key_s))
		slider.value = cur
		slider.tooltip_text = "Intensity %.2f (0.25–2.0)" % cur
		slider.value_changed.connect(func(v: float) -> void:
			if _map_renderer != null and _map_renderer.has_method("set_secondary_tint_intensity"):
				_map_renderer.call("set_secondary_tint_intensity", key_s, v)
			slider.tooltip_text = "Intensity %.2f (0.25–2.0)" % v
		)
		cell.add_child(slider)
		_secondary_row.add_child(cell)
	layout_changed.emit()


func _on_intensity_preset(preset_id: String, active_secs: Array) -> void:
	if _map_renderer == null:
		return
	if _map_renderer.has_method("apply_secondary_intensity_preset"):
		_map_renderer.call("apply_secondary_intensity_preset", preset_id)
	elif _map_renderer.has_method("set_all_secondary_tint_intensity"):
		var levels := {"soft": 0.5, "med": 1.0, "hard": 1.5, "max": 2.0}
		_map_renderer.call("set_all_secondary_tint_intensity", float(levels.get(preset_id, 1.0)))
	else:
		var levels2 := {"soft": 0.5, "med": 1.0, "hard": 1.5, "max": 2.0}
		var v := float(levels2.get(preset_id, 1.0))
		for sk in active_secs:
			if _map_renderer.has_method("set_secondary_tint_intensity"):
				_map_renderer.call("set_secondary_tint_intensity", str(sk), v)
	# Pass 22: intensity also links to primary mapmode when primary is a tint mode.
	if _map_renderer.has_method("link_intensity_to_primary_mapmode"):
		_map_renderer.call("link_intensity_to_primary_mapmode", preset_id)
	# Rebuild chips so sliders reflect new values.
	var stack_live: Array = []
	if "debug_tint_mode_secondaries" in _map_renderer:
		var live2 = _map_renderer.debug_tint_mode_secondaries
		if live2 is Array:
			stack_live = live2.duplicate()
	if stack_live.is_empty():
		stack_live = active_secs.duplicate()
	_rebuild_secondary_tint_chips(stack_live, _current_mode)


func _on_secondary_chip_toggled(key: String, on: bool) -> void:
	if _map_renderer == null:
		return
	# Ensure renderer list matches chip: if off and present → toggle; if on and missing → toggle.
	var has := false
	if "debug_tint_mode_secondaries" in _map_renderer:
		var live = _map_renderer.debug_tint_mode_secondaries
		if live is Array:
			has = key in live
	if on and not has:
		if _map_renderer.has_method("toggle_secondary_tint"):
			_map_renderer.call("toggle_secondary_tint", key)
	elif not on and has:
		if _map_renderer.has_method("toggle_secondary_tint"):
			_map_renderer.call("toggle_secondary_tint", key)
	# Rebuild chips from live state.
	var stack_live: Array = []
	if "debug_tint_mode_secondaries" in _map_renderer:
		var live2 = _map_renderer.debug_tint_mode_secondaries
		if live2 is Array:
			stack_live = live2.duplicate()
	_rebuild_secondary_tint_chips(stack_live, _current_mode)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Secondary %s · %s" % [key, "ON" if on else "OFF"])


func _secondary_chip_color(key: String) -> Color:
	match key:
		"strain":
			return Color(0.95, 0.55, 0.6, 0.92)
		"vitality":
			return Color(0.45, 0.92, 0.7, 0.92)
		"loyalty":
			return Color(0.95, 0.82, 0.45, 0.92)
		"development":
			return Color(0.55, 0.78, 0.98, 0.92)
		_:
			return Color(0.7, 0.75, 0.85, 0.9)


func _apply_stack_fallback(stack: Array) -> void:
	if _map_renderer == null:
		return
	# Best-effort: force supply overlay if requested.
	if "supply" in stack:
		if "supply_mode" in _map_renderer and not bool(_map_renderer.supply_mode):
			if _map_renderer.has_method("_toggle_supply_overlay"):
				_map_renderer.call("_toggle_supply_overlay")
	if "weather" in stack:
		if _map_renderer.has_method("_sync_weather_mapmode_particles"):
			_map_renderer.call("_sync_weather_mapmode_particles", true)


func _build_weather_icon_legend() -> void:
	if _wx_row == null:
		return
	for c in _wx_row.get_children():
		c.queue_free()
	_wx_filter_btns.clear()
	var caption := Label.new()
	caption.text = "Wx"
	caption.add_theme_font_size_override("font_size", 10)
	caption.modulate = Color(0.7, 0.85, 1.0, 0.9)
	_wx_row.add_child(caption)
	for key in ["dry", "mud", "snow", "storm"]:
		# Pass 13: clickable filter chips (toggle ground-state highlight).
		var btn := Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, 22)
		btn.add_theme_font_size_override("font_size", 10)
		btn.text = " %s" % key
		btn.tooltip_text = _weather_key_tooltip(key) + "\nClick to filter mapmode (toggle)."
		var tex: Texture2D = _WxIcons.icon_for(key, 32)
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
		var k: String = str(key)
		btn.toggled.connect(func(pressed: bool) -> void:
			_on_weather_filter_toggled(k, pressed)
		)
		_wx_row.add_child(btn)
		_wx_filter_btns[k] = btn
	_sync_weather_filter_buttons()


func _weather_key_tooltip(key: String) -> String:
	match key:
		"mud":
			return "Mud — heavy move penalty (armor worse)"
		"snow":
			return "Snow/frozen — mild move hit; winter wear"
		"storm":
			return "Storm — air/naval/spotting down; interdiction up"
		_:
			return "Dry — normal move/supply"


func _on_weather_filter_toggled(key: String, pressed: bool) -> void:
	if pressed:
		_wx_filter_key = key
	else:
		# Only clear if this key was the active filter.
		if _wx_filter_key == key:
			_wx_filter_key = ""
	_sync_weather_filter_buttons()
	if _map_renderer != null:
		# Pass 14/15: absolute set + particle/minimap sync (avoid set_weather_ground_filter toggle).
		if "weather_ground_filter" in _map_renderer:
			_map_renderer.weather_ground_filter = _wx_filter_key
			if _map_renderer.has_method("_refresh_province_fill_colors"):
				_map_renderer.call("_refresh_province_fill_colors", true)
			if _map_renderer.has_method("_sync_weather_particle_filter"):
				_map_renderer.call("_sync_weather_particle_filter")
			# Refresh minimap weather dots under filter.
			if "_map_minimap" in _map_renderer:
				var mm = _map_renderer._map_minimap
				if mm != null and is_instance_valid(mm):
					if mm.has_method("invalidate_weather_cache"):
						mm.call("invalidate_weather_cache")
					if mm.has_method("set_show_weather_dots") and str(_map_renderer.current_map_mode) == "weather":
						mm.call("set_show_weather_dots", false)
						mm.call("set_show_weather_dots", true)
	if _legend != null and _current_mode == "weather":
		if _wx_filter_key.is_empty():
			_legend.text = str(MODE_HINTS.get("weather", "")) + " · click Wx icons to filter"
		else:
			_legend.text = "Weather filter: %s (click again to clear)" % _wx_filter_key


func _sync_weather_filter_buttons() -> void:
	for k in _wx_filter_btns.keys():
		var btn: Button = _wx_filter_btns[k]
		var on := (str(k) == _wx_filter_key)
		btn.set_pressed_no_signal(on)
		btn.modulate = Color(1.15, 1.15, 1.2, 1.0) if on else Color(0.85, 0.9, 1.0, 0.9)


func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	if _body:
		_body.visible = not _collapsed
	if _collapse_btn:
		_collapse_btn.text = "▸" if _collapsed else "▾"
	layout_changed.emit()


func _on_mode_pressed(mode: String) -> void:
	set_mode(mode, true)


func set_mode(mode: String, notify_renderer: bool = true) -> void:
	var m := mode.strip_edges().to_lower()
	if not m in MODES:
		m = "political"
	if m == _current_mode and notify_renderer:
		return
	_current_mode = m
	for key in _buttons.keys():
		var btn: Button = _buttons[key]
		btn.button_pressed = (key == m)
	_update_legend(m)
	if notify_renderer and _map_renderer != null and _map_renderer.has_method("set_map_mode"):
		_map_renderer.call("set_map_mode", m)
	# Pass 22: ensure Ix row appears for primary-linked modes.
	var stack_live: Array = []
	if _map_renderer != null and "debug_tint_mode_secondaries" in _map_renderer:
		var live = _map_renderer.debug_tint_mode_secondaries
		if live is Array:
			stack_live = live.duplicate()
	_rebuild_secondary_tint_chips(stack_live, m)
	mode_changed.emit(m)


func _update_legend(mode: String) -> void:
	if _legend == null:
		return
	var base := str(MODE_HINTS.get(mode, ""))
	# Weather mapmode chip: surface weather legend hint on supply/naval (live call path).
	var show_wx := mode in ["supply", "naval", "infra", "weather"]
	if _wx_row != null:
		_wx_row.visible = show_wx
	if show_wx:
		var wx := format_weather_mapmode_hint()
		if not wx.is_empty():
			base = "%s · %s" % [base, wx] if not base.is_empty() else wx
		if mode == "weather":
			if _wx_filter_key.is_empty():
				base = "%s · click Wx icons to filter" % base
			else:
				base = "Weather filter: %s (click again to clear)" % _wx_filter_key
	# Leaving weather mode clears filter so other modes aren't dimmed.
	if mode != "weather" and not _wx_filter_key.is_empty():
		_wx_filter_key = ""
		_sync_weather_filter_buttons()
		if _map_renderer != null and "weather_ground_filter" in _map_renderer:
			_map_renderer.weather_ground_filter = ""
	# Pass 18: plain mode change clears secondary chips unless stack reapplied.
	if _secondary_row != null and mode not in ["vitality", "development", "strain", "loyalty"]:
		# Keep chips if renderer still has secondaries (stacked preset active).
		var has_sec := false
		if _map_renderer != null and "debug_tint_mode_secondaries" in _map_renderer:
			var live = _map_renderer.debug_tint_mode_secondaries
			has_sec = live is Array and not live.is_empty()
		if not has_sec:
			_rebuild_secondary_tint_chips([])
	_legend.text = base
	layout_changed.emit()


## Weather legend hint for mapmode toolbar (call site for format_weather_legend).
func format_weather_mapmode_hint() -> String:
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("format_weather_legend_bbcode"):
		# Plain short hint (toolbar is Label, not richtext).
		return WEATHER_LEGEND_HINT
	return WEATHER_LEGEND_HINT


func get_current_mode() -> String:
	return _current_mode
