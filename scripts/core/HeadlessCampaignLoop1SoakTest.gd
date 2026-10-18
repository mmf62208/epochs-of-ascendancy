extends SceneTree

## CL1c sped-up 1936 campaign. Real F5 days, real start_land_battle captures.
## Empty enemy hexes use the shipped light-sim capture (not a scripted owner flip).
## Divisions are stationed on the attacker's border provinces. Capture moves the
## station onto the taken hex, and the front cache drops on owner change, so the
## next day can walk forward. No new march planner.
## S4 and the M8 victory gate do not need a battle.

const D_MAX := 400
const STALL_DAYS := 40
const S4_DAYS := 30

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _next: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCampaignLoop1SoakTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCampaignLoop1SoakTest: ", msg)


func _run() -> void:
	var wall0 := Time.get_ticks_msec()
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	var gd := get_root().get_node_or_null("GameData")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	_next = load("res://scripts/ui/PlayNextHook.gd") as GDScript
	if mm == null or tm == null or bm == null or _boot == null or _war == null or _cap == null or _end == null:
		_fail("autoloads missing")
		_finish(wall0)
		return
	await _s4_time_limit(mm, sm, tm)
	await _m8_major_blocks_victory(mm, sm, tm)
	var first := await _defeat_run(mm, sm, bm, tm, lm, "S2")
	var second := await _defeat_run(mm, sm, bm, tm, lm, "S2b")
	if first.is_empty() or second.is_empty():
		_fail("determinism runs did not both finish")
	elif int(first.get("day", -1)) != int(second.get("day", -2)) or str(first.get("md5", "")) != str(second.get("md5", "x")):
		_fail("S2 determinism day %s/%s md5 %s/%s" % [str(first.get("day")), str(second.get("day")), str(first.get("md5")), str(second.get("md5"))])
	else:
		_pass("S2 determinism day %d md5 %s" % [int(first.get("day", 0)), str(first.get("md5", ""))])
	await _observer_war(mm, sm, bm, tm, lm, gd)
	await _player_victory(mm, sm, bm, tm, lm)
	var wall := Time.get_ticks_msec() - wall0
	print("SOAK wall_ms=%d" % wall)
	_finish(wall0)


func _finish(_wall0: int) -> void:
	var ok := _failures == 0
	print("HeadlessCampaignLoop1SoakTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCampaignLoop1SoakTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _boot_as(mm: Node, sm: Node, bm: Node, lm: Node, player: String) -> bool:
	_clear_forms(lm)
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
	if not _boot.boot(mm, sm, player):
		_fail("boot %s failed" % player)
		return false
	_cap.apply_economy_factories_to_map()
	_war.reset_for_test()
	_cap.reset_for_test()
	_end.call("reset_for_test")
	_war.clear_rule_overrides()
	return true


func _s4_time_limit(mm: Node, sm: Node, tm: Node) -> void:
	var t0 := Time.get_ticks_msec()
	if not _boot.boot(mm, sm, "GER"):
		_fail("S4 boot failed")
		return
	_cap.apply_economy_factories_to_map()
	_war.reset_for_test()
	_cap.reset_for_test()
	_end.call("reset_for_test")
	var end_date := "1936-01-31"
	_war.set_rule_overrides({"end_date": end_date})
	var ranked: Array = _end.call("factory_rank")
	for i in range(S4_DAYS):
		_advance(tm)
		if bool(_end.call("latched")):
			break
	var model: Dictionary = _end.call("view_model")
	var date := _date(tm)
	var wall := Time.get_ticks_msec() - t0
	print("SOAK S4 days=%d wall_ms=%d date=%s rank0=%s" % [int(tm.total_days_elapsed), wall, date, str(ranked[0]) if not ranked.is_empty() else ""])
	if date != end_date:
		_fail("S4 date want %s got %s" % [end_date, date])
		return
	if str(model.get("date", "")) != end_date or str(model.get("kind", "")) != "time":
		_fail("S4 latch kind=%s date=%s" % [str(model.get("kind", "")), str(model.get("date", ""))])
		return
	var want_outcome := "victory" if not ranked.is_empty() and str(ranked[0]) == "GER" else "defeat"
	var want_title := "Victory: Ascendant" if want_outcome == "victory" else "Defeat: Eclipsed (rank %d)" % _rank_of(ranked, "GER")
	if str(model.get("outcome", "")) != want_outcome or str(model.get("title", "")) != want_title:
		_fail("S4 want %s/%s got %s/%s" % [want_outcome, want_title, str(model.get("outcome")), str(model.get("title"))])
		return
	if not bool(tm.paused):
		_fail("S4 clock not paused")
		return
	var elapsed := int(tm.total_days_elapsed)
	var locked: Dictionary = _advance(tm)
	if int(locked.get("days", 1)) != 0 or int(tm.total_days_elapsed) != elapsed or _date(tm) != end_date:
		_fail("S4 extra day moved the clock")
		return
	_pass("S4 time limit %s %s" % [want_title, end_date])


func _m8_major_blocks_victory(mm: Node, sm: Node, tm: Node) -> void:
	if not _boot.boot(mm, sm, "GER"):
		_fail("M8 boot failed")
		return
	_cap.apply_economy_factories_to_map()
	_war.reset_for_test()
	_cap.reset_for_test()
	_end.call("reset_for_test")
	_war.set_rule_overrides({"victory_min_majors_defeated": 1, "victory_count_minors": true})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("M8 declare POL failed")
		return
	if not bool(_war.declare_war("GER", "FRA", "test").get("ok", false)):
		_fail("M8 declare FRA failed")
		return
	_hold_until(mm, sm, "POL", "GER")
	_advance(tm)
	if not _cap.is_capitulated("POL"):
		_fail("M8 POL did not capitulate progress=%.4f" % float(_cap.progress("POL")))
		return
	if bool(_end.call("latched")):
		_fail("M8 victory latched while FRA is still an enemy major")
		return
	_pass("M8 no victory while at war with FRA")
	var peace: Dictionary = _war.make_peace("GER", "FRA", "test")
	if not bool(peace.get("ok", false)):
		_fail("M8 peace FRA failed %s" % str(peace))
		return
	_advance(tm)
	var model: Dictionary = _end.call("view_model")
	if str(model.get("outcome", "")) != "victory" or str(model.get("kind", "")) != "decisive":
		_fail("M8 victory after FRA peace got %s" % str(model))
		return
	_pass("M8 victory after the major war ends")


func _defeat_run(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, label: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	if not _boot_as(mm, sm, bm, lm, "POL"):
		return {}
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("%s declare failed" % label)
		return {}
	var stationed := _station_border(mm, "GER", "POL")
	if stationed <= 0:
		_fail("%s no GER border divisions" % label)
		return {}
	var fought := await _fight_until(mm, tm, "POL", label)
	var wall := Time.get_ticks_msec() - t0
	var days := int(tm.total_days_elapsed)
	print("SOAK %s days=%d wall_ms=%d ms_per_day=%.1f stationed=%d progress=%.4f" % [label, days, wall, float(wall) / maxf(float(days), 1.0), stationed, float(_cap.progress("POL"))])
	if not bool(fought.get("ok", false)):
		_fail("%s UNKNOWN POL progress %.4f after %d days (real battles stalled)" % [label, float(_cap.progress("POL")), days])
		return {}
	var model: Dictionary = _end.call("view_model")
	if str(model.get("outcome", "")) != "defeat" or str(model.get("kind", "")) != "defeat":
		_fail("%s end model %s" % [label, str(model)])
		return {}
	var reason := str(model.get("reason", ""))
	if str(model.get("title", "")) != "Defeat" or reason.find("capitulated") < 0:
		_fail("%s title/reason %s / %s" % [label, str(model.get("title")), reason])
		return {}
	if str(model.get("player_tag", "")) != "POL":
		_fail("%s player tag %s" % [label, str(model.get("player_tag"))])
		return {}
	if not bool(tm.paused):
		_fail("%s clock not paused" % label)
		return {}
	if _next != null:
		var rec: Dictionary = _next.call("recommend", "POL")
		if str(rec.get("label", "")) != "Campaign over":
			_fail("%s NEXT label %s" % [label, str(rec.get("label"))])
			return {}
	var elapsed := int(tm.total_days_elapsed)
	var date := _date(tm)
	var locked: Dictionary = tm.call("advance_live_f5_equivalent_days", 20)
	if int(locked.get("days", 1)) != 0 or int(tm.total_days_elapsed) != elapsed or _date(tm) != date:
		_fail("%s 20 more days advanced the date" % label)
		return {}
	var ai: Dictionary = bm.call("try_ai_start_land_battles", elapsed + 1)
	if int(ai.get("started_n", 1)) != 0 or str(ai.get("reason", "")) != "campaign_end":
		_fail("%s AI still starts after defeat %s" % [label, str(ai)])
		return {}
	if _still_owns(mm, "POL"):
		_fail("%s POL still owns land" % label)
		return {}
	if _war.is_at_war("GER", "POL") or not _war.in_truce("GER", "POL"):
		_fail("%s war/truce after defeat" % label)
		return {}
	_pass("%s defeat day %d" % [label, days])
	return {"day": days, "md5": _owner_md5(mm), "date": date}


func _observer_war(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node, gd: Node) -> void:
	var t0 := Time.get_ticks_msec()
	if not _boot_as(mm, sm, bm, lm, "USA"):
		return
	var before := _settlement_count(gd)
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("S1 declare failed")
		return
	var stationed := _station_border(mm, "GER", "POL")
	var fought := await _fight_until(mm, tm, "POL", "S1")
	var wall := Time.get_ticks_msec() - t0
	var days := int(tm.total_days_elapsed)
	print("SOAK S1 days=%d wall_ms=%d ms_per_day=%.1f stationed=%d progress=%.4f" % [days, wall, float(wall) / maxf(float(days), 1.0), stationed, float(_cap.progress("POL"))])
	if not bool(fought.get("ok", false)):
		_fail("S1 UNKNOWN POL progress %.4f after %d days (real battles stalled)" % [float(_cap.progress("POL")), days])
		return
	if not _cap.is_capitulated("POL"):
		_fail("S1 POL not capitulated")
		return
	var row: Dictionary = _cap_row("POL")
	if str(row.get("outcome", "")) != "annex_all" or str(row.get("war_leader", "")) != "GER":
		_fail("S1 outcome %s leader %s" % [str(row.get("outcome")), str(row.get("war_leader"))])
		return
	if _still_owns(mm, "POL") or _war.is_at_war("GER", "POL") or not _war.in_truce("GER", "POL"):
		_fail("S1 owners/war/truce after annex")
		return
	if _settlement_count(gd) - before != 1:
		_fail("S1 settlement rows %d" % (_settlement_count(gd) - before))
		return
	var owned_before := _count_owner(mm, "GER")
	for _i in range(5):
		_advance(tm)
	if _war.is_at_war("GER", "POL") or _count_owner(mm, "GER") != owned_before:
		_fail("S1 GER kept attacking POL after peace")
		return
	if bool(_end.call("latched")):
		_fail("S1 observer latched an end")
		return
	_pass("S1 POL annexed by GER day %d" % days)


func _player_victory(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	var t0 := Time.get_ticks_msec()
	if not _boot_as(mm, sm, bm, lm, "GER"):
		return
	bm.set("include_player_in_ai_land_battles", true)
	_war.set_rule_overrides({"victory_min_majors_defeated": 1, "victory_count_minors": true})
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("S3 declare failed")
		return
	var stationed := _station_border(mm, "GER", "POL")
	var fought := await _fight_until(mm, tm, "POL", "S3")
	var wall := Time.get_ticks_msec() - t0
	var days := int(tm.total_days_elapsed)
	print("SOAK S3 days=%d wall_ms=%d ms_per_day=%.1f stationed=%d progress=%.4f" % [days, wall, float(wall) / maxf(float(days), 1.0), stationed, float(_cap.progress("POL"))])
	if not bool(fought.get("ok", false)):
		_fail("S3 UNKNOWN POL progress %.4f after %d days (real battles stalled)" % [float(_cap.progress("POL")), days])
		return
	var model: Dictionary = _end.call("view_model")
	if str(model.get("outcome", "")) != "victory" or str(model.get("kind", "")) != "decisive":
		_fail("S3 model %s" % str(model))
		return
	if str(model.get("title", "")) != "Victory" or str(model.get("player_tag", "")) != "GER":
		_fail("S3 title/player %s %s" % [str(model.get("title")), str(model.get("player_tag"))])
		return
	if not bool(tm.paused):
		_fail("S3 clock not paused")
		return
	var stats: Dictionary = model.get("stats", {})
	if int(stats.get("capitulated_by_side", 0)) < 1:
		_fail("S3 stats %s" % str(stats))
		return
	_pass("S3 victory day %d" % days)


func _fight_until(mm: Node, tm: Node, tag: String, label: String) -> Dictionary:
	var stall := 0
	var prev := float(_cap.progress(tag))
	var owned := _count_owner(mm, tag)
	for _i in range(D_MAX):
		_advance(tm)
		if _cap.is_capitulated(tag):
			return {"ok": true, "days": int(tm.total_days_elapsed)}
		var prog := float(_cap.progress(tag))
		var now_owned := _count_owner(mm, tag)
		if prog > prev + 0.0000001 or now_owned < owned:
			stall = 0
		else:
			stall += 1
		prev = prog
		owned = now_owned
		var day := int(tm.total_days_elapsed)
		if day % 20 == 0 or stall == 1:
			print("SOAK %s day=%d progress=%.4f owned=%d" % [label, day, prog, owned])
		if stall >= STALL_DAYS:
			break
	return {"ok": false, "days": int(tm.total_days_elapsed)}


func _hold_until(mm: Node, sm: Node, tag: String, holder: String) -> void:
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


func _date(tm: Node) -> String:
	return "%04d-%02d-%02d" % [int(tm.current_year), int(tm.current_month), int(tm.current_day)]


func _rank_of(ranked: Array, tag: String) -> int:
	for i in range(ranked.size()):
		if str(ranked[i]) == tag:
			return i + 1
	return ranked.size()


func _cap_row(tag: String) -> Dictionary:
	var gd := get_root().get_node_or_null("GameData")
	if gd == null:
		return {}
	var st: Dictionary = gd.peace_state.get("campaign_capitulation", {})
	var raw: Variant = (st.get("capitulated", {}) as Dictionary).get(tag, {})
	return raw if raw is Dictionary else {}


func _settlement_count(gd: Node) -> int:
	if gd == null:
		return 0
	var raw: Variant = gd.peace_state.get("peace_settlements", [])
	return (raw as Array).size() if raw is Array else 0


func _still_owns(mm: Node, tag: String) -> bool:
	return _count_owner(mm, tag) > 0


func _count_owner(mm: Node, tag: String) -> int:
	var pids: Variant = mm.call("get_provinces_by_owner", tag)
	return (pids as Array).size() if pids is Array else 0


func _clear_forms(lm: Node) -> void:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()


func _owner_md5(mm: Node) -> String:
	var provs: Dictionary = mm.call("get_all_provinces")
	var keys: Array = provs.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for k in keys:
		var p: Object = provs[k]
		if p == null or bool(p.get("is_sea")):
			continue
		parts.append("%d:%s" % [int(k), str(p.get("owner_tag")).strip_edges().to_upper()])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update("\n".join(parts).to_utf8_buffer())
	return ctx.finish().hex_encode()
