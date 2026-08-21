# scripts/ui/UnitCardCombatStrip.gd
## Docked unit-card combat lines. Director: lines.append_array(UnitCardCombatStrip.lines_for(formation))
## Offline SOT: tools/map_generation/lib/unit_card_combat_strip_product.py
class_name UnitCardCombatStrip
extends RefCounted


static func lines_for(formation: Object) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if formation == null:
		return lines
	var xp := 48.0
	if "combat_experience" in formation:
		xp = float(formation.get("combat_experience"))
	lines.append("XP %s" % xp_band(xp))
	if "planning" in formation:
		lines.append("Planning %.0f%%" % _as_percent(float(formation.get("planning"))))
	if "entrenchment" in formation:
		lines.append("Entrenchment %.0f%%" % _as_percent(float(formation.get("entrenchment"))))
	if "last_equip_loss_plain" in formation:
		var loss := str(formation.get("last_equip_loss_plain")).strip_edges()
		if not loss.is_empty():
			lines.append(loss)
	if "last_supply_plain" in formation:
		var sup := str(formation.get("last_supply_plain")).strip_edges()
		if not sup.is_empty():
			lines.append(sup)
	var str_v := 1.0
	if "strength" in formation:
		str_v = float(formation.get("strength"))
	lines.append("Strength %.0f%%" % _as_percent(str_v))
	var comp: Dictionary = LandCombatPower.composition_from_formation(formation)
	if bool(comp.get("has_composition", false)) or float(comp.get("armor", 0.0)) > 0.001:
		var toe := int(comp.get("manpower", 0))
		var left := maxi(0, int(round(float(toe) * str_v)))
		var fuel_pct := 100.0
		if "fuel_level" in formation:
			fuel_pct = clampf(float(formation.get("fuel_level")), 0.0, 1.0) * 100.0
		lines.append(
			"Speed %.1f · Armor %.0f%% · Men %d/%d"
			% [
				float(comp.get("speed", 1.0)),
				float(comp.get("armor", 0.0)) * 100.0,
				left,
				toe,
			]
		)
		lines.append(
			"Width %.0f · Fuel %.0f%%"
			% [float(comp.get("width", 2.0)), fuel_pct]
		)
		var toe_eq: Dictionary = LandCombatPower.equipment_toe(comp)
		if not toe_eq.is_empty():
			var bits: PackedStringArray = PackedStringArray()
			var keys: Array = toe_eq.keys()
			keys.sort()
			for k in keys:
				if bits.size() >= 4:
					break
				var short := str(k).replace("_equipment", "").replace("_", " ")
				bits.append("%s %d" % [short, int(toe_eq[k])])
			if not bits.is_empty():
				lines.append("TOE " + " · ".join(bits))
		var stock_line := _stockpile_toe_line(formation)
		if not stock_line.is_empty():
			lines.append(stock_line)
	if "last_manpower_loss" in formation:
		var men_l := int(formation.get("last_manpower_loss"))
		if men_l > 0 and "last_equip_loss_plain" not in formation:
			lines.append("men −%d" % men_l)
	if "is_training" in formation and bool(formation.get("is_training")):
		var prog := float(formation.get("training_progress")) if "training_progress" in formation else 0.0
		var need := 14.0
		var mode := "new"
		if formation.has_method("has_meta"):
			if bool(formation.has_meta("organize_days")):
				need = float(formation.get_meta("organize_days"))
			if bool(formation.has_meta("organize_mode")):
				mode = str(formation.get_meta("organize_mode"))
		if mode == "refit":
			lines.append("Refit %d/%dd · org/str recovering" % [int(prog), int(need)])
		else:
			lines.append("Training %d/%dd · not combat-ready" % [int(prog), int(need)])
	if "combat_log" in formation:
		var raw: Variant = formation.get("combat_log")
		if raw is Array:
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
					lines.append(" ".join(bits))
	return lines


static func bbcode_for(formation: Object) -> String:
	return "\n".join(lines_for(formation))



static func _stockpile_toe_line(formation: Object) -> String:
	if typeof(ProductionManager) == TYPE_NIL:
		return ""
	var fid := ""
	if "formation_id" in formation:
		fid = str(formation.get("formation_id")).strip_edges()
	if fid.is_empty():
		return ""
	var fill := 0.0
	if ProductionManager.has_method("unit_toe_fill_ratio"):
		fill = float(ProductionManager.unit_toe_fill_ratio(fid))
	var tag := ""
	if "country_tag" in formation:
		tag = str(formation.get("country_tag")).strip_edges().to_upper()
	var rifles := 0
	var trucks := 0
	if not tag.is_empty() and ProductionManager.has_method("get_country_equipment_stockpile"):
		var st: Dictionary = ProductionManager.get_country_equipment_stockpile(tag)
		rifles = int(st.get("rifles", st.get("infantry_equipment", 0)))
		trucks = int(st.get("trucks", st.get("truck", 0)))
	var last := ""
	if "last_stockpile_toe_plain" in ProductionManager:
		last = str(ProductionManager.last_stockpile_toe_plain).strip_edges()
	if fill <= 0.0 and rifles <= 0 and trucks <= 0 and last.is_empty():
		return ""
	if last.is_empty():
		return "Fill %.0f%% · stock rifles %d · trucks %d" % [fill * 100.0, rifles, trucks]
	return last


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
