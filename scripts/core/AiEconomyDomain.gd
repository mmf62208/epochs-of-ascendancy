# scripts/core/AiEconomyDomain.gd
## Needs-shaped production touch and a research queue that does not sit idle.
## Tag choice inside apply_interactive_multi_ai_day_live is unchanged.
## This domain only backfills a major the rotator has missed for 7 days,
## and it stamps a military or civilian bias the soak can read.
class_name AiEconomyDomain
extends RefCounted

static var _tech_ids: Array = []


static func tick(day: int) -> Dictionary:
	var out := {"research_started": 0, "production_backfill": 0, "military": 0, "civilian": 0}
	if not AiCredibleDomain.enabled():
		out["skipped"] = true
		return out
	var st := AiCredibleDomain.state()
	var last_p: Dictionary = st.get("last_production_day", {}) as Dictionary
	var last_r: Dictionary = st.get("last_research_day", {}) as Dictionary
	var seen: Dictionary = st.get("seen_day", {}) as Dictionary
	var bias: Dictionary = st.get("bias", {}) as Dictionary
	_note_profile(day, last_p)
	var player := AiCredibleDomain.player_tag()
	var tags: Array = AiCredibleDomain.majors()
	var idle_limit := AiCredibleDomain.tune_int("production_idle_days", 7)
	var research_budget := AiCredibleDomain.tune_int("research_starts_per_day", 2)
	var research_rows: Array = []
	for raw in tags:
		var tag := str(raw)
		if tag.is_empty() or tag == player:
			continue
		if not seen.has(tag):
			seen[tag] = day
		research_rows.append({"tag": tag, "prev": int(last_r.get(tag, -1))})
	research_rows.sort_custom(func(a, b):
		var da := int((a as Dictionary).get("prev", -1))
		var db := int((b as Dictionary).get("prev", -1))
		if da == db:
			return str((a as Dictionary).get("tag", "")) < str((b as Dictionary).get("tag", ""))
		return da < db
	)
	var started := 0
	for raw_r in research_rows:
		if started >= research_budget:
			break
		var tag_r := str((raw_r as Dictionary).get("tag", ""))
		var prev_r := int((raw_r as Dictionary).get("prev", -1))
		if prev_r >= 0 and day - prev_r <= idle_limit:
			if _research_live(tag_r):
				continue
		if _ensure_research(tag_r):
			last_r[tag_r] = day
			started += 1
	out["research_started"] = started
	for raw_r2 in research_rows:
		var tag_b := str((raw_r2 as Dictionary).get("tag", ""))
		var prev_b := int(last_r.get(tag_b, -1))
		if prev_b >= 0 and day - prev_b > idle_limit and not _research_live(tag_b):
			AiCredibleDomain.counter_add("research_idle_breaches", 1)
			AiCredibleDomain.trace_line("RESEARCH_IDLE day=%d tag=%s gap=%d" % [day, tag_b, day - prev_b])
	var backfill := 0
	for raw_p in tags:
		var tag_p := str(raw_p)
		if tag_p.is_empty() or tag_p == player:
			continue
		var at_war := typeof(WarStateDomain) != TYPE_NIL and WarStateDomain.loop_enabled() and not WarStateDomain.enemies_of(tag_p).is_empty()
		if at_war:
			bias[tag_p] = "military"
			_add_stock(tag_p, "infantry_equipment", 1)
			out["military"] = int(out["military"]) + 1
		else:
			bias[tag_p] = "civilian"
		var produced := int(last_p.get(tag_p, -1))
		var first := int(seen.get(tag_p, day))
		var gap := day - produced if produced >= 0 else day - first
		var backfill_cap := AiCredibleDomain.tune_int("production_backfill_per_day", 8)
		if gap > idle_limit:
			if backfill < backfill_cap and typeof(GameData) != TYPE_NIL and GameData.has_method("apply_production_for_tag"):
				var live: Dictionary = GameData.apply_production_for_tag(tag_p)
				backfill += 1
				if bool(live.get("ok", false)):
					last_p[tag_p] = day
					out["production_backfill"] = int(out["production_backfill"]) + 1
					gap = 0
			if gap > idle_limit:
				AiCredibleDomain.counter_add("production_idle_breaches", 1)
				AiCredibleDomain.trace_line("PROD_IDLE day=%d tag=%s gap=%d" % [day, tag_p, gap])
	var peace_tags: Array = []
	for raw_c in tags:
		var tag_c := str(raw_c)
		if tag_c == player:
			continue
		if str(bias.get(tag_c, "")) == "civilian":
			peace_tags.append(tag_c)
	peace_tags.sort()
	if not peace_tags.is_empty():
		var pick := str(peace_tags[day % peace_tags.size()])
		_add_stock(pick, "support_equipment", 1)
		out["civilian"] = 1
		out["civilian_tag"] = pick
	st["last_production_day"] = last_p
	st["last_research_day"] = last_r
	st["seen_day"] = seen
	st["bias"] = bias
	return out


static func _note_profile(day: int, last_p: Dictionary) -> void:
	if typeof(GameData) == TYPE_NIL or not GameData.has_method("get_last_interactive_multi_ai_profile"):
		return
	var prof: Variant = GameData.get_last_interactive_multi_ai_profile()
	if not (prof is Dictionary):
		return
	var countries: Variant = (prof as Dictionary).get("countries", [])
	if not (countries is Array):
		return
	for raw in countries:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		if str(row.get("step", "")) != "production":
			continue
		if not bool(row.get("ok", false)):
			continue
		var tag := str(row.get("tag", "")).strip_edges().to_upper()
		if not tag.is_empty():
			last_p[tag] = day


static func _ensure_research(tag: String) -> bool:
	if _research_live(tag):
		return true
	if typeof(TechnologyManager) == TYPE_NIL or not TechnologyManager.has_method("start_research"):
		return false
	var tech := _first_available(tag)
	if tech.is_empty():
		return false
	return bool(TechnologyManager.start_research(tag, tech))


static func _research_live(tag: String) -> bool:
	if typeof(TechnologyManager) == TYPE_NIL or not TechnologyManager.has_method("get_active_research_count"):
		return false
	return TechnologyManager.get_active_research_count(tag) > 0


static func _first_available(tag: String) -> String:
	if typeof(TechnologyManager) == TYPE_NIL or not ("technology_nodes" in TechnologyManager):
		return ""
	if _tech_ids.is_empty():
		var nodes: Variant = TechnologyManager.technology_nodes
		if nodes is Dictionary:
			_tech_ids = (nodes as Dictionary).keys()
			_tech_ids.sort()
	var cap := AiCredibleDomain.tune_int("research_scan_cap", 32)
	var found := _scan_available(tag, cap)
	if not found.is_empty():
		return found
	# Cap keeps the common day cheap. A miss walks the rest once so a major
	# whose early ids are locked or finished does not sit idle.
	return _scan_available(tag, _tech_ids.size())


static func _scan_available(tag: String, limit: int) -> String:
	var n := 0
	for id_v in _tech_ids:
		if n >= limit:
			break
		n += 1
		var tid := str(id_v)
		if TechnologyManager.has_method("get_node_status") and TechnologyManager.get_node_status(tag, tid) == "available":
			return tid
	return ""


static func _add_stock(tag: String, equipment_id: String, amount: int) -> void:
	if typeof(ProductionManager) == TYPE_NIL or not ProductionManager.has_method("add_to_country_equipment_stockpile"):
		return
	ProductionManager.add_to_country_equipment_stockpile(tag, equipment_id, amount)
