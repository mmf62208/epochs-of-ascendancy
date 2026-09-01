# scripts/ui/LivingTitleBoot.gd
## Graphical F5 title on the live world map: pick scenario date, country, or load a save.
## Headless / UNIT ORDER QA / env overrides skip this overlay.
class_name LivingTitleBoot
extends CanvasLayer

signal boot_closed(result: Dictionary)

const LIVING_TITLE_NATIONS := ["GER", "ENG", "FRA", "JAP", "USA", "SOV", "ITA", "POL"]
const LIVING_TITLE_ERAS := [1918, 1936, 2026]
const NATION_LABELS := {
	"GER": "Germany",
	"ENG": "United Kingdom",
	"FRA": "France",
	"JAP": "Japan",
	"USA": "United States",
	"SOV": "Soviet Union",
	"ITA": "Italy",
	"POL": "Poland",
}

var _tag := "GER"
var _year := 1936
var _nation_btns: Dictionary = {}
var _era_btns: Dictionary = {}
var _begin_btn: Button
var _status: Label
var _closed := false


## False for Maginot / QA / env-chosen boots. True for a normal graphical F5.
static func should_show_living_title() -> bool:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return false
	if OS.get_environment("EOA_SKIP_TITLE").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_UNIT_ORDER_QA").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_UI_SMOKE").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_YEAR_MULTI_AI").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_RUN_50_TURN_SIM").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_RUN_LONG_SIM").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_HEADLESS_EVIDENCE").strip_edges() == "1":
		return false
	if OS.get_environment("EOA_FAST_TEST").strip_edges() == "1":
		return false
	var env_tag := OS.get_environment("EOA_PLAYER_TAG").strip_edges().to_upper()
	if not env_tag.is_empty():
		return false
	var env_year := OS.get_environment("EOA_START_YEAR").strip_edges()
	if env_year in ["1918", "1936", "2026"]:
		return false
	for a in OS.get_cmdline_args():
		var al := str(a).to_lower().strip_edges()
		if al == "--map-evidence" or al == "--test-evidence":
			return false
	return true


## Headless-safe apply: new campaign pick, or load a save slot.
static func apply_living_title_boot(
	tag: String = "GER",
	year: int = 1936,
	load_slot: String = ""
) -> Dictionary:
	var slot := load_slot.strip_edges()
	if not slot.is_empty():
		if typeof(SaveLoadManager) == TYPE_NIL or not SaveLoadManager.has_method("load_game_detailed"):
			return {"ok": false, "reason": "no load api", "slot": slot, "mode": "load"}
		var loaded: Dictionary = SaveLoadManager.load_game_detailed(slot)
		loaded["mode"] = "load"
		loaded["slot"] = slot
		loaded["live"] = true
		return loaded
	if typeof(MainMenu) != TYPE_NIL:
		var picked: Dictionary = MainMenu.apply_living_campaign_pick(tag, year)
		picked["mode"] = "new"
		picked["slot"] = ""
		return picked
	return {"ok": false, "reason": "no campaign pick", "mode": "new"}


## Owner tag if this hex belongs to a playable living nation; else empty.
## Named Maginot hexes only in tests — never walks the 3520 board.
static func playable_tag_from_province(province_id: int) -> String:
	var pid := int(province_id)
	if pid <= 0 or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return ""
	var p: Object = MapManager.get_province(pid)
	if p == null:
		return ""
	var tag := str(p.get("owner_tag")).strip_edges().to_upper()
	if tag.is_empty():
		tag = str(p.get("controller_tag")).strip_edges().to_upper()
	if tag.is_empty() or not LIVING_TITLE_NATIONS.has(tag):
		return ""
	return tag


## Map-side country select: playable land/capital applies the shipped living-player boot.
## Non-playable nations return ok=false and do not change the player tag.
static func apply_playable_country_from_province(province_id: int, year: int = 1936) -> Dictionary:
	var pid := int(province_id)
	var tag := playable_tag_from_province(pid)
	if tag.is_empty():
		return {
			"ok": false,
			"playable": false,
			"pid": pid,
			"player_tag": "",
			"reason": "not a playable country",
			"mode": "map",
		}
	var out: Dictionary = apply_living_title_boot(tag, year, "")
	out["playable"] = true
	out["pid"] = pid
	out["mode"] = "map"
	out["source"] = "map_province"
	return out


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.22)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 560)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	RetrowaveTheme.style_menu_panel(panel)
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 28
	panel.offset_top = -280
	panel.offset_right = 448
	panel.offset_bottom = 300

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Epochs of Ascendancy"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetrowaveTheme.style_title(title, RetrowaveTheme.CYAN)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "The world is live. Click a playable country on the map, pick a date, or load a save."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(sub)
	col.add_child(sub)

	var scen_h := Label.new()
	scen_h.text = "SCENARIO DATE"
	RetrowaveTheme.style_column_header(scen_h)
	col.add_child(scen_h)
	var era_row := HBoxContainer.new()
	era_row.add_theme_constant_override("separation", 6)
	col.add_child(era_row)
	for yr in LIVING_TITLE_ERAS:
		var ebtn := Button.new()
		ebtn.text = str(int(yr))
		ebtn.custom_minimum_size = Vector2(88, 34)
		ebtn.pressed.connect(_on_year.bind(int(yr)))
		era_row.add_child(ebtn)
		_era_btns[int(yr)] = ebtn

	var nat_h := Label.new()
	nat_h.text = "PLAY AS"
	RetrowaveTheme.style_column_header(nat_h)
	col.add_child(nat_h)
	var row_a := HBoxContainer.new()
	row_a.add_theme_constant_override("separation", 4)
	col.add_child(row_a)
	var row_b := HBoxContainer.new()
	row_b.add_theme_constant_override("separation", 4)
	col.add_child(row_b)
	var i := 0
	for tag in LIVING_TITLE_NATIONS:
		var nbtn := Button.new()
		nbtn.text = str(tag)
		nbtn.tooltip_text = str(NATION_LABELS.get(str(tag), tag))
		nbtn.custom_minimum_size = Vector2(88, 32)
		nbtn.pressed.connect(_on_tag.bind(str(tag)))
		if i < 4:
			row_a.add_child(nbtn)
		else:
			row_b.add_child(nbtn)
		_nation_btns[str(tag)] = nbtn
		i += 1

	var sav_h := Label.new()
	sav_h.text = "LOAD GAME"
	RetrowaveTheme.style_column_header(sav_h)
	col.add_child(sav_h)
	_fill_save_rows(col)

	_begin_btn = Button.new()
	_begin_btn.custom_minimum_size = Vector2(0, 42)
	_begin_btn.pressed.connect(_on_begin_new)
	RetrowaveTheme.style_primary_button(_begin_btn)
	col.add_child(_begin_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(_status)
	col.add_child(_status)

	_refresh_choice_buttons()


func _fill_save_rows(col: VBoxContainer) -> void:
	var n := 0
	if typeof(SaveLoadManager) != TYPE_NIL and SaveLoadManager.has_method("list_slots_for_ui"):
		var rows: Array = SaveLoadManager.list_slots_for_ui()
		for raw in rows:
			if n >= 8:
				break
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = raw
			if not bool(row.get("can_load", row.get("occupied", false))):
				continue
			var slot := str(row.get("slot", "")).strip_edges()
			if slot.is_empty():
				continue
			var btn := Button.new()
			btn.text = "Load · %s" % str(row.get("label", slot))
			btn.custom_minimum_size = Vector2(0, 30)
			btn.pressed.connect(_on_load.bind(slot))
			RetrowaveTheme.style_secondary_button(btn)
			col.add_child(btn)
			n += 1
	if n == 0:
		var empty := Label.new()
		empty.text = "No saves yet — start a new campaign."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		RetrowaveTheme.style_body_label(empty)
		col.add_child(empty)


func select_from_province(province_id: int) -> Dictionary:
	var pid := int(province_id)
	var tag := playable_tag_from_province(pid)
	if tag.is_empty():
		if _status != null:
			_status.text = "Not a playable country — pick GER/ENG/FRA/JAP/USA/SOV/ITA/POL on the map."
		return {"ok": false, "playable": false, "pid": pid, "reason": "not a playable country"}
	_tag = tag
	_refresh_choice_buttons()
	if _status != null:
		_status.text = "Selected %s on the map — Begin to start · %d" % [
			str(NATION_LABELS.get(tag, tag)), _year
		]
	return {"ok": true, "playable": true, "pid": pid, "player_tag": tag}


func _on_tag(tag: String) -> void:
	_tag = tag.strip_edges().to_upper()
	_refresh_choice_buttons()


func _on_year(year: int) -> void:
	_year = int(year)
	_refresh_choice_buttons()


func _refresh_choice_buttons() -> void:
	for k in _nation_btns.keys():
		var btn: Button = _nation_btns[k]
		if btn == null or not is_instance_valid(btn):
			continue
		if str(k) == _tag:
			RetrowaveTheme.style_primary_button(btn)
		else:
			RetrowaveTheme.style_secondary_button(btn)
	for yk in _era_btns.keys():
		var ebtn: Button = _era_btns[yk]
		if ebtn == null or not is_instance_valid(ebtn):
			continue
		if int(yk) == _year:
			RetrowaveTheme.style_primary_button(ebtn)
		else:
			RetrowaveTheme.style_secondary_button(ebtn)
	if _begin_btn != null:
		var place := str(NATION_LABELS.get(_tag, _tag))
		_begin_btn.text = "Begin · %s · %d" % [place, _year]
	if _status != null:
		_status.text = "Click a playable nation on the map (or a tag). Default is GER 1936 Maginot until you Begin."


func _on_begin_new() -> void:
	var out: Dictionary = apply_living_title_boot(_tag, _year, "")
	_finish(out)


func _on_load(slot: String) -> void:
	var out: Dictionary = apply_living_title_boot(_tag, _year, slot)
	_finish(out)


func _finish(out: Dictionary) -> void:
	if _closed:
		return
	_closed = true
	_center_on_player(str(out.get("player_tag", _tag)))
	boot_closed.emit(out)
	queue_free()


func _center_on_player(tag: String) -> void:
	var t := tag.strip_edges().to_upper()
	if t.is_empty():
		t = "GER"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var mr: Node = tree.get_first_node_in_group("map_renderer")
	if mr == null and tree.current_scene != null:
		mr = tree.current_scene.find_child("MapRenderer", true, false)
	if mr == null or not mr.has_method("_center_camera_on_province"):
		return
	var pid := 710300 if t == "GER" else -1
	if t == "FRA":
		pid = 710739
	elif t == "ENG":
		pid = 711414
	elif t == "JAP":
		pid = 903981
	var loader: Node = tree.current_scene.find_child("ScenarioLoader", true, false) if tree.current_scene else null
	if loader != null and loader.has_method("_get_capital_province_id_for_tag"):
		var cap := int(loader.call("_get_capital_province_id_for_tag", t))
		if cap > 0:
			pid = cap
	if pid > 0:
		mr.call("_center_camera_on_province", pid, "soft")
