class_name SupplyIntelBridge
extends RefCounted

## Converts combat presence + map control into SupplyManager enemy_presence entries.


static func refresh_manager(
	manager: Node,
	friendly_tag: String,
	registry: CombatPresenceRegistry,
	provinces: Dictionary,
	hubs: Dictionary,
	rules: SupplyRules,
) -> void:
	if manager == null or registry == null:
		return
	var store: Dictionary = {}
	for pid_var in registry.all_province_ids():
		var pid := int(pid_var)
		store[pid] = _presence_for_province(pid, friendly_tag, registry, provinces, hubs, rules)
	for pid_var in provinces:
		var province: Province = provinces[pid_var]
		if province == null:
			continue
		var ctrl := _ctrl(province)
		if ctrl.is_empty() or ctrl == friendly_tag:
			continue
		var merged: Dictionary = store.get(province.id, {}).duplicate()
		merged["enemy_controlled"] = true
		merged["enemy_brigade_equiv"] = float(merged.get("enemy_brigade_equiv", 0.0)) + 1.0
		store[province.id] = merged
	manager.set_meta("enemy_presence", store)


static func _presence_for_province(
	pid: int,
	friendly_tag: String,
	registry: CombatPresenceRegistry,
	provinces: Dictionary,
	hubs: Dictionary,
	rules: SupplyRules,
) -> Dictionary:
	var report := registry.get_report(pid)
	var presence := {
		"enemy_air_superiority": 0.0,
		"enemy_naval_at_port": false,
		"enemy_brigade_equiv": 0.0,
	}

	var friendly_air := 0.0
	var enemy_air := 0.0
	for tag in report.air_by_tag:
		if str(tag) == friendly_tag:
			friendly_air += report.total_air(tag)
		else:
			enemy_air += report.total_air(tag)

	if enemy_air > 0.0:
		var ratio := enemy_air / maxf(friendly_air + enemy_air, 1.0)
		var scale := float(rules.get_block("intel").get("air_threat_from_superiority_ratio", 10.0))
		presence["enemy_air_superiority"] = clampf(ratio * scale, 0.0, scale)

		# Deeper wiring to AircraftDesignSystem: immature designs or poor range configs reduce effective air superiority
		# (prototypes have lower reliability/range impact). Human can improve via iteration/agents.
		var tree := Engine.get_main_loop() as SceneTree
		if tree:
			var debug = tree.get_first_node_in_group("debug_overlay")
			if debug and debug.has_method("_get_or_create_aircraft_design_system"):
				var ads = debug.call("_get_or_create_aircraft_design_system")
				if ads and ads.has_method("get_demo_air_modifier"):
					var mod: float = ads.get_demo_air_modifier("demo_p51_prototype")
					if mod < 1.0:
						presence["enemy_air_superiority"] *= mod  # immature enemy air less threatening
					elif mod > 1.0:
						presence["enemy_air_superiority"] *= min(mod, 1.3)

	for tag in report.land_by_tag:
		if str(tag) != friendly_tag:
			presence["enemy_brigade_equiv"] = float(presence["enemy_brigade_equiv"]) + report.total_land(tag)

	for tag in report.naval_at_port_by_tag:
		if str(tag) != friendly_tag and report.total_naval_at_port(tag) > 0.0:
			presence["enemy_naval_at_port"] = true

	var hub: ProvinceSupplyHub = hubs.get(pid)
	if hub != null and hub.port_level > 0:
		for tag in report.naval_by_tag:
			if str(tag) != friendly_tag and report.total_naval_at_port(tag) > 0.2:
				presence["enemy_naval_at_port"] = true

	var province: Province = provinces.get(pid)
	if province != null:
		for adj_id in province.adjacencies:
			var adj: Province = provinces.get(adj_id)
			if adj == null:
				continue
			var adj_ctrl := _ctrl(adj)
			if not adj_ctrl.is_empty() and adj_ctrl != friendly_tag:
				presence["adjacent_enemy"] = true

	return presence


static func _ctrl(province: Province) -> String:
	if not province.controller_tag.is_empty():
		return province.controller_tag
	return province.owner_tag

static func record_naval_spotting(sea_pid: int, spotter: String, spotted: String, strength: float) -> void:
	# Stub: record for intel UI or alerts. In full would update per-country naval intel map.
	print("Intel: naval spotting recorded %s spotted %s (%.1f) at sea %d" % [spotter, spotted, strength, sea_pid])
