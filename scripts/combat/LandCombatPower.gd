# scripts/combat/LandCombatPower.gd
class_name LandCombatPower
extends RefCounted

## Fielded-template land combat power. Offline SOT: land_combat_power_product.py
## CombatLoop can call these static helpers. Safe if SupplyManager / GameData are NIL.

const INFANTRY_SPEED := 1.0
const ARMOR_SPEED := 1.5
const BASE_POWER := 100.0
## Infantry + transport + tanks. Speed = min of remaining (mounted infantry drops foot).
const EL_SPEED := {
	"infantry": 1.0,
	"motorcycle": 2.4,
	"truck": 2.0,
	"halftrack": 1.6,
	"artillery": 0.85,
	"recon": 1.20,
	"engineer": 1.0,
	"anti_tank": 0.90,
	"anti_air": 0.90,
	"light_tank": 1.8,
	"medium_tank": 1.5,
	"heavy_tank": 1.2,
}
const EL_ARMOR := {
	"infantry": 0.0,
	"motorcycle": 0.0,
	"truck": 0.05,
	"halftrack": 0.35,
	"artillery": 0.05,
	"recon": 0.0,
	"engineer": 0.0,
	"anti_tank": 0.05,
	"anti_air": 0.05,
	"light_tank": 0.45,
	"medium_tank": 0.70,
	"heavy_tank": 0.90,
}
const EL_DEFENSE := {
	"infantry": 1.0,
	"motorcycle": 0.65,
	"truck": 0.75,
	"halftrack": 1.20,
	"artillery": 0.80,
	"recon": 0.40,
	"engineer": 0.90,
	"anti_tank": 0.60,
	"anti_air": 0.50,
	"light_tank": 1.10,
	"medium_tank": 1.30,
	"heavy_tank": 1.50,
}
const EL_MANPOWER := {
	"infantry": 3000,
	"motorcycle": 400,
	"truck": 200,
	"halftrack": 280,
	"artillery": 350,
	"recon": 120,
	"engineer": 250,
	"anti_tank": 220,
	"anti_air": 200,
	"light_tank": 400,
	"medium_tank": 500,
	"heavy_tank": 520,
}
const EL_SOFT := {
	"infantry": 1.0,
	"motorcycle": 0.85,
	"truck": 1.0,
	"halftrack": 1.05,
	"artillery": 1.40,
	"recon": 0.35,
	"engineer": 0.25,
	"anti_tank": 0.20,
	"anti_air": 0.40,
	"light_tank": 1.10,
	"medium_tank": 1.20,
	"heavy_tank": 1.15,
}
const EL_HARD := {
	"infantry": 0.15,
	"motorcycle": 0.10,
	"truck": 0.10,
	"halftrack": 0.35,
	"artillery": 0.45,
	"recon": 0.05,
	"engineer": 0.10,
	"anti_tank": 0.85,
	"anti_air": 0.20,
	"light_tank": 0.70,
	"medium_tank": 1.00,
	"heavy_tank": 1.25,
}
const EL_FUEL := {
	"infantry": 0.0,
	"motorcycle": 0.04,
	"truck": 0.06,
	"halftrack": 0.08,
	"artillery": 0.02,
	"recon": 0.03,
	"engineer": 0.02,
	"anti_tank": 0.02,
	"anti_air": 0.02,
	"light_tank": 0.12,
	"medium_tank": 0.16,
	"heavy_tank": 0.20,
}
const EL_SUPPLY := {
	"infantry": 0.8,
	"motorcycle": 0.4,
	"truck": 0.5,
	"halftrack": 0.6,
	"artillery": 0.5,
	"recon": 0.25,
	"engineer": 0.35,
	"anti_tank": 0.40,
	"anti_air": 0.35,
	"light_tank": 0.8,
	"medium_tank": 1.0,
	"heavy_tank": 1.2,
}
const EL_WIDTH := {
	"infantry": 2.0,
	"motorcycle": 0.0,
	"truck": 0.0,
	"halftrack": 0.0,
	"artillery": 0.0,
	"recon": 0.0,
	"engineer": 0.0,
	"anti_tank": 0.0,
	"anti_air": 0.0,
	"light_tank": 2.0,
	"medium_tank": 3.0,
	"heavy_tank": 3.0,
}
const EL_EQUIP := {
	"infantry": {"infantry_equipment": 80},
	"motorcycle": {"motorcycles": 40},
	"truck": {"trucks": 24},
	"halftrack": {"halftracks": 16},
	"artillery": {"artillery": 12},
	"recon": {"recon_equipment": 12},
	"engineer": {"support_equipment": 20},
	"anti_tank": {"anti_tank": 12},
	"anti_air": {"anti_air": 12},
	"light_tank": {"tanks": 12},
	"medium_tank": {"tanks": 10},
	"heavy_tank": {"tanks": 8},
}
const MOUNTED_IDS := ["motorcycle", "truck", "halftrack"]
const SKIP_SPEED_WHEN_MOUNTED := ["infantry", "artillery", "recon", "engineer", "anti_tank", "anti_air"]
const INFANTRY_BNS_MAX := 6
const TANK_BNS_MAX := 3
const ARMOR_PLAINS_HILLS := 1.5
const ARMOR_MOUNTAIN := 0.85
const MOUNTAIN_INFANTRY_MOUNTAIN := 1.15
const READINESS_MIN := 0.3
const READINESS_MAX := 1.2
const LEADER_BONUS_SCALE := 1.0
const LEADER_BONUS_CAP := 0.25


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
	var c: Dictionary = composition_from_formation(formation)
	var base := INFANTRY_SPEED
	if bool(c.get("has_composition", false)):
		base = float(c.get("speed", INFANTRY_SPEED))
	elif template_kind(formation) == "armor":
		base = ARMOR_SPEED
	return base * fuel_speed_mult(formation, float(c.get("fuel_use", 0.0)))


static func _split_supports(support: String) -> Array:
	var out: Array = []
	for part in str(support).replace(";", ",").split(","):
		var s := str(part).strip_edges().to_lower()
		if s.is_empty() or s in ["none", "foot"]:
			continue
		if s == "engineers":
			s = "engineer"
		if s in ["at", "anti-tank"]:
			s = "anti_tank"
		if s in ["aa", "anti-air"]:
			s = "anti_air"
		if EL_SPEED.has(s) and not out.has(s):
			out.append(s)
	return out


static func composition_stats(
	mobility: String = "foot",
	armor_element: String = "",
	core: String = "infantry",
	support: String = "",
	infantry_bns: int = 1,
	tank_bns: int = -1,
) -> Dictionary:
	var core_id := str(core).strip_edges().to_lower()
	if not EL_SPEED.has(core_id):
		core_id = "infantry"
	var mob := str(mobility).strip_edges().to_lower()
	if mob.is_empty() or mob == "none":
		mob = "foot"
	var arm := str(armor_element).strip_edges().to_lower()
	if arm in ["none", "foot"]:
		arm = ""
	var inf_n := clampi(int(infantry_bns), 1, INFANTRY_BNS_MAX)
	var tank_n := 0
	if int(tank_bns) < 0:
		tank_n = 1 if EL_SPEED.has(arm) else 0
	else:
		tank_n = clampi(int(tank_bns), 0, TANK_BNS_MAX)
		if tank_n <= 0:
			arm = ""
	if not EL_SPEED.has(arm):
		arm = ""
		tank_n = 0
	var sup_list: Array = _split_supports(support)
	var counts: Dictionary = {core_id: inf_n}
	if EL_SPEED.has(mob):
		counts[mob] = inf_n
	if arm != "":
		counts[arm] = tank_n
	for sid in sup_list:
		counts[str(sid)] = 1
	var ids: Array = [core_id]
	if EL_SPEED.has(mob) and not ids.has(mob):
		ids.append(mob)
	if EL_SPEED.has(arm) and not ids.has(arm):
		ids.append(arm)
	for sid in sup_list:
		if not ids.has(str(sid)):
			ids.append(str(sid))
	var mounted := false
	for i in ids:
		if str(i) in MOUNTED_IDS:
			mounted = true
			break
	var speeds: Array = []
	var armor_v := 0.0
	var defense := 0.0
	var men := 0
	var soft := 0.0
	var hard := 0.0
	var fuel_use := 0.0
	var supply_need := 0.0
	var width := 0.0
	var equip: Dictionary = {}
	for i in ids:
		var eid := str(i)
		var n := int(counts.get(eid, 1))
		if n <= 0:
			continue
		if not (mounted and eid in SKIP_SPEED_WHEN_MOUNTED):
			speeds.append(float(EL_SPEED.get(eid, 1.0)))
		armor_v = maxf(armor_v, float(EL_ARMOR.get(eid, 0.0)))
		defense += float(EL_DEFENSE.get(eid, 0.0)) * float(n)
		men += int(EL_MANPOWER.get(eid, 0)) * n
		soft += float(EL_SOFT.get(eid, 1.0)) * float(n)
		hard += float(EL_HARD.get(eid, 0.0)) * float(n)
		fuel_use += float(EL_FUEL.get(eid, 0.0)) * float(n)
		supply_need += float(EL_SUPPLY.get(eid, 0.0)) * float(n)
		width += float(EL_WIDTH.get(eid, 0.0)) * float(n)
		var pack: Dictionary = EL_EQUIP.get(eid, {}) as Dictionary if EL_EQUIP.get(eid, {}) is Dictionary else {}
		for ek in pack.keys():
			equip[str(ek)] = int(equip.get(str(ek), 0)) + int(pack[ek]) * n
	var speed := INFANTRY_SPEED
	if not speeds.is_empty():
		speed = float(speeds[0])
		for s in speeds:
			speed = minf(speed, float(s))
	var kind := "infantry"
	if arm != "":
		kind = "armor"
	elif mounted:
		kind = "motor"
	var has_comp := mounted or arm != "" or mob != "foot" or not sup_list.is_empty() or inf_n != 1 or tank_n > 1
	var sup_join := PackedStringArray()
	for sid in sup_list:
		sup_join.append(str(sid))
	return {
		"ok": true,
		"has_composition": has_comp,
		"ids": ids,
		"counts": counts,
		"mobility": mob,
		"armor_element": arm,
		"support": ",".join(sup_join),
		"supports": sup_list,
		"infantry_bns": inf_n,
		"tank_bns": tank_n,
		"speed": speed,
		"armor": armor_v,
		"defense": defense,
		"manpower": men,
		"soft": soft,
		"hard": hard,
		"fuel_use": fuel_use,
		"supply_need": supply_need,
		"width": width,
		"equipment": equip,
		"mounted": mounted,
		"kind": kind,
	}


static func composition_from_formation(formation: Object) -> Dictionary:
	var mob := "foot"
	var arm := ""
	var sup := ""
	var inf_n := 1
	var tank_n := -1
	if formation == null:
		return composition_stats(mob, arm, "infantry", sup, inf_n, tank_n)
	if formation.has_meta("mobility"):
		mob = str(formation.get_meta("mobility"))
	elif "mobility" in formation:
		mob = str(formation.get("mobility"))
	if formation.has_meta("armor_element"):
		arm = str(formation.get_meta("armor_element"))
	elif "armor_element" in formation:
		arm = str(formation.get("armor_element"))
	if formation.has_meta("support"):
		sup = str(formation.get_meta("support"))
	elif "support" in formation:
		sup = str(formation.get("support"))
	if formation.has_meta("infantry_bns"):
		inf_n = int(formation.get_meta("infantry_bns"))
	elif "infantry_bns" in formation:
		inf_n = int(formation.get("infantry_bns"))
	if formation.has_meta("tank_bns"):
		tank_n = int(formation.get_meta("tank_bns"))
	elif "tank_bns" in formation:
		tank_n = int(formation.get("tank_bns"))
	if arm.is_empty():
		arm = _infer_armor_element(formation)
	return composition_stats(mob, arm, "infantry", sup, inf_n, tank_n)


static func _infer_armor_element(formation: Object) -> String:
	var blob := _identity_blob(formation)
	if formation != null and formation.has_meta("visual_archetype"):
		blob += " " + str(formation.get_meta("visual_archetype")).to_lower()
	if "heavy" in blob and "tank" in blob:
		return "heavy_tank"
	if "light" in blob and "tank" in blob:
		return "light_tank"
	if _is_armor_blob(blob):
		return "medium_tank"
	return ""


static func equipment_toe(comp: Dictionary) -> Dictionary:
	var raw: Variant = comp.get("equipment", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for k in (raw as Dictionary).keys():
		out[str(k)] = int((raw as Dictionary)[k])
	return out


static func pierce_mult(hard: float, defender_armor: float) -> float:
	return clampf(1.0 + 0.18 * (float(hard) - float(defender_armor)), 0.70, 1.35)


static func shortage_mult(stock: Dictionary, toe: Dictionary) -> float:
	if toe.is_empty():
		return 1.0
	if stock.is_empty():
		return 1.0
	var need := 0
	var have := 0
	for k in toe.keys():
		var n := int(toe[k])
		if n <= 0:
			continue
		need += n
		have += mini(n, maxi(0, int(stock.get(k, 0))))
	if need <= 0:
		return 1.0
	return clampf(0.55 + 0.45 * (float(have) / float(need)), 0.55, 1.0)


static func fuel_speed_mult(formation: Object, fuel_use: float = -1.0) -> float:
	var use := float(fuel_use)
	if use < 0.0:
		use = float(composition_from_formation(formation).get("fuel_use", 0.0))
	if use <= 1e-9:
		return 1.0
	var f := _fuel_level_of(formation)
	if f >= 0.35:
		return 1.0
	return 0.45 + 0.55 * (f / 0.35)


static func fuel_power_mult(formation: Object, fuel_use: float = -1.0) -> float:
	var use := float(fuel_use)
	if use < 0.0:
		use = float(composition_from_formation(formation).get("fuel_use", 0.0))
	if use <= 1e-9:
		return 1.0
	var f := _fuel_level_of(formation)
	if f >= 0.30:
		return 1.0
	return 0.55 + 0.45 * (f / 0.30)


static func apply_fuel_burn(formation: Object, kind: String = "march") -> float:
	if formation == null:
		return 1.0
	var use := float(composition_from_formation(formation).get("fuel_use", 0.0))
	var cur := _fuel_level_of(formation)
	if use <= 1e-9:
		return cur
	var combat := str(kind).strip_edges().to_lower() == "combat"
	var rate := (0.10 + use * 0.22) if combat else (0.08 + use * 0.18)
	var nxt := clampf(cur - rate, 0.0, 1.0)
	_set_fuel_level(formation, nxt)
	return nxt


static func apply_fuel_resupply(formation: Object, amount: float = 0.10) -> float:
	if formation == null:
		return 1.0
	var nxt := clampf(_fuel_level_of(formation) + maxf(0.0, amount), 0.0, 1.0)
	_set_fuel_level(formation, nxt)
	return nxt


static func _fuel_level_of(formation: Object) -> float:
	if formation == null:
		return 1.0
	if "fuel_level" in formation:
		return clampf(float(formation.get("fuel_level")), 0.0, 1.0)
	if formation.has_meta("fuel_level"):
		return clampf(float(formation.get_meta("fuel_level")), 0.0, 1.0)
	return 1.0


static func _set_fuel_level(formation: Object, value: float) -> void:
	if formation == null:
		return
	var v := clampf(value, 0.0, 1.0)
	if "fuel_level" in formation:
		formation.set("fuel_level", v)
	else:
		formation.set_meta("fuel_level", v)


static func shortage_mult_for_formation(formation: Object, comp: Dictionary = {}) -> float:
	if formation == null or typeof(ProductionManager) == TYPE_NIL:
		return 1.0
	var fid := ""
	if "formation_id" in formation:
		fid = str(formation.get("formation_id"))
	if fid.is_empty() or not ProductionManager.has_method("get_unit_equipment_stock"):
		return 1.0
	var stock: Dictionary = ProductionManager.get_unit_equipment_stock(fid)
	if stock.is_empty():
		return 1.0
	var toe: Dictionary = equipment_toe(comp if not comp.is_empty() else composition_from_formation(formation))
	return shortage_mult(stock, toe)


static func combat_power(formation: Object, terrain: String = "plains", role: String = "", opponent: Object = null) -> float:
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
	var comp: Dictionary = composition_from_formation(formation)
	if bool(comp.get("has_composition", false)):
		var soft_c := float(comp.get("soft", 0.0))
		power *= 0.70 + 0.12 * clampf(soft_c, 0.5, 4.0)
		var hard_c := float(comp.get("hard", 0.0))
		power *= 0.92 + 0.08 * clampf(hard_c, 0.0, 2.0)
		var armor_v := float(comp.get("armor", 0.0))
		if _resolve_combat_role(formation, role) == "defend":
			power *= (1.0 + 0.30 * clampf(armor_v, 0.0, 1.0))
			power *= clampf(0.75 + 0.20 * float(comp.get("defense", 1.0)), 0.75, 1.35)
		else:
			power *= (1.0 + 0.12 * clampf(armor_v, 0.0, 1.0))
			if opponent != null:
				var oc: Dictionary = composition_from_formation(opponent)
				power *= pierce_mult(hard_c, float(oc.get("armor", 0.0)))
	else:
		var soft = _try_template_soft_attack(formation)
		if soft != null:
			power *= 0.7 + 0.3 * float(soft)
		if opponent != null and _resolve_combat_role(formation, role) != "defend":
			var oc2: Dictionary = composition_from_formation(opponent)
			if float(oc2.get("armor", 0.0)) > 0.001:
				power *= pierce_mult(0.15, float(oc2.get("armor", 0.0)))
	power *= fuel_power_mult(formation, float(comp.get("fuel_use", 0.0)))
	power *= shortage_mult_for_formation(formation, comp)
	power *= leader_power_mult(formation, terrain, role)
	if "combat_experience" in formation:
		power *= xp_power_mult(float(formation.get("combat_experience")))
	return float(power)


## Green ~0.80 · regular ~1.0 · veteran ~1.18. Same curve as ReinforcementLogisticsCalculator.
static func xp_power_mult(xp: float) -> float:
	var x := clampf(xp, 0.0, 100.0)
	if x <= 20.0:
		return lerpf(0.78, 0.88, x / 20.0)
	if x <= 40.0:
		return lerpf(0.88, 0.98, (x - 20.0) / 20.0)
	if x <= 60.0:
		return lerpf(0.98, 1.0, (x - 40.0) / 20.0)
	if x <= 80.0:
		return lerpf(1.0, 1.1, (x - 60.0) / 20.0)
	return lerpf(1.1, 1.2, (x - 80.0) / 20.0)


static func dilute_xp_replacements(old_xp: float, strength_gain: float, new_strength: float, recruit_xp: float = 22.0) -> float:
	var old_v := clampf(old_xp, 0.0, 100.0)
	var rec := clampf(recruit_xp, 0.0, 100.0)
	var gain := maxf(0.0, strength_gain)
	var new_s := maxf(0.05, new_strength)
	var frac := clampf(gain / new_s, 0.0, 1.0)
	var blended := (1.0 - frac) * old_v + frac * rec
	blended += 0.30 * (1.0 - frac)
	return clampf(blended, 0.0, 100.0)


static func dilute_xp_heavy_loss(old_xp: float, strength_lost: float) -> float:
	var drop := maxf(0.0, strength_lost)
	if drop < 0.08:
		return clampf(old_xp, 0.0, 100.0)
	return clampf(old_xp * (1.0 - 0.20 * drop), 0.0, 100.0)


## 1.0 + clamp(attack|defense * scale, 0, 0.25). Attacker=attack; defender=defense else attack*0.6
static func leader_power_mult(formation: Object, terrain: String = "plains", role: String = "") -> float:
	if formation == null:
		return 1.0
	var mods := _leader_mods(formation, terrain)
	if not bool(mods.get("has_leader", false)):
		return 1.0
	var raw := 0.0
	if _resolve_combat_role(formation, role) == "defend":
		if bool(mods.get("has_defense", false)):
			raw = float(mods.get("defense", 0.0))
		else:
			raw = float(mods.get("attack", 0.0)) * 0.6
	else:
		raw = float(mods.get("attack", 0.0))
	raw += float(mods.get("terrain", 0.0))
	return 1.0 + clampf(raw * LEADER_BONUS_SCALE, 0.0, LEADER_BONUS_CAP)


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


static func _prop_opt(obj: Object, names: Array) -> Variant:
	if obj == null:
		return null
	for n in names:
		var key := str(n)
		if key in obj:
			return float(obj.get(key))
	return null


static func _resolve_combat_role(formation: Object, role: String) -> String:
	var r := str(role).strip_edges().to_lower()
	if r in ["defend", "defender", "defense", "def"]:
		return "defend"
	if r in ["attack", "attacker", "offense", "offence", "att"]:
		return "attack"
	if formation == null:
		return "attack"
	if "is_defender" in formation and bool(formation.get("is_defender")):
		return "defend"
	var cr := ""
	if "combat_role" in formation:
		cr = str(formation.get("combat_role"))
	elif "role" in formation:
		cr = str(formation.get("role"))
	var crl := cr.strip_edges().to_lower()
	if crl in ["defend", "defender", "defense", "def"]:
		return "defend"
	var mission := ""
	if "current_land_mission" in formation:
		mission = str(formation.get("current_land_mission")).strip_edges().to_upper()
	if mission in ["DEFEND", "GARRISON"]:
		return "defend"
	return "attack"


static func _leader_from_formation(formation: Object) -> Object:
	if formation == null:
		return null
	if "assigned_leader" in formation:
		var assigned = formation.get("assigned_leader")
		if assigned != null and typeof(assigned) == TYPE_OBJECT:
			return assigned
	if "leader" in formation:
		var nested = formation.get("leader")
		if nested != null and typeof(nested) == TYPE_OBJECT:
			return nested
	var lid := ""
	if "assigned_leader_id" in formation:
		lid = str(formation.get("assigned_leader_id")).strip_edges()
	if lid.is_empty() and "leader_id" in formation:
		lid = str(formation.get("leader_id")).strip_edges()
	if typeof(LeaderManager) != TYPE_NIL:
		if not lid.is_empty() and LeaderManager.has_method("get_leader"):
			var by_id = LeaderManager.get_leader(lid)
			if by_id != null:
				return by_id
		if "formation_id" in formation and LeaderManager.has_method("get_leader_for_army"):
			var by_army = LeaderManager.get_leader_for_army(str(formation.get("formation_id")))
			if by_army != null:
				return by_army
	return null


static func _leader_mods(formation: Object, terrain: String) -> Dictionary:
	var out := {
		"has_leader": false,
		"has_defense": false,
		"attack": 0.0,
		"defense": 0.0,
		"terrain": 0.0,
	}
	var leader: Object = _leader_from_formation(formation)
	var src: Object = leader if leader != null else formation
	if src == null:
		return out
	var attack: Variant = null
	var defense: Variant = null
	if src.has_method("get_attack_modifier"):
		attack = float(src.call("get_attack_modifier"))
		out["has_leader"] = true
	else:
		attack = _prop_opt(src, ["attack_modifier", "attack"])
	if src.has_method("get_defense_modifier"):
		defense = float(src.call("get_defense_modifier"))
		out["has_defense"] = true
		out["has_leader"] = true
	else:
		defense = _prop_opt(src, ["defense_modifier", "defense"])
		if defense != null:
			out["has_defense"] = true
	if attack != null:
		out["attack"] = float(attack)
		out["has_leader"] = true
	if defense != null:
		out["defense"] = float(defense)
		out["has_leader"] = true
	if src.has_method("get_terrain_modifier"):
		out["terrain"] = float(src.call("get_terrain_modifier", terrain))
	else:
		var tmod = _prop_opt(src, ["terrain_modifier"])
		if tmod != null:
			out["terrain"] = float(tmod)
	return out


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
	var c: Dictionary = composition_from_formation(formation)
	if bool(c.get("has_composition", false)) and float(c.get("width", 0.0)) > 0.1:
		return maxf(0.1, float(c.get("width")))
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
