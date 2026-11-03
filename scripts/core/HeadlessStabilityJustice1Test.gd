extends SceneTree

## STABILITY-JUSTICE-1. Flag default off. Player stability and a 30-day
## justification on the shipped apply_war_goal_justify / apply_war_goal_execute path.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessStabilityJustice1Test.gd

const OFF_SEED := "20fe9063de285f19d4f9b8a105abfd31"
const PID := 710739

var _failures: int = 0
var _sj: GDScript


func _init() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessStabilityJustice1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessStabilityJustice1Test: ", msg)


func _run() -> void:
	_sj = load("res://scripts/core/StabilityJusticeDomain.gd") as GDScript
	var gd := root.get_node_or_null("GameData")
	if gd == null or _sj == null:
		_fail("GameData or StabilityJusticeDomain missing")
		_finish()
		return
	_test_accessor(gd)
	_test_flag_off(gd)
	_test_flag_on(gd)
	_test_save_roundtrip(gd)
	_test_drift_clamp(gd)
	_test_chip_one_decimal(gd)
	_test_offered_target_and_declare_warning(gd)
	_test_chip_refreshes_on_load(gd)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessStabilityJustice1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessStabilityJustice1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _test_accessor(gd: Node) -> void:
	for bad in ["", "0", "true", "yes", "on", "TRUE"]:
		OS.set_environment("EOA_STABILITY_JUSTICE", bad)
		if bool(gd.call("stability_justice_enabled")):
			_fail("flag on for value '%s'" % bad)
			return
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	if not bool(gd.call("stability_justice_enabled")):
		_fail("flag stayed off for EOA_STABILITY_JUSTICE=1")
		return
	_pass("accessor is on only for EOA_STABILITY_JUSTICE=1")


func _test_flag_off(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "")
	_sj.call("clear_state")
	if bool(gd.call("stability_justice_enabled")):
		_fail("flag off check left the accessor on")
		return
	gd.call("apply_war_goal_justify", PID)
	gd.call("apply_war_goal_execute", PID)
	gd.call("stability_justice_tick_day")
	if bool(_sj.call("has_state")) or bool(gd.peace_state.has("stability_justice")):
		_fail("flag off created stability state")
		return
	var save: Dictionary = gd.call("get_save_data")
	if save.has("stability_justice"):
		_fail("flag off save gained stability_justice")
		return
	if str(gd.call("stability_justice_chip_line")) != "":
		_fail("flag off chip line is not empty")
		return
	if not is_equal_approx(float(gd.call("stability_justice_output_multiplier", "GER")), 1.0):
		_fail("flag off production multiplier is not 1")
		return
	var scale: Dictionary = gd.call("stability_justice_supply_scale")
	if bool(scale.get("apply", false)):
		_fail("flag off supply scale applied")
		return
	var seed_line := str(_sj.get("OFF_SEED_BASELINE"))
	print("HeadlessStabilityJustice1Test: seed_line=%s" % seed_line)
	if seed_line != OFF_SEED:
		_fail("seed line %s != OFF baseline %s" % [seed_line, OFF_SEED])
		return
	_pass("flag off: no stability state, seed line %s" % seed_line)


func _test_flag_on(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	var started: Dictionary = gd.call("apply_war_goal_justify", PID)
	if int(started.get("justify_days_done", -1)) != 1 or bool(started.get("justify_complete", true)):
		_fail("justify start days=%s complete=%s" % [str(started.get("justify_days_done")), str(started.get("justify_complete"))])
		return
	if "1/30" not in str(started.get("summary", "")):
		_fail("justify summary missing progress: %s" % str(started.get("summary", "")))
		return
	for _i in range(29):
		gd.call("stability_justice_tick_day")
	var just: Dictionary = _sj.call("justify_status")
	if int(just.get("days_done", -1)) != 30 or not bool(just.get("complete", false)):
		_fail("justify did not complete: %s" % str(just))
		return
	var before := float(_sj.call("stability"))
	var declared: Dictionary = gd.call("apply_war_goal_execute", PID)
	var after := float(_sj.call("stability"))
	if not is_equal_approx(after, before) or bool(declared.get("stability_penalized", true)):
		_fail("justified declare changed stability %s -> %s penalized=%s" % [before, after, str(declared.get("stability_penalized"))])
		return
	_pass("justify completes in 30 days and a justified declare is free")

	_sj.call("clear_state")
	var unjust: Dictionary = gd.call("apply_war_goal_execute", PID)
	var dropped := float(_sj.call("stability"))
	if not is_equal_approx(dropped, 0.85) or not bool(unjust.get("stability_penalized", false)):
		_fail("unjustified declare stability=%s penalized=%s" % [dropped, str(unjust.get("stability_penalized"))])
		return
	_pass("unjustified declare costs 0.15 stability")

	_sj.call("import_save_blob", {"stability": 0.0, "justify": {"active": false}})
	var player := str(_sj.call("player_tag"))
	if not is_equal_approx(float(gd.call("stability_justice_output_multiplier", player)), 0.75):
		_fail("stability 0 multiplier %s" % str(gd.call("stability_justice_output_multiplier", player)))
		return
	if not is_equal_approx(float(gd.call("stability_justice_output_multiplier", "FRA")), 1.0):
		_fail("non-player multiplier changed")
		return
	_sj.call("import_save_blob", {"stability": 0.5, "justify": {"active": false}})
	if not is_equal_approx(float(_sj.call("output_multiplier_for_tag", player)), 1.0):
		_fail("stability 0.5 should not slow production")
		return
	_sj.call("import_save_blob", {"stability": 0.25, "justify": {"active": false}})
	if not is_equal_approx(float(_sj.call("output_multiplier_for_tag", player)), 0.875):
		_fail("stability 0.25 multiplier %s" % str(_sj.call("output_multiplier_for_tag", player)))
		return
	var low: Dictionary = gd.call("stability_justice_supply_scale")
	if not bool(low.get("apply", false)) or not is_equal_approx(float(low.get("multiplier", 0.0)), 0.875):
		_fail("supply scale at 0.25: %s" % str(low))
		return
	var chip := str(gd.call("stability_justice_chip_line"))
	if not chip.begins_with("Stability "):
		_fail("chip line missing: %s" % chip)
		return
	_pass("low-stability multiplier and chip line")


func _test_save_roundtrip(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	gd.peace_state["occupation_province"] = {
		"1": {"resistance_level": 1.0},
	}
	gd.call("apply_war_goal_justify", PID)
	for _i in range(9):
		gd.call("stability_justice_tick_day")
	var expect_stab := float(_sj.call("stability"))
	var expect_days := int((_sj.call("justify_status") as Dictionary).get("days_done", -1))
	if expect_days != 10:
		_fail("roundtrip setup days=%d" % expect_days)
		return
	if expect_stab >= 1.0:
		_fail("occupation drift did not lower stability (%s)" % expect_stab)
		return
	var save: Dictionary = gd.call("get_save_data")
	if not (save.get("stability_justice") is Dictionary):
		_fail("flag on save missing stability_justice")
		return
	_sj.call("clear_state")
	if bool(_sj.call("has_state")):
		_fail("clear_state left stability state")
		return
	gd.call("apply_save_data", save)
	var loaded := float(_sj.call("stability"))
	var days := int((_sj.call("justify_status") as Dictionary).get("days_done", -1))
	if not is_equal_approx(loaded, expect_stab) or days != expect_days:
		_fail("roundtrip stability %s vs %s days %d vs %d" % [loaded, expect_stab, days, expect_days])
		return
	_pass("flag on save/load roundtrip stability=%.4f justify=%d/30" % [loaded, days])

	_sj.call("import_save_blob", {"stability": 0.2, "justify": {"active": true, "province_id": PID, "days_done": 4, "complete": false}})
	gd.call("apply_save_data", {"version": 1})
	if bool(_sj.call("has_state")) or not is_equal_approx(float(_sj.call("stability")), 1.0):
		_fail("pre-flag load stability=%s state=%s" % [str(_sj.call("stability")), str(_sj.call("has_state"))])
		return
	var just: Dictionary = _sj.call("justify_status")
	if bool(just.get("active", true)) or int(just.get("days_done", -1)) != 0:
		_fail("pre-flag load kept a justification %s" % str(just))
		return
	var partial := {"stability": 0.4}
	_sj.call("import_save_blob", partial)
	if not is_equal_approx(float(_sj.call("stability")), 0.4):
		_fail("missing justify subkey did not default")
		return
	var partial_just: Dictionary = _sj.call("justify_status")
	if bool(partial_just.get("active", true)):
		_fail("missing justify subkey started a justification")
		return
	_pass("pre-flag save loads at stability 1.0 with no justification")


func _test_drift_clamp(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	var player := str(_sj.call("player_tag"))
	gd.peace_state["campaign_wars"] = {
		"wars": {"AAA|%s" % player: {"a": "AAA", "b": player}},
		"truces": {},
		"log": [],
		"justifies": {},
		"booted": true,
	}
	gd.peace_state["occupation_province"] = {
		"9": {"resistance_level": 1.0},
	}
	gd.call("apply_war_goal_execute", 1)
	var guard := 0
	while float(_sj.call("stability")) > 0.0 and guard < 800:
		gd.call("stability_justice_tick_day")
		guard += 1
	if not is_equal_approx(float(_sj.call("stability")), 0.0):
		_fail("drift did not clamp at 0 after %d ticks (stability=%s)" % [guard, str(_sj.call("stability"))])
		return
	gd.call("stability_justice_tick_day")
	if float(_sj.call("stability")) < 0.0:
		_fail("stability went below 0")
		return
	gd.peace_state["campaign_wars"] = {
		"wars": {},
		"truces": {},
		"log": [],
		"justifies": {},
		"booted": true,
	}
	gd.peace_state["occupation_province"] = {}
	guard = 0
	while float(_sj.call("stability")) < 1.0 and guard < 2000:
		gd.call("stability_justice_tick_day")
		guard += 1
	if not is_equal_approx(float(_sj.call("stability")), 1.0):
		_fail("recovery did not clamp at 1 after %d ticks (stability=%s)" % [guard, str(_sj.call("stability"))])
		return
	gd.call("stability_justice_tick_day")
	if float(_sj.call("stability")) > 1.0:
		_fail("stability went above 1")
		return
	_pass("drift stays clamped to 0..1")


const _UNJUST_WARN := "Unjustified: −15% stability"


func _test_chip_one_decimal(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	_sj.call("import_save_blob", {"stability": 0.998, "justify": {"active": false}})
	var line := str(gd.call("stability_justice_chip_line"))
	if line != "Stability 99.8%":
		_fail("chip one decimal want Stability 99.8%% got %s" % line)
		return
	_sj.call("import_save_blob", {"stability": 1.0, "justify": {"active": false}})
	var full := str(gd.call("stability_justice_chip_line"))
	if full != "Stability 100.0%":
		_fail("chip one decimal at full want Stability 100.0%% got %s" % full)
		return
	_pass("chip shows one decimal (Stability 99.8%)")


func _test_offered_target_and_declare_warning(gd: Node) -> void:
	## Germany 1936, flag on. The NEXT chip is painted while the seat is still
	## USA ("Justify war on Japan"). The seat then becomes Germany and the
	## player clicks that chip. The offered country, the justify, and the later
	## declare must all be Japan. Before the 30-day stability justify finishes,
	## the Declare chip names the stability cost.
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_CALENDAR_AUTOSAVE", "0")
	var mm := root.get_node_or_null("MapManager")
	var sm := root.get_node_or_null("SupplyManager")
	var lm := root.get_node_or_null("LeaderManager")
	var sp := root.get_node_or_null("SessionPlayers")
	var tm := root.get_node_or_null("TimeManager")
	var boot: GDScript = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	var hook: GDScript = load("res://scripts/ui/PlayNextHook.gd") as GDScript
	var war: GDScript = load("res://scripts/core/WarStateDomain.gd") as GDScript
	if mm == null or boot == null or hook == null or war == null or lm == null:
		_fail("target agreement missing map, hook, or war domain")
		return
	if tm != null and "scenario_start_year" in tm:
		tm.scenario_start_year = 1936
	if tm != null and "total_days_elapsed" in tm:
		tm.total_days_elapsed = 0
	if not bool(boot.call("boot", mm, sm, "GER")):
		_fail("target agreement map boot failed")
		return
	war.call("reset_for_test")
	war.call("clear_rule_overrides")
	_sj.call("clear_state")
	if not lm.has_method("set_player_country_tag"):
		_fail("LeaderManager.set_player_country_tag missing")
		return
	lm.call("set_player_country_tag", "USA")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "USA")
	var mr := _make_map_renderer()
	if mr == null:
		_fail("MapRenderer missing for the NEXT chip")
		return
	mr.call("_refresh_next_hook_chip")
	var chip := _next_chip(mr)
	if chip == null:
		_fail("PlayNextHookChip was not built")
		return
	var offered := chip.text
	if "Japan" not in offered:
		_fail("offered NEXT text was not Japan: %s" % offered)
		return
	lm.call("set_player_country_tag", "GER")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "GER")
	chip.pressed.emit()
	var just: Dictionary = _sj.call("justify_status")
	var jowner := _owner_of(mm, int(just.get("province_id", 0)))
	var defenders := _player_justify_defenders(gd, "GER")
	if jowner != "JAP" or not defenders.has("JAP") or defenders.has("FRA"):
		_fail("offered Japan justified owner=%s defenders=%s chip='%s'" % [jowner, str(defenders), offered])
		return
	if tm != null and "total_days_elapsed" in tm:
		tm.total_days_elapsed = 14
	var decl: Dictionary = hook.call("recommend", "GER")
	var downer := _owner_of(mm, int(decl.get("to_id", -1)))
	var shown := "%s\n%s" % [str(decl.get("label", "")), str(decl.get("hint", ""))]
	if downer != "JAP" or "Japan" not in str(decl.get("label", "")):
		_fail("declare target owner=%s label=%s (offered JAP, justified JAP)" % [downer, str(decl.get("label", ""))])
		return
	if _UNJUST_WARN not in shown:
		_fail("declare chip missing stability warning: %s" % shown)
		return
	var applied: Dictionary = hook.call("apply", decl)
	if not _war_pair(gd, "GER", "JAP"):
		_fail("declare did not open GER-JAP apply=%s wars=%s" % [str(applied), _wars_text(gd)])
		return
	if _war_pair(gd, "GER", "FRA"):
		_fail("declare also opened France")
		return
	_pass("offered Japan == justify Japan == declare Japan")
	_pass("declare warns '%s' before the 30-day justify completes" % _UNJUST_WARN)
	if is_instance_valid(mr):
		mr.queue_free()


func _test_chip_refreshes_on_load(gd: Node) -> void:
	OS.set_environment("EOA_STABILITY_JUSTICE", "1")
	_sj.call("clear_state")
	_sj.call("import_save_blob", {"stability": 1.0, "justify": {"active": false}})
	var mr := _make_map_renderer()
	if mr == null:
		_fail("MapRenderer missing for load refresh")
		return
	mr.call("_refresh_next_hook_chip")
	var chip := _next_chip(mr)
	if chip == null:
		_fail("chip missing before load")
		return
	if "100.0%" not in chip.text and "100%" not in chip.text:
		_fail("chip paint missing stability: %s" % chip.text)
		return
	_sj.call("import_save_blob", {"stability": 0.998, "justify": {"active": false}})
	if "99.8%" in chip.text:
		_fail("chip changed before load_completed: %s" % chip.text)
		return
	var slm := root.get_node_or_null("SaveLoadManager")
	if slm == null or not slm.has_signal("load_completed"):
		_fail("SaveLoadManager.load_completed missing")
		return
	slm.emit_signal("load_completed", "sj1_headless")
	if "99.8%" not in chip.text:
		_fail("chip did not refresh on load_completed: %s" % chip.text)
		return
	_pass("stability chip refreshes on load_completed")
	if is_instance_valid(mr):
		mr.queue_free()


func _make_map_renderer() -> Node:
	var scr: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if scr == null:
		return null
	var mr := scr.new() as Node
	if mr == null:
		return null
	var ui := CanvasLayer.new()
	ui.name = "UI"
	mr.add_child(ui)
	var info := Panel.new()
	info.name = "InfoPanel"
	var close := Button.new()
	close.name = "BtnClose"
	info.add_child(close)
	ui.add_child(info)
	if "info_panel" in mr:
		mr.set("info_panel", info)
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	mr.add_child(container)
	if "container" in mr:
		mr.set("container", container)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	mr.add_child(cam)
	root.add_child(mr)
	return mr


func _next_chip(mr: Node) -> Button:
	var ui := mr.get_node_or_null("UI")
	if ui == null:
		return null
	return ui.get_node_or_null("PlayNextHookChip") as Button


func _owner_of(mm: Node, pid: int) -> String:
	if pid <= 0 or mm == null or not mm.has_method("get_province"):
		return ""
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _player_justify_defenders(gd: Node, attacker: String) -> Array:
	var out: Array = []
	var cw: Variant = gd.peace_state.get("campaign_wars", {})
	if not (cw is Dictionary):
		return out
	var just: Variant = (cw as Dictionary).get("justifies", {})
	if not (just is Dictionary):
		return out
	var want := attacker.strip_edges().to_upper()
	for k in (just as Dictionary).keys():
		var row_v: Variant = (just as Dictionary)[k]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		if str(row.get("attacker", "")).strip_edges().to_upper() != want:
			continue
		out.append(str(row.get("defender", "")).strip_edges().to_upper())
	return out


func _war_pair(gd: Node, a: String, b: String) -> bool:
	var cw: Variant = gd.peace_state.get("campaign_wars", {})
	if not (cw is Dictionary):
		return false
	var wars: Variant = (cw as Dictionary).get("wars", {})
	if not (wars is Dictionary):
		return false
	var aa := a.strip_edges().to_upper()
	var bb := b.strip_edges().to_upper()
	for k in (wars as Dictionary).keys():
		var row_v: Variant = (wars as Dictionary)[k]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var x := str(row.get("a", "")).strip_edges().to_upper()
		var y := str(row.get("b", "")).strip_edges().to_upper()
		if (x == aa and y == bb) or (x == bb and y == aa):
			return true
		var atk := str(row.get("attacker", "")).strip_edges().to_upper()
		var dfn := str(row.get("defender", "")).strip_edges().to_upper()
		if (atk == aa and dfn == bb) or (atk == bb and dfn == aa):
			return true
	return false


func _wars_text(gd: Node) -> String:
	var cw: Variant = gd.peace_state.get("campaign_wars", {})
	if not (cw is Dictionary):
		return ""
	return str((cw as Dictionary).get("wars", {}))
