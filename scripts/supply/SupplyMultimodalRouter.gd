class_name SupplyMultimodalRouter
extends RefCounted

## Picks fastest valid land / sea / air route for a cargo profile.


static func find_best_route(
	source_id: int,
	target_id: int,
	owner_tag: String,
	provinces: Dictionary,
	adjacency: AdjacencySystem,
	hubs: Dictionary,
	rules: SupplyRules,
	cargo: SupplyCargoProfile,
	waypoints: Array[int] = [],
	forced_mode: String = "",
) -> SupplyRoutePlan:
	var modes: Array[String] = []
	if not forced_mode.is_empty():
		modes = [forced_mode]
	else:
		if cargo == null or cargo.land_ok:
			modes.append("land")
		if cargo != null and cargo.prefers_sea:
			modes.append("sea")
		if cargo != null and cargo.prefers_air:
			modes.append("air")
		if modes.is_empty():
			modes = ["land"]

	var best: SupplyRoutePlan = null
	for mode in modes:
		var plan := SupplyPathfinder.find_route_for_mode(
			mode, source_id, target_id, owner_tag,
			provinces, adjacency, hubs, rules, waypoints,
		)
		if plan.path_length() < 2:
			continue
		if best == null or plan.total_days < best.total_days:
			best = plan
	# Land-only cargo still needs sea when own land is discontinuous (East Prussia,
	# overseas holdings) and no alliance/transit rights allow overland through neutrals.
	if best == null or best.path_length() < 2:
		if not modes.has("sea"):
			var sea_plan := SupplyPathfinder.find_route_for_mode(
				"sea", source_id, target_id, owner_tag,
				provinces, adjacency, hubs, rules, waypoints,
			)
			if sea_plan != null and sea_plan.path_length() >= 2:
				best = sea_plan
		if best == null or best.path_length() < 2:
			if not modes.has("air"):
				var air_plan := SupplyPathfinder.find_route_for_mode(
					"air", source_id, target_id, owner_tag,
					provinces, adjacency, hubs, rules, waypoints,
				)
				if air_plan != null and air_plan.path_length() >= 2:
					best = air_plan
	if best == null:
		best = SupplyPathfinder.find_route(
			source_id, target_id, owner_tag, provinces, adjacency, hubs, rules, waypoints,
		)
	if best != null and cargo != null:
		best.cargo_tons_per_day = cargo.cargo_tons
	return best
