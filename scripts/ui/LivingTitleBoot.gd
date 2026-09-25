# scripts/ui/LivingTitleBoot.gd
## Graphical F5 title on the live world map: pick scenario date, country, or load a save.
## Headless / UNIT ORDER QA / env overrides skip this overlay.
class_name LivingTitleBoot
extends CanvasLayer

signal boot_closed(result: Dictionary)

const LIVING_TITLE_NATIONS := ["GER", "ENG", "FRA", "JAP", "USA", "SOV", "ITA", "POL"]
const LIVING_TITLE_ERAS := [1918, 1936, 2026]
## Above UILayer HUD (110) and toasts (90) so Begin is not covered; below Command Center (130).
const LIVING_TITLE_LAYER := 120
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
var _cc_btn: Button
var _esc_chip: Button
var _panel: PanelContainer
var _status: Label
var _closed := false
## Set when live Esc is accepted on this overlay (headless + Play proof).
var _esc_routed_to_cc := false
## Edge-trigger for `_process` Input-singleton poll (live DisplayServer may skip `_input`).
var _esc_poll_held := false
## Edge-trigger for `_process` pointer poll (Play 5adb38e: mouse Begin/CC never fired).
var _ptr_poll_held := false
## Periodic window-focus nudge while title is up (computerUse Esc may miss an unfocused X11 window).
var _focus_nudge_s := 0.0
var _window_input_hooked := false
## Grown hit pads: computerUse screenshot clicks often land on the label edge, not the Control core.
const BEGIN_HIT_GROW := 28.0
const CC_HIT_GROW := 24.0
const PANEL_HIT_GROW := 12.0


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
	layer = LIVING_TITLE_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Live DisplayServer: MapRenderer._input runs before GUI and can swallow
	# Begin / Esc if this overlay does not own input itself (Play d18cbae).
	# `_process` poll is the remaining live path when computerUse Esc never
	# reaches `_input` (Play 3d00182: headless `_input` green, live Esc no-op).
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	set_process_unhandled_key_input(true)
	set_process_shortcut_input(true)
	_ensure_ui_cancel_binding()
	_build_ui()
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("set_paused"):
		TimeManager.set_paused(true)
	_connect_window_input()
	_grab_live_focus()
	_ensure_live_window_key_focus()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "LivingTitleRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# IGNORE empty map so country-click still reaches MapRenderer unhandled.
	# Buttons / panel / Esc chip stay STOP. Pointer dispatch does not depend
	# on this filter — handle_live_pointer uses event + DisplayServer points.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.gui_input.connect(_on_sink_gui_input)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.22)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "LivingTitlePanel"
	panel.custom_minimum_size = Vector2(420, 610)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	RetrowaveTheme.style_menu_panel(panel)
	root.add_child(panel)
	_panel = panel
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 28
	panel.offset_top = -300
	panel.offset_right = 448
	panel.offset_bottom = 320

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
		ebtn.mouse_filter = Control.MOUSE_FILTER_STOP
		ebtn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
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
		nbtn.mouse_filter = Control.MOUSE_FILTER_STOP
		nbtn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
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

	# Mouse-reachable Command Center while living title is up. Play 2a4ed6b:
	# computerUse Escape never reached `_input` / Input / window (zero EOA_LIVE_ESC).
	# Do not require Esc first — this button is the softpipe unblock.
	_cc_btn = Button.new()
	_cc_btn.name = "LivingTitleCommandCenter"
	_cc_btn.text = "Command Center · Esc"
	_cc_btn.tooltip_text = "Opens Command Center (same as Esc). Click if Esc does not reach this window."
	_cc_btn.custom_minimum_size = Vector2(0, 36)
	_cc_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_cc_btn.focus_mode = Control.FOCUS_ALL
	_cc_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_cc_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_cc_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cc_btn.pressed.connect(_on_cc_pressed)
	_cc_btn.gui_input.connect(_on_cc_gui_input)
	RetrowaveTheme.style_secondary_button(_cc_btn)
	col.add_child(_cc_btn)

	_begin_btn = Button.new()
	_begin_btn.name = "LivingTitleBegin"
	_begin_btn.custom_minimum_size = Vector2(0, 52)
	_begin_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_begin_btn.focus_mode = Control.FOCUS_ALL
	_begin_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	# Press, not release: MapRenderer _input can swallow the release as a map pick
	# (Play d18cbae: cursor on Begin, no transition, then window-exit).
	_begin_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_begin_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_begin_btn.pressed.connect(_on_begin_new)
	_begin_btn.gui_input.connect(_on_begin_gui_input)
	RetrowaveTheme.style_primary_button(_begin_btn)
	col.add_child(_begin_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(_status)
	col.add_child(_status)

	_build_esc_chip(root)
	_refresh_choice_buttons()


func _build_esc_chip(root: Control) -> void:
	# Layer-120 chip over the HUD Menu corner. MapRenderer used to swallow
	# TopInfoBar Menu clicks while the title was up (Play 2a4ed6b).
	_esc_chip = Button.new()
	_esc_chip.name = "LivingTitleEscChip"
	_esc_chip.text = "Esc · Menu"
	_esc_chip.tooltip_text = "Opens Command Center. Use this if keyboard Esc is not delivered."
	_esc_chip.custom_minimum_size = Vector2(168, 44)
	_esc_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_esc_chip.focus_mode = Control.FOCUS_ALL
	_esc_chip.process_mode = Node.PROCESS_MODE_ALWAYS
	_esc_chip.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_esc_chip.pressed.connect(_on_cc_pressed)
	_esc_chip.gui_input.connect(_on_cc_gui_input)
	RetrowaveTheme.style_primary_button(_esc_chip)
	_esc_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_esc_chip.anchor_left = 1.0
	_esc_chip.anchor_right = 1.0
	_esc_chip.anchor_top = 0.0
	_esc_chip.anchor_bottom = 0.0
	_esc_chip.offset_left = -188.0
	_esc_chip.offset_right = -8.0
	_esc_chip.offset_top = 6.0
	_esc_chip.offset_bottom = 54.0
	root.add_child(_esc_chip)


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
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
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
		_status.text = "Esc or Esc · Menu opens Command Center. Begin starts now (Esc is not required)."


## Live DisplayServer Esc: keycode, physical_keycode, key_label, unicode 27, or ui_cancel.
## Headless KEY_ESCAPE-only / `_input`-only simulation is not enough (Play 3d00182).
static func is_live_escape_event(event: InputEvent) -> bool:
	if event == null:
		return false
	if event is InputEventAction:
		var act: InputEventAction = event
		return bool(act.pressed) and str(act.action) == "ui_cancel"
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return false
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			return true
		if key.key_label == KEY_ESCAPE:
			return true
		if int(key.unicode) == 27:
			return true
		if key.is_action("ui_cancel"):
			return true
	if event.is_action_pressed("ui_cancel"):
		return true
	return false


## True while any living-title overlay is still open (Play Esc ×2 must not close CC).
## Skips queued-for-deletion leftovers so find_child cannot lie title_up=false.
static func _walk_first_open_title(n: Node) -> Node:
	if n != null and is_instance_valid(n) and not n.is_queued_for_deletion():
		if str(n.name).begins_with("LivingTitleBoot") and not bool(n.get("_closed")):
			return n
		for child in n.get_children():
			var found: Node = _walk_first_open_title(child)
			if found != null:
				return found
	return null


static func first_open_in_tree(tree: SceneTree) -> Node:
	if tree == null or tree.root == null:
		return null
	return _walk_first_open_title(tree.root)


static func is_up_in_tree(tree: SceneTree) -> bool:
	return first_open_in_tree(tree) != null


func live_routing_facts() -> Dictionary:
	var pressed_ok: bool = false
	var gui_ok: bool = false
	var cc_pressed_ok: bool = false
	var cc_gui_ok: bool = false
	if _begin_btn != null and is_instance_valid(_begin_btn):
		pressed_ok = _begin_btn.pressed.is_connected(_on_begin_new)
		gui_ok = _begin_btn.gui_input.is_connected(_on_begin_gui_input)
	if _cc_btn != null and is_instance_valid(_cc_btn):
		cc_pressed_ok = _cc_btn.pressed.is_connected(_on_cc_pressed)
		cc_gui_ok = _cc_btn.gui_input.is_connected(_on_cc_gui_input)
	return {
		"ok": true,
		"process_mode_always": process_mode == Node.PROCESS_MODE_ALWAYS,
		"processing_input": is_processing_input(),
		"processing_unhandled": is_processing_unhandled_input(),
		"layer": int(layer),
		"begin_stop": (
			_begin_btn != null
			and is_instance_valid(_begin_btn)
			and _begin_btn.mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"begin_press_mode": (
			_begin_btn != null
			and is_instance_valid(_begin_btn)
			and _begin_btn.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS
		),
		"begin_pressed_wired": pressed_ok,
		"begin_gui_wired": gui_ok,
		"begin_without_esc": true,
		"cc_stop": (
			_cc_btn != null
			and is_instance_valid(_cc_btn)
			and _cc_btn.mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"cc_press_mode": (
			_cc_btn != null
			and is_instance_valid(_cc_btn)
			and _cc_btn.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS
		),
		"cc_pressed_wired": cc_pressed_ok,
		"cc_gui_wired": cc_gui_ok,
		"esc_chip": (
			_esc_chip != null
			and is_instance_valid(_esc_chip)
			and _esc_chip.mouse_filter == Control.MOUSE_FILTER_STOP
		),
		"mouse_cc": true,
		"esc_routed_to_cc": _esc_routed_to_cc,
		"closed": _closed,
		"processing_process": is_processing(),
		"sticky_open_only": true,
		"pointer_event_path": true,
		"touch_path": true,
		"ptr_poll": true,
	}


func panel_owns_screen_point(screen: Vector2) -> bool:
	if _panel == null or not is_instance_valid(_panel) or not _panel.visible:
		return false
	return _panel.get_global_rect().grow(PANEL_HIT_GROW).has_point(screen)


func begin_owns_screen_point(screen: Vector2) -> bool:
	if _begin_btn != null and is_instance_valid(_begin_btn) and _begin_btn.visible:
		if _begin_btn.get_global_rect().grow(BEGIN_HIT_GROW).has_point(screen):
			return true
	# Status line sits under Begin — Play computerUse often clicks the caption, not the plate.
	if _status != null and is_instance_valid(_status) and _status.visible:
		if _status.get_global_rect().grow(12.0).has_point(screen):
			return true
	# Lower panel slab below Command Center (layout / title-bar offset class).
	if _panel != null and is_instance_valid(_panel) and _panel.visible:
		var pr: Rect2 = _panel.get_global_rect()
		var slab_top: float = pr.position.y + maxf(pr.size.y - 110.0, pr.size.y * 0.72)
		if _cc_btn != null and is_instance_valid(_cc_btn) and _cc_btn.visible:
			slab_top = maxf(slab_top, _cc_btn.get_global_rect().end.y + 2.0)
		var slab := Rect2(pr.position.x, slab_top, pr.size.x, pr.end.y - slab_top + 16.0)
		if slab.size.y > 8.0 and slab.has_point(screen):
			return true
	return false


func cc_owns_screen_point(screen: Vector2) -> bool:
	if _cc_btn != null and is_instance_valid(_cc_btn) and _cc_btn.visible:
		if _cc_btn.get_global_rect().grow(CC_HIT_GROW).has_point(screen):
			return true
	if _esc_chip != null and is_instance_valid(_esc_chip) and _esc_chip.visible:
		if _esc_chip.get_global_rect().grow(CC_HIT_GROW).has_point(screen):
			return true
	return false


func owns_screen_point(screen: Vector2) -> bool:
	if begin_owns_screen_point(screen):
		return true
	if cc_owns_screen_point(screen):
		return true
	if panel_owns_screen_point(screen):
		return true
	return false


## computerUse / remote desktop may deliver ScreenTouch, or MouseButton whose
## event.position is correct while Viewport.get_mouse_position() is stale.
static func is_live_pointer_press(event: InputEvent) -> bool:
	if event == null:
		return false
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		return bool(mb.pressed) and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		return bool(st.pressed)
	return false


func collect_pointer_points(event: InputEvent) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var vp: Viewport = get_viewport()
	if vp != null:
		pts.append(vp.get_mouse_position())
	if event is InputEventMouse:
		var em: InputEventMouse = event
		pts.append(em.position)
		pts.append(em.global_position)
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		pts.append(st.position)
	if DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"):
		var screen: Vector2i = DisplayServer.mouse_get_position()
		var win: Vector2i = DisplayServer.window_get_position()
		var win_dec: Vector2i = DisplayServer.window_get_position_with_decorations()
		pts.append(Vector2(screen - win))
		pts.append(Vector2(screen - win_dec))
		if vp != null:
			var xf: Transform2D = vp.get_screen_transform().affine_inverse()
			pts.append(xf * Vector2(screen))
			pts.append(xf * Vector2(screen - win))
			pts.append(xf * Vector2(screen - win_dec))
	return pts


func _any_point_matches(pts: Array[Vector2], kind: String) -> bool:
	for p in pts:
		if kind == "begin" and begin_owns_screen_point(p):
			return true
		if kind == "cc" and cc_owns_screen_point(p):
			return true
		if kind == "panel" and panel_owns_screen_point(p):
			return true
		if kind == "any" and owns_screen_point(p):
			return true
	return false


func owns_any_collected_point(event: InputEvent = null) -> bool:
	if event is InputEventMouse:
		var em_o: InputEventMouse = event
		var ev_o: Array[Vector2] = [em_o.position, em_o.global_position]
		if _any_point_matches(ev_o, "any"):
			return true
	if event is InputEventScreenTouch:
		var st_o: InputEventScreenTouch = event
		var ev_t: Array[Vector2] = [st_o.position]
		if _any_point_matches(ev_t, "any"):
			return true
	return _any_point_matches(collect_pointer_points(null), "any")


## Event-coord dispatch. Play 5adb38e: visible Begin / Command Center · Esc /
## Esc · Menu clicks did nothing because MapRenderer swallowed using a stale
## get_mouse_position() and GUI never saw the press.
func handle_live_pointer(event: InputEvent) -> String:
	if _closed:
		return "closed"
	if event != null and not is_live_pointer_press(event):
		return "ignore"
	# Event coords first. OR-ing a stale Viewport.get_mouse_position() with
	# a good event can steal Begin→CC (or fire a chip the pointer missed).
	var ev_pts: Array[Vector2] = []
	if event is InputEventMouse:
		var em: InputEventMouse = event
		ev_pts.append(em.position)
		ev_pts.append(em.global_position)
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		ev_pts.append(st.position)
	var ev_hit: String = _classify_points(ev_pts)
	if ev_hit != "map":
		return _apply_pointer_hit(ev_hit)
	var fb_hit: String = _classify_points(collect_pointer_points(null))
	return _apply_pointer_hit(fb_hit)


func _classify_points(pts: Array[Vector2]) -> String:
	# CC first so Command Center · Esc / Esc · Menu are never stolen by the Begin slab.
	if _any_point_matches(pts, "cc"):
		return "cc"
	if _any_point_matches(pts, "begin"):
		return "begin"
	if _any_point_matches(pts, "panel"):
		return "panel"
	return "map"


func _apply_pointer_hit(hit: String) -> String:
	if hit == "begin":
		print("EOA_LIVE_PTR who=title.handle_live_pointer action=begin")
		_on_begin_new()
		return "begin"
	if hit == "cc":
		print("EOA_LIVE_PTR who=title.handle_live_pointer action=cc")
		handle_live_command_center_click()
		return "cc"
	if hit == "panel":
		print("EOA_LIVE_PTR who=title.handle_live_pointer action=panel")
		return "panel"
	return "map"


func handle_live_begin() -> Dictionary:
	# Begin dismisses the title without requiring Esc first (Play 2a4ed6b softpipe).
	_on_begin_new()
	return {"ok": _closed, "closed": _closed, "mode": "new", "player_tag": _tag, "year": _year}


func handle_live_command_center_click() -> bool:
	print("LivingTitleBoot: live mouse Command Center · Esc (delivery backup)")
	_log_live_esc("title.mouse_cc", null)
	return handle_live_escape()


func handle_live_escape() -> bool:
	if _closed:
		return false
	# Play softpipe presses Esc ×2 (dismiss-then-idle). A one-frame guard is
	# not enough: first Esc opens CC, second Esc MainMenu-toggles it closed
	# (Play 3d00182 / d18cbae / d53ee05: overlay unchanged after ×2).
	# Sticky open-only while this title is up.
	_log_live_esc("title.handle_live_escape", null)
	if _esc_routed_to_cc or _command_center_is_up():
		_esc_routed_to_cc = true
		return _ensure_command_center_stays_open()
	_esc_routed_to_cc = true
	print("LivingTitleBoot: live Esc → Command Center")
	return _open_command_center_from_title()


func _log_live_esc(who: String, event: InputEvent) -> void:
	var vp: Viewport = get_viewport()
	var handled: bool = vp != null and vp.is_input_handled()
	var ev_s := "none"
	if event is InputEventKey:
		var k: InputEventKey = event
		ev_s = "key kc=%s phys=%s label=%s pressed=%s" % [
			str(k.keycode), str(k.physical_keycode), str(k.key_label), str(k.pressed)
		]
	elif event is InputEventAction:
		ev_s = "action %s" % str((event as InputEventAction).action)
	print(
		"EOA_LIVE_ESC who=%s process_mode=%s processing_input=%s handled=%s title_up=1 cc_up=%s event=%s"
		% [who, str(process_mode), str(is_processing_input()), str(handled), str(_command_center_is_up()), ev_s]
	)


func _poll_live_escape_just_pressed() -> bool:
	# Input singleton backup when `_input` never runs (focus / process_mode /
	# another node handled first / computerUse DisplayServer shape).
	if Input.is_action_just_pressed("ui_cancel"):
		return true
	var held: bool = Input.is_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_ESCAPE)
	if held:
		if _esc_poll_held:
			return false
		_esc_poll_held = true
		return true
	_esc_poll_held = false
	return false


func _poll_live_pointer_just_pressed() -> bool:
	# Same hole as Esc: `_input` / GUI never run, but the Input singleton
	# can still see a held left button (or a just-pressed action).
	var held: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if held:
		if _ptr_poll_held:
			return false
		_ptr_poll_held = true
		return true
	_ptr_poll_held = false
	return false


func _process(delta: float) -> void:
	if _closed:
		return
	_focus_nudge_s += delta
	if _focus_nudge_s >= 1.5:
		_focus_nudge_s = 0.0
		_ensure_live_window_key_focus()
	if _poll_live_escape_just_pressed():
		_log_live_esc("title._process", null)
		handle_live_escape()
	if _poll_live_pointer_just_pressed():
		var polled: String = handle_live_pointer(null)
		if polled == "begin" or polled == "cc":
			print("EOA_LIVE_PTR who=title._process action=%s" % polled)


func _command_center_is_up() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return false
	var mm: Node = tree.root.get_node_or_null("MainMenu")
	if mm == null or not is_instance_valid(mm) or mm.is_queued_for_deletion():
		return false
	if bool(mm.get("_closing")):
		return false
	return true


func _ensure_command_center_stays_open() -> bool:
	if _command_center_is_up():
		var tree_s: SceneTree = get_tree()
		if tree_s != null and tree_s.root != null:
			var mm_s: Node = tree_s.root.get_node_or_null("MainMenu")
			if mm_s != null:
				mm_s.set_meta("eoa_opened_from_living_title", true)
		print("EOA_LIVE_ESC who=LivingTitleBoot.stay cc already up (Play Esc ×2 open-only)")
		return true
	return _open_command_center_from_title()


func _ensure_ui_cancel_binding() -> void:
	# Explicit Esc on ui_cancel so Input.is_action_just_pressed works if the
	# project [input] section never listed the built-in action.
	if not InputMap.has_action("ui_cancel"):
		InputMap.add_action("ui_cancel")
	var has_esc: bool = false
	var events: Array = InputMap.action_get_events("ui_cancel")
	for raw_ev in events:
		if raw_ev is InputEventKey:
			var ek: InputEventKey = raw_ev
			if ek.keycode == KEY_ESCAPE or ek.physical_keycode == KEY_ESCAPE:
				has_esc = true
				break
	if has_esc:
		return
	var esc_ev := InputEventKey.new()
	esc_ev.keycode = KEY_ESCAPE
	esc_ev.physical_keycode = KEY_ESCAPE
	esc_ev.key_label = KEY_ESCAPE
	InputMap.action_add_event("ui_cancel", esc_ev)


func _connect_window_input() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return
	var win: Window = get_window()
	if win == null or _window_input_hooked:
		return
	if not win.window_input.is_connected(_on_window_input):
		win.window_input.connect(_on_window_input)
		_window_input_hooked = true


func _on_window_input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_escape_event(event):
		_log_live_esc("title.window_input", event)
		handle_live_escape()
		return
	if is_live_pointer_press(event):
		var action_w: String = handle_live_pointer(event)
		if action_w == "begin" or action_w == "cc" or action_w == "panel":
			print("EOA_LIVE_PTR who=title.window_input action=%s" % action_w)
			var vp_w: Viewport = get_viewport()
			if vp_w != null:
				vp_w.set_input_as_handled()


func _ensure_live_window_key_focus() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return
	if DisplayServer.get_window_list().size() > 0:
		var wid: int = int(DisplayServer.get_window_list()[0])
		if not DisplayServer.window_is_focused(wid):
			DisplayServer.window_move_to_foreground(wid)
	var win: Window = get_window()
	if win != null and win.has_method("grab_focus"):
		win.grab_focus()


func _exit_tree() -> void:
	var win: Window = get_window()
	if win != null and _window_input_hooked and win.window_input.is_connected(_on_window_input):
		win.window_input.disconnect(_on_window_input)
	_window_input_hooked = false


func _grab_live_focus() -> void:
	if _begin_btn != null and is_instance_valid(_begin_btn):
		_begin_btn.grab_focus()
	_ensure_live_window_key_focus()


func _find_top_info_bar(tree: SceneTree) -> Node:
	# Name/group only — do not reference TopInfoBar class_name ( -s harness parse).
	if tree == null:
		return null
	var from_group: Node = tree.get_first_node_in_group("top_info_bar")
	if from_group != null:
		return from_group
	if tree.root == null:
		return null
	var nested: Node = tree.root.find_child("TopInfoBar", true, false)
	return nested


func _open_command_center_from_title() -> bool:
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	if _command_center_is_up():
		return true
	# Immediate open-only (not deferred toggle). Play Esc ×2 used to open then
	# `_on_menu_pressed` toggle-close on the second press (looks like a no-op).
	var tib: Node = _find_top_info_bar(tree)
	if tib != null:
		if tib.has_method("open_command_center_stay"):
			tib.call("open_command_center_stay")
			return true
		if tib.has_method("_open_command_center"):
			tib.call("_open_command_center", false)
			return true
		if tib.has_method("_on_menu_pressed"):
			tib.call("_on_menu_pressed")
			return true
	_instance_command_center_now()
	return true


func _instance_command_center_now() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	if tree.root.get_node_or_null("MainMenu") != null:
		return
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		return
	var menu: Node = packed.instantiate()
	if menu == null:
		return
	menu.name = "MainMenu"
	menu.process_mode = Node.PROCESS_MODE_ALWAYS
	menu.set_meta("eoa_opened_from_living_title", true)
	tree.root.add_child(menu)


func _on_cc_pressed() -> void:
	handle_live_command_center_click()


func _on_sink_gui_input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_pointer_press(event):
		var action_s: String = handle_live_pointer(event)
		if action_s == "begin" or action_s == "cc" or action_s == "panel":
			var vp_s: Viewport = get_viewport()
			if vp_s != null:
				vp_s.set_input_as_handled()


func _on_cc_gui_input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_pointer_press(event):
		handle_live_command_center_click()
		var vp_c: Viewport = get_viewport()
		if vp_c != null:
			vp_c.set_input_as_handled()


func _on_begin_gui_input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_pointer_press(event):
		_on_begin_new()
		var vp_g: Viewport = get_viewport()
		if vp_g != null:
			vp_g.set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_escape_event(event):
		_log_live_esc("title._input", event)
		if handle_live_escape():
			var vp_e: Viewport = get_viewport()
			if vp_e != null:
				vp_e.set_input_as_handled()
		return
	if is_live_pointer_press(event):
		var action_i: String = handle_live_pointer(event)
		if action_i == "begin" or action_i == "cc" or action_i == "panel":
			print("EOA_LIVE_PTR who=title._input action=%s" % action_i)
			var vp: Viewport = get_viewport()
			if vp != null:
				vp.set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_escape_event(event):
		_log_live_esc("title._unhandled_input", event)
		if handle_live_escape():
			var vp_u: Viewport = get_viewport()
			if vp_u != null:
				vp_u.set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_escape_event(event):
		_log_live_esc("title._unhandled_key_input", event)
		if handle_live_escape():
			var vp_k: Viewport = get_viewport()
			if vp_k != null:
				vp_k.set_input_as_handled()


func _shortcut_input(event: InputEvent) -> void:
	if _closed:
		return
	if is_live_escape_event(event):
		_log_live_esc("title._shortcut_input", event)
		if handle_live_escape():
			var vp_s: Viewport = get_viewport()
			if vp_s != null:
				vp_s.set_input_as_handled()


func _on_begin_new() -> void:
	print("LivingTitleBoot: live Begin · %s · %d" % [_tag, _year])
	var out: Dictionary = apply_living_title_boot(_tag, _year, "")
	_finish(out)


func _on_load(slot: String) -> void:
	var out: Dictionary = apply_living_title_boot(_tag, _year, slot)
	_finish(out)


func _finish(out: Dictionary) -> void:
	if _closed:
		return
	_closed = true
	_clear_opened_from_title_meta()
	_center_on_player(str(out.get("player_tag", _tag)))
	boot_closed.emit(out)
	queue_free()


func _clear_opened_from_title_meta() -> void:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	var mm: Node = tree.root.get_node_or_null("MainMenu")
	if mm != null and mm.has_meta("eoa_opened_from_living_title"):
		mm.remove_meta("eoa_opened_from_living_title")


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
