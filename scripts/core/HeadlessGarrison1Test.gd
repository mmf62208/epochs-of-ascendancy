extends SceneTree

## GARRISON-1: 1936 border garrisons, AI cover, liberation notice, German names.
const BERLIN := 710300
const ELBING := 711086
const STOLP := 711091
const WAR_DAYS := 60
const SOAK_DAYS := 100
const TAGS := ["GER", "FRA", "ENG", "SOV", "ITA", "JAP", "USA", "POL", "CZE"]
const CAPITALS := {
	"GER": 710300,
	"FRA": 710707,
	"ENG": 711414,
	"USA": 800792,
	"SOV": 903534,
	"ITA": 710963,
	"JAP": 903995,
	"POL": 711112,
	"CZE": 710146,
}
const POL_CZESTOCHOWA := 711054

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
	print("  [FAIL] HeadlessGarrison1Test: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessGarrison1Test: ", msg)


func _run() -> void:
	var mm := get_root().get_node_or_null("MapManager")
	var sm := get_root().get_node_or_null("SupplyManager")
	var bm := get_root().get_node_or_null("BattleManager")
	var tm := get_root().get_node_or_null("TimeManager")
	var lm := get_root().get_node_or_null("LeaderManager")
	_boot = load("res://scripts/core/CampaignLoopTestBoot.gd") as GDScript
	_war = load("res://scripts/core/WarStateDomain.gd") as GDScript
	_cap = load("res://scripts/core/CapitulationDomain.gd") as GDScript
	if mm == null or bm == null or tm == null or lm == null or _boot == null or _war == null:
		_fail("autoloads missing")
		_finish()
		return
	if not _boot.call("boot", mm, sm, "GER"):
		_fail("board boot failed")
		_finish()
		return
	_clear(lm)
	if not lm.has_method("seed_1936_start_garrisons"):
		_fail("seed_1936_start_garrisons missing")
		_finish()
		return
	var pm := get_root().get_node_or_null("ProductionManager")
	var seeded: Dictionary = lm.call("seed_1936_start_garrisons", true)
	print("GARRISON_COUNTS %s" % str(seeded.get("counts", {})))
	_assert_garrison_fielding(lm, pm, seeded)
	seeded = _assert_occupied_skip(lm)
	seeded = _assert_nation_template(lm)
	_assert_toast_zoom_pick()
	_assert_stations(mm, lm, seeded)
	_assert_names(bm)
	_assert_same_owner_skipped(mm, bm)
	_assert_liberation_notice(mm, bm)
	_assert_cover(mm, bm, lm)
	_assert_save_roundtrip(lm)
	_assert_berlin_holds(mm, tm, lm)
	_assert_ai_soak(mm, sm, tm, lm)
	_finish()


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessGarrison1Test: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessGarrison1Test: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _assert_garrison_fielding(lm: Node, pm: Node, seeded: Dictionary) -> void:
	var placed := int(seeded.get("placed", -1))
	var skipped := int(seeded.get("skipped_occupied", -1))
	var targets := int(seeded.get("targets", -1))
	if placed != 549 or skipped != 0 or targets != 549 or placed != targets:
		_fail("empty board placed=%d skipped=%d targets=%d" % [placed, skipped, targets])
		return
	var seen := 0
	for tag in TAGS:
		for f in lm.call("get_formations_for_country", tag):
			if f == null or not bool(f.get_meta("garrison_1936", false)):
				continue
			seen += 1
			var name_s := str(f.name)
			var did := str(f.design_id)
			var want := str(lm.call("garrison_1936_design_for", tag))
			if did != want or did == "german_infantry_division_1943":
				_fail("%s design %s want %s" % [tag, did, want])
				return
			if bool(lm.call("_garrison_design_is_foreign", tag, did)):
				_fail("%s foreign design %s" % [tag, did])
				return
			if name_s.to_lower().contains("german") or name_s.contains("_") or not name_s.ends_with("Garrison Division"):
				_fail("%s name %s" % [tag, name_s])
				return
			if not name_s.begins_with(tag + " "):
				_fail("%s name tag %s" % [tag, name_s])
				return
			var label := str(lm.call("garrison_1936_design_label", did))
			if label.contains("_") or label == did:
				_fail("%s design label %s" % [tag, label])
				return
			if absf(float(f.strength) - 1.0) > 0.001:
				_fail("%s strength %.3f" % [tag, float(f.strength)])
				return
			if pm == null or not pm.has_method("unit_toe_fill_ratio"):
				_fail("ProductionManager fill missing")
				return
			var ratio := float(pm.call("unit_toe_fill_ratio", str(f.formation_id)))
			var stock_v: Variant = pm.call("get_unit_equipment_stock", str(f.formation_id))
			var inf := 0
			if stock_v is Dictionary:
				inf = int((stock_v as Dictionary).get("infantry_equipment", 0))
			if ratio < 0.999 or inf < 80:
				_fail("%s fill %.3f stock %s" % [tag, ratio, str(stock_v)])
				return
	if seen != placed:
		_fail("fielded %d != placed %d" % [seen, placed])
		return
	_pass("549 garrisons full TOE, 1936 design, nation names")


func _assert_occupied_skip(lm: Node) -> Dictionary:
	_clear(lm)
	_boot.call("make_division", "occ_berlin", "GER", BERLIN)
	var occ: Dictionary = lm.call("seed_1936_start_garrisons", true)
	var placed := int(occ.get("placed", -1))
	var skipped := int(occ.get("skipped_occupied", -1))
	var targets := int(occ.get("targets", -1))
	var berlin = lm.call("get_formation", "garr1936_GER_%d" % BERLIN)
	if skipped < 1 or placed + skipped != targets or berlin != null:
		_fail("occupied Berlin placed=%d skipped=%d targets=%d garrison=%s" % [placed, skipped, targets, str(berlin != null)])
	else:
		_pass("occupied hex skipped (%d+%d=%d)" % [placed, skipped, targets])
	_clear(lm)
	return lm.call("seed_1936_start_garrisons", true)


func _assert_nation_template(lm: Node) -> Dictionary:
	var dd: Object = null
	var gd := get_root().get_node_or_null("GameData")
	if gd != null:
		dd = gd.get("design_data")
	if dd != null and dd.has_method("register_runtime_template_from_dict"):
		var tpl: Variant = dd.call("register_runtime_template_from_dict", {
			"id": "fra_infantry_1936",
			"name": "Division d'Infanterie 1936",
			"design_nation": "FRA",
			"visual_archetype": "infantry",
		})
		if tpl == null:
			_fail("could not register fra_infantry_1936")
		else:
			_clear(lm)
			lm.call("seed_1936_start_garrisons", true)
			var fra = lm.call("get_formation", "garr1936_FRA_710707")
			var ger = lm.call("get_formation", "garr1936_GER_%d" % BERLIN)
			var fra_did := str(fra.design_id) if fra != null else ""
			var ger_did := str(ger.design_id) if ger != null else ""
			var label := str(lm.call("garrison_1936_design_label", fra_did))
			if fra_did != "fra_infantry_1936" or ger_did == "fra_infantry_1936" or label != "Division d'Infanterie 1936":
				_fail("template pick FRA=%s GER=%s label=%s" % [fra_did, ger_did, label])
			else:
				_pass("FRA uses fra_infantry_1936; GER stays %s" % ger_did)
		if dd.get("templates") is Dictionary:
			(dd.get("templates") as Dictionary).erase("fra_infantry_1936")
	else:
		_fail("design catalog missing")
	_clear(lm)
	return lm.call("seed_1936_start_garrisons", true)


func _assert_toast_zoom_pick() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	var select_fn := _func_slice(src, "_select_map_unit")
	if select_fn.count("toast_map_debug") != 0 or select_fn.count("_show_inspector_toast") != 1:
		_fail("duplicate toast still in _select_map_unit")
		return
	var card_fn := _func_slice(src, "_show_unit_detail_popup")
	var label_fn := _func_slice(src, "_formation_card_design_text")
	if "garrison_1936_design_label" not in label_fn or "_formation_is_garrison_1936" not in card_fn:
		_fail("card still prints raw garrison design")
		return
	var raise_src := FileAccess.get_file_as_string("res://scripts/combat/BattleManager.gd")
	var raise_fn := _func_slice(raise_src, "_raise_garrison_at")
	if "field_1936_garrison" not in raise_fn or "german_infantry_division_1943" in raise_fn:
		_fail("cover raise still hardcodes the 1943 german design")
		return
	var lod: GDScript = load("res://scripts/map/MapZoomLOD.gd") as GDScript
	var home_line := bool(lod.call("show_unit_counters_for_zoom", 0.40, true))
	var home_garr := bool(lod.call("show_garrison_counters_for_zoom", 0.40, true))
	var ops_garr := bool(lod.call("show_garrison_counters_for_zoom", 0.90, true))
	var kulm_steals := bool(lod.call("garrison_chip_owns_click", 710259, 710300))
	var berlin_owns := bool(lod.call("garrison_chip_owns_click", 710300, 710300))
	if not home_line or home_garr or not ops_garr or kulm_steals or not berlin_owns:
		_fail("chip lod line=%s garr0.40=%s garr0.90=%s kulm=%s berlin=%s" % [home_line, home_garr, ops_garr, kulm_steals, berlin_owns])
		return
	print("GARRISON_CHIP_VIS z=0.40 line_counters=%s garrison_counters=%s visible_garrison_chips_at_default_zoom=0" % [str(home_line), str(home_garr)])
	_pass("one toast; garrisons hidden at z=0.40; Kulmbach cannot own a Berlin click")


func _func_slice(src: String, fname: String) -> String:
	var key := "func %s" % fname
	var i := src.find(key)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + 10)
	if j < 0:
		j = src.length()
	return src.substr(i, j - i)


func _assert_stations(mm: Node, lm: Node, seeded: Dictionary) -> void:
	var counts: Dictionary = seeded.get("counts", {})
	for tag in TAGS:
		var n := int(counts.get(tag, 0))
		if n < 1:
			_fail("%s garrison count %d" % [tag, n])
			return
		var cap := int(CAPITALS[tag])
		if _station_of(lm, "garr1936_%s_%d" % [tag, cap]) != cap:
			_fail("%s capital %d has no garrison" % [tag, cap])
			return
	if _station_of(lm, "garr1936_POL_%d" % POL_CZESTOCHOWA) != POL_CZESTOCHOWA:
		_fail("POL border capital-class %d has no garrison" % POL_CZESTOCHOWA)
		return
	if _owner(mm, BERLIN) != "GER":
		_fail("seed flipped Berlin")
		return
	_pass("nine tags garrisoned; capitals held")


func _assert_names(bm: Node) -> void:
	if not bm.has_method("campaign_province_display_name"):
		_fail("campaign_province_display_name missing")
		return
	var elbing := str(bm.call("campaign_province_display_name", ELBING, "Elbląski"))
	var stolp := str(bm.call("campaign_province_display_name", STOLP, "Słupski"))
	if elbing != "Elbing" or stolp != "Stolp":
		_fail("names %s / %s" % [elbing, stolp])
		return
	_pass("Elbing and Stolp display names")


func _assert_same_owner_skipped(mm: Node, bm: Node) -> void:
	_set_hold(mm, ELBING, "GER", "GER")
	bm.set("last_capture_notice", "")
	bm.call("_apply_attacker_win_capture_light", "GER", ELBING, BERLIN, "")
	if _owner(mm, ELBING) != "GER" or _ctrl(mm, ELBING) != "GER":
		_fail("same-owner capture mutated %s/%s" % [_owner(mm, ELBING), _ctrl(mm, ELBING)])
		return
	if str(bm.get("last_capture_notice")) != "":
		_fail("same-owner capture posted %s" % str(bm.get("last_capture_notice")))
		return
	_pass("same-owner light capture did not run")


func _assert_liberation_notice(mm: Node, bm: Node) -> void:
	_set_hold(mm, ELBING, "GER", "POL")
	bm.set("last_capture_notice", "")
	bm.call("_apply_attacker_win_capture_light", "GER", ELBING, BERLIN, "")
	if _owner(mm, ELBING) != "GER" or _ctrl(mm, ELBING) != "GER":
		_fail("liberation left %s/%s" % [_owner(mm, ELBING), _ctrl(mm, ELBING)])
		return
	var notice := str(bm.get("last_capture_notice"))
	if "Elbing" not in notice or "captured" not in notice.to_lower():
		_fail("liberation notice %s" % notice)
		return
	_pass("liberation notice: %s" % notice)


func _assert_cover(mm: Node, bm: Node, lm: Node) -> void:
	if not bool(_war.declare_war("GER", "POL", "test").get("ok", false)):
		_fail("cover declare failed")
		return
	var hole := ELBING
	_remove_stationed(lm, hole)
	var pol_from := _pol_neighbor(mm, hole)
	if pol_from <= 0:
		_fail("no POL neighbor of %d" % hole)
		return
	_boot.call("make_division", "pol_probe", "POL", pol_from)
	if not bm.has_method("try_ai_cover_threatened_borders"):
		_fail("try_ai_cover_threatened_borders missing")
		return
	var covered: Dictionary = bm.call("try_ai_cover_threatened_borders")
	var back := false
	for f in lm.call("get_formations_for_country", "GER"):
		if f != null and int(f.stationed_province_id) == hole:
			back = true
			break
	if not back:
		_fail("cover did not fill %d (%s)" % [hole, str(covered)])
		return
	_pass("AI cover filled %d within %d day (moved=%s)" % [hole, int(covered.get("within_days", 1)), str(covered.get("moved", 0))])


func _assert_save_roundtrip(lm: Node) -> void:
	var fid := "garr1936_GER_%d" % BERLIN
	var before := _station_of(lm, fid)
	if before != BERLIN:
		_fail("Berlin garrison missing before save")
		return
	var blob: Dictionary = lm.call("get_save_data")
	_clear(lm)
	lm.call("apply_save_data", blob)
	if _station_of(lm, fid) != BERLIN:
		_fail("Berlin garrison did not reload")
		return
	var f = lm.call("get_formation", fid)
	if f == null or not bool(f.get_meta("garrison_1936", false)):
		_fail("reloaded garrison lost garrison_1936")
		return
	var pm := get_root().get_node_or_null("ProductionManager")
	if pm != null and pm.has_method("clear_unit_equipment_stock"):
		pm.call("clear_unit_equipment_stock", fid)
	_clear(lm)
	lm.call("apply_save_data", blob)
	f = lm.call("get_formation", fid)
	if f == null or not bool(f.get_meta("garrison_1936", false)):
		_fail("reloaded garrison lost garrison_1936 after stock clear")
		return
	if str(f.design_id) == "german_infantry_division_1943" or str(f.name).to_lower().contains("german"):
		_fail("reload kept raw german design name=%s design=%s" % [str(f.name), str(f.design_id)])
		return
	if pm != null and pm.has_method("unit_toe_fill_ratio"):
		var ratio := float(pm.call("unit_toe_fill_ratio", fid))
		if ratio < 0.999:
			_fail("reload fill %.3f" % ratio)
			return
	var formations_v: Variant = blob.get("formations", {})
	if formations_v is Dictionary and (formations_v as Dictionary).has(fid):
		var row: Dictionary = (formations_v as Dictionary)[fid] as Dictionary
		row.erase("equipment_stock")
		(formations_v as Dictionary)[fid] = row
		blob["formations"] = formations_v
		if pm != null and pm.has_method("clear_unit_equipment_stock"):
			pm.call("clear_unit_equipment_stock", fid)
		_clear(lm)
		lm.call("apply_save_data", blob)
		if pm != null and float(pm.call("unit_toe_fill_ratio", fid)) < 0.999:
			_fail("old garrison blob did not refill TOE")
			return
	_pass("garrison save/load %s @ %d full TOE" % [fid, BERLIN])


func _assert_berlin_holds(mm: Node, tm: Node, lm: Node) -> void:
	_clear(lm)
	lm.call("seed_1936_start_garrisons", true)
	var pol_n := _station_attacker(mm, "POL", "GER")
	print("GARRISON_BERLIN pol_on_ger_border=%d" % pol_n)
	if pol_n < 1:
		_fail("no POL division on the German border")
		return
	var dec: Dictionary = _war.declare_war("GER", "POL", "test")
	if not bool(dec.get("ok", false)):
		_fail("berlin declare %s" % str(dec))
		return
	var ger0: Dictionary = {}
	for pid_v in mm.call("get_provinces_by_owner", "GER"):
		ger0[int(pid_v)] = true
	var first_loss := -1
	var lost_pid := -1
	for day in range(1, WAR_DAYS + 1):
		tm.call("advance_live_f5_equivalent_days", 1)
		if first_loss < 0:
			for pid_v in ger0.keys():
				var pid := int(pid_v)
				if _owner(mm, pid) != "GER":
					first_loss = day
					lost_pid = pid
					break
		if _owner(mm, BERLIN) != "GER":
			_fail("Berlin fell on day %d" % day)
			return
	print(
		"GARRISON_BERLIN days=%d berlin=%s first_core_loss=%d pid=%d name=%s"
		% [int(tm.total_days_elapsed), _owner(mm, BERLIN), first_loss, lost_pid, _name(mm, lost_pid)]
	)
	_pass("Berlin still GER after %d days" % WAR_DAYS)


func _assert_ai_soak(mm: Node, sm: Node, tm: Node, lm: Node) -> void:
	if not _boot.call("boot", mm, sm, "USA"):
		_fail("soak boot failed")
		return
	_war.call("reset_for_test")
	if _cap != null:
		_cap.call("reset_for_test")
	var end: GDScript = load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if end != null:
		end.call("reset_for_test")
	_clear(lm)
	lm.call("seed_1936_start_garrisons", true)
	for pair in [["GER", "POL"], ["FRA", "ITA"], ["SOV", "POL"]]:
		var dec: Dictionary = _war.declare_war(str(pair[0]), str(pair[1]), "test")
		if not bool(dec.get("ok", false)):
			_fail("soak declare %s failed %s" % [str(pair), str(dec)])
			return
	var fell: Array = []
	for day in range(1, SOAK_DAYS + 1):
		tm.call("advance_live_f5_equivalent_days", 1)
		if _cap == null:
			continue
		for tag in TAGS:
			if bool(_cap.call("is_capitulated", tag)):
				var mark := "%s@%d" % [tag, day]
				if mark not in fell and not _already_fell(fell, tag):
					fell.append(mark)
	print("GARRISON_SOAK days=%d elapsed=%d capitulations=%s" % [SOAK_DAYS, int(tm.total_days_elapsed), str(fell)])
	_pass("100-day AI soak recorded")


func _already_fell(fell: Array, tag: String) -> bool:
	for item in fell:
		if str(item).begins_with(tag + "@"):
			return true
	return false


func _pol_neighbor(mm: Node, pid: int) -> int:
	var nbrs: Array = mm.call("get_adjacent_provinces", pid, true)
	for nid_v in nbrs:
		var nid := int(nid_v)
		var p: Object = mm.call("get_province", nid)
		if p == null or bool(p.get("is_sea")):
			continue
		if str(p.get("owner_tag")).strip_edges().to_upper() == "POL":
			return nid
	return -1


func _remove_stationed(lm: Node, pid: int) -> void:
	var drop: Array = []
	for f in lm.call("get_formations_for_country", "GER"):
		if f != null and int(f.stationed_province_id) == pid:
			drop.append(str(f.formation_id))
	for fid in drop:
		lm.formations.erase(fid)


func _station_of(lm: Node, fid: String) -> int:
	if not lm.has_method("get_formation"):
		return -1
	var f = lm.call("get_formation", fid)
	if f == null:
		return -1
	return int(f.stationed_province_id)


func _set_hold(mm: Node, pid: int, owner: String, ctrl: String) -> void:
	mm.call("update_province_owner", pid, owner, ctrl, true, true)


func _owner(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("owner_tag")).strip_edges().to_upper()


func _ctrl(mm: Node, pid: int) -> String:
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	var c := str(p.get("controller_tag")).strip_edges().to_upper()
	if c.is_empty():
		c = str(p.get("owner_tag")).strip_edges().to_upper()
	return c


func _name(mm: Node, pid: int) -> String:
	if pid <= 0:
		return ""
	var p: Object = mm.call("get_province", pid)
	if p == null:
		return ""
	return str(p.get("name"))


func _station_attacker(mm: Node, att: String, defender: String) -> int:
	var owned: Array = mm.call("get_provinces_by_owner", att)
	var n := 0
	for pid_v in owned:
		var pid := int(pid_v)
		var p0: Object = mm.call("get_province", pid)
		if p0 == null or bool(p0.get("is_sea")):
			continue
		var borders := false
		for nid_v in mm.call("get_adjacent_provinces", pid, true):
			var p: Object = mm.call("get_province", int(nid_v))
			if p == null or bool(p.get("is_sea")):
				continue
			if str(p.get("owner_tag")).strip_edges().to_upper() == defender:
				borders = true
				break
		if not borders:
			continue
		_boot.call("make_division", "probe_%s_%d" % [att, pid], att, pid)
		n += 1
	return n


func _clear(lm: Node) -> void:
	if lm != null and "formations" in lm and lm.formations is Dictionary:
		lm.formations.clear()
	if lm != null and "_garrisons_1936_seeded" in lm:
		lm._garrisons_1936_seeded = false
