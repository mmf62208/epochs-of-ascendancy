extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	print("EFL_SMOKE_START")
	var gd: Node = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("NO_GD"); quit(1); return
	var r: Dictionary = gd.call("apply_equipment_flow_primary_live", 1)
	print("EFL_OK=", str(r.get("ok", false)), " create=", str(r.get("create_ok", false)),
		" interdict=", str(r.get("interdict_ok", false)), " deliver=", str(r.get("deliver_ok", false)))
	print("EFL_SMOKE_DONE")
	quit(0)
