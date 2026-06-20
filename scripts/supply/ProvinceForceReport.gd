class_name ProvinceForceReport
extends RefCounted

var province_id: int = -1
var land_by_tag: Dictionary = {}
var air_by_tag: Dictionary = {}
var naval_by_tag: Dictionary = {}
var naval_at_port_by_tag: Dictionary = {}
## Engineer / combat-engineer brigade equivalents (friendly repair crews).
var engineers_by_tag: Dictionary = {}


func _init(p_province_id: int = -1) -> void:
	province_id = p_province_id


func add_land(tag: String, amount: float) -> void:
	land_by_tag[tag] = float(land_by_tag.get(tag, 0.0)) + amount


func add_air(tag: String, amount: float) -> void:
	air_by_tag[tag] = float(air_by_tag.get(tag, 0.0)) + amount


func add_naval(tag: String, amount: float, at_port: bool) -> void:
	naval_by_tag[tag] = float(naval_by_tag.get(tag, 0.0)) + amount
	if at_port:
		naval_at_port_by_tag[tag] = float(naval_at_port_by_tag.get(tag, 0.0)) + amount


func total_land(tag: String) -> float:
	return float(land_by_tag.get(tag, 0.0))


func total_air(tag: String) -> float:
	return float(air_by_tag.get(tag, 0.0))


## Returns air power ratio (friendly / enemy) using assets in registry.
## Used for continuous scale (not binary flag). 3:1 to 5:1 typically needed for full suppression in large provinces.
func get_air_power_ratio(friendly_tag: String) -> float:
	var f := 0.0
	var e := 0.0
	for t in air_by_tag:
		var val := float(air_by_tag[t])
		if str(t) == friendly_tag:
			f += val
		else:
			e += val
	return f / maxf(e, 0.01)


func get_air_dominance_for(tag: String) -> float:
	# Legacy 0-1 fraction my/total. Kept for compat; prefer get_air_power_ratio for new continuous calcs.
	# For dominance in large regions: ratio 3:1 ~0.75 fraction, 4:1~0.8, 5:1~0.83+
	var my = total_air(tag)
	var total = my
	for t in air_by_tag.keys():
		if t != tag:
			total += float(air_by_tag[t])
	if total <= 0.0:
		return 1.0
	return my / total


func air_dominance_level(tag: String) -> String:
	# Continuous scale: none/partial/full . Uses ratio thresholds for overwhelming majority needed.
	# Slight adv (e.g. 1.2:1) = none (enemy can still CAS/interdict with +cost -effect).
	# ~3:1-5:1 or dom>~0.75-0.83 for full. Even full is costly to attacker (high losses, supply drain).
	var ratio := get_air_power_ratio(tag)
	if ratio >= 4.0:  # overwhelming e.g. 4:1+
		return "full"
	elif ratio >= 1.8:  # partial adv allows limited enemy ops
		return "partial"
	else:
		return "none"


func total_naval_at_port(tag: String) -> float:
	return float(naval_at_port_by_tag.get(tag, 0.0))


func add_engineers(tag: String, brigade_equiv: float) -> void:
	if brigade_equiv <= 0.0:
		return
	engineers_by_tag[tag] = float(engineers_by_tag.get(tag, 0.0)) + brigade_equiv


func total_engineers(tag: String) -> float:
	return float(engineers_by_tag.get(tag.strip_edges().to_upper(), 0.0))


func set_engineers(tag: String, amount: float) -> void:
	var t := tag.strip_edges().to_upper()
	if amount <= 0.001:
		engineers_by_tag.erase(t)
	else:
		engineers_by_tag[t] = amount

## === AIR RECON / INTEL EXPANSION ===
## Recon from air missions (RECON profile) gives persistent bonus to spotting/intel in province.
## Feeds naval recon, land preview accuracy, reduces "fog" in battle odds, Supply interdict estimates.
var air_recon_by_tag: Dictionary = {}  # tag -> recon_points (decays daily or persists short)

func add_air_recon(tag: String, points: float) -> void:
	air_recon_by_tag[tag] = float(air_recon_by_tag.get(tag, 0.0)) + points

func total_air_recon(tag: String) -> float:
	return float(air_recon_by_tag.get(tag, 0.0))

func get_air_recon_bonus(friendly_tag: String) -> float:
	var own := total_air_recon(friendly_tag)
	var enemy := 0.0
	for t in air_recon_by_tag:
		if str(t) != friendly_tag:
			enemy += float(air_recon_by_tag[t])
	# Net advantage (our recon - enemy counter-recon)
	return clampf( (own - enemy * 0.6) * 0.12 , -0.4, 1.2)  # scales to meaningful % bonus

func decay_air_recon(days: float = 1.0) -> void:
	for t in air_recon_by_tag.keys():
		air_recon_by_tag[t] = maxf(0.0, float(air_recon_by_tag[t]) * (1.0 - 0.25 * days))
		if air_recon_by_tag[t] < 0.05:
			air_recon_by_tag.erase(t)
