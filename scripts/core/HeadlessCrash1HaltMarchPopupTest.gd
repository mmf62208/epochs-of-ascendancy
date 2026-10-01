extends SceneTree

## CRASH-1 halt-march popup + same-dest re-issue guard.
## Opens the unit card on a marching unit, fires Halt pressed, waits frames,
## asserts no crash / no "freed while signal", one live UnitDetailPopup, and
## the march is cleared. Also: re-issuing the same dest is a no-op.
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
const DESIGN := "infantry_1936"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const FLUSH_FRAMES := 8

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mr: Node = null
var _ui: CanvasLayer = null
var _mv: Script = null


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
	_pass("popup detach+queue_free; same-dest no-op needles")


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
	root.add_child(_mr)
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


func _find_halt_btn() -> Button:
	if _ui == null:
		return null
	var pop: Node = _ui.get_node_or_null("UnitDetailPopup")
	if pop == null:
		return null
	var named: Button = pop.find_child("BtnHaltMarch", true, false) as Button
	if named != null:
		return named
	for n in pop.find_children("*", "Button", true, false):
		if n is Button and str((n as Button).text) == "Halt march":
			return n as Button
	return null


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


func _cleanup() -> void:
	_fm("clear_march", FID)
	if _lm != null and "formations" in _lm and _lm.formations is Dictionary:
		_lm.formations.erase(FID)
	if _mr != null and is_instance_valid(_mr):
		_mr.queue_free()
		_mr = null
