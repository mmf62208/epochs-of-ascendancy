# scripts/map/MapRenderer.gd
class_name MapRenderer
extends Node2D

#region Exports
@export var container: Node2D
@export var info_panel: Panel
@export var info_name: Label
@export var info_owner: Label
@export var info_population: Label
@export var info_terrain: Label
@export var info_factories: Label
@export var info_dev: Label
@export var info_resources: Label
@export var info_core: Label
@export var info_special: Label
@export var info_logistics: Label
@export var info_combat: Label
@export var info_modifiers: RichTextLabel
@export var info_national: Label
@export var btn_national_spirits: Button
@export var btn_close: Button

# Dynamically created infrastructure investment UI (MVP — matches engineers button pattern)
var _btn_invest_infra: Button = null
var _label_invest_status: Label = null
var _progress_invest: ProgressBar = null
var _btn_cancel_invest: Button = null
var _label_invest_modifiers: Label = null  # breakdown of engineer/tech/stability/sabotage for active project + current levels always visible

# Dynamically created Special Sites section in InfoPanel
var _label_special_sites_header: Label = null
var _special_sites_container: VBoxContainer = null

# Direct action button for inspector (enhancement for clicked/selected province interactivity per Phase 2)
var _btn_settle: Button = null
var _btn_assign_agent: Button = null

# Preloaded for event/riot map visuals (wired from new assets; used in riot markers + tints for active_riots provinces)
var _riot_icon_tex: Texture2D = null
# NATO sheet for variants (based on nation tag or era/tech for majors/researched units; uses AtlasTexture subregions for variety without splitting files)
var _nato_sheet_tex: Texture2D = null

#region Terrain / readability (fill characterization layered under overlays)
## Cohesion: terrain strength, `terrain_tone_close_zoom_multiplier`, and `development_close_zoom_multiplier`
## all key off `terrain_zoom_near_thresh` (map container scale). Labels/glyphs use `province_detail_min_zoom`
## for visibility — intentionally separate gates (detail vs characterization).
## RGB multiplier applied after political coloring so terrain reads at a glance without hiding ownership.
@export_range(0.0, 0.35, 0.01) var terrain_tone_strength: float = 0.145
## Terrain reads more strongly when zoomed out (province fills can otherwise look homogeneous).
@export_range(1.0, 1.4, 0.02) var terrain_tone_far_zoom_boost: float = 1.24
## Slightly tame terrain modulation when zoomed fully in so overlays dominate.
@export_range(0.82, 1.0, 0.01) var terrain_tone_near_zoom_factor: float = 0.94
@export_range(0.06, 0.45, 0.02) var terrain_zoom_far_thresh: float = 0.24
@export_range(0.7, 2.5, 0.05) var terrain_zoom_near_thresh: float = 1.22
## As scale enters tactical zoom (`terrain_zoom_near_thresh`), ease terrain modulation toward × this — smooth ramp (see `_tactical_character_blend`; ~88–100% thresh band).
@export_range(0.78, 1.0, 0.01) var terrain_tone_close_zoom_multiplier: float = 0.93
# LOD fade thresholds for V (veg) and S (snow ref) layers match world_map_layers.yaml lod section for clean parchment at close zoom (main snow via WeatherOverlay dynamic). See set_layer_alphas and _update zoom bucket.
## Extra brighten toward developed provinces (normalized ~0–9 gameplay band).
@export_range(0.0, 0.12, 0.005) var development_visual_lighten: float = 0.058
## Very subtle warmth on high-development land (paired with lighten; keeps overlays legible).
@export_range(0.0, 0.09, 0.005) var development_visual_warmth: float = 0.028
## How strongly sea provinces blend toward deep water vs trace political hue.
@export_range(0.05, 0.55, 0.01) var sea_political_trace: float = 0.26
## With Supply overlay (L), pull terrain/dev characterization back toward political color before depot tint —
## keeps reds/greens/teals readable and avoids muddy stacking.
@export_range(0.34, 1.0, 0.02) var supply_overlay_base_character_blend: float = 0.78
## How strongly depot health tints province fills while L is on (political→terrain/dev applied first).
@export_range(0.18, 0.52, 0.01) var supply_depot_fill_blend: float = 0.34
## Extra outline thickness for province name labels when L is visible (helps on tinted fills).
@export_range(0, 5, 1) var province_name_outline_boost_supply_overlay: int = 2
## Regenerate province fill colors when `abs(container.scale)` crosses this width (same units as drift below).
## Typical play ~0.15–6 scale → ~20–40 repaints across the zoom range at default 0.05.
@export_range(0.028, 0.11, 0.002) var fill_zoom_bucket_size: float = 0.05
## Repaint once drift inside the current bucket exceeds `fill_zoom_bucket_size * this` (avoids stale tone while zoom lerps).
@export_range(0.22, 0.58, 0.02) var fill_zoom_intra_bucket_drift: float = 0.38
## Towards tactical zoom (`terrain_zoom_near_thresh`), ease dev lighten/warmth toward this × full strength (smooth ramp).
@export_range(0.82, 1.0, 0.01) var development_close_zoom_multiplier: float = 0.91
#endregion

#region Province names (visible at lower zoom when enabled)
@export var show_province_names: bool = true
@export var province_name_font_size: int = 11
@export var province_name_color: Color = Color(1, 1, 1, 0.85)
#endregion

#region Hover name
@export var show_hover_province_name: bool = true
@export var hover_name_follow_mouse: bool = false
#endregion

#region Feature markers
## --- Map canvas stacking (ProvinceContainers scale; typical z values, low → high) ---
## -1  ConflictOverlayLayer (fills under provinces)
##  0  `Prov_*` Polygon2D + `Z_MAP_GLYPH*` Labels (8 / 10 with L), then compare/hover/select Line2D (11–16),
##     then supply/engineer Line2D (`Z_SUPPLY` 20; `trade_transit` glow at 19). Trade corridor **rings** match
##     soft amber underlay in `SupplyMapLayer` (`OUTLINE_TRADE_TRANSIT`).
##  6  AgentNetworkLayer
## ~58 Military + trade **polylines** (`supply_route_layer_z_order`; `SupplyMapLayer` draws trade first, thinner).
## 82/100 Floating province **name** Labels (higher index while L held — `province_name_label_z_index*`).
@export var feature_icon_ring_radius: float = 28.0
@export var province_detail_min_zoom: float = MapCanvasConfig.PROVINCE_DETAIL_MIN_ZOOM
## Keep name labels above drawn supply/trade polylines (see `SupplyMapLayer`).
@export_range(30, 140, 2) var province_name_label_z_index: int = 82
@export_range(40, 160, 2) var province_name_label_z_index_supply_overlay: int = 100
## Polylines layer z (under name labels, above default province fills at 0).
@export_range(12, 90, 2) var supply_route_layer_z_order: int = 58
## Gentle dim for route lines while L is on so fills + rings win the first read.
@export_range(0.55, 1.0, 0.02) var supply_route_layer_modulate_with_overlay: float = 0.91
## Additional alpha scale for trade corridor polylines only while L is on (secondary logistics read).
@export_range(0.72, 1.0, 0.02) var trade_corridor_supply_overlay_dim: float = 0.86
#endregion

#region Debug
@export var debug_draw_province_centroids: bool = false
#endregion

#region Camera Controls
@export var pan_speed: float = 900.0
@export var edge_scroll_speed: float = 1100.0
@export var edge_margin: float = 50.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.15
@export var max_zoom: float = MapCanvasConfig.MAX_CAMERA_ZOOM
@export var middle_mouse_pan_speed: float = 1.0
@export var enable_map_wrap: bool = true
@export var fill_viewport_on_load: bool = true
@export var viewport_fill_ratio: float = MapCanvasConfig.VIEWPORT_FILL_RATIO
#endregion

#region Picking (MapPickGrid integration)
## Recommended production configuration for 250+ provinces (pure spatial, zero Area2D overhead):
##   use_spatial_picking = true
##   create_area_nodes_for_fallback = false
##
## In this mode:
## - No Area2D nodes are created at render time.
## - Hover is handled exclusively by _update_spatial_hover() polling MapPickGrid.
## - Clicks are handled by the unhandled_input spatial path.
## - All visuals (outlines, fills, etc.) continue to work on the province node via ProvinceMapVisuals.
## This is the intended long-term default for performance and simplicity.
@export var use_spatial_picking: bool = true
@export var create_area_nodes_for_fallback: bool = false
#endregion

@export var show_coarse_territory_overlays: bool = false  # Invisible hit regions for world pan; no grey boxes on map.

const GRAND_THEATER_CANONICAL_BOUNDS: Rect2 = MapCanvasConfig.GRAND_THEATER_BOUNDS  # Legacy 5000×2000 @ MapCanvasConfig.THEATER_SCALE (1.2) for Europe tactical headroom.
const WORLD_CANONICAL_BOUNDS: Rect2 = MapCanvasConfig.WORLD_CANONICAL_BOUNDS  # Full world canvas scaled to match theater (8192×4096 @ 1.2).
const UI_TOP_BAR_CLEARANCE := 84.0
const UI_MAP_TOOLBAR_HEIGHT := 56.0

const COUNTRY_BORDER_COLOR := Color(0.03, 0.03, 0.05, 0.92)
const COUNTRY_BORDER_WIDTH := 3.8
const COUNTRY_FRONTIER_PREFIX := "CountryFrontier_"
const _EDGE_KEY_PRECISION := 1.0

## Toggle for separate terrain layer (the high-res detailed raster bg image). When OFF: clean political view (solid ownership fills, no terrain texture underneath) — highly valued in grand strat (HOI4/EU4 players often prefer political/clean for readability of borders/infra/ownership; use terrain mode for combat planning/immersion). Perfect for map editing at close zoom too.
var show_terrain_layer: bool = true

var _is_middle_dragging := false
var _middle_drag_start := Vector2.ZERO
var _last_mouse_pos := Vector2.ZERO

var provinces: Dictionary[int, Province] = {}
var geometry: Dictionary = {}
var countries: Dictionary[String, Variant] = {}
var adjacency: AdjacencySystem

var province_nodes: Dictionary[int, Node2D] = {}
var province_centroids: Dictionary[int, Vector2] = {}
var _province_name_labels: Dictionary[int, Label] = {}
var current_hover: Node2D = null
var _hover_province: Province = null
var hover_tooltip: ProvinceHoverTooltip = null

var selected_province_id: int = -1
var _hover_outline_province_id: int = -1
var _compare_preview_province_id: int = -1
var _outline_pulse_phase: float = 0.0
var _last_zoom: float = 1.0
var _hover_fill_province_id: int = -1
var _current_theater_bounds: Rect2 = GRAND_THEATER_CANONICAL_BOUNDS  # updated on theater/chunk/world load; used for camera clamp to avoid gray lost space on pan/zoom to NA etc.

# Coarse world territories for clickable "regions" when on full world grand/stitched view.
# Provides "territory you can click to get into" for non-Europe areas (Africa, Aus, E Asia etc.) even without detailed province polys.
# These are large strategic level for grand strategy scroll feel + future expansion (detailed gen per continent).
# Visible as faint overlays, only prominent or always in world mode. Clicking sets "territory" selection + info.
var _coarse_territories: Dictionary = {}  # negative id -> { "name": String, "rect": Rect2, "display_name": String, "desc": String }
var _coarse_container: Node2D = null
var _selected_coarse_id: int = 0  # 0 none, negative for coarse terr id
var _theater_print_count: int = 0  # for throttling auto theater print spam during playtest pan/zoom
var _active_theater_id: String = ""
var _active_chunk_index: int = -1
var _last_lod_band: int = -1
var _theater_debounce_left: float = 0.0
var _pending_theater_update: bool = false
var _last_theater_cam_pos: Vector2 = Vector2(-99999.0, -99999.0)
var _full_map_refresh_scheduled: bool = false
const THEATER_DEBOUNCE_SEC := 0.35
const CHUNK_LOAD_ZOOM_MIN := 2.4  # Avoid expensive chunk texture swaps during normal Europe playtest zoom.
const ZOOM_THEATER_THRESHOLD := 0.12

const _HOVER_FILL_TINT := Color(0.5, 0.82, 1.0, 1.0)
const _COMPARE_FILL_TINT := Color(1.0, 0.72, 0.32, 1.0)
const _CANDIDATE_FILL_TINT := ProvinceMapVisuals.FILL_COMPARE_CANDIDATE
const _CONFLICT_FILL_TINT := ProvinceMapVisuals.FILL_CONFLICT
const _AGENT_FILL_TINT := ProvinceMapVisuals.FILL_AGENT

var _supply_role_by_province: Dictionary[int, String] = {}
var _compare_candidate_ids: Array[int] = []
var _supply_legend_panel: PanelContainer = null
var _compare_hint_label: Label = null
var _legend_tracked_year: int = -1
var _legend_tracked_month: int = -1
var _legend_tracked_day: int = -1
var _map_time_pulse_bbcode: String = ""
var _map_time_pulse_kind: String = ""
var _map_time_pulse_until_msec: int = 0
var _engineer_assign_flash_by_province: Dictionary[int, Dictionary] = {}
const _ENGINEER_ASSIGN_FLASH_MS := 2400
var _engineer_deploy_pick_index: int = 0
var debug_combat_attacker_province_id: int = -1
## Player-selected province to launch assaults from (Ctrl+click enemy to attack).
var attack_staging_province_id: int = -1

## Phase 4: last combat outcome details (settlement_def_bonus used, winner, capture) for inspector append + richer toasts/logs after real assaults (map/F10).
var _last_combat_outcome_text: String = ""

var _btn_attack: Button = null
var border_layer: Node2D = null
var _political_labels_layer: Node2D = null
var _region_highlight_layer: Node2D = null
var _map_lod_tier: int = 0  # MapZoomLOD.Tier.STRATEGIC

#region Supply overlay
@export var supply_overlay_panel: SupplyMenuPanel
var supply_map_layer: SupplyMapLayer = null
var supply_mode: bool = false
var _supply_reroute_active: bool = false
var _supply_overlay_legend: RichTextLabel = null
#endregion

const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")
const MapPoliticalLabelsLayerScript = preload("res://scripts/map/MapPoliticalLabelsLayer.gd")
const MapRegionHighlightLayerScript = preload("res://scripts/map/MapRegionHighlightLayer.gd")
const META_MAP_GLYPH_PX := &"_map_glyph_px"
const META_MAP_GLYPH_CAPITAL := &"_map_glyph_capital"
const META_MAP_GLYPH_OFFS := &"_map_glyph_offs"
var _zoom_fill_characterization_scale: float = 1.0
var _fill_color_zoom_bucket: int = -2000000000
var _fill_zoom_at_last_paint: float = -10.0
var _last_detail_zoom: float = -1.0
var _last_hover_mouse: Vector2 = Vector2(-99999, -99999)
var _last_viewport_cull_pos: Vector2 = Vector2(-99999, -99999)
var _last_viewport_cull_zoom: float = -1.0
var _viewport_culling_active: bool = false

#region Conflict overlay
@export var show_conflict_overlay: bool = true
var _conflict_layer: ConflictOverlayLayer = null
#endregion

#region Agent network overlay
@export var show_agent_overlay: bool = true
var _agent_layer: AgentNetworkLayer = null
#endregion

var weather_layer: Node = null  # WeatherOverlayLayer when present (grand high-res snow/blackout etc.)
var terrain_layer_stack: TerrainLayerStack = null  # NASA/NE real-world layers when built
var _world_class_bootstrapped: bool = false

var _btn_station_engineers: Button = null

# Demo map tint mode for strain (welfare) / vitality (settlement) / development re-tint layers (wired from DebugOverlay / hotkeys F1-F4).
# "supply" handled via the L overlay toggle (existing supply layer) but exposable as mode.
var debug_tint_mode: String = ""  # "", "vitality", "strain", "development", "loyalty", "infra"  -- boosts the corresponding tint/characterize layer for basic mapmode-style views. Use set_map_mode().
var current_map_mode: String = "political"  # "political" | "strain" | "vitality" | "development" | "supply" | "loyalty" | "infra"  (Phase 2 map UX; loyalty/foreign_mil%, infra/road density using built_* + layers; builds on prior mapmodes+inspector)

var _map_mode_toolbar: PanelContainer = null
var _info_panel_dragging: bool = false
var _info_panel_drag_offset: Vector2 = Vector2.ZERO
var _map_minimap: PanelContainer = null
var _map_search: HBoxContainer = null
var _adjacency_preview: Node2D = null
var _province_mesh_layer: Node2D = null
## Phase E: batched political fills at strategic zoom (fewer per-poly tint updates).
const BATCHED_MESH_ZOOM_MAX := 0.55
var _batched_mesh_fills_prefer: bool = true
var _batched_mesh_fills_forced: bool = false
var _batched_mesh_active: bool = false
var _map_mode_apply_scheduled: bool = false
var _last_mesh_zoom_bucket: int = -999


func _ready():
	add_to_group("map_renderer")
	_wire_info_panel_refs()
	if btn_close == null:
		btn_close = get_node_or_null("UI/InfoPanel/BtnClose") as Button

	if btn_close:
		btn_close.text = "Close"
		btn_close.tooltip_text = "Close province inspector"
		if not btn_close.pressed.is_connected(_on_close_pressed):
			btn_close.pressed.connect(_on_close_pressed)
	else:
		push_warning("MapRenderer: Could not find BtnClose!")

	if container == null:
		container = get_node_or_null("ProvinceContainers") as Node2D

	if _riot_icon_tex == null:
		_riot_icon_tex = load("res://assets/graphics/icons/events/riot_crowd_64.png") as Texture2D
		if _riot_icon_tex == null:
			_riot_icon_tex = load("res://assets/graphics/icons/events/riot_marker_32.png") as Texture2D  # fallback new generated
	if _nato_sheet_tex == null:
		_nato_sheet_tex = load("res://assets/graphics/units/nato_counters_sheet.png") as Texture2D
		if _nato_sheet_tex == null:
			_nato_sheet_tex = load("res://assets/graphics/units/nato_counters_1930s.png") as Texture2D

	var cam := get_node_or_null("MapCamera") as Camera2D
	if cam:
		cam.make_current()
		print("✅ Camera2D activated")
		# Early default view for world class: Europe area of the stitched world, but allow full pan/scroll (bounds set above).
		# This ensures something is visible immediately on graphical launch, no black.
		cam.position = MapCanvasConfig.europe_center()
		cam.zoom = Vector2.ONE * MapCanvasConfig.DEFAULT_CAMERA_ZOOM
	else:
		push_warning("MapRenderer: MapCamera node missing!")

	var cam_input := get_node_or_null("CameraInput") as CameraController
	if cam_input:
		# MapRenderer drives MapCamera pan/zoom; avoid duplicate ProvinceContainers nudging.
		cam_input.enable_wasd = false
		cam_input.enable_pan = false
		cam_input.enable_edge_pan = false
		cam_input.enable_zoom = false
		cam_input.set_wrap_bounds(_current_theater_bounds)

	# Connect infra signals for live inspector project progress and layer updates (playability).
	call_deferred("_connect_infra_signals_for_inspector")
	call_deferred("_setup_player_map_ux")

	# Setup coarse world territories (hidden by default; shown on world grand load for full stitched scroll + clickable regions outside Europe detailed).
	# Addresses "not every province/region on the map has a territory you can click to get into" for the world base.
	call_deferred("_setup_coarse_world_territories", false)

	# WORLD CLASS DEFAULT: Prioritize full stitched world grand underlay for grand strategy scrollable feel (world map with all continents, mountains on Africa/Aus/EAsia etc from elevation layers).
	# Europe detailed phase1 polys will overlay on the Europe portion of the world bg (coords aligned via generator).
	# This ensures a visible, scrollable world-class map on launch even if high-res europe fails.
	# Heavy loads deferred; always guarantee a fallback texture synchronously so NEVER black screen.
	var init_bg := get_node_or_null("WorldBackground") as Sprite2D
	if init_bg:
		init_bg.visible = true
		init_bg.centered = false
		# Try world clean first (lighter, stitched full world for class place).
		var tex := load("res://assets/maps/layers/world_grand_theater_clean.png") as Texture2D
		if tex == null:
			tex = load("res://assets/maps/world_grand_theater_ultra_high.jpg") as Texture2D
		if tex == null:
			tex = load("res://assets/maps/world_grand_theater_ultra_high.png") as Texture2D
		# Fallback to europe detailed for close zoom if world not available.
		if tex == null:
			tex = load("res://assets/maps/europe_grand_theater_ultra_high.jpg") as Texture2D
		if tex == null:
			tex = load("res://assets/maps/europe_grand_theater_ultra_high.png") as Texture2D
		if tex == null:
			tex = load("res://assets/maps/layers/europe_grand_theater_clean.png") as Texture2D
		if tex == null:
			tex = load("res://assets/maps/layers/world_base_stylized.png") as Texture2D
		if tex:
			init_bg.texture = tex
			init_bg.visible = true
			init_bg.modulate = Color(0.95, 0.93, 0.88, 0.95)
			if init_bg.texture:
				init_bg.texture_filter = 2
			# For world class, use full world bounds for scroll/pan.
			if "world" in str(tex.resource_path).to_lower() or "grand_theater_clean" in str(tex.resource_path).to_lower():
				_current_theater_bounds = WORLD_CANONICAL_BOUNDS
				init_bg.position = WORLD_CANONICAL_BOUNDS.position
				var tw := float(tex.get_width())
				var th := float(tex.get_height())
				if tw > 0 and th > 0:
					init_bg.scale = Vector2(WORLD_CANONICAL_BOUNDS.size.x / tw, WORLD_CANONICAL_BOUNDS.size.y / th)
				print("MapRenderer: WORLD CLASS stitched grand underlay set as default (full scrollable world map base). Europe polys overlay detailed area. Use F10 chunks or zoom for other continents (mountains via H layer).")
				set_meta("full_world_underlay_active", true)
				# Show coarse territories immediately (ALWAYS enabled in world view) for clickable regions on other continents (Africa/Aus/EAsia/NA/SAm etc). World class: every area has territory you can click.
				_setup_coarse_world_territories(true)
				# Full-world elevation + rivers load in bootstrap_world_class_map (TestRunner); chunk swaps on zoom via F10/harness.
				call_deferred("_clamp_camera_to_theater")
				call_deferred("center_europe_in_world_view")
			else:
				# europe fallback
				_current_theater_bounds = GRAND_THEATER_CANONICAL_BOUNDS
				init_bg.position = Vector2.ZERO
				var tw := float(tex.get_width())
				var th := float(tex.get_height())
				if tw > 0 and th > 0:
					init_bg.scale = Vector2(GRAND_THEATER_CANONICAL_BOUNDS.size.x / tw, GRAND_THEATER_CANONICAL_BOUNDS.size.y / th)
				print("MapRenderer: Default stylized grand theater map set (", "HIGH QUALITY LARGER 8K+ version for close zoom" if "ultra_high" in str(tex.resource_path).to_lower() else "high quality", " - detailed colorized, replaces old map)")
				if fill_viewport_on_load:
					call_deferred("fit_camera_to_bounds", GRAND_THEATER_CANONICAL_BOUNDS, MapCanvasConfig.europe_center(), MapCanvasConfig.EUROPE_VIEW_FILL_RATIO)
			_suppress_old_background_maps()
			call_deferred("_fit_background_to_bounds")
		else:
			# Ultimate fallback: use the scene default world_map.png (guaranteed in tscn) + bright to NEVER black, polys will tint over it.
			var fallback_tex := load("res://assets/maps/world_map.png") as Texture2D
			if fallback_tex:
				init_bg.texture = fallback_tex
				init_bg.visible = true
				init_bg.modulate = Color(0.8, 0.85, 0.7, 0.9)  # light to show polys
				init_bg.centered = false
				_current_theater_bounds = WORLD_CANONICAL_BOUNDS
				var tw := float(fallback_tex.get_width())
				var th := float(fallback_tex.get_height())
				if tw > 0 and th > 0:
					init_bg.scale = Vector2(WORLD_CANONICAL_BOUNDS.size.x / tw, WORLD_CANONICAL_BOUNDS.size.y / th)
				print("MapRenderer: FALLBACK world_map base (light) — map polys will render over it. Load world grand for full class.")
			else:
				init_bg.texture = null
				init_bg.modulate = Color(0.3, 0.35, 0.25, 1.0)
				init_bg.scale = Vector2(1,1)
				init_bg.position = Vector2.ZERO
				_current_theater_bounds = WORLD_CANONICAL_BOUNDS
				print("MapRenderer: FALLBACK solid bg (no textures) — map polys will still render.")
		# Hide underlying to avoid grey bleed
		var pm := find_child("ProvinceMap", true, false) as Sprite2D
		if pm:
			pm.visible = false
			pm.texture = null
			pm.modulate = Color(0,0,0,0)
		_suppress_old_background_maps()
		# Early force for polys container to be visible (in case scale/pos from other code). Polys will get colors from later scenario refresh.
		if container:
			container.visible = true

	_setup_hover_tooltip()
	_setup_inspector_extras()
	_connect_time_manager_signals()
	_connect_map_manager_signals()
	_connect_trade_manager_signals_for_map_layers()
	_init_legend_calendar_tracking()
	set_process(true)
	print("MapRenderer _ready() completed")


func _init_legend_calendar_tracking() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	_legend_tracked_year = TimeManager.get_current_year()
	_legend_tracked_month = TimeManager.get_current_month()
	_legend_tracked_day = TimeManager.get_current_day()


func _connect_map_manager_signals() -> void:
	if typeof(MapManager) == TYPE_NIL:
		return
	if not MapManager.province_data_changed.is_connected(_on_map_province_data_changed):
		MapManager.province_data_changed.connect(_on_map_province_data_changed)


func _on_map_province_data_changed(province_id: int, what: String) -> void:
	if what not in ["effects", "development", "infrastructure", "owner", "controller", "all", "infrastructure_project", "settlement", "welfare", "policy", "burden"]:
		return
	if provinces.has(province_id):
		_refresh_single_province_fill(province_id)
		# If the info panel is open on this province, refresh the investment section live
		if _is_info_panel_visible():
			show_info_panel(provinces[province_id])
	if _hover_fill_province_id == province_id:
		_apply_hover_fill(province_id, true)
	if what in ["owner", "controller", "all"]:
		if typeof(MapManager) != TYPE_NIL:
			var live: Province = MapManager.get_province(province_id)
			if live != null and provinces.has(province_id):
				provinces[province_id].owner_tag = live.owner_tag
				provinces[province_id].controller_tag = live.controller_tag
		_update_country_borders()
		_rebuild_province_mesh_layer()
	_update_riot_markers()  # live update for riot ignition/spread in monthly (even if no explicit data_changed for riot, force on owner events + full)


func _connect_trade_manager_signals_for_map_layers() -> void:
	## Lightweight map refresh when TradeFlows get real routes — avoids stale polylines / rings.
	if typeof(TradeManager) == TYPE_NIL:
		return
	if not TradeManager.trade_flow_created.is_connected(_on_trade_flow_supply_map_refresh):
		TradeManager.trade_flow_created.connect(_on_trade_flow_supply_map_refresh)
	if not TradeManager.trade_flow_rerouted.is_connected(_on_trade_flow_map_rerouted):
		TradeManager.trade_flow_rerouted.connect(_on_trade_flow_map_rerouted)
	if not TradeManager.trade_flow_suspended.is_connected(_on_trade_flow_map_suspended):
		TradeManager.trade_flow_suspended.connect(_on_trade_flow_map_suspended)
	if not TradeManager.trade_flow_interdicted.is_connected(_on_trade_flow_map_interdicted):
		TradeManager.trade_flow_interdicted.connect(_on_trade_flow_map_interdicted)


func _on_trade_flow_supply_map_refresh(
	flow_id: String, from: String, to: String, _itype: String, _qty: float,
) -> void:
	_try_refresh_trade_supply_map_layers()
	_maybe_toast_player_trade_route_event("activated", flow_id, from, to, "")


func _on_trade_flow_map_rerouted(flow_id: String, _new_plan_id: String) -> void:
	_try_refresh_trade_supply_map_layers()
	var flow := TradeManager.get_trade_flow(flow_id) if typeof(TradeManager) != TYPE_NIL else null
	if flow != null:
		_maybe_toast_player_trade_route_event("rerouted", flow_id, flow.from_tag, flow.to_tag, "")


func _on_trade_flow_map_suspended(flow_id: String, reason: String) -> void:
	_try_refresh_trade_supply_map_layers()
	var flow := TradeManager.get_trade_flow(flow_id) if typeof(TradeManager) != TYPE_NIL else null
	if flow == null:
		return
	## Interdict→suspend is already announced by TradeManager for meaningful losses; avoid double toasts.
	if reason.strip_edges().begins_with("interdicted_"):
		return
	_maybe_toast_player_trade_route_event("suspended", flow_id, flow.from_tag, flow.to_tag, reason)


## Refresh polylines / rings when convoy risk or throughput changes (no extra toast — TradeManager toasts big hits).
func _on_trade_flow_map_interdicted(
	_flow_id: String, _interdictor_type: String, _loss_fraction: float, _metadata: Dictionary,
) -> void:
	_try_refresh_trade_supply_map_layers()


func _try_refresh_trade_supply_map_layers() -> void:
	if not is_inside_tree():
		return
	_refresh_supply_routes()
	if supply_mode:
		_refresh_supply_highlights()
		_update_supply_legend_text()
	if _hover_province != null and hover_tooltip != null and hover_tooltip.visible:
		_refresh_hover_tooltip(_hover_province)


## Optional feedback when trade geometry changes — skips noise for spectators.
func _maybe_toast_player_trade_route_event(
	kind: String,
	_flow_id: String,
	from: String,
	to: String,
	detail: String = "",
) -> void:
	if typeof(LeaderEventUI) == TYPE_NIL or not LeaderEventUI.has_method("show_toast"):
		return
	var p := _player_tag().strip_edges().to_upper()
	var a := from.strip_edges().to_upper()
	var b := to.strip_edges().to_upper()
	if p.is_empty() or (p != a and p != b):
		return
	var pair := "%s ↔ %s" % [a, b]
	var msg := ""
	match kind:
		"suspended":
			msg = "Trade corridor paused — %s" % pair
			if not detail.is_empty():
				msg += " · %s" % detail
		"rerouted":
			msg = "Trade corridor updated — %s" % pair
		_:
			msg = "Trade corridor on map — %s (L overlay)" % pair
	LeaderEventUI.show_toast(msg, 2.6)


func _show_map_layer_toast(message: String) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(message, 2.8)
	else:
		print("MapRenderer: ", message)


func _connect_time_manager_signals() -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	if not TimeManager.game_day_advanced.is_connected(_on_game_day_advanced_legend):
		TimeManager.game_day_advanced.connect(_on_game_day_advanced_legend)
	if not TimeManager.game_month_advanced.is_connected(_on_time_advanced_refresh_legend):
		TimeManager.game_month_advanced.connect(_on_time_advanced_refresh_legend)
	if not TimeManager.game_year_advanced.is_connected(_on_time_advanced_refresh_legend):
		TimeManager.game_year_advanced.connect(_on_time_advanced_refresh_legend)


func _on_game_day_advanced_legend(year: int, month: int, day: int) -> void:
	if _legend_tracked_day < 0:
		_legend_tracked_day = day
		_legend_tracked_month = month
		_legend_tracked_year = year
		return
	if day != _legend_tracked_day or month != _legend_tracked_month or year != _legend_tracked_year:
		_try_set_map_time_pulse(
			GameDateDisplay.build_map_time_pulse_bbcode("day", year, month, day),
			"day",
			2200,
		)
	_legend_tracked_day = day
	_legend_tracked_month = month
	_legend_tracked_year = year
	_refresh_province_fill_colors()
	_refresh_map_time_ui()


func _on_time_advanced_refresh_legend(_a: Variant = null, _b: Variant = null) -> void:
	_note_time_boundary_for_legend(_b != null)
	_refresh_map_time_ui()


func _note_time_boundary_for_legend(is_month_signal: bool) -> void:
	if typeof(TimeManager) == TYPE_NIL:
		return
	var cur_y := TimeManager.get_current_year()
	var cur_m := TimeManager.get_current_month()
	var cur_d := TimeManager.get_current_day()
	if _legend_tracked_year < 0:
		_legend_tracked_year = cur_y
		_legend_tracked_month = cur_m
		_legend_tracked_day = cur_d
		return
	if cur_y > _legend_tracked_year:
		_try_set_map_time_pulse(
			GameDateDisplay.build_map_time_pulse_bbcode("year", cur_y, cur_m, cur_d),
			"year",
			5000,
		)
	elif is_month_signal and cur_m != _legend_tracked_month:
		_try_set_map_time_pulse(
			GameDateDisplay.build_map_time_pulse_bbcode("month", cur_y, cur_m, cur_d),
			"month",
			5000,
		)
	_legend_tracked_year = cur_y
	_legend_tracked_month = cur_m
	_legend_tracked_day = cur_d


func _try_set_map_time_pulse(bbcode: String, kind: String, duration_msec: int) -> void:
	if bbcode.is_empty():
		return
	var new_prio := GameDateDisplay.time_pulse_priority(kind)
	if not _map_time_pulse_bbcode.is_empty() and Time.get_ticks_msec() <= _map_time_pulse_until_msec:
		var cur_prio := GameDateDisplay.time_pulse_priority(_map_time_pulse_kind)
		if cur_prio >= new_prio:
			return
	_map_time_pulse_bbcode = bbcode
	_map_time_pulse_kind = kind
	_map_time_pulse_until_msec = Time.get_ticks_msec() + duration_msec


func _refresh_map_time_ui() -> void:
	if supply_mode:
		_update_supply_legend_text()
	if _hover_province != null and hover_tooltip != null and hover_tooltip.visible:
		_refresh_hover_tooltip(_hover_province)


func _get_active_map_time_pulse_bbcode() -> String:
	if _map_time_pulse_bbcode.is_empty():
		return ""
	if Time.get_ticks_msec() > _map_time_pulse_until_msec:
		return ""
	return _map_time_pulse_bbcode


func _expire_map_time_pulse_if_needed() -> void:
	if _map_time_pulse_bbcode.is_empty():
		return
	if Time.get_ticks_msec() <= _map_time_pulse_until_msec:
		return
	_map_time_pulse_bbcode = ""
	_map_time_pulse_kind = ""
	if supply_mode:
		_update_supply_legend_text()


func _is_info_panel_visible() -> bool:
	return info_panel != null and info_panel is CanvasItem and info_panel.visible

func _wire_info_panel_refs() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		push_warning("MapRenderer: UI CanvasLayer missing — province inspector unavailable")
		return
	if info_panel == null:
		info_panel = ui.get_node_or_null("InfoPanel") as Panel
		if info_panel != null and not (info_panel is CanvasItem):
			push_warning("MapRenderer: info_panel wired to non-CanvasItem (type=" + str(info_panel.get_class()) + ", script=" + str(info_panel.get_script()) + ") — likely bad NodePath in scene or wiring. Inspector visible access will be skipped.")
			info_panel = null
	if info_name == null:
		info_name = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelName") as Label
	if info_owner == null:
		info_owner = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelOwner") as Label
	if info_population == null:
		info_population = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelPopulation") as Label
	if info_terrain == null:
		info_terrain = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelTerrain") as Label
	if info_factories == null:
		info_factories = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelFactories") as Label
	if info_dev == null:
		info_dev = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelDev") as Label
	if info_resources == null:
		info_resources = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelResources") as Label
	if info_core == null:
		info_core = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelCore") as Label
	if info_special == null:
		info_special = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelSpecial") as Label
	if info_logistics == null:
		info_logistics = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelLogistics") as Label
	if info_combat == null:
		info_combat = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelCombat") as Label
	if info_modifiers == null:
		info_modifiers = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/RichTextModifiers") as RichTextLabel
	if info_national == null:
		info_national = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent/LabelNationalHeader") as Label
	if btn_national_spirits == null:
		btn_national_spirits = ui.get_node_or_null("InfoPanel/BtnNationalSpirits") as Button
	if btn_close == null:
		btn_close = ui.get_node_or_null("InfoPanel/BtnClose") as Button

	# Force labels to wrap inside the panel box width (text comes down) and fill so they use the full inspector size.
	for lbl in [info_name, info_owner, info_population, info_terrain, info_factories, info_dev, info_resources, info_core, info_special, info_logistics, info_combat, info_national]:
		if lbl != null:
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if info_modifiers != null:
		info_modifiers.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _setup_inspector_extras() -> void:
	if btn_national_spirits and not btn_national_spirits.pressed.is_connected(_on_open_national_spirits_pressed):
		btn_national_spirits.pressed.connect(_on_open_national_spirits_pressed)
	if info_modifiers == null:
		info_modifiers = get_node_or_null("UI/InfoPanel/InfoScroll/InfoContent/RichTextModifiers") as RichTextLabel
	if info_national == null:
		info_national = get_node_or_null("UI/InfoPanel/InfoScroll/InfoContent/LabelNationalHeader") as Label
	if info_modifiers:
		info_modifiers.bbcode_enabled = true
		info_modifiers.fit_content = true
		info_modifiers.scroll_active = true
		info_modifiers.custom_minimum_size = Vector2(420, 160)
		info_modifiers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if btn_national_spirits == null:
		btn_national_spirits = get_node_or_null("UI/InfoPanel/BtnNationalSpirits") as Button
		if btn_national_spirits and not btn_national_spirits.pressed.is_connected(_on_open_national_spirits_pressed):
			btn_national_spirits.pressed.connect(_on_open_national_spirits_pressed)
	_ensure_station_engineers_button()
	_ensure_attack_button()
	_ensure_settle_button()


func _setup_hover_tooltip() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	hover_tooltip = ProvinceHoverTooltip.new()
	hover_tooltip.name = "ProvinceHoverTooltip"
	ui.add_child(hover_tooltip)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_toward_mouse(1.0 + zoom_speed)
			_refresh_terrain_zoom_aware()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_toward_mouse(1.0 - zoom_speed)
			_refresh_terrain_zoom_aware()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			_toggle_supply_overlay()
			get_viewport().set_input_as_handled()
			return

		# Demo toggles for new dynamic infra layers (roads/rails/cities/sites) - makes map come alive with player builds.
		# R/T/C/Y or F10 DebugOverlay buttons. Sites layer shows vector runways/docks for airfields/ports.
		if event.keycode == KEY_R:
			var ol := get_overlay_layer("InfrastructureOverlayLayer")
			if ol and ol.has_method("toggle_roads"):
				ol.toggle_roads()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_T:  # T for rails (R taken)
			var ol := get_overlay_layer("InfrastructureOverlayLayer")
			if ol and ol.has_method("toggle_rails"):
				ol.toggle_rails()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_C:
			var ol := get_overlay_layer("InfrastructureOverlayLayer")
			if ol and ol.has_method("toggle_cities"):
				ol.toggle_cities()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Y:  # Y for "Yards / special sites" (airfields, ports, etc.)
			var ol := get_overlay_layer("InfrastructureOverlayLayer")
			if ol and ol.has_method("toggle_sites"):
				ol.toggle_sites()
			get_viewport().set_input_as_handled()
			return

		# Real-world terrain sub-layers (U/H/V) when TerrainLayerStack is loaded.
		# Default view is clean high-quality parchment + rivers + directional hills + coast (world-class readable).
		# V reveals the very faint optional vegetation tint layer (pastel, low alpha, toggleable, zoom-friendly in future).
		if event.keycode == KEY_U and terrain_layer_stack:
			terrain_layer_stack.toggle_rivers()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_H and terrain_layer_stack:
			terrain_layer_stack.toggle_elevation()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_V and terrain_layer_stack:
			terrain_layer_stack.toggle_vegetation()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_S and terrain_layer_stack:  # S = persistent peak snow (NASA/DEM mask; seasonal snow via WeatherOverlay)
			terrain_layer_stack.toggle_snow_mask()
			var on := terrain_layer_stack.is_snow_mask_user_visible() if terrain_layer_stack.has_method("is_snow_mask_user_visible") else false
			_show_map_layer_toast("Peak snow (persistent): %s — Alps/Himalayas/Arctic; seasonal snow via weather later" % ("ON" if on else "OFF"))
			get_viewport().set_input_as_handled()
			return

		# Basic mapmode hotkeys (F1-F5) for Phase 2 map UX depth on 460-prov test map.
		# F1=political (default clean), F2=strain (welfare), F3=vitality (settlement), F4=development (dev lighten), F5=supply (L layer).
		# Uses existing characterize / supply / dev code paths. Toasts via DebugOverlay. Zero interference with normal play (F-keys debug-only intent).
		if event.keycode == KEY_F1:
			set_map_mode("political")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			set_map_mode("strain")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F3:
			set_map_mode("vitality")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F4:
			set_map_mode("development")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5:
			set_map_mode("supply")
			get_viewport().set_input_as_handled()
			return
		# F6/F7 for Phase 2 map UX additions (loyalty/foreign_mil tint, infra/road density using built_road/rail + layers)
		if event.keycode == KEY_F6:
			set_map_mode("loyalty")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F7:
			set_map_mode("infra")
			get_viewport().set_input_as_handled()
			return
		# Debug world chunk load for portion testing (Ctrl+0..3 loads the 4 ~4k x 2k chunks of the full world source).
		# Keeps province/terrain/snow_potential/region data from active scenario (europe full set), just swaps visual underlay + per-chunk elev/veg/snow ref layers for H/V/S.
		# Useful to verify chunk snow bits, alignment, etc while Europe work continues.
		if event.ctrl_pressed and event.keycode >= KEY_0 and event.keycode <= KEY_3:
			var ci: int = event.keycode - KEY_0
			load_world_chunk_underlay(ci)
			get_viewport().set_input_as_handled()
			return

	# Spatial picking click handling — this path makes the system fully functional
	# even when create_area_nodes_for_fallback=false (pure MapPickGrid mode, zero Area2D nodes).
	if use_spatial_picking and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos := _screen_to_world(get_viewport().get_mouse_position())
		var pid := -1
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
			pid = MapManager.get_province_at_world_pos(world_pos, true)
		if pid > 10000:
			# Demo virtual child vid -> map to parent for real province data/selection (log proves child was hit via override in manager)
			print(" [DEMO PICK NORMALIZE] hit virtual child vid=", pid, " -> parent ", (pid / 1000), " for selection/inspector (child poly pick test succeeded)")
			pid = pid / 1000
		if pid < 0 or not provinces.has(pid):
			# Coarse world territory fallback: when no detailed province (e.g. panned to Africa/Aus/E Asia on stitched world grand), hit large strategic region for "click to get into".
			# Gives grand strategy world map the feel that every area has a clickable territory/region, even if detailed provs are Europe-focused for current scenario.
			var ctid := _hit_coarse_territory(world_pos)
			if ctid != 0:
				_show_coarse_territory_info(ctid)
				get_viewport().set_input_as_handled()
				return
		if pid >= 0 and provinces.has(pid):
			_selected_coarse_id = 0  # clear any coarse when detailed province selected
			var resolved_province: Province = provinces[pid] as Province
			var resolved_node: Node2D = _province_node(pid)
			if event is InputEventMouseButton and event.ctrl_pressed:
				if _try_execute_province_attack(pid, resolved_province):
					get_viewport().set_input_as_handled()
					return
			if event is InputEventMouseButton and event.shift_pressed:
				if typeof(DebugOverlay) != TYPE_NIL and DebugOverlay.is_map_debug_tools_active():
					if selected_province_id >= 0 and adjacency != null and adjacency.are_adjacent(pid, selected_province_id):
						debug_combat_attacker_province_id = pid
						attack_staging_province_id = pid
						DebugOverlay.toast_map_debug(
							"Attacker staging: %s (%d) → battle at selected %d"
							% [resolved_province.name, pid, selected_province_id]
						)
						get_viewport().set_input_as_handled()
						return
				if _try_station_engineers_at_province(resolved_province):
					get_viewport().set_input_as_handled()
					return
			if _try_set_attack_staging(resolved_province):
				pass  # still open inspector below
			if supply_mode and _handle_supply_province_click(resolved_province):
				_select_province(resolved_province, resolved_node)
				get_viewport().set_input_as_handled()
				return
			show_info_panel(resolved_province)
			_select_province(resolved_province, resolved_node)
			get_viewport().set_input_as_handled()
			return

	if use_spatial_picking and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if typeof(DebugOverlay) != TYPE_NIL and DebugOverlay.is_map_debug_tools_active():
			var world_pos_r := _screen_to_world(get_viewport().get_mouse_position())
			var pid_r := -1
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
				pid_r = MapManager.get_province_at_world_pos(world_pos_r, true)
			if pid_r > 10000:
				print(" [DEMO PICK NORMALIZE right] virtual child ", pid_r, " -> parent ", (pid_r / 1000))
				pid_r = pid_r / 1000
			if pid_r >= 0:
				debug_cycle_province_owner(pid_r)
				get_viewport().set_input_as_handled()
				return

	# Middle mouse drag start
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_middle_dragging = true
				_middle_drag_start = get_viewport().get_mouse_position()
				_last_mouse_pos = _middle_drag_start
			else:
				_is_middle_dragging = false


func _process(delta: float) -> void:
	_expire_map_time_pulse_if_needed()

	# Throttle fill/LOD work — every frame was costly during pan/zoom with 472 polys.
	if Engine.get_process_frames() % 2 == 0:
		_refresh_province_detail_visibility()

	if hover_tooltip and hover_tooltip.visible and _hover_province != null and hover_name_follow_mouse:
		_refresh_hover_tooltip(_hover_province)

	_handle_camera_input(delta)
	_outline_pulse_phase += delta * 4.5
	_update_outline_pulse()

	# Spatial picking integration (MapPickGrid via MapManager)
	if use_spatial_picking:
		_update_spatial_hover()

	# High value: auto theater/LOD/chunk from camera zoom/pos (drives "closer zoom options", portion loading).
	# High value: detect zoom change for auto theater/LOD swap (closer zooms, portion loading).
	var cam := get_viewport().get_camera_2d()
	if cam:
		var z := cam.zoom.x if cam.zoom else 1.0
		var p := cam.global_position
		var zoom_changed: bool = abs(z - _last_zoom) > ZOOM_THEATER_THRESHOLD
		var pan_changed: bool = false
		if z > 1.5:
			pan_changed = p.distance_to(_last_theater_cam_pos) > 400.0 / maxf(z, 0.2)
		if zoom_changed or pan_changed:
			if zoom_changed:
				_last_zoom = z
			if pan_changed:
				_last_theater_cam_pos = p
			_pending_theater_update = true
			_theater_debounce_left = THEATER_DEBOUNCE_SEC
			if zoom_changed:
				_sync_batched_mesh_fills(false)
	if _pending_theater_update:
		_theater_debounce_left -= delta
		if _theater_debounce_left <= 0.0:
			_pending_theater_update = false
			auto_update_theater_from_camera()
	if cam:
		_clamp_camera_to_theater()
	_sync_peak_snow_overlay()


func _mount_peak_snow_overlay() -> void:
	if terrain_layer_stack == null:
		return
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg == null or bg.texture == null:
		return
	if terrain_layer_stack.has_method("mount_peak_snow_on_map"):
		terrain_layer_stack.call("mount_peak_snow_on_map", self, bg, 8)


func _sync_peak_snow_overlay() -> void:
	if terrain_layer_stack == null or not terrain_layer_stack.show_snow_mask_layer:
		return
	if terrain_layer_stack.has_method("sync_peak_snow_transform"):
		terrain_layer_stack.sync_peak_snow_transform()


func _handle_camera_input(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var nav_delta := MapViewInput.motion_delta(delta)
	var move_dir := Vector2.ZERO

	# WASD / Arrow keys (simulation pause must not freeze map navigation)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move_dir.x += 1

	# Edge scrolling (including top strip over TopInfoBar — only block modals/panels)
	if not MapViewInput.edge_pan_blocked_by_gui(get_viewport()):
		var mouse_pos := get_viewport().get_mouse_position()
		var viewport_size := get_viewport().get_visible_rect().size

		if mouse_pos.x < edge_margin:              move_dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_margin: move_dir.x += 1
		if mouse_pos.y < edge_margin:              move_dir.y -= 1
		elif mouse_pos.y > viewport_size.y - edge_margin: move_dir.y += 1

	# Middle mouse drag (pixel-based — works while paused)
	if _is_middle_dragging:
		var current_mouse := get_viewport().get_mouse_position()
		var drag_delta := current_mouse - _last_mouse_pos
		cam.global_position -= drag_delta * middle_mouse_pan_speed / cam.zoom.x
		_last_mouse_pos = current_mouse
	_clamp_camera_to_theater()

	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		cam.global_position += move_dir * pan_speed * nav_delta / cam.zoom.x
		_clamp_camera_to_theater()


func _zoom_toward_mouse(zoom_change: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var mouse_screen := get_viewport().get_mouse_position()
	var old_zoom := cam.zoom

	var new_zoom := old_zoom * zoom_change
	new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
	new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)

	if new_zoom == old_zoom:
		return

	var world_before := cam.get_canvas_transform().affine_inverse() * mouse_screen
	cam.zoom = new_zoom
	var world_after := cam.get_canvas_transform().affine_inverse() * mouse_screen
	cam.global_position += world_before - world_after
	_clamp_camera_to_theater()

## Converts screen (pixel) mouse position to world/map space using the active Camera2D.
## This is the key bridge for using MapPickGrid / MapManager picking.
func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return screen_pos
	return cam.get_canvas_transform().affine_inverse() * screen_pos


func _on_close_pressed() -> void:
	hide_info_panel()


## Player-facing map UX: toolbar, minimap, search, adjacency preview, optional mesh layer.
func _setup_player_map_ux() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return

	if _map_mode_toolbar == null:
		var ToolbarScript := preload("res://scripts/ui/map/MapModeToolbar.gd")
		_map_mode_toolbar = PanelContainer.new()
		_map_mode_toolbar.set_script(ToolbarScript)
		_map_mode_toolbar.name = "MapModeToolbar"
		ui.add_child(_map_mode_toolbar)
		if _map_mode_toolbar.has_method("bind_map_renderer"):
			_map_mode_toolbar.call("bind_map_renderer", self)
		if _map_mode_toolbar.has_signal("layout_changed"):
			_map_mode_toolbar.layout_changed.connect(_layout_map_ui)

	if _map_search == null:
		var SearchScript := preload("res://scripts/ui/map/MapProvinceSearch.gd")
		_map_search = HBoxContainer.new()
		_map_search.set_script(SearchScript)
		_map_search.name = "MapProvinceSearch"
		ui.add_child(_map_search)
		var cam := get_node_or_null("MapCamera") as Camera2D
		if _map_search.has_method("bind"):
			_map_search.call("bind", self, cam)

	if _map_minimap == null:
		var MinimapScript := preload("res://scripts/ui/map/MapMinimap.gd")
		_map_minimap = PanelContainer.new()
		_map_minimap.set_script(MinimapScript)
		_map_minimap.name = "MapMinimap"
		_map_minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_map_minimap.offset_left = 12.0
		_map_minimap.offset_top = -120.0
		_map_minimap.offset_right = 200.0
		_map_minimap.offset_bottom = -12.0
		ui.add_child(_map_minimap)
		var cam2 := get_node_or_null("MapCamera") as Camera2D
		if _map_minimap.has_method("bind"):
			_map_minimap.call("bind", self, cam2)
		if _map_minimap.has_method("set_lod_tier"):
			_map_minimap.call("set_lod_tier", _map_lod_tier)

	if _adjacency_preview == null and container != null:
		var AdjScript := preload("res://scripts/map/AdjacencyPreviewLayer.gd")
		_adjacency_preview = Node2D.new()
		_adjacency_preview.set_script(AdjScript)
		_adjacency_preview.name = "AdjacencyPreviewLayer"
		_adjacency_preview.z_index = 75
		container.add_child(_adjacency_preview)

	# ProvinceMeshLayer created on demand via _ensure_province_mesh_layer() (Phase E batched fills)
	_layout_map_ui()
	_wire_info_panel_drag()
	var vp := get_viewport()
	if vp and not vp.size_changed.is_connected(_layout_map_ui):
		vp.size_changed.connect(_layout_map_ui)


func _layout_map_ui() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var top_clearance := UI_TOP_BAR_CLEARANCE
	if get_tree():
		var tib := TopInfoBar.find_in_tree(get_tree())
		if tib != null and tib.has_method("get_bar_height"):
			top_clearance = maxf(top_clearance, float(tib.call("get_bar_height")) + 4.0)
	var toolbar_h := UI_MAP_TOOLBAR_HEIGHT
	if _map_mode_toolbar != null and _map_mode_toolbar.has_method("get_panel_height"):
		toolbar_h = float(_map_mode_toolbar.call("get_panel_height"))
	var chrome_top := top_clearance + toolbar_h + 6.0

	if _map_mode_toolbar is Control:
		var tb := _map_mode_toolbar as Control
		tb.set_anchors_preset(Control.PRESET_TOP_LEFT)
		tb.offset_left = 8.0
		tb.offset_top = top_clearance
		tb.offset_right = minf(620.0, get_viewport().get_visible_rect().size.x - 16.0)
		tb.offset_bottom = top_clearance + toolbar_h

	if _map_search is Control:
		var sr := _map_search as Control
		sr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		sr.offset_left = -320.0
		sr.offset_top = chrome_top
		sr.offset_right = -12.0
		sr.offset_bottom = chrome_top + 32.0

	if info_panel is Control and not info_panel.has_meta("user_moved"):
		var ip := info_panel as Control
		ip.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ip.offset_left = 12.0
		ip.offset_top = chrome_top + 4.0
		ip.offset_right = 562.0
		ip.offset_bottom = ip.offset_top + 520.0


func _wire_info_panel_drag() -> void:
	if info_panel == null or not (info_panel is Control):
		return
	if info_panel.has_meta("drag_wired"):
		return
	info_panel.set_meta("drag_wired", true)
	info_panel.gui_input.connect(_on_info_panel_gui_input)


func _on_info_panel_gui_input(event: InputEvent) -> void:
	if info_panel == null or not (info_panel is Control):
		return
	var ip := info_panel as Control
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.position.y <= 34.0:
				_info_panel_dragging = true
				_info_panel_drag_offset = mb.position
				ip.set_meta("user_moved", true)
			else:
				_info_panel_dragging = false
	elif event is InputEventMouseMotion and _info_panel_dragging:
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _info_panel_drag_offset
		ip.offset_left += delta.x
		ip.offset_top += delta.y
		ip.offset_right += delta.x
		ip.offset_bottom += delta.y
		_info_panel_drag_offset = mm.position


func select_province_by_id(province_id: int) -> bool:
	return focus_province_by_id(province_id)


## Simple map mode toggle helper (demo for task): forces re-tint emphasizing strain/vitality/development.
func force_map_tint_demo(mode: String = "") -> void:
	set_map_mode(mode if mode in ["vitality", "strain", "development", "political", "supply", "loyalty", "infra"] else "")


## Sets basic mapmode-style visual layer/tint using existing characterize / supply layer / dev lighten code.
## Supports: "political" (default clean), "strain" (welfare), "vitality" (settlement), "development" (dev boost), "supply" (L overlay).
## Clear labels + toast guidance provided by callers (DebugOverlay). Emits refresh for live 460-prov updates.
func set_map_mode(mode: String = "political") -> void:
	var m := mode.strip_edges().to_lower()
	if not m in ["political", "strain", "vitality", "development", "supply", "loyalty", "infra"]:
		m = "political"
	if m == current_map_mode and m != "infra":
		return
	current_map_mode = m
	if m == "supply":
		if not supply_mode:
			_toggle_supply_overlay()
	elif supply_mode:
		_toggle_supply_overlay()
	# Infra mode: schedule async layer rebuild (sync rebuild of 472 provinces freezes the UI).
	if m == "infra":
		var ol := get_overlay_layer("InfrastructureOverlayLayer")
		if ol and ol.has_method("_schedule_rebuild_all_infra_layers"):
			ol.call("_schedule_rebuild_all_infra_layers")
		elif ol and ol.has_method("rebuild_all_infra_layers"):
			ol.call_deferred("rebuild_all_infra_layers")
		if ol and ol.has_method("set_show_roads"):
			ol.set_show_roads(true)
			ol.set_show_rails(true)
	debug_tint_mode = "strain" if m == "strain" else ("vitality" if m == "vitality" else ("development" if m == "development" else ("loyalty" if m == "loyalty" else ("infra" if m == "infra" else ("region_control" if m == "region_control" else "")))))
	if not _map_mode_apply_scheduled:
		_map_mode_apply_scheduled = true
		call_deferred("_apply_map_mode_visuals")


func _apply_map_mode_visuals() -> void:
	_map_mode_apply_scheduled = false
	var m := current_map_mode
	_refresh_province_fill_colors(true)
	if info_panel and info_panel is CanvasItem and info_panel.visible and selected_province_id >= 0 and provinces.has(selected_province_id):
		show_info_panel(provinces[selected_province_id])
	print("MapRenderer: map_mode set to '%s' (current_map_mode=%s, debug_tint_mode='%s')." % [m, current_map_mode, debug_tint_mode])
	if typeof(DebugOverlay) != TYPE_NIL:
		var mode_label := "Political (default)"
		if m == "strain": mode_label = "Strain (welfare)"
		elif m == "vitality": mode_label = "Vitality (settlement)"
		elif m == "development": mode_label = "Development (lighten)"
		elif m == "supply": mode_label = "Supply overlay"
		elif m == "loyalty": mode_label = "Loyalty (foreign mil % tint)"
		elif m == "infra": mode_label = "Infra/Road Density"
		DebugOverlay.toast_map_debug("Map mode: %s — %s" % [m, mode_label])
	# Do not force mesh rebuild on mode change — that rebuilds all province meshes synchronously and hangs.
	_sync_batched_mesh_fills(false)


func hide_info_panel() -> void:
	if info_panel and info_panel is CanvasItem:
		info_panel.visible = false
	elif info_panel != null:
		push_warning("MapRenderer: hide_info_panel called on non-CanvasItem (got " + str(info_panel.get_script() if info_panel.get_script() else info_panel.get_class()) + ")")
	_selected_coarse_id = 0
	_clear_selection()


func _refresh_province_detail_visibility() -> void:
	if container == null:
		return

	var current_zoom := _get_camera_zoom()
	var tier: int = MapZoomLODScript.tier_for_zoom(current_zoom)
	if tier != _map_lod_tier:
		_map_lod_tier = tier
		_sync_political_labels_tier(tier)
		if _region_highlight_layer != null and is_instance_valid(_region_highlight_layer):
			if _region_highlight_layer.has_method("sync_tier"):
				_region_highlight_layer.call("sync_tier", tier)
		_sync_hovered_strategic_region(_hover_province)
		_sync_border_lod(tier)
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_lod_tier"):
			_map_minimap.call("set_lod_tier", tier)
		if _hover_province != null:
			if MapZoomLODScript.show_province_hover_detail(tier):
				_apply_hover_visuals(_hover_province.id, true)
			elif _hover_outline_province_id >= 0:
				_apply_hover_visuals(_hover_outline_province_id, false)

	_sync_viewport_culling()
	var show_details: bool = MapZoomLODScript.show_province_glyphs(tier) or current_zoom > province_detail_min_zoom
	var show_prov_names: bool = show_province_names and MapZoomLODScript.show_province_labels(tier)
	_zoom_fill_characterization_scale = current_zoom
	# Bucket boundaries + drift are in the same space as `container.scale` length.
	var q := clampf(fill_zoom_bucket_size, 0.028, 0.14)
	var b := int(floor((current_zoom + 0.0001) / q))
	var bucket_changed := b != _fill_color_zoom_bucket
	var drift_frac := clampf(fill_zoom_intra_bucket_drift, 0.15, 0.65)
	var drift := (
		_fill_zoom_at_last_paint >= 0.0
		and absf(current_zoom - _fill_zoom_at_last_paint) >= q * drift_frac
	)
	if bucket_changed or drift:
		if bucket_changed:
			_fill_color_zoom_bucket = b
		_refresh_province_fill_colors()

	# LOD polish for real layers (V veg + S snow ref): auto-fade at close/tactical zoom for clean parchment default (as designed; subtle only when wanted or zoomed).
	# Main dynamic snow is still the WeatherOverlay veil (S is ref only).
	if terrain_layer_stack and terrain_layer_stack.has_method("set_layer_alphas"):
		var z := current_zoom
		var veg_a := clampf( (z - 0.4) / 1.0 , 0.15, 1.0)  # strong fade when zoomed in
		var snow_forced: bool = terrain_layer_stack.show_snow_mask_layer if terrain_layer_stack != null else false
		var snow_a := 0.82 if snow_forced else clampf( (z - 0.35) / 0.9 , 0.35, 1.0)
		terrain_layer_stack.call("set_layer_alphas", veg_a, snow_a)

	# Gate heavy per-frame glyph/name style + layout work (theme overrides, reset_size, positions).
	# Only re-apply when zoom meaningfully changes (or first time). This prevents constant CPU
	# on idle after load while keeping LOD correct on actual zoom/pan.
	var zoom_for_details := current_zoom
	var detail_delta := absf(zoom_for_details - _last_detail_zoom)
	var needs_detail_update := bucket_changed or drift or detail_delta > 0.003 or _last_detail_zoom < 0.0
	if needs_detail_update:
		_last_detail_zoom = zoom_for_details

	# For high-detail phase1 bg + roads overlay: fade in the detail layer on zoom for better province-level roads/buildings/cities visibility.
	var detail_layer := container.get_node_or_null("DetailOverlay") as Sprite2D
	if detail_layer and detail_layer.texture:
		var target_a := clampf( (current_zoom - 0.3) * 1.2 , 0.3, 0.95)
		detail_layer.modulate.a = target_a

		for id in _province_name_labels:
			var lbl: Variant = _province_name_labels[id]
			if lbl is Label and is_instance_valid(lbl):
				(lbl as Label).visible = show_prov_names and show_details
				if show_prov_names and show_details:
					var l2 := lbl as Label
					l2.z_index = _map_province_name_label_z_index()
					l2.add_theme_font_size_override("font_size", _scale_province_name_font(current_zoom, true))
					_apply_province_name_label_readability_styles(l2, current_zoom)

		for pid in province_nodes:
			var node: Variant = province_nodes[pid]
			if node is Node2D and is_instance_valid(node):
				for child in (node as Node2D).get_children():
					if child is Label and not (child as Label).has_meta(META_MAP_GLYPH_PX):
						(child as Label).visible = show_details
				_layout_zoomed_map_glyphs_for_province_node(int(pid), current_zoom, show_details)


## Smooth 0→1 ramp as map scale enters tactical band (relative to `terrain_zoom_near_thresh`).
func _tactical_character_blend(zoom_scale: float, band_start_frac: float, band_end_frac: float) -> float:
	var zn := maxf(terrain_zoom_near_thresh, 0.05)
	var span := zn * maxf(band_end_frac - band_start_frac, 0.03)
	var z0 := zn * band_start_frac
	var z1 := z0 + span
	var zz := maxf(zoom_scale, 0.02)
	var u := clampf(inverse_lerp(z0, z1, zz), 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func _province_name_outline_zoom_extra(zoom_metric: float) -> int:
	var zmt := zoom_metric
	if zmt <= province_detail_min_zoom:
		return 0
	return mini(2, int((zmt - province_detail_min_zoom) * 2.0))


## Shared smooth ramp + cap for province names and map glyphs so tactical zoom scales read as one system.
func _zoom_detail_scale_smooth(zoom_metric: float, cap: float = 1.8) -> float:
	var denom := maxf(province_detail_min_zoom, 0.05)
	var raw := clampf(zoom_metric / denom, 1.0, cap)
	var span := maxf(cap - 1.0, 0.001)
	var u := clampf((raw - 1.0) / span, 0.0, 1.0)
	var smooth_u := u * u * (3.0 - 2.0 * u)
	return lerpf(1.0, raw, smooth_u)


func _apply_province_name_label_readability_styles(
	label: Label,
	outline_zoom_hint: float = -1.0,
) -> void:
	var fc := province_name_color
	if supply_mode:
		fc.a = minf(0.92, fc.a + 0.035)
	label.add_theme_color_override("font_color", fc)
	var zz := outline_zoom_hint
	if zz <= 0.0001:
		zz = absf(container.scale.x) if container != null else 1.0
	var zex := _province_name_outline_zoom_extra(zz)
	var sup_boost := clampi(province_name_outline_boost_supply_overlay, 0, 5) if supply_mode else 0
	var ol_cap := 7 if supply_mode else 9
	var ol := clampi(3 + sup_boost + zex, 2, ol_cap)
	label.add_theme_constant_override("outline_size", ol)
	var oa := 0.72 if supply_mode else 0.62
	if zz >= province_detail_min_zoom * 1.05:
		oa = minf(0.82, oa + 0.038)
	if supply_mode and zz >= province_detail_min_zoom * 1.18:
		oa = maxf(0.62, oa - 0.048)
	elif (not supply_mode) and zz >= province_detail_min_zoom * 1.32:
		oa = maxf(0.64, oa - 0.035)
	label.add_theme_color_override("font_outline_color", Color(0.015, 0.035, 0.065, oa))
	var sh_a := 0.84 if supply_mode else 0.8
	if zz >= province_detail_min_zoom * 1.35:
		sh_a = clampf(sh_a - 0.045, 0.68, 0.88)
	var sh := Color(0, 0.03, 0.08, sh_a)
	label.add_theme_color_override("font_shadow_color", sh)
	label.add_theme_constant_override("shadow_offset_x", 2 if supply_mode else 1)
	label.add_theme_constant_override("shadow_offset_y", 2 if supply_mode else 1)


func _scale_province_name_font(current_zoom: float, for_visible_names: bool) -> int:
	if not for_visible_names:
		return province_name_font_size
	var z := _zoom_detail_scale_smooth(current_zoom, 1.8)
	return clampi(int(round(float(province_name_font_size) * z)), 9, 26)


func _apply_static_map_glyph_outline(lbl: Label) -> void:
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.065, 0.1, 0.62))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0.02, 0.06, 0.5))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)


func _layout_zoomed_map_glyphs_for_province_node(pid: int, zoom_metric: float, show_glyphs: bool) -> void:
	var node: Variant = province_nodes.get(pid)
	if node == null or not (node is Node2D):
		return
	var ctr: Vector2 = province_centroids.get(pid, Vector2.ZERO) as Vector2
	var nd := node as Node2D
	for child in nd.get_children():
		if child is Label and (child as Label).has_meta(META_MAP_GLYPH_PX):
			var lbl := child as Label
			var base_px := int(lbl.get_meta(META_MAP_GLYPH_PX))
			lbl.visible = show_glyphs
			if show_glyphs:
				var zsc := _zoom_detail_scale_smooth(zoom_metric, 1.8)
				var fs := clampi(int(round(float(base_px) * zsc)), maxi(8, base_px - 6), 40)
				lbl.add_theme_font_size_override("font_size", fs)
			else:
				lbl.add_theme_font_size_override("font_size", base_px)
			var gzx := 0
			if zoom_metric > province_detail_min_zoom:
				gzx = mini(2, int((zoom_metric - province_detail_min_zoom) * 2.2))
			var g_ol_max := 5 if supply_mode else 7
			var g_ol := clampi(2 + (2 if supply_mode else 0) + gzx, 1, g_ol_max)
			var goa := 0.71 if supply_mode else 0.62
			if zoom_metric >= province_detail_min_zoom * 1.08:
				goa = minf(0.88, goa + 0.065)
			if supply_mode and zoom_metric >= province_detail_min_zoom * 1.18:
				goa = maxf(0.58, goa - 0.065)
			elif (not supply_mode) and zoom_metric >= province_detail_min_zoom * 1.32:
				goa = maxf(0.58, goa - 0.04)
			var goa_cap := 0.78 if supply_mode else 0.88
			lbl.add_theme_color_override(
				"font_outline_color",
				Color(0.038, 0.06, 0.096, clampf(goa, 0.52, goa_cap)),
			)
			lbl.add_theme_constant_override("outline_size", g_ol)
			var g_glyph_a := clampf((0.94 if supply_mode else 0.90) + 0.025 * zoom_metric / maxf(province_detail_min_zoom, 0.08), 0.82, 0.97)
			lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, g_glyph_a))
			lbl.z_index = (
				ProvinceMapVisuals.Z_MAP_GLYPH_SUPPLY_OVERLAY
				if supply_mode
				else ProvinceMapVisuals.Z_MAP_GLYPH
			)
			lbl.reset_size()
			var ms := lbl.get_minimum_size()
			if lbl.has_meta(META_MAP_GLYPH_CAPITAL):
				lbl.position = ctr - ms * 0.5
			elif lbl.has_meta(META_MAP_GLYPH_OFFS):
				var ofs: Variant = lbl.get_meta(META_MAP_GLYPH_OFFS)
				if ofs is Vector2:
					lbl.position = ctr + ofs as Vector2 - ms * 0.5


func _terrain_tone_strength_for_current_zoom() -> float:
	var base := clampf(terrain_tone_strength, 0.0, 0.42)
	var z := maxf(_zoom_fill_characterization_scale, 0.07)
	var raw_t := clampf(
		inverse_lerp(terrain_zoom_near_thresh, terrain_zoom_far_thresh, z),
		0.0,
		1.0,
	)
	var t := raw_t * raw_t * (3.0 - 2.0 * raw_t)
	var mul := lerpf(terrain_tone_near_zoom_factor, terrain_tone_far_zoom_boost, t)
	var out := clampf(base * mul, 0.0, 0.48)
	var tactical_damp := _tactical_character_blend(z, 0.88, 1.0)
	var close_mul := clampf(terrain_tone_close_zoom_multiplier, 0.75, 1.0)
	out *= lerpf(1.0, close_mul, tactical_damp)
	return out


func initialize(p_provinces: Dictionary, p_geometry: Dictionary, p_adjacency: AdjacencySystem, p_countries: Dictionary = {}):
	provinces = MapScenarioData.coerce_provinces(p_provinces)
	geometry = p_geometry
	adjacency = p_adjacency
	countries = MapScenarioData.coerce_countries(p_countries)
	render_provinces()
	_fit_background_to_bounds()


func render_provinces():
	if container == null:
		push_error("MapRenderer: container not assigned")
		return

	var restore_pid := selected_province_id if info_panel != null and info_panel is CanvasItem and info_panel.visible else -1

	_clear_selection()
	# Preserve rasters and weather layer so map images (WorldBackground/ProvinceMap) and weather visuals survive the render clear and
	# continue to provide the underlay for polys + outlines (fixes "no map images, only outlines"). Weather layer is preserved like rasters.
	var raster_preserved: Dictionary = {}
	for child in container.get_children():
		if child.name in ["WorldBackground", "ProvinceMap", "WeatherOverlayLayer"]:
			raster_preserved[child.name] = child
			container.remove_child(child)
			continue
		child.queue_free()
	province_nodes.clear()
	province_centroids.clear()
	_province_name_labels.clear()

	print("Rendering map with %d provinces using Polygon2D..." % provinces.size())

	for id in provinces.keys():
		var province: Province = provinces[id]
		if not geometry.has(id):
			continue

		var geo = geometry[id]
		var node := _create_province_node(province, geo)
		container.add_child(node)
		province_nodes[id] = node

	# Re-attach any preserved rasters so the map image is present for the new polys.
	for rname in raster_preserved:
		var r = raster_preserved[rname]
		if r:
			container.add_child(r)
			r.name = rname

	# Ensure WorldBackground (the high-res terrain layer) draws first (under polys)
	var wb_re := container.get_node_or_null("WorldBackground") as Sprite2D
	if wb_re:
		container.move_child(wb_re, 0)

	# After re-attach, immediately suppress any old background map (e.g. ProvinceMap that could show grey underneath the stylized one)
	_suppress_old_background_maps()

	# Fit the (stylized grand) background to current bounds so the detailed map aligns properly on load/render.
	_fit_background_to_bounds()

	# Force the detailed raster underlay (grand theater) to be loaded/shown for this 460-prov slice.
	# This makes the raster (not just crude vector polys) the visible map base; polys stay at low alpha (0.06) for ownership/state tints.
	# Call is robust (idempotent inside) and helps when direct _ready loads were skipped or timing differed in graphical runs.
	call_deferred("apply_phase1_europe_background")

	# Extra: in grand mode, ensure polys use low fill so the detailed image (requested map) is the visible terrain, not a "grey map" from fills.
	# This is called here too for loads where render happens without full apply.
	if is_using_grand_stylized_map() or true:  # allow clean mode even on non-grand loads
		for id in province_nodes:
			var n = province_nodes[id]
			if n:
				for ch in n.get_children():
					if ch is Polygon2D:
						var c := (ch as Polygon2D).color
						c.a = 0.06 if show_terrain_layer else 0.82
						(ch as Polygon2D).color = c

	# Support for in-game ProvinceEditor (docs/PROVINCE_EDITOR_IN_GAME_DESIGN.md)
	# When active, the editor can request lower normal province visibility so the clean parchment base + new drawn borders are easier to see.
	var prov_editor := container.get_node_or_null("ProvinceEditor") as Node
	if prov_editor and prov_editor.has_method("is_active") and prov_editor.is_active():
		# Editor is drawing — we could further dim normal fills here if desired
		pass

	_fill_color_zoom_bucket = -2000000000
	_fill_zoom_at_last_paint = -10.0
	_refresh_province_detail_visibility()
	_setup_supply_layer()
	_setup_conflict_layer()
	_setup_agent_layer()
	_setup_infrastructure_overlay_layer()
	call_deferred("_setup_terrain_layer_stack")
	call_deferred("_setup_weather_overlay_layer")
	_refresh_supply_highlights()
	_update_compare_hint_label()
	print("✅ Map rendered with real polygons")

	if restore_pid >= 0 and provinces.has(restore_pid):
		var restored: Province = provinces[restore_pid] as Province
		var restored_node: Node2D = _province_node(restore_pid)
		if restored != null and restored_node != null:
			_select_province(restored, restored_node)
			show_info_panel(restored)

	# Sync MapPickGrid (via MapManager) after rendering for best picking accuracy
	if use_spatial_picking and typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("set_geometry_world_space"):
			MapManager.set_geometry_world_space(_is_world_canvas_active())
		if MapManager.has_method("sync_render_centroids"):
			MapManager.sync_render_centroids(province_centroids)
		if MapManager.has_method("rebuild_pick_grid"):
			MapManager.rebuild_pick_grid(MapCanvasConfig.PICK_GRID_CELL_SIZE)

	_update_country_borders()
	_sync_border_lod(_map_lod_tier)
	_rebuild_political_labels()
	_rebuild_region_highlight()
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("invalidate_political_cache"):
		_map_minimap.call("invalidate_political_cache")
	_update_unit_icons_for_test()  # demo: show generated NATO icons on provinces that have the test formations spawned in TestRunner/DebugOverlay loads
	call_deferred("_rebuild_province_mesh_layer")
	call_deferred("_sync_batched_mesh_fills", true)


# ====================== PHASE E: BATCHED MESH FILLS ======================

func set_batched_mesh_fills_forced(on: bool) -> void:
	_batched_mesh_fills_forced = on
	_sync_batched_mesh_fills(true)


func is_batched_mesh_fills_active() -> bool:
	return _batched_mesh_active


func get_batched_mesh_stats() -> Dictionary:
	if _province_mesh_layer != null and _province_mesh_layer.has_method("get_stats"):
		var stats: Dictionary = _province_mesh_layer.call("get_stats")
		stats["active"] = _batched_mesh_active
		stats["zoom"] = _get_camera_zoom()
		return stats
	return {"active": false, "polygons": 0, "buckets": 0, "zoom": _get_camera_zoom()}


func _ensure_province_mesh_layer() -> void:
	if _province_mesh_layer != null and is_instance_valid(_province_mesh_layer):
		return
	if container == null:
		return
	var MeshScript := preload("res://scripts/map/ProvinceMeshLayer.gd")
	_province_mesh_layer = Node2D.new()
	_province_mesh_layer.set_script(MeshScript)
	_province_mesh_layer.name = "ProvinceMeshLayer"
	_province_mesh_layer.z_index = -1
	container.add_child(_province_mesh_layer)
	container.move_child(_province_mesh_layer, mini(maxi(0, container.get_child_count() - 1), 1))
	if _province_mesh_layer.has_method("set_color_resolver"):
		_province_mesh_layer.call("set_color_resolver", Callable(self, "_mesh_color_for_owner_tag"))


func _mesh_color_for_owner_tag(tag: String) -> Color:
	if tag.is_empty() or not countries.has(tag):
		return Color(0.34, 0.34, 0.41, 0.86)
	var nation: Variant = countries[tag]
	if nation is Country:
		var c := (nation as Country).color
		c.a = 0.82
		return c
	if typeof(nation) == TYPE_DICTIONARY:
		var d: Dictionary = nation
		if d.has("color"):
			var cc := Color(String(d["color"]))
			cc.a = 0.82
			return cc
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_country_color"):
		var mc := MapManager.get_country_color(tag)
		mc.a = 0.82
		return mc
	return Color(0.34, 0.34, 0.41, 0.86)


func _rebuild_province_mesh_layer() -> void:
	_ensure_province_mesh_layer()
	if _province_mesh_layer == null or not _province_mesh_layer.has_method("rebuild_from_provinces"):
		return
	var owner_resolver := func(pid: int) -> String:
		if provinces.has(pid):
			var p: Province = provinces[pid] as Province
			if p != null:
				return p.owner_tag
		return "NEU"
	_province_mesh_layer.call("rebuild_from_provinces", provinces, geometry, owner_resolver)


func _get_camera_zoom() -> float:
	return MapZoomLODScript.read_camera_zoom(get_viewport() if get_viewport() else null)


func _ensure_political_labels_layer() -> Node2D:
	if _political_labels_layer != null and is_instance_valid(_political_labels_layer):
		return _political_labels_layer
	if container == null:
		return null
	_political_labels_layer = container.get_node_or_null("PoliticalLabelsLayer") as Node2D
	if _political_labels_layer == null:
		_political_labels_layer = MapPoliticalLabelsLayerScript.new()
		_political_labels_layer.name = "PoliticalLabelsLayer"
		container.add_child(_political_labels_layer)
	return _political_labels_layer


func _rebuild_political_labels() -> void:
	var layer := _ensure_political_labels_layer()
	if layer == null:
		return
	if layer.has_method("rebuild_from_map_data"):
		layer.call("rebuild_from_map_data", province_centroids, provinces)
	if layer.has_method("sync_tier"):
		layer.call("sync_tier", _map_lod_tier)


func _sync_political_labels_tier(tier: int) -> void:
	if _political_labels_layer != null and is_instance_valid(_political_labels_layer):
		if _political_labels_layer.has_method("sync_tier"):
			_political_labels_layer.call("sync_tier", tier)


func _ensure_region_highlight_layer() -> Node2D:
	if _region_highlight_layer != null and is_instance_valid(_region_highlight_layer):
		return _region_highlight_layer
	if container == null:
		return null
	_region_highlight_layer = container.get_node_or_null("RegionHighlightLayer") as Node2D
	if _region_highlight_layer == null:
		_region_highlight_layer = MapRegionHighlightLayerScript.new()
		_region_highlight_layer.name = "RegionHighlightLayer"
		container.add_child(_region_highlight_layer)
	return _region_highlight_layer


func _rebuild_region_highlight() -> void:
	var layer := _ensure_region_highlight_layer()
	if layer == null:
		return
	if layer.has_method("rebuild_from_geometry"):
		layer.call("rebuild_from_geometry", geometry, _is_world_canvas_active())
	if layer.has_method("sync_tier"):
		layer.call("sync_tier", _map_lod_tier)


func _sync_hovered_strategic_region(province: Province) -> void:
	var rid := -1
	if (
		province != null
		and typeof(MapManager) != TYPE_NIL
		and MapManager.has_method("get_province_region_id")
	):
		rid = MapManager.get_province_region_id(province.id)
	if _region_highlight_layer != null and is_instance_valid(_region_highlight_layer):
		if _region_highlight_layer.has_method("set_hovered_region"):
			_region_highlight_layer.call("set_hovered_region", rid, _map_lod_tier)
	if _political_labels_layer != null and is_instance_valid(_political_labels_layer):
		if _political_labels_layer.has_method("set_hovered_region"):
			_political_labels_layer.call("set_hovered_region", rid, _map_lod_tier)


func _sync_border_lod(tier: int) -> void:
	if border_layer == null or not is_instance_valid(border_layer):
		return
	var w: float = MapZoomLODScript.country_border_width(tier)
	var a: float = MapZoomLODScript.country_border_alpha(tier)
	for child in border_layer.get_children():
		if not (child is Line2D):
			continue
		if not str(child.name).begins_with(COUNTRY_FRONTIER_PREFIX):
			continue
		var seg := child as Line2D
		seg.width = w
		var c := seg.default_color
		c.a = a
		seg.default_color = c


func _get_camera_world_rect(margin_ratio: float = 0.10) -> Rect2:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null:
		return Rect2()
	var vp_size := get_viewport().get_visible_rect().size
	var zoom := maxf(cam.zoom.x, cam.zoom.y)
	var half := vp_size * 0.5 / maxf(zoom, 0.01)
	var center := cam.global_position
	var rect := Rect2(center - half, half * 2.0)
	var margin := margin_ratio * maxf(rect.size.x, rect.size.y)
	return rect.grow(margin)


func _sync_viewport_culling(force: bool = false) -> void:
	var use_cull := MapZoomLODScript.use_viewport_culling(_map_lod_tier)
	if not use_cull:
		if _viewport_culling_active:
			_clear_viewport_culling()
		return

	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null:
		return
	var pos := cam.global_position
	var zoom := _get_camera_zoom()
	if (
		not force
		and _viewport_culling_active
		and pos.distance_squared_to(_last_viewport_cull_pos) < 256.0
		and absf(zoom - _last_viewport_cull_zoom) < 0.015
	):
		return
	_last_viewport_cull_pos = pos
	_last_viewport_cull_zoom = zoom
	_viewport_culling_active = true

	var world_rect := _get_camera_world_rect(0.14)
	var visible_pids: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_in_rect"):
		for pid in MapManager.get_provinces_in_rect(world_rect, 96.0):
			visible_pids[int(pid)] = true
	if selected_province_id >= 0:
		visible_pids[selected_province_id] = true
	if _hover_province != null:
		visible_pids[_hover_province.id] = true
	for pid in _get_interesting_province_ids().keys():
		visible_pids[int(pid)] = true

	for pid_var in province_nodes.keys():
		var pid := int(pid_var)
		var node: Node2D = province_nodes[pid_var] as Node2D
		if node == null or not is_instance_valid(node):
			continue
		node.visible = visible_pids.has(pid)

	if _political_labels_layer != null and is_instance_valid(_political_labels_layer):
		if _political_labels_layer.has_method("sync_viewport"):
			_political_labels_layer.call("sync_viewport", world_rect, true)


func _clear_viewport_culling() -> void:
	if not _viewport_culling_active:
		return
	_viewport_culling_active = false
	_last_viewport_cull_pos = Vector2(-99999, -99999)
	_last_viewport_cull_zoom = -1.0
	for pid_var in province_nodes.keys():
		var node: Node2D = province_nodes[pid_var] as Node2D
		if node != null and is_instance_valid(node):
			node.visible = true
	if _political_labels_layer != null and is_instance_valid(_political_labels_layer):
		if _political_labels_layer.has_method("sync_viewport"):
			_political_labels_layer.call("sync_viewport", Rect2(), false)


func _should_use_batched_mesh_fills() -> bool:
	if _batched_mesh_fills_forced:
		return true
	if not _batched_mesh_fills_prefer:
		return false
	if current_map_mode != "political" and debug_tint_mode != "":
		return false
	if supply_mode:
		return false
	return MapZoomLODScript.use_batched_mesh_fills(MapZoomLODScript.tier_for_zoom(_get_camera_zoom())) and not show_terrain_layer


func _sync_batched_mesh_fills(force: bool = false) -> void:
	var z := _get_camera_zoom()
	var bucket := int(z * 20.0)
	if not force and bucket == _last_mesh_zoom_bucket and not _batched_mesh_fills_forced:
		return
	_last_mesh_zoom_bucket = bucket
	var want := _should_use_batched_mesh_fills()
	if want == _batched_mesh_active and not force:
		return
	_batched_mesh_active = want
	_ensure_province_mesh_layer()
	if _province_mesh_layer == null:
		return
	if want:
		_rebuild_province_mesh_layer()
		if _province_mesh_layer.has_method("set_enabled"):
			_province_mesh_layer.call("set_enabled", true)
		for pid in province_nodes.keys():
			var node: Node2D = province_nodes[pid] as Node2D
			if node == null:
				continue
			var poly := _get_province_polygon(node)
			if poly != null:
				var c := poly.color
				c.a = 0.02
				poly.color = c
	else:
		if _province_mesh_layer.has_method("set_enabled"):
			_province_mesh_layer.call("set_enabled", false)
		_refresh_province_fill_colors()


## Switch to a clean base map texture
## Call from Debug or editor (ProvinceEditor). Falls back if file not present.
## Recommended: prepare a dedicated clean_parchment version of your grand theater image with no borders/text for best editing experience.
## For world work we will have chunked versions in world_chunks/ (see split script + manifest).
func set_clean_base_map(texture_path: String = "res://assets/maps/europe_grand_theater_ultra_high.jpg") -> void:
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg == null:
		return
	if ResourceLoader.exists(texture_path):
		var tex := load(texture_path) as Texture2D
		if tex:
			bg.texture = tex
			bg.modulate = Color(0.95, 0.93, 0.88, 0.98)  # slightly cleaner paper tone for editing
			bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			print("MapRenderer: Switched to clean base map for province editing: ", texture_path)
			_fit_background_to_bounds()
	else:
		push_warning("MapRenderer: Clean base map not found at " + texture_path + " - using current")

## DEBUG helper for world portion / chunk work.
## Quickly swap in one of the 4 world chunks (0-3) as the underlay. This proves the "load only the portion you need"
## model while the detailed Europe 5000x2000 remains the active dev canvas.
## In a full implementation the manifest's world_pixel_origin would be used to correctly position/scale multiple chunks or
## a high-detail theater inset on top of a low-res world base.
## Side effect: ProvinceEditor (if active) will auto-load the chunk's rivers.json for river snap (better natural borders on sub-theater).
func debug_load_world_chunk(chunk_index: int = 0) -> void:
	var full_underlay_active := bool(get_meta("full_world_underlay_active", false))
	if full_underlay_active:
		var tls_only := find_child("TerrainLayerStack", true, false)
		if tls_only and tls_only.has_method("load_world_chunk_layers"):
			tls_only.call("load_world_chunk_layers", chunk_index)
		var chunk_rect := _get_world_chunk_rect(chunk_index)
		if chunk_rect.size.x > 0 and tls_only and tls_only.has_method("fit_to_bounds"):
			tls_only.call("fit_to_bounds", chunk_rect)
		print("MapRenderer: chunk ", chunk_index, " detail layers only (full world underlay kept for seamless scroll).")
		return
	var path := "res://assets/maps/world_chunks/world_chunk_%02d_world_grand_theater_clean.png" % chunk_index
	if not ResourceLoader.exists(path):
		push_warning("MapRenderer: world chunk not found " + path)
		return
	var tex := load(path) as Texture2D
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg == null or tex == null:
		return
	bg.texture = tex
	bg.visible = true
	bg.modulate = Color(0.95, 0.93, 0.88, 0.98)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg.set_meta("grand_fitted", false)

	# Position and scale for world canvas using manifest (seamless chunk tiling in 8192x4096 view).
	# When world grand or large bounds active, place the chunk tex at its exact world origin so it aligns with the raster coords and Europe polys (at NW of world).
	var positioned_for_world := false
	var manifest_path := "res://assets/maps/world_chunks/world_chunks_manifest.json"
	if ResourceLoader.exists(manifest_path):
		var f := FileAccess.open(manifest_path, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if typeof(data) == TYPE_DICTIONARY and data.has("chunks"):
				var clean_chunks = data["chunks"].get("clean_underlay", [])
				if chunk_index < clean_chunks.size():
					var info = clean_chunks[chunk_index]
					print("MapRenderer: DEBUG loaded world chunk ", chunk_index,
						" origin=", info.get("world_pixel_origin", []),
						" size=", info.get("pixel_rect", []))
					var o = info.get("world_pixel_origin", [0,0])
					var s = info.get("pixel_rect", [0,0,4144,2096])
					_current_theater_bounds = Rect2(float(o[0]), float(o[1]), float(s[2]), float(s[3]))
					bg.position = Vector2(float(o[0]), float(o[1]))
					var tw := maxf(1.0, float(bg.texture.get_width()))
					var th := maxf(1.0, float(bg.texture.get_height()))
					var pw := float(s[2])
					var ph := float(s[3])
					bg.scale = Vector2(pw / tw, ph / th)
					bg.centered = false
					positioned_for_world = true
					_clamp_camera_to_theater()
					# Continue to rivers note etc.
	# Fallback for non-world or missing manifest
	if not positioned_for_world:
		print("MapRenderer: DEBUG loaded world chunk ", chunk_index, " as underlay for portion testing.")
		_current_theater_bounds = Rect2(0,0,4144,2096)
		_clamp_camera_to_theater()
	# Try load chunk-specific rivers for editor snap in that theater
	var cr_path := "res://assets/maps/world_chunks/world_chunk_%02d_rivers.json" % chunk_index
	if ResourceLoader.exists(cr_path):
		# For demo, just print; real would feed to ProvinceEditor or MapManager for sub-theater snap
		print("  (chunk has its own rivers.json for localized snap; load manually in editor if needed)")
	# Note: snow_mask now chunk-aware (normalized _snow_mask.png preferred); dynamic winter bits via WeatherOverlay use chunk snow if present when bg is chunk tex. Ref S layer also switches in TerrainLayerStack.
	# Important: strategic regions, snow_potential (inference), full control bonuses (pride, factory_output etc), terrain tags are all driven by province data / ScenarioLoader / MapManager -- NOT the visual underlay. So chunk swap for visuals keeps data/connections consistent (Europe test uses provinces_full_europe data regardless of chunk).

## Load a world chunk as the main grand underlay (for testing multi-theater / full world expansion).
## Keeps the Europe snow mask for winter high-elev white bits (or extend for chunk snow).
## Stub for camera/zoom or scenario driven theater swap (portion of world or high detail inset).
## Future: use manifest world_pixel_origin + camera rect to auto load chunk + per chunk layers + update LOD.
func load_theater(theater_id: String = "europe") -> void:
	if theater_id == _active_theater_id:
		return
	_active_theater_id = theater_id
	_theater_print_count += 1
	if _theater_print_count <= 3 or _theater_print_count % 8 == 0:
		print("MapRenderer: load_theater (", theater_id, ") - swapping via manifest/chunks for theater/zoom. Data consistent.")
	set_meta("current_theater", theater_id)
	if theater_id.to_lower().contains("chunk"):
		var idx := 0
		if theater_id.contains("1"): idx = 1
		elif theater_id.contains("2"): idx = 2
		elif theater_id.contains("3"): idx = 3
		load_world_chunk_underlay(idx)
		# update LOD for chunk
		var tls := find_child("TerrainLayerStack", true, false)
		if tls and tls.has_method("set_layer_alphas"):
			tls.call("set_layer_alphas", 0.8, 0.7)
		if not bool(get_meta("full_world_underlay_active", false)):
			_current_theater_bounds = Rect2(0,0,4144,2096)  # approx chunk; for better use manifest origin+size
		# else keep full world bounds for seamless scroll
	elif theater_id.to_lower() == "world" or theater_id.to_lower().contains("full"):
		_active_chunk_index = -1
		if bool(get_meta("full_world_underlay_active", false)) and _world_class_bootstrapped:
			_apply_world_terrain_layers()
			_position_terrain_above_background()
		else:
			load_world_grand_underlay()
	else:
		_active_chunk_index = -1
		_current_theater_bounds = GRAND_THEATER_CANONICAL_BOUNDS
		set_meta("full_world_underlay_active", false)
	# Future: camera rect / zoom to auto-select chunk or high-detail inset from manifest + per chunk layers + LOD.
	_clamp_camera_to_theater()
	_refresh_province_fill_colors()

## Basic auto theater/LOD from camera zoom + rough pos (beyond stub; uses existing chunk/theater + LOD alpha).
## High value for "number of closer zoom options" + portion loading. Call manually or from process/harness.
func _compute_world_chunk_index(p: Vector2) -> int:
	if MapCanvasConfig.is_world_mode(_current_theater_bounds):
		var half := MapCanvasConfig.world_chunk_half_size()
		var cx := int(clamp(p.x / half.x, 0, 1))
		var cy := int(clamp(p.y / half.y, 0, 1))
		return cy * 2 + cx
	var ec := MapCanvasConfig.europe_center()
	if p.x > ec.x and p.y > ec.y:
		return 3
	if p.x > ec.x:
		return 2
	if p.y > ec.y:
		return 1
	return 0


func _is_world_canvas_active() -> bool:
	return bool(get_meta("full_world_underlay_active", false)) or MapCanvasConfig.is_world_mode(_current_theater_bounds)


func auto_update_theater_from_camera() -> void:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null:
		return
	var z := cam.zoom.x if cam.zoom else 1.0
	var p := cam.global_position if cam else Vector2.ZERO
	var tls := find_child("TerrainLayerStack", true, false)

	# Cheap LOD alpha updates only (no texture/chunk reload).
	var lod_band := 1
	var veg_a := 0.85
	var snow_a := 0.75
	if z > 2.2:
		lod_band = 3
		veg_a = 1.0
		snow_a = 0.95
	elif z > 1.8:
		lod_band = 2
		veg_a = 0.95
		snow_a = 0.9
	elif z < 0.55:
		lod_band = 0
		veg_a = 0.75
		snow_a = 0.65
	if lod_band != _last_lod_band and tls and tls.has_method("set_layer_alphas"):
		_last_lod_band = lod_band
		tls.call("set_layer_alphas", veg_a, snow_a)

	# Expensive chunk/theater swap — only when the target theater id actually changes.
	if z > CHUNK_LOAD_ZOOM_MIN:
		var ci := _compute_world_chunk_index(p)
		var tid := "chunk%d_demo" % ci
		if tid != _active_theater_id:
			load_theater(tid)
	elif z < 0.55:
		if MapCanvasConfig.is_world_mode(_current_theater_bounds):
			if tls and tls.has_method("set_layer_alphas"):
				tls.call("set_layer_alphas", 0.75, 0.65)
			if not bool(get_meta("full_world_underlay_active", false)):
				load_theater("world")
		elif _active_theater_id != "europe":
			load_theater("europe")
	elif z < 0.8 and tls and tls.has_method("set_layer_alphas") and _last_lod_band != 1:
		_last_lod_band = 1
		tls.call("set_layer_alphas", 0.85, 0.75)

	if _theater_print_count % 12 == 0:
		print("MapRenderer: auto theater/LOD from camera zoom=", z, " pos=", p, " (closer zooms + chunk portions for demo)")

## Clamp or wrap camera within current theater bounds (wrap enables seamless toroidal pan for tactical refinement).
func _clamp_camera_to_theater() -> void:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null:
		return
	cam.global_position = _apply_camera_bounds(cam.global_position)
	_sync_camera_controller_wrap()


func get_camera_wrap_bounds() -> Rect2:
	return _current_theater_bounds


func _apply_camera_bounds(pos: Vector2) -> Vector2:
	var b := _current_theater_bounds
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		return pos
	if enable_map_wrap:
		return MapCanvasConfig.wrap_position(pos, b)
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	var margin := 300.0 / maxf(0.05, cam.zoom.x if cam else 1.0)
	pos.x = clampf(pos.x, b.position.x - margin, b.position.x + b.size.x + margin)
	pos.y = clampf(pos.y, b.position.y - margin, b.position.y + b.size.y + margin)
	return pos


func _sync_camera_controller_wrap() -> void:
	if not enable_map_wrap:
		return
	var ctrls := get_tree().get_nodes_in_group("camera_controller")
	for node in ctrls:
		var cc := node as CameraController
		if cc != null:
			if cc.has_method("set_wrap_bounds"):
				cc.set_wrap_bounds(_current_theater_bounds)
			if cc.target != null:
				cc.target.position = MapCanvasConfig.wrap_position(cc.target.position, _current_theater_bounds)


## Fit the active camera zoom so map bounds fill the viewport (reduces gray margins).
func fit_camera_to_bounds(bounds: Rect2, center: Vector2, fill_ratio: float = -1.0) -> void:
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null or bounds.size.x <= 0.0:
		return
	var ratio := viewport_fill_ratio if fill_ratio < 0.0 else fill_ratio
	var vp := get_viewport().get_visible_rect().size
	var z := MapCanvasConfig.zoom_to_fill_bounds(bounds, vp, ratio, min_zoom, max_zoom)
	cam.zoom = Vector2(z, z)
	cam.global_position = _apply_camera_bounds(center)
	_sync_camera_controller_wrap()


func fit_camera_to_fill_viewport(center: Vector2 = Vector2.INF, fill_ratio: float = -1.0) -> void:
	var c := center
	if c == Vector2.INF:
		c = MapCanvasConfig.europe_world_center() if _is_world_canvas_active() else MapCanvasConfig.europe_center()
	fit_camera_to_bounds(_current_theater_bounds, c, fill_ratio)


## Load full world grand underlay for HOI/Vic-style high level overview (big canvas, zoom in to Europe or other for detail).
## Call from debug button or future "world mode". Updates bounds + clamp so no gray loss. Europe polys remain positioned for test.
func load_world_grand_underlay() -> void:
	# Prefer the world-class clean base (artistic + baked accurate cues from chunks: prominent Great Lakes, aligned Rockies/Andes/Greenland compact). Rivers/elev overlays add high-vis detail. Falls back to ultra if clean missing.
	var candidates := [
		"res://assets/maps/layers/world_grand_theater_clean.png",
		"res://assets/maps/world_grand_theater_ultra_high.jpg",
		"res://assets/maps/world_grand_theater_ultra_high.png",
	]
	var path := ""
	var tex: Texture2D = null
	for c in candidates:
		if ResourceLoader.exists(c):
			tex = load(c) as Texture2D
			if tex:
				path = c
				break
	if tex == null:
		print("MapRenderer: no world grand underlay found (run world build + check assets)")
		return
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if get_meta("full_world_underlay_active", false) and bg and bg.texture and str(bg.texture.resource_path) == path:
		_apply_world_terrain_layers()
		_position_terrain_above_background()
		return
	if bg:
		bg.texture = tex
		var tw := float(tex.get_width()) if tex.get_width() > 0 else WORLD_CANONICAL_BOUNDS.size.x
		var th := float(tex.get_height()) if tex.get_height() > 0 else WORLD_CANONICAL_BOUNDS.size.y
		bg.scale = Vector2(WORLD_CANONICAL_BOUNDS.size.x / tw, WORLD_CANONICAL_BOUNDS.size.y / th)
		bg.position = WORLD_CANONICAL_BOUNDS.position
		bg.centered = false
		bg.visible = true
		bg.modulate = Color(0.95, 0.93, 0.88, 0.98)
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		bg.remove_meta("grand_fitted")
	_current_theater_bounds = WORLD_CANONICAL_BOUNDS
	set_meta("full_world_underlay_active", true)
	_clamp_camera_to_theater()
	_apply_world_terrain_layers()
	_position_terrain_above_background()
	_suppress_old_background_maps()
	print("MapRenderer: Loaded WORLD grand underlay (", path, ") + aligned elevation/rivers for mountains/lakes.")
	_refresh_province_fill_colors()
	_setup_coarse_world_territories(true)

	# Force rivers/lakes layer to be highly visible on the large world map view (Great Lakes prominent in NA when panned or in overview).
	# The edited world_layer_rivers.png (with very prominent Great Lakes shapes) + high alpha will make the accurate lakes stand out on top of the base.
	var tls2 := terrain_layer_stack
	if tls2 == null:
		tls2 = find_child("TerrainLayerStack", true, false) as TerrainLayerStack
	if tls2:
		tls2.show_rivers_layer = true
		tls2.show_elevation_layer = true
		if tls2.has_method("_apply_visibility"):
			tls2.call("_apply_visibility")
		var riv = tls2.get("_rivers") if tls2.has_method("get") else null
		if riv and riv is Sprite2D:
			riv.modulate.a = 0.95  # very prominent for lakes and rivers on the large map (Great Lakes now clear on auto world)
			print("  Rivers/lakes layer forced high visibility (Great Lakes will show clearly on large world view).")
		var elev = tls2.get("_elevation") if tls2.has_method("get") else null
		if elev and elev is Sprite2D:
			elev.modulate.a = 0.68
			print("  Elevation/mountains layer forced visible (NA Rockies, Greenland compact, SA Andes aligned on large view).")


## Single authoritative world-class bootstrap: ultra world underlay, mountains + lakes layers aligned, Europe framed.
func bootstrap_world_class_map() -> void:
	if not is_inside_tree():
		call_deferred("bootstrap_world_class_map")
		return
	if _world_class_bootstrapped:
		return
	load_world_grand_underlay()
	_setup_terrain_layer_stack()
	_mount_peak_snow_overlay()
	_apply_world_terrain_layers()
	_position_terrain_above_background()
	_suppress_old_background_maps()
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam:
		cam.global_position = MapCanvasConfig.europe_world_center()
		if fill_viewport_on_load:
			fit_camera_to_bounds(
				MapCanvasConfig.europe_world_rect(),
				MapCanvasConfig.europe_world_center(),
				MapCanvasConfig.EUROPE_VIEW_FILL_RATIO,
			)
		else:
			cam.zoom = Vector2.ONE * (0.35 * MapCanvasConfig.THEATER_SCALE)
	_clamp_camera_to_theater()
	if not provinces.is_empty():
		force_full_map_refresh()
	_world_class_bootstrapped = true
	print("MapRenderer: bootstrap_world_class_map complete (world ultra + mountains/rivers/lakes aligned, Europe framed).")


func _position_terrain_above_background() -> void:
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg:
		bg.z_index = -20
	var tls := terrain_layer_stack
	if tls == null:
		tls = find_child("TerrainLayerStack", true, false) as TerrainLayerStack
		terrain_layer_stack = tls
	if tls:
		tls.z_index = -15


func _apply_world_terrain_layers() -> void:
	_setup_terrain_layer_stack()
	var tls := terrain_layer_stack
	if tls == null:
		tls = find_child("TerrainLayerStack", true, false) as TerrainLayerStack
		terrain_layer_stack = tls
	if tls == null:
		return
	if tls.has_method("try_load_world_from_metadata"):
		tls.try_load_world_from_metadata()
	if tls.has_method("configure_for_world_launch"):
		tls.configure_for_world_launch()
	tls.fit_to_bounds(WORLD_CANONICAL_BOUNDS)
	tls.visible = true

## Reset camera + bounds to Europe grand theater (for quick return after world/NA pan or chunk loads).
## Keeps Europe polys and data as the testable focus.
func reset_camera_to_europe() -> void:
	_current_theater_bounds = GRAND_THEATER_CANONICAL_BOUNDS
	set_meta("full_world_underlay_active", false)
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam:
		# Center on Europe grand + reasonable zoom for overview of the 471-prov test area
		if fill_viewport_on_load:
			fit_camera_to_bounds(
				GRAND_THEATER_CANONICAL_BOUNDS,
				MapCanvasConfig.europe_center(),
				MapCanvasConfig.EUROPE_VIEW_FILL_RATIO,
			)
		else:
			cam.global_position = MapCanvasConfig.europe_center()
			cam.zoom = Vector2.ONE * (0.6 * MapCanvasConfig.THEATER_SCALE)
	_clamp_camera_to_theater()
	# Restore Europe underlay + layers if we were on world/chunk
	load_theater("europe")
	print("MapRenderer: reset camera + bounds to Europe (playtest focus restored; world/NA view available via button)")
	_setup_coarse_world_territories(false)  # hide/low for focused Europe view

## Helper to get the world rect for a chunk (from manifest or fallback) for precise layer fitting (mountains/elev align to bg).
func _get_world_chunk_rect(chunk_index: int) -> Rect2:
	var manifest_path := "res://assets/maps/world_chunks/world_chunks_manifest.json"
	if ResourceLoader.exists(manifest_path):
		var f := FileAccess.open(manifest_path, FileAccess.READ)
		if f:
			var parser := JSON.new()
			if parser.parse(f.get_as_text()) == OK:
				var data: Dictionary = parser.data
				if data.has("chunks") and data["chunks"].has("clean_underlay"):
					var arr: Array = data["chunks"]["clean_underlay"]
					if chunk_index >= 0 and chunk_index < arr.size():
						var info: Dictionary = arr[chunk_index]
						if info.has("world_pixel_origin") and info.has("pixel_rect"):
							var origin: Array = info["world_pixel_origin"]
							var prect: Array = info["pixel_rect"]
							var ox := float(origin[0]) if origin.size() > 0 else 0.0
							var oy := float(origin[1]) if origin.size() > 1 else 0.0
							# Manifest pixel_rect is [origin_x, origin_y, width, height] in world canvas pixels.
							var w := float(prect[2]) if prect.size() > 2 else MapCanvasConfig.world_chunk_half_size().x
							var h := float(prect[3]) if prect.size() > 3 else MapCanvasConfig.world_chunk_half_size().y
							if prect.size() >= 2:
								ox = float(prect[0])
								oy = float(prect[1])
							return Rect2(ox, oy, w, h)
			f.close()
	# Fallback approx 2x2 grid on scaled world canvas
	var half := MapCanvasConfig.world_chunk_half_size()
	var cw := half.x
	var ch := half.y
	var col := chunk_index % 2
	var row := chunk_index / 2
	return Rect2(col * (cw - 48), row * (ch - 48), cw, ch)  # overlap approx

## Setup (or toggle visibility of) coarse world territories for clickable high-level regions on the stitched world grand.
## Gives "every area on the map has a region or territory you can click to get into" for grand strategy scroll feel.
## Even with Europe-focused detailed provinces (471), the world bg now has Africa, Australia, East Asia etc as clickable strategic territories.
## They are large rect-based for perf/simplicity; positioned in world 8192x4096 canvas coords to roughly match standard stylized world layout.
## When active (world view), faint colored polys; click resolves to territory info (no detailed prov yet, but "enter" by centering or future load chunk/detailed gen).
## Call with show=true on world load, false on Europe reset.
func _setup_coarse_world_territories(show: bool = true) -> void:
	if _coarse_container == null:
		_coarse_container = Node2D.new()
		_coarse_container.name = "CoarseWorldTerritories"
		_coarse_container.z_index = -10  # behind detailed provinces/polys
		add_child(_coarse_container)
		# Define key territories (approx rects in world canvas units; tune as needed for visual alignment with bg features).
		# Negative ids to not collide with real province ids (1+ or 9000+).
		_coarse_territories.clear()
		_coarse_territories[-100] = {
			"name": "Africa",
			"rect": MapCanvasConfig.scale_rect(Rect2(2100, 1900, 2200, 1500)),
			"display_name": "Africa (Coarse Strategic Region)",
			"desc": "High-level territory for grand strategy overview. Detailed province generation (rivers, elevation, infra) can be expanded here for full-world scenarios. Click to focus camera or 'enter' for future sub-map."
		}
		_coarse_territories[-101] = {
			"name": "Australia",
			"rect": MapCanvasConfig.scale_rect(Rect2(6300, 3100, 1300, 900)),
			"display_name": "Australia & Oceania (Coarse)",
			"desc": "Strategic region placeholder. Mountains/outback elevation ref available in world layers. Expandable for detailed play."
		}
		_coarse_territories[-102] = {
			"name": "East Asia",
			"rect": MapCanvasConfig.scale_rect(Rect2(5600, 500, 2000, 1400)),
			"display_name": "East Asia (Coarse Strategic Region)",
			"desc": "China, Japan, Korea area high-level. Himalayas and other mountains in elevation layer (toggle H). Build detailed provinces off the world stitched map here."
		}
		_coarse_territories[-103] = {
			"name": "North America",
			"rect": MapCanvasConfig.scale_rect(Rect2(300, 300, 1600, 1300)),
			"display_name": "North America (Coarse)",
			"desc": "NA strategic overview. Zoom or load relevant world chunk for detail layers (elev/rivers). Future full provinces."
		}
		_coarse_territories[-104] = {
			"name": "South America",
			"rect": MapCanvasConfig.scale_rect(Rect2(900, 1700, 900, 1400)),
			"display_name": "South America (Coarse)",
			"desc": "SA territory. Andes mountains via world elevation. Part of full stitched world for scrollable grand strategy."
		}
		# Create visual polys (invisible by default — click uses rect hit test, not poly alpha).
		for tid in _coarse_territories:
			var info: Dictionary = _coarse_territories[tid]
			var r: Rect2 = info.rect
			var poly := Polygon2D.new()
			poly.polygon = PackedVector2Array([r.position, Vector2(r.position.x + r.size.x, r.position.y), r.position + r.size, Vector2(r.position.x, r.position.y + r.size.y)])
			var vis_alpha := 0.12 if (show and show_coarse_territory_overlays) else 0.0
			poly.color = Color(0.15, 0.25, 0.15, vis_alpha)
			poly.name = "Coarse_" + str(info.name).replace(" ", "_")
			_coarse_container.add_child(poly)
			info["poly_node"] = poly
	else:
		# Toggle existing
		for tid in _coarse_territories:
			var info: Dictionary = _coarse_territories[tid]
			var poly: Polygon2D = info.get("poly_node")
			if poly:
				poly.color.a = 0.12 if (show and show_coarse_territory_overlays) else 0.0
	# Also ensure input handling knows about them (in _input or pick fallthrough).

## Simple rect hit test for coarse territories (used when detailed province pick returns none).
func _hit_coarse_territory(world_pos: Vector2) -> int:
	for tid in _coarse_territories:
		var r: Rect2 = _coarse_territories[tid].rect
		if r.has_point(world_pos):
			return tid
	return 0

## Show info for a coarse world territory (called from click handling when no detailed province hit).
func _show_coarse_territory_info(terr_id: int) -> void:
	if not _coarse_territories.has(terr_id) or info_panel == null:
		return
	var info: Dictionary = _coarse_territories[terr_id]
	_selected_coarse_id = terr_id
	selected_province_id = -1  # clear detailed
	_layout_map_ui()
	info_panel.visible = true
	if info_name: info_name.text = info.get("display_name", info.name)
	if info_owner: info_owner.text = "World Overview Territory (coarse/strategic)"
	if info_population: info_population.text = "Type: Strategic Region (expandable)"
	if info_terrain: info_terrain.text = "Part of stitched world grand map. Toggle H for elevation/mountains."
	if info_factories: info_factories.text = "No detailed factories yet (Europe scenario focus)"
	if info_dev: info_dev.text = "Dev/Infra: N/A (use world layers or zoom to Europe for test)"
	if info_resources: info_resources.text = "Resources: See world_layer for overview"
	if info_core: info_core.text = "Core: None (future nations)"
	if info_special: info_special.text = "Special: " + info.get("desc", "Grand strategy scrollable territory.")
	if info_combat:
		info_combat.text = "Coarse territory - no combat data. Zoom into a detailed theater (e.g. Europe 471 provs) or load chunk for layers."
	if info_modifiers:
		info_modifiers.text = "World map base active. Scroll/pan for full grand strategy feel. Click Europe areas for detailed provinces. Other continents: future detailed province gen off this stitched world."
	if info_national:
		info_national.text = "Inspector: Coarse World Territory | Click to center camera on region."
	# Optional: center camera on the terr rect center for "get into" feel
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam:
		var r: Rect2 = info.rect
		cam.global_position = r.position + r.size * 0.5
		cam.zoom = Vector2(0.8, 0.8)  # zoom in a bit on the region
		_clamp_camera_to_theater()
	print("[COARSE TERRITORY] Clicked/entered: ", info.get("display_name", info.name), " id=", terr_id)

## Center camera + "enter" a coarse territory (for F10 or future UI).
func debug_focus_coarse_territory(terr_name: String = "Africa") -> void:
	for tid in _coarse_territories:
		if _coarse_territories[tid].name.to_lower() == terr_name.to_lower():
			_show_coarse_territory_info(tid)
			return
	print("No coarse terr named ", terr_name)

## Center camera on the Europe theater area within the full world canvas (for context when using world grand underlay).
## Keeps the detailed 471-prov test map as the playable focus while showing world scale.
func center_europe_in_world_view() -> void:
	_current_theater_bounds = WORLD_CANONICAL_BOUNDS
	set_meta("full_world_underlay_active", true)
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam:
		# Europe placement in scaled world raster; center on the remapped detailed theater rect.
		if fill_viewport_on_load:
			fit_camera_to_bounds(
				MapCanvasConfig.europe_world_rect(),
				MapCanvasConfig.europe_world_center(),
				MapCanvasConfig.EUROPE_VIEW_FILL_RATIO,
			)
		else:
			cam.global_position = MapCanvasConfig.europe_world_center()
			cam.zoom = Vector2.ONE * (0.35 * MapCanvasConfig.THEATER_SCALE)  # overview with Europe prominent
	_clamp_camera_to_theater()
	print("MapRenderer: centered on Europe theater inside world view (world scale visible, Europe test polys aligned to NW portion of bg)")

## Alias per spec for center_europe_inside_world (ensures grand underlay base, Europe 471 polys + river children NW aligned, coarse rects always).
func center_europe_inside_world() -> void:
	center_europe_in_world_view()
	print("MapRenderer: center_europe_inside_world alias invoked (scrollable grand strategy + clamp active).")

## Demo: load sample subdivided geometry for river-aware subdiv test (from generate)
func load_sample_subdiv_geometry() -> void:
	var path := "res://tools/map_generation/output/phase1_europe/sample_subdivided_geometry.json"
	if not FileAccess.file_exists(path):
		print("MapRenderer: no sample_subdivided_geometry.json (run generate_europe_phase1.py)")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var sdata = JSON.parse_string(txt)
	if typeof(sdata) == TYPE_DICTIONARY:
		var sprov: Variant = sdata.get("provinces", [])
		var children := 0
		var child_terrains := []
		var river_aware_children := 0
		for pp in sprov:
			if str(pp.get("id", "")).contains("_c"):
				children += 1
				child_terrains.append(pp.get("terrain", "unknown"))
				if bool(pp.get("river_aware", false)):
					river_aware_children += 1
		print("MapRenderer: loaded sample subdiv geo with ", sprov.size(), " provinces (", children, " river-aware children, ", river_aware_children, " with river-cross natural border from real rivers.json)")
		print("  child terrains (from inference layer): ", child_terrains)
		set_meta("sample_subdiv_loaded", true)
		# push integrate: also load in MapManager
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("load_sample_subdiv_geometry"):
			MapManager.call("load_sample_subdiv_geometry", path)
		# Could replace current geometry for demo, but for now log (data independent)
	else:
		print("MapRenderer: bad sample geo")

## Debug: spawn visible Line2D overlays for the 5 river-aware sample children (green for river-cross natural borders).
## Call after load_sample_subdiv_geometry(); removes prior debug layer. Aligns to same pixel space as underlay/provinces.
func debug_spawn_subdiv_draw_children() -> void:
	var prior := get_node_or_null("SubdivDebug")
	if prior:
		prior.queue_free()
	var target_parent := container if is_instance_valid(container) else self
	var subdiv_container := Node2D.new()
	subdiv_container.name = "SubdivDebug"
	subdiv_container.z_index = 95
	target_parent.add_child(subdiv_container)
	var sample_path := "res://tools/map_generation/output/phase1_europe/sample_subdivided_geometry.json"
	if not FileAccess.file_exists(sample_path):
		print("MapRenderer: no sample geo for debug draw")
		return
	var f := FileAccess.open(sample_path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var sdata = JSON.parse_string(txt)
	if typeof(sdata) != TYPE_DICTIONARY:
		return
	var sprov: Variant = sdata.get("provinces", [])
	var drawn := 0
	for pp in sprov:
		var pid_str := str(pp.get("id", ""))
		if not pid_str.contains("_c"):
			continue
		var ptsv = pp.get("points", [])
		if ptsv.size() < 3:
			continue
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color(0.2, 0.85, 0.3, 0.95) if bool(pp.get("river_aware", false)) else Color(0.3, 0.6, 0.95, 0.8)
		for p in ptsv:
			line.add_point(Vector2(p[0], p[1]))
		# close
		if ptsv.size() >= 3:
			line.add_point(Vector2(ptsv[0][0], ptsv[0][1]))
		subdiv_container.add_child(line)
		# label
		var lbl := Label.new()
		var center = pp.get("suggested_center", [0,0])
		lbl.position = Vector2(center[0], center[1])
		lbl.text = str(pp.get("parent_id","?")) + "_c (river)" if bool(pp.get("river_aware",false)) else str(pp.get("parent_id","?")) + "_c"
		lbl.modulate = Color(1,1,0.6)
		lbl.scale = Vector2(0.7, 0.7)
		subdiv_container.add_child(lbl)
		drawn += 1
	print("MapRenderer: spawned SubdivDebug with ", drawn, " child polys (green=river-cross guided). Remove node or reload to clear.")

## Convenience: apply the sample river subdiv demo (registers in MapManager with terrain carry) + ensure visuals + geo mutate visual for live test.
func debug_apply_sample_subdiv_demo(parent_id: int = 82) -> void:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_sample_subdiv_demo"):
		MapManager.call("apply_sample_subdiv_demo", parent_id)
	else:
		debug_spawn_subdiv_draw_children()
	print("MapRenderer: demo river subdiv apply complete for parent ", parent_id, " (5 children with inference terrain + river_aware; see MapManager + SubdivDebug)")

## Demo geo mutation: temp visual "subdiv" of the parent using sample children points (live mutate view for testing picking/inspector/combat feel without full data swap).
## Spawns labeled Line2D children + note. Call after or via apply. Use revert to clean.
func debug_apply_demo_geo_mutate(parent_id: int = 82) -> void:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_sample_subdiv_demo"):
		MapManager.call("apply_sample_subdiv_demo", parent_id)
	else:
		debug_spawn_subdiv_draw_children()
	var cont := get_node_or_null("DemoSubdivMutate")
	if cont:
		cont.queue_free()
	cont = Node2D.new()
	cont.name = "DemoSubdivMutate"
	cont.z_index = 96
	add_child(cont)
	var sprov: Array = []
	var path := "res://tools/map_generation/output/phase1_europe/sample_subdivided_geometry.json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var txt := f.get_as_text()
		f.close()
		var sdata = JSON.parse_string(txt)
		if typeof(sdata) == TYPE_DICTIONARY:
			var raw: Variant = sdata.get("provinces", [])
			if raw is Array:
				sprov = raw
			for pp in sprov:
				if str(pp.get("parent_id", "")) == str(parent_id) and str(pp.get("id", "")).contains("_c"):
					var ptsv = pp.get("points", [])
					if ptsv.size() < 3: continue
					var line := Line2D.new()
					line.width = 2.5
					line.default_color = Color(0.2, 0.9, 0.5, 0.9) if bool(pp.get("river_aware", false)) else Color(0.5, 0.7, 0.9, 0.8)
					for p in ptsv:
						line.add_point(Vector2(p[0], p[1]))
					if ptsv.size() >= 3:
						line.add_point(Vector2(ptsv[0][0], ptsv[0][1]))
					cont.add_child(line)
					var lbl := Label.new()
					var c = pp.get("suggested_center", [0, 0])
					lbl.position = Vector2(c[0], c[1]) - Vector2(40, 0)
					lbl.text = "DEMO:" + str(pp.get("terrain", "?")) + ("(river)" if bool(pp.get("river_aware", false)) else "")
					lbl.scale = Vector2(0.55, 0.55)
					lbl.modulate = Color(1, 1, 0.7)
					cont.add_child(lbl)
	var note := get_node_or_null("DemoMutateNote")
	if note: note.queue_free()
	note = Label.new()
	note.name = "DemoMutateNote"
	note.text = "DEMO MUTATE ACTIVE: pid82 split to 5 river-cross sample children (coastal terrain + river_aware carried from layers). Visual only for test; revert to restore parent view. Affects insight already."
	note.position = Vector2(1800, 700)
	note.scale = Vector2(0.8, 0.8)
	add_child(note)
	# Actual geo override for test (picking/visual sim on parent) -- use the sprov from visuals load which succeeded
	var pts := []
	for pp in sprov:
		if str(pp.get("parent_id", "")) == str(parent_id) and str(pp.get("id", "")).contains("_c"):
			pts.append(pp.get("points", []))
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("apply_demo_geometry_override") and pts.size() > 0:
		MapManager.call("apply_demo_geometry_override", parent_id, pts)
		print("MapRenderer: demo geo mutate VISUAL active for ", parent_id, " (5 child Line2D + labels spawned over map; temp) + GEO OVERRIDE with ", pts.size(), " polys")
		debug_draw_demo_override()  # draw using the override data for picking test
	else:
		print("MapRenderer: demo geo mutate VISUAL active for ", parent_id, " (5 child Line2D + labels spawned over map; temp)")

func debug_revert_demo_geo() -> void:
	var cont := get_node_or_null("DemoSubdivMutate")
	if cont: cont.queue_free()
	var note := get_node_or_null("DemoMutateNote")
	if note: note.queue_free()
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("clear_demo_geometry_override"):
		MapManager.call("clear_demo_geometry_override", 82)
	var ov_draw := get_node_or_null("DemoOverrideDraw")
	if ov_draw: ov_draw.queue_free()
	print("MapRenderer: demo geo mutate reverted (parent view restored) + GEO OVERRIDE cleared")


## Remove all debug/QC overlays from normal F5 play (DEMO labels, subdiv lines, IconPreviewTest, etc.).
func cleanup_playtest_debug_overlays() -> void:
	debug_revert_demo_geo()
	for n in ["SubdivDebug"]:
		var node := get_node_or_null(n)
		if node:
			node.queue_free()
	if container:
		for child_name in ["IconPreviewTest", "DemoDataObjectsDeferred"]:
			var ch := container.get_node_or_null(child_name)
			if ch:
				ch.queue_free()
			var found := container.find_child(child_name, true, false)
			if found and is_instance_valid(found):
				found.queue_free()

## Debug draw using the manager's demo geo override pts (actual override data for picking/visual test on subdivided children).
## Draws the child polys from override + labels with effective terrain (coastal etc from sample carry). Called from mutate and harness.
func debug_draw_demo_override() -> void:
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_demo_geometry_override"):
		return
	var ov: Array = MapManager.get_demo_geometry_override(82)
	if ov.size() == 0:
		return
	var prior := get_node_or_null("DemoOverrideDraw")
	if prior:
		prior.queue_free()
	var cont := Node2D.new()
	cont.name = "DemoOverrideDraw"
	cont.z_index = 97
	add_child(cont)
	for i in range(ov.size()):
		var ptsv: Array = ov[i]
		if ptsv.size() < 3: continue
		var line := Line2D.new()
		line.width = 2.0
		line.default_color = Color(0.1, 0.8, 0.3, 0.8)  # green for override children
		for p in ptsv:
			line.add_point(Vector2(p[0], p[1]))
		if ptsv.size() >= 3:
			line.add_point(Vector2(ptsv[0][0], ptsv[0][1]))
		cont.add_child(line)
		var lbl := Label.new()
		var c := Vector2.ZERO
		if ptsv.size() > 0:
			c = Vector2(ptsv[0][0], ptsv[0][1])
		lbl.position = c - Vector2(50, 0)
		var eff := "coastal"
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_effective_terrain_for_demo"):
			eff = MapManager.get_effective_terrain_for_demo(82)
		lbl.text = "OVR child" + str(i) + ":" + eff + "(r)"
		lbl.scale = Vector2(0.5, 0.5)
		lbl.modulate = Color(1,1,0.5)
		cont.add_child(lbl)
	var demo_eff := "coastal"
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_effective_terrain_for_demo"):
		demo_eff = MapManager.get_effective_terrain_for_demo(82)
	print("MapRenderer: drew using demo geo override for 82 (", ov.size(), " child polys, effective terrain ", demo_eff, " for picking/visual test)")

func load_world_chunk_underlay(chunk_index: int) -> void:
	if chunk_index == _active_chunk_index:
		return
	_active_chunk_index = chunk_index
	debug_load_world_chunk(chunk_index)
	# Wire terrain stack to chunk layers so H (elev), V (veg), S (snow ref) toggles use the chunk-aligned rasters (not europe master).
	# This keeps the ref layers (for inspection) matching the portion underlay. Snow for dynamic winter bits also chunk-aware in WeatherOverlay.
	var tls := find_child("TerrainLayerStack", true, false)
	if tls and tls.has_method("load_world_chunk_layers"):
		# call returns Variant; avoid := inference warning (strict mode treats as error)
		tls.call("load_world_chunk_layers", chunk_index)
	# Ensure layers (esp elevation for mountains/hills) are fitted exactly to this chunk's world rect so mountains line up with grand clean bg features for that portion (Africa, Aus, E Asia etc).
	# Uses manifest pixel/world origin for precise alignment across stitched chunks.
	var chunk_rect := _get_world_chunk_rect(chunk_index)
	if chunk_rect.size.x > 0 and tls and tls.has_method("fit_to_bounds"):
		tls.call("fit_to_bounds", chunk_rect)
	# Snow note: chunk snow uses normalized world_chunk_XX_snow_mask.png (or legacy europe_ fallback)
	var csm_path := "res://assets/maps/world_chunks/world_chunk_%02d_snow_mask.png" % chunk_index
	if not ResourceLoader.exists(csm_path):
		csm_path = "res://assets/maps/world_chunks/world_chunk_%02d_europe_snow_mask.png" % chunk_index
	if ResourceLoader.exists(csm_path):
		print("  chunk has its snow_mask for localized high elev snow bits")
	else:
		print("  no chunk-specific snow_mask (weather will use europe/global if present; high elev white bits may be limited for this portion)")
	print("MapRenderer: Loaded world chunk ", chunk_index, " as underlay. Snow mask (dynamic via weather + ref via S) active.")
	# Stub for future camera-driven theater swap (zoom or scenario "active_theater" -> load appropriate chunk or high-detail inset + LOD).
	# Would use manifest + camera rect to pick/swap layers without full reload.
	if false:  # placeholder
		load_theater("europe_chunk0_demo")
	# Notify ProvinceEditor (if active/in group) to switch to chunk-local rivers.json for snap (enables natural river-based border editing on the loaded portion without full world data).
	var pe_nodes := get_tree().get_nodes_in_group("province_editor") if get_tree() else []
	if pe_nodes.size() > 0:
		var pe := pe_nodes[0]
		if pe and pe.has_method("load_chunk_rivers_for_snap"):
			pe.call("load_chunk_rivers_for_snap", chunk_index)
			print("  Notified ProvinceEditor of chunk ", chunk_index, " for per-chunk river snap.")

	# Next wiring for chunks + scenario connections: re-seed WM from current provinces (snow_potential still applies via data, not visual), re-apply supply regional bonuses (full control effects), log full control status for demo tags to prove data independence.
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("initialize_province"):
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_provinces"):
			var aps := MapManager.get_all_provinces()
			var wseedc := 0
			for pidv in aps:
				var p: Province = aps[pidv]
				if p and p.snow_potential > 0.0:
					WeatherManager.initialize_province(pidv, {"is_northern": p.snow_potential > 0.05, "lat": 55.0, "high_ground_fraction": p.snow_potential, "snow_potential": p.snow_potential})
					wseedc += 1
			if wseedc > 0: print("  re-seeded WM for ", wseedc, " provinces with snow_potential (chunk visual swap, data same)")
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("_apply_regional_control_throughput_bonuses"):
		SupplyManager._apply_regional_control_throughput_bonuses()
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_fully_controlled_strategic_regions"):
		var engc := MapManager.get_fully_controlled_strategic_regions("ENG").size()
		var gerc := MapManager.get_fully_controlled_strategic_regions("GER").size()
		print("  full control post-chunk: ENG=", engc, " GER=", gerc, " (bonuses/pride still active; regions data-driven)")
	# Re-wire trade flows for current regional convoy protection (naval etc may affect sea routes in this chunk)
	if typeof(TradeManager) != TYPE_NIL:
		for f in TradeManager.get_active_trade_flows():
			if f and TradeManager.has_method("_try_assign_supply_route_to_flow"):
				TradeManager._try_assign_supply_route_to_flow(f)
		print("  trade flows re-assigned for chunk (convoy bonuses from full regions apply to routes)")
	# Skip refresh_all_project_visuals on chunk swap — it spammed province_data_changed → full infra rebuilds during pan/zoom.


func _create_province_node(province: Province, geo: Dictionary) -> Node2D:
	var node := Node2D.new()
	node.name = "Prov_%d" % province.id

	var points: PackedVector2Array = geo.get("points", PackedVector2Array())
	if points.size() < 3:
		return node

	# Scale to tactical canvas (+44% global) + island inflation; optionally remap onto world underlay.
	points = MapCanvasConfig.transform_province_points(points, _is_world_canvas_active(), true)

	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = _get_province_color(province)
	poly.antialiased = true

	# Area2D is now completely optional.
	# In the recommended production pure-spatial configuration (use_spatial_picking=true AND
	# create_area_nodes_for_fallback=false), no Area2D nodes are ever created.
	if create_area_nodes_for_fallback or not use_spatial_picking:
		var area := Area2D.new()
		var collision := CollisionPolygon2D.new()
		collision.polygon = points
		area.add_child(collision)
		area.input_event.connect(_on_province_input.bind(province, node))
		area.mouse_entered.connect(_on_mouse_entered.bind(node, province))
		area.mouse_exited.connect(_on_mouse_exited.bind(node))

		node.add_child(area)

	node.add_child(poly)

	var center := _calculate_centroid(points)
	province_centroids[province.id] = center

	if debug_draw_province_centroids:
		var marker := _make_centroid_debug_marker(4.0)
		marker.position = center
		node.add_child(marker)

	if province.has_feature("capital"):
		var star := Label.new()
		star.text = "⭐"
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.z_index = ProvinceMapVisuals.Z_MAP_GLYPH
		star.add_theme_font_size_override("font_size", 22)
		star.set_meta(META_MAP_GLYPH_PX, 22)
		star.set_meta(META_MAP_GLYPH_CAPITAL, true)
		_apply_static_map_glyph_outline(star)
		star.reset_size()
		var sms := star.get_minimum_size()
		star.position = center - sms * 0.5
		node.add_child(star)

	var icon_dirs := _feature_icon_offsets_radial(_count_special_icons(province), feature_icon_ring_radius)
	var icon_i := 0
	for feature in province.special_features.keys():
		var fk := str(feature)
		if fk == "capital" or icon_i >= icon_dirs.size():
			continue
		var offs: Vector2 = icon_dirs[icon_i]
		var icon := Label.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.text = _get_feature_icon(fk)
		icon.z_index = ProvinceMapVisuals.Z_MAP_GLYPH
		icon.add_theme_font_size_override("font_size", 15)
		icon.set_meta(META_MAP_GLYPH_PX, 15)
		icon.set_meta(META_MAP_GLYPH_OFFS, offs)
		_apply_static_map_glyph_outline(icon)
		icon.reset_size()
		var ims := icon.get_minimum_size()
		icon.position = center + offs - ims * 0.5
		node.add_child(icon)
		icon_i += 1

	_create_or_update_province_name_label(province, center)

	return node


func _create_or_update_province_name_label(province: Province, center: Vector2) -> void:
	if not show_province_names or container == null:
		return

	var current_zoom := absf(container.scale.x)
	var show_details_zoom := current_zoom > province_detail_min_zoom

	var label: Label
	if _province_name_labels.has(province.id):
		label = _province_name_labels[province.id]
		if not is_instance_valid(label):
			_province_name_labels.erase(province.id)
			label = null

	if label == null:
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(label)
		_province_name_labels[province.id] = label

	label.z_index = _map_province_name_label_z_index()
	label.add_theme_font_size_override(
		"font_size",
		_scale_province_name_font(current_zoom, show_details_zoom),
	)
	_apply_province_name_label_readability_styles(label, current_zoom)
	label.reset_size()
	var ms := label.get_minimum_size()
	label.position = center - Vector2(ms.x * 0.5, 8)
	label.visible = true


func _count_special_icons(province: Province) -> int:
	var n := 0
	for feature in province.special_features.keys():
		if str(feature) != "capital":
			n += 1
	return mini(n, 4)


func _feature_icon_offsets_radial(count: int, radius: float) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	if count <= 0:
		return pts
	var mid_angle := PI * 0.5
	var span := clampf(PI * (0.42 + 0.11 * float(count - 1)), PI * 0.38, PI * 1.12)
	for i in count:
		var u := 0.5 if count == 1 else float(i) / float(count - 1)
		var ang := mid_angle - span * 0.5 + u * span
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	return pts


func _make_centroid_debug_marker(radius: float) -> Polygon2D:
	var poly := Polygon2D.new()
	var ring := PackedVector2Array()
	var segments := 12
	for i in segments:
		var a := TAU * float(i) / float(segments)
		ring.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = ring
	poly.color = Color(1.0, 0.08, 0.06, 0.95)
	poly.z_index = 500
	return poly


func _calculate_centroid(points: PackedVector2Array) -> Vector2:
	if points.size() < 3:
		return points[0] if points.size() > 0 else Vector2.ZERO

	var area := 0.0
	var cx := 0.0
	var cy := 0.0

	for i in range(points.size()):
		var p1 := points[i]
		var p2 := points[(i + 1) % points.size()]

		var cross := p1.x * p2.y - p2.x * p1.y
		area += cross
		cx += (p1.x + p2.x) * cross
		cy += (p1.y + p2.y) * cross

	area *= 0.5

	if absf(area) < 0.0001:
		var sum := Vector2.ZERO
		for p in points:
			sum += p
		return sum / float(points.size())

	cx /= (6.0 * area)
	cy /= (6.0 * area)
	return Vector2(cx, cy)


func _get_province_color(province: Province) -> Color:
	var base := _political_province_base_color(province)
	var c := _characterize_province_fill(base, province, _overlay_base_character_blend())
	if is_using_grand_stylized_map() or (not show_terrain_layer):
		if show_terrain_layer:
			# Low alpha so the high-res detailed terrain/rivers/hills/swamp/desert image (the requested upscaled map) shows as the terrain layer.
			c.a = 0.06
		else:
			# Clean political view: solid fills for ownership/infra focus (no terrain raster underneath). Matches player preference in HOI4/EU4 for clean modes.
			c.a = 0.82
	return c


func _overlay_base_character_blend() -> float:
	if supply_mode:
		return clampf(supply_overlay_base_character_blend, 0.3, 1.0)
	return 1.0


func _supply_depot_mix_amount() -> float:
	return clampf(supply_depot_fill_blend, 0.12, 0.55)


func _political_province_base_color(province: Province) -> Color:
	var land_fallback := Color(0.34, 0.34, 0.41, 0.86)
	var sea_fallback := Color(0.16, 0.33, 0.47, 0.88)
	if province.owner_tag.is_empty() or not countries.has(province.owner_tag):
		return sea_fallback if province.is_sea else land_fallback
	var nation: Variant = countries[province.owner_tag]
	if nation is Country:
		var c := nation as Country
		var col := c.color
		col.a = clampf(col.a if col.a > 0.05 else 0.85, 0.72, 0.93)
		return col
	if typeof(nation) == TYPE_DICTIONARY:
		var d: Dictionary = nation
		if d.has("color"):
			var co: Variant = d["color"]
			var cc: Color
			if typeof(co) == TYPE_COLOR:
				cc = co as Color
			else:
				cc = Color(String(co))
			cc.a = clampf(cc.a if cc.a > 0.05 else 0.85, 0.72, 0.93)
			return cc
	return land_fallback


## Terrain + development hues sit on top of political color; overlays tint afterward.
## `character_blend` pulls toward raw political fills when < 1 (used under Supply / heavy tinting).
func _characterize_province_fill(base: Color, province: Province, character_blend: float = 1.0) -> Color:
	var cb := clampf(character_blend, 0.2, 1.0)
	if province.is_sea:
		var sea_col := _shade_sea_province_fill(base)
		return base.lerp(sea_col, cb)
	var mul := _terrain_palette_multipliers(province.terrain)
	var toned := Color(
		clampf(base.r * mul.x, 0.02, 1.0),
		clampf(base.g * mul.y, 0.02, 1.0),
		clampf(base.b * mul.z, 0.02, 1.0),
		base.a,
	)
	var k := _terrain_tone_strength_for_current_zoom() * cb
	var col := base.lerp(toned, k)
	var z := maxf(_zoom_fill_characterization_scale, 0.07)
	var dev_blend := _tactical_character_blend(z, 0.82, 1.04)
	var dev_mul := clampf(development_close_zoom_multiplier, 0.78, 1.0)
	var dev_near := lerpf(1.0, dev_mul, dev_blend)
	var dev_n := clampf(float(clampi(province.development_level, 0, 50)) / 9.0, 0.0, 1.0)
	dev_n = sqrt(dev_n)
	var lighten := clampf(development_visual_lighten, 0.0, 0.2) * dev_n * cb * dev_near
	col = col.lightened(lighten)
	var warmth := clampf(development_visual_warmth, 0.0, 0.12) * cb * dev_near
	if warmth > 0.0005:
		col = col.lerp(col * Color(1.028, 1.012, 0.992, 1.0), dev_n * warmth)
	
	# Welfare burden strain tint (enhancement for social_services / cultural war systems): subtle unhealthy red/gray shift on high-burden provinces.
	# Represents unsustainable "services" load (expansive/elite anti-natal policies) draining vitality. Ties directly to Province local_supply penalty + erosion monthly + HH fuel.
	# Complements settlement vitality (healthy cyan-green). Visible in inspector + on map when zoomed; retrowave-safe, low alpha.
	if typeof(GameData) != TYPE_NIL:
		var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
		var wbur := float(ps.get("welfare_burden", {}).get(province.owner_tag if province.owner_tag else "player", 0.0))
		if wbur > 12.0:
			var wnorm := clampf((wbur - 12.0) / 60.0, 0.0, 0.9)
			var strain_tint := clampf(wnorm * 0.08 * cb, 0.0, 0.11)
			# Muted unhealthy shift: desaturate + slight red bias (strain on land/people from overreach)
			col = col.lerp(Color(0.92, 0.78, 0.82, 1.0), strain_tint)

	# Settlement / repopulation vitality: subtle cyan-green shift for "our people thriving here" (playtest feedback for relocation/policy systems).
	# Keeps retrowave aesthetic — not garish, just a living-land feel on high-settlement provinces.
	if province.settlement_level > 0.05:
		var s := clampf(province.settlement_level, 0.0, 1.5)
		var vitality := clampf(s * 0.035 * cb, 0.0, 0.12)
		col = col.lerp(Color(0.88, 1.05, 0.95, 1.0), vitality)  # soft healthy tint

	# Demo mode boost for 'strain'/'vitality' toggle (DebugOverlay/hotkey example): makes the policy/relocation effects pop visually for instant feedback.
	# Does not change underlying data; just demo re-tint path + connection to inspector on click.
	if debug_tint_mode == "strain":
		if typeof(GameData) != TYPE_NIL:
			var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			var wbur := float(ps.get("welfare_burden", {}).get(province.owner_tag if province.owner_tag else "player", 0.0))
			if wbur > 5.0:
				var wnorm := clampf((wbur - 5.0) / 50.0, 0.0, 1.0)
				col = col.lerp(Color(0.95, 0.75, 0.78, 1.0), 0.18 * wnorm * cb)
	elif debug_tint_mode == "vitality" and province.settlement_level > 0.01:
		var s := clampf(province.settlement_level, 0.0, 1.5)
		col = col.lerp(Color(0.82, 1.08, 0.92, 1.0), clampf(s * 0.09 * cb, 0.0, 0.22))
	elif debug_tint_mode == "development":
		# Development mapmode layer: amplifies existing development_visual_lighten / warmth (uses dev_n from characterize).
		# Makes high-dev provinces pop more (brighter/warmer) as a distinct visual layer without new code.
		var dev_n2 := clampf(float(clampi(province.development_level, 0, 50)) / 9.0, 0.0, 1.0)
		dev_n2 = sqrt(dev_n2)
		var dev_z := maxf(_zoom_fill_characterization_scale, 0.07)
		var dev_b2 := _tactical_character_blend(dev_z, 0.82, 1.04)
		var dev_m2 := clampf(development_close_zoom_multiplier, 0.78, 1.0)
		var dev_nr2 := lerpf(1.0, dev_m2, dev_b2)
		var dev_lighten_boost := clampf(development_visual_lighten, 0.0, 0.2) * dev_n2 * cb * dev_nr2 * 2.2  # boosted for mapmode visibility
		if dev_lighten_boost > 0.001:
			col = col.lightened(minf(0.28, dev_lighten_boost))
		var dev_warmth_boost := clampf(development_visual_warmth, 0.0, 0.12) * cb * dev_nr2 * 2.0
		if dev_warmth_boost > 0.0005:
			col = col.lerp(col * Color(1.035, 1.018, 0.99, 1.0), dev_n2 * dev_warmth_boost)
	elif debug_tint_mode == "loyalty":
		# Loyalty / foreign mil % tint layer (Phase 2 map UX): uses real GameData.get_military_loyalty_multiplier(owner) + foreign_military_pct.
		# Low loyalty (high foreign %) applies a warning tint (desat + amber bias) to show institutional strain / separatism risk on map.
		# Ties to combat (loyalty scales attack in previews/BM), production, erosion. Visible in inspector too.
		if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
			var loy: float = GameData.get_military_loyalty_multiplier(province.owner_tag if province.owner_tag else "player")
			var foreign_pct := 0.0
			var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			if ps and ps.has("foreign_military_pct"):
				foreign_pct = float(ps.get("foreign_military_pct", {}).get(province.owner_tag if province.owner_tag else "player", 0.0))
			if loy < 0.92 or foreign_pct > 0.1:  # noticeable deviation
				var lnorm := clampf((0.92 - loy) + (foreign_pct * 0.6), 0.0, 1.0)
				# Amber/desat warning for low loyalty (foreign mil drag visible on 460-prov map)
				col = col.lerp(Color(0.98, 0.90, 0.72, 1.0), clampf(lnorm * 0.16 * cb, 0.0, 0.18))
	elif debug_tint_mode == "infra":
		# Infra / road density highlight (Phase 2): uses existing built_road_neighbors + built_rail_neighbors (from Province + MapManager build_* APIs) + raw infrastructure level.
		# High density (many explicit connections or high infra) gets a steel/blue-green density boost tint + stronger dev-like lighten.
		# Leverages the InfrastructureOverlayLayer roads/rails (Line2D children rebuilt on infra changes). No new geometry; just visual emphasis for mapmode.
		var road_n := float(province.built_road_neighbors.size() if province.built_road_neighbors else 0)
		var rail_n := float(province.built_rail_neighbors.size() if province.built_rail_neighbors else 0)
		var conn_density := clampf((road_n + rail_n * 1.5) / 8.0, 0.0, 1.0)  # rail weighted; 460 map has variable wiring
		var infra_n := clampf(float(clampi(province.infrastructure, 0, 50)) / 18.0, 0.0, 1.0)
		var density := maxf(conn_density, infra_n * 0.7)
		if density > 0.12:
			# Subtle industrial/connected pop (steel-blue green tint for "developed arteries")
			var dboost := clampf(density * 0.13 * cb, 0.0, 0.16)
			col = col.lerp(Color(0.78, 0.92, 0.98, 1.0), dboost)
			# Extra lighten on high density (pairs with existing dev but specific to built infra connections)
			if density > 0.25:
				col = col.lightened(clampf(density * 0.09 * cb, 0.0, 0.12))
	elif debug_tint_mode == "region_control":
		# Region control tint: green for fully controlled strategic region by owner (from MapManager + inferred regions), light red for partial/not full.
		# Ties to regional pride bonuses, snow on high control areas, etc. Visible feedback for "taking ground" on the 460-prov map.
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("is_strategic_region_fully_controlled") and MapManager.has_method("get_province_region_id"):
			var pid := province.id
			var own := province.owner_tag if province.owner_tag else ""
			var rid := MapManager.get_province_region_id(pid) if MapManager.has_method("get_province_region_id") else 0
			if rid > 0:
				if MapManager.is_strategic_region_fully_controlled(rid, own):
					col = col.lerp(Color(0.6, 1.0, 0.6, 1.0), 0.18 * cb)  # green for full control + pride
				else:
					col = col.lerp(Color(1.0, 0.75, 0.75, 1.0), 0.1 * cb)  # light red for not fully controlled
	return col


func _shade_sea_province_fill(base: Color) -> Color:
	var deep := Color(0.05, 0.20, 0.34, clampf(base.a * 1.02, 0.74, 0.94))
	var mix := clampf(sea_political_trace, 0.0, 0.9)
	var col := deep.lerp(base, mix)
	col.r = clampf(col.r * 1.05, 0.0, 1.0)
	col.g = clampf(col.g * 1.03, 0.0, 1.0)
	return col


func _terrain_palette_multipliers(terrain_key: String) -> Vector3:
	var key := terrain_key.strip_edges().to_lower()
	match key:
		"hills":
			return Vector3(0.93, 0.89, 0.82)
		"mountains", "mountain":
			return Vector3(0.86, 0.88, 0.93)
		"desert", "arid":
			return Vector3(1.05, 0.98, 0.87)
		"tundra", "arctic":
			return Vector3(0.93, 0.96, 1.06)
		"urban":
			return Vector3(0.94, 0.95, 1.03)
		"coastal", "coast", "harbor", "port":
			return Vector3(0.90, 0.97, 1.03)
		"forest", "woods", "jungle":
			return Vector3(0.88, 0.97, 0.90)
		"marsh", "swamp":
			return Vector3(0.88, 0.93, 0.94)
		"plains", _:
			return Vector3(0.97, 0.99, 0.93)


# ====================== INTERACTION ======================

func _on_province_input(_viewport: Node, event: InputEvent, _shape_idx: int, province: Province, node: Node2D):
	# When pure spatial picking is active (no Area2D or ignoring it), this handler should not fire for hover/selection.
	# The unhandled_input path above handles clicks.
	if use_spatial_picking:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var resolved_province := province
		var resolved_node := node

		if supply_mode and _handle_supply_province_click(resolved_province):
			_select_province(resolved_province, resolved_node)
			return
		show_info_panel(resolved_province)
		_select_province(resolved_province, resolved_node)


func _clear_selection() -> void:
	if selected_province_id >= 0:
		_set_selection_outline(selected_province_id, false)
	selected_province_id = -1
	if _adjacency_preview != null and _adjacency_preview.has_method("clear_selection"):
		_adjacency_preview.call("clear_selection")
	_clear_compare_preview_outline()
	_refresh_compare_candidate_outlines()
	_update_supply_legend_text()
	_update_compare_hint_label()


## Select a province and pan the map camera to it (used by production / relocate UI).
## Now also drives the modern CameraController (ProvinceContainers) so auto-center works reliably for map tools / changes.
func focus_province_by_id(province_id: int) -> bool:
	if province_id < 0 or typeof(MapManager) == TYPE_NIL:
		return false
	var province: Province = MapManager.get_province(province_id)
	if province == null:
		return false
	var node := _province_node(province_id)
	if node == null:
		return false
	_select_province(province, node)
	var pos: Vector2 = province_centroids.get(province_id, Vector2.ZERO)
	if pos == Vector2.ZERO:
		pos = MapManager.get_province_centroid(province_id)
	var cam := get_node_or_null("MapCamera") as Camera2D
	if cam != null and pos != Vector2.ZERO:
		var tactical_z := clampf(2.4 * MapCanvasConfig.THEATER_SCALE, min_zoom, max_zoom)
		cam.global_position = _apply_camera_bounds(pos)
		cam.zoom = Vector2(tactical_z, tactical_z)
	show_info_panel(province)
	MapManager.province_selected.emit(province_id)
	return true


func _select_province(province: Province, node: Node2D) -> void:
	if selected_province_id >= 0 and selected_province_id != province.id:
		_set_selection_outline(selected_province_id, false)

	selected_province_id = province.id
	_set_selection_outline(province.id, true)
	if _adjacency_preview != null and _adjacency_preview.has_method("set_selected_province"):
		_adjacency_preview.call("set_selected_province", province.id)
	var sm := _supply_manager()
	if sm != null:
		sm.set_selected_province(province.id)
	if info_panel != null and info_panel is CanvasItem and info_panel.visible:
		show_info_panel(province)
	if _hover_province != null:
		_refresh_hover_tooltip(_hover_province)
	else:
		_clear_compare_preview_outline()
	_refresh_supply_highlights()
	_refresh_compare_candidate_outlines()
	_update_supply_legend_text()
	_update_compare_hint_label()


func _clear_hover_state() -> void:
	if _hover_fill_province_id >= 0:
		_apply_hover_fill(_hover_fill_province_id, false)
		_hover_fill_province_id = -1
	if _hover_outline_province_id >= 0:
		_set_hover_outline(_hover_outline_province_id, false)
		_hover_outline_province_id = -1
	current_hover = null
	_hover_province = null
	_set_conflict_highlight(-1)
	_set_agent_highlight(-1)
	_sync_hovered_strategic_region(null)
	_hide_hover_tooltip()


func _on_mouse_entered(node: Node2D, province: Province):
	# When spatial picking is the primary mode, completely ignore Area2D hover events.
	# This reduces overhead from hundreds of Area2D nodes at scale.
	if use_spatial_picking:
		return
	current_hover = node
	_hover_province = province
	_apply_hover_visuals(province.id, true)
	_sync_hovered_strategic_region(province)
	if show_hover_province_name:
		_refresh_hover_tooltip(province)


func _on_mouse_exited(node: Node2D) -> void:
	if use_spatial_picking:
		return   # Pure spatial mode - Area2D events are ignored
	if node != null and current_hover != node:
		return
	_clear_hover_state()


func _refresh_hover_tooltip(province: Province) -> void:
	if hover_tooltip == null or province == null:
		return
	var counterpart := _battle_counterpart_for_hover(province)
	_update_compare_preview_outline(province, counterpart)
	_refresh_compare_candidate_outlines()
	var hover_role := str(_supply_role_by_province.get(province.id, ""))
	var is_candidate := _is_compare_candidate(province.id) and counterpart == null
	var contested := ProvinceInsight.is_province_contested(province)
	var has_agent := ProvinceInsight.has_active_agent_network(province)
	var p_tag := _player_tag()
	if p_tag.is_empty():
		p_tag = ProvinceInsight.country_tag_for_province(province)
	var has_radio := (
		not p_tag.is_empty()
		and ProvinceInsight.province_benefits_country(province, p_tag)
		and MapTechnologyContext.has_support_radio_bonuses(p_tag)
	)
	var has_tech := has_radio
	if not has_tech and typeof(TechnologyManager) != TYPE_NIL and not p_tag.is_empty():
		has_tech = TechnologyManager.get_active_research_count(p_tag) > 0
	if not has_tech and not p_tag.is_empty():
		var prod_note := MapTechnologyContext.build_province_production_tech_bbcode(province, p_tag)
		has_tech = not prod_note.is_empty() and "need" in prod_note.to_lower()
	if not has_tech and not p_tag.is_empty():
		var elig_glance := MapTechnologyContext.build_build_eligibility_glance_bbcode(province, p_tag)
		has_tech = not elig_glance.is_empty() and (
			"lock" in elig_glance.to_lower()
			or "📉" in elig_glance
			or "🏔" in elig_glance
			or "↗" in elig_glance
		)
	var text := ""
	if MapZoomLODScript.show_strategic_hover_tooltip(_map_lod_tier):
		text = ProvinceInsight.build_strategic_hover_tooltip(province)
	elif MapZoomLODScript.show_compact_hover_tooltip(_map_lod_tier):
		text = ProvinceInsight.build_compact_hover_tooltip(province)
	else:
		text = ProvinceInsight.build_hover_tooltip(
			province, selected_province_id, counterpart, supply_mode, hover_role,
			is_candidate, contested, has_agent,
		)
	var mouse := get_viewport().get_mouse_position()
	var compare_active := counterpart != null
	var selected_accent := selected_province_id == province.id
	var dual := contested and has_agent
	var agent_activity := has_agent and ProvinceInsight.agent_has_daily_activity(province)
	var agent_pressure := ProvinceInsight.agent_pressure_focus_kind(province) if has_agent else ""
	if hover_role == "infra_sabotage":
		agent_pressure = "sabotage"
		if typeof(MapManager) != TYPE_NIL:
			var hover_bd: Dictionary = MapManager.get_infrastructure_repair_breakdown(province.id)
			if ProvinceInsight.daily_infra_duel_winner(province, hover_bd) == "repair":
				agent_pressure = "repair"
			elif ProvinceInsight.daily_infra_duel_winner(province, hover_bd) == "even":
				agent_pressure = "stalemate"
	elif hover_role in [
		"infra_repair", "infra_repair_engineers", "infra_duel_even",
		"engineers_stationed", "engineers_needed", "engineers_recommended", "engineers_insufficient",
	]:
		agent_pressure = (
			"repair"
			if hover_role in ["infra_repair", "infra_repair_engineers", "engineers_stationed"]
			else "stalemate"
		)
		if hover_role in ["engineers_needed", "engineers_recommended", "engineers_insufficient"]:
			agent_pressure = "sabotage"
	elif hover_role == "depot_sabotage":
		agent_pressure = "depot"
	elif hover_role == "supply_pressure":
		agent_pressure = "disrupt"
	var hover_bd_eng: Dictionary = {}
	var has_engineers := false
	var engineers_needed := false
	if typeof(MapManager) != TYPE_NIL:
		hover_bd_eng = MapManager.get_infrastructure_repair_breakdown(province.id)
		has_engineers = ProvinceInsight.has_engineers_stationed(hover_bd_eng)
		engineers_needed = ProvinceInsight.province_needs_engineer_assignment(province, hover_bd_eng)
	hover_tooltip.show_text(
		text,
		mouse,
		get_viewport().get_visible_rect().size,
		true,
		supply_mode,
		compare_active,
		selected_accent,
		is_candidate,
		contested and not compare_active,
		has_agent and not compare_active,
		has_tech and not compare_active,
		has_radio and not compare_active,
		dual and not compare_active,
		agent_activity,
		has_engineers and supply_mode and not compare_active,
		engineers_needed and supply_mode and not compare_active,
		agent_pressure,
	)
	_set_conflict_highlight(province.id if ProvinceInsight.is_province_contested(province) else -1)
	_set_agent_highlight(province.id if ProvinceInsight.has_active_agent_network(province) else -1)
	_update_compare_hint_label()


func _set_conflict_highlight(province_id: int) -> void:
	if _conflict_layer == null or not is_instance_valid(_conflict_layer):
		return
	_conflict_layer.set_highlight_province(province_id)


func _set_agent_highlight(province_id: int) -> void:
	if _agent_layer == null or not is_instance_valid(_agent_layer):
		return
	_agent_layer.set_highlight_province(province_id)


func _is_compare_candidate(province_id: int) -> bool:
	if selected_province_id < 0 or province_id == selected_province_id:
		return false
	return province_id in _compare_candidate_ids


func _battle_counterpart_for_hover(province: Province) -> Province:
	if selected_province_id < 0 or selected_province_id == province.id:
		return null
	if adjacency == null or not adjacency.are_adjacent(province.id, selected_province_id):
		return null
	if not provinces.has(selected_province_id):
		return null
	return provinces[selected_province_id] as Province


func _hide_hover_tooltip() -> void:
	_clear_compare_preview_outline()
	if hover_tooltip:
		hover_tooltip.hide_tooltip()

## Uses MapManager + MapPickGrid (when available) for fast hover detection.
## This is the primary hover mechanism when use_spatial_picking is true (hybrid with Area2D).
func _update_spatial_hover() -> void:
	if not use_spatial_picking:
		return

	var mouse_screen := get_viewport().get_mouse_position()
	# Skip expensive pick query + world transform when mouse hasn't moved (big idle CPU win after load).
	if mouse_screen.distance_squared_to(_last_hover_mouse) < 0.5:
		return
	_last_hover_mouse = mouse_screen

	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return

	var world_pos := _screen_to_world(mouse_screen)

	var pid := -1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
		pid = MapManager.get_province_at_world_pos(world_pos, true)
	if pid > 10000:
		# normalize demo virtual for hover too (log not every move; manager already logged the hit)
		pid = pid / 1000
	var new_hover_province: Province = null
	if pid >= 0 and provinces.has(pid):
		new_hover_province = provinces[pid]

	# Only update state if the hovered province actually changed
	if new_hover_province != _hover_province:
		if _hover_province != null:
			_clear_hover_state()
		if new_hover_province != null:
			_hover_province = new_hover_province
			current_hover = province_nodes.get(pid) as Node2D
			_apply_hover_visuals(pid, true)
			_sync_hovered_strategic_region(new_hover_province)
			if show_hover_province_name:
				_refresh_hover_tooltip(new_hover_province)


# ====================== INFO PANEL ======================

func show_info_panel(province: Province) -> void:
	if selected_province_id < 0 and _selected_coarse_id != 0:
		_show_coarse_territory_info(_selected_coarse_id)
		return
	if info_panel == null or province == null:
		return
	if not (info_panel is CanvasItem):
		push_warning("MapRenderer: info_panel is not a CanvasItem (type=" + str(info_panel.get_class()) + ", script=" + str(info_panel.get_script()) + ") — cannot show inspector. Check scene NodePath exports for the MapRenderer or wiring in _wire_info_panel_refs.")
		return

	_layout_map_ui()
	info_panel.visible = true

	var name_text := province.name
	if selected_province_id >= 0 and selected_province_id != province.id:
		var other := _battle_counterpart_for_hover(province)
		if other != null:
			name_text += "  ⚔ vs " + other.name
	info_name.text = name_text
	var ctrl_note := ""
	if ProvinceInsight.is_province_contested(province):
		ctrl_note = "  ⚑ held by %s" % province.controller_tag
	elif province.controller_tag != province.owner_tag and not province.controller_tag.is_empty():
		ctrl_note = " (controlled by %s)" % province.controller_tag
	info_owner.text = (
		"Owner: %s%s" % [province.owner_tag if province.owner_tag != "" else "None", ctrl_note]
	)
	info_population.text = "Population: %s" % str(province.population)
	info_terrain.text = "Terrain: " + province.terrain.capitalize()
	info_factories.text = "Factories: %d" % province.factories
	info_dev.text = "Development: %d  ·  Infrastructure: %d" % [
		province.development_level, province.infrastructure,
	]
	if info_logistics != null:
		info_logistics.text = ProvinceInsight.build_at_a_glance_logistics(province)
	if info_combat != null:
		info_combat.text = ProvinceInsight.build_combat_summary_for_inspector(
			province, selected_province_id,
		)
		# Live full display for settlement/welfare + derived (org recovery, attrition, local supply, combat def from settlement, welfare drag).
		# Uses Province getters (which bake settlement bonuses + welfare drag for supply) + explicit helper.
		var slev := province.settlement_level
		if slev > 0.01:
			var def_b := province.get_settlement_combat_def_bonus()
			info_combat.text += "\nSettlement Lv: %.2f  (+%.1f%% org, -%.1f%% attr, +supply; combat def +%.1f%%; 2.5%%/lv cap25%%)" % [
				slev, slev * 4.0, slev * 3.0, def_b * 100.0
			]
		if typeof(GameData) != TYPE_NIL:
			var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			var w := float(ps.get("welfare_burden", {}).get(province.owner_tag if province.owner_tag else "player", 0.0))
			if w > 5.0:
				info_combat.text += "\nWelfare burden: %.0f (drag on local supply/org/attrition for owner provinces)" % w
			# Show current derived from Province getters (post settlement + any welfare)
			var org_m := province.get_organization_recovery_modifier()
			var att_m := province.get_attrition_modifier()
			var sup_m := province.get_local_supply_generation_modifier()
			info_combat.text += "\n[derived: org×%.2f attr×%.2f supply+%.2f]" % [org_m, att_m, sup_m]
	# Phase 4: show outcome details (settlement_def_bonus used, winner, capture) in inspector after real assault (from map/F10).
	# (Appended here so post-assault show_info_panel displays it; consumed after.)
	if _last_combat_outcome_text != "":
		if info_combat != null:
			info_combat.text += "\n[Recent Assault Outcome: %s]" % _last_combat_outcome_text
		# Evidence print for final polish validation: confirms enhanced inspector combat feedback (from _try_execute mouse/Ctrl path + debug_stage F10 path) surfaces post-execute, before clear.
		print("[INSPECTOR COMBAT FEEDBACK EVIDENCE] Enhanced outcome appended to inspector (sett_def_bonus/winner/capture from BM result). Post-execute show_info_panel + toast. (Cleared after display; state like settlement/owner from capture persists via SaveLoad + force_refresh.)")
		_last_combat_outcome_text = ""

	# Live per-formation combat state (org/readiness/strength) for stationed land units at this province.
	# Makes persistent combat loop visible in inspector: damage from assaults, healing from supply/infra, reinforce from prod stock.
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formations_for_country"):
		var owner_t := province.owner_tag if province.owner_tag != "" else province.controller_tag
		if owner_t != "":
			var forms_here: Array = []
			for f in LeaderManager.get_formations_for_country(owner_t):
				if f != null and f.stationed_province_id == province.id and f.get_category() == "land":
					forms_here.append(f)
			if forms_here.size() > 0 and info_combat != null:
				info_combat.text += "\n--- Stationed Units (persistent combat state) ---"
				var shown := 0
				for f in forms_here:
					if shown >= 5: break  # cap for readability
					var oname := str(f.name if f.name else f.formation_id)
					var oorg := float(f.organization if "organization" in f else 1.0)
					var ordy := float(f.readiness if "readiness" in f else 1.0)
					var ostr := float(f.strength if "strength" in f else 1.0)
					info_combat.text += "\n  %s: org %.2f  rdy %.2f  str %.2f" % [oname, oorg, ordy, ostr]
					shown += 1
				if forms_here.size() > shown:
					info_combat.text += "\n  (+ %d more...)" % (forms_here.size() - shown)
	if info_modifiers != null:
		info_modifiers.text = ProvinceInsight.build_inspector_text(province, selected_province_id)
	if info_national != null:
		var conflict_note := ""
		if ProvinceInsight.is_province_contested(province):
			conflict_note = " Contested provinces show ⚑ in tooltip and diagonal stripes on the map."
		info_national.text = (
			"Inspector: Province | National | Effective columns. "
			+ "National section lists spirits, timed effects, agents, then combined rollup."
			+ conflict_note
		)

	var res_text := "Resources: "
	if province.resources.size() > 0:
		for key in province.resources:
			res_text += "%s:%s " % [key, str(province.resources[key])]
	else:
		res_text += "None"
	info_resources.text = res_text.strip_edges()

	# Quick visibility for special site economic impact
	var ssm = _get_special_site_manager()
	if ssm != null and typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_national_special_site_trade_capacity_bonus"):
		var nat_bonus := TradeManager.get_national_special_site_trade_capacity_bonus(province.owner_tag)
		if nat_bonus > 0 and info_resources != null:
			info_resources.text += "  |  Trade Cap +%d (Special Sites)" % int(nat_bonus)

	info_core.text = "Core For: " + (", ".join(province.core_for) if province.core_for.size() > 0 else "None")

	var special_list := []
	for feature in province.special_features.keys():
		var fk := str(feature)
		var level = province.special_features[feature]
		special_list.append("%s %s (Lv.%d)" % [_get_feature_icon(fk), fk.capitalize(), level])
	info_special.text = "Special: " + (", ".join(special_list) if special_list.size() > 0 else "None")

	_update_station_engineers_button(province)
	_update_infrastructure_investment_ui(province)
	_update_special_sites_ui(province)
	_update_attack_button(province)
	_update_settle_button(province)
	_update_assign_agent_button(province)


func _ensure_station_engineers_button() -> void:
	if info_panel == null:
		return
	if _btn_station_engineers != null and is_instance_valid(_btn_station_engineers):
		return
	_btn_station_engineers = Button.new()
	_btn_station_engineers.name = "BtnStationEngineers"
	_btn_station_engineers.text = "Station engineers"
	_btn_station_engineers.tooltip_text = (
		"Move an engineer-capable division here (same as a move-to-province order).\n"
		+ "Each click cycles which division moves; Shift+click picks the best match on the map.\n"
		+ "Supply overlay (L) shows URGENT / recommended / weak rings."
	)
	_btn_station_engineers.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn_station_engineers.offset_left = 210.0
	_btn_station_engineers.offset_top = 8.0
	_btn_station_engineers.offset_right = 360.0
	_btn_station_engineers.offset_bottom = 32.0
	_btn_station_engineers.visible = false
	if not _btn_station_engineers.pressed.is_connected(_on_station_engineers_pressed):
		_btn_station_engineers.pressed.connect(_on_station_engineers_pressed)
	info_panel.add_child(_btn_station_engineers)


func _update_station_engineers_button(province: Province) -> void:
	_ensure_station_engineers_button()
	if _btn_station_engineers == null:
		return
	if province == null:
		_btn_station_engineers.visible = false
		return
	var bd: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL:
		bd = MapManager.get_infrastructure_repair_breakdown(province.id)
	var level := ProvinceInsight.get_engineer_guidance_level(province, bd)
	var can_station := ProvinceInsight.province_accepts_player_engineers(province, bd)
	var p_tag := _player_tag()
	if p_tag.is_empty():
		p_tag = ProvinceInsight.country_tag_for_province(province)
	var next_name := _next_engineer_deploy_label(p_tag)
	var roster_n := 0
	if typeof(SupplyManager) != TYPE_NIL:
		roster_n = SupplyManager.get_engineer_capable_formations(p_tag).size()
	_btn_station_engineers.visible = can_station and roster_n > 0 and level != "present"
	match level:
		"critical":
			_btn_station_engineers.text = "Deploy %s (URGENT)" % next_name if not next_name.is_empty() else "Deploy engineers (URGENT)"
			_btn_station_engineers.tooltip_text = (
				"Sabotage is winning the daily duel here.\n"
				+ "Moves an engineer-capable division here (Shift+click on map).\n"
				+ "Amber pulsing ring on Supply overlay (L)."
			)
		"recommended":
			_btn_station_engineers.text = "Deploy %s" % next_name if not next_name.is_empty() else "Deploy engineers"
			_btn_station_engineers.tooltip_text = (
				"Repair is weak — engineers recommended before sabotage escalates.\n"
				+ "Shift+click province · softer amber ring on L overlay."
			)
		"present_insufficient":
			_btn_station_engineers.text = "Deploy %s (+more)" % next_name if not next_name.is_empty() else "Deploy more engineers"
			_btn_station_engineers.tooltip_text = (
				"Engineers are present but repair still loses (or barely holds).\n"
				+ "Cycle another division here or clear the ◎ agent network."
			)
		_:
			if ProvinceInsight.has_engineers_stationed(bd) and roster_n > 1:
				_btn_station_engineers.text = "Reassign %s" % next_name if not next_name.is_empty() else "Reassign engineers"
				_btn_station_engineers.visible = can_station
				_btn_station_engineers.tooltip_text = (
					"Engineers are holding repair — cycle a different division to this province."
				)
			else:
				_btn_station_engineers.text = "Deploy engineers"
				_btn_station_engineers.visible = false
	if can_station and typeof(SupplyManager) != TYPE_NIL:
		var tip_lines: PackedStringArray = [
			"Move an engineer-capable division here (updates repair at origin and destination).",
			"Shift+click on the map picks the best division; this button cycles divisions.",
		]
		for entry in SupplyManager.get_engineer_capable_formations(p_tag):
			var label := str(entry.get("display_name", "?"))
			var pid := int(entry.get("stationed_province_id", -1))
			var loc := "unassigned"
			if pid >= 0 and provinces.has(pid):
				var sp: Province = provinces[pid] as Province
				if sp != null:
					loc = sp.name
			tip_lines.append("· %s — %s" % [label, loc])
		_btn_station_engineers.tooltip_text = "\n".join(tip_lines)


# ====================== INFRASTRUCTURE INVESTMENT UI (Phase A) ======================

func _info_content_vbox() -> VBoxContainer:
	if info_name != null and info_name.get_parent() is VBoxContainer:
		return info_name.get_parent() as VBoxContainer
	var ui := get_node_or_null("UI")
	if ui == null:
		return null
	return ui.get_node_or_null("InfoPanel/InfoScroll/InfoContent") as VBoxContainer


func _ensure_infrastructure_investment_ui() -> void:
	var content := _info_content_vbox()
	if content == null:
		return

	# Always ensure the full set exists (idempotent; supports repeated show_info_panel + hot script reloads)
	if _label_invest_status == null or not is_instance_valid(_label_invest_status):
		_label_invest_status = Label.new()
		_label_invest_status.name = "LabelInvestStatus"
		_label_invest_status.text = ""
		_label_invest_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label_invest_status.custom_minimum_size = Vector2(320, 0)
		_label_invest_status.add_theme_font_size_override("font_size", 11)
		content.add_child(_label_invest_status)

	if _progress_invest == null or not is_instance_valid(_progress_invest):
		_progress_invest = ProgressBar.new()
		_progress_invest.name = "ProgressInvest"
		_progress_invest.custom_minimum_size = Vector2(320, 14)
		_progress_invest.max_value = 100.0
		_progress_invest.value = 0.0
		_progress_invest.visible = false
		_progress_invest.modulate = Color(0.6, 0.95, 0.85, 0.95)
		content.add_child(_progress_invest)

	if _label_invest_modifiers == null or not is_instance_valid(_label_invest_modifiers):
		_label_invest_modifiers = Label.new()
		_label_invest_modifiers.name = "LabelInvestModifiers"
		_label_invest_modifiers.text = ""
		_label_invest_modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label_invest_modifiers.custom_minimum_size = Vector2(320, 0)
		_label_invest_modifiers.add_theme_font_size_override("font_size", 10)
		_label_invest_modifiers.visible = false
		content.add_child(_label_invest_modifiers)

	if _btn_invest_infra == null or not is_instance_valid(_btn_invest_infra):
		_btn_invest_infra = Button.new()
		_btn_invest_infra.name = "BtnInvestInfrastructure"
		_btn_invest_infra.text = "Invest in Infrastructure"
		_btn_invest_infra.tooltip_text = "Start a provincial development project. Raises infrastructure over time, improving supply, combat width, and unlocking advanced factory types. Cost scales with current level."
		_btn_invest_infra.custom_minimum_size = Vector2(200, 28)
		_btn_invest_infra.visible = false
		if not _btn_invest_infra.pressed.is_connected(_on_invest_infrastructure_pressed):
			_btn_invest_infra.pressed.connect(_on_invest_infrastructure_pressed)
		content.add_child(_btn_invest_infra)

	if _btn_cancel_invest == null or not is_instance_valid(_btn_cancel_invest):
		_btn_cancel_invest = Button.new()
		_btn_cancel_invest.name = "BtnCancelInvest"
		_btn_cancel_invest.text = "Cancel Project"
		_btn_cancel_invest.tooltip_text = "Cancel the active infrastructure investment (no refund, progress lost)."
		_btn_cancel_invest.custom_minimum_size = Vector2(140, 24)
		_btn_cancel_invest.visible = false
		if not _btn_cancel_invest.pressed.is_connected(_on_cancel_infra_project_pressed):
			_btn_cancel_invest.pressed.connect(_on_cancel_infra_project_pressed)
		content.add_child(_btn_cancel_invest)

	if _btn_assign_agent == null or not is_instance_valid(_btn_assign_agent):
		_btn_assign_agent = Button.new()
		_btn_assign_agent.name = "BtnAssignAgent"
		_btn_assign_agent.text = "Assign Agent Here"
		_btn_assign_agent.tooltip_text = (
			"Establish an agent network on this province (infrastructure sabotage or intelligence).\n"
			+ "Uses AgentManager when available; refreshes agent overlay and province modifiers."
		)
		_btn_assign_agent.custom_minimum_size = Vector2(200, 28)
		_btn_assign_agent.visible = false
		if not _btn_assign_agent.pressed.is_connected(_on_assign_agent_pressed):
			_btn_assign_agent.pressed.connect(_on_assign_agent_pressed)
		content.add_child(_btn_assign_agent)


func _update_assign_agent_button(province: Province) -> void:
	_ensure_infrastructure_investment_ui()
	if _btn_assign_agent == null:
		return
	if province == null or province.is_sea:
		_btn_assign_agent.visible = false
		return
	var player_tag := _player_tag()
	var owner := province.owner_tag
	var show_ui: bool = not owner.is_empty() and (owner == player_tag or OS.is_debug_build())
	if typeof(AgentManager) == TYPE_NIL:
		show_ui = false
	_btn_assign_agent.visible = show_ui
	if not show_ui:
		return
	var has_net := false
	if typeof(ProvinceInsight) != TYPE_NIL:
		has_net = ProvinceInsight.has_active_agent_network(province)
	if has_net:
		_btn_assign_agent.text = "Agent Network Active"
		_btn_assign_agent.disabled = true
	else:
		_btn_assign_agent.text = "Assign Agent Here"
		_btn_assign_agent.disabled = false


func _on_assign_agent_pressed() -> void:
	debug_assign_random_agent_mission_here()
	if selected_province_id >= 0 and provinces.has(selected_province_id):
		show_info_panel(provinces[selected_province_id])


func _update_infrastructure_investment_ui(province: Province) -> void:
	_ensure_infrastructure_investment_ui()
	if _btn_invest_infra == null or _label_invest_status == null:
		return
	if province == null:
		_btn_invest_infra.visible = false
		_label_invest_status.visible = false
		if _progress_invest: _progress_invest.visible = false
		if _btn_cancel_invest: _btn_cancel_invest.visible = false
		if _label_invest_modifiers: _label_invest_modifiers.visible = false
		return

	var mgr = _get_infra_manager()
	if mgr == null:
		_btn_invest_infra.visible = false
		_label_invest_status.visible = false
		if _progress_invest: _progress_invest.visible = false
		if _btn_cancel_invest: _btn_cancel_invest.visible = false
		if _label_invest_modifiers: _label_invest_modifiers.visible = false
		return

	var player_tag := _player_tag()
	var show_ui: bool = (
		mgr.should_show_investment_button(province.id, player_tag)
		if mgr.has_method("should_show_investment_button")
		else true
	)
	if not show_ui:
		_btn_invest_infra.visible = false
		_label_invest_status.visible = false
		if _progress_invest: _progress_invest.visible = false
		if _btn_cancel_invest: _btn_cancel_invest.visible = false
		if _label_invest_modifiers: _label_invest_modifiers.visible = false
		return

	_label_invest_status.visible = true
	_btn_invest_infra.visible = true

	var status: Dictionary = (
		mgr.get_project_status(province.id) if mgr.has_method("get_project_status") else {}
	)
	var has_project: bool = bool(status.get("active", false))

	# Always surface current levels + any active project card (progress bar, ETA, cancel, modifiers per DESIGN)
	var cur_infra := province.infrastructure
	var cur_dev := province.development_level

	if has_project:
		var pct := int(round(float(status.get("progress", 0.0))))
		var eta := int(status.get("eta_days", 0))
		var target := int(status.get("target_level", cur_infra + 1))
		var sabotaged := bool(status.get("is_sabotaged", false))
		var sab_note := " ⚠ Sabotage slowing progress" if sabotaged else ""
		_label_invest_status.text = "Infra Project: %d%% → Lv.%d (ETA %d days)%s" % [
			pct, target, eta, sab_note
		]
		_label_invest_status.modulate = Color(1.0, 0.85, 0.4) if sabotaged else Color(0.6, 0.95, 0.85)

		if _progress_invest:
			_progress_invest.visible = true
			_progress_invest.value = clampf(pct, 0.0, 100.0)
			_progress_invest.modulate = Color(1.0, 0.6, 0.4, 0.95) if sabotaged else Color(0.6, 0.95, 0.85, 0.95)

		# Modifiers breakdown (engineer mult, tech, stability, sabotage) + current levels always
		var mods: Dictionary = status.get("modifiers", {}) if status.has("modifiers") else {}
		var mod_bits: Array = []
		if mods.has("engineer"):
			mod_bits.append("Eng +%.1f" % float(mods["engineer"]))
		if mods.has("tech"):
			mod_bits.append("Tech +%.1f" % float(mods["tech"]))
		if mods.has("stability"):
			mod_bits.append("Stab %.1f" % float(mods["stability"]))
		if mods.has("regional"):
			mod_bits.append("Reg +%.1f" % float(mods["regional"]))
		if mods.has("sabotage"):
			mod_bits.append("Sab %.1f" % float(mods["sabotage"]))
		var mod_str := " | ".join(mod_bits) if not mod_bits.is_empty() else "Base work rate"
		if _label_invest_modifiers:
			_label_invest_modifiers.text = "Curr Lv: Infra %d / Dev %d  ·  Mods: %s" % [cur_infra, cur_dev, mod_str]
			_label_invest_modifiers.visible = true
			_label_invest_modifiers.modulate = Color(0.9, 0.95, 0.8)

		_btn_invest_infra.text = "Project Active"
		_btn_invest_infra.disabled = true

		if _btn_cancel_invest:
			_btn_cancel_invest.visible = true
			_btn_cancel_invest.disabled = false
	else:
		_label_invest_status.text = "Infra: %d  ·  Dev: %d  (Invest to raise)" % [cur_infra, cur_dev]
		_label_invest_status.modulate = Color(0.85, 0.9, 0.95)

		if _progress_invest: _progress_invest.visible = false
		if _btn_cancel_invest: _btn_cancel_invest.visible = false
		if _label_invest_modifiers:
			_label_invest_modifiers.visible = false

		_btn_invest_infra.text = "Invest in Infrastructure"
		_btn_invest_infra.disabled = false


func _on_invest_infrastructure_pressed() -> void:
	if selected_province_id < 0:
		return
	var mgr = _get_infra_manager()
	if mgr == null:
		print("InfrastructureDevelopmentManager not available yet.")
		return

	var player := _player_tag()
	var result: Dictionary = {}
	if mgr.has_method("try_start_infrastructure_investment"):
		result = mgr.try_start_infrastructure_investment(selected_province_id, player)
	else:
		# Fallback to older API — target current + 1
		var target := 0
		if provinces.has(selected_province_id):
			target = provinces[selected_province_id].infrastructure + 1
		var proj: RefCounted = (
			mgr.start_infrastructure_project(selected_province_id, target if target > 0 else 5, player)
			if mgr.has_method("start_infrastructure_project")
			else null
		)
		result = {"success": proj != null, "reason": "started via legacy call" if proj else "manager missing method"}

	if result.get("success", false):
		var eta := int(result.get("eta_days", 18))
		var cost := int(result.get("cost_pp", 0))
		var pname := ""
		if provinces.has(selected_province_id):
			pname = provinces[selected_province_id].name
		# Auto-center on the province where the infra change/project started so the player sees the update location.
		focus_province_by_id(selected_province_id)
		_show_inspector_toast(
			"Infrastructure project started%s — ETA ~%d days (spent %d Mandate)" % [
				(" in " + pname) if not pname.is_empty() else "",
				eta,
				cost,
			],
			3.0,
		)
		if provinces.has(selected_province_id):
			show_info_panel(provinces[selected_province_id])
	else:
		_show_inspector_toast(
			str(result.get("reason", "Cannot start infrastructure investment")),
			3.5,
			true,
		)


func _on_cancel_infra_project_pressed() -> void:
	if selected_province_id < 0:
		return
	var mgr = _get_infra_manager()
	if mgr == null or not mgr.has_method("cancel_project"):
		_show_inspector_toast("Cancel unavailable (manager missing)", 2.5, true)
		return
	var ok: bool = mgr.cancel_project(selected_province_id, "player_cancelled")
	if ok:
		_show_inspector_toast("Infrastructure project cancelled.", 2.5)
		if provinces.has(selected_province_id):
			show_info_panel(provinces[selected_province_id])  # refresh UI (button re-enables, bar hides)
		else:
			_update_infrastructure_investment_ui(null)
	else:
		_show_inspector_toast("No active project to cancel.", 2.0, true)


## Live refresh for inspector when infra project on selected province makes progress or completes.
## Keeps "active project %/ETA" and derived effects (supply/org) up to date without manual re-click.
func _on_infra_progress_for_inspector(pid: int, _proj: Variant, _delta: float) -> void:
	if pid == selected_province_id and info_panel != null and info_panel.visible and provinces.has(pid):
		# Refresh just the invest UI + combat derived (settlement etc already live via other)
		_update_infrastructure_investment_ui(provinces[pid])
		if info_combat != null:
			# Re-append derived if needed; full show_info_panel would re-do everything
			if typeof(GameData) != TYPE_NIL:
				var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
				var w := float(ps.get("welfare_burden", {}).get(provinces[pid].owner_tag if provinces[pid].owner_tag else "player", 0.0))
				if w > 5.0:
					# Already appended in main, but trigger visual nudge via re-show if wanted
					pass
	# Force map overlay redraw so active project pulse/% ring in InfrastructureOverlayLayer updates live (progress polled + animation)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(pid, "infrastructure_project")
	var ol := get_overlay_layer("InfrastructureOverlayLayer")
	if ol and ol.has_method("queue_redraw"):
		ol.queue_redraw()

func _on_infra_completed_for_inspector(pid: int, _new_level: int, _axis: String, _proj: Variant) -> void:
	if pid == selected_province_id and info_panel != null and info_panel.visible and provinces.has(pid):
		show_info_panel(provinces[pid])  # full refresh for new infra level effects on combat/supply
		force_refresh_tints_for_owner(provinces[pid].owner_tag)


func _connect_infra_signals_for_inspector() -> void:
	if typeof(InfrastructureDevelopmentManager) == TYPE_NIL:
		return
	if not InfrastructureDevelopmentManager.project_progress_updated.is_connected(_on_infra_progress_for_inspector):
		InfrastructureDevelopmentManager.project_progress_updated.connect(_on_infra_progress_for_inspector)
	if not InfrastructureDevelopmentManager.project_completed.is_connected(_on_infra_completed_for_inspector):
		InfrastructureDevelopmentManager.project_completed.connect(_on_infra_completed_for_inspector)


func _show_inspector_toast(message: String, duration: float = 2.5, is_error: bool = false) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(message, duration, is_error)
	else:
		print(message)


# ====================== PROVINCE ASSAULT (main combat loop) ======================

func _try_set_attack_staging(province: Province) -> bool:
	if province == null or typeof(BattleManager) == TYPE_NIL:
		return false
	var p_tag := _player_tag()
	if p_tag.is_empty():
		return false
	if _province_controlled_by(province, p_tag):
		var divisions: Array = BattleManager.get_divisions_at_province(province.id, p_tag)
		if divisions.is_empty():
			return false
		attack_staging_province_id = province.id
		debug_combat_attacker_province_id = province.id
		_show_inspector_toast(
			"Attack staging: %s — Ctrl+click adjacent enemy province" % province.name,
			2.8,
		)
		return true
	return false


func _try_execute_province_attack(target_pid: int, target_province: Province) -> bool:
	if target_province == null or typeof(BattleManager) == TYPE_NIL:
		return false
	var p_tag := _player_tag()
	if p_tag.is_empty():
		_show_inspector_toast("Set player country (TopInfoBar) before attacking.", 3.0, true)
		return true

	var from_pid := attack_staging_province_id
	if from_pid < 0:
		from_pid = debug_combat_attacker_province_id

	# Wire real combat + explicit preview with CURRENT settlement/loyalty/welfare data (Province getters + BM.can_assault; used by map click Ctrl+click, attack button, and F10 sample).
	var pre: Dictionary = {}
	if typeof(ProvinceInsight) != TYPE_NIL and provinces.has(from_pid):
		pre = ProvinceInsight.get_battle_preview(provinces[from_pid], target_province)
	var can_pre := {}
	if typeof(BattleManager) != TYPE_NIL:
		can_pre = BattleManager.can_assault_province(p_tag, target_pid, from_pid)
	var t_def_b := 0.0
	if target_province.has_method("get_settlement_combat_def_bonus"):
		t_def_b = target_province.get_settlement_combat_def_bonus()
	print("[MapRenderer] Real combat from map: PREVIEW (live Province settlement/loyalty/welfare) stage#%d vs #%d def_bonus=%.1f%% can=%s (main-loop AI auto via TimeManager; weather/air in resolver)" % [from_pid, target_pid, t_def_b*100.0, str(can_pre.get("ok",false))])
	if pre:
		print("  [MAP COMBAT PREVIEW] atk=%.2f def=%.2f (factors current settlement=% .2f on def, welfare drag, loyalty mult)" % [float(pre.get("attack_power",0)), float(pre.get("defense_power",0)), target_province.settlement_level])

	var assault: Dictionary = BattleManager.execute_province_assault(p_tag, target_pid, from_pid)
	if not bool(assault.get("success", false)):
		_show_inspector_toast(str(assault.get("reason", "Attack failed")), 3.2, true)
		return true

	var result: Dictionary = assault.get("result", {}) as Dictionary
	var winner := str(result.get("winner", ""))
	var captured := bool(result.get("province_control_change", false))
	var outcome := str(result.get("outcome", winner))
	var atk := str(result.get("attacker_tag", p_tag))
	var def: String = str(result.get("defender_tag", target_province.owner_tag))

	# Phase 4: Enhance inspector combat feedback after real assault (from map mouse or F10). Show outcome details (settlement_def_bonus used, winner, capture) in toast + inspector; log live numbers.
	# Uses BM result (context merged: settlement_def_bonus, target_settlement_level, loyalty_factor, winner, province_control_change from execute/Resolver).
	var s_def_b := float(result.get("settlement_def_bonus", 1.0))
	var t_sett_lev := float(result.get("target_settlement_level", 0.0))
	var loy_f := float(result.get("loyalty_factor", 1.0))
	var outcome_details := "winner=%s capture=%s sett_def_bonus=%.2f (target_sett=%.2f) loyalty=%.2f" % [winner, str(captured), s_def_b, t_sett_lev, loy_f]
	print("[MapRenderer] Real assault (map/F10) live numbers: " + outcome_details + " (settlement_def_bonus applied in BM.execute; see Resolver for phased scores)")
	_last_combat_outcome_text = outcome_details

	if captured:
		_show_inspector_toast(
			"%s captured %s (%s; def_bonus=%.0f%% used)" % [atk, target_province.name, outcome, (s_def_b-1.0)*100.0],
			4.0,
		)
		force_border_update()
	elif winner == "attacker":
		_show_inspector_toast(
			"Attack repulsed at %s — %s (no capture; def_bonus=%.0f%%)" % [target_province.name, outcome, (s_def_b-1.0)*100.0],
			3.5,
		)
	else:
		_show_inspector_toast(
			"%s held %s — %s (def_bonus=%.0f%%)" % [def, target_province.name, outcome, (s_def_b-1.0)*100.0],
			3.5,
		)

	if provinces.has(target_pid):
		# Auto-center on the province where the recent combat/assault change happened (capture, damage, owner shift) so visual (tint, settlement, control) is immediately visible.
		focus_province_by_id(target_pid)
		show_info_panel(provinces[target_pid])
	return true


func _province_controlled_by(province: Province, country_tag: String) -> bool:
	if province == null:
		return false
	var tag := country_tag.strip_edges().to_upper()
	var ctrl := province.controller_tag.strip_edges().to_upper()
	if not ctrl.is_empty():
		return ctrl == tag
	return province.owner_tag.strip_edges().to_upper() == tag


func _ensure_attack_button() -> void:
	if info_panel == null:
		return
	if _btn_attack != null and is_instance_valid(_btn_attack):
		return
	_btn_attack = Button.new()
	_btn_attack.name = "BtnAttackProvince"
	_btn_attack.text = "Attack (Ctrl+click target)"
	_btn_attack.tooltip_text = (
		"Select a friendly province with a division, then Ctrl+click an adjacent enemy province.\n"
		+ "Or click this button while viewing an attackable neighbor."
	)
	_btn_attack.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn_attack.offset_left = 210.0
	_btn_attack.offset_top = 8.0
	_btn_attack.offset_right = 440.0
	_btn_attack.offset_bottom = 32.0
	_btn_attack.visible = false
	if not _btn_attack.pressed.is_connected(_on_attack_province_pressed):
		_btn_attack.pressed.connect(_on_attack_province_pressed)
	info_panel.add_child(_btn_attack)


func _update_attack_button(province: Province) -> void:
	_ensure_attack_button()
	if _btn_attack == null:
		return
	if province == null or typeof(BattleManager) == TYPE_NIL:
		_btn_attack.visible = false
		return

	var p_tag := _player_tag()
	if p_tag.is_empty():
		_btn_attack.visible = false
		return

	var preview: Dictionary = BattleManager.can_assault_province(
		p_tag,
		province.id,
		attack_staging_province_id if attack_staging_province_id >= 0 else debug_combat_attacker_province_id,
	)
	var can_attack := bool(preview.get("ok", false))
	_btn_attack.visible = can_attack
	if can_attack:
		_btn_attack.text = "Attack from %s" % str(preview.get("from_province_name", "adjacent"))
		_btn_attack.tooltip_text = (
			"Launch assault on %s using %s.\nCtrl+click works from the map too."
			% [province.name, str(preview.get("division_name", preview.get("formation_id", "division")))]
		)


func _on_attack_province_pressed() -> void:
	if selected_province_id < 0:
		return
	if not provinces.has(selected_province_id):
		return
	_try_execute_province_attack(selected_province_id, provinces[selected_province_id])


# Direct inspector action button enhancement: "Settle this province now" on the clicked/selected prov (real Province mutate + live tint/inspector via emit).
func _ensure_settle_button() -> void:
	if info_panel == null:
		return
	if _btn_settle != null and is_instance_valid(_btn_settle):
		return
	_btn_settle = Button.new()
	_btn_settle.name = "BtnSettleProvince"
	_btn_settle.text = "🏠 Settle This Province Now (+0.35)"
	_btn_settle.tooltip_text = (
		"Direct action on selected/inspected province: bumps settlement_level.\n"
		+ "Real Province data + MapManager emit → map vitality tint update + inspector refresh + combat/supply bonuses live.\n"
		+ "For test harness / mapmode verification on 460-prov Europe."
	)
	_btn_settle.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_btn_settle.offset_left = 8.0
	_btn_settle.offset_top = 38.0   # below close/spirits row
	_btn_settle.offset_right = 225.0
	_btn_settle.offset_bottom = 62.0
	_btn_settle.visible = false
	if not _btn_settle.pressed.is_connected(_on_settle_province_pressed):
		_btn_settle.pressed.connect(_on_settle_province_pressed)
	info_panel.add_child(_btn_settle)


func _update_settle_button(province: Province) -> void:
	_ensure_settle_button()
	if _btn_settle == null:
		return
	if province == null or province.is_sea:
		_btn_settle.visible = false
		return
	_btn_settle.visible = true
	_btn_settle.text = "🏠 Settle #%d (+0.35, now %.2f)" % [province.id, province.settlement_level]
	_btn_settle.tooltip_text = "Settle this province now (real data). After click: vitality tint strengthens (cyan-green via characterize), inspector shows updated bonuses, combat def +2.5%/lev. Use with map modes (F3 vitality)."


func _on_settle_province_pressed() -> void:
	# Delegate to the public debug helper (reuses real Province + emit path, toasts/logs)
	debug_settle_selected_province(0.35)


# ====================== SPECIAL SITES UI (InfoPanel) ======================

func _update_special_sites_ui(province: Province) -> void:
	_ensure_special_sites_ui()
	if _label_special_sites_header == null or _special_sites_container == null:
		return
	if province == null:
		_label_special_sites_header.visible = false
		_special_sites_container.visible = false
		return

	var sites := province.special_sites
	if sites.is_empty():
		_label_special_sites_header.visible = true
		_label_special_sites_header.text = "Special Sites (None)"
		_special_sites_container.visible = true

		# Clear previous
		for child in _special_sites_container.get_children():
			child.queue_free()

		# === Real Site Construction Picker ===
		var ssm = _get_special_site_manager()
		if ssm != null and ssm.has_method("get_constructible_sites_for_province"):
			var available := ssm.get_constructible_sites_for_province(province) as Array
			if available.size() > 0:
				var header := Label.new()
				header.text = "Available Constructions:"
				header.add_theme_font_size_override("font_size", 11)
				_special_sites_container.add_child(header)

				for site_id_var in available:
					var site_id := str(site_id_var)
					var def: Dictionary = (
						ssm.get_site_definition(site_id) if ssm.has_method("get_site_definition") else {}
					)
					var name := str(def.get("name", site_id)) if def else site_id

					var cons := def.get("construction", {}) as Dictionary if def else {}
					var req_infra := int(cons.get("required_infra_level", 1))
					var days := int(cons.get("base_days", 30))
					var pp := int(cons.get("political_power_cost", 50))

					var row := HBoxContainer.new()
					_special_sites_container.add_child(row)

					var info_label := Label.new()
					info_label.text = "%s (Infra %d, %d days, %d PP)" % [name, req_infra, days, pp]
					info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					row.add_child(info_label)

					# Effects summary from JSON
					var effects := def.get("effects", {}) as Dictionary if def else {}
					var eff_parts := []
					for k in effects:
						var val: Variant = effects[k]
						if val is float or val is int:
							if val > 0:
								eff_parts.append("+%d %s" % [int(val), str(k).replace("_", " ").capitalize()])
					if eff_parts.size() > 0:
						var eff_label := Label.new()
						eff_label.text = "  " + " · ".join(eff_parts)
						eff_label.add_theme_font_size_override("font_size", 9)
						eff_label.modulate = Color(0.6, 0.9, 0.7)
						row.add_child(eff_label)

					var btn := Button.new()
					btn.text = "Build"
					btn.custom_minimum_size = Vector2(70, 24)
					btn.pressed.connect(_on_construct_special_site_pressed.bind(province.id, site_id))
					row.add_child(btn)
			else:
				var note := Label.new()
				note.text = "No special sites available at current infrastructure level."
				note.add_theme_font_size_override("font_size", 10)
				_special_sites_container.add_child(note)
		else:
			# Fallback
			var build_btn := Button.new()
			build_btn.text = "Construct New Special Site (Port)"
			build_btn.pressed.connect(_on_start_special_site_construction_pressed.bind(province.id))
			_special_sites_container.add_child(build_btn)
		return

	_label_special_sites_header.visible = true
	_special_sites_container.visible = true

	# Clear previous
	for child in _special_sites_container.get_children():
		child.queue_free()

	_label_special_sites_header.text = "Special Sites (%d)" % sites.size()

	# Show national trade capacity bonus from special sites (makes the economic impact visible)
	var ssm = _get_special_site_manager()
	if ssm != null and typeof(TradeManager) != TYPE_NIL and TradeManager.has_method("get_national_special_site_trade_capacity_bonus"):
		var bonus := TradeManager.get_national_special_site_trade_capacity_bonus(province.owner_tag)
		if bonus > 0:
			var bonus_label := Label.new()
			bonus_label.text = "National Trade Capacity +%d from special sites" % int(bonus)
			bonus_label.add_theme_font_size_override("font_size", 10)
			bonus_label.modulate = Color(0.6, 0.9, 0.7)
			_special_sites_container.add_child(bonus_label)

	for site in sites:
		if site == null:
			continue

		var row := HBoxContainer.new()
		_special_sites_container.add_child(row)

		var name_label := Label.new()
		var state_icon := "✓" if site.is_completed() else "🚧" if site.is_under_construction() else "⚠"
		var dmg := " [Dmg %d]" % site.damage_level if site.is_damaged() else ""
		name_label.text = "%s %s (T%d)%s" % [state_icon, site.id, site.tier, dmg]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		if site.is_damaged():
			var repair_btn := Button.new()
			repair_btn.text = "Repair"
			repair_btn.custom_minimum_size = Vector2(60, 24)
			repair_btn.pressed.connect(_on_repair_special_site_pressed.bind(province.id, site))
			row.add_child(repair_btn)

		if site.can_be_upgraded():
			var target_def := {}
			if ssm != null and ssm.has_method("get_site_definition"):
				target_def = ssm.get_site_definition(site.get_upgrade_target_id())

			var cons := target_def.get("construction", {}) as Dictionary if target_def else {}
			var up_days := int(cons.get("base_days", 60))
			var up_pp := int(cons.get("political_power_cost", 100))

			var upgrade_btn := Button.new()
			upgrade_btn.text = "Upgrade → T%d (%d days, %d PP)" % [site.tier + 1, up_days, up_pp]
			upgrade_btn.custom_minimum_size = Vector2(160, 24)
			upgrade_btn.pressed.connect(_on_upgrade_special_site_pressed.bind(province.id, site))
			row.add_child(upgrade_btn)

		# Show key effects
		var effects_label := Label.new()
		var eff_text := ""
		if site.supply_bonus > 0:
			eff_text += "+%d Supply " % int(site.supply_bonus)
		if site.trade_capacity > 0:
			eff_text += "+%d Trade" % int(site.trade_capacity)
		effects_label.text = eff_text.strip_edges()
		effects_label.add_theme_font_size_override("font_size", 10)
		row.add_child(effects_label)


func _ensure_special_sites_ui() -> void:
	var content := _info_content_vbox()
	if content == null:
		return
	if _label_special_sites_header != null and is_instance_valid(_label_special_sites_header):
		return

	_label_special_sites_header = Label.new()
	_label_special_sites_header.name = "LabelSpecialSitesHeader"
	_label_special_sites_header.text = "Special Sites"
	_label_special_sites_header.add_theme_font_size_override("font_size", 12)
	content.add_child(_label_special_sites_header)

	_special_sites_container = VBoxContainer.new()
	_special_sites_container.name = "SpecialSitesContainer"
	_special_sites_container.add_theme_constant_override("separation", 4)
	content.add_child(_special_sites_container)


func _on_repair_special_site_pressed(province_id: int, site: SpecialSite) -> void:
	if site == null or not site.is_damaged():
		return

	var repair_amount := 1

	# Sophisticated repair: engineers present give bonus repair
	var mgr = _get_infra_manager()
	if mgr != null and mgr.has_method("get_engineer_brigades_in_province"):
		var engineers: float = float(mgr.get_engineer_brigades_in_province(province_id))
		if engineers > 0.5:
			repair_amount += 1   # engineers speed up special site repair too

	site.repair_damage(repair_amount)

	# Notify systems
	if typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(province_id, "special_site")

	# Refresh the panel
	if provinces.has(province_id):
		show_info_panel(provinces[province_id])

	print("Repaired special site %s in province %d (amount %d)" % [site.id, province_id, repair_amount])


func _on_upgrade_special_site_pressed(province_id: int, site: SpecialSite) -> void:
	if site == null or not site.can_be_upgraded():
		return

	var mgr = _get_infra_manager()
	if mgr == null or not mgr.has_method("start_special_site_upgrade_project"):
		# Fallback: instant upgrade for debug
		site.complete_upgrade()
		if typeof(MapManager) != TYPE_NIL:
			MapManager.notify_province_changed(province_id, "special_site")
		if provinces.has(province_id):
			show_info_panel(provinces[province_id])
		print("Instant upgraded special site (fallback)")
		return

	var player := _player_tag()
	var proj: RefCounted = mgr.start_special_site_upgrade_project(province_id, site, player)
	if proj:
		print("Started upgrade project for special site %s in province %d" % [site.id, province_id])
		if provinces.has(province_id):
			show_info_panel(provinces[province_id])
	else:
		print("Could not start upgrade project")


func _on_start_special_site_construction_pressed(province_id: int) -> void:
	var mgr = _get_infra_manager()
	if mgr == null or not mgr.has_method("debug_start_special_site_project"):
		return

	var player := _player_tag()
	mgr.debug_start_special_site_project(province_id, "port_tier_2", player)   # MVP: starts real project for basic port

	if provinces.has(province_id):
		show_info_panel(provinces[province_id])


func _on_construct_special_site_pressed(province_id: int, site_id: String) -> void:
	var mgr = _get_infra_manager()
	if mgr == null or not mgr.has_method("start_special_site_project"):
		print("Cannot start special site project - manager missing method")
		return

	var player := _player_tag()
	var proj: RefCounted = mgr.start_special_site_project(province_id, site_id, player)
	if proj:
		print("Started real special site construction project: %s in province %d" % [site_id, province_id])
	else:
		print("Failed to start special site project for %s" % site_id)

	if provinces.has(province_id):
		show_info_panel(provinces[province_id])


func _get_special_site_manager() -> Object:
	return get_node_or_null("/root/SpecialSiteManager")


func _get_infra_manager() -> Object:
	if typeof(InfrastructureDevelopmentManager) != TYPE_NIL:
		return InfrastructureDevelopmentManager
	# Fallback for early boot / tests
	return get_node_or_null("/root/InfrastructureDevelopmentManager")


func _next_engineer_deploy_label(country_tag: String) -> String:
	if typeof(SupplyManager) == TYPE_NIL:
		return "engineers"
	var formations := SupplyManager.get_engineer_capable_formations(country_tag)
	if formations.is_empty():
		return ""
	_engineer_deploy_pick_index = _engineer_deploy_pick_index % formations.size()
	var entry: Dictionary = formations[_engineer_deploy_pick_index]
	var name := str(entry.get("display_name", ""))
	if name.length() > 22:
		name = name.substr(0, 20) + "…"
	return name if not name.is_empty() else "engineers"


func _formation_id_for_deploy(country_tag: String, province: Province, use_cycle: bool) -> String:
	if typeof(SupplyManager) == TYPE_NIL:
		return ""
	if use_cycle:
		var formations := SupplyManager.get_engineer_capable_formations(country_tag)
		if formations.is_empty():
			return ""
		_engineer_deploy_pick_index = _engineer_deploy_pick_index % formations.size()
		var fid := str(formations[_engineer_deploy_pick_index].get("formation_id", ""))
		_engineer_deploy_pick_index += 1
		return fid
	return SupplyManager.pick_formation_for_engineer_deployment(country_tag, province.id)


func _try_station_engineers_at_province(
	province: Province,
	_brigade_equiv: float = 1.0,
	use_cycle: bool = false,
) -> bool:
	if province == null or typeof(SupplyManager) == TYPE_NIL:
		return false
	var tag := _player_tag()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	var bd_before: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL:
		bd_before = MapManager.get_infrastructure_repair_breakdown(province.id)
	var level_before := ProvinceInsight.get_engineer_guidance_level(province, bd_before)
	var fid := _formation_id_for_deploy(tag, province, use_cycle)
	var result: Dictionary = FormationMovement.move_engineer_formation_to_province(
		fid, province.id, tag,
	)
	if not bool(result.get("ok", false)):
		var err := str(result.get("error", "Could not station engineers"))
		var msg := ProvinceInsight.build_engineer_assignment_toast_message(
			province, false, level_before, "", 0.0, err, result,
		)
		_trigger_engineer_assignment_flash(province.id, false)
		if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
			LeaderEventUI.show_toast(msg, 3.5, true)
		return false
	var bd_after: Dictionary = bd_before
	if typeof(MapManager) != TYPE_NIL:
		bd_after = MapManager.get_infrastructure_repair_breakdown(province.id)
	var level_after := str(result.get("guidance_after", ""))
	if level_after.is_empty():
		level_after = ProvinceInsight.get_engineer_guidance_level(province, bd_after)
	var eng := float(result.get("engineer_brigades", 0.0))
	_trigger_engineer_assignment_flash(province.id, true, "arrived")
	_refresh_supply_highlights()
	_refresh_single_province_fill(province.id)
	var moved_from_pid := int(result.get("moved_from_province_id", -1))
	if moved_from_pid >= 0 and moved_from_pid != province.id:
		_trigger_engineer_assignment_flash(moved_from_pid, true, "departed")
		_refresh_single_province_fill(moved_from_pid)
		if _hover_province != null and _hover_province.id == moved_from_pid:
			_refresh_hover_tooltip(_hover_province)
		if selected_province_id == moved_from_pid:
			var origin_p: Province = MapManager.get_province(moved_from_pid) if typeof(MapManager) != TYPE_NIL else null
			if origin_p != null:
				show_info_panel(origin_p)
	if _hover_province != null and _hover_province.id == province.id:
		_refresh_hover_tooltip(province)
	if selected_province_id == province.id:
		show_info_panel(province)
		_select_province(province, _province_node(province.id))
	var msg_ok := ProvinceInsight.build_engineer_assignment_toast_message(
		province, true, level_before, level_after, eng, "", result,
	)
	if not supply_mode:
		msg_ok += " · Press L for Supply overlay rings"
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(msg_ok, 4.0)
	return true


func _trigger_engineer_assignment_flash(
	province_id: int,
	success: bool,
	kind: String = "arrived",
) -> void:
	_engineer_assign_flash_by_province[province_id] = {
		"until_msec": Time.get_ticks_msec() + _ENGINEER_ASSIGN_FLASH_MS,
		"success": success,
		"kind": kind,
	}
	var node := _province_node(province_id)
	if node == null:
		return
	var role := "engineers_stationed" if success else "engineers_needed"
	if kind == "departed":
		role = "engineers_recommended"
	var style: Dictionary = ProvinceMapVisuals.get_supply_outline_style(role)
	ProvinceMapVisuals.ensure_polished_outline(
		node,
		_province_polygon(node),
		ProvinceMapVisuals.NODE_SUPPLY,
		style["color"],
		style["width"],
		style["glow"],
		style["glow_extra"],
		style["z_index"],
	)


func _apply_engineer_assignment_flash_pulses() -> void:
	var now := Time.get_ticks_msec()
	var expired: Array[int] = []
	for pid in _engineer_assign_flash_by_province.keys():
		var flash: Dictionary = _engineer_assign_flash_by_province[pid]
		if now > int(flash.get("until_msec", 0)):
			expired.append(pid)
			continue
		var node := _province_node(int(pid))
		if node == null:
			continue
		var success := bool(flash.get("success", true))
		var kind := str(flash.get("kind", "arrived"))
		var col := ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED
		var glow := ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED_GLOW
		var pulse_amt := 0.62
		if not success:
			col = ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE
			glow = ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE_GLOW
			pulse_amt = 0.44
		elif kind == "departed":
			pulse_amt = 0.30
		var boost := 0.48 + 0.28 * sin(_outline_pulse_phase * 5.25 + float(pid) * 0.4)
		ProvinceMapVisuals.apply_pulse_to_polished(
			node,
			ProvinceMapVisuals.NODE_SUPPLY,
			col,
			3.05 + boost,
			glow,
			5.1 + boost * 1.75,
			_outline_pulse_phase + float(pid) * 0.2,
			pulse_amt,
			1.38,
		)
	for pid in expired:
		_engineer_assign_flash_by_province.erase(pid)
	if not expired.is_empty():
		_refresh_supply_highlights()


func _on_station_engineers_pressed() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		return
	var province: Province = provinces[selected_province_id] as Province
	var ok := _try_station_engineers_at_province(province, 1.0, true)
	if ok:
		# Auto-center on the province where engineers were (re)stationed so the repair/supply visual update is seen.
		focus_province_by_id(selected_province_id)


#region Overlay layer infrastructure (preparing for M3 gameplay overlays)
## Clean API for adding future layers (AgentNetworkLayer, ConflictOverlayLayer, TechBuildLayer, etc.)
## All overlay layers live under ProvinceContainers so they move/zoom with the map.
## Data for overlays is best accessed via MapManager (centroids, bounds, adjacency, effects, etc.).
func add_overlay_layer(layer_name: String, layer_node: Node2D, z_index: int = 0) -> void:
	if container == null or layer_node == null:
		return
	layer_node.name = layer_name
	layer_node.z_index = z_index   # Allows basic ordering (e.g. supply routes behind conflict lines)
	var existing := container.get_node_or_null(layer_name)
	if existing:
		existing.queue_free()
	container.add_child(layer_node)

func remove_overlay_layer(layer_name: String) -> void:
	if container == null:
		return
	var existing := container.get_node_or_null(layer_name)
	if existing:
		existing.queue_free()

func get_active_overlay_layers() -> Array[String]:
	## Returns names of active custom overlay layers added via add_overlay_layer.
	## Excludes core map elements. Useful for UI/debug.
	var names: Array[String] = []
	if container == null:
		return names
	var excluded: Array[String] = ["SupplyMapLayer", "ProvinceContainers"]
	for child in container.get_children():
		if child is Node2D:
			var n := child.name
			if n not in excluded and not n.begins_with("Prov_") and not n.ends_with("Outline") and not n.ends_with("Glow"):
				names.append(n)
	return names

func get_overlay_layer(name: String) -> Node2D:
	if container == null:
		return null
	return container.get_node_or_null(name) as Node2D

## Convenience for toggling the new dynamic infra layers (roads/rails/cities/sites) from UI or input.
## These layers visualize player-built infrastructure (via projects) making the map "come alive".
func set_infra_layer_visibility(show_roads: bool, show_rails: bool, show_cities: bool, show_sites: bool = true):
	var ol := get_overlay_layer("InfrastructureOverlayLayer")
	if ol and ol.has_method("set_show_roads"):
		ol.set_show_roads(show_roads)
		ol.set_show_rails(show_rails)
		ol.set_show_cities(show_cities)
		if ol.has_method("set_show_sites"):
			ol.set_show_sites(show_sites)

func _setup_conflict_layer() -> void:
	if not show_conflict_overlay or container == null:
		remove_overlay_layer("ConflictOverlay")
		_conflict_layer = null
		return
	if _conflict_layer == null or not is_instance_valid(_conflict_layer):
		_conflict_layer = ConflictOverlayLayer.new()
	var centroids := province_centroids
	var provs := provinces
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("get_all_centroids"):
			centroids = MapManager.get_all_centroids()
		if MapManager.has_method("get_all_provinces"):
			provs = MapManager.get_all_provinces()
	_conflict_layer.setup_with_map(container, centroids, provs, geometry)
	add_overlay_layer("ConflictOverlay", _conflict_layer, -1)


## Convenience alias for scenes/scripts that call this after map init.
func setup_demo_conflict_overlay() -> void:
	_setup_conflict_layer()


func _setup_agent_layer() -> void:
	if not show_agent_overlay or container == null:
		remove_overlay_layer("AgentNetworkLayer")
		_agent_layer = null
		return
	if _agent_layer == null or not is_instance_valid(_agent_layer):
		_agent_layer = AgentNetworkLayer.new()
	var sm := _supply_manager()
	if sm != null and sm.get("player_tag"):
		_agent_layer.target_country = str(sm.player_tag).strip_edges().to_upper()
	else:
		_agent_layer.target_country = ""
	_agent_layer.setup()
	add_overlay_layer("AgentNetworkLayer", _agent_layer, 6)


func setup_demo_agent_overlay() -> void:
	_setup_agent_layer()

## Always-on infrastructure visual layer (roads/rail/cities + special sites).
## This is the key "map comes alive" element: decisions (infra projects, special sites, explicit road builds)
## update province data -> emit -> overlay rebuilds its Node2D sub-layers (editable Line2D etc).
## Toggle with R/T/C (hotkeys) or F10 Debug buttons. Rebuilt live on project complete.
func _setup_infrastructure_overlay_layer() -> void:
	if container == null:
		return
	var existing := get_overlay_layer("InfrastructureOverlayLayer")
	if existing != null and is_instance_valid(existing):
		# Already present (e.g. from TestRunner or prior render); just ensure group + rebuild
		if not existing.is_in_group("infrastructure_overlay"):
			existing.add_to_group("infrastructure_overlay")
		if existing.has_method("rebuild_all_infra_layers"):
			existing.rebuild_all_infra_layers()
		return
	# Use load() for the layer script to be resilient to compile order / class resolution during full project checks
	# (historical parse cascades showed "Could not resolve class InfrastructureOverlayLayer" when the overlay file itself had temporary syntax issues).
	var LayerScript := load("res://scripts/map/InfrastructureOverlayLayer.gd")
	if LayerScript == null:
		push_error("MapRenderer: Could not load InfrastructureOverlayLayer.gd")
		return
	var layer: Node = null
	if LayerScript is GDScript:
		layer = LayerScript.new()
	if layer == null:
		return
	add_overlay_layer("InfrastructureOverlayLayer", layer, 8)
	# group is added inside layer._ready, but ensure
	if not layer.is_in_group("infrastructure_overlay"):
		layer.add_to_group("infrastructure_overlay")
	print("MapRenderer: InfrastructureOverlayLayer created and added (roads/rails/cities + special sites live layer).")

func setup_demo_infrastructure_overlay() -> void:
	_setup_infrastructure_overlay_layer()


func _setup_terrain_layer_stack() -> void:
	if container == null:
		return
	var existing := find_child("TerrainLayerStack", true, false) as TerrainLayerStack
	if existing != null and is_instance_valid(existing):
		terrain_layer_stack = existing
		if is_using_world_grand_map():
			if existing.try_load_world_from_metadata():
				existing.configure_for_world_launch()
				existing.fit_to_bounds(WORLD_CANONICAL_BOUNDS)
				_position_terrain_above_background()
				_apply_terrain_layer_visibility()
				_mount_peak_snow_overlay()
		return
	var stack_script := load("res://scripts/map/TerrainLayerStack.gd") as GDScript
	if stack_script == null:
		return
	var stack: TerrainLayerStack = stack_script.new() as TerrainLayerStack
	if stack == null:
		return
	stack.name = "TerrainLayerStack"
	add_child(stack)
	stack.z_index = -15
	terrain_layer_stack = stack
	var loaded := false
	if is_using_world_grand_map() and stack.try_load_world_from_metadata():
		stack.fit_to_bounds(WORLD_CANONICAL_BOUNDS)
		stack.configure_for_world_launch()
		loaded = true
	elif stack.try_load_from_metadata("europe"):
		var b := get_rendered_province_bounds()
		if is_using_grand_stylized_map():
			b = GRAND_THEATER_CANONICAL_BOUNDS
		stack.fit_to_bounds(b)
		stack.show_base_layer = show_terrain_layer
		var wb := find_child("WorldBackground", true, false) as Sprite2D
		if wb and stack.has_base_texture():
			wb.visible = false
		loaded = true
	if loaded:
		_apply_terrain_layer_visibility()
		_mount_peak_snow_overlay()
		print("MapRenderer: TerrainLayerStack active (U=rivers/lakes, H=elevation/mountains, V=vegetation, S=snow ref).")
		if terrain_layer_stack and terrain_layer_stack.has_method("set_layer_alphas"):
			terrain_layer_stack.call("set_layer_alphas", 0.9, 0.85)


func _setup_weather_overlay_layer() -> void:
	if container == null:
		return
	# WeatherManager is now registered as autoload (project.godot), so always available as singleton.
	# Transient path kept for very early headless/test setups before autoload fully wired.
	var wm = null
	if Engine.has_singleton("WeatherManager"):
		wm = Engine.get_singleton("WeatherManager")
	if wm == null:
		wm = get_node_or_null("/root/WeatherManager")
	if wm == null and get_tree() != null and get_tree().root != null:
		if get_tree().root.has_meta("weather_manager"):
			wm = get_tree().root.get_meta("weather_manager")
		if wm == null:
			for c in get_tree().root.get_children():
				if c.name == "WeatherManager":
					wm = c
					break
	if wm == null:
		var wm_script: Script = load("res://scripts/weather/WeatherManager.gd") as Script
		if wm_script == null:
			push_warning("MapRenderer: WeatherManager.gd failed to load — skipping weather overlay setup.")
			return
		wm = wm_script.new()
		if wm:
			wm.name = "WeatherManager"
			get_tree().root.set_meta("weather_manager", wm)
			get_tree().root.add_child.call_deferred(wm)
			if not Engine.has_singleton("WeatherManager"):
				Engine.register_singleton("WeatherManager", wm)
			print("MapRenderer: Created transient WeatherManager (now also autoloaded in project)")
	# Demo seeds for special pids (high north test cases) + blackout. Real integration (all inferred snow_potential provinces)
	# is handled centrally in MapManager.initialize() after it pulls _province_terrain from loader (so effects/overlay always consistent).
	if wm and wm.has_method("initialize_province"):
		for pid in [999, 998, 997]:
			var sp_demo := 0.5 if pid == 999 else (0.3 if pid == 998 else 0.0)
			wm.initialize_province(pid, {"is_northern": pid != 997, "lat": 68 if pid==999 else (60 if pid==998 else 45), "high_ground_fraction": 0.4 if pid==999 else 0.25, "snow_potential": sp_demo})
		# Blackout demo only in harness/headless — skip on normal graphical play (was spamming logs at load).

	# Robust existing check: search container and root to prevent dups from multiple inits/loads (as seen in test logs with repeated scenario applies).
	# Check by node + by name to catch deferred adds in progress.
	var existing = container.get_node_or_null("WeatherOverlayLayer")
	if not existing:
		existing = container.find_child("WeatherOverlayLayer", true, false)
	if not existing and get_tree() and get_tree().root:
		existing = get_tree().root.find_child("WeatherOverlayLayer", true, false)
	if existing:
		weather_layer = existing as Node
		if weather_layer and weather_layer.has_method("refresh_for_grand_theater"):
			weather_layer.call_deferred("refresh_for_grand_theater")
		return
	# Load defensively (same pattern as infra for compile resilience)
	var WScript := load("res://scripts/map/WeatherOverlayLayer.gd")
	var layer = (WScript as GDScript).new() if WScript is GDScript else null
	if layer == null:
		return
	layer.name = "WeatherOverlayLayer"
	container.add_child.call_deferred(layer)
	# Only print the 'added' message when we actually create one (prevents spam on re-inits from repeated scenario loads).
	if not has_meta("weather_layer_printed"):
		set_meta("weather_layer_printed", true)
		print("MapRenderer: WeatherOverlayLayer added (stub for snow progression, storms, events on GRAND THEATER bg; toggle via debug or hotkey). Hidden by default per design.")

# Recommended data access for any overlay layer:
#   MapManager.get_all_centroids()
#   MapManager.get_world_bounds()
#   MapManager.get_adjacency_system()
#   MapManager.get_province_effects(pid, tag)
#   MapManager.get_provinces_in_rect(...) for culling
#endregion


#region Supply map layer
## Polylines: trade corridors share hue with province `trade_transit` rings; drawn first beneath military routes — see `SupplyMapLayer`.
func _map_province_name_label_z_index() -> int:
	return province_name_label_z_index_supply_overlay if supply_mode else province_name_label_z_index


## Slows outline pulses while L is on so hover / supply / engineer rings do not compete visually.
func _map_overlay_pulse_speed_scale() -> float:
	return 0.82 if supply_mode else 1.0


func _sync_map_label_glyph_stack(zoom_metric: float = -1.0) -> void:
	var zz := zoom_metric
	if zz <= 0.0001 and container != null:
		zz = absf(container.scale.x)
	if zz <= 0.0001:
		zz = 1.0
	var show_glyphs := zz > province_detail_min_zoom
	for id in _province_name_labels:
		var lbl: Variant = _province_name_labels[id]
		if lbl is Label and is_instance_valid(lbl):
			var l2 := lbl as Label
			l2.z_index = _map_province_name_label_z_index()
			if show_province_names and show_glyphs:
				_apply_province_name_label_readability_styles(l2, zz)
	for pid in province_nodes:
		_layout_zoomed_map_glyphs_for_province_node(int(pid), zz, show_glyphs)


func _sync_supply_route_canvas_stack() -> void:
	if supply_map_layer == null or not is_instance_valid(supply_map_layer):
		return
	supply_map_layer.z_index = clampi(supply_route_layer_z_order, -40, 120)
	var lm := clampf(supply_route_layer_modulate_with_overlay, 0.5, 1.0)
	if supply_mode and supply_map_layer.visible:
		supply_map_layer.self_modulate = Color(lm, lm, lm, 1.0)
		supply_map_layer.trade_corridor_supply_dim = clampf(trade_corridor_supply_overlay_dim, 0.72, 1.0)
	else:
		supply_map_layer.self_modulate = Color.WHITE
		supply_map_layer.trade_corridor_supply_dim = 1.0
	_sync_map_label_glyph_stack()
	supply_map_layer.queue_redraw()


func _setup_supply_layer() -> void:
	if container == null:
		return
	if supply_map_layer == null or not is_instance_valid(supply_map_layer):
		supply_map_layer = SupplyMapLayer.new()
		supply_map_layer.name = "SupplyMapLayer"
		container.add_child(supply_map_layer)
	var sm := _supply_manager()
	if sm != null and sm.rules != null:
		supply_map_layer.setup(province_centroids, sm.rules)
	_ensure_supply_overlay_panel()
	_refresh_supply_routes()
	_sync_supply_route_canvas_stack()


func _ensure_supply_overlay_panel() -> void:
	if supply_overlay_panel != null:
		supply_overlay_panel.set_callbacks(
			_on_supply_commit, _on_supply_clear_waypoints, _on_supply_close_overlay,
		)
		return
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	supply_overlay_panel = SupplyMenuPanel.new()
	supply_overlay_panel.name = "SupplyMenuPanel"
	supply_overlay_panel.custom_minimum_size = Vector2(420, 300)
	supply_overlay_panel.position = Vector2(16, 120)
	ui.add_child(supply_overlay_panel)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_top = 12
	vbox.offset_right = -12
	vbox.offset_bottom = -12
	supply_overlay_panel.add_child(vbox)
	supply_overlay_panel.title_label = Label.new()
	supply_overlay_panel.title_label.text = "Supply command"
	vbox.add_child(supply_overlay_panel.title_label)
	supply_overlay_panel.mode_option = OptionButton.new()
	vbox.add_child(supply_overlay_panel.mode_option)
	supply_overlay_panel.setup_mode_selector()
	supply_overlay_panel.depot_label = Label.new()
	supply_overlay_panel.depot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(supply_overlay_panel.depot_label)
	supply_overlay_panel.attrition_label = Label.new()
	supply_overlay_panel.attrition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(supply_overlay_panel.attrition_label)
	supply_overlay_panel.body_label = RichTextLabel.new()
	supply_overlay_panel.body_label.fit_content = true
	supply_overlay_panel.body_label.custom_minimum_size = Vector2(380, 90)
	vbox.add_child(supply_overlay_panel.body_label)
	var row := HBoxContainer.new()
	supply_overlay_panel.btn_commit = Button.new()
	supply_overlay_panel.btn_commit.text = "Commit route"
	row.add_child(supply_overlay_panel.btn_commit)
	supply_overlay_panel.btn_clear = Button.new()
	supply_overlay_panel.btn_clear.text = "Clear waypoints"
	row.add_child(supply_overlay_panel.btn_clear)
	supply_overlay_panel.btn_close = Button.new()
	supply_overlay_panel.btn_close.text = "Close"
	row.add_child(supply_overlay_panel.btn_close)
	vbox.add_child(row)
	supply_overlay_panel.set_callbacks(
		_on_supply_commit, _on_supply_clear_waypoints, _on_supply_close_overlay,
	)
	supply_overlay_panel.set_mode_callback(_on_supply_mode_changed)


func _player_tag() -> String:
	var sm := _supply_manager()
	if sm != null and sm.get("player_tag"):
		return str(sm.player_tag).strip_edges().to_upper()
	return ""


func _supply_manager() -> Node:
	return get_tree().root.get_node_or_null("SupplyManager")


func build_supply_network(city_layer: Dictionary, player_tag: String = "USA") -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	sm.build_network(provinces, countries, city_layer, adjacency, player_tag)
	if sm.has_method("seed_demo_enemy_forces"):
		sm.seed_demo_enemy_forces()
	if sm.has_method("seed_demo_engineer_presence"):
		sm.seed_demo_engineer_presence(player_tag)
	_setup_supply_layer()


func _toggle_supply_overlay() -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	sm.toggle_overlay()
	supply_mode = sm.overlay_visible
	if supply_map_layer:
		supply_map_layer.visible = supply_mode
	if supply_mode:
		_refresh_supply_routes()
	else:
		_end_supply_reroute()
	_refresh_province_fill_colors()
	_refresh_province_detail_visibility()
	_refresh_supply_highlights()
	_update_supply_overlay_legend()
	_refresh_compare_candidate_outlines()
	if _hover_province != null:
		_refresh_hover_tooltip(_hover_province)
	if supply_overlay_panel:
		if not supply_mode:
			supply_overlay_panel.hide_panel()
	_sync_supply_route_canvas_stack()


func _refresh_supply_routes() -> void:
	var sm := _supply_manager()
	if supply_map_layer == null or sm == null:
		return
	supply_map_layer.set_routes(sm.get_all_routes())
	supply_map_layer.visible = supply_mode
	_sync_supply_route_canvas_stack()
	_refresh_supply_highlights()


func _handle_supply_province_click(province: Province) -> bool:
	var sm := _supply_manager()
	if sm == null:
		return false
	sm.set_selected_province(province.id)
	if not _supply_reroute_active:
		var source: int = sm.get_capital_hub_id()
		if source < 0:
			source = province.id
		sm.begin_player_reroute(source, province.id)
		_supply_reroute_active = true
		_show_supply_preview()
		return true
	sm.add_reroute_waypoint(province.id)
	_show_supply_preview()
	_refresh_supply_highlights()
	return true


func _show_supply_preview() -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	var plan: SupplyRoutePlan = sm.preview_player_route()
	_update_supply_menu(plan, true)
	_refresh_supply_routes()


func _update_supply_menu(plan: SupplyRoutePlan, reroute_mode: bool) -> void:
	var sm := _supply_manager()
	if sm == null or supply_overlay_panel == null:
		return
	var depot: ProvinceDepotState = sm.get_depot_state(sm.get_selected_province_id())
	if depot == null:
		depot = sm.get_depot_state(plan.target_province_id)
	var attrition: Dictionary = sm.get_attrition_cargo_summary()
	var extra := ""
	for line in sm.get_depot_menu_lines(5):
		extra += line + "\n"
	var pid: int = SupplyManager.get_selected_province_id()
	var province: Province = provinces.get(pid) as Province if provinces.has(pid) else null
	supply_overlay_panel.show_supply_state(
		plan, depot, attrition, reroute_mode, province, sm.player_tag, extra.strip_edges(),
	)


func _on_supply_mode_changed(mode: String) -> void:
	var sm := _supply_manager()
	if sm:
		sm.set_routing_mode(mode)
	_show_supply_preview()


func _on_supply_commit() -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	var plan: SupplyRoutePlan = sm.commit_player_route()
	_update_supply_menu(plan, false)
	_refresh_supply_routes()


func _on_supply_clear_waypoints() -> void:
	var sm := _supply_manager()
	if sm:
		sm.clear_reroute_waypoints()
	_show_supply_preview()


func _on_supply_close_overlay() -> void:
	_toggle_supply_overlay()


func _end_supply_reroute() -> void:
	_supply_reroute_active = false
	var sm := _supply_manager()
	if sm:
		sm.clear_reroute_waypoints()


func _refresh_province_fill_colors(refresh_all: bool = false) -> void:
	if container != null:
		_zoom_fill_characterization_scale = absf(container.scale.x)
	var use_all := refresh_all or debug_tint_mode != "" or current_map_mode != "political"
	var interesting := {} if use_all else _get_interesting_province_ids()
	for pid in province_nodes.keys():
		if interesting.size() > 0 and not interesting.has(int(pid)):
			continue  # lazy cull
		var node: Variant = province_nodes[pid]
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if not provinces.has(pid):
			continue
		var province: Province = provinces[pid] as Province
		var poly: Polygon2D = _get_province_polygon(node as Node2D)
		if poly == null:
			continue
		var col := _get_province_color(province)
		if supply_mode:
			var fill := ProvinceInsight.depot_fill_ratio(int(pid))
			if fill >= 0.0:
				col = col.lerp(_supply_depot_tint_color(fill), _supply_depot_mix_amount())
		col = _apply_agent_pressure_base_tint(col, province)
		# Riot tint for active_riots provinces (red overlay hint when political or any mode; visible on inspector hover too via single refresh)
		if typeof(GameData) != TYPE_NIL and GameData.has_method("has_active_riot") and GameData.has_active_riot(int(pid)):
			col = col.lerp(Color(0.85, 0.25, 0.25, 0.55), 0.40)  # riot red tint
		poly.color = col
	_refresh_supply_highlights()
	_fill_zoom_at_last_paint = _zoom_fill_characterization_scale


## Perf/scale helper for lazy culling in fills/overlays: return set of "active" pids worth processing (events/riots/pending research, player/majors owned, high pop/econ proxies, borders).
## Used by _refresh_province_fill_colors (lazy skip non-int) + callers for EventOverlay hints. Cheap; falls back full if no GameData.
func _get_interesting_province_ids() -> Dictionary:
	var ints := {}
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_provinces_with_active_riots"):
		for pid in GameData.get_provinces_with_active_riots():
			ints[int(pid)] = true
		# also pending research owners for ethics marker
		if GameData.has_method("get_tags_with_pending_research"):
			for tag in GameData.get_tags_with_pending_research():
				if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
					for op in MapManager.get_provinces_by_owner(tag):
						ints[int(op)] = true
	# Include majors for full (as weather culling precedent)
	for mt in ["GER", "FRA", "ENG", "SOV", "USA", "ITA", "JAP"]:
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
			for pp in MapManager.get_provinces_by_owner(mt):
				ints[int(pp)] = true
	# If player current known (via scenario or MapManager), include
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_player_tag"):
		var ptag = MapManager.get_player_tag()
		if ptag and MapManager.has_method("get_provinces_by_owner"):
			for pp in MapManager.get_provinces_by_owner(ptag):
				ints[int(pp)] = true
	if ints.is_empty():
		# fallback: all (no culling if no data)
		for pid in province_nodes.keys():
			ints[int(pid)] = true
	return ints


## Helper for NATO sheet variant: pick 64px cell region based on nation tag (color variant) + archetype/era.
## Sheet 512x512 /8x8 grid; cols vary tone (0 grey,2 blue,4 green,6 khaki per context), rows unit type rough.
func _get_nato_sheet_region(tag: String, arch: String, era: String = "ww2") -> Rect2:
	if _nato_sheet_tex == null:
		return Rect2()
	var cell := 64.0
	var col := 0
	var tagu := tag.to_upper()
	if tagu in ["SOV", "RUS"]: col = 2  # blue-ish
	elif tagu in ["GER"]: col = 6  # khaki/brown
	elif tagu in ["FRA", "ENG"]: col = 4  # green
	elif tagu in ["USA"]: col = 1
	else: col = 3
	var row := 0
	var au := arch.to_lower()
	if "tank" in au or "armor" in au: row = 2
	elif "inf" in au: row = 0
	elif "art" in au: row = 1
	elif "log" in au or "truck" in au: row = 3
	elif "air" in au or "fighter" in au or "bomber" in au: row = 5
	elif "naval" in au or "ship" in au: row = 7
	elif "rock" in au: row = 4
	else: row = 6
	# clamp
	col = clamp(col, 0, 7)
	row = clamp(row, 0, 7)
	return Rect2(col * cell, row * cell, cell, cell)


func _province_polygon(node: Node2D) -> PackedVector2Array:
	var poly := _get_province_polygon(node)
	if poly == null:
		return PackedVector2Array()
	return poly.polygon


func _province_node(province_id: int) -> Node2D:
	var node: Variant = province_nodes.get(province_id)
	return node as Node2D if node is Node2D else null

## Robust helper to find the Polygon2D child regardless of whether an Area2D was also added.
## Essential for pure spatial mode (no Area2D) and hybrid mode.
func _get_province_polygon(node: Node2D) -> Polygon2D:
	if node == null:
		return null
	for child in node.get_children():
		if child is Polygon2D:
			return child as Polygon2D
	return null


func _apply_hover_visuals(province_id: int, active: bool) -> void:
	if active and not MapZoomLODScript.show_province_hover_detail(_map_lod_tier):
		return
	if active:
		if _hover_outline_province_id >= 0 and _hover_outline_province_id != province_id:
			_apply_hover_visuals(_hover_outline_province_id, false)
		_hover_outline_province_id = province_id
		_hover_fill_province_id = province_id
	_set_hover_outline(province_id, active)
	if active:
		_apply_hover_fill(province_id, true)
		if selected_province_id >= 0:
			_refresh_compare_candidate_outlines()
		if supply_mode:
			_update_supply_legend_text()
	elif _hover_fill_province_id == province_id:
		_apply_hover_fill(province_id, false)
		_hover_fill_province_id = -1
	if not active and supply_mode:
		_update_supply_legend_text()
	if not active and selected_province_id >= 0:
		_refresh_compare_candidate_outlines()


func _hover_outline_colors(province_id: int) -> Dictionary:
	var colors := {
		"color": ProvinceMapVisuals.OUTLINE_HOVER,
		"glow": ProvinceMapVisuals.OUTLINE_HOVER_GLOW,
	}
	if not provinces.has(province_id):
		return colors
	var hp: Province = provinces[province_id] as Province
	var contested := ProvinceInsight.is_province_contested(hp)
	var agent := ProvinceInsight.has_active_agent_network(hp)
	if contested and agent:
		var dual_lerp := 0.22 if supply_mode else 0.28
		var dual_base := ProvinceMapVisuals.OUTLINE_DUAL
		match ProvinceInsight.agent_pressure_focus_kind(hp):
			"disrupt":
				dual_base = ProvinceMapVisuals.OUTLINE_DUAL_DISRUPT
				dual_lerp = 0.16 if ProvinceInsight.agent_applies_daily_pressure(hp) else dual_lerp
			"sabotage":
				dual_base = ProvinceMapVisuals.OUTLINE_DUAL_SABOTAGE
				dual_lerp = 0.16 if ProvinceInsight.agent_applies_daily_pressure(hp) else dual_lerp
		if ProvinceInsight.agent_has_today_pressure_tick(hp):
			dual_lerp = maxf(0.12, dual_lerp - 0.06)
		colors["color"] = dual_base.lerp(ProvinceMapVisuals.OUTLINE_HOVER, dual_lerp)
		colors["glow"] = ProvinceMapVisuals.OUTLINE_DUAL_GLOW
	elif agent:
		var agent_lerp := 0.28 if ProvinceInsight.agent_has_daily_activity(hp) else 0.38
		var pressure_kind := ProvinceInsight.agent_pressure_focus_kind(hp)
		var agent_outline := ProvinceMapVisuals.OUTLINE_AGENT
		if pressure_kind == "disrupt":
			agent_outline = ProvinceMapVisuals.OUTLINE_AGENT_DISRUPT
			agent_lerp = 0.24 if ProvinceInsight.agent_applies_daily_pressure(hp) else agent_lerp
		elif pressure_kind == "sabotage":
			agent_outline = ProvinceMapVisuals.OUTLINE_AGENT_SABOTAGE
			agent_lerp = 0.24 if ProvinceInsight.agent_applies_daily_pressure(hp) else agent_lerp
		if ProvinceInsight.agent_has_today_pressure_tick(hp):
			agent_lerp = maxf(0.18, agent_lerp - 0.08)
		colors["color"] = agent_outline.lerp(ProvinceMapVisuals.OUTLINE_HOVER, agent_lerp)
		colors["glow"] = ProvinceMapVisuals.OUTLINE_AGENT_GLOW
	elif contested:
		colors["color"] = ProvinceMapVisuals.OUTLINE_CONFLICT.lerp(ProvinceMapVisuals.OUTLINE_HOVER, 0.42)
		colors["glow"] = ProvinceMapVisuals.OUTLINE_CONFLICT_GLOW
	if provinces.has(province_id):
		var hp2: Province = provinces[province_id] as Province
		if _province_has_support_radio_benefit(hp2):
			colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO, 0.18)
			colors["glow"] = colors["glow"].lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO_GLOW, 0.24)
		if ProvinceInsight.agent_applies_daily_pressure(hp2):
			var role := str(_supply_role_by_province.get(province_id, ""))
			if role == "infra_sabotage":
				colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE, 0.2)
				colors["glow"] = colors["glow"].lerp(ProvinceMapVisuals.OUTLINE_INFRA_SABOTAGE_GLOW, 0.22)
			elif role == "supply_pressure":
				colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_SUPPLY_PRESSURE, 0.16)
			elif role in [
				"infra_repair", "infra_repair_engineers", "engineers_stationed", "engineers_needed",
				"engineers_recommended", "engineers_insufficient",
			]:
				var eng_col := ProvinceMapVisuals.OUTLINE_INFRA_REPAIR
				var eng_glow := ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_GLOW
				var lerp_amt := 0.18
				match role:
					"infra_repair_engineers":
						eng_col = ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_ENGINEERS
						eng_glow = ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_ENGINEERS_GLOW
					"engineers_stationed":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED_GLOW
					"engineers_needed":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED_GLOW
						lerp_amt = 0.26
					"engineers_recommended":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED.lerp(
							ProvinceMapVisuals.OUTLINE_INFRA_REPAIR, 0.35,
						)
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED_GLOW.lerp(
							ProvinceMapVisuals.OUTLINE_INFRA_REPAIR_GLOW, 0.3,
						)
					"engineers_insufficient":
						eng_col = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED.lerp(
							ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED, 0.5,
						)
						eng_glow = ProvinceMapVisuals.OUTLINE_ENGINEERS_STATIONED_GLOW.lerp(
							ProvinceMapVisuals.OUTLINE_ENGINEERS_NEEDED_GLOW, 0.4,
						)
						lerp_amt = 0.22
				colors["color"] = colors["color"].lerp(eng_col, lerp_amt)
				colors["glow"] = colors["glow"].lerp(eng_glow, lerp_amt * 0.9)
			elif role == "depot_sabotage":
				colors["color"] = colors["color"].lerp(ProvinceMapVisuals.OUTLINE_DEPOT_SABOTAGE, 0.14)
	return colors


func _set_hover_outline(province_id: int, visible: bool) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		var width := 2.8 if province_id == selected_province_id else 2.5
		if provinces.has(province_id):
			var hp: Province = provinces[province_id] as Province
			if ProvinceInsight.agent_has_today_pressure_tick(hp):
				width += 0.3
			if (
				ProvinceInsight.is_province_contested(hp)
				and ProvinceInsight.has_active_agent_network(hp)
			):
				width += 0.35
				if province_id == selected_province_id:
					width += 0.2
				if ProvinceInsight.agent_applies_daily_pressure(hp):
					width += 0.15
		var oc: Dictionary = _hover_outline_colors(province_id)
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_HOVER,
			oc["color"],
			width,
			oc["glow"],
			3.5,
			ProvinceMapVisuals.Z_HOVER,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_HOVER)
		if _hover_outline_province_id == province_id:
			_hover_outline_province_id = -1


func _set_selection_outline(province_id: int, visible: bool) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		var sel_col := ProvinceMapVisuals.OUTLINE_SELECT
		var sel_glow := ProvinceMapVisuals.OUTLINE_SELECT_GLOW
		if provinces.has(province_id):
			var sp: Province = provinces[province_id] as Province
			var contested := ProvinceInsight.is_province_contested(sp)
			var agent := ProvinceInsight.has_active_agent_network(sp)
			if contested and agent:
				var dual_sel := ProvinceMapVisuals.OUTLINE_DUAL
				match ProvinceInsight.agent_pressure_focus_kind(sp):
					"disrupt":
						dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_DISRUPT
					"sabotage":
						dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_SABOTAGE
				sel_col = dual_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.35)
				sel_glow = ProvinceMapVisuals.OUTLINE_DUAL_GLOW
			elif contested:
				sel_col = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED
				sel_glow = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED_GLOW
			elif agent:
				var agent_sel := ProvinceMapVisuals.OUTLINE_AGENT
				match ProvinceInsight.agent_pressure_focus_kind(sp):
					"disrupt":
						agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_DISRUPT
					"sabotage":
						agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_SABOTAGE
				sel_col = agent_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.5)
				sel_glow = ProvinceMapVisuals.OUTLINE_AGENT_GLOW
			if _province_has_support_radio_benefit(sp):
				sel_col = sel_col.lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO, 0.12)
				sel_glow = sel_glow.lerp(ProvinceMapVisuals.OUTLINE_SUPPORT_RADIO_GLOW, 0.18)
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_SELECT,
			sel_col,
			3.5,
			sel_glow,
			4.0,
			ProvinceMapVisuals.Z_SELECT,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_SELECT)


func _clear_compare_preview_outline() -> void:
	if _compare_preview_province_id >= 0:
		_set_compare_preview_outline(_compare_preview_province_id, false)
	_compare_preview_province_id = -1


func _update_compare_preview_outline(hover_province: Province, counterpart: Province) -> void:
	_clear_compare_preview_outline()
	if hover_province == null or counterpart == null:
		return
	if counterpart.id == hover_province.id:
		return
	_compare_preview_province_id = counterpart.id
	_set_compare_preview_outline(counterpart.id, true)


func _refresh_single_province_fill(province_id: int) -> void:
	if container != null:
		_zoom_fill_characterization_scale = absf(container.scale.x)
	if not provinces.has(province_id):
		return
	var node := _province_node(province_id)
	if node == null:
		return
	var poly := _get_province_polygon(node)
	if poly == null:
		return
	var province: Province = provinces[province_id] as Province
	var col := _get_province_color(province)
	if supply_mode:
		var fill := ProvinceInsight.depot_fill_ratio(province_id)
		if fill >= 0.0:
			col = col.lerp(_supply_depot_tint_color(fill), _supply_depot_mix_amount())
	col = _apply_agent_pressure_base_tint(col, province)
	col = _apply_recovering_fill_tint(col, province_id)
	col = _apply_support_radio_fill_tint(col, province)
	# Riot tint (live on data_changed for riot pids)
	if typeof(GameData) != TYPE_NIL and GameData.has_method("has_active_riot") and GameData.has_active_riot(province_id):
		col = col.lerp(Color(0.85, 0.25, 0.25, 0.55), 0.40)
	poly.color = col


## Public helper for F10 harness / tester: force re-compute all province fills (tints).
## Used to make welfare burden strain tint + settlement vitality update live on map after national policy changes
## (welfare_burden is per-owner, not per-province_data_changed pid).
func force_full_map_refresh() -> void:
	if not is_inside_tree() or container == null or provinces.is_empty():
		return
	if _full_map_refresh_scheduled:
		return
	_full_map_refresh_scheduled = true
	call_deferred("_force_full_map_refresh_impl")


func _force_full_map_refresh_impl() -> void:
	_full_map_refresh_scheduled = false
	if not is_inside_tree() or container == null or provinces.is_empty():
		return
	# Ensure riot markers live on full refresh (for 50T harness events + F10 mapmodes)
	_update_riot_markers()
	_refresh_province_fill_colors()
	# If inspector open, re-pull live settlement/welfare numbers into it
	if info_panel and info_panel is CanvasItem and info_panel.visible and selected_province_id >= 0 and provinces.has(selected_province_id):
		show_info_panel(provinces[selected_province_id])
	if OS.get_environment("EOA_MAP_DEBUG_DEMOS").strip_edges() == "1":
		print("[MapRenderer] Force full map tint/inspector refresh done (welfare strain + settlement live update).")


## Public helper: refresh only provinces owned by tag (efficient for welfare policy trigger on one owner).
## Also refreshes open inspector if it matches.
func force_refresh_tints_for_owner(owner_tag: String) -> void:
	if owner_tag.is_empty() or not provinces:
		return
	var refreshed := 0
	for pid in provinces.keys():
		var p: Province = provinces[pid]
		if p and p.owner_tag == owner_tag:
			_refresh_single_province_fill(pid)
			refreshed += 1
			if info_panel and info_panel is CanvasItem and info_panel.visible and selected_province_id == pid:
				show_info_panel(p)
	print("[MapRenderer] Force tint refresh for owner %s on %d provinces (strain tint + inspector live)." % [owner_tag, refreshed])


## === Direct province action harness helpers (for inspector interactivity + F10 harness on clicked/selected province) ===
## Use real Province (settlement_level mutate + getters), GameData (policy for strain), BattleManager/ProvinceInsight (preview).
## Called from DebugOverlay buttons after user clicks a province (sets selected_province_id) or from headless tester (temp set).
## Trigger live tint/inspector updates via existing emit + refresh paths. Minimal, zero-interference adds for Phase 2 map UX.

func debug_settle_selected_province(amount: float = 0.35) -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		print("[MapRenderer] debug_settle_selected: no selected province (click one first in inspector or use F10 after pick).")
		return
	var p: Province = provinces[selected_province_id] as Province
	if p == null or p.is_sea:
		print("[MapRenderer] debug_settle_selected: skip sea/invalid.")
		return
	var before := p.settlement_level
	p.settlement_level = clampf(before + amount, 0.0, 2.0)
	# Use real data path: emit so MapRenderer tints + inspector catch (as in GameData relocation)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_signal("province_data_changed"):
		MapManager.province_data_changed.emit(selected_province_id, "settlement")
	_refresh_single_province_fill(selected_province_id)
	if info_panel and info_panel is CanvasItem and info_panel.visible:
		show_info_panel(p)
	# Auto-center on the changed province so the visual effect (tint, bonuses) is immediately visible to the player.
	focus_province_by_id(selected_province_id)
	var msg := "Settled selected #%d '%s' (%.2f → %.2f). Uses real Province settlement_level + emit → vitality tint + inspector bonuses live. (Combat def +%.1f%% now)" % [
		selected_province_id, p.name if p.name else "?", before, p.settlement_level,
		p.get_settlement_combat_def_bonus() * 100.0 if p.has_method("get_settlement_combat_def_bonus") else (p.settlement_level * 2.5)
	]
	print("[MapRenderer] " + msg)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("🏠 " + msg + " Click to re-inspect or assault for effects.")

func debug_trigger_welfare_strain_on_selected() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		print("[MapRenderer] debug_trigger_welfare: no selected (click province first).")
		return
	var p: Province = provinces[selected_province_id] as Province
	if p == null:
		return
	var owner := p.owner_tag if p.owner_tag != "" else "player"
	if typeof(GameData) != TYPE_NIL and GameData.has_method("apply_social_services_policy"):
		GameData.apply_social_services_policy(owner, "expansive_burden")
	# Real welfare path: force tints (national burden affects owner provs) + inspector
	force_refresh_tints_for_owner(owner)
	if info_panel and info_panel is CanvasItem and info_panel.visible and selected_province_id >= 0:
		show_info_panel(p)
	var ps: Dictionary = GameData.get_peace_state() if (typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state")) else {}
	var w := float(ps.get("welfare_burden", {}).get(owner, 0.0)) if ps else 0.0
	var msg := "Welfare strain triggered on owner '%s' of selected #%d (burden=%.1f). Uses GameData policy + MapRenderer force tints/inspector (strain layer red-gray)." % [owner, selected_province_id, w]
	print("[MapRenderer] " + msg)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("😣 " + msg + " Advance time or click prov for live welfare drag in inspector.")

func debug_preview_combat_vs_adjacent() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		print("[MapRenderer] debug_preview_combat: no selected province (click to select first).")
		return
	var att_p: Province = provinces[selected_province_id] as Province
	if att_p == null:
		return
	var adj_list: Array = []
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces"):
		adj_list = MapManager.get_adjacent_provinces(selected_province_id)
	var def_p: Province = null
	var def_pid := -1
	for aidv in adj_list:
		var aid := int(aidv)
		if provinces.has(aid):
			var ap: Province = provinces[aid] as Province
			if ap and not ap.is_sea and ap.owner_tag != att_p.owner_tag:
				def_p = ap
				def_pid = aid
				break
	if def_p == null:
		print("[MapRenderer] debug_preview_combat: no adjacent enemy for #%d (select a border province)." % selected_province_id)
		return
	# Use REAL preview: ProvinceInsight.get_battle_preview (which CombatResolver/BattleManager delegate to) + BattleManager.can_assault for full context.
	var preview: Dictionary = {}
	if typeof(ProvinceInsight) != TYPE_NIL:
		preview = ProvinceInsight.get_battle_preview(att_p, def_p)
	var bm_preview: Dictionary = {}
	if typeof(BattleManager) != TYPE_NIL:
		bm_preview = BattleManager.can_assault_province(att_p.owner_tag if att_p.owner_tag else "player", def_pid, selected_province_id)
	var def_bonus := 0.0
	if def_p.has_method("get_settlement_combat_def_bonus"):
		def_bonus = def_p.get_settlement_combat_def_bonus()
	var msg := "Combat PREVIEW (real Province + ProvinceInsight/BattleManager): Att #%d '%s' (sett=%.2f) vs Def #%d '%s' (sett=%.2f, def_bonus=%.1f%%)" % [
		selected_province_id, att_p.name if att_p.name else "?", att_p.settlement_level,
		def_pid, def_p.name if def_p.name else "?", def_p.settlement_level, def_bonus * 100.0
	]
	if preview.has("attack_power") or preview.has("defense_power"):
		msg += " | preview atk=%.2f def=%.2f" % [float(preview.get("attack_power", 0)), float(preview.get("defense_power", 0))]
	if bm_preview.has("ok"):
		msg += " | can_assault=%s reason=%s" % [str(bm_preview.get("ok")), str(bm_preview.get("reason", ""))]
	print("[MapRenderer] " + msg)
	# Also log settlement contrast explicitly for tester evidence
	print("  [PREVIEW DETAIL] attacker org_mod=%.2f supply_mod=%.2f ; defender settlement def uplift uses Province.get_settlement_combat_def_bonus() + BattleManager apply (2.5%%/lev)." % [
		att_p.get_organization_recovery_modifier() if att_p.has_method("get_organization_recovery_modifier") else 0.0,
		att_p.get_local_supply_generation_modifier() if att_p.has_method("get_local_supply_generation_modifier") else 0.0
	])
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("⚔ " + msg + " (click selected to re-inspect; use Ctrl+click for real assault if staged)")


## New direct inspector/harness action (Phase 2 map UX): "Invest Infra here" on selected/clicked province.
## Uses REAL API: InfrastructureDevelopmentManager.try_start_infrastructure_investment (or legacy start) + MapManager update path.
## Triggers province_data_changed ("infrastructure") → MapRenderer refresh + InfrastructureOverlayLayer rebuild_road/rail (built_* lists grow on completes, density tints live).
## Logs + inspector update + layer emphasis. Zero-interference (safe project start, no forced complete).
func debug_invest_infra_selected_province() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		print("[MapRenderer] debug_invest_infra: no selected province (click one first; F10 or map click sets selected).")
		return
	var p: Province = provinces[selected_province_id] as Province
	if p == null or p.is_sea:
		print("[MapRenderer] debug_invest_infra: skip sea/invalid.")
		return
	var mgr = _get_infra_manager()
	if mgr == null:
		print("[MapRenderer] debug_invest_infra: InfrastructureDevelopmentManager not available.")
		return
	var player := _player_tag()
	var result: Dictionary = {}
	if mgr.has_method("try_start_infrastructure_investment"):
		result = mgr.try_start_infrastructure_investment(selected_province_id, player)
	else:
		var target := p.infrastructure + 1
		var proj: RefCounted = mgr.start_infrastructure_project(selected_province_id, target if target > 0 else 5, player) if mgr.has_method("start_infrastructure_project") else null
		result = {"success": proj != null, "reason": "started via legacy" if proj else "no method"}
	var before_infra := p.infrastructure
	# Force live updates: refresh tints/layers (infra mode will emphasize density), inspector, overlay rebuild
	if result.get("success", false):
		_refresh_single_province_fill(selected_province_id)
		var ol := get_overlay_layer("InfrastructureOverlayLayer")
		if ol and ol.has_method("rebuild_all_infra_layers"):
			ol.rebuild_all_infra_layers()
		if ol and ol.has_method("set_show_roads"):
			ol.set_show_roads(true)
			ol.set_show_rails(true)
		if info_panel and info_panel is CanvasItem and info_panel.visible:
			show_info_panel(p)
		# If in infra mapmode, re-apply for density highlight using new/pending project
		if current_map_mode == "infra":
			_refresh_province_fill_colors()
		var eta := int(result.get("eta_days", 18))
		var msg := "Invest Infra on selected #%d '%s' (infra %d; project ETA ~%d days). Real InfraDevManager API + emit → layer rebuild (roads/rails density) + tint/inspector live on 460-prov." % [selected_province_id, p.name if p.name else "?", before_infra, eta]
		print("[MapRenderer] " + msg)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("🏗️ " + msg + " Use F7 infra mode or click to see density highlight + project status.")
	else:
		print("[MapRenderer] debug_invest_infra: failed - %s" % str(result.get("reason", "unknown")))
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("🏗️ Invest Infra failed on #%d: %s" % [selected_province_id, str(result.get("reason", ""))])


## New direct inspector/harness action (Phase 2): "Assign random agent mission here" (or stage sample assault preview from here to adj).
## Chooses "assign random agent mission here" using real APIs: AgentManager.establish_network (province-bound networks) + GameData.resolve_agent_policy_mission fallback + AgentNetworkLayer refresh.
## Picks a demo focus/mission (e.g. infrastructure_sabotage or intelligence) on the selected province id → affects supply/infra/Province getters live, agent layer viz.
## Also does a combat stage preview to adjacent (real BattleManager.can + ProvinceInsight) for "stage sample assault" flavor.
## Logs/previews + forces inspector + map refresh (for 460 live counts/tints). Safe (no full execute unless formations ready).
func debug_assign_random_agent_mission_here() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		print("[MapRenderer] debug_agent_mission: no selected (click province first for 'here').")
		return
	var p: Province = provinces[selected_province_id] as Province
	if p == null:
		return
	var pid := selected_province_id
	var owner := p.owner_tag if p.owner_tag != "" else "player"
	# Real agent path: try establish_network on this prov (province_id keyed). Use or recruit a temp agent for demo.
	var used_real := false
	if typeof(AgentManager) != TYPE_NIL and AgentManager.has_method("establish_network"):
		var agents_list: Array = []
		if AgentManager.has_method("get_agents_for_country"):
			agents_list = AgentManager.get_agents_for_country(owner)
		var lead_id := ""
		if agents_list.size() > 0:
			lead_id = str(agents_list[0].agent_id) if agents_list[0] != null else ""
		if lead_id.is_empty() and AgentManager.has_method("recruit_agent"):
			var new_a = AgentManager.recruit_agent(owner)
			if new_a:
				lead_id = str(new_a.agent_id) if new_a != null else ""
		if not lead_id.is_empty():
			var focus := "infrastructure_sabotage" if (randf() < 0.6) else "intelligence"
			if AgentManager.establish_network(lead_id, pid, focus):
				used_real = true
				print("[MapRenderer] debug_agent_mission: established real network on #%d focus=%s (AgentManager + province networks). Affects infra/sabotage getters + AgentNetworkLayer." % [pid, focus])
				# Refresh agent layer if present
				var al := get_overlay_layer("AgentNetworkLayer")
				if al and al.has_method("refresh_all"):
					al.refresh_all()
				elif al and al.has_method("queue_redraw"):
					al.queue_redraw()
	# Fallback shim (used in harness): GameData policy mission resolve (ties to welfare etc on owner, visible in strain tints)
	if not used_real and typeof(GameData) != TYPE_NIL and GameData.has_method("resolve_agent_policy_mission"):
		var pol_miss := "welfare" if (randf() < 0.5) else "infrastructure"
		GameData.resolve_agent_policy_mission("debug_random_agent_%d" % pid, pol_miss, owner, "success")
		print("[MapRenderer] debug_agent_mission: fallback resolve_agent_policy_mission on #%d (pol=%s) for owner %s." % [pid, pol_miss, owner])
	# Also stage sample assault preview from here (selected) to adjacent enemy (real APIs + logs, builds on debug_preview)
	var adj_list: Array = []
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces"):
		adj_list = MapManager.get_adjacent_provinces(pid)
	var staged_to := -1
	for aidv in adj_list:
		var aid := int(aidv)
		if provinces.has(aid):
			var ap: Province = provinces[aid] as Province
			if ap and not ap.is_sea and ap.owner_tag != p.owner_tag:
				staged_to = aid
				# set staging state for map input consistency (like shift-click path)
				debug_combat_attacker_province_id = pid
				attack_staging_province_id = pid
				break
	var preview2: Dictionary = {}
	if staged_to >= 0 and typeof(ProvinceInsight) != TYPE_NIL:
		preview2 = ProvinceInsight.get_battle_preview(p, provinces[staged_to])
	var bm2 := {}
	if staged_to >= 0 and typeof(BattleManager) != TYPE_NIL:
		bm2 = BattleManager.can_assault_province(p.owner_tag if p.owner_tag else "player", staged_to, pid)
	var msg := "Agent mission assigned here on #%d '%s' (real AgentManager.establish / GameData.resolve + network on pid). " % [pid, p.name if p.name else "?"]
	if staged_to >= 0:
		msg += "Staged sample assault from here → adj #%d (real BM.can + ProvinceInsight preview; settlement/loyalty/welfare in logs)." % staged_to
	else:
		msg += "No adj enemy for sample assault stage (pick border prov)."
	print("[MapRenderer] " + msg)
	if staged_to >= 0 and preview2:
		print("  [STAGE DETAIL] preview atk=%.2f def=%.2f can=%s" % [float(preview2.get("attack_power",0)), float(preview2.get("defense_power",0)), str(bm2.get("ok", false))])
	# Live 460 update: inspector + full refresh (tints for infra/agent effects, counts)
	if info_panel and info_panel is CanvasItem and info_panel.visible:
		show_info_panel(p)
	_refresh_province_fill_colors()
	var ol2 := get_overlay_layer("InfrastructureOverlayLayer")
	if ol2 and ol2.has_method("rebuild_all_infra_layers"):
		ol2.rebuild_all_infra_layers()
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("🕵️ " + msg + " Click to re-inspect; F7 infra mode sees any sabotage density shift; advance time for network daily effects.")


## Phase 3: F10 harness "Stage + Execute Sample Assault from selected" (builds directly on existing attack_staging, _try_set_attack_staging, _try_execute_province_attack, BattleManager.execute).
## Sets staging on selected (if friendly with formations via _try or direct), picks adjacent enemy, runs REAL BattleManager.execute_province_assault (uses live Province settlement_level + loyalty/welfare from GameData in can/execute/Resolver for previews+outcome).
## Logs full outcome (incl. settlement_def_bonus in BM context), updates ownership on capture (via BM.apply -> MapManager.update_owner + emit), refreshes tints/inspector/layers.
## Complements existing Ctrl+click / attack button path (which already calls real execute); this makes sample full exec one-button from F10 on clean 460 map.
func debug_stage_and_execute_sample_assault() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		print("[MapRenderer] debug_stage_execute_assault: no selected province (click map first to set selected).")
		return
	var sel_p: Province = provinces[selected_province_id] as Province
	if sel_p == null or sel_p.is_sea:
		return
	var p_tag := _player_tag()
	if p_tag.is_empty():
		p_tag = sel_p.owner_tag if sel_p.owner_tag else "USA"
	# Use real staging logic: prefer selected if it can stage (has friendly formations), else find one.
	var staging_pid := selected_province_id
	var staged := _try_set_attack_staging(sel_p)
	if not staged:
		# Fallback: pick any owned adj with divisions for demo (still real BM path)
		var adjs: Array = MapManager.get_adjacent_provinces(selected_province_id) if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces") else []
		for aidv in adjs:
			var apid := int(aidv)
			if provinces.has(apid):
				var ap: Province = provinces[apid]
				if ap and not ap.is_sea and _province_controlled_by(ap, p_tag):
					if typeof(BattleManager) != TYPE_NIL:
						var divs: Array = BattleManager.get_divisions_at_province(apid, p_tag)
						if not divs.is_empty():
							staging_pid = apid
							attack_staging_province_id = apid
							debug_combat_attacker_province_id = apid
							break
	# Now pick adjacent enemy target for assault
	var adj_list: Array = MapManager.get_adjacent_provinces(selected_province_id) if (typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces")) else MapManager.get_adjacent_provinces(staging_pid) if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces") else []
	var target_pid := -1
	var target_p: Province = null
	for aidv in adj_list:
		var aid := int(aidv)
		if provinces.has(aid):
			var ap: Province = provinces[aid]
			if ap and not ap.is_sea and ap.owner_tag != p_tag and ap.owner_tag != "":
				target_pid = aid
				target_p = ap
				break
	if target_pid < 0 or target_p == null:
		print("[MapRenderer] debug_stage_execute_assault: no adjacent enemy from #%d (select border province with enemy neighbor)." % selected_province_id)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("⚔ No adjacent enemy for sample assault on selected #%d." % selected_province_id)
		return
	# Real preview with CURRENT settlement/loyalty/welfare data (via Province getters + BM.can which factors GameData loyalty + Province.settlement)
	var preview: Dictionary = {}
	if typeof(ProvinceInsight) != TYPE_NIL:
		preview = ProvinceInsight.get_battle_preview(provinces[staging_pid] if provinces.has(staging_pid) else sel_p, target_p)
	var can: Dictionary = {}
	if typeof(BattleManager) != TYPE_NIL:
		can = BattleManager.can_assault_province(p_tag, target_pid, staging_pid)
	var def_bonus := 0.0
	if target_p.has_method("get_settlement_combat_def_bonus"):
		def_bonus = target_p.get_settlement_combat_def_bonus()
	print("[MapRenderer] Combat PREVIEW (real current data for F10 assault): stage #%d -> target #%d (sett_def=%.1f%%, can=%s, preview_atk=%.2f)" % [
		staging_pid, target_pid, def_bonus*100.0, str(can.get("ok", false)),
		float(preview.get("attack_power", 0.0))
	])

	# Snapshot formation combat state BEFORE to demonstrate persistent damage (org/readiness/strength now live on Formation).
	var att_fid_pre := ""
	var def_fid_pre := ""
	var before_att := {}
	var before_def := {}
	if typeof(LeaderManager) != TYPE_NIL:
		# Try to resolve likely attacker formation via BattleManager helpers or preview
		var pre_divs := BattleManager.get_divisions_at_province(staging_pid, p_tag) if BattleManager and BattleManager.has_method("get_divisions_at_province") else []
		if pre_divs.size() > 0:
			att_fid_pre = str(pre_divs[0].get("formation_id", ""))
		if att_fid_pre.is_empty() and preview.has("formation_id"):
			att_fid_pre = str(preview.get("formation_id", ""))
		var def_divs := BattleManager.get_divisions_at_province(target_pid, target_p.owner_tag if target_p else "") if BattleManager and BattleManager.has_method("get_divisions_at_province") else []
		if def_divs.size() > 0:
			def_fid_pre = str(def_divs[0].get("formation_id", ""))
		if not att_fid_pre.is_empty():
			var fa := LeaderManager.get_formation(att_fid_pre)
			if fa:
				before_att = {"org": fa.organization, "rdy": fa.readiness, "str": fa.strength}
		if not def_fid_pre.is_empty():
			var fd := LeaderManager.get_formation(def_fid_pre)
			if fd:
				before_def = {"org": fd.organization, "rdy": fd.readiness, "str": fd.strength}
	if before_att or before_def:
		print("[COMBAT PRE] before assault att=%s %s  def=%s %s" % [att_fid_pre, before_att, def_fid_pre, before_def])

	# Execute REAL assault (BattleManager.execute uses live Province + settlement/loyalty/welfare in context/Resolver)
	var assault: Dictionary = BattleManager.execute_province_assault(p_tag, target_pid, staging_pid)
	var success := bool(assault.get("success", false))
	var res: Dictionary = assault.get("result", {}) if success else {}
	var outcome := str(res.get("outcome", res.get("winner", "unknown")))
	var captured := bool(res.get("province_control_change", false))
	# Phase 4 enhanced: inspector combat feedback for F10 sample too (settlement_def_bonus, winner, capture details + live log nums)
	var s_def_b := float(res.get("settlement_def_bonus", 1.0))
	var t_sett_lev := float(res.get("target_settlement_level", 0.0))
	var loy_f := float(res.get("loyalty_factor", 1.0))
	var outcome_details := "winner=%s capture=%s sett_def_bonus=%.2f (target_sett=%.2f) loyalty=%.2f" % [outcome if outcome != "unknown" else str(res.get("winner","")), str(captured), s_def_b, t_sett_lev, loy_f]
	print("[MapRenderer] F10 Sample Assault live numbers: " + outcome_details + " (real BM path; settlement_def_bonus from context in execute)")
	_last_combat_outcome_text = outcome_details
	var logmsg := "⚔ Sample Assault EXECUTED from #%d -> #%d: success=%s outcome=%s capture=%s (real BM.execute + current settlement/loyalty/welfare; def_bonus=%.2f used)." % [staging_pid, target_pid, str(success), outcome, str(captured), s_def_b]
	# Auto-center so user sees the recent change location for F10 map tool assaults too.
	if success and provinces.has(target_pid):
		focus_province_by_id(target_pid)
	print("[MapRenderer] " + logmsg)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(logmsg + " | " + outcome_details)
	# Post: update owner happened in BM if captured; refresh everything live
	if captured and typeof(MapManager) != TYPE_NIL:
		# ensure local cache sync
		if provinces.has(target_pid):
			var livep := MapManager.get_province(target_pid)
			if livep: provinces[target_pid].owner_tag = livep.owner_tag
	force_border_update()
	force_full_map_refresh()
	# Rebuild infra/road layers in case capture affects visuals
	var ol := get_overlay_layer("InfrastructureOverlayLayer")
	if ol and ol.has_method("rebuild_all_infra_layers"):
		ol.rebuild_all_infra_layers()
	if info_panel and info_panel is CanvasItem and info_panel.visible:
		if provinces.has(target_pid):
			show_info_panel(provinces[target_pid])
		elif provinces.has(selected_province_id):
			show_info_panel(provinces[selected_province_id])
	# Clear staging after exec
	attack_staging_province_id = -1
	debug_combat_attacker_province_id = -1

	# Snapshot AFTER + delta to prove persistent combat state (damage applied in BM, now visible; recovery will happen on next daily Supply tick if supplied).
	var after_att := {}
	var after_def := {}
	if typeof(LeaderManager) != TYPE_NIL:
		if not att_fid_pre.is_empty():
			var fa2 := LeaderManager.get_formation(att_fid_pre)
			if fa2:
				after_att = {"org": fa2.organization, "rdy": fa2.readiness, "str": fa2.strength}
		if not def_fid_pre.is_empty():
			var fd2 := LeaderManager.get_formation(def_fid_pre)
			if fd2:
				after_def = {"org": fd2.organization, "rdy": fd2.readiness, "str": fd2.strength}
	if after_att or after_def:
		print("[COMBAT POST] after assault att=%s %s  def=%s %s" % [att_fid_pre, after_att, def_fid_pre, after_def])
		# Simple delta for evidence
		if before_att and after_att:
			print("  DELTA att org %.2f->%.2f  rdy %.2f->%.2f" % [float(before_att.get("org",0)), float(after_att.get("org",0)), float(before_att.get("rdy",0)), float(after_att.get("rdy",0))])
		if before_def and after_def:
			print("  DELTA def org %.2f->%.2f  rdy %.2f->%.2f" % [float(before_def.get("org",0)), float(after_def.get("org",0)), float(before_def.get("rdy",0)), float(after_def.get("rdy",0))])

	# Optional: advance 1-2 days to demo recovery (SupplyManager now recovers org/rdy based on stationed infra/supply). Safe for harness.
	if success and typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("advance_days"):
		# Only in debug harness calls; small advance to show healing without full sim
		TimeManager.advance_days(2.0)
		print("[COMBAT RECOVERY DEMO] Advanced 2 days post-assault; formations should show org/readiness recovery if in supplied province (check logs or re-inspect).")
		# Re-log current after recovery
		if typeof(LeaderManager) != TYPE_NIL:
			if not att_fid_pre.is_empty():
				var far := LeaderManager.get_formation(att_fid_pre)
				if far: print("  RECOVERED att %s org=%.2f rdy=%.2f" % [att_fid_pre, far.organization, far.readiness])
			if not def_fid_pre.is_empty():
				var fdr := LeaderManager.get_formation(def_fid_pre)
				if fdr: print("  RECOVERED def %s org=%.2f rdy=%.2f" % [def_fid_pre, fdr.organization, fdr.readiness])


func _province_has_support_radio_benefit(province: Province) -> bool:
	if province == null:
		return false
	var tag := _player_tag()
	if tag.is_empty():
		tag = ProvinceInsight.country_tag_for_province(province)
	return (
		not tag.is_empty()
		and MapTechnologyContext.has_support_radio_bonuses(tag)
		and ProvinceInsight.province_benefits_country(province, tag)
	)


func _apply_support_radio_fill_tint(col: Color, province: Province) -> Color:
	if not _province_has_support_radio_benefit(province):
		return col
	var strength := 0.06 if supply_mode else 0.09
	if province != null and ProvinceInsight.agent_applies_daily_pressure(province):
		strength = minf(strength, 0.05)
	return col.lerp(ProvinceMapVisuals.FILL_SUPPORT_RADIO, strength)


func _apply_recovering_fill_tint(col: Color, province_id: int) -> Color:
	if not supply_mode:
		return col
	var role := str(_supply_role_by_province.get(province_id, ""))
	if role in [
		"infra_repair", "infra_repair_engineers", "engineers_stationed", "engineers_needed",
		"engineers_recommended", "engineers_insufficient",
	]:
		var strength := 0.44
		match role:
			"infra_repair_engineers":
				strength = 0.48
			"engineers_stationed":
				strength = 0.22
			"engineers_needed":
				strength = 0.32
				return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.14).lerp(
					ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength,
				)
			"engineers_recommended":
				strength = 0.26
				return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.08).lerp(
					ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength,
				)
			"engineers_insufficient":
				strength = 0.30
				return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.11).lerp(
					ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength,
				)
		return col.lerp(ProvinceMapVisuals.FILL_INFRA_RECOVERING, strength)
	if role == "infra_sabotage":
		return col.lerp(ProvinceMapVisuals.FILL_INFRA_SABOTAGE_ACTIVE, 0.34)
	if role == "infra_duel_even":
		return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.09).lerp(
			ProvinceMapVisuals.FILL_INFRA_RECOVERING, 0.18,
		)
	if str(_supply_role_by_province.get(province_id, "")) == "supply_pressure":
		return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.14)
	if str(_supply_role_by_province.get(province_id, "")) == "depot_sabotage":
		return col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, 0.12)
	return col


func _apply_agent_pressure_base_tint(col: Color, province: Province) -> Color:
	var strength := ProvinceInsight.get_agent_pressure_fill_strength(province, supply_mode)
	if strength <= 0.0:
		return col
	var tint := ProvinceInsight.get_agent_pressure_fill_tint(province)
	if tint.a <= 0.0:
		return col
	col = col.lerp(tint, strength)
	if (
		ProvinceInsight.agent_pressure_focus_kind(province) == "sabotage"
		and province.infrastructure <= 12
	):
		col = col.lerp(ProvinceMapVisuals.FILL_AGENT_SABOTAGE, 0.04)
	return col


func _apply_hover_fill(province_id: int, active: bool) -> void:
	if not active:
		_refresh_single_province_fill(province_id)
		return
	var node := _province_node(province_id)
	if node == null or not provinces.has(province_id):
		return
	var poly := _get_province_polygon(node)
	if poly == null:
		return
	var province: Province = provinces[province_id] as Province
	var col := _get_province_color(province)
	if supply_mode:
		var fill := ProvinceInsight.depot_fill_ratio(province_id)
		if fill >= 0.0:
			col = col.lerp(_supply_depot_tint_color(fill), _supply_depot_mix_amount())
	col = _apply_agent_pressure_base_tint(col, province)
	col = _apply_recovering_fill_tint(col, province_id)
	col = _apply_support_radio_fill_tint(col, province)
	var boost := 0.2
	if _compare_preview_province_id >= 0 and province_id == _hover_outline_province_id:
		col = col.lerp(_COMPARE_FILL_TINT, 0.14)
		boost = 0.16
	elif _is_compare_candidate(province_id):
		col = col.lerp(_CANDIDATE_FILL_TINT, 0.12)
		boost = 0.18
	var contested := ProvinceInsight.is_province_contested(province)
	var agent := ProvinceInsight.has_active_agent_network(province)
	if contested and agent:
		var dual_strength := 0.14
		if supply_mode:
			dual_strength = 0.2
		if province_id == selected_province_id:
			dual_strength += 0.04
		col = col.lerp(ProvinceMapVisuals.FILL_DUAL, dual_strength)
		if ProvinceInsight.agent_applies_daily_pressure(province):
			match ProvinceInsight.agent_pressure_focus_kind(province):
				"disrupt":
					col = col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT, 0.07)
				"sabotage":
					col = col.lerp(ProvinceMapVisuals.FILL_AGENT_SABOTAGE, 0.07)
	elif agent:
		var agent_tint := _AGENT_FILL_TINT
		match ProvinceInsight.agent_pressure_focus_kind(province):
			"disrupt":
				agent_tint = ProvinceMapVisuals.FILL_AGENT_DISRUPT
			"sabotage":
				agent_tint = ProvinceMapVisuals.FILL_AGENT_SABOTAGE
		var fill_strength := 0.08
		if ProvinceInsight.agent_applies_daily_pressure(province):
			fill_strength = 0.2 if supply_mode else 0.15
		if ProvinceInsight.agent_has_today_pressure_tick(province):
			fill_strength += 0.06
		elif ProvinceInsight.agent_has_daily_activity(province):
			fill_strength += 0.03
		col = col.lerp(agent_tint, fill_strength)
	elif contested:
		col = col.lerp(_CONFLICT_FILL_TINT, 0.09)
	poly.color = col.lerp(_HOVER_FILL_TINT, boost)


func _update_outline_pulse() -> void:
	var hover_on_selection := (
		_hover_outline_province_id >= 0
		and _hover_outline_province_id == selected_province_id
	)
	if _hover_outline_province_id >= 0:
		var node := _province_node(_hover_outline_province_id)
		if node != null:
			var hover_w := 3.0 if hover_on_selection else 2.5
			var pulse_amp := 0.4 if hover_on_selection else 0.35
			var pulse_speed := (5.5 if hover_on_selection else 4.5) * _map_overlay_pulse_speed_scale()
			if supply_mode:
				pulse_amp = minf(pulse_amp, 0.36 if hover_on_selection else 0.32)
			if provinces.has(_hover_outline_province_id):
				var hp: Province = provinces[_hover_outline_province_id] as Province
				var dual_hover := (
					ProvinceInsight.is_province_contested(hp)
					and ProvinceInsight.has_active_agent_network(hp)
				)
				if ProvinceInsight.agent_has_today_pressure_tick(hp):
					hover_w += 0.35
					pulse_amp += 0.12 if not supply_mode else 0.085
					pulse_speed += 0.60 if not supply_mode else 0.42
				elif ProvinceInsight.agent_applies_daily_pressure(hp):
					hover_w += 0.2
					pulse_amp += 0.06 if not supply_mode else 0.045
				if dual_hover:
					hover_w += 0.25
					pulse_amp += 0.08 if not supply_mode else 0.055
					if supply_mode:
						pulse_amp += 0.035
			var hoc: Dictionary = _hover_outline_colors(_hover_outline_province_id)
			ProvinceMapVisuals.apply_pulse_to_polished(
				node,
				ProvinceMapVisuals.NODE_HOVER,
				hoc["color"],
				hover_w,
				hoc["glow"],
				6.0,
				_outline_pulse_phase,
				pulse_amp,
				pulse_speed,
			)
	if selected_province_id >= 0 and not hover_on_selection:
		var sel_node := _province_node(selected_province_id)
		if sel_node != null:
			var sel_col := ProvinceMapVisuals.OUTLINE_SELECT
			var sel_glow := ProvinceMapVisuals.OUTLINE_SELECT_GLOW
			if provinces.has(selected_province_id):
				var sp: Province = provinces[selected_province_id] as Province
				var contested := ProvinceInsight.is_province_contested(sp)
				var agent := ProvinceInsight.has_active_agent_network(sp)
				if contested and agent:
					var dual_sel := ProvinceMapVisuals.OUTLINE_DUAL
					match ProvinceInsight.agent_pressure_focus_kind(sp):
						"disrupt":
							dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_DISRUPT
						"sabotage":
							dual_sel = ProvinceMapVisuals.OUTLINE_DUAL_SABOTAGE
					sel_col = dual_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.35)
					sel_glow = ProvinceMapVisuals.OUTLINE_DUAL_GLOW
				elif contested:
					sel_col = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED
					sel_glow = ProvinceMapVisuals.OUTLINE_SELECT_CONTESTED_GLOW
				elif agent:
					var agent_sel := ProvinceMapVisuals.OUTLINE_AGENT
					match ProvinceInsight.agent_pressure_focus_kind(sp):
						"disrupt":
							agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_DISRUPT
						"sabotage":
							agent_sel = ProvinceMapVisuals.OUTLINE_AGENT_SABOTAGE
					sel_col = agent_sel.lerp(ProvinceMapVisuals.OUTLINE_SELECT, 0.5)
					sel_glow = ProvinceMapVisuals.OUTLINE_AGENT_GLOW
			ProvinceMapVisuals.apply_pulse_to_polished(
				sel_node,
				ProvinceMapVisuals.NODE_SELECT,
				sel_col,
				3.5,
				sel_glow,
				7.5,
				_outline_pulse_phase + 0.8,
				0.3,
				3.2 * _map_overlay_pulse_speed_scale(),
			)
	if _compare_preview_province_id >= 0:
		var cmp_node := _province_node(_compare_preview_province_id)
		if cmp_node != null:
			ProvinceMapVisuals.apply_pulse_to_polished(
				cmp_node,
				ProvinceMapVisuals.NODE_COMPARE,
				ProvinceMapVisuals.OUTLINE_COMPARE,
				3.0,
				ProvinceMapVisuals.OUTLINE_COMPARE_GLOW,
				5.8,
				_outline_pulse_phase + 1.6,
				0.45,
				5.0 * _map_overlay_pulse_speed_scale(),
			)
	for pid in _compare_candidate_ids:
		if pid == _compare_preview_province_id:
			continue
		var cand_node := _province_node(pid)
		if cand_node == null:
			continue
		var emph := pid == _hover_outline_province_id
		var c_col := (
			ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_EMPH
			if emph
			else ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE
		)
		ProvinceMapVisuals.apply_pulse_to_polished(
			cand_node,
			ProvinceMapVisuals.NODE_COMPARE_CANDIDATE,
			c_col,
			2.6 if emph else 1.6,
			ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_GLOW if not emph else ProvinceMapVisuals.OUTLINE_COMPARE_GLOW,
			4.1,
			_outline_pulse_phase + float(pid % 5) * 0.4,
			0.22 if emph else 0.12,
			(3.0 if emph else 2.0) * _map_overlay_pulse_speed_scale(),
		)
	if supply_mode:
		_pulse_supply_outlines()
	_apply_engineer_assignment_flash_pulses()


func _refresh_compare_candidate_outlines() -> void:
	for pid in _compare_candidate_ids:
		_set_compare_candidate_outline(pid, false, false)
	_compare_candidate_ids.clear()
	if selected_province_id < 0 or adjacency == null:
		return
	for nid in adjacency.get_neighbors(selected_province_id):
		var id := int(nid)
		if id == selected_province_id:
			continue
		if id == _compare_preview_province_id:
			continue
		_compare_candidate_ids.append(id)
		var emphasized := id == _hover_outline_province_id
		_set_compare_candidate_outline(id, true, emphasized)


func _set_compare_candidate_outline(province_id: int, visible: bool, emphasized: bool = false) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		var color := ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE
		var glow := ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_GLOW
		var width := 1.6
		if emphasized:
			color = ProvinceMapVisuals.OUTLINE_COMPARE_CANDIDATE_EMPH
			glow = ProvinceMapVisuals.OUTLINE_COMPARE_GLOW
			width = 2.6
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_COMPARE_CANDIDATE,
			color,
			width,
			glow,
			2.5,
			ProvinceMapVisuals.Z_COMPARE_CANDIDATE,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_COMPARE_CANDIDATE)


func _set_compare_preview_outline(province_id: int, visible: bool) -> void:
	var node := _province_node(province_id)
	if node == null:
		return
	if visible:
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_COMPARE,
			ProvinceMapVisuals.OUTLINE_COMPARE,
			2.8,
			ProvinceMapVisuals.OUTLINE_COMPARE_GLOW,
			3.0,
			ProvinceMapVisuals.Z_COMPARE,
		)
	else:
		ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_COMPARE)


func _supply_highlight_roles() -> Dictionary[int, String]:
	var roles: Dictionary[int, String] = {}
	if not supply_mode:
		return roles
	var sm := _supply_manager()
	for pid in province_nodes.keys():
		if ProvinceInsight.depot_fill_ratio(int(pid)) >= 0.0:
			roles[int(pid)] = "hub"  # overwritten below if on route / preview / selected
	if sm == null:
		return roles
	var selected: int = SupplyManager.get_selected_province_id()
	if selected < 0:
		selected = selected_province_id
	if selected >= 0:
		roles[selected] = "active"
	var preview_pids: Dictionary[int, bool] = {}
	if _supply_reroute_active:
		var preview: SupplyRoutePlan = sm.preview_player_route()
		if preview != null and preview.path_length() > 0:
			for pid_var in preview.province_path:
				preview_pids[int(pid_var)] = true
	for plan_var in sm.get_all_routes():
		if not (plan_var is SupplyRoutePlan):
			continue
		var plan := plan_var as SupplyRoutePlan
		if plan.represents_trade_flow:
			continue
		for pid_var in plan.province_path:
			var pid := int(pid_var)
			if str(roles.get(pid, "")) == "active":
				continue
			if preview_pids.has(pid):
				roles[pid] = "preview"
			else:
				roles[pid] = "route"
	for pid in preview_pids.keys():
		if str(roles.get(pid, "")) != "active":
			roles[pid] = "preview"
	# Trade corridors: soft ring on path provinces that are not already primary logistics / depots.
	for plan_var in sm.get_all_routes():
		if not (plan_var is SupplyRoutePlan):
			continue
		var tplan := plan_var as SupplyRoutePlan
		if not tplan.represents_trade_flow or tplan.province_path.size() < 2:
			continue
		for pid_var in tplan.province_path:
			var pid2 := int(pid_var)
			var cur := str(roles.get(pid2, ""))
			if cur in ["active", "preview", "route", "hub"]:
				continue
			roles[pid2] = "trade_transit"
	_apply_infra_pressure_overlay_roles(roles)
	return roles


func _apply_infra_pressure_overlay_roles(roles: Dictionary[int, String]) -> void:
	if not supply_mode or typeof(MapManager) == TYPE_NIL:
		return
	for pid_var in province_nodes.keys():
		var pid := int(pid_var)
		var existing: String = str(roles.get(pid, ""))
		if existing in ["active", "preview", "route"]:
			continue
		if not provinces.has(pid):
			continue
		var p: Province = provinces[pid] as Province
		if p == null:
			continue
		var bd: Dictionary = MapManager.get_infrastructure_repair_breakdown(pid)
		var eng_role := ProvinceInsight.get_engineer_supply_overlay_role(p, bd)
		if not eng_role.is_empty():
			roles[pid] = eng_role
			continue
		if ProvinceInsight.agent_pressure_focus_kind(p) == "disrupt":
			roles[pid] = "supply_pressure"
			continue
		var depot_sab := float(bd.get("depot_sabotage_level", 0.0))
		if depot_sab > 0.12:
			roles[pid] = "depot_sabotage"
			continue


func _pulse_supply_outlines() -> void:
	for pid in _supply_role_by_province.keys():
		if _engineer_assign_flash_by_province.has(pid):
			continue  # `_apply_engineer_assignment_flash_pulses` owns NODE_SUPPLY for this province.
		if int(pid) == _hover_outline_province_id:
			continue  # Hover outline already pulses this province; avoids stacked ring flicker.
		var role: String = str(_supply_role_by_province[pid])
		if role not in [
			"active", "preview", "route", "infra_sabotage", "infra_repair", "infra_repair_engineers",
			"infra_duel_even", "depot_sabotage", "supply_pressure", "engineers_stationed",
			"engineers_needed", "engineers_recommended", "engineers_insufficient", "trade_transit",
		]:
			continue
		var node := _province_node(int(pid))
		if node == null:
			continue
		var style: Dictionary = ProvinceMapVisuals.get_supply_outline_style(role)
		var phase_off := float(int(pid) % 7) * 0.35
		ProvinceMapVisuals.apply_pulse_to_polished(
			node,
			ProvinceMapVisuals.NODE_SUPPLY,
			style["color"],
			style["width"],
			style["glow"],
			float(style["width"]) + float(style["glow_extra"]),
			_outline_pulse_phase + phase_off,
			_pulse_amount_for_supply_role(role),
			float(style.get("pulse_speed", 1.0)),
		)


func _pulse_amount_for_supply_role(role: String) -> float:
	match role:
		"active":
			return 0.21
		"preview":
			return 0.26
		"route":
			return 0.15
		"infra_sabotage":
			return 0.66
		"infra_duel_even":
			return 0.42
		"supply_pressure":
			return 0.42
		"depot_sabotage":
			return 0.32
		"infra_repair":
			return 0.14
		"infra_repair_engineers":
			return 0.24
		"engineers_stationed":
			return 0.12
		"engineers_needed":
			return 0.58
		"engineers_recommended":
			return 0.35
		"engineers_insufficient":
			return 0.48
		"trade_transit":
			return 0.038
		"hub":
			return 0.17
		_:
			return 0.28


func _refresh_supply_highlights() -> void:
	var roles := _supply_highlight_roles()
	_supply_role_by_province = roles
	for pid in province_nodes.keys():
		var node := _province_node(int(pid))
		if node == null:
			continue
		var role: String = str(roles.get(int(pid), ""))
		if role.is_empty():
			ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_SUPPLY)
			continue
		var style: Dictionary = ProvinceMapVisuals.get_supply_outline_style(role)
		ProvinceMapVisuals.ensure_polished_outline(
			node,
			_province_polygon(node),
			ProvinceMapVisuals.NODE_SUPPLY,
			style["color"],
			style["width"],
			style["glow"],
			style["glow_extra"],
			style["z_index"],
		)


func _update_supply_overlay_legend() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	if _supply_overlay_legend == null or not is_instance_valid(_supply_overlay_legend):
		var panel := PanelContainer.new()
		_supply_legend_panel = panel
		panel.name = "SupplyOverlayLegend"
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.offset_left = 10.0
		panel.offset_top = 10.0
		panel.custom_minimum_size = Vector2(520, 0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.08, 0.14, 0.88)
		style.border_color = Color(0.35, 0.55, 0.85, 0.75)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", style)
		var margin := MarginContainer.new()
		panel.add_child(margin)
		_supply_overlay_legend = RichTextLabel.new()
		_supply_overlay_legend.bbcode_enabled = true
		_supply_overlay_legend.fit_content = true
		_supply_overlay_legend.scroll_active = false
		_supply_overlay_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_supply_overlay_legend.add_theme_font_size_override("normal_font_size", 11)
		margin.add_child(_supply_overlay_legend)
		ui.add_child(panel)
	_update_supply_legend_text()


func _update_supply_legend_text() -> void:
	_set_supply_legend_visible(supply_mode)
	if _supply_overlay_legend != null and supply_mode:
		var hover_role := ""
		if _hover_province != null:
			hover_role = str(_supply_role_by_province.get(_hover_province.id, ""))
		var hid := _hover_province.id if _hover_province != null else -1
		var contested_n := ProvinceInsight.count_contested_provinces(provinces)
		var agent_n := ProvinceInsight.count_agent_networks(provinces, _player_tag())
		var dual_n := ProvinceInsight.count_dual_situation_provinces(provinces)
		var pulse := _get_active_map_time_pulse_bbcode()
		_supply_overlay_legend.text = ProvinceInsight.build_supply_legend_bbcode(
			selected_province_id,
			_compare_candidate_ids.size(),
			hid,
			hover_role,
			contested_n,
			agent_n,
			_player_tag(),
			dual_n,
			pulse,
			_map_time_pulse_kind,
		)
		_apply_supply_legend_time_pulse_style(not pulse.is_empty(), _map_time_pulse_kind)
	_update_compare_hint_label()


func _apply_supply_legend_time_pulse_style(pulse_active: bool, pulse_kind: String = "") -> void:
	if _supply_legend_panel == null:
		return
	var style := _supply_legend_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	if not pulse_active:
		style.border_color = Color(0.35, 0.55, 0.85, 0.75)
	elif pulse_kind == "year":
		style.border_color = Color(0.45, 0.82, 1.0, 0.95)
	elif pulse_kind == "month":
		style.border_color = Color(0.55, 0.72, 0.92, 0.9)
	elif pulse_kind == "day":
		style.border_color = Color(0.42, 0.52, 0.68, 0.82)
	else:
		style.border_color = Color(0.55, 0.72, 0.92, 0.9)


func _update_compare_hint_label() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	if _compare_hint_label == null or not is_instance_valid(_compare_hint_label):
		_compare_hint_label = Label.new()
		_compare_hint_label.name = "CompareHintLabel"
		_compare_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_compare_hint_label.add_theme_font_size_override("font_size", 11)
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
		_compare_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_compare_hint_label.offset_left = 12.0
		_compare_hint_label.offset_top = 52.0
		_compare_hint_label.custom_minimum_size = Vector2(480, 0)
		ui.add_child(_compare_hint_label)
	var contested_n := ProvinceInsight.count_contested_provinces(provinces)
	var agent_n := ProvinceInsight.count_agent_networks(provinces, _player_tag())
	var dual_n := ProvinceInsight.count_dual_situation_provinces(provinces)
	var show_compare := selected_province_id >= 0 and not supply_mode
	var show_conflict := contested_n > 0 and not supply_mode and not show_compare
	var show_agent := agent_n > 0 and not supply_mode and not show_compare and not show_conflict
	var show_supply_compare := selected_province_id >= 0 and supply_mode
	var p_tag := _player_tag()
	var has_radio := MapTechnologyContext.has_support_radio_bonuses(p_tag)
	var show_supply_overlays := (
		supply_mode
		and not show_supply_compare
		and (contested_n > 0 or agent_n > 0 or has_radio)
	)
	_compare_hint_label.visible = (
		show_compare or show_conflict or show_agent or show_supply_compare or show_supply_overlays
	)
	if show_supply_compare:
		var hid := _hover_province.id if _hover_province != null else -1
		var hover_cand := _is_compare_candidate(hid)
		var base := ProvinceInsight.build_map_compare_hint_plain(
			selected_province_id, _compare_candidate_ids.size(), hid, hover_cand,
		)
		var overlay := ProvinceInsight.build_map_supply_mode_hint_plain(
			contested_n, agent_n, dual_n, selected_province_id, p_tag,
		)
		_compare_hint_label.text = base + "  |  " + overlay if not overlay.is_empty() else base
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
	elif show_supply_overlays:
		_compare_hint_label.text = ProvinceInsight.build_map_supply_mode_hint_plain(
			contested_n, agent_n, dual_n, -1, p_tag,
		)
		_compare_hint_label.add_theme_color_override("font_color", Color(0.55, 0.92, 0.78))
	elif show_compare:
		var hid := _hover_province.id if _hover_province != null else -1
		var hover_cand := _is_compare_candidate(hid)
		_compare_hint_label.text = ProvinceInsight.build_map_compare_hint_plain(
			selected_province_id, _compare_candidate_ids.size(), hid, hover_cand,
		)
	elif show_conflict:
		_compare_hint_label.text = ProvinceInsight.build_conflict_map_hint_plain(contested_n)
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	elif show_agent:
		_compare_hint_label.text = (
			"◎ %d agent network%s — rings pulse daily · hover for strength & today's activity"
			% [agent_n, "s" if agent_n != 1 else ""]
		)
		_compare_hint_label.add_theme_color_override("font_color", Color(0.72, 0.55, 1.0))
	else:
		_compare_hint_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))


func _set_supply_legend_visible(visible: bool) -> void:
	if _supply_overlay_legend == null:
		return
	var panel: CanvasItem = _supply_legend_panel
	if panel == null:
		var margin := _supply_overlay_legend.get_parent()
		panel = margin.get_parent() if margin else null
	if panel is CanvasItem:
		panel.visible = visible


func _supply_depot_tint_color(fill_ratio: float) -> Color:
	if fill_ratio < 0.35:
		return Color(0.85, 0.2, 0.25, 0.9)
	if fill_ratio < 0.65:
		return Color(0.9, 0.65, 0.15, 0.85)
	return Color(0.25, 0.75, 0.45, 0.85)


func _on_open_national_spirits_pressed() -> void:
	if selected_province_id < 0 or not provinces.has(selected_province_id):
		return
	var province: Province = provinces[selected_province_id] as Province
	var tag := ProvinceInsight.country_tag_for_province(province)
	var existing := get_tree().root.get_node_or_null("NationalSpiritsScreen")
	if existing != null:
		existing.queue_free()
	var packed: PackedScene = load("res://scenes/ui/NationalSpiritsScreen.tscn") as PackedScene
	if packed == null:
		return
	var screen: NationalSpiritsScreen = packed.instantiate() as NationalSpiritsScreen
	if screen == null:
		return
	screen.country_tag = tag
	screen.name = "NationalSpiritsScreen"
	get_tree().root.add_child(screen)
	screen.refresh_screen()


#endregion


func _get_feature_icon(feature: String) -> String:
	match feature.to_lower():
		"port", "major_port": return "⚓"
		"naval_shipyard": return "⚙️"
		"airfield": return "✈️"
		"fort": return "🛡️"
		"research_center": return "🔬"
		"oil_rig", "oil": return "⛽"
		"nuclear_plant": return "☢️"
		"spaceport": return "🚀"
		"mega_factory", "major_factory": return "🏭"
		_: return "◆"


## Returns the tight AABB of the actually rendered Polygon2D points (for fitting custom backgrounds
## such as the phase1 europe grand strategy image to the current geometry, or other dynamic underlays).
func get_rendered_province_bounds() -> Rect2:
	# When the high-res grand theater stylized map (the requested upscaled improved one) is the active underlay,
	# ALWAYS use the large canonical rect for fit, camera framing, and placement. This ensures the pretty detailed
	# image (rivers, hills, swamps, full UK/Scand/N Russia scope) is the full playable base even if the current
	# active province set is the small 180-prov phase1 subset (which can report degenerate 0,0 bounds).
	# The 180/120 "proposed children" are for splitter debug viz overlaid on the large image; main interaction
	# and the styled map should use the large space.
	if is_using_grand_stylized_map():
		return GRAND_THEATER_CANONICAL_BOUNDS
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	var found := false
	for id in province_nodes.keys():
		var n := province_nodes[id]
		if n == null:
			continue
		for ch in n.get_children():
			if ch is Polygon2D:
				var pts: PackedVector2Array = (ch as Polygon2D).polygon
				if pts.size() >= 3:
					found = true
					for pt in pts:
						min_x = minf(min_x, pt.x)
						max_x = maxf(max_x, pt.x)
						min_y = minf(min_y, pt.y)
						max_y = maxf(max_y, pt.y)
	if not found or is_inf(min_x) or (max_x - min_x < 10) or (max_y - min_y < 10):
		# Robust fallback using the canonical large rect for the high-quality larger grand theater map (up-res for close zoom).
		# Ensures the detailed bg is always full underlay (not small overlay) .
		return GRAND_THEATER_CANONICAL_BOUNDS
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _fit_background_to_bounds() -> void:
	# Fit the current WorldBackground (stylized grand map) to the rendered province bounds.
	# Called after render and in apply to ensure the detailed colorized map aligns on first load.
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if not bg or not bg.texture:
		return
	# Idempotent guard for the grand high-res case (the expensive 8K+ one): repeated calls during init / mode cycles / heavy demos
	# were causing log spam ("Fitted..." dozens of times) and unnecessary bounds scans + scale writes even when nothing changed.
	# The guard lets the first real fit happen, then skips identical grand fits until a new texture or explicit clear.
	if bg.has_meta("grand_fitted") and is_using_grand_stylized_map():
		_suppress_old_background_maps()
		return
	var b := get_rendered_province_bounds()
	if is_using_world_grand_map():
		b = WORLD_CANONICAL_BOUNDS
	elif is_using_grand_stylized_map():
		b = GRAND_THEATER_CANONICAL_BOUNDS
	bg.position = b.position
	var img_size := Vector2(bg.texture.get_width(), bg.texture.get_height())
	bg.scale = b.size / img_size
	bg.centered = false
	if bg.texture:
		bg.texture_filter = 2  # LINEAR_WITH_MIPMAPS for zoom
	# Always suppress any old background map underneath the stylized one (e.g. ProvinceMap raster that may show grey/black)
	_suppress_old_background_maps()
	if is_using_grand_stylized_map():
		bg.set_meta("grand_fitted", true)
	if terrain_layer_stack:
		var b2 := b
		terrain_layer_stack.fit_to_bounds(b2)
	_sync_peak_snow_overlay()
	# Only print on actual fit (guard above suppresses the repeat cases that were spamming the log during startup + evidence cycles).
	print("MapRenderer: Fitted stylized background to geo bounds for alignment (underneath suppressed)")
	_refresh_terrain_zoom_aware()

func is_using_world_grand_map() -> bool:
	if get_meta("full_world_underlay_active", false):
		return true
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg and bg.texture:
		var p := str(bg.texture.resource_path).to_lower()
		return "world_grand" in p or p.ends_with("world_map.png")
	return false


func is_using_grand_stylized_map() -> bool:
	if is_using_world_grand_map():
		return false
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg and bg.texture:
		var p := str(bg.texture.resource_path).to_lower()
		return "grand_theater" in p or "europe_grand" in p
	return false


## Applies the grand-strategy Europe background image (for phase1 test maps) and fits its
## transform (position + scale) so the image underlays the rendered province geometry bbox.
## This ensures "map images" are visible together with vector polys + outlines/grid.
## Sets meta so any future alignment code can preserve the fit.
func apply_phase1_europe_background() -> void:
	if not is_inside_tree():
		call_deferred("apply_phase1_europe_background")
		return
	if is_using_world_grand_map():
		print("MapRenderer: world grand underlay active — keeping world canvas (skip europe-only bg replace).")
		call_deferred("_setup_weather_overlay_layer")
		return
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg == null:
		bg = get_node_or_null("WorldBackground") as Sprite2D
	if bg == null:
		push_warning("MapRenderer: No WorldBackground node found for phase1 bg apply. (Scene may need the Sprite2D named WorldBackground under the map root.)")
		return

	# Idempotent: if we already have the desired high-res grand theater ultra map loaded, just suppress + fit + re-frame.
	# This prevents repeated scenario loads from spamming re-apply, dupe layers, and state flips between 840/180 bounds.
	if bg.texture:
		var rp := str(bg.texture.resource_path).to_lower()
		if "ultra_high" in rp or ("grand_theater" in rp and bg.get_meta("phase1_custom_bg", false)):
			_suppress_old_background_maps()
			_fit_background_to_bounds()
			# Still ensure weather is there once
			call_deferred("_setup_weather_overlay_layer")
			return

	# Robust discovery of the detailed grand theater / stylized Europe raster background.
	# Tries known high-res names first, then scans assets/maps for any large JPG/PNG whose name suggests Europe/grand/detail/theater.
	# This ensures the beautiful underlay (the "raster map of the area") is used even if the exact filename differs from the canonical ultra_high.
	# The vector provinces (low alpha in grand mode) provide tints, pick areas, and unit placement over the terrain image.
	var tex: Texture2D = null
	var tried := [
		"res://assets/maps/europe_grand_theater_ultra_high.jpg",
		"res://assets/maps/europe_grand_theater_ultra_high.png",
		"res://assets/maps/europe_grand_theater_ultra_1936.jpg",
		"res://assets/maps/europe_grand_theater_ultra_1936.png",
		"res://assets/maps/europe_grand_theater_ultra_1936_4k.png",
		"res://assets/maps/europe_grand_strategy_1936.jpg",
		"res://assets/maps/europe_ultra_detail_1936_4k.png",
		"res://assets/maps/europe_high_detail_1936_4k.png",
		"res://assets/maps/europe_ultra_detail_1936.png",
	]
	for p in tried:
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
			if tex != null:
				break
	if tex == null:
		# Scan for any suitable large map image in the folder (user-provided raster or different naming).
		var maps_dir := "res://assets/maps/"
		if DirAccess.dir_exists_absolute(maps_dir):
			var da := DirAccess.open(maps_dir)
			if da != null:
				da.list_dir_begin()
				var f := da.get_next()
				while f != "":
					if not da.current_is_dir():
						var fl := f.to_lower()
						if (fl.ends_with(".jpg") or fl.ends_with(".png")) and (fl.find("europe") != -1 or fl.find("grand") != -1 or fl.find("detail") != -1 or fl.find("theater") != -1 or fl.find("ultra") != -1):
							var path := maps_dir + f
							if ResourceLoader.exists(path):
								var candidate := load(path) as Texture2D
								if candidate != null and candidate.get_width() >= 2000:
									tex = candidate
									break
					f = da.get_next()
				da.list_dir_end()
	if tex != null:
		bg.texture = tex
		if bg.has_meta("grand_fitted"):
			bg.remove_meta("grand_fitted")
		bg.visible = true
		bg.modulate = Color(0.92, 0.90, 0.85, 0.92)
		bg.centered = false
		if bg.texture:
			bg.texture_filter = 2
		_suppress_old_background_maps()
		print("MapRenderer: Loaded stylized grand theater / detailed raster background: ", tex.resource_path)
	else:
		bg.modulate = Color(0.85, 0.85, 0.9, 0.65)
		push_warning("MapRenderer: No suitable grand/Europe raster background found in assets/maps/. Vector provinces will be visible without the detailed terrain underlay. Add a large JPG/PNG with 'europe'/'grand'/'detail' in the name for the world-class GS look.")
	bg.visible = true
	var old := find_child("ProvinceMap", true, false) as Sprite2D
	if old != null:
		old.visible = false
		if old.texture:
			old.texture = null  # clear any old grey/black generated province raster or map image

	# Aggressively suppress any lingering grey/black base (world_map.png or similar) when we have the detailed grand theater image.
	# The new map should not have transparent-ish over old grey.
	if bg.texture and ("grand_theater" in str(bg.texture.resource_path).to_lower() or "ultra_detail" in str(bg.texture.resource_path).to_lower()):
		bg.visible = true
		# Already set high alpha/modulate earlier; here ensure no siblings or other map sprites show old base
		if container:
			for c in container.get_children():
				if c is Sprite2D and c.name in ["ProvinceMap", "BaseMap", "MapRaster"]:
					c.visible = false
					if c.texture and ("world_map" in str(c.texture.resource_path).to_lower() or "grey" in str(c.texture.resource_path).to_lower() or "gray" in str(c.texture.resource_path).to_lower()):
						c.texture = null

	# Also ensure the scene's initial WorldBackground texture (world_map grey/black) is not competing if we have a phase1 one.
	# (We already overwrote .texture above when successful.)
	_suppress_old_background_maps()

	# Auto-spawn data-driven objects from map gen layers (city placements etc.) so objects are tied
	# to province areas on the background image. Supports GRAND THEATER geography (full UK/Ireland,
	# Scandinavia to high north, northern Russia/Murmansk/Karelia + prior Canaries/NA/Egypt/Suez/Iraq/ME),
	# hills/swamps, desert (special handling for infra placement). Northern heavy snow variants.
	spawn_data_driven_objects_from_layers()
	call_deferred("_setup_weather_overlay_layer")

	bg.centered = false
	var b := get_rendered_province_bounds()
	# For the high-quality larger grand theater map (requested for closer zoom), use the canonical large rect so the detailed bg is full underlay.
	# This supports deep zoom for counters, lines, weather on the terrain.
	if is_using_grand_stylized_map():
		b = GRAND_THEATER_CANONICAL_BOUNDS
	bg.position = b.position
	# Dynamic fit using actual texture pixel size (supports the larger high-res grand image)
	if bg.texture:
		var img_size := Vector2(bg.texture.get_width(), bg.texture.get_height())
		bg.scale = b.size / img_size
	else:
		bg.scale = b.size / Vector2(4096.0, 1465.0)  # fallback
	bg.set_meta("phase1_custom_bg", true)
	# Use linear mipmap for smooth high detail zoom into provinces (buildings, roads, cities in bg, river details etc.)
	if bg.texture:
		bg.texture_filter = 2  # CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS (safe int)

	_suppress_old_background_maps()

	# Setup matching detail overlay and legend if not present (for calls from DebugOverlay etc.)
	call_deferred("_fit_background_to_bounds")
	var cont := container
	if cont:
		var detail := cont.get_node_or_null("DetailOverlay") as Sprite2D
		if detail == null:
			detail = Sprite2D.new()
			detail.name = "DetailOverlay"
			detail.texture = load("res://assets/maps/europe_roads_cities_detail_overlay_4k.png") as Texture2D
			detail.position = bg.position
			detail.scale = bg.scale
			detail.z_index = -3
			detail.modulate = Color(1,1,1,0.65)
			cont.add_child(detail)
		var leg := cont.get_node_or_null("MapLegend") as Sprite2D
		if leg == null:
			leg = Sprite2D.new()
			leg.name = "MapLegend"
			leg.texture = load("res://assets/maps/europe_map_legend_1936.png") as Texture2D
			leg.position = Vector2(6200, 150)
			leg.scale = Vector2(0.35, 0.35)
			leg.modulate = Color(1,1,1,0.55)
			cont.add_child(leg)

	print("MapRenderer: Applied phase1 GRAND THEATER ultra high-detail bg (full UK/Ireland + Scand high north + N Russia + prior south; no borders, sharp rivers for zoom, infra placeable) fitted dynamically to current geo bounds ", b)

## Spawn data-driven static objects (cities etc.) from map gen layers (e.g. province_city_layer positions).
## Objects are tied to province areas on the background image (GRAND THEATER: full UK/Ireland + full Scandinavia + northern Russia high north + Canaries/NA/Egypt/Suez/Iraq/ME).
## Handles hills/swamps/desert (desert gets sparser infra placement; all infra types allowed everywhere incl difficult terrain).
## Northern areas get heavy regional snow in winter layers. Dynamic layers overlay for decisions.
## Seasons/damage/era/culture (tech/focus/country) can modulate via variants in data. High-res bg supports zoom to river/coast/fjord detail.
func spawn_data_driven_objects_from_layers() -> void:
	if typeof(ScenarioLoader) == TYPE_NIL:
		return
	var loader = get_node_or_null("/root/ScenarioLoader")
	if loader == null:
		return
	var city_data: Dictionary = {}
	if loader.has("province_city_layer") and loader.province_city_layer.has("provinces"):
		city_data = loader.province_city_layer["provinces"]
	if city_data.is_empty():
		return

	var parent := container.get_node_or_null("DataDrivenObjects") as Node2D
	if parent == null:
		parent = Node2D.new()
		parent.name = "DataDrivenObjects"
		container.add_child(parent)

	var placed := 0
	for pid_str in city_data:
		var pid := int(pid_str)
		var entry: Dictionary = city_data[pid_str]
		for c in entry.get("cities", []):
			var pos_arr: Array = c.get("position", [0, 0])
			var pos := Vector2(pos_arr[0], pos_arr[1])
			var sz: float = 6.0 + clamp(float(c.get("population", 10000)) / 100000.0, 0.0, 10.0)
			var rect := ColorRect.new()
			rect.size = Vector2(sz, sz)
			rect.position = pos - rect.size * 0.5
			# Terrain-aware (hills/swamp/desert from data; desert limits density). Prefer MapManager (handles unwrap of infer json) for consistency with inspector/effects.
			var terrain := "plains"
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_terrain"):
				var tdict: Dictionary = MapManager.get_province_terrain(pid)
				terrain = str(tdict.get("terrain", "plains"))
			elif loader.has("province_terrain_layer") and loader.province_terrain_layer.has(pid_str):
				var t = loader.province_terrain_layer[pid_str]
				terrain = t.get("terrain", "plains") if t is Dictionary else str(t)
			if "desert" in terrain.to_lower():
				rect.color = Color(0.92, 0.85, 0.65, 0.75)
				rect.size *= 0.6
			elif "swamp" in terrain.to_lower() or "marsh" in terrain.to_lower():
				rect.color = Color(0.45, 0.58, 0.38, 0.8)
			elif "hill" in terrain.to_lower():
				rect.color = Color(0.68, 0.62, 0.55, 0.82)
			else:
				rect.color = Color(0.88, 0.82, 0.72, 0.85)
			parent.add_child(rect)
			placed += 1
			if placed > 25:
				break
		if placed > 25:
			break
	if placed > 0:
		print("MapRenderer: Spawned %d data-driven objects from city_layer (tied to bg image + province areas; desert/hills/swamp handled)." % placed)


## Starter Map Visual Editor support: place a demo object (city, airfield, port, etc.)
## at an approximate world position (for now: camera center; full version converts
## screen mouse pos via camera + map container to world coords inside province poly).
## Respects terrain from data (hills/swamp get different tint/size; desert uses sparser
## style + limited density per the Python tool variants + identify_europe_provinces).
## Objects live under DataDrivenObjects so they sit visually with the ultra bg image.
## Call from DebugOverlay editor buttons. Expand later for drag, multi-type, live layers
## (roads/rails as Line2D on infra sublayer), season/damage/era/culture swaps (tech/focus/culture
## driven architecture variants), and JSON export for Python roundtrip to update city_layer etc.
func place_demo_object_at_mouse(type: String = "city", exact_world_pos: Vector2 = Vector2.INF) -> void:
	if container == null:
		return
	var parent := container.get_node_or_null("DataDrivenObjects") as Node2D
	if parent == null:
		parent = Node2D.new()
		parent.name = "DataDrivenObjects"
		container.add_child(parent)

	# Get world pos using accurate screen->world (camera canvas inverse) for precise placement at high zoom on the high-res 8K+ detailed map.
	# Editor LMB in DebugOverlay sets last_editor_screen_mouse so click positions land exactly where intended on terrain features (rivers, hills, coasts) in the image.
	# exact_world_pos allows load/roundtrip to place at stored coords precisely (no jitter).
	# In grand high-res mode we prefer positions inside the large fitted bg rect so placements land on the visible styled map even if current province geometry is the small 180-prov subset.
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	var pos := MapCanvasConfig.europe_center()
	if exact_world_pos != Vector2.INF:
		pos = exact_world_pos
	elif cam:
		if has_meta("last_editor_screen_mouse"):
			var sm: Vector2 = get_meta("last_editor_screen_mouse")
			pos = _screen_to_world(sm)
		else:
			pos = cam.get_screen_center_position()
		# If we are in grand high-res and the computed pos looks way off (e.g. from a prior tiny 180-prov map state), snap to the current bg rect center.
		if is_using_grand_stylized_map():
			var grand := GRAND_THEATER_CANONICAL_BOUNDS
			if pos.y > grand.size.y or pos.y < grand.position.y or pos.x > grand.size.x or pos.x < grand.position.x:
				var bgc := find_child("WorldBackground", true, false) as Sprite2D
				if bgc and bgc.texture:
					var br := get_rendered_province_bounds()
					pos = br.position + br.size * 0.5
		# Slight random offset so repeated clicks don't stack exactly (small for high-res precision)
		pos += Vector2(randf_range(-8, 8), randf_range(-6, 6))

	var sz: float = 8.0
	var col := Color(0.9, 0.85, 0.7, 0.9)
	var label := type
	if type == "airfield":
		sz = 10.0
		col = Color(0.6, 0.65, 0.75, 0.85)
	elif type == "port":
		sz = 7.0
		col = Color(0.5, 0.7, 0.85, 0.9)
	elif type == "factory":
		sz = 6.0
		col = Color(0.75, 0.6, 0.55, 0.9)

	# Simple rect proxy (later: use pregen sprites or scenes per era/culture/tech)
	var rect := ColorRect.new()
	rect.size = Vector2(sz, sz)
	rect.position = pos - rect.size * 0.5
	rect.color = col
	rect.name = "EditorDemo_%s_%d" % [type, Time.get_ticks_msec()]
	parent.add_child(rect)

	# Store for export / roundtrip (extend with terrain, province hint, variant keys)
	if not has_meta("editor_placements"):
		set_meta("editor_placements", [])
	var placements: Array = get_meta("editor_placements", [])
	placements.append({
		"type": type,
		"position": [pos.x, pos.y],
		"size": sz,
		"terrain_aware": true,  # would query actual terrain at pos via province or data
		"notes": "demo placed via starter visual editor; desert limits density, hills/swamp tint adjusted"
	})
	set_meta("editor_placements", placements)

	print("MapRenderer: Editor placed demo %s at %s (precise on high-res grand bg or exact from load/LMB). Tied to image + province area. Export for python roundtrip." % [type, pos])
	# Note: for desert provinces (tagged in Python identify), future placement code can
	# auto-use sand_track style, lower density, special runway/port sprites etc.


## Export current editor placements (manual + data-driven) as dict for DebugOverlay to
## save/roundtrip to Python map gen tool (e.g. to refine city_layer, add visual features
## for hills/swamp/desert, or bake into new variant images).
func export_editor_placements() -> Dictionary:
	var data := {
		"version": 1,
		"source": "starter_map_visual_editor",
		"generated_at": Time.get_datetime_string_from_system(),
		"placements": get_meta("editor_placements", []),
		"notes": [
			"Positions are in world/map coords matching the bg image fit in MapRenderer.",
			"Use with GRAND THEATER expanded geo (full UK/Ireland + Scandinavia high north + N Russia Murmansk/Kola/Arkhangelsk + Canaries/NA/Egypt/Suez/Iraq/ME).",
			"Python tool can merge these into province_city_layer or visual_variants.",
			"Desert infra: limited by design; seasons/regional snow (heavy north), bomb damage, era/culture (tech+focus+country) to be layered.",
			"Call spawn_data_driven_objects_from_layers() after loading new data to refresh."
		]
	}
	print("MapRenderer: export_editor_placements -> %d manual/editor placements" % data["placements"].size())
	return data


## Clear demo/editor objects (for iteration in visual editor / playtest).
func clear_editor_demo_objects() -> void:
	if container == null:
		return
	var parent := container.get_node_or_null("DataDrivenObjects") as Node2D
	if parent:
		parent.queue_free()
		print("MapRenderer: Cleared DataDrivenObjects (demo editor placements and data-driven spawns). Re-apply bg or reload to respawn from layers.")
	# Also clear meta placements
	if has_meta("editor_placements"):
		set_meta("editor_placements", [])


## Public: returns current editor placements array (for Debug list, export, roundtrip).
func get_editor_placements() -> Array:
	return get_meta("editor_placements", []) as Array


## Public: remove a placement entry by approximate position (used by editor list Delete).
func remove_editor_placement_at(pos: Vector2, tol: float = 30.0) -> bool:
	if not has_meta("editor_placements"):
		return false
	var arr: Array = get_meta("editor_placements", [])
	for i in range(arr.size() - 1, -1, -1):
		var p: Dictionary = arr[i] as Dictionary
		var pp := Vector2(float(p.get("position", [0, 0])[0]), float(p.get("position", [0, 0])[1]))
		if pp.distance_to(pos) <= tol:
			arr.remove_at(i)
			set_meta("editor_placements", arr)
			return true
	return false


## Toggle separate terrain layer (detailed high-res raster bg vs clean political view).
## When disabled: hides the beautiful terrain/rivers/hills image so polys show solid ownership colors (clean view for focus on infra/ownership or precise editing).
func toggle_terrain_layer() -> void:
	set_show_terrain_layer(not show_terrain_layer)


func set_show_terrain_layer(enabled: bool) -> void:
	show_terrain_layer = enabled
	_apply_terrain_layer_visibility()
	_refresh_terrain_zoom_aware()
	print("MapRenderer: Terrain layer ", "ON (detailed high-res bg + thin outlines)" if enabled else "OFF (CLEAN POLITICAL VIEW - solid fills, no terrain raster)")
	_sync_batched_mesh_fills(true)


func _apply_terrain_layer_visibility() -> void:
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg:
		bg.visible = show_terrain_layer
		if show_terrain_layer:
			bg.modulate = Color(0.92, 0.90, 0.85, 0.92)
		else:
			bg.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if terrain_layer_stack:
		terrain_layer_stack.show_base_layer = show_terrain_layer
		terrain_layer_stack.visible = show_terrain_layer
		terrain_layer_stack._apply_visibility()
		_refresh_terrain_zoom_aware()
	# Force repaint of fills with correct alpha (low for terrain visible, higher for clean political)
	_fill_color_zoom_bucket = -999999999

func _refresh_terrain_zoom_aware() -> void:
	if terrain_layer_stack and terrain_layer_stack.has_method("apply_zoom_level") and container:
		var z: float = absf(container.scale.x)  # current zoom level (scale of the map container)
		terrain_layer_stack.call("apply_zoom_level", z)
	for id in province_nodes.keys():
		_refresh_single_province_fill(id)
	_suppress_old_background_maps()
	# If weather snow/blackout active, let it re-apply tint/veil now that terrain visibility changed (cheap rebuild)
	call_deferred("_maybe_refresh_weather_for_terrain")


func _maybe_refresh_weather_for_terrain() -> void:
	if container == null: return
	var wl := container.get_node_or_null("WeatherOverlayLayer") as Node
	if wl and wl.has_method("_rebuild_visuals"):
		wl.call("_rebuild_visuals")


## Centralized suppression so old grey/black (world_map.png, generated ProvinceMap rasters, etc) NEVER show underneath the desired high-res grand theater map.
func _suppress_old_background_maps() -> void:
	# Under container (most rasters live here after preserve/reattach)
	if container:
		for c in container.get_children():
			if c is Sprite2D:
				var s := c as Sprite2D
				var rp := str(s.texture.resource_path).to_lower() if s.texture else ""
				if s.name in ["ProvinceMap", "BaseMap", "MapRaster"] or "world_map" in rp or "grey" in rp or "gray" in rp:
					s.visible = false
					s.texture = null
					s.modulate = Color(0, 0, 0, 0)
	# Also check siblings/parent level (scene root may have ProvinceMap)
	var p := get_parent()
	if p:
		for c in p.get_children():
			if c is Sprite2D:
				var s := c as Sprite2D
				var rp := str(s.texture.resource_path).to_lower() if s.texture else ""
				if s.name in ["ProvinceMap", "BaseMap", "MapRaster"] or "world_map" in rp:
					s.visible = false
					s.texture = null
					s.modulate = Color(0, 0, 0, 0)
	# Deep search for any lingering
	var old_pm := find_child("ProvinceMap", true, false) as Sprite2D
	if old_pm:
		old_pm.visible = false
		old_pm.texture = null
		old_pm.modulate = Color(0, 0, 0, 0)
	var old_bg := find_child("WorldBackground", true, false) as Sprite2D
	if old_bg and old_bg.texture:
		var rp2 := str(old_bg.texture.resource_path).to_lower()
		if "world_map" in rp2 and show_terrain_layer:  # only kill if it's the bad one
			old_bg.visible = false
			old_bg.texture = null
	# Extra: in grand high-res mode, any other large Sprite that looks like a full-screen map raster (gray / generated / black) gets hidden so the styled one is the clear base.
	if is_using_grand_stylized_map() and container:
		var current_wb := find_child("WorldBackground", true, false) as Sprite2D
		for c in container.get_children():
			if c is Sprite2D and c != current_wb:
				var s := c as Sprite2D
				if s.texture:
					var rps := str(s.texture.resource_path).to_lower()
					var sz := s.texture.get_size()
					if sz.x > 1000 and sz.y > 500 and ("map" in rps or "province" in rps or "base" in rps or "raster" in rps or "grey" in rps or "gray" in rps or "world" in rps):
						s.visible = false
						s.modulate = Color(0,0,0,0)


## Demo: adds NATO symbol sprites (using generated assets) to province nodes that have
## stationed formations (from the test spawns in TestRunner / phase1 loads).
## Replaces previous ColorRect fallback now that proper symbol suite exists.
func _update_unit_icons_for_test() -> void:
	if typeof(SupplyManager) == TYPE_NIL or not SupplyManager.has_method("get_formations_stationed_at_province"):
		return

	# Clear any previous demo icons
	for id in province_nodes.keys():
		var n := province_nodes[id]
		if n == null: continue
		for c in n.get_children():
			if c.name.begins_with("DemoUnitIcon_"):
				c.queue_free()

	var idx := 0
	for id in province_nodes.keys():
		var forms: Array = SupplyManager.get_formations_stationed_at_province(id)
		var p: Province = provinces.get(id)
		var has_unit := not forms.is_empty()
		if not has_unit and p and not p.owner_tag.is_empty() and not SupplyManager.division_deployments.is_empty():
			for fid in SupplyManager.division_deployments:
				var dep: Dictionary = SupplyManager.division_deployments[fid] as Dictionary
				if int(dep.get("province_id", -1)) == id:
					has_unit = true
					break
		if not has_unit:
			continue

		var n := province_nodes[id]
		var counter := Node2D.new()
		counter.name = "DemoUnitIcon_" + str(id)
		counter.position = Vector2(0, -8)
		counter.scale = Vector2(0.6, 0.6)
		n.add_child(counter)

		# Use actual NATO symbol if available, type-aware for starting/buildable units.
		# Now driven primarily by visual_archetype from the design template (enriched for #engines, fighter/bomber types, carrier variants, jet/prop, biplane, ship size/type/era, tank class/era, helos, transports etc.)
		# Falls back to heuristics on ftype/design name. Supports ww2/modern subfolders.
		var tex_path := "res://assets/graphics/units/nato/modern/infantry_32.png"
		var ftype := ""
		var arch := ""
		var dsn := ""
		if forms.size() > 0:
			var ff = forms[0]
			if ff and ff.has_method("get_category"):
				ftype = ff.get_category()
			elif "formation_type" in ff:
				ftype = str(ff.formation_type)
			# Resolve design + visual_archetype for precise model (fighter_1eng, bomber_4eng, carrier_fighter, jet_fighter, biplane_fighter, light_carrier, fleet_carrier, ww1_tank, interwar_light_tank, light_tank, medium_tank, heavy_tank, etc.)
			if ff and "design_id" in ff and str(ff.design_id) != "": dsn = str(ff.design_id).to_lower()
			if ff and "naval_design_id" in ff and str(ff.naval_design_id) != "": dsn = str(ff.naval_design_id).to_lower()
			if ff and "air_design_id" in ff and (dsn == "" or "air" in ftype): dsn = str(ff.air_design_id).to_lower()
			if dsn != "" and typeof(GameData) != TYPE_NIL and GameData.has_method("design_data") and GameData.design_data != null:
				var tpl = GameData.design_data.get_template(dsn)
				if tpl != null:
					arch = str(tpl.visual_archetype).to_lower().strip_edges()
		# Era folder
		var era_folder := "modern"
		if "ww1" in arch or "ww2" in arch or "interwar" in arch or "191" in dsn or "193" in dsn or "194" in dsn:
			era_folder = "ww2"
		# Map archetype to icon (precise for engines/type/carrier/jet/biplane/ship_size/tank_class)
		if arch != "":
			if "biplane" in arch:
				tex_path = "res://assets/graphics/units/nato/ww2/fighter_32.png"
			elif "jet_fighter" in arch or ("fighter" in arch and "jet" in arch):
				tex_path = "res://assets/graphics/units/nato/modern/fighter_32.png"
			elif "carrier_fighter" in arch or ("fighter" in arch and "carrier" in arch):
				tex_path = "res://assets/graphics/units/nato/modern/fighter_32.png"
			elif "prop_fighter" in arch or "fighter" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/fighter_32.png"
			elif "dive_bomber" in arch or "dive" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"
			elif "four_engine_bomber" in arch or "foureng" in arch or ("bomber" in arch and ("4" in arch or "b17" in dsn or "strat" in dsn)):
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"
			elif "twin_engine_bomber" in arch or ("bomber" in arch and "2" in arch):
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"
			elif "bomber" in arch or "bomber" in ftype.to_lower():
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"
			elif "light_carrier" in arch or "fleet_carrier" in arch or ("carrier" in arch and ("ship" in arch or "naval" in ftype)):
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/carrier_32.png"
			elif "light_tank" in arch or ("light" in arch and "tank" in arch):
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/light_tank_32.png"
			elif "heavy_tank" in arch or ("heavy" in arch and "tank" in arch):
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/heavy_tank_32.png"
			elif "medium_tank" in arch or "tank" in arch or "panzer" in dsn or "sherman" in dsn or "tiger" in dsn or "t34" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/medium_tank_32.png"
			elif "helicopter" in arch or "helo" in arch or "naval_helicopter" in arch or "attack_helicopter" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/helicopter_32.png"
			elif "seaplane" in arch or "flying_boat" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"  # proxy, or add seaplane icon later
			elif "jet_bomber" in arch:
				tex_path = "res://assets/graphics/units/nato/modern/bomber_32.png"
			elif "truck" in arch or "logistics" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/logistics_32.png"
			elif "armored_vehicle" in arch or "apc" in arch or "ifv" in arch or "recon" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/medium_tank_32.png"  # armored car proxy
			elif "amphib_tank" in arch or "amphib_vehicle" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/light_tank_32.png"  # amphib proxy
			elif "armed_merchant" in arch or "naval_transport" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/logistics_32.png"  # or destroyer if armed
			elif "submarine" in arch or "sub" in arch or "uboat" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/submarine_32.png"
			elif "battleship" in arch or "cruiser" in arch or "frigate" in arch or "destroyer" in arch or "patrol" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/destroyer_32.png"  # or cruiser if asset, but use destroyer/cruiser
			elif "transport" in arch or "logistics" in arch or "merchant" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/logistics_32.png"
			elif "rocket" in arch or "mlrs" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/rocket_32.png"
			elif "artillery" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/artillery_32.png"
			elif "infantry" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/infantry_32.png"
			# fallback for other archetypes to closest
		# Legacy ftype + dsn heuristics (for compatibility)
		if "naval" in ftype or "ship" in ftype or "sub" in ftype.to_lower():
			if "carrier" in ftype or "carrier" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/carrier_32.png"
			else:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/destroyer_32.png"
		elif "air" in ftype or "plane" in ftype or "bomber" in ftype.to_lower():
			if "bomber" in arch or "bomber" in ftype.to_lower() or "b17" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"
			else:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/fighter_32.png"
		elif "tank" in ftype or "armor" in ftype:
			if "light" in arch or "light_tank" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/light_tank_32.png"
			elif "heavy" in arch or "heavy_tank" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/heavy_tank_32.png"
			else:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/medium_tank_32.png"
		# dsn name overrides for legacy
		if dsn != "":
			if "panzer" in dsn or "sherman" in dsn or "tiger" in dsn or "medium_tank" in dsn or "t34" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/medium_tank_32.png"
			elif "u_boat" in dsn or "fletcher" in dsn or "destroyer" in dsn or "bismarck" in dsn or "king_george" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/destroyer_32.png"
			elif "bf109" in dsn or "p51" in dsn or "spitfire" in dsn or "zero" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/fighter_32.png"
			elif "b17" in dsn or "bomber" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"
		var tex: Texture2D = load(tex_path) as Texture2D
		# Enhance with NATO sheet variants for majors or researched (e.g. SOV/GER tanks use sheet subregions for grey/blue/green/khaki variants per tag/era; falls back to individuals)
		if _nato_sheet_tex != null and tex != null and (p and p.owner_tag in ["GER","SOV","FRA","ENG","USA"] or "tank" in arch or "armor" in arch or "medium" in arch or "heavy" in arch):
			var reg := _get_nato_sheet_region( (p.owner_tag if p else ""), arch, era_folder )
			if reg.size.x > 0:
				var atlas := AtlasTexture.new()
				atlas.atlas = _nato_sheet_tex
				atlas.region = reg
				tex = atlas as Texture2D
		if tex:
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = true
			# Nation-specific color tint for land forces/units to make them distinct on map (not overlapping neighbors). Use country color for modulation on land/armor icons.
			var use_nation_color = "tank" in arch or "armored" in arch or "truck" in arch or "infantry" in arch or "light_tank" in arch or "medium_tank" in arch or "heavy_tank" in arch or "amphib" in arch
			if use_nation_color and p and p.owner_tag:
				var nation_col = Color(0.8, 0.8, 0.8, 1.0)
				if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_country_color"):
					nation_col = MapManager.get_country_color(p.owner_tag)
				spr.modulate = nation_col  # tint the NATO symbol with nation color for land forces
			counter.add_child(spr)
		else:
			# fallback rect if texture missing
			var bg := ColorRect.new()
			bg.size = Vector2(20, 16)
			bg.position = Vector2(-10, -8)
			bg.color = Color(0.1, 0.12, 0.18, 0.9)
			counter.add_child(bg)

		idx += 1

	# Also refresh riot/event markers (tied to active_riots in GameData) after unit icons for map modes.
	_update_riot_markers()


## Riot / crisis event overlay markers (simple Node2D sprites on province nodes for provinces with GameData.active_riots).
## Uses riot_crowd_64 (or generated riot_marker) + small red tint hint. Called on unit refresh + data_changed for live.
## Visible on political map mode or any; inspector hover gets tint from fill.
func _update_riot_markers() -> void:
	# Clear old
	for id in province_nodes.keys():
		var n := province_nodes[id]
		if n == null: continue
		for c in n.get_children():
			if c.name.begins_with("RiotMarker_"):
				c.queue_free()

	if typeof(GameData) == TYPE_NIL or not GameData.has_method("has_active_riot"):
		return
	var riot_pids := []
	if GameData.has_method("get_provinces_with_active_riots"):
		riot_pids = GameData.get_provinces_with_active_riots()
	else:
		return
	if riot_pids.is_empty():
		return

	for pidv in riot_pids:
		var pid := int(pidv)
		if not province_nodes.has(pid): continue
		var n := province_nodes[pid]
		var marker := Node2D.new()
		marker.name = "RiotMarker_" + str(pid)
		marker.position = Vector2(12, -14)  # offset top-rightish of province label/unit
		marker.scale = Vector2(0.55, 0.55)
		n.add_child(marker)

		var tex: Texture2D = _riot_icon_tex
		if tex == null:
			tex = load("res://assets/graphics/icons/events/riot_crowd_64.png") as Texture2D
			if tex == null:
				tex = load("res://assets/graphics/icons/events/riot_marker_32.png") as Texture2D
		if tex:
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = true
			spr.modulate = Color(0.95, 0.4, 0.35, 0.95)  # riot red accent
			marker.add_child(spr)
		else:
			# fallback emoji-ish rect or label
			var fb := Label.new()
			fb.text = "⚠"
			fb.add_theme_font_size_override("font_size", 10)
			fb.modulate = Color(0.9,0.3,0.3,0.9)
			marker.add_child(fb)


## --- Dynamic country frontiers (shared-edge model) ---

func force_border_update() -> void:
	_update_country_borders()


func _ensure_border_layer() -> void:
	if border_layer != null and is_instance_valid(border_layer):
		return
	if container == null:
		return
	border_layer = Node2D.new()
	border_layer.name = "BorderLayer"
	border_layer.z_index = 15
	container.add_child(border_layer)


func _update_country_borders(_affected_pids: Array = []) -> void:
	_ensure_border_layer()
	if border_layer == null or province_nodes.is_empty():
		return
	_sync_shared_edge_frontiers(province_nodes.keys())


func _sync_shared_edge_frontiers(_scan_pids: Array) -> void:
	for child in border_layer.get_children():
		var cname := str(child.name)
		if cname.begins_with(COUNTRY_FRONTIER_PREFIX):
			child.queue_free()

	var edge_map: Dictionary = {}
	for pid_var in province_nodes.keys():
		var pid := int(pid_var)
		var owner := _live_owner_tag(pid)
		if owner.is_empty():
			continue
		var pts := _province_polygon_points(pid)
		if pts.size() < 3:
			continue
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var key := _canonical_edge_key(a, b)
			if not edge_map.has(key):
				edge_map[key] = {"a": a, "b": b, "owners": {}, "count": 0}
			var rec: Dictionary = edge_map[key]
			rec["owners"][owner] = true
			rec["count"] = int(rec.get("count", 0)) + 1

	var seg_idx := 0
	for key in edge_map.keys():
		var rec: Dictionary = edge_map[key]
		var owners: Dictionary = rec.get("owners", {})
		var count := int(rec.get("count", 0))
		var is_international := owners.size() >= 2
		var is_outer := count <= 1
		if not is_international and not is_outer:
			continue
		var a: Vector2 = rec.get("a", Vector2.ZERO)
		var b: Vector2 = rec.get("b", Vector2.ZERO)
		var seg := Line2D.new()
		seg.name = COUNTRY_FRONTIER_PREFIX + str(seg_idx)
		seg.points = PackedVector2Array([a, b])
		# Per-nation border colors for clear visibility of each nation's borders (use owner color from MapManager)
		var use_color := COUNTRY_BORDER_COLOR
		if owners.size() == 1:
			var own := owners.keys()[0] as String
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_country_color"):
				use_color = MapManager.get_country_color(own)
		seg.default_color = use_color
		seg.width = MapZoomLODScript.country_border_width(_map_lod_tier)
		var ba: float = MapZoomLODScript.country_border_alpha(_map_lod_tier)
		seg.default_color.a = ba
		seg.antialiased = true
		seg.joint_mode = Line2D.LINE_JOINT_ROUND
		seg.begin_cap_mode = Line2D.LINE_CAP_ROUND
		seg.end_cap_mode = Line2D.LINE_CAP_ROUND
		border_layer.add_child(seg)
		seg_idx += 1


func _live_owner_tag(province_id: int) -> String:
	var live: Province = null
	if typeof(MapManager) != TYPE_NIL:
		live = MapManager.get_province(province_id)
	if live == null:
		live = provinces.get(province_id)
	if live == null:
		return ""
	return live.owner_tag.strip_edges().to_upper()


func _province_polygon_points(province_id: int) -> PackedVector2Array:
	if province_nodes.has(province_id):
		var pnode: Node2D = province_nodes[province_id]
		for ch in pnode.get_children():
			if ch is Polygon2D:
				return (ch as Polygon2D).polygon
	if geometry.has(province_id):
		var g: Dictionary = geometry[province_id]
		var pts: PackedVector2Array = g.get("points", PackedVector2Array())
		if pts.size() >= 3:
			return MapCanvasConfig.transform_province_points(pts, _is_world_canvas_active(), true)
	return PackedVector2Array()


func _canonical_edge_key(a: Vector2, b: Vector2) -> String:
	var step := _EDGE_KEY_PRECISION
	var ax := int(roundf(a.x / step))
	var ay := int(roundf(a.y / step))
	var bx := int(roundf(b.x / step))
	var by := int(roundf(b.y / step))
	if ax > bx or (ax == bx and ay > by):
		var tx := ax
		ax = bx
		bx = tx
		var ty := ay
		ay = by
		by = ty
	return "%d,%d|%d,%d" % [ax, ay, bx, by]


static func debug_cycle_province_owner(province_id: int) -> void:
	var mr := Engine.get_main_loop().root.get_first_node_in_group("map_renderer") as MapRenderer
	if mr == null or province_id < 0:
		return
	mr._cycle_province_owner_tag(province_id)


func _cycle_province_owner_tag(province_id: int) -> void:
	if not provinces.has(province_id):
		return
	const DEMO_TAGS: Array[String] = ["YUG", "SRB", "CRO", "SLO", "HUN", "BGR", "GER", "SOV", "USA", "ENG"]
	var prov: Province = provinces[province_id]
	var current := prov.owner_tag.to_upper() if not prov.owner_tag.is_empty() else "YUG"
	var idx := DEMO_TAGS.find(current)
	var next_tag := DEMO_TAGS[(idx + 1) % DEMO_TAGS.size()] if idx >= 0 else DEMO_TAGS[0]
	if typeof(MapManager) != TYPE_NIL:
		MapManager.ensure_country_stub(next_tag)
		MapManager.update_province_owner(province_id, next_tag, next_tag, false)
	else:
		prov.owner_tag = next_tag
		prov.controller_tag = next_tag
		_refresh_single_province_fill(province_id)
		_update_country_borders()
	if typeof(DebugOverlay) != TYPE_NIL and DebugOverlay.is_map_debug_tools_active():
		DebugOverlay.toast_map_debug("Province %d → %s" % [province_id, next_tag])
