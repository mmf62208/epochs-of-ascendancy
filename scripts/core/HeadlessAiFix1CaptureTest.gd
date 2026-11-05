extends SceneTree

## SIM-1104-A: empty-hex light capture needs supply + adjacency, capitals take
## 4 contiguous days, and an uncovered capital gets a rushed garrison when an
## enemy is within 4 hops. Berlin (710300) must not fall before day 30 in a
## POL-on-border / GER-empty setup.
##
## Real-source mutant: if LIGHT_CAPTURE_CAPITAL_DAYS dropped to 1 or the
## supply/adjacency/capital-cover helpers vanished, this test fails.

const BERLIN := 710300
const WARSAW := 711112
const HOLD_DAYS := 30
const SRC_BM := "res://scripts/combat/BattleManager.gd"

var _failures := 0
var _boot: GDScript
var _war: GDScript
var _cap: GDScript
var _end: GDScript


func _init() -> void:
	OS.set_environment("EOA_CAMPAIGN_LOOP", "1")
	OS.set_environment("EOA_SCENARIO_EARLY_WARS", "0")
	OS.set_environment("EOA_LIVE_F5_EQUIV", "1")
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessAiFix1CaptureTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessAiFix1CaptureTest: ", msg)


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
	if mm == null or sm == null or bm == null or tm == null or lm == null or _boot == null:
		_fail("autoloads missing")
		_finish()
		return
	_assert_source_mutant(bm)
	if not _boot_observer(mm, sm, bm, lm):
		_finish()
		return
	_assert_helpers(bm)
	_assert_ordinary_siege(mm, bm, tm, lm)
	if not _boot_observer(mm, sm, bm, lm):
		_finish()
		return
	_assert_capital_not_instant(mm, bm, tm, lm)
	if not _boot_observer(mm, sm, bm, lm):
		_finish()
		return
	_assert_supply_and_adjacency(mm, bm, lm)
	if not _boot_observer(mm, sm, bm, lm):
		_finish()
		return
	_assert_berlin_holds_30(mm, sm, bm, tm, lm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessAiFix1CaptureTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessAiFix1CaptureTest: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _boot_observer(mm: Node, sm: Node, bm: Node, lm: Node) -> bool:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		(lm.formations as Dictionary).clear()
	if bm != null:
		bm.set("include_player_in_ai_land_battles", false)
		if "_open_land_battles" in bm:
			bm._open_land_battles = []
		if "_empty_hex_siege" in bm:
			bm._empty_hex_siege = {}
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
	return true


func _assert_source_mutant(bm: Node) -> void:
	if not FileAccess.file_exists(SRC_BM):
		_fail("BattleManager.gd missing")
		return
	var src := FileAccess.get_file_as_string(SRC_BM)
	if "LIGHT_CAPTURE_CAPITAL_DAYS" not in src:
		_fail("mutant skip_capital_siege: LIGHT_CAPTURE_CAPITAL_DAYS missing")
		return
	if "LIGHT_CAPTURE_ORDINARY_DAYS" not in src:
		_fail("mutant skip_ordinary_siege: LIGHT_CAPTURE_ORDINARY_DAYS missing")
		return
	if "LIGHT_CAPTURE_MIN_SUPPLY" not in src:
		_fail("mutant skip_supply: LIGHT_CAPTURE_MIN_SUPPLY missing")
		return
	if "func try_ai_cover_capital_approaches" not in src:
		_fail("mutant skip_capital_cover: try_ai_cover_capital_approaches missing")
		return
	if "CAPITAL_THREAT_HOPS" not in src:
		_fail("mutant skip_capital_cover: CAPITAL_THREAT_HOPS missing")
		return
	if "func light_capture_allowed" not in src:
		_fail("mutant skip_adjacency: light_capture_allowed missing")
		return
	var cap_days := int(bm.LIGHT_CAPTURE_CAPITAL_DAYS)
	var ord_days := int(bm.LIGHT_CAPTURE_ORDINARY_DAYS)
	var hops := int(bm.CAPITAL_THREAT_HOPS)
	if cap_days < 3 or cap_days > 5:
		_fail("mutant instant_capital: LIGHT_CAPTURE_CAPITAL_DAYS=%d want 3-5" % cap_days)
		return
	if ord_days < 2:
		_fail("mutant one_hex_per_day: LIGHT_CAPTURE_ORDINARY_DAYS=%d want >=2 (Berlin 12-hex walk)" % ord_days)
		return
	if hops < 3 or hops > 5:
		_fail("mutant skip_capital_cover: CAPITAL_THREAT_HOPS=%d want 3-5" % hops)
		return
	if cap_days <= 1:
		_fail("mutant instant_capital would fall Berlin in 1 day")
		return
	_pass("source mutant killed (capital %dd, ordinary %dd, hops %d)" % [cap_days, ord_days, hops])


func _assert_helpers(bm: Node) -> void:
	if not bm.has_method("empty_hex_capture_days_needed") or not bm.has_method("is_capital_or_high_value"):
		_fail("empty-hex helper methods missing")
		return
	if not bool(bm.call("is_capital_or_high_value", BERLIN)):
		_fail("Berlin %d is not capital/high-value" % BERLIN)
		return
	if not bool(bm.call("is_capital_or_high_value", WARSAW)):
		_fail("Warsaw %d is not capital/high-value" % WARSAW)
		return
	var need := int(bm.call("empty_hex_capture_days_needed", BERLIN))
	if need < 3:
		_fail("mutant instant_capital: Berlin need=%d" % need)
		return
	_pass("Berlin/Warsaw capital days=%d" % need)


func _assert_ordinary_siege(mm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("ordinary siege declare failed")
		return
	if _cap != null:
		_cap.ensure_snapshot()
	var pair: Array = _first_empty_ger_border(mm, bm)
	if pair.size() < 2:
		_fail("no POL→GER ordinary empty border pair")
		return
	var from_id := int(pair[0])
	var to_id := int(pair[1])
	_boot.make_division("aifix1_pol_ord", "POL", from_id)
	tm.set("_live_f5_equiv_clock", true)
	tm.total_days_elapsed = 0
	if "_empty_hex_siege" in bm:
		bm._empty_hex_siege = {}
	var first: Dictionary = bm.call("start_land_battle", "POL", to_id, from_id, "aifix1_pol_ord")
	if _owner(mm, to_id) != "GER":
		_fail("ordinary hex %d flipped on day 1 %s" % [to_id, str(first)])
		tm.set("_live_f5_equiv_clock", false)
		return
	if bool(first.get("light_capture", false)) and bool(first.get("instant", false)):
		_fail("ordinary hex instant-captured on first pressure %s" % str(first))
		tm.set("_live_f5_equiv_clock", false)
		return
	tm.total_days_elapsed = 1
	var second: Dictionary = bm.call("start_land_battle", "POL", to_id, from_id, "aifix1_pol_ord")
	if _owner(mm, to_id) != "GER":
		_fail("ordinary hex %d flipped on day 2 %s" % [to_id, str(second)])
		tm.set("_live_f5_equiv_clock", false)
		return
	tm.total_days_elapsed = 2
	var third: Dictionary = bm.call("start_land_battle", "POL", to_id, from_id, "aifix1_pol_ord")
	tm.set("_live_f5_equiv_clock", false)
	if _owner(mm, to_id) != "POL":
		_fail("ordinary hex %d still %s after 3 contiguous days %s" % [to_id, _owner(mm, to_id), str(third)])
		return
	_pass("ordinary empty hex %d took 3 contiguous days" % to_id)


func _assert_capital_not_instant(mm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("capital siege declare failed")
		return
	if _cap != null:
		_cap.ensure_snapshot()
	var from_id := _first_neighbor(mm, BERLIN)
	if from_id <= 0:
		_fail("Berlin has no land neighbor")
		return
	_set_hold(mm, from_id, "POL", "POL")
	_boot.make_division("aifix1_pol_ber", "POL", from_id)
	tm.set("_live_f5_equiv_clock", true)
	tm.total_days_elapsed = 0
	if "_empty_hex_siege" in bm:
		bm._empty_hex_siege = {}
	var first: Dictionary = bm.call("start_land_battle", "POL", BERLIN, from_id, "aifix1_pol_ber")
	if _owner(mm, BERLIN) != "GER":
		_fail("Berlin fell on first empty-hex pressure %s" % str(first))
		tm.set("_live_f5_equiv_clock", false)
		return
	tm.total_days_elapsed = 1
	bm.call("start_land_battle", "POL", BERLIN, from_id, "aifix1_pol_ber")
	if _owner(mm, BERLIN) != "GER":
		_fail("Berlin fell on day 2 of empty-hex pressure")
		tm.set("_live_f5_equiv_clock", false)
		return
	tm.set("_live_f5_equiv_clock", false)
	_pass("Berlin held through 2 empty-hex pressure days")


func _assert_supply_and_adjacency(mm: Node, bm: Node, lm: Node) -> void:
	if not bm.has_method("light_capture_allowed"):
		_fail("light_capture_allowed missing")
		return
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("supply declare failed")
		return
	var pair: Array = _first_empty_ger_border(mm, bm)
	if pair.size() < 2:
		_fail("no border pair for supply/adjacency")
		return
	var from_id := int(pair[0])
	var to_id := int(pair[1])
	_boot.make_division("aifix1_pol_sup", "POL", from_id)
	var ok_row: Dictionary = bm.call("light_capture_allowed", "POL", from_id, to_id, "aifix1_pol_sup")
	if not bool(ok_row.get("ok", false)):
		_fail("in-supply adjacent capture blocked %s" % str(ok_row))
		return
	var far := BERLIN if to_id != BERLIN else WARSAW
	var adj: Dictionary = bm.call("light_capture_allowed", "POL", from_id, far, "aifix1_pol_sup")
	if bool(adj.get("ok", false)):
		_fail("non-adjacent capture allowed from %d to %d" % [from_id, far])
		return
	# Isolate staging: flip every friendly neighbor so light-sim marks a pocket.
	var nbrs: Array = mm.call("get_adjacent_provinces", from_id, true)
	var flipped: Array = []
	for nid_v in nbrs:
		var nid := int(nid_v)
		if nid == to_id:
			continue
		var np: Object = mm.call("get_province", nid)
		if np == null or bool(np.get("is_sea")):
			continue
		if str(np.get("controller_tag")).strip_edges().to_upper() != "POL":
			continue
		_set_hold(mm, nid, "GER", "GER")
		flipped.append(nid)
	var pocket: Dictionary = bm.call("light_capture_allowed", "POL", from_id, to_id, "aifix1_pol_sup")
	for pid_v in flipped:
		_set_hold(mm, int(pid_v), "POL", "POL")
	if bool(pocket.get("ok", false)):
		_fail("out-of-supply pocket capture allowed %s" % str(pocket))
		return
	_pass("supply + adjacency gates hold")


func _assert_berlin_holds_30(mm: Node, sm: Node, bm: Node, tm: Node, lm: Node) -> void:
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("30d declare failed")
		return
	if _cap != null:
		_cap.ensure_snapshot()
	var n := _station_border(mm, "POL", "GER")
	if n <= 0:
		_fail("no POL border divisions")
		return
	var fall_day := -1
	for d in range(1, HOLD_DAYS + 1):
		tm.call("advance_live_f5_equivalent_days", 1)
		if _owner(mm, BERLIN) != "GER" and fall_day < 0:
			fall_day = d
			break
	if fall_day > 0 and fall_day < HOLD_DAYS:
		_fail("Berlin fell on day %d (want hold through %d)" % [fall_day, HOLD_DAYS])
		return
	if _owner(mm, BERLIN) != "GER":
		_fail("Berlin holder %s after %d days" % [_owner(mm, BERLIN), HOLD_DAYS])
		return
	_pass("Berlin still GER after %d pol-only days (stationed=%d)" % [HOLD_DAYS, n])


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
		_boot.make_division("aifix1_%s_%d" % [att, pid], att, pid)
		n += 1
	return n


func _first_empty_ger_border(mm: Node, bm: Node = null) -> Array:
	var owned: Array = mm.call("get_provinces_by_owner", "POL")
	owned.sort()
	for pid_v in owned:
		var pid := int(pid_v)
		for nid_v in mm.call("get_adjacent_provinces", pid, true):
			var nid := int(nid_v)
			if nid == BERLIN:
				continue
			var p: Object = mm.call("get_province", nid)
			if p == null or bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() != "GER":
				continue
			if bm != null and bm.has_method("empty_hex_capture_days_needed"):
				if int(bm.call("empty_hex_capture_days_needed", nid)) > int(bm.LIGHT_CAPTURE_ORDINARY_DAYS):
					continue
			return [pid, nid]
	return []


func _first_neighbor(mm: Node, pid: int) -> int:
	for nid_v in mm.call("get_adjacent_provinces", pid, true):
		var nid := int(nid_v)
		var p: Object = mm.call("get_province", nid)
		if p == null or bool(p.get("is_sea")):
			continue
		return nid
	return -1


func _owner(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _set_hold(mm: Node, pid: int, owner: String, ctrl: String) -> void:
	if mm.has_method("update_province_owner"):
		mm.call("update_province_owner", pid, owner, ctrl, true, true)
