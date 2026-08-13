# scripts/map/ProvincePolygonUtil.gd
## Shared safe province polygon helpers for world_full geometry.
## Invalid / self-intersecting outlines fail Godot triangulation and spam:
##   "Invalid polygon data, triangulation failed" → main-thread hang.
## Use these for every province fill path and when assigning Polygon2D.polygon.

class_name ProvincePolygonUtil
extends RefCounted

const MIN_EDGE_SQ := 0.000001  # drop zero-length edges
const MIN_AREA := 0.5  # approx world units² — reject slivers
const FALLBACK_RADIUS := 16.0


## Remove consecutive duplicates / zero edges; drop closing dup of first point.
static func sanitize(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return PackedVector2Array()
	var out := PackedVector2Array()
	out.resize(0)
	for i in range(points.size()):
		var p: Vector2 = points[i]
		if out.is_empty():
			out.append(p)
			continue
		if out[out.size() - 1].distance_squared_to(p) < MIN_EDGE_SQ:
			continue
		out.append(p)
	# Drop last if it closes the ring
	if out.size() >= 4 and out[0].distance_squared_to(out[out.size() - 1]) < MIN_EDGE_SQ:
		out.resize(out.size() - 1)
	if out.size() < 3:
		return PackedVector2Array()
	return out


static func approx_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var a := 0.0
	for i in range(points.size()):
		var j := (i + 1) % points.size()
		a += points[i].x * points[j].y - points[j].x * points[i].y
	return absf(a) * 0.5


static func centroid(points: PackedVector2Array) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in points:
		acc += p
	return acc / float(points.size())


## True if Godot can triangulate for canvas fill.
static func is_drawable(points: PackedVector2Array) -> bool:
	var clean := sanitize(points)
	if clean.size() < 3:
		return false
	if approx_area(clean) < MIN_AREA:
		return false
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(clean)
	return not indices.is_empty()


## Best-effort drawable outline: sanitize → optional convex hull fallback.
## Returns empty if even hull fails (caller should use circle).
static func make_drawable(points: PackedVector2Array) -> PackedVector2Array:
	var clean := sanitize(points)
	if clean.size() < 3:
		return PackedVector2Array()
	if is_drawable(clean):
		return clean
	# Convex hull is always simple (non-self-intersecting) when ≥3 points.
	var hull: PackedVector2Array = Geometry2D.convex_hull(clean)
	hull = sanitize(hull)
	if hull.size() >= 3 and is_drawable(hull):
		return hull
	return PackedVector2Array()


## Assign to Polygon2D safely. Returns points actually stored (may be hull).
static func assign_polygon2d(poly: Polygon2D, points: PackedVector2Array) -> PackedVector2Array:
	if poly == null:
		return PackedVector2Array()
	var drawable := make_drawable(points)
	if drawable.size() < 3:
		# Minimal triangle around centroid so node still has something
		var c := centroid(sanitize(points))
		if c == Vector2.ZERO and points.size() > 0:
			c = points[0]
		drawable = PackedVector2Array([
			c + Vector2(0, -6),
			c + Vector2(5.2, 3),
			c + Vector2(-5.2, 3),
		])
	poly.polygon = drawable
	return drawable


## Assign CollisionPolygon2D — prefers convex (physics-friendly).
static func assign_collision_polygon(collision: CollisionPolygon2D, points: PackedVector2Array) -> PackedVector2Array:
	if collision == null:
		return PackedVector2Array()
	var clean := sanitize(points)
	if clean.size() < 3:
		return PackedVector2Array()
	var hull: PackedVector2Array = Geometry2D.convex_hull(clean)
	hull = sanitize(hull)
	if hull.size() < 3:
		hull = make_drawable(clean)
	if hull.size() < 3:
		return PackedVector2Array()
	collision.polygon = hull
	return hull


## Safe canvas fill. Returns "poly" | "hull" | "circle".
static func draw_fill(
	item: CanvasItem,
	points: PackedVector2Array,
	color: Color,
	fallback_center: Vector2 = Vector2.ZERO,
	fallback_radius: float = FALLBACK_RADIUS,
) -> String:
	if item == null:
		return "none"
	var clean := sanitize(points)
	var center := fallback_center
	if center == Vector2.ZERO and clean.size() > 0:
		center = centroid(clean)
	var drawable := make_drawable(clean)
	if drawable.size() >= 3:
		item.draw_colored_polygon(drawable, color)
		# hull if drawable differs from clean in size a lot
		if drawable.size() != clean.size():
			return "hull"
		return "poly"
	if center != Vector2.ZERO:
		item.draw_circle(center, fallback_radius, color)
		return "circle"
	return "none"


## Safe draw_polygon (multi-color API used by some overlays).
static func draw_fill_colors(
	item: CanvasItem,
	points: PackedVector2Array,
	colors: PackedColorArray,
	fallback_center: Vector2 = Vector2.ZERO,
	fallback_radius: float = FALLBACK_RADIUS,
) -> String:
	if item == null or colors.is_empty():
		return "none"
	var col: Color = colors[0]
	return draw_fill(item, points, col, fallback_center, fallback_radius)


## Convert loose Array points (geo JSON style) to PackedVector2Array.
static func from_variant_points(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raw is PackedVector2Array:
		return sanitize(raw as PackedVector2Array)
	if raw is Array:
		for p in raw as Array:
			if p is Vector2:
				out.append(p as Vector2)
			elif p is Array and (p as Array).size() >= 2:
				out.append(Vector2(float(p[0]), float(p[1])))
	return sanitize(out)
