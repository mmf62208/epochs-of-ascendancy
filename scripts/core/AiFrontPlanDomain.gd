# scripts/core/AiFrontPlanDomain.gd
## One main axis per war, held for axis_stable_days unless that segment is gone.
## Air wings are assigned to the axis region. Land-battle starts rise to a
## small count cap while at war (LandBattleAi still clamps the hard max).
class_name AiFrontPlanDomain
extends RefCounted


static func war_start_cap() -> int:
	if not AiCredibleDomain.enabled():
		return 1
	return maxi(1, AiCredibleDomain.tune_int("at_war_starts_per_day", 2))


static func tick(day: int) -> Dictionary:
	var out := {"axes": 0, "air": 0}
	if not AiCredibleDomain.enabled():
		out["skipped"] = true
		return out
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return out
	var player := AiCredibleDomain.player_tag()
	var stable := AiCredibleDomain.tune_int("axis_stable_days", 10)
	for raw in AiCredibleDomain.majors():
		var tag := str(raw)
		if tag.is_empty() or tag == player:
			continue
		if WarStateDomain.enemies_of(tag).is_empty():
			continue
		out["gates"] = int(out.get("gates", 0)) + _step_off_core_gate(tag)
		var prev := _stored_axis(tag)
		var since := int(prev.get("since_day", -99999))
		var refresh := prev.is_empty() or day - since >= stable
		if refresh:
			var targets := _scan_targets(tag)
			if not targets.is_empty():
				choose_axis(tag, day, targets)
				out["axes"] = int(out["axes"]) + 1
		var axis := _stored_axis(tag)
		if axis.is_empty():
			continue
		out["air"] = int(out["air"]) + _assign_air(tag, day, axis)
	return out


## Offer one step from a core gate into the lowest adjacent enemy hex.
## Border fill keeps the last unit on that gate, so this is a no-op while
## the gate is still the thing between the enemy and the core.
static func _step_off_core_gate(tag: String) -> int:
	if typeof(BattleManager) == TYPE_NIL or not BattleManager.has_method("start_land_battle"):
		return 0
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formations_for_country"):
		return 0
	var gates: Dictionary = {}
	for g in AiStartGarrisonDomain.core_gates(tag):
		gates[int(g)] = true
	if gates.is_empty():
		return 0
	var enemies: Dictionary = {}
	for e in WarStateDomain.enemies_of(tag):
		var et := str(e).strip_edges().to_upper()
		if not et.is_empty():
			enemies[et] = true
	if enemies.is_empty():
		return 0
	var best_fid := ""
	var best_pid := 0
	for form in LeaderManager.get_formations_for_country(tag):
		if form == null:
			continue
		var ft := str(form.formation_type) if "formation_type" in form else ""
		if ft != "division" and ft != "garrison":
			continue
		var fid := str(form.formation_id) if "formation_id" in form else ""
		var pid := int(form.stationed_province_id) if "stationed_province_id" in form else 0
		if fid.is_empty() or not gates.has(pid):
			continue
		if "is_in_combat" in form and bool(form.is_in_combat):
			continue
		if typeof(FormationMovement) != TYPE_NIL and FormationMovement.has_march(fid):
			continue
		if not AiBorderFillDomain.may_leave(tag, fid, pid):
			continue
		if best_fid.is_empty() or fid < best_fid:
			best_fid = fid
			best_pid = pid
	if best_fid.is_empty() or best_pid <= 0:
		return 0
	var dest := _lowest_enemy_hex(best_pid, enemies)
	if dest <= 0:
		return 0
	var opened: Dictionary = BattleManager.start_land_battle(tag, dest, best_pid, best_fid)
	return 1 if bool(opened.get("success", false)) else 0


static func _lowest_enemy_hex(pid: int, enemies: Dictionary) -> int:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_adjacent_provinces"):
		return 0
	var nids: Array = []
	var seen: Dictionary = {}
	for nid_v in MapManager.get_adjacent_provinces(pid, true):
		var nid := int(nid_v)
		if nid <= 0 or seen.has(nid):
			continue
		seen[nid] = true
		nids.append(nid)
	nids.sort()
	for nid2 in nids:
		var prov: Province = MapManager.get_province(int(nid2)) if MapManager.has_method("get_province") else null
		if prov == null or bool(prov.is_sea):
			continue
		var ot := str(prov.controller_tag).strip_edges().to_upper()
		if ot.is_empty():
			ot = str(prov.owner_tag).strip_edges().to_upper()
		if enemies.has(ot):
			return int(nid2)
	return 0


static func choose_axis(tag: String, day: int, targets: Array) -> Dictionary:
	var scored := _score_segments(tag, targets)
	if scored.is_empty():
		return {}
	var best: Dictionary = scored[0]
	var st := AiCredibleDomain.state()
	var axes: Dictionary = st.get("axes", {}) as Dictionary
	var prev: Dictionary = {}
	if axes.get(tag) is Dictionary:
		prev = axes[tag]
	var prev_seg := str(prev.get("segment", ""))
	var since := int(prev.get("since_day", day))
	var stable := AiCredibleDomain.tune_int("axis_stable_days", 10)
	var prev_row: Dictionary = {}
	for raw in scored:
		var row: Dictionary = raw
		if str(row.get("segment", "")) == prev_seg:
			prev_row = row
			break
	var chosen: Dictionary = best
	if not prev_seg.is_empty() and not prev_row.is_empty() and day - since < stable:
		chosen = prev_row.duplicate(true)
		chosen["since_day"] = since
	else:
		chosen = best.duplicate(true)
		chosen["since_day"] = day
		if str(chosen.get("segment", "")) != prev_seg:
			var line := "AXIS day=%d tag=%s seg=%s score=%.2f" % [day, tag, str(chosen.get("segment", "")), float(chosen.get("score", 0.0))]
			print("AiCredible: axis %s seg=%s day=%d score=%.2f" % [tag, str(chosen.get("segment", "")), day, float(chosen.get("score", 0.0))])
			AiCredibleDomain.trace_line(line)
	axes[tag] = chosen
	st["axes"] = axes
	return chosen


static func filter_opportunities(opps: Array, day: int) -> Array:
	if not AiCredibleDomain.enabled() or opps.is_empty():
		return opps
	var by_tag: Dictionary = {}
	for raw in opps:
		if not (raw is Dictionary):
			continue
		var tag := str((raw as Dictionary).get("tag", "")).strip_edges().to_upper()
		if tag.is_empty():
			continue
		if not by_tag.has(tag):
			by_tag[tag] = []
		(by_tag[tag] as Array).append(raw)
	var kept: Array = []
	var tags: Array = by_tag.keys()
	tags.sort()
	for tag_v in tags:
		var tag := str(tag_v)
		var rows: Array = by_tag[tag]
		var axis := _stored_axis(tag)
		if axis.is_empty():
			axis = choose_axis(tag, day, _targets_from_opps(rows))
		var seg := str(axis.get("segment", ""))
		var matched: Array = []
		for raw2 in rows:
			if segment_of(raw2) == seg:
				matched.append(raw2)
		if matched.is_empty():
			kept.append_array(rows)
		else:
			kept.append_array(matched)
	return AiBorderFillDomain.retain_attacks(kept)


static func segment_of(opp: Dictionary) -> String:
	var defender := str(opp.get("defender_tag", "")).strip_edges().to_upper()
	var region := int(opp.get("region_id", 0))
	if region <= 0:
		region = _region_of_pid(int(opp.get("to_id", opp.get("province_id", 0))))
	return "%s:%d" % [defender, region]


static func note_start(tag: String, segment: String, on_axis: bool) -> void:
	var st := AiCredibleDomain.state()
	var counts: Dictionary = st.get("starts", {}) as Dictionary
	if not (counts.get(tag) is Dictionary):
		counts[tag] = {"total": 0, "on_axis": 0, "segment": segment}
	var row: Dictionary = counts[tag]
	row["total"] = int(row.get("total", 0)) + 1
	if on_axis:
		row["on_axis"] = int(row.get("on_axis", 0)) + 1
	row["segment"] = segment
	counts[tag] = row
	st["starts"] = counts


static func axis_segment(tag: String) -> String:
	return str(_stored_axis(tag).get("segment", ""))


static func concentration(tag: String) -> float:
	var counts: Variant = AiCredibleDomain.state().get("starts", {})
	if not (counts is Dictionary):
		return 0.0
	var row_v: Variant = (counts as Dictionary).get(tag, {})
	if not (row_v is Dictionary):
		return 0.0
	var row: Dictionary = row_v
	var total := int(row.get("total", 0))
	if total <= 0:
		return 0.0
	return float(row.get("on_axis", 0)) / float(total)


static func _score_segments(tag: String, targets: Array) -> Array:
	var groups: Dictionary = {}
	for raw in targets:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var seg := segment_of(row)
		if not groups.has(seg):
			groups[seg] = {
				"segment": seg,
				"count": 0,
				"region_id": int(row.get("region_id", 0)),
				"defender": str(row.get("defender_tag", "")).strip_edges().to_upper(),
				"score": 0.0,
			}
		var g: Dictionary = groups[seg]
		g["count"] = int(g.get("count", 0)) + 1
		if int(g.get("region_id", 0)) <= 0:
			g["region_id"] = int(row.get("region_id", 0))
		groups[seg] = g
	var goal_w: Dictionary = {}
	var goals := AiCredibleDomain.goals_for(tag)
	var targets_g: Variant = goals.get("targets", [])
	if targets_g is Array:
		for raw_g in targets_g:
			if raw_g is Dictionary:
				goal_w[str((raw_g as Dictionary).get("tag", "")).strip_edges().to_upper()] = float((raw_g as Dictionary).get("weight", 0.0))
	var rows: Array = []
	var keys: Array = groups.keys()
	keys.sort()
	for k in keys:
		var g2: Dictionary = groups[k]
		var score := float(g2.get("count", 0)) * 10.0 + float(goal_w.get(str(g2.get("defender", "")), 0.0)) * 5.0
		g2["score"] = score
		rows.append(g2)
	rows.sort_custom(func(a, b):
		var ds := float((a as Dictionary).get("score", 0.0)) - float((b as Dictionary).get("score", 0.0))
		if absf(ds) > 0.0001:
			return ds > 0.0
		return str((a as Dictionary).get("segment", "")) < str((b as Dictionary).get("segment", ""))
	)
	return rows


static func _scan_targets(tag: String) -> Array:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("collect_live_border_assault_targets"):
		return []
	var cap := AiCredibleDomain.tune_int("axis_scan_cap", 32)
	var raw: Array = MapManager.collect_live_border_assault_targets(tag, cap)
	var out: Array = []
	for row_v in raw:
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		var to_id := int(row.get("province_id", row.get("to_id", -1)))
		out.append({
			"to_id": to_id,
			"defender_tag": str(row.get("defender_tag", "")),
			"region_id": _region_of_pid(to_id),
			"tag": tag,
		})
	return out


static func _targets_from_opps(rows: Array) -> Array:
	var out: Array = []
	for raw in rows:
		if raw is Dictionary:
			out.append(raw)
	return out


static func _stored_axis(tag: String) -> Dictionary:
	var axes: Variant = AiCredibleDomain.state().get("axes", {})
	if not (axes is Dictionary):
		return {}
	var row: Variant = (axes as Dictionary).get(tag, {})
	return (row as Dictionary).duplicate(true) if row is Dictionary else {}


static func _region_of_pid(pid: int) -> int:
	if pid <= 0 or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return 0
	var p: Province = MapManager.get_province(pid)
	if p == null or not ("strategic_region_id" in p):
		return 0
	return int(p.strategic_region_id)


static func _assign_air(tag: String, day: int, axis: Dictionary) -> int:
	var region := int(axis.get("region_id", 0))
	if region <= 0:
		return 0
	var st := AiCredibleDomain.state()
	var air: Dictionary = st.get("air", {}) as Dictionary
	if int(air.get(tag, -1)) == region:
		return 0
	var since := int(axis.get("since_day", day))
	var window := AiCredibleDomain.tune_int("air_assign_within_days", 7)
	if day - since > window:
		return 0
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formations_for_country"):
		return 0
	if not LeaderManager.has_method("assign_air_wing_to_region"):
		return 0
	var ids: Array = []
	for f in LeaderManager.get_formations_for_country(tag):
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != "air_wing" and ft != "air_squadron" and ft != "air_group":
			continue
		var fid := str(f.formation_id) if "formation_id" in f else ""
		if not fid.is_empty():
			ids.append(fid)
	if ids.is_empty():
		return 0
	ids.sort()
	var res: Dictionary = LeaderManager.assign_air_wing_to_region(str(ids[0]), region, "CAS")
	if not bool(res.get("ok", false)):
		return 0
	air[tag] = region
	st["air"] = air
	var line := "AIR day=%d tag=%s region=%d wing=%s" % [day, tag, region, str(ids[0])]
	print("AiCredible: air %s region=%d day=%d wing=%s" % [tag, region, day, str(ids[0])])
	AiCredibleDomain.trace_line(line)
	return 1
