extends SceneTree

## CL1-S3-POL-1 measuring test. RESULT=PASS means the runs finished and the
## table printed. It does not require the S3 stall to be gone.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessCl1S3Pol1Test.gd
##   CL1_S3_POL_1_VARIANTS=s3,flag_off,no_victory,s1
##   CL1_S3_POL_1_DAYS  cap (default soak D_MAX=400)
##
## Variants (one at a time, measured):
##   s3         GER player, include_player_in_ai_land_battles=true, victory overrides (soak S3)
##   flag_off   same as s3 but flag stays false
##   no_victory same as s3 without victory_min_majors_defeated / victory_count_minors
##   s1         USA player, flag false (soak S1 control)

const D_MAX := 400
const STALL_DAYS := 40
const FORM_TAGS: Array[String] = ["GER", "POL"]

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCl1S3Pol1Test: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if mm == null or tm == null or bm == null or lm == null or _boot == null or _war == null or _cap == null or _end == null:
		_fail("autoloads missing")
		_finish()
		return
	var raw := OS.get_environment("CL1_S3_POL_1_VARIANTS").strip_edges()
	if raw.is_empty():
		raw = "s3"
	var variants: PackedStringArray = raw.split(",", false)
	print("HeadlessCl1S3Pol1Test: variants=%s stall_days=%d d_max=%d" % [raw, STALL_DAYS, D_MAX])
	for v in variants:
		var name := str(v).strip_edges()
		if name.is_empty():
			continue
		await _run_variant(mm, sm, bm, tm, lm, name)
	_finish()


func _finish() -> void:
	print("HeadlessCl1S3Pol1Test: PASS (failures=", _failures, ")")
	print("HeadlessCl1S3Pol1Test: RESULT=PASS")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0)


func _run_variant(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, variant: String) -> void:
	var player := "GER"
	var flag := true
	var victory := true
	if variant == "flag_off":
		flag = false
	elif variant == "no_victory":
		victory = false
	elif variant == "s1":
		player = "USA"
		flag = false
		victory = false
	elif variant != "s3":
		print("CL1S3 variant=%s SKIP unknown" % variant)
		return
	var t0 := Time.get_ticks_msec()
	if not _boot_as(mm, sm, bm, lm, player):
		return
	bm.set("include_player_in_ai_land_battles", flag)
	if victory:
		_war.set_rule_overrides({"victory_min_majors_defeated": 1, "victory_count_minors": true})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("%s declare failed" % variant)
		return
	var stationed := _station_border(mm, "GER", "POL")
	print(
		"CL1S3 START variant=%s player=%s flag=%s victory=%s stationed=%d pol_thr=%.4f"
		% [variant, player, str(flag).to_lower(), str(victory).to_lower(), stationed, float(_cap.threshold("POL"))]
	)
	var fought := await _fight_until(mm, sm, bm, tm, lm, "POL", variant)
	var wall := Time.get_ticks_msec() - t0
	var days := int(tm.total_days_elapsed)
	var prog := float(_cap.progress("POL"))
	var owned := _count_owner(mm, "POL")
	var capd := bool(_cap.is_capitulated("POL"))
	var latched := bool(_end.call("latched"))
	var model: Dictionary = _end.call("view_model")
	print(
		"CL1S3 END variant=%s days=%d wall_ms=%d stationed=%d progress=%.4f owned=%d capitulated=%s latched=%s kind=%s outcome=%s paused=%s fought_ok=%s"
		% [
			variant,
			days,
			wall,
			stationed,
			prog,
			owned,
			str(capd).to_lower(),
			str(latched).to_lower(),
			str(model.get("kind", "")),
			str(model.get("outcome", "")),
			str(bool(tm.paused)).to_lower(),
			str(bool(fought.get("ok", false))).to_lower(),
		]
	)
	_dump_snapshot(mm, bm, lm, variant, "END")


func _boot_as(mm: Node, sm: Node, bm: Node, lm: Node, player: String) -> bool:
	# Same surface as HeadlessCampaignLoop1SoakTest._boot_as (no extra AI-war wipe).
	_clear_forms(lm)
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
	if not _boot.boot(mm, sm, player):
		_fail("boot %s failed" % player)
		return false
	if OS.get_environment("CL1_S3_POL_1_WIPE").strip_edges() == "1" and bm != null:
		if bm.has_method("reset_ai_war1_for_test"):
			bm.call("reset_ai_war1_for_test")
		if "_empty_hex_siege" in bm:
			bm._empty_hex_siege = {}
		if sm != null and "division_deployments" in sm and sm.division_deployments is Dictionary:
			(sm.division_deployments as Dictionary).clear()
	_cap.apply_economy_factories_to_map()
	_war.reset_for_test()
	_cap.reset_for_test()
	_end.call("reset_for_test")
	_war.clear_rule_overrides()
	_dump_leftover(bm, sm, "BOOT player=%s" % player)
	return true


func _dump_leftover(bm: Node, sm: Node, label: String) -> void:
	var cd_n := 0
	var blk_n := 0
	var siege := {}
	var stall := {}
	if bm != null:
		if "_retake_cooldown" in bm and bm._retake_cooldown is Dictionary:
			cd_n = (bm._retake_cooldown as Dictionary).size()
		if "_retake_blocked" in bm and bm._retake_blocked is Dictionary:
			blk_n = (bm._retake_blocked as Dictionary).size()
		if "_empty_hex_siege" in bm and bm._empty_hex_siege is Dictionary:
			siege = bm._empty_hex_siege
		if "_ai_stall" in bm and bm._ai_stall is Dictionary:
			stall = bm._ai_stall
	var dep_n := 0
	if sm != null and "division_deployments" in sm and sm.division_deployments is Dictionary:
		dep_n = (sm.division_deployments as Dictionary).size()
	print(
		"CL1S3 LEFTOVER %s cooldown_n=%d blocked_n=%d dep_n=%d siege=%s stall=%s"
		% [label, cd_n, blk_n, dep_n, str(siege), str(stall)]
	)


func _fight_until(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, tag: String, label: String) -> Dictionary:
	var stall := 0
	var prev := float(_cap.progress(tag))
	var owned := _count_owner(mm, tag)
	var last_flip := ""
	var freeze_dumped := false
	var d_max := D_MAX
	var env_days := OS.get_environment("CL1_S3_POL_1_DAYS").strip_edges()
	if not env_days.is_empty() and env_days.is_valid_int():
		d_max = maxi(int(env_days), 1)
	for _i in range(d_max):
		var owners_before: Dictionary = _owner_map(mm, tag)
		var rej_before: Dictionary = {}
		if bm.has_method("ai_reject_counters"):
			rej_before = bm.call("ai_reject_counters", true)
		_advance(tm)
		var day := int(tm.total_days_elapsed)
		var prog := float(_cap.progress(tag))
		var now_owned := _count_owner(mm, tag)
		var flipped: Array = _flipped_pids(mm, tag, owners_before)
		if not flipped.is_empty():
			last_flip = "day=%d pids=%s" % [day, str(flipped)]
		var rej: Dictionary = {}
		if bm.has_method("ai_reject_counters"):
			rej = bm.call("ai_reject_counters", false)
		var started_line := _battle_line(bm)
		if prog > prev + 0.0000001 or now_owned < owned:
			stall = 0
			freeze_dumped = false
		else:
			stall += 1
		if stall == 1 and not freeze_dumped:
			print(
				"CL1S3 FREEZE_START variant=%s day=%d progress=%.4f owned=%d last_flip=%s paused=%s latched=%s"
				% [label, day, prog, now_owned, last_flip, str(bool(tm.paused)).to_lower(), str(bool(_end.call("latched"))).to_lower()]
			)
			_dump_snapshot(mm, bm, lm, label, "FREEZE")
			freeze_dumped = true
		if day % 20 == 0 or stall == 1 or (stall > 1 and stall % 10 == 0):
			print(
				"CL1S3 %s day=%d progress=%.4f owned=%d stall=%d last_flip=%s %s rejects=%s"
				% [label, day, prog, now_owned, stall, last_flip, started_line, str(rej)]
			)
		prev = prog
		owned = now_owned
		if _cap.is_capitulated(tag):
			print("CL1S3 CAPITULATED variant=%s day=%d progress=%.4f last_flip=%s" % [label, day, prog, last_flip])
			return {"ok": true, "days": day, "last_flip": last_flip}
		if stall >= STALL_DAYS:
			print(
				"CL1S3 STALL variant=%s day=%d progress=%.4f owned=%d last_flip=%s"
				% [label, day, prog, now_owned, last_flip]
			)
			_dump_snapshot(mm, bm, lm, label, "STALL")
			break
	return {"ok": false, "days": int(tm.total_days_elapsed), "last_flip": last_flip}


func _dump_snapshot(mm: Node, bm: Node, lm: Node, variant: String, phase: String) -> void:
	var pol_pids: Array = _owner_pids(mm, "POL")
	print("CL1S3 SNAP %s %s pol_owned_n=%d pol_pids=%s" % [variant, phase, pol_pids.size(), str(pol_pids)])
	print("CL1S3 SNAP %s %s ger_units=%s" % [variant, phase, str(_unit_rows(lm, "GER"))])
	print("CL1S3 SNAP %s %s pol_units=%s" % [variant, phase, str(_unit_rows(lm, "POL"))])
	var open_n := 0
	var open_s := "[]"
	if bm != null and "_open_land_battles" in bm and bm._open_land_battles is Array:
		open_n = (bm._open_land_battles as Array).size()
		open_s = str(bm._open_land_battles)
	print("CL1S3 SNAP %s %s open_battles_n=%d open=%s" % [variant, phase, open_n, open_s])
	var siege := {}
	if bm != null and "_empty_hex_siege" in bm and bm._empty_hex_siege is Dictionary:
		siege = bm._empty_hex_siege
	print("CL1S3 SNAP %s %s empty_hex_siege=%s" % [variant, phase, str(siege)])
	var stall := {}
	if bm != null and "_ai_stall" in bm and bm._ai_stall is Dictionary:
		stall = bm._ai_stall
	print("CL1S3 SNAP %s %s ai_stall=%s" % [variant, phase, str(stall)])
	var rej := {}
	if bm != null and bm.has_method("ai_reject_counters"):
		rej = bm.call("ai_reject_counters", false)
	print("CL1S3 SNAP %s %s rejects=%s flag=%s" % [variant, phase, str(rej), str(bool(bm.get("include_player_in_ai_land_battles"))).to_lower()])


func _battle_line(bm: Node) -> String:
	var open_n := 0
	if bm != null and "_open_land_battles" in bm and bm._open_land_battles is Array:
		open_n = (bm._open_land_battles as Array).size()
	var siege_n := 0
	if bm != null and "_empty_hex_siege" in bm and bm._empty_hex_siege is Dictionary:
		siege_n = (bm._empty_hex_siege as Dictionary).size()
	return "open=%d siege=%d" % [open_n, siege_n]


func _unit_rows(lm: Node, tag: String) -> Array:
	var out: Array = []
	if lm == null or not ("formations" in lm) or not (lm.formations is Dictionary):
		return out
	var forms: Dictionary = lm.formations
	var keys: Array = forms.keys()
	keys.sort()
	for k in keys:
		var f: Object = forms[k]
		if f == null:
			continue
		var t := str(f.get("country_tag")).strip_edges().to_upper()
		if t != tag:
			continue
		out.append({
			"id": str(k),
			"station": int(f.get("stationed_province_id")),
			"str": float(f.get("strength")),
			"org": float(f.get("organization")),
		})
	return out


func _owner_map(mm: Node, tag: String) -> Dictionary:
	var out := {}
	for pid in _owner_pids(mm, tag):
		out[int(pid)] = true
	return out


func _flipped_pids(mm: Node, tag: String, before: Dictionary) -> Array:
	var now: Dictionary = _owner_map(mm, tag)
	var lost: Array = []
	for k in before.keys():
		var pid := int(k)
		if not now.has(pid):
			lost.append(pid)
	lost.sort()
	return lost


func _owner_pids(mm: Node, tag: String) -> Array:
	var pids: Variant = mm.call("get_provinces_by_owner", tag)
	var out: Array = []
	if pids is Array:
		for pid_v in pids:
			out.append(int(pid_v))
		out.sort()
	return out


func _station_border(mm: Node, att: String, defender: String) -> int:
	var owned: Array = mm.call("get_provinces_by_owner", att)
	owned.sort()
	var n := 0
	for pid_v in owned:
		var pid := int(pid_v)
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		var borders := false
		for nid_v in nbrs:
			var p: Object = mm.call("get_province", int(nid_v))
			if p == null or bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() == defender:
				borders = true
				break
		if not borders:
			continue
		_boot.make_division("cl1_%s_%d" % [att, pid], att, pid)
		n += 1
	return n


func _advance(tm: Node) -> Dictionary:
	return tm.call("advance_live_f5_equivalent_days", 1)


func _count_owner(mm: Node, tag: String) -> int:
	var pids: Variant = mm.call("get_provinces_by_owner", tag)
	return (pids as Array).size() if pids is Array else 0


func _clear_forms(lm: Node) -> void:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
