extends SceneTree

## CL1b capitulation and peace. Goldens are the economy-layer weights:
##   POL 55 provinces, factory sum 167, keys 3, capital 711112 weight 44.
##   NATION-TAGS-1 Lviv+Lutsk (factories 0) made the total 277.
##   MAP-RECONCILE-1 adds Stanislawow, Tarnopol, Rovno, Drohobych, Kovel
##   (factories 1, base 1). Total 287. Capital-only 44/287 = 0.153310.
##   Threshold stays 0.62 (stability, not province count).
##   The extra weight is Lviv 906005 and Lutsk 906006 (base 1, factories 0).
##   LUX pid 710977, factories 3, weight 29, minor threshold 0.50, annex_all.
##   FRA stability 70, threshold 0.68, keep_occupied.
## Crossing the threshold goes through the daily hook (not a direct check_all),
## so a removed day hook fails this test.

const POL_CAPITAL := 711112
const POL_CAP_PROGRESS := 44.0 / 287.0
const POL_THRESHOLD := 0.62
const LUX_PID := 710977
const LUX_THRESHOLD := 0.50
const FRA_THRESHOLD := 0.68
const FRA_CAPITAL := 710707

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCampaignLoop1CapitulationPeaceTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCampaignLoop1CapitulationPeaceTest: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var gd := get_root().get_node_or_null("GameData")
	var sl := get_root().get_node_or_null("SaveLoadManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	if mm == null or tm == null or gd == null or _boot == null or _war == null or _cap == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("campaign boot failed")
		_finish()
		return
	_pass("boot world_accurate player=GER")
	var applied := int(_cap.apply_economy_factories_to_map())
	if applied < 3000:
		_fail("economy factories applied %d" % applied)
	else:
		_pass("economy factories applied %d" % applied)
	_war.reset_for_test()
	_cap.reset_for_test()
	_war.clear_rule_overrides()
	for pair in [["GER", "POL"], ["GER", "LUX"], ["GER", "FRA"]]:
		var declared: Dictionary = _war.declare_war(str(pair[0]), str(pair[1]), "test")
		if not bool(declared.get("ok", false)):
			_fail("declare %s-%s failed %s" % [pair[0], pair[1], str(declared)])
	_boot.make_division("cl1_pol", "POL", POL_CAPITAL)
	_boot.make_division("cl1_fra", "FRA", FRA_CAPITAL)
	_boot.make_division("cl1_lux", "LUX", LUX_PID)
	_advance(tm)
	if _cap.is_capitulated("POL") or _cap.is_capitulated("LUX") or _cap.is_capitulated("FRA"):
		_fail("capitulated before the threshold")
	else:
		_pass("no capitulation at progress 0")
	_assert_goldens()
	_assert_capitals()
	_set_controller(mm, sm, POL_CAPITAL, "GER")
	var pol_prog := float(_cap.progress("POL"))
	if absf(pol_prog - POL_CAP_PROGRESS) > 0.000001:
		_fail("POL capital progress want %.6f got %.6f" % [POL_CAP_PROGRESS, pol_prog])
	else:
		_pass("POL capital progress %.6f" % pol_prog)
	_advance(tm)
	if _cap.is_capitulated("POL"):
		_fail("POL capitulated on capital alone")
	var check_ms := float(_cap.last_check_ms())
	var slow := OS.get_environment("EOA_SLOW_BOX").strip_edges() == "1"
	var check_bar := 20.0 if slow else 10.0
	var annex_bar := 3000.0 if slow else 1500.0
	print("PERF daily_check_ms=%.3f bar=%.1f slow_box=%s" % [check_ms, check_bar, "1" if slow else "0"])
	if check_ms <= 0.0 or check_ms > check_bar:
		_fail("daily check %.3f ms outside (0, %.1f]" % [check_ms, check_bar])
	else:
		_pass("daily check %.3f ms" % check_ms)
	_occupy_until(mm, sm, "POL", "GER")
	_occupy_until(mm, sm, "LUX", "GER")
	_occupy_until(mm, sm, "FRA", "GER")
	_arm_battle(bm, "cl1_pol", "POL", "GER", POL_CAPITAL)
	_arm_battle(bm, "cl1_fra", "FRA", "GER", FRA_CAPITAL)
	_arm_battle(bm, "cl1_lux", "LUX", "GER", LUX_PID)
	var before := _settlement_count(gd)
	_advance(tm)
	_assert_outcome("POL", "annex_all", mm)
	_assert_outcome("LUX", "annex_all", mm)
	_assert_outcome("FRA", "keep_occupied", mm)
	if _still_owns(mm, "POL"):
		_fail("POL still owns land after annex_all")
	else:
		_pass("POL annexed to the war leader")
	if not _owner_is(mm, FRA_CAPITAL, "FRA"):
		_fail("FRA capital owner changed under keep_occupied")
	else:
		_pass("FRA rump kept")
	var annex_ms := float(_cap.last_annex_ms())
	print("PERF annex_all_ms=%.3f bar=%.1f" % [annex_ms, annex_bar])
	if annex_ms <= 0.0 or annex_ms > annex_bar:
		_fail("annex_all %.3f ms outside (0, %.1f]" % [annex_ms, annex_bar])
	else:
		_pass("annex_all %.3f ms" % annex_ms)
	var added := _settlement_count(gd) - before
	if added != 3:
		_fail("settlement rows added %d want 3" % added)
	else:
		_pass("one settlement row per capitulation")
	_assert_fights_closed(bm, lm)
	_assert_save_keys(sl)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessCampaignLoop1CapitulationPeaceTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCampaignLoop1CapitulationPeaceTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _assert_goldens() -> void:
	var pol_thr := float(_cap.threshold("POL"))
	var lux_thr := float(_cap.threshold("LUX"))
	var fra_thr := float(_cap.threshold("FRA"))
	if absf(pol_thr - POL_THRESHOLD) > 0.000001:
		_fail("POL threshold want %.2f got %.4f" % [POL_THRESHOLD, pol_thr])
	elif absf(lux_thr - LUX_THRESHOLD) > 0.000001:
		_fail("LUX threshold want %.2f got %.4f" % [LUX_THRESHOLD, lux_thr])
	elif absf(fra_thr - FRA_THRESHOLD) > 0.000001:
		_fail("FRA threshold want %.2f got %.4f" % [FRA_THRESHOLD, fra_thr])
	else:
		_pass("thresholds POL %.2f LUX %.2f FRA %.2f" % [pol_thr, lux_thr, fra_thr])
	if absf(float(_cap.progress("POL"))) > 0.000001:
		_fail("POL progress at peace-occupation 0 got %.4f" % float(_cap.progress("POL")))
	if str(_cap.default_outcome("POL")) != "annex_all" or str(_cap.default_outcome("LUX")) != "annex_all":
		_fail("minor outcome want annex_all")
	elif str(_cap.default_outcome("FRA")) != "keep_occupied":
		_fail("FRA outcome want keep_occupied got %s" % str(_cap.default_outcome("FRA")))
	else:
		_pass("outcomes minor annex_all major keep_occupied")


func _assert_capitals() -> void:
	var caps: Dictionary = _cap.derived_capitals()
	var gd := get_root().get_node_or_null("GameData")
	var st: Dictionary = gd.peace_state.get("campaign_capitulation", {})
	var owned: Dictionary = st.get("start_owned", {})
	var keys: Array = caps.keys()
	keys.sort()
	if keys.size() != 65:
		_fail("derived capitals %d want 65" % keys.size())
	var bad := 0
	var lines: PackedStringArray = []
	for tag_v in keys:
		var tag := str(tag_v)
		var pid := int(caps[tag])
		var mine: Array = owned.get(tag, [])
		var hit := false
		for v in mine:
			if int(v) == pid:
				hit = true
				break
		if pid <= 0 or not hit:
			bad += 1
			_fail("capital %s -> %d not owned" % [tag, pid])
		lines.append("%s %d" % [tag, pid])
	if int(caps.get("POL", -1)) != POL_CAPITAL:
		_fail("POL capital %s want %d" % [str(caps.get("POL", -1)), POL_CAPITAL])
	if int(caps.get("LUX", -1)) != LUX_PID:
		_fail("LUX capital %s want %d" % [str(caps.get("LUX", -1)), LUX_PID])
	if bad == 0 and keys.size() == 65:
		_pass("65 capitals resolve to owned provinces")
	var path := OS.get_environment("HOME") + "/campaign1_evidence/cl1b_capitals.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()


func _assert_outcome(tag: String, outcome: String, mm: Node) -> void:
	if not _cap.is_capitulated(tag):
		_fail("%s did not capitulate" % tag)
		return
	if _war.is_at_war("GER", tag):
		_fail("%s war still open" % tag)
	elif not _war.in_truce("GER", tag):
		_fail("%s truce missing" % tag)
	else:
		_pass("%s war ended with truce" % tag)
	var gd := get_root().get_node_or_null("GameData")
	var st: Dictionary = gd.peace_state.get("campaign_capitulation", {})
	var row: Dictionary = (st.get("capitulated", {}) as Dictionary).get(tag, {})
	if str(row.get("outcome", "")) != outcome:
		_fail("%s outcome want %s got %s" % [tag, outcome, str(row.get("outcome", ""))])
	elif str(row.get("war_leader", "")) != "GER":
		_fail("%s war leader want GER got %s" % [tag, str(row.get("war_leader", ""))])
	else:
		_pass("%s %s leader GER" % [tag, outcome])
	var again: Dictionary = _war.declare_war("GER", tag, "redeclare")
	if bool(again.get("ok", false)):
		_fail("truce did not block re-declare %s" % tag)


func _assert_fights_closed(bm: Node, lm: Node) -> void:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		for fid_v in lm.formations.keys():
			var f: Variant = lm.formations[fid_v]
			if f == null:
				continue
			var tag := str(f.country_tag).strip_edges().to_upper()
			if tag != "POL" and tag != "FRA" and tag != "LUX":
				continue
			if "is_in_combat" in f and bool(f.is_in_combat):
				_fail("%s formation still in combat" % tag)
	if bm != null and "_open_land_battles" in bm:
		for raw in bm._open_land_battles:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var att := str((raw as Dictionary).get("att_tag", "")).strip_edges().to_upper()
			var def := str((raw as Dictionary).get("def_tag", "")).strip_edges().to_upper()
			if att in ["POL", "FRA", "LUX"] or def in ["POL", "FRA", "LUX"]:
				_fail("open battle remains %s vs %s" % [att, def])
	if lm != null and lm.has_method("get_formations_for_country"):
		var left: Array = lm.call("get_formations_for_country", "POL")
		if not left.is_empty():
			_fail("POL formations still active after annex_all")
		else:
			_pass("POL formations inactive and fights closed")
	else:
		_pass("fights closed")


func _assert_save_keys(sl: Node) -> void:
	if sl == null or not sl.has_method("_gather_save_data"):
		_fail("SaveLoadManager._gather_save_data missing")
		return
	var blob: Dictionary = sl.call("_gather_save_data")
	var game: Dictionary = blob.get("game_data", {})
	var missing: PackedStringArray = []
	for key in ["campaign_wars", "campaign_capitulation", "campaign_end"]:
		if not game.has(key):
			missing.append(key)
	if not missing.is_empty():
		_fail("save whitelist missing %s" % ", ".join(missing))
	else:
		_pass("save whitelist has campaign_wars, campaign_capitulation, campaign_end")


func _advance(tm: Node) -> void:
	tm.paused = false
	tm.call("advance_live_f5_equivalent_days", 1)


func _set_controller(mm: Node, sm: Node, pid: int, controller: String) -> void:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return
	var owner := str(p.get("owner_tag")).strip_edges().to_upper()
	if sm != null and sm.has_method("begin_control_batch"):
		sm.call("begin_control_batch")
	mm.call("update_province_owner", pid, owner, controller, true, true)
	if sm != null and sm.has_method("end_control_batch"):
		sm.call("end_control_batch")


func _occupy_until(mm: Node, sm: Node, tag: String, holder: String) -> void:
	if float(_cap.progress(tag)) + 0.0000001 >= float(_cap.threshold(tag)):
		return
	var pids: Array = mm.call("get_provinces_by_owner", tag)
	pids.sort()
	if sm != null and sm.has_method("begin_control_batch"):
		sm.call("begin_control_batch")
	for pid_v in pids:
		var pid := int(pid_v)
		var p: Object = mm.call("get_province", pid)
		if p == null:
			continue
		var owner := str(p.get("owner_tag")).strip_edges().to_upper()
		var ctrl := str(p.get("controller_tag")).strip_edges().to_upper()
		if ctrl == holder:
			continue
		mm.call("update_province_owner", pid, owner, holder, true, true)
		if float(_cap.progress(tag)) + 0.0000001 >= float(_cap.threshold(tag)):
			break
	if sm != null and sm.has_method("end_control_batch"):
		sm.call("end_control_batch")


func _arm_battle(bm: Node, fid: String, tag: String, att: String, pid: int) -> void:
	var lm := get_root().get_node_or_null("LeaderManager")
	if lm != null and lm.formations is Dictionary and lm.formations.has(fid):
		var f: Variant = lm.formations[fid]
		if f != null and "is_in_combat" in f:
			f.is_in_combat = true
	if bm == null or not ("_open_land_battles" in bm):
		return
	bm._open_land_battles.append({
		"att_tag": att,
		"def_tag": tag,
		"att_fid": "",
		"def_fid": fid,
		"def_fids": [fid],
		"to_id": pid,
		"from_id": pid,
		"att_org": 1.0,
		"def_org": 1.0,
		"att_stance": "hold",
		"days_elapsed": 0,
	})


func _settlement_count(gd: Node) -> int:
	var raw: Variant = gd.peace_state.get("peace_settlements", [])
	if raw is Array:
		return (raw as Array).size()
	return 0


func _still_owns(mm: Node, tag: String) -> bool:
	var pids: Array = mm.call("get_provinces_by_owner", tag)
	return not pids.is_empty()


func _owner_is(mm: Node, pid: int, tag: String) -> bool:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return false
	return str(p.get("owner_tag")).strip_edges().to_upper() == tag
