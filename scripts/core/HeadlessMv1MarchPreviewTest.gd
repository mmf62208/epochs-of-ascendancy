extends SceneTree

## MV-1 move ETA preview: preview_own_land_march writes nothing and must
## match enqueue_own_land_march path + calendar_days. NUTS3 Rhineland fixture
## (Köln 710417 / Bonn 710416 / Leverkusen 710418 + RX-1 Neuss–Mettmann).
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessMv1MarchPreviewTest.gd

const ADJ_PATH := "res://data/provinces_pilot_europe_nuts3/province_adjacency.json"
const BONN := 710416
const KOELN := 710417
const LEV := 710418
const NEUSS := 710413
const METTMANN := 710412
const ESSEN := 710403
const BERLIN := 710300
const FRA_FRONT := 710739
const SEA_ID := 950001
const GER_TAG := "GER"
const FRA_TAG := "FRA"
const FID := "mv1_ger_preview"
const DESIGN := "infantry_1936"

var _failures := 0
var _lm: Node = null
var _mm: Node = null
var _mv: Script = null


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessMv1MarchPreviewTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessMv1MarchPreviewTest: ", msg)


func _autoload(name: String) -> Node:
	return root.get_node_or_null(name)


func _new_obj(path: String) -> Object:
	var scr: Script = load(path) as Script
	if scr == null:
		return null
	return scr.new()


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessMv1MarchPreviewTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessMv1MarchPreviewTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


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
	_seed_ix1_spine_roads()
	Rx1RhineCrossing.reset_to_1936()
	_make_form(FID, GER_TAG, DESIGN, BONN)
	_test_preview_writes_nothing()
	_test_preview_equals_commit_pairs()
	_test_reasons()
	_test_spine_faster_than_offroad()
	_cleanup()


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


func _test_source_needles() -> void:
	var move := _read("res://scripts/formations/FormationMovement.gd")
	var ren := _read("res://scripts/map/MapRenderer.gd")
	if "func preview_own_land_march" not in move:
		_fail("preview_own_land_march missing")
		return
	var prev := _slice_func(move, "preview_own_land_march")
	if "_orders[" in prev or "_orders." in prev:
		_fail("preview_own_land_march writes _orders")
		return
	var enq := _slice_func(move, "enqueue_own_land_march")
	if "preview_own_land_march" not in enq or "_orders[fid]" not in enq:
		_fail("enqueue_own_land_march must call preview then store")
		return
	if "MarchPreviewLine" not in ren or "_refresh_march_preview_for_hover" not in ren:
		_fail("MapRenderer missing MarchPreviewLine / hover-change hook")
		return
	var spatial := _slice_func(ren, "_update_spatial_hover")
	if "_unit_detail_popup_is_visible() or _is_mouse_over_blocking_ui()" in spatial:
		_fail("_update_spatial_hover must not early-return on card-visible OR blocking-UI")
		return
	if "_refresh_march_preview_for_hover" not in spatial:
		_fail("_update_spatial_hover must still refresh march preview with the card up")
		return
	if "_clear_left_slop_after_still_click" not in ren:
		_fail("still-click slop clear missing")
		return
	var hover_fn := _slice_func(ren, "_refresh_hover_tooltip")
	if "preview_own_land_march" in hover_fn or "_refresh_march_preview_for_hover" in hover_fn:
		_fail("_refresh_hover_tooltip must not BFS / preview (per-frame path)")
		return
	var preview_line := _slice_func(ren, "_ensure_march_preview_line")
	if "antialiased = true" in preview_line or ", true)" in preview_line:
		_fail("MarchPreviewLine must not be antialiased")
		return
	var open_unit := _slice_func(ren, "_try_open_unit_at_world")
	if "player_only" not in open_unit or "_formation_is_player_tag" not in open_unit:
		_fail("_try_open_unit_at_world must gate player_only + _formation_is_player_tag")
		return
	if "_select_map_unit(fo)" in open_unit and "if not _formation_is_player_tag(fo):" not in open_unit:
		_fail("_try_open_unit_at_world must refuse non-player before _select_map_unit")
		return
	if "_mv1_selected_own_land_ready_to_commit" not in ren:
		_fail("preview==commit skip helper missing")
		return
	if "var mv1_commit: bool" not in ren:
		_fail("mv1_commit must be computed once after the land-counter block")
		return
	if "if not mv1_commit and not event.shift_pressed" not in ren:
		_fail("capital-star branch must skip when mv1_commit")
		return
	var spill := _slice_func(ren, "_nearest_player_land_formation_at_world")
	if "CHROME_SPILL_WORLD" not in spill or "340.0" not in spill:
		_fail("CHROME_SPILL_WORLD fallback must stay frozen at 340")
		return
	_pass("preview API is pure; enqueue uses it; hover BFS is change-only")


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
		{"id": NEUSS, "tag": GER_TAG, "name": "Neuss"},
		{"id": METTMANN, "tag": GER_TAG, "name": "Mettmann"},
		{"id": ESSEN, "tag": GER_TAG, "name": "Essen"},
		{"id": BERLIN, "tag": GER_TAG, "name": "Berlin"},
		{"id": FRA_FRONT, "tag": FRA_TAG, "name": "Bas-Rhin"},
		{"id": SEA_ID, "tag": GER_TAG, "name": "North Sea", "sea": true},
	]
	var provs: Dictionary = {}
	var countries: Dictionary = {
		GER_TAG: {"tag": GER_TAG, "name": "Germany"},
		FRA_TAG: {"tag": FRA_TAG, "name": "France"},
	}
	for row in rows:
		var pid := int(row["id"])
		var p: Object = _new_obj("res://scripts/data/Province.gd")
		if p == null:
			_fail("Province create failed")
			return false
		var sea := bool(row.get("sea", false))
		p.set("id", pid)
		p.set("owner_tag", "" if sea else str(row["tag"]))
		p.set("controller_tag", "" if sea else str(row["tag"]))
		p.set("terrain", "sea" if sea else "plains")
		p.set("name", str(row["name"]))
		p.set("is_sea", sea)
		p.set("infrastructure", 4)
		p.set("development_level", 3)
		p.set("core_for", [str(row["tag"])])
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
	if not _edge(BONN, KOELN) or not _edge(KOELN, LEV) or not _edge(NEUSS, METTMANN):
		_fail("fixture missing Bonn–Köln / Köln–Leverkusen / Neuss–Mettmann edges")
		return false
	_pass("nuts3 fixture Bonn/Köln/Leverkusen + Rhine Neuss–Mettmann")
	return true


func _edge(a: int, b: int) -> bool:
	if _mm == null or not _mm.has_method("get_adjacent_provinces"):
		return false
	for n in _mm.call("get_adjacent_provinces", a, true):
		if int(n) == b:
			return true
	return false


func _seed_ix1_spine_roads() -> void:
	if _mm.has_method("build_road_connection"):
		_mm.call("build_road_connection", BONN, KOELN)
		_mm.call("build_road_connection", KOELN, LEV)


func _clear_ix1_spine_roads() -> void:
	if _mm.has_method("remove_road_connection"):
		_mm.call("remove_road_connection", BONN, KOELN)
		_mm.call("remove_road_connection", KOELN, LEV)


func _make_form(fid: String, tag: String, design: String, station: int) -> void:
	var f: Object = _new_obj("res://scripts/formations/Formation.gd")
	if f == null:
		_fail("Formation create failed")
		return
	f.set("formation_id", fid)
	f.set("country_tag", tag)
	f.set("formation_type", "division")
	f.set("design_id", design)
	f.set("stationed_province_id", station)
	f.set("strength", 1.0)
	f.set("organization", 1.0)
	f.set("readiness", 1.0)
	f.set("name", "%s MV-1 Div" % tag)
	if "formations" in _lm:
		_lm.formations[fid] = f
	elif _lm.has_method("register_formation"):
		_lm.call("register_formation", f)


func _station(pid: int) -> void:
	if _lm == null:
		return
	var f: Object = null
	if _lm.has_method("get_formation"):
		f = _lm.call("get_formation", FID)
	elif "formations" in _lm:
		f = _lm.formations.get(FID)
	if f != null:
		f.set("stationed_province_id", pid)


func _clear_order() -> void:
	if _mv != null:
		_mv.call("clear_march", FID)


func _paths_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	var i := 0
	while i < a.size():
		if int(a[i]) != int(b[i]):
			return false
		i += 1
	return true


func _assert_preview_commit(from_id: int, dest_id: int, label: String) -> void:
	_station(from_id)
	_clear_order()
	var preview: Dictionary = _mv.call("preview_own_land_march", FID, dest_id, GER_TAG)
	if bool(_mv.call("has_march", FID)):
		_fail("%s: preview wrote an order" % label)
		return
	var commit: Dictionary = _mv.call("enqueue_own_land_march", FID, dest_id, GER_TAG)
	if not bool(preview.get("ok", false)) or not bool(commit.get("ok", false)):
		_fail("%s: preview/commit not ok preview=%s commit=%s" % [label, str(preview), str(commit)])
		_clear_order()
		return
	var p_path: Array = preview.get("path", []) as Array
	var c_path: Array = commit.get("path", []) as Array
	if not _paths_equal(p_path, c_path):
		_fail("%s: path drift preview=%s commit=%s" % [label, str(p_path), str(c_path)])
		_clear_order()
		return
	if int(preview.get("calendar_days", -1)) != int(commit.get("calendar_days", -2)):
		_fail(
			"%s: calendar_days drift preview=%s commit=%s"
			% [label, str(preview.get("calendar_days")), str(commit.get("calendar_days"))]
		)
		_clear_order()
		return
	if int(preview.get("hops", -1)) != int(commit.get("hops", -2)):
		_fail("%s: hops drift" % label)
		_clear_order()
		return
	_pass(
		"%s preview==commit hops=%s days=%s path=%s"
		% [label, str(preview.get("hops")), str(preview.get("calendar_days")), str(p_path)]
	)
	_clear_order()


func _test_preview_writes_nothing() -> void:
	_station(BONN)
	_clear_order()
	var preview: Dictionary = _mv.call("preview_own_land_march", FID, LEV, GER_TAG)
	if not bool(preview.get("ok", false)):
		_fail("spine preview not ok: %s" % str(preview))
		return
	if bool(_mv.call("has_march", FID)):
		_fail("has_march true after preview")
		return
	var listed: Array = _mv.call("list_marches")
	if not listed.is_empty():
		_fail("list_marches not empty after preview")
		return
	_pass("preview creates no order (has_march false)")


func _test_preview_equals_commit_pairs() -> void:
	_assert_preview_commit(BONN, LEV, "ix1_spine_bonn_leverkusen")
	_assert_preview_commit(BONN, KOELN, "ix1_spine_bonn_koeln")
	_assert_preview_commit(KOELN, LEV, "ix1_spine_koeln_leverkusen")
	_assert_preview_commit(NEUSS, METTMANN, "rx1_rhine_neuss_mettmann")
	_assert_preview_commit(KOELN, ESSEN, "offroad_koeln_essen")


func _test_reasons() -> void:
	_station(BONN)
	_clear_order()
	var here: Dictionary = _mv.call("preview_own_land_march", FID, BONN, GER_TAG)
	if bool(here.get("ok", true)) or str(here.get("reason", "")) != "already here" or not bool(here.get("already_here", false)):
		_fail("already here reason: %s" % str(here))
	elif bool(_mv.call("has_march", FID)):
		_fail("already here preview wrote an order")
	else:
		_pass("reason already here")
	var enemy: Dictionary = _mv.call("preview_own_land_march", FID, FRA_FRONT, GER_TAG)
	if bool(enemy.get("ok", true)) or str(enemy.get("reason", "")) != "not your land":
		_fail("not your land (FRA): %s" % str(enemy))
	else:
		_pass("reason not your land (enemy)")
	var sea: Dictionary = _mv.call("preview_own_land_march", FID, SEA_ID, GER_TAG)
	if bool(sea.get("ok", true)) or str(sea.get("reason", "")) != "not your land":
		_fail("not your land (sea): %s" % str(sea))
	else:
		_pass("reason not your land (sea)")
	var nopath: Dictionary = _mv.call("preview_own_land_march", FID, BERLIN, GER_TAG)
	if bool(nopath.get("ok", true)) or str(nopath.get("reason", "")) != "no own-land path":
		_fail("no own-land path (Berlin): %s" % str(nopath))
	else:
		_pass("reason no own-land path")
	if bool(_mv.call("has_march", FID)):
		_fail("reason previews wrote an order")


func _test_spine_faster_than_offroad() -> void:
	_seed_ix1_spine_roads()
	_station(BONN)
	_clear_order()
	var spine: Dictionary = _mv.call("preview_own_land_march", FID, KOELN, GER_TAG)
	_station(KOELN)
	var off: Dictionary = _mv.call("preview_own_land_march", FID, ESSEN, GER_TAG)
	if not bool(spine.get("ok", false)) or not bool(off.get("ok", false)):
		_fail("spine/off-road preview not ok spine=%s off=%s" % [str(spine), str(off)])
		return
	if int(spine.get("hops", 0)) != int(off.get("hops", -1)):
		_fail("spine/off-road hop counts differ spine=%s off=%s" % [str(spine.get("hops")), str(off.get("hops"))])
		return
	var spine_eta := float(spine.get("eta_days", 99.0))
	var off_eta := float(off.get("eta_days", 0.0))
	if spine_eta >= off_eta:
		_fail("spine ETA %.3f not < off-road ETA %.3f" % [spine_eta, off_eta])
		return
	# Same 2-hop corridor with roads vs without.
	_station(BONN)
	var spine2: Dictionary = _mv.call("preview_own_land_march", FID, LEV, GER_TAG)
	_clear_ix1_spine_roads()
	var off2: Dictionary = _mv.call("preview_own_land_march", FID, LEV, GER_TAG)
	_seed_ix1_spine_roads()
	if not bool(spine2.get("ok", false)) or not bool(off2.get("ok", false)):
		_fail("2-hop spine/off preview not ok")
		return
	if int(spine2.get("hops", 0)) != int(off2.get("hops", -1)):
		_fail("2-hop hop counts differ")
		return
	if float(spine2.get("eta_days", 99.0)) >= float(off2.get("eta_days", 0.0)):
		_fail(
			"2-hop spine ETA %.3f not < same-path off-road %.3f"
			% [float(spine2.get("eta_days")), float(off2.get("eta_days"))]
		)
		return
	if bool(_mv.call("has_march", FID)):
		_fail("spine/off-road preview wrote an order")
		return
	_pass(
		"spine ETA < same-length off-road (1hop %.3f<%.3f, 2hop %.3f<%.3f)"
		% [spine_eta, off_eta, float(spine2.get("eta_days")), float(off2.get("eta_days"))]
	)


func _cleanup() -> void:
	_clear_order()
	if _lm != null and "formations" in _lm:
		_lm.formations.erase(FID)
