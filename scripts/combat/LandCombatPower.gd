# scripts/combat/LandCombatPower.gd
class_name LandCombatPower
extends RefCounted

## Fielded-template land combat power. Offline SOT: land_combat_power_product.py
## CombatLoop can call these static helpers. Safe if SupplyManager / GameData are NIL.

const INFANTRY_SPEED := 1.0
const ARMOR_SPEED := 1.5
const BASE_POWER := 100.0
const ARMOR_PLAINS_HILLS := 1.5
const ARMOR_MOUNTAIN := 0.85
const MOUNTAIN_INFANTRY_MOUNTAIN := 1.15
const READINESS_MIN := 0.3
const READINESS_MAX := 1.2


static func template_kind(formation: Object) -> String:
	if formation == null:
		return "infantry"
	var blob := _identity_blob(formation)
	var kind := "infantry"
	if "mountain" in blob or "gebirg" in blob:
		kind = "mountain_infantry"
	if _is_armor_blob(blob):
		kind = "armor"
	return kind


static func template_speed(formation: Object) -> float:
	if template_kind(formation) == "armor":
		return ARMOR_SPEED
	return INFANTRY_SPEED


static func combat_power(formation: Object, terrain: String = "plains") -> float:
	if formation == null:
		return 0.0
	var org := _prop_f(formation, ["organization", "org"], 1.0)
	var strength := _prop_f(formation, ["strength"], 1.0)
	var readiness := clampf(_prop_f(formation, ["readiness"], 1.0), READINESS_MIN, READINESS_MAX)
	var power := BASE_POWER * org * strength * readiness
	var kind := template_kind(formation)
	var terr := _norm_terrain(terrain)
	if kind == "armor":
		if terr == "plains" or terr == "hills":
			power *= ARMOR_PLAINS_HILLS
		elif terr == "mountain":
			power *= ARMOR_MOUNTAIN
	elif kind == "mountain_infantry" and terr == "mountain":
		power *= MOUNTAIN_INFANTRY_MOUNTAIN
	var soft = _try_template_soft_attack(formation)
	if soft != null:
		power *= 0.7 + 0.3 * float(soft)
	return float(power)


static func _identity_blob(formation: Object) -> String:
	var blob := ""
	if formation == null:
		return blob
	if "design_id" in formation:
		blob += str(formation.design_id)
	if "name" in formation:
		blob += " " + str(formation.name)
	if "formation_type" in formation:
		blob += " " + str(formation.formation_type)
	if "formation_id" in formation:
		blob += " " + str(formation.formation_id)
	return blob.to_lower()


static func _is_armor_blob(blob: String) -> bool:
	return "armor" in blob or "armour" in blob or "panzer" in blob or "tank" in blob


static func _norm_terrain(raw: String) -> String:
	var t := str(raw).strip_edges().to_lower()
	if t in ["mountain", "mountains", "alpine", "snow_capped"]:
		return "mountain"
	if t in ["hills", "hill", "highland"]:
		return "hills"
	if t.is_empty():
		return "plains"
	return t


static func _prop_f(obj: Object, names: Array, fallback: float) -> float:
	if obj == null:
		return fallback
	for n in names:
		var key := str(n)
		if key in obj:
			return float(obj.get(key))
	return fallback


static func _try_template_soft_attack(formation: Object) -> Variant:
	var fid := ""
	var did := ""
	if formation != null:
		if "formation_id" in formation:
			fid = str(formation.formation_id)
		if "design_id" in formation:
			did = str(formation.design_id)
	var div: Object = _try_supply_division(fid)
	if div == null:
		div = _try_supply_division(did)
	var soft = _soft_from_loaded(div)
	if soft != null:
		return soft
	return _soft_from_loaded(_try_design_template(did))


static func _try_supply_division(id: String) -> Object:
	if id.is_empty():
		return null
	if typeof(SupplyManager) == TYPE_NIL:
		return null
	if not ("division_templates" in SupplyManager):
		return null
	var loader = SupplyManager.division_templates
	if loader == null or not loader.has_method("get_division"):
		return null
	return loader.get_division(id)


static func _try_design_template(id: String) -> Object:
	if id.is_empty():
		return null
	if typeof(GameData) == TYPE_NIL:
		return null
	if not ("design_data" in GameData) or GameData.design_data == null:
		return null
	if not GameData.design_data.has_method("get_template"):
		return null
	return GameData.design_data.get_template(id)


static func _soft_from_loaded(obj: Object) -> Variant:
	if obj == null:
		return null
	if obj.has_method("get_combined_combat_modifiers"):
		var mods = obj.call("get_combined_combat_modifiers")
		var from_mods = _soft_from_dict(mods)
		if from_mods != null:
			return from_mods
	if obj.has_method("get_aggregated_infantry_stats"):
		var stats = obj.call("get_aggregated_infantry_stats")
		var from_stats = _soft_from_dict(stats)
		if from_stats != null:
			return from_stats
	if obj.has_method("get_final_combat_stats"):
		var final_stats = obj.call("get_final_combat_stats")
		var from_final = _soft_from_dict(final_stats)
		if from_final != null:
			return from_final
	if "infantry_equipment_stats" in obj:
		var from_inf = _soft_from_dict(obj.get("infantry_equipment_stats"))
		if from_inf != null:
			return from_inf
	if "base_stats" in obj:
		return _soft_from_dict(obj.get("base_stats"))
	return null


static func _soft_from_dict(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if not d.has("soft_attack"):
		return null
	return float(d.get("soft_attack"))


const BASE_COMBAT_WIDTH := 10.0
const OVERWIDTH_FACTOR := 0.35
const INFANTRY_WIDTH := 2.0
const ARMOR_WIDTH := 3.0


static func unit_width(formation: Object) -> float:
	if template_kind(formation) == "armor":
		return ARMOR_WIDTH
	return INFANTRY_WIDTH


static func combat_width_for_terrain(terrain: String, infra_level: int = 2) -> float:
	# mirrors data/combat/combat_width_rules.json
	var terr := _norm_terrain(terrain)
	var tmod := 1.0
	match terr:
		"hills":
			tmod = 0.85
		"forest":
			tmod = 0.75
		"jungle":
			tmod = 0.55
		"mountain":
			tmod = 0.45
		"urban":
			tmod = 0.65
		"marsh":
			tmod = 0.60
		"desert":
			tmod = 0.90
		"arctic":
			tmod = 0.50
	var il := clampi(infra_level, 0, 5)
	var imod := 1.0
	match il:
		0:
			imod = 0.6
		1:
			imod = 0.8
		3:
			imod = 1.2
		4:
			imod = 1.4
		5:
			imod = 1.6
	return BASE_COMBAT_WIDTH * tmod * imod


static func engaged_power(powers: Array, widths: Array, combat_width: float) -> float:
	var rows: Array = []
	for i in powers.size():
		var p := float(powers[i])
		var w := INFANTRY_WIDTH
		if i < widths.size():
			w = maxf(0.1, float(widths[i]))
		rows.append([p, w])
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var remaining := maxf(0.1, combat_width)
	var total := 0.0
	for row in rows:
		var power := float(row[0])
		var width := float(row[1])
		if remaining <= 1e-6:
			total += power * OVERWIDTH_FACTOR
			continue
		if width <= remaining:
			total += power
			remaining -= width
		else:
			var frac := remaining / width
			total += power * frac + power * (1.0 - frac) * OVERWIDTH_FACTOR
			remaining = 0.0
	return total
