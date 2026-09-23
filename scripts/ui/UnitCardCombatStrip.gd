# scripts/ui/UnitCardCombatStrip.gd
## Docked unit-card combat lines. Director: lines.append_array(UnitCardCombatStrip.lines_for(formation))
## Offline SOT: tools/map_generation/lib/unit_card_combat_strip_product.py
class_name UnitCardCombatStrip
extends RefCounted


static func lines_for(formation: Object) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if formation == null or not is_instance_valid(formation):
		return lines
	# Promote Fill · TOE above XP/plan so the fold clip still shows equipment (Play P0).
	# GER Division demo must not throw when LandCombatPower / ProductionManager meta is missing.
	var fold := _fill_toe_fold_line(formation, _safe_composition(formation))
	if fold.is_empty():
		fold = _fill_percent_line(formation)
	if fold.is_empty() or fold.begins_with("Strength"):
		fold = "Fill —% · TOE —"
	lines.append(fold)
	var xp := _safe_float_prop(formation, "combat_experience", 48.0)
	lines.append("XP %s" % xp_band(xp))
	if "planning" in formation:
		lines.append("Planning %.0f%%" % _as_percent(_safe_float_prop(formation, "planning", 0.0)))
	if "entrenchment" in formation:
		lines.append("Entrenchment %.0f%%" % _as_percent(_safe_float_prop(formation, "entrenchment", 0.0)))
	if "last_equip_loss_plain" in formation:
		var loss := str(formation.get("last_equip_loss_plain")).strip_edges()
		if not loss.is_empty():
			lines.append(loss)
	if "last_supply_plain" in formation:
		var sup := str(formation.get("last_supply_plain")).strip_edges()
		if not sup.is_empty():
			lines.append(sup)
	var str_v := _safe_float_prop(formation, "strength", 1.0)
	lines.append("Strength %.0f%%" % _as_percent(str_v))
	var ft := str(formation.get("formation_type")) if "formation_type" in formation else ""
	if ft == "air_wing" or ft == "air_squadron" or ft == "air_group":
		var mission := str(formation.get("current_air_mission")) if "current_air_mission" in formation else "CAS"
		if mission.strip_edges().is_empty():
			mission = "CAS"
		var rid := 0
		if "assigned_region_id" in formation:
			var rid_v: Variant = formation.get("assigned_region_id")
			if typeof(rid_v) == TYPE_INT or typeof(rid_v) == TYPE_FLOAT:
				rid = int(rid_v)
		var rng := str(formation.get("air_range_config")) if "air_range_config" in formation else "COMBAT_LOAD"
		var fuel_pct := clampf(_safe_float_prop(formation, "fuel_level", 1.0), 0.0, 1.0) * 100.0
		lines.append(
			"%s · region %d · range %s · fuel %.0f%%" % [mission, rid, rng, fuel_pct]
		)
		if rid > 0:
			lines.append("CAS assigned · Unassign")
		else:
			lines.append("CAS unassigned · Assign")
	if "last_manpower_loss" in formation:
		var men_v: Variant = formation.get("last_manpower_loss")
		var men_l := 0
		if typeof(men_v) == TYPE_INT or typeof(men_v) == TYPE_FLOAT:
			men_l = int(men_v)
		if men_l > 0 and "last_equip_loss_plain" not in formation:
			lines.append("men −%d" % men_l)
	if "is_training" in formation and bool(formation.get("is_training")):
		var prog := _safe_float_prop(formation, "training_progress", 0.0)
		var need := 14.0
		var mode := "new"
		if formation.has_method("has_meta"):
			if bool(formation.has_meta("organize_days")):
				need = _safe_meta_float(formation, "organize_days", 14.0)
			if bool(formation.has_meta("organize_mode")):
				mode = str(formation.get_meta("organize_mode"))
		if mode == "refit":
			lines.append("Refit %d/%dd · org/str recovering" % [int(prog), int(need)])
		else:
			lines.append("Training %d/%dd · not combat-ready" % [int(prog), int(need)])
	# Last-3 combat_log stays on tooltip — first-session card body keeps Fill/TOE above the fold.
	return lines


static func bbcode_for(formation: Object) -> String:
	return "\n".join(lines_for(formation))


static func tooltip_lines_for(formation: Object) -> PackedStringArray:
	var tips: PackedStringArray = PackedStringArray()
	if formation == null or not is_instance_valid(formation):
		return tips
	var str_v := _safe_float_prop(formation, "strength", 1.0)
	var comp: Dictionary = _safe_composition(formation)
	if bool(comp.get("has_composition", false)) or float(comp.get("armor", 0.0)) > 0.001:
		var toe := int(comp.get("manpower", 0))
		var left := maxi(0, int(round(float(toe) * str_v)))
		var fuel_pct := 100.0
		if "fuel_level" in formation:
			fuel_pct = clampf(float(formation.get("fuel_level")), 0.0, 1.0) * 100.0
		tips.append(
			"Speed %.1f · Armor %.0f%% · Men %d/%d"
			% [
				float(comp.get("speed", 1.0)),
				float(comp.get("armor", 0.0)) * 100.0,
				left,
				toe,
			]
		)
		tips.append("Width %.0f · Fuel %.0f%%" % [float(comp.get("width", 2.0)), fuel_pct])
	var stock := _stockpile_stock_line(formation)
	if not stock.is_empty():
		tips.append(stock)
	var clog := _combat_log_tip_lines(formation)
	for ln in clog:
		tips.append(ln)
	return tips


static func _combat_log_tip_lines(formation: Object) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if formation == null or not ("combat_log" in formation):
		return out
	var raw: Variant = formation.get("combat_log")
	if not (raw is Array):
		return out
	var log: Array = raw as Array
	var start := maxi(0, log.size() - 3)
	for i in range(start, log.size()):
		var row: Variant = log[i]
		if not (row is Dictionary):
			continue
		var d: Dictionary = row as Dictionary
		var date := str(d.get("date", "")).strip_edges()
		var outcome := str(d.get("outcome", d.get("result", ""))).strip_edges()
		var bits := PackedStringArray()
		if not date.is_empty():
			bits.append(date)
		if not outcome.is_empty():
			bits.append(outcome)
		if not bits.is_empty():
			out.append(" ".join(bits))
	return out


static func _toe_bits_from_comp(comp: Dictionary) -> PackedStringArray:
	var bits: PackedStringArray = PackedStringArray()
	var toe_eq: Dictionary = _safe_equipment_toe(comp)
	if toe_eq.is_empty():
		return bits
	var keys: Array = toe_eq.keys()
	keys.sort()
	for k in keys:
		if bits.size() >= 4:
			break
		var short := str(k).replace("_equipment", "").replace("_", " ").strip_edges()
		bits.append("%s %d" % [short, int(toe_eq[k])])
	return bits


static func _fill_ratio_for(formation: Object) -> float:
	if formation == null:
		return -1.0
	if not is_instance_valid(formation):
		return -1.0
	# Local toe_fill first — GER Division demo may have no ProductionManager stock.
	if "toe_fill" in formation:
		var tv: Variant = formation.get("toe_fill")
		if typeof(tv) == TYPE_FLOAT or typeof(tv) == TYPE_INT:
			return clampf(float(tv), 0.0, 2.0)
	if formation.has_method("has_meta") and bool(formation.has_meta("toe_fill")):
		var meta_fill := _safe_meta_float(formation, "toe_fill", -1.0)
		if meta_fill >= 0.0:
			return clampf(meta_fill, 0.0, 2.0)
	# Avoid calling ProductionManager.unit_toe_fill_ratio — get_formation_toe
	# type-casts Formation and can abort the card before body is parented.
	var fid := ""
	if "formation_id" in formation:
		var fid_v: Variant = formation.get("formation_id")
		if typeof(fid_v) == TYPE_STRING or typeof(fid_v) == TYPE_INT:
			fid = str(fid_v).strip_edges()
	if (
		not fid.is_empty()
		and typeof(ProductionManager) != TYPE_NIL
		and ProductionManager != null
		and ProductionManager.has_method("get_unit_equipment_stock")
	):
		var toe: Dictionary = _safe_equipment_toe(_safe_composition(formation))
		if not toe.is_empty():
			var have_stock: Dictionary = {}
			var stock_v: Variant = ProductionManager.call("get_unit_equipment_stock", fid)
			if stock_v is Dictionary:
				have_stock = stock_v as Dictionary
			var need := 0
			var have := 0
			for k in toe.keys():
				var n := int(toe[k])
				if n <= 0:
					continue
				need += n
				have += mini(n, maxi(0, int(have_stock.get(k, 0))))
			if need > 0:
				return clampf(float(have) / float(need), 0.0, 2.0)
	return -1.0


static func _fill_percent_line(formation: Object) -> String:
	var fill := _fill_ratio_for(formation)
	if fill < 0.0:
		# Strength% is casualties remaining — never alias it as Fill%.
		return "Fill —%"
	return "Fill %.0f%%" % (fill * 100.0)


static func _fill_toe_fold_line(formation: Object, comp: Dictionary) -> String:
	var fill_s := _fill_percent_line(formation)
	var bits := _toe_bits_from_comp(comp)
	if fill_s.is_empty() and bits.is_empty():
		return ""
	if bits.is_empty():
		return fill_s
	var toe_s := "TOE " + " · ".join(bits)
	if fill_s.is_empty():
		return toe_s
	return "%s · %s" % [fill_s, toe_s]


static func _stockpile_stock_line(formation: Object) -> String:
	if typeof(ProductionManager) == TYPE_NIL or ProductionManager == null:
		return ""
	var tag := ""
	if formation != null and is_instance_valid(formation) and "country_tag" in formation:
		tag = str(formation.get("country_tag")).strip_edges().to_upper()
	if tag.is_empty() or not ProductionManager.has_method("get_country_equipment_stockpile"):
		return ""
	var st_v: Variant = ProductionManager.call("get_country_equipment_stockpile", tag)
	if not (st_v is Dictionary):
		return ""
	var st: Dictionary = st_v as Dictionary
	var rifles := int(st.get("rifles", st.get("infantry_equipment", 0)))
	var trucks := int(st.get("trucks", st.get("truck", 0)))
	if rifles <= 0 and trucks <= 0:
		return ""
	return "stock rifles %d · trucks %d" % [rifles, trucks]


static func _stockpile_toe_line(formation: Object) -> String:
	# Fold helper kept for greps / older callers. Prefer Fill · TOE on the card.
	return _fill_percent_line(formation)


static func xp_band(xp: float) -> String:
	var x := clampf(xp, 0.0, 100.0)
	if x <= 20.0:
		return "Green"
	if x <= 40.0:
		return "Trained"
	if x <= 60.0:
		return "Regular"
	if x <= 80.0:
		return "Seasoned"
	return "Veteran"


static func _as_percent(raw: float) -> float:
	var v := raw
	if v <= 1.5:
		v *= 100.0
	return clampf(v, 0.0, 150.0)


static func _safe_composition(formation: Object) -> Dictionary:
	if formation == null or not is_instance_valid(formation):
		return {}
	# Demo GER Division often has no composition meta — skip LandCombatPower so
	# a missing/throwing helper cannot abort the docked card.
	if not _formation_has_composition_meta(formation):
		return {}
	if typeof(LandCombatPower) == TYPE_NIL:
		return {}
	if not LandCombatPower.has_method("composition_from_formation"):
		return {}
	var raw: Variant = LandCombatPower.composition_from_formation(formation)
	if raw is Dictionary:
		return raw as Dictionary
	return {}


static func _formation_has_composition_meta(formation: Object) -> bool:
	if formation == null:
		return false
	if "mobility" in formation or "armor_element" in formation or "equipment" in formation:
		return true
	if "infantry_bns" in formation or "tank_bns" in formation or "support" in formation:
		return true
	if not formation.has_method("has_meta"):
		return false
	return (
		bool(formation.has_meta("mobility"))
		or bool(formation.has_meta("armor_element"))
		or bool(formation.has_meta("infantry_bns"))
		or bool(formation.has_meta("tank_bns"))
		or bool(formation.has_meta("support"))
	)


static func _safe_equipment_toe(comp: Dictionary) -> Dictionary:
	if comp.is_empty():
		return {}
	if typeof(LandCombatPower) == TYPE_NIL:
		return {}
	if not LandCombatPower.has_method("equipment_toe"):
		return {}
	var raw: Variant = LandCombatPower.equipment_toe(comp)
	if raw is Dictionary:
		return raw as Dictionary
	return {}


static func _safe_float_prop(formation: Object, key: String, fallback: float) -> float:
	if formation == null or key.is_empty() or not (key in formation):
		return fallback
	var v: Variant = formation.get(key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_STRING and str(v).is_valid_float():
		return float(str(v))
	return fallback


static func _safe_meta_float(formation: Object, key: String, fallback: float) -> float:
	if formation == null or not formation.has_method("has_meta"):
		return fallback
	if not bool(formation.has_meta(key)):
		return fallback
	var v: Variant = formation.get_meta(key)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_STRING and str(v).is_valid_float():
		return float(str(v))
	return fallback
