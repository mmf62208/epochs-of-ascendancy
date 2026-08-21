# scripts/map/MapPoliticalLabelsLayer.gd
## Nation + strategic-region + state name labels (Vic3/EU4/HOI4-style zoom LOD).
class_name MapPoliticalLabelsLayer
extends Node2D

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")

var _nation_labels: Dictionary = {}  # tag -> Label
var _region_labels: Dictionary = {}  # region_id -> Label
var _state_labels: Dictionary = {}  # state_id -> Label
var _built: bool = false
var _current_tier: int = 0  # MapZoomLOD.Tier.STRATEGIC
var _current_map_mode: String = "political"
var _hover_region_id: int = -1
var _viewport_rect: Rect2 = Rect2()
var _viewport_culling_active: bool = false


func _ready() -> void:
	z_index = 12
	set_process(false)


func rebuild_from_map_data(province_centroids: Dictionary, provinces: Dictionary) -> void:
	_clear_labels()
	if typeof(MapManager) == TYPE_NIL:
		return
	_build_nation_labels(province_centroids, provinces)
	_build_region_labels(province_centroids)
	_build_state_labels(province_centroids, provinces)
	_built = true
	_apply_tier_visibility(_current_tier)


func set_map_mode_context(map_mode: String) -> void:
	var m := map_mode.strip_edges().to_lower()
	if m == _current_map_mode:
		return
	_current_map_mode = m if not m.is_empty() else "political"
	if _built:
		_apply_tier_visibility(_current_tier)


func sync_tier(tier: int) -> void:
	if tier == _current_tier and _built:
		_apply_region_label_visibility()
		_apply_state_label_visibility()
		return
	_current_tier = tier
	if not _built:
		return
	_apply_tier_visibility(tier)


func set_hovered_region(region_id: int, tier: int = -1) -> void:
	if tier >= 0:
		_current_tier = tier
	_hover_region_id = region_id
	if not _built:
		return
	_apply_region_label_visibility()


func sync_viewport(world_rect: Rect2, active: bool) -> void:
	_viewport_rect = world_rect
	_viewport_culling_active = active
	if not _built:
		return
	_apply_tier_visibility(_current_tier)


func _clear_labels() -> void:
	for lbl in _nation_labels.values():
		if lbl is Node:
			(lbl as Node).queue_free()
	for lbl in _region_labels.values():
		if lbl is Node:
			(lbl as Node).queue_free()
	for lbl in _state_labels.values():
		if lbl is Node:
			(lbl as Node).queue_free()
	_nation_labels.clear()
	_region_labels.clear()
	_state_labels.clear()
	_built = false


const _NATION_DISPLAY_NAMES := {
	"GER": "Germany",
	"FRA": "France",
	"ENG": "United Kingdom",
	"GBR": "United Kingdom",
	"UK": "United Kingdom",
	"SOV": "Soviet Union",
	"RUS": "Russia",
	"ITA": "Italy",
	"USA": "United States",
	"JAP": "Japan",
	"POL": "Poland",
	"CHI": "China",
	"SPA": "Spain",
	"SPR": "Spain",
	"AUS": "Austria",
	"CZE": "Czechoslovakia",
	"HUN": "Hungary",
	"ROM": "Romania",
	"YUG": "Yugoslavia",
	"TUR": "Turkey",
	"SWE": "Sweden",
	"NOR": "Norway",
	"FIN": "Finland",
	"DEN": "Denmark",
	"DNK": "Denmark",
	"HOL": "Netherlands",
	"NLD": "Netherlands",
	"BEL": "Belgium",
	"LUX": "Luxembourg",
	"SWI": "Switzerland",
	"CHE": "Switzerland",
	"POR": "Portugal",
	"GRE": "Greece",
	"BUL": "Bulgaria",
	"CAN": "Canada",
	"MEX": "Mexico",
	"BRA": "Brazil",
	"ARG": "Argentina",
	"AST": "Australia",
	"AUL": "Australia",
	"RAJ": "British Raj",
	"IND": "British Raj",
	"MAN": "Manchukuo",
	"IRE": "Ireland",
	"IRL": "Ireland",
	"LIT": "Lithuania",
	"LAT": "Latvia",
	"EST": "Estonia",
	"PER": "Iran",
	"SIA": "Siam",
	"AFG": "Afghanistan",
	"SAU": "Saudi Arabia",
	"YEM": "Yemen",
	"EGY": "Egypt",
	"IRQ": "Iraq",
	"ALB": "Albania",
	"CHL": "Chile",
	"COL": "Colombia",
	"VEN": "Venezuela",
	"BOL": "Bolivia",
	"PAR": "Paraguay",
	"URG": "Uruguay",
	"ECU": "Ecuador",
	"CUB": "Cuba",
	"HAI": "Haiti",
	"DOM": "Dominican Republic",
	"GUA": "Guatemala",
	"HON": "Honduras",
	"NIC": "Nicaragua",
	"COS": "Costa Rica",
	"ELS": "El Salvador",
	"PAN": "Panama",
	"LIB": "Liberia",
	"BHU": "Bhutan",
	"NEP": "Nepal",
	"MON": "Mongolia",
	"NZL": "New Zealand",
	"MLT": "Malta",
	"CYP": "Cyprus",
	"LIE": "Liechtenstein",
	"ICE": "Iceland",
}


func _resolve_nation_display_name(tag: String) -> String:
	var t := tag.strip_edges().to_upper()
	if MapManager != null and MapManager.has_method("get_country"):
		var country = MapManager.get_country(t)
		if country != null:
			if country is Dictionary and country.has("name"):
				var dn := str(country["name"]).strip_edges()
				# Prefer full name over raw tag stubs
				if not dn.is_empty() and dn.to_upper() != t:
					return dn
			elif country is Object and "name" in country:
				var on := str(country.name).strip_edges()
				if not on.is_empty() and on.to_upper() != t:
					return on
	if _NATION_DISPLAY_NAMES.has(t):
		return str(_NATION_DISPLAY_NAMES[t])
	return t


func _resolve_capital_province_id(tag: String, provinces: Dictionary) -> int:
	var t := tag.strip_edges().to_upper()
	var cap_id := -1
	if MapManager != null and MapManager.has_method("get_country"):
		var country = MapManager.get_country(t)
		if country is Dictionary:
			cap_id = int(country.get("capital_province_id", country.get("capital", -1)))
		elif country is Object and "capital_province_id" in country:
			cap_id = int(country.capital_province_id)
	if cap_id >= 0 and provinces.has(cap_id):
		var cp: Province = provinces[cap_id]
		if cp != null and not cp.is_sea:
			var ot := cp.owner_tag.strip_edges().to_upper()
			var ct := cp.controller_tag.strip_edges().to_upper()
			if ot == t or ct == t or ot.is_empty():
				return cap_id
	for pid_var in provinces.keys():
		var pid := int(pid_var)
		var prov: Province = provinces[pid]
		if prov == null or prov.is_sea:
			continue
		if prov.owner_tag.strip_edges().to_upper() != t:
			continue
		if prov.has_feature("capital"):
			return pid
	return -1


func _owned_land_pids(tag: String, provinces: Dictionary) -> Array[int]:
	var t := tag.strip_edges().to_upper()
	var out: Array[int] = []
	for pid_var in provinces.keys():
		var pid := int(pid_var)
		var prov: Province = provinces[pid]
		if prov == null or prov.is_sea:
			continue
		if prov.owner_tag.strip_edges().to_upper() == t:
			out.append(pid)
	return out


func _neighbor_pids(pid: int, province: Province) -> Array:
	if province != null and province.adjacencies.size() > 0:
		return province.adjacencies
	if MapManager != null and MapManager.has_method("get_adjacency_system"):
		var adj = MapManager.get_adjacency_system()
		if adj != null and adj.has_method("get_neighbors"):
			return adj.get_neighbors(pid)
		if adj != null and adj.has_method("get_land_neighbors"):
			return adj.get_land_neighbors(pid)
	return []


## Centroid of the connected landmass that contains the capital (not the capital city pin).
## Fixes UK "United Kingdom" sitting on London / hanging off the island.
func _capital_landmass_centroid(tag: String, province_centroids: Dictionary, provinces: Dictionary) -> Vector2:
	var owned := _owned_land_pids(tag, provinces)
	if owned.is_empty():
		return Vector2.INF
	var owned_set: Dictionary = {}
	for pid in owned:
		owned_set[pid] = true

	var cap_id := _resolve_capital_province_id(tag, provinces)
	var seed_id := cap_id if cap_id >= 0 and owned_set.has(cap_id) else owned[0]

	# BFS through same-owner land neighbors → capital's contiguous landmass.
	var component: Array[int] = []
	var q: Array[int] = [seed_id]
	var seen: Dictionary = {seed_id: true}
	while not q.is_empty():
		var cur: int = int(q.pop_front())
		component.append(cur)
		var prov: Province = provinces.get(cur) as Province
		for nid_v in _neighbor_pids(cur, prov):
			var nid: int = int(nid_v)
			if seen.has(nid) or not owned_set.has(nid):
				continue
			if not province_centroids.has(nid):
				continue
			seen[nid] = true
			q.append(nid)

	# Population-weighted centroid of that landmass (inland visual center).
	var sum := Vector2.ZERO
	var wsum := 0.0
	for pid in component:
		if not province_centroids.has(pid):
			continue
		var prov2: Province = provinces.get(pid) as Province
		var w := 1.0
		if prov2 != null:
			w = maxf(1.0, float(prov2.population) / 40000.0)
		sum += (province_centroids[pid] as Vector2) * w
		wsum += w
	if wsum <= 0.0:
		return Vector2.INF
	return sum / wsum


func _main_mass_centroid(tag: String, province_centroids: Dictionary, provinces: Dictionary) -> Vector2:
	## Largest connected same-owner landmass by province count (fallback without capital).
	var owned := _owned_land_pids(tag, provinces)
	if owned.is_empty():
		return Vector2.INF
	var owned_set: Dictionary = {}
	for pid in owned:
		owned_set[pid] = true
	var best: Array[int] = []
	var global_seen: Dictionary = {}
	for start in owned:
		if global_seen.has(start):
			continue
		var comp: Array[int] = []
		var q: Array[int] = [start]
		global_seen[start] = true
		while not q.is_empty():
			var cur: int = int(q.pop_front())
			comp.append(cur)
			var prov: Province = provinces.get(cur) as Province
			for nid_v in _neighbor_pids(cur, prov):
				var nid: int = int(nid_v)
				if global_seen.has(nid) or not owned_set.has(nid):
					continue
				if not province_centroids.has(nid):
					continue
				global_seen[nid] = true
				q.append(nid)
		if comp.size() > best.size():
			best = comp
	var sum := Vector2.ZERO
	var wsum := 0.0
	for pid in best:
		if not province_centroids.has(pid):
			continue
		var prov2: Province = provinces.get(pid) as Province
		var w := maxf(1.0, float(prov2.population) / 40000.0) if prov2 else 1.0
		sum += (province_centroids[pid] as Vector2) * w
		wsum += w
	if wsum <= 0.0:
		return Vector2.INF
	return sum / wsum


func _build_nation_labels(province_centroids: Dictionary, provinces: Dictionary) -> void:
	var by_tag: Dictionary = {}  # tag -> {sum, count, color, name, pop}
	for pid_var in province_centroids.keys():
		var pid := int(pid_var)
		if not provinces.has(pid):
			continue
		var prov: Province = provinces[pid]
		if prov == null or prov.is_sea:
			continue
		var tag := prov.owner_tag.strip_edges().to_upper()
		if tag.is_empty():
			continue
		var c: Vector2 = province_centroids[pid]
		if not by_tag.has(tag):
			var col := Color(0.85, 0.88, 0.95, 0.95)
			if MapManager.has_method("get_country_color"):
				col = MapManager.get_country_color(tag)
			by_tag[tag] = {
				"sum": Vector2.ZERO,
				"count": 0,
				"pop": 0,
				"color": col,
				"name": _resolve_nation_display_name(tag),
			}
		var entry: Dictionary = by_tag[tag]
		entry["sum"] = (entry["sum"] as Vector2) + c
		entry["count"] = int(entry["count"]) + 1
		entry["pop"] = int(entry["pop"]) + int(prov.population)

	var nation_label_nodes: Array[Label] = []
	# Prefer majors first so FRA/ENG/ITA/SOV win collision resolution over LUX-size tags.
	var tags_sorted: Array = by_tag.keys()
	tags_sorted.sort_custom(func(a, b):
		return int(by_tag[a]["count"]) > int(by_tag[b]["count"])
	)
	for tag_var in tags_sorted:
		var tag := str(tag_var)
		var e: Dictionary = by_tag[tag]
		var n := int(e["count"])
		if n <= 0:
			continue
		# Skip tiny minors at strategic (noise); still label if ≥4 or known major table.
		if n < 4 and not _NATION_DISPLAY_NAMES.has(tag):
			continue
		# Placement: capital's contiguous landmass center (not city pin) → largest mass → mean.
		var center := _capital_landmass_centroid(tag, province_centroids, provinces)
		if center == Vector2.INF:
			center = _main_mass_centroid(tag, province_centroids, provinces)
		if center == Vector2.INF:
			center = (e["sum"] as Vector2) / float(n)
		# Scale by province count + population (HOI/EU style: larger countries = larger names).
		var pop := int(e.get("pop", 0))
		var font_px := 14
		if n >= 200 or pop >= 40_000_000:
			font_px = 28
		elif n >= 80 or pop >= 15_000_000:
			font_px = 24
		elif n >= 30 or pop >= 5_000_000:
			font_px = 20
		elif n >= 12:
			font_px = 17
		else:
			font_px = 14
		var lbl := _make_label(str(e["name"]), center, font_px, e["color"] as Color)
		lbl.name = "NationLabel_%s" % tag
		add_child(lbl)
		_fit_and_center_label(lbl)
		_nation_labels[tag] = lbl
		nation_label_nodes.append(lbl)
	_resolve_label_collisions(nation_label_nodes, 120.0)


func _build_region_labels(province_centroids: Dictionary) -> void:
	if not MapManager.has_method("get_all_strategic_regions"):
		return
	var regions: Dictionary = MapManager.get_all_strategic_regions()
	for rid_var in regions.keys():
		var rid := int(rid_var)
		var reg: Dictionary = regions[rid_var]
		if reg.is_empty():
			continue
		var pids: Array = reg.get("province_ids", [])
		var sum := Vector2.ZERO
		var count := 0
		for pid_var in pids:
			var pid := int(pid_var)
			if not province_centroids.has(pid):
				continue
			sum += province_centroids[pid] as Vector2
			count += 1
		if count <= 0:
			continue
		var center := sum / float(count)
		var rname := str(reg.get("name", MapManager.get_strategic_region_name(rid)))
		var lbl := _make_label(rname, center, 16, Color(0.78, 0.82, 0.92, 0.9))
		lbl.name = "RegionLabel_%d" % rid
		add_child(lbl)
		_fit_and_center_label(lbl)
		_region_labels[rid] = lbl


## Stream 2: state names for states mapmode (operational zoom). Prefer ScenarioLoader names.
## Budget: Europe NUTS quota first (first-session Maginot theater), then geo-grid RoW —
## never pure province_n global rank (RoW mega-states starved Europe).
func _build_state_labels(province_centroids: Dictionary, provinces: Dictionary) -> void:
	var by_state: Dictionary = {}  # sid -> {sum, count, name, europe_nuts}
	var loader: Node = null
	var tree := get_tree()
	if tree != null:
		loader = tree.root.find_child("ScenarioLoader", true, false)
	if loader == null:
		loader = get_node_or_null("/root/ScenarioLoader")
	for pid_var in province_centroids.keys():
		var pid := int(pid_var)
		if not provinces.has(pid):
			continue
		var prov: Province = provinces[pid]
		if prov == null or prov.is_sea:
			continue
		var sid := 0
		if loader != null and loader.has_method("get_province_state_id"):
			sid = int(loader.get_province_state_id(pid))
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_state_id"):
			sid = int(MapManager.get_province_state_id(pid))
		if sid <= 0:
			continue
		var c: Vector2 = province_centroids[pid]
		if not by_state.has(sid):
			var sname := "State %d" % sid
			if loader != null and loader.has_method("get_state_name"):
				sname = str(loader.get_state_name(sid))
			by_state[sid] = {
				"sum": Vector2.ZERO,
				"count": 0,
				"name": sname,
				"europe_nuts": false,
			}
		var entry: Dictionary = by_state[sid]
		entry["sum"] = (entry["sum"] as Vector2) + c
		entry["count"] = int(entry["count"]) + 1
		# Europe NUTS block (accurate board IDs 710000+)
		if pid >= 710000 and pid < 800000:
			entry["europe_nuts"] = true
	var all_rows: Array = []
	for sid_var in by_state.keys():
		var e2: Dictionary = by_state[sid_var]
		var n2 := int(e2["count"])
		if n2 <= 0:
			continue
		var center2: Vector2 = (e2["sum"] as Vector2) / float(n2)
		all_rows.append({
			"sid": int(sid_var),
			"count": n2,
			"name": str(e2["name"]),
			"center": center2,
			"europe_nuts": bool(e2.get("europe_nuts", false)),
		})
	var budget := 120
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_count"):
		var nprov := int(MapManager.get_province_count())
		if nprov >= 5000:
			budget = 120
		elif nprov >= 2000:
			budget = 96
	var selected: Array = _select_state_labels_for_budget(all_rows, budget, 48)
	var state_nodes: Array[Label] = []
	for row in selected:
		var sid := int(row["sid"])
		var center: Vector2 = row["center"] as Vector2
		var lbl := _make_label(str(row["name"]), center, 15, Color(0.92, 0.88, 0.72, 0.92))
		lbl.name = "StateLabel_%d" % sid
		lbl.visible = false
		add_child(lbl)
		_fit_and_center_label(lbl)
		_state_labels[sid] = lbl
		state_nodes.append(lbl)
	_resolve_label_collisions(state_nodes, 110.0)


## Mirror pure map_state_labels_surface_product.select_state_labels_for_budget.
func _select_state_labels_for_budget(all_rows: Array, budget: int, europe_quota: int) -> Array:
	if all_rows.is_empty() or budget <= 0:
		return []
	var eq := maxi(8, mini(europe_quota, budget))
	var europe: Array = []
	var rest: Array = []
	for r in all_rows:
		if bool(r.get("europe_nuts", false)):
			europe.append(r)
		else:
			rest.append(r)
	europe.sort_custom(func(a, b):
		var ca := int(a.get("count", 0))
		var cb := int(b.get("count", 0))
		if ca != cb:
			return ca > cb
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	var picked: Array = []
	var picked_ids: Dictionary = {}
	for i in range(mini(eq, europe.size())):
		var er: Dictionary = europe[i]
		picked.append(er)
		picked_ids[int(er["sid"])] = true
	var remain := budget - picked.size()
	var leftover: Array = []
	for r2 in all_rows:
		if not picked_ids.has(int(r2["sid"])):
			leftover.append(r2)
	if remain > 0 and not leftover.is_empty():
		var grid_pick: Array = _geo_grid_pick_state_rows(leftover, remain)
		for g in grid_pick:
			var gsid := int(g["sid"])
			if picked_ids.has(gsid):
				continue
			picked.append(g)
			picked_ids[gsid] = true
			if picked.size() >= budget:
				break
		remain = budget - picked.size()
	if remain > 0:
		leftover.sort_custom(func(a, b): return int(a.get("count", 0)) > int(b.get("count", 0)))
		for r3 in leftover:
			var sid3 := int(r3["sid"])
			if picked_ids.has(sid3):
				continue
			picked.append(r3)
			picked_ids[sid3] = true
			if picked.size() >= budget:
				break
	return picked


func _geo_grid_pick_state_rows(rows: Array, budget: int, cols: int = 6, row_n: int = 4) -> Array:
	if rows.is_empty() or budget <= 0:
		return []
	var minx := 1e12
	var maxx := -1e12
	var miny := 1e12
	var maxy := -1e12
	for r in rows:
		var c: Vector2 = r["center"] as Vector2
		minx = minf(minx, c.x)
		maxx = maxf(maxx, c.x)
		miny = minf(miny, c.y)
		maxy = maxf(maxy, c.y)
	var span_x := maxf(maxx - minx, 1.0)
	var span_y := maxf(maxy - miny, 1.0)
	var cells: Dictionary = {}  # Vector2i -> Array
	for r in rows:
		var c2: Vector2 = r["center"] as Vector2
		var gx := int((c2.x - minx) / span_x * float(cols))
		var gy := int((c2.y - miny) / span_y * float(row_n))
		gx = clampi(gx, 0, cols - 1)
		gy = clampi(gy, 0, row_n - 1)
		var key := Vector2i(gx, gy)
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(r)
	for k in cells.keys():
		var arr: Array = cells[k]
		arr.sort_custom(func(a, b): return int(a.get("count", 0)) > int(b.get("count", 0)))
		cells[k] = arr
	var out: Array = []
	var seen: Dictionary = {}
	var depth := 0
	var keys: Array = cells.keys()
	keys.sort_custom(func(a, b):
		var va: Vector2i = a
		var vb: Vector2i = b
		if va.y != vb.y:
			return va.y < vb.y
		return va.x < vb.x
	)
	while out.size() < budget and depth < 32:
		var progress := false
		for ck in keys:
			var group: Array = cells[ck]
			if depth >= group.size():
				continue
			var row: Dictionary = group[depth]
			var sid := int(row["sid"])
			if seen.has(sid):
				continue
			seen[sid] = true
			out.append(row)
			progress = true
			if out.size() >= budget:
				break
		if not progress:
			break
		depth += 1
	return out


func _resolve_label_collisions(labels: Array, min_sep: float) -> void:
	if labels.size() < 2:
		return
	for _pass in 3:
		for i in range(labels.size()):
			var la: Label = labels[i] as Label
			if la == null:
				continue
			for j in range(i + 1, labels.size()):
				var lb: Label = labels[j] as Label
				if lb == null:
					continue
				var delta := la.position - lb.position
				var dist := delta.length()
				if dist >= min_sep:
					continue
				var push := Vector2(min_sep, 0.0)
				if dist > 0.01:
					push = delta.normalized() * ((min_sep - dist) * 0.5)
				la.position += push
				lb.position -= push


func _make_label(text: String, pos: Vector2, font_px: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Readable on bright solid fills (GER red / FRA blue): light text + strong dark outline (HOI/EU4).
	var readable := Color(0.96, 0.97, 1.0, 0.96)
	# Keep a hint of nation hue in the text without washing into the fill.
	readable = readable.lerp(Color(col.r, col.g, col.b, 1.0), 0.18)
	lbl.add_theme_font_size_override("font_size", maxi(font_px, 14))
	lbl.add_theme_color_override("font_color", readable)
	lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.95))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.z_index = 12
	lbl.clip_text = false
	lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.set_meta("label_anchor", pos)
	return lbl


func _fit_and_center_label(lbl: Label) -> void:
	lbl.reset_size()
	var ms := lbl.get_minimum_size()
	lbl.custom_minimum_size = Vector2(ms.x + 16.0, ms.y + 10.0)
	lbl.reset_size()
	if lbl.has_meta("label_anchor"):
		lbl.position = (lbl.get_meta("label_anchor") as Vector2) - lbl.size * 0.5
	else:
		lbl.position = lbl.position - lbl.size * 0.5


func _apply_tier_visibility(tier: int) -> void:
	var show_n: bool = MapZoomLODScript.show_nation_labels(tier)
	var show_r: bool = MapZoomLODScript.show_region_labels(tier)
	# Hide nation labels when states mapmode is active so state names own the surface.
	if _current_map_mode == "states":
		show_n = false
	var nation_px: int = MapZoomLODScript.nation_label_font_px(tier)
	var region_px: int = MapZoomLODScript.region_label_font_px(tier)
	for lbl in _nation_labels.values():
		if lbl is Label:
			var l := lbl as Label
			var in_view := (
				not _viewport_culling_active
				or _viewport_rect.size == Vector2.ZERO
				or _viewport_rect.has_point(l.position)
			)
			l.visible = show_n and in_view
			if show_n:
				l.add_theme_font_size_override("font_size", nation_px)
				var c := l.get_theme_color("font_color")
				c.a = MapZoomLODScript.label_alpha_for_tier(tier, "nation")
				l.add_theme_color_override("font_color", c)
				_fit_and_center_label(l)
	for rid_var in _region_labels.keys():
		var lbl_r: Variant = _region_labels[rid_var]
		if lbl_r is Label:
			var lr := lbl_r as Label
			lr.add_theme_font_size_override("font_size", region_px)
	_apply_region_label_visibility(show_r)
	_apply_state_label_visibility()


func _apply_region_label_visibility(force_show_tier: bool = false) -> void:
	var show_r: bool = force_show_tier or MapZoomLODScript.show_region_labels(_current_tier)
	if _current_map_mode == "states":
		show_r = false
	for rid_var in _region_labels.keys():
		var rid := int(rid_var)
		var lbl: Variant = _region_labels[rid_var]
		if not (lbl is Label):
			continue
		var l := lbl as Label
		var active := show_r and _hover_region_id >= 0 and rid == _hover_region_id
		l.visible = active
		if active:
			l.add_theme_font_size_override("font_size", MapZoomLODScript.region_label_font_px(_current_tier))
			var c2 := l.get_theme_color("font_color")
			c2.a = MapZoomLODScript.label_alpha_for_tier(_current_tier, "region")
			l.add_theme_color_override("font_color", c2)


func _apply_state_label_visibility() -> void:
	var show_s: bool = MapZoomLODScript.show_state_labels(_current_tier, _current_map_mode)
	var font_px: int = MapZoomLODScript.state_label_font_px(_current_tier)
	for sid_var in _state_labels.keys():
		var lbl: Variant = _state_labels[sid_var]
		if not (lbl is Label):
			continue
		var l := lbl as Label
		var in_view := (
			not _viewport_culling_active
			or _viewport_rect.size == Vector2.ZERO
			or _viewport_rect.has_point(l.position)
		)
		l.visible = show_s and in_view
		if show_s:
			l.add_theme_font_size_override("font_size", font_px)
			var c3 := l.get_theme_color("font_color")
			c3.a = MapZoomLODScript.label_alpha_for_tier(_current_tier, "region")
			l.add_theme_color_override("font_color", c3)
			_fit_and_center_label(l)
