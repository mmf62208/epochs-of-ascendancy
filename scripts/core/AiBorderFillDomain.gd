# scripts/core/AiBorderFillDomain.gd
## When a neighbour is at war or justifying, keep a land unit on every friendly
## hex that already touches an enemy land unit, and do not spend that last unit
## on an attack. Empty contact hexes are filled before anyone attacks elsewhere.
## Quiet border hexes (no enemy unit adjacent) are not locked, so a nation with
## no garrison still walks into an empty neighbour. No RNG. Marches are capped
## by count (defence_marches_per_day), never by wall-clock.
class_name AiBorderFillDomain
extends RefCounted


static func enabled() -> bool:
	return AiCredibleDomain.enabled()


## False when this sole unit is the last one on a core gate that already
## touches a threatened neighbour. Callers that attack elsewhere must obey it.
static func may_leave(tag: String, fid: String, pid: int) -> bool:
	if not enabled():
		return true
	if tag.is_empty() or fid.is_empty() or pid <= 0:
		return true
	var threats := _threatened_set(tag)
	if threats.is_empty():
		return true
	var here: Array = (_hex_index(tag).get(pid, []) as Array)
	if here.size() != 1 or str(here[0]) != fid:
		return true
	if not _touches_enemy_land(pid, threats):
		return true
	return not AiStartGarrisonDomain.is_core_gate(tag, pid)


static func tick(day: int) -> Dictionary:
	var out := {"marches": 0, "holes": 0}
	if not enabled():
		out["skipped"] = true
		return out
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return out
	if not _any_threat():
		return out
	var budget := AiCredibleDomain.tune_int("defence_marches_per_day", 2)
	var used := 0
	var player := AiCredibleDomain.player_tag()
	var tags: Array = AiCredibleDomain.majors()
	for raw in tags:
		var tag := str(raw)
		if tag.is_empty() or tag == player:
			continue
		if used >= budget:
			break
		var threats := _threatened(tag)
		if threats.is_empty():
			continue
		if not _has_land(tag):
			continue
		var holes: Array = _contact_holes(tag, threats)
		out["holes"] = int(out["holes"]) + holes.size()
		for hole_v in holes:
			if used >= budget:
				break
			var dest := int(hole_v)
			if dest <= 0 or _unit_on(tag, dest) or _march_inbound(tag, dest):
				continue
			if _march_one_to(tag, dest, threats):
				used += 1
				out["marches"] = int(out["marches"]) + 1
				AiCredibleDomain.trace_line("BORDER day=%d tag=%s dest=%d" % [day, tag, dest])
	return out


## Drop attacks that would leave the last land unit on a hex already touching
## an enemy unit. A unit on a border with no enemy unit adjacent can still attack,
## which is what lets an ungarrisoned neighbour walk into empty hexes.
static func retain_attacks(opps: Array) -> Array:
	if not enabled() or opps.is_empty():
		return opps
	var index: Dictionary = {}
	var threats: Dictionary = {}
	var out: Array = []
	for raw in opps:
		if not (raw is Dictionary):
			out.append(raw)
			continue
		var row: Dictionary = raw
		var tag := str(row.get("tag", "")).strip_edges().to_upper()
		var fid := str(row.get("formation_id", "")).strip_edges()
		var frm := int(row.get("from_id", 0))
		if not index.has(tag):
			index[tag] = _hex_index(tag)
		if not threats.has(tag):
			threats[tag] = _threatened_set(tag)
		if _blocks(tag, fid, frm, index[tag], threats[tag]):
			continue
		out.append(row)
	return out


static func _blocks(tag: String, fid: String, frm: int, hex_index: Dictionary, threats: Dictionary) -> bool:
	if tag.is_empty() or fid.is_empty() or frm <= 0 or threats.is_empty():
		return false
	var here: Array = hex_index.get(frm, []) as Array
	if here.size() != 1 or str(here[0]) != fid:
		return false
	if _touches_enemy_unit(frm, threats):
		return true
	if not _touches_enemy_land(frm, threats):
		return false
	return AiStartGarrisonDomain.is_core_gate(tag, frm)


static func _any_threat() -> bool:
	if not WarStateDomain.justify_rows().is_empty():
		return true
	for raw in AiCredibleDomain.majors():
		var tag := str(raw)
		if tag.is_empty():
			continue
		if not WarStateDomain.enemies_of(tag).is_empty():
			return true
	return false


static func _threatened(tag: String) -> Array:
	var set := _threatened_set(tag)
	var out: Array = set.keys()
	out.sort()
	return out


static func _threatened_set(tag: String) -> Dictionary:
	var out: Dictionary = {}
	if typeof(WarStateDomain) == TYPE_NIL:
		return out
	for e in WarStateDomain.enemies_of(tag):
		var et := str(e).strip_edges().to_upper()
		if not et.is_empty():
			out[et] = true
	for row_v in WarStateDomain.justify_rows():
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var a := str(row.get("attacker", "")).strip_edges().to_upper()
		var b := str(row.get("defender", "")).strip_edges().to_upper()
		if a == tag and not b.is_empty():
			out[b] = true
		elif b == tag and not a.is_empty():
			out[a] = true
	return out


static func _contact_holes(tag: String, threats: Array) -> Array:
	var holes: Dictionary = {}
	for enemy_v in threats:
		var enemy := str(enemy_v)
		for fid_v in _land_ids(enemy):
			var form: Formation = LeaderManager.get_formation(str(fid_v))
			if form == null:
				continue
			var epid := int(form.stationed_province_id)
			if epid <= 0:
				continue
			for nid in _adj(epid):
				var prov: Province = MapManager.get_province(nid)
				if prov == null or bool(prov.is_sea):
					continue
				if _prov_tag(prov) != tag:
					continue
				if _unit_on(tag, nid):
					continue
				holes[nid] = enemy
	var ranked: Array = []
	for pid_v in holes.keys():
		var pid := int(pid_v)
		var enemy := str(holes[pid])
		ranked.append({
			"pid": pid,
			"enemy": enemy,
			"goal": _goal(tag, enemy),
		})
	ranked.sort_custom(func(a, b):
		var da: Dictionary = a
		var db: Dictionary = b
		var ga := float(da.get("goal", 0.0))
		var gb := float(db.get("goal", 0.0))
		if not is_equal_approx(ga, gb):
			return ga > gb
		var ea := str(da.get("enemy", ""))
		var eb := str(db.get("enemy", ""))
		if ea != eb:
			return ea < eb
		return int(da.get("pid", 0)) < int(db.get("pid", 0))
	)
	var out: Array = []
	for row_v in ranked:
		out.append(int((row_v as Dictionary).get("pid", 0)))
	return out


static func _march_one_to(tag: String, dest: int, threats: Array) -> bool:
	if dest <= 0 or typeof(FormationMovement) == TYPE_NIL or typeof(LeaderManager) == TYPE_NIL:
		return false
	var threat_set: Dictionary = {}
	for t in threats:
		threat_set[str(t)] = true
	var cap := AiDefenceDomain.capital_pid(tag)
	var probes := AiCredibleDomain.tune_int("defence_path_probes", 6)
	var best_fid := ""
	var best_hops := 999999
	var seen := 0
	for fid_v in _land_ids(tag):
		if seen >= probes:
			break
		var fid := str(fid_v)
		var form: Formation = LeaderManager.get_formation(fid)
		if form == null:
			continue
		if "is_in_combat" in form and bool(form.is_in_combat):
			continue
		if FormationMovement.has_march(fid):
			continue
		var station := int(form.stationed_province_id)
		if station <= 0 or station == dest or station == cap:
			continue
		if _sole_contact(tag, fid, station, threat_set):
			continue
		seen += 1
		var path: Array = FormationMovement.find_own_land_path(station, dest, tag)
		if path.size() < 2:
			continue
		if path.size() < best_hops or (path.size() == best_hops and (best_fid.is_empty() or fid < best_fid)):
			best_hops = path.size()
			best_fid = fid
	if best_fid.is_empty():
		return false
	var enq: Dictionary = FormationMovement.enqueue_own_land_march(best_fid, dest, tag)
	return bool(enq.get("ok", false))


static func _sole_contact(tag: String, fid: String, pid: int, threats: Dictionary) -> bool:
	var idx := _hex_index(tag)
	var here: Array = idx.get(pid, []) as Array
	if here.size() != 1 or str(here[0]) != fid:
		return false
	return _touches_enemy_unit(pid, threats)


static func _touches_enemy_land(pid: int, threats: Dictionary) -> bool:
	for nid in _adj(pid):
		var prov: Province = MapManager.get_province(nid)
		if prov == null or bool(prov.is_sea):
			continue
		if threats.has(_prov_tag(prov)):
			return true
	return false


static func _touches_enemy_unit(pid: int, threats: Dictionary) -> bool:
	for nid in _adj(pid):
		var prov: Province = MapManager.get_province(nid)
		if prov == null or bool(prov.is_sea):
			continue
		var ot := _prov_tag(prov)
		if not threats.has(ot):
			continue
		if _unit_on(ot, nid):
			return true
	return false


static func _hex_index(tag: String) -> Dictionary:
	var out: Dictionary = {}
	for fid_v in _land_ids(tag):
		var fid := str(fid_v)
		var form: Formation = LeaderManager.get_formation(fid)
		if form == null:
			continue
		var pid := int(form.stationed_province_id)
		if pid <= 0:
			continue
		if not out.has(pid):
			out[pid] = []
		(out[pid] as Array).append(fid)
	return out


static func _land_ids(tag: String) -> Array:
	var ids: Array = []
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formations_for_country"):
		return ids
	for form in LeaderManager.get_formations_for_country(tag):
		if form == null:
			continue
		var ft := str(form.formation_type) if "formation_type" in form else ""
		if ft != "division" and ft != "garrison":
			continue
		var fid := str(form.formation_id) if "formation_id" in form else ""
		if fid.is_empty():
			continue
		ids.append(fid)
	ids.sort()
	return ids


static func _has_land(tag: String) -> bool:
	return not _land_ids(tag).is_empty()


static func _unit_on(tag: String, pid: int) -> bool:
	if pid <= 0:
		return false
	for fid_v in _land_ids(tag):
		var form: Formation = LeaderManager.get_formation(str(fid_v))
		if form != null and int(form.stationed_province_id) == pid:
			return true
	return false


static func _march_inbound(tag: String, dest: int) -> bool:
	if typeof(FormationMovement) == TYPE_NIL:
		return false
	for raw in FormationMovement.list_marches():
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		if str(row.get("country_tag", "")).strip_edges().to_upper() != tag:
			continue
		if int(row.get("dest_id", -1)) == dest:
			return true
	return false


static func _goal(us: String, them: String) -> float:
	var goals := AiCredibleDomain.goals_for(us)
	var raw: Variant = goals.get("targets", [])
	if not (raw is Array):
		return 0.0
	for item in raw:
		if item is Dictionary and str((item as Dictionary).get("tag", "")).strip_edges().to_upper() == them:
			return float((item as Dictionary).get("weight", 0.0))
	return 0.0


static func _adj(pid: int) -> Array:
	var out: Array = []
	if pid <= 0 or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_adjacent_provinces"):
		return out
	var seen: Dictionary = {}
	for nid_v in MapManager.get_adjacent_provinces(pid, true):
		var nid := int(nid_v)
		if nid <= 0 or seen.has(nid):
			continue
		seen[nid] = true
		out.append(nid)
	out.sort()
	return out


static func _prov_tag(prov: Province) -> String:
	if prov == null:
		return ""
	var ctrl := str(prov.controller_tag).strip_edges().to_upper()
	if not ctrl.is_empty():
		return ctrl
	return str(prov.owner_tag).strip_edges().to_upper()
