# scripts/map/MapZoomLOD.gd
## Vic3 / EU4 / HOI4-style zoom tiers for map political readability.
class_name MapZoomLOD
extends RefCounted

enum Tier { STRATEGIC, OPERATIONAL, TACTICAL }

# Camera zoom bands (aligned with docs/MAP_SYSTEM_DESIGN.md §4.2, scaled for THEATER_SCALE canvas).
const STRATEGIC_MAX_ZOOM: float = 0.55
const OPERATIONAL_MAX_ZOOM: float = 1.22
const TACTICAL_MIN_ZOOM: float = 0.8 / MapCanvasConfig.THEATER_SCALE


static func read_camera_zoom(viewport: Viewport) -> float:
	if viewport == null:
		return 1.0
	var cam := viewport.get_camera_2d()
	if cam == null:
		return 1.0
	return maxf(cam.zoom.x, cam.zoom.y)


static func tier_for_zoom(z: float) -> Tier:
	if z <= STRATEGIC_MAX_ZOOM:
		return Tier.STRATEGIC
	if z <= OPERATIONAL_MAX_ZOOM:
		return Tier.OPERATIONAL
	return Tier.TACTICAL


static func tier_name(t: Tier) -> String:
	match t:
		Tier.STRATEGIC:
			return "strategic"
		Tier.OPERATIONAL:
			return "operational"
		Tier.TACTICAL:
			return "tactical"
		_:
			return "unknown"


static func show_nation_labels(t: Tier) -> bool:
	return t == Tier.STRATEGIC or t == Tier.OPERATIONAL


static func show_region_labels(t: Tier) -> bool:
	return t == Tier.OPERATIONAL


static func show_province_labels(t: Tier) -> bool:
	return t == Tier.TACTICAL


static func show_country_borders(t: Tier) -> bool:
	return true


static func show_province_glyphs(t: Tier) -> bool:
	return t == Tier.TACTICAL


static func use_batched_mesh_fills(t: Tier) -> bool:
	return t == Tier.STRATEGIC


static func label_alpha_for_tier(t: Tier, kind: String) -> float:
	match kind:
		"nation":
			return 0.92 if t == Tier.STRATEGIC else 0.78
		"region":
			return 0.88
		"province":
			return 0.94
		_:
			return 0.85
