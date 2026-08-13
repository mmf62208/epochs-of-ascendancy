# scripts/map/MapCanvasConfig.gd
## Single source for Europe tactical canvas scale (+72.8% vs legacy 5000×2000 / 8192×4096).
class_name MapCanvasConfig
extends RefCounted

const THEATER_SCALE: float = 1.728

const BASE_GRAND_SIZE := Vector2(5000.0, 2000.0)
const BASE_WORLD_SIZE := Vector2(8192.0, 4096.0)
const BASE_EUROPE_CENTER := Vector2(2500.0, 1000.0)

const GRAND_THEATER_BOUNDS := Rect2(0.0, 0.0, 5000.0 * THEATER_SCALE, 2000.0 * THEATER_SCALE)
## Exact equirect canvas × THEATER_SCALE (must match province transform + underlay fit 1:1).
const WORLD_CANONICAL_BOUNDS := Rect2(0.0, 0.0, 8192.0 * THEATER_SCALE, 4096.0 * THEATER_SCALE)

const BASE_EU_WX0: float = 3526.0
const BASE_EU_WY0: float = 979.0
const BASE_EU_WW: float = 1593.0
const BASE_EU_WH: float = 1372.0
const ISLAND_EXTRA_SCALE: float = 1.4
const ISLAND_TINY_EXTRA_SCALE: float = 1.55
const SMALL_PROVINCE_MAX_EXTENT: float = 45.0
const SMALL_PROVINCE_MAX_AREA: float = 280.0
const TINY_PROVINCE_MAX_EXTENT: float = 22.0
const TINY_PROVINCE_MAX_AREA: float = 90.0

const PICK_GRID_CELL_SIZE: float = 64.0 * THEATER_SCALE
const PROVINCE_DETAIL_MIN_ZOOM: float = 0.8 / THEATER_SCALE
const DEFAULT_CAMERA_ZOOM: float = 0.4 * THEATER_SCALE
const DEFAULT_CAMERA_ZOOM_ALT: float = 0.45 * THEATER_SCALE
const MAX_CAMERA_ZOOM: float = 14.0
const VIEWPORT_FILL_RATIO: float = 0.96
const EUROPE_VIEW_FILL_RATIO: float = 0.92


static func wrap_position(p: Vector2, bounds: Rect2) -> Vector2:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return p
	var rel := p - bounds.position
	rel.x = fposmod(rel.x, bounds.size.x)
	if rel.x < 0.0:
		rel.x += bounds.size.x
	rel.y = fposmod(rel.y, bounds.size.y)
	if rel.y < 0.0:
		rel.y += bounds.size.y
	return bounds.position + rel


static func zoom_to_fill_bounds(bounds: Rect2, viewport_size: Vector2, fill_ratio: float, min_z: float, max_z: float) -> float:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or viewport_size.x <= 0.0:
		return min_z
	var zx := viewport_size.x * fill_ratio / bounds.size.x
	var zy := viewport_size.y * fill_ratio / bounds.size.y
	return clampf(minf(zx, zy), min_z, max_z)


static func europe_center() -> Vector2:
	return BASE_EUROPE_CENTER * THEATER_SCALE


static func europe_world_rect() -> Rect2:
	return Rect2(
		Vector2(BASE_EU_WX0, BASE_EU_WY0) * THEATER_SCALE,
		Vector2(BASE_EU_WW, BASE_EU_WH) * THEATER_SCALE,
	)


static func europe_world_center() -> Vector2:
	return europe_world_rect().get_center()


static func world_chunk_half_size() -> Vector2:
	return BASE_WORLD_SIZE * THEATER_SCALE * 0.5


static func is_world_mode(bounds: Rect2) -> bool:
	return bounds.size.x > BASE_GRAND_SIZE.x * THEATER_SCALE * 1.05


static func scale_point(p: Vector2) -> Vector2:
	return p * THEATER_SCALE


static func scale_points(pts: PackedVector2Array) -> PackedVector2Array:
	if THEATER_SCALE == 1.0:
		return pts
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = scale_point(pts[i])
	return out


static func scale_rect(r: Rect2) -> Rect2:
	return Rect2(scale_point(r.position), r.size * THEATER_SCALE)


static func polygon_area(pts: PackedVector2Array) -> float:
	if pts.size() < 3:
		return 0.0
	var area := 0.0
	for i in pts.size():
		var j := (i + 1) % pts.size()
		area += pts[i].x * pts[j].y - pts[j].x * pts[i].y
	return absf(area) * 0.5


static func polygon_max_extent(pts: PackedVector2Array) -> float:
	if pts.is_empty():
		return 0.0
	var min_v := pts[0]
	var max_v := pts[0]
	for pt in pts:
		min_v = min_v.min(pt)
		max_v = max_v.max(pt)
	return maxf(max_v.x - min_v.x, max_v.y - min_v.y)


static func polygon_centroid(pts: PackedVector2Array) -> Vector2:
	if pts.is_empty():
		return Vector2.ZERO
	if pts.size() < 3:
		var sum := Vector2.ZERO
		for pt in pts:
			sum += pt
		return sum / float(pts.size())
	var area := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in pts.size():
		var j := (i + 1) % pts.size()
		var cross := pts[i].x * pts[j].y - pts[j].x * pts[i].y
		area += cross
		cx += (pts[i].x + pts[j].x) * cross
		cy += (pts[i].y + pts[j].y) * cross
	if is_zero_approx(area):
		var sum2 := Vector2.ZERO
		for pt in pts:
			sum2 += pt
		return sum2 / float(pts.size())
	area *= 0.5
	return Vector2(cx / (6.0 * area), cy / (6.0 * area))


static func island_inflation_factor(pts: PackedVector2Array) -> float:
	if pts.size() < 3:
		return 1.0
	var ext := polygon_max_extent(pts)
	var area := polygon_area(pts)
	if ext <= TINY_PROVINCE_MAX_EXTENT or area <= TINY_PROVINCE_MAX_AREA:
		return ISLAND_TINY_EXTRA_SCALE
	if ext <= SMALL_PROVINCE_MAX_EXTENT or area <= SMALL_PROVINCE_MAX_AREA:
		return ISLAND_EXTRA_SCALE
	return 1.0


static func inflate_points_from_centroid(pts: PackedVector2Array, factor: float) -> PackedVector2Array:
	if factor <= 1.001 or pts.size() < 3:
		return pts
	var center := polygon_centroid(pts)
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = center + (pts[i] - center) * factor
	return out


static func remap_europe_to_world(local_pts: PackedVector2Array) -> PackedVector2Array:
	var grand := GRAND_THEATER_BOUNDS.size
	var eu := europe_world_rect()
	var out := PackedVector2Array()
	out.resize(local_pts.size())
	for i in local_pts.size():
		var ptv := local_pts[i]
		var fx := ptv.x / grand.x
		var fy := ptv.y / grand.y
		out[i] = Vector2(eu.position.x + fx * eu.size.x, eu.position.y + fy * eu.size.y)
	return out


## geometry_is_world_native: points already live in full-world equirectangular canvas (8192×4096 base).
## When true, skip Europe-local → world-slot remapping so Americas/Asia/etc. land on the world underlay.
static func transform_province_points(
	pts: PackedVector2Array,
	world_mode: bool,
	apply_island_inflate: bool = true,
	geometry_is_world_native: bool = false,
) -> PackedVector2Array:
	var working := pts
	if apply_island_inflate:
		var inflate := island_inflation_factor(pts)
		if inflate > 1.001:
			working = inflate_points_from_centroid(pts, inflate)
	var scaled := scale_points(working)
	if world_mode and not geometry_is_world_native:
		return remap_europe_to_world(scaled)
	return scaled


## Headless / TestRunner evidence: counts how many provinces get island inflation tiers.
static func summarize_island_inflation(geometry: Dictionary) -> Dictionary:
	var tiny := 0
	var small := 0
	var normal := 0
	for pid_var in geometry.keys():
		var geo: Dictionary = geometry[pid_var]
		var pts: PackedVector2Array = geo.get("points", PackedVector2Array())
		if pts.size() < 3:
			continue
		var f := island_inflation_factor(pts)
		if f >= ISLAND_TINY_EXTRA_SCALE - 0.001:
			tiny += 1
		elif f >= ISLAND_EXTRA_SCALE - 0.001:
			small += 1
		else:
			normal += 1
	return {
		"tiny_inflated": tiny,
		"small_inflated": small,
		"normal": normal,
		"theater_scale": THEATER_SCALE,
		"island_extra": ISLAND_EXTRA_SCALE,
		"tiny_extra": ISLAND_TINY_EXTRA_SCALE,
	}
