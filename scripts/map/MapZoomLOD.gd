# scripts/map/MapZoomLOD.gd
## Vic3 / EU4 / HOI4-style zoom tiers for map political readability.
class_name MapZoomLOD
extends RefCounted

enum Tier { STRATEGIC, OPERATIONAL, TACTICAL }

# Camera zoom bands (aligned with docs/MAP_SYSTEM_DESIGN.md §4.2, scaled for THEATER_SCALE canvas).
const STRATEGIC_MAX_ZOOM: float = 0.55
# Europe Home frame (~Berlin+Paris+Rome) lands ~1.3; keep that as operational so
# states names and first-session LOD match the human Europe view (not tactical).
const OPERATIONAL_MAX_ZOOM: float = 1.55
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


## Shore ink in screen pixels. World width is this / camera zoom so Europe
## Home (~0.318) still shows a coast. Same-owner ProvEdge_ stays tactical-only.
const COAST_SCREEN_PX := 4.5

static func coast_border_width_for_zoom(zoom: float) -> float:
	var z := zoom
	if not is_finite(z):
		z = 1.0
	return COAST_SCREEN_PX / maxf(z, 0.04)


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
##
## Europe Home (Berlin+Paris+Rome + pad) lands ~0.33 on 720p and ~0.49 on 1080p —
## that is ≤ STRATEGIC_MAX 0.55, so tier_for_zoom calls Home "strategic". World
## fit is ~0.09–0.14. Do not widen the general strategic tier (labels/hover/mesh);
## counters use EUROPE_HOME_COUNTER_MIN_ZOOM so Begin GER → Home still paints.
const EUROPE_HOME_COUNTER_MIN_ZOOM: float = 0.24


static func show_unit_counters(t: Tier, master_enabled: bool = true) -> bool:
	if not master_enabled:
		return false
	return t != Tier.STRATEGIC


## Zoom-based chip paint. Home band is above this floor even when the LOD tier
## is still strategic. World Shift+Home stays culled.
static func show_unit_counters_for_zoom(z: float, master_enabled: bool = true) -> bool:
	if not master_enabled:
		return false
	if z > EUROPE_HOME_COUNTER_MIN_ZOOM:
		return true
	return show_unit_counters(tier_for_zoom(z), true)


static func unit_counter_compact(t: Tier) -> bool:
	return t == Tier.STRATEGIC


static func unit_counter_min_zoom() -> float:
	## Full-chip band starts at Europe Home, not world-fit strategic.
	return EUROPE_HOME_COUNTER_MIN_ZOOM


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
			return 36
		Tier.OPERATIONAL:
			return 28
		_:
			return 16


## First-session country-name screen size. Labels stay world-space Controls
## (Camera2D multiplies the raster). Size via font_size / zoom — never node.scale.
## Mid ~0.776 is the Play Home-adjacent wheel-in that used to smear "Germany".
const NATION_LABEL_EUROPE_ZOOM: float = 0.40
const NATION_LABEL_MID_ZOOM: float = 0.776
const NATION_LABEL_CLOSE_ZOOM: float = 1.80
const NATION_LABEL_FADE_START_ZOOM: float = 0.82
const NATION_LABEL_HIDE_ZOOM: float = 0.98
## City end-labels (Köln/Bonn/Leverkusen) appear at 1.50 — nation names must be gone.
const NATION_LABEL_CITY_LABEL_ZOOM: float = 1.50
const NATION_LABEL_EUROPE_HEIGHT_FRAC: float = 0.032
const NATION_LABEL_MID_HEIGHT_FRAC: float = 0.026
const NATION_LABEL_FONT_PX_MIN: int = 10
const NATION_LABEL_FONT_PX_MAX: int = 96


static func nation_label_target_frac_of_height(z: float) -> float:
	var zz := maxf(z, 0.01)
	if zz <= NATION_LABEL_EUROPE_ZOOM:
		return NATION_LABEL_EUROPE_HEIGHT_FRAC
	if zz >= NATION_LABEL_HIDE_ZOOM:
		return 0.0
	if zz <= NATION_LABEL_MID_ZOOM:
		var span_mid := maxf(NATION_LABEL_MID_ZOOM - NATION_LABEL_EUROPE_ZOOM, 0.01)
		var t_mid := clampf((zz - NATION_LABEL_EUROPE_ZOOM) / span_mid, 0.0, 1.0)
		return lerpf(NATION_LABEL_EUROPE_HEIGHT_FRAC, NATION_LABEL_MID_HEIGHT_FRAC, t_mid)
	# Fade band (0.82–0.98): hold mid on-screen size. Alpha fades separately.
	return NATION_LABEL_MID_HEIGHT_FRAC


static func nation_label_hidden_for_camera(z: float) -> bool:
	return z >= NATION_LABEL_HIDE_ZOOM or z >= NATION_LABEL_CITY_LABEL_ZOOM


static func nation_label_alpha_for_camera(z: float) -> float:
	if nation_label_hidden_for_camera(z):
		return 0.0
	if z < NATION_LABEL_FADE_START_ZOOM:
		return 0.96
	var span := maxf(NATION_LABEL_HIDE_ZOOM - NATION_LABEL_FADE_START_ZOOM, 0.01)
	var t := clampf((z - NATION_LABEL_FADE_START_ZOOM) / span, 0.0, 1.0)
	return clampf(0.96 * (1.0 - t), 0.0, 0.96)


## Font px such that font_px * camera.zoom == target screen px (node.scale stays 1).
## Oversamples when zoomed out so the camera shrinks a larger raster — not a magnified one.
static func nation_label_font_px_for_camera(z: float, viewport_h: float) -> int:
	var frac := nation_label_target_frac_of_height(z)
	var target := frac * maxf(viewport_h, 1.0)
	if target <= 0.5 or nation_label_hidden_for_camera(z):
		return 0
	var font_px := int(round(target / maxf(z, 0.08)))
	return clampi(font_px, NATION_LABEL_FONT_PX_MIN, NATION_LABEL_FONT_PX_MAX)


static func nation_label_effective_screen_px(font_px: int, z: float, node_scale: float) -> float:
	return float(maxi(font_px, 0)) * maxf(z, 0.0) * maxf(node_scale, 0.0)


static func nation_label_height_ratio(font_px: int, z: float, node_scale: float, viewport_h: float) -> float:
	var h := maxf(viewport_h, 1.0)
	return nation_label_effective_screen_px(font_px, z, node_scale) / h


## Magnifying a texture: camera.zoom * node.scale > 1 blows up a smaller raster.
static func nation_label_is_texture_magnified(font_px: int, z: float, node_scale: float) -> bool:
	if font_px <= 0:
		return false
	var effective := nation_label_effective_screen_px(font_px, z, node_scale)
	if effective <= 0.5:
		return false
	return effective > float(font_px) + 0.75 or node_scale > 1.02


static func region_label_font_px(t: Tier) -> int:
	match t:
		Tier.OPERATIONAL:
			return 18
		_:
			return 14


static func label_alpha_for_tier(t: Tier, kind: String) -> float:
	match kind:
		"nation":
			return 0.96
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
