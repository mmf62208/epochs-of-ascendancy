extends SceneTree

## DETERMINISM-1 probe. Prints the live border scan for JAP/GER/POL.
## The scan used to stop after 12 ms of wall time, so the same boot under
## CPU load returned a shorter border list. No Play.

func _init() -> void:
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var boot := load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if boot == null or mm == null or not bool(boot.boot(mm, sm, "GER")):
		print("FRONT_PROBE boot_failed")
		quit(1)
		return
	var ok := true
	for tag in ["JAP", "GER", "POL", "FRA"]:
		if not _one(mm, tag, "edges"):
			ok = false
		_one(mm, tag, "assault")
	if ok:
		print("FRONT_PROBE RESULT=PASS")
		quit(0)
	else:
		print("FRONT_PROBE RESULT=FAIL")
		quit(1)


func _one(mm: Node, tag: String, kind: String) -> bool:
	var t0 := Time.get_ticks_usec()
	var rows: Array = []
	if kind == "edges":
		rows = mm.call("collect_owned_border_edges", tag, 8)
	else:
		rows = mm.call("collect_live_border_assault_targets", tag, 8)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var parts: PackedStringArray = []
	var first_from := 0
	for i in mini(6, rows.size()):
		var row: Variant = rows[i]
		if row is Dictionary:
			var d: Dictionary = row
			if i == 0:
				first_from = int(d.get("from_province_id", 0))
			parts.append("%s>%s" % [str(d.get("from_province_id", 0)), str(d.get("province_id", 0))])
	print("FRONT %s %s n=%d ms=%.2f first=%s" % [tag, kind, rows.size(), ms, ",".join(parts)])
	if kind != "edges":
		return true
	var expect := {"JAP": 903951, "GER": 710173, "POL": 711054, "FRA": 710739}
	var want := int(expect.get(tag, 0))
	if rows.size() < 8 or first_from != want:
		print("FRONT_FAIL %s edges n=%d first_from=%d want=%d" % [tag, rows.size(), first_from, want])
		return false
	return true
