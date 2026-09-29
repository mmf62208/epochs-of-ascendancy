extends SceneTree

## MV-1b headless: player-tag gate on `_try_open_unit_at_world` and
## `edge_pan_blocked_by_gui` ancestry / meta (province panel + unit card).
## Does not launch the 3520 board.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessMv1bInputGateTest.gd

const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_INPUT := "res://scripts/map/MapViewInput.gd"

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessMv1bInputGateTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessMv1bInputGateTest: ", msg)


func _run_and_quit() -> void:
	_run()
	var ok := _failures == 0
	print("HeadlessMv1bInputGateTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessMv1bInputGateTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


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
	_test_edge_pan_ancestry_and_meta()


func _test_source_needles() -> void:
	var ren := _read(SRC_REN)
	var inp := _read(SRC_INPUT)
	if ren.is_empty() or inp.is_empty():
		_fail("MapRenderer / MapViewInput source missing")
		return
	var open_unit := _slice_func(ren, "_try_open_unit_at_world")
	if open_unit.is_empty():
		_fail("_try_open_unit_at_world missing")
		return
	if "player_only" not in open_unit:
		_fail("_try_open_unit_at_world must pass player_only to pick")
		return
	if "_formation_is_player_tag" not in open_unit:
		_fail("_try_open_unit_at_world must check _formation_is_player_tag")
		return
	if "_select_map_unit(fo)" not in open_unit:
		_fail("_try_open_unit_at_world still selects player air/fleet")
		return
	var select_i := open_unit.find("_select_map_unit(fo)")
	var tag_i := open_unit.find("if not _formation_is_player_tag(fo):")
	if tag_i < 0 or select_i < 0 or tag_i > select_i:
		_fail("player-tag gate must run before _select_map_unit")
		return
	if "_mv1_selected_own_land_ready_to_commit" not in ren:
		_fail("preview==commit skip helper missing from MapRenderer")
		return
	var spill := _slice_func(ren, "_nearest_player_land_formation_at_world")
	if "CHROME_SPILL_WORLD" not in spill or "340.0" not in spill:
		_fail("fallback CHROME_SPILL_WORLD must stay 340 (item 4 out of scope)")
		return
	if "func control_or_ancestor_blocks_edge_pan" not in inp:
		_fail("MapViewInput.control_or_ancestor_blocks_edge_pan missing")
		return
	var edge := _slice_func(inp, "edge_pan_blocked_by_gui")
	if "control_or_ancestor_blocks_edge_pan" not in edge:
		_fail("edge_pan_blocked_by_gui must use ancestry helper")
		return
	if "InfoPanel" not in _slice_func(inp, "control_or_ancestor_blocks_edge_pan"):
		_fail("ancestry helper must name InfoPanel")
		return
	if "UnitDetailPopup" not in _slice_func(inp, "control_or_ancestor_blocks_edge_pan"):
		_fail("ancestry helper must name UnitDetailPopup")
		return
	if "blocks_edge_pan" not in _slice_func(inp, "control_or_ancestor_blocks_edge_pan"):
		_fail("ancestry helper must honor blocks_edge_pan meta")
		return
	_pass("source needles: player-tag gate + preview skip + edge-pan ancestry")


func _test_edge_pan_ancestry_and_meta() -> void:
	var host := Node.new()
	host.name = "Mv1bEdgePanHost"
	root.add_child(host)

	var noise := Label.new()
	noise.name = "MapLegendCaption"
	noise.text = "not chrome"
	host.add_child(noise)
	if MapViewInput.control_or_ancestor_blocks_edge_pan(noise):
		_fail("plain Label must not block edge pan")
		host.queue_free()
		return

	var info := Panel.new()
	info.name = "InfoPanel"
	host.add_child(info)
	var info_close := Button.new()
	info_close.name = "BtnClose"
	info_close.text = "Close"
	info.add_child(info_close)
	if not MapViewInput.control_or_ancestor_blocks_edge_pan(info_close):
		_fail("InfoPanel Close ancestor walk must block edge pan")
		host.queue_free()
		return
	if not MapViewInput.control_or_ancestor_blocks_edge_pan(info):
		_fail("InfoPanel root must block edge pan")
		host.queue_free()
		return

	var card := PanelContainer.new()
	card.name = "UnitDetailPopup"
	card.set_meta("unit_card_dock", true)
	host.add_child(card)
	var title_row := HBoxContainer.new()
	card.add_child(title_row)
	var card_close := Button.new()
	card_close.name = "BtnClose"
	card_close.text = "Close"
	title_row.add_child(card_close)
	if not MapViewInput.control_or_ancestor_blocks_edge_pan(card_close):
		_fail("UnitDetailPopup Close ancestor walk must block edge pan")
		host.queue_free()
		return
	if not MapViewInput.control_or_ancestor_blocks_edge_pan(card):
		_fail("UnitDetailPopup / unit_card_dock must block edge pan")
		host.queue_free()
		return

	var flagged := Control.new()
	flagged.name = "DockedCardRoot"
	flagged.set_meta("blocks_edge_pan", true)
	host.add_child(flagged)
	var flagged_child := Button.new()
	flagged_child.name = "InnerClose"
	flagged.add_child(flagged_child)
	if not MapViewInput.control_or_ancestor_blocks_edge_pan(flagged_child):
		_fail("blocks_edge_pan meta on ancestor must block")
		host.queue_free()
		return

	if MapViewInput.control_or_ancestor_blocks_edge_pan(null):
		_fail("null node must not block")
		host.queue_free()
		return

	host.queue_free()
	_pass("edge_pan ancestry / InfoPanel / UnitDetailPopup / blocks_edge_pan meta")
