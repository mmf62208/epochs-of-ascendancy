extends SceneTree

## CL1-S1-STALL-FIX: the empty-hex siege holder must not be the rear-spare
## march. CampaignLoop1Soak S1 froze at progress 0.3763 when the spare picker
## walked the sieging division off staging on days 1–2, then
## light_capture_allowed returned "formation not at staging" on day 3.
##
## Layout uses the S1 711062/711063 pair as the empty second target:
##   F=711069 GER, X sieging T=711092 POL (F is not adjacent to 711063)
##   S=711062 GER Pilski empty staging, adjacent to F, stages T2=711063 POL
##   Y on 711070 GER, adjacent to S, not sieging (control)
## 711085 is POL-inland in 1936 and is not a GER staging hex.

const F_PID := 711069
const T_PID := 711092
const S_PID := 711062
const T2_PID := 711063
const Y_PID := 711070
const FID_X := "cl1s1_siege_x"
const FID_Y := "cl1s1_spare_y"
const DAYS := 2

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript
var _mv: Script


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_LIVE_F5_EQUIV", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessCl1SiegeHold1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessCl1SiegeHold1Test: ", msg)


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
	# Runtime load — do not name FormationMovement at parse time in a -s harness.
	_mv = load("res://scripts/formations/FormationMovement.gd") as Script
	if mm == null or sm == null or bm == null or tm == null or lm == null or _boot == null or _war == null:
		_fail("autoloads missing")
		_finish()
		return
	_test_siege_holder_not_marched(mm, sm, bm, tm, lm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessCl1SiegeHold1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessCl1SiegeHold1Test: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _test_siege_holder_not_marched(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not _boot_observer(mm, sm, bm, tm, lm):
		return
	if not _layout_ok(mm):
		_fail(
			"S1 layout F=%d T=%d S=%d T2=%d Y=%d not GER/POL/adjacent as required"
			% [F_PID, T_PID, S_PID, T2_PID, Y_PID]
		)
		return
	if bm.has_method("empty_hex_capture_days_needed"):
		var need := int(bm.call("empty_hex_capture_days_needed", T_PID))
		if need != 3:
			_fail("T=%d siege days want 3 got %d (capital/high-value?)" % [T_PID, need])
			return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("declare GER-POL failed")
		return
	if _cap != null:
		_cap.ensure_snapshot()
	_boot.make_division(FID_X, "GER", F_PID)
	_boot.make_division(FID_Y, "GER", Y_PID)
	var fx: Object = lm.call("get_formation", FID_X) if lm.has_method("get_formation") else null
	var fy: Object = lm.call("get_formation", FID_Y) if lm.has_method("get_formation") else null
	if fx == null or fy == null:
		_fail("formations not fielded")
		return
	var today := int(tm.total_days_elapsed)
	bm._empty_hex_siege = {
		"GER": {
			"to_id": T_PID,
			"from_id": F_PID,
			"fid": FID_X,
			"days": 1,
			"last_day": today,
			"need": 3,
			"ok": true,
			"captured": false,
		}
	}
	print(
		"CL1_S1_STALL_FIX setup F=%d T=%d S=%d T2=%d Y_hex=%d fid_x=%s fid_y=%s day=%d owner_T=%s"
		% [F_PID, T_PID, S_PID, T2_PID, Y_PID, FID_X, FID_Y, today, _owner(mm, T_PID)]
	)
	var x_marched := false
	var y_marched := false
	var x_left_f := false
	for d in range(DAYS):
		var row: Dictionary = {}
		if tm.has_method("advance_live_f5_equivalent_days"):
			row = tm.call("advance_live_f5_equivalent_days", 1)
		if bool(_fm("has_march", FID_X)):
			x_marched = true
		if bool(_fm("has_march", FID_Y)):
			y_marched = true
		var x_station := int(fx.get("stationed_province_id"))
		var y_station := int(fy.get("stationed_province_id"))
		if x_station != F_PID and x_station != T_PID:
			x_left_f = true
		if y_station == S_PID:
			y_marched = true
		print(
			"CL1_S1_STALL_FIX day=%d elapsed=%d x_station=%d y_station=%d has_march_x=%s has_march_y=%s owner_T=%s siege=%s adv=%s"
			% [
				d + 1,
				int(tm.total_days_elapsed),
				x_station,
				y_station,
				str(bool(_fm("has_march", FID_X))),
				str(bool(_fm("has_march", FID_Y))),
				_owner(mm, T_PID),
				str(bm._empty_hex_siege.get("GER", {})),
				str(row.get("days", -1)),
			]
		)
	var x_station_end := int(fx.get("stationed_province_id"))
	var y_station_end := int(fy.get("stationed_province_id"))
	var owner_t := _owner(mm, T_PID)
	if x_marched or bool(_fm("has_march", FID_X)):
		_fail("siege holder %s was enqueued for a rear-spare march" % FID_X)
		return
	if x_left_f:
		_fail("siege holder %s left staging F=%d station=%d (marched off the siege)" % [FID_X, F_PID, x_station_end])
		return
	if owner_t != "GER":
		_fail("GER did not capture T=%d on siege day 3 owner=%s station_x=%d" % [T_PID, owner_t, x_station_end])
		return
	if x_station_end != T_PID and x_station_end != F_PID:
		_fail("siege holder station after capture want T or F got %d" % x_station_end)
		return
	if not y_marched and y_station_end == Y_PID and not bool(_fm("has_march", FID_Y)):
		_fail("control spare %s was never marched toward S=%d (rear marches look off)" % [FID_Y, S_PID])
		return
	_pass(
		"holder %s stayed on F until capture of T=%d; control %s marched (station %d→%d)"
		% [FID_X, T_PID, FID_Y, Y_PID, y_station_end]
	)


func _boot_observer(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> bool:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	_fm("apply_save_data", {})
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_empty_hex_siege" in bm:
			bm._empty_hex_siege = {}
		if bm.has_method("reset_ai_war1_for_test"):
			bm.reset_ai_war1_for_test()
	if not _boot.boot(mm, sm, "USA"):
		_fail("boot USA failed")
		return false
	if _cap != null:
		_cap.apply_economy_factories_to_map()
		_cap.reset_for_test()
	if _war != null:
		_war.reset_for_test()
		_war.clear_rule_overrides()
	if _end != null:
		_end.call("reset_for_test")
	var sp := get_root().get_node_or_null("SessionPlayers")
	if sp != null and sp.has_method("setup_solo_play"):
		sp.call("setup_solo_play", "USA")
	_boot.set_observer("USA")
	if tm != null:
		tm.set("_live_f5_equiv_clock", false)
	return true


func _layout_ok(mm: Node) -> bool:
	if _owner(mm, F_PID) != "GER" or _owner(mm, T_PID) != "POL":
		return false
	if _owner(mm, S_PID) != "GER" or _owner(mm, T2_PID) != "POL":
		return false
	if _owner(mm, Y_PID) != "GER":
		return false
	if not _adjacent(mm, F_PID, T_PID):
		return false
	if not _adjacent(mm, F_PID, S_PID):
		return false
	if not _adjacent(mm, S_PID, T2_PID):
		return false
	if not _adjacent(mm, Y_PID, S_PID):
		return false
	# X on F must not also be an assault source for T2, or S is never empty-fid.
	if _adjacent(mm, F_PID, T2_PID):
		return false
	if S_PID == F_PID or Y_PID == F_PID:
		return false
	return true


func _owner(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _adjacent(mm: Node, a: int, b: int) -> bool:
	if not mm.has_method("get_adjacent_provinces"):
		return false
	for nid_v in mm.call("get_adjacent_provinces", a, true):
		if int(nid_v) == b:
			return true
	return false


func _fm(method: String, a: Variant = null) -> Variant:
	# Runtime load() + instance.call — do not name FormationMovement at parse
	# time in a -s harness (SupplyManager is not visible then).
	if _mv == null:
		return null
	var inst: Object = _mv.new() as Object
	if inst == null:
		return null
	if a != null:
		return inst.call(method, a)
	return inst.call(method)
