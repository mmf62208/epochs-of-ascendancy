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


## Stream 2: V3-style state names only on states mapmode at operational zoom.
static func show_state_labels(t: Tier, map_mode: String = "") -> bool:
	var m := map_mode.strip_edges().to_lower()
	if m != "states":
		return false
	return t == Tier.OPERATIONAL


static func state_label_font_px(t: Tier) -> int:
	match t:
		Tier.OPERATIONAL:
			return 15
		Tier.TACTICAL:
			return 13
		_:
			return 12


static func show_province_labels(t: Tier) -> bool:
	return t == Tier.TACTICAL


static func show_country_borders(t: Tier) -> bool:
	return true


static func show_province_hover_detail(t: Tier) -> bool:
	return t == Tier.TACTICAL


static func show_compact_hover_tooltip(t: Tier) -> bool:
	return t == Tier.OPERATIONAL


static func show_strategic_hover_tooltip(t: Tier) -> bool:
	return t == Tier.STRATEGIC


static func country_border_width(t: Tier) -> float:
	## International frontiers only (dark). Slightly thicker so Maginot/GER-FRA reads at a glance.
	match t:
		Tier.STRATEGIC:
			return 4.2
		Tier.OPERATIONAL:
			return 3.4
		_:
			return 2.8


static func country_border_alpha(t: Tier) -> float:
	match t:
		Tier.STRATEGIC:
			return 0.98
		Tier.OPERATIONAL:
			return 0.95
		_:
			return 0.92


static func coast_border_width(t: Tier) -> float:
	match t:
		Tier.STRATEGIC:
			return 1.4
		Tier.OPERATIONAL:
			return 1.2
		_:
			return 1.0


## Subtle same-owner province edges — tactical only (avoids NUTS spiderweb at operational).
static func show_province_internal_borders(t: Tier) -> bool:
	return t == Tier.TACTICAL


static func province_internal_border_width(t: Tier) -> float:
	if t != Tier.TACTICAL:
		return 0.0
	return 0.9


## Unit / OOB map counters (DemoUnitIcon pins).
## Master off hides all. Strategic hides chips so capitals/fronts stay clickable.
## Operational+ = full chips (pin-first pick when visible).
static func show_unit_counters(t: Tier, master_enabled: bool = true) -> bool:
	if not master_enabled:
		return false
	return t != Tier.STRATEGIC


static func unit_counter_compact(t: Tier) -> bool:
	return t == Tier.STRATEGIC


static func unit_counter_min_zoom() -> float:
	## Full-chip band starts just above strategic (chips culled at world zoom).
	return STRATEGIC_MAX_ZOOM + 0.02


static func show_province_glyphs(t: Tier) -> bool:
	return t == Tier.TACTICAL


static func use_batched_mesh_fills(t: Tier) -> bool:
	return t == Tier.STRATEGIC


## World boards (≥2200): prefer batched fills at strategic AND operational zoom.
## Small boards: strategic only (tactical never forced — per-poly detail wins).
static func use_batched_mesh_fills_for_board(t: Tier, province_count: int) -> bool:
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return t == Tier.STRATEGIC or t == Tier.OPERATIONAL
	return use_batched_mesh_fills(t)


static func use_viewport_culling(t: Tier) -> bool:
	return t == Tier.STRATEGIC


## High province counts (full-world ~1700+): cull off-screen at strategic AND operational zoom.
## Pure helper — unit-tested; MapRenderer passes live province_count.
const HIGH_PROVINCE_CULL_THRESHOLD: int = 800
## World-full boards (~2665): also cull at tactical so pan stays smooth when zoomed in.
const WORLD_BOARD_CULL_THRESHOLD: int = 2200
## GIS accurate hybrid (~5.5k post US merge / ~8k pre): tighter glyph caps for HOI-like KEY_I readability.
## Floor 5000 so post-merge world_accurate (~5670) still uses dense-board budgets.
## Post full RoW sparse merge board is ~3.5k (was ~4.6k T1 / ~5.6k post-US / ~8.7k raw).
const ACCURATE_BOARD_CULL_THRESHOLD: int = 3000


static func use_viewport_culling_for_board(t: Tier, province_count: int) -> bool:
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		# All tiers — world_full pan/zoom path
		return true
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return t == Tier.STRATEGIC or t == Tier.OPERATIONAL
	return use_viewport_culling(t)


## Margin scale for get_provinces_in_rect when board is large (more neighbors at edges).
## World boards use a slightly larger margin so pan does not pop edge provinces mid-frame.
static func cull_rect_margin_px(province_count: int) -> float:
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 192.0
	if province_count >= 1500:
		return 140.0
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return 110.0
	return 96.0


## Cap dense overlay redraws on huge boards (resource glyphs / non-critical markers).
## World boards keep a tighter budget so pan/zoom stays smooth at 2665.
## Uses MapPolishFormatters.resource_icon_budget when available (live pilot path).
static func max_resource_icons_for_board(province_count: int, zoom: float = 0.5) -> int:
	if true:
		return int(MapPolishFormatters.resource_icon_budget(zoom, province_count))
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 180
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return 360
	return 9999


## Max province name labels drawn in tactical zoom on large boards (viewport-culled further).
static func max_province_labels_for_board(province_count: int) -> int:
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 140
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return 220
	return 9999


## City marker / hub glyph min zoom on world boards.
## Dense GIS boards hide cities until operational zoom so strategic view stays clean (plan A3).
static func city_marker_min_zoom_for_board(province_count: int) -> float:
	if province_count >= ACCURATE_BOARD_CULL_THRESHOLD:
		return 0.58
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 0.48
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return 0.55
	return 0.70


## Factories / airfields / ports (sites layer) — require deeper zoom than cities on dense boards.
static func site_marker_min_zoom_for_board(province_count: int) -> float:
	if province_count >= ACCURATE_BOARD_CULL_THRESHOLD:
		return 0.62
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 0.42
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return 0.38
	return 0.32

static func show_minimap_political_dots(t: Tier) -> bool:
	return t == Tier.STRATEGIC


## Pass 24: munitions depot pip density / radius by map LOD.
static func munitions_pip_max_count(t: Tier) -> int:
	match t:
		Tier.STRATEGIC:
			return 16
		Tier.OPERATIONAL:
			return 28
		_:
			return 48


static func munitions_pip_radius(t: Tier) -> float:
	match t:
		Tier.STRATEGIC:
			return 2.4
		Tier.OPERATIONAL:
			return 1.9
		_:
			return 1.55


## At strategic zoom, prefer low-fill (critical) depots first.
static func munitions_pip_prefer_critical(t: Tier) -> bool:
	return t == Tier.STRATEGIC


static func show_minimap_munitions_detail(t: Tier) -> bool:
	## Urgency ticks / extra chrome only operational+tactical.
	return t != Tier.STRATEGIC


static func nation_label_font_px(t: Tier) -> int:
	match t:
		Tier.STRATEGIC:
			return 26
		Tier.OPERATIONAL:
			return 20
		_:
			return 16


static func region_label_font_px(t: Tier) -> int:
	match t:
		Tier.OPERATIONAL:
			return 18
		_:
			return 14


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


## Phase 2/3 gap-closure — overlay budgets + lower-vert far zoom for ~60 fps mid hardware.
static func max_overlay_icons_for_board(province_count: int, zoom: float = 0.5) -> int:
	var base := max_resource_icons_for_board(province_count, zoom)
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		if zoom <= STRATEGIC_MAX_ZOOM:
			return mini(base, 64)
		if zoom <= OPERATIONAL_MAX_ZOOM:
			return mini(base, 96)
		return mini(base, 128)
	return base


static func max_battle_markers_for_board(province_count: int) -> int:
	if province_count >= ACCURATE_BOARD_CULL_THRESHOLD:
		return 28
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 36
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return 56
	return 80


static func max_flow_routes_for_board(province_count: int) -> int:
	if province_count >= ACCURATE_BOARD_CULL_THRESHOLD:
		return 16
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 24
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return 36
	return 48


## EquipmentFlow glyph LOD policy (CP3 paint polish) — pure, unit-testable.
## strategic: few aggregated corridor glyphs · operational: discrete · tactical: denser discrete.
static func equipment_flow_glyph_policy(t: Tier) -> Dictionary:
	match t:
		Tier.STRATEGIC:
			return {
				"tier": "strategic",
				"show": true,
				"max_glyphs": 8,
				"aggregate": true,
				"style": "corridor",
				"draw_corridor_lines": true,
				"glyph_scale": 0.85,
			}
		Tier.OPERATIONAL:
			return {
				"tier": "operational",
				"show": true,
				"max_glyphs": 18,
				"aggregate": false,
				"style": "discrete",
				"draw_corridor_lines": true,
				"glyph_scale": 1.0,
			}
		_:
			return {
				"tier": "tactical",
				"show": true,
				"max_glyphs": 32,
				"aggregate": false,
				"style": "discrete",
				"draw_corridor_lines": false,
				"glyph_scale": 1.15,
			}


static func equipment_flow_glyph_policy_for_name(tier_name_s: String) -> Dictionary:
	var n := tier_name_s.strip_edges().to_lower()
	if n == "strategic":
		return equipment_flow_glyph_policy(Tier.STRATEGIC)
	if n == "operational":
		return equipment_flow_glyph_policy(Tier.OPERATIONAL)
	return equipment_flow_glyph_policy(Tier.TACTICAL)


static func max_equipment_flow_glyphs_for_board(t: Tier, province_count: int) -> int:
	var pol: Dictionary = equipment_flow_glyph_policy(t)
	var base := int(pol.get("max_glyphs", 12))
	# Dense GIS board: keep KEY_I legible (fewer discrete glyphs, corridor bias at strategic).
	if province_count >= ACCURATE_BOARD_CULL_THRESHOLD:
		return maxi(3, int(base * 0.45))
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return maxi(4, int(base * 0.65))
	if province_count >= HIGH_PROVINCE_CULL_THRESHOLD:
		return maxi(6, int(base * 0.85))
	return base


## Lower-vert fallback: skip dense province glyphs / labels when far zoomed on huge boards.
static func use_lower_vert_fallback(t: Tier, province_count: int) -> bool:
	if province_count < HIGH_PROVINCE_CULL_THRESHOLD:
		return false
	return t == Tier.STRATEGIC or (province_count >= WORLD_BOARD_CULL_THRESHOLD and t == Tier.OPERATIONAL)


## Soft GPU pan/zoom target: frame budget ms for MapRendererPerf hotspot gating.
static func target_frame_ms_mid_hardware() -> float:
	return 16.67  # 60 fps


static func overlay_draw_stride(t: Tier, province_count: int) -> int:
	## Process-frame stride for animated overlays (flow arrows, battle pulse).
	if province_count >= WORLD_BOARD_CULL_THRESHOLD:
		return 4 if t == Tier.STRATEGIC else 3
	return 2
