# scripts/ui/ProvinceOOBStrip.gd
## Pass 8/9/10: horizontal OOB strip for multi-formation provinces (icons + names).
## Pass 9: defaults to player-owned formations only.
## Pass 10: "Yours / All" toggle for intel-style full stack read.
class_name ProvinceOOBStrip
extends PanelContainer

const _UnitIcons = preload("res://scripts/ui/UnitIconLibrary.gd")

signal formation_focused(formation_id: String)
## Emitted when player toggles Yours ↔ All (MapRenderer re-filters).
signal filter_mode_changed(player_only: bool)
## Division fold → Attacker/Defender sheet (Play: Open fight was missing).
signal open_fight_requested(formation_id: String)

var _title: Label
var _scroll: ScrollContainer
var _row: HBoxContainer
var _empty: Label
var _filter_btn: Button
var _fight_btn: Button
var _province_id: int = -1
## When true, only show formations matching the player country tag.
var player_only: bool = true
var _last_player_tag: String = ""
var _last_formations: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(280, 80)
	RetrowaveTheme.style_world_panel(self)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)
	_title = Label.new()
	_title.text = "OOB · your stack"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_body_label(_title)
	_title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	title_row.add_child(_title)
	_filter_btn = Button.new()
	_filter_btn.focus_mode = Control.FOCUS_NONE
	_filter_btn.custom_minimum_size = Vector2(56, 22)
	_filter_btn.add_theme_font_size_override("font_size", 11)
	RetrowaveTheme.style_secondary_button(_filter_btn)
	_filter_btn.pressed.connect(_on_filter_toggle)
	title_row.add_child(_filter_btn)
	_sync_filter_btn()
	_fight_btn = Button.new()
	_fight_btn.name = "OpenFightFoldBtn"
	_fight_btn.text = "Open fight"
	_fight_btn.focus_mode = Control.FOCUS_NONE
	_fight_btn.custom_minimum_size = Vector2(88, 22)
	_fight_btn.add_theme_font_size_override("font_size", 11)
	RetrowaveTheme.style_primary_button(_fight_btn)
	_fight_btn.pressed.connect(_on_open_fight_pressed)
	title_row.add_child(_fight_btn)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 40)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	_scroll.add_child(_row)
	_empty = Label.new()
	_empty.text = "No player formations here."
	RetrowaveTheme.style_body_label(_empty)
	_empty.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	vbox.add_child(_empty)
	_empty.visible = false


func clear_strip() -> void:
	_province_id = -1
	_last_formations = []
	for c in _row.get_children():
		c.queue_free()
	_empty.visible = true
	_title.text = "OOB · empty"
	visible = false


func _sync_filter_btn() -> void:
	if _filter_btn == null:
		return
	if player_only:
		_filter_btn.text = "Yours"
		_filter_btn.tooltip_text = "Showing player units. Click for all nations (intel)."
	else:
		_filter_btn.text = "All"
		_filter_btn.tooltip_text = "Showing all nations. Click for player-only."


func _formation_id_of(item: Variant) -> String:
	if item is Object and "formation_id" in item:
		return str(item.formation_id)
	if item is Dictionary:
		return str((item as Dictionary).get("formation_id", ""))
	return ""


func _on_open_fight_pressed() -> void:
	var fid := ""
	if _province_id == 710173:
		for item in _last_formations:
			var tag := _formation_country_tag(item)
			if not tag.is_empty() and tag != "GER":
				continue
			fid = _formation_id_of(item)
			if not fid.is_empty():
				break
	if fid.is_empty() and not _last_formations.is_empty():
		fid = _formation_id_of(_last_formations[0])
	open_fight_requested.emit(fid)


func _on_filter_toggle() -> void:
	player_only = not player_only
	_sync_filter_btn()
	filter_mode_changed.emit(player_only)
	if _province_id >= 0 and not _last_formations.is_empty():
		show_for_province(_province_id, _last_formations, _last_player_tag)


## Optional player_tag filter (Pass 9). Empty tag + player_only uses LeaderManager.
func show_for_province(province_id: int, formations: Array, player_tag: String = "") -> void:
	_province_id = province_id
	_last_formations = formations.duplicate()
	for c in _row.get_children():
		c.queue_free()
	var tag := player_tag.strip_edges().to_upper()
	if tag.is_empty():
		tag = _resolve_player_tag()
	_last_player_tag = tag
	_sync_filter_btn()
	if _fight_btn != null:
		if province_id == 710173 and (tag == "GER" or tag.is_empty()):
			_fight_btn.tooltip_text = "Maginot — 1. Infanterie can assault Alsace"
		else:
			_fight_btn.tooltip_text = "Open the Attacker/Defender sheet"
	var filtered: Array = []
	if player_only and not tag.is_empty():
		for item in formations:
			if _formation_country_tag(item) == tag:
				filtered.append(item)
	else:
		filtered = formations.duplicate()
	var n := filtered.size()
	var total := formations.size()
	if n <= 0:
		_empty.visible = true
		if player_only and total > 0:
			_title.text = "OOB · yours · province %d · 0 (of %d)" % [province_id, total]
			_empty.text = "No player formations here (%d foreign). Try All." % total
			# Keep strip visible so player can flip to All intel view.
			visible = total >= 2
		else:
			_title.text = "OOB · province %d · 0" % province_id
			_empty.text = "No formations here."
			visible = false
		return
	_empty.visible = false
	if player_only and not tag.is_empty():
		_title.text = "Division fold · yours (%s) · %d unit%s" % [
			tag, n, "s" if n != 1 else ""
		]
	else:
		_title.text = "Division fold · all · %d unit%s" % [n, "s" if n != 1 else ""]
	for item in filtered:
		_row.add_child(_make_chip(item))
	visible = true


func _resolve_player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		return str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	return ""


func _formation_country_tag(item: Variant) -> String:
	if item is Dictionary:
		var d: Dictionary = item
		return str(d.get("country_tag", d.get("owner_tag", d.get("tag", "")))).strip_edges().to_upper()
	if item is Object:
		var fo: Object = item as Object
		if "country_tag" in fo:
			return str(fo.country_tag).strip_edges().to_upper()
		if "owner_tag" in fo:
			return str(fo.owner_tag).strip_edges().to_upper()
	return ""


func _make_chip(item: Variant) -> Control:
	var panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	panel.add_child(h)
	# Pass 11: nationality color chip (left bar) from MapManager country color.
	var tag := _formation_country_tag(item)
	var nat_col := _country_color_for_tag(tag)
	var nat := ColorRect.new()
	nat.custom_minimum_size = Vector2(5, 28)
	nat.color = nat_col
	nat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nat.tooltip_text = tag if not tag.is_empty() else "—"
	h.add_child(nat)
	var icon_wrap := PanelContainer.new()
	icon_wrap.custom_minimum_size = Vector2(30, 30)
	# Subtle nation-tinted frame around unit icon.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.14, 0.9)
	sb.border_color = Color(nat_col.r, nat_col.g, nat_col.b, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	icon_wrap.add_theme_stylebox_override("panel", sb)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(28, 28)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_s := "Formation"
	var fid := ""
	var ftype := ""
	var cat := ""
	var arch := ""
	var dsn := ""
	if item is Dictionary:
		var d: Dictionary = item
		name_s = str(d.get("name", d.get("formation_id", "Unit")))
		fid = str(d.get("formation_id", ""))
		ftype = str(d.get("type", ""))
		cat = str(d.get("category", ""))
		arch = str(d.get("visual_archetype", d.get("archetype", "")))
		dsn = str(d.get("design_id", fid))
	elif item is Object:
		var fo: Object = item as Object
		if "name" in fo:
			name_s = str(fo.name)
		if "formation_id" in fo:
			fid = str(fo.formation_id)
		if fo.has_method("get_category"):
			cat = str(fo.call("get_category"))
			ftype = cat
		if "design_id" in fo:
			dsn = str(fo.design_id)
		if dsn != "" and typeof(GameData) != TYPE_NIL and GameData.design_data != null:
			var tpl = GameData.design_data.get_template(dsn)
			if tpl != null and "visual_archetype" in tpl:
				arch = str(tpl.visual_archetype)
	var tex: Texture2D = _UnitIcons.icon_for_stem(
		_UnitIcons.resolve_stem(ftype, cat, arch, dsn), 32
	)
	if tex != null:
		tr.texture = tex
	icon_wrap.add_child(tr)
	h.add_child(icon_wrap)
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 2)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lbl := Label.new()
	lbl.text = name_s if name_s.length() <= 22 else name_s.substr(0, 20) + "…"
	lbl.tooltip_text = name_s if fid.is_empty() else "%s\n%s" % [name_s, fid]
	if not tag.is_empty():
		lbl.tooltip_text = "%s\n%s · %s" % [name_s, tag, fid] if not fid.is_empty() else "%s\n%s" % [name_s, tag]
	RetrowaveTheme.style_body_label(lbl)
	name_col.add_child(lbl)
	if not tag.is_empty() and not player_only:
		var tag_lbl := Label.new()
		tag_lbl.text = tag
		tag_lbl.add_theme_font_size_override("font_size", 10)
		tag_lbl.add_theme_color_override("font_color", nat_col.lightened(0.15))
		name_col.add_child(tag_lbl)
	# Pass 12–16: org/str/rdy/xp (+ fuel naval/air) (+ ammo land).
	var org_v := _formation_stat(item, "organization", 1.0)
	var str_v := _formation_stat(item, "strength", 1.0)
	var rdy_v := _formation_stat(item, "readiness", 1.0)
	var xp_v := _formation_xp_frac(item)
	var show_fuel := _formation_uses_fuel(item)
	var fuel_v := _formation_stat(item, "fuel_level", 1.0) if show_fuel else -1.0
	var ammo_v := _formation_ammo_frac(item)
	var bars := _make_stat_bars(org_v, str_v, rdy_v, xp_v, fuel_v, ammo_v)
	name_col.add_child(bars)
	var tip := "%s\nOrg %.0f%% · Str %.0f%% · Rdy %.0f%% · XP %.0f" % [
		lbl.tooltip_text if not lbl.tooltip_text.is_empty() else name_s,
		org_v * 100.0,
		str_v * 100.0,
		rdy_v * 100.0,
		xp_v * 100.0,
	]
	if show_fuel:
		tip += " · Fuel %.0f%%" % (fuel_v * 100.0)
	if ammo_v >= 0.0:
		tip += " · Ammo %.0f%%" % (ammo_v * 100.0)
	lbl.tooltip_text = tip
	h.add_child(name_col)
	var btn := Button.new()
	btn.text = "Focus"
	btn.custom_minimum_size = Vector2(52, 24)
	RetrowaveTheme.style_secondary_button(btn)
	if not fid.is_empty():
		btn.pressed.connect(func() -> void: formation_focused.emit(fid))
	else:
		btn.disabled = true
	h.add_child(btn)
	return panel


func _formation_stat(item: Variant, key: String, default_v: float = 1.0) -> float:
	if item is Dictionary:
		var d: Dictionary = item
		if d.has(key):
			return clampf(float(d.get(key, default_v)), 0.0, 1.5)
	elif item is Object:
		var fo: Object = item as Object
		if key in fo:
			return clampf(float(fo.get(key)), 0.0, 1.5)
	return default_v


## Pass 14: combat_experience is 0–100 band → normalize to 0–1 for bar.
func _formation_xp_frac(item: Variant) -> float:
	var raw := 48.0
	if item is Dictionary:
		var d: Dictionary = item
		if d.has("combat_experience"):
			raw = float(d.get("combat_experience", 48.0))
		elif d.has("experience"):
			raw = float(d.get("experience", 48.0))
	elif item is Object:
		var fo: Object = item as Object
		if "combat_experience" in fo:
			raw = float(fo.get("combat_experience"))
		elif "experience" in fo:
			raw = float(fo.get("experience"))
	# Already normalized?
	if raw <= 1.5:
		return clampf(raw, 0.0, 1.0)
	return clampf(raw / 100.0, 0.0, 1.0)


## Pass 15: true for naval/air formations that track fuel_level.
func _formation_uses_fuel(item: Variant) -> bool:
	var cat := ""
	var ftype := ""
	if item is Dictionary:
		var d: Dictionary = item
		cat = str(d.get("category", "")).to_lower()
		ftype = str(d.get("type", d.get("formation_type", ""))).to_lower()
		if d.has("fuel_level"):
			# Explicit fuel field — show even for land if present.
			return true
	elif item is Object:
		var fo: Object = item as Object
		if fo.has_method("get_category"):
			cat = str(fo.call("get_category")).to_lower()
		if "formation_type" in fo:
			ftype = str(fo.formation_type).to_lower()
		if "fuel_level" in fo and cat in ["naval", "air", "space"]:
			return true
	if cat in ["naval", "air", "space"]:
		return true
	if "fleet" in ftype or "ship" in ftype or "task_force" in ftype:
		return true
	if "air" in ftype or "wing" in ftype or "squadron" in ftype:
		return true
	return false


## Pass 16/17: ammo from field, then depot stockpile at station, else land readiness×strength proxy.
func _formation_ammo_frac(item: Variant) -> float:
	for key in ["ammo_level", "ammo", "munitions", "ordnance", "supply_level"]:
		if item is Dictionary:
			var d: Dictionary = item
			if d.has(key):
				return clampf(float(d.get(key, 1.0)), 0.0, 1.5)
		elif item is Object:
			var fo: Object = item as Object
			if key in fo:
				return clampf(float(fo.get(key)), 0.0, 1.5)
	# Pass 17: prefer live province depot fill ratio at stationed province.
	var depot_frac := _depot_ammo_frac_for_formation(item)
	if depot_frac >= 0.0:
		# Blend depot stock with formation readiness so green units still show drag.
		var r := _formation_stat(item, "readiness", 1.0)
		return clampf(depot_frac * 0.7 + r * 0.3, 0.0, 1.0)
	# Land formations get a soft proxy so the bar is useful without a dedicated field.
	if _formation_is_land(item):
		var r2 := _formation_stat(item, "readiness", 1.0)
		var s := _formation_stat(item, "strength", 1.0)
		return clampf(r2 * 0.55 + s * 0.45, 0.0, 1.0)
	return -1.0


## Depot stockpile fill at formation's stationed province (−1 if unavailable).
func _depot_ammo_frac_for_formation(item: Variant) -> float:
	var pid := -1
	if item is Dictionary:
		pid = int(item.get("stationed_province_id", item.get("province_id", -1)))
	elif item is Object:
		var fo: Object = item as Object
		if "stationed_province_id" in fo:
			pid = int(fo.stationed_province_id)
	if pid < 0:
		# Fallback: currently selected OOB province.
		pid = _province_id
	if pid < 0:
		return -1.0
	if typeof(SupplyManager) == TYPE_NIL:
		return -1.0
	# Pass 18: prefer munitions-specific depot ratio when available.
	if SupplyManager.has_method("get_depot_munitions_ratio"):
		var mun_r := float(SupplyManager.get_depot_munitions_ratio(pid))
		if mun_r >= 0.0:
			return clampf(mun_r, 0.0, 1.0)
	if not SupplyManager.has_method("get_depot_state"):
		return -1.0
	var depot = SupplyManager.get_depot_state(pid)
	if depot == null:
		return -1.0
	if depot.has_method("munitions_ratio"):
		return clampf(float(depot.munitions_ratio()), 0.0, 1.0)
	if depot.has_method("fill_ratio"):
		return clampf(float(depot.fill_ratio()), 0.0, 1.0)
	if "stockpile" in depot and "storage_capacity" in depot:
		var cap := float(depot.storage_capacity)
		if cap <= 0.0:
			return -1.0
		return clampf(float(depot.stockpile) / cap, 0.0, 1.0)
	return -1.0


func _formation_is_land(item: Variant) -> bool:
	var cat := ""
	var ftype := ""
	if item is Dictionary:
		var d: Dictionary = item
		cat = str(d.get("category", "")).to_lower()
		ftype = str(d.get("type", d.get("formation_type", ""))).to_lower()
	elif item is Object:
		var fo: Object = item as Object
		if fo.has_method("get_category"):
			cat = str(fo.call("get_category")).to_lower()
		if "formation_type" in fo:
			ftype = str(fo.formation_type).to_lower()
	if cat in ["naval", "air", "space"]:
		return false
	if "fleet" in ftype or "ship" in ftype or "air" in ftype or "wing" in ftype:
		return false
	return true


## Thin bars: org/str/rdy/xp + optional fuel + optional ammo.
func _make_stat_bars(org_v: float, str_v: float, rdy_v: float = 1.0, xp_v: float = 0.48, fuel_v: float = -1.0, ammo_v: float = -1.0) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 1)
	var rows := 4
	if fuel_v >= 0.0:
		rows += 1
	if ammo_v >= 0.0:
		rows += 1
	wrap.custom_minimum_size = Vector2(90, 4 + rows * 4)
	wrap.add_child(_one_bar(org_v, Color(0.25, 0.9, 1.0, 0.95), Color(0.1, 0.15, 0.22, 0.9)))
	wrap.add_child(_one_bar(str_v, Color(0.95, 0.35, 0.75, 0.95), Color(0.1, 0.15, 0.22, 0.9)))
	wrap.add_child(_one_bar(rdy_v, Color(0.45, 0.95, 0.55, 0.95), Color(0.1, 0.15, 0.22, 0.9)))
	wrap.add_child(_one_bar(xp_v, Color(0.95, 0.82, 0.28, 0.95), Color(0.1, 0.15, 0.22, 0.9)))
	if fuel_v >= 0.0:
		var fuel_col := Color(1.0, 0.72, 0.22, 0.95).lerp(Color(1.0, 0.28, 0.2, 0.95), clampf(1.0 - fuel_v, 0.0, 1.0))
		wrap.add_child(_one_bar(fuel_v, fuel_col, Color(0.1, 0.15, 0.22, 0.9)))
	if ammo_v >= 0.0:
		# Ammo: slate-blue; empties toward grey-red.
		var ammo_col := Color(0.55, 0.7, 0.95, 0.95).lerp(Color(0.85, 0.4, 0.4, 0.95), clampf(1.0 - ammo_v, 0.0, 1.0))
		wrap.add_child(_one_bar(ammo_v, ammo_col, Color(0.1, 0.15, 0.22, 0.9)))
	return wrap


func _one_bar(frac: float, fill: Color, track: Color) -> Control:
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.value = clampf(frac, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(90, 4)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = track
	bg.set_corner_radius_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(1)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


func _country_color_for_tag(tag: String) -> Color:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		return Color(0.45, 0.5, 0.58, 1.0)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_country_color"):
		var c: Color = MapManager.get_country_color(t)
		if c.a > 0.01:
			return c
	# Stable hash fallback so unknown tags still get a distinct hue.
	var h := float(absi(t.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.85, 1.0)
