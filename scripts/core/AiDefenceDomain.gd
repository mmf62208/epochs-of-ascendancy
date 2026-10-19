# scripts/core/AiDefenceDomain.gd
## Keep a unit on a threatened capital. Marches use FormationMovement.enqueue_own_land_march.
## A day counts as capital-empty only when the nation has an army, an enemy
## borders the capital, and nothing is stationed there or already marching in.
class_name AiDefenceDomain
extends RefCounted

const CITY_PATH := "res://data/provinces_world_accurate/province_city_layer.json"

static var _caps: Dictionary = {}
static var _caps_loaded: bool = false


static func tick(day: int) -> Dictionary:
	var out := {"marches": 0, "capital_empty": 0, "threatened": 0}
	if not AiCredibleDomain.enabled():
		out["skipped"] = true
		return out
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return out
	var budget := AiCredibleDomain.tune_int("defence_marches_per_day", 2)
	var used := 0
	var tags: Array = AiCredibleDomain.majors()
	var player := AiCredibleDomain.player_tag()
	for raw in tags:
		var tag := str(raw)
		if tag.is_empty() or tag == player:
			continue
		if WarStateDomain.enemies_of(tag).is_empty():
			continue
		if not enemy_borders_capital(tag):
			continue
		out["threatened"] = int(out["threatened"]) + 1
		var cap := capital_pid(tag)
		if _unit_on(tag, cap):
			continue
		var inbound := _march_inbound(tag, cap)
		if inbound:
			continue
		if used < budget and _march_one_to(tag, cap):
			used += 1
			out["marches"] = int(out["marches"]) + 1
			AiCredibleDomain.trace_line("DEFEND day=%d tag=%s dest=%d" % [day, tag, cap])
			continue
		if _any_division(tag):
			out["capital_empty"] = int(out["capital_empty"]) + 1
			AiCredibleDomain.counter_add("capital_empty_days", 1)
			AiCredibleDomain.trace_line("CAPITAL_EMPTY day=%d tag=%s" % [day, tag])
	return out


static func capital_pid(tag: String) -> int:
	_load_caps()
	return int(_caps.get(tag.strip_edges().to_upper(), -1))


static func enemy_borders_capital(tag: String) -> bool:
	var cap := capital_pid(tag)
	if cap <= 0 or typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_adjacent_provinces"):
		return false
	if typeof(WarStateDomain) == TYPE_NIL or not WarStateDomain.loop_enabled():
		return false
	var enemies: Dictionary = {}
	for e in WarStateDomain.enemies_of(tag):
		enemies[str(e)] = true
	if enemies.is_empty():
		return false
	for nid_v in MapManager.get_adjacent_provinces(cap, true):
		var n: Province = MapManager.get_province(int(nid_v))
		if n == null or bool(n.is_sea):
			continue
		if enemies.has(str(n.owner_tag).strip_edges().to_upper()):
			return true
	return false


static func _march_one_to(tag: String, dest: int) -> bool:
	if dest <= 0 or typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formations_for_country"):
		return false
	if typeof(FormationMovement) == TYPE_NIL:
		return false
	var probes := AiCredibleDomain.tune_int("defence_path_probes", 6)
	var best_fid := ""
	var best_hops := 999999
	var seen := 0
	var forms: Array = LeaderManager.get_formations_for_country(tag)
	var ids: Array = []
	for f in forms:
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != "division":
			continue
		var fid := str(f.formation_id) if "formation_id" in f else ""
		if fid.is_empty():
			continue
		ids.append(fid)
	ids.sort()
	for fid_v in ids:
		if seen >= probes:
			break
		var fid := str(fid_v)
		var f: Formation = LeaderManager.get_formation(fid) if LeaderManager.has_method("get_formation") else null
		if f == null:
			continue
		if "is_in_combat" in f and bool(f.is_in_combat):
			continue
		if FormationMovement.has_march(fid):
			continue
		var station := int(f.stationed_province_id) if "stationed_province_id" in f else -1
		if station <= 0 or station == dest:
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


static func _unit_on(tag: String, pid: int) -> bool:
	if pid <= 0 or typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formations_for_country"):
		return false
	for f in LeaderManager.get_formations_for_country(tag):
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft != "division":
			continue
		if int(f.stationed_province_id) == pid:
			return true
	return false


static func _any_division(tag: String) -> bool:
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formations_for_country"):
		return false
	for f in LeaderManager.get_formations_for_country(tag):
		if f == null:
			continue
		var ft := str(f.formation_type) if "formation_type" in f else ""
		if ft == "division":
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


static func _load_caps() -> void:
	if _caps_loaded:
		return
	_caps_loaded = true
	_caps = {}
	if not FileAccess.file_exists(CITY_PATH):
		return
	var f := FileAccess.open(CITY_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var rows: Variant = parsed.get("provinces", parsed) if parsed is Dictionary else {}
	if not (rows is Dictionary):
		return
	for pid_s in (rows as Dictionary).keys():
		var row_v: Variant = (rows as Dictionary)[pid_s]
		if not (row_v is Dictionary):
			continue
		var row: Dictionary = row_v
		if not bool(row.get("capital", false)) and not bool(row.get("is_capital", false)):
			continue
		var ct := str(row.get("tag", "")).strip_edges().to_upper()
		if ct.is_empty():
			continue
		var pid := int(pid_s)
		if not _caps.has(ct) or pid < int(_caps[ct]):
			_caps[ct] = pid
