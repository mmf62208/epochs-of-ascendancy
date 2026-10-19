extends SceneTree

## CL1a war gate. Peaceful 1936 start. GER–FRA and JAP–CHI only with
## EOA_SCENARIO_EARLY_WARS=1. AI golden: player GER, min_day 0, min_ratio 0
## → JAP justifies against CHI on day 0 and declares on day 30.

var _failures := 0
var _fra_from := -1
var _fra_to := -1
var _pol_from := -1
var _pol_to := -1
var _boot: GDScript
var _war: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCampaignLoop1WarGateTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCampaignLoop1WarGateTest: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	if mm == null or bm == null or _boot == null or _war == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.boot(mm, sm, "GER"):
		_fail("campaign boot failed")
		_finish()
		return
	_pass("boot world_accurate player=GER")
	_fra_from = _border_from(mm, "GER", "FRA")
	_fra_to = _border_to(mm, "GER", "FRA")
	_pol_from = _border_from(mm, "GER", "POL")
	_pol_to = _border_to(mm, "GER", "POL")
	if _fra_from <= 0 or _pol_from <= 0:
		_fail("missing GER border pair FRA=%d→%d POL=%d→%d" % [_fra_from, _fra_to, _pol_from, _pol_to])
		_finish()
		return
	_pass("borders FRA %d→%d POL %d→%d" % [_fra_from, _fra_to, _pol_from, _pol_to])
	if bool(bm.get("include_player_in_ai_land_battles")):
		_fail("include_player_in_ai_land_battles default must be false")
	else:
		_pass("autopilot default false")
	_boot.make_division("cl1_ger_fra", "GER", _fra_from)
	_boot.make_division("cl1_ger_pol", "GER", _pol_from)
	_test_peaceful(bm, mm)
	_test_ai_golden()
	_test_early_wars(bm, mm)
	_test_killswitch(bm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessCampaignLoop1WarGateTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCampaignLoop1WarGateTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _test_peaceful(bm: Node, mm: Node) -> void:
	_war.reset_for_test()
	_war.clear_rule_overrides()
	if _war.is_at_war("GER", "FRA") or _war.is_at_war("GER", "POL") or _war.is_at_war("JAP", "CHI"):
		_fail("day 0 peaceful start has a war")
	else:
		_pass("day 0 all pairs at peace")
	var pol: Dictionary = bm.can_assault_province("GER", _pol_to, _pol_from)
	if str(pol.get("reason", "")).find("Not at war") < 0:
		_fail("POL assault want Not at war got %s" % str(pol))
	else:
		_pass("POL assault refused: %s" % str(pol.get("reason", "")))
	var fra: Dictionary = bm.can_assault_province("GER", _fra_to, _fra_from)
	if str(fra.get("reason", "")).find("Not at war") < 0:
		_fail("FRA assault at peace want Not at war got %s" % str(fra))
	else:
		_pass("FRA assault refused while at peace")
	if not _targets_only_enemies(mm, "GER"):
		_fail("GER collect returned a non-enemy")
	else:
		_pass("GER collect has no non-enemy")
	if not _targets_only_enemies(mm, "SOV"):
		_fail("SOV collect returned a non-enemy")
	else:
		_pass("SOV collect has no non-enemy")


func _test_ai_golden() -> void:
	_war.reset_for_test()
	_war.set_rule_overrides({
		"ai_declare_min_day": 0,
		"ai_declare_min_ratio": 0.0,
	})
	var saw_justify := false
	var saw_declare := false
	for day in range(0, 31):
		var events: Array = _war.try_ai_declare_wars(day)
		for ev in events:
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var row: Dictionary = ev
			var action := str(row.get("action", ""))
			var att := str(row.get("attacker", ""))
			var defender := str(row.get("defender", ""))
			if day == 0 and action == "justify" and att == "JAP" and defender == "CHI":
				saw_justify = true
			if day == 30 and action == "declare" and att == "JAP" and defender == "CHI":
				saw_declare = true
		if day == 0 and _war.is_at_war("JAP", "CHI"):
			_fail("JAP–CHI declared on justify day")
	if not saw_justify:
		_fail("AI golden missing JAP justify CHI on day 0 neighbours=%s" % str(_war.land_neighbours("JAP")))
	else:
		_pass("AI JAP justifies vs CHI on day 0")
	if not saw_declare or not _war.is_at_war("JAP", "CHI"):
		_fail("AI golden missing JAP declare CHI on day 30")
	else:
		_pass("AI JAP declares on CHI on day 30")
	_war.clear_rule_overrides()


func _test_early_wars(bm: Node, mm: Node) -> void:
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "1")
	_war.reset_for_test()
	_war.reload_start_wars()
	if not _war.is_at_war("GER", "FRA") or not _war.is_at_war("JAP", "CHI"):
		_fail("early wars missing GER–FRA or JAP–CHI")
	elif _war.is_at_war("GER", "POL"):
		_fail("early wars included GER–POL")
	else:
		_pass("early wars GER–FRA and JAP–CHI only")
	var fra: Dictionary = bm.can_assault_province("GER", _fra_to, _fra_from)
	if not bool(fra.get("ok", false)):
		_fail("FRA assault with early wars failed: %s" % str(fra))
	else:
		_pass("FRA assault ok under early wars")
	if _collect_has_defender(mm, "GER", "POL"):
		_fail("GER collect included POL before declare")
	else:
		_pass("GER collect has no POL defender")
	mm.call("precompute_live_border_fronts", "GER")
	if not ("_live_fronts_precompute" in mm) or not (mm._live_fronts_precompute as Dictionary).has("GER"):
		_fail("precompute did not fill GER front cache")
	else:
		_pass("GER front cache filled")
	var rel := get_root().get_node_or_null("RelationsManager")
	if rel != null and rel.has_method("set_guarantee"):
		rel.call("set_guarantee", "ENG", "POL", true)
	var declared: Dictionary = _war.declare_war("GER", "POL", "test")
	if not bool(declared.get("ok", false)):
		_fail("declare GER–POL failed: %s" % str(declared))
	if ("_live_fronts_precompute" in mm) and (mm._live_fronts_precompute as Dictionary).has("GER"):
		_fail("declare did not erase GER front cache")
	else:
		_pass("declare erased GER front cache")
	if not _war.is_at_war("GER", "ENG"):
		_fail("ENG guarantee did not join GER–POL call-to-arms")
	else:
		_pass("ENG joined on POL guarantee")
	if not _collect_has_defender(mm, "GER", "POL"):
		_fail("POL target missing after declare")
	else:
		_pass("POL target appears after declare")
	_war.make_peace("GER", "POL", "test")
	_war.make_peace("GER", "ENG", "test")
	if _collect_has_defender(mm, "GER", "POL"):
		_fail("POL target remained after peace")
	else:
		_pass("POL target gone after peace")
	var again: Dictionary = _war.declare_war("GER", "POL", "test")
	if bool(again.get("ok", false)) or not _war.in_truce("GER", "POL"):
		_fail("truce did not block re-declare: %s" % str(again))
	else:
		_pass("truce blocks GER–POL re-declare")


func _test_killswitch(bm: Node) -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "0")
	var pol: Dictionary = bm.can_assault_province("GER", _pol_to, _pol_from)
	var reason := str(pol.get("reason", ""))
	if reason.find("Not at war") >= 0 or not bool(pol.get("ok", false)):
		_fail("killswitch POL assault not legacy-ok: %s" % str(pol))
	else:
		_pass("killswitch allows POL assault")


func _border_from(mm: Node, att: String, defender: String) -> int:
	return _border_pair(mm, att, defender).x


func _border_to(mm: Node, att: String, defender: String) -> int:
	return _border_pair(mm, att, defender).y


func _border_pair(mm: Node, att: String, defender: String) -> Vector2i:
	if not mm.has_method("get_provinces_by_owner"):
		return Vector2i(-1, -1)
	var owned: Array = mm.call("get_provinces_by_owner", att)
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
		nbrs.sort()
		for nid_v in nbrs:
			var n: Object = mm.call("get_province", int(nid_v))
			if n == null or bool(n.get("is_sea")):
				continue
			if str(n.get("owner_tag")).strip_edges().to_upper() == defender:
				return Vector2i(pid, int(nid_v))
	return Vector2i(-1, -1)


func _targets_only_enemies(mm: Node, tag: String) -> bool:
	var enemies: Dictionary = {}
	for e in _war.enemies_of(tag):
		enemies[str(e)] = true
	for row in mm.call("collect_live_border_assault_targets", tag, 8):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d := str((row as Dictionary).get("defender_tag", "")).strip_edges().to_upper()
		if d.is_empty():
			continue
		if not enemies.has(d):
			print("  [INFO] non-enemy target %s -> %s" % [tag, d])
			return false
	return true


func _collect_has_defender(mm: Node, tag: String, defender: String) -> bool:
	for row in mm.call("collect_live_border_assault_targets", tag, 12):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str((row as Dictionary).get("defender_tag", "")).strip_edges().to_upper() == defender:
			return true
	return false
