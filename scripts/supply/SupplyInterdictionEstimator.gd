class_name SupplyInterdictionEstimator
extends RefCounted

## Estimates convoy / column loss risk from control, adjacent enemies, and stub force presence.
## Enhanced for continuous air superiority: uses air_power_ratio for interdiction.
## High enemy air adv (e.g. 3:1+) increases chance/cost significantly.
## If we (route owner) have high air adv, we can reduce enemy air's interdict effect (but this estimator is per-side).

static func estimate(
	path: Array[int],
	provinces: Dictionary,
	hubs: Dictionary,
	owner_tag: String,
	rules: SupplyRules,
	enemy_presence: Dictionary = {},
) -> Dictionary:
	var inter_rules := rules.get_block("interdiction")
	var total := 0.0
	var breakdown := {
		"base_hops": 0.0,
		"enemy_control": 0.0,
		"adjacent_enemy": 0.0,
		"enemy_air": 0.0,
		"enemy_naval": 0.0,
		"enemy_land": 0.0,
	}

	var air_rules := {}
	if rules.has_method("get_block"):
		air_rules = rules.get_block("air")

	for i in path.size():
		var pid := int(path[i])
		var province: Province = provinces.get(pid)
		if province == null:
			continue

		total += float(inter_rules.get("base_per_province_hop", 0.015))
		breakdown["base_hops"] += float(inter_rules.get("base_per_province_hop", 0.015))

		var presence: Dictionary = enemy_presence.get(pid, {})
		if typeof(presence) != TYPE_DICTIONARY:
			presence = {}

		var controller := province.controller_tag if not province.controller_tag.is_empty() else province.owner_tag
		if (
			(not controller.is_empty() and controller != owner_tag)
			or bool(presence.get("enemy_controlled", false))
		):
			var bump := float(inter_rules.get("enemy_controlled_hop", 0.12))
			total += bump
			breakdown["enemy_control"] += bump

		if bool(presence.get("adjacent_enemy", false)):
			var adj_bump := float(inter_rules.get("adjacent_enemy_province", 0.045))
			total += adj_bump
			breakdown["adjacent_enemy"] += adj_bump
		else:
			for adj_id in province.adjacencies:
				var adj: Province = provinces.get(adj_id)
				if adj == null:
					continue
				var adj_ctrl := adj.controller_tag if not adj.controller_tag.is_empty() else adj.owner_tag
				if not adj_ctrl.is_empty() and adj_ctrl != owner_tag:
					total += float(inter_rules.get("adjacent_enemy_province", 0.045))
					breakdown["adjacent_enemy"] += float(inter_rules.get("adjacent_enemy_province", 0.045))
					break

		# Continuous air: use air_power_ratio if present (enemy view of ratio = their enemy ratio for us? )
		# presence here is "enemy presence" relative to owner; so enemy_air_power high means bad for owner.
		var air_p_ratio := float(presence.get("air_power_ratio", 1.0))  # for the route owner vs enemies
		var enemy_air_p := float(presence.get("enemy_air_power", 0.0))
		var our_air_p := float(presence.get("our_air_power", 0.0))  # owner's view

		# For this estimator, enemy_air_superiority (legacy) or direct: if enemies have adv over owner, high interdict
		var enemy_adv_ratio := enemy_air_p / maxf(our_air_p, 0.01) if our_air_p + enemy_air_p > 0 else float(presence.get("enemy_air_superiority", 0))
		if enemy_adv_ratio > 0.1 or float(presence.get("enemy_air_superiority", 0)) > 0.0:
			var air_bump := 0.0
			var per_ratio := float(inter_rules.get("enemy_air_superiority_per_air_power_ratio", 0.04))
			if per_ratio <= 0.0:
				per_ratio = 0.04
			air_bump = clampf(enemy_adv_ratio * per_ratio, 0.0, 0.35)
			# Overwhelming enemy air ( >3:1 ) does more damage to our supply
			if enemy_adv_ratio >= 3.0:
				air_bump *= 1.6
				# Even if not full in estimator, scale up
			elif enemy_adv_ratio >= 1.5:
				air_bump *= 1.2
			# If owner has high adv, reduce the bump (we contest their air)
			if air_p_ratio >= 2.5:
				air_bump *= 0.5
			total += air_bump
			breakdown["enemy_air"] += air_bump
		else:
			# fallback legacy
			var air_lvl := float(presence.get("enemy_air_superiority", 0))
			if air_lvl > 0.0:
				var air_bump := air_lvl * float(inter_rules.get("enemy_air_superiority_per_level", 0.06))
				total += air_bump
				breakdown["enemy_air"] += air_bump

		if bool(presence.get("enemy_naval_at_port", false)):
			var naval_bump := float(inter_rules.get("enemy_naval_at_port", 0.14))
			total += naval_bump
			breakdown["enemy_naval"] += naval_bump

		var brigades := float(presence.get("enemy_brigade_equiv", 0.0))
		if brigades > 0.0:
			var land_bump := brigades * float(inter_rules.get("enemy_land_forces_per_brigade_equiv", 0.025))
			total += land_bump
			breakdown["enemy_land"] += land_bump

		# Regional control wiring: full friendly control of region reduces interdiction risk (convoy_efficiency, naval_range from bonuses; strategic depth etc.)
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("is_strategic_region_fully_controlled"):
			var rid := MapManager.get_province_region_id(pid)
			if rid > 0 and MapManager.is_strategic_region_fully_controlled(rid, owner_tag):
				var red := float(inter_rules.get("full_regional_control_reduction", 0.05))
				total = max(0.0, total - red)
				breakdown["regional_control"] = breakdown.get("regional_control", 0.0) - red

		var hub: ProvinceSupplyHub = hubs.get(pid)
		if hub != null and hub.port_level > 0 and bool(presence.get("enemy_naval_at_port", false)):
			breakdown["enemy_naval"] += float(inter_rules.get("enemy_naval_at_port", 0.14)) * 0.5

	var max_chance := float(inter_rules.get("max_interdiction_chance", 0.92))
	return {
		"chance": clampf(total, 0.0, max_chance),
		"breakdown": breakdown,
	}
