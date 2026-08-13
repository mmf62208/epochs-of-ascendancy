# scripts/map/MapProvincePickPolicy.gd
## Pure province pick helpers (land-over-sea, ocean placeholder names).
## Callable without a full MapManager scene for headless unit tests.
class_name MapProvincePickPolicy
extends RefCounted


## Matches "Atlantic -38E -2N" and renamed "North Atlantic Waters (-38E -2N)" labels.
static func is_ocean_latlon_placeholder_name(name: String) -> bool:
	var n := name.strip_edges()
	if n.is_empty():
		return false
	if n.contains(" Waters (") and n.ends_with("N)"):
		for prefix in ["North ", "Mid ", "Tropical ", "South "]:
			if n.begins_with(prefix) and ("Atlantic" in n or "Pacific" in n or "Indian" in n or "Arctic" in n):
				return true
	for prefix in ["Atlantic ", "Pacific ", "Indian ", "Arctic ", "Southern "]:
		if not n.begins_with(prefix):
			continue
		var rest := n.substr(prefix.length()).strip_edges()
		if rest.is_empty():
			return false
		if rest[0] == "-" or (rest[0] >= "0" and rest[0] <= "9"):
			return true
	return false


static func is_sea_terrain(terrain: String, domain: String = "", name: String = "") -> bool:
	var t := terrain.strip_edges().to_lower()
	if t in ["sea", "ocean", "water", "lake"]:
		return true
	var d := domain.strip_edges().to_lower()
	if d in ["sea", "ocean", "naval", "water"]:
		return true
	if is_ocean_latlon_placeholder_name(name) and t != "coastal":
		return true
	return false


## Among candidate province records that contain the click, prefer land then nearest centroid
## (area as tie-break). Nearest centroid beats pure smallest-area so dense satellites / wrong
## large polys don't steal a city click when the city poly also contains the point.
## candidates: Array of { "id": int, "sea": bool, "area": float, "contains": bool,
##   optional "dist2": float (squared distance from click to centroid) }
static func prefer_land_among_candidates(candidates: Array, primary_hit: int = -1) -> int:
	var land: Array = []
	var sea: Array = []
	for c in candidates:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = c
		if not bool(d.get("contains", false)):
			continue
		if bool(d.get("sea", false)):
			sea.append(d)
		else:
			land.append(d)
	if not land.is_empty():
		return _best_pick_id(land)
	if primary_hit >= 0:
		return primary_hit
	if not sea.is_empty():
		return _best_pick_id(sea)
	return primary_hit


## Prefer smallest dist2 when present; else smallest area; id as last resort.
static func _best_pick_id(rows: Array) -> int:
	var best_id := -1
	var best_d := INF
	var best_a := INF
	var has_dist := false
	for r in rows:
		var d: Dictionary = r
		if d.has("dist2"):
			has_dist = true
			break
	for r in rows:
		var d: Dictionary = r
		var pid := int(d.get("id", -1))
		var a := float(d.get("area", 1.0))
		if a <= 0.0:
			a = 1.0
		if has_dist:
			var dist2 := float(d.get("dist2", INF))
			if dist2 < best_d - 1e-9 or (absf(dist2 - best_d) <= 1e-9 and a < best_a):
				best_d = dist2
				best_a = a
				best_id = pid
		else:
			if a < best_a:
				best_a = a
				best_id = pid
	return best_id


static func _smallest_id(rows: Array) -> int:
	return _best_pick_id(rows)


static func polygon_area_abs(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var area := 0.0
	var j := poly.size() - 1
	for i in poly.size():
		area += (poly[j].x + poly[i].x) * (poly[j].y - poly[i].y)
		j = i
	return absf(area) * 0.5
