# scripts/map/LeaderStationOverlayLayer.gd
## Phase 3: leader OOB station + formation visuals (ties to major #26).

class_name LeaderStationOverlayLayer
extends Node2D

@export var enabled: bool = true
@export var max_markers: int = 32

var _centroids: Dictionary = {}
var _last_n: int = 0


func setup(centroids: Dictionary) -> void:
	_centroids = centroids
	queue_redraw()


func _ready() -> void:
	z_index = 7


func refresh() -> void:
	queue_redraw()


func get_draw_stats() -> Dictionary:
	return {"marker_n": _last_n, "enabled": enabled}


func _draw() -> void:
	_last_n = 0
	if not enabled:
		return
	var stations: Array = _collect_stations()
	for entry in stations:
		if _last_n >= max_markers:
			break
		var pid := int(entry.get("pid", -1))
		if pid < 0 or not _centroids.has(pid):
			continue
		var c: Vector2 = _centroids[pid]
		var rank := str(entry.get("rank", "gen"))
		var name_short := str(entry.get("name", "HQ")).substr(0, 8)
		_draw_leader_marker(c, rank, name_short, float(entry.get("formations", 1)))
		_last_n += 1


func _collect_stations() -> Array:
	var out: Array = []
	if typeof(LeaderManager) != TYPE_NIL:
		# Prefer public APIs if present
		if LeaderManager.has_method("get_all_leaders"):
			var leaders = LeaderManager.get_all_leaders()
			if leaders is Array:
				for L in leaders:
					if L is Dictionary:
						var pid := int(L.get("province_id", L.get("station_province", -1)))
						if pid > 0:
							out.append({
								"pid": pid,
								"name": str(L.get("name", L.get("id", "Leader"))),
								"rank": str(L.get("rank", L.get("role", "gen"))),
								"formations": int(L.get("formation_n", 1)),
							})
					elif L is Object:
						var pid2 := -1
						if "province_id" in L:
							pid2 = int(L.province_id)
						elif "station_province_id" in L:
							pid2 = int(L.station_province_id)
						if pid2 > 0:
							var lname := "Leader"
							if "name" in L:
								lname = str(L.name)
							out.append({
								"pid": pid2,
								"name": lname,
								"rank": "gen",
								"formations": 1,
							})
		elif LeaderManager.has_method("get_leader_pool"):
			var pool = LeaderManager.get_leader_pool()
			if pool is Array:
				for L in pool:
					if L is Dictionary and int(L.get("province_id", 0)) > 0:
						out.append({
							"pid": int(L.get("province_id")),
							"name": str(L.get("name", "Leader")),
							"rank": str(L.get("rank", "gen")),
							"formations": 1,
						})
	if out.is_empty() and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_contested_provinces"):
		# Soft fallback: HQ pins on contested for visual continuity
		var cont: Dictionary = MapManager.get_contested_provinces()
		var i := 0
		for pid_v in cont.keys():
			if i >= 6:
				break
			out.append({"pid": int(pid_v), "name": "Front HQ", "rank": "gen", "formations": 1})
			i += 1
	return out


func _draw_leader_marker(pos: Vector2, rank: String, label: String, formations: float) -> void:
	var col := Color(0.95, 0.85, 0.35, 0.9)
	if rank.to_lower().contains("adm") or rank.to_lower().contains("nav"):
		col = Color(0.45, 0.7, 0.95, 0.9)
	elif rank.to_lower().contains("air"):
		col = Color(0.7, 0.85, 1.0, 0.9)
	# Staff flag
	draw_rect(Rect2(pos + Vector2(-2, -14), Vector2(4, 14)), col)
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(2, -14), pos + Vector2(14, -10), pos + Vector2(2, -6),
	]), col)
	# Formation pips
	var n := clampi(int(formations), 1, 4)
	for i in range(n):
		draw_circle(pos + Vector2(-8 + i * 5, 8), 2.0, Color(1, 1, 1, 0.7))
	# Label stub as small bar (font draw optional; keeps layer cheap)
	draw_rect(Rect2(pos + Vector2(6, -2), Vector2(mini(36.0, 4.0 * float(label.length())), 3)), Color(0.95, 0.95, 0.9, 0.55))
