extends SceneTree

## SAVE-LIST-1. Load list stays truthful after a same-second overwrite, autosave
## rows name their slot, and refresh on a panel that is not in the tree does not
## error (rebuild waits until re-enter).
##
##   XDG_DATA_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessSaveList1Test.gd

const DATE_A := "1936-07-19"
const DATE_A_LABEL := "19 Jul 1936"
const DATE_B := "1936-08-20"
const DATE_B_LABEL := "20 Aug 1936"
const AUTO_DATE := "1936-02-03"
const AUTO_DATE_LABEL := "3 Feb 1936"
const MARKER := "SAVE_LIST_1_MARKER"

var _failures: int = 0


func _init() -> void:
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	call_deferred("_start")


func _flush_log() -> void:
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")


func _progress(msg: String) -> void:
	print("  HeadlessSaveList1Test: ", msg)
	_flush_log()


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessSaveList1Test: ", msg)
	_flush_log()


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessSaveList1Test: ", msg)
	_flush_log()


func _emit_result_and_die(ok: bool) -> void:
	print("HeadlessSaveList1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessSaveList1Test: RESULT=", "PASS" if ok else "FAIL")
	_flush_log()
	quit(0 if ok else 1)


func _start() -> void:
	await _run()
	_emit_result_and_die(_failures == 0)


func _sl() -> Node:
	return root.get_node_or_null("SaveLoadManager")


func _run() -> void:
	var sl := _sl()
	if sl == null:
		_fail("SaveLoadManager missing")
		return
	if sl.has_method("_ensure_save_dir"):
		sl.call("_ensure_save_dir")
	_test_case1_same_second_overwrite(sl)
	_test_case2_autosave_slot_token(sl)
	await _test_case3_refresh_not_in_tree(sl)


func _write_probe(sl: Node, slot: String, unix: int, game_date: String, locked: bool = false) -> String:
	if sl.has_method("_ensure_save_dir"):
		sl.call("_ensure_save_dir")
	var data := {
		"save_version": 2,
		"metadata": {
			"timestamp_unix": unix,
			"timestamp": "1936-01-01T00:00:00",
			"game_date": game_date,
			"last_played": "1936-01-01T00:00:00",
			"save_kind": str(sl.call("slot_kind", slot)),
			"session_locked": locked,
			"player_tag": "GER",
		},
		"land_war": {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}},
	}
	var path := str(sl.call("get_save_path", slot))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("probe write failed for %s" % slot)
		return ""
	f.store_string(JSON.stringify(data))
	f.close()
	return path


func _mtime(path: String) -> int:
	if path.is_empty() or not FileAccess.file_exists(path):
		return -1
	return int(FileAccess.get_modified_time(path))


func _make_ocp(node_name: String = "OrderCommandPanel_save_list_1") -> Node:
	var packed: PackedScene = load("res://scenes/ui/OrderCommandPanel.tscn") as PackedScene
	if packed == null:
		_fail("OrderCommandPanel.tscn missing")
		return null
	var ocp: Node = packed.instantiate()
	ocp.name = node_name
	ocp.set_meta("eoa_skip_first_refresh", true)
	return ocp


func _clear_saves_cache(ocp: Node) -> void:
	if ocp == null:
		return
	ocp.set("_saves_list_cache_valid", false)
	ocp.set("_saves_fp_last", "")
	ocp.set("_shared_saves_valid", false)
	ocp.set("_shared_saves_fp", "")
	ocp.set("_saves_rebuild_from_all", false)


func _disconnect_save_list(ocp: Node, sl: Node) -> void:
	if ocp == null or sl == null:
		return
	if not sl.has_signal("save_list_changed"):
		return
	var cb := Callable(ocp, "_rebuild_saves_section")
	if sl.save_list_changed.is_connected(cb):
		sl.save_list_changed.disconnect(cb)


func _rebuild_saves(ocp: Node) -> void:
	if ocp != null and ocp.has_method("_rebuild_saves_section"):
		ocp.call("_rebuild_saves_section")


func _rebuild_saves_via_fingerprint(ocp: Node) -> void:
	if ocp == null:
		return
	if ocp.has_method("_saves_sync_fingerprint"):
		ocp.call("_saves_sync_fingerprint")
	ocp.set("_saves_rebuild_from_all", true)
	_rebuild_saves(ocp)
	ocp.set("_saves_rebuild_from_all", false)


func _row_label(ocp: Node, slot: String) -> Label:
	if ocp == null:
		return null
	var n: Node = ocp.find_child("SlotRowLabel_%s" % slot, true, false)
	if n is Label:
		return n as Label
	return null


func _row_text(ocp: Node, slot: String) -> String:
	var lbl := _row_label(ocp, slot)
	if lbl == null:
		return ""
	return str(lbl.text)


func _test_case1_same_second_overwrite(sl: Node) -> void:
	_progress("case 1: same-second quicksave overwrite")
	var ocp := _make_ocp("OrderCommandPanel_case1")
	if ocp == null:
		return
	root.add_child(ocp)
	_clear_saves_cache(ocp)
	var path := ""
	var mt_a := -1
	var mt_b := -1
	var landed := false
	var attempts: int = 0
	while attempts < 8:
		attempts += 1
		path = _write_probe(sl, "quicksave", 100, DATE_A, false)
		if path.is_empty():
			ocp.queue_free()
			return
		_clear_saves_cache(ocp)
		_rebuild_saves(ocp)
		var first := _row_text(ocp, "quicksave")
		if first.find(DATE_A_LABEL) < 0:
			_fail("case 1: quicksave row missing %s before overwrite: %s" % [DATE_A_LABEL, first])
			ocp.queue_free()
			return
		mt_a = _mtime(path)
		_disconnect_save_list(ocp, sl)
		_write_probe(sl, "quicksave", 200, DATE_B, false)
		mt_b = _mtime(path)
		if mt_a == mt_b and mt_a >= 0:
			landed = true
			break
		_progress("case 1: mtime moved %d -> %d, retry same-second overwrite" % [mt_a, mt_b])
	if not landed:
		_fail("case 1: could not land a same-second overwrite (mtime %d -> %d)" % [mt_a, mt_b])
		ocp.queue_free()
		return
	if sl.has_method("_notify_save_list_refresh"):
		sl.call("_notify_save_list_refresh")
	_disconnect_save_list(ocp, sl)
	_rebuild_saves_via_fingerprint(ocp)
	var after := _row_text(ocp, "quicksave")
	if after.find(DATE_B_LABEL) < 0:
		_fail("case 1: quicksave row still shows %s after same-second overwrite: %s" % [DATE_A_LABEL if after.find(DATE_A_LABEL) >= 0 else "stale", after])
		ocp.queue_free()
		return
	if after.find(DATE_A_LABEL) >= 0:
		_fail("case 1: quicksave row kept %s after overwrite: %s" % [DATE_A_LABEL, after])
		ocp.queue_free()
		return
	ocp.queue_free()
	_pass("case 1: same-second overwrite shows %s" % DATE_B_LABEL)


func _has_slot_token(text: String, title: String, slot: String) -> bool:
	var raw := str(text)
	if raw.find(title) < 0:
		return false
	if raw.find(slot) >= 0:
		return true
	var token := slot
	if slot.begins_with("autosave_"):
		token = slot.substr("autosave_".length())
	if token.is_empty():
		return false
	# Title prefix "Session 1" / "Autosave 2" (example in the brief).
	if raw.find("%s %s" % [title, token]) >= 0:
		return true
	return false


func _test_case2_autosave_slot_token(sl: Node) -> void:
	_progress("case 2: autosave rows keep Session/Autosave and add a slot token")
	_write_probe(sl, "autosave_1", 300, AUTO_DATE, true)
	_write_probe(sl, "autosave_2", 300, AUTO_DATE, false)
	var row_s: Dictionary = sl.call("_format_slot_ui_row", "autosave_1", true, {
		"game_date": AUTO_DATE,
		"save_kind": "auto",
		"timestamp_unix": 300,
		"timestamp": "1936-02-03T00:00:00",
		"player_tag": "GER",
		"session_locked": true,
	})
	var row_a: Dictionary = sl.call("_format_slot_ui_row", "autosave_2", true, {
		"game_date": AUTO_DATE,
		"save_kind": "auto",
		"timestamp_unix": 300,
		"timestamp": "1936-02-03T00:00:00",
		"player_tag": "GER",
		"session_locked": false,
	})
	var lab_s := str(row_s.get("label", ""))
	var lab_a := str(row_a.get("label", ""))
	if lab_s.find("Session") < 0:
		_fail("case 2: session row missing Session title: %s" % lab_s)
		return
	if lab_a.find("Autosave") < 0:
		_fail("case 2: autosave row missing Autosave title: %s" % lab_a)
		return
	if not _has_slot_token(lab_s, "Session", "autosave_1"):
		_fail("case 2: session row missing slot token: %s" % lab_s)
		return
	if not _has_slot_token(lab_a, "Autosave", "autosave_2"):
		_fail("case 2: autosave row missing slot token: %s" % lab_a)
		return
	if lab_s == lab_a:
		_fail("case 2: session and autosave labels are identical: %s" % lab_s)
		return
	var ocp := _make_ocp("OrderCommandPanel_case2")
	if ocp == null:
		return
	root.add_child(ocp)
	_clear_saves_cache(ocp)
	_rebuild_saves(ocp)
	var ui_s := _row_text(ocp, "autosave_1")
	var ui_a := _row_text(ocp, "autosave_2")
	if ui_s.find("Session") < 0 or not _has_slot_token(ui_s, "Session", "autosave_1"):
		_fail("case 2: panel session row missing Session title + slot token: %s" % ui_s)
		ocp.queue_free()
		return
	if ui_a.find("Autosave") < 0 or not _has_slot_token(ui_a, "Autosave", "autosave_2"):
		_fail("case 2: panel autosave row missing Autosave title + slot token: %s" % ui_a)
		ocp.queue_free()
		return
	if ui_s == ui_a:
		_fail("case 2: panel autosave rows read the same: %s" % ui_s)
		ocp.queue_free()
		return
	ocp.queue_free()
	_pass("case 2: Session/Autosave titles keep prefix and add slot tokens")


func _plant_marker(ocp: Node) -> Label:
	if ocp == null:
		return null
	var host: Node = ocp.find_child("SavesSectionHost", true, false)
	if host == null:
		var body: Node = ocp.get("_body")
		host = body
	if host == null:
		return null
	var existing: Node = host.get_node_or_null(MARKER)
	if existing is Label:
		return existing as Label
	var marker := Label.new()
	marker.name = MARKER
	marker.text = MARKER
	host.add_child(marker)
	return marker


func _marker_alive(ocp: Node) -> bool:
	if ocp == null or not is_instance_valid(ocp):
		return false
	var n: Node = ocp.find_child(MARKER, true, false)
	return n is Label and is_instance_valid(n) and not n.is_queued_for_deletion()


func _test_case3_refresh_not_in_tree(sl: Node) -> void:
	_progress("case 3: refresh while not inside the tree")
	_write_probe(sl, "quicksave", 100, DATE_A, false)
	var ocp := _make_ocp("OrderCommandPanel_case3")
	if ocp == null:
		return
	root.add_child(ocp)
	_clear_saves_cache(ocp)
	_rebuild_saves(ocp)
	var marker := _plant_marker(ocp)
	if marker == null:
		_fail("case 3: could not plant rebuild marker")
		ocp.queue_free()
		return
	_disconnect_save_list(ocp, sl)
	root.remove_child(ocp)
	if ocp.is_inside_tree():
		_fail("case 3: panel still inside the tree after remove_child")
		ocp.free()
		return
	print("  HeadlessSaveList1Test: case 3: calling refresh while not in tree")
	_flush_log()
	if ocp.has_method("refresh"):
		ocp.call("refresh")
	print("  HeadlessSaveList1Test: case 3: refresh returned")
	_flush_log()
	if not is_instance_valid(ocp):
		_fail("case 3: panel died during out-of-tree refresh")
		return
	if not _marker_alive(ocp):
		_fail("case 3: refresh rebuilt while panel was not inside the tree")
		ocp.free()
		return
	root.add_child(ocp)
	if not ocp.is_inside_tree():
		_fail("case 3: panel did not re-enter the tree")
		ocp.queue_free()
		return
	await process_frame
	await process_frame
	await process_frame
	if _marker_alive(ocp):
		_fail("case 3: rebuild was not deferred until the panel re-entered the tree")
		ocp.queue_free()
		return
	ocp.queue_free()
	_pass("case 3: out-of-tree refresh is quiet; rebuild waits for re-enter")
