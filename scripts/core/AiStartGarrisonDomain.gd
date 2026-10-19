# scripts/core/AiStartGarrisonDomain.gd
## Put each nation's existing land divisions on its capital and land borders.
## The plan is data/scenarios/ai_start_garrisons_1936.json. Stations are a pure
## function of that policy, the map, and the land formations already spawned.
## No new units, no RNG, no province-id renumber.
class_name AiStartGarrisonDomain
extends RefCounted

const POLICY_PATH := "res://data/scenarios/ai_start_garrisons_1936.json"

static var _policy: Dictionary = {}
static var _policy_loaded: bool = false


static func reset_cache() -> void:
	_policy_loaded = false
	_policy = {}


static func enabled() -> bool:
	return AiCredibleDomain.enabled()


static func policy() -> Dictionary:
	if _policy_loaded:
		return _policy
	_policy_loaded = true
	_policy = {}
	if not FileAccess.file_exists(POLICY_PATH):
		return _policy
	var f := FileAccess.open(POLICY_PATH, FileAccess.READ)
	if f == null:
		return _policy
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_policy = parsed
	return _policy


static func apply() -> Dictionary:
	var out := {"ok": true, "moved": 0, "tags": [], "summary": ""}
	if not enabled():
		out["skipped"] = true
		out["reason"] = "killswitch"
		out["summary"] = "skipped"
		return out
	if typeof(LeaderManager) == TYPE_NIL or typeof(MapManager) == TYPE_NIL:
		out["ok"] = false
		out["reason"] = "missing autoload"
		return out
	var forms_by_tag: Dictionary = _land_by_tag()
	if forms_by_tag.is_empty():
		out["summary"] = "no land formations"
		return out
	var tags: Array = forms_by_tag.keys()
	tags.sort()
	var strength: Dictionary = {}
	var owned: Dictionary = {}
	var borders: Dictionary = {}
	for tag_v in tags:
		var tag := str(tag_v)
		var own: Array = _owned_land(tag)
		owned[tag] = own
		strength[tag] = _strength_of(own)
		borders[tag] = _border_groups(tag, own)
	var assign: Dictionary = {}
	var capital_of: Dictionary = {}
	var capital_fid: Dictionary = {}
	for tag_v2 in tags:
		var tag2 := str(tag_v2)
		var ids: Array = forms_by_tag[tag2]
		var cap := _capital(tag2, owned[tag2])
		capital_of[tag2] = cap
		if ids.is_empty():
			continue
		var start_i := 0
		if cap > 0 and bool(policy().get("capital_first", true)):
			assign[str(ids[0])] = cap
			capital_fid[tag2] = str(ids[0])
			start_i = 1
		var rest: Array = []
		for i in range(start_i, ids.size()):
			rest.append(str(ids[i]))
		_pass_border(tag2, rest, borders[tag2], strength, assign)
	var tops: Dictionary = {}
	if bool(policy().get("cover_enemy_stations", true)):
		tops = _pass_cover(tags, forms_by_tag, owned, borders, strength, assign, capital_fid)
	if bool(policy().get("reserve_one_hop", true)):
		_pass_reserve(tags, forms_by_tag, owned, borders, strength, assign, capital_fid, tops)
	var moved := 0
	var fid_keys: Array = assign.keys()
	fid_keys.sort()
	for fid_v in fid_keys:
		var fid := str(fid_v)
		var pid := int(assign[fid])
		if pid <= 0:
			continue
		var form: Formation = LeaderManager.get_formation(fid)
		if form == null:
			continue
		if int(form.stationed_province_id) != pid:
			form.stationed_province_id = pid
			moved += 1
	var rows: Array = _reports(tags, forms_by_tag, owned, borders, capital_of, assign)
	out["moved"] = moved
	out["tags"] = rows
	out["summary"] = _summary(rows)
	return out


static func core_snapshot(tag: String) -> Dictionary:
	var nation := tag.strip_edges().to_upper()
	var tokens: Array = []
	var block: Variant = policy().get("core_name_tokens", {})
	if block is Dictionary:
		var raw: Variant = (block as Dictionary).get(nation, [])
		if raw is Array:
			tokens = raw
	var hop_n := int(policy().get("core_hops", 0))
	var own: Array = _owned_land(nation)
	var cap := _capital(nation, own)
	var hop_set: Dictionary = {}
	if hop_n > 0 and cap > 0:
		hop_set = _hops_within(nation, cap, hop_n, own)
	var pids: Array = []
	var names: Dictionary = {}
	var weights: Dictionary = {}
	var total := 0
	for pid_v in own:
		var pid := int(pid_v)
		var prov: Province = MapManager.get_province(pid) if typeof(MapManager) != TYPE_NIL else null
		var nm := str(prov.name) if prov != null else ""
		var w := int(prov.factories) if prov != null else 1
		if w < 1:
			w = 1
		var take := pid == cap or hop_set.has(pid) or _name_hit(nm, tokens)
		if not take:
			continue
		pids.append(pid)
		names[pid] = nm
		weights[pid] = w
		total += w
	pids.sort()
	return {
		"tag": nation,
		"pids": pids,
		"names": names,
		"weights": weights,
		"weight": total,
		"capital": cap,
	}


static func _pass_border(tag: String, rest: Array, groups: Dictionary, strength: Dictionary, assign: Dictionary) -> void:
	if rest.is_empty() or groups.is_empty():
		return
	var neighbours: Array = groups.keys()
	neighbours.sort_custom(func(a, b):
		return _neigh_before(tag, str(a), str(b), strength)
	)
	var used: Dictionary = {}
	for fid_v in assign.keys():
		var upid := int(assign[fid_v])
		used[upid] = int(used.get(upid, 0)) + 1
	var ni := 0
	for fid_v2 in rest:
		var nb := ""
		var guard := 0
		while guard < neighbours.size():
			var cand := str(neighbours[ni % neighbours.size()])
			ni += 1
			guard += 1
			var hexes: Array = groups.get(cand, []) as Array
			if not hexes.is_empty():
				nb = cand
				break
		if nb.is_empty():
			break
		var pid := _pick_hex(groups[nb], used)
		if pid <= 0:
			continue
		assign[str(fid_v2)] = pid
		used[pid] = int(used.get(pid, 0)) + 1


static func _pass_cover(
	tags: Array,
	forms_by_tag: Dictionary,
	owned: Dictionary,
	borders: Dictionary,
	strength: Dictionary,
	assign: Dictionary,
	capital_fid: Dictionary,
) -> Dictionary:
	var station: Dictionary = _stations(tags, forms_by_tag, assign)
	var tops: Dictionary = {}
	for tag_v in tags:
		var tag := str(tag_v)
		var jobs: Array = _contact_jobs(tag, tags, forms_by_tag, owned[tag], station, strength)
		if jobs.is_empty():
			continue
		tops[tag] = {
			"pid": int((jobs[0] as Dictionary).get("pid", 0)),
			"enemy": str((jobs[0] as Dictionary).get("enemy", "")),
		}
		var locked: Dictionary = {}
		var cap_fid := str(capital_fid.get(tag, ""))
		if not cap_fid.is_empty():
			locked[cap_fid] = true
		var covered: Dictionary = {}
		var our_ids: Array = forms_by_tag[tag]
		for job_v in jobs:
			var jpid := int((job_v as Dictionary).get("pid", 0))
			for fid_v in our_ids:
				var fid := str(fid_v)
				if int(station.get(fid, -1)) == jpid:
					locked[fid] = true
					covered[jpid] = true
					break
		var groups: Dictionary = borders.get(tag, {})
		for job_v2 in jobs:
			var job: Dictionary = job_v2
			var pid := int(job.get("pid", 0))
			if covered.has(pid):
				continue
			var pick := _pull_lowest(tag, our_ids, station, groups, strength, locked)
			if pick.is_empty():
				break
			assign[pick] = pid
			station[pick] = pid
			locked[pick] = true
			covered[pid] = true
	return tops


static func _pass_reserve(
	tags: Array,
	forms_by_tag: Dictionary,
	owned: Dictionary,
	borders: Dictionary,
	strength: Dictionary,
	assign: Dictionary,
	capital_fid: Dictionary,
	tops: Dictionary,
) -> void:
	var station: Dictionary = _stations(tags, forms_by_tag, assign)
	for tag_v in tags:
		var tag := str(tag_v)
		var top: Dictionary = tops.get(tag, {}) as Dictionary
		if top.is_empty():
			continue
		var contact := int(top.get("pid", 0))
		var enemy := str(top.get("enemy", ""))
		if contact <= 0 or enemy.is_empty():
			continue
		var own: Array = owned[tag]
		var own_set: Dictionary = {}
		for pid_v in own:
			own_set[int(pid_v)] = true
		var dests: Array = []
		for nid_v in _adj(contact):
			var nid := int(nid_v)
			if not own_set.has(nid) or nid == contact:
				continue
			if _touches(nid, enemy):
				continue
			dests.append(nid)
		dests.sort()
		if dests.is_empty():
			continue
		var dest := int(dests[0])
		var jobs: Array = _contact_jobs(tag, tags, forms_by_tag, own, station, strength)
		var job_hex: Dictionary = {}
		for job_v in jobs:
			job_hex[int((job_v as Dictionary).get("pid", 0))] = true
		var locked: Dictionary = {}
		var cap_fid := str(capital_fid.get(tag, ""))
		if not cap_fid.is_empty():
			locked[cap_fid] = true
		var our_ids: Array = forms_by_tag[tag]
		for fid_v in our_ids:
			var fid := str(fid_v)
			if job_hex.has(int(station.get(fid, -1))):
				locked[fid] = true
		var groups: Dictionary = borders.get(tag, {})
		var pick := _pull_lowest(tag, our_ids, station, groups, strength, locked)
		if pick.is_empty():
			continue
		assign[pick] = dest
		station[pick] = dest


static func _contact_jobs(
	tag: String,
	tags: Array,
	forms_by_tag: Dictionary,
	own: Array,
	station: Dictionary,
	strength: Dictionary,
) -> Array:
	var own_set: Dictionary = {}
	for pid_v in own:
		own_set[int(pid_v)] = true
	var raw: Array = []
	for et_v in tags:
		var et := str(et_v)
		if et == tag or not forms_by_tag.has(et):
			continue
		for efid_v in forms_by_tag[et]:
			var efid := str(efid_v)
			var epid := int(station.get(efid, -1))
			if epid <= 0:
				continue
			for nid in _adj(epid):
				if not own_set.has(nid):
					continue
				raw.append({
					"pid": nid,
					"enemy": et,
					"goal": _goal(tag, et),
					"stren": int(strength.get(et, 0)),
					"efid": efid,
				})
	raw.sort_custom(func(a, b):
		return _job_before(a, b)
	)
	var jobs: Array = []
	var seen: Dictionary = {}
	for job_v in raw:
		var job: Dictionary = job_v
		var pid := int(job.get("pid", 0))
		if seen.has(pid):
			continue
		seen[pid] = true
		jobs.append(job)
	return jobs


static func _pull_lowest(
	tag: String,
	our_ids: Array,
	station: Dictionary,
	groups: Dictionary,
	strength: Dictionary,
	locked: Dictionary,
) -> String:
	var best := ""
	var best_g := 0.0
	var best_s := 0
	var have := false
	for fid_v in our_ids:
		var fid := str(fid_v)
		if locked.has(fid):
			continue
		var pr := _hex_priority(tag, int(station.get(fid, -1)), groups, strength)
		var g := float(pr.get("goal", -1.0))
		var s := int(pr.get("stren", -1))
		if not have or g < best_g or (is_equal_approx(g, best_g) and s < best_s) or (is_equal_approx(g, best_g) and s == best_s and fid > best):
			best = fid
			best_g = g
			best_s = s
			have = true
	return best


static func _hex_priority(tag: String, pid: int, groups: Dictionary, strength: Dictionary) -> Dictionary:
	var best_g := -1.0
	var best_s := -1
	if pid <= 0:
		return {"goal": best_g, "stren": best_s}
	for nb_v in groups.keys():
		var nb := str(nb_v)
		for row_v in groups[nb]:
			if not (row_v is Dictionary):
				continue
			if int((row_v as Dictionary).get("pid", 0)) != pid:
				continue
			var g := _goal(tag, nb)
			var s := int(strength.get(nb, 0))
			if g > best_g or (is_equal_approx(g, best_g) and s > best_s):
				best_g = g
				best_s = s
	return {"goal": best_g, "stren": best_s}


static func _reports(
	tags: Array,
	forms_by_tag: Dictionary,
	owned: Dictionary,
	borders: Dictionary,
	capital_of: Dictionary,
	assign: Dictionary,
) -> Array:
	var station: Dictionary = _stations(tags, forms_by_tag, assign)
	var rows: Array = []
	for tag_v in tags:
		var tag := str(tag_v)
		var ids: Array = forms_by_tag[tag]
		var cap := int(capital_of.get(tag, -1))
		var on_cap := false
		var occ: Dictionary = {}
		var placed: PackedStringArray = PackedStringArray()
		for fid_v in ids:
			var fid := str(fid_v)
			var pid := int(station.get(fid, -1))
			if pid == cap and cap > 0:
				on_cap = true
			if pid > 0:
				occ[pid] = true
			placed.append("%s@%d" % [fid, pid])
		var border_ids: Dictionary = {}
		var groups: Dictionary = borders.get(tag, {})
		for nb_v in groups.keys():
			for row_v in groups[nb_v]:
				if row_v is Dictionary:
					border_ids[int((row_v as Dictionary).get("pid", 0))] = true
		var border_total := 0
		var border_covered := 0
		for bpid_v in border_ids.keys():
			if int(bpid_v) <= 0:
				continue
			border_total += 1
			if occ.has(int(bpid_v)):
				border_covered += 1
		var own: Array = owned.get(tag, [])
		var open_pids: Array = _open_contacts(tag, tags, forms_by_tag, own, station, occ)
		rows.append({
			"tag": tag,
			"capital_pid": cap,
			"capital_garrisoned": on_cap,
			"border_covered": border_covered,
			"border_total": border_total,
			"units": ids.size(),
			"open_contacts": open_pids.size(),
			"open_pids": open_pids,
			"stations": ", ".join(placed),
		})
	return rows


static func _open_contacts(
	tag: String,
	tags: Array,
	forms_by_tag: Dictionary,
	own: Array,
	station: Dictionary,
	occ: Dictionary,
) -> Array:
	var own_set: Dictionary = {}
	for pid_v in own:
		own_set[int(pid_v)] = true
	var open: Dictionary = {}
	for et_v in tags:
		var et := str(et_v)
		if et == tag or not forms_by_tag.has(et):
			continue
		for efid_v in forms_by_tag[et]:
			var epid := int(station.get(str(efid_v), -1))
			if epid <= 0:
				continue
			for nid in _adj(epid):
				if own_set.has(nid) and not occ.has(nid):
					open[nid] = true
	var pids: Array = open.keys()
	pids.sort()
	return pids


static func _summary(rows: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for row_v in rows:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		parts.append(
			"%s capital=%s units=%d border=%d/%d open=%d"
			% [
				str(row.get("tag", "")),
				"y" if bool(row.get("capital_garrisoned", false)) else "n",
				int(row.get("units", 0)),
				int(row.get("border_covered", 0)),
				int(row.get("border_total", 0)),
				int(row.get("open_contacts", 0)),
			]
		)
	return "; ".join(parts)


static func _stations(tags: Array, forms_by_tag: Dictionary, assign: Dictionary) -> Dictionary:
	var station: Dictionary = {}
	for tag_v in tags:
		for fid_v in forms_by_tag[tag_v]:
			var fid := str(fid_v)
			if assign.has(fid):
				station[fid] = int(assign[fid])
				continue
			var form: Formation = LeaderManager.get_formation(fid)
			station[fid] = int(form.stationed_province_id) if form != null else -1
	return station


static func _land_by_tag() -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = LeaderManager.formations.keys()
	keys.sort()
	for fid_v in keys:
		var form: Formation = LeaderManager.get_formation(str(fid_v))
		if form == null:
			continue
		if "campaign_inactive" in form and bool(form.campaign_inactive):
			continue
		var ft := str(form.formation_type)
		if ft != "division" and ft != "garrison":
			continue
		var tag := str(form.country_tag).strip_edges().to_upper()
		if tag.is_empty():
			continue
		if not out.has(tag):
			out[tag] = []
		(out[tag] as Array).append(str(form.formation_id))
	for tag_v in out.keys():
		(out[tag_v] as Array).sort()
	return out


static func _owned_land(tag: String) -> Array:
	var out: Array = []
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_provinces_by_owner"):
		return out
	for pid_v in MapManager.get_provinces_by_owner(tag):
		var pid := int(pid_v)
		var prov: Province = MapManager.get_province(pid) if MapManager.has_method("get_province") else null
		if prov == null or bool(prov.is_sea):
			continue
		if _prov_tag(prov) != tag:
			continue
		out.append(pid)
	out.sort()
	return out


static func _border_groups(tag: String, own: Array) -> Dictionary:
	var own_set: Dictionary = {}
	for pid_v in own:
		own_set[int(pid_v)] = true
	var groups: Dictionary = {}
	for pid_v2 in own:
		var pid := int(pid_v2)
		var counts: Dictionary = {}
		for nid in _adj(pid):
			if own_set.has(nid):
				continue
			var prov: Province = MapManager.get_province(nid)
			if prov == null or bool(prov.is_sea):
				continue
			var ot := _prov_tag(prov)
			if ot.is_empty() or ot == tag:
				continue
			counts[ot] = int(counts.get(ot, 0)) + 1
		var ots: Array = counts.keys()
		ots.sort()
		for ot_v in ots:
			var ot2 := str(ot_v)
			if not groups.has(ot2):
				groups[ot2] = []
			(groups[ot2] as Array).append({"pid": pid, "contacts": int(counts[ot2])})
	return groups


static func _pick_hex(hexes: Array, used: Dictionary) -> int:
	var best_pid := -1
	var best_used := 0
	var best_c := 0
	var have := false
	for row_v in hexes:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var pid := int(row.get("pid", 0))
		if pid <= 0:
			continue
		var c := int(row.get("contacts", 0))
		var u := int(used.get(pid, 0))
		if not have or u < best_used or (u == best_used and c < best_c) or (u == best_used and c == best_c and pid < best_pid):
			best_pid = pid
			best_used = u
			best_c = c
			have = true
	return best_pid


static func _neigh_before(us: String, a: String, b: String, strength: Dictionary) -> bool:
	var ga := _goal(us, a)
	var gb := _goal(us, b)
	if not is_equal_approx(ga, gb):
		return ga > gb
	var sa := int(strength.get(a, 0))
	var sb := int(strength.get(b, 0))
	if sa != sb:
		return sa > sb
	return a < b


static func _job_before(a: Variant, b: Variant) -> bool:
	var da: Dictionary = a
	var db: Dictionary = b
	var ga := float(da.get("goal", 0.0))
	var gb := float(db.get("goal", 0.0))
	if not is_equal_approx(ga, gb):
		return ga > gb
	var sa := int(da.get("stren", 0))
	var sb := int(db.get("stren", 0))
	if sa != sb:
		return sa > sb
	var ea := str(da.get("enemy", ""))
	var eb := str(db.get("enemy", ""))
	if ea != eb:
		return ea < eb
	var pa := int(da.get("pid", 0))
	var pb := int(db.get("pid", 0))
	if pa != pb:
		return pa < pb
	return str(da.get("efid", "")) < str(db.get("efid", ""))


static func _goal(us: String, them: String) -> float:
	var goals := AiCredibleDomain.goals_for(us)
	var raw: Variant = goals.get("targets", [])
	if not (raw is Array):
		return 0.0
	for item in raw:
		if not (item is Dictionary):
			continue
		if str((item as Dictionary).get("tag", "")).strip_edges().to_upper() == them:
			return float((item as Dictionary).get("weight", 0.0))
	return 0.0


static func _capital(tag: String, own: Array) -> int:
	var own_set: Dictionary = {}
	for pid_v in own:
		own_set[int(pid_v)] = true
	var cap := AiDefenceDomain.capital_pid(tag)
	if cap > 0 and own_set.has(cap):
		return cap
	var caps: Variant = policy().get("capitals", {})
	if caps is Dictionary and (caps as Dictionary).has(tag):
		var c2 := int((caps as Dictionary)[tag])
		if c2 > 0 and own_set.has(c2):
			return c2
	if not own.is_empty():
		return int(own[0])
	return -1


static func _strength_of(own: Array) -> int:
	var total := 0
	for pid_v in own:
		var prov: Province = MapManager.get_province(int(pid_v))
		if prov == null:
			continue
		total += maxi(int(prov.factories), 0)
	return total


static func _hops_within(tag: String, origin: int, max_hops: int, own: Array) -> Dictionary:
	var own_set: Dictionary = {}
	for pid_v in own:
		own_set[int(pid_v)] = true
	var dist: Dictionary = {origin: 0}
	var q: Array = [origin]
	var qi := 0
	while qi < q.size():
		var n: int = int(q[qi])
		qi += 1
		var nd: int = int(dist[n])
		if nd >= max_hops:
			continue
		for nid in _adj(n):
			if dist.has(nid) or not own_set.has(nid):
				continue
			dist[nid] = nd + 1
			q.append(nid)
	return dist


static func _touches(pid: int, enemy: String) -> bool:
	for nid in _adj(pid):
		var prov: Province = MapManager.get_province(nid)
		if prov == null or bool(prov.is_sea):
			continue
		if _prov_tag(prov) == enemy:
			return true
	return false


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


static func _name_hit(nm: String, tokens: Array) -> bool:
	var low := nm.to_lower()
	for tok_v in tokens:
		var tok := str(tok_v).strip_edges().to_lower()
		if not tok.is_empty() and tok in low:
			return true
	return false


static func _prov_tag(prov: Province) -> String:
	if prov == null:
		return ""
	var ctrl := str(prov.controller_tag).strip_edges().to_upper()
	if not ctrl.is_empty():
		return ctrl
	return str(prov.owner_tag).strip_edges().to_upper()
