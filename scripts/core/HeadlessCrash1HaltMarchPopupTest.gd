extends SceneTree

## CRASH-1 halt-march popup + same-dest re-issue + FIX #1 release swallow.
## Opens the unit card, fires Halt / Press / Hold / Withdraw / Assign on
## press, rebuilds, then releases at the same screen pos. Asserts no
## inspector, no camera move, selection unchanged. Also: Halt only while
## marching (refresh on start / arrival / re-target).
## Does not load WorldMap.tscn / 3520 polygons.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCrash1HaltMarchPopupTest.gd
##   tools/eoa_crash1_halt_march_guard.sh

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const LEV := 710418
const BERLIN := 710300
const GER_TAG := "GER"
const FID := "crash1_ger_halt"
const FID_DECOY := "crash1_ger_decoy"
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const FLUSH_FRAMES := 8
const LEADER_ID := "crash1_ger_leader"

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _bm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _mv: Script = null
var _cam: Camera2D = null
var _info: Panel = null


func _init() -> void:
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessCrash1HaltMarchPopupTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCrash1HaltMarchPopupTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCrash1HaltMarchPopupTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCrash1HaltMarchPopupTest: ", msg)


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
	_mv = load("res://scripts/formations/FormationMovement.gd") as Script
	if _lm == null or _mm == null:
		_fail("autoloads missing")
		return
	if _mv == null:
		_fail("FormationMovement.gd missing")
		return
	if _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", GER_TAG)
	if not _setup_nuts3_fixture():
		return
	if not _setup_formation():
		return
	if not _setup_map_renderer():
		return
	await _test_halt_pressed_no_free_during_signal()
	_test_same_dest_reissue_is_noop()
	_test_retarget_other_province()
	await _test_card_refresh_on_march_start_end()
	await _test_five_button_release_does_not_click_through()
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
	if "old.free()" in show_pop or "\t\told.free()" in show_pop:
		_fail("_show_unit_detail_popup must not free() the live card")
		return
	if "remove_child(old)" not in show_pop or "queue_free()" not in show_pop:
		_fail("_show_unit_detail_popup must detach + queue_free")
		return
	if "UnitDetailPopup_dying" not in show_pop:
		_fail("dying popup must be renamed before the new card is added")
		return
	var move_fn := _slice_func(ren, "_try_move_selected_unit_to_province")
	if "_selected_unit_already_marching_to" not in move_fn:
		_fail("_try_move_selected_unit_to_province must no-op same dest")
		return
	if "_selected_unit_same_march_dest_click" not in ren:
		_fail("_selected_unit_same_march_dest_click missing")
		return
	if "_selected_unit_same_march_dest_click(world_pos)" not in ren:
		_fail("still-click path must consume same-dest re-issue before the star inspector")
		return
	if "_arm_unit_card_press_consume()" not in show_pop:
		_fail("unit-card buttons must arm the press-consume latch")
		return
	if show_pop.count("_arm_unit_card_press_consume()") < 5:
		_fail("Halt/Press/Hold/Withdraw/Assign must each arm the latch")
		return
	if "BtnPressStance" not in show_pop or "BtnHoldStance" not in show_pop:
		_fail("Press/Hold buttons must be named for the guard")
		return
	if "BtnWithdraw" not in show_pop or "BtnAssignLeader" not in show_pop:
		_fail("Withdraw/Assign buttons must be named for the guard")
		return
	if "ACTION_MODE_BUTTON_PRESS" not in show_pop:
		_fail("card command buttons must fire on press")
		return
	var input_fn := _slice_func(ren, "_input")
	var unh_fn := _slice_func(ren, "_unhandled_input")
	var skip_fn := _slice_func(ren, "_left_release_must_skip_pick")
	var chip_fn := _slice_func(ren, "_try_open_land_chip_from_input")
	if "_consume_unit_card_press_release_if_armed()" not in input_fn:
		_fail("_input must swallow the matching card-button release")
		return
	if "_consume_unit_card_press_release_if_armed()" not in unh_fn:
		_fail("_unhandled_input must swallow the matching card-button release")
		return
	if "_unit_card_consumed_press" not in skip_fn:
		_fail("_left_release_must_skip_pick must honor the card-press latch")
		return
	if "_unit_card_consumed_press" not in chip_fn:
		_fail("land-chip still-click must honor the card-press latch")
		return
	var move_full := _slice_func(ren, "_try_move_selected_unit_to_province")
	var hop_fn := _slice_func(ren, "_on_march_hop_ui")
	if "_refresh_open_unit_card_for_selected()" not in move_full:
		_fail("march start/re-target must refresh the open unit card")
		return
	if "_refresh_open_unit_card_for_selected()" not in hop_fn:
		_fail("march hop/arrival must refresh the open unit card")
		return
	_pass("popup detach+queue_free; same-dest no-op; release-latch; card-refresh needles")


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
	# Runtime load() + instance.call — do not name FormationMovement at parse
	# time in a -s harness (SupplyManager is not visible then). Script.call
	# on the GDScript resource misses statics in 4.7.1.
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


func _setup_formation() -> bool:
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
	f.set("name", "GER CRASH-1 Div")
	if "formations" in _lm:
		_lm.formations[FID] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)
	_pass("seeded GER formation at Bonn")
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
	_pass("MapRenderer + UI canvas")
	return true


func _formation() -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", FID)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(FID)
	return null


func _count_live_unit_popups() -> int:
	if _ui == null:
		return 0
	var n := 0
	for c in _ui.get_children():
		if c == null or not is_instance_valid(c):
			continue
		if c.is_queued_for_deletion():
			continue
		var nm := str(c.name)
		if nm == "UnitDetailPopup":
			n += 1
		elif nm.begins_with("UnitDetailPopup") and not nm.ends_with("_dying"):
			n += 1
	return n


func _count_named(parent: Node, prefix: String) -> int:
	if parent == null:
		return 0
	var n := 0
	for c in parent.get_children():
		if str(c.name).begins_with(prefix):
			n += 1
	return n


func _find_card_btn(node_name: String, text_prefix: String) -> Button:
	if _ui == null:
		return null
	var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
	if pop == null:
		return null
	var named: Button = pop.find_child(node_name, true, false) as Button
	if named != null:
		return named
	for n in pop.find_children("*", "Button", true, false):
		if n is Button and str((n as Button).text).begins_with(text_prefix):
			return n as Button
	return null


func _find_halt_btn() -> Button:
	return _find_card_btn("BtnHaltMarch", "Halt march")


func _flush_frames() -> void:
	var i := 0
	while i < FLUSH_FRAMES:
		await process_frame
		i += 1


func _test_halt_pressed_no_free_during_signal() -> void:
	var fo: Object = _formation()
	if fo == null:
		_fail("formation missing for halt")
		return
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	var marched: Dictionary = _fm("enqueue_own_land_march", FID, KOELN, GER_TAG)
	if not bool(marched.get("ok", false)):
		_fail("enqueue Bonn→Köln failed: %s" % str(marched.get("reason", marched)))
		return
	if not bool(_fm("has_march", FID)):
		_fail("has_march false after enqueue")
		return
	_mr.call("_show_unit_detail_popup", fo)
	if _count_live_unit_popups() != 1:
		_fail("expected 1 unit popup before Halt, got %d" % _count_live_unit_popups())
		return
	var halt_btn: Button = _find_halt_btn()
	if halt_btn == null:
		_fail("Halt march button missing on marching card")
		return
	halt_btn.pressed.emit()
	await _flush_frames()
	if bool(_fm("has_march", FID)):
		_fail("unit still marching after Halt")
		return
	if _count_live_unit_popups() != 1:
		_fail("expected exactly 1 live unit popup after Halt, got %d" % _count_live_unit_popups())
		return
	if _ui.get_node_or_null("UnitDetailPopup") == null:
		_fail("live UnitDetailPopup missing after Halt rebuild")
		return
	if _ui.get_node_or_null("UnitDetailPopup_dying") != null:
		_fail("dying popup still in the UI tree after flush")
		return
	if _find_halt_btn() != null:
		_fail("Halt button still present after march cleared")
		return
	_pass("Halt pressed: no free-during-signal, one live card, march cleared")


func _koeln_province() -> Object:
	if _mm != null and _mm.has_method("get_province"):
		return _mm.call("get_province", KOELN)
	return null


func _lev_province() -> Object:
	if _mm != null and _mm.has_method("get_province"):
		return _mm.call("get_province", LEV)
	return null


func _test_same_dest_reissue_is_noop() -> void:
	_fm("clear_march", FID)
	var fo: Object = _formation()
	if fo != null:
		fo.set("stationed_province_id", BONN)
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	var dest_p: Object = _koeln_province()
	if dest_p == null:
		_fail("Köln province missing")
		return
	var first: bool = bool(_mr.call("_try_move_selected_unit_to_province", dest_p))
	if not first or not bool(_fm("has_march", FID)):
		_fail("first march to Köln failed")
		return
	var before: Dictionary = _fm("get_march", FID)
	var lines_before := _count_named(_mr, "MarchPathLine")
	var again: bool = bool(_mr.call("_try_move_selected_unit_to_province", dest_p))
	if not again:
		_fail("same-dest re-issue must stay handled")
		return
	if not bool(_mr.call("_selected_unit_already_marching_to", KOELN)):
		_fail("_selected_unit_already_marching_to Köln is false")
		return
	if bool(_mr.call("_selected_unit_already_marching_to", LEV)):
		_fail("_selected_unit_already_marching_to Leverkusen must be false")
		return
	if str(_mr.selected_formation_id) != FID:
		_fail("selection dropped on same-dest re-issue")
		return
	var after: Dictionary = _fm("get_march", FID)
	if int(after.get("dest_id", -1)) != KOELN:
		_fail("dest changed on same-dest re-issue")
		return
	if int(after.get("hop_index", -1)) != int(before.get("hop_index", -1)):
		_fail("hop_index reset on same-dest re-issue")
		return
	var lines_after := _count_named(_mr, "MarchPathLine")
	if lines_after != lines_before:
		_fail("MarchPathLine duplicated on same-dest re-issue (%d → %d)" % [lines_before, lines_after])
		return
	_pass("same-dest re-issue is no-op (selection/order/line kept)")


func _test_retarget_other_province() -> void:
	var dest_p: Object = _lev_province()
	if dest_p == null:
		_fail("Leverkusen province missing")
		return
	if not bool(_mr.call("_try_move_selected_unit_to_province", dest_p)):
		_fail("re-target to Leverkusen failed")
		return
	var after: Dictionary = _fm("get_march", FID)
	if int(after.get("dest_id", -1)) != LEV:
		_fail("re-target dest want %d got %s" % [LEV, str(after.get("dest_id"))])
		return
	if str(_mr.selected_formation_id) != FID:
		_fail("selection dropped on re-target")
		return
	_pass("different province still re-targets the march")


func _lmb(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	return ev


func _button_screen_pos(btn: Button) -> Vector2:
	if btn == null:
		return Vector2(97, 731)
	var r: Rect2 = btn.get_global_rect()
	if r.size.x > 1.0 and r.size.y > 1.0:
		return r.position + r.size * 0.5
	return btn.position + Vector2(24, 10)


func _camera_pos() -> Vector2:
	if _cam != null and is_instance_valid(_cam):
		return _cam.global_position
	return Vector2.ZERO


func _inspector_visible() -> bool:
	if _info != null and is_instance_valid(_info):
		return _info.visible
	return false


func _seed_leader() -> void:
	if _lm == null or not ("leaders" in _lm):
		return
	var L: Object = _new_obj("res://scripts/leaders/Leader.gd")
	if L == null:
		return
	L.set("leader_id", LEADER_ID)
	L.set("name", "Test General")
	L.set("country_tag", GER_TAG)
	L.set("assigned_army_id", "")
	L.set("is_injured", false)
	L.set("is_deceased", false)
	L.set("is_retired", false)
	L.set("is_captured", false)
	_lm.leaders[LEADER_ID] = L


func _seed_decoy_formation() -> Object:
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		return null
	f.set("formation_id", FID_DECOY)
	f.set("country_tag", GER_TAG)
	f.set("formation_type", "division")
	f.set("design_id", DESIGN)
	f.set("stationed_province_id", LEV)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("name", "Division 0")
	if "formations" in _lm:
		_lm.formations[FID_DECOY] = f
	return f


func _place_decoy_chip_at_screen(screen: Vector2) -> void:
	if _mr == null:
		return
	var decoy: Object = _formation_by_id(FID_DECOY)
	if decoy == null:
		decoy = _seed_decoy_formation()
	if decoy == null:
		return
	var world: Vector2 = _mr.call("_screen_to_world", screen) as Vector2
	var host: Node2D = null
	if "province_nodes" in _mr and _mr.province_nodes.has(LEV):
		host = _mr.province_nodes[LEV] as Node2D
	if host == null:
		return
	var old: Node = host.get_node_or_null("DemoUnitIcon_%d" % LEV)
	if old != null:
		old.free()
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_%d" % LEV
	icon.visible = true
	host.add_child(icon)
	icon.global_position = world
	icon.set_meta("formation", decoy)
	icon.set_meta("formation_id", FID_DECOY)
	if "show_unit_counters" in _mr:
		_mr.show_unit_counters = true
	if "_demo_unit_icon_pids" in _mr:
		var pids: Array = _mr._demo_unit_icon_pids
		if not pids.has(LEV):
			pids.append(LEV)
			_mr._demo_unit_icon_pids = pids


func _formation_by_id(fid: String) -> Object:
	if _lm != null and _lm.has_method("get_formation"):
		return _lm.call("get_formation", fid)
	if _lm != null and "formations" in _lm:
		return _lm.formations.get(fid)
	return null


func _inject_open_battle() -> void:
	_bm = _autoload("BattleManager")
	if _bm == null or not ("_open_land_battles" in _bm):
		return
	var rows: Array = _bm._open_land_battles
	for raw in rows:
		if raw is Dictionary and str((raw as Dictionary).get("att_fid", "")) == FID:
			return
	rows.append({
		"id": "lb_crash1",
		"from_id": BONN,
		"to_id": BERLIN,
		"att_tag": GER_TAG,
		"def_tag": "FRA",
		"att_fid": FID,
		"def_fid": "crash1_fra_def",
		"att_fids": [FID],
		"def_fids": ["crash1_fra_def"],
		"att_n": 1,
		"def_n": 1,
		"att_org": 1.0,
		"def_org": 1.0,
		"att_stance": "press",
		"days_elapsed": 0,
		"next_hook": "Unpause to fight · Press or Hold",
	})
	_bm._open_land_battles = rows


func _clear_injected_battle() -> void:
	if _bm == null or not ("_open_land_battles" in _bm):
		return
	var kept: Array = []
	for raw in _bm._open_land_battles:
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == "lb_crash1":
			continue
		kept.append(raw)
	_bm._open_land_battles = kept


func _show_selected_card() -> void:
	var fo: Object = _formation()
	if fo == null or _mr == null:
		return
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	_mr.call("_show_unit_detail_popup", fo)


func _assert_no_click_through(label: String, cam_before: Vector2, sel_before: String, pid_before: int, insp_before: bool) -> void:
	if bool(_mr.get("_unit_card_consumed_press")):
		_fail("%s latch still armed after release" % label)
	if str(_mr.selected_formation_id) != sel_before:
		_fail("%s release changed selection %s → %s" % [label, sel_before, str(_mr.selected_formation_id)])
		return
	if str(_mr.selected_formation_id) == FID_DECOY:
		_fail("%s release selected the decoy unit" % label)
		return
	if _inspector_visible() and not insp_before:
		_fail("%s release opened the inspector" % label)
		return
	if int(_mr.selected_province_id) != pid_before:
		_fail("%s release changed selected province %d → %d" % [label, pid_before, int(_mr.selected_province_id)])
		return
	if _camera_pos().distance_to(cam_before) > 0.5:
		_fail("%s release moved the camera" % label)
		return
	_pass("%s press+release: no inspector, no camera move, selection kept" % label)


func _press_button_then_release(btn: Button, label: String) -> void:
	if btn == null:
		_fail("%s button missing on card" % label)
		return
	var pos: Vector2 = _button_screen_pos(btn)
	_place_decoy_chip_at_screen(pos)
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	if "selected_province_id" in _mr:
		_mr.selected_province_id = -1
	if _info != null:
		_info.visible = false
	var cam_before: Vector2 = _camera_pos()
	var sel_before := str(_mr.selected_formation_id)
	var pid_before := int(_mr.selected_province_id)
	var insp_before := _inspector_visible()
	_mr.call("_input", _lmb(true, pos))
	if is_instance_valid(btn):
		btn.pressed.emit()
	await _flush_frames()
	if not bool(_mr.get("_unit_card_consumed_press")) and not bool(_mr.get("_unit_card_release_eaten")):
		_fail("%s did not arm the card-press latch" % label)
		return
	_mr.call("_input", _lmb(false, pos))
	_mr.call("_unhandled_input", _lmb(false, pos))
	await _flush_frames()
	_assert_no_click_through(label, cam_before, sel_before, pid_before, insp_before)


func _test_card_refresh_on_march_start_end() -> void:
	_fm("clear_march", FID)
	var fo: Object = _formation()
	if fo != null:
		fo.set("stationed_province_id", BONN)
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	_mr.call("_show_unit_detail_popup", fo)
	if _find_halt_btn() != null:
		_fail("Halt must be absent before a march starts")
		return
	var dest_p: Object = _koeln_province()
	if dest_p == null:
		_fail("Köln missing for card-refresh")
		return
	if not bool(_mr.call("_try_move_selected_unit_to_province", dest_p)):
		_fail("march start for card-refresh failed")
		return
	if _find_halt_btn() == null:
		_fail("open card must show Halt after march start (no re-select)")
		return
	var lev_p: Object = _lev_province()
	if lev_p != null:
		if not bool(_mr.call("_try_move_selected_unit_to_province", lev_p)):
			_fail("re-target for card-refresh failed")
			return
		if _find_halt_btn() == null:
			_fail("open card must keep Halt after re-target")
			return
	_fm("clear_march", FID)
	_mr.call("_on_march_hop_ui", LEV, true)
	await _flush_frames()
	if _find_halt_btn() != null:
		_fail("open card must drop Halt after arrival")
		return
	_pass("open card refreshes Halt on start / re-target / arrival")


func _test_five_button_release_does_not_click_through() -> void:
	_seed_leader()
	_seed_decoy_formation()
	_inject_open_battle()
	_fm("enqueue_own_land_march", FID, KOELN, GER_TAG)
	if "selected_formation_id" in _mr:
		_mr.selected_formation_id = FID
	_show_selected_card()
	await _press_button_then_release(_find_halt_btn(), "Halt")
	_fm("enqueue_own_land_march", FID, KOELN, GER_TAG)
	_inject_open_battle()
	_show_selected_card()
	await _press_button_then_release(_find_card_btn("BtnPressStance", "Press"), "Press")
	_inject_open_battle()
	_show_selected_card()
	await _press_button_then_release(_find_card_btn("BtnHoldStance", "Hold"), "Hold")
	_inject_open_battle()
	_show_selected_card()
	await _press_button_then_release(_find_card_btn("BtnWithdraw", "Withdraw"), "Withdraw")
	_seed_leader()
	if _formation() != null:
		_formation().set("leader_id", "")
	_show_selected_card()
	await _press_button_then_release(_find_card_btn("BtnAssignLeader", "Assign"), "Assign")
	_clear_injected_battle()
	_fm("clear_march", FID)


func _cleanup() -> void:
	_fm("clear_march", FID)
	_clear_injected_battle()
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID)
		_lm.formations.erase(FID_DECOY)
	if _lm != null and "leaders" in _lm and _lm.leaders is Dictionary:
		_lm.leaders.erase(LEADER_ID)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
