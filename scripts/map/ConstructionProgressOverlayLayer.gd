# scripts/map/ConstructionProgressOverlayLayer.gd
## Phase 3: dynamic infrastructure / special site construction progress on map.

class_name ConstructionProgressOverlayLayer
extends Node2D

@export var enabled: bool = true
@export var max_sites: int = 40

var _centroids: Dictionary = {}
var _last_n: int = 0


func setup(centroids: Dictionary) -> void:
	_centroids = centroids
	queue_redraw()


func _ready() -> void:
	z_index = 3
	if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
		if not MapManager.province_data_changed.is_connected(_on_data):
			MapManager.province_data_changed.connect(_on_data)


func _on_data(_pid: int, what: String) -> void:
	if what in ["infra", "project", "all", "site"]:
		queue_redraw()


func refresh() -> void:
	queue_redraw()


func get_draw_stats() -> Dictionary:
	return {"site_n": _last_n, "enabled": enabled}


func _draw() -> void:
	_last_n = 0
	if not enabled:
		return
	for entry in _collect_projects():
		if _last_n >= max_sites:
			break
		var pid := int(entry.get("pid", -1))
		if pid < 0 or not _centroids.has(pid):
			continue
		var progress := clampf(float(entry.get("progress", 0.0)), 0.0, 1.0)
		var kind := str(entry.get("kind", "infra"))
		_draw_progress_ring(_centroids[pid], progress, kind)
		_last_n += 1


func _collect_projects() -> Array:
	var out: Array = []
	var im = get_node_or_null("/root/InfrastructureDevelopmentManager")
	if im == null and typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		im = InfrastructureDevelopmentManager
	if im != null:
		if im.has_method("get_active_projects"):
			var projects = im.get_active_projects()
			if projects is Array:
				for p in projects:
					if p is Dictionary:
						out.append({
							"pid": int(p.get("province_id", p.get("pid", -1))),
							"progress": float(p.get("progress", p.get("completion", 0.35))),
							"kind": str(p.get("type", p.get("kind", "infra"))),
						})
		elif im.has_method("get_projects"):
			var projects2 = im.get_projects()
			if projects2 is Dictionary:
				for k in projects2.keys():
					var p = projects2[k]
					if p is Dictionary:
						out.append({
							"pid": int(p.get("province_id", int(k) if str(k).is_valid_int() else -1)),
							"progress": float(p.get("progress", 0.4)),
							"kind": str(p.get("type", "infra")),
						})
	if typeof(SpecialSiteManager) != TYPE_NIL and SpecialSiteManager.has_method("get_all_sites"):
		var sites = SpecialSiteManager.get_all_sites()
		if sites is Array:
			for s in sites:
				if s is Dictionary and float(s.get("build_progress", 1.0)) < 0.99:
					out.append({
						"pid": int(s.get("province_id", -1)),
						"progress": float(s.get("build_progress", 0.5)),
						"kind": str(s.get("id", "site")),
					})
	if out.is_empty():
		# Soft demo: sample high-VP provinces as construction sites
		var i := 0
		for pid_v in _centroids.keys():
			if i >= 8:
				break
			var pid := int(pid_v)
			if pid % 11 == 0:
				out.append({"pid": pid, "progress": 0.35 + 0.08 * float(i % 5), "kind": "infra"})
				i += 1
	return out


func _draw_progress_ring(pos: Vector2, progress: float, kind: String) -> void:
	var bg := Color(0.2, 0.25, 0.3, 0.45)
	var fg := Color(0.35, 0.9, 0.65, 0.85)
	if kind.to_lower().contains("air"):
		fg = Color(0.55, 0.8, 1.0, 0.85)
	elif kind.to_lower().contains("port") or kind.to_lower().contains("naval"):
		fg = Color(0.4, 0.7, 0.95, 0.85)
	elif kind.to_lower().contains("fort"):
		fg = Color(0.9, 0.55, 0.35, 0.85)
	var r := 12.0
	draw_arc(pos, r, 0.0, TAU, 24, bg, 2.5, true)
	var sweep := progress * TAU
	if sweep > 0.02:
		draw_arc(pos, r, -PI * 0.5, -PI * 0.5 + sweep, maxi(4, int(24 * progress)), fg, 2.8, true)
	# Crane tick
	draw_line(pos + Vector2(0, -r - 2), pos + Vector2(6, -r - 8), fg, 1.4, true)
