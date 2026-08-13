# scripts/space/SpaceLayerManager.gd
## Runtime orbital compact ledger: site ownership, habitats, lift/command pools, SpaceFlows.
## Autoload. Pure math stays in SpaceLayerCalculator.
extends Node

const CALC_PATH := "res://scripts/space/SpaceLayerCalculator.gd"

signal site_claimed(site_id: String, owner_tag: String, body_id: String)
signal habitat_built(habitat_id: String, owner_tag: String, site_id: String, tier: String)
signal space_flow_created(flow_id: String, from_tag: String, to_tag: String)
signal space_flow_interdicted(flow_id: String, cause: String, loss: float)
signal space_flow_delivered(flow_id: String, amount: float)

## site_id -> { body_id, owner_tag, controller_tag, claimed_year, resources: [] }
var _sites: Dictionary = {}
## habitat_id -> { site_id, owner_tag, tier, active, loyalty, autonomy, supply_months, parent_tag }
var _habitats: Dictionary = {}
## country_tag -> { lift_capacity, orbital_command, lift_used, command_used, space_stockpile: {} }
var _nations: Dictionary = {}
## flow_id -> SpaceFlow dict
var _flows: Dictionary = {}
## survey_id -> mission dict (S4)
var _surveys: Dictionary = {}
## discovery_id -> discovery dict (S4)
var _discoveries: Dictionary = {}
## project_id -> terraform project (S6)
var _terraform: Dictionary = {}
## stellar node id -> claim state (S7)
var _galaxy_claims: Dictionary = {}
## Player-selected map layer for UI (S5)
var _view_layer: String = "earth_surface"
var _view_flags: Array = []
var _view_milestones: Array = []
var _flow_seq: int = 0
var _habitat_seq: int = 0
var _survey_seq: int = 0
var _discovery_seq: int = 0
var _terraform_seq: int = 0
var _current_year: int = 1936


func _ready() -> void:
	_ensure_sites_catalog()
	if typeof(TimeManager) != TYPE_NIL:
		if TimeManager.has_signal("game_year_advanced") and not TimeManager.game_year_advanced.is_connected(_on_year):
			TimeManager.game_year_advanced.connect(_on_year)
		if TimeManager.has_signal("game_month_advanced") and not TimeManager.game_month_advanced.is_connected(_on_month):
			TimeManager.game_month_advanced.connect(_on_month)


func _on_year(year: int) -> void:
	_current_year = year


func _on_month(year: int, month: int) -> void:
	_current_year = year
	# Interactive F5: skip full space monthly AI/survey stack (can freeze clock at month ends).
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_interactive_light_sim") and bool(TimeManager.is_interactive_light_sim()):
		process_monthly_space(year, month, {"skip_ai_sustain": true, "skip_rival_surveys": true})
		return
	process_monthly_space(year, month)


func reset_for_new_scenario() -> void:
	_sites.clear()
	_habitats.clear()
	_nations.clear()
	_flows.clear()
	_surveys.clear()
	_discoveries.clear()
	_terraform.clear()
	_galaxy_claims.clear()
	_view_layer = "earth_surface"
	_view_flags = []
	_view_milestones = []
	_flow_seq = 0
	_habitat_seq = 0
	_survey_seq = 0
	_discovery_seq = 0
	_terraform_seq = 0
	_ensure_sites_catalog()


func _calc():
	return load(CALC_PATH)


func get_rules() -> Dictionary:
	var c = _calc()
	if c != null and c.has_method("get_rules"):
		return c.get_rules() as Dictionary
	return {}


func _ensure_sites_catalog() -> void:
	## Index all capture_sites from rules once (unowned until claimed).
	var rules := get_rules()
	var bodies: Array = rules.get("bodies", []) as Array if rules.get("bodies") is Array else []
	for b in bodies:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		var body: Dictionary = b as Dictionary
		var body_id := str(body.get("id", ""))
		var sites: Array = body.get("capture_sites", []) as Array if body.get("capture_sites") is Array else []
		for s in sites:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var site: Dictionary = s as Dictionary
			var sid := str(site.get("id", ""))
			if sid.is_empty() or _sites.has(sid):
				continue
			var res: Array = []
			if site.get("resources") is Array:
				res = (site["resources"] as Array).duplicate()
			_sites[sid] = {
				"site_id": sid,
				"body_id": body_id,
				"label": str(site.get("label", sid)),
				"owner_tag": "",
				"controller_tag": "",
				"claimed_year": -1,
				"resources": res,
				"asteroid_size": str(site.get("asteroid_size", body.get("asteroid_size", ""))),
				"resources_roll": bool(site.get("resources_roll", false)),
				"layer": str(body.get("layer", "")),
				"habitability_band": str(body.get("habitability_band", "hostile")),
			}


func _norm_tag(t: String) -> String:
	return t.strip_edges().to_upper()


func _ensure_nation(tag: String) -> Dictionary:
	var t := _norm_tag(tag)
	if t.is_empty():
		return {}
	if not _nations.has(t):
		_nations[t] = {
			"tag": t,
			"lift_capacity": 2.0,
			"orbital_command": 2.0,
			"lift_used": 0.0,
			"command_used": 0.0,
			"space_stockpile": {
				"propellant": 0.0, "water": 0.0, "oxygen": 0.0, "food": 0.0,
				"energy": 0.0, "structural_metals": 0.0, "rare_samples": 0.0,
			},
			"tech_flags": [],
			"milestones": [],
			"landing_craft": 0,
			"bombardment_ships": 0,
			"orbital_weapons": 0,
			"orbital_defenses": 0,
			"fleet_strength": 0.0,
			"max_reach_au": 0.5,
		}
	return _nations[t] as Dictionary


## --- Capacity -----------------------------------------------------------------

func set_nation_capacity(tag: String, lift: float = -1.0, orbital_command: float = -1.0) -> Dictionary:
	var n := _ensure_nation(tag)
	if n.is_empty():
		return {"ok": false}
	if lift >= 0.0:
		n["lift_capacity"] = lift
	if orbital_command >= 0.0:
		n["orbital_command"] = orbital_command
	_nations[_norm_tag(tag)] = n
	return {"ok": true, "nation": n.duplicate(true)}


func add_lift_capacity(tag: String, delta: float) -> float:
	var n := _ensure_nation(tag)
	n["lift_capacity"] = maxf(0.0, float(n.get("lift_capacity", 0.0)) + delta)
	_nations[_norm_tag(tag)] = n
	return float(n["lift_capacity"])


## Commercial lift charter (non-space powers buy surplus from sellers).
func buy_commercial_lift(buyer_tag: String, seller_tag: String, amount: float = 1.0, opts: Dictionary = {}) -> Dictionary:
	var rules := get_rules()
	var cl: Dictionary = rules.get("commercial_lift", {}) as Dictionary if rules.get("commercial_lift") is Dictionary else {}
	if not bool(cl.get("non_space_power_can_buy_lift", true)) and not bool(opts.get("force", false)):
		return {"ok": false, "error": "commercial_lift_disabled"}
	var buyer := _ensure_nation(buyer_tag)
	var seller := _ensure_nation(seller_tag)
	if buyer.is_empty() or seller.is_empty():
		return {"ok": false, "error": "bad_tags"}
	var amt := maxf(0.1, amount)
	var seller_free := float(seller.get("lift_capacity", 0.0)) - float(seller.get("lift_used", 0.0))
	if bool(cl.get("requires_seller_lift_surplus", true)) and seller_free < amt and not bool(opts.get("force", false)):
		return {"ok": false, "error": "seller_no_surplus", "seller_free": seller_free, "need": amt}
	var price := float(cl.get("price_suu_per_boost_unit", 12.0)) * amt
	# Transfer abstract lift capacity units
	seller["lift_capacity"] = maxf(0.0, float(seller.get("lift_capacity", 0.0)) - amt)
	buyer["lift_capacity"] = float(buyer.get("lift_capacity", 0.0)) + amt
	_nations[_norm_tag(buyer_tag)] = buyer
	_nations[_norm_tag(seller_tag)] = seller
	return {
		"ok": true,
		"buyer": _norm_tag(buyer_tag),
		"seller": _norm_tag(seller_tag),
		"amount": amt,
		"price_suu": price,
		"buyer_lift": float(buyer.get("lift_capacity", 0.0)),
		"seller_lift": float(seller.get("lift_capacity", 0.0)),
	}


func create_sustain_flow(
	from_tag: String,
	to_tag: String,
	item_id: String = "propellant",
	quantity: float = 5.0,
	path: Array = [],
	opts: Dictionary = {},
) -> Dictionary:
	## Habitat sustain SpaceFlow — life-support majors credit supply_months on advance.
	var fid := create_space_flow(from_tag, to_tag, item_id, quantity, path, opts)
	if fid.is_empty():
		return {"ok": false, "error": "create_failed"}
	if _flows.has(fid):
		var f: Dictionary = (_flows[fid] as Dictionary).duplicate(true)
		f["sustain"] = true
		f["metadata"] = f.get("metadata", {}) if f.get("metadata") is Dictionary else {}
		(f["metadata"] as Dictionary)["sustain"] = true
		_flows[fid] = f
	return {"ok": true, "flow_id": fid, "item_id": item_id, "quantity": quantity}


func get_supply_board(tag: String) -> Dictionary:
	var t := _norm_tag(tag)
	var n := get_nation_space_board(t)
	var stock: Dictionary = n.get("stockpile", {}) as Dictionary if n.get("stockpile") is Dictionary else {}
	var habs := get_habitats_for_tag(t)
	var min_supply := 999.0
	var total_supply := 0.0
	for h in habs:
		if h is Dictionary:
			var sm := float((h as Dictionary).get("supply_months", 0.0))
			total_supply += sm
			if sm < min_supply:
				min_supply = sm
	if habs.is_empty():
		min_supply = 0.0
	var active_flows := 0
	for f in get_active_space_flows():
		if f is Dictionary:
			var fd: Dictionary = f as Dictionary
			if str(fd.get("to_tag", "")) == t or str(fd.get("from_tag", "")) == t:
				active_flows += 1
	return {
		"ok": true,
		"tag": t,
		"lift_capacity": float(n.get("lift_capacity", 0.0)),
		"lift_free": float(n.get("lift_free", 0.0)),
		"stockpile": stock.duplicate(true),
		"habitats_n": habs.size(),
		"min_supply_months": min_supply if not habs.is_empty() else 0.0,
		"avg_supply_months": (total_supply / float(habs.size())) if habs.size() > 0 else 0.0,
		"active_flows": active_flows,
		"model": "orbital_compact_ledger",
	}


func recompute_command_used(tag: String) -> float:
	var t := _norm_tag(tag)
	var used := 0.0
	var rules := get_rules()
	var tiers: Dictionary = rules.get("habitat_tiers", {}) as Dictionary if rules.get("habitat_tiers") is Dictionary else {}
	for hid in _habitats.keys():
		var h: Dictionary = _habitats[hid] as Dictionary
		if str(h.get("owner_tag", "")) != t or not bool(h.get("active", true)):
			continue
		var tier := str(h.get("tier", "outpost"))
		var td: Dictionary = tiers.get(tier, {}) as Dictionary if tiers.get(tier) is Dictionary else {}
		used += float(td.get("orbital_command_cost", td.get("mc_cost", 1.0)))
	var n := _ensure_nation(t)
	n["command_used"] = used
	_nations[t] = n
	return used


func get_nation_space_board(tag: String) -> Dictionary:
	var n := _ensure_nation(tag).duplicate(true)
	recompute_command_used(tag)
	n = (_nations[_norm_tag(tag)] as Dictionary).duplicate(true)
	var lift_cap := float(n.get("lift_capacity", 0.0))
	var cmd_cap := float(n.get("orbital_command", 0.0))
	var cmd_used := float(n.get("command_used", 0.0))
	var calc = _calc()
	var strain: Dictionary = {}
	if calc != null and calc.has_method("colony_strain"):
		strain = calc.colony_strain(cmd_used, cmd_cap, 6.0, 1.0) as Dictionary
	return {
		"tag": _norm_tag(tag),
		"lift_capacity": lift_cap,
		"lift_used": float(n.get("lift_used", 0.0)),
		"lift_free": maxf(0.0, lift_cap - float(n.get("lift_used", 0.0))),
		"orbital_command": cmd_cap,
		"command_used": cmd_used,
		"command_free": maxf(0.0, cmd_cap - cmd_used),
		"expansion_strain": strain,
		"habitats_n": get_habitats_for_tag(tag).size(),
		"sites_n": get_sites_for_tag(tag).size(),
		"stockpile": (n.get("space_stockpile", {}) as Dictionary).duplicate(true),
		"model": "orbital_compact_ledger",
	}


## --- Sites --------------------------------------------------------------------

func get_site(site_id: String) -> Dictionary:
	return (_sites.get(site_id, {}) as Dictionary).duplicate(true) if _sites.has(site_id) else {}


func get_sites_for_tag(tag: String) -> Array:
	var t := _norm_tag(tag)
	var out: Array = []
	for sid in _sites.keys():
		var s: Dictionary = _sites[sid] as Dictionary
		if str(s.get("owner_tag", "")) == t or str(s.get("controller_tag", "")) == t:
			out.append(s.duplicate(true))
	return out


func get_unowned_sites_on_body(body_id: String) -> Array:
	var out: Array = []
	for sid in _sites.keys():
		var s: Dictionary = _sites[sid] as Dictionary
		if str(s.get("body_id", "")) != body_id:
			continue
		if str(s.get("owner_tag", "")).is_empty():
			out.append(s.duplicate(true))
	return out


func claim_site(site_id: String, owner_tag: String, year: int = -1, opts: Dictionary = {}) -> Dictionary:
	_ensure_sites_catalog()
	if not _sites.has(site_id):
		return {"ok": false, "error": "unknown_site"}
	var s: Dictionary = (_sites[site_id] as Dictionary).duplicate(true)
	var prev := str(s.get("owner_tag", ""))
	if not prev.is_empty() and not bool(opts.get("force", false)):
		return {"ok": false, "error": "already_owned", "owner": prev}
	var tag := _norm_tag(owner_tag)
	_ensure_nation(tag)
	# Lift gate for first off-world claim beyond earth-orbit optional soft check
	var need_lift := float(opts.get("lift_cost", 1.0))
	var n := _ensure_nation(tag)
	if bool(opts.get("require_lift", true)) and float(n.get("lift_capacity", 0.0)) < need_lift:
		return {"ok": false, "error": "insufficient_lift", "need": need_lift, "have": float(n.get("lift_capacity", 0.0))}
	s["owner_tag"] = tag
	s["controller_tag"] = tag
	s["claimed_year"] = year if year >= 0 else _current_year
	# Optional resource roll for asteroids
	if bool(s.get("resources_roll", false)) and (s.get("resources") as Array).is_empty():
		s["resources"] = _roll_asteroid_resources(str(s.get("asteroid_size", "small")))
	_sites[site_id] = s
	site_claimed.emit(site_id, tag, str(s.get("body_id", "")))
	return {"ok": true, "site": s.duplicate(true)}


func _roll_asteroid_resources(size_key: String) -> Array:
	var pool := ["structural_metals", "propellant", "water", "rare_samples", "energy"]
	var calc = _calc()
	var slots := 2
	if calc != null and calc.has_method("asteroid_caps"):
		var caps: Dictionary = calc.asteroid_caps(size_key) as Dictionary
		slots = mini(int(caps.get("sites", 1)) + 1, pool.size())
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var used: Dictionary = {}
	while out.size() < slots and used.size() < pool.size():
		var pick: String = pool[rng.randi() % pool.size()]
		if used.has(pick):
			continue
		used[pick] = true
		out.append(pick)
	return out


## --- Habitats -----------------------------------------------------------------

func build_habitat(
	site_id: String,
	owner_tag: String,
	tier: String = "outpost",
	opts: Dictionary = {},
) -> Dictionary:
	if not _sites.has(site_id):
		return {"ok": false, "error": "unknown_site"}
	var s: Dictionary = _sites[site_id] as Dictionary
	var tag := _norm_tag(owner_tag)
	if str(s.get("owner_tag", "")) != tag and not bool(opts.get("allow_foreign", false)):
		return {"ok": false, "error": "not_owner"}
	var rules := get_rules()
	var tiers: Dictionary = rules.get("habitat_tiers", {}) as Dictionary if rules.get("habitat_tiers") is Dictionary else {}
	if not tiers.has(tier):
		return {"ok": false, "error": "bad_tier"}
	var td: Dictionary = tiers[tier] as Dictionary
	var cost := float(td.get("orbital_command_cost", td.get("mc_cost", 1.0)))
	# Asteroid building slot limits
	var size_key := str(s.get("asteroid_size", ""))
	if not size_key.is_empty():
		var calc = _calc()
		if calc != null and calc.has_method("asteroid_caps"):
			var caps: Dictionary = calc.asteroid_caps(size_key) as Dictionary
			var existing := 0
			for hid in _habitats.keys():
				var hh: Dictionary = _habitats[hid] as Dictionary
				if str(hh.get("site_id", "")) == site_id and bool(hh.get("active", true)):
					existing += 1
			if existing >= int(caps.get("max_building_slots", 99)):
				return {"ok": false, "error": "asteroid_slot_cap", "max": int(caps.get("max_building_slots", 0))}
	recompute_command_used(tag)
	var n := _ensure_nation(tag)
	var cmd_cap := float(n.get("orbital_command", 0.0))
	var cmd_used := float(n.get("command_used", 0.0))
	if cmd_used + cost > cmd_cap and not bool(opts.get("allow_over_command", false)):
		return {
			"ok": false, "error": "insufficient_orbital_command",
			"need": cmd_used + cost, "have": cmd_cap,
		}
	_habitat_seq += 1
	var hid := "hab_%s_%d" % [tag.to_lower(), _habitat_seq]
	var parent := _norm_tag(str(opts.get("parent_tag", tag)))
	if parent.is_empty():
		parent = tag
	var hab := {
		"habitat_id": hid,
		"site_id": site_id,
		"body_id": str(s.get("body_id", "")),
		"layer": str(s.get("layer", "")),
		"owner_tag": tag,
		"parent_tag": parent,
		"tier": tier,
		"active": true,
		"loyalty": float(opts.get("loyalty", 55.0)),
		"autonomy": float(opts.get("autonomy", 15.0)),
		"supply_months": float(opts.get("supply_months", 6.0)),
		"admin_mode": str(opts.get("admin_mode", "direct")),
		"created_year": _current_year,
		"years_since_founding": 0.0,
		"neglect_months": 0,
		"breakaway_ready": false,
		"orbital_command_cost": cost,
		"space_rp_bonus": float(td.get("space_rp_bonus", 0.0)),
		# Colony–parent multi-vector relations (mirror CRS vectors)
		"parent_vectors": {
			"public": float(opts.get("public", 20.0)),
			"elite": float(opts.get("elite", 15.0)),
			"military": float(opts.get("military", 10.0)),
			"trust": float(opts.get("trust", 25.0)),
			"dependency": float(opts.get("dependency", 40.0)),
		},
		"third_party": {},  # tag -> { vectors, last_contact_year }
	}
	_habitats[hid] = hab
	recompute_command_used(tag)
	habitat_built.emit(hid, tag, site_id, tier)
	return {"ok": true, "habitat": hab.duplicate(true), "nation": get_nation_space_board(tag)}


func get_habitat(habitat_id: String) -> Dictionary:
	return (_habitats.get(habitat_id, {}) as Dictionary).duplicate(true) if _habitats.has(habitat_id) else {}


func get_habitats_for_tag(tag: String) -> Array:
	var t := _norm_tag(tag)
	var out: Array = []
	for hid in _habitats.keys():
		var h: Dictionary = _habitats[hid] as Dictionary
		if str(h.get("owner_tag", "")) == t:
			out.append(h.duplicate(true))
	return out


func total_station_research_bonus(tag: String) -> float:
	var bonus := 0.0
	for h in get_habitats_for_tag(tag):
		if h is Dictionary:
			bonus += float((h as Dictionary).get("space_rp_bonus", 0.0))
	return bonus


## --- SpaceFlows ---------------------------------------------------------------

func create_space_flow(
	from_tag: String,
	to_tag: String,
	item_id: String,
	quantity_per_turn: float,
	path: Array = [],
	opts: Dictionary = {},
) -> String:
	var fr := _norm_tag(from_tag)
	var to := _norm_tag(to_tag)
	if fr.is_empty() or to.is_empty():
		return ""
	_flow_seq += 1
	var fid := "sflow_%d_%d" % [_current_year, _flow_seq]
	var corridor_risk := float(opts.get("corridor_risk", 0.08))
	var flow := {
		"flow_id": fid,
		"from_tag": fr,
		"to_tag": to,
		"item_id": item_id.strip_edges().to_lower(),
		"quantity_per_turn": quantity_per_turn,
		"baseline_quantity": quantity_per_turn,
		"path": path.duplicate() if path is Array else [],
		"corridor_risk": corridor_risk,
		"active": true,
		"total_delivered": 0.0,
		"total_lost": 0.0,
		"last_delivery_ratio": 1.0,
		"demo": bool(opts.get("demo", false)),
		"metadata": (opts.get("metadata", {}) as Dictionary).duplicate(true) if opts.get("metadata") is Dictionary else {},
	}
	_flows[fid] = flow
	space_flow_created.emit(fid, fr, to)
	return fid


func get_space_flow(flow_id: String) -> Dictionary:
	return (_flows.get(flow_id, {}) as Dictionary).duplicate(true) if _flows.has(flow_id) else {}


func get_active_space_flows() -> Array:
	var out: Array = []
	for fid in _flows.keys():
		var f: Dictionary = _flows[fid] as Dictionary
		if bool(f.get("active", false)):
			out.append(f.duplicate(true))
	return out


func interdict_space_flow(flow_id: String, cause: String, loss_fraction: float, meta: Dictionary = {}) -> bool:
	if not _flows.has(flow_id):
		return false
	var f: Dictionary = (_flows[flow_id] as Dictionary).duplicate(true)
	if not bool(f.get("active", false)):
		return false
	var loss := clampf(loss_fraction, 0.05, 0.95)
	# Blend with corridor risk
	var risk := float(f.get("corridor_risk", 0.05))
	var effective := clampf(loss * 0.65 + risk * 0.35, 0.05, 0.95)
	var prev := float(f.get("quantity_per_turn", 0.0))
	f["quantity_per_turn"] = prev * (1.0 - effective)
	f["total_lost"] = float(f.get("total_lost", 0.0)) + prev * effective
	var base := float(f.get("baseline_quantity", prev))
	f["last_delivery_ratio"] = float(f["quantity_per_turn"]) / base if base > 0.001 else 0.0
	var node := str(meta.get("node_id", ""))
	if node.is_empty() and f.get("path") is Array and (f["path"] as Array).size() > 0:
		node = str((f["path"] as Array)[0])
	var calc = _calc()
	var plain := ""
	if calc != null and calc.has_method("interdict_attribution_plain"):
		plain = str(calc.interdict_attribution_plain(cause, node, str(f.get("from_tag", "")), str(f.get("to_tag", ""))))
	else:
		plain = "Space interdiction (%s) on %s → %s" % [cause, f.get("from_tag", ""), f.get("to_tag", "")]
	if not f.get("metadata") is Dictionary:
		f["metadata"] = {}
	var md: Dictionary = f["metadata"] as Dictionary
	if not md.has("interdiction_history"):
		md["interdiction_history"] = []
	(md["interdiction_history"] as Array).append({
		"cause": cause,
		"loss": effective,
		"plain": plain,
		"node_id": node,
		"year": _current_year,
	})
	md["last_interdiction_plain"] = plain
	f["metadata"] = md
	if float(f["quantity_per_turn"]) <= 0.001:
		f["active"] = false
	_flows[flow_id] = f
	space_flow_interdicted.emit(flow_id, cause, effective)
	return true


func advance_space_flows() -> Dictionary:
	var report := {"delivered": 0, "amount": 0.0, "events": []}
	for fid in _flows.keys():
		var f: Dictionary = (_flows[fid] as Dictionary).duplicate(true)
		if not bool(f.get("active", false)):
			continue
		var qty := float(f.get("quantity_per_turn", 0.0))
		if qty <= 0.0:
			continue
		# Attrition from residual corridor risk
		var risk := float(f.get("corridor_risk", 0.0))
		var delivered := qty * (1.0 - risk * 0.08)
		f["total_delivered"] = float(f.get("total_delivered", 0.0)) + delivered
		var base := float(f.get("baseline_quantity", qty))
		f["last_delivery_ratio"] = delivered / base if base > 0.001 else 1.0
		# Credit recipient stockpile abstract
		var to := str(f.get("to_tag", ""))
		var item := str(f.get("item_id", "propellant"))
		var n := _ensure_nation(to)
		var stock: Dictionary = n.get("space_stockpile", {}) as Dictionary if n.get("space_stockpile") is Dictionary else {}
		stock[item] = float(stock.get(item, 0.0)) + delivered
		n["space_stockpile"] = stock
		_nations[_norm_tag(to)] = n
		# Habitat supply buffer if delivery is life support
		if item in ["food", "water", "oxygen", "propellant", "volatiles"]:
			for hid in _habitats.keys():
				var h: Dictionary = (_habitats[hid] as Dictionary).duplicate(true)
				if str(h.get("owner_tag", "")) == _norm_tag(to) and bool(h.get("active", true)):
					h["supply_months"] = minf(24.0, float(h.get("supply_months", 0.0)) + 0.15)
					_habitats[hid] = h
		_flows[fid] = f
		report["delivered"] = int(report["delivered"]) + 1
		report["amount"] = float(report["amount"]) + delivered
		space_flow_delivered.emit(fid, delivered)
	return report


func process_monthly_space_risks(year: int = 0, month: int = 0, opts: Dictionary = {}) -> Dictionary:
	var report := {"checked": 0, "interdicted": 0, "events": []}
	var force := bool(opts.get("force_hit", false))
	var force_loss := float(opts.get("force_loss", 0.4))
	var force_cause := str(opts.get("force_cause", "asat"))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var calc = _calc()
	for fid in _flows.keys():
		var f: Dictionary = _flows[fid] as Dictionary
		if not bool(f.get("active", false)):
			continue
		if bool(f.get("demo", false)) and not force:
			continue
		report["checked"] = int(report["checked"]) + 1
		var risk := float(f.get("corridor_risk", 0.05))
		var hit_chance := 0.05
		if calc != null and calc.has_method("spaceflow_hit_chance"):
			hit_chance = float(calc.spaceflow_hit_chance(risk))
		else:
			hit_chance = clampf(risk * 0.55, 0.02, 0.5)
		if not force and rng.randf() > hit_chance:
			continue
		var loss := force_loss if force else clampf(risk * rng.randf_range(0.35, 0.85), 0.08, 0.7)
		var cause := force_cause if force else _pick_cause(risk, rng)
		var node := ""
		if f.get("path") is Array and (f["path"] as Array).size() > 0:
			var path: Array = f["path"] as Array
			node = str(path[rng.randi() % path.size()])
		if interdict_space_flow(str(fid), cause, loss, {"node_id": node, "year": year, "month": month, "silent": true}):
			report["interdicted"] = int(report["interdicted"]) + 1
			(report["events"] as Array).append({"flow_id": str(fid), "cause": cause, "loss": loss, "node": node})
	return report


func _pick_cause(risk: float, rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	if risk > 0.2 and r < 0.4:
		return "asat"
	if r < 0.55:
		return "solar_storm"
	if r < 0.75:
		return "patrol_cutter"
	if r < 0.9:
		return "debris_cascade"
	return "piracy"


func process_monthly_space(year: int = 0, month: int = 0, opts: Dictionary = {}) -> Dictionary:
	var risks: Dictionary = process_monthly_space_risks(year, month, opts)
	var deliv: Dictionary = advance_space_flows()
	var ai_sustain: Dictionary = {}
	if not bool(opts.get("skip_ai_sustain", false)):
		ai_sustain = process_monthly_space_ai_sustain(year, month, opts)
	var rival_surveys: Dictionary = {}
	if not bool(opts.get("skip_rival_surveys", false)):
		rival_surveys = process_monthly_rival_surveys(year, month, opts)
	var survey_tick: Dictionary = advance_surveys(1, opts)
	var disc_events: Dictionary = process_discovery_events(opts)
	var drift_events: Array = []
	var indep_events: Array = []
	var rules := get_rules()
	var indep_rules: Dictionary = {}
	var cc: Dictionary = rules.get("colony_control", {}) as Dictionary if rules.get("colony_control") is Dictionary else {}
	if cc.get("independence") is Dictionary:
		indep_rules = cc["independence"] as Dictionary
	var drift_yr := float(indep_rules.get("drift_per_year_if_neglected", 2.5)) / 12.0
	var min_years := float(indep_rules.get("min_years_to_breakaway", 20))
	for hid in _habitats.keys():
		var h: Dictionary = (_habitats[hid] as Dictionary).duplicate(true)
		if not bool(h.get("active", true)):
			continue
		var supply := float(h.get("supply_months", 0.0))
		supply = maxf(0.0, supply - 1.0)
		h["supply_months"] = supply
		h["years_since_founding"] = float(h.get("years_since_founding", 0.0)) + (1.0 / 12.0)
		var neglected := supply < 3.0
		if neglected:
			h["neglect_months"] = int(h.get("neglect_months", 0)) + 1
			h["autonomy"] = minf(100.0, float(h.get("autonomy", 0.0)) + drift_yr * 12.0 * 0.35)
			h["loyalty"] = maxf(0.0, float(h.get("loyalty", 50.0)) - 1.5)
			# Parent trust/public soft hit
			var pv: Dictionary = h.get("parent_vectors", {}) as Dictionary if h.get("parent_vectors") is Dictionary else {}
			pv["trust"] = clampf(float(pv.get("trust", 0.0)) - 0.8, -100.0, 100.0)
			pv["public"] = clampf(float(pv.get("public", 0.0)) - 0.5, -100.0, 100.0)
			pv["dependency"] = clampf(float(pv.get("dependency", 0.0)) - 0.3, -100.0, 100.0)
			h["parent_vectors"] = pv
			drift_events.append({"habitat_id": hid, "autonomy": h["autonomy"], "supply": supply})
		else:
			h["neglect_months"] = maxi(0, int(h.get("neglect_months", 0)) - 1)
			# Care improves parent CRS slightly
			var pv2: Dictionary = h.get("parent_vectors", {}) as Dictionary if h.get("parent_vectors") is Dictionary else {}
			pv2["trust"] = clampf(float(pv2.get("trust", 0.0)) + 0.15, -100.0, 100.0)
			h["parent_vectors"] = pv2
		var yrs := float(h.get("years_since_founding", 0.0))
		var auto := float(h.get("autonomy", 0.0))
		var ready := auto >= 100.0 and yrs >= min_years
		h["breakaway_ready"] = ready
		if ready:
			indep_events.append({"habitat_id": hid, "years": yrs, "autonomy": auto, "parent": h.get("parent_tag", "")})
		_habitats[hid] = h
	return {
		"year": year, "month": month,
		"risks": risks, "delivery": deliv,
		"ai_sustain": ai_sustain,
		"rival_surveys": rival_surveys,
		"survey_tick": survey_tick,
		"discovery_events": disc_events,
		"drift_events": drift_events, "independence_events": indep_events,
		"ok": true, "model": "orbital_compact_ledger",
	}


## AI rival survey competition — other tags probe contested / high-value bodies.
func process_monthly_rival_surveys(year: int = 0, month: int = 0, opts: Dictionary = {}) -> Dictionary:
	var report := {
		"year": year, "month": month,
		"rivals_checked": 0, "surveys_started": 0, "events": [],
	}
	var rivals: Array = opts.get("rivals", ["USA", "SOV", "GER", "ENG", "JAP"]) as Array if opts.get("rivals") is Array else ["USA", "SOV", "GER", "ENG", "JAP"]
	var targets: Array = opts.get("targets", ["luna", "mars", "europa", "titan", "ceres"]) as Array if opts.get("targets") is Array else ["luna", "mars", "europa", "titan", "ceres"]
	var max_new := int(opts.get("max_new_per_month", 2))
	var started := 0
	for raw in rivals:
		if started >= max_new:
			break
		var tag := _norm_tag(str(raw))
		if tag.is_empty():
			continue
		report["rivals_checked"] = int(report["rivals_checked"]) + 1
		_ensure_nation(tag)
		# Skip if already has active survey
		var busy := false
		for s in get_surveys_for_tag(tag):
			if s is Dictionary and bool((s as Dictionary).get("active", false)):
				busy = true
				break
		if busy and not bool(opts.get("allow_multi", false)):
			continue
		# Pick a body not yet discovered by this tag
		var body := ""
		for t in targets:
			var bid := str(t)
			var known := false
			for d in get_discoveries_for_tag(tag):
				if d is Dictionary and str((d as Dictionary).get("body_id", "")) == bid:
					known = true
					break
			if known:
				continue
			# Prefer bodies others have surveyed (competition race)
			var contested := false
			for did in _discoveries.keys():
				var disc: Dictionary = _discoveries[did] as Dictionary
				if str(disc.get("body_id", "")) == bid and str(disc.get("owner_tag", "")) != tag:
					contested = true
					break
			body = bid
			if contested or bool(opts.get("prefer_any", true)):
				break
		if body.is_empty():
			continue
		var res: Dictionary = start_survey(tag, body, {
			"months": int(opts.get("months", 4)),
			"has_isr": bool(opts.get("has_isr", true)),
			"has_probe": true,
			"force_success": bool(opts.get("force_success", false)),
		})
		if bool(res.get("ok", false)):
			started += 1
			report["surveys_started"] = started
			(report["events"] as Array).append({
				"type": "rival_survey",
				"tag": tag,
				"body_id": body,
				"survey_id": (res.get("survey", {}) as Dictionary).get("survey_id", "") if res.get("survey") is Dictionary else "",
				"contested": true,
			})
	report["ok"] = true
	return report


## Unresolved discoveries for a tag (player board surface).
func list_unresolved_discoveries(tag: String = "") -> Array:
	var t := _norm_tag(tag)
	var out: Array = []
	for did in _discoveries.keys():
		var d: Dictionary = _discoveries[did] as Dictionary
		if not t.is_empty() and str(d.get("owner_tag", "")) != t:
			continue
		if bool(d.get("choice_resolved", false)):
			continue
		out.append(d.duplicate(true))
	return out


## Player agency on discovery events (not news-only).
func list_discovery_choices(discovery_id: String) -> Dictionary:
	if not _discoveries.has(discovery_id):
		return {"ok": false, "error": "unknown_discovery", "choices": []}
	var d: Dictionary = _discoveries[discovery_id] as Dictionary
	var class_id := str(d.get("class_id", "resource_assay"))
	var choices: Array = []
	match class_id:
		"biosignature":
			choices = [
				{"id": "fund_terraform", "label": "Fund terraform seed study", "effect": "terraform_candidate"},
				{"id": "classify_secret", "label": "Classify / secret program", "effect": "secret_prestige"},
				{"id": "publish_science", "label": "Publish for prestige", "effect": "public_prestige"},
			]
		"deep_time_relic":
			choices = [
				{"id": "open_project", "label": "Open multi-year project", "effect": "project_track"},
				{"id": "military_seal", "label": "Military seal site", "effect": "mil_control"},
				{"id": "share_allies", "label": "Share with allies", "effect": "diplo_share"},
			]
		"hazard_map":
			choices = [
				{"id": "reroute", "label": "Reroute corridors", "effect": "risk_down"},
				{"id": "minefield", "label": "Seed defensive mines", "effect": "denial"},
				{"id": "ignore", "label": "Accept risk", "effect": "none"},
			]
		"first_contact_signal":
			choices = [
				{"id": "listen", "label": "Keep listening (optional narrative)", "effect": "narrative"},
				{"id": "jam", "label": "Jam / ignore", "effect": "close"},
				{"id": "share_un", "label": "Share internationally", "effect": "diplo_share"},
			]
		_:
			choices = [
				{"id": "claim_site", "label": "Claim high-yield site", "effect": "claim_boost"},
				{"id": "stockpile", "label": "Stockpile rare samples", "effect": "samples"},
				{"id": "license", "label": "License extraction rights", "effect": "trade"},
			]
	return {
		"ok": true,
		"discovery_id": discovery_id,
		"class_id": class_id,
		"choices": choices,
		"resolved": bool(d.get("choice_resolved", false)),
		"chosen_id": str(d.get("chosen_id", "")),
	}


func resolve_discovery_choice(discovery_id: String, choice_id: String, opts: Dictionary = {}) -> Dictionary:
	if not _discoveries.has(discovery_id):
		return {"ok": false, "error": "unknown_discovery"}
	var d: Dictionary = (_discoveries[discovery_id] as Dictionary).duplicate(true)
	if bool(d.get("choice_resolved", false)) and not bool(opts.get("force", false)):
		return {"ok": false, "error": "already_resolved", "chosen_id": d.get("chosen_id", "")}
	var listed: Dictionary = list_discovery_choices(discovery_id)
	var valid := false
	var effect := ""
	var label := ""
	for c in listed.get("choices", []):
		if c is Dictionary and str((c as Dictionary).get("id", "")) == choice_id:
			valid = true
			effect = str((c as Dictionary).get("effect", ""))
			label = str((c as Dictionary).get("label", choice_id))
			break
	if not valid:
		return {"ok": false, "error": "bad_choice", "choice_id": choice_id}
	d["choice_resolved"] = true
	d["chosen_id"] = choice_id
	d["choice_effect"] = effect
	d["choice_label"] = label
	var tag := str(d.get("owner_tag", ""))
	var payoffs: Dictionary = {}
	match effect:
		"terraform_candidate":
			d["terraform_candidate"] = true
			payoffs["terraform_candidate"] = true
		"samples":
			var n := _ensure_nation(tag)
			var stock: Dictionary = n.get("space_stockpile", {}) as Dictionary if n.get("space_stockpile") is Dictionary else {}
			stock["rare_samples"] = float(stock.get("rare_samples", 0.0)) + 2.0
			n["space_stockpile"] = stock
			_nations[_norm_tag(tag)] = n
			payoffs["rare_samples"] = 2.0
		"claim_boost":
			payoffs["claim_priority"] = true
		"risk_down":
			payoffs["corridor_risk_mod"] = -0.05
		"secret_prestige", "public_prestige", "project_track", "mil_control", "diplo_share", "denial", "narrative", "close", "trade", "none":
			payoffs["flag"] = effect
		_:
			payoffs["flag"] = effect
	d["choice_payoffs"] = payoffs
	_discoveries[discovery_id] = d
	if not bool(opts.get("silent", false)) and typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		LeaderEventUI.post_news(
			"Space decision: %s" % label,
			"%s chooses «%s» on %s discovery at %s." % [tag, label, str(d.get("class_id", "")), str(d.get("body_id", ""))],
			"technology",
		)
	return {
		"ok": true,
		"discovery_id": discovery_id,
		"choice_id": choice_id,
		"effect": effect,
		"payoffs": payoffs,
		"discovery": d.duplicate(true),
	}


## AI monthly: open sustain SpaceFlows for starved habitats; optional commercial lift buy.
func process_monthly_space_ai_sustain(year: int = 0, month: int = 0, opts: Dictionary = {}) -> Dictionary:
	var report := {
		"year": year, "month": month,
		"checked": 0, "flows_created": 0, "lift_buys": 0, "events": [],
	}
	var supply_floor := float(opts.get("supply_floor", 4.0))
	var tags_seen: Dictionary = {}
	for hid in _habitats.keys():
		var h: Dictionary = _habitats[hid] as Dictionary
		if not bool(h.get("active", true)):
			continue
		var tag := str(h.get("owner_tag", ""))
		if tag.is_empty():
			continue
		report["checked"] = int(report["checked"]) + 1
		var supply := float(h.get("supply_months", 0.0))
		if supply >= supply_floor:
			continue
		# Already have active sustain flow to this owner?
		var has_sustain := false
		for f in get_active_space_flows():
			if not (f is Dictionary):
				continue
			var fd: Dictionary = f as Dictionary
			if str(fd.get("to_tag", "")) == tag and bool(fd.get("sustain", false)):
				has_sustain = true
				break
		if has_sustain and not bool(opts.get("force_new_flow", false)):
			continue
		var item := "propellant"
		if supply < 2.0:
			item = "food"
		var flow: Dictionary = create_sustain_flow(tag, tag, item, 6.0, ["earth", "leo_band"], {
			"corridor_risk": 0.06,
			"demo": bool(opts.get("demo", false)),
		})
		if bool(flow.get("ok", false)):
			report["flows_created"] = int(report["flows_created"]) + 1
			(report["events"] as Array).append({
				"type": "sustain_flow", "tag": tag, "habitat_id": hid,
				"item": item, "flow_id": flow.get("flow_id", ""),
			})
		# Weak lift: try commercial charter once per tag per month
		if not tags_seen.has(tag):
			tags_seen[tag] = true
			var n := _ensure_nation(tag)
			if float(n.get("lift_capacity", 0.0)) < 2.0:
				# Find surplus seller
				for other in _nations.keys():
					if str(other) == tag:
						continue
					var sn: Dictionary = _nations[other] as Dictionary
					var free := float(sn.get("lift_capacity", 0.0)) - float(sn.get("lift_used", 0.0))
					if free >= 1.0:
						var buy: Dictionary = buy_commercial_lift(tag, str(other), 1.0)
						if bool(buy.get("ok", false)):
							report["lift_buys"] = int(report["lift_buys"]) + 1
							(report["events"] as Array).append({
								"type": "lift_buy", "buyer": tag, "seller": str(other),
							})
						break
	report["ok"] = true
	return report


## Discovery campaign events — plain text + optional LeaderEventUI news.
func process_discovery_events(opts: Dictionary = {}) -> Dictionary:
	var fired: Array = []
	var silent := bool(opts.get("silent", false))
	for did in _discoveries.keys():
		var d: Dictionary = (_discoveries[did] as Dictionary).duplicate(true)
		if bool(d.get("event_fired", false)) and not bool(opts.get("refire", false)):
			continue
		var class_id := str(d.get("class_id", "resource_assay"))
		var body := str(d.get("body_id", ""))
		var tag := str(d.get("owner_tag", ""))
		var title := "Space discovery: %s" % class_id.replace("_", " ")
		var body_txt := "%s survey of %s yields %s (%s)." % [
			tag, body, class_id.replace("_", " "), str(d.get("payoff", "")),
		]
		var chain := "space_survey"
		match class_id:
			"biosignature":
				chain = "terraform_candidate"
				title = "Biosignature: %s" % body
				body_txt = "%s detects a terraforming candidate at %s. Garden megaproject path open." % [tag, body]
			"deep_time_relic":
				chain = "deep_time_project"
				title = "Deep-time relic: %s" % body
				body_txt = "%s recovers a multi-year relic project seed from %s." % [tag, body]
			"hazard_map":
				chain = "corridor_hazard"
				title = "Hazard map: %s" % body
				body_txt = "%s charts permanent corridor risk near %s." % [tag, body]
			"first_contact_signal":
				chain = "first_contact_optional"
				title = "Anomalous signal: %s" % body
				body_txt = "%s logs an optional first-contact narrative signal from %s (not required for solar play)." % [tag, body]
			_:
				chain = "resource_assay"
		var evt := {
			"discovery_id": did,
			"owner_tag": tag,
			"body_id": body,
			"class_id": class_id,
			"chain": chain,
			"title": title,
			"body": body_txt,
			"year": _current_year,
		}
		d["event_fired"] = true
		d["event_chain"] = chain
		d["event_title"] = title
		_discoveries[did] = d
		fired.append(evt)
		if not silent and typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
			LeaderEventUI.post_news(title, body_txt, "technology")
	return {"ok": true, "fired_n": fired.size(), "events": fired}


## Player-facing space layer board (UI chrome surface).
func build_space_layer_ui_board(tag: String = "", opts: Dictionary = {}) -> Dictionary:
	var t := _norm_tag(tag)
	if t.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		t = _norm_tag(str(LeaderManager.get_player_country_tag()))
	if t.is_empty():
		t = "USA"
	var fog: Dictionary = get_layer_fog_board()
	var supply: Dictionary = get_supply_board(t)
	var power: Dictionary = compute_space_power_for_tag(t)
	var galaxy: Dictionary = get_galaxy_board()
	var surveys := get_surveys_for_tag(t)
	var discs := get_discoveries_for_tag(t)
	var habs := get_habitats_for_tag(t)
	var active_surveys := 0
	for s in surveys:
		if s is Dictionary and bool((s as Dictionary).get("active", false)):
			active_surveys += 1
	var strips: Array = []
	strips.append("Lift %.1f free · OC free %.1f" % [
		float(supply.get("lift_free", 0.0)),
		float(get_nation_space_board(t).get("command_free", 0.0)),
	])
	strips.append("Habitats %d · min supply %.1f mo · flows %d" % [
		int(supply.get("habitats_n", 0)),
		float(supply.get("min_supply_months", 0.0)),
		int(supply.get("active_flows", 0)),
	])
	strips.append("Layers unlocked %d · fogged %d · view %s" % [
		int(fog.get("unlocked_n", 0)),
		int(fog.get("fogged_n", 0)),
		str(fog.get("view_layer", _view_layer)),
	])
	strips.append("Surveys active %d · discoveries %d · space power %.1f" % [
		active_surveys, discs.size(), float(power.get("space_power_index", 0.0)),
	])
	if bool(galaxy.get("unlocked", false)):
		strips.append("Galaxy bridge open · nodes %d claimed %d" % [
			int(galaxy.get("nodes_n", 0)), int(galaxy.get("claimed_n", 0)),
		])
	else:
		strips.append("Galaxy bridge locked (solar mastery)")
	var plain := " · ".join(PackedStringArray(strips))
	return {
		"ok": true,
		"tag": t,
		"plain": plain,
		"strips": strips,
		"fog": fog,
		"supply": supply,
		"space_power": power,
		"galaxy_unlocked": bool(galaxy.get("unlocked", false)),
		"habitats_n": habs.size(),
		"surveys_active": active_surveys,
		"discoveries_n": discs.size(),
		"view_layer": _view_layer,
		"model": "orbital_compact_ledger",
		"ui": "SpaceLayerBoardView",
	}


## --- Colony relations & range -------------------------------------------------

func parent_colony_crs(habitat_id: String) -> float:
	var h := get_habitat(habitat_id)
	if h.is_empty():
		return 0.0
	var v: Dictionary = h.get("parent_vectors", {}) as Dictionary if h.get("parent_vectors") is Dictionary else {}
	var s := 0.0
	for k in ["public", "elite", "military", "trust"]:
		s += float(v.get(k, 0.0))
	return s / 4.0


func apply_parent_vector_delta(habitat_id: String, deltas: Dictionary) -> Dictionary:
	if not _habitats.has(habitat_id):
		return {"ok": false, "error": "unknown_habitat"}
	var h: Dictionary = (_habitats[habitat_id] as Dictionary).duplicate(true)
	var v: Dictionary = h.get("parent_vectors", {}) as Dictionary if h.get("parent_vectors") is Dictionary else {}
	for k in deltas.keys():
		v[str(k)] = clampf(float(v.get(str(k), 0.0)) + float(deltas[k]), -100.0, 100.0)
	h["parent_vectors"] = v
	_habitats[habitat_id] = h
	return {"ok": true, "crs": parent_colony_crs(habitat_id), "vectors": v.duplicate(true)}


func layer_reach_au(layer_id: String) -> float:
	match str(layer_id):
		"earth_surface", "near_earth":
			return 0.05
		"cis_lunar":
			return 0.3
		"inner_system", "main_belt":
			return 1.5
		"outer_system":
			return 5.0
		"galaxy_bridge":
			return 50.0
		_:
			return 1.0


func body_layer(body_id: String) -> String:
	var calc = _calc()
	if calc != null and calc.has_method("body_by_id"):
		var b: Dictionary = calc.body_by_id(body_id) as Dictionary
		return str(b.get("layer", ""))
	return ""


func distance_au_between_bodies(a_body: String, b_body: String) -> float:
	if a_body == b_body:
		return 0.0
	var la := layer_reach_au(body_layer(a_body))
	var lb := layer_reach_au(body_layer(b_body))
	return absf(la - lb) + 0.05


func can_interact_range(from_tag: String, habitat_id: String) -> Dictionary:
	## Reach: nation max_reach_au vs habitat body distance from Earth proxy.
	var h := get_habitat(habitat_id)
	if h.is_empty():
		return {"ok": false, "can": false, "error": "unknown_habitat"}
	var n := _ensure_nation(from_tag)
	var reach := float(n.get("max_reach_au", 0.5))
	var body := str(h.get("body_id", ""))
	var dist := distance_au_between_bodies("earth", body)
	# Parent always can interact with own colony
	var parent := str(h.get("parent_tag", ""))
	var owner := str(h.get("owner_tag", ""))
	var tag := _norm_tag(from_tag)
	if tag == parent or tag == owner:
		return {"ok": true, "can": true, "distance_au": dist, "reach_au": reach, "reason": "parent_or_owner"}
	var can := reach + 0.001 >= dist
	return {
		"ok": true, "can": can, "distance_au": dist, "reach_au": reach,
		"reason": "in_range" if can else "out_of_range",
	}


func open_third_party_relation(habitat_id: String, other_tag: String) -> Dictionary:
	var interact := can_interact_range(other_tag, habitat_id)
	if not bool(interact.get("can", false)):
		return {"ok": false, "error": "out_of_range", "interact": interact}
	if not _habitats.has(habitat_id):
		return {"ok": false, "error": "unknown_habitat"}
	var h: Dictionary = (_habitats[habitat_id] as Dictionary).duplicate(true)
	var tp: Dictionary = h.get("third_party", {}) as Dictionary if h.get("third_party") is Dictionary else {}
	var ot := _norm_tag(other_tag)
	if not tp.has(ot):
		tp[ot] = {
			"vectors": {"public": 0.0, "elite": 0.0, "military": 0.0, "trust": 5.0, "dependency": 0.0},
			"last_contact_year": _current_year,
		}
	else:
		var row: Dictionary = (tp[ot] as Dictionary).duplicate(true)
		row["last_contact_year"] = _current_year
		tp[ot] = row
	h["third_party"] = tp
	_habitats[habitat_id] = h
	return {"ok": true, "relation": (tp[ot] as Dictionary).duplicate(true), "interact": interact}


func force_independence_tick(habitat_id: String, months: int = 12, opts: Dictionary = {}) -> Dictionary:
	## Test/dual helper: advance neglect months without full calendar.
	if not _habitats.has(habitat_id):
		return {"ok": false, "error": "unknown_habitat"}
	var mitigated := bool(opts.get("mitigated", false))
	var h: Dictionary = (_habitats[habitat_id] as Dictionary).duplicate(true)
	var rules := get_rules()
	var indep_rules: Dictionary = {}
	var cc: Dictionary = rules.get("colony_control", {}) as Dictionary if rules.get("colony_control") is Dictionary else {}
	if cc.get("independence") is Dictionary:
		indep_rules = cc["independence"] as Dictionary
	var drift := float(indep_rules.get("drift_per_year_if_neglected", 2.5)) / 12.0
	if mitigated:
		drift *= 0.35
	var min_years := float(indep_rules.get("min_years_to_breakaway", 20))
	for _i in range(maxi(months, 1)):
		h["years_since_founding"] = float(h.get("years_since_founding", 0.0)) + (1.0 / 12.0)
		if not mitigated:
			h["supply_months"] = maxf(0.0, float(h.get("supply_months", 0.0)) - 1.0)
		if float(h.get("supply_months", 0.0)) < 3.0 or not mitigated:
			h["autonomy"] = minf(100.0, float(h.get("autonomy", 0.0)) + drift * 12.0 * (0.35 if float(h.get("supply_months", 0.0)) < 3.0 else 0.15))
			if float(h.get("supply_months", 0.0)) < 3.0:
				h["loyalty"] = maxf(0.0, float(h.get("loyalty", 50.0)) - 1.2)
	var ready := float(h.get("autonomy", 0.0)) >= 100.0 and float(h.get("years_since_founding", 0.0)) >= min_years
	h["breakaway_ready"] = ready
	_habitats[habitat_id] = h
	return {
		"ok": true,
		"habitat": h.duplicate(true),
		"breakaway_ready": ready,
		"crs": parent_colony_crs(habitat_id),
	}


func build_colony_board(habitat_id: String) -> Dictionary:
	var h := get_habitat(habitat_id)
	if h.is_empty():
		return {"ok": false, "error": "unknown_habitat"}
	var crs := parent_colony_crs(habitat_id)
	var band := "neutral"
	if crs < -40.0:
		band = "hostile"
	elif crs < -10.0:
		band = "cold"
	elif crs < 25.0:
		band = "neutral"
	elif crs < 55.0:
		band = "cordial"
	elif crs < 80.0:
		band = "partner"
	else:
		band = "ally_ready"
	return {
		"ok": true,
		"habitat_id": habitat_id,
		"parent_tag": h.get("parent_tag", ""),
		"owner_tag": h.get("owner_tag", ""),
		"body_id": h.get("body_id", ""),
		"tier": h.get("tier", ""),
		"loyalty": h.get("loyalty", 0.0),
		"autonomy": h.get("autonomy", 0.0),
		"supply_months": h.get("supply_months", 0.0),
		"years_since_founding": h.get("years_since_founding", 0.0),
		"breakaway_ready": h.get("breakaway_ready", false),
		"parent_crs": crs,
		"parent_band": band,
		"parent_vectors": (h.get("parent_vectors", {}) as Dictionary).duplicate(true) if h.get("parent_vectors") is Dictionary else {},
		"third_party_n": (h.get("third_party", {}) as Dictionary).size() if h.get("third_party") is Dictionary else 0,
		"admin_mode": h.get("admin_mode", "direct"),
		"model": "orbital_compact_ledger",
	}


## --- Combat / landing / bombardment ------------------------------------------

func set_space_military(tag: String, patch: Dictionary) -> Dictionary:
	var n := _ensure_nation(tag)
	for k in ["landing_craft", "bombardment_ships", "orbital_weapons", "orbital_defenses", "fleet_strength", "max_reach_au"]:
		if patch.has(k):
			n[k] = patch[k]
	_nations[_norm_tag(tag)] = n
	return n.duplicate(true)


func can_land_assault(attacker_tag: String, site_id: String) -> Dictionary:
	var site := get_site(site_id)
	if site.is_empty():
		return {"ok": false, "can": false, "error": "unknown_site"}
	var n := _ensure_nation(attacker_tag)
	var craft := int(n.get("landing_craft", 0))
	var rules := get_rules()
	var sc: Dictionary = rules.get("space_combat", {}) as Dictionary if rules.get("space_combat") is Dictionary else {}
	var need: Array = sc.get("landing_craft_required", ["dropship", "shuttle", "lander"]) as Array if sc.get("landing_craft_required") is Array else ["dropship"]
	var body := str(site.get("body_id", ""))
	var dist := distance_au_between_bodies("earth", body)
	var reach := float(n.get("max_reach_au", 0.5))
	var in_range := reach + 0.001 >= dist
	var can := craft > 0 and in_range
	return {
		"ok": true, "can": can,
		"landing_craft": craft,
		"required_types": need,
		"in_range": in_range,
		"distance_au": dist,
		"reason": "ok" if can else ("no_landing_craft" if craft <= 0 else "out_of_range"),
	}


func can_bombard_body(attacker_tag: String, body_id: String, defender_tag: String = "") -> Dictionary:
	var n := _ensure_nation(attacker_tag)
	var bombs := int(n.get("bombardment_ships", 0))
	var weapons := int(n.get("orbital_weapons", 0))
	var dist := distance_au_between_bodies("earth", body_id)
	var reach := float(n.get("max_reach_au", 0.5))
	var in_range := reach + 0.001 >= dist
	var def_defenses := 0
	if not defender_tag.is_empty():
		var d := _ensure_nation(defender_tag)
		def_defenses = int(d.get("orbital_defenses", 0))
	var can := (bombs > 0 or weapons > 0) and in_range
	var contested := def_defenses > 0
	return {
		"ok": true, "can": can,
		"in_range": in_range,
		"bombardment_ships": bombs,
		"orbital_weapons": weapons,
		"defender_orbital_defenses": def_defenses,
		"needs_superiority_window": contested,
		"distance_au": dist,
		"reason": "ok" if can else ("no_bombardment_capability" if bombs + weapons <= 0 else "out_of_range"),
		"threat_note": "Undefended surface faces elevated threat" if can and def_defenses <= 0 else "",
	}


## Space power snapshot for diplomacy / NationalPowerCalculator inputs
func get_space_power_inputs(tag: String) -> Dictionary:
	var t := _norm_tag(tag)
	var habs := get_habitats_for_tag(t)
	var stations := 0
	for h in habs:
		if h is Dictionary:
			var tier := str((h as Dictionary).get("tier", ""))
			if tier in ["platform", "orbital", "ring"]:
				stations += 1
	var n := _ensure_nation(t)
	return {
		"fleet_strength": float(n.get("fleet_strength", 0.0)),
		"habitats": float(habs.size()),
		"stations": float(stations),
		"lift_capacity": float(n.get("lift_capacity", 0.0)),
		"orbital_defenses": float(n.get("orbital_defenses", 0)),
		"bombardment_capable_ships": float(n.get("bombardment_ships", 0)),
		"orbital_weapons": float(n.get("orbital_weapons", 0)),
		"isr_coverage": float(stations) * 0.5 + float(n.get("orbital_defenses", 0)) * 0.2,
	}


func compute_space_power_for_tag(tag: String) -> Dictionary:
	var calc = _calc()
	var inputs := get_space_power_inputs(tag)
	if calc != null and calc.has_method("compute_space_power_index"):
		var sp: Dictionary = calc.compute_space_power_index(inputs) as Dictionary
		# Also merge national threat for desk
		var npc = load("res://scripts/national/NationalPowerCalculator.gd")
		if npc != null and npc.has_method("compute_power_index"):
			var np: Dictionary = npc.compute_power_index({
				"factories": 10,
				"space_power_index": float(sp.get("space_power_index", 0.0)),
				"bombardment_ships": float(inputs.get("bombardment_capable_ships", 0.0)),
				"orbital_defenses": float(inputs.get("orbital_defenses", 0.0)),
			}) as Dictionary
			sp["national_effective_threat"] = np.get("effective_threat", 0.0)
			sp["space_bombardment_asymmetry"] = np.get("space_bombardment_asymmetry", false)
		return sp
	return {"space_power_index": 0.0}


func get_board_summary() -> Dictionary:
	return {
		"sites_n": _sites.size(),
		"habitats_n": _habitats.size(),
		"flows_n": _flows.size(),
		"nations_n": _nations.size(),
		"active_flows": get_active_space_flows().size(),
		"model": "orbital_compact_ledger",
	}


func get_save_data() -> Dictionary:
	return {
		"sites": _sites.duplicate(true),
		"habitats": _habitats.duplicate(true),
		"nations": _nations.duplicate(true),
		"flows": _flows.duplicate(true),
		"surveys": _surveys.duplicate(true),
		"discoveries": _discoveries.duplicate(true),
		"terraform": _terraform.duplicate(true),
		"galaxy_claims": _galaxy_claims.duplicate(true),
		"view_layer": _view_layer,
		"view_flags": _view_flags.duplicate(),
		"view_milestones": _view_milestones.duplicate(),
		"flow_seq": _flow_seq,
		"habitat_seq": _habitat_seq,
		"survey_seq": _survey_seq,
		"discovery_seq": _discovery_seq,
		"terraform_seq": _terraform_seq,
		"current_year": _current_year,
		"model": "orbital_compact_ledger",
	}


func apply_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	if data.get("sites") is Dictionary:
		_sites = (data["sites"] as Dictionary).duplicate(true)
	if data.get("habitats") is Dictionary:
		_habitats = (data["habitats"] as Dictionary).duplicate(true)
	if data.get("nations") is Dictionary:
		_nations = (data["nations"] as Dictionary).duplicate(true)
	if data.get("flows") is Dictionary:
		_flows = (data["flows"] as Dictionary).duplicate(true)
	if data.get("surveys") is Dictionary:
		_surveys = (data["surveys"] as Dictionary).duplicate(true)
	if data.get("discoveries") is Dictionary:
		_discoveries = (data["discoveries"] as Dictionary).duplicate(true)
	if data.get("terraform") is Dictionary:
		_terraform = (data["terraform"] as Dictionary).duplicate(true)
	if data.get("galaxy_claims") is Dictionary:
		_galaxy_claims = (data["galaxy_claims"] as Dictionary).duplicate(true)
	_view_layer = str(data.get("view_layer", _view_layer))
	if data.get("view_flags") is Array:
		_view_flags = (data["view_flags"] as Array).duplicate()
	if data.get("view_milestones") is Array:
		_view_milestones = (data["view_milestones"] as Array).duplicate()
	_flow_seq = int(data.get("flow_seq", _flow_seq))
	_habitat_seq = int(data.get("habitat_seq", _habitat_seq))
	_survey_seq = int(data.get("survey_seq", _survey_seq))
	_discovery_seq = int(data.get("discovery_seq", _discovery_seq))
	_terraform_seq = int(data.get("terraform_seq", _terraform_seq))
	_current_year = int(data.get("current_year", _current_year))
	_ensure_sites_catalog()  # fill any new sites from rules not in save


## --- S4 Survey / discovery ----------------------------------------------------

func start_survey(tag: String, body_id: String, opts: Dictionary = {}) -> Dictionary:
	var t := _norm_tag(tag)
	if t.is_empty() or body_id.is_empty():
		return {"ok": false, "error": "bad_args"}
	_ensure_nation(t)
	var calc = _calc()
	var dist := distance_au_between_bodies("earth", body_id)
	var months := 6
	if calc != null and calc.has_method("survey_duration_months"):
		months = int(calc.survey_duration_months(dist))
	if opts.has("months"):
		months = maxi(1, int(opts["months"]))
	_survey_seq += 1
	var sid := "survey_%s_%d" % [t.to_lower(), _survey_seq]
	var mission := {
		"survey_id": sid,
		"owner_tag": t,
		"body_id": body_id,
		"months_total": months,
		"months_left": months,
		"active": true,
		"has_isr": bool(opts.get("has_isr", false)),
		"has_radar": bool(opts.get("has_radar", true)),
		"has_probe": bool(opts.get("has_probe", true)),
		"force_success": bool(opts.get("force_success", false)),
		"started_year": _current_year,
	}
	_surveys[sid] = mission
	return {"ok": true, "survey": mission.duplicate(true)}


func advance_surveys(months: int = 1, opts: Dictionary = {}) -> Dictionary:
	var completed: Array = []
	var failed: Array = []
	var calc = _calc()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if opts.has("seed"):
		rng.seed = int(opts["seed"])
	for sid in _surveys.keys():
		var m: Dictionary = (_surveys[sid] as Dictionary).duplicate(true)
		if not bool(m.get("active", false)):
			continue
		m["months_left"] = int(m.get("months_left", 1)) - maxi(months, 1)
		if int(m["months_left"]) > 0:
			_surveys[sid] = m
			continue
		m["active"] = false
		m["months_left"] = 0
		var chance := 0.7
		if calc != null and calc.has_method("survey_success_chance"):
			chance = float(calc.survey_success_chance(
				bool(m.get("has_isr", false)),
				bool(m.get("has_radar", true)),
				bool(m.get("has_probe", true)),
			))
		var success := bool(m.get("force_success", false)) or rng.randf() <= chance
		if success:
			var dclass: Dictionary = {}
			if calc != null and calc.has_method("pick_discovery_class"):
				dclass = calc.pick_discovery_class(rng) as Dictionary
			else:
				dclass = {"id": "resource_assay", "payoff": "high_yield_site"}
			_discovery_seq += 1
			var did := "disc_%d" % _discovery_seq
			var disc := {
				"discovery_id": did,
				"survey_id": sid,
				"owner_tag": m.get("owner_tag", ""),
				"body_id": m.get("body_id", ""),
				"class_id": str(dclass.get("id", "resource_assay")),
				"payoff": str(dclass.get("payoff", "")),
				"year": _current_year,
			}
			# Biosignature marks terraform candidate
			if str(disc["class_id"]) == "biosignature" or str(disc["payoff"]) == "terraform_candidate":
				disc["terraform_candidate"] = true
			_discoveries[did] = disc
			m["result"] = "success"
			m["discovery_id"] = did
			completed.append(disc)
		else:
			m["result"] = "failed"
			failed.append(m.duplicate(true))
		_surveys[sid] = m
	return {
		"ok": true,
		"completed_n": completed.size(),
		"failed_n": failed.size(),
		"discoveries": completed,
		"failed": failed,
	}


func get_surveys_for_tag(tag: String) -> Array:
	var t := _norm_tag(tag)
	var out: Array = []
	for sid in _surveys.keys():
		var m: Dictionary = _surveys[sid] as Dictionary
		if str(m.get("owner_tag", "")) == t:
			out.append(m.duplicate(true))
	return out


func get_discoveries_for_tag(tag: String) -> Array:
	var t := _norm_tag(tag)
	var out: Array = []
	for did in _discoveries.keys():
		var d: Dictionary = _discoveries[did] as Dictionary
		if str(d.get("owner_tag", "")) == t:
			out.append(d.duplicate(true))
	return out


func force_complete_survey(survey_id: String, opts: Dictionary = {}) -> Dictionary:
	if not _surveys.has(survey_id):
		return {"ok": false, "error": "unknown_survey"}
	var m: Dictionary = (_surveys[survey_id] as Dictionary).duplicate(true)
	m["months_left"] = 0
	m["force_success"] = bool(opts.get("force_success", true))
	m["active"] = true
	_surveys[survey_id] = m
	return advance_surveys(1, opts)


## --- S5 Map layer fog / view --------------------------------------------------

func set_view_access(flags: Array = [], milestones: Array = []) -> void:
	_view_flags = flags.duplicate() if flags is Array else []
	_view_milestones = milestones.duplicate() if milestones is Array else []


func set_view_layer(layer_id: String) -> Dictionary:
	var board := get_layer_fog_board()
	var known := false
	for row in board.get("layers", []):
		if row is Dictionary and str((row as Dictionary).get("id", "")) == layer_id:
			known = true
			break
	if not known and layer_id != "earth_surface":
		return {"ok": false, "error": "unknown_layer", "layer": layer_id}
	_view_layer = layer_id
	return {"ok": true, "view_layer": _view_layer, "board": board}


func get_view_layer() -> String:
	return _view_layer


func get_layer_fog_board(flags: Array = [], milestones: Array = []) -> Dictionary:
	var fl: Array = flags if flags.size() > 0 else _view_flags
	var ms: Array = milestones if milestones.size() > 0 else _view_milestones
	var calc = _calc()
	if calc != null and calc.has_method("build_layer_fog_board"):
		var board: Dictionary = calc.build_layer_fog_board(fl, ms) as Dictionary
		board["view_layer"] = _view_layer
		var view_unlocked := false
		for row in board.get("layers", []):
			if row is Dictionary and str((row as Dictionary).get("id", "")) == _view_layer:
				view_unlocked = bool((row as Dictionary).get("unlocked", false))
				board["view_fogged"] = bool((row as Dictionary).get("fogged", false))
				board["view_silhouette"] = bool((row as Dictionary).get("silhouette", false))
				break
		board["view_unlocked"] = view_unlocked or _view_layer == "earth_surface"
		return board
	return {"ok": false, "layers": [], "view_layer": _view_layer}


func reveal_layer_for_view(layer_id: String) -> Dictionary:
	## Adds a synthetic flag so dual can prove fog clear without full tech tree.
	var flag := "allow_%s" % layer_id
	if not _view_flags.has(flag):
		_view_flags.append(flag)
	# Map common layer gates from rules
	match layer_id:
		"near_earth":
			if not _view_flags.has("allow_satellites"):
				_view_flags.append("allow_satellites")
		"cis_lunar":
			if not _view_flags.has("allow_lunar_operations"):
				_view_flags.append("allow_lunar_operations")
		"inner_system":
			if not _view_flags.has("allow_mars_ops"):
				_view_flags.append("allow_mars_ops")
		"outer_system":
			if not _view_flags.has("allow_outer_system"):
				_view_flags.append("allow_outer_system")
		"galaxy_bridge":
			if not _view_flags.has("allow_galaxy_bridge"):
				_view_flags.append("allow_galaxy_bridge")
			if not _view_flags.has("solar_industrial_base"):
				_view_flags.append("solar_industrial_base")
	var board := get_layer_fog_board()
	return {"ok": true, "layer": layer_id, "flags": _view_flags.duplicate(), "board": board}


## --- S6 Terraform megaproject -------------------------------------------------

func start_terraform(tag: String, body_id: String = "", opts: Dictionary = {}) -> Dictionary:
	var t := _norm_tag(tag)
	var rules := get_rules()
	var tf: Dictionary = rules.get("terraform", {}) as Dictionary if rules.get("terraform") is Dictionary else {}
	var body := body_id if not body_id.is_empty() else str(tf.get("default_candidate_body", "mars"))
	var gardens := 0
	for pid in _terraform.keys():
		var p: Dictionary = _terraform[pid] as Dictionary
		if str(p.get("stage", "")) == "garden" and bool(p.get("active", true)):
			gardens += 1
	var max_g := int(tf.get("max_garden_worlds", 2))
	if gardens >= max_g and not bool(opts.get("allow_extra", false)):
		return {"ok": false, "error": "max_garden_worlds", "max": max_g}
	# Prefer biosignature discoveries as candidates
	var candidate_ok := bool(opts.get("force_candidate", false))
	for d in get_discoveries_for_tag(t):
		if d is Dictionary and bool((d as Dictionary).get("terraform_candidate", false)):
			if str((d as Dictionary).get("body_id", "")) == body or body_id.is_empty():
				candidate_ok = true
				if body_id.is_empty():
					body = str((d as Dictionary).get("body_id", body))
	if not candidate_ok and not bool(opts.get("force_candidate", true)):
		# default allow start at candidate stage (survey optional)
		pass
	_terraform_seq += 1
	var pid2 := "tf_%s_%d" % [t.to_lower(), _terraform_seq]
	var project := {
		"project_id": pid2,
		"owner_tag": t,
		"body_id": body,
		"stage": "candidate",
		"months_in_stage": 0,
		"active": true,
		"crises": [],
		"seed_delivered": 0.0,
		"garden": false,
	}
	_terraform[pid2] = project
	return {"ok": true, "project": project.duplicate(true)}


func advance_terraform(project_id: String, months: int = 1, opts: Dictionary = {}) -> Dictionary:
	if not _terraform.has(project_id):
		return {"ok": false, "error": "unknown_project"}
	var calc = _calc()
	var p: Dictionary = (_terraform[project_id] as Dictionary).duplicate(true)
	if not bool(p.get("active", true)):
		return {"ok": false, "error": "inactive", "project": p}
	var stage := str(p.get("stage", "candidate"))
	var need := 24
	if calc != null and calc.has_method("terraform_stage_months"):
		need = int(calc.terraform_stage_months(stage))
	p["months_in_stage"] = int(p.get("months_in_stage", 0)) + maxi(months, 1)
	if bool(opts.get("deliver_seed", false)) or stage == "seed":
		p["seed_delivered"] = float(p.get("seed_delivered", 0.0)) + float(opts.get("seed_amount", 1.0))
	var advanced := false
	while int(p.get("months_in_stage", 0)) >= need and stage != "garden":
		p["months_in_stage"] = int(p["months_in_stage"]) - need
		if calc != null and calc.has_method("terraform_next_stage"):
			stage = str(calc.terraform_next_stage(stage))
		else:
			match stage:
				"candidate":
					stage = "seed"
				"seed":
					stage = "stabilize"
				"stabilize":
					stage = "garden"
				_:
					stage = "garden"
		p["stage"] = stage
		advanced = true
		if calc != null and calc.has_method("terraform_stage_months"):
			need = int(calc.terraform_stage_months(stage))
		if stage == "garden":
			p["garden"] = true
			p["months_in_stage"] = need
			break
	if bool(opts.get("force_crisis", false)):
		var crises: Array = p.get("crises", []) as Array if p.get("crises") is Array else []
		crises.append({"year": _current_year, "type": str(opts.get("crisis_type", "storm_loss"))})
		p["crises"] = crises
	_terraform[project_id] = p
	var frac := 0.0
	if calc != null and calc.has_method("terraform_progress_frac"):
		frac = float(calc.terraform_progress_frac(str(p.get("stage", "")), int(p.get("months_in_stage", 0))))
	return {
		"ok": true,
		"project": p.duplicate(true),
		"stage_advanced": advanced,
		"progress_frac": frac,
		"is_garden": bool(p.get("garden", false)),
	}


func get_terraform_projects(tag: String = "") -> Array:
	var t := _norm_tag(tag)
	var out: Array = []
	for pid in _terraform.keys():
		var p: Dictionary = _terraform[pid] as Dictionary
		if t.is_empty() or str(p.get("owner_tag", "")) == t:
			out.append(p.duplicate(true))
	return out


func garden_world_count() -> int:
	var n := 0
	for pid in _terraform.keys():
		var p: Dictionary = _terraform[pid] as Dictionary
		if bool(p.get("garden", false)):
			n += 1
	return n


## --- S7 Galaxy bridge ---------------------------------------------------------

func get_galaxy_board(flags: Array = [], milestones: Array = []) -> Dictionary:
	var fl: Array = flags if flags is Array and flags.size() > 0 else _view_flags
	var ms: Array = milestones if milestones is Array and milestones.size() > 0 else _view_milestones
	var calc = _calc()
	var unlocked := false
	if calc != null and calc.has_method("galaxy_bridge_unlocked"):
		unlocked = bool(calc.galaxy_bridge_unlocked(fl, ms))
	var nodes: Array = []
	var cors: Array = []
	if calc != null:
		if calc.has_method("galaxy_nodes"):
			nodes = calc.galaxy_nodes(unlocked) as Array
		if calc.has_method("galaxy_corridors"):
			cors = calc.galaxy_corridors(unlocked) as Array
	# Merge claims
	var claimed_n := 0
	for i in range(nodes.size()):
		if not (nodes[i] is Dictionary):
			continue
		var n: Dictionary = (nodes[i] as Dictionary).duplicate(true)
		var nid := str(n.get("id", ""))
		if _galaxy_claims.has(nid):
			n["owner_tag"] = str((_galaxy_claims[nid] as Dictionary).get("owner_tag", ""))
			claimed_n += 1
		else:
			n["owner_tag"] = ""
		nodes[i] = n
	return {
		"ok": true,
		"unlocked": unlocked,
		"nodes": nodes,
		"corridors": cors,
		"claimed_n": claimed_n,
		"nodes_n": nodes.size(),
		"model": "orbital_compact_ledger",
	}


func claim_galaxy_node(tag: String, node_id: String, opts: Dictionary = {}) -> Dictionary:
	var board := get_galaxy_board()
	if not bool(board.get("unlocked", false)) and not bool(opts.get("force", false)):
		return {"ok": false, "error": "galaxy_locked"}
	var found := false
	for n in board.get("nodes", []):
		if n is Dictionary and str((n as Dictionary).get("id", "")) == node_id:
			found = true
			break
	if not found:
		return {"ok": false, "error": "unknown_node"}
	if _galaxy_claims.has(node_id) and not bool(opts.get("force", false)):
		return {"ok": false, "error": "already_claimed", "owner": (_galaxy_claims[node_id] as Dictionary).get("owner_tag", "")}
	var t := _norm_tag(tag)
	_galaxy_claims[node_id] = {
		"node_id": node_id,
		"owner_tag": t,
		"claimed_year": _current_year,
	}
	return {"ok": true, "claim": (_galaxy_claims[node_id] as Dictionary).duplicate(true), "board": get_galaxy_board()}


func unlock_galaxy_for_view() -> Dictionary:
	for f in ["allow_galaxy_bridge", "allow_ftl_relay", "solar_industrial_base"]:
		if not _view_flags.has(f):
			_view_flags.append(f)
	for m in ["solar_industrial_mastery", "first_ftl_probe"]:
		if not _view_milestones.has(m):
			_view_milestones.append(m)
	return get_galaxy_board()
