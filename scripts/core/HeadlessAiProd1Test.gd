extends SceneTree
## AI-PROD-1: headless campaign boot must be able to opt into live AI lines.
## On a base without CampaignLoopTestBoot.boot_ai_production the helper is skipped
## and assert 1 FAILs with "AI lines=0". The helper is not called from boot().
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessAiProd1Test.gd
##   AI_PROD_1_DAYS=180  optional longer window (fallback d180 line/completion count)

const AI_TAGS: Array[String] = ["GER", "FRA", "ENG", "SOV", "ITA", "JAP", "POL"]
const MAJOR_TAGS: Array[String] = ["GER", "FRA", "ENG", "USA", "SOV", "ITA", "JAP"]

var _failures := 0
var _boot: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAiProd1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAiProd1Test: ", msg)


func _run() -> void:
	var days := 30
	var env_days := OS.get_environment("AI_PROD_1_DAYS").strip_edges()
	if not env_days.is_empty() and env_days.is_valid_int():
		days = maxi(int(env_days), 1)
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var pm := get_root().get_node_or_null("ProductionManager")
	var bm := get_root().get_node_or_null("BattleManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var cap: GDScript = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	if mm == null or tm == null or pm == null or _boot == null or cap == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.boot(mm, sm, "USA"):
		_fail("boot failed")
		_finish()
		return
	cap.apply_economy_factories_to_map()
	if _script_has(_boot, "boot_ai_production"):
		var info: Variant = _boot.call("boot_ai_production", "USA")
		print("HeadlessAiProd1Test: boot_ai_production %s" % JSON.stringify(info))
	else:
		print("HeadlessAiProd1Test: boot_ai_production absent (base path)")
	var owned := _lines_by_owner(pm)
	var n_lines := 0
	for tag in AI_TAGS:
		n_lines += (owned.get(tag, []) as Array).size()
	if n_lines <= 0:
		_fail("AI lines=0")
		_finish()
		return
	var missing: PackedStringArray = []
	for tag in AI_TAGS:
		var rows: Array = owned.get(tag, []) as Array
		if rows.is_empty():
			missing.append(tag)
	if not missing.is_empty():
		_fail("AI lines missing for %s (owned=%s)" % [",".join(missing), JSON.stringify(owned)])
	else:
		_pass("AI lines for %s" % ",".join(AI_TAGS))
	var wrong: PackedStringArray = []
	for lid_v in pm.get_line_ids():
		var lid := str(lid_v)
		if not lid.begins_with("oob_"):
			continue
		var parts: PackedStringArray = lid.split("_", false, 3)
		if parts.size() < 2:
			continue
		var want := parts[1].to_upper()
		var line: Variant = pm.get_line(lid)
		var owner := str(pm.call("_resolve_line_owner_tag", line, lid))
		if owner != want:
			wrong.append("%s->%s" % [lid, owner])
	if not wrong.is_empty():
		_fail("wrong-owner %s" % ",".join(wrong))
	else:
		_pass("oob line owners match tags")
	if _failures > 0:
		_finish()
		return
	for _d in range(days):
		tm.call("advance_live_f5_equivalent_days", 1)
		await process_frame
	var majors_done := 0
	var done_bits: PackedStringArray = []
	for tag in MAJOR_TAGS:
		if tag == "USA":
			continue
		var best := 0
		var cc := 0
		var up := 0
		for lid_v2 in pm.get_line_ids():
			var lid2 := str(lid_v2)
			if not lid2.begins_with("oob_%s_" % tag) or not lid2.contains("infantry"):
				continue
			var line2: Variant = pm.get_line(lid2)
			if line2 == null:
				continue
			cc = int(line2.completed_count) if "completed_count" in line2 else 0
			if line2.has_method("get_current_state"):
				var st: Variant = line2.call("get_current_state")
				if st != null and "units_produced" in st:
					up = int(st.units_produced)
			best = maxi(best, maxi(cc, up))
		if best > 0:
			majors_done += 1
		done_bits.append("%s cc=%d up=%d" % [tag, cc, up])
	print("HeadlessAiProd1Test: infantry days=%d majors_done=%d %s" % [days, majors_done, ", ".join(done_bits)])
	if majors_done < 4:
		_fail("infantry completions majors=%d want>=4 (%s)" % [majors_done, ", ".join(done_bits)])
	else:
		_pass("infantry completions majors=%d (day-path units_produced; completed_count is the PP counter)" % majors_done)
	var sample := "GER"
	var rep: Dictionary = pm.advance_days_for_country(sample, 1.0)
	var touched := int(rep.get("lines_touched", 0))
	var soft := int(rep.get("soft_stock_credit", 0))
	if touched < 1 or soft != 0:
		_fail("%s advance lines_touched=%d soft_stock_credit=%d" % [sample, touched, soft])
	else:
		_pass("%s advance lines_touched=%d soft_stock_credit=0" % [sample, touched])
	_print_battle_counters(bm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAiProd1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAiProd1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _script_has(scr: GDScript, method_name: String) -> bool:
	for m in scr.get_script_method_list():
		if typeof(m) == TYPE_DICTIONARY and str((m as Dictionary).get("name", "")) == method_name:
			return true
	return false


func _lines_by_owner(pm: Node) -> Dictionary:
	var out := {}
	for lid_v in pm.get_line_ids():
		var lid := str(lid_v)
		var line: Variant = pm.get_line(lid)
		var owner := ""
		if line != null:
			owner = str(pm.call("_resolve_line_owner_tag", line, lid))
		if not out.has(owner):
			out[owner] = []
		(out[owner] as Array).append(lid)
	return out


func _print_battle_counters(bm: Node) -> void:
	if bm == null:
		print("HeadlessAiProd1Test: battles open=0")
		return
	var open_n := 0
	if bm.has_method("get_open_land_battles"):
		open_n = (bm.call("get_open_land_battles") as Array).size()
	print("HeadlessAiProd1Test: battles open=%d" % open_n)
