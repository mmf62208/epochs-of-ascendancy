extends SceneTree

## ORDERS-1 play-loop: Halt / Hold / Withdraw do what the card says,
## with a visible card (and chip/path) state change.
## Does not load WorldMap.tscn / 3520 polygons.
## Does not touch first-session tip / TipDismiss / release-fallthrough.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessOrders1HaltHoldWithdrawTest.gd
##   tools/eoa_orders1_guard.sh

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const LEV := 710418
const BERLIN := 710300
const GER_TAG := "GER"
const FID := "orders1_ger_div"
const FID_DEF := "orders1_fra_def"
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const BATTLE_ID := "lb_orders1"
const FLUSH_FRAMES := 8

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _mv: Script = null
var _cam: Camera2D = null
var _info: Panel = null
var _chip: Node2D = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessOrders1HaltHoldWithdrawTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessOrders1HaltHoldWithdrawTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessOrders1HaltHoldWithdrawTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessOrders1HaltHoldWithdrawTest: ", msg)


func _info_line(msg: String) -> void:
	print("  [INFO] HeadlessOrders1HaltHoldWithdrawTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _slice_func(src: String, func_name: String) -> String:
	var needle := "func %s" % func_name
	var i := src.find(needle)
	if i < 0:
		return ""
	var nxt_a := src.find("\nfunc ", i + needle.length())
	var nxt_b := src.find("\nstatic func ", i + needle.length())
	var nxt := -1
	if nxt_a >= 0 and nxt_b >= 0:
		nxt = mini(nxt_a, nxt_b)
	elif nxt_a >= 0:
		nxt = nxt_a
	else:
		nxt = nxt_b
	if nxt < 0:
		return src.substr(i)
	return src.substr(i, nxt - i)


func _run() -> void:
	_test_source_needles()
	_lm = _autoload("LeaderManager")
	_mm = _autoload("MapManager")
	_bm = _autoload("BattleManager")
	_mv = load("res://scripts/formations/FormationMovement.gd") as Script
	if _lm == null or _mm == null or _bm == null:
		_fail("autoloads missing")
		return
	if _mv == null:
		_fail("FormationMovement.gd missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_nuts3_fixture():
		return
	if not _setup_formations():
		return
	if not _setup_map_renderer():
		return
	await _test_halt_loop()
	await _test_hold_loop()
	await _test_withdraw_loop()
	_cleanup()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	if ren.is_empty():
		_fail("MapRenderer.gd missing")
		return
	var show_pop := _slice_func(ren, "_show_unit_detail_popup")
	if show_pop.is_empty():
		_fail("_show_unit_detail_popup missing")
		return
	if "BtnHaltMarch" not in show_pop or "clear_march" not in show_pop:
		_fail("Halt march must call clear_march")
		return
	if "BtnHoldStance" not in show_pop or "set_land_battle_stance" not in show_pop:
		_fail("Hold must call set_land_battle_stance")
		return
	if "BtnWithdraw" not in show_pop or "withdraw_from_land_battle" not in show_pop:
		_fail("Withdraw must call withdraw_from_land_battle")
		return
	if "Hold ●" not in show_pop:
		_fail("Hold must paint Hold ● when stance is hold")
		return
	# ORDERS-1 visible-state contract: pending withdraw must be readable
	# on the rebuilt card (button and/or body), not only a toast of "true".
	if "Withdraw ●" not in show_pop and "Withdrawing" not in show_pop:
		_fail("card must show Withdraw ● or Withdrawing after same-day withdraw")
		return
	if "show_first_session_action_tip" in show_pop or "TipDismiss" in show_pop:
		_fail("unit-card popup must not own the first-session tip strip")
		return
	_pass("source needles: Halt/Hold/Withdraw + visible withdraw state; tip strip fenced")


func _setup_nuts3_fixture() -> bool:
	if not FileAccess.file_exists(ADJ_PATH):
		_fail("nuts3 adjacency missing")
		return false
	var adj_sys: Object = _new_obj("res://scripts/data/AdjacencySystem.gd")
	if adj_sys == null:
		_fail("AdjacencySystem create failed")
		return false
	if adj_sys.has_method("load_adjacency"):
		adj_sys.call("load_adjacency", ADJ_PATH)
	var rows: Array = [
		{"id": BONN, "tag": GER_TAG, "name": "Bonn"},
		{"id": KOELN, "tag": GER_TAG, "name": "Köln"},
		{"id": LEV, "tag": GER_TAG, "name": "Leverkusen"},
		{"id": BERLIN, "tag": GER_TAG, "name": "Berlin"},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {GER_TAG: {"tag": GER_TAG, "name": "Germany"}}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("Province create failed")
			return false
		p.set("id", pid)
		p.set("owner_tag", GER_TAG)
		p.set("controller_tag", GER_TAG)
		p.set("terrain", "plains")
		p.set("name", str(row["name"]))
		p.set("is_sea", false)
		p.set("infrastructure", 4)
		p.set("development_level", 3)
		p.set("core_for", [GER_TAG])
		provs[pid] = p
		if adj_sys.has_method("register_province"):
			adj_sys.call("register_province", p)
	var mds: Script = load("res://scripts/data/MapScenarioData.gd") as Script
	var map_data: Object = mds.new(provs, {}, adj_sys, countries) if mds != null else null
	if map_data == null:
		_fail("MapScenarioData create failed")
		return false
	if _mm.has_method("initialize_from_map_data"):
		_mm.call("initialize_from_map_data", map_data)
	else:
		_fail("initialize_from_map_data missing")
		return false
	if not _edge(BONN, KOELN) or not _edge(KOELN, LEV):
		_fail("fixture missing Bonn–Köln / Köln–Leverkusen")
		return false
	_pass("nuts3 fixture Bonn/Köln/Leverkusen + Berlin")
	return true


func _edge(a: int, b: int) -> bool:
	if _mm == null or not _mm.has_method("get_adjacent_provinces"):
		return false
	for n in _mm.call("get_adjacent_provinces", a, true):
		if int(n) == b:
			return true
	return false


func _fm(method: String, a: Variant = null, b: Variant = null, c: Variant = null) -> Variant:
	if _mv == null:
		return null
	var inst: Object = _mv.new() as Object
	if inst == null:
		return null
	if c != null:
		return inst.call(method, a, b, c)
	if b != null:
		return inst.call(method, a, b)
	if a != null:
		return inst.call(method, a)
	return inst.call(method)


func _setup_formations() -> bool:
	_fm("clear_march", FID)
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed")
		return false
	f.set("formation_id", FID)
	f.set("country_tag", GER_TAG)
	f.set("formation_type", "division")
	f.set("design_id", DESIGN)
	f.set("stationed_province_id", BONN)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("is_in_combat", false)
	f.set("name", "GER ORDERS-1 Div")
	if "formations" in _lm:
		_lm.formations[FID] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)
	var d: Object = _new_obj("res://scripts/formations/Formation.gd")
	if d != null:
		d.set("formation_id", FID_DEF)
		d.set("country_tag", "FRA")
		d.set("formation_type", "division")
		d.set("design_id", DESIGN)
		d.set("stationed_province_id", BERLIN)
		d.set("strength", 1.0)
		d.set("organization", 1.0)
		d.set("readiness", 1.0)
		d.set("is_in_combat", false)
		d.set("name", "FRA ORDERS-1 Def")
		if "formations" in _lm:
			_lm.formations[FID_DEF] = d
	_pass("seeded GER attacker at Bonn + FRA defender")
	return true


func _setup_map_renderer() -> bool:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		return false
	_mr = mr_script.new() as Node
	if _mr == null:
		_fail("MapRenderer create failed")
		return false
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	_mr.add_child(container)
	if "container" in _mr:
		_mr.container = container
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	_mr.add_child(_ui)
	_info = Panel.new()
	_info.name = "InfoPanel"
	_info.visible = false
	_info.size = Vector2(280, 200)
	_ui.add_child(_info)
	_mr.set("info_panel", _info)
	_cam = Camera2D.new()
	_cam.name = "MapCamera"
	_cam.position = Vector2(400, 300)
	_cam.enabled = true
	_mr.add_child(_cam)
	root.add_child(_mr)
	_cam.make_current()
	var pids: Array = [BONN, KOELN, LEV, BERLIN]
	for pid_v in pids:
		var pid := int(pid_v)
		var gp: Variant = _mm.call("get_province", pid) if _mm.has_method("get_province") else null
		if gp == null:
			_fail("MapManager missing province %d" % pid)
			return false
		if "provinces" in _mr:
			_mr.provinces[pid] = gp
		var node := Node2D.new()
		node.name = "Province_%d" % pid
		container.add_child(node)
		if "province_nodes" in _mr:
			_mr.province_nodes[pid] = node
		if "province_centroids" in _mr:
			_mr.province_centroids[pid] = Vector2(float(pid % 100) * 8.0, 40.0)
	_place_chip()
	_pass("MapRenderer + UI canvas + GER chip")
	return true


func _place_chip() -> void:
	if _mr == null or not ("province_nodes" in _mr):
		return
	var host: Node2D = _mr.province_nodes.get(BONN) as Node2D
	if host == null:
		return
	var old: Node = host.get_node_or_null("DemoUnitIcon_%d" % BONN)
	if old != null:
		old.free()
	_chip = Node2D.new()
	_chip.name = "DemoUnitIcon_%d" % BONN
	_chip.visible = true
	host.add_child(_chip)
	_chip.position = Vector2.ZERO
	var fo: Object = _formation()
	_chip.set_meta("formation", fo)
	_chip.set_meta("formation_id", FID)
	_chip.set_meta("province_id", BONN)
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true
	if "_demo_unit_icon_pids" in _mr:
		var pids: Array = _mr._demo_unit_icon_pids
		if not pids.has(BONN):
			pids.append(BONN)
			_mr._demo_unit_icon_pids = pids
	if fo != null and _mr.has_method("_attach_unit_counter_chrome"):
		_mr.call("_attach_unit_counter_chrome", _chip, fo, Color(0.2, 0.35, 0.22, 1.0))
	if _mr.has_method("_refresh_selected_unit_chip"):
		_mr.call("_refresh_selected_unit_chip")


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _count_named(parent: Node, prefix: String) -> int:
	if parent == null:
		return 0
	var n := 0
	for c in parent.get_children():
		if str(c.name).begins_with(prefix):
			n += 1
	return n


func _find_card_btn(node_name: String, text_prefix: String) -> Button:
	var pop: Node = _popup()
	if pop == null:
		return null
	var named: Button = pop.find_child(node_name, true, false) as Button
	if named != null:
		return named
	for n in pop.find_children("*", "Button", true, false):
		if n is Button and str((n as Button).text).begins_with(text_prefix):
			return n as Button
	return null


func _popup() -> Node:
	if _ui == null:
		return null
	return _ui.get_node_or_null("UnitDetailPopup")


func _card_text() -> String:
	var pop: Node = _popup()
	if pop == null:
		return ""
	var bits: PackedStringArray = PackedStringArray()
	for n in pop.find_children("*", "Label", true, false):
		if n is Label:
			var t := str((n as Label).text).strip_edges()
			if not t.is_empty():
				bits.append(t)
	for n2 in pop.find_children("*", "Button", true, false):
		if n2 is Button:
			var bt := str((n2 as Button).text).strip_edges()
			if not bt.is_empty():
				bits.append(bt)
	return " | ".join(bits)


func _button_screen_pos(btn: Button) -> Vector2:
	if btn == null:
		return Vector2(97, 731)
	var r: Rect2 = btn.get_global_rect()
	if r.size.x > 1.0 and r.size.y > 1.0:
		return r.position + r.size * 0.5
	return btn.position + Vector2(24, 10)


func _log_button_rect(label: String, btn: Button) -> void:
	if btn == null:
		_info_line("%s missing" % label)
		return
	var r: Rect2 = btn.get_global_rect()
	_info_line(
		"%s text=%s rect=(%.1f,%.1f %.1fx%.1f) center=(%.1f,%.1f)"
		% [label, btn.text, r.position.x, r.position.y, r.size.x, r.size.y,
			r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5]
	)


func _show_selected_card() -> void:
	var fo: Object = _formation()
	if fo == null or _mr == null:
		return
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	_mr.call("_show_unit_detail_popup", fo)


func _flush_frames() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _chip_has(name_s: String) -> bool:
	if _chip == null or not is_instance_valid(_chip):
		return false
	return _chip.get_node_or_null(name_s) != null


func _inject_open_battle(days_elapsed: int = 0) -> void:
	if _bm == null or not ("_open_land_battles" in _bm):
		return
	_clear_injected_battle()
	var rows: Array = _bm._open_land_battles
	rows.append({
		"id": BATTLE_ID,
		"from_id": BONN,
		"to_id": BERLIN,
		"att_tag": GER_TAG,
		"def_tag": "FRA",
		"att_fid": FID,
		"def_fid": FID_DEF,
		"att_fids": [FID],
		"def_fids": [FID_DEF],
		"att_n": 1,
		"def_n": 1,
		"att_org": 1.0,
		"def_org": 1.0,
		"att_stance": "press",
		"days_elapsed": days_elapsed,
		"withdraw_pending": false,
		"next_hook": "Unpause to fight · Press or Hold",
	})
	_bm._open_land_battles = rows
	var fo: Object = _formation()
	if fo != null:
		fo.set("is_in_combat", true)
	if _mr.has_method("_attach_unit_counter_chrome") and _chip != null and fo != null:
		_mr.call("_attach_unit_counter_chrome", _chip, fo, Color(0.2, 0.35, 0.22, 1.0))
	if _mr.has_method("_sync_land_battle_bubbles"):
		_mr.call("_sync_land_battle_bubbles")


func _clear_injected_battle() -> void:
	if _bm == null or not ("_open_land_battles" in _bm):
		return
	var kept: Array = []
	for raw in _bm._open_land_battles:
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == BATTLE_ID:
			continue
		kept.append(raw)
	_bm._open_land_battles = kept


func _battle_for_fid() -> Dictionary:
	if _bm != null and _bm.has_method("get_land_battle_for_formation"):
		return _bm.call("get_land_battle_for_formation", FID) as Dictionary
	return {}


func _test_halt_loop() -> void:
	_fm("clear_march", FID)
	var fo: Object = _formation()
	if fo == null:
		_fail("formation missing for Halt")
		return
	fo.set("stationed_province_id", BONN)
	fo.set("is_in_combat", false)
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	var marched: Dictionary = _fm("enqueue_own_land_march", FID, KOELN, GER_TAG)
	if not bool(marched.get("ok", false)):
		_fail("enqueue Bonn→Köln failed: %s" % str(marched.get("reason", marched)))
		return
	if not bool(_fm("has_march", FID)):
		_fail("has_march false after enqueue")
		return
	if _mr.has_method("_try_move_selected_unit_to_province"):
		var dest_p: Object = _mm.call("get_province", KOELN) if _mm.has_method("get_province") else null
		if dest_p != null:
			_mr.call("_try_move_selected_unit_to_province", dest_p)
	_show_selected_card()
	await _flush_frames()
	var halt_btn: Button = _find_card_btn("BtnHaltMarch", "Halt march")
	var assign_btn: Button = _find_card_btn("BtnAssignLeader", "Assign")
	_log_button_rect("Halt", halt_btn)
	_log_button_rect("Assign", assign_btn)
	if halt_btn == null:
		_fail("Halt march missing on marching card")
		return
	if assign_btn != null:
		var hr: Rect2 = halt_btn.get_global_rect()
		var ar: Rect2 = assign_btn.get_global_rect()
		var gap := ar.position.x - (hr.position.x + hr.size.x)
		_info_line("Halt-vs-Assign layout gap_x=%.1f (click Halt center, not Assign)" % gap)
		if hr.intersects(ar):
			_fail("Halt and Assign rects overlap — Play will misclick")
			return
	var path_before := _count_named(_mr, "MarchPathLine")
	var station_before := int(fo.get("stationed_province_id"))
	halt_btn.pressed.emit()
	await _flush_frames()
	if bool(_fm("has_march", FID)):
		_fail("unit still marching after Halt")
		return
	if int(fo.get("stationed_province_id")) != station_before:
		_fail("Halt moved the unit off hex %d" % station_before)
		return
	if _find_card_btn("BtnHaltMarch", "Halt march") != null:
		_fail("Halt still on card after march cleared")
		return
	var path_after := _count_named(_mr, "MarchPathLine")
	if path_after > 0 and path_after >= path_before and path_before > 0:
		_fail("MarchPathLine still present after Halt")
		return
	var after_txt := _card_text()
	if after_txt.findn("Halt march") >= 0:
		_fail("card text still lists Halt march")
		return
	_info_line("after Halt card=%s" % after_txt)
	_pass("Halt: march cleared, stay on hex, Halt gone, path dropped")


func _test_hold_loop() -> void:
	_fm("clear_march", FID)
	_inject_open_battle(0)
	if _bm != null and _bm.has_method("set_land_battle_stance"):
		var api_r: Dictionary = _bm.call("set_land_battle_stance", FID, "hold") as Dictionary
		var api_bat: Dictionary = _battle_for_fid()
		_info_line("direct set_land_battle_stance r=%s stance=%s" % [str(api_r), str(api_bat.get("att_stance", ""))])
		if str(api_bat.get("att_stance", "")) == "hold":
			_pass("direct BattleManager Hold API sets att_stance")
			# Reset so the card button must do the same work.
			_inject_open_battle(0)
		else:
			_fail("direct Hold API did not set att_stance (r=%s)" % str(api_r))
	_show_selected_card()
	await _flush_frames()
	var hold_btn: Button = _find_card_btn("BtnHoldStance", "Hold")
	var press_btn: Button = _find_card_btn("BtnPressStance", "Press")
	if hold_btn == null:
		_fail("Hold missing on fighting card")
		return
	if hold_btn.text.find("●") >= 0:
		_fail("Hold already marked before press")
		return
	_log_button_rect("Hold", hold_btn)
	_log_button_rect("Press", press_btn)
	hold_btn.pressed.emit()
	await _flush_frames()
	var bat: Dictionary = _battle_for_fid()
	if str(bat.get("att_stance", "")) != "hold":
		_fail("Hold did not set att_stance=hold (got %s)" % str(bat.get("att_stance", "")))
		return
	var hold_after: Button = _find_card_btn("BtnHoldStance", "Hold")
	if hold_after == null or hold_after.text != "Hold ●":
		_fail("card Hold button want 'Hold ●' got %s" % (hold_after.text if hold_after != null else "missing"))
		return
	var press_after: Button = _find_card_btn("BtnPressStance", "Press")
	if press_after != null and press_after.text == "Press ●":
		_fail("Press still marked after Hold")
		return
	var txt := _card_text()
	if txt.find("Hold ●") < 0:
		_fail("card text missing Hold ●")
		return
	_info_line("after Hold card=%s" % txt)
	_pass("Hold: att_stance=hold and card shows Hold ●")


func _test_withdraw_loop() -> void:
	_fm("clear_march", FID)
	_inject_open_battle(0)
	_show_selected_card()
	await _flush_frames()
	var wd_btn: Button = _find_card_btn("BtnWithdraw", "Withdraw")
	if wd_btn == null:
		_fail("Withdraw missing on fighting card")
		return
	_log_button_rect("Withdraw", wd_btn)
	var before_txt := _card_text()
	_info_line("before Withdraw card=%s" % before_txt)
	wd_btn.pressed.emit()
	await _flush_frames()
	var wr_bat: Dictionary = _battle_for_fid()
	var pending := bool(wr_bat.get("withdraw_pending", false))
	var still_in := not wr_bat.is_empty()
	if not pending and still_in:
		_fail("Withdraw neither pending nor resolved")
		return
	if not pending and not still_in:
		# Instant resolve (days_elapsed>=1 path). Card must drop Withdraw + Fight.
		var gone: Button = _find_card_btn("BtnWithdraw", "Withdraw")
		if gone != null:
			_fail("resolved Withdraw left the Withdraw button")
			return
		_pass("Withdraw: fight resolved, Withdraw gone")
		return
	var after_txt := _card_text()
	_info_line("after Withdraw card=%s pending=%s" % [after_txt, str(pending)])
	var wd_after: Button = _find_card_btn("BtnWithdraw", "Withdraw")
	var marked := wd_after != null and wd_after.text.find("●") >= 0
	var body_wd := after_txt.findn("Withdrawing") >= 0
	if not marked and not body_wd:
		_fail("same-day Withdraw left no visible card state (want Withdraw ● or Withdrawing)")
		return
	if after_txt == before_txt:
		_fail("Withdraw left card text unchanged")
		return
	_pass("Withdraw: pending bounce + visible card state")


func _cleanup() -> void:
	_fm("clear_march", FID)
	_clear_injected_battle()
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID)
		_lm.formations.erase(FID_DEF)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
