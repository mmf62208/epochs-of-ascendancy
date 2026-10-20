extends SceneTree

## CL1 polish before beta. One world_accurate boot, named cases.
## Cases 1–6 fail on the pre-fix campaign loop and pass after.
## Case 7 reports whether a diplomatic declare spawns a German air wing.
## Case 8 reports live factory share against the economy layer.

const LUX_CAPITAL := 710977
const CZE_CAPITAL := 710146

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _chrome: GDScript
var _next: GDScript
var _peace: GDScript
var _mm: Node
var _tm: Node
var _lm: Node


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	call_deferred("_start")


func _start() -> void:
	await _run()
	var ok := _failures == 0
	print("HeadlessCl1PolishTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCl1PolishTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _fail(case: String, msg: String) -> void:
	_failures += 1
	print("CL1_POLISH case=%s FAIL %s" % [case, msg])


func _pass(case: String, msg: String) -> void:
	print("CL1_POLISH case=%s PASS %s" % [case, msg])


func _run() -> void:
	_mm = get_root().get_node_or_null("MapManager")
	_tm = get_root().get_node_or_null("TimeManager")
	_lm = get_root().get_node_or_null("LeaderManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	_end = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	_chrome = load("res://scripts/ui/CampaignWarChrome.gd") as GDScript
	_next = load("res://scripts/ui/PlayNextHook.gd") as GDScript
	_peace = load("res://scripts/ui/PeaceConferenceWindow.gd") as GDScript
	if _mm == null or _tm == null or _boot == null or _war == null or _cap == null or _end == null:
		_fail("boot", "autoloads or scripts missing")
		return
	if not _boot.boot(_mm, sm, "GER"):
		_fail("boot", "board boot failed")
		return
	if _lm != null and _lm.has_method("set_player_country_tag"):
		_lm.call("set_player_country_tag", "GER")
	var sp := get_root().get_node_or_null("SessionPlayers")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "GER")
	_reset_war()
	_pass("boot", "world_accurate player=GER")
	_case_factory()
	_case_names()
	_case_cas()
	_case_next()
	_case_justify()
	_case_stats()
	_case_peace_style()
	_case_keep_playing()


func _reset_war() -> void:
	_war.reset_for_test()
	_war.clear_rule_overrides()
	_cap.reset_for_test()
	_end.reset_for_test()
	if _tm != null:
		_tm.total_days_elapsed = 0
		_tm.scenario_start_year = 1936


func _owner(pid: int) -> String:
	if _mm == null or not _mm.has_method("get_province"):
		return ""
	var p: Object = _mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _border_to(src: String, dst: String) -> int:
	if _mm == null or not _mm.has_method("get_provinces_by_owner"):
		return -1
	var best := -1
	var owned: Array = _mm.call("get_provinces_by_owner", src)
	for pid_v in owned:
		var pid := int(pid_v)
		var nbrs: Array = _mm.call("get_adjacent_provinces", pid, true)
		for nid_v in nbrs:
			var n: Object = _mm.call("get_province", int(nid_v))
			if n == null or bool(n.get("is_sea")):
				continue
			if str(n.get("owner_tag")).strip_edges().to_upper() != dst:
				continue
			var nid := int(nid_v)
			if best < 0 or nid < best:
				best = nid
	return best


func _gd():
	return get_root().get_node_or_null("GameData")


func _pending() -> Dictionary:
	var gd = _gd()
	if gd == null:
		return {}
	var raw: Variant = gd.peace_state.get("campaign_capitulation", {})
	if not (raw is Dictionary):
		return {}
	var pending: Variant = (raw as Dictionary).get("pending_sheet", {})
	return pending if pending is Dictionary else {}


func _case_factory() -> void:
	var case := "factory"
	var applied := int(_cap.apply_economy_factories_to_map())
	var mismatch := 0
	var land := 0
	var walk_world := 0.0
	var walk_ger := 0.0
	var provs: Dictionary = _mm.get("_provinces")
	var keys: Array = provs.keys()
	keys.sort()
	for pid_v in keys:
		var p: Object = provs[pid_v]
		if p == null or bool(p.get("is_sea")):
			continue
		land += 1
		var fac := int(_cap.economy_factories(int(pid_v)))
		if int(p.get("factories")) != fac:
			mismatch += 1
		var ctrl := str(p.get("controller_tag")).strip_edges().to_upper()
		if ctrl.is_empty():
			ctrl = str(p.get("owner_tag")).strip_edges().to_upper()
		walk_world += float(fac)
		if ctrl == "GER":
			walk_ger += float(fac)
	var live := float(_end.factory_share("GER"))
	var walk := walk_ger / walk_world if walk_world > 0.0 else 0.0
	print(
		"FACTORY_SHARE live_pct=%.4f walk_pct=%.4f ger=%.0f world=%.0f land=%d mismatch=%d applied=%d"
		% [live * 100.0, walk * 100.0, walk_ger, walk_world, land, mismatch, applied]
	)
	if mismatch != 0:
		_fail(case, "economy layer disagrees with live factories mismatch=%d" % mismatch)
		return
	if absf(live - walk) > 0.0000001:
		_fail(case, "factory_share %.6f != economy walk %.6f" % [live, walk])
		return
	_pass(case, "live share matches economy layer on the same land provinces")


func _case_names() -> void:
	var case := "names"
	var cze := str(_war.tag_name("CZE"))
	var lux := str(_war.tag_name("LUX"))
	var eng := str(_war.tag_name("ENG"))
	var pol := str(_war.tag_name("POL"))
	if cze != "Czechoslovakia":
		_fail(case, "tag_name CZE got %s" % cze)
	elif lux != "Luxembourg":
		_fail(case, "tag_name LUX got %s" % lux)
	elif eng != "Britain":
		_fail(case, "tag_name ENG got %s (rules name must win)" % eng)
	elif pol != "Poland":
		_fail(case, "tag_name POL got %s" % pol)
	else:
		_pass(case, "Czechoslovakia Luxembourg Britain Poland")
	if _owner(CZE_CAPITAL) != "CZE":
		_fail(case, "CZE capital %d owner %s" % [CZE_CAPITAL, _owner(CZE_CAPITAL)])
	else:
		var dip: Dictionary = _next.living_diplomacy_from_province(CZE_CAPITAL, "GER", false)
		var sentence := str(dip.get("sentence", ""))
		if sentence.find("Czechoslovakia") < 0 or sentence.find("CZE") >= 0:
			_fail(case, "influence sentence got %s" % sentence)
		else:
			_pass(case, "influence %s" % sentence)
	_war.declare_war("GER", "CZE", "player")
	_war.declare_war("GER", "POL", "player")
	_war.declare_war("GER", "FRA", "player")
	var line := str(_war.player_enemies_line())
	if line.find("Czechoslovakia") < 0 or line.find("CZE") >= 0:
		_fail(case, "enemies line got %s" % line)
	else:
		_pass(case, "enemies %s" % line)
	_reset_war()


func _air_count() -> int:
	if _lm == null:
		return 0
	var forms_v: Variant = _lm.get("formations")
	if not (forms_v is Dictionary):
		return 0
	var n := 0
	var forms: Dictionary = forms_v
	for fid_v in forms.keys():
		var f: Object = forms[fid_v]
		if f == null:
			continue
		var tag := str(f.get("country_tag")).strip_edges().to_upper()
		if tag != "GER":
			continue
		var ft := str(f.get("formation_type"))
		if ft in ["air_wing", "air_squadron", "air_group"]:
			n += 1
	return n


func _case_cas() -> void:
	var case := "cas"
	_reset_war()
	var before := _air_count()
	var declared: Dictionary = _war.declare_war("GER", "POL", "player")
	var after := _air_count()
	print(
		"CAS_DECLARE_DELTA before=%d after=%d delta=%d declare_ok=%s"
		% [before, after, after - before, str(bool(declared.get("ok", false)))]
	)
	if after != before:
		_fail(case, "diplomatic declare changed GER air wings %d -> %d" % [before, after])
	else:
		_pass(case, "declare did not spawn an air wing")
	_reset_war()


func _stripped_rank() -> Dictionary:
	var facts: Dictionary = _next._gather_facts("GER")
	var stripped := {
		"research_days_left": 99.0,
		"focus_days_left": 99.0,
		"steel_stock": 99.0,
		"war_goal_pid": int(facts.get("war_goal_pid", -1)),
		"war_goal_tag": str(facts.get("war_goal_tag", "")),
		"war_justified": bool(facts.get("war_justified", false)),
		"war_declared": bool(facts.get("war_declared", false)),
	}
	var rec: Dictionary = _next.rank_from_snapshot(stripped)
	rec["war_goal_tag"] = str(facts.get("war_goal_tag", ""))
	rec["war_justified"] = bool(facts.get("war_justified", false))
	rec["war_declared"] = bool(facts.get("war_declared", false))
	rec["war_goal_pid"] = int(facts.get("war_goal_pid", -1))
	return rec


func _case_next() -> void:
	var case := "next"
	_reset_war()
	var idle: Dictionary = _war.suggest_player_target()
	var idle_tag := str(idle.get("tag", ""))
	var neighbours: Array = _war.land_neighbours("GER")
	if idle_tag.is_empty() or not neighbours.has(idle_tag) or _war.is_at_war("GER", idle_tag):
		_fail(case, "idle suggestion %s is not a valid neighbour" % idle_tag)
	else:
		_pass(case, "idle suggestion %s is a valid neighbour" % idle_tag)
	var pol_pid := _border_to("GER", "POL")
	if pol_pid <= 0:
		_fail(case, "no GER–POL border")
		return
	var started: Dictionary = _war.begin_player_justify_from_province(pol_pid)
	if not bool(started.get("ok", false)):
		_fail(case, "justify POL failed %s" % str(started))
		return
	_tm.total_days_elapsed = 0
	var pending: Dictionary = _stripped_rank()
	var pending_label := str(pending.get("label", ""))
	if str(pending.get("war_goal_tag", "")) != "POL" or bool(pending.get("war_justified", true)):
		_fail(case, "in-progress facts want POL unjustified got %s" % str(pending))
	elif str(pending.get("action", "")) != "justify" or pending_label.find("Poland") < 0 or pending_label.find("France") >= 0:
		_fail(case, "in-progress NEXT want Justify Poland got %s" % pending_label)
	else:
		_pass(case, "in-progress NEXT %s" % pending_label)
	_tm.total_days_elapsed = 14
	var ready: Dictionary = _stripped_rank()
	var ready_label := str(ready.get("label", ""))
	if str(ready.get("war_goal_tag", "")) != "POL" or not bool(ready.get("war_justified", false)):
		_fail(case, "ready facts want POL justified got %s" % str(ready))
	elif str(ready.get("action", "")) != "declare" or ready_label.find("Poland") < 0 or ready_label.find("France") >= 0:
		_fail(case, "ready NEXT want Declare Poland got %s" % ready_label)
	else:
		_pass(case, "ready NEXT %s" % ready_label)
	_reset_war()


func _mount_pair(pol_pid: int, fra_pid: int) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "Cl1PolishJustify"
	root.add_child(layer)
	var host_pol := Panel.new()
	host_pol.name = "HostPol"
	var host_fra := Panel.new()
	host_fra.name = "HostFra"
	layer.add_child(host_pol)
	layer.add_child(host_fra)
	_chrome.mount(host_pol, _mm.call("get_province", pol_pid))
	_chrome.mount(host_fra, _mm.call("get_province", fra_pid))
	return {
		"layer": layer,
		"pol": host_pol.get_node_or_null("BtnDeclareWar"),
		"fra": host_fra.get_node_or_null("BtnDeclareWar"),
	}


func _case_justify() -> void:
	var case := "justify"
	_reset_war()
	var pol_pid := _border_to("GER", "POL")
	var fra_pid := _border_to("GER", "FRA")
	if pol_pid <= 0 or fra_pid <= 0:
		_fail(case, "borders POL=%d FRA=%d" % [pol_pid, fra_pid])
		return
	var started: Dictionary = _war.begin_player_justify_from_province(pol_pid)
	if not bool(started.get("ok", false)):
		_fail(case, "justify start %s" % str(started))
		return
	_tm.total_days_elapsed = 0
	var ui: Dictionary = _mount_pair(pol_pid, fra_pid)
	var pol: Button = ui.get("pol") as Button
	var fra: Button = ui.get("fra") as Button
	if pol == null or fra == null:
		_fail(case, "buttons missing")
		return
	if pol.text != "Justifying Poland — 14 days left" or not pol.disabled:
		_fail(case, "in-progress text got %s disabled=%s" % [pol.text, str(pol.disabled)])
	elif pol.text.find("1 days") >= 0:
		_fail(case, "bad plural %s" % pol.text)
	else:
		_pass(case, "in-progress %s" % pol.text)
	if fra.disabled or fra.text != "Justify war on France":
		_fail(case, "second justify must stay available got %s disabled=%s" % [fra.text, str(fra.disabled)])
	else:
		_pass(case, "France still %s" % fra.text)
	_tm.total_days_elapsed = 13
	if _tm.has_signal("game_day_advanced"):
		_tm.game_day_advanced.emit(1936, 1, 14)
	if pol.text != "Justifying Poland — 1 day left" or pol.text.find("1 days") >= 0:
		_fail(case, "live countdown got %s" % pol.text)
	else:
		_pass(case, "live countdown %s" % pol.text)
	_tm.total_days_elapsed = 14
	if _tm.has_signal("game_day_advanced"):
		_tm.game_day_advanced.emit(1936, 1, 15)
	if pol.text.find("Declare war on Poland") < 0 or pol.disabled:
		_fail(case, "ready POL got %s disabled=%s" % [pol.text, str(pol.disabled)])
	else:
		_pass(case, "ready POL %s" % pol.text)
	var tip := str(fra.tooltip_text)
	if fra.text != "Justify unavailable" or not fra.disabled or fra.text.find("Declare") >= 0:
		_fail(case, "other nation got %s disabled=%s" % [fra.text, str(fra.disabled)])
	elif fra.text.find("days") >= 0:
		_fail(case, "other nation still looks like a countdown %s" % fra.text)
	elif tip.find("Poland") < 0 or tip.find("not a countdown") < 0:
		_fail(case, "tooltip got %s" % tip)
	else:
		_pass(case, "other nation %s tip=%s" % [fra.text, tip])
	var layer: Node = ui.get("layer")
	if layer != null and is_instance_valid(layer):
		layer.queue_free()
	_reset_war()


func _case_stats() -> void:
	var case := "stats"
	_reset_war()
	_gd().peace_state["campaign_capitulation"] = {
		"capitulated": {
			"POL": {"tag": "POL", "enemies": ["GER"]},
			"LUX": {"tag": "LUX", "enemies": ["GER"]},
			"FRA": {"tag": "FRA", "enemies": ["GER"]},
		},
		"start_owned": {"GER": []},
	}
	var stats: Dictionary = _end._stats("GER")
	if int(stats.get("capitulated_by_side", -1)) != 3:
		_fail(case, "capitulated_by_side want 3 got %s" % str(stats.get("capitulated_by_side", null)))
	var screen = load("res://scripts/ui/CampaignEndScreen.gd").new()
	screen._model = {"stats": stats}
	var line := str(screen._stats_line())
	print("STATS_LINE %s" % line)
	if line.find("controlled") < 0:
		_fail(case, "stats dropped controlled: %s" % line)
	elif line.find("Majors defeated 1") < 0 or line.find("Minors capitulated 2") < 0:
		_fail(case, "stats do not label majors and minors: %s" % line)
	elif line.find("3 nations") >= 0:
		_fail(case, "stats still lump majors and minors: %s" % line)
	else:
		_pass(case, line)
	screen.free()
	_reset_war()


func _case_peace_style() -> void:
	var case := "peace_style"
	_reset_war()
	for n in get_nodes_in_group("campaign_peace_sheet"):
		if is_instance_valid(n):
			n.queue_free()
	var sheet: Dictionary = _peace.open_living_sheet("GER", "LUX", LUX_CAPITAL, {"outcome_default": "annex_all"})
	var title := str(sheet.get("title", ""))
	if title != "Peace with Luxembourg":
		_fail(case, "sheet title got %s" % title)
	var layers := get_nodes_in_group("campaign_peace_sheet")
	if layers.is_empty():
		_fail(case, "peace sheet layer missing")
		return
	var panel := (layers[0] as Node).get_node_or_null("PeacePanel") as Panel
	var title_lbl: Label = null
	var annex: Button = null
	var style: StyleBox = null
	if panel != null:
		title_lbl = panel.get_node_or_null("Title") as Label
		annex = panel.get_node_or_null("BtnAnnexAll") as Button
		style = panel.get_theme_stylebox("panel")
	var border := Color(1, 1, 0, 1)
	if style is StyleBoxFlat:
		border = (style as StyleBoxFlat).border_color
	if title_lbl == null or title_lbl.text != "Peace with Luxembourg":
		_fail(case, "label got %s" % (title_lbl.text if title_lbl != null else "null"))
	elif not (style is StyleBoxFlat) or border.b <= border.r:
		_fail(case, "panel border rgb=(%.2f,%.2f,%.2f) is not the inspector cyan" % [border.r, border.g, border.b])
	elif annex == null or annex.action_mode != BaseButton.ACTION_MODE_BUTTON_PRESS:
		_fail(case, "annex button press mode missing")
	else:
		_pass(case, "Peace with Luxembourg border b=%.2f r=%.2f" % [border.b, border.r])
	for n in get_nodes_in_group("campaign_peace_sheet"):
		if is_instance_valid(n):
			n.queue_free()
	_reset_war()


func _case_keep_playing() -> void:
	var case := "keep"
	_reset_war()
	var fra_pid := _border_to("GER", "FRA")
	if fra_pid <= 0 or _owner(LUX_CAPITAL) != "LUX" or _owner(fra_pid) != "FRA":
		_fail(case, "owners FRA pid %d=%s LUX=%s" % [fra_pid, _owner(fra_pid), _owner(LUX_CAPITAL)])
		return
	var gd = _gd()
	gd.peace_state["peace_settlements"] = []
	gd.peace_state["peace_last_settlement"] = {}
	gd.peace_state["peace_settlement_count"] = 0
	gd.peace_state["campaign_end"] = {"outcome": "victory", "keep_playing": false}
	_cap.arm_pending_sheet("GER", "FRA", "keep_occupied")
	if _pending().is_empty():
		_fail(case, "pending sheet did not arm")
		return
	_end.set_keep_playing()
	var last: Variant = gd.peace_state.get("peace_last_settlement", {})
	var last_d: Dictionary = last if last is Dictionary else {}
	if not _pending().is_empty():
		_fail(case, "keep_occupied still pending %s" % str(_pending()))
	elif str(last_d.get("campaign_outcome", "")) != "keep_occupied" or str(last_d.get("loser_tag", "")) != "FRA":
		_fail(case, "keep_occupied settlement got %s" % str(last_d))
	elif _owner(fra_pid) != "FRA":
		_fail(case, "keep_occupied changed FRA owner to %s" % _owner(fra_pid))
	else:
		_pass(case, "keep_occupied applied, France still owns %d" % fra_pid)
	_cap.arm_pending_sheet("GER", "LUX", "annex_all")
	_end.set_keep_playing()
	last = gd.peace_state.get("peace_last_settlement", {})
	last_d = last if last is Dictionary else {}
	if not _pending().is_empty():
		_fail(case, "annex still pending %s" % str(_pending()))
	elif _owner(LUX_CAPITAL) != "GER":
		_fail(case, "annex left Luxembourg owner %s" % _owner(LUX_CAPITAL))
	elif str(last_d.get("campaign_outcome", "")) != "annex_all" or str(last_d.get("loser_tag", "")) != "LUX":
		_fail(case, "annex settlement got %s" % str(last_d))
	else:
		_pass(case, "annex_all applied, Luxembourg capital now Germany")
