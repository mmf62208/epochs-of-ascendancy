# scripts/national/RelationsManager.gd
## Bilateral Strategic Compact Ledger — multi-vector relations + AI concern flags.
## Registered as autoload if present; also usable via load().
extends Node

const RULES_PATH := "res://data/diplomacy/relation_rules.json"

signal relations_changed(a: String, b: String, snapshot: Dictionary)
signal concern_flag_raised(a: String, b: String, flag_id: String)
signal concern_flag_cleared(a: String, b: String, flag_id: String)
## Pass 25: alliance proposal lifecycle.
signal alliance_proposed(from_tag: String, to_tag: String, proposal: Dictionary)
signal alliance_resolved(from_tag: String, to_tag: String, accepted: bool, proposal: Dictionary)

var _rules: Dictionary = {}
## key "A|B" sorted tags -> { vectors: {}, flags: {}, policy: {}, history: [] }
var _pairs: Dictionary = {}
## Pass 25: pending alliance proposals key "FROM>TO" -> {from, to, day, crs, status}.
var _alliance_proposals: Dictionary = {}
## Pass 30: campaign-shared counter templates (persist with save; not only user://).
var campaign_counter_templates: Array = []
const CAMPAIGN_TEMPLATE_MAX := 12


func _ready() -> void:
	_load_rules()
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_signal("game_day_advanced"):
		if not TimeManager.game_day_advanced.is_connected(_on_game_day_alliance_ai):
			TimeManager.game_day_advanced.connect(_on_game_day_alliance_ai)


func reset_for_new_scenario() -> void:
	_pairs.clear()
	_alliance_proposals.clear()
	campaign_counter_templates.clear()
	_load_rules()


func get_rules() -> Dictionary:
	if _rules.is_empty():
		_load_rules()
	return _rules


func _pair_key(a: String, b: String) -> String:
	var x := a.strip_edges().to_upper()
	var y := b.strip_edges().to_upper()
	if x.is_empty() or y.is_empty() or x == y:
		return ""
	return x + "|" + y if x < y else y + "|" + x


func _ensure_pair(a: String, b: String) -> Dictionary:
	var key := _pair_key(a, b)
	if key.is_empty():
		return {}
	if not _pairs.has(key):
		var vectors: Dictionary = {}
		var defaults_raw: Variant = get_rules().get("vectors", ["public", "elite", "military", "alignment", "trust", "dependency"])
		var defaults: Array = defaults_raw as Array if defaults_raw is Array else ["public", "elite", "military", "alignment", "trust", "dependency"]
		var d0: float = float(get_rules().get("vector_default", 0))
		for v in defaults:
			vectors[str(v)] = d0
		var parts: PackedStringArray = key.split("|")
		_pairs[key] = {
			"a": str(parts[0]) if parts.size() > 0 else "",
			"b": str(parts[1]) if parts.size() > 1 else "",
			"vectors": vectors,
			"flags": {},
			"policy": {
				"import_tariff": 0.0,
				"export_tariff": 0.0,
				"import_subsidy": 0.0,
				"export_subsidy": 0.0,
				"embargo": false,
				"mfn": false,
				"alliance": false,
				"guarantee": false,
			},
			"import_share": {},
			"history": [],
		}
	return _pairs[key] as Dictionary


func get_vectors(a: String, b: String) -> Dictionary:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return {}
	return (pair.get("vectors", {}) as Dictionary).duplicate(true)


func get_crs(a: String, b: String) -> float:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return 0.0
	var vectors: Dictionary = pair.get("vectors", {}) as Dictionary
	var weights: Dictionary = get_rules().get("crs_weights", {}) as Dictionary if get_rules().get("crs_weights") is Dictionary else {}
	var crs := 0.0
	var wsum := 0.0
	for k in ["public", "elite", "military", "alignment", "trust"]:
		var w := float(weights.get(k, 0.2))
		crs += float(vectors.get(k, 0.0)) * w
		wsum += w
	if wsum > 0.0:
		crs /= wsum
	# Dependency tilt: positive dependency on partner from a's POV makes a more captive (slight CRS softener for a when evaluating)
	var dep := float(vectors.get("dependency", 0.0))
	var tilt := float(get_rules().get("dependency_tilt_scale", 0.15))
	crs += dep * tilt * 0.01 * 10.0  # mild
	return clampf(crs, -100.0, 100.0)


func get_band(a: String, b: String) -> Dictionary:
	var crs := get_crs(a, b)
	var bands: Array = get_rules().get("bands", []) as Array if get_rules().get("bands") is Array else []
	for raw in bands:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var band: Dictionary = raw as Dictionary
		if crs <= float(band.get("max_crs", 100.0)):
			return {
				"id": str(band.get("id", "neutral")),
				"label": str(band.get("label", "Neutral")),
				"accept_floor": float(band.get("accept_floor", 0.95)),
				"crs": crs,
			}
	return {"id": "neutral", "label": "Neutral", "accept_floor": 0.95, "crs": crs}


func apply_vector_delta(a: String, b: String, deltas: Dictionary, reason: String = "") -> Dictionary:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return {}
	var vmin := float(get_rules().get("vector_min", -100))
	var vmax := float(get_rules().get("vector_max", 100))
	var vectors: Dictionary = pair["vectors"] as Dictionary
	for k in deltas:
		var key := str(k)
		if not vectors.has(key) and key != "dependency":
			continue
		vectors[key] = clampf(float(vectors.get(key, 0.0)) + float(deltas[k]), vmin, vmax)
	pair["vectors"] = vectors
	if not reason.is_empty():
		var hist: Array = pair.get("history", []) as Array
		hist.append({"reason": reason, "deltas": deltas.duplicate(true)})
		if hist.size() > 40:
			hist = hist.slice(hist.size() - 40, hist.size())
		pair["history"] = hist
	_pairs[_pair_key(a, b)] = pair
	var snap := get_snapshot(a, b)
	relations_changed.emit(a.strip_edges().to_upper(), b.strip_edges().to_upper(), snap)
	return snap


func apply_deal_outcome(a: String, b: String, outcome_key: String) -> Dictionary:
	var table: Dictionary = get_rules().get("deal_outcome_deltas", {}) as Dictionary if get_rules().get("deal_outcome_deltas") is Dictionary else {}
	var deltas: Dictionary = table.get(outcome_key, {}) as Dictionary if table.get(outcome_key) is Dictionary else {}
	if deltas.is_empty():
		return get_snapshot(a, b)
	return apply_vector_delta(a, b, deltas, outcome_key)


func raise_flag(a: String, b: String, flag_id: String) -> void:
	var pair := _ensure_pair(a, b)
	if pair.is_empty() or flag_id.is_empty():
		return
	var flags: Dictionary = pair.get("flags", {}) as Dictionary
	if flags.has(flag_id):
		return
	flags[flag_id] = {"raised_tick": Time.get_ticks_msec(), "active": true}
	pair["flags"] = flags
	_pairs[_pair_key(a, b)] = pair
	concern_flag_raised.emit(a.strip_edges().to_upper(), b.strip_edges().to_upper(), flag_id)


func clear_flag(a: String, b: String, flag_id: String) -> void:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return
	var flags: Dictionary = pair.get("flags", {}) as Dictionary
	if flags.erase(flag_id):
		pair["flags"] = flags
		_pairs[_pair_key(a, b)] = pair
		concern_flag_cleared.emit(a.strip_edges().to_upper(), b.strip_edges().to_upper(), flag_id)


func get_flags(a: String, b: String) -> PackedStringArray:
	var pair := _ensure_pair(a, b)
	var out: PackedStringArray = []
	if pair.is_empty():
		return out
	var flags: Dictionary = pair.get("flags", {}) as Dictionary
	for k in flags:
		out.append(str(k))
	return out


func get_policy(a: String, b: String) -> Dictionary:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return {}
	return (pair.get("policy", {}) as Dictionary).duplicate(true)


func set_policy(a: String, b: String, policy_patch: Dictionary) -> Dictionary:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return {}
	var pol: Dictionary = (pair.get("policy", {}) as Dictionary).duplicate(true)
	for k in policy_patch:
		pol[str(k)] = policy_patch[k]
	# Clamp tariff bands
	for tk in ["import_tariff", "export_tariff", "import_subsidy", "export_subsidy"]:
		if pol.has(tk):
			pol[tk] = clampf(float(pol[tk]), 0.0, 0.5)
	pair["policy"] = pol
	# Tariff war flag
	var tsum := float(pol.get("import_tariff", 0.0)) + float(pol.get("export_tariff", 0.0))
	var thr := 0.5
	var cf: Dictionary = get_rules().get("concern_flags", {}) as Dictionary if get_rules().get("concern_flags") is Dictionary else {}
	if cf.get("tariff_war") is Dictionary:
		thr = float((cf["tariff_war"] as Dictionary).get("tariff_sum_threshold", 0.5))
	if tsum >= thr:
		raise_flag(a, b, "tariff_war")
		apply_vector_delta(a, b, {"elite": -3}, "tariff_war")
	_pairs[_pair_key(a, b)] = pair
	return get_snapshot(a, b)


## Pass 24: formal mutual alliance treaty (persists via pair policy).
func set_alliance(a: String, b: String, allied: bool = true) -> Dictionary:
	var snap := set_policy(a, b, {"alliance": allied})
	if allied:
		# Mutual defense posture also raises alignment/military trust slightly.
		apply_vector_delta(a, b, {"military": 4, "alignment": 5, "trust": 3}, "alliance_treaty")
		# Clear any pending proposals between the pair.
		_clear_proposals_between(a, b)
	else:
		apply_vector_delta(a, b, {"military": -2, "alignment": -3, "trust": -2}, "alliance_broken")
	return get_snapshot(a, b)


func is_allied(a: String, b: String) -> bool:
	var pol := get_policy(a, b)
	return bool(pol.get("alliance", false))


## Pass 25: open alliance negotiation (does not form treaty until accept).
func propose_alliance(from_tag: String, to_tag: String) -> Dictionary:
	var fr := from_tag.strip_edges().to_upper()
	var to := to_tag.strip_edges().to_upper()
	if fr.is_empty() or to.is_empty() or fr == to:
		return {"ok": false, "reason": "invalid_tags"}
	if is_allied(fr, to):
		return {"ok": false, "reason": "already_allied", "snapshot": get_snapshot(fr, to)}
	var key := "%s>%s" % [fr, to]
	var rev := "%s>%s" % [to, fr]
	if _alliance_proposals.has(rev):
		# Counter-proposal already pending from them — treat as accept opportunity.
		return {"ok": true, "reason": "reciprocal_pending", "proposal": (_alliance_proposals[rev] as Dictionary).duplicate(true)}
	var day := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		day = int(TimeManager.get_total_days_elapsed())
	var crs := get_crs(fr, to)
	var band := get_band(fr, to)
	var prop := {
		"from": fr,
		"to": to,
		"day": day,
		"crs": crs,
		"band_id": str(band.get("id", "neutral")),
		"status": "pending",
	}
	_alliance_proposals[key] = prop
	# Soft diplomatic goodwill on offer.
	apply_vector_delta(fr, to, {"public": 1, "trust": 1}, "alliance_proposed")
	alliance_proposed.emit(fr, to, prop.duplicate(true))
	return {"ok": true, "reason": "proposed", "proposal": prop.duplicate(true)}


func accept_alliance(accepter_tag: String, proposer_tag: String) -> Dictionary:
	return _accept_alliance_impl(accepter_tag, proposer_tag)


func _accept_alliance_impl(accepter_tag: String, proposer_tag: String) -> Dictionary:
	var acc := accepter_tag.strip_edges().to_upper()
	var prop_tag := proposer_tag.strip_edges().to_upper()
	var key := "%s>%s" % [prop_tag, acc]
	if not _alliance_proposals.has(key):
		# Also allow accepting reciprocal if they proposed to us under reverse key misuse.
		key = "%s>%s" % [acc, prop_tag]
		if not _alliance_proposals.has(key):
			return {"ok": false, "reason": "no_proposal"}
		# If we find our own outgoing, can't accept our own.
		if str((_alliance_proposals[key] as Dictionary).get("from", "")) == acc:
			return {"ok": false, "reason": "cannot_accept_own"}
	var prop: Dictionary = (_alliance_proposals[key] as Dictionary).duplicate(true)
	if str(prop.get("status", "")) != "pending":
		return {"ok": false, "reason": "not_pending", "proposal": prop}
	# Pass 26: honor counter-offer terms (min CRS, optional guarantee).
	var min_crs := float(prop.get("min_crs", 0.0))
	if min_crs > 0.0 and get_crs(prop_tag, acc) < min_crs:
		return {"ok": false, "reason": "crs_below_counter_min", "min_crs": min_crs, "proposal": prop}
	prop["status"] = "accepted"
	_alliance_proposals.erase(key)
	var snap := set_alliance(prop_tag, acc, true)
	if bool(prop.get("require_guarantee", false)):
		# Accepter grants guarantee to proposer (or mutual if already allied).
		set_guarantee(acc, prop_tag, true)
	alliance_resolved.emit(prop_tag, acc, true, prop)
	return {"ok": true, "reason": "accepted", "proposal": prop, "snapshot": snap}


func decline_alliance(decliner_tag: String, proposer_tag: String) -> Dictionary:
	var dec := decliner_tag.strip_edges().to_upper()
	var prop_tag := proposer_tag.strip_edges().to_upper()
	var key := "%s>%s" % [prop_tag, dec]
	if not _alliance_proposals.has(key):
		return {"ok": false, "reason": "no_proposal"}
	var prop: Dictionary = (_alliance_proposals[key] as Dictionary).duplicate(true)
	prop["status"] = "declined"
	_alliance_proposals.erase(key)
	apply_vector_delta(prop_tag, dec, {"public": -1, "trust": -2, "elite": -1}, "alliance_declined")
	alliance_resolved.emit(prop_tag, dec, false, prop)
	return {"ok": true, "reason": "declined", "proposal": prop}


func cancel_alliance_proposal(from_tag: String, to_tag: String) -> bool:
	var key := "%s>%s" % [from_tag.strip_edges().to_upper(), to_tag.strip_edges().to_upper()]
	if _alliance_proposals.has(key):
		_alliance_proposals.erase(key)
		return true
	return false


## Pass 26: counter an incoming alliance offer with modified terms (replaces their proposal with ours).
## terms: { "require_guarantee": bool, "note": String, "min_crs": float }
func counter_alliance_offer(responder_tag: String, original_proposer: String, terms: Dictionary = {}) -> Dictionary:
	var resp := responder_tag.strip_edges().to_upper()
	var orig := original_proposer.strip_edges().to_upper()
	if resp.is_empty() or orig.is_empty() or resp == orig:
		return {"ok": false, "reason": "invalid_tags"}
	var incoming_key := "%s>%s" % [orig, resp]
	if not _alliance_proposals.has(incoming_key):
		return {"ok": false, "reason": "no_incoming_to_counter"}
	var old: Dictionary = (_alliance_proposals[incoming_key] as Dictionary).duplicate(true)
	_alliance_proposals.erase(incoming_key)
	# Soft hit for rejecting as-is.
	apply_vector_delta(orig, resp, {"trust": -1, "elite": -1}, "alliance_countered")
	var day := 0
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
		day = int(TimeManager.get_total_days_elapsed())
	var crs := get_crs(resp, orig)
	var band := get_band(resp, orig)
	var require_g := bool(terms.get("require_guarantee", false))
	var note := str(terms.get("note", "counter-offer"))
	var min_crs := float(terms.get("min_crs", 0.0))
	var prop := {
		"from": resp,
		"to": orig,
		"day": day,
		"crs": crs,
		"band_id": str(band.get("id", "neutral")),
		"status": "pending",
		"is_counter": true,
		"counter_of": orig,
		"require_guarantee": require_g,
		"note": note,
		"min_crs": min_crs,
		"prior_crs": float(old.get("crs", 0.0)),
	}
	var out_key := "%s>%s" % [resp, orig]
	_alliance_proposals[out_key] = prop
	apply_vector_delta(resp, orig, {"public": 1, "military": 1}, "alliance_counter_offered")
	alliance_proposed.emit(resp, orig, prop.duplicate(true))
	return {"ok": true, "reason": "countered", "proposal": prop.duplicate(true), "replaced": old}


func get_pending_alliance_proposals(for_tag: String = "") -> Array:
	var tag := for_tag.strip_edges().to_upper()
	var out: Array = []
	for k in _alliance_proposals.keys():
		var p: Dictionary = _alliance_proposals[k]
		if p == null:
			continue
		if tag.is_empty():
			out.append((p as Dictionary).duplicate(true))
			continue
		if str(p.get("from", "")) == tag or str(p.get("to", "")) == tag:
			out.append((p as Dictionary).duplicate(true))
	return out


func get_outgoing_alliance_proposals(from_tag: String) -> Array:
	var fr := from_tag.strip_edges().to_upper()
	var out: Array = []
	for p in get_pending_alliance_proposals(fr):
		if str(p.get("from", "")) == fr:
			out.append(p)
	return out


func get_incoming_alliance_proposals(to_tag: String) -> Array:
	var to := to_tag.strip_edges().to_upper()
	var out: Array = []
	for p in get_pending_alliance_proposals(to):
		if str(p.get("to", "")) == to:
			out.append(p)
	return out


func has_pending_alliance(from_tag: String, to_tag: String) -> bool:
	var key := "%s>%s" % [from_tag.strip_edges().to_upper(), to_tag.strip_edges().to_upper()]
	return _alliance_proposals.has(key)


## AI auto-resolve pending proposals aimed at non-player tags (and optional player auto if CRS very high).
func _on_game_day_alliance_ai(_y: int = 0, _m: int = 0, _d: int = 0) -> void:
	if _alliance_proposals.is_empty():
		return
	var player := ""
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player = str(LeaderManager.get_player_country_tag()).to_upper()
	var keys: Array = _alliance_proposals.keys().duplicate()
	for k in keys:
		if not _alliance_proposals.has(k):
			continue
		var prop: Dictionary = _alliance_proposals[k]
		var to_tag := str(prop.get("to", "")).to_upper()
		var from_tag := str(prop.get("from", "")).to_upper()
		if to_tag.is_empty() or to_tag == player:
			continue  # player decides manually
		var day0 := int(prop.get("day", 0))
		var now := day0
		if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_total_days_elapsed"):
			now = int(TimeManager.get_total_days_elapsed())
		# Wait at least 1 day before AI decides.
		if now - day0 < 1:
			continue
		var crs := get_crs(from_tag, to_tag)
		var band := get_band(from_tag, to_tag)
		var bid := str(band.get("id", "neutral"))
		var accept := false
		var counter := false
		if bid in ["ally_ready", "partner"] or crs >= 55.0:
			accept = true
		elif crs >= 40.0 and bid == "cordial":
			accept = (now - day0) >= 3  # warm up
		elif crs >= 25.0 and crs < 40.0 and (now - day0) >= 2 and not bool(prop.get("is_counter", false)):
			# Pass 26: mid-band AI may counter with a guarantee requirement.
			counter = true
		elif crs < 10.0 or bid in ["hostile", "cold"]:
			accept = false
			decline_alliance(to_tag, from_tag)
			continue
		else:
			# Neutral: 30% after 5 days
			if now - day0 >= 5 and (hash(str(k) + str(now)) % 100) < 30:
				accept = true
			else:
				continue
		if counter:
			counter_alliance_offer(to_tag, from_tag, {
				"require_guarantee": true,
				"note": "AI counter: mutual defense + guarantee",
				"min_crs": 35.0,
			})
			continue
		if accept:
			accept_alliance(to_tag, from_tag)


func _clear_proposals_between(a: String, b: String) -> void:
	var x := a.strip_edges().to_upper()
	var y := b.strip_edges().to_upper()
	_alliance_proposals.erase("%s>%s" % [x, y])
	_alliance_proposals.erase("%s>%s" % [y, x])


## Unilateral independence guarantee (we guarantee them).
func set_guarantee(a: String, b: String, on: bool = true) -> Dictionary:
	## Stored as directed keys on the pair: guarantee_a_of_b style via tags.
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return {}
	var pol: Dictionary = (pair.get("policy", {}) as Dictionary).duplicate(true)
	var guarantor := a.strip_edges().to_upper()
	var protected := b.strip_edges().to_upper()
	var key := "guarantee_by_%s" % guarantor
	if on:
		pol[key] = protected
		pol["guarantee"] = true  # any active guarantee on this pair
	else:
		pol.erase(key)
		# Clear blanket flag if no guarantee_* keys remain.
		var any_g := false
		for k in pol.keys():
			if str(k).begins_with("guarantee_by_"):
				any_g = true
				break
		if not any_g:
			pol["guarantee"] = false
	pair["policy"] = pol
	_pairs[_pair_key(a, b)] = pair
	if on:
		apply_vector_delta(a, b, {"public": 2, "trust": 2}, "independence_guarantee")
	return get_snapshot(a, b)


func has_guarantee(guarantor: String, protected: String) -> bool:
	var pol := get_policy(guarantor, protected)
	var g := guarantor.strip_edges().to_upper()
	var p := protected.strip_edges().to_upper()
	if str(pol.get("guarantee_by_%s" % g, "")) == p:
		return true
	# Legacy / reverse: if either direction stored simply.
	return bool(pol.get("guarantee", false)) and (is_allied(g, p) or float(get_crs(g, p)) >= 40.0)


## Formal treaty ally OR active guarantee (not mere CRS partner).
func is_formal_ally_or_guaranteed(a: String, b: String) -> bool:
	if is_allied(a, b):
		return true
	if has_guarantee(a, b) or has_guarantee(b, a):
		return true
	return false


func evaluate_deal_concerns(
	from_tag: String,
	to_tag: String,
	item_types: Array = [],
	visibility: String = "public",
	tech_gap_years: float = 0.0,
) -> Dictionary:
	## Returns { flags: [], hard_block: bool, reasons: [] }
	var flags_out: Array = []
	var reasons: Array = []
	var hard := false
	var band := get_band(from_tag, to_tag)
	var crs := float(band.get("crs", 0.0))
	var types := []
	for t in item_types:
		types.append(str(t).to_lower())
	var vis := visibility.strip_edges().to_lower()
	var cf: Dictionary = get_rules().get("concern_flags", {}) as Dictionary if get_rules().get("concern_flags") is Dictionary else {}

	if vis == "black" or vis == "black_visibility":
		flags_out.append("embargo_evasion")
		reasons.append("Black-market path risks scandal and trust damage")

	if "province" in types:
		flags_out.append("territory_humiliation")
		reasons.append("Territory cession permanently scars trust and public opinion")
		if crs < 55.0:
			hard = true
			reasons.append("CRS too low for peaceful territorial transfer")

	if "docking_rights" in types or "military_access" in types:
		flags_out.append("basing_sovereignty")
		var basing_floor := 55.0
		if cf.get("basing_sovereignty") is Dictionary:
			basing_floor = float((cf["basing_sovereignty"] as Dictionary).get("hard_block_if_crs_below", 55))
		if crs < basing_floor:
			hard = true
			reasons.append("Basing/access refused below Partner band")

	if "design" in types or "tech_share" in types:
		if tech_gap_years >= 8.0:
			flags_out.append("tech_leak_risk")
			var floor := 40.0
			if cf.get("tech_leak_risk") is Dictionary:
				floor = float((cf["tech_leak_risk"] as Dictionary).get("hard_block_if_crs_below", 40))
			if crs < floor:
				hard = true
				reasons.append("Tech gap too large for current trust")

	if "equipment" in types or "design" in types:
		# Soft flag — full rival check needs war graph later
		if crs < 25.0:
			flags_out.append("enemy_arming")
			reasons.append("Arms/design to cold partner raises enemy_arming concern")

	var pol := get_policy(from_tag, to_tag)
	if bool(pol.get("embargo", false)) and vis != "black":
		hard = true
		reasons.append("Embargo blocks public trade")

	return {
		"flags": flags_out,
		"hard_block": hard,
		"reasons": reasons,
		"crs": crs,
		"band": band,
	}


func get_snapshot(a: String, b: String) -> Dictionary:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return {}
	var band := get_band(a, b)
	return {
		"a": str(pair.get("a", "")),
		"b": str(pair.get("b", "")),
		"vectors": (pair.get("vectors", {}) as Dictionary).duplicate(true),
		"crs": float(band.get("crs", 0.0)),
		"band": band,
		"flags": get_flags(a, b),
		"policy": get_policy(a, b),
		"relationship_years": float(pair.get("relationship_years", 0.0)),
		"model": "strategic_compact_ledger",
	}


func set_relationship_years(a: String, b: String, years: float) -> void:
	var pair := _ensure_pair(a, b)
	if pair.is_empty():
		return
	pair["relationship_years"] = maxf(years, 0.0)
	_pairs[_pair_key(a, b)] = pair


func get_relationship_discounts(a: String, b: String) -> Dictionary:
	var band := get_band(a, b)
	var pol := get_policy(a, b)
	var pair := _ensure_pair(a, b)
	var years := float(pair.get("relationship_years", 0.0)) if not pair.is_empty() else 0.0
	var npc = load("res://scripts/national/NationalPowerCalculator.gd")
	if npc != null and npc.has_method("relationship_discount_mults"):
		return npc.relationship_discount_mults(str(band.get("id", "neutral")), bool(pol.get("mfn", false)), years) as Dictionary
	return {"trade_suu_mult": 1.0, "tech_share_suu_mult": 1.0}


## Power asymmetry + nuclear placate: smaller AI bends more to nuclear great powers.
func get_power_matchup_report(self_tag: String, other_tag: String, self_inputs: Dictionary = {}, other_inputs: Dictionary = {}) -> Dictionary:
	var npc = load("res://scripts/national/NationalPowerCalculator.gd")
	if npc == null:
		return {}
	var sp: Dictionary = npc.compute_power_index(self_inputs) as Dictionary
	var op: Dictionary = npc.compute_power_index(other_inputs) as Dictionary
	var mu: Dictionary = npc.matchup(sp, op) as Dictionary
	var placate_delta: float = float(npc.ai_placate_accept_floor_delta(mu))
	var band := get_band(self_tag, other_tag)
	var accept_floor: float = float(band.get("accept_floor", 0.95)) + placate_delta
	# Flags are advisory here — callers (AI tick / desk) may raise; avoid side effects in pure matchup queries
	return {
		"self_power": sp,
		"other_power": op,
		"matchup": mu,
		"accept_floor_adjusted": snappedf(accept_floor, 0.01),
		"placate_delta": placate_delta,
		"band": band,
		"player_warning": str(mu.get("label", "peer")),
		"suggest_flags": (
			(["nuclear_intimidation"] if bool(mu.get("nuclear_asymmetry", false)) else [])
			+ (["hopelessly_outmatched"] if bool(mu.get("hopeless", false)) else [])
		),
	}


## Spy/diplomatic mission clarity on bilateral ledger and optional third-party trade.
func build_spy_relation_report(
	observer_tag: String,
	target_tag: String,
	third_party_tag: String = "",
	mission_success: bool = false,
	has_network: bool = false,
	third_party_trade_summaries: Array = [],
) -> Dictionary:
	var npc = load("res://scripts/national/NationalPowerCalculator.gd")
	var clarity: float = 0.35
	if npc != null and npc.has_method("spy_clarity"):
		clarity = float(npc.spy_clarity(mission_success, has_network))
	var rules: Dictionary = {}
	if npc != null and npc.has_method("get_rules"):
		var nr: Dictionary = npc.get_rules() as Dictionary
		rules = nr.get("spy_intel", {}) as Dictionary if nr.get("spy_intel") is Dictionary else {}
	var snap := get_snapshot(observer_tag, target_tag)
	var out := {
		"observer": observer_tag.strip_edges().to_upper(),
		"target": target_tag.strip_edges().to_upper(),
		"clarity": clarity,
		"revealed": {},
		"model": "strategic_compact_ledger",
	}
	var revealed: Dictionary = {}
	if clarity >= float(rules.get("reveal_flags_at", 0.4)):
		revealed["flags"] = get_flags(observer_tag, target_tag)
	if clarity >= float(rules.get("reveal_vectors_at", 0.5)):
		revealed["vectors"] = get_vectors(observer_tag, target_tag)
		revealed["crs"] = get_crs(observer_tag, target_tag)
		revealed["band"] = get_band(observer_tag, target_tag)
	else:
		# Partial: band label only
		revealed["band_label"] = str((snap.get("band", {}) as Dictionary).get("label", "Unknown"))
	if not third_party_tag.is_empty() and clarity >= float(rules.get("reveal_third_party_trade_at", 0.55)):
		var tp_snap := get_snapshot(target_tag, third_party_tag)
		revealed["third_party"] = {
			"tag": third_party_tag.strip_edges().to_upper(),
			"crs": float(tp_snap.get("crs", 0.0)),
			"band": tp_snap.get("band", {}),
			"flags": get_flags(target_tag, third_party_tag),
			"active_trade_summaries": third_party_trade_summaries,
		}
	out["revealed"] = revealed
	out["snapshot_partial"] = clarity < 0.9
	return out


func get_save_data() -> Dictionary:
	var tpls: Array = []
	for t in campaign_counter_templates:
		if t is Dictionary:
			tpls.append((t as Dictionary).duplicate(true))
	return {
		"pairs": _pairs.duplicate(true),
		"alliance_proposals": _alliance_proposals.duplicate(true),
		"campaign_counter_templates": tpls,
	}


func apply_save_data(data: Dictionary) -> void:
	if data.has("pairs") and data["pairs"] is Dictionary:
		_pairs = (data["pairs"] as Dictionary).duplicate(true)
	if data.has("alliance_proposals") and data["alliance_proposals"] is Dictionary:
		_alliance_proposals = (data["alliance_proposals"] as Dictionary).duplicate(true)
	if data.has("campaign_counter_templates") and data["campaign_counter_templates"] is Array:
		campaign_counter_templates = []
		for t in data["campaign_counter_templates"]:
			if t is Dictionary:
				campaign_counter_templates.append((t as Dictionary).duplicate(true))


## Pass 30: campaign-shared counter templates API.
func get_campaign_counter_templates() -> Array:
	var out: Array = []
	for t in campaign_counter_templates:
		if t is Dictionary:
			out.append((t as Dictionary).duplicate(true))
	return out


func add_campaign_counter_template(tpl: Dictionary) -> bool:
	var label := str(tpl.get("label", "Custom")).strip_edges()
	if label.is_empty():
		label = "Custom"
	var entry := tpl.duplicate(true)
	entry["label"] = label
	entry["id"] = str(entry.get("id", "camp_%d" % Time.get_ticks_msec()))
	entry["campaign"] = true
	var replaced := false
	for i in campaign_counter_templates.size():
		if str((campaign_counter_templates[i] as Dictionary).get("label", "")) == label:
			campaign_counter_templates[i] = entry
			replaced = true
			break
	if not replaced:
		campaign_counter_templates.append(entry)
	while campaign_counter_templates.size() > CAMPAIGN_TEMPLATE_MAX:
		campaign_counter_templates.pop_front()
	return true


func delete_campaign_counter_template(label: String) -> bool:
	var next: Array = []
	var found := false
	for t in campaign_counter_templates:
		if str((t as Dictionary).get("label", "")) == label:
			found = true
			continue
		next.append(t)
	campaign_counter_templates = next
	return found


func _load_rules() -> void:
	_rules = {}
	if not FileAccess.file_exists(RULES_PATH):
		return
	var f := FileAccess.open(RULES_PATH, FileAccess.READ)
	if f == null:
		return
	var p := JSON.new()
	if p.parse(f.get_as_text()) == OK and typeof(p.data) == TYPE_DICTIONARY:
		_rules = p.data
