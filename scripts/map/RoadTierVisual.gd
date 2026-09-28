# scripts/map/RoadTierVisual.gd
## RT-1 Phase 1 — pure road-tier + edge-sanity helpers (visual only).
## Source of truth for the era-relative formula already used by
## InfrastructureOverlayLayer._rebuild_road_layer_inner (no gameplay change).
## Dirt=0, Paved=1, Highway=2. Explicit built_road_neighbors edges are highway.
class_name RoadTierVisual
extends RefCounted

const TIER_DIRT := 0
const TIER_PAVED := 1
const TIER_HIGHWAY := 2

## Screen-pixel design widths (recomputed from zoom in _draw, never world-locked).
const DIRT_SCREEN_PX := 2.6
const PAVED_SCREEN_PX := 4.0
const PAVED_EDGE_SCREEN_PX := 1.2
const HIGHWAY_SCREEN_PX := 6.0
const HIGHWAY_CASING_SCREEN_PX := 8.5
const HIGHWAY_STRIPE_SCREEN_PX := 1.6
const DIRT_DASH_SCREEN_PX := 9.0
const DIRT_GAP_SCREEN_PX := 6.0

## Palette: saturated enough to read on political fills (not thin grey).
const DIRT_COLOR := Color(0.84, 0.56, 0.18, 0.96)
const PAVED_COLOR := Color(0.34, 0.36, 0.40, 0.94)
const PAVED_EDGE_COLOR := Color(0.16, 0.17, 0.20, 0.82)
const HIGHWAY_CASING_COLOR := Color(0.05, 0.05, 0.07, 0.96)
const HIGHWAY_CORE_COLOR := Color(0.22, 0.24, 0.28, 0.95)
const HIGHWAY_STRIPE_COLOR := Color(0.98, 0.94, 0.62, 0.98)

## Zoom LOD. Europe Home is ~0.33–0.69 (strategic / low operational). The
## previous FAR_MAX=0.45 left Home in the mid band, so every NUTS3 dirt
## edge painted a continent-wide grey mesh. Keep far above Home so the
## first wheel-in still hides paved. Europe/Home = highways only.
const ZOOM_FAR_MAX := 1.05
const ZOOM_CLOSE_MIN := 1.55
const DIRT_ZOOM_FLOOR := 1.55
const END_LABEL_ZOOM_MIN := 1.55
const END_LABEL_FONT_PX := 14

## Fallback when the board has no usable shared-border set.
## Tuned on the Rhineland: Bonn–Köln 7.86 and Köln–Leverkusen 3.15 pass;
## Köln–Düren 12.78 and Köln–Essen 14.62 fail. Largest real Köln neighbour
## on world_accurate is Neuss at 9.40.
const RHINE_CENTROID_GAP_CAP := 11.0

const KOELN_ID := 710417
const BONN_ID := 710416
const LEVERKUSEN_ID := 710418
const ESSEN_ID := 710403
const DUREN_ID := 710419

## NUTS3 Europe id block (pilot board + world_accurate Europe).
const NUTS3_ID_MIN := 710000
const NUTS3_ID_MAX := 799999


## Keep today's era-relative formula: road_infra_min / +3 / +6; explicit ⇒ 2.
static func road_tier_for_edge(avg_infra: float, era_profile: Dictionary, explicit: bool) -> int:
	if explicit:
		return TIER_HIGHWAY
	var road_min: float = float(era_profile.get("road_infra_min", 3.0))
	var tier: int = TIER_DIRT
	if avg_infra >= road_min + 3.0:
		tier = TIER_HIGHWAY if avg_infra >= road_min + 6.0 else TIER_PAVED
	elif avg_infra >= road_min:
		tier = TIER_PAVED
	return tier


static func lod_band_for_zoom(zoom: float) -> int:
	var z: float = zoom
	if not is_finite(z):
		z = 1.0
	if z <= ZOOM_FAR_MAX:
		return 0
	if z >= ZOOM_CLOSE_MIN:
		return 2
	return 1


static func dirt_hidden_at_zoom(zoom: float) -> bool:
	return zoom < DIRT_ZOOM_FLOOR


## Europe/Home: only formula highways (or explicit). Mid: paved+highway.
## Close: dirt+paved+highway. Remapped display highways do NOT show at Europe.
static func tier_visible_at_zoom(formula_tier: int, explicit: bool, display_tier: int, zoom: float) -> bool:
	var z: float = zoom
	if not is_finite(z):
		z = 1.0
	var lod: int = lod_band_for_zoom(z)
	if lod <= 0:
		return explicit or formula_tier == TIER_HIGHWAY
	if lod == 1:
		return display_tier >= TIER_PAVED
	return true


static func display_tier_from_rank(rank01: float, explicit: bool) -> int:
	if explicit:
		return TIER_HIGHWAY
	var r: float = rank01
	if not is_finite(r):
		r = 0.0
	r = clampf(r, 0.0, 0.999)
	if r >= 0.67:
		return TIER_HIGHWAY
	if r >= 0.34:
		return TIER_PAVED
	return TIER_DIRT


static func end_labels_visible_at_zoom(zoom: float) -> bool:
	return zoom >= END_LABEL_ZOOM_MIN


static func end_labels_visible_for_span(zoom: float, _spine_span_world: float) -> bool:
	return end_labels_visible_at_zoom(zoom)


static func screen_width_for_tier(tier: int, lod_band: int) -> float:
	var w: float = DIRT_SCREEN_PX
	match tier:
		TIER_PAVED:
			w = PAVED_SCREEN_PX
		TIER_HIGHWAY:
			w = HIGHWAY_SCREEN_PX
		_:
			w = DIRT_SCREEN_PX
	# Close zoom: cap so strokes do not blow out; far uses colour+width only.
	if lod_band >= 2:
		w = minf(w, HIGHWAY_SCREEN_PX)
	return w


static func edge_key(a: int, b: int) -> String:
	return "%d_%d" % [mini(a, b), maxi(a, b)]


## share_border_known=true uses the geometry flag. Otherwise centroid-gap fallback.
static func road_edge_passes_sanity(
	distance: float,
	share_border_known: bool,
	share_border: bool,
	centroid_cap: float = RHINE_CENTROID_GAP_CAP,
) -> bool:
	if share_border_known:
		return share_border
	if not is_finite(distance) or distance <= 0.0:
		return false
	return distance <= centroid_cap


static func must_draw_pairs() -> Array:
	return [[BONN_ID, KOELN_ID], [KOELN_ID, LEVERKUSEN_ID]]


static func must_not_draw_pairs() -> Array:
	return [[KOELN_ID, ESSEN_ID], [KOELN_ID, DUREN_ID]]


## Quantized undirected segment key (same idea as shared_edge_adjacency_product).
static func quantized_segment_key(a: Vector2, b: Vector2, quant: float) -> String:
	var q: float = maxf(quant, 0.5)
	var ax: int = int(round(a.x / q))
	var ay: int = int(round(a.y / q))
	var bx: int = int(round(b.x / q))
	var by: int = int(round(b.y / q))
	if ax > bx or (ax == bx and ay > by):
		var tx: int = ax
		var ty: int = ay
		ax = bx
		ay = by
		bx = tx
		by = ty
	if ax == bx and ay == by:
		return ""
	return "%d_%d_%d_%d" % [ax, ay, bx, by]


## pid → PackedVector2Array rings → undirected "min_max" keys that share a border.
static func shared_border_keys_from_rings(rings: Dictionary, quant: float = 4.0) -> Dictionary:
	var edge_to_pids: Dictionary = {}
	for pid_v in rings.keys():
		var pid: int = int(pid_v)
		var ring_v: Variant = rings[pid_v]
		if typeof(ring_v) != TYPE_PACKED_VECTOR2_ARRAY:
			continue
		var ring: PackedVector2Array = ring_v
		if ring.size() < 3:
			continue
		var n: int = ring.size()
		for i in range(n):
			var a: Vector2 = ring[i]
			var b: Vector2 = ring[(i + 1) % n]
			var sk: String = quantized_segment_key(a, b, quant)
			if sk.is_empty():
				continue
			var owners: Variant = edge_to_pids.get(sk, PackedInt32Array())
			var packed: PackedInt32Array = owners
			var found := false
			for j in packed.size():
				if int(packed[j]) == pid:
					found = true
					break
			if not found:
				packed.append(pid)
				edge_to_pids[sk] = packed
	var keys: Dictionary = {}
	for sk in edge_to_pids.keys():
		var packed2: PackedInt32Array = edge_to_pids[sk]
		if packed2.size() < 2:
			continue
		for i in range(packed2.size()):
			for j in range(i + 1, packed2.size()):
				keys[edge_key(int(packed2[i]), int(packed2[j]))] = true
	return keys


static func is_nuts3_pid(pid: int) -> bool:
	return pid >= NUTS3_ID_MIN and pid <= NUTS3_ID_MAX
