extends SceneTree
## Headless smoke for Command Center criterion:
## 1) MainMenu script/scene loads (CanvasLayer overlay)
## 2) shipped save_game_detailed writes a slot
## 3) list_slots_for_ui marks occupied
## 4) load_game_detailed returns ok
## Run: godot --path . --headless -s res://tools/command_center_save_load_smoke.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await process_frame

	var fails: PackedStringArray = []
	# --- MainMenu must parse and instantiate ---
	var packed: PackedScene = load("res://scenes/ui/MainMenu.tscn") as PackedScene
	if packed == null:
		fails.append("MainMenu.tscn failed to load")
	else:
		var menu: Node = packed.instantiate()
		if menu == null:
			fails.append("MainMenu instantiate null")
		else:
			if not (menu is CanvasLayer):
				fails.append("MainMenu is not CanvasLayer (got %s)" % menu.get_class())
			# Attach so _ready runs (builds UI); process_mode always
			menu.process_mode = Node.PROCESS_MODE_ALWAYS
			root.add_child(menu)
			await process_frame
			await process_frame
			if not is_instance_valid(menu):
				fails.append("MainMenu freed unexpectedly")
			elif menu.get_script() == null:
				fails.append("MainMenu has no script")
			else:
				print("CC_SMOKE: MainMenu loaded class=", menu.get_class(), " script_ok")
			# Exercise Command Center save entry (same path as Save Game button).
			if menu.has_method("_save_to_slot"):
				print("CC_SMOKE: calling MainMenu._save_to_slot(slot_cc_ui)")
				menu.call("_save_to_slot", "slot_cc_ui")
				await process_frame
				if not FileAccess.file_exists("user://saves/slot_cc_ui.json"):
					fails.append("MainMenu._save_to_slot did not create slot_cc_ui.json")
				else:
					print("CC_SMOKE: MainMenu._save_to_slot wrote file")
			else:
				fails.append("MainMenu missing _save_to_slot")
			# Close without hanging
			if menu.has_method("_force_close"):
				menu.call("_force_close")
			elif is_instance_valid(menu):
				menu.queue_free()
			await process_frame

	var slm: Node = root.get_node_or_null("/root/SaveLoadManager")
	if slm == null:
		fails.append("SaveLoadManager missing")
		_finish(fails)
		return

	var slot := "slot_cc_smoke"
	print("CC_SMOKE: save_game_detailed slot=", slot)
	var save_res: Dictionary = slm.call("save_game_detailed", slot)
	print("CC_SMOKE: save_res=", save_res)
	if not bool(save_res.get("ok", false)):
		fails.append("save_game_detailed failed: %s" % str(save_res.get("error", "?")))
	var bytes := int(save_res.get("bytes", 0))
	if bytes < 100:
		fails.append("save bytes too small: %d" % bytes)
	if not FileAccess.file_exists("user://saves/%s.json" % slot):
		fails.append("save file missing on disk")

	var listed: Array = slm.call("list_slots_for_ui") if slm.has_method("list_slots_for_ui") else []
	var found := false
	for row in listed:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("slot", "")) == slot and bool(row.get("occupied", false)):
			found = true
			print("CC_SMOKE: list marks occupied label=", row.get("label", ""))
			break
	if not found:
		fails.append("list_slots_for_ui did not mark slot occupied")

	print("CC_SMOKE: load_game_detailed slot=", slot)
	var load_res: Dictionary = slm.call("load_game_detailed", slot)
	print("CC_SMOKE: load_res=", load_res)
	if not bool(load_res.get("ok", false)):
		fails.append("load_game_detailed failed: %s" % str(load_res.get("error", "?")))
	else:
		print("CC_SMOKE: load_game_detailed ok (same API MainMenu Load buttons use)")

	# Structural: MainMenu._on_load_slot must still call load_game_detailed (source gate)
	var menu_src := FileAccess.get_file_as_string("res://scripts/ui/MainMenu.gd")
	if "load_game_detailed" not in menu_src or "_on_load_slot" not in menu_src:
		fails.append("MainMenu.gd missing load_game_detailed / _on_load_slot wiring")
	else:
		print("CC_SMOKE: MainMenu Load button wired to load_game_detailed")

	_finish(fails)


func _finish(fails: PackedStringArray) -> void:
	if fails.is_empty():
		print("CC_SMOKE PASS")
		quit(0)
	else:
		for f in fails:
			print("CC_SMOKE FAIL: ", f)
		print("CC_SMOKE FAIL")
		quit(3)
