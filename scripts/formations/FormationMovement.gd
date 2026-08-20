class_name FormationMovement
extends RefCounted

## Bridge for division map movement orders. Engineer repair deployment uses the same path
## as future general formation movement (move_to_province order type).
## Own-land march queue mirrors tools/map_generation/lib/unit_own_land_march_product.py

const ORDER_MOVE_TO_PROVINCE := "move_to_province"
const ORDER_OWN_LAND_MARCH := "own_land_march"

const BASE_HOP_DAYS := 1.0
const HOP_DAYS_MIN := 0.25
const HOP_DAYS_MAX := 3.0
const INFANTRY_SPEED := 1.0
const ARMOR_SPEED := 1.5
const MOUNTAIN_INFANTRY_DISCOUNT := 0.70
const ARMOR_MOUNTAIN_PENALTY := 1.60

## fid -> {path, hop_index, progress, hop_cost, dest_id, tag, from_id}
static var _orders: Dictionary = {}


## Move any land division to a province (registers presence + updates stationed_province_id).
## Hop-commit / arrive only — player clicks enqueue_own_land_march.
static func move_formation_to_province(
	formation_id: String,
	province_id: int,
	country_tag: String = "",
) -> Dictionary:
	if typeof(SupplyManager) == TYPE_NIL:
		return {"ok": false, "error": "SupplyManager unavailable"}
	return SupplyManager.move_formation_to_province(formation_id, province_id, country_tag)


## Engineer-capable divisions only — same movement pipeline, validates engineer brigades.
static func move_engineer_formation_to_province(
	formation_id: String,
	province_id: int,
	country_tag: String = "",
) -> Dictionary:
	if typeof(SupplyManager) == TYPE_NIL:
		return {"ok": false, "error": "SupplyManager unavailable"}
	return SupplyManager.deploy_engineer_formation_to_province(formation_id, province_id, country_tag)


static func _clamp(v: float, lo: float, hi: float) -> float:
	return maxf(lo, minf(hi, v))


static func hop_days(terrain: String, infra: float, template_speed: float, template_kind: String = "infantry") -> float:
	# mirrors unit_own_land_march_product.hop_days
	var terr := str(terrain or "plains").strip_edges().to_lower()
	if terr.is_empty():
		terr = "plains"
	var kind := str(template_kind or "infantry").strip_edges().to_lower()
	var days := BASE_HOP_DAYS * _terrain_cost(terr) * _infra_cost(infra) * _speed_cost(template_speed)
	if terr == "mountain" and "mountain" in kind:
		days *= MOUNTAIN_INFANTRY_DISCOUNT
	if terr == "mountain" and _is_armor_motor(kind):
		days *= ARMOR_MOUNTAIN_PENALTY
	return _clamp(days, HOP_DAYS_MIN, HOP_DAYS_MAX)


static func calendar_days(eta: float) -> int:
	if eta <= 0.0:
		return 0
	return maxi(1, int(ceili(eta - 1e-9)))


static func march_legal(dest_owner: String, player_tag: String, dest_is_land: bool) -> bool:
	if not dest_is_land:
		return false
	var owner := dest_owner.strip_edges().to_upper()
	var tag := player_tag.strip_edges().to_upper()
	return not owner.is_empty() and owner == tag


static func _terrain_cost(terrain: String) -> float:
	match terrain:
		"plains":
			return 1.0
		"hills":
			return 1.20
		"forest":
			return 1.25
		"desert":
			return 1.30
		"urban":
			return 1.15
		"jungle":
			return 1.50
		"marsh", "marshes", "swamp":
			return 1.60
		"mountain", "mountains", "alpine":
			return 1.80
		_:
			return 1.0


static func _infra_cost(infra: float) -> float:
	var x := _clamp(float(infra), 0.0, 1.0)
	return 1.5 - 0.5 * x


static func _speed_cost(template_speed: float) -> float:
	var spd := float(template_speed)
	if spd <= 1e-9:
		return HOP_DAYS_MAX / BASE_HOP_DAYS
	return 1.0 / spd


static func _is_armor_motor(kind: String) -> bool:
	return "armor" in kind or "armour" in kind or "motor" in kind or "mech" in kind


static func _norm_terrain(raw: String) -> String:
	var t := raw.strip_edges().to_lower()
	if t in ["mountain", "mountains", "alpine", "snow_capped"]:
		return "mountain"
	if t in ["marsh", "marshes", "swamp", "wetland"]:
		return "marsh"
	if t in ["hills", "hill", "highland"]:
		return "hills"
	if t in ["forest", "woods"]:
		return "forest"
	if t in ["urban", "metro"]:
		return "urban"
	if t in ["desert", "arid"]:
		return "desert"
	if t in ["jungle"]:
		return "jungle"
	return "plains"


static func _infra_unit(province: Province) -> float:
	if province == null:
		return 0.5
	return _clamp(float(province.infrastructure) / 10.0, 0.0, 1.0)


static func _ctrl_tag(province: Province) -> String:
	if province == null:
		return ""
	var ctrl := str(province.controller_tag).strip_edges().to_upper()
	if not ctrl.is_empty():
		return ctrl
	return str(province.owner_tag).strip_edges().to_upper()


static func template_profile(formation: Object) -> Dictionary:
	var kind := str(LandCombatPower.template_kind(formation))
	var speed := float(LandCombatPower.template_speed(formation))
	return {"template_kind": kind, "template_speed": speed}


static func find_own_land_path(from_id: int, to_id: int, owner_tag: String, max_hops: int = 80) -> Array[int]:
	var empty: Array[int] = []
	if from_id <= 0 or to_id <= 0 or typeof(MapManager) == TYPE_NIL:
		return empty
	if from_id == to_id:
		return [from_id]
	var tag := owner_tag.strip_edges().to_upper()
	if tag.is_empty():
		return empty
	var q: Array = [from_id]
	var prev: Dictionary = {}
	var seen: Dictionary = {from_id: true}
	var hops: Dictionary = {from_id: 0}
	var qi := 0
	while qi < q.size():
		var n: int = int(q[qi])
		qi += 1
		var nh: int = int(hops.get(n, 0))
		if nh >= max_hops:
			continue
		var nbs: Array = MapManager.get_adjacent_provinces(n, true)
		for nb in nbs:
			var xi := int(nb)
			if seen.has(xi):
				continue
			var p: Province = MapManager.get_province(xi) if MapManager.has_method("get_province") else null
			if p == null or bool(p.is_sea):
				continue
			if _ctrl_tag(p) != tag:
				continue
			seen[xi] = true
			prev[xi] = n
			hops[xi] = nh + 1
			if xi == to_id:
				var path: Array[int] = [to_id]
				var cur := to_id
				while prev.has(cur):
					cur = int(prev[cur])
					path.push_front(cur)
				return path
			q.append(xi)
	return empty


static func _hop_cost_into(pid: int, profile: Dictionary) -> float:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_province"):
		return 1.0
	var p: Province = MapManager.get_province(pid)
	var terr := "plains"
	var infra := 0.5
	if p != null:
		terr = _norm_terrain(str(p.terrain))
		infra = _infra_unit(p)
	return hop_days(
		terr,
		infra,
		float(profile.get("template_speed", INFANTRY_SPEED)),
		str(profile.get("template_kind", "infantry")),
	)


static func remaining_eta_days(order: Dictionary) -> float:
	if order.is_empty():
		return 0.0
	var path: Array = order.get("path", []) as Array
	var hop_i := int(order.get("hop_index", 1))
	var progress := float(order.get("progress", 0.0))
	var hop_cost := float(order.get("hop_cost", 1.0))
	var left := maxf(0.0, hop_cost - progress)
	var fid := str(order.get("formation_id", ""))
	var f: Object = null
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		f = LeaderManager.get_formation(fid)
	var prof: Dictionary = template_profile(f)
	for i in range(hop_i + 1, path.size()):
		left += _hop_cost_into(int(path[i]), prof)
	return left


static func enqueue_own_land_march(
	formation_id: String,
	dest_id: int,
	country_tag: String,
) -> Dictionary:
	var fid := formation_id.strip_edges()
	var tag := country_tag.strip_edges().to_upper()
	if fid.is_empty() or tag.is_empty() or dest_id <= 0:
		return {"ok": false, "reason": "bad args"}
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return {"ok": false, "reason": "no formation"}
	var f: Formation = LeaderManager.get_formation(fid)
	if f == null:
		return {"ok": false, "reason": "unknown unit"}
	if str(f.country_tag).strip_edges().to_upper() != tag:
		return {"ok": false, "reason": "not your unit"}
	var from_id := int(f.stationed_province_id) if "stationed_province_id" in f else -1
	if from_id < 0:
		return {"ok": false, "reason": "no station"}
	if from_id == dest_id:
		return {"ok": false, "reason": "already here", "already_here": true}
	if typeof(MapManager) == TYPE_NIL:
		return {"ok": false, "reason": "no map"}
	var dest: Province = MapManager.get_province(dest_id)
	if dest == null:
		return {"ok": false, "reason": "no dest"}
	if not march_legal(_ctrl_tag(dest), tag, not bool(dest.is_sea)):
		return {"ok": false, "reason": "not your land"}
	var path: Array[int] = find_own_land_path(from_id, dest_id, tag)
	if path.size() < 2:
		return {"ok": false, "reason": "no own-land path"}
	var prof: Dictionary = template_profile(f)
	var first_cost := _hop_cost_into(int(path[1]), prof)
	var order := {
		"formation_id": fid,
		"country_tag": tag,
		"path": path,
		"hop_index": 1,
		"progress": 0.0,
		"hop_cost": first_cost,
		"dest_id": dest_id,
		"from_id": from_id,
		"order_type": ORDER_OWN_LAND_MARCH,
	}
	_orders[fid] = order
	var eta := remaining_eta_days(order)
	var hops_n := path.size() - 1
	return {
		"ok": true,
		"reason": "",
		"path": path,
		"hops": hops_n,
		"eta_days": eta,
		"calendar_days": calendar_days(eta),
		"from_id": from_id,
		"dest_id": dest_id,
		"formation_id": fid,
		"replaced": true,
	}


static func clear_march(formation_id: String) -> bool:
	var fid := formation_id.strip_edges()
	if fid.is_empty() or not _orders.has(fid):
		return false
	_orders.erase(fid)
	return true


static func has_march(formation_id: String) -> bool:
	return _orders.has(formation_id.strip_edges())


static func list_marches() -> Array:
	var out: Array = []
	for fid_v in _orders.keys():
		var row: Dictionary = get_march(str(fid_v))
		if not row.is_empty():
			out.append(row)
	return out


static func soonest_calendar_eta_to(province_id: int, country_tag: String = "") -> int:
	var dest := int(province_id)
	var tag := country_tag.strip_edges().to_upper()
	var best := 99
	if dest <= 0:
		return best
	for fid_v in _orders.keys():
		var order: Dictionary = _orders[fid_v] as Dictionary
		if int(order.get("dest_id", -1)) != dest:
			continue
		if not tag.is_empty() and str(order.get("country_tag", "")).to_upper() != tag:
			continue
		var eta := calendar_days(remaining_eta_days(order))
		if eta > 0 and eta < best:
			best = eta
	return best


static func get_march(formation_id: String) -> Dictionary:
	var fid := formation_id.strip_edges()
	if not _orders.has(fid):
		return {}
	return (_orders[fid] as Dictionary).duplicate(true)


static func get_save_data() -> Dictionary:
	var marches := {}
	for fid_v in _orders.keys():
		var fid := str(fid_v)
		var order: Dictionary = (_orders[fid] as Dictionary).duplicate(true)
		var path_out: Array = []
		for pid in order.get("path", []):
			path_out.append(int(pid))
		if path_out.size() < 2 or fid.is_empty():
			continue
		marches[fid] = {
			"formation_id": fid,
			"country_tag": str(order.get("country_tag", "")),
			"path": path_out,
			"hop_index": int(order.get("hop_index", 1)),
			"progress": float(order.get("progress", 0.0)),
			"hop_cost": float(order.get("hop_cost", 1.0)),
			"dest_id": int(order.get("dest_id", -1)),
			"from_id": int(order.get("from_id", -1)),
			"order_type": str(order.get("order_type", ORDER_OWN_LAND_MARCH)),
		}
	return {"version": 1, "marches": marches}


static func apply_save_data(data: Dictionary) -> void:
	_orders.clear()
	if data.is_empty():
		return
	var marches: Dictionary = data.get("marches", {}) as Dictionary
	for fid_v in marches.keys():
		var raw = marches[fid_v]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = raw
		var fid := str(row.get("formation_id", fid_v)).strip_edges()
		var path_out: Array = []
		for pid in row.get("path", []):
			path_out.append(int(pid))
		if fid.is_empty() or path_out.size() < 2:
			continue
		if int(row.get("dest_id", 0)) <= 0:
			continue
		_orders[fid] = {
			"formation_id": fid,
			"country_tag": str(row.get("country_tag", "")).strip_edges().to_upper(),
			"path": path_out,
			"hop_index": int(row.get("hop_index", 1)),
			"progress": float(row.get("progress", 0.0)),
			"hop_cost": float(row.get("hop_cost", 1.0)),
			"dest_id": int(row.get("dest_id", -1)),
			"from_id": int(row.get("from_id", -1)),
			"order_type": str(row.get("order_type", ORDER_OWN_LAND_MARCH)),
		}
	if not _orders.is_empty():
		print("FormationMovement: restored %d own-land march(es)" % _orders.size())


## Advance every queued march by `days` (interactive + headless day flush).
## Returns [{formation_id, from_id, to_id, arrived, dest_id}]
static func tick_all_marches(days: float = 1.0) -> Array:
	var moved: Array = []
	if days <= 0.0 or _orders.is_empty():
		return moved
	var fids: Array = _orders.keys()
	for fid_v in fids:
		var fid := str(fid_v)
		if not _orders.has(fid):
			continue
		var order: Dictionary = _orders[fid] as Dictionary
		order["progress"] = float(order.get("progress", 0.0)) + days
		var hops_done: Array = _commit_ready_hops(order)
		for h in hops_done:
			moved.append(h)
		if bool(order.get("arrived", false)):
			_orders.erase(fid)
		else:
			_orders[fid] = order
	for mv in moved:
		if mv is Dictionary:
			_notify_map_light(
				int(mv.get("from_id", -1)),
				int(mv.get("to_id", -1)),
				bool(mv.get("arrived", false)),
				int(mv.get("dest_id", -1)),
			)
	return moved


static func _commit_ready_hops(order: Dictionary) -> Array:
	var out: Array = []
	var path: Array = order.get("path", []) as Array
	var tag := str(order.get("country_tag", ""))
	var fid := str(order.get("formation_id", ""))
	var dest_id := int(order.get("dest_id", -1))
	while float(order.get("progress", 0.0)) + 1e-6 >= float(order.get("hop_cost", 1.0)):
		var hop_i := int(order.get("hop_index", 1))
		if hop_i >= path.size():
			order["arrived"] = true
			break
		var to_pid := int(path[hop_i])
		var from_pid := int(path[hop_i - 1]) if hop_i > 0 else int(order.get("from_id", -1))
		order["progress"] = float(order.get("progress", 0.0)) - float(order.get("hop_cost", 1.0))
		var res: Dictionary = move_formation_to_province(fid, to_pid, tag)
		if not bool(res.get("ok", false)) and typeof(LeaderManager) != TYPE_NIL:
			var f: Formation = LeaderManager.get_formation(fid)
			if f != null:
				f.stationed_province_id = to_pid
		var arrived := hop_i >= path.size() - 1 or to_pid == dest_id
		var hop_row := {
			"formation_id": fid,
			"from_id": from_pid,
			"to_id": to_pid,
			"dest_id": dest_id,
			"arrived": arrived,
		}
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("try_reinforce_land_battle"):
			var rf: Dictionary = BattleManager.try_reinforce_land_battle(fid, to_pid, tag)
			hop_row["reinforced"] = bool(rf.get("joined", false))
			hop_row["reinforce"] = rf
		out.append(hop_row)
		var f2: Object = null
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
			f2 = LeaderManager.get_formation(fid)
		if f2 != null:
			LandCombatPower.apply_fuel_burn(f2, "march")
		if arrived:
			order["arrived"] = true
			order["hop_index"] = path.size()
			break
		order["hop_index"] = hop_i + 1
		order["hop_cost"] = _hop_cost_into(int(path[hop_i + 1]), template_profile(f2))
	return out


static func _notify_map_light(from_pid: int, to_pid: int, arrived: bool = false, dest_id: int = -1) -> void:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return
	for mr in (tree as SceneTree).get_nodes_in_group("map_renderer"):
		if mr.has_method("refresh_after_capture_light"):
			mr.call_deferred("refresh_after_capture_light", to_pid, from_pid)
		if mr.has_method("_on_march_hop_ui"):
			mr.call_deferred("_on_march_hop_ui", to_pid, arrived, dest_id, {})
