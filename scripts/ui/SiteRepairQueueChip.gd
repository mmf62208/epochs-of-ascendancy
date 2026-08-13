# scripts/ui/SiteRepairQueueChip.gd
## Pass 22/23: theater-wide special-site repair queue (player + optional allies).
class_name SiteRepairQueueChip
extends PanelContainer

signal focus_province_requested(province_id: int)
signal repair_site_requested(province_id: int, site_id: String)
signal repair_batch_requested(limit: int)

const LIST_MAX := 8

var _title: Label
var _summary: Label
var _list: VBoxContainer
var _btn_refresh: Button
var _btn_batch: Button
var _btn_all: Button
var _btn_allies: Button
var _map_renderer: Node = null
## Pass 23/24: include non-player sites. ally_scope: "none" | "treaty" | "partner"
var include_allies: bool = false
var ally_scope: String = "none"
## Cycle: none → treaty → partner → none
const _SCOPE_CYCLE: Array[String] = ["none", "treaty", "partner"]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300, 220)
	RetrowaveTheme.style_world_panel(self)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	_title = Label.new()
	_title.text = "Repair queue"
	RetrowaveTheme.style_body_label(_title)
	_title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	v.add_child(_title)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_font_size_override("font_size", 10)
	_summary.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	v.add_child(_summary)
	var scope_row := HBoxContainer.new()
	scope_row.add_theme_constant_override("separation", 6)
	v.add_child(scope_row)
	_btn_allies = Button.new()
	_btn_allies.focus_mode = Control.FOCUS_NONE
	_btn_allies.text = "Player only"
	_btn_allies.custom_minimum_size = Vector2(0, 22)
	_btn_allies.add_theme_font_size_override("font_size", 10)
	_btn_allies.tooltip_text = (
		"Cycle scope:\n• Player only\n• Formal allies (alliance treaty / guarantee)\n• Partners (CRS band + treaties)\nDiplomacy → Propose Alliance / Guarantee."
	)
	RetrowaveTheme.style_secondary_button(_btn_allies)
	_btn_allies.pressed.connect(_cycle_ally_scope)
	scope_row.add_child(_btn_allies)
	_sync_scope_button()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 100)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	_btn_refresh = Button.new()
	_btn_refresh.text = "Refresh"
	_btn_refresh.focus_mode = Control.FOCUS_NONE
	_btn_refresh.custom_minimum_size = Vector2(0, 24)
	_btn_refresh.add_theme_font_size_override("font_size", 11)
	RetrowaveTheme.style_secondary_button(_btn_refresh)
	_btn_refresh.pressed.connect(refresh)
	row.add_child(_btn_refresh)
	_btn_batch = Button.new()
	_btn_batch.text = "Repair 5"
	_btn_batch.focus_mode = Control.FOCUS_NONE
	_btn_batch.custom_minimum_size = Vector2(0, 24)
	_btn_batch.add_theme_font_size_override("font_size", 11)
	_btn_batch.tooltip_text = "Repair up to 5 most-damaged sites in scope (−1 each; engineers local)."
	RetrowaveTheme.style_secondary_button(_btn_batch)
	_btn_batch.pressed.connect(func() -> void: repair_batch_requested.emit(5))
	row.add_child(_btn_batch)
	_btn_all = Button.new()
	_btn_all.text = "Repair all"
	_btn_all.focus_mode = Control.FOCUS_NONE
	_btn_all.custom_minimum_size = Vector2(0, 24)
	_btn_all.add_theme_font_size_override("font_size", 11)
	_btn_all.tooltip_text = "Repair all damaged special sites in current scope (capped at 40/pass)."
	_btn_all.modulate = Color(1.05, 0.92, 0.55, 1.0)
	RetrowaveTheme.style_secondary_button(_btn_all)
	_btn_all.pressed.connect(func() -> void: repair_batch_requested.emit(40))
	row.add_child(_btn_all)


func bind_map_renderer(renderer: Node) -> void:
	_map_renderer = renderer


func _cycle_ally_scope() -> void:
	var idx := _SCOPE_CYCLE.find(ally_scope)
	if idx < 0:
		idx = 0
	idx = (idx + 1) % _SCOPE_CYCLE.size()
	ally_scope = str(_SCOPE_CYCLE[idx])
	include_allies = ally_scope != "none"
	_sync_scope_button()
	refresh()


func _sync_scope_button() -> void:
	if _btn_allies == null:
		return
	match ally_scope:
		"treaty":
			_btn_allies.text = "Formal allies"
			_btn_allies.modulate = Color(0.85, 1.05, 0.95, 1.0)
		"partner":
			_btn_allies.text = "Partners+"
			_btn_allies.modulate = Color(0.95, 0.95, 0.75, 1.0)
		_:
			_btn_allies.text = "Player only"
			_btn_allies.modulate = Color(1, 1, 1, 1)


func refresh() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var entries: Array = _collect_damaged_entries()
	if _summary:
		if entries.is_empty():
			match ally_scope:
				"treaty":
					_summary.text = "No damaged sites on formal allies (treaty/guarantee)."
				"partner":
					_summary.text = "No damaged sites on partners/allies."
				_:
					_summary.text = "No damaged special sites on player provinces."
		else:
			var total_dmg := 0
			var treaty_n := 0
			var partner_n := 0
			for e in entries:
				total_dmg += int(e.get("damage", 0))
				var ak := str(e.get("ally_kind", ""))
				if ak == "treaty":
					treaty_n += 1
				elif ak == "partner":
					partner_n += 1
			_summary.text = "%d sites · T%d/P%d · %d dmg · %s · worst first" % [
				entries.size(), treaty_n, partner_n, total_dmg, ally_scope
			]
	var shown := mini(LIST_MAX, entries.size())
	for i in shown:
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_list.add_child(row)
		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 10)
		var ak := str(e.get("ally_kind", ""))
		var ally_mark := ""
		if ak == "treaty":
			ally_mark = " ⚔"
		elif ak == "partner" or bool(e.get("is_ally", false)):
			ally_mark = " ★"
		var owner_s := str(e.get("owner_tag", ""))
		lbl.text = "P%d · %s · dmg %d%s" % [
			int(e.get("province_id", -1)),
			str(e.get("site_id", "?")),
			int(e.get("damage", 0)),
			ally_mark,
		]
		lbl.tooltip_text = "Province %d · %s · owner %s · %s" % [
			int(e.get("province_id", -1)), str(e.get("site_id", "")), owner_s,
			ak if not ak.is_empty() else "player",
		]
		if ak == "treaty":
			lbl.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
		elif bool(e.get("is_ally", false)):
			lbl.add_theme_color_override("font_color", Color(0.75, 0.95, 0.8))
		row.add_child(lbl)
		var pid: int = int(e.get("province_id", -1))
		var sid: String = str(e.get("site_id", ""))
		var focus_btn := Button.new()
		focus_btn.text = "Go"
		focus_btn.focus_mode = Control.FOCUS_NONE
		focus_btn.custom_minimum_size = Vector2(36, 22)
		focus_btn.add_theme_font_size_override("font_size", 10)
		RetrowaveTheme.style_secondary_button(focus_btn)
		focus_btn.pressed.connect(func() -> void:
			focus_province_requested.emit(pid)
		)
		row.add_child(focus_btn)
		var rep_btn := Button.new()
		rep_btn.text = "Fix"
		rep_btn.focus_mode = Control.FOCUS_NONE
		rep_btn.custom_minimum_size = Vector2(36, 22)
		rep_btn.add_theme_font_size_override("font_size", 10)
		rep_btn.modulate = Color(1.05, 0.9, 0.65, 1.0)
		RetrowaveTheme.style_secondary_button(rep_btn)
		rep_btn.pressed.connect(func() -> void:
			repair_site_requested.emit(pid, sid)
		)
		row.add_child(rep_btn)
	if entries.size() > LIST_MAX:
		var more := Label.new()
		more.text = "+%d more (use Repair 5 / all)" % (entries.size() - LIST_MAX)
		more.add_theme_font_size_override("font_size", 9)
		more.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
		_list.add_child(more)


func _collect_damaged_entries() -> Array:
	var out: Array = []
	if _map_renderer != null and _map_renderer.has_method("collect_damaged_player_sites"):
		var raw = _map_renderer.call("collect_damaged_player_sites", include_allies, ally_scope)
		if raw is Array:
			return raw as Array
	# Fallback: walk MapManager provinces if exposed.
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_all_provinces"):
		return out
	var player := _player_tag()
	var provs = MapManager.get_all_provinces()
	if not provs is Array and not provs is Dictionary:
		return out
	var iterable: Array = []
	if provs is Dictionary:
		for v in (provs as Dictionary).values():
			iterable.append(v)
	else:
		iterable = provs as Array
	for p in iterable:
		if p == null or not ("special_sites" in p):
			continue
		var owner := str(p.owner_tag).to_upper() if "owner_tag" in p else ""
		var is_player := player.is_empty() or owner == player
		var is_ally := false
		var ally_kind := ""
		if not is_player:
			if ally_scope == "none" or not include_allies:
				continue
			if _map_renderer != null and _map_renderer.has_method("classify_ally_tag"):
				ally_kind = str(_map_renderer.call("classify_ally_tag", owner, player))
			elif _map_renderer != null and _map_renderer.has_method("is_ally_or_partner_tag"):
				if bool(_map_renderer.call("is_ally_or_partner_tag", owner, player)):
					ally_kind = "partner"
			if ally_kind.is_empty():
				continue
			if ally_scope == "treaty" and ally_kind != "treaty":
				continue
			is_ally = true
		var pid := int(p.id) if "id" in p else -1
		for site in p.special_sites:
			if site == null:
				continue
			if site.has_method("is_damaged") and site.is_damaged():
				out.append({
					"province_id": pid,
					"site_id": str(site.id) if "id" in site else "",
					"damage": int(site.damage_level) if "damage_level" in site else 1,
					"owner_tag": owner,
					"is_ally": is_ally,
					"ally_kind": ally_kind,
				})
	out.sort_custom(func(a, b) -> bool:
		var ra := 0 if not bool(a.get("is_ally", false)) else (1 if str(a.get("ally_kind", "")) == "treaty" else 2)
		var rb := 0 if not bool(b.get("is_ally", false)) else (1 if str(b.get("ally_kind", "")) == "treaty" else 2)
		if ra != rb:
			return ra < rb
		return int(a.get("damage", 0)) > int(b.get("damage", 0))
	)
	return out


func _player_tag() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		return str(LeaderManager.get_player_country_tag()).to_upper()
	return ""
