# scripts/space/SpaceLayerCalculator.gd
## Pure-ish helpers for orbital compact ledger (gates, graph, SpaceFlow math).
## Loadable via load() — no autoload required for S0.
class_name SpaceLayerCalculator
extends RefCounted

const RULES_PATH := "res://data/space/space_layer_rules.json"
static var _rules: Dictionary = {}


static func get_rules() -> Dictionary:
	if _rules.is_empty():
		_load()
	return _rules


static func _load() -> void:
	if not FileAccess.file_exists(RULES_PATH):
		_rules = {"model": "orbital_compact_ledger", "layers": [], "bodies": [], "corridors": []}
		return
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		_rules = {"model": "orbital_compact_ledger", "layers": [], "bodies": [], "corridors": []}
		return
	var txt := f.get_as_text()
	var data: Variant = JSON.parse_string(txt)
	_rules = data as Dictionary if data is Dictionary else {}


static func layer_unlocked(layer: Dictionary, flags: Array = [], milestones: Array = []) -> bool:
	if bool(layer.get("always_visible", false)):
		return true
	var fl: Dictionary = {}
	for x in flags:
		fl[str(x)] = true
	var ms: Dictionary = {}
	for x in milestones:
		ms[str(x)] = true
	var gate_flags: Array = layer.get("gate_flags", []) as Array if layer.get("gate_flags") is Array else []
	var gate_ms: Array = layer.get("gate_milestones", []) as Array if layer.get("gate_milestones") is Array else []
	var mode := str(layer.get("gate_mode", "any"))
	if mode == "all_flags":
		if gate_flags.is_empty():
			return false
		for g in gate_flags:
			if not fl.has(str(g)):
				return false
		return true
	var flag_hit := false
	for g in gate_flags:
		if fl.has(str(g)):
			flag_hit = true
			break
	var ms_hit := false
	for g in gate_ms:
		if ms.has(str(g)):
			ms_hit = true
			break
	if gate_flags.is_empty() and gate_ms.is_empty():
		return false
	return flag_hit or ms_hit


static func visible_layers(flags: Array = [], milestones: Array = []) -> Array:
	if _rules.is_empty():
		_load()
	var out: Array = []
	var layers: Array = get_rules().get("layers", []) as Array if get_rules().get("layers") is Array else []
	for raw in layers:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = (raw as Dictionary).duplicate(true)
		var unlocked := layer_unlocked(layer, flags, milestones)
		layer["unlocked"] = unlocked
		layer["fogged"] = not unlocked and not bool(layer.get("always_visible", false))
		out.append(layer)
	out.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	return out


static func bodies_for_flags(flags: Array = [], milestones: Array = []) -> Array:
	var unlocked: Dictionary = {}
	for L in visible_layers(flags, milestones):
		if L is Dictionary and bool((L as Dictionary).get("unlocked", false)):
			unlocked[str((L as Dictionary).get("id", ""))] = true
	var out: Array = []
	var bodies: Array = get_rules().get("bodies", []) as Array if get_rules().get("bodies") is Array else []
	for b in bodies:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		if unlocked.has(str((b as Dictionary).get("layer", ""))):
			out.append((b as Dictionary).duplicate(true))
	return out


static func open_corridors(flags: Array = [], milestones: Array = []) -> Array:
	var unlocked: Dictionary = {}
	for L in visible_layers(flags, milestones):
		if L is Dictionary and bool((L as Dictionary).get("unlocked", false)):
			unlocked[str((L as Dictionary).get("id", ""))] = true
	var out: Array = []
	var cors: Array = get_rules().get("corridors", []) as Array if get_rules().get("corridors") is Array else []
	for c in cors:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		if unlocked.has(str((c as Dictionary).get("layer", ""))):
			out.append((c as Dictionary).duplicate(true))
	return out


static func spaceflow_hit_chance(route_risk: float) -> float:
	var r: Dictionary = get_rules().get("spaceflow", {}) as Dictionary if get_rules().get("spaceflow") is Dictionary else {}
	var risk := maxf(float(route_risk), 0.0)
	return clampf(risk * float(r.get("hit_chance_scale", 0.55)), float(r.get("hit_chance_min", 0.02)), float(r.get("hit_chance_max", 0.5)))


static func spaceflow_loss_fraction(route_risk: float, roll: float = 0.6) -> float:
	var r: Dictionary = get_rules().get("spaceflow", {}) as Dictionary if get_rules().get("spaceflow") is Dictionary else {}
	var risk := maxf(float(route_risk), 0.0)
	var rr := clampf(float(roll), 0.35, 0.85)
	return clampf(risk * rr, float(r.get("loss_min", 0.08)), float(r.get("loss_max", 0.7)))


static func interdict_attribution_plain(cause: String, node_id: String, fr: String, to: String) -> String:
	var c := cause.strip_edges().to_lower()
	var n := node_id if not node_id.is_empty() else "unknown node"
	if c == "asat":
		return "ASAT strike near %s degraded the %s → %s space convoy" % [n, fr, to]
	if c == "solar_storm":
		return "Solar storm along %s delayed/damaged the %s → %s transfer" % [n, fr, to]
	if c == "patrol_cutter":
		return "Hostile patrol cutters interdicted %s → %s near %s" % [fr, to, n]
	if c == "piracy":
		return "Piracy hit the %s → %s corridor near %s" % [fr, to, n]
	if c == "debris_cascade":
		return "Debris cascade near %s struck the %s → %s flight path" % [n, fr, to]
	return "Space interdiction on %s → %s at %s (%s)" % [fr, to, n, c]


static func colony_strain(command_used: float, command_cap: float, supply_months: float, distance: float = 1.0) -> Dictionary:
	var r: Dictionary = get_rules().get("colony_control", {}) as Dictionary if get_rules().get("colony_control") is Dictionary else {}
	var cap_root: Dictionary = get_rules().get("capacity_model", {}) as Dictionary if get_rules().get("capacity_model") is Dictionary else {}
	var exp: Dictionary = cap_root.get("expansion_strain", {}) as Dictionary if cap_root.get("expansion_strain") is Dictionary else {}
	var over := maxf(0.0, command_used - command_cap)
	var strain := over * float(exp.get("per_habitat_over_command", 0.04))
	strain += maxf(0.0, distance - 1.0) * 0.05
	if distance >= 2.0:
		strain += float(exp.get("per_outer_system_habitat", 0.04))
	var starve := supply_months < float(r.get("starvation_months", 3))
	if starve:
		strain += 0.2
	return {
		"strain": snappedf(minf(1.0, strain), 0.001),
		"mc_over": over > 0.0,
		"command_over": over > 0.0,
		"orbital_command_over": over > 0.0,
		"starvation_risk": starve,
		"admin_modes": (r.get("admin_modes", []) as Array).duplicate() if r.get("admin_modes") is Array else [],
	}


static func body_by_id(body_id: String) -> Dictionary:
	for b in get_rules().get("bodies", []):
		if b is Dictionary and str((b as Dictionary).get("id", "")) == body_id:
			return (b as Dictionary).duplicate(true)
	return {}


static func site_count_for_body(body_id: String) -> int:
	var b := body_by_id(body_id)
	if b.is_empty():
		return 0
	var sites: Array = b.get("capture_sites", []) as Array if b.get("capture_sites") is Array else []
	if not sites.is_empty():
		return sites.size()
	return int(b.get("sites", 0))


static func multi_site_sol_report() -> Dictionary:
	var luna_n := site_count_for_body("luna")
	var mars_n := site_count_for_body("mars")
	var ceres_n := site_count_for_body("ceres")
	var bodies: Array = get_rules().get("bodies", []) as Array if get_rules().get("bodies") is Array else []
	var has_phobos := not body_by_id("phobos").is_empty()
	var has_titan := not body_by_id("titan").is_empty()
	var ok := luna_n >= 6 and mars_n >= 8 and ceres_n >= 4 and has_phobos and has_titan
	return {
		"ok": ok,
		"luna_sites": luna_n,
		"mars_sites": mars_n,
		"ceres_sites": ceres_n,
		"has_phobos": has_phobos,
		"has_titan": has_titan,
		"body_n": bodies.size(),
	}


static func asteroid_caps(size_key: String) -> Dictionary:
	var table: Dictionary = get_rules().get("asteroid_size_table", {}) as Dictionary if get_rules().get("asteroid_size_table") is Dictionary else {}
	var row: Dictionary = table.get(size_key, table.get("small", {})) as Dictionary
	return {
		"size": size_key,
		"sites": int(row.get("sites", 1)),
		"max_pop": int(row.get("max_pop", 800)),
		"max_building_slots": int(row.get("max_building_slots", 3)),
	}


static func loft_cost_mult(via_luna: bool = false, via_l1: bool = false, via_station_luna: bool = false) -> float:
	var r: Dictionary = get_rules().get("staging_discounts", {}) as Dictionary if get_rules().get("staging_discounts") is Dictionary else {}
	if via_station_luna:
		return float(r.get("via_station_then_luna_mult", 0.55))
	if via_luna:
		return float(r.get("via_luna_base_loft_mult", 0.62))
	if via_l1:
		return float(r.get("via_l1_depot_loft_mult", 0.72))
	return float(r.get("earth_direct_to_mars_loft_mult", 1.0))


static func compute_space_power_index(inputs: Dictionary) -> Dictionary:
	var r: Dictionary = get_rules().get("space_power", {}) as Dictionary if get_rules().get("space_power") is Dictionary else {}
	var w: Dictionary = r.get("weights", {}) as Dictionary if r.get("weights") is Dictionary else {}
	var fleet := float(inputs.get("fleet_strength", 0))
	var orb_w := float(inputs.get("orbital_weapons", 0))
	var bomb := float(inputs.get("bombardment_capable_ships", 0))
	var defs := float(inputs.get("orbital_defenses", 0))
	var isr := float(inputs.get("isr_coverage", 0))
	var habs := float(inputs.get("habitats", 0))
	var stations := float(inputs.get("stations", 0))
	var lift := float(inputs.get("lift_capacity", 0))
	var score := (
		fleet * float(w.get("fleet_strength", 1.0))
		+ orb_w * float(w.get("orbital_weapons", 40.0))
		+ bomb * float(w.get("bombardment_capable_ships", 25.0))
		+ defs * float(w.get("orbital_defenses", 18.0))
		+ isr * float(w.get("isr_coverage", 12.0))
		+ habs * float(w.get("habitats", 8.0))
		+ stations * float(w.get("stations", 15.0))
		+ lift * float(w.get("lift_capacity", 3.0))
	)
	var undefended := defs < 1.0 and (bomb + orb_w) > 0.0
	var threat_mult := float(r.get("undefended_earth_threat_mult", 2.2)) if undefended else 1.0
	return {
		"space_power_index": snappedf(score, 0.1),
		"bombardment_threat": (bomb + orb_w * 0.5) > 0.0,
		"undefended_surface_penalty": undefended,
		"effective_space_threat": snappedf(score * threat_mult, 0.1),
		"threat_mult": threat_mult,
	}


static func independence_projection(neglect_years: float, mitigated: bool = false) -> Dictionary:
	var cc: Dictionary = get_rules().get("colony_control", {}) as Dictionary if get_rules().get("colony_control") is Dictionary else {}
	var r: Dictionary = cc.get("independence", {}) as Dictionary if cc.get("independence") is Dictionary else {}
	var gen := float(r.get("generation_years", 25))
	var mn := float(r.get("min_years_to_breakaway", 20))
	var drift := float(r.get("drift_per_year_if_neglected", 2.5))
	if mitigated:
		drift *= 0.35
	var years := maxf(mn, 100.0 / maxf(drift, 0.1))
	var autonomy := minf(100.0, neglect_years * drift)
	return {
		"generation_years": gen,
		"min_years_to_breakaway": mn,
		"projected_years_if_neglected": snappedf(years, 0.1),
		"autonomy_after_neglect": snappedf(autonomy, 0.1),
		"breakaway_ready": autonomy >= 100.0 and neglect_years >= mn,
		"mitigated": mitigated,
	}


static func spotting_detect_chance(range_au: float = 0.5, has_radar: bool = true, isr: bool = false, stealth: bool = false) -> float:
	var sc: Dictionary = get_rules().get("space_combat", {}) as Dictionary if get_rules().get("space_combat") is Dictionary else {}
	var s: Dictionary = sc.get("spotting", {}) as Dictionary if sc.get("spotting") is Dictionary else {}
	var c := float(s.get("base_detect", 0.25))
	if has_radar:
		c += float(s.get("radar_bonus", 0.2))
	if isr:
		c += float(s.get("isr_constellation_bonus", 0.25))
	if stealth:
		c -= float(s.get("stealth_fleet_penalty", 0.15))
	c -= float(range_au) * float(s.get("range_falloff_per_au", 0.12))
	return clampf(c, 0.02, 0.98)


static func habitability_band_for_body(body_id: String) -> Dictionary:
	var b := body_by_id(body_id)
	var band_id := str(b.get("habitability_band", "hostile"))
	var bands: Dictionary = {}
	var hab_raw: Variant = get_rules().get("habitability", {})
	if hab_raw is Dictionary:
		var hab: Dictionary = hab_raw as Dictionary
		if hab.get("bands") is Dictionary:
			bands = hab["bands"] as Dictionary
	var row: Dictionary = {}
	if bands.get(band_id) is Dictionary:
		row = bands[band_id] as Dictionary
	return {
		"body_id": body_id,
		"band": band_id,
		"life_support_mult": float(row.get("life_support_mult", 1.0)),
		"max_pop_scale": float(row.get("max_pop_scale", 0.25)),
		"notes": str(row.get("notes", "")),
	}


## --- S4 Survey ----------------------------------------------------------------

static func survey_duration_months(distance_au: float = 0.5) -> int:
	var s: Dictionary = get_rules().get("survey", {}) as Dictionary if get_rules().get("survey") is Dictionary else {}
	var base := int(s.get("base_months", 6))
	var per_au := float(s.get("months_per_au", 2.0))
	return maxi(1, base + int(ceil(float(distance_au) * per_au)))


static func survey_success_chance(has_isr: bool = false, has_radar: bool = true, has_probe: bool = true) -> float:
	var s: Dictionary = get_rules().get("survey", {}) as Dictionary if get_rules().get("survey") is Dictionary else {}
	var c := float(s.get("success_base", 0.55))
	if has_isr:
		c += float(s.get("isr_bonus", 0.15))
	if has_radar:
		c += float(s.get("radar_bonus", 0.1))
	if has_probe:
		c += float(s.get("probe_bonus", 0.12))
	return clampf(c, 0.05, 0.98)


static func pick_discovery_class(rng: RandomNumberGenerator = null) -> Dictionary:
	var s: Dictionary = get_rules().get("survey", {}) as Dictionary if get_rules().get("survey") is Dictionary else {}
	var classes: Array = s.get("discovery_classes", []) as Array if s.get("discovery_classes") is Array else []
	if classes.is_empty():
		return {"id": "resource_assay", "weight": 1, "payoff": "high_yield_site"}
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var total := 0
	for c in classes:
		if c is Dictionary:
			total += int((c as Dictionary).get("weight", 1))
	if total <= 0:
		return (classes[0] as Dictionary).duplicate(true)
	var roll := r.randi_range(1, total)
	var acc := 0
	for c in classes:
		if not (c is Dictionary):
			continue
		acc += int((c as Dictionary).get("weight", 1))
		if roll <= acc:
			return (c as Dictionary).duplicate(true)
	return (classes[classes.size() - 1] as Dictionary).duplicate(true)


## --- S5 Layer fog board -------------------------------------------------------

static func build_layer_fog_board(flags: Array = [], milestones: Array = []) -> Dictionary:
	var layers := visible_layers(flags, milestones)
	var fog_cfg: Dictionary = get_rules().get("layer_fog", {}) as Dictionary if get_rules().get("layer_fog") is Dictionary else {}
	var unlocked_n := 0
	var fogged_n := 0
	var rows: Array = []
	for L in layers:
		if not (L is Dictionary):
			continue
		var row: Dictionary = L as Dictionary
		var unlocked := bool(row.get("unlocked", false))
		var fogged := bool(row.get("fogged", false))
		if unlocked:
			unlocked_n += 1
		if fogged:
			fogged_n += 1
		rows.append({
			"id": str(row.get("id", "")),
			"label": str(row.get("label", row.get("id", ""))),
			"unlocked": unlocked,
			"fogged": fogged,
			"order": int(row.get("order", 0)),
			"silhouette": fogged and bool(fog_cfg.get("show_fogged_silhouettes", true)),
			"alpha": float(fog_cfg.get("silhouette_alpha", 0.28)) if fogged else 1.0,
		})
	return {
		"ok": true,
		"layers": rows,
		"unlocked_n": unlocked_n,
		"fogged_n": fogged_n,
		"show_silhouettes": bool(fog_cfg.get("show_fogged_silhouettes", true)),
		"model": "orbital_compact_ledger",
	}


## --- S6 Terraform -------------------------------------------------------------

static func terraform_stage_months(stage: String) -> int:
	var t: Dictionary = get_rules().get("terraform", {}) as Dictionary if get_rules().get("terraform") is Dictionary else {}
	var m: Dictionary = t.get("months_per_stage", {}) as Dictionary if t.get("months_per_stage") is Dictionary else {}
	return maxi(1, int(m.get(stage, 24)))


static func terraform_progress_frac(stage: String, months_in_stage: int) -> float:
	var need := terraform_stage_months(stage)
	return clampf(float(months_in_stage) / float(maxi(need, 1)), 0.0, 1.0)


static func terraform_next_stage(stage: String) -> String:
	var t: Dictionary = get_rules().get("terraform", {}) as Dictionary if get_rules().get("terraform") is Dictionary else {}
	var stages: Array = t.get("stages", ["candidate", "seed", "stabilize", "garden"]) as Array
	var s := str(stage)
	for i in range(stages.size()):
		if str(stages[i]) == s and i + 1 < stages.size():
			return str(stages[i + 1])
	return s


static func is_garden_stage(stage: String) -> bool:
	return str(stage) == "garden"


## --- S7 Galaxy bridge ---------------------------------------------------------

static func galaxy_nodes(unlocked: bool = false) -> Array:
	var g: Dictionary = get_rules().get("galaxy_bridge", {}) as Dictionary if get_rules().get("galaxy_bridge") is Dictionary else {}
	var nodes: Array = g.get("nodes", []) as Array if g.get("nodes") is Array else []
	var out: Array = []
	for n in nodes:
		if not (n is Dictionary):
			continue
		var row: Dictionary = (n as Dictionary).duplicate(true)
		row["reachable"] = unlocked or bool(row.get("always_home", false))
		out.append(row)
	return out


static func galaxy_bridge_unlocked(flags: Array = [], milestones: Array = []) -> bool:
	var g: Dictionary = get_rules().get("galaxy_bridge", {}) as Dictionary if get_rules().get("galaxy_bridge") is Dictionary else {}
	var layer_proxy := {
		"gate_flags": g.get("gate_flags", []),
		"gate_milestones": g.get("gate_milestones", []),
		"gate_mode": str(g.get("gate_mode", "any")),
		"always_visible": false,
	}
	return layer_unlocked(layer_proxy, flags, milestones)


static func galaxy_corridors(unlocked: bool = false) -> Array:
	var g: Dictionary = get_rules().get("galaxy_bridge", {}) as Dictionary if get_rules().get("galaxy_bridge") is Dictionary else {}
	var cors: Array = g.get("corridors", []) as Array if g.get("corridors") is Array else []
	var out: Array = []
	for c in cors:
		if not (c is Dictionary):
			continue
		var row: Dictionary = (c as Dictionary).duplicate(true)
		row["open"] = unlocked
		out.append(row)
	return out

