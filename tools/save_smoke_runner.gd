extends SceneTree
## Headless smoke: call shipped SaveLoadManager save_game_detailed + list_slots_for_ui.
## Invoked as: godot --path . --headless -s res://... (or absolute path via --script)

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Wait for autoloads
	await process_frame
	await process_frame
	var slm: Node = root.get_node_or_null("/root/SaveLoadManager")
	if slm == null:
		print("SAVE_SMOKE FAIL: SaveLoadManager missing")
		quit(2)
		return
	if slm.has_method("_ensure_save_dir"):
		slm.call("_ensure_save_dir")
	var slot := "slot_goal_smoke"
	print("SAVE_SMOKE: writing slot=", slot)
	var res: Dictionary = slm.call("save_game_detailed", slot)
	print("SAVE_SMOKE: result=", res)
	var ok := bool(res.get("ok", false))
	var abs_p := str(res.get("absolute_path", res.get("path", "")))
	var bytes := int(res.get("bytes", 0))
	print("SAVE_SMOKE: ok=", ok, " absolute_path=", abs_p, " bytes=", bytes)
	var listed: Array = []
	if slm.has_method("list_slots_for_ui"):
		listed = slm.call("list_slots_for_ui")
	var found_occupied := false
	for row in listed:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("slot", "")) == slot and bool(row.get("occupied", false)):
			found_occupied = true
			print("SAVE_SMOKE: list_slots_for_ui marks occupied label=", row.get("label", ""))
			break
	print("SAVE_SMOKE: listed_n=", listed.size(), " found_occupied=", found_occupied)
	var file_ok := FileAccess.file_exists("user://saves/%s.json" % slot)
	print("SAVE_SMOKE: file_exists=", file_ok)
	if ok and found_occupied and file_ok and bytes > 100:
		print("SAVE_SMOKE PASS")
		quit(0)
	else:
		print("SAVE_SMOKE FAIL")
		quit(3)
