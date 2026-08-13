# scripts/production/ReinforcementLogisticsCalculator.gd
## Pure helpers for reinforce_experience_logistics_ledger (RF0/RF1).
## Transit time, hub distance, era mobility, experience blend — no autoload required.
class_name ReinforcementLogisticsCalculator
extends RefCounted

const MODEL := "reinforce_experience_logistics_ledger"

const MODE_BASE_DAYS: Dictionary = {
	"rail": 1.0,
	"road": 1.5,
	"sealift": 2.2,
	"river": 1.3,
	"airlift": 0.45,
	"helicopter": 0.65,
	"drone_logistics": 0.35,
	"orbital": 0.12,
}

const ERA_MOBILITY: Dictionary = {
	"rail_age": 0.72,
	"motor_air_dawn": 0.95,
	"airlift_age": 1.25,
	"network_drone": 1.55,
	"orbital_support": 1.9,
}

## Policy → { recruit_xp 0–100, training_days, throughput, manpower_qty_mult }
const TRAINING_POLICIES: Dictionary = {
	"volunteer_cadre": {"recruit_xp": 52.0, "training_days": 180.0, "throughput": 0.85, "manpower_qty": 0.55},
	"short_conscript": {"recruit_xp": 22.0, "training_days": 45.0, "throughput": 1.15, "manpower_qty": 1.35},
	"two_year_service": {"recruit_xp": 38.0, "training_days": 120.0, "throughput": 1.0, "manpower_qty": 1.0},
	"wartime_crash": {"recruit_xp": 12.0, "training_days": 14.0, "throughput": 1.4, "manpower_qty": 1.7},
	"selective_service": {"recruit_xp": 34.0, "training_days": 90.0, "throughput": 1.05, "manpower_qty": 0.95},
	"all_volunteer_force": {"recruit_xp": 48.0, "training_days": 150.0, "throughput": 0.9, "manpower_qty": 0.65},
	"reserve_recall": {"recruit_xp": 42.0, "training_days": 30.0, "throughput": 1.1, "manpower_qty": 1.2},
	"national_service": {"recruit_xp": 36.0, "training_days": 100.0, "throughput": 1.0, "manpower_qty": 1.05},
	"vr_holodeck_pipeline": {"recruit_xp": 40.0, "training_days": 40.0, "throughput": 1.25, "manpower_qty": 0.9},
	"clone_batch_fill": {"recruit_xp": 8.0, "training_days": 3.0, "throughput": 1.8, "manpower_qty": 2.2},
	"space_cadre_loft": {"recruit_xp": 60.0, "training_days": 200.0, "throughput": 0.7, "manpower_qty": 0.2},
}


static func normalize_mode(mode: String) -> String:
	var m := mode.strip_edges().to_lower()
	if MODE_BASE_DAYS.has(m):
		return m
	return "rail"


static func era_band_for_year(year: int) -> String:
	var y := year
	if y < 1936:
		return "rail_age"
	if y < 1956:
		return "motor_air_dawn"
	if y < 1996:
		return "airlift_age"
	if y < 2041:
		return "network_drone"
	return "orbital_support"


static func era_mobility(year: int = 1939, era_band: String = "") -> float:
	var band := era_band.strip_edges()
	if band.is_empty():
		band = era_band_for_year(year)
	return float(ERA_MOBILITY.get(band, 1.0))


static func base_mode_days(mode: String) -> float:
	return float(MODE_BASE_DAYS.get(normalize_mode(mode), 1.0))


## distance_km from unit to nearest friendly hub; 0 = at hub.
static func distance_factor(distance_km: float) -> float:
	var d := maxf(0.0, distance_km)
	# 0 km → 1.0; 500 km → ~1.5; 2000 km → ~2.6 (soft curve)
	return clampf(1.0 + sqrt(d / 500.0) * 0.55, 1.0, 3.5)


static func hub_access_mult(depot_fill: float = 1.0, corridor_control: float = 1.0) -> float:
	var fill := clampf(depot_fill, 0.0, 1.5)
	var corr := clampf(corridor_control, 0.0, 1.0)
	return clampf(0.55 + fill * 0.35 + corr * 0.35, 0.55, 1.25)


static func resource_fill_mult(fuel: float = 1.0, supplies: float = 1.0, electronics: float = 1.0, mode: String = "rail") -> float:
	var f := clampf(fuel, 0.0, 1.0)
	var s := clampf(supplies, 0.0, 1.0)
	var e := clampf(electronics, 0.0, 1.0)
	var m := normalize_mode(mode)
	var mult := 0.45 * s + 0.35 * f + 0.2
	if m == "airlift" or m == "helicopter":
		mult = 0.55 * f + 0.3 * s + 0.15
	elif m == "drone_logistics":
		mult = 0.4 * e + 0.35 * f + 0.25 * s
	elif m == "orbital":
		mult = 0.45 * e + 0.35 * f + 0.2 * s
	return clampf(mult, 0.5, 1.0)


static func policy_profile(policy_id: String) -> Dictionary:
	var p := policy_id.strip_edges().to_lower()
	if TRAINING_POLICIES.has(p):
		return (TRAINING_POLICIES[p] as Dictionary).duplicate(true)
	return (TRAINING_POLICIES["two_year_service"] as Dictionary).duplicate(true)


static func recruit_xp_for_policy(policy_id: String) -> float:
	return float(policy_profile(policy_id).get("recruit_xp", 30.0))


static func training_throughput(policy_id: String) -> float:
	return float(policy_profile(policy_id).get("throughput", 1.0))


## Core transit clock — RF1 lock.
static func transit_days(
	mode: String = "rail",
	hops: int = 1,
	distance_km: float = 0.0,
	year: int = 1939,
	depot_fill: float = 1.0,
	corridor_control: float = 1.0,
	fuel: float = 1.0,
	supplies: float = 1.0,
	electronics: float = 1.0,
	policy_id: String = "two_year_service",
	for_manpower: bool = false,
) -> float:
	var m := normalize_mode(mode)
	var base := base_mode_days(m)
	var hop_n := maxi(1, hops)
	var dist := distance_factor(distance_km)
	var era := era_mobility(year)
	var hub := hub_access_mult(depot_fill, corridor_control)
	var res := resource_fill_mult(fuel, supplies, electronics, m)
	var train := 1.0
	if for_manpower:
		train = clampf(training_throughput(policy_id), 0.55, 1.8)
	var raw := (base * float(hop_n) * dist) / maxf(0.35, era * hub * res * train)
	return clampf(raw, 0.25, 90.0)


## Manpower refill blend — surviving cadre keeps knowledge; greens dilute.
static func blend_combat_experience_manpower(
	old_xp: float,
	recruit_xp: float,
	fraction_replaced: float,
	cadre_bonus: float = 2.0,
) -> float:
	var old_v := clampf(old_xp, 0.0, 100.0)
	var rec := clampf(recruit_xp, 0.0, 100.0)
	var frac := clampf(fraction_replaced, 0.0, 1.0)
	var blended := (1.0 - frac) * old_v + frac * rec
	# Surviving cadre mentors slightly if unit not wiped
	blended += cadre_bonus * (1.0 - frac) * 0.15
	return clampf(blended, 0.0, 100.0)


## Equipment rearm — much smaller XP hit than manpower (warriors learn tools).
static func blend_combat_experience_rearm(
	old_xp: float,
	rearm_fraction: float,
	novelty: float = 0.35,
	rearm_penalty: float = 8.0,
) -> float:
	var old_v := clampf(old_xp, 0.0, 100.0)
	var frac := clampf(rearm_fraction, 0.0, 1.0)
	var nov := clampf(novelty, 0.0, 1.0)
	return clampf(old_v - rearm_penalty * frac * nov, 0.0, 100.0)


static func experience_combat_mult(xp: float) -> float:
	var x := clampf(xp, 0.0, 100.0)
	# Green ~0.80, regular ~1.0, veteran ~1.18
	if x <= 20.0:
		return lerpf(0.78, 0.88, x / 20.0)
	if x <= 40.0:
		return lerpf(0.88, 0.98, (x - 20.0) / 20.0)
	if x <= 60.0:
		return lerpf(0.98, 1.0, (x - 40.0) / 20.0)
	if x <= 80.0:
		return lerpf(1.0, 1.1, (x - 60.0) / 20.0)
	return lerpf(1.1, 1.2, (x - 80.0) / 20.0)


static func experience_band(xp: float) -> String:
	var x := clampf(xp, 0.0, 100.0)
	if x <= 20.0:
		return "green"
	if x <= 40.0:
		return "trained"
	if x <= 60.0:
		return "regular"
	if x <= 80.0:
		return "seasoned"
	return "veteran"


## Daily strength absorb cap after replacements arrive (fraction of TOE).
static func daily_strength_absorb_cap(
	hub_access: float = 1.0,
	policy_id: String = "two_year_service",
	org: float = 1.0,
) -> float:
	var thr := training_throughput(policy_id)
	var base := 0.04 * thr * clampf(hub_access, 0.55, 1.25) * clampf(org, 0.4, 1.2)
	return clampf(base, 0.02, 0.12)


static func attribution_plain_transit(
	mode: String,
	days: float,
	distance_km: float,
	year: int,
) -> String:
	return "Reinforcements via %s: ~%.1f days (%.0f km, era %s)." % [
		normalize_mode(mode), days, distance_km, era_band_for_year(year),
	]


static func attribution_plain_xp_dilution(
	old_xp: float,
	new_xp: float,
	formation_label: String = "formation",
) -> String:
	var band_old := experience_band(old_xp)
	var band_new := experience_band(new_xp)
	if new_xp < old_xp - 0.5:
		return "%s experience diluted %s→%s (%.0f→%.0f) as green replacements joined." % [
			formation_label, band_old, band_new, old_xp, new_xp,
		]
	return "%s experience held steady (%s, %.0f)." % [formation_label, band_new, new_xp]


## --- RF2–RF4 helpers: mode unlock, policy matrix, non-instant checks ------------

static func list_training_policy_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for k in TRAINING_POLICIES.keys():
		out.append(str(k))
	return out


static func policy_tradeoff_score(policy_id: String) -> Dictionary:
	## Higher qty vs higher quality are opposing axes (not free stack).
	var p := policy_profile(policy_id)
	var qty := float(p.get("manpower_qty", 1.0))
	var quality := float(p.get("recruit_xp", 30.0)) / 100.0
	var days := float(p.get("training_days", 90.0))
	return {
		"policy_id": policy_id.strip_edges().to_lower(),
		"manpower_qty": qty,
		"recruit_xp": float(p.get("recruit_xp", 30.0)),
		"training_days": days,
		"throughput": float(p.get("throughput", 1.0)),
		"quality_axis": quality,
		"quantity_axis": clampf(qty / 2.2, 0.0, 1.0),
		"tradeoff_plain": _policy_tradeoff_plain(policy_id, qty, float(p.get("recruit_xp", 30.0)), days),
	}


static func _policy_tradeoff_plain(policy_id: String, qty: float, xp: float, days: float) -> String:
	return "Policy %s: qty×%.2f · recruit XP %.0f · train %.0fd (quality↔quantity trade-off)." % [
		policy_id, qty, xp, days,
	]


## Advanced modes need era and optional tech flags (RF4).
## tech_flags: { "drone_logistics": bool, "orbital_lift": bool, "strategic_airlift": bool }
static func mode_unlocked(mode: String, year: int = 1939, tech_flags: Dictionary = {}) -> bool:
	var m := normalize_mode(mode)
	var band := era_band_for_year(year)
	match m:
		"rail", "road", "river", "sealift":
			return true
		"airlift":
			if year >= 1942:
				return true
			return bool(tech_flags.get("strategic_airlift", false))
		"helicopter":
			return year >= 1955 or bool(tech_flags.get("helicopter_lift", false))
		"drone_logistics":
			if band == "network_drone" or band == "orbital_support" or year >= 2005:
				return true
			return bool(tech_flags.get("drone_logistics", false))
		"orbital":
			if band == "orbital_support" or year >= 2045:
				return true
			return bool(tech_flags.get("orbital_lift", false))
		_:
			return false


static func preferred_reinforce_mode(year: int = 1939, tech_flags: Dictionary = {}, overseas: bool = false) -> String:
	if mode_unlocked("orbital", year, tech_flags) and bool(tech_flags.get("prefer_orbital", false)):
		return "orbital"
	if mode_unlocked("drone_logistics", year, tech_flags) and year >= 2010:
		return "drone_logistics"
	if mode_unlocked("airlift", year, tech_flags) and year >= 1956:
		return "airlift"
	if mode_unlocked("helicopter", year, tech_flags) and not overseas:
		return "helicopter"
	if overseas:
		return "sealift"
	if year >= 1936:
		return "rail"
	return "rail"


## RF2: a reinforce action is non-instant when days_total > min and force_deliver is false.
static func is_non_instant_flow(days_total: float, force_deliver: bool, active: bool) -> bool:
	if force_deliver:
		return false
	return active and days_total >= 0.75


static func combat_xp_mult_ok_pair(green_xp: float = 15.0, vet_xp: float = 90.0) -> Dictionary:
	var g := experience_combat_mult(green_xp)
	var v := experience_combat_mult(vet_xp)
	return {
		"ok": g < 0.9 and v > 1.1 and v > g + 0.2,
		"green_mult": g,
		"vet_mult": v,
	}
