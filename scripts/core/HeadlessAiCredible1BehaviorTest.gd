extends SceneTree

## AI-CREDIBLE-1 behaviour gates B1–B10, the CL1 JAP–CHI golden, and the killswitch.
## Advances the campaign clock only by writing total_days_elapsed. Declare checks
## go through _war.try_ai_declare_wars. No unseeded RNG.

var _failures := 0
var _mm: Node
var _boot: GDScript
var _lm: Node
var _tm: Node
var _pm: Node
var _tech: Node
var _rel: Node
var _war: GDScript
var _ai: GDScript
var _def: GDScript
var _econ: GDScript
var _front: GDScript
var _plan: GDScript
var _cap: GDScript
var _move: GDScript
var _notice: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_AI_CREDIBLE", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAiCredible1BehaviorTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAiCredible1BehaviorTest: ", msg)


func _run() -> void:
	_mm = get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	if _mm == null or _boot == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.boot(_mm, sm, "USA"):
		_fail("campaign boot failed")
		_finish()
		return
	_lm = root.get_node_or_null("LeaderManager")
	_tm = root.get_node_or_null("TimeManager")
	_pm = root.get_node_or_null("ProductionManager")
	_tech = root.get_node_or_null("TechnologyManager")
	_rel = root.get_node_or_null("RelationsManager")
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_ai = load("res://scripts/core/AiCredibleDomain.gd") as GDScript
	_def = load("res://scripts/core/AiDefenceDomain.gd") as GDScript
	_econ = load("res://scripts/core/AiEconomyDomain.gd") as GDScript
	_front = load("res://scripts/core/AiFrontPlanDomain.gd") as GDScript
	_plan = load("res://scripts/core/AiWarPlannerDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_move = load("res://scripts/formations/FormationMovement.gd") as GDScript
	_notice = load("res://scripts/ui/AiPeaceNotice.gd") as GDScript
	if _war == null or _ai == null or _def == null or _econ == null or _front == null or _plan == null or _cap == null:
		_fail("domain scripts failed to load")
		_finish()
		return
	_pass("boot world_accurate player=USA")
	_set_player("USA")
	_test_golden()
	_test_b3_peaceful_justify_cancel()
	_test_b1_coalition()
	_test_b2_losing_second_front()
	_test_b4_capital_defence()
	_test_b5_production()
	_test_b6_research()
	_test_b9_axis()
	_test_b10_air()
	_test_b7_peace()
	await _test_b8_player_notice()
	_test_killswitch_golden()
	_finish()


func _finish() -> void:
	OS.set_environment("EOA_AI_CREDIBLE", "1")
	var ok := _failures == 0
	print("HeadlessAiCredible1BehaviorTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAiCredible1BehaviorTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _reset() -> void:
	OS.set_environment("EOA_AI_CREDIBLE", "1")
	_war.reset_for_test()
	_war.clear_rule_overrides()
	_ai.reset_for_test()
	if _cap != null:
		_cap.reset_for_test()
	_set_clock(0)
	_clear_formations()
	if _rel != null and _rel.has_method("set_guarantee"):
		_rel.call("set_guarantee", "ENG", "POL", false)


func _set_player(tag: String) -> void:
	if _lm != null and _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", tag)


func _set_clock(day: int) -> void:
	if _tm == null:
		return
	_tm.total_days_elapsed = day
	_tm.scenario_start_year = 1936
	_tm.current_year = 1936
	_tm.current_month = 1
	_tm.current_day = 1


func _clear_formations() -> void:
	if _lm == null or not ("formations" in _lm):
		return
	var ids: Array = _lm.formations.keys()
	for id_v in ids:
		var fid := str(id_v)
		if not fid.begins_with("aic_"):
			continue
		if _move != null:
			_move.clear_march(fid)
		_lm.formations.erase(id_v)


func _make_unit(fid: String, tag: String, station: int, kind: String) -> void:
	if _lm == null:
		return
	var scr: GDScript = load("res://scripts/formations/Formation.gd") as GDScript
	if scr == null:
		return
	var f = scr.new()
	f.formation_id = fid
	f.country_tag = tag
	f.formation_type = kind
	f.design_id = "infantry_division" if kind == "division" else "fighter_wing"
	f.stationed_province_id = station
	f.strength = 1.0
	f.organization = 1.0
	f.readiness = 1.0
	f.name = "%s %s" % [tag, fid]
	_lm.formations[fid] = f


func _owns(tag: String) -> Array:
	var out: Array = []
	if _mm == null or not _mm.has_method("get_provinces_by_owner"):
		return out
	for pid_v in _mm.call("get_provinces_by_owner", tag):
		out.append(int(pid_v))
	out.sort()
	return out


func _land_neighbor(pid: int, owner: String) -> int:
	if _mm == null or not _mm.has_method("get_adjacent_provinces"):
		return -1
	for nid_v in _mm.call("get_adjacent_provinces", pid, true):
		var n = _mm.call("get_province", int(nid_v))
		if n == null or bool(n.is_sea):
			continue
		if str(n.owner_tag).strip_edges().to_upper() == owner:
			return int(nid_v)
	return -1


func _flip_one(from_tag: String, to_tag: String) -> int:
	for pid in _owns(from_tag):
		var p = _mm.call("get_province", pid)
		if p == null or bool(p.is_sea):
			continue
		if int(pid) == _def.capital_pid(from_tag):
			continue
		_mm.call("update_province_owner", pid, to_tag, to_tag, true, true)
		return int(pid)
	return -1


func _count_action(events: Array, action: String, attacker: String, defender: String) -> int:
	var n := 0
	for ev in events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = ev
		if str(row.get("action", "")) != action:
			continue
		if not attacker.is_empty() and str(row.get("attacker", "")) != attacker:
			continue
		if not defender.is_empty() and str(row.get("defender", "")) != defender:
			continue
		n += 1
	return n


func _test_golden() -> void:
	_reset()
	_set_player("GER")
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_declare_min_ratio": 0.0,
	})
	var j := false
	var d := false
	for day in range(0, 31):
		var events: Array = _war.try_ai_declare_wars(day)
		if _count_action(events, "justify", "JAP", "CHI") > 0 and day == 0:
			j = true
		if _count_action(events, "declare", "JAP", "CHI") > 0 and day == 30:
			d = true
	if j and d and _war.is_at_war("JAP", "CHI"):
		_pass("golden JAP justifies CHI day 0 and declares day 30")
	else:
		_fail("golden JAP-CHI justify=%s declare=%s at_war=%s" % [j, d, _war.is_at_war("JAP", "CHI")])


func _test_b3_peaceful_justify_cancel() -> void:
	_reset()
	_set_player("USA")
	var early_declare := 0
	for day in range(0, 180):
		var events: Array = _war.try_ai_declare_wars(day)
		early_declare += _count_action(events, "declare", "", "")
		if _war.any_war():
			early_declare += 1
			break
	if early_declare == 0:
		_pass("B3 no AI declare in the first 180 days")
	else:
		_fail("B3 declare or war before day 180 count=%d" % early_declare)
	_war.set_rule_overrides({
		"ai_declare_checks_per_day": 8,
		"ai_declare_min_ratio": 0.0,
	})
	var justified: Array = _war.try_ai_declare_wars(180)
	var n_just := _count_action(justified, "justify", "", "")
	if n_just <= 0:
		_fail("B3 day 180 produced no justify")
		return
	_pass("B3 day 180 justifies=%d" % n_just)
	_war.set_rule_overrides({
		"ai_declare_checks_per_day": 8,
		"ai_declare_min_ratio": 999.0,
	})
	_set_clock(181)
	var cancelled: Array = _war.try_ai_declare_wars(181)
	var n_cancel := _count_action(cancelled, "cancel", "", "")
	var n_decl := _count_action(cancelled, "declare", "", "")
	var still: int = _war.justify_rows().size()
	if n_cancel >= n_just and n_decl == 0 and still == 0:
		_pass("B3 stale justify cancelled before declare")
	else:
		_fail("B3 cancel=%d declare=%d remaining=%d" % [n_cancel, n_decl, still])
	_reset()
	_set_player("USA")
	_war.set_rule_overrides({
		"ai_declare_checks_per_day": 8,
		"ai_declare_min_ratio": 0.0,
	})
	var again: Array = _war.try_ai_declare_wars(180)
	var pairs: Dictionary = {}
	for ev in again:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = ev
		if str(row.get("action", "")) != "justify":
			continue
		pairs["%s>%s" % [str(row.get("attacker", "")), str(row.get("defender", ""))]] = int(row.get("ready_day", -1))
	if pairs.is_empty():
		_fail("B3 re-justify empty")
		return
	var early := 0
	for day in range(181, 210):
		var evs: Array = _war.try_ai_declare_wars(day)
		early += _count_action(evs, "declare", "", "")
	var declared: Array = _war.try_ai_declare_wars(210)
	var got := _count_action(declared, "declare", "", "")
	var gap_ok := true
	for k in pairs.keys():
		if int(pairs[k]) - 180 < 30:
			gap_ok = false
	if early == 0 and got > 0 and gap_ok:
		_pass("B3 declare waits >=30 days (ready day 210, declares=%d)" % got)
	else:
		_fail("B3 early=%d day210=%d gap_ok=%s pairs=%s" % [early, got, gap_ok, str(pairs)])


func _test_b1_coalition() -> void:
	_reset()
	_set_player("USA")
	var ger: float = _war.military_strength("GER")
	var pol: float = _war.military_strength("POL")
	var eng: float = _war.military_strength("ENG")
	var solo: float = ger / maxf(pol, 0.0001)
	var coal: float = ger / maxf(pol + eng, 0.0001)
	print("HeadlessAiCredible1BehaviorTest: B1 strength GER=%.1f POL=%.1f ENG=%.1f solo=%.3f coal=%.3f" % [ger, pol, eng, solo, coal])
	if eng <= 0.0 or solo <= coal:
		_fail("B1 strength setup solo=%.3f coal=%.3f" % [solo, coal])
		return
	var threshold: float = (solo + coal) * 0.5
	_rel.call("set_guarantee", "ENG", "POL", true)
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_declare_min_ratio": threshold,
		"ai_declare_checks_per_day": 1,
	})
	var events: Array = _war.try_ai_declare_wars(0)
	var hit := _count_action(events, "justify", "GER", "POL")
	if hit == 0:
		_pass("B1 GER does not justify guaranteed POL (threshold=%.3f)" % threshold)
	else:
		_fail("B1 GER justified POL under coalition threshold %.3f events=%s" % [threshold, str(events)])


func _test_b2_losing_second_front() -> void:
	_reset()
	_set_player("USA")
	_set_clock(200)
	var opened: Dictionary = _war.declare_war("GER", "ENG", "fixture")
	if not bool(opened.get("ok", false)):
		_fail("B2 could not open GER-ENG (%s)" % str(opened))
		return
	var ratio: float = float(_war.military_strength("GER")) / maxf(float(_war.military_strength("ENG")), 0.0001)
	print("HeadlessAiCredible1BehaviorTest: B2 GER/ENG ratio=%.3f" % ratio)
	_ai.set_tuning({
		"losing_ratio": ratio + 0.25,
		"second_front_ratio": 0.0,
	})
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_declare_min_ratio": 0.0,
		"ai_max_wars": 2,
		"ai_declare_checks_per_day": 8,
	})
	var events: Array = _war.try_ai_declare_wars(200)
	var extra := _count_action(events, "justify", "GER", "")
	if extra == 0:
		_pass("B2 GER opens no second front while losing")
	else:
		_fail("B2 GER justified a second front %s" % str(events))


func _test_b4_capital_defence() -> void:
	_reset()
	_set_player("USA")
	_set_clock(300)
	var cap: int = int(_def.capital_pid("POL"))
	print("HeadlessAiCredible1BehaviorTest: B4 POL capital=%d" % cap)
	if cap <= 0:
		_fail("B4 POL capital missing")
		return
	if _land_neighbor(cap, "GER") <= 0:
		var flipped := false
		if _mm.has_method("get_adjacent_provinces"):
			for nid_v in _mm.call("get_adjacent_provinces", cap, true):
				var n = _mm.call("get_province", int(nid_v))
				if n == null or bool(n.is_sea):
					continue
				_mm.call("update_province_owner", int(nid_v), "GER", "GER", true, true)
				flipped = true
				break
		if not flipped or _land_neighbor(cap, "GER") <= 0:
			_fail("B4 no land neighbour of POL capital to give GER")
			return
	var home := _land_neighbor(cap, "POL")
	if home <= 0:
		for pid in _owns("POL"):
			if int(pid) == cap:
				continue
			home = int(pid)
			break
	if home <= 0:
		_fail("B4 no POL station")
		return
	_make_unit("aic_pol_div", "POL", home, "division")
	var war: Dictionary = _war.declare_war("GER", "POL", "fixture")
	if not bool(war.get("ok", false)):
		_fail("B4 declare failed %s" % str(war))
		return
	if not _def.enemy_borders_capital("POL"):
		_fail("B4 enemy does not border POL capital")
		return
	var tick: Dictionary = _def.tick(300)
	var inbound := false
	if _move != null:
		for raw in _move.list_marches():
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = raw
			if str(row.get("country_tag", "")) == "POL" and int(row.get("dest_id", -1)) == cap:
				inbound = true
	var on_cap := false
	for f in _lm.call("get_formations_for_country", "POL"):
		if f != null and str(f.formation_type) == "division" and int(f.stationed_province_id) == cap:
			on_cap = true
	if (inbound or on_cap) and _ai.counter_get("capital_empty_days") == 0:
		_pass("B4 POL capital covered marches=%s" % str(tick))
	else:
		_fail("B4 inbound=%s on_cap=%s empty=%d tick=%s" % [inbound, on_cap, _ai.counter_get("capital_empty_days"), str(tick)])


func _test_b5_production() -> void:
	_reset()
	_set_player("USA")
	for day in range(0, 9):
		_set_clock(day)
		_econ.tick(day)
	if _ai.counter_get("production_idle_breaches") == 0:
		_pass("B5 no production idle breach over 9 days")
	else:
		_fail("B5 production idle breaches=%d" % _ai.counter_get("production_idle_breaches"))
	_set_clock(20)
	var before := 0
	if _pm != null and _pm.has_method("get_country_equipment_amount"):
		before = int(_pm.call("get_country_equipment_amount", "GER", "infantry_equipment"))
	_war.declare_war("GER", "POL", "fixture")
	var econ: Dictionary = _econ.tick(20)
	var bias := str(_ai.state().get("bias", {}).get("GER", ""))
	var after := before
	if _pm != null and _pm.has_method("get_country_equipment_amount"):
		after = int(_pm.call("get_country_equipment_amount", "GER", "infantry_equipment"))
	if bias == "military" and after > before:
		_pass("B5 GER at war shifts military stock %d→%d" % [before, after])
	else:
		_fail("B5 bias=%s stock %d→%d econ=%s" % [bias, before, after, str(econ)])


func _test_b6_research() -> void:
	_reset()
	_set_player("USA")
	for day in range(0, 9):
		_set_clock(day)
		_econ.tick(day)
	var idle: Array = []
	for raw in _ai.majors():
		var tag := str(raw)
		if tag == "USA":
			continue
		var live := false
		if _tech != null and _tech.has_method("get_active_research_count"):
			live = int(_tech.call("get_active_research_count", tag)) > 0
		if not live:
			idle.append(tag)
	if idle.is_empty() and _ai.counter_get("research_idle_breaches") == 0:
		_pass("B6 every non-player major has research")
	else:
		_fail("B6 idle=%s breaches=%d" % [str(idle), _ai.counter_get("research_idle_breaches")])


func _test_b9_axis() -> void:
	_reset()
	_set_player("USA")
	var first: Array = [
		{"defender_tag": "POL", "region_id": 5, "to_id": 1, "tag": "GER"},
		{"defender_tag": "POL", "region_id": 5, "to_id": 2, "tag": "GER"},
		{"defender_tag": "POL", "region_id": 5, "to_id": 3, "tag": "GER"},
		{"defender_tag": "CZE", "region_id": 9, "to_id": 4, "tag": "GER"},
	]
	var axis: Dictionary = _front.choose_axis("GER", 400, first)
	var seg := str(axis.get("segment", ""))
	if seg != "POL:5":
		_fail("B9 first axis %s" % seg)
		return
	var second: Array = [
		{"defender_tag": "POL", "region_id": 5, "to_id": 1, "tag": "GER"},
		{"defender_tag": "CZE", "region_id": 9, "to_id": 4, "tag": "GER"},
		{"defender_tag": "CZE", "region_id": 9, "to_id": 6, "tag": "GER"},
		{"defender_tag": "CZE", "region_id": 9, "to_id": 7, "tag": "GER"},
		{"defender_tag": "CZE", "region_id": 9, "to_id": 8, "tag": "GER"},
	]
	var held: Dictionary = _front.choose_axis("GER", 405, second)
	if str(held.get("segment", "")) != "POL:5":
		_fail("B9 axis moved inside the stable window to %s" % str(held.get("segment", "")))
		return
	var later: Dictionary = _front.choose_axis("GER", 420, second)
	if str(later.get("segment", "")) != "CZE:9":
		_fail("B9 axis did not refresh after the stable window (%s)" % str(later.get("segment", "")))
		return
	var pinned: Dictionary = _front.choose_axis("GER", 500, first)
	if str(pinned.get("segment", "")) != "POL:5":
		_fail("B9 could not re-pin POL:5 (%s)" % str(pinned.get("segment", "")))
		return
	for _i in range(6):
		_front.note_start("GER", "POL:5", true)
	for _j in range(2):
		_front.note_start("GER", "CZE:9", false)
	var conc: float = float(_front.concentration("GER"))
	if conc + 0.0001 >= 0.60:
		_pass("B9 axis stable 10 days and concentration=%.2f" % conc)
	else:
		_fail("B9 concentration %.2f" % conc)


func _test_b10_air() -> void:
	_reset()
	_set_player("USA")
	_set_clock(500)
	var stamped := 0
	for pid in _owns("POL"):
		var p = _mm.call("get_province", int(pid))
		if p == null or bool(p.is_sea):
			continue
		if not ("strategic_region_id" in p):
			continue
		p.strategic_region_id = 77
		stamped += 1
	var home := -1
	for pid2 in _owns("GER"):
		home = int(pid2)
		break
	if home <= 0 or stamped <= 0:
		_fail("B10 station or region stamp missing stamped=%d" % stamped)
		return
	_make_unit("aic_ger_air", "GER", home, "air_wing")
	var war: Dictionary = _war.declare_war("GER", "POL", "fixture")
	if not bool(war.get("ok", false)):
		_fail("B10 declare %s" % str(war))
		return
	var assigned := false
	for day in range(500, 508):
		_set_clock(day)
		_front.tick(day)
		var wing = _lm.call("get_formation", "aic_ger_air") if _lm != null and _lm.has_method("get_formation") else null
		if wing != null and "assigned_region_id" in wing and int(wing.assigned_region_id) == 77:
			assigned = true
			break
	var seg: String = str(_front.axis_segment("GER"))
	if assigned and seg.ends_with(":77"):
		_pass("B10 wing on axis %s" % seg)
	else:
		_fail("B10 assigned=%s seg=%s" % [assigned, seg])


func _test_b7_peace() -> void:
	_reset()
	_set_player("USA")
	_set_clock(600)
	var war: Dictionary = _war.declare_war("GER", "POL", "fixture")
	if not bool(war.get("ok", false)):
		_fail("B7 declare %s" % str(war))
		return
	_cap.ensure_snapshot()
	var pid := _flip_one("POL", "GER")
	var prog: float = float(_cap.progress("POL"))
	print("HeadlessAiCredible1BehaviorTest: B7 flipped=%d POL progress=%.4f" % [pid, prog])
	if pid <= 0 or prog <= 0.0:
		_fail("B7 progress did not move")
		return
	_ai.set_tuning({
		"peace_loss_fraction": prog * 0.5,
		"peace_goal_met_progress": prog * 0.5,
		"peace_quiet_days": 0,
	})
	var peace: Dictionary = _plan.tick_peace(600)
	if not _war.is_at_war("GER", "POL") and _war.in_truce("GER", "POL"):
		_pass("B7 losing POL accepted peace peaces=%s" % str(peace.get("peaces", 0)))
	else:
		_fail("B7 still_war=%s truce=%s peace=%s" % [_war.is_at_war("GER", "POL"), _war.in_truce("GER", "POL"), str(peace)])
		return
	var again: Dictionary = _war.declare_war("GER", "POL", "fixture")
	if bool(again.get("truce", false)) or str(again.get("reason", "")) == "truce":
		_pass("B7 truce blocks a new declare")
	else:
		_fail("B7 truce not honoured %s" % str(again))


func _test_b8_player_notice() -> void:
	_reset()
	_set_player("POL")
	_set_clock(700)
	var war: Dictionary = _war.declare_war("GER", "POL", "fixture")
	if not bool(war.get("ok", false)):
		_fail("B8 declare %s" % str(war))
		return
	_cap.ensure_snapshot()
	var pid := _flip_one("GER", "POL")
	var prog: float = float(_cap.progress("GER"))
	print("HeadlessAiCredible1BehaviorTest: B8 flipped=%d GER progress=%.4f" % [pid, prog])
	if pid <= 0 or prog <= 0.0:
		_fail("B8 GER progress did not move")
		return
	_ai.set_tuning({
		"peace_loss_fraction": prog * 0.5,
		"peace_goal_met_progress": prog * 0.5,
		"peace_quiet_days": 0,
	})
	_plan.tick_peace(700)
	var offer: Dictionary = _ai.player_offer()
	if offer.is_empty() or _war.is_at_war("GER", "POL") == false:
		_fail("B8 expected a player offer while the war continues offer=%s" % str(offer))
		return
	if root != null:
		root.size = Vector2(1280, 800)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	var catcher := MapCatcher.new()
	catcher.name = "AicMapCatcher"
	catcher.position = Vector2.ZERO
	catcher.size = Vector2(1280, 800)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(catcher)
	var notice: Node = _notice.present(root, offer)
	if notice == null:
		_fail("B8 notice did not present")
		catcher.queue_free()
		return
	var accept := notice.find_child("AcceptPeace", true, false) as Button
	if accept == null:
		_fail("B8 AcceptPeace missing")
		notice.queue_free()
		catcher.queue_free()
		return
	accept.pressed.emit()
	var notice_c := notice as Control
	if notice_c != null and notice_c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("B8 notice kept mouse_filter STOP after accept")
	await process_frame
	catcher.hits = 0
	_click_at(Vector2(24, 24))
	await process_frame
	var accepted: bool = not bool(_war.is_at_war("GER", "POL")) and bool(_war.in_truce("GER", "POL"))
	if accepted and catcher.hits >= 1:
		_pass("B8 accept ends the war and the next click is not swallowed")
	else:
		_fail("B8 accept war=%s truce=%s hits=%d" % [bool(_war.is_at_war("GER", "POL")), bool(_war.in_truce("GER", "POL")), catcher.hits])
	if is_instance_valid(notice):
		notice.queue_free()
	# Decline path. The previous peace already ended the war, so open another
	# pair the player is in: FRA (human is POL, so use a fresh GER-POL only if
	# the truce allows — it does not). SOV-POL is a new pair.
	_set_clock(701)
	var war2: Dictionary = _war.declare_war("SOV", "POL", "fixture")
	if not bool(war2.get("ok", false)):
		_fail("B8 second declare %s" % str(war2))
		catcher.queue_free()
		return
	_cap.reset_for_test()
	_cap.ensure_snapshot()
	var pid2 := _flip_one("SOV", "POL")
	var prog2: float = float(_cap.progress("SOV"))
	if pid2 <= 0 or prog2 <= 0.0:
		_fail("B8 SOV progress did not move")
		catcher.queue_free()
		return
	_ai.set_tuning({
		"peace_loss_fraction": prog2 * 0.5,
		"peace_goal_met_progress": prog2 * 0.5,
		"peace_quiet_days": 0,
	})
	_ai.clear_player_offer()
	_plan.tick_peace(701)
	var offer2: Dictionary = _ai.player_offer()
	var notice2: Node = _notice.present(root, offer2)
	var decline: Button = null
	if notice2 != null:
		decline = notice2.find_child("DeclinePeace", true, false) as Button
	if decline == null:
		_fail("B8 decline notice missing offer=%s" % str(offer2))
		catcher.queue_free()
		return
	decline.pressed.emit()
	await process_frame
	catcher.hits = 0
	_click_at(Vector2(24, 24))
	await process_frame
	var offer_left: Dictionary = _ai.player_offer()
	if bool(_war.is_at_war("SOV", "POL")) and offer_left.is_empty() and catcher.hits >= 1:
		_pass("B8 decline keeps the war and the next click is not swallowed")
	else:
		_fail("B8 decline war=%s offer=%s hits=%d" % [bool(_war.is_at_war("SOV", "POL")), str(offer_left), catcher.hits])
	if notice2 != null and is_instance_valid(notice2):
		notice2.queue_free()
	catcher.queue_free()


func _test_killswitch_golden() -> void:
	_reset()
	OS.set_environment("EOA_AI_CREDIBLE", "0")
	_set_player("GER")
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_declare_min_ratio": 0.0,
	})
	var before: String = str(_ai.trace_text())
	var j := false
	var d := false
	for day in range(0, 31):
		var events: Array = _war.try_ai_declare_wars(day)
		if _count_action(events, "justify", "JAP", "CHI") > 0 and day == 0:
			j = true
		if _count_action(events, "declare", "JAP", "CHI") > 0 and day == 30:
			d = true
	var after: String = str(_ai.trace_text())
	if j and d and after == before:
		_pass("killswitch keeps legacy JAP-CHI and writes no credible trace")
	else:
		_fail("killswitch justify=%s declare=%s trace_grew=%s" % [j, d, after != before])
	OS.set_environment("EOA_AI_CREDIBLE", "1")


func _click_at(screen_pt: Vector2) -> void:
	var vp: Viewport = root.get_viewport()
	if vp != null:
		vp.warp_mouse(screen_pt)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = screen_pt
	down.global_position = screen_pt
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(down)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = screen_pt
	up.global_position = screen_pt
	up.button_mask = 0
	Input.parse_input_event(up)
	if Input.has_method("flush_buffered_events"):
		Input.flush_buffered_events()


class MapCatcher extends Control:
	var hits := 0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
			hits += 1
			accept_event()
