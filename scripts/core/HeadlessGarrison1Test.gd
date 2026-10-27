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
	_assert_play_p2(lm)
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
	# Play #133 1280x800 Europe Home is z=0.787 (godot_r1.log EOA_ZOOM_BEGIN from=0.787).
	var play_line := bool(lod.call("show_unit_counters_for_zoom", 0.787, true))
	var play_garr := bool(lod.call("show_garrison_counters_for_zoom", 0.787, true))
	var close_garr := bool(lod.call("show_garrison_counters_for_zoom", 1.00, true))
	var kulm_steals := bool(lod.call("garrison_chip_owns_click", 710259, 710300))
	var berlin_owns := bool(lod.call("garrison_chip_owns_click", 710300, 710300))
	var mr_src := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	var defer_fn := _func_slice(mr_src, "_defer_garrison_icon")
	var hold_fn := _func_slice(mr_src, "_hold_queued_icons_for_zoom")
	var vis_fn := _func_slice(mr_src, "_sync_unit_counter_visibility")
	var boot_uses_lod := (
		"show_garrison_counters_for_zoom" in defer_fn
		and "show_garrison_counters_for_zoom" in hold_fn
		and "show_garrison_counters_for_zoom" in vis_fn
	)
	if (
		not home_line or home_garr or not play_line or play_garr or not close_garr
		or kulm_steals or not berlin_owns or not boot_uses_lod
	):
		_fail(
			"chip lod line0.40=%s garr0.40=%s line0.787=%s garr0.787=%s garr1.00=%s kulm=%s berlin=%s boot_lod=%s"
			% [home_line, home_garr, play_line, play_garr, close_garr, kulm_steals, berlin_owns, boot_uses_lod]
		)
		return
	print(
		"GARRISON_CHIP_VIS z=0.787 line_counters=%s garrison_counters=%s visible_garrison_chips_at_default_zoom=0"
		% [str(play_line), str(play_garr)]
	)
	_pass("one toast; garrisons hidden at play home z=0.787; Kulmbach cannot own a Berlin click")


## Play findings on #133: fleet/air TOE, leader type, optional layers, Fill% == chip.
func _assert_play_p2(lm: Node) -> void:
	var reasons: PackedStringArray = PackedStringArray()
	var lcp: GDScript = load("res://scripts/combat/LandCombatPower.gd") as GDScript
	var strip: GDScript = load("res://scripts/ui/UnitCardCombatStrip.gd") as GDScript
	var pm := get_root().get_node_or_null("ProductionManager")
	# Load at runtime. A class_name reference here compiles ScenarioLoader before
	# autoloads exist and breaks Formation.new() in field_designed_unit.
	var sl_script: GDScript = load("res://scripts/core/ScenarioLoader.gd") as GDScript
	var sl: Object = sl_script.new() if sl_script != null else null
	if lcp == null or not lcp.has_method("equipment_toe_for_formation"):
		reasons.append("b: equipment_toe_for_formation missing")
	if strip == null or not strip.has_method("shared_display_percent"):
		reasons.append("e: shared_display_percent missing")
	if pm == null or not pm.has_method("has_unit_equipment_ledger"):
		reasons.append("e: has_unit_equipment_ledger missing")
	if sl == null or not sl.has_method("_missing_layer_is_warning"):
		reasons.append("d: _missing_layer_is_warning missing")
	else:
		var warn_legacy_super := bool(sl.call("_missing_layer_is_warning", "provinces", "super_regions.json"))
		var warn_legacy_hier := bool(sl.call("_missing_layer_is_warning", "provinces", "hierarchy_scaffold.json"))
		var warn_wa_super := bool(sl.call("_missing_layer_is_warning", "provinces_world_accurate", "super_regions.json"))
		var warn_wa_hier := bool(sl.call("_missing_layer_is_warning", "provinces_world_accurate", "hierarchy_scaffold.json"))
		var legacy_missing := not FileAccess.file_exists("res://data/provinces/super_regions.json") and not FileAccess.file_exists("res://data/provinces/hierarchy_scaffold.json")
		var wa_present := FileAccess.file_exists("res://data/provinces_world_accurate/super_regions.json") and FileAccess.file_exists("res://data/provinces_world_accurate/hierarchy_scaffold.json")
		if warn_legacy_super or warn_legacy_hier or not warn_wa_super or not warn_wa_hier or not legacy_missing or not wa_present:
			reasons.append(
				"d: legacy_warn=%s/%s wa_warn=%s/%s legacy_missing=%s wa_present=%s"
				% [warn_legacy_super, warn_legacy_hier, warn_wa_super, warn_wa_hier, legacy_missing, wa_present]
			)
	var lm_src := FileAccess.get_file_as_string("res://scripts/leaders/LeaderManager.gd")
	var field_fn := _func_slice(lm_src, "field_designed_unit")
	if (
		"_allowed_leader_types_for_formation_type" not in field_fn
		or "[\"general\", \"field_marshal\"]" in field_fn
	):
		reasons.append("c: field_designed_unit still picks generals for every domain")
	var pol: Dictionary = lm.call("field_designed_unit", "POL", "king_george_v_class_bb", 950001, "naval", {
		"formation_id": "p2_pol_kgv",
		"display_name": "POL king_george_v_class_bb",
		"quiet": true,
		"force_new": true,
	})
	var pol_f: Object = lm.call("get_formation", "p2_pol_kgv")
	if not bool(pol.get("ok", false)) or pol_f == null or str(pol_f.formation_type) != "fleet":
		reasons.append("c: POL fleet field failed %s" % str(pol))
	elif not str(pol_f.leader_id).strip_edges().is_empty():
		var pol_leader: Object = lm.call("get_leader", str(pol_f.leader_id))
		var pol_lt := str(pol_leader.leader_type) if pol_leader != null else ""
		if pol_lt != "admiral":
			reasons.append("c: POL fleet leader %s is %s" % [str(pol_f.leader_id), pol_lt])
	var eng: Dictionary = lm.call("field_designed_unit", "ENG", "king_george_v_class_bb", 950001, "naval", {
		"formation_id": "p2_eng_fleet",
		"display_name": "ENG Fleet",
		"quiet": true,
		"force_new": true,
	})
	var air: Dictionary = lm.call("field_designed_unit", "ENG", "bf109g_fighter", 711414, "air", {
		"formation_id": "p2_eng_wing",
		"display_name": "ENG Wing",
		"quiet": true,
		"force_new": true,
	})
	var eng_f: Object = lm.call("get_formation", "p2_eng_fleet")
	var air_f: Object = lm.call("get_formation", "p2_eng_wing")
	if strip != null and eng_f != null and air_f != null and bool(eng.get("ok", false)) and bool(air.get("ok", false)):
		var fleet_ln := _first_line(strip.call("lines_for", eng_f))
		var air_ln := _first_line(strip.call("lines_for", air_f))
		var fleet_ok := (
			"infantry" not in fleet_ln
			and ("naval" in fleet_ln or "mk15" in fleet_ln or "14inch" in fleet_ln or "carrier boiler" in fleet_ln)
		)
		var air_ok := (
			"infantry" not in air_ln
			and ("mg151" in air_ln or "aircraft" in air_ln)
		)
		if not fleet_ok or not air_ok:
			reasons.append("b: fleet='%s' air='%s'" % [fleet_ln, air_ln])
	else:
		reasons.append("b: could not field ENG fleet/air")
	if strip != null:
		lm.call("field_designed_unit", "CZE", "m3_stuart_light_tank", 710200, "land", {
			"formation_id": "p2_cze_div0",
			"display_name": "Division 0",
			"quiet": true,
			"force_new": true,
			"skip_leader": true,
			"strength": 1.0,
		})
		var div: Object = lm.call("get_formation", "p2_cze_div0")
		if div == null:
			reasons.append("e: Division 0 was not fielded")
		else:
			if pm != null and pm.has_method("clear_unit_equipment_stock"):
				pm.call("clear_unit_equipment_stock", "p2_cze_div0")
			div.set("strength", 1.0)
		var bare := _first_line(strip.call("lines_for", div) if div != null else PackedStringArray())
		var bare_pct := -1
		if strip.has_method("shared_display_percent"):
			bare_pct = int(strip.call("shared_display_percent", div))
		if "Fill 0%" in bare or bare_pct != 100 or not bare.begins_with("Fill 100%"):
			reasons.append("e: untracked card='%s' shared=%d" % [bare, bare_pct])
		if div != null:
			div.set_meta("toe_fill", 0.28)
			var tracked := _first_line(strip.call("lines_for", div))
			var tracked_pct := -1
			if strip.has_method("shared_display_percent"):
				tracked_pct = int(strip.call("shared_display_percent", div))
			if "Fill 28%" not in tracked or tracked_pct != 28:
				reasons.append("e: tracked card='%s' shared=%d" % [tracked, tracked_pct])
	var mr_src := FileAccess.get_file_as_string("res://scripts/map/MapRenderer.gd")
	var chrome := _func_slice(mr_src, "_attach_unit_counter_chrome")
	if "shared_display_percent" not in chrome or "fill_ratio = str_v" in mr_src:
		reasons.append("e: chip StrNum is not the card Fill source")
	if reasons.is_empty():
		_pass("fleet/air TOE, POL admiral, optional province layers, Fill% matches chip")
		return
	_fail("play p2: %s" % " | ".join(reasons))


func _first_line(raw: Variant) -> String:
	if raw is PackedStringArray:
		var rows: PackedStringArray = raw as PackedStringArray
		if rows.is_empty():
			return ""
		return str(rows[0])
	if raw is Array and not (raw as Array).is_empty():
		return str((raw as Array)[0])
	return ""


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
