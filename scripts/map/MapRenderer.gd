# scripts/map/MapRenderer.gd
class_name MapRenderer
extends Node2D

const _MapPolishFormatters := preload("res://scripts/map/MapPolishFormatters.gd")
const _MapNextListHelpers := preload("res://scripts/map/MapNextListHelpers.gd")
const ProvincePolygonUtil = preload("res://scripts/map/ProvincePolygonUtil.gd")
const _OccupationOverlayLayerScr = preload("res://scripts/map/OccupationOverlayLayer.gd")
const _MapRendererPerfScr = preload("res://scripts/map/MapRendererPerf.gd")
const _StrategicFlowOverlayLayerScr = preload("res://scripts/map/StrategicFlowOverlayLayer.gd")
const _BattleIndicatorOverlayLayerScr = preload("res://scripts/map/BattleIndicatorOverlayLayer.gd")
const _DomainOpsOverlayLayerScr = preload("res://scripts/map/DomainOpsOverlayLayer.gd")
const _LeaderStationOverlayLayerScr = preload("res://scripts/map/LeaderStationOverlayLayer.gd")
const _ConstructionProgressOverlayLayerScr = preload("res://scripts/map/ConstructionProgressOverlayLayer.gd")
const RoutePackQRScr = preload("res://scripts/ui/RoutePackQR.gd")
const _SFX_PATHS := {
	"select": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Select.wav",
	"confirm": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Click Bounce.wav",
	"achievement": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Achievement.wav",
	"error": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Error.wav",
	"map": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Map.wav",
	## Pass 55: pin-focus pulse cue (Map.wav soft ping).
	"pin_focus": "res://Sound FX Starter Pack Vol. 1/UI & Menus/Map.wav",
}
var _last_select_flair_pid: int = -1
var _last_select_flair_msec: int = 0
var _map_sfx_player: AudioStreamPlayer = null

#region Exports
const _TerrainTiles = preload("res://scripts/map/TerrainTileLibrary.gd")
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
## Low = continuous ocean (hides void-hex / coarse tile seams). High = per-owner sea tint.
@export_range(0.05, 0.55, 0.01) var sea_political_trace: float = 0.08
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
@export var pan_speed: float = 2200.0
@export var edge_scroll_speed: float = 2200.0
@export var edge_margin: float = 64.0
@export var zoom_speed: float = 0.18
## Floor zoom-out; world GIS boards may lower further via world_min_zoom.
@export var min_zoom: float = 0.06
@export var max_zoom: float = MapCanvasConfig.MAX_CAMERA_ZOOM
@export var middle_mouse_pan_speed: float = 1.2
## Toroidal wrap confuses GIS world_accurate pan (can't "reach" Europe). Prefer off for full world boards.
@export var enable_map_wrap: bool = false
## Extra zoom-out floor for ~14k-wide GIS world (see all continents).
@export var world_min_zoom: float = 0.045
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

## HOI4/EU4-style: international frontiers are near-black (fills carry nation color).
## Never stroke every unmatched GIS edge in owner color — that creates the NUTS spiderweb.
const COUNTRY_BORDER_COLOR := Color(0.04, 0.05, 0.08, 0.94)
const COUNTRY_BORDER_WIDTH := 3.2
const COAST_BORDER_COLOR := Color(0.02, 0.04, 0.08, 0.55)
const PROVINCE_INTERNAL_BORDER_COLOR := Color(0.08, 0.09, 0.12, 0.22)
const COUNTRY_FRONTIER_PREFIX := "CountryFrontier_"
const COAST_FRONTIER_PREFIX := "CoastEdge_"
const PROVINCE_EDGE_PREFIX := "ProvEdge_"
## GIS NUTS verts rarely share exact coords; 2.5px bin still matches most shared edges.
const _EDGE_KEY_PRECISION := 2.5

## Toggle for separate terrain layer (the high-res detailed raster bg image). When OFF: clean political view (solid ownership fills, no terrain texture underneath) — highly valued in grand strat (HOI4/EU4 players often prefer political/clean for readability of borders/infra/ownership; use terrain mode for combat planning/immersion). Perfect for map editing at close zoom too.
## Default OFF: world underlay hex/void ocean + muddy double-stack made political unreadable (2026-07 playtest).
var show_terrain_layer: bool = false
## Master switch for OOB unit counters (round/square pins). LOD still hides at strategic zoom when ON.
## Toggle with **U**. Default ON — operational/tactical show units; strategic stays clean political.
var show_unit_counters: bool = true
## Solid deep-ocean plate under provinces so gaps never show void-hex underlay or grey clear color.
var _ocean_floor: Polygon2D = null

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
## Map-space selection outline (reliable when per-node polys are thin/hidden).
var _select_outline_layer: Node2D = null
var _select_outline_line: Line2D = null
var _select_outline_glow: Line2D = null
var _march_path_line: Line2D = null
var _next_hook_chip: Button = null
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
var _border_lod_tier_built: int = -999  # last tier used when frontiers were rebuilt
var _political_labels_layer: Node2D = null
var _political_labels_rebuild_pending: bool = false
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
#region Occupation overlay (gap-closure Phase 1 — #24 visual depth)
## Default off for playability — occupation poly fills on world_full invalid geometry hung F5
## (triangulation failed spam). Toggle with O / F10 when needed.
@export var show_occupation_overlay: bool = false
var _occupation_layer = null  # OccupationOverlayLayer
#endregion
#region Phase 2/3 gap-closure overlays
@export var show_strategic_flow_overlay: bool = false
## Independent of master supply/sealane overlay — EquipmentFlow story glyphs only.
@export var show_equipment_flow_glyphs: bool = true
@export var show_battle_indicator_overlay: bool = false  # Off by default — continuous redraw freezes world_full pan/hover
@export var show_domain_ops_overlay: bool = false
@export var show_leader_station_overlay: bool = false
@export var show_construction_progress_overlay: bool = false  # On-demand; default off for world_full frame budget
var _strategic_flow_layer = null
var _battle_indicator_layer = null
var _land_battle_bubble_layer: Node2D = null
var _domain_ops_layer = null
var _leader_station_layer = null
var _construction_progress_layer = null
#endregion
#region Perf profile (gap-closure Phase 1)
@export var enable_perf_profile: bool = false
var _perf = null  # MapRendererPerf
var _perf_frame_start_usec: int = 0
#endregion
#endregion

#region Agent network overlay
@export var show_agent_overlay: bool = false  # Default off — ambient pulse redraw froze interactive F5
var _agent_layer: AgentNetworkLayer = null
#endregion

var weather_layer: Node = null  # WeatherOverlayLayer when present (grand high-res snow/blackout etc.)
var terrain_layer_stack: TerrainLayerStack = null  # NASA/NE real-world layers when built
var _world_class_bootstrapped: bool = false

var _btn_station_engineers: Button = null

# Demo map tint mode for strain (welfare) / vitality (settlement) / development re-tint layers (wired from DebugOverlay / hotkeys F1-F4).
# "supply" handled via the L overlay toggle (existing supply layer) but exposable as mode.
var debug_tint_mode: String = ""  # "", "vitality", "strain", "development", "loyalty", "infra"  -- boosts the corresponding tint/characterize layer for basic mapmode-style views. Use set_map_mode().
## Pass 16/17: secondary stacked tints (e.g. vitality primary + strain + loyalty).
var debug_tint_mode_secondary: String = ""  # first secondary (compat)
var debug_tint_mode_secondaries: Array = []  # Pass 17: full secondary list
## Pass 20: per-secondary intensity 0.25–2.0 (default 1.0). Also drives primary tint strength for matching modes (Pass 22).
var secondary_tint_intensity: Dictionary = {}
## Pass 22: remembered intensity per primary mapmode (restored on mode switch).
var primary_mapmode_intensity: Dictionary = {}
## Pass 21: named intensity presets for secondaries.
const SECONDARY_INTENSITY_PRESETS: Dictionary = {
	"soft": 0.5,
	"med": 1.0,
	"hard": 1.5,
	"max": 2.0,
}
## Modes whose primary fill strength is scaled by intensity.
const INTENSITY_LINKED_MODES: Array = ["strain", "vitality", "development", "loyalty", "munitions"]
var current_map_mode: String = "political"  # "political" | "strain" | "vitality" | "development" | "supply" | "munitions" | "loyalty" | "infra"  (Phase 2 map UX)
## Pass 13: weather legend click filter (empty = show all ground states).
var weather_ground_filter: String = ""


var _map_mode_toolbar: PanelContainer = null
var _info_panel_dragging: bool = false
var _info_panel_drag_offset: Vector2 = Vector2.ZERO
var _map_minimap: PanelContainer = null
var _map_search: HBoxContainer = null
var _adjacency_preview: Node2D = null
var _province_mesh_layer: Node2D = null
var _province_id_badge: Label = null
## Pass 51: shared bulk chip selection across multi-window library popups.
var _route_pack_bulk_sel: Array = []  # [{kind, value}]
var _route_pack_bulk_watchers: Array = []  # Callables
## Pass 52: temporary pin-focus pulse rings at world position.
var _pin_focus_pulse_node: Node2D = null
var _pin_focus_pulse_t: float = 0.0
const PIN_FOCUS_PULSE_DURATION := 1.55
## Pass 54: pin focus history stack (newest last) for Pin Back.
var _pin_focus_history: Array = []  # [{pid, label, source, risk, zoom}]
const PIN_FOCUS_HISTORY_MAX := 32
## Phase E: batched political fills at strategic zoom (fewer per-poly tint updates).
const BATCHED_MESH_ZOOM_MAX := 0.55
var _batched_mesh_fills_prefer: bool = true
var _batched_mesh_fills_forced: bool = false
var _batched_mesh_active: bool = false
var _map_mode_apply_scheduled: bool = false
var _last_mesh_zoom_bucket: int = -999


func _ready():
	add_to_group("map_renderer")
	_ensure_perf()
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
	# IMPORTANT: load texture BEFORE unify reparent. get_node_or_null("WorldBackground") only finds
	# direct children — after reparent under ProvinceContainers it returns null and underlay setup
	# was skipped, then apply_phase1_europe_background stuffed Europe 5k×2k under world polys → dual map.
	var init_bg := find_child("WorldBackground", true, false) as Sprite2D
	if init_bg == null:
		init_bg = get_node_or_null("WorldBackground") as Sprite2D
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
			# Texture loaded for optional terrain mode; clean political hides it (no void-hex ocean).
			init_bg.visible = show_terrain_layer
			init_bg.modulate = Color(0.95, 0.93, 0.88, 0.95) if show_terrain_layer else Color(1.0, 1.0, 1.0, 0.0)
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
				init_bg.visible = show_terrain_layer
				init_bg.modulate = Color(0.8, 0.85, 0.7, 0.9) if show_terrain_layer else Color(1.0, 1.0, 1.0, 0.0)
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

	# AFTER underlay texture is set: unify parent + fit equirect (single canvas).
	_unify_map_canvas_transform()
	_fit_background_to_bounds()
	# Clean political default: hide photo underlay + continuous ocean floor (void-hex fix).
	_ensure_ocean_floor()
	_apply_terrain_layer_visibility()
	_apply_clean_political_clear_color()
	call_deferred("_unify_map_canvas_transform")
	call_deferred("_fit_background_to_bounds")
	call_deferred("_ensure_ocean_floor")
	call_deferred("_apply_terrain_layer_visibility")

	_setup_hover_tooltip()
	_setup_inspector_extras()
	_connect_time_manager_signals()
	_connect_map_manager_signals()
	_connect_trade_manager_signals_for_map_layers()
	_init_legend_calendar_tracking()
	process_mode = Node.PROCESS_MODE_ALWAYS  # pan/zoom/edge while sim paused
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
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
		# Nation names follow era ownership / control (debounced — avoid rebuild per province in mass transfers).
		_schedule_political_labels_rebuild()
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
	# Interactive 1x: never repaint fills on the day tick (even deferred queue) — month only.
	var light := (
		typeof(TimeManager) != TYPE_NIL
		and TimeManager.has_method("is_interactive_light_sim")
		and bool(TimeManager.is_interactive_light_sim())
	)
	if not light:
		_refresh_province_fill_colors()
	_refresh_map_time_ui()
	var open_n := _sync_land_battle_bubbles()
	if open_n > 0:
		_play_map_sfx("map")
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_open_land_battles"):
			for raw_b in BattleManager.get_open_land_battles():
				if typeof(raw_b) != TYPE_DICTIONARY:
					continue
				var hook_s := str((raw_b as Dictionary).get("next_hook", ""))
				if "tomorrow" in hook_s.to_lower():
					_show_inspector_toast(hook_s, 4.5)
					break
		if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("peek_last_land_aar"):
			var aar: Dictionary = BattleManager.peek_last_land_aar()
			var aar_line := str(aar.get("line", ""))
			if not aar_line.is_empty():
				_show_inspector_toast(aar_line, 5.5)
				_play_map_sfx("achievement" if str(aar.get("winner", "")) == "attacker" else "map")
	# Pass 17: live-update airfield repair rings without full province rebuild.
	call_deferred("_refresh_feature_progress_rings")
	# Pass 22: refresh repair queue chip list on day advance.
	if _repair_queue_chip != null and is_instance_valid(_repair_queue_chip) and _repair_queue_chip.visible:
		if _repair_queue_chip.has_method("refresh"):
			_repair_queue_chip.call_deferred("refresh")
	# Pass 21/22: munitions desk samples on day tick via its own signal; nudge if visible.
	if _munitions_desk != null and is_instance_valid(_munitions_desk) and _munitions_desk.visible:
		if _munitions_desk.has_method("push_sample"):
			_munitions_desk.call_deferred("push_sample")
		if _munitions_desk.has_method("refresh"):
			_munitions_desk.call_deferred("refresh")
	# Pass 23: refresh munitions minimap pips when shown.
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("invalidate_munitions_cache"):
			_map_minimap.call_deferred("invalidate_munitions_cache")
	# Pass 25: sample multi-day risk history for active compare paths.
	_sample_route_risk_day_history()


func _on_time_advanced_refresh_legend(_a: Variant = null, _b: Variant = null) -> void:
	_note_time_boundary_for_legend(_b != null)
	_refresh_map_time_ui()
	var light := (
		typeof(TimeManager) != TYPE_NIL
		and TimeManager.has_method("is_interactive_light_sim")
		and bool(TimeManager.is_interactive_light_sim())
	)
	# Month boundary: one deferred fill is enough; never sync-paint inside the tick.
	if light:
		call_deferred("_refresh_province_fill_colors")
	else:
		_refresh_province_fill_colors()


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
		info_name = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelName") as Label
	if info_owner == null:
		info_owner = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelOwner") as Label
	if info_population == null:
		info_population = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelPopulation") as Label
	if info_terrain == null:
		info_terrain = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelTerrain") as Label
	if info_factories == null:
		info_factories = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelFactories") as Label
	if info_dev == null:
		info_dev = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelDev") as Label
	if info_resources == null:
		info_resources = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelResources") as Label
	if info_core == null:
		info_core = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelCore") as Label
	if info_special == null:
		info_special = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelSpecial") as Label
	if info_logistics == null:
		info_logistics = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelLogistics") as Label
	if info_combat == null:
		info_combat = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelCombat") as Label
	if info_modifiers == null:
		info_modifiers = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/RichTextModifiers") as RichTextLabel
	if info_national == null:
		info_national = ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelNationalHeader") as Label
	if btn_national_spirits == null:
		btn_national_spirits = ui.get_node_or_null("InfoPanel/BtnNationalSpirits") as Button
	if btn_close == null:
		btn_close = ui.get_node_or_null("InfoPanel/BtnClose") as Button

	# Force labels to wrap inside the panel box (ScrollContainer needs a width min for autowrap).
	for lbl in [info_name, info_owner, info_population, info_terrain, info_factories, info_dev, info_resources, info_core, info_special, info_logistics, info_combat, info_national]:
		if lbl != null:
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = false
	if info_modifiers != null:
		info_modifiers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_info_panel_inner()


func _setup_inspector_extras() -> void:
	if btn_national_spirits and not btn_national_spirits.pressed.is_connected(_on_open_national_spirits_pressed):
		btn_national_spirits.pressed.connect(_on_open_national_spirits_pressed)
	if info_modifiers == null:
		info_modifiers = get_node_or_null("UI/InfoPanel/InfoScroll/InfoContentMargin/InfoContent/RichTextModifiers") as RichTextLabel
	if info_national == null:
		info_national = get_node_or_null("UI/InfoPanel/InfoScroll/InfoContentMargin/InfoContent/LabelNationalHeader") as Label
	if info_modifiers:
		info_modifiers.bbcode_enabled = true
		# Grow height with content; width is constrained by _layout_info_panel_inner so long
		# national-spirit / coarse-territory lines wrap instead of spilling past the box.
		info_modifiers.fit_content = true
		info_modifiers.scroll_active = false
		info_modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_modifiers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if btn_national_spirits == null:
		btn_national_spirits = get_node_or_null("UI/InfoPanel/BtnNationalSpirits") as Button
		if btn_national_spirits and not btn_national_spirits.pressed.is_connected(_on_open_national_spirits_pressed):
			btn_national_spirits.pressed.connect(_on_open_national_spirits_pressed)
	_layout_info_panel_inner()
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


var _wheel_zoom_terrain_at_msec: int = 0
var _pending_terrain_zoom_refresh: bool = false
const WHEEL_TERRAIN_REFRESH_MS := 180


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Wheel zoom even when GUI has focus on non-scroll chrome (legend can steal wheel —
		# if mouse is over map / empty space, always zoom). ScrollContainers still get wheel
		# when hovered via normal GUI order; we only force-zoom when not over a ScrollContainer.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _wheel_should_zoom_map():
				var factor := (1.0 + zoom_speed * 1.35) if event.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 - zoom_speed * 1.35)
				_zoom_toward_mouse(factor)
				# NEVER call full _refresh_terrain_zoom_aware() per notch — that looped all
				# 2665 province fills every wheel tick and made scroll feel broken/glitchy.
				_schedule_light_terrain_zoom_refresh()
				get_viewport().set_input_as_handled()


func _schedule_light_terrain_zoom_refresh() -> void:
	_pending_terrain_zoom_refresh = true
	var now := Time.get_ticks_msec()
	if now - _wheel_zoom_terrain_at_msec < WHEEL_TERRAIN_REFRESH_MS:
		return
	_wheel_zoom_terrain_at_msec = now
	_pending_terrain_zoom_refresh = false
	_refresh_terrain_zoom_light()


func _refresh_terrain_zoom_light() -> void:
	## Cheap zoom response: LOD alphas only — no per-province fill rebuild.
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	var z := 1.0
	if cam:
		z = maxf(cam.zoom.x, cam.zoom.y)
	elif container:
		z = absf(container.scale.x)
	if terrain_layer_stack and terrain_layer_stack.has_method("apply_zoom_level"):
		terrain_layer_stack.call("apply_zoom_level", z)
	# Pass 7: resync unit counter scales + LOD visibility without full icon rebuild.
	_sync_unit_counter_scales(z)
	_sync_unit_counter_visibility(z)
	# Bucketed fill repaint only when zoom crossed a band (existing system).
	if fill_zoom_bucket_size > 0.0:
		var bucket := int(floor(z / fill_zoom_bucket_size))
		if bucket != _fill_color_zoom_bucket:
			_fill_color_zoom_bucket = bucket
			_fill_zoom_at_last_paint = z
			# Deferred so this wheel event returns immediately.
			call_deferred("_refresh_province_fill_colors")


func _wheel_should_zoom_map() -> bool:
	var vp := get_viewport()
	if vp == null:
		return true
	var hov: Control = vp.gui_get_hovered_control()
	if hov == null:
		return true
	var n: Node = hov
	while n != null:
		var nn := str(n.name)
		# Don't steal wheel from tech list / info scroll / menus.
		if n is ScrollContainer or n is TextEdit or n is CodeEdit:
			return false
		if nn in ["TechnologyScreen", "InfoPanel", "MainMenu", "DebugOverlay", "OrderCommandPanel"]:
			return false
		if nn.ends_with("Screen") or nn.ends_with("Popup"):
			return false
		if nn == "TopInfoBar":
			return false
		n = n.get_parent()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Esc: dismiss stuck overlays (legend / tech / info) so playtest is never trapped.
		if event.keycode == KEY_ESCAPE:
			var ui_esc := get_node_or_null("UI") as CanvasLayer
			if ui_esc != null:
				var unit_pop := ui_esc.get_node_or_null("UnitDetailPopup")
				if unit_pop != null:
					unit_pop.queue_free()
					get_viewport().set_input_as_handled()
					return
			# Clear selected map unit before other dismissals.
			if not selected_formation_id.is_empty():
				selected_formation_id = ""
				_refresh_selected_unit_chip()
				_show_inspector_toast("Unit selection cleared", 2.0)
				get_viewport().set_input_as_handled()
				return
			if _dismiss_map_overlays_esc():
				get_viewport().set_input_as_handled()
				return
		# Stack cycle on selected pin province: [ previous · ] next (unit card also has buttons).
		if (
			(event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_BRACKETRIGHT)
			and not selected_formation_id.is_empty()
			and not event.ctrl_pressed
			and not event.alt_pressed
		):
			var stack_dir := -1 if event.keycode == KEY_BRACKETLEFT else 1
			if _cycle_selected_stack_unit(stack_dir):
				get_viewport().set_input_as_handled()
				return
		if event.keycode == KEY_L:
			_toggle_supply_overlay()
			if supply_mode:
				_show_map_layer_toast("Supply legend ON — Close button, L, or Esc to hide")
			else:
				_show_map_layer_toast("Supply legend OFF")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_O and not event.ctrl_pressed and not event.alt_pressed:
			toggle_occupation_overlay()
			var st: Dictionary = get_occupation_overlay_stats()
			_show_map_layer_toast("Occupation overlay %s · draws %s · icons %s" % ["ON" if show_occupation_overlay else "OFF", st.get("draw_n", 0), st.get("icon_n", 0)])
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_J and not event.ctrl_pressed:
			var onj: bool = toggle_battle_indicator_overlay()
			_show_map_layer_toast("Battle indicators %s" % ("ON" if onj else "OFF"))
			get_viewport().set_input_as_handled()
			return
		# Shift+U — unit counters. Must beat plain U (supply flow) the same way Shift+I beats I.
		if event.keycode == KEY_U and event.shift_pressed and not event.ctrl_pressed and not event.alt_pressed:
			toggle_unit_counters()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_U and not event.ctrl_pressed and not event.shift_pressed:
			var onu: bool = toggle_strategic_flow_overlay()
			_show_map_layer_toast("Supply/sealane flow %s" % ("ON" if onu else "OFF"))
			get_viewport().set_input_as_handled()
			return
		# I: EquipmentFlow glyphs · Shift+I: first-session WarLoop (flow + fronts + assault brief)
		if event.keycode == KEY_I and not event.ctrl_pressed and not event.alt_pressed:
			if event.shift_pressed:
				show_first_session_war_path()
				get_viewport().set_input_as_handled()
				return
			var ong: bool = toggle_equipment_flow_glyphs()
			var gq: Dictionary = get_equipment_flow_glyph_query()
			_show_map_layer_toast(
				"Equipment flow glyphs %s · tier %s · max %s · Shift+I=WarLoop" % [
					"ON" if ong else "OFF",
					str(gq.get("tier_name", "?")),
					str((gq.get("lod_policy", {}) as Dictionary).get("max_glyphs", "?")),
				]
			)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_K and not event.ctrl_pressed:
			var onk: bool = toggle_domain_ops_overlay()
			_show_map_layer_toast("Naval/air ops overlay %s" % ("ON" if onk else "OFF"))
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
		# M4: G — highlight supply corridor capital/hub → currently selected province
		if event.keycode == KEY_G and not event.ctrl_pressed and not event.alt_pressed:
			highlight_corridor_capital_to_selected()
			get_viewport().set_input_as_handled()
			return
		# First-session help toast (? or Shift+/)
		if event.keycode == KEY_SLASH and event.shift_pressed:
			_toast_first_session_help()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_QUESTION:
			_toast_first_session_help()
			get_viewport().set_input_as_handled()
			return
		# Phase C: B — live fronts. Toast + cycle + camera ONLY (never outline/scan on key frame).
		if event.keycode == KEY_B and not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed:
			_run_live_border_fronts_instant()
			get_viewport().set_input_as_handled()
			return
		# Home: re-center Europe · End: Asia focus · Shift+Home: full world fit
		if event.keycode == KEY_HOME:
			ensure_world_navigation_ready()
			if event.shift_pressed:
				fit_camera_to_full_world()
			else:
				center_europe_in_world_view()
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Map: Europe · WASD/edge/MMB pan · wheel zoom · Shift+Home=world")
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_END:
			ensure_world_navigation_ready()
			_focus_asia_view()
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
		# Pass 10: F8 weather ground-state mapmode (dry/mud/snow/storm fills).
		if event.keycode == KEY_F8:
			set_map_mode("weather")
		# F9 — resources; Shift+F9 — states; Ctrl+F9 — terrain (modifiers first so plain F9 does not clobber)
		if event.keycode == KEY_F9:
			if event.ctrl_pressed:
				set_map_mode("terrain")
			elif event.shift_pressed:
				set_map_mode("states")
			else:
				set_map_mode("resources")
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
		# Prefer unit/navy/armor icons when the click lands on a counter (open unit detail).
		if _try_open_unit_at_world(world_pos):
			get_viewport().set_input_as_handled()
			return
		var pid := -1
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
			pid = MapManager.get_province_at_world_pos(world_pos, true)
			if MapManager.has_method("resolve_pick_province_id"):
				pid = MapManager.resolve_pick_province_id(pid)
		if pid < 0 or not provinces.has(pid):
			# Coarse world territory fallback: when no detailed province (e.g. panned to Africa/Aus/E Asia on stitched world grand), hit large strategic region for "click to get into".
			# Gives grand strategy world map the feel that every area has a clickable territory/region, even if detailed provs are Europe-focused for current scenario.
			var ctid := _hit_coarse_territory(world_pos)
			if ctid != 0:
				_show_coarse_territory_info(ctid, true)
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
			# Unit move: selected pin + click friendly province.
			if not selected_formation_id.is_empty() and not event.ctrl_pressed:
				if _try_move_selected_unit_to_province(resolved_province):
					_select_province(resolved_province, resolved_node)
					get_viewport().set_input_as_handled()
					return
			if _try_set_attack_staging(resolved_province):
				pass  # still open inspector below
			if supply_mode and _handle_supply_province_click(resolved_province):
				_select_province(resolved_province, resolved_node)
				get_viewport().set_input_as_handled()
				return
			# Master-off: chips hidden — one-shot discoverability for unit pick.
			if not _unit_pick_strategic_hint_shown and not _unit_counters_want_visible():
				_unit_pick_strategic_hint_shown = true
				_show_inspector_toast("Click a unit chip to command (Shift+U toggles counters).", 3.5)
			# Select first (outline immediately); center + left inspector (avoid covering selection).
			_select_province(resolved_province, resolved_node)
			_center_camera_on_province(resolved_province.id, "soft")
			show_info_panel(resolved_province)
			get_viewport().set_input_as_handled()
			return

	if use_spatial_picking and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if typeof(DebugOverlay) != TYPE_NIL and DebugOverlay.is_map_debug_tools_active():
			var world_pos_r := _screen_to_world(get_viewport().get_mouse_position())
			var pid_r := -1
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
				pid_r = MapManager.get_province_at_world_pos(world_pos_r, true)
				if MapManager.has_method("resolve_pick_province_id"):
					pid_r = MapManager.resolve_pick_province_id(pid_r)
			if pid_r >= 0:
				debug_cycle_province_owner(pid_r)
				get_viewport().set_input_as_handled()
				return

	# Middle or right mouse drag start (right-drag for laptop trackpads / no middle button)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Do not start map pan under Command Center / modal overlays.
				if MapViewInput.modal_blocks_map_nav(get_viewport()):
					_is_middle_dragging = false
				else:
					_is_middle_dragging = true
					_middle_drag_start = get_viewport().get_mouse_position()
					_last_mouse_pos = _middle_drag_start
			else:
				_is_middle_dragging = false


func _process(delta: float) -> void:
	if _perf != null and _perf.enabled:
		_perf_frame_start_usec = Time.get_ticks_usec()
		_perf.begin("process_total")
	_expire_map_time_pulse_if_needed()

	# When sim is paused, skip heavy LOD/fill/theater work — pan/zoom/UI stay responsive for playtest.
	var sim_paused := false
	if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("is_paused"):
		sim_paused = bool(TimeManager.is_paused())
	elif Engine.time_scale < 0.01:
		sim_paused = true

	# Camera always — pan/zoom/edge must work while paused (looking at map is the playtest path).
	_handle_camera_input(delta)
	# GIS dual-map watchdog: re-lock canvas identity + equirect underlay every ~0.5s while playing.
	if _is_gis_board_active() and Engine.get_process_frames() % 30 == 0:
		_reassert_gis_single_canvas()
	# Pass 8: animate stack badges even while paused (map readability).
	_pulse_stack_badges(delta)
	# Pass 52: pin-focus pulse rings (works while paused).
	_update_pin_focus_pulse(delta)

	# Selection/hover outline pulse always (including paused playtest) so shape stays readable.
	_outline_pulse_phase += delta * 4.5
	_update_outline_pulse()
	if use_spatial_picking:
		_update_spatial_hover()
	if not sim_paused:
		# Throttle fill/LOD — world_full (2k+ polys) needs coarse cadence.
		var detail_every := 6 if province_nodes.size() >= 800 else 2
		if Engine.get_process_frames() % detail_every == 0:
			_refresh_province_detail_visibility()
		if hover_tooltip and hover_tooltip.visible and _hover_province != null and hover_name_follow_mouse:
			_refresh_hover_tooltip(_hover_province)
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
	else:
		# Paused: light hover only (camera already handled above every frame).
		if use_spatial_picking and Engine.get_process_frames() % 4 == 0:
			_update_spatial_hover()
	if _perf != null and _perf.enabled:
		_perf.end("process_total")
		var frame_ms := float(Time.get_ticks_usec() - _perf_frame_start_usec) / 1000.0
		_perf.mark_frame(frame_ms)


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


## Top HUD height (TopInfoBar + map mode toolbar). Edge pan-north starts just *below* this strip
## so the bar never thrash-pans, but players can still scroll the map upward.
func _map_nav_top_clearance() -> float:
	var top_clearance := UI_TOP_BAR_CLEARANCE
	if get_tree():
		var tib := TopInfoBar.find_in_tree(get_tree())
		if tib != null and tib.has_method("get_bar_height"):
			top_clearance = maxf(top_clearance, float(tib.call("get_bar_height")) + 4.0)
	var toolbar_h := UI_MAP_TOOLBAR_HEIGHT
	if _map_mode_toolbar != null and _map_mode_toolbar.has_method("get_panel_height"):
		toolbar_h = float(_map_mode_toolbar.call("get_panel_height"))
	return top_clearance + toolbar_h + 4.0


func _handle_camera_input(delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	# Command Center / modal screens: freeze all map pan (WASD, edge, drag).
	# Edge-only block was insufficient — WASD still moved the map under MainMenu.
	if MapViewInput.modal_blocks_map_nav(get_viewport()):
		_is_middle_dragging = false
		return

	var nav_delta := MapViewInput.motion_delta(delta)
	var move_dir := Vector2.ZERO
	var moved := false

	# WASD / Arrow keys (simulation pause must not freeze map navigation)
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    move_dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  move_dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  move_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move_dir.x += 1

	# Edge scrolling: left/right/bottom + north band just below top HUD (not over the bar itself).
	if not MapViewInput.edge_pan_blocked_by_gui(get_viewport()):
		var mouse_pos := get_viewport().get_mouse_position()
		var viewport_size := get_viewport().get_visible_rect().size
		if mouse_pos.x < edge_margin:
			move_dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_margin:
			move_dir.x += 1
		if mouse_pos.y > viewport_size.y - edge_margin:
			move_dir.y += 1
		# Pan north via a strip *under* the HUD (not raw y=0 — bar is full-width PASS chrome
		# and re-enabling true top-edge pan thrashed world_full when hovering 1x/Prod).
		var top_safe := _map_nav_top_clearance()
		if mouse_pos.y >= top_safe and mouse_pos.y < top_safe + edge_margin:
			move_dir.y -= 1

	# Middle / right mouse drag (pixel-based — works while paused). Drag up → camera north.
	if _is_middle_dragging:
		var current_mouse := get_viewport().get_mouse_position()
		var drag_delta := current_mouse - _last_mouse_pos
		if drag_delta.length_squared() > 0.01:
			cam.global_position -= drag_delta * middle_mouse_pan_speed / cam.zoom.x
			moved = true
		_last_mouse_pos = current_mouse

	if move_dir != Vector2.ZERO:
		move_dir = move_dir.normalized()
		# edge_scroll_speed for edge/WASD feel; pan_speed kept as alias baseline
		var speed := maxf(pan_speed, edge_scroll_speed)
		cam.global_position += move_dir * speed * nav_delta / cam.zoom.x
		moved = true

	# Flush debounced terrain zoom after wheel burst settles.
	if _pending_terrain_zoom_refresh and Time.get_ticks_msec() - _wheel_zoom_terrain_at_msec >= WHEEL_TERRAIN_REFRESH_MS:
		_wheel_zoom_terrain_at_msec = Time.get_ticks_msec()
		_pending_terrain_zoom_refresh = false
		_refresh_terrain_zoom_light()

	# Only clamp when camera moved — wrapping/clamp every idle frame was thrashing redraws.
	if moved:
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
		# Pass 46: restore persisted heat prefs after minimap exists.
		call_deferred("apply_stored_pack_risk_heat_prefs")

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
		var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
		var pw := 520.0
		# Left dock: stays off the selected province (camera also offsets for free map area).
		var ph := minf(580.0, maxf(360.0, vp.y - chrome_top - 48.0))
		var cx := 12.0
		var cy := chrome_top + 8.0
		ip.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ip.offset_left = cx
		ip.offset_top = cy
		ip.offset_right = cx + pw
		ip.offset_bottom = cy + ph
		ip.custom_minimum_size = Vector2(pw, ph)
		ip.z_index = 40
	_layout_info_panel_inner()


## Keep InfoPanel text fully inside the cyan box.
## Critical: never let content min-width exceed the panel; always clip; pin scroll size in pixels
## (anchor-only layout was letting content grow wider than the frame — scrollbar far outside).
func _layout_info_panel_inner() -> void:
	if info_panel == null or not (info_panel is Control):
		return
	var ip := info_panel as Control
	ip.clip_contents = true
	ip.mouse_filter = Control.MOUSE_FILTER_STOP
	RetrowaveTheme.style_info_panel_flat(ip)

	var panel_w := absf(ip.offset_right - ip.offset_left)
	var panel_h := absf(ip.offset_bottom - ip.offset_top)
	if panel_w < 80.0:
		panel_w = maxf(ip.size.x, 560.0)
	if panel_h < 80.0:
		panel_h = maxf(ip.size.y, 400.0)
	# Lock panel pixel size so children cannot inflate it.
	ip.custom_minimum_size = Vector2(panel_w, panel_h)
	ip.size = Vector2(panel_w, panel_h)

	const PAD_L := 18.0
	const PAD_R := 16.0
	const HEADER_H := 40.0
	const FOOTER_PAD := 12.0
	const INNER_L := 12.0
	const INNER_R := 12.0
	const SCROLLBAR_W := 14.0

	if btn_national_spirits != null:
		btn_national_spirits.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		btn_national_spirits.position = Vector2(PAD_L, 8.0)
		btn_national_spirits.custom_minimum_size = Vector2(150, 26)
		btn_national_spirits.size = Vector2(150, 26)
		btn_national_spirits.mouse_filter = Control.MOUSE_FILTER_STOP
	if btn_close != null:
		btn_close.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		var close_w := 70.0
		btn_close.position = Vector2(panel_w - PAD_R - close_w, 8.0)
		btn_close.custom_minimum_size = Vector2(close_w, 26)
		btn_close.size = Vector2(close_w, 26)
		btn_close.mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_province_id_badge()
	if _province_id_badge != null and btn_close != null:
		_province_id_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		var id_w := 96.0
		_province_id_badge.position = Vector2(btn_close.position.x - id_w - 8.0, 10.0)
		_province_id_badge.custom_minimum_size = Vector2(id_w, 22)
		_province_id_badge.size = Vector2(id_w, 22)

	# Explicit pixel box for scroll — do NOT use full-rect anchors (content growth was expanding it).
	var scroll_x := PAD_L
	var scroll_y := HEADER_H
	var scroll_w := maxf(panel_w - PAD_L - PAD_R, 120.0)
	var scroll_h := maxf(panel_h - HEADER_H - FOOTER_PAD, 80.0)
	var text_w := maxf(scroll_w - INNER_L - INNER_R - SCROLLBAR_W, 100.0)

	var scroll := ip.get_node_or_null("InfoScroll") as ScrollContainer
	if scroll != null:
		scroll.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		scroll.anchor_left = 0.0
		scroll.anchor_top = 0.0
		scroll.anchor_right = 0.0
		scroll.anchor_bottom = 0.0
		scroll.position = Vector2(scroll_x, scroll_y)
		scroll.size = Vector2(scroll_w, scroll_h)
		scroll.custom_minimum_size = Vector2(scroll_w, scroll_h)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.clip_contents = true
		scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		scroll.scroll_horizontal = 0

	var content_margin := ip.get_node_or_null("InfoScroll/InfoContentMargin") as MarginContainer
	if content_margin != null:
		content_margin.add_theme_constant_override("margin_left", int(INNER_L))
		content_margin.add_theme_constant_override("margin_right", int(INNER_R))
		content_margin.add_theme_constant_override("margin_top", 4)
		content_margin.add_theme_constant_override("margin_bottom", 6)
		# Width must equal scroll client (minus nothing — margins are inside this width).
		var col_w := maxf(scroll_w - SCROLLBAR_W, 100.0)
		content_margin.custom_minimum_size = Vector2(col_w, 0)
		content_margin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		content_margin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var content := ip.get_node_or_null("InfoScroll/InfoContentMargin/InfoContent") as VBoxContainer
	if content == null:
		content = ip.get_node_or_null("InfoScroll/InfoContent") as VBoxContainer
	if content != null:
		content.custom_minimum_size = Vector2(text_w, 0)
		content.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		content.add_theme_constant_override("separation", 6)

	for lbl in [
		info_name, info_owner, info_population, info_terrain, info_factories, info_dev,
		info_resources, info_core, info_special, info_logistics, info_combat, info_national,
	]:
		_apply_info_label_wrap(lbl, text_w)

	if info_modifiers != null:
		_apply_info_richtext_wrap(info_modifiers, text_w)

	if _label_invest_status != null:
		_apply_info_label_wrap(_label_invest_status, text_w)
	if _label_invest_modifiers != null:
		_apply_info_label_wrap(_label_invest_modifiers, text_w)
	if _progress_invest != null and is_instance_valid(_progress_invest):
		_progress_invest.custom_minimum_size = Vector2(text_w, 14)
		_progress_invest.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	_apply_info_content_wrap_vertical_only(content, text_w)

	if scroll != null:
		scroll.scroll_horizontal = 0


func _apply_info_label_wrap(lbl: Label, text_w: float) -> void:
	if lbl == null:
		return
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lbl.custom_minimum_size = Vector2(text_w, 0)
	lbl.clip_text = false
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _apply_info_richtext_wrap(rtl: RichTextLabel, text_w: float) -> void:
	if rtl == null:
		return
	# fit_content height-only: width must stay locked or the whole panel content goes ultra-wide.
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.clip_contents = true
	rtl.custom_minimum_size = Vector2(text_w, 0)
	# Godot 4: set width explicitly so autowrap engages before fit_content measures height.
	rtl.size = Vector2(text_w, maxf(rtl.size.y, 8.0))


func _apply_info_content_wrap_vertical_only(node: Node, text_w: float) -> void:
	if node == null:
		return
	if node is HBoxContainer:
		for c in node.get_children():
			if c is Label:
				var hl := c as Label
				hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				hl.clip_text = false
				hl.custom_minimum_size = Vector2(0, 0)
				hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			elif c is Control:
				var cc := c as Control
				if cc.custom_minimum_size.x > text_w:
					cc.custom_minimum_size.x = 0.0
				_apply_info_content_wrap_vertical_only(c, text_w)
		return
	if node is Label:
		_apply_info_label_wrap(node as Label, text_w)
	elif node is RichTextLabel:
		_apply_info_richtext_wrap(node as RichTextLabel, text_w)
	else:
		if node is Control:
			var ctrl := node as Control
			if ctrl != null and ctrl.custom_minimum_size.x > text_w + 4.0:
				ctrl.custom_minimum_size.x = text_w
		for c in node.get_children():
			_apply_info_content_wrap_vertical_only(c, text_w)


func _wire_info_panel_drag() -> void:
	if info_panel == null or not (info_panel is Control):
		return
	if info_panel.has_meta("drag_wired"):
		return
	info_panel.set_meta("drag_wired", true)
	info_panel.gui_input.connect(_on_info_panel_gui_input)


func _bring_info_panel_to_front() -> void:
	if info_panel == null or not (info_panel is Control):
		return
	var ip := info_panel as Control
	ip.z_index = 60
	var p := ip.get_parent()
	if p != null:
		p.move_child(ip, p.get_child_count() - 1)


func _on_info_panel_gui_input(event: InputEvent) -> void:
	if info_panel == null or not (info_panel is Control):
		return
	var ip := info_panel as Control
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_bring_info_panel_to_front()
				# Drag from title strip; still allow click-to-raise anywhere on panel.
				if mb.position.y <= 36.0:
					_info_panel_dragging = true
					_info_panel_drag_offset = mb.position
					ip.set_meta("user_moved", true)
					ip.accept_event()
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
		ip.accept_event()


func select_province_by_id(province_id: int) -> bool:
	return focus_province_by_id(province_id)


## Simple map mode toggle helper (demo for task): forces re-tint emphasizing strain/vitality/development.
func force_map_tint_demo(mode: String = "") -> void:
	set_map_mode(mode if mode in ["vitality", "strain", "development", "political", "supply", "munitions", "loyalty", "infra", "naval", "weather", "resources", "states", "terrain", "chokepoints", "occupation", "resistance", "compliance"] else "")


## Sets basic mapmode-style visual layer/tint using existing characterize / supply layer / dev lighten code.
## Supports: "political" (default clean), "strain" (welfare), "vitality" (settlement), "development" (dev boost), "supply" (L overlay),
## "naval"/"chokepoints" (data-driven strait highlight from MapManager.get_naval_chokepoint_provinces).
## Clear labels + toast guidance provided by callers (DebugOverlay). Emits refresh for live map updates.
## Pass 18: highlight a supply/trade route by province path (from minimap double-click).
func highlight_supply_route_path(province_path: Array, seconds: float = 4.5) -> void:
	if province_path.is_empty():
		return
	if not supply_mode:
		_toggle_supply_overlay()
	_setup_supply_layer()
	if supply_map_layer == null:
		return
	var pts: PackedVector2Array = PackedVector2Array()
	for pid_v in province_path:
		var pid := int(pid_v)
		if province_centroids.has(pid):
			pts.append(province_centroids[pid] as Vector2)
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			var c: Vector2 = MapManager.get_province_centroid(pid)
			if c != Vector2.ZERO:
				pts.append(c)
	if pts.size() < 2:
		return
	if supply_map_layer.has_method("highlight_route_points"):
		supply_map_layer.call("highlight_route_points", pts, seconds)
	# Bright-yellow road edges along this corridor (infra overlay); mute everything else.
	var ol := get_overlay_layer("InfrastructureOverlayLayer")
	if ol != null and ol.has_method("set_supply_corridor_path"):
		ol.call("set_supply_corridor_path", province_path)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Route highlight · %d provinces" % province_path.size())


## Phase C: player-facing multi-front / live border assault targets.
## Uses MapManager.collect_live_border_assault_targets — not station IDs.
## Hotkey B · toolbar preset "Fronts". Returns {ok, count, best_province_id, toast, targets}.
## Keep this path light: cache targets, toast + select only (no full inspector rebuild — that hung B @ 3520).
var _live_border_fronts_cycle: int = 0
var _live_border_fronts_cache_tag: String = ""
var _live_border_fronts_cache: Array = []
var _live_border_fronts_cache_msec: int = 0
var _live_border_fronts_busy: bool = false
const _LIVE_BORDER_FRONTS_CACHE_MS: int = 8000

## Instant B path: use precomputed/cached targets only; pan camera; toast. No outline, no scan.
func _run_live_border_fronts_instant() -> void:
	var tag := "GER"
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		var pt := str(LeaderManager.get_player_country_tag()).to_upper()
		if not pt.is_empty():
			tag = pt
	# Ensure cache: first B may build once under budget; then O(1).
	if _live_border_fronts_cache.is_empty() or _live_border_fronts_cache_tag != tag:
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("collect_live_border_assault_targets"):
			_live_border_fronts_cache = MapManager.collect_live_border_assault_targets(tag, 8)
			_live_border_fronts_cache_tag = tag
			_live_border_fronts_cache_msec = Time.get_ticks_msec()
	var targets: Array = _live_border_fronts_cache
	if targets.is_empty():
		var empty_toast := "Fronts · %s · no enemy border targets" % tag
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(empty_toast)
		return
	_live_border_fronts_cycle = _live_border_fronts_cycle % targets.size()
	var idx := _live_border_fronts_cycle
	_live_border_fronts_cycle = (_live_border_fronts_cycle + 1) % targets.size()
	var row: Dictionary = targets[idx] if targets[idx] is Dictionary else {}
	var best_id := int(row.get("province_id", -1))
	var dtag := str(row.get("defender_tag", "?"))
	var nm := str(row.get("name", "#%d" % best_id))
	var toast := "Fronts · %s · %s #%d vs %s (%d/%d · B next)" % [
		tag, nm, best_id, dtag, idx + 1, targets.size()
	]
	# Visible player feedback (DebugOverlay alone is easy to miss).
	if has_method("_show_inspector_toast"):
		_show_inspector_toast(toast, 4.0)
	elif typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(toast, 4.0)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(toast)
	# Camera pan to front + light pink select (no full redraw).
	if best_id > 0 and province_centroids.has(best_id):
		selected_province_id = best_id
		var cam := get_viewport().get_camera_2d() if get_viewport() else null
		if cam != null:
			cam.global_position = province_centroids[best_id] as Vector2
		# Cheap outline only — skip heavy ProvinceInsight dual paths by direct line if available.
		if _select_outline_line != null or has_method("_ensure_select_outline_layer"):
			call_deferred("_focus_fronts_outline_only", best_id)


## Deferred: pink outline without re-entering heavy insight paths mid-key.
func _focus_fronts_outline_only(best_id: int) -> void:
	if best_id <= 0:
		return
	# Minimal map-space outline only (no per-node dual/agent insight).
	var map_pts := _map_space_province_polygon(best_id)
	if map_pts.size() < 3:
		return
	_ensure_select_outline_layer()
	var w := 3.5
	var sel_col := Color(1.0, 0.35, 0.85, 0.95)
	var sel_glow := Color(1.0, 0.45, 0.9, 0.35)
	if _select_outline_glow != null:
		_select_outline_glow.points = map_pts
		_select_outline_glow.default_color = sel_glow
		_select_outline_glow.width = w * 1.8
		_select_outline_glow.visible = true
	if _select_outline_line != null:
		_select_outline_line.points = map_pts
		_select_outline_line.default_color = sel_col
		_select_outline_line.width = w
		_select_outline_line.visible = true


func show_live_border_fronts(country_tag: String = "", max_count: int = 8) -> Dictionary:
	var result := {
		"ok": false,
		"count": 0,
		"best_province_id": -1,
		"toast": "",
		"targets": [],
		"empty": true,
		"defender_tag": "",
	}
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		tag = str(LeaderManager.get_player_country_tag()).to_upper()
	if tag.is_empty():
		tag = "GER"
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("collect_live_border_assault_targets"):
		result["toast"] = "Fronts unavailable"
		return result
	var targets: Array = MapManager.collect_live_border_assault_targets(tag, maxi(max_count, 4))
	_live_border_fronts_cache = targets
	_live_border_fronts_cache_tag = tag
	_live_border_fronts_cache_msec = Time.get_ticks_msec()
	result["targets"] = targets
	result["count"] = targets.size()
	if targets.is_empty():
		result["ok"] = true
		result["empty"] = true
		result["toast"] = "Fronts · %s · no enemy border targets" % tag
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(str(result["toast"]))
		return result
	_live_border_fronts_cycle = _live_border_fronts_cycle % targets.size()
	var idx := _live_border_fronts_cycle
	_live_border_fronts_cycle = (_live_border_fronts_cycle + 1) % maxi(1, targets.size())
	var row: Dictionary = targets[idx] if targets[idx] is Dictionary else {}
	var best_id := int(row.get("province_id", -1))
	var dtag := str(row.get("defender_tag", "?"))
	var nm := str(row.get("name", "#%d" % best_id))
	result["best_province_id"] = best_id
	result["defender_tag"] = dtag
	result["ok"] = true
	result["empty"] = false
	result["toast"] = "Fronts · %s · %s #%d vs %s (%d/%d · B next)" % [
		tag, nm, best_id, dtag, idx + 1, targets.size()
	]
	if best_id > 0 and province_centroids.has(best_id):
		selected_province_id = best_id
		var cam2 := get_viewport().get_camera_2d() if get_viewport() else null
		if cam2 != null:
			cam2.global_position = province_centroids[best_id] as Vector2
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(str(result["toast"]))
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(str(result["toast"]), 3.5)
	return result


## M4: capital/hub → front corridor polyline. Prefer SupplyManager multimodal (land only with
## transit rights; else sea), then MapManager land BFS with same rights filter.
## Returns {ok, path, source, target, hops, method, via_sea}.
func highlight_supply_corridor(from_id: int, to_id: int, seconds: float = 6.5, owner_tag: String = "") -> Dictionary:
	var result := {
		"ok": false, "path": [], "source": from_id, "target": to_id, "hops": 0, "method": "",
		"via_sea": false,
	}
	if from_id <= 0 or to_id <= 0:
		return result
	var path: Array = []
	var method := ""
	var via_sea := false
	# 1) Full multimodal plan when SupplyManager has network (respects _is_friendly transit rights).
	var sm := _supply_manager()
	if sm != null and sm.has_method("preview_player_route"):
		if sm.has_method("begin_player_reroute"):
			sm.begin_player_reroute(from_id, to_id)
		var plan: SupplyRoutePlan = sm.preview_player_route()
		if plan != null and plan.path_length() >= 2:
			path = []
			for pid_v in plan.province_path:
				path.append(int(pid_v))
			method = "supply_plan"
			if "routing_mode" in plan and str(plan.routing_mode) == "sea":
				via_sea = true
			elif "uses_port" in plan and bool(plan.uses_port):
				via_sea = true
	# 2) Infra-weighted land path (own + allied/access only — not neutral)
	if path.size() < 2 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("find_infra_weighted_land_path"):
		var wpath: Array = MapManager.find_infra_weighted_land_path(from_id, to_id, owner_tag)
		if wpath.size() >= 2:
			path = wpath
			method = "infra_weighted"
	# 3) Plain land BFS with transit filter
	if path.size() < 2 and typeof(MapManager) != TYPE_NIL and MapManager.has_method("find_land_path"):
		var bpath: Array = MapManager.find_land_path(from_id, to_id, owner_tag)
		if bpath.size() >= 2:
			path = bpath
			method = "land_bfs"
	if path.size() < 2:
		var no_msg := "Corridor: no land path %d → %d (need alliance/access, or sea route)" % [from_id, to_id]
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(no_msg)
		_show_inspector_toast(no_msg, 4.0, true)
		return result
	highlight_supply_route_path(path, seconds)
	result["ok"] = true
	result["path"] = path
	result["hops"] = maxi(0, path.size() - 1)
	result["method"] = method
	result["via_sea"] = via_sea
	# Soft fuel/network read along corridor (mirrors map_supply_hub_brief_product fuel_score).
	var fuel_score := _corridor_path_fuel_score(path, from_id)
	result["fuel_score"] = fuel_score
	var from_name := _province_display_name(from_id)
	var to_name := _province_display_name(to_id)
	var sea_note := " · SEA (no land transit)" if via_sea else ""
	var toast := "Supply · %s → %s · %d hops · %s%s" % [from_name, to_name, result["hops"], method, sea_note]
	if fuel_score >= 0.0:
		toast = "Supply · %s → %s · %d hops · fuel %.2f · %s%s" % [
			from_name, to_name, result["hops"], fuel_score, method, sea_note
		]
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(toast)
	_show_inspector_toast(toast, 4.5)
	return result


## M4: from capital (or best key hub) of selected province owner → selected front province.
func highlight_corridor_capital_to_selected() -> Dictionary:
	var target := selected_province_id
	if target < 0 and typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_selected_province_id"):
		target = int(SupplyManager.get_selected_province_id())
	if target < 0:
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Corridor: select a front province first (G)")
		return {"ok": false, "error": "no_selection"}
	var tag := ""
	if provinces.has(target):
		var p: Province = provinces[target] as Province
		if p != null:
			tag = str(p.owner_tag)
	var source := _resolve_corridor_source_for_tag(tag, target)
	return highlight_supply_corridor(source, target, 7.0, tag)


func _province_display_name(pid: int) -> String:
	if provinces.has(pid):
		var p: Province = provinces[pid] as Province
		if p != null and not str(p.name).is_empty():
			return str(p.name)
	return "#%d" % pid


## Soft corridor fuel 0–1 from oil/fuel/rubber + hub factories (pure product parity).
func _corridor_path_fuel_score(path: Array, hub_id: int) -> float:
	if path.is_empty():
		return -1.0
	var path_fuel := 0.0
	for pid_v in path:
		var pid := int(pid_v)
		if not provinces.has(pid):
			continue
		var p: Province = provinces[pid] as Province
		if p == null:
			continue
		var res: Variant = p.get("resources") if "resources" in p else null
		if res is Dictionary:
			var rd: Dictionary = res as Dictionary
			path_fuel += float(rd.get("oil", 0)) + float(rd.get("fuel", 0)) + float(rd.get("rubber", 0))
		elif res is Object and res != null:
			for k in ["oil", "fuel", "rubber"]:
				if k in res:
					path_fuel += float(res.get(k))
	var n: float = maxf(1.0, float(path.size()))
	var path_term: float = clampf((path_fuel / n) / 8.0, 0.0, 1.0)
	var depot := 0.0
	if provinces.has(hub_id):
		var hub: Province = provinces[hub_id] as Province
		if hub != null:
			if "factories" in hub:
				depot += float(hub.factories)
			elif "civilian_factories" in hub:
				depot += float(hub.civilian_factories) + float(hub.get("military_factories") if "military_factories" in hub else 0)
			if "infrastructure" in hub:
				depot += 0.5 * float(hub.infrastructure)
	var depot_term: float = clampf(depot / 15.0, 0.0, 1.0)
	return 0.55 * path_term + 0.45 * depot_term


## Collect capital + key_provinces for tag (scenario / loader). Used for hub-ranked G corridor.
func _collect_supply_hub_candidates_for_tag(owner_tag: String) -> Array:
	var tag := owner_tag.strip_edges().to_upper()
	var out: Array = []
	var seen: Dictionary = {}
	var tree := get_tree()
	if tree == null or tag.is_empty():
		return out
	var loader: Node = tree.root.find_child("ScenarioLoader", true, false)
	if loader == null:
		return out
	var capital := 0
	var keys: Array = []
	if loader.has_method("_get_capital_province_id_for_tag"):
		capital = int(loader.call("_get_capital_province_id_for_tag", tag))
	if "countries" in loader:
		var countries: Variant = loader.get("countries")
		if countries is Dictionary and (countries as Dictionary).has(tag):
			var c: Variant = (countries as Dictionary)[tag]
			if c is Dictionary:
				if capital <= 0:
					capital = int((c as Dictionary).get("capital_province_id", 0))
				var kp: Variant = (c as Dictionary).get("key_provinces", [])
				if kp is Array:
					keys = kp as Array
			elif c != null:
				if capital <= 0 and "capital_province_id" in c:
					capital = int(c.capital_province_id)
				if "key_provinces" in c and c.key_provinces is Array:
					keys = c.key_provinces as Array
	if capital > 0:
		seen[capital] = true
		out.append(capital)
	for k in keys:
		var kid := int(k)
		if kid > 0 and not seen.has(kid):
			seen[kid] = true
			out.append(kid)
	return out


## Prefer closest land hub (fewest hops) among capital + key_provinces to front_id.
## Pure mirror of map_supply_hub_brief_product.pick_best_hub hop ranking.
func _pick_best_supply_hub_for_front(owner_tag: String, front_id: int, candidates: Array) -> int:
	if front_id <= 0 or candidates.is_empty():
		return -1
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("find_land_path"):
		return int(candidates[0]) if not candidates.is_empty() else -1
	var tag := owner_tag.strip_edges().to_upper()
	var best_id := -1
	var best_hops := 999999
	for c in candidates:
		var hub := int(c)
		if hub <= 0:
			continue
		if hub == front_id:
			return hub
		var path: Array = MapManager.find_land_path(hub, front_id, tag)
		if path.size() < 1:
			continue
		var hops := maxi(0, path.size() - 1)
		if hops < best_hops:
			best_hops = hops
			best_id = hub
	return best_id


func _resolve_corridor_source_for_tag(owner_tag: String, fallback_id: int = -1) -> int:
	var tag := owner_tag.strip_edges().to_upper()
	# Prefer best capital/key hub toward front (fallback_id is the selected front).
	var candidates: Array = _collect_supply_hub_candidates_for_tag(tag)
	# SupplyManager capital hub as additional candidate
	var sm := _supply_manager()
	if sm != null and sm.has_method("get_capital_hub_id"):
		var hub := int(sm.get_capital_hub_id())
		if hub >= 0 and not candidates.has(hub):
			candidates.insert(0, hub)
	if fallback_id > 0 and not candidates.is_empty():
		var best := _pick_best_supply_hub_for_front(tag, fallback_id, candidates)
		if best > 0:
			return best
	if not candidates.is_empty():
		return int(candidates[0])
	# Scenario capital for tag (legacy single-source path)
	var tree := get_tree()
	if tree != null:
		var loader: Node = tree.root.find_child("ScenarioLoader", true, false)
		if loader != null:
			if loader.has_method("_get_capital_province_id_for_tag") and not tag.is_empty():
				var cap := int(loader.call("_get_capital_province_id_for_tag", tag))
				if cap > 0:
					return cap
			if "countries" in loader and not tag.is_empty():
				var countries: Variant = loader.get("countries")
				if countries is Dictionary and (countries as Dictionary).has(tag):
					var c: Variant = (countries as Dictionary)[tag]
					if c is Dictionary:
						var cid := int((c as Dictionary).get("capital_province_id", 0))
						if cid > 0:
							return cid
					elif c != null and "capital_province_id" in c:
						var cid2 := int(c.capital_province_id)
						if cid2 > 0:
							return cid2
	if fallback_id > 0:
		return fallback_id
	return -1


## Pass 19: multi-route compare — highlight A vs B with distinct colors + toast summary.
func compare_supply_routes(path_a: Array, path_b: Array, meta_a: Dictionary = {}, meta_b: Dictionary = {}) -> void:
	compare_supply_routes_multi([path_a, path_b], [meta_a, meta_b])


## Pass 26/27: A/B, A/B/C, or A/B/C/D multi-route compare.
func compare_supply_routes_multi(paths: Array, metas: Array = []) -> void:
	if paths.size() < 2:
		return
	var path_a: Array = paths[0] as Array if paths[0] is Array else []
	var path_b: Array = paths[1] as Array if paths[1] is Array else []
	if path_a.is_empty() or path_b.is_empty():
		return
	var path_c: Array = []
	var path_d: Array = []
	if paths.size() >= 3 and paths[2] is Array:
		path_c = paths[2] as Array
	if paths.size() >= 4 and paths[3] is Array:
		path_d = paths[3] as Array
	if not supply_mode:
		_toggle_supply_overlay()
	_setup_supply_layer()
	if supply_map_layer == null:
		return
	var pts_a := _province_path_to_points(path_a)
	var pts_b := _province_path_to_points(path_b)
	var pts_c := _province_path_to_points(path_c) if not path_c.is_empty() else PackedVector2Array()
	var pts_d := _province_path_to_points(path_d) if not path_d.is_empty() else PackedVector2Array()
	if not path_d.is_empty() and supply_map_layer.has_method("compare_route_points_abcd"):
		supply_map_layer.call("compare_route_points_abcd", pts_a, pts_b, pts_c, pts_d, 8.0)
	elif not path_c.is_empty() and supply_map_layer.has_method("compare_route_points_abc"):
		supply_map_layer.call("compare_route_points_abc", pts_a, pts_b, pts_c, 7.0)
	elif supply_map_layer.has_method("compare_route_points"):
		supply_map_layer.call("compare_route_points", pts_a, pts_b, 6.0)
	elif supply_map_layer.has_method("highlight_route_points"):
		supply_map_layer.call("highlight_route_points", pts_a, 6.0)
	var meta_a: Dictionary = metas[0] if metas.size() > 0 and metas[0] is Dictionary else {}
	var meta_b: Dictionary = metas[1] if metas.size() > 1 and metas[1] is Dictionary else {}
	var meta_c: Dictionary = metas[2] if metas.size() > 2 and metas[2] is Dictionary else {}
	var meta_d: Dictionary = metas[3] if metas.size() > 3 and metas[3] is Dictionary else {}
	var risk_a := float(meta_a.get("interdiction", 0.0))
	var risk_b := float(meta_b.get("interdiction", 0.0))
	var risk_c := float(meta_c.get("interdiction", 0.0))
	var risk_d := float(meta_d.get("interdiction", 0.0))
	# Live recompute when meta risk missing or zeroed by caller.
	if risk_a <= 0.0:
		var la := estimate_path_interdiction(path_a)
		if la >= 0.0:
			risk_a = la
	if risk_b <= 0.0:
		var lb := estimate_path_interdiction(path_b)
		if lb >= 0.0:
			risk_b = lb
	if not path_c.is_empty() and risk_c <= 0.0:
		var lc := estimate_path_interdiction(path_c)
		if lc >= 0.0:
			risk_c = lc
	if not path_d.is_empty() and risk_d <= 0.0:
		var ld := estimate_path_interdiction(path_d)
		if ld >= 0.0:
			risk_d = ld
	var hops_a := path_a.size()
	var hops_b := path_b.size()
	var hops_c := path_c.size()
	var hops_d := path_d.size()
	var winner := "A"
	var best_risk := risk_a
	var best_hops := hops_a
	if risk_b < best_risk or (is_equal_approx(risk_b, best_risk) and hops_b < best_hops):
		winner = "B"
		best_risk = risk_b
		best_hops = hops_b
	if not path_c.is_empty() and (risk_c < best_risk or (is_equal_approx(risk_c, best_risk) and hops_c < best_hops)):
		winner = "C"
		best_risk = risk_c
		best_hops = hops_c
	if not path_d.is_empty() and (risk_d < best_risk or (is_equal_approx(risk_d, best_risk) and hops_d < best_hops)):
		winner = "D"
	if typeof(DebugOverlay) != TYPE_NIL:
		if not path_d.is_empty():
			DebugOverlay.toast_map_debug(
				"Route pack A/B/C/D · prefer %s · A%.0f B%.0f C%.0f D%.0f" % [
					winner, risk_a * 100.0, risk_b * 100.0, risk_c * 100.0, risk_d * 100.0
				]
			)
		elif path_c.is_empty():
			DebugOverlay.toast_map_debug(
				"Route compare · A %dhops/%.0f%% vs B %dhops/%.0f%% · prefer %s" % [
					hops_a, risk_a * 100.0, hops_b, risk_b * 100.0, winner
				]
			)
		else:
			DebugOverlay.toast_map_debug(
				"Route compare A/B/C · prefer %s · A%.0f%% B%.0f%% C%.0f%%" % [
					winner, risk_a * 100.0, risk_b * 100.0, risk_c * 100.0
				]
			)
	_show_route_compare_card({
		"hops_a": hops_a,
		"hops_b": hops_b,
		"hops_c": hops_c,
		"hops_d": hops_d,
		"risk_a": risk_a,
		"risk_b": risk_b,
		"risk_c": risk_c,
		"risk_d": risk_d,
		"winner": winner,
		"focus_a": int(meta_a.get("focus_pid", -1)),
		"focus_b": int(meta_b.get("focus_pid", -1)),
		"focus_c": int(meta_c.get("focus_pid", -1)),
		"focus_d": int(meta_d.get("focus_pid", -1)),
		"owner_a": str(meta_a.get("owner_tag", "")),
		"owner_b": str(meta_b.get("owner_tag", "")),
		"owner_c": str(meta_c.get("owner_tag", "")),
		"owner_d": str(meta_d.get("owner_tag", "")),
		"path_a": path_a.duplicate(),
		"path_b": path_b.duplicate(),
		"path_c": path_c.duplicate() if not path_c.is_empty() else [],
		"path_d": path_d.duplicate() if not path_d.is_empty() else [],
		"has_c": not path_c.is_empty(),
		"has_d": not path_d.is_empty(),
		"risk_recomputed": bool(meta_a.get("risk_recomputed", false)) or bool(meta_b.get("risk_recomputed", false)),
		"risk_saved_a": float(meta_a.get("risk_saved", risk_a)),
		"risk_saved_b": float(meta_b.get("risk_saved", risk_b)),
		"risk_saved_c": float(meta_c.get("risk_saved", risk_c)),
		"risk_saved_d": float(meta_d.get("risk_saved", risk_d)),
	})


func _province_path_to_points(province_path: Array) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for pid_v in province_path:
		var pid := int(pid_v)
		if province_centroids.has(pid):
			pts.append(province_centroids[pid] as Vector2)
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			var c: Vector2 = MapManager.get_province_centroid(pid)
			if c != Vector2.ZERO:
				pts.append(c)
	return pts


## Pass 19: toggle a secondary tint key on/off (toolbar chips).
func toggle_secondary_tint(key: String) -> void:
	var k := key.strip_edges().to_lower()
	if k not in ["strain", "vitality", "development", "loyalty"]:
		return
	if k in debug_tint_mode_secondaries:
		debug_tint_mode_secondaries.erase(k)
	else:
		debug_tint_mode_secondaries.append(k)
		if not secondary_tint_intensity.has(k):
			secondary_tint_intensity[k] = 1.0
	debug_tint_mode_secondary = str(debug_tint_mode_secondaries[0]) if not debug_tint_mode_secondaries.is_empty() else ""
	_refresh_province_fill_colors(true)


## Pass 20: set secondary tint strength (0.25–2.0). Pass 22 also accepts munitions + links primary memory.
func set_secondary_tint_intensity(key: String, intensity: float) -> void:
	var k := key.strip_edges().to_lower()
	if k not in ["strain", "vitality", "development", "loyalty", "munitions"]:
		return
	var v := clampf(intensity, 0.25, 2.0)
	secondary_tint_intensity[k] = v
	# Pass 22: remember for primary mapmode intensity when this key is the active primary.
	if k in INTENSITY_LINKED_MODES and (k == current_map_mode or k == debug_tint_mode):
		primary_mapmode_intensity[k] = v
	if k != "munitions" and k not in debug_tint_mode_secondaries:
		debug_tint_mode_secondaries.append(k)
	debug_tint_mode_secondary = str(debug_tint_mode_secondaries[0]) if not debug_tint_mode_secondaries.is_empty() else ""
	_refresh_province_fill_colors(true)


func get_secondary_tint_intensity(key: String) -> float:
	var k := key.strip_edges().to_lower()
	return clampf(float(secondary_tint_intensity.get(k, 1.0)), 0.25, 2.0)


## Pass 21: set intensity for all active secondaries (or all known keys if none active).
func set_all_secondary_tint_intensity(intensity: float) -> void:
	var v := clampf(intensity, 0.25, 2.0)
	var keys: Array = debug_tint_mode_secondaries.duplicate() if not debug_tint_mode_secondaries.is_empty() else ["strain", "vitality", "development", "loyalty"]
	for key_v in keys:
		var k := str(key_v).strip_edges().to_lower()
		if k not in ["strain", "vitality", "development", "loyalty", "munitions"]:
			continue
		secondary_tint_intensity[k] = v
	# Always refresh when primary is intensity-linked.
	if not debug_tint_mode_secondaries.is_empty() or current_map_mode in INTENSITY_LINKED_MODES:
		_refresh_province_fill_colors(true)


## Pass 21: soft / med / hard / max intensity presets.
func apply_secondary_intensity_preset(preset: String) -> void:
	var p := preset.strip_edges().to_lower()
	var v := float(SECONDARY_INTENSITY_PRESETS.get(p, 1.0))
	set_all_secondary_tint_intensity(v)
	link_intensity_to_primary_mapmode(p)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Secondary intensity · %s (%.2f)" % [p, v])


## Pass 22: apply intensity preset to current primary mapmode (and remember it).
func link_intensity_to_primary_mapmode(preset_or_value: Variant = "med") -> void:
	var v := 1.0
	if preset_or_value is String:
		var p := str(preset_or_value).strip_edges().to_lower()
		if SECONDARY_INTENSITY_PRESETS.has(p):
			v = float(SECONDARY_INTENSITY_PRESETS[p])
		elif p.is_valid_float():
			v = float(p)
	else:
		v = float(preset_or_value)
	v = clampf(v, 0.25, 2.0)
	var pm := current_map_mode.strip_edges().to_lower()
	if pm in INTENSITY_LINKED_MODES:
		primary_mapmode_intensity[pm] = v
		secondary_tint_intensity[pm] = v
		_refresh_province_fill_colors(true)
	elif debug_tint_mode in INTENSITY_LINKED_MODES:
		var dt := str(debug_tint_mode)
		primary_mapmode_intensity[dt] = v
		secondary_tint_intensity[dt] = v
		_refresh_province_fill_colors(true)


func get_primary_mapmode_intensity(mode: String = "") -> float:
	var m := mode.strip_edges().to_lower()
	if m.is_empty():
		m = current_map_mode.strip_edges().to_lower()
	return clampf(float(primary_mapmode_intensity.get(m, secondary_tint_intensity.get(m, 1.0))), 0.25, 2.0)


## Pass 22/29/46–48: serialize map UI (compare slots + heat/legend/ramp prefs).
func get_save_data() -> Dictionary:
	var slots_out: Array = []
	for s in _route_compare_slots:
		if s is Dictionary:
			slots_out.append((s as Dictionary).duplicate(true))
		else:
			slots_out.append({})
	var labels_out: Array = []
	for i in 4:
		if i < _route_compare_slot_labels.size():
			labels_out.append(str(_route_compare_slot_labels[i]))
		else:
			labels_out.append("")
	var heat_show := true
	var heat_int := 1.0
	var legend_op := 1.0
	var heat_ramp := "classic"
	var cool_hex := "59d9ff"
	var hot_hex := "ff4026"
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("get_show_pack_risk_heat"):
			heat_show = bool(_map_minimap.call("get_show_pack_risk_heat"))
		if _map_minimap.has_method("get_pack_risk_heat_intensity"):
			heat_int = float(_map_minimap.call("get_pack_risk_heat_intensity"))
		if _map_minimap.has_method("get_pack_legend_opacity"):
			legend_op = float(_map_minimap.call("get_pack_legend_opacity"))
		if _map_minimap.has_method("get_pack_heat_ramp"):
			heat_ramp = str(_map_minimap.call("get_pack_heat_ramp"))
		if _map_minimap.has_method("get_pack_heat_cool"):
			cool_hex = (_map_minimap.call("get_pack_heat_cool") as Color).to_html(false)
		if _map_minimap.has_method("get_pack_heat_hot"):
			hot_hex = (_map_minimap.call("get_pack_heat_hot") as Color).to_html(false)
	var lib_layout := str(load_pack_risk_heat_prefs().get("library_layout", "standard"))
	return {
		"route_compare_slots": slots_out,
		"route_compare_slot_labels": labels_out,
		"secondary_tint_intensity": secondary_tint_intensity.duplicate(true),
		"primary_mapmode_intensity": primary_mapmode_intensity.duplicate(true),
		"current_map_mode": current_map_mode,
		"route_risk_day_history": _route_risk_day_history.duplicate(true),
		"munitions_occupation_filter": munitions_occupation_filter,
		"pack_risk_heat_show": heat_show,
		"pack_risk_heat_intensity": heat_int,
		"pack_legend_opacity": legend_op,
		"pack_heat_ramp": heat_ramp,
		"pack_heat_cool": cool_hex,
		"pack_heat_hot": hot_hex,
		"pack_library_layout": lib_layout,
	}


## Pass 22/29: restore map UI from save.
func apply_save_data(data: Dictionary) -> void:
	if data == null or data.is_empty():
		return
	if data.has("secondary_tint_intensity") and data["secondary_tint_intensity"] is Dictionary:
		secondary_tint_intensity = (data["secondary_tint_intensity"] as Dictionary).duplicate(true)
	if data.has("primary_mapmode_intensity") and data["primary_mapmode_intensity"] is Dictionary:
		primary_mapmode_intensity = (data["primary_mapmode_intensity"] as Dictionary).duplicate(true)
	if data.has("route_compare_slots") and data["route_compare_slots"] is Array:
		_route_compare_slots = []
		for s in data["route_compare_slots"]:
			if s is Dictionary:
				_route_compare_slots.append((s as Dictionary).duplicate(true))
			else:
				_route_compare_slots.append({})
		while _route_compare_slots.size() < 4:
			_route_compare_slots.append({})
		if _route_compare_slots.size() > 4:
			_route_compare_slots.resize(4)
	if data.has("route_compare_slot_labels") and data["route_compare_slot_labels"] is Array:
		_route_compare_slot_labels = []
		for lab in data["route_compare_slot_labels"]:
			_route_compare_slot_labels.append(str(lab))
		while _route_compare_slot_labels.size() < 4:
			_route_compare_slot_labels.append("")
		if _route_compare_slot_labels.size() > 4:
			_route_compare_slot_labels.resize(4)
	if data.has("munitions_occupation_filter"):
		var mf := str(data["munitions_occupation_filter"]).strip_edges().to_lower()
		if mf in ["all", "occupied", "mine"]:
			call_deferred("_on_munitions_occupation_filter_changed", mf)
	if data.has("current_map_mode"):
		var m := str(data["current_map_mode"]).strip_edges().to_lower()
		if m in ["political", "strain", "vitality", "development", "supply", "munitions", "loyalty", "infra", "naval", "weather", "resources", "states", "terrain"]:
			call_deferred("set_map_mode", m)
	if data.has("route_risk_day_history") and data["route_risk_day_history"] is Dictionary:
		_route_risk_day_history = (data["route_risk_day_history"] as Dictionary).duplicate(true)
	# Pass 46–49: restore heat + legend + ramp + custom colors prefs.
	if (
		data.has("pack_risk_heat_show")
		or data.has("pack_risk_heat_intensity")
		or data.has("pack_legend_opacity")
		or data.has("pack_heat_ramp")
		or data.has("pack_library_layout")
		or data.has("pack_heat_cool")
		or data.has("pack_heat_hot")
	):
		var hs := true
		var hi := 1.0
		var lo := 1.0
		var hr := "classic"
		var ll := "standard"
		var cool_h := "59d9ff"
		var hot_h := "ff4026"
		if data.has("pack_risk_heat_show"):
			hs = bool(data["pack_risk_heat_show"])
		if data.has("pack_risk_heat_intensity"):
			hi = float(data["pack_risk_heat_intensity"])
		if data.has("pack_legend_opacity"):
			lo = float(data["pack_legend_opacity"])
		if data.has("pack_heat_ramp"):
			hr = str(data["pack_heat_ramp"])
		if data.has("pack_library_layout"):
			ll = str(data["pack_library_layout"])
		if data.has("pack_heat_cool"):
			cool_h = str(data["pack_heat_cool"])
		if data.has("pack_heat_hot"):
			hot_h = str(data["pack_heat_hot"])
		call_deferred("_apply_pack_risk_heat_prefs", hs, hi, lo, hr, cool_h, hot_h)
		save_pack_risk_heat_prefs(hs, hi, lo, hr, ll, cool_h, hot_h)
	call_deferred("_refresh_province_fill_colors", true)
	call_deferred("_notify_minimap_pack_pins")


const ROUTE_PACK_MAP_PREFS_PATH := "user://route_packs/_map_prefs.json"
const PACK_HEAT_RAMPS: PackedStringArray = ["classic", "inferno", "viridis", "mono", "custom"]
const PACK_LIBRARY_LAYOUTS: PackedStringArray = ["standard", "compact", "wide", "left"]
const PACK_LIBRARY_DOCKS: PackedStringArray = ["float", "left", "right", "bottom"]
const PACK_LIBRARY_THEMES: PackedStringArray = ["classic", "mono", "amber", "magenta"]


## Pass 49: parse color hex (rrggbb or #rrggbb) → Color.
func _pack_heat_hex_to_color(hex: String, fallback: Color) -> Color:
	var h := hex.strip_edges().trim_prefix("#")
	if h.length() == 6 or h.length() == 8:
		return Color.html("#" + h)
	return fallback


## Pass 46–49: load heat + legend + ramp + custom colors + library layout prefs.
func load_pack_risk_heat_prefs() -> Dictionary:
	_ensure_route_pack_library_dir()
	var defaults := {
		"show": true,
		"intensity": 1.0,
		"legend_opacity": 1.0,
		"heat_ramp": "classic",
		"library_layout": "standard",
		"heat_cool": "59d9ff",
		"heat_hot": "ff4026",
		"library_w": 600.0,
		"library_h": 560.0,
		"heat_ramp_legend": true,
		"library_dock": "float",
		"library_docks": {},
		"library_opacity": 1.0,
		"library_opacities": {},
		"pin_focus_sfx": true,
		"library_opacity_link": false,
		"pin_focus_sfx_db": -8.0,
		"library_theme": "classic",
		"library_themes": {},
		"pin_focus_sfx_bus": "Master",
	}
	if not FileAccess.file_exists(ROUTE_PACK_MAP_PREFS_PATH):
		return defaults
	var f := FileAccess.open(ROUTE_PACK_MAP_PREFS_PATH, FileAccess.READ)
	if f == null:
		return defaults
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(txt) != OK or not (p.data is Dictionary):
		return defaults
	var d: Dictionary = p.data
	var ramp := str(d.get("pack_heat_ramp", d.get("heat_ramp", "classic"))).to_lower()
	if ramp not in PACK_HEAT_RAMPS:
		ramp = "classic"
	var layout := str(d.get("pack_library_layout", d.get("library_layout", "standard"))).to_lower()
	if layout not in PACK_LIBRARY_LAYOUTS:
		layout = "standard"
	var dock_raw := str(d.get("pack_library_dock", d.get("library_dock", "float"))).to_lower()
	if dock_raw not in PACK_LIBRARY_DOCKS:
		dock_raw = "float"
	var docks_out: Dictionary = {}
	var docks_raw = d.get("pack_library_docks", d.get("library_docks", {}))
	if docks_raw is Dictionary:
		for dk in (docks_raw as Dictionary).keys():
			var dv := str((docks_raw as Dictionary)[dk]).to_lower()
			if dv in PACK_LIBRARY_DOCKS:
				docks_out[str(dk)] = dv
	var opac_out: Dictionary = {}
	var opac_raw = d.get("pack_library_opacities", d.get("library_opacities", {}))
	if opac_raw is Dictionary:
		for ok in (opac_raw as Dictionary).keys():
			opac_out[str(ok)] = clampf(float((opac_raw as Dictionary)[ok]), 0.35, 1.0)
	return {
		"show": bool(d.get("pack_risk_heat_show", d.get("show", true))),
		"intensity": clampf(float(d.get("pack_risk_heat_intensity", d.get("intensity", 1.0))), 0.0, 2.0),
		"legend_opacity": clampf(
			float(d.get("pack_legend_opacity", d.get("legend_opacity", 1.0))), 0.0, 1.0
		),
		"heat_ramp": ramp,
		"library_layout": layout,
		"heat_cool": str(d.get("pack_heat_cool", d.get("heat_cool", "59d9ff"))),
		"heat_hot": str(d.get("pack_heat_hot", d.get("heat_hot", "ff4026"))),
		"library_w": clampf(float(d.get("pack_library_w", d.get("library_w", 600.0))), 400.0, 1200.0),
		"library_h": clampf(float(d.get("pack_library_h", d.get("library_h", 560.0))), 360.0, 1000.0),
		"heat_ramp_legend": bool(d.get("pack_heat_ramp_legend", d.get("heat_ramp_legend", true))),
		"library_dock": dock_raw,
		"library_docks": docks_out,
		"library_opacity": clampf(float(d.get("pack_library_opacity", d.get("library_opacity", 1.0))), 0.35, 1.0),
		"library_opacities": opac_out,
		"pin_focus_sfx": bool(d.get("pack_pin_focus_sfx", d.get("pin_focus_sfx", true))),
		"library_opacity_link": bool(d.get("pack_library_opacity_link", d.get("library_opacity_link", false))),
		"pin_focus_sfx_db": clampf(float(d.get("pack_pin_focus_sfx_db", d.get("pin_focus_sfx_db", -8.0))), -40.0, 0.0),
		"library_theme": _normalize_library_theme(str(d.get("pack_library_theme", d.get("library_theme", "classic")))),
		"library_themes": _parse_library_themes_map(d.get("pack_library_themes", d.get("library_themes", {}))),
		"pin_focus_sfx_bus": str(d.get("pack_pin_focus_sfx_bus", d.get("pin_focus_sfx_bus", "Master"))),
	}


## Pass 46–57: persist map pack prefs to user://route_packs/_map_prefs.json.
func save_pack_risk_heat_prefs(
	show_heat: bool,
	intensity: float,
	legend_opacity: float = 1.0,
	heat_ramp: String = "",
	library_layout: String = "",
	heat_cool: String = "",
	heat_hot: String = "",
	library_w: float = -1.0,
	library_h: float = -1.0,
	heat_ramp_legend: Variant = null,
	library_dock: String = "",
	library_docks: Variant = null,
	library_opacity: float = -1.0,
	library_opacities: Variant = null,
	pin_focus_sfx: Variant = null,
	library_opacity_link: Variant = null,
	pin_focus_sfx_db: float = 999.0,
	library_theme: String = "",
	library_themes: Variant = null,
	pin_focus_sfx_bus: String = ""
) -> bool:
	_ensure_route_pack_library_dir()
	var prev := load_pack_risk_heat_prefs()
	var ramp := heat_ramp.strip_edges().to_lower()
	if ramp.is_empty():
		ramp = str(prev.get("heat_ramp", "classic"))
	if ramp not in PACK_HEAT_RAMPS:
		ramp = "classic"
	var layout := library_layout.strip_edges().to_lower()
	if layout.is_empty():
		layout = str(prev.get("library_layout", "standard"))
	if layout not in PACK_LIBRARY_LAYOUTS:
		layout = "standard"
	var cool := heat_cool.strip_edges()
	if cool.is_empty():
		cool = str(prev.get("heat_cool", "59d9ff"))
	var hot := heat_hot.strip_edges()
	if hot.is_empty():
		hot = str(prev.get("heat_hot", "ff4026"))
	var lw := library_w if library_w > 0.0 else float(prev.get("library_w", 600.0))
	var lh := library_h if library_h > 0.0 else float(prev.get("library_h", 560.0))
	var rleg := bool(prev.get("heat_ramp_legend", true))
	if heat_ramp_legend != null:
		rleg = bool(heat_ramp_legend)
	var dock := library_dock.strip_edges().to_lower()
	if dock.is_empty():
		dock = str(prev.get("library_dock", "float"))
	if dock not in PACK_LIBRARY_DOCKS:
		dock = "float"
	var docks_save: Dictionary = {}
	var prev_docks = prev.get("library_docks", {})
	if prev_docks is Dictionary:
		docks_save = (prev_docks as Dictionary).duplicate(true)
	if library_docks is Dictionary:
		docks_save = (library_docks as Dictionary).duplicate(true)
	var lop := library_opacity if library_opacity > 0.0 else float(prev.get("library_opacity", 1.0))
	lop = clampf(lop, 0.35, 1.0)
	var opac_save: Dictionary = {}
	var prev_opac = prev.get("library_opacities", {})
	if prev_opac is Dictionary:
		opac_save = (prev_opac as Dictionary).duplicate(true)
	if library_opacities is Dictionary:
		opac_save = (library_opacities as Dictionary).duplicate(true)
	var pin_sfx := bool(prev.get("pin_focus_sfx", true))
	if pin_focus_sfx != null:
		pin_sfx = bool(pin_focus_sfx)
	var link_op := bool(prev.get("library_opacity_link", false))
	if library_opacity_link != null:
		link_op = bool(library_opacity_link)
	var pin_db := float(prev.get("pin_focus_sfx_db", -8.0))
	if pin_focus_sfx_db < 100.0:
		pin_db = clampf(pin_focus_sfx_db, -40.0, 0.0)
	var theme_id := library_theme.strip_edges().to_lower()
	if theme_id.is_empty():
		theme_id = str(prev.get("library_theme", "classic"))
	theme_id = _normalize_library_theme(theme_id)
	var themes_save: Dictionary = {}
	var prev_themes = prev.get("library_themes", {})
	if prev_themes is Dictionary:
		themes_save = (prev_themes as Dictionary).duplicate(true)
	if library_themes is Dictionary:
		themes_save = _parse_library_themes_map(library_themes)
	var sfx_bus := pin_focus_sfx_bus.strip_edges()
	if sfx_bus.is_empty():
		sfx_bus = str(prev.get("pin_focus_sfx_bus", "Master"))
	if sfx_bus.is_empty():
		sfx_bus = "Master"
	var f := FileAccess.open(ROUTE_PACK_MAP_PREFS_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var payload := {
		"v": 12,
		"pack_risk_heat_show": show_heat,
		"pack_risk_heat_intensity": clampf(intensity, 0.0, 2.0),
		"pack_legend_opacity": clampf(legend_opacity, 0.0, 1.0),
		"pack_heat_ramp": ramp,
		"pack_library_layout": layout,
		"pack_heat_cool": cool.trim_prefix("#"),
		"pack_heat_hot": hot.trim_prefix("#"),
		"pack_library_w": clampf(lw, 400.0, 1200.0),
		"pack_library_h": clampf(lh, 360.0, 1000.0),
		"pack_heat_ramp_legend": rleg,
		"pack_library_dock": dock,
		"pack_library_docks": docks_save,
		"pack_library_opacity": lop,
		"pack_library_opacities": opac_save,
		"pack_pin_focus_sfx": pin_sfx,
		"pack_library_opacity_link": link_op,
		"pack_pin_focus_sfx_db": pin_db,
		"pack_library_theme": theme_id,
		"pack_library_themes": themes_save,
		"pack_pin_focus_sfx_bus": sfx_bus,
	}
	f.store_string(JSON.stringify(payload))
	f.close()
	return true


## Pass 51: cycle heat ramp preset (dir +1 / -1). Persists prefs. Returns new ramp id.
func cycle_pack_heat_ramp(dir: int = 1) -> String:
	var prefs := load_pack_risk_heat_prefs()
	var cur := str(prefs.get("heat_ramp", "classic"))
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_heat_ramp"):
		cur = str(_map_minimap.call("get_pack_heat_ramp"))
	var idx := PACK_HEAT_RAMPS.find(cur)
	if idx < 0:
		idx = 0
	var step := 1 if dir >= 0 else -1
	idx = posmod(idx + step, PACK_HEAT_RAMPS.size())
	var nxt := str(PACK_HEAT_RAMPS[idx])
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_heat_ramp"):
		_map_minimap.call("set_pack_heat_ramp", nxt)
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		nxt,
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		-1.0,
		-1.0,
		null,
		str(prefs.get("library_dock", "float"))
	)
	return nxt


## Pass 51: shared bulk chip selection APIs (multi-window library).
func get_route_pack_bulk_selection() -> Array:
	var out: Array = []
	for e in _route_pack_bulk_sel:
		if e is Dictionary:
			out.append((e as Dictionary).duplicate(true))
	return out


func set_route_pack_bulk_selection(entries: Array) -> void:
	_route_pack_bulk_sel = []
	for e in entries:
		if e is Dictionary:
			var d: Dictionary = e
			var k := str(d.get("kind", ""))
			var v := str(d.get("value", ""))
			if k.is_empty():
				continue
			_route_pack_bulk_sel.append({"kind": k, "value": v})
	_notify_route_pack_bulk_watchers()


func toggle_route_pack_bulk_chip(kind: String, value: String) -> void:
	for i in range(_route_pack_bulk_sel.size() - 1, -1, -1):
		var e = _route_pack_bulk_sel[i]
		if e is Dictionary and str(e.get("kind", "")) == kind and str(e.get("value", "")) == value:
			_route_pack_bulk_sel.remove_at(i)
			_notify_route_pack_bulk_watchers()
			return
	_route_pack_bulk_sel.append({"kind": kind, "value": value})
	_notify_route_pack_bulk_watchers()


func clear_route_pack_bulk_selection() -> void:
	_route_pack_bulk_sel.clear()
	_notify_route_pack_bulk_watchers()


func register_route_pack_bulk_watcher(cb: Callable) -> void:
	if cb.is_valid() and not _route_pack_bulk_watchers.has(cb):
		_route_pack_bulk_watchers.append(cb)


func unregister_route_pack_bulk_watcher(cb: Callable) -> void:
	_route_pack_bulk_watchers.erase(cb)


func _notify_route_pack_bulk_watchers() -> void:
	var alive: Array = []
	for cb in _route_pack_bulk_watchers:
		if cb is Callable and (cb as Callable).is_valid():
			alive.append(cb)
			(cb as Callable).call()
	_route_pack_bulk_watchers = alive


## Pass 53/54: per-window dock map helpers (window index → dock id).
func get_library_dock_for_window(window_idx: int) -> String:
	var prefs := load_pack_risk_heat_prefs()
	var docks = prefs.get("library_docks", {})
	var key := str(maxi(1, window_idx))
	if docks is Dictionary and docks.has(key):
		var d := str(docks[key]).to_lower()
		if d in PACK_LIBRARY_DOCKS:
			return d
	# Fall back to global dock for window 1.
	var g := str(prefs.get("library_dock", "float")).to_lower()
	return g if g in PACK_LIBRARY_DOCKS else "float"


func set_library_dock_for_window(window_idx: int, dock: String) -> void:
	var d := dock.strip_edges().to_lower()
	if d not in PACK_LIBRARY_DOCKS:
		d = "float"
	var prefs := load_pack_risk_heat_prefs()
	var docks: Dictionary = {}
	var prev_d = prefs.get("library_docks", {})
	if prev_d is Dictionary:
		docks = (prev_d as Dictionary).duplicate(true)
	docks[str(maxi(1, window_idx))] = d
	# Persist via save with extra field - merge into file.
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		d if window_idx <= 1 else str(prefs.get("library_dock", "float")),
		docks,
		float(prefs.get("library_opacity", 1.0)),
		prefs.get("library_opacities", {})
	)


## Pass 55: per-window library opacity.
func get_library_opacity_for_window(window_idx: int) -> float:
	var prefs := load_pack_risk_heat_prefs()
	var opac = prefs.get("library_opacities", {})
	var key := str(maxi(1, window_idx))
	if opac is Dictionary and opac.has(key):
		return clampf(float(opac[key]), 0.35, 1.0)
	return clampf(float(prefs.get("library_opacity", 1.0)), 0.35, 1.0)


func set_library_opacity_for_window(window_idx: int, opacity: float) -> void:
	var op := clampf(opacity, 0.35, 1.0)
	var prefs := load_pack_risk_heat_prefs()
	var opac: Dictionary = {}
	var prev_o = prefs.get("library_opacities", {})
	if prev_o is Dictionary:
		opac = (prev_o as Dictionary).duplicate(true)
	var link_all := bool(prefs.get("library_opacity_link", false))
	if link_all:
		# Pass 56: write same opacity to every known window key + global.
		for k in opac.keys():
			opac[str(k)] = op
		# Ensure current window key exists.
		opac[str(maxi(1, window_idx))] = op
		# Also stamp windows 1–4 so secondaries inherit even if never opened.
		for wi in range(1, 5):
			opac[str(wi)] = op
	else:
		opac[str(maxi(1, window_idx))] = op
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		str(prefs.get("library_dock", "float")),
		prefs.get("library_docks", {}),
		op if (link_all or window_idx <= 1) else float(prefs.get("library_opacity", 1.0)),
		opac,
		null,
		null
	)
	# Live-update other open library windows when linked.
	if link_all:
		_apply_library_opacity_to_open_windows(op)


## Pass 56: set link-all opacity flag (persisted).
func set_library_opacity_link_all(enable: bool) -> void:
	var prefs := load_pack_risk_heat_prefs()
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		str(prefs.get("library_dock", "float")),
		prefs.get("library_docks", {}),
		float(prefs.get("library_opacity", 1.0)),
		prefs.get("library_opacities", {}),
		null,
		enable
	)


func get_library_opacity_link_all() -> bool:
	return bool(load_pack_risk_heat_prefs().get("library_opacity_link", false))


## Pass 56/57: apply opacity to every open PackLibraryPopup* panel (preserve theme RGB).
func _apply_library_opacity_to_open_windows(opacity: float) -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var op := clampf(opacity, 0.35, 1.0)
	for ch in ui.get_children():
		if ch is Control and str(ch.name).begins_with("PackLibraryPopup"):
			var ctl := ch as Control
			var m := ctl.modulate
			m.a = op
			ctl.modulate = m


## Pass 56: pin focus SFX mute flag.
func get_pin_focus_sfx_enabled() -> bool:
	return bool(load_pack_risk_heat_prefs().get("pin_focus_sfx", true))


func set_pin_focus_sfx_enabled(enable: bool) -> void:
	var prefs := load_pack_risk_heat_prefs()
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		str(prefs.get("library_dock", "float")),
		prefs.get("library_docks", {}),
		float(prefs.get("library_opacity", 1.0)),
		prefs.get("library_opacities", {}),
		enable,
		null,
		float(prefs.get("pin_focus_sfx_db", -8.0)),
		str(prefs.get("library_theme", "classic"))
	)


## Pass 57: pin focus SFX volume (dB, -40..0).
func get_pin_focus_sfx_volume_db() -> float:
	return clampf(float(load_pack_risk_heat_prefs().get("pin_focus_sfx_db", -8.0)), -40.0, 0.0)


func set_pin_focus_sfx_volume_db(db: float) -> void:
	var prefs := load_pack_risk_heat_prefs()
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		str(prefs.get("library_dock", "float")),
		prefs.get("library_docks", {}),
		float(prefs.get("library_opacity", 1.0)),
		prefs.get("library_opacities", {}),
		bool(prefs.get("pin_focus_sfx", true)),
		null,
		clampf(db, -40.0, 0.0),
		str(prefs.get("library_theme", "classic"))
	)


const ROUTE_PACK_THEME_PRESETS_PATH := "user://route_packs/_library_themes.json"


func _parse_library_themes_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not raw is Dictionary:
		return out
	for k in (raw as Dictionary).keys():
		out[str(k)] = _normalize_library_theme(str((raw as Dictionary)[k]))
	return out


func _normalize_library_theme(theme_id: String) -> String:
	var t := theme_id.strip_edges().to_lower()
	if t.is_empty():
		return "classic"
	if t in PACK_LIBRARY_THEMES:
		return t
	# Pass 58: allow custom ids present in theme preset file.
	var presets := get_library_theme_presets()
	if presets.has(t):
		return t
	return "classic"


func get_library_theme() -> String:
	return _normalize_library_theme(str(load_pack_risk_heat_prefs().get("library_theme", "classic")))


func set_library_theme(theme_id: String) -> void:
	set_library_theme_for_window(1, theme_id)


## Pass 58: per-window library theme.
func get_library_theme_for_window(window_idx: int) -> String:
	var prefs := load_pack_risk_heat_prefs()
	var themes = prefs.get("library_themes", {})
	var key := str(maxi(1, window_idx))
	if themes is Dictionary and themes.has(key):
		return _normalize_library_theme(str(themes[key]))
	return get_library_theme()


func set_library_theme_for_window(window_idx: int, theme_id: String) -> void:
	var tid := _normalize_library_theme(theme_id)
	var prefs := load_pack_risk_heat_prefs()
	var themes: Dictionary = {}
	var prev_t = prefs.get("library_themes", {})
	if prev_t is Dictionary:
		themes = (prev_t as Dictionary).duplicate(true)
	themes[str(maxi(1, window_idx))] = tid
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		str(prefs.get("library_dock", "float")),
		prefs.get("library_docks", {}),
		float(prefs.get("library_opacity", 1.0)),
		prefs.get("library_opacities", {}),
		bool(prefs.get("pin_focus_sfx", true)),
		null,
		float(prefs.get("pin_focus_sfx_db", -8.0)),
		tid if window_idx <= 1 else str(prefs.get("library_theme", "classic")),
		themes,
		str(prefs.get("pin_focus_sfx_bus", "Master"))
	)


## Pass 58: built-in + file theme presets {id: {modulate: Color, title: Color}}.
func get_library_theme_presets() -> Dictionary:
	var out: Dictionary = {
		"classic": {"modulate": Color(1, 1, 1, 1), "title": RetrowaveTheme.CYAN},
		"mono": {"modulate": Color(0.9, 0.92, 0.96, 1), "title": Color(0.85, 0.88, 0.92, 1)},
		"amber": {"modulate": Color(1.05, 0.98, 0.88, 1), "title": Color(1.0, 0.82, 0.4, 1)},
		"magenta": {"modulate": Color(1.05, 0.92, 1.05, 1), "title": RetrowaveTheme.MAGENTA},
	}
	if not FileAccess.file_exists(ROUTE_PACK_THEME_PRESETS_PATH):
		return out
	var f := FileAccess.open(ROUTE_PACK_THEME_PRESETS_PATH, FileAccess.READ)
	if f == null:
		return out
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(txt) != OK or not (p.data is Dictionary):
		return out
	var root: Dictionary = p.data
	var themes = root.get("themes", root)
	if not themes is Dictionary:
		return out
	for k in (themes as Dictionary).keys():
		var id := str(k).strip_edges().to_lower()
		if id.is_empty():
			continue
		var entry = (themes as Dictionary)[k]
		if not entry is Dictionary:
			continue
		var ed: Dictionary = entry
		var mod_c := _pack_heat_hex_to_color(str(ed.get("modulate", "ffffff")), Color(1, 1, 1))
		var title_c := _pack_heat_hex_to_color(str(ed.get("title", "33e6ff")), RetrowaveTheme.CYAN)
		out[id] = {"modulate": mod_c, "title": title_c}
	return out


## Pass 58: write theme presets file (built-ins + optional extra custom map).
func save_library_theme_presets_file(extra: Dictionary = {}) -> String:
	_ensure_route_pack_library_dir()
	var themes_out: Dictionary = {}
	var builtins := {
		"classic": {"modulate": "ffffff", "title": "33e6ff"},
		"mono": {"modulate": "e6ebf5", "title": "d9e0eb"},
		"amber": {"modulate": "fffaf0", "title": "ffd166"},
		"magenta": {"modulate": "fff0ff", "title": "ff33cc"},
	}
	for k in builtins.keys():
		themes_out[k] = builtins[k]
	for k2 in extra.keys():
		var id2 := str(k2).strip_edges().to_lower()
		if id2.is_empty():
			continue
		var e2 = extra[k2]
		if e2 is Dictionary:
			var mhex := str(e2.get("modulate", "ffffff")).trim_prefix("#")
			var thex := str(e2.get("title", "33e6ff")).trim_prefix("#")
			themes_out[id2] = {"modulate": mhex, "title": thex}
	var payload := {
		"v": 1,
		"format": "epochs_library_themes",
		"generated": Time.get_datetime_string_from_system(true),
		"themes": themes_out,
	}
	var f := FileAccess.open(ROUTE_PACK_THEME_PRESETS_PATH, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	return ROUTE_PACK_THEME_PRESETS_PATH


## Pass 58: import theme presets from path or default file. Returns count of themes loaded.
func load_library_theme_presets_file(path: String = "") -> int:
	var pth := path if not path.is_empty() else ROUTE_PACK_THEME_PRESETS_PATH
	if not FileAccess.file_exists(pth):
		return 0
	# Touch via get_library_theme_presets which reads the file.
	# If custom path, copy into default location.
	if pth != ROUTE_PACK_THEME_PRESETS_PATH:
		var rf := FileAccess.open(pth, FileAccess.READ)
		if rf == null:
			return 0
		var body := rf.get_as_text()
		rf.close()
		_ensure_route_pack_library_dir()
		var wf := FileAccess.open(ROUTE_PACK_THEME_PRESETS_PATH, FileAccess.WRITE)
		if wf == null:
			return 0
		wf.store_string(body)
		wf.close()
	return get_library_theme_presets().size()


## Pass 58/59: force-play pin focus SFX at current volume/bus (ignores mute for preview).
func preview_pin_focus_sfx() -> void:
	var path := str(_SFX_PATHS.get("pin_focus", _SFX_PATHS["map"]))
	if not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if stream == null:
		return
	if _map_sfx_player == null or not is_instance_valid(_map_sfx_player):
		_map_sfx_player = AudioStreamPlayer.new()
		_map_sfx_player.name = "MapActionSfx"
		add_child(_map_sfx_player)
	_map_sfx_player.bus = get_pin_focus_sfx_bus()
	_map_sfx_player.volume_db = get_pin_focus_sfx_volume_db()
	_map_sfx_player.stream = stream
	_map_sfx_player.play()


## Pass 59: pin focus SFX audio bus name (must exist in AudioServer or falls back to Master).
func get_pin_focus_sfx_bus() -> String:
	var bus := str(load_pack_risk_heat_prefs().get("pin_focus_sfx_bus", "Master")).strip_edges()
	if bus.is_empty():
		bus = "Master"
	if AudioServer.get_bus_index(bus) < 0:
		return "Master"
	return bus


func set_pin_focus_sfx_bus(bus_name: String) -> void:
	var bus := bus_name.strip_edges()
	if bus.is_empty() or AudioServer.get_bus_index(bus) < 0:
		bus = "Master"
	var prefs := load_pack_risk_heat_prefs()
	var snap := _snapshot_pack_map_ui_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		str(snap.get("library_layout", "standard")),
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		str(prefs.get("library_dock", "float")),
		prefs.get("library_docks", {}),
		float(prefs.get("library_opacity", 1.0)),
		prefs.get("library_opacities", {}),
		bool(prefs.get("pin_focus_sfx", true)),
		null,
		float(prefs.get("pin_focus_sfx_db", -8.0)),
		str(prefs.get("library_theme", "classic")),
		prefs.get("library_themes", {}),
		bus
	)


func list_audio_bus_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i in AudioServer.bus_count:
		out.append(AudioServer.get_bus_name(i))
	if out.is_empty():
		out.append("Master")
	return out


## Pass 59: upsert theme colors into presets file (creates custom id).
func upsert_library_theme_preset(theme_id: String, modulate: Color, title_col: Color) -> bool:
	var id := theme_id.strip_edges().to_lower()
	if id.is_empty():
		return false
	# Merge with existing file themes.
	var extra: Dictionary = {}
	if FileAccess.file_exists(ROUTE_PACK_THEME_PRESETS_PATH):
		var f0 := FileAccess.open(ROUTE_PACK_THEME_PRESETS_PATH, FileAccess.READ)
		if f0 != null:
			var t0 := f0.get_as_text()
			f0.close()
			var p0 := JSON.new()
			if p0.parse(t0) == OK and p0.data is Dictionary:
				var th = (p0.data as Dictionary).get("themes", {})
				if th is Dictionary:
					for k in (th as Dictionary).keys():
						extra[str(k)] = (th as Dictionary)[k]
	extra[id] = {
		"modulate": modulate.to_html(false),
		"title": title_col.to_html(false),
	}
	return not save_library_theme_presets_file(extra).is_empty()


## Pass 59/64: share code EOTM1.<base64url(json)> for one theme.
## to_clipboard=false for strip/batch export without clobbering clipboard.
func export_library_theme_share_code(theme_id: String = "", to_clipboard: bool = true) -> String:
	var tid := _normalize_library_theme(theme_id if not theme_id.is_empty() else get_library_theme())
	var presets := get_library_theme_presets()
	var mod_c := Color(1, 1, 1)
	var title_c := RetrowaveTheme.CYAN
	if presets.has(tid) and presets[tid] is Dictionary:
		var pe: Dictionary = presets[tid]
		if pe.get("modulate") is Color:
			mod_c = pe.get("modulate") as Color
		if pe.get("title") is Color:
			title_c = pe.get("title") as Color
	var payload := {
		"v": 1,
		"format": "epochs_library_theme",
		"id": tid,
		"modulate": mod_c.to_html(false),
		"title": title_c.to_html(false),
	}
	var json_s := JSON.stringify(payload)
	var b64 := Marshalls.utf8_to_base64(json_s)
	# URL-safe-ish
	b64 = b64.replace("+", "-").replace("/", "_")
	var code := "EOTM1." + b64
	if to_clipboard and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(code)
	return code


## Pass 59: import EOTM1 share code → upserts preset. Returns {ok, id, error}.
func import_library_theme_share_code(code: String = "") -> Dictionary:
	var raw := code.strip_edges()
	if raw.is_empty() and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		raw = DisplayServer.clipboard_get().strip_edges()
	if raw.is_empty():
		return {"ok": false, "error": "empty"}
	if not raw.begins_with("EOTM1."):
		return {"ok": false, "error": "prefix"}
	var b64 := raw.substr(6).replace("-", "+").replace("_", "/")
	var json_s := Marshalls.base64_to_utf8(b64)
	if json_s.is_empty():
		return {"ok": false, "error": "decode"}
	var p := JSON.new()
	if p.parse(json_s) != OK or not (p.data is Dictionary):
		return {"ok": false, "error": "parse"}
	var root: Dictionary = p.data
	var id := _sanitize_library_theme_id(str(root.get("id", "shared")))
	if id.is_empty():
		id = "shared"
	var mod_c := _pack_heat_hex_to_color(str(root.get("modulate", "ffffff")), Color(1, 1, 1))
	var title_c := _pack_heat_hex_to_color(str(root.get("title", "33e6ff")), RetrowaveTheme.CYAN)
	if not upsert_library_theme_preset(id, mod_c, title_c):
		return {"ok": false, "error": "write", "id": id}
	return {"ok": true, "id": id, "modulate": mod_c.to_html(false), "title": title_c.to_html(false)}


## Pass 59/60: flash highlight on selected ItemList rows.
## pulse_col: L-cyan / R-magenta defaults via callers. stagger > 0 cascades multi-select.
func pulse_item_list_selection(
	list: ItemList,
	duration: float = 0.85,
	pulse_col: Color = Color(0.35, 0.95, 1.0, 0.55),
	stagger: float = 0.0
) -> int:
	if list == null or not is_instance_valid(list):
		return 0
	var sels: PackedInt32Array = list.get_selected_items()
	if sels.is_empty():
		return 0
	var originals: Dictionary = {}  # idx -> Color
	for si in sels:
		var idx := int(si)
		originals[idx] = list.get_item_custom_bg_color(idx)
	var gen := Time.get_ticks_msec()
	list.set_meta("_pack_select_pulse_gen", gen)
	var restore_one := func(i2: int) -> void:
		if not is_instance_valid(list):
			return
		if int(list.get_meta("_pack_select_pulse_gen", 0)) != gen:
			return
		if i2 < 0 or i2 >= list.item_count:
			return
		if not originals.has(i2):
			return
		var col: Color = originals[i2] as Color
		if col.a < 0.01:
			list.set_item_custom_bg_color(i2, Color(0, 0, 0, 0))
		else:
			list.set_item_custom_bg_color(i2, col)
	var st := maxf(0.0, stagger)
	if st <= 0.001:
		for si2 in sels:
			list.set_item_custom_bg_color(int(si2), pulse_col)
		get_tree().create_timer(duration).timeout.connect(func() -> void:
			for k in originals.keys():
				restore_one.call(int(k))
		)
	else:
		# Pass 60: cascade multi-select pulse (stagger seconds between items).
		for oi in sels.size():
			var idx_s := int(sels[oi])
			var delay_on := float(oi) * st
			var delay_off := delay_on + duration
			var capture_idx := idx_s
			get_tree().create_timer(delay_on).timeout.connect(func() -> void:
				if not is_instance_valid(list):
					return
				if int(list.get_meta("_pack_select_pulse_gen", 0)) != gen:
					return
				if capture_idx >= 0 and capture_idx < list.item_count:
					list.set_item_custom_bg_color(capture_idx, pulse_col)
			)
			get_tree().create_timer(delay_off).timeout.connect(func() -> void:
				restore_one.call(capture_idx)
			)
	return sels.size()


## Pass 60: sanitize theme id (a–z 0–9 _ - , max 32).
func _sanitize_library_theme_id(theme_id: String) -> String:
	var s := theme_id.strip_edges().to_lower()
	if s.is_empty():
		return ""
	var out := ""
	for i in s.length():
		var ch := s[i]
		var o := ch.unicode_at(0)
		var ok := (o >= 97 and o <= 122) or (o >= 48 and o <= 57) or ch == "_" or ch == "-"
		out += ch if ok else "_"
	if out.length() > 32:
		out = out.substr(0, 32)
	# Collapse repeated underscores.
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out


## Pass 60: write EOTM1 theme share code as QR PNG. Returns path or "".
func export_library_theme_share_qr_png(theme_id: String = "") -> String:
	var code := export_library_theme_share_code(theme_id)
	if code.is_empty():
		return ""
	var out_path := "user://library_theme_qr.png"
	var engine_path: String = RoutePackQRScr.encode_to_user_png(code, out_path, -1, 2)
	if not engine_path.is_empty() and FileAccess.file_exists(engine_path):
		return engine_path
	return ""


## Pass 61: global library layout preset id.
func get_library_layout() -> String:
	var layout := str(load_pack_risk_heat_prefs().get("library_layout", "standard")).to_lower()
	return layout if layout in PACK_LIBRARY_LAYOUTS else "standard"


func set_library_layout(layout_id: String) -> void:
	var lid := layout_id.strip_edges().to_lower()
	if lid not in PACK_LIBRARY_LAYOUTS:
		lid = "standard"
	var snap := _snapshot_pack_map_ui_prefs()
	var prefs := load_pack_risk_heat_prefs()
	save_pack_risk_heat_prefs(
		bool(snap.get("show", true)),
		float(snap.get("intensity", 1.0)),
		float(snap.get("legend_opacity", 1.0)),
		str(snap.get("heat_ramp", "classic")),
		lid,
		str(snap.get("heat_cool", "")),
		str(snap.get("heat_hot", "")),
		float(prefs.get("library_w", 600.0)),
		float(prefs.get("library_h", 560.0)),
		bool(prefs.get("heat_ramp_legend", true)),
		str(prefs.get("library_dock", "float")),
		prefs.get("library_docks", {}),
		float(prefs.get("library_opacity", 1.0)),
		prefs.get("library_opacities", {}),
		bool(prefs.get("pin_focus_sfx", true)),
		null,
		float(prefs.get("pin_focus_sfx_db", -8.0)),
		str(prefs.get("library_theme", "classic")),
		prefs.get("library_themes", {}),
		str(prefs.get("pin_focus_sfx_bus", "Master"))
	)


## Pass 60/61/64: full library chrome snapshot — EOCS1.<base64url(json)>.
## Includes theme + colors, dock, opacity, layout, pin SFX prefs.
## to_clipboard=false for strip/batch export without clobbering clipboard.
func export_library_chrome_share_code(window_idx: int = 1, to_clipboard: bool = true) -> String:
	var w := maxi(1, window_idx)
	var tid := get_library_theme_for_window(w)
	var presets := get_library_theme_presets()
	var mod_c := Color(1, 1, 1)
	var title_c := RetrowaveTheme.CYAN
	if presets.has(tid) and presets[tid] is Dictionary:
		var pe: Dictionary = presets[tid]
		if pe.get("modulate") is Color:
			mod_c = pe.get("modulate") as Color
		if pe.get("title") is Color:
			title_c = pe.get("title") as Color
	var payload := {
		"v": 2,
		"format": "epochs_library_chrome",
		"window": w,
		"theme": tid,
		"modulate": mod_c.to_html(false),
		"title": title_c.to_html(false),
		"dock": get_library_dock_for_window(w),
		"opacity": get_library_opacity_for_window(w),
		"layout": get_library_layout(),
		"pin_sfx": get_pin_focus_sfx_enabled(),
		"pin_sfx_db": get_pin_focus_sfx_volume_db(),
		"pin_sfx_bus": get_pin_focus_sfx_bus(),
	}
	var json_s := JSON.stringify(payload)
	var b64 := Marshalls.utf8_to_base64(json_s)
	b64 = b64.replace("+", "-").replace("/", "_")
	var code := "EOCS1." + b64
	if to_clipboard and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(code)
	return code


## Pass 60/61: import EOCS1 chrome snapshot → theme/dock/opacity/layout/pin-sfx.
## Returns {ok, theme, dock, opacity, layout, pin_sfx, …}.
func import_library_chrome_share_code(code: String = "", window_idx: int = 1) -> Dictionary:
	var raw := code.strip_edges()
	if raw.is_empty() and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		raw = DisplayServer.clipboard_get().strip_edges()
	if raw.is_empty():
		return {"ok": false, "error": "empty"}
	# Accept EOCS1 chrome or fall back to EOTM1 theme-only.
	if raw.begins_with("EOTM1."):
		var theme_only := import_library_theme_share_code(raw)
		if not bool(theme_only.get("ok", false)):
			return theme_only
		var tid0 := str(theme_only.get("id", "shared"))
		set_library_theme_for_window(window_idx, tid0)
		return {
			"ok": true,
			"theme": tid0,
			"dock": get_library_dock_for_window(window_idx),
			"opacity": get_library_opacity_for_window(window_idx),
			"layout": get_library_layout(),
			"pin_sfx": get_pin_focus_sfx_enabled(),
			"pin_sfx_db": get_pin_focus_sfx_volume_db(),
			"pin_sfx_bus": get_pin_focus_sfx_bus(),
			"format": "EOTM1",
		}
	if not raw.begins_with("EOCS1."):
		return {"ok": false, "error": "prefix"}
	var b64 := raw.substr(6).replace("-", "+").replace("_", "/")
	var json_s := Marshalls.base64_to_utf8(b64)
	if json_s.is_empty():
		return {"ok": false, "error": "decode"}
	var p := JSON.new()
	if p.parse(json_s) != OK or not (p.data is Dictionary):
		return {"ok": false, "error": "parse"}
	var root: Dictionary = p.data
	var tid := _sanitize_library_theme_id(str(root.get("theme", root.get("id", "shared"))))
	if tid.is_empty():
		tid = "shared"
	var mod_c := _pack_heat_hex_to_color(str(root.get("modulate", "ffffff")), Color(1, 1, 1))
	var title_c := _pack_heat_hex_to_color(str(root.get("title", "33e6ff")), RetrowaveTheme.CYAN)
	upsert_library_theme_preset(tid, mod_c, title_c)
	set_library_theme_for_window(window_idx, tid)
	var dock := str(root.get("dock", "float")).strip_edges().to_lower()
	if dock in PACK_LIBRARY_DOCKS:
		set_library_dock_for_window(window_idx, dock)
	else:
		dock = get_library_dock_for_window(window_idx)
	var opac := clampf(float(root.get("opacity", 1.0)), 0.35, 1.0)
	set_library_opacity_for_window(window_idx, opac)
	var layout := str(root.get("layout", get_library_layout())).strip_edges().to_lower()
	if layout in PACK_LIBRARY_LAYOUTS:
		set_library_layout(layout)
	else:
		layout = get_library_layout()
	# Pin SFX prefs optional (v2+ / older snaps without keys keep current).
	var sfx_touched := false
	if root.has("pin_sfx"):
		set_pin_focus_sfx_enabled(bool(root.get("pin_sfx")))
		sfx_touched = true
	if root.has("pin_sfx_db"):
		set_pin_focus_sfx_volume_db(float(root.get("pin_sfx_db")))
		sfx_touched = true
	if root.has("pin_sfx_bus"):
		set_pin_focus_sfx_bus(str(root.get("pin_sfx_bus")))
		sfx_touched = true
	if sfx_touched:
		notify_pin_sfx_ui_refresh()
	return {
		"ok": true,
		"theme": tid,
		"dock": dock,
		"opacity": opac,
		"layout": layout,
		"pin_sfx": get_pin_focus_sfx_enabled(),
		"pin_sfx_db": get_pin_focus_sfx_volume_db(),
		"pin_sfx_bus": get_pin_focus_sfx_bus(),
		"modulate": mod_c.to_html(false),
		"title": title_c.to_html(false),
		"format": "EOCS1",
	}


## Pass 60: write EOCS1 chrome share as QR PNG.
func export_library_chrome_share_qr_png(window_idx: int = 1) -> String:
	var code := export_library_chrome_share_code(window_idx)
	if code.is_empty():
		return ""
	var out_path := "user://library_chrome_qr.png"
	var engine_path: String = RoutePackQRScr.encode_to_user_png(code, out_path, -1, 2)
	if not engine_path.is_empty() and FileAccess.file_exists(engine_path):
		return engine_path
	return ""


## Pass 63/64: horizontal strip of theme QRs with bitmap labels. Returns path or "".
## theme_ids empty → all presets (max 12). Does not touch clipboard.
func export_library_theme_qr_strip_png(theme_ids: Array = [], path: String = "user://library_theme_qr_strip.png") -> String:
	var ids: Array = []
	if theme_ids.is_empty():
		var matches := list_library_theme_id_matches("", 12)
		for m in matches:
			ids.append(str(m))
	else:
		for t in theme_ids:
			var tid := _sanitize_library_theme_id(str(t))
			if not tid.is_empty() and not ids.has(tid):
				ids.append(tid)
	if ids.is_empty():
		return ""
	var cell := 96
	var pad := 8
	var label_h := 14
	var n := ids.size()
	var strip_w := n * cell + (n + 1) * pad
	var strip_h := cell + label_h + pad * 3
	var strip := Image.create(strip_w, strip_h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.08, 0.09, 0.12, 1.0))
	for i in n:
		var code := export_library_theme_share_code(str(ids[i]), false)
		var qr_img: Image = RoutePackQRScr.encode_to_image(code, -1, 2)
		if qr_img == null:
			continue
		qr_img.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		var ox := pad + i * (cell + pad)
		var oy := pad
		strip.blit_rect(qr_img, Rect2i(0, 0, cell, cell), Vector2i(ox, oy))
		# Pass 64: 3×5 bitmap label under cell.
		var label := str(ids[i])
		if label.length() > 14:
			label = label.substr(0, 13) + "…"
		_blit_bitmap_label(strip, ox, oy + cell + 3, label, Color(0.75, 0.9, 1.0, 1.0), cell)
	var out := path if not path.is_empty() else "user://library_theme_qr_strip.png"
	_ensure_route_pack_library_dir()
	var abs_path := ProjectSettings.globalize_path(out)
	if strip.save_png(abs_path) != OK:
		return ""
	return out


## Pass 63/64: strip of chrome QRs for given windows (default 1..2). No clipboard.
func export_library_chrome_qr_strip_png(
	window_indices: Array = [],
	path: String = "user://library_chrome_qr_strip.png"
) -> String:
	var wins: Array = []
	if window_indices.is_empty():
		wins = [1, 2]
	else:
		for w in window_indices:
			var wi := maxi(1, int(w))
			if not wins.has(wi):
				wins.append(wi)
	var cell := 112
	var pad := 8
	var label_h := 14
	var n := wins.size()
	var strip_w := n * cell + (n + 1) * pad
	var strip_h := cell + label_h + pad * 3
	var strip := Image.create(strip_w, strip_h, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.08, 0.09, 0.12, 1.0))
	for i in n:
		var wi2: int = int(wins[i])
		var code := export_library_chrome_share_code(wi2, false)
		var qr_img: Image = RoutePackQRScr.encode_to_image(code, -1, 2)
		if qr_img == null:
			continue
		qr_img.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		var ox := pad + i * (cell + pad)
		var oy := pad
		strip.blit_rect(qr_img, Rect2i(0, 0, cell, cell), Vector2i(ox, oy))
		var label := "win%d %s" % [wi2, get_library_theme_for_window(wi2)]
		if label.length() > 16:
			label = label.substr(0, 15) + "…"
		_blit_bitmap_label(strip, ox, oy + cell + 3, label, Color(1.0, 0.85, 0.55, 1.0), cell)
	var out := path if not path.is_empty() else "user://library_chrome_qr_strip.png"
	_ensure_route_pack_library_dir()
	var abs_path := ProjectSettings.globalize_path(out)
	if strip.save_png(abs_path) != OK:
		return ""
	return out


## Pass 64: tiny 3×5 bitmap font blit (a–z 0–9 _ - . space). Clips to max_w.
func _blit_bitmap_label(img: Image, x0: int, y0: int, text: String, col: Color, max_w: int = 96) -> void:
	if img == null:
		return
	var s := text.to_lower()
	var cx := x0
	var scale := 1
	# Fit: glyph 3px + 1 gap = 4; scale up if room.
	var need := s.length() * 4 * scale
	if need > max_w and s.length() > 0:
		# keep scale 1; truncation handled by caller
		pass
	for i in s.length():
		if cx + 4 > x0 + max_w:
			break
		var ch := s[i]
		var rows: Array = _bitmap_glyph_3x5(ch)
		for ry in rows.size():
			var bits: int = int(rows[ry])
			for rx in 3:
				if (bits >> (2 - rx)) & 1:
					var px := cx + rx
					var py := y0 + ry
					if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
						img.set_pixel(px, py, col)
		cx += 4


## 3×5 glyph rows as 3-bit ints (MSB = left). Unknown → box.
func _bitmap_glyph_3x5(ch: String) -> Array:
	# Compact retro font for strip labels.
	match ch:
		" ": return [0, 0, 0, 0, 0]
		"-": return [0, 0, 7, 0, 0]
		"_": return [0, 0, 0, 0, 7]
		".": return [0, 0, 0, 0, 2]
		"0": return [7, 5, 5, 5, 7]
		"1": return [2, 6, 2, 2, 7]
		"2": return [7, 1, 7, 4, 7]
		"3": return [7, 1, 7, 1, 7]
		"4": return [5, 5, 7, 1, 1]
		"5": return [7, 4, 7, 1, 7]
		"6": return [7, 4, 7, 5, 7]
		"7": return [7, 1, 1, 1, 1]
		"8": return [7, 5, 7, 5, 7]
		"9": return [7, 5, 7, 1, 7]
		"a": return [2, 5, 7, 5, 5]
		"b": return [6, 5, 6, 5, 6]
		"c": return [3, 4, 4, 4, 3]
		"d": return [6, 5, 5, 5, 6]
		"e": return [7, 4, 6, 4, 7]
		"f": return [7, 4, 6, 4, 4]
		"g": return [3, 4, 5, 5, 3]
		"h": return [5, 5, 7, 5, 5]
		"i": return [7, 2, 2, 2, 7]
		"j": return [1, 1, 1, 5, 2]
		"k": return [5, 5, 6, 5, 5]
		"l": return [4, 4, 4, 4, 7]
		"m": return [5, 7, 7, 5, 5]
		"n": return [5, 7, 7, 7, 5]
		"o": return [2, 5, 5, 5, 2]
		"p": return [6, 5, 6, 4, 4]
		"q": return [2, 5, 5, 7, 3]
		"r": return [6, 5, 6, 5, 5]
		"s": return [3, 4, 2, 1, 6]
		"t": return [7, 2, 2, 2, 2]
		"u": return [5, 5, 5, 5, 7]
		"v": return [5, 5, 5, 5, 2]
		"w": return [5, 5, 7, 7, 5]
		"x": return [5, 5, 2, 5, 5]
		"y": return [5, 5, 2, 2, 2]
		"z": return [7, 1, 2, 4, 7]
		_: return [7, 5, 5, 5, 7]


## Pass 61/62/64: decode first QR payload from image.
## Prefer pure-GDScript RoutePackQR decoder; fall back to zbarimg CLI.
## Returns text; last engine stats via get_last_qr_decode_stats().
func decode_qr_payload_from_image(path: String) -> String:
	var pth := path.strip_edges()
	if pth.is_empty():
		return ""
	# Pass 62: engine decoder first (no external dependency).
	var engine_text: String = RoutePackQRScr.decode_from_path(pth)
	if not engine_text.is_empty():
		return engine_text.strip_edges()
	var abs_path := pth
	if pth.begins_with("user://") or pth.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(pth)
	if not FileAccess.file_exists(abs_path):
		if FileAccess.file_exists(pth):
			abs_path = pth
		else:
			return ""
	var output: Array = []
	var exit_code := OS.execute(
		"zbarimg",
		PackedStringArray(["-q", "--raw", abs_path]),
		output,
		true
	)
	if exit_code != 0 and output.is_empty():
		return ""
	var fallback := ""
	for line in output:
		var s := str(line).strip_edges()
		if s.is_empty():
			continue
		# Prefer share-code prefixes.
		if (
			s.begins_with("EOTM1.")
			or s.begins_with("EOCS1.")
			or s.begins_with("EORP1.")
			or s.begins_with("EORP2.")
			or s.begins_with("EORP3.")
		):
			return s
		if fallback.is_empty():
			fallback = s
	return fallback


## Pass 64: last engine QR decode RS stats (empty/zero if zbarimg path used).
func get_last_qr_decode_stats() -> Dictionary:
	return RoutePackQRScr.get_last_decode_stats()


## Pass 61/64: import library theme/chrome from a QR image path.
## Auto-routes EOCS1 / EOTM1. Returns import result + path + optional rs stats.
func import_library_share_from_qr_image(path: String, window_idx: int = 1) -> Dictionary:
	var payload := decode_qr_payload_from_image(path)
	var rs := get_last_qr_decode_stats()
	if payload.is_empty():
		return {"ok": false, "error": "no_qr", "path": path, "rs": rs}
	if payload.begins_with("EOCS1.") or payload.begins_with("EOTM1."):
		var r := import_library_chrome_share_code(payload, window_idx)
		r["path"] = path
		r["payload_len"] = payload.length()
		r["rs"] = rs
		# Pass 64: toast RS correction stats when blocks were repaired.
		var corr := int(rs.get("blocks_corrected", 0))
		var raw_fb := int(rs.get("blocks_raw_fallback", 0))
		if (corr > 0 or raw_fb > 0) and typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"QR RS · fixed %d · raw %d · blocks %d" % [
					corr, raw_fb, int(rs.get("blocks", 0))
				]
			)
		return r
	return {
		"ok": false,
		"error": "prefix",
		"path": path,
		"raw": payload.substr(0, mini(40, payload.length())),
		"rs": rs,
	}


## Pass 62: batch import theme/chrome QR images. Last successful EOCS1/EOTM1 wins UI state.
## Returns {ok, total, imported, failed, last, errors[]}.
func import_library_shares_from_qr_images(paths: Array, window_idx: int = 1) -> Dictionary:
	var total := 0
	var imported := 0
	var failed := 0
	var errors: Array = []
	var last: Dictionary = {}
	for p in paths:
		var path := str(p).strip_edges()
		if path.is_empty():
			continue
		total += 1
		var r := import_library_share_from_qr_image(path, window_idx)
		if bool(r.get("ok", false)):
			imported += 1
			last = r
		else:
			failed += 1
			errors.append({
				"path": path,
				"error": str(r.get("error", "fail")),
			})
	return {
		"ok": imported > 0,
		"total": total,
		"imported": imported,
		"failed": failed,
		"last": last,
		"errors": errors,
	}


## Pass 62: watchers for live pin-SFX UI refresh (compare card controls).
var _pin_sfx_ui_watchers: Array = []  # Array of Callable


func register_pin_sfx_ui_watcher(cb: Callable) -> void:
	if not cb.is_valid():
		return
	# Dedup by equality if possible.
	for existing in _pin_sfx_ui_watchers:
		if existing is Callable and (existing as Callable) == cb:
			return
	_pin_sfx_ui_watchers.append(cb)


func unregister_pin_sfx_ui_watcher(cb: Callable) -> void:
	var next: Array = []
	for existing in _pin_sfx_ui_watchers:
		if existing is Callable and (existing as Callable) == cb:
			continue
		next.append(existing)
	_pin_sfx_ui_watchers = next


func notify_pin_sfx_ui_refresh() -> void:
	var alive: Array = []
	for cb in _pin_sfx_ui_watchers:
		if cb is Callable and (cb as Callable).is_valid():
			alive.append(cb)
			(cb as Callable).call()
	_pin_sfx_ui_watchers = alive


## Pass 61: list theme preset ids matching a query (for autocomplete). Max 16.
func list_library_theme_id_matches(query: String = "", max_n: int = 16) -> PackedStringArray:
	var q := query.strip_edges().to_lower()
	var out: PackedStringArray = PackedStringArray()
	var presets := get_library_theme_presets()
	var keys: Array = []
	for bk in PACK_LIBRARY_THEMES:
		keys.append(str(bk))
	for pk in presets.keys():
		var pks := str(pk)
		if not keys.has(pks):
			keys.append(pks)
	keys.sort()
	var lim := maxi(1, max_n)
	for k in keys:
		var id := str(k)
		if q.is_empty() or id.contains(q) or id.begins_with(q):
			out.append(id)
			if out.size() >= lim:
				break
	return out


## Pass 57/58: apply chrome/title accent for library theme (keeps opacity in modulate.a).
func apply_library_theme_to_panel(panel: Control, title: Label = null, theme_id: String = "") -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var tid := _normalize_library_theme(theme_id if not theme_id.is_empty() else get_library_theme())
	var a := panel.modulate.a
	var presets := get_library_theme_presets()
	var title_col := RetrowaveTheme.CYAN
	var mod_c := Color(1, 1, 1, 1)
	if presets.has(tid) and presets[tid] is Dictionary:
		var pe: Dictionary = presets[tid]
		if pe.get("modulate") is Color:
			mod_c = pe.get("modulate") as Color
		if pe.get("title") is Color:
			title_col = pe.get("title") as Color
	else:
		match tid:
			"mono":
				mod_c = Color(0.9, 0.92, 0.96, 1)
				title_col = Color(0.85, 0.88, 0.92, 1)
			"amber":
				mod_c = Color(1.05, 0.98, 0.88, 1)
				title_col = Color(1.0, 0.82, 0.4, 1)
			"magenta":
				mod_c = Color(1.05, 0.92, 1.05, 1)
				title_col = RetrowaveTheme.MAGENTA
			_:
				mod_c = Color(1, 1, 1, 1)
				title_col = RetrowaveTheme.CYAN
	mod_c.a = a
	panel.modulate = mod_c
	if title != null and is_instance_valid(title):
		title.add_theme_color_override("font_color", title_col)


## Pass 57: resolve pack names that exist in the library (for JSON packs assign).
func resolve_route_pack_library_names(names: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for n in names:
		var stem := _sanitize_pack_library_name(str(n))
		if stem.is_empty() or seen.has(stem):
			continue
		var path := ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
		if FileAccess.file_exists(path):
			seen[stem] = true
			out.append(stem)
	return out


## Pass 52: export shared bulk selection (+ matching pack names) to clipboard.
## Returns clipboard text or "" on failure.
func export_route_pack_bulk_clipboard(include_matching_packs: bool = true) -> String:
	var bulk: Array = get_route_pack_bulk_selection()
	var tags: PackedStringArray = PackedStringArray()
	var groups: PackedStringArray = PackedStringArray()
	for e in bulk:
		if not e is Dictionary:
			continue
		var k := str(e.get("kind", ""))
		var v := str(e.get("value", ""))
		if k == "tag" and not v.is_empty():
			tags.append("#" + v)
		elif k == "group":
			groups.append("@group:" + v)
	var lines: PackedStringArray = PackedStringArray()
	lines.append("# Epochs pack bulk export")
	lines.append("generated=" + Time.get_datetime_string_from_system(true))
	if tags.is_empty() and groups.is_empty():
		lines.append("bulk=(empty)")
	else:
		if not tags.is_empty():
			lines.append("tags=" + " ".join(tags))
		if not groups.is_empty():
			lines.append("groups=" + " ".join(groups))
	if include_matching_packs and (not tags.is_empty() or not groups.is_empty()):
		var q_parts: PackedStringArray = PackedStringArray()
		for t in tags:
			q_parts.append(t)
		for g in groups:
			q_parts.append(g)
		if tags.size() >= 2:
			q_parts.append("@tagor")
		if groups.size() >= 2:
			q_parts.append("@groupor")
		var q := " ".join(q_parts)
		var names: PackedStringArray = PackedStringArray()
		for ent in list_route_pack_library(q, "name"):
			if ent is Dictionary:
				var nm := str((ent as Dictionary).get("name", ""))
				if not nm.is_empty():
					names.append(nm)
		lines.append("packs=" + str(names.size()))
		for nm2 in names:
			lines.append("  - " + nm2)
	var text := "\n".join(lines)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
	return text


## Pass 56: structured bulk JSON export (schema epochs_pack_bulk v1).
## Returns JSON string; also sets clipboard. Writes path if non-empty.
func export_route_pack_bulk_json(
	include_matching_packs: bool = true,
	path: String = ""
) -> String:
	var bulk: Array = get_route_pack_bulk_selection()
	var tags: Array = []
	var groups: Array = []
	for e in bulk:
		if not e is Dictionary:
			continue
		var k := str(e.get("kind", ""))
		var v := str(e.get("value", ""))
		if k == "tag" and not v.is_empty():
			tags.append(v)
		elif k == "group":
			groups.append(v)
	var packs: Array = []
	if include_matching_packs and (not tags.is_empty() or not groups.is_empty()):
		var q_parts: PackedStringArray = PackedStringArray()
		for t in tags:
			q_parts.append("#" + str(t))
		for g in groups:
			q_parts.append("@group:" + str(g))
		if tags.size() >= 2:
			q_parts.append("@tagor")
		if groups.size() >= 2:
			q_parts.append("@groupor")
		for ent in list_route_pack_library(" ".join(q_parts), "name"):
			if ent is Dictionary:
				var nm := str((ent as Dictionary).get("name", ""))
				if not nm.is_empty():
					packs.append(nm)
	var payload := {
		"v": 1,
		"format": "epochs_pack_bulk",
		"generated": Time.get_datetime_string_from_system(true),
		"tags": tags,
		"groups": groups,
		"packs": packs,
	}
	var text := JSON.stringify(payload, "\t")
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
	if not path.is_empty():
		var wf := FileAccess.open(path, FileAccess.WRITE)
		if wf != null:
			wf.store_string(text)
			wf.close()
	return text


## Pass 53/56: import bulk chips from clipboard / text / JSON schema.
## merge_mode: union (default) | replace. Returns {ok, tags, groups, total, mode, format}.
func import_route_pack_bulk_clipboard(text: String = "", merge_mode: String = "union") -> Dictionary:
	var raw := text
	if raw.is_empty() and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		raw = DisplayServer.clipboard_get()
	raw = raw.strip_edges()
	if raw.is_empty():
		return {"ok": false, "tags": 0, "groups": 0, "total": 0, "error": "empty"}
	# Pass 56: JSON schema path.
	if raw.begins_with("{"):
		var jp := JSON.new()
		if jp.parse(raw) == OK and jp.data is Dictionary:
			var root: Dictionary = jp.data
			var fmt := str(root.get("format", ""))
			if fmt == "epochs_pack_bulk" or root.has("tags") or root.has("groups"):
				var tags_j: Array = []
				var groups_j: Array = []
				var ta = root.get("tags", [])
				var ga = root.get("groups", [])
				if ta is Array:
					for t in ta:
						var ts := str(t).strip_edges().to_lower().trim_prefix("#")
						if not ts.is_empty() and not tags_j.has(ts):
							tags_j.append(ts)
				if ga is Array:
					for g in ga:
						var gs := _sanitize_pack_library_group(str(g))
						if not groups_j.has(gs):
							groups_j.append(gs)
				if tags_j.is_empty() and groups_j.is_empty():
					return {"ok": false, "tags": 0, "groups": 0, "total": 0, "error": "empty", "format": "json"}
				var mode_j := merge_mode.strip_edges().to_lower()
				var next_j: Array = []
				if mode_j != "replace":
					for e0 in get_route_pack_bulk_selection():
						if e0 is Dictionary:
							next_j.append(e0)
				var seen_j: Dictionary = {}
				for e1 in next_j:
					if e1 is Dictionary:
						seen_j["%s|%s" % [str(e1.get("kind", "")), str(e1.get("value", ""))]] = true
				var at := 0
				var ag := 0
				for t2 in tags_j:
					var kt := "tag|%s" % t2
					if seen_j.has(kt):
						continue
					seen_j[kt] = true
					next_j.append({"kind": "tag", "value": t2})
					at += 1
				for g2 in groups_j:
					var kg := "group|%s" % g2
					if seen_j.has(kg):
						continue
					seen_j[kg] = true
					next_j.append({"kind": "group", "value": g2})
					ag += 1
				set_route_pack_bulk_selection(next_j)
				# Pass 57: surface packs list for optional Left-list select.
				var packs_j: Array = []
				var pa = root.get("packs", [])
				if pa is Array:
					packs_j = resolve_route_pack_library_names(pa as Array)
				return {
					"ok": true,
					"tags": at,
					"groups": ag,
					"total": next_j.size(),
					"mode": mode_j if mode_j == "replace" else "union",
					"format": "json",
					"packs": packs_j,
				}
	var tags_in: Array = []
	var groups_in: Array = []
	for line in raw.split("\n"):
		var ln := str(line).strip_edges()
		if ln.is_empty() or ln.begins_with("# Epochs") or ln.begins_with("generated=") or ln.begins_with("packs="):
			continue
		if ln.begins_with("  - "):
			continue
		if ln.begins_with("tags="):
			ln = ln.substr(5)
		elif ln.begins_with("groups="):
			ln = ln.substr(7)
		elif ln.begins_with("bulk="):
			continue
		for part in ln.split(" "):
			var tok := str(part).strip_edges()
			if tok.is_empty():
				continue
			if tok.begins_with("#"):
				var t := tok.substr(1).strip_edges().to_lower()
				if not t.is_empty() and not tags_in.has(t):
					tags_in.append(t)
			elif tok.begins_with("@group:") or tok.begins_with("@g:"):
				var g := tok.substr(7) if tok.begins_with("@group:") else tok.substr(3)
				g = _sanitize_pack_library_group(g)
				if not groups_in.has(g):
					groups_in.append(g)
	if tags_in.is_empty() and groups_in.is_empty():
		return {"ok": false, "tags": 0, "groups": 0, "total": 0, "error": "parse"}
	var mode := merge_mode.strip_edges().to_lower()
	var next: Array = []
	if mode != "replace":
		for e in get_route_pack_bulk_selection():
			if e is Dictionary:
				next.append(e)
	var seen: Dictionary = {}
	for e2 in next:
		if e2 is Dictionary:
			seen["%s|%s" % [str(e2.get("kind", "")), str(e2.get("value", ""))]] = true
	var added_t := 0
	var added_g := 0
	for t2 in tags_in:
		var key_t := "tag|%s" % t2
		if seen.has(key_t):
			continue
		seen[key_t] = true
		next.append({"kind": "tag", "value": t2})
		added_t += 1
	for g2 in groups_in:
		var key_g := "group|%s" % g2
		if seen.has(key_g):
			continue
		seen[key_g] = true
		next.append({"kind": "group", "value": g2})
		added_g += 1
	set_route_pack_bulk_selection(next)
	return {
		"ok": true,
		"tags": added_t,
		"groups": added_g,
		"total": next.size(),
		"mode": mode if mode == "replace" else "union",
		"format": "text",
	}


const ROUTE_PACK_PIN_HISTORY_PATH := "user://route_packs/_pin_focus_history.json"


## Pass 54/55: push pin focus history entry (persisted).
func push_pin_focus_history(entry: Dictionary) -> void:
	var pid := int(entry.get("pid", -1))
	if pid < 0:
		return
	# Skip consecutive duplicates.
	if not _pin_focus_history.is_empty():
		var last: Dictionary = _pin_focus_history[_pin_focus_history.size() - 1]
		if int(last.get("pid", -1)) == pid:
			return
	_pin_focus_history.append({
		"pid": pid,
		"label": str(entry.get("label", "")),
		"source": str(entry.get("source", "")),
		"risk": float(entry.get("risk", 0.0)),
		"zoom": str(entry.get("zoom", "soft")),
	})
	while _pin_focus_history.size() > PIN_FOCUS_HISTORY_MAX:
		_pin_focus_history.remove_at(0)
	save_pin_focus_history()


## Pass 54/55: pop previous pin focus (skips current). Returns info dict or empty.
func pop_pin_focus_history(zoom_mode: String = "soft") -> Dictionary:
	if _pin_focus_history.size() < 2:
		return {}
	# Drop current.
	_pin_focus_history.pop_back()
	var prev: Dictionary = _pin_focus_history[_pin_focus_history.size() - 1]
	var pid := int(prev.get("pid", -1))
	var zm := zoom_mode if not zoom_mode.is_empty() else str(prev.get("zoom", "soft"))
	if pid >= 0 and has_method("focus_province_by_id"):
		focus_province_by_id(pid, zm)
		var ppos: Vector2 = province_centroids.get(pid, Vector2.ZERO) as Vector2
		if ppos == Vector2.ZERO and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			ppos = MapManager.get_province_centroid(pid)
		if ppos != Vector2.ZERO:
			spawn_pin_focus_pulse(ppos)
	save_pin_focus_history()
	return prev.duplicate(true)


func get_pin_focus_history_size() -> int:
	return _pin_focus_history.size()


## Pass 56: copy of history (newest last).
func get_pin_focus_history() -> Array:
	var out: Array = []
	for e in _pin_focus_history:
		if e is Dictionary:
			out.append((e as Dictionary).duplicate(true))
	return out


## Pass 56: jump to history index (0=oldest). Truncates stack after that entry. Returns info.
func jump_pin_focus_history(index: int, zoom_mode: String = "soft") -> Dictionary:
	if index < 0 or index >= _pin_focus_history.size():
		return {}
	# Truncate to keep jumped entry as current (drop newer).
	if index < _pin_focus_history.size() - 1:
		_pin_focus_history.resize(index + 1)
	var cur: Dictionary = _pin_focus_history[index]
	var pid := int(cur.get("pid", -1))
	var zm := zoom_mode if not zoom_mode.is_empty() else str(cur.get("zoom", "soft"))
	if pid >= 0 and has_method("focus_province_by_id"):
		focus_province_by_id(pid, zm)
		var ppos: Vector2 = province_centroids.get(pid, Vector2.ZERO) as Vector2
		if ppos == Vector2.ZERO and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			ppos = MapManager.get_province_centroid(pid)
		if ppos != Vector2.ZERO:
			spawn_pin_focus_pulse(ppos)
	save_pin_focus_history()
	return cur.duplicate(true)


## Pass 56: clear history stack (+ disk).
func clear_pin_focus_history() -> void:
	_pin_focus_history.clear()
	save_pin_focus_history()


## Pass 55: persist pin focus history to user://route_packs/_pin_focus_history.json.
func save_pin_focus_history() -> bool:
	_ensure_route_pack_library_dir()
	var f := FileAccess.open(ROUTE_PACK_PIN_HISTORY_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var entries: Array = []
	for e in _pin_focus_history:
		if e is Dictionary:
			entries.append((e as Dictionary).duplicate(true))
	f.store_string(JSON.stringify({
		"v": 1,
		"count": entries.size(),
		"entries": entries,
	}))
	f.close()
	return true


## Pass 55: load pin focus history from disk (replaces in-memory stack).
func load_pin_focus_history() -> int:
	_ensure_route_pack_library_dir()
	if not FileAccess.file_exists(ROUTE_PACK_PIN_HISTORY_PATH):
		return 0
	var f := FileAccess.open(ROUTE_PACK_PIN_HISTORY_PATH, FileAccess.READ)
	if f == null:
		return 0
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(txt) != OK or not (p.data is Dictionary):
		return 0
	var root: Dictionary = p.data
	var arr = root.get("entries", [])
	if not arr is Array:
		return 0
	_pin_focus_history = []
	for item in arr as Array:
		if not item is Dictionary:
			continue
		var pid := int((item as Dictionary).get("pid", -1))
		if pid < 0:
			continue
		_pin_focus_history.append({
			"pid": pid,
			"label": str((item as Dictionary).get("label", "")),
			"source": str((item as Dictionary).get("source", "")),
			"risk": float((item as Dictionary).get("risk", 0.0)),
			"zoom": str((item as Dictionary).get("zoom", "soft")),
		})
		if _pin_focus_history.size() >= PIN_FOCUS_HISTORY_MAX:
			break
	return _pin_focus_history.size()


## Pass 53: cool/hot colors for pulse tint (from minimap ramp).
func _pin_focus_pulse_ramp_colors() -> Array:
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_heat_ramp_colors"):
		var cols: Array = _map_minimap.call("get_pack_heat_ramp_colors")
		if cols.size() >= 2:
			return [cols[0] as Color, cols[1] as Color]
	return [Color(0.45, 0.95, 1.0, 0.95), Color(1.0, 0.35, 0.22, 0.95)]


## Pass 52/53: world-space expanding rings at pin focus (auto-fades; heat-ramp tint).
func spawn_pin_focus_pulse(world_pos: Vector2) -> void:
	if world_pos == Vector2.ZERO:
		return
	var parent_n: Node = container if container != null else self
	if _pin_focus_pulse_node != null and is_instance_valid(_pin_focus_pulse_node):
		_pin_focus_pulse_node.queue_free()
		_pin_focus_pulse_node = null
	var ramp_c: Array = _pin_focus_pulse_ramp_colors()
	var cool_p: Color = ramp_c[0] as Color
	var hot_p: Color = ramp_c[1] as Color
	var root := Node2D.new()
	root.name = "PinFocusPulse"
	root.z_index = 16
	root.position = world_pos
	parent_n.add_child(root)
	for ri in 3:
		var ring := Line2D.new()
		ring.name = "Ring%d" % ri
		ring.width = 2.2 - float(ri) * 0.35
		ring.closed = true
		var base := cool_p.lerp(hot_p, float(ri) / 2.0)
		base.a = 0.95
		ring.default_color = base
		ring.antialiased = true
		var pts: PackedVector2Array = PackedVector2Array()
		var nseg := 28
		var rad0 := 10.0 + float(ri) * 6.0
		for si in nseg:
			var a := TAU * float(si) / float(nseg)
			pts.append(Vector2(cos(a), sin(a)) * rad0)
		ring.points = pts
		root.add_child(ring)
	# Center pip (hot end of ramp).
	var pip := Line2D.new()
	pip.name = "Pip"
	pip.width = 3.0
	pip.closed = true
	var pip_c := hot_p
	pip_c.a = 0.95
	pip.default_color = pip_c
	var ppts: PackedVector2Array = PackedVector2Array()
	for si2 in 12:
		var a2 := TAU * float(si2) / 12.0
		ppts.append(Vector2(cos(a2), sin(a2)) * 4.0)
	pip.points = ppts
	root.add_child(pip)
	_pin_focus_pulse_node = root
	_pin_focus_pulse_t = 0.0
	# Pass 55–57: soft map ping (mute + volume handled in _play_map_sfx).
	_play_map_sfx("pin_focus")


func _update_pin_focus_pulse(delta: float) -> void:
	if _pin_focus_pulse_node == null or not is_instance_valid(_pin_focus_pulse_node):
		_pin_focus_pulse_node = null
		return
	_pin_focus_pulse_t += delta
	var u := clampf(_pin_focus_pulse_t / PIN_FOCUS_PULSE_DURATION, 0.0, 1.0)
	if u >= 1.0:
		_pin_focus_pulse_node.queue_free()
		_pin_focus_pulse_node = null
		return
	var sc := 1.0 + u * 2.8
	_pin_focus_pulse_node.scale = Vector2(sc, sc)
	var fade := 1.0 - u
	for ch in _pin_focus_pulse_node.get_children():
		if ch is Line2D:
			var col: Color = (ch as Line2D).default_color
			col.a = clampf(fade * (0.95 if ch.name != "Pip" else 1.0), 0.0, 1.0)
			(ch as Line2D).default_color = col


## Pass 51: position library panel for dock mode (float/left/right/bottom).
func _apply_library_dock_layout(c: Control, dock: String, width: float, height: float, shift: float = 0.0) -> void:
	var w := clampf(width, 400.0, 1200.0)
	var h := clampf(height, 360.0, 1000.0)
	var d := dock.strip_edges().to_lower()
	if d not in PACK_LIBRARY_DOCKS:
		d = "float"
	match d:
		"left":
			c.set_anchors_preset(Control.PRESET_CENTER_LEFT)
			c.offset_left = 8.0 + shift
			c.offset_right = 8.0 + w + shift
			c.offset_top = -h * 0.5
			c.offset_bottom = h * 0.5
		"right":
			c.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			c.offset_left = -8.0 - w - shift
			c.offset_right = -8.0 - shift
			c.offset_top = -h * 0.5
			c.offset_bottom = h * 0.5
		"bottom":
			c.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			c.offset_left = -w * 0.5 + shift
			c.offset_right = w * 0.5 + shift
			c.offset_top = -16.0 - h
			c.offset_bottom = -16.0
		_:
			c.set_anchors_preset(Control.PRESET_CENTER)
			c.offset_left = -w * 0.5 + shift
			c.offset_right = w * 0.5 + shift
			c.offset_top = -h * 0.5 + shift * 0.5
			c.offset_bottom = h * 0.5 + shift * 0.5


## Pass 46–50: apply heat + legend + ramp + custom colors to minimap.
func _apply_pack_risk_heat_prefs(
	show_heat: bool,
	intensity: float,
	legend_opacity: float = 1.0,
	heat_ramp: String = "classic",
	heat_cool: String = "59d9ff",
	heat_hot: String = "ff4026",
	heat_ramp_legend: bool = true
) -> void:
	if _map_minimap == null or not is_instance_valid(_map_minimap):
		return
	if _map_minimap.has_method("set_show_pack_risk_heat"):
		_map_minimap.call("set_show_pack_risk_heat", show_heat)
	if _map_minimap.has_method("set_pack_risk_heat_intensity"):
		_map_minimap.call("set_pack_risk_heat_intensity", intensity)
	if _map_minimap.has_method("set_pack_legend_opacity"):
		_map_minimap.call("set_pack_legend_opacity", legend_opacity)
	if _map_minimap.has_method("set_pack_heat_cool"):
		_map_minimap.call(
			"set_pack_heat_cool",
			_pack_heat_hex_to_color(heat_cool, Color(0.35, 0.85, 1.0))
		)
	if _map_minimap.has_method("set_pack_heat_hot"):
		_map_minimap.call(
			"set_pack_heat_hot",
			_pack_heat_hex_to_color(heat_hot, Color(1.0, 0.25, 0.15))
		)
	if _map_minimap.has_method("set_pack_heat_ramp"):
		_map_minimap.call("set_pack_heat_ramp", heat_ramp)
	if _map_minimap.has_method("set_show_heat_ramp_legend"):
		_map_minimap.call("set_show_heat_ramp_legend", heat_ramp_legend)


## Pass 46–55: load prefs file onto minimap (call after minimap bind).
func apply_stored_pack_risk_heat_prefs() -> void:
	var prefs := load_pack_risk_heat_prefs()
	_apply_pack_risk_heat_prefs(
		bool(prefs.get("show", true)),
		float(prefs.get("intensity", 1.0)),
		float(prefs.get("legend_opacity", 1.0)),
		str(prefs.get("heat_ramp", "classic")),
		str(prefs.get("heat_cool", "59d9ff")),
		str(prefs.get("heat_hot", "ff4026")),
		bool(prefs.get("heat_ramp_legend", true)),
	)
	# Pass 55: restore pin focus history from disk.
	load_pin_focus_history()


## Pass 48/49: snapshot current heat/legend/ramp/colors for save calls from UI.
func _snapshot_pack_map_ui_prefs() -> Dictionary:
	var show_h := true
	var inten := 1.0
	var leg := 1.0
	var ramp := "classic"
	var cool := "59d9ff"
	var hot := "ff4026"
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("get_show_pack_risk_heat"):
			show_h = bool(_map_minimap.call("get_show_pack_risk_heat"))
		if _map_minimap.has_method("get_pack_risk_heat_intensity"):
			inten = float(_map_minimap.call("get_pack_risk_heat_intensity"))
		if _map_minimap.has_method("get_pack_legend_opacity"):
			leg = float(_map_minimap.call("get_pack_legend_opacity"))
		if _map_minimap.has_method("get_pack_heat_ramp"):
			ramp = str(_map_minimap.call("get_pack_heat_ramp"))
		if _map_minimap.has_method("get_pack_heat_cool"):
			cool = (_map_minimap.call("get_pack_heat_cool") as Color).to_html(false)
		if _map_minimap.has_method("get_pack_heat_hot"):
			hot = (_map_minimap.call("get_pack_heat_hot") as Color).to_html(false)
	var layout := str(load_pack_risk_heat_prefs().get("library_layout", "standard"))
	return {
		"show": show_h,
		"intensity": inten,
		"legend_opacity": leg,
		"heat_ramp": ramp,
		"library_layout": layout,
		"heat_cool": cool,
		"heat_hot": hot,
	}


## Pass 49/50: build focus candidates [{pid, risk, label, source}].
## filter: {tags, groups, pack_names, tag_or, group_or} — empty = all loaded pins.
func _pack_focus_candidates(filter: Dictionary = {}) -> Array:
	var tags: Array = filter.get("tags", []) if filter.get("tags") is Array else []
	var groups: Array = filter.get("groups", []) if filter.get("groups") is Array else []
	var pack_names: Array = filter.get("pack_names", []) if filter.get("pack_names") is Array else []
	var tag_or := bool(filter.get("tag_or", true))
	var group_or := bool(filter.get("group_or", true))
	var has_filter := not tags.is_empty() or not groups.is_empty() or not pack_names.is_empty()
	var cands: Array = []
	var seen_pid: Dictionary = {}
	var add_cand := func(pid: int, risk: float, label: String, source: String) -> void:
		if pid < 0 or seen_pid.has(pid):
			return
		seen_pid[pid] = true
		cands.append({
			"focus_pid": pid,
			"risk": risk,
			"label": label,
			"source": source,
		})
	var pack_matches_filter := func(stem: String, meta: Dictionary) -> bool:
		var sl := stem.to_lower()
		if not pack_names.is_empty() and tags.is_empty() and groups.is_empty():
			for pn in pack_names:
				var pns := str(pn).to_lower()
				if pns.is_empty():
					continue
				if sl == pns or sl.contains(pns) or pns.contains(sl):
					return true
			return false
		var mtags: Array = meta.get("tags", []) if meta.get("tags") is Array else []
		var mtag_low: PackedStringArray = PackedStringArray()
		for mt in mtags:
			mtag_low.append(str(mt).to_lower())
		var mgrp := _sanitize_pack_library_group(str(meta.get("group", "")))
		if not tags.is_empty():
			if tag_or:
				var any_t := false
				for t in tags:
					var tl := str(t).to_lower()
					for ml in mtag_low:
						if ml == tl or ml.contains(tl):
							any_t = true
							break
					if any_t:
						break
				if not any_t:
					return false
			else:
				for t2 in tags:
					var tl2 := str(t2).to_lower()
					var hit_t := false
					for ml2 in mtag_low:
						if ml2 == tl2 or ml2.contains(tl2):
							hit_t = true
							break
					if not hit_t:
						return false
		if not groups.is_empty():
			if group_or:
				var any_g := false
				for g in groups:
					var gs := _sanitize_pack_library_group(str(g))
					if gs.is_empty():
						if mgrp.is_empty():
							any_g = true
							break
					elif _group_is_under(mgrp, gs):
						any_g = true
						break
				if not any_g:
					return false
			else:
				for g2 in groups:
					var gs2 := _sanitize_pack_library_group(str(g2))
					if gs2.is_empty():
						if not mgrp.is_empty():
							return false
					elif not _group_is_under(mgrp, gs2):
						return false
		return true
	var focus_from_peek := func(stem: String) -> void:
		var peek: Dictionary = peek_route_pack_library(stem)
		if not bool(peek.get("ok", false)):
			return
		var best_pid := -1
		var best_risk := -1.0
		var route_keys := ["path_a", "path_b", "path_c", "path_d"]
		var risk_keys := ["risk_a", "risk_b", "risk_c", "risk_d"]
		for ri in 4:
			var path: Array = peek.get(route_keys[ri], []) if peek.get(route_keys[ri]) is Array else []
			if path.size() < 2:
				continue
			var mid_pid := int(path[path.size() / 2])
			var rv := float(peek.get(risk_keys[ri], 0.0))
			if rv > best_risk:
				best_risk = rv
				best_pid = mid_pid
		if best_pid >= 0:
			add_cand.call(best_pid, best_risk, stem, "library")
	# Library packs matching filter.
	if has_filter:
		if not pack_names.is_empty() and tags.is_empty() and groups.is_empty():
			for pn2 in pack_names:
				focus_from_peek.call(str(pn2))
		else:
			var q_parts: PackedStringArray = PackedStringArray()
			for t3 in tags:
				q_parts.append("#" + str(t3))
			for g3 in groups:
				var g3s := str(g3)
				q_parts.append("@group:" + g3s)
			if tags.size() >= 2 and tag_or:
				q_parts.append("@tagor")
			if groups.size() >= 2 and group_or:
				q_parts.append("@groupor")
			var q := " ".join(q_parts)
			for e in list_route_pack_library(q, "mtime"):
				if not e is Dictionary:
					continue
				var nm := str((e as Dictionary).get("name", ""))
				if nm.is_empty():
					continue
				if not pack_names.is_empty():
					var ok_n2 := false
					var nml := nm.to_lower()
					for pn3 in pack_names:
						var p3 := str(pn3).to_lower()
						if nml == p3 or nml.contains(p3):
							ok_n2 = true
							break
					if not ok_n2:
						continue
				focus_from_peek.call(nm)
	# Loaded minimap pins (filter by slot label ↔ library tags when filtering).
	for p in get_pack_slot_pins():
		if not p is Dictionary:
			continue
		var pe: Dictionary = p
		var pid_p := int(pe.get("focus_pid", -1))
		var risk_p := float(pe.get("risk", 0.0))
		var lab_p := str(pe.get("label", ""))
		var slot_i := int(pe.get("slot", -1))
		var slot_lab := get_route_compare_slot_label(slot_i) if slot_i >= 0 else ""
		if slot_lab.is_empty():
			slot_lab = lab_p
		if has_filter:
			var meta_p := get_route_pack_library_tags(slot_lab)
			# Try stem from label prefix before · 
			if meta_p.is_empty() or (meta_p.get("tags", []) as Array).is_empty():
				var stem_try := slot_lab.split("·")[0].strip_edges() if slot_lab.contains("·") else slot_lab
				meta_p = get_route_pack_library_tags(stem_try)
			if not bool(pack_matches_filter.call(slot_lab, meta_p)):
				# Still allow if pack_names soft-match pin label.
				var soft := false
				for pn4 in pack_names:
					if lab_p.to_lower().contains(str(pn4).to_lower()) or slot_lab.to_lower().contains(str(pn4).to_lower()):
						soft = true
						break
				if not soft:
					continue
		add_cand.call(pid_p, risk_p, slot_lab if not slot_lab.is_empty() else lab_p, "pin")
	return cands


## Pass 49/50: cycle-focus pack pin by risk (highest first). Optional bulk/tag filter.
## filter keys: tags, groups, pack_names, tag_or, group_or.
## Returns focused province id or -1.
func focus_pack_pin_by_risk(
	cycle_index: int = 0,
	highest_first: bool = true,
	filter: Dictionary = {}
) -> int:
	var ranked: Array = _pack_focus_candidates(filter)
	if ranked.is_empty():
		return -1
	ranked.sort_custom(func(a, b) -> bool:
		var ra := float((a as Dictionary).get("risk", 0.0))
		var rb := float((b as Dictionary).get("risk", 0.0))
		if highest_first:
			return ra > rb
		return ra < rb
	)
	var idx := posmod(cycle_index, ranked.size())
	var pe: Dictionary = ranked[idx]
	var pid := int(pe.get("focus_pid", -1))
	if pid >= 0 and has_method("focus_province_by_id"):
		focus_province_by_id(pid)
	return pid


## Pass 50: last pin-focus cycle stats for UI toasts.
func focus_pack_pin_by_risk_info(
	cycle_index: int = 0,
	highest_first: bool = true,
	filter: Dictionary = {},
	zoom_mode: String = "soft"
) -> Dictionary:
	var ranked: Array = _pack_focus_candidates(filter)
	if ranked.is_empty():
		return {"pid": -1, "total": 0, "index": 0, "label": "", "source": "", "zoom": zoom_mode}
	ranked.sort_custom(func(a, b) -> bool:
		var ra := float((a as Dictionary).get("risk", 0.0))
		var rb := float((b as Dictionary).get("risk", 0.0))
		if highest_first:
			return ra > rb
		return ra < rb
	)
	var idx := posmod(cycle_index, ranked.size())
	var pe: Dictionary = ranked[idx]
	var pid := int(pe.get("focus_pid", -1))
	var zm := zoom_mode.strip_edges().to_lower()
	if zm not in ["tactical", "soft", "keep"]:
		zm = "soft"
	if pid >= 0 and has_method("focus_province_by_id"):
		focus_province_by_id(pid, zm)
		# Pass 52: pulse marker at focus centroid.
		var ppos: Vector2 = province_centroids.get(pid, Vector2.ZERO) as Vector2
		if ppos == Vector2.ZERO and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			ppos = MapManager.get_province_centroid(pid)
		if ppos != Vector2.ZERO:
			spawn_pin_focus_pulse(ppos)
		# Pass 54: history stack for Pin Back.
		push_pin_focus_history({
			"pid": pid,
			"label": str(pe.get("label", "")),
			"source": str(pe.get("source", "")),
			"risk": float(pe.get("risk", 0.0)),
			"zoom": zm,
		})
	return {
		"pid": pid,
		"total": ranked.size(),
		"index": idx,
		"label": str(pe.get("label", "")),
		"source": str(pe.get("source", "")),
		"risk": float(pe.get("risk", 0.0)),
		"zoom": zm,
		"history": _pin_focus_history.size(),
	}


## Pass 29: pack slot display name.
func set_route_compare_slot_label(slot: int, label: String) -> void:
	if slot < 0 or slot >= 4:
		return
	while _route_compare_slot_labels.size() < 4:
		_route_compare_slot_labels.append("")
	_route_compare_slot_labels[slot] = label.strip_edges()


func get_route_compare_slot_label(slot: int) -> String:
	if slot < 0 or slot >= _route_compare_slot_labels.size():
		return ""
	return str(_route_compare_slot_labels[slot])


## Pass 30/34: refresh minimap pack pins + legend after save/load/auto/reorder.
func _notify_minimap_pack_pins() -> void:
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("set_pack_pins"):
			_map_minimap.call("set_pack_pins", get_pack_slot_pins())
		elif _map_minimap.has_method("invalidate_pack_pins"):
			_map_minimap.call("invalidate_pack_pins")
		if _map_minimap.has_method("set_pack_legend"):
			_map_minimap.call("set_pack_legend", get_pack_slot_legend())


## Pass 29–32: auto-build A–D compare from open SupplyManager routes (lowest risk first).
## player_only: majority player-controlled path filter.
## owner_filter: if non-empty, fuzzy-match plan.owner_tag (exact / contains / 1-edit short tags).
## Returns number of routes packed (0 if none).
func auto_pack_open_supply_routes(max_routes: int = 4, player_only: bool = false, owner_filter: String = "") -> int:
	var cap := clampi(max_routes, 2, 4)
	if typeof(SupplyManager) == TYPE_NIL or not SupplyManager.has_method("get_all_routes"):
		return 0
	var player := ""
	if player_only:
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
			player = str(LeaderManager.get_player_country_tag()).to_upper()
		elif "player_tag" in SupplyManager:
			player = str(SupplyManager.player_tag).to_upper()
	var own_f := owner_filter.strip_edges().to_upper()
	var routes: Array = SupplyManager.get_all_routes()
	var ranked: Array = []
	for plan_var in routes:
		if not (plan_var is SupplyRoutePlan):
			continue
		var plan := plan_var as SupplyRoutePlan
		if plan.province_path.size() < 2:
			continue
		var plan_owner := str(plan.owner_tag).to_upper() if "owner_tag" in plan else ""
		if not own_f.is_empty() and not _owner_tag_fuzzy_match(plan_owner, own_f):
			continue
		var path: Array = []
		for pid in plan.province_path:
			path.append(int(pid))
		if player_only and not player.is_empty() and not _path_majority_player(path, player):
			continue
		var inter := float(plan.interdiction_chance) if "interdiction_chance" in plan else 0.0
		if inter <= 0.0:
			var est := estimate_path_interdiction(path)
			if est >= 0.0:
				inter = est
		var focus_pid := int(plan.target_province_id) if "target_province_id" in plan else -1
		if focus_pid < 0 and not path.is_empty():
			focus_pid = int(path[path.size() - 1])
		ranked.append({
			"path": path,
			"interdiction": inter,
			"focus_pid": focus_pid,
			"hops": path.size(),
			"owner_tag": plan_owner,
		})
	if ranked.size() < 2:
		return 0
	ranked.sort_custom(func(a, b) -> bool:
		var ra := float(a.get("interdiction", 1.0))
		var rb := float(b.get("interdiction", 1.0))
		if not is_equal_approx(ra, rb):
			return ra < rb
		return int(a.get("hops", 99)) < int(b.get("hops", 99))
	)
	var paths: Array = []
	var metas: Array = []
	var n := mini(cap, ranked.size())
	for i in n:
		var e: Dictionary = ranked[i]
		paths.append((e.get("path", []) as Array).duplicate())
		metas.append({
			"interdiction": float(e.get("interdiction", 0.0)),
			"focus_pid": int(e.get("focus_pid", -1)),
			"owner_tag": str(e.get("owner_tag", "")),
		})
	compare_supply_routes_multi(paths, metas)
	return n


## Pass 30: true if ≥ half of path provinces are player-controlled (controller else owner).
func _path_majority_player(path: Array, player: String) -> bool:
	if path.is_empty() or player.is_empty():
		return false
	var mine := 0
	var total := 0
	for pid_v in path:
		var pid := int(pid_v)
		var p: Province = provinces.get(pid) as Province if provinces.has(pid) else null
		if p == null and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			p = MapManager.get_province(pid) as Province
		if p == null:
			continue
		total += 1
		var ctrl := str(p.controller_tag).to_upper() if "controller_tag" in p else ""
		var own := str(p.owner_tag).to_upper() if "owner_tag" in p else ""
		var eff := ctrl if not ctrl.is_empty() else own
		if eff == player:
			mine += 1
	if total <= 0:
		return false
	return float(mine) / float(total) >= 0.5


## Pass 30–33: share code for last compare pack.
## EORP1 paths only · EORP2 + history · EORP3 deflate-compressed compact payload (default).
func export_route_pack_share_code(include_history: bool = true, compressed: bool = true) -> String:
	if _last_route_compare_data.is_empty():
		return ""
	var payload := _build_route_pack_payload(include_history, compressed)
	var code := ""
	if compressed:
		# EORP3: deflate + base64 of compact JSON (delta paths, percent history).
		var json := JSON.stringify(payload)
		var raw := json.to_utf8_buffer()
		var zipped: PackedByteArray = raw.compress(FileAccess.COMPRESSION_DEFLATE)
		if zipped.is_empty():
			# Fall back to uncompressed EORP1/2
			return export_route_pack_share_code(include_history, false)
		code = "EORP3." + Marshalls.raw_to_base64(zipped)
	else:
		var json2 := JSON.stringify(payload)
		var b64 := Marshalls.utf8_to_base64(json2)
		var prefix := "EORP2." if include_history else "EORP1."
		code = prefix + b64
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(code)
	return code


## Pass 33: build share payload (compact when compressed=true).
func _build_route_pack_payload(include_history: bool, compact: bool) -> Dictionary:
	var path_a: Array = _last_route_compare_data.get("path_a", []) as Array if _last_route_compare_data.get("path_a") is Array else []
	var path_b: Array = _last_route_compare_data.get("path_b", []) as Array if _last_route_compare_data.get("path_b") is Array else []
	var path_c: Array = _last_route_compare_data.get("path_c", []) as Array if _last_route_compare_data.get("path_c") is Array else []
	var path_d: Array = _last_route_compare_data.get("path_d", []) as Array if _last_route_compare_data.get("path_d") is Array else []
	var payload: Dictionary
	if compact:
		payload = {
			"v": 3,
			"a": _path_delta_encode(path_a),
			"b": _path_delta_encode(path_b),
			"c": _path_delta_encode(path_c),
			"d": _path_delta_encode(path_d),
			"ra": int(round(float(_last_route_compare_data.get("risk_a", 0.0)) * 100.0)),
			"rb": int(round(float(_last_route_compare_data.get("risk_b", 0.0)) * 100.0)),
			"rc": int(round(float(_last_route_compare_data.get("risk_c", 0.0)) * 100.0)),
			"rd": int(round(float(_last_route_compare_data.get("risk_d", 0.0)) * 100.0)),
			"fa": int(_last_route_compare_data.get("focus_a", -1)),
			"fb": int(_last_route_compare_data.get("focus_b", -1)),
			"fc": int(_last_route_compare_data.get("focus_c", -1)),
			"fd": int(_last_route_compare_data.get("focus_d", -1)),
			"oa": str(_last_route_compare_data.get("owner_a", "")),
			"ob": str(_last_route_compare_data.get("owner_b", "")),
			"oc": str(_last_route_compare_data.get("owner_c", "")),
			"od": str(_last_route_compare_data.get("owner_d", "")),
		}
		if include_history and _route_risk_day_history.has("last"):
			var tr = _route_risk_day_history["last"]
			if tr is Dictionary:
				payload["ha"] = _samples_to_pct((tr as Dictionary).get("samples_a", []))
				payload["hb"] = _samples_to_pct((tr as Dictionary).get("samples_b", []))
				payload["hc"] = _samples_to_pct((tr as Dictionary).get("samples_c", []))
				payload["hd"] = _samples_to_pct((tr as Dictionary).get("samples_d", []))
		else:
			payload["v"] = 3  # still compact paths even without history
	else:
		payload = {
			"v": 2 if include_history else 1,
			"a": path_a,
			"b": path_b,
			"c": path_c,
			"d": path_d,
			"ra": float(_last_route_compare_data.get("risk_a", 0.0)),
			"rb": float(_last_route_compare_data.get("risk_b", 0.0)),
			"rc": float(_last_route_compare_data.get("risk_c", 0.0)),
			"rd": float(_last_route_compare_data.get("risk_d", 0.0)),
			"fa": int(_last_route_compare_data.get("focus_a", -1)),
			"fb": int(_last_route_compare_data.get("focus_b", -1)),
			"fc": int(_last_route_compare_data.get("focus_c", -1)),
			"fd": int(_last_route_compare_data.get("focus_d", -1)),
			"oa": str(_last_route_compare_data.get("owner_a", "")),
			"ob": str(_last_route_compare_data.get("owner_b", "")),
			"oc": str(_last_route_compare_data.get("owner_c", "")),
			"od": str(_last_route_compare_data.get("owner_d", "")),
		}
		if include_history and _route_risk_day_history.has("last"):
			var tr2 = _route_risk_day_history["last"]
			if tr2 is Dictionary:
				payload["ha"] = (tr2 as Dictionary).get("samples_a", [])
				payload["hb"] = (tr2 as Dictionary).get("samples_b", [])
				payload["hc"] = (tr2 as Dictionary).get("samples_c", [])
				payload["hd"] = (tr2 as Dictionary).get("samples_d", [])
	return payload


## Pass 33: path as [start, Δ1, Δ2, …] for smaller JSON.
func _path_delta_encode(path: Array) -> Array:
	if path.is_empty():
		return []
	var out: Array = [int(path[0])]
	for i in range(1, path.size()):
		out.append(int(path[i]) - int(path[i - 1]))
	return out


func _path_delta_decode(enc: Array) -> Array:
	if enc.is_empty():
		return []
	# Detect absolute vs delta: if looks like plain path (mostly large positive, no tiny deltas pattern)
	# Compact always stores start + deltas. Decode: running sum.
	var out: Array = []
	var cur := int(enc[0])
	out.append(cur)
	for i in range(1, enc.size()):
		cur += int(enc[i])
		out.append(cur)
	return out


## Pass 33: float samples 0–1 → int percent 0–100 (and reverse).
func _samples_to_pct(samples: Variant) -> Array:
	var out: Array = []
	if not (samples is Array):
		return out
	for s in samples as Array:
		out.append(clampi(int(round(float(s) * 100.0)), 0, 100))
	return out


func _samples_from_pct(samples: Variant) -> Array:
	var out: Array = []
	if not (samples is Array):
		return out
	for s in samples as Array:
		var v := float(s)
		# Heuristic: values > 1.5 treated as percent integers
		if v > 1.5:
			out.append(clampf(v / 100.0, 0.0, 1.0))
		else:
			out.append(clampf(v, 0.0, 1.0))
	return out


## Pass 30–33: import pack share code (EORP1 / EORP2 / EORP3). Returns true on success.
func import_route_pack_share_code(code: String) -> bool:
	var s := code.strip_edges()
	var with_hist := false
	var compact := false
	if s.begins_with("EORP3."):
		s = s.substr(6)
		compact = true
		with_hist = true
	elif s.begins_with("EORP2."):
		s = s.substr(6)
		with_hist = true
	elif s.begins_with("EORP1."):
		s = s.substr(6)
	elif "EORP3." in s:
		var i3 := s.find("EORP3.")
		s = s.substr(i3 + 6)
		compact = true
		with_hist = true
	elif "EORP2." in s:
		var i2 := s.find("EORP2.")
		s = s.substr(i2 + 6)
		with_hist = true
	elif "EORP1." in s:
		var i1 := s.find("EORP1.")
		s = s.substr(i1 + 6)
	var json_s := ""
	if compact:
		var zipped := Marshalls.base64_to_raw(s)
		if zipped.is_empty():
			return false
		# Decompress with generous buffer (share payloads stay small).
		var raw := zipped.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
		if raw.is_empty():
			return false
		json_s = raw.get_string_from_utf8()
	else:
		json_s = Marshalls.base64_to_utf8(s)
	if json_s.is_empty():
		return false
	var p := JSON.new()
	if p.parse(json_s) != OK or not (p.data is Dictionary):
		return false
	var d: Dictionary = p.data
	var ver_payload := int(d.get("v", 1))
	if ver_payload >= 2:
		with_hist = true
	if ver_payload >= 3:
		compact = true
	var path_a: Array
	var path_b: Array
	var path_c: Array
	var path_d: Array
	if compact:
		path_a = _path_delta_decode(d.get("a", []) as Array if d.get("a") is Array else [])
		path_b = _path_delta_decode(d.get("b", []) as Array if d.get("b") is Array else [])
		path_c = _path_delta_decode(d.get("c", []) as Array if d.get("c") is Array else [])
		path_d = _path_delta_decode(d.get("d", []) as Array if d.get("d") is Array else [])
	else:
		path_a = d.get("a", []) as Array if d.get("a") is Array else []
		path_b = d.get("b", []) as Array if d.get("b") is Array else []
		path_c = d.get("c", []) as Array if d.get("c") is Array else []
		path_d = d.get("d", []) as Array if d.get("d") is Array else []
	if path_a.is_empty() or path_b.is_empty():
		return false
	# Risks: compact stores percent ints; legacy stores 0–1 floats.
	var ra := float(d.get("ra", 0.0))
	var rb := float(d.get("rb", 0.0))
	var rc := float(d.get("rc", 0.0))
	var rd := float(d.get("rd", 0.0))
	if compact or ra > 1.5:
		ra = clampf(ra / 100.0, 0.0, 1.0)
		rb = clampf(rb / 100.0, 0.0, 1.0)
		rc = clampf(rc / 100.0, 0.0, 1.0)
		rd = clampf(rd / 100.0, 0.0, 1.0)
	var paths: Array = [path_a, path_b]
	var metas: Array = [
		{"interdiction": ra, "focus_pid": int(d.get("fa", -1)), "owner_tag": str(d.get("oa", "")), "risk_recomputed": false},
		{"interdiction": rb, "focus_pid": int(d.get("fb", -1)), "owner_tag": str(d.get("ob", "")), "risk_recomputed": false},
	]
	if not path_c.is_empty():
		paths.append(path_c)
		metas.append({"interdiction": rc, "focus_pid": int(d.get("fc", -1)), "owner_tag": str(d.get("oc", ""))})
	if not path_d.is_empty():
		paths.append(path_d)
		metas.append({"interdiction": rd, "focus_pid": int(d.get("fd", -1)), "owner_tag": str(d.get("od", ""))})
	# Restore history samples before compare seeds a fresh track.
	if with_hist and (d.has("ha") or d.has("hb")):
		var track := {
			"path_a": path_a.duplicate(),
			"path_b": path_b.duplicate(),
			"path_c": path_c.duplicate(),
			"path_d": path_d.duplicate(),
			"samples_a": _samples_from_pct(d.get("ha", [])),
			"samples_b": _samples_from_pct(d.get("hb", [])),
			"samples_c": _samples_from_pct(d.get("hc", [])),
			"samples_d": _samples_from_pct(d.get("hd", [])),
		}
		_route_risk_day_history["last"] = track
	compare_supply_routes_multi(paths, metas)
	return true


## Pass 32: fuzzy owner match — exact, substring, prefix, or ≤1 edit for short tags (≤5).
func _owner_tag_fuzzy_match(plan_owner: String, filter: String) -> bool:
	var o := plan_owner.strip_edges().to_upper()
	var f := filter.strip_edges().to_upper()
	if f.is_empty():
		return true
	if o.is_empty():
		return false
	if o == f:
		return true
	if o.contains(f) or f.contains(o):
		return true
	if o.begins_with(f) or f.begins_with(o):
		return true
	if o.length() <= 5 and f.length() <= 5 and _tag_edit_distance(o, f) <= 1:
		return true
	return false


## Pass 32: Levenshtein distance for short country tags.
func _tag_edit_distance(a: String, b: String) -> int:
	var la := a.length()
	var lb := b.length()
	if la == 0:
		return lb
	if lb == 0:
		return la
	var prev: Array = []
	var cur: Array = []
	prev.resize(lb + 1)
	cur.resize(lb + 1)
	for j in lb + 1:
		prev[j] = j
	for i in la:
		cur[0] = i + 1
		for j in lb:
			var cost := 0 if a[i] == b[j] else 1
			cur[j + 1] = mini(mini(int(cur[j]) + 1, int(prev[j + 1]) + 1), int(prev[j]) + cost)
		var tmp := prev
		prev = cur
		cur = tmp
	return int(prev[lb])


## Pass 31–34: write QR PNG of share code. Prefer in-engine RoutePackQR (auto module size); fallback qrencode.
## Returns user:// path or "".
func export_route_pack_qr_png(include_history: bool = true) -> String:
	var code := export_route_pack_share_code(include_history)
	if code.is_empty():
		return ""
	var out_path := "user://route_pack_qr.png"
	# Pass 32/34: pure GDScript encoder with auto module px (target ~248 outer).
	var engine_path: String = RoutePackQRScr.encode_to_user_png(code, out_path, -1, 2)
	if not engine_path.is_empty() and FileAccess.file_exists(engine_path):
		return engine_path
	# Fallback: system qrencode (scale 4–6 by payload length)
	var abs_out := ProjectSettings.globalize_path(out_path)
	var scale := 6 if code.length() < 120 else (5 if code.length() < 280 else 4)
	var args := PackedStringArray(["-o", abs_out, "-s", str(scale), "-m", "2", "-l", "M", code])
	var exit_code := OS.execute("qrencode", args, [], false, false)
	if exit_code != 0:
		# Retry with shorter EORP1 code if payload too large.
		if include_history:
			return export_route_pack_qr_png(false)
		return ""
	if not FileAccess.file_exists(out_path):
		return ""
	return out_path


## Pass 34: write share code to user://route_pack_share.eorp (and optional clipboard). Returns path or "".
func export_route_pack_share_file(include_history: bool = true, compressed: bool = true) -> String:
	var code := export_route_pack_share_code(include_history, compressed)
	if code.is_empty():
		return ""
	var path := "user://route_pack_share.eorp"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(code)
	f.close()
	return path


## Pass 34: import share code from user://route_pack_share.eorp (or given path). Returns true on success.
func import_route_pack_share_file(path: String = "user://route_pack_share.eorp") -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var code := f.get_as_text().strip_edges()
	f.close()
	if code.is_empty():
		return false
	return import_route_pack_share_code(code)


const ROUTE_PACK_LIBRARY_DIR := "user://route_packs/"
const ROUTE_PACK_TAGS_PATH := "user://route_packs/_tags.json"


## Pass 35: ensure library directory exists.
func _ensure_route_pack_library_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(ROUTE_PACK_LIBRARY_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


## Pass 35: sanitize pack library name → safe filename stem.
func _sanitize_pack_library_name(name: String) -> String:
	var s := name.strip_edges().to_lower()
	if s.is_empty():
		s = "pack"
	var out := ""
	for i in s.length():
		var ch := s[i]
		var o := ch.unicode_at(0)
		var ok := (o >= 97 and o <= 122) or (o >= 48 and o <= 57) or ch == "_" or ch == "-"
		out += ch if ok else "_"
	if out.length() > 40:
		out = out.substr(0, 40)
	return out


## Pass 36: load tags sidecar {stem: {tags: [], note: ""}}.
func _load_pack_library_tags() -> Dictionary:
	_ensure_route_pack_library_dir()
	if not FileAccess.file_exists(ROUTE_PACK_TAGS_PATH):
		return {}
	var f := FileAccess.open(ROUTE_PACK_TAGS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(txt) != OK or not (p.data is Dictionary):
		return {}
	return (p.data as Dictionary).duplicate(true)


## Pass 36: persist tags sidecar.
func _save_pack_library_tags(data: Dictionary) -> bool:
	_ensure_route_pack_library_dir()
	var f := FileAccess.open(ROUTE_PACK_TAGS_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


## Pass 36: parse tag string "a, b #c" → unique lowercase tags.
func _parse_pack_tags(tag_str: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var raw := tag_str.strip_edges().replace("#", " ").replace(";", ",")
	for part in raw.split(","):
		for tok in str(part).split(" "):
			var t := tok.strip_edges().to_lower()
			if t.is_empty():
				continue
			if seen.has(t):
				continue
			seen[t] = true
			out.append(t)
	return out


## Pass 36–40: set tags (and optional note) for a library pack stem (preserves favorite + group).
func set_route_pack_library_tags(name: String, tags: Array, note: String = "") -> bool:
	var stem := _sanitize_pack_library_name(name)
	var data := _load_pack_library_tags()
	var clean: Array = []
	var seen: Dictionary = {}
	for t in tags:
		var ts := str(t).strip_edges().to_lower()
		if ts.is_empty() or seen.has(ts):
			continue
		seen[ts] = true
		clean.append(ts)
	var prev_fav := false
	var prev_group := ""
	if data.has(stem) and data[stem] is Dictionary:
		prev_fav = bool((data[stem] as Dictionary).get("favorite", false))
		prev_group = str((data[stem] as Dictionary).get("group", ""))
	data[stem] = {
		"tags": clean,
		"note": note.strip_edges(),
		"favorite": prev_fav,
		"group": prev_group,
	}
	return _save_pack_library_tags(data)


## Pass 36–40: get tags for stem → {tags, note, favorite, group}.
func get_route_pack_library_tags(name: String) -> Dictionary:
	var stem := _sanitize_pack_library_name(name)
	var data := _load_pack_library_tags()
	if data.has(stem) and data[stem] is Dictionary:
		var e: Dictionary = data[stem]
		return {
			"tags": e.get("tags", []) if e.get("tags") is Array else [],
			"note": str(e.get("note", "")),
			"favorite": bool(e.get("favorite", false)),
			"group": str(e.get("group", "")),
		}
	return {"tags": [], "note": "", "favorite": false, "group": ""}


## Pass 38/40: set/clear favorite star for a library pack (preserves group).
func set_route_pack_library_favorite(name: String, favorite: bool) -> bool:
	var stem := _sanitize_pack_library_name(name)
	var data := _load_pack_library_tags()
	var tags: Array = []
	var note := ""
	var group := ""
	if data.has(stem) and data[stem] is Dictionary:
		var e: Dictionary = data[stem]
		tags = e.get("tags", []) if e.get("tags") is Array else []
		note = str(e.get("note", ""))
		group = str(e.get("group", ""))
	data[stem] = {"tags": tags, "note": note, "favorite": favorite, "group": group}
	return _save_pack_library_tags(data)


## Pass 40: set folder group for a pack stem (empty = ungrouped).
func set_route_pack_library_group(name: String, group: String) -> bool:
	var stem := _sanitize_pack_library_name(name)
	var data := _load_pack_library_tags()
	var tags: Array = []
	var note := ""
	var fav := false
	if data.has(stem) and data[stem] is Dictionary:
		var e: Dictionary = data[stem]
		tags = e.get("tags", []) if e.get("tags") is Array else []
		note = str(e.get("note", ""))
		fav = bool(e.get("favorite", false))
	var g := _sanitize_pack_library_group(group)
	data[stem] = {"tags": tags, "note": note, "favorite": fav, "group": g}
	return _save_pack_library_tags(data)


## Pass 40/41: sanitize group path (nested folder-like: theater/east/coast).
## Allows a–z, 0–9, _, -, / ; collapses // ; max 48 chars.
func _sanitize_pack_library_group(group: String) -> String:
	var s := group.strip_edges().to_lower().replace("\\", "/")
	if s.is_empty():
		return ""
	var out := ""
	for i in s.length():
		var ch := s[i]
		var o := ch.unicode_at(0)
		var ok := (o >= 97 and o <= 122) or (o >= 48 and o <= 57) or ch == "_" or ch == "-" or ch == "/"
		out += ch if ok else "_"
	# Collapse repeated slashes and trim edges.
	while out.contains("//"):
		out = out.replace("//", "/")
	while out.begins_with("/"):
		out = out.substr(1)
	while out.ends_with("/"):
		out = out.substr(0, out.length() - 1)
	if out.length() > 48:
		out = out.substr(0, 48)
	return out


## Pass 41: parent path of nested group (theater/east → theater), "" if root.
func _group_parent_path(group: String) -> String:
	var g := _sanitize_pack_library_group(group)
	if g.is_empty() or not g.contains("/"):
		return ""
	var i := g.rfind("/")
	if i <= 0:
		return ""
	return g.substr(0, i)


## Pass 41: depth of nested group (""=0, a=1, a/b=2).
func _group_depth(group: String) -> int:
	var g := _sanitize_pack_library_group(group)
	if g.is_empty():
		return 0
	return g.count("/") + 1


## Pass 41: true if child is under parent path (exact or nested prefix).
func _group_is_under(child: String, parent: String) -> bool:
	var c := _sanitize_pack_library_group(child)
	var p := _sanitize_pack_library_group(parent)
	if p.is_empty():
		return true
	if c == p:
		return true
	return c.begins_with(p + "/")


## Pass 38: true if pack is favorited.
func is_route_pack_library_favorite(name: String) -> bool:
	return bool(get_route_pack_library_tags(name).get("favorite", false))


## Pass 38: toggle favorite; returns new state.
func toggle_route_pack_library_favorite(name: String) -> bool:
	var next := not is_route_pack_library_favorite(name)
	set_route_pack_library_favorite(name, next)
	return next


## Pass 37: collect unique tags across library with counts [{tag, count}].
func list_all_pack_library_tags() -> Array:
	var counts: Dictionary = {}
	for e in list_route_pack_library("", "mtime"):
		if not e is Dictionary:
			continue
		var tags: Array = (e as Dictionary).get("tags", []) if (e as Dictionary).get("tags") is Array else []
		for tg in tags:
			var t := str(tg).strip_edges().to_lower()
			if t.is_empty():
				continue
			counts[t] = int(counts.get(t, 0)) + 1
	var out: Array = []
	for k in counts.keys():
		out.append({"tag": str(k), "count": int(counts[k])})
	out.sort_custom(func(a, b) -> bool:
		var ca := int(a.get("count", 0))
		var cb := int(b.get("count", 0))
		if ca != cb:
			return ca > cb
		return str(a.get("tag", "")) < str(b.get("tag", ""))
	)
	return out


## Pass 37–40: sort library entries. mode: mtime | name | size | tags | fav | group
func sort_route_pack_library(entries: Array, mode: String = "mtime") -> Array:
	var m := mode.strip_edges().to_lower()
	if m.is_empty():
		m = "mtime"
	var sorted_e: Array = entries.duplicate()
	sorted_e.sort_custom(func(a, b) -> bool:
		if not (a is Dictionary) or not (b is Dictionary):
			return false
		var ad: Dictionary = a
		var bd: Dictionary = b
		match m:
			"name":
				return str(ad.get("name", "")).to_lower() < str(bd.get("name", "")).to_lower()
			"size":
				var sa := int(ad.get("bytes", 0))
				var sb := int(bd.get("bytes", 0))
				if sa != sb:
					return sa > sb
				return str(ad.get("name", "")) < str(bd.get("name", ""))
			"tags":
				var ta: Array = ad.get("tags", []) if ad.get("tags") is Array else []
				var tb: Array = bd.get("tags", []) if bd.get("tags") is Array else []
				if ta.size() != tb.size():
					return ta.size() > tb.size()
				return str(ad.get("name", "")) < str(bd.get("name", ""))
			"fav", "favorite", "favorites":
				var fa := 1 if bool(ad.get("favorite", false)) else 0
				var fb := 1 if bool(bd.get("favorite", false)) else 0
				if fa != fb:
					return fa > fb
				var ma2 := int(ad.get("mtime", 0))
				var mb2 := int(bd.get("mtime", 0))
				if ma2 != mb2:
					return ma2 > mb2
				return str(ad.get("name", "")) < str(bd.get("name", ""))
			"group", "folder":
				var ga := str(ad.get("group", "")).to_lower()
				var gb := str(bd.get("group", "")).to_lower()
				# Named groups first, ungrouped last; then name.
				if ga.is_empty() != gb.is_empty():
					return not ga.is_empty()
				if ga != gb:
					return ga < gb
				return str(ad.get("name", "")).to_lower() < str(bd.get("name", "")).to_lower()
			_:
				# mtime default (newest first)
				var ma := int(ad.get("mtime", 0))
				var mb := int(bd.get("mtime", 0))
				if ma != mb:
					return ma > mb
				return str(ad.get("name", "")) < str(bd.get("name", ""))
	)
	return sorted_e


## Pass 37/40: set note only (preserves tags + favorite + group).
func set_route_pack_library_note(name: String, note: String) -> bool:
	var stem := _sanitize_pack_library_name(name)
	var cur := get_route_pack_library_tags(stem)
	var tags: Array = cur.get("tags", []) if cur.get("tags") is Array else []
	var ok := set_route_pack_library_tags(stem, tags, note)
	# set_route_pack_library_tags preserves fav/group already.
	return ok


## Pass 35–38: list pack library entries [{name, path, bytes, mtime, tags, note, favorite}].
## query: name substring or #tag filter. sort_mode: mtime | name | size | tags | fav
func list_route_pack_library(query: String = "", sort_mode: String = "mtime") -> Array:
	_ensure_route_pack_library_dir()
	var tags_db := _load_pack_library_tags()
	var out: Array = []
	var dir := DirAccess.open(ROUTE_PACK_LIBRARY_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".eorp") and not fname.begins_with("_"):
			var path := ROUTE_PACK_LIBRARY_DIR + fname
			var stem := fname.get_basename()
			var bytes := 0
			var mtime := 0
			if FileAccess.file_exists(path):
				var rf := FileAccess.open(path, FileAccess.READ)
				if rf != null:
					bytes = int(rf.get_length())
					rf.close()
				mtime = int(FileAccess.get_modified_time(path))
			var tags: Array = []
			var note := ""
			var fav := false
			var group := ""
			if tags_db.has(stem) and tags_db[stem] is Dictionary:
				var te: Dictionary = tags_db[stem]
				tags = te.get("tags", []) if te.get("tags") is Array else []
				note = str(te.get("note", ""))
				fav = bool(te.get("favorite", false))
				group = str(te.get("group", ""))
			out.append({
				"name": stem,
				"path": path,
				"bytes": bytes,
				"mtime": mtime,
				"tags": tags,
				"note": note,
				"favorite": fav,
				"group": group,
			})
		fname = dir.get_next()
	dir.list_dir_end()
	if not query.strip_edges().is_empty():
		out = filter_route_pack_library(out, query)
	return sort_route_pack_library(out, sort_mode)


## Pass 38: export library index JSON (+ optional CSV). Returns primary JSON path or "".
func export_route_pack_library_index(
	json_path: String = "user://route_packs/_index.json",
	also_csv: bool = true
) -> String:
	_ensure_route_pack_library_dir()
	var entries: Array = list_route_pack_library("", "fav")
	var index := {
		"v": 1,
		"generated": Time.get_datetime_string_from_system(true),
		"count": entries.size(),
		"packs": entries,
	}
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		return ""
	jf.store_string(JSON.stringify(index, "\t"))
	jf.close()
	if also_csv:
		var csv_path := json_path.get_basename() + ".csv"
		if csv_path == json_path:
			csv_path = "user://route_packs/_index.csv"
		var cf := FileAccess.open(csv_path, FileAccess.WRITE)
		if cf != null:
			cf.store_line("name,bytes,mtime,favorite,group,tags,note")
			for e in entries:
				if not e is Dictionary:
					continue
				var ed: Dictionary = e
				var tags: Array = ed.get("tags", []) if ed.get("tags") is Array else []
				var tp: PackedStringArray = PackedStringArray()
				for tg in tags:
					tp.append(str(tg))
				var tag_join := "|".join(tp)
				var note_esc := str(ed.get("note", "")).replace("\"", "'").replace("\n", " ")
				cf.store_line("%s,%d,%d,%s,\"%s\",\"%s\",\"%s\"" % [
					str(ed.get("name", "")),
					int(ed.get("bytes", 0)),
					int(ed.get("mtime", 0)),
					"1" if bool(ed.get("favorite", false)) else "0",
					str(ed.get("group", "")),
					tag_join,
					note_esc,
				])
			cf.close()
	return json_path


## Pass 36–43/49: filter by name, #tag, @fav, @group, @groupor, @tagor.
## Tags default AND; @tagor / @tor ORs multiple #tags. Groups: @groupor ORs paths.
func filter_route_pack_library(entries: Array, query: String) -> Array:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return entries
	var tokens: Array = []
	for part in q.split(" "):
		var t := str(part).strip_edges()
		if not t.is_empty():
			tokens.append(t)
	if tokens.is_empty():
		return entries
	# Pass 43/49: OR modes for groups and tags.
	var group_or := false
	var tag_or := false
	var group_keys: Array = []  # collected @group: keys
	var tag_keys: Array = []  # collected #tags
	var other_tokens: Array = []
	for tok0 in tokens:
		var ts0 := str(tok0)
		if ts0 in ["@groupor", "@gor", "@or_groups", "@groups_or"]:
			group_or = true
			continue
		if ts0 in ["@tagor", "@tor", "@or_tags", "@tags_or"]:
			tag_or = true
			continue
		if ts0.begins_with("@group:") or ts0.begins_with("@g:"):
			var gk := ts0.substr(7) if ts0.begins_with("@group:") else ts0.substr(3)
			group_keys.append(gk)
			continue
		if ts0.begins_with("#"):
			var tk := ts0.substr(1)
			if not tk.is_empty():
				tag_keys.append(tk)
			continue
		other_tokens.append(ts0)
	var filtered: Array = []
	for e in entries:
		if not e is Dictionary:
			continue
		var ed: Dictionary = e
		var nm := str(ed.get("name", "")).to_lower()
		var note := str(ed.get("note", "")).to_lower()
		var group := str(ed.get("group", "")).to_lower()
		var tag_list: Array = ed.get("tags", []) if ed.get("tags") is Array else []
		var fav := bool(ed.get("favorite", false))
		var tag_parts: PackedStringArray = PackedStringArray()
		for tg in tag_list:
			tag_parts.append(str(tg).to_lower())
		var tag_join := " ".join(tag_parts)
		var match_tag_key := func(tkey: String) -> bool:
			for tg2 in tag_list:
				var tgl := str(tg2).to_lower()
				if tgl == tkey or tgl.contains(tkey):
					return true
			return false
		# Group path match helper.
		var match_group_key := func(gkey: String) -> bool:
			if gkey.is_empty():
				return group.is_empty()
			return _group_is_under(group, gkey)
		# Apply group filter(s).
		if not group_keys.is_empty():
			if group_or:
				var any_g := false
				for gk2 in group_keys:
					if match_group_key.call(str(gk2)):
						any_g = true
						break
				if not any_g:
					continue
			else:
				var all_g := true
				for gk3 in group_keys:
					if not match_group_key.call(str(gk3)):
						all_g = false
						break
				if not all_g:
					continue
		# Pass 49: apply tag filter(s) AND/OR.
		if not tag_keys.is_empty():
			if tag_or:
				var any_t := false
				for tk2 in tag_keys:
					if match_tag_key.call(str(tk2)):
						any_t = true
						break
				if not any_t:
					continue
			else:
				var all_t := true
				for tk3 in tag_keys:
					if not match_tag_key.call(str(tk3)):
						all_t = false
						break
				if not all_t:
					continue
		var ok_all := true
		for tok in other_tokens:
			var tok_s := str(tok)
			# Pass 39: favorites-only filter tokens.
			if tok_s in ["@fav", "@favorite", "@favorites", "★", ":fav"]:
				if not fav:
					ok_all = false
					break
				continue
			var key := tok_s
			if key.is_empty():
				continue
			var hit := nm.contains(key) or note.contains(key) or tag_join.contains(key) or group.contains(key)
			if not hit:
				ok_all = false
				break
		if ok_all:
			filtered.append(ed)
	return filtered


## Pass 39: bulk-apply tags (union or replace) to many pack stems. Returns count updated.
func bulk_tag_route_pack_library(names: Array, tags_str: String, replace: bool = false) -> int:
	var add_tags := _parse_pack_tags(tags_str)
	if add_tags.is_empty() and not replace:
		return 0
	var n := 0
	for name_v in names:
		var stem := _sanitize_pack_library_name(str(name_v))
		if stem.is_empty():
			continue
		# Only tag packs that exist as .eorp files.
		var path := ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
		if not FileAccess.file_exists(path):
			continue
		var cur := get_route_pack_library_tags(stem)
		var existing: Array = cur.get("tags", []) if cur.get("tags") is Array else []
		var note := str(cur.get("note", ""))
		var merged: Array = []
		var seen: Dictionary = {}
		if not replace:
			for t in existing:
				var ts := str(t).strip_edges().to_lower()
				if ts.is_empty() or seen.has(ts):
					continue
				seen[ts] = true
				merged.append(ts)
		for t2 in add_tags:
			var ts2 := str(t2).strip_edges().to_lower()
			if ts2.is_empty() or seen.has(ts2):
				continue
			seen[ts2] = true
			merged.append(ts2)
		if set_route_pack_library_tags(stem, merged, note):
			n += 1
	return n


## Pass 40: remove tags from many pack stems. Returns count updated.
## If tags_str empty → clear all tags on those packs.
func bulk_untag_route_pack_library(names: Array, tags_str: String = "") -> int:
	var remove_tags := _parse_pack_tags(tags_str)
	var clear_all := remove_tags.is_empty()
	var rem_set: Dictionary = {}
	for t in remove_tags:
		rem_set[str(t).to_lower()] = true
	var n := 0
	for name_v in names:
		var stem := _sanitize_pack_library_name(str(name_v))
		if stem.is_empty():
			continue
		var path := ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
		if not FileAccess.file_exists(path):
			continue
		var cur := get_route_pack_library_tags(stem)
		var existing: Array = cur.get("tags", []) if cur.get("tags") is Array else []
		var note := str(cur.get("note", ""))
		var kept: Array = []
		if not clear_all:
			for t in existing:
				var ts := str(t).strip_edges().to_lower()
				if ts.is_empty() or rem_set.has(ts):
					continue
				kept.append(ts)
		if set_route_pack_library_tags(stem, kept, note):
			n += 1
	return n


## Pass 40: bulk-set folder group on many packs. Returns count updated.
func bulk_group_route_pack_library(names: Array, group: String) -> int:
	var n := 0
	for name_v in names:
		var stem := _sanitize_pack_library_name(str(name_v))
		if stem.is_empty():
			continue
		var path := ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
		if not FileAccess.file_exists(path):
			continue
		if set_route_pack_library_group(stem, group):
			n += 1
	return n


## Pass 40/41: list unique groups with counts [{group, count, depth}] (nested paths).
func list_all_pack_library_groups() -> Array:
	var counts: Dictionary = {}
	for e in list_route_pack_library("", "mtime"):
		if not e is Dictionary:
			continue
		var g := _sanitize_pack_library_group(str((e as Dictionary).get("group", "")))
		counts[g] = int(counts.get(g, 0)) + 1
		# Ensure parent path nodes exist for tree headers even if empty of direct packs.
		var parent := _group_parent_path(g)
		while not parent.is_empty():
			if not counts.has(parent):
				counts[parent] = 0
			parent = _group_parent_path(parent)
	var out: Array = []
	for k in counts.keys():
		out.append({
			"group": str(k),
			"count": int(counts[k]),
			"depth": _group_depth(str(k)),
		})
	out.sort_custom(func(a, b) -> bool:
		var ga := str(a.get("group", ""))
		var gb := str(b.get("group", ""))
		# Ungrouped last
		if ga.is_empty() != gb.is_empty():
			return not ga.is_empty()
		return ga < gb
	)
	return out


const ROUTE_PACK_SEARCH_HISTORY_PATH := "user://route_packs/_search_history.json"
const ROUTE_PACK_SEARCH_HISTORY_MAX := 12


## Pass 41/43: normalize history entries to {q, pinned}. Accepts legacy string list.
func _normalize_search_history_entry(item: Variant) -> Dictionary:
	if item is Dictionary:
		var d: Dictionary = item
		return {
			"q": str(d.get("q", d.get("query", ""))).strip_edges(),
			"pinned": bool(d.get("pinned", d.get("favorite", false))),
		}
	return {"q": str(item).strip_edges(), "pinned": false}


## Pass 41/43: load recent searches [{q, pinned}] — pinned first, then newest.
func load_route_pack_search_history() -> Array:
	_ensure_route_pack_library_dir()
	if not FileAccess.file_exists(ROUTE_PACK_SEARCH_HISTORY_PATH):
		return []
	var f := FileAccess.open(ROUTE_PACK_SEARCH_HISTORY_PATH, FileAccess.READ)
	if f == null:
		return []
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(txt) != OK or not (p.data is Dictionary):
		return []
	var arr = (p.data as Dictionary).get("queries", [])
	if not arr is Array:
		return []
	var out: Array = []
	for item in arr as Array:
		var e := _normalize_search_history_entry(item)
		if str(e.get("q", "")).is_empty():
			continue
		out.append(e)
	# Pinned first.
	out.sort_custom(func(a, b) -> bool:
		var pa := 1 if bool(a.get("pinned", false)) else 0
		var pb := 1 if bool(b.get("pinned", false)) else 0
		if pa != pb:
			return pa > pb
		return false  # keep relative order for same pin state
	)
	return out


## Pass 41/43: push query onto history (dedupe; preserve pin; cap unpinned).
func push_route_pack_search_history(query: String) -> void:
	var q := query.strip_edges()
	if q.is_empty() or q.length() > 120:
		return
	var hist: Array = load_route_pack_search_history()
	var was_pinned := false
	for h in hist:
		var he := _normalize_search_history_entry(h)
		if str(he.get("q", "")) == q:
			was_pinned = bool(he.get("pinned", false))
			break
	var next: Array = [{"q": q, "pinned": was_pinned}]
	var unpinned_n := 0 if was_pinned else 1
	for h2 in hist:
		var he2 := _normalize_search_history_entry(h2)
		var hq := str(he2.get("q", ""))
		if hq.is_empty() or hq == q:
			continue
		var pin := bool(he2.get("pinned", false))
		if not pin:
			if unpinned_n >= ROUTE_PACK_SEARCH_HISTORY_MAX:
				continue
			unpinned_n += 1
		next.append({"q": hq, "pinned": pin})
	_save_route_pack_search_history(next)


## Pass 43: pin/unpin a history query. Returns new pinned state (false if missing).
func set_route_pack_search_history_pinned(query: String, pinned: bool) -> bool:
	var q := query.strip_edges()
	if q.is_empty():
		return false
	var hist: Array = load_route_pack_search_history()
	var found := false
	var next: Array = []
	for h in hist:
		var he := _normalize_search_history_entry(h)
		var hq := str(he.get("q", ""))
		if hq.is_empty():
			continue
		if hq == q:
			he["pinned"] = pinned
			found = true
		next.append(he)
	if not found:
		next.insert(0, {"q": q, "pinned": pinned})
	_save_route_pack_search_history(next)
	return pinned


## Pass 43: toggle pin on history query.
func toggle_route_pack_search_history_pinned(query: String) -> bool:
	var hist: Array = load_route_pack_search_history()
	var cur := false
	for h in hist:
		var he := _normalize_search_history_entry(h)
		if str(he.get("q", "")) == query.strip_edges():
			cur = bool(he.get("pinned", false))
			break
	return set_route_pack_search_history_pinned(query, not cur)


func _save_route_pack_search_history(entries: Array) -> void:
	_ensure_route_pack_library_dir()
	var f := FileAccess.open(ROUTE_PACK_SEARCH_HISTORY_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"v": 2, "queries": entries}))
	f.close()


## Pass 42: clear search history file. Returns true if cleared/written.
## Pass 43: keep_pinned=true retains starred history entries.
func clear_route_pack_search_history(keep_pinned: bool = false) -> bool:
	_ensure_route_pack_library_dir()
	var kept: Array = []
	if keep_pinned:
		for h in load_route_pack_search_history():
			var he := _normalize_search_history_entry(h)
			if bool(he.get("pinned", false)) and not str(he.get("q", "")).is_empty():
				kept.append(he)
	var f := FileAccess.open(ROUTE_PACK_SEARCH_HISTORY_PATH, FileAccess.WRITE)
	if f == null:
		var abs_p := ProjectSettings.globalize_path(ROUTE_PACK_SEARCH_HISTORY_PATH)
		return DirAccess.remove_absolute(abs_p) == OK
	f.store_string(JSON.stringify({"v": 2, "queries": kept}))
	f.close()
	return true


## Pass 45: export search history JSON (+ optional CSV). Returns primary JSON path or "".
func export_route_pack_search_history(
	json_path: String = "user://route_packs/_search_history_export.json",
	also_csv: bool = true
) -> String:
	_ensure_route_pack_library_dir()
	var hist: Array = load_route_pack_search_history()
	var payload := {
		"v": 1,
		"generated": Time.get_datetime_string_from_system(true),
		"count": hist.size(),
		"queries": hist,
	}
	var jf := FileAccess.open(json_path, FileAccess.WRITE)
	if jf == null:
		return ""
	jf.store_string(JSON.stringify(payload, "\t"))
	jf.close()
	if also_csv:
		var csv_path := json_path.get_basename() + ".csv"
		var cf := FileAccess.open(csv_path, FileAccess.WRITE)
		if cf != null:
			cf.store_line("query,pinned")
			for h in hist:
				var he := _normalize_search_history_entry(h)
				var q_esc := str(he.get("q", "")).replace("\"", "'")
				cf.store_line("\"%s\",%s" % [q_esc, "1" if bool(he.get("pinned", false)) else "0"])
			cf.close()
	return json_path


## Pass 46: import search history from JSON export (or live history file).
## merge_mode: union (default) | replace. Returns {ok, imported, skipped, path}.
func import_route_pack_search_history(
	json_path: String = "user://route_packs/_search_history_export.json",
	merge_mode: String = "union"
) -> Dictionary:
	if json_path.is_empty() or not FileAccess.file_exists(json_path):
		# Fallback to live history file shape.
		if FileAccess.file_exists(ROUTE_PACK_SEARCH_HISTORY_PATH):
			json_path = ROUTE_PACK_SEARCH_HISTORY_PATH
		else:
			return {"ok": false, "imported": 0, "skipped": 0, "path": json_path, "error": "missing"}
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "imported": 0, "skipped": 0, "path": json_path, "error": "open"}
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(txt) != OK or not (p.data is Dictionary):
		return {"ok": false, "imported": 0, "skipped": 0, "path": json_path, "error": "parse"}
	var root: Dictionary = p.data
	var arr = root.get("queries", [])
	if not arr is Array:
		return {"ok": false, "imported": 0, "skipped": 0, "path": json_path, "error": "empty"}
	var mode := merge_mode.strip_edges().to_lower()
	var incoming: Array = []
	for item in arr as Array:
		var he := _normalize_search_history_entry(item)
		if str(he.get("q", "")).is_empty():
			continue
		incoming.append(he)
	if incoming.is_empty():
		return {"ok": false, "imported": 0, "skipped": 0, "path": json_path, "error": "empty"}
	var next: Array = []
	var seen: Dictionary = {}
	var imported := 0
	if mode != "replace":
		for h in load_route_pack_search_history():
			var cur := _normalize_search_history_entry(h)
			var cq := str(cur.get("q", ""))
			if cq.is_empty() or seen.has(cq):
				continue
			seen[cq] = true
			next.append(cur)
	for he2 in incoming:
		var iq := str(he2.get("q", ""))
		if iq.is_empty():
			continue
		if seen.has(iq):
			# Union: pin if either side pinned.
			for i in next.size():
				if str((next[i] as Dictionary).get("q", "")) == iq:
					var pinned := bool((next[i] as Dictionary).get("pinned", false)) or bool(he2.get("pinned", false))
					next[i] = {"q": iq, "pinned": pinned}
					break
			continue
		seen[iq] = true
		next.append({"q": iq, "pinned": bool(he2.get("pinned", false))})
		imported += 1
	# Cap unpinned.
	var capped: Array = []
	var unpinned_n := 0
	for he3 in next:
		var pin3 := bool((he3 as Dictionary).get("pinned", false))
		if not pin3:
			if unpinned_n >= ROUTE_PACK_SEARCH_HISTORY_MAX:
				continue
			unpinned_n += 1
		capped.append(he3)
	_save_route_pack_search_history(capped)
	return {"ok": true, "imported": imported, "skipped": maxi(0, incoming.size() - imported), "path": json_path, "mode": mode, "total": capped.size()}


## Pass 42: world bounds for heatmap — prefer MapManager, else pin hull.
## Returns Rect2 (position = min corner, size = span). Empty size if unavailable.
func _heatmap_world_bounds(pin_pts: Array) -> Rect2:
	# Prefer live map world bounds.
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_world_bounds"):
		var wb: Rect2 = MapManager.get_world_bounds()
		if wb.size.x > 10.0 and wb.size.y > 10.0:
			return wb
	# Fallback: canonical world bounds (MapCanvasConfig).
	var cr: Rect2 = MapCanvasConfig.WORLD_CANONICAL_BOUNDS
	if cr.size.x > 10.0 and cr.size.y > 10.0:
		return cr
	# Last resort: pin bounding box.
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	var any := false
	for entry in pin_pts:
		if not entry is Dictionary:
			continue
		var pos: Vector2 = (entry as Dictionary).get("pos", Vector2.ZERO) as Vector2
		if pos == Vector2.ZERO:
			continue
		any = true
		min_x = minf(min_x, pos.x)
		min_y = minf(min_y, pos.y)
		max_x = maxf(max_x, pos.x)
		max_y = maxf(max_y, pos.y)
	if not any:
		return Rect2()
	var pad := 24.0
	return Rect2(min_x - pad, min_y - pad, max_x - min_x + pad * 2.0, max_y - min_y + pad * 2.0)


## Pass 41/42: export risk heatmap PNG from pack pins (MapManager geo bounds preferred).
## Returns user:// path or "".
func export_route_pack_risk_heatmap(path: String = "user://route_risk_heatmap.png", side: int = 256) -> String:
	var pins: Array = get_pack_slot_pins()
	if pins.is_empty():
		return ""
	var sz := clampi(side, 64, 512)
	var pts: Array = []
	for p in pins:
		if not p is Dictionary:
			continue
		var pos: Vector2 = (p as Dictionary).get("pos", Vector2.ZERO) as Vector2
		var risk := clampf(float((p as Dictionary).get("risk", 0.0)), 0.0, 1.0)
		if pos == Vector2.ZERO:
			continue
		pts.append({"pos": pos, "risk": risk})
	if pts.is_empty():
		return ""
	var bounds := _heatmap_world_bounds(pts)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return ""
	var min_x := bounds.position.x
	var min_y := bounds.position.y
	var wspan := maxf(bounds.size.x, 1.0)
	var hspan := maxf(bounds.size.y, 1.0)
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.08, 0.12, 1.0))
	# Soft falloff blobs per pin (risk → heat).
	for entry in pts:
		var e: Dictionary = entry
		var wp: Vector2 = e["pos"] as Vector2
		var risk_v: float = float(e["risk"])
		var nx := ((wp.x - min_x) / wspan) * float(sz - 1)
		var ny := ((wp.y - min_y) / hspan) * float(sz - 1)
		var cx := int(round(nx))
		var cy := int(round(ny))
		var rad := int(round(8.0 + risk_v * 14.0))
		var heat := Color(0.35, 0.85, 1.0, 1.0).lerp(Color(1.0, 0.25, 0.18, 1.0), risk_v)
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var px := cx + dx
				var py := cy + dy
				if px < 0 or py < 0 or px >= sz or py >= sz:
					continue
				var dist := sqrt(float(dx * dx + dy * dy))
				if dist > float(rad):
					continue
				var fall := 1.0 - dist / float(rad)
				fall = fall * fall
				var a := fall * (0.35 + risk_v * 0.55)
				var prev := img.get_pixel(px, py)
				var out_c := Color(
					clampf(prev.r + heat.r * a, 0.0, 1.0),
					clampf(prev.g + heat.g * a, 0.0, 1.0),
					clampf(prev.b + heat.b * a, 0.0, 1.0),
					1.0
				)
				img.set_pixel(px, py, out_c)
		# Core bright pixel.
		if cx >= 0 and cy >= 0 and cx < sz and cy < sz:
			img.set_pixel(cx, cy, Color(1.0, 0.95, 0.7, 1.0).lerp(Color(1.0, 0.4, 0.2, 1.0), risk_v))
	var abs_path := ProjectSettings.globalize_path(path)
	if img.save_png(abs_path) != OK:
		return ""
	return path


## Pass 39: import library index and merge metadata (tags/note/favorite) into sidecar.
## Does not create missing .eorp files. Returns {ok, merged, skipped, path}.
func import_route_pack_library_index(
	json_path: String = "user://route_packs/_index.json",
	merge_mode: String = "union"
) -> Dictionary:
	# merge_mode: union = keep local tags + add index tags; replace = index overwrites tags/note/fav
	if json_path.is_empty() or not FileAccess.file_exists(json_path):
		return {"ok": false, "merged": 0, "skipped": 0, "path": json_path, "error": "missing"}
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "merged": 0, "skipped": 0, "path": json_path, "error": "open"}
	var txt := f.get_as_text()
	f.close()
	var p := JSON.new()
	if p.parse(txt) != OK or not (p.data is Dictionary):
		return {"ok": false, "merged": 0, "skipped": 0, "path": json_path, "error": "parse"}
	var root: Dictionary = p.data
	var packs: Array = root.get("packs", []) if root.get("packs") is Array else []
	if packs.is_empty():
		return {"ok": false, "merged": 0, "skipped": 0, "path": json_path, "error": "empty"}
	var mode := merge_mode.strip_edges().to_lower()
	var merged := 0
	var skipped := 0
	var data := _load_pack_library_tags()
	for item in packs:
		if not item is Dictionary:
			skipped += 1
			continue
		var ed: Dictionary = item
		var stem := _sanitize_pack_library_name(str(ed.get("name", "")))
		if stem.is_empty():
			skipped += 1
			continue
		var eorp := ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
		if not FileAccess.file_exists(eorp):
			skipped += 1
			continue
		var idx_tags: Array = ed.get("tags", []) if ed.get("tags") is Array else []
		var idx_note := str(ed.get("note", ""))
		var idx_fav := bool(ed.get("favorite", false))
		var idx_group := _sanitize_pack_library_group(str(ed.get("group", "")))
		var local_tags: Array = []
		var local_note := ""
		var local_fav := false
		var local_group := ""
		if data.has(stem) and data[stem] is Dictionary:
			var le: Dictionary = data[stem]
			local_tags = le.get("tags", []) if le.get("tags") is Array else []
			local_note = str(le.get("note", ""))
			local_fav = bool(le.get("favorite", false))
			local_group = str(le.get("group", ""))
		var out_tags: Array = []
		var seen: Dictionary = {}
		if mode == "replace":
			for t in idx_tags:
				var ts := str(t).strip_edges().to_lower()
				if ts.is_empty() or seen.has(ts):
					continue
				seen[ts] = true
				out_tags.append(ts)
			data[stem] = {
				"tags": out_tags,
				"note": idx_note if not idx_note.is_empty() else local_note,
				"favorite": idx_fav,
				"group": idx_group if not idx_group.is_empty() else local_group,
			}
		else:
			# union (default): local tags + index tags; note keeps non-empty preferred local then index
			for t in local_tags:
				var ts2 := str(t).strip_edges().to_lower()
				if ts2.is_empty() or seen.has(ts2):
					continue
				seen[ts2] = true
				out_tags.append(ts2)
			for t3 in idx_tags:
				var ts3 := str(t3).strip_edges().to_lower()
				if ts3.is_empty() or seen.has(ts3):
					continue
				seen[ts3] = true
				out_tags.append(ts3)
			var note_out := local_note if not local_note.is_empty() else idx_note
			var group_out := local_group if not local_group.is_empty() else idx_group
			data[stem] = {
				"tags": out_tags,
				"note": note_out,
				"favorite": local_fav or idx_fav,
				"group": group_out,
			}
		merged += 1
	if not _save_pack_library_tags(data):
		return {"ok": false, "merged": merged, "skipped": skipped, "path": json_path, "error": "save"}
	return {"ok": true, "merged": merged, "skipped": skipped, "path": json_path, "mode": mode}


## Pass 35/36: save current pack share into library as `name`.eorp (+ optional tags). Returns path or "".
func save_route_pack_to_library(name: String, include_history: bool = true, tags_str: String = "", note: String = "") -> String:
	var code := export_route_pack_share_code(include_history, true)
	if code.is_empty():
		return ""
	_ensure_route_pack_library_dir()
	var stem := _sanitize_pack_library_name(name)
	var path := ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(code)
	f.close()
	# Pass 36: attach tags.
	var tags := _parse_pack_tags(tags_str)
	set_route_pack_library_tags(stem, tags, note)
	# Also mirror to default share path for Shift+Import compatibility.
	export_route_pack_share_file(include_history, true)
	return path


## Pass 35: load pack from library by stem name or full path.
func load_route_pack_from_library(name_or_path: String) -> bool:
	var path := name_or_path.strip_edges()
	if path.is_empty():
		return false
	if not path.begins_with("user://") and not path.begins_with("res://") and not path.begins_with("/"):
		path = ROUTE_PACK_LIBRARY_DIR + _sanitize_pack_library_name(path) + ".eorp"
	elif not path.ends_with(".eorp") and not FileAccess.file_exists(path):
		path = ROUTE_PACK_LIBRARY_DIR + _sanitize_pack_library_name(path.get_file().get_basename()) + ".eorp"
	return import_route_pack_share_file(path)


## Pass 35/36: delete library entry by stem name (+ tags). Returns true if removed.
func delete_route_pack_from_library(name: String) -> bool:
	var stem := _sanitize_pack_library_name(name)
	var path := ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
	if not FileAccess.file_exists(path):
		return false
	var abs_path := ProjectSettings.globalize_path(path)
	var err := DirAccess.remove_absolute(abs_path)
	if err == OK:
		var data := _load_pack_library_tags()
		if data.has(stem):
			data.erase(stem)
			_save_pack_library_tags(data)
	return err == OK


## Pass 36: peek pack file → summary dict without applying compare.
## {ok, name, routes, risk_a..d, hops_a..d, owners, tags, note}
func peek_route_pack_library(name_or_path: String) -> Dictionary:
	var path := name_or_path.strip_edges()
	if path.is_empty():
		return {"ok": false}
	var stem := path
	if not path.begins_with("user://") and not path.begins_with("res://") and not path.begins_with("/"):
		stem = _sanitize_pack_library_name(path)
		path = ROUTE_PACK_LIBRARY_DIR + stem + ".eorp"
	else:
		stem = path.get_file().get_basename()
	if not FileAccess.file_exists(path):
		return {"ok": false, "name": stem}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "name": stem}
	var code := f.get_as_text().strip_edges()
	f.close()
	var payload := _decode_route_pack_share_payload(code)
	if payload.is_empty():
		return {"ok": false, "name": stem}
	var tags_info := get_route_pack_library_tags(stem)
	var nroutes := 2
	if (payload.get("path_d", []) as Array).size() >= 2:
		nroutes = 4
	elif (payload.get("path_c", []) as Array).size() >= 2:
		nroutes = 3
	return {
		"ok": true,
		"name": stem,
		"routes": nroutes,
		"risk_a": float(payload.get("risk_a", 0.0)),
		"risk_b": float(payload.get("risk_b", 0.0)),
		"risk_c": float(payload.get("risk_c", 0.0)),
		"risk_d": float(payload.get("risk_d", 0.0)),
		"hops_a": (payload.get("path_a", []) as Array).size(),
		"hops_b": (payload.get("path_b", []) as Array).size(),
		"hops_c": (payload.get("path_c", []) as Array).size(),
		"hops_d": (payload.get("path_d", []) as Array).size(),
		"owner_a": str(payload.get("owner_a", "")),
		"owner_b": str(payload.get("owner_b", "")),
		"tags": tags_info.get("tags", []),
		"note": str(tags_info.get("note", "")),
		"path_a": payload.get("path_a", []),
		"path_b": payload.get("path_b", []),
		"path_c": payload.get("path_c", []),
		"path_d": payload.get("path_d", []),
	}


## Pass 36: decode share code to payload dict (no side effects). Empty on failure.
func _decode_route_pack_share_payload(code: String) -> Dictionary:
	var s := code.strip_edges()
	var compact := false
	if s.begins_with("EORP3."):
		s = s.substr(6)
		compact = true
	elif s.begins_with("EORP2."):
		s = s.substr(6)
	elif s.begins_with("EORP1."):
		s = s.substr(6)
	elif "EORP3." in s:
		s = s.substr(s.find("EORP3.") + 6)
		compact = true
	elif "EORP2." in s:
		s = s.substr(s.find("EORP2.") + 6)
	elif "EORP1." in s:
		s = s.substr(s.find("EORP1.") + 6)
	var json_s := ""
	if compact:
		var zipped := Marshalls.base64_to_raw(s)
		if zipped.is_empty():
			return {}
		var raw := zipped.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
		if raw.is_empty():
			return {}
		json_s = raw.get_string_from_utf8()
	else:
		json_s = Marshalls.base64_to_utf8(s)
	if json_s.is_empty():
		return {}
	var p := JSON.new()
	if p.parse(json_s) != OK or not (p.data is Dictionary):
		return {}
	var d: Dictionary = p.data
	var ver_payload := int(d.get("v", 1))
	if ver_payload >= 3:
		compact = true
	var path_a: Array
	var path_b: Array
	var path_c: Array
	var path_d: Array
	if compact:
		path_a = _path_delta_decode(d.get("a", []) as Array if d.get("a") is Array else [])
		path_b = _path_delta_decode(d.get("b", []) as Array if d.get("b") is Array else [])
		path_c = _path_delta_decode(d.get("c", []) as Array if d.get("c") is Array else [])
		path_d = _path_delta_decode(d.get("d", []) as Array if d.get("d") is Array else [])
	else:
		path_a = d.get("a", []) as Array if d.get("a") is Array else []
		path_b = d.get("b", []) as Array if d.get("b") is Array else []
		path_c = d.get("c", []) as Array if d.get("c") is Array else []
		path_d = d.get("d", []) as Array if d.get("d") is Array else []
	if path_a.is_empty() or path_b.is_empty():
		return {}
	var ra := float(d.get("ra", 0.0))
	var rb := float(d.get("rb", 0.0))
	var rc := float(d.get("rc", 0.0))
	var rd := float(d.get("rd", 0.0))
	if compact or ra > 1.5:
		ra = clampf(ra / 100.0, 0.0, 1.0)
		rb = clampf(rb / 100.0, 0.0, 1.0)
		rc = clampf(rc / 100.0, 0.0, 1.0)
		rd = clampf(rd / 100.0, 0.0, 1.0)
	return {
		"path_a": path_a,
		"path_b": path_b,
		"path_c": path_c,
		"path_d": path_d,
		"risk_a": ra,
		"risk_b": rb,
		"risk_c": rc,
		"risk_d": rd,
		"owner_a": str(d.get("oa", "")),
		"owner_b": str(d.get("ob", "")),
		"owner_c": str(d.get("oc", "")),
		"owner_d": str(d.get("od", "")),
		"focus_a": int(d.get("fa", -1)),
		"focus_b": int(d.get("fb", -1)),
		"focus_c": int(d.get("fc", -1)),
		"focus_d": int(d.get("fd", -1)),
	}


## Pass 36: dual-pane library compare — Left pack → A/B, Right pack → C/D.
## Returns number of routes packed (0 if fail).
func compare_library_packs(name_left: String, name_right: String) -> int:
	var left := peek_route_pack_library(name_left)
	var right := peek_route_pack_library(name_right)
	if not bool(left.get("ok", false)) or not bool(right.get("ok", false)):
		return 0
	var la: Array = left.get("path_a", []) as Array if left.get("path_a") is Array else []
	var lb: Array = left.get("path_b", []) as Array if left.get("path_b") is Array else []
	var ra: Array = right.get("path_a", []) as Array if right.get("path_a") is Array else []
	var rb: Array = right.get("path_b", []) as Array if right.get("path_b") is Array else []
	if la.size() < 2 or ra.size() < 2:
		return 0
	var paths: Array = []
	var metas: Array = []
	# Route A from left.
	paths.append(la.duplicate())
	metas.append({
		"interdiction": float(left.get("risk_a", 0.0)),
		"focus_pid": int(la[la.size() - 1]),
		"owner_tag": str(left.get("owner_a", "")),
	})
	# Route B: prefer left B, else right A (still need ≥2 before C).
	if lb.size() >= 2:
		paths.append(lb.duplicate())
		metas.append({
			"interdiction": float(left.get("risk_b", 0.0)),
			"focus_pid": int(lb[lb.size() - 1]),
			"owner_tag": str(left.get("owner_b", "")),
		})
		# C = right A, D = right B
		paths.append(ra.duplicate())
		metas.append({
			"interdiction": float(right.get("risk_a", 0.0)),
			"focus_pid": int(ra[ra.size() - 1]),
			"owner_tag": str(right.get("owner_a", "")),
		})
		if rb.size() >= 2:
			paths.append(rb.duplicate())
			metas.append({
				"interdiction": float(right.get("risk_b", 0.0)),
				"focus_pid": int(rb[rb.size() - 1]),
				"owner_tag": str(right.get("owner_b", "")),
			})
	else:
		# Left only A: B/C from right A/B
		paths.append(ra.duplicate())
		metas.append({
			"interdiction": float(right.get("risk_a", 0.0)),
			"focus_pid": int(ra[ra.size() - 1]),
			"owner_tag": str(right.get("owner_a", "")),
		})
		if rb.size() >= 2:
			paths.append(rb.duplicate())
			metas.append({
				"interdiction": float(right.get("risk_b", 0.0)),
				"focus_pid": int(rb[rb.size() - 1]),
				"owner_tag": str(right.get("owner_b", "")),
			})
	if paths.size() < 2:
		return 0
	compare_supply_routes_multi(paths, metas)
	_notify_minimap_pack_pins()
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Lib compare · %s | %s · %d routes" % [
			str(left.get("name", "?")), str(right.get("name", "?")), paths.size()
		])
	return paths.size()


## Pass 35: share + QR toast/popup (compact preview after Share).
func _show_share_with_qr_toast(code: String, prefix: String) -> void:
	if code.is_empty():
		return
	# Generate QR for preview (also updates user://route_pack_qr.png).
	var qr_path := "user://route_pack_qr.png"
	var engine_path: String = RoutePackQRScr.encode_to_user_png(code, qr_path, -1, 2)
	if engine_path.is_empty():
		# Fallback try full export path (may use qrencode).
		export_route_pack_qr_png(true)
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Share %s · %d chars" % [prefix, code.length()])
		return
	var old := ui.get_node_or_null("ShareQRToast")
	if old != null:
		old.queue_free()
	var panel := PanelContainer.new()
	panel.name = "ShareQRToast"
	RetrowaveTheme.style_world_panel(panel)
	ui.add_child(panel)
	var c := panel as Control
	c.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	c.offset_left = -130.0
	c.offset_right = 130.0
	c.offset_top = -210.0
	c.offset_bottom = -16.0
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Shared %s · %d chars" % [prefix, code.length()]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	vbox.add_child(title)
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(140, 140)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if FileAccess.file_exists(qr_path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(qr_path))
		if img != null:
			tex_rect.texture = ImageTexture.create_from_image(img)
	vbox.add_child(tex_rect)
	var hint := Label.new()
	hint.text = "Clipboard + QR preview"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	vbox.add_child(hint)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	RetrowaveTheme.style_secondary_button(close_btn)
	close_btn.pressed.connect(func() -> void:
		panel.queue_free()
	)
	vbox.add_child(close_btn)
	# Auto-dismiss after a few seconds.
	get_tree().create_timer(6.0).timeout.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
	)


## Pass 35–37/50: pack library browser — search, tags, dual-pane; Shift = second window.
func _show_pack_library_popup(include_history: bool = true, force_new: bool = false) -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var popup_name := "PackLibraryPopup"
	var window_idx := 1
	if force_new:
		window_idx = 2
		while ui.get_node_or_null("PackLibraryPopup_%d" % window_idx) != null:
			window_idx += 1
		popup_name = "PackLibraryPopup_%d" % window_idx
	else:
		var old := ui.get_node_or_null("PackLibraryPopup")
		if old != null:
			old.queue_free()
	var panel := PanelContainer.new()
	panel.name = popup_name
	RetrowaveTheme.style_world_panel(panel)
	ui.add_child(panel)
	var c := panel as Control
	# Seed size + dock from prefs (Pass 50/51/53 per-window dock).
	var lib_sz := load_pack_risk_heat_prefs()
	var lib_w := clampf(float(lib_sz.get("library_w", 600.0)), 400.0, 1200.0)
	var lib_h := clampf(float(lib_sz.get("library_h", 560.0)), 360.0, 1000.0)
	var shift_xy := float(window_idx - 1) * 36.0
	var cur_dock := get_library_dock_for_window(window_idx)
	var lib_opacity := get_library_opacity_for_window(window_idx)
	_apply_library_dock_layout(c, cur_dock, lib_w, lib_h, shift_xy)
	c.modulate = Color(1, 1, 1, lib_opacity)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "Pack library" + (" · %d" % window_idx if window_idx > 1 else "")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.tooltip_text = "Drag to move (float). Drop near screen edge to dock left/right/bottom."
	RetrowaveTheme.style_body_label(title)
	title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	vbox.add_child(title)
	# Pass 57/58: per-window library theme chrome.
	var cur_theme := get_library_theme_for_window(window_idx)
	apply_library_theme_to_panel(panel, title, cur_theme)
	# Pass 51: title drag move + edge snap dock.
	var title_drag: Array = [false, Vector2.ZERO, Vector2.ZERO]  # dragging, start_mouse, start_pos
	title.gui_input.connect(func(ev_t: InputEvent) -> void:
		if ev_t is InputEventMouseButton and ev_t.button_index == MOUSE_BUTTON_LEFT:
			if ev_t.pressed:
				title_drag[0] = true
				title_drag[1] = ev_t.global_position
				title_drag[2] = c.position
				title.accept_event()
			else:
				if bool(title_drag[0]):
					title_drag[0] = false
					# Edge snap → dock.
					var vp_s := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
					var mp := title.get_global_mouse_position()
					var new_dock := "float"
					if mp.x < 48.0:
						new_dock = "left"
					elif mp.x > vp_s.x - 48.0:
						new_dock = "right"
					elif mp.y > vp_s.y - 48.0:
						new_dock = "bottom"
					cur_dock = new_dock
					var w_now := maxf(absf(c.offset_right - c.offset_left), lib_w)
					var h_now := maxf(absf(c.offset_bottom - c.offset_top), lib_h)
					if new_dock == "float":
						# Keep free position via anchors top-left after drag.
						pass
					else:
						_apply_library_dock_layout(c, new_dock, w_now, h_now, shift_xy)
					set_library_dock_for_window(window_idx, cur_dock)
					if typeof(DebugOverlay) != TYPE_NIL:
						DebugOverlay.toast_map_debug("Library dock · %s · win %d" % [cur_dock, window_idx])
				title.accept_event()
		elif ev_t is InputEventMouseMotion and bool(title_drag[0]):
			# Float drag: switch to top-left anchors and move.
			if cur_dock != "float":
				cur_dock = "float"
				c.set_anchors_preset(Control.PRESET_TOP_LEFT)
				c.offset_left = c.position.x
				c.offset_top = c.position.y
				c.offset_right = c.position.x + lib_w
				c.offset_bottom = c.position.y + lib_h
			var delta_t: Vector2 = ev_t.global_position - (title_drag[1] as Vector2)
			var base_p: Vector2 = title_drag[2] as Vector2
			c.position = base_p + delta_t
			title.accept_event()
	)
	var path_lbl := Label.new()
	path_lbl.text = ROUTE_PACK_LIBRARY_DIR + "  ·  nested groups · history · heatmap"
	path_lbl.add_theme_font_size_override("font_size", 9)
	path_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(path_lbl)
	# Pass 48/51: library layout presets + dock mode.
	var layout_row := HBoxContainer.new()
	layout_row.add_theme_constant_override("separation", 4)
	vbox.add_child(layout_row)
	var layout_cap := Label.new()
	layout_cap.text = "Layout"
	layout_cap.add_theme_font_size_override("font_size", 9)
	layout_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	layout_row.add_child(layout_cap)
	var layout_opt := OptionButton.new()
	layout_opt.focus_mode = Control.FOCUS_NONE
	layout_opt.add_theme_font_size_override("font_size", 9)
	layout_opt.tooltip_text = "Library layout · Ctrl+1 standard · Ctrl+2 compact · Ctrl+3 wide · Ctrl+4 left"
	var layout_ids: PackedStringArray = PACK_LIBRARY_LAYOUTS
	for li in layout_ids.size():
		layout_opt.add_item(str(layout_ids[li]), li)
	var lib_prefs0 := load_pack_risk_heat_prefs()
	var cur_layout := str(lib_prefs0.get("library_layout", "standard"))
	var layout_idx0 := layout_ids.find(cur_layout)
	layout_opt.select(layout_idx0 if layout_idx0 >= 0 else 0)
	layout_row.add_child(layout_opt)
	# Forward ref for layout application (filled after dual lists; used by chrome import).
	var apply_lib_layout_ref: Array = [null]  # [Callable]
	# Pass 51: dock mode selector.
	var dock_cap := Label.new()
	dock_cap.text = "Dock"
	dock_cap.add_theme_font_size_override("font_size", 9)
	dock_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	layout_row.add_child(dock_cap)
	var dock_opt := OptionButton.new()
	dock_opt.focus_mode = Control.FOCUS_NONE
	dock_opt.add_theme_font_size_override("font_size", 9)
	dock_opt.tooltip_text = "Dock · Ctrl+Shift+← left · → right · ↓ bottom · ↑ float"
	var dock_ids: PackedStringArray = PACK_LIBRARY_DOCKS
	for di in dock_ids.size():
		dock_opt.add_item(str(dock_ids[di]), di)
	var dock_idx0 := dock_ids.find(cur_dock)
	dock_opt.select(dock_idx0 if dock_idx0 >= 0 else 0)
	layout_row.add_child(dock_opt)
	var apply_dock_choice := func(dd: String) -> void:
		var ddx := dd.strip_edges().to_lower()
		if ddx not in dock_ids:
			ddx = "float"
		cur_dock = ddx
		var di_sel := dock_ids.find(ddx)
		if di_sel >= 0:
			dock_opt.select(di_sel)
		var w_d := maxf(absf(c.offset_right - c.offset_left), lib_w)
		var h_d := maxf(absf(c.offset_bottom - c.offset_top), lib_h)
		_apply_library_dock_layout(c, ddx, w_d, h_d, shift_xy)
		set_library_dock_for_window(window_idx, ddx)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Library dock · %s · win %d" % [ddx, window_idx])
	dock_opt.item_selected.connect(func(idx_d: int) -> void:
		var dd := str(dock_ids[idx_d]) if idx_d >= 0 and idx_d < dock_ids.size() else "float"
		apply_dock_choice.call(dd)
	)
	# Pass 54: library panel opacity.
	var opac_cap := Label.new()
	opac_cap.text = "α"
	opac_cap.add_theme_font_size_override("font_size", 9)
	opac_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	layout_row.add_child(opac_cap)
	var opac_slider := HSlider.new()
	opac_slider.min_value = 0.35
	opac_slider.max_value = 1.0
	opac_slider.step = 0.05
	opac_slider.custom_minimum_size = Vector2(56, 16)
	opac_slider.value = lib_opacity
	opac_slider.tooltip_text = "Library panel opacity for this window (persisted per-window)"
	opac_slider.value_changed.connect(func(ov: float) -> void:
		var m_o := c.modulate
		m_o.a = ov
		c.modulate = m_o
		set_library_opacity_for_window(window_idx, ov)
	)
	layout_row.add_child(opac_slider)
	# Pass 56: link opacity across all library windows.
	var link_op_chk := CheckBox.new()
	link_op_chk.text = "Link α"
	link_op_chk.focus_mode = Control.FOCUS_NONE
	link_op_chk.add_theme_font_size_override("font_size", 9)
	link_op_chk.button_pressed = get_library_opacity_link_all()
	link_op_chk.tooltip_text = "When on, opacity changes apply to all library windows"
	layout_row.add_child(link_op_chk)
	link_op_chk.toggled.connect(func(on_l: bool) -> void:
		set_library_opacity_link_all(on_l)
		if on_l:
			set_library_opacity_for_window(window_idx, opac_slider.value)
			_apply_library_opacity_to_open_windows(opac_slider.value)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Library opacity link · %s" % ("ON" if on_l else "OFF"))
	)
	# Pass 57/58: per-window library theme + preset file.
	var theme_cap := Label.new()
	theme_cap.text = "Theme"
	theme_cap.add_theme_font_size_override("font_size", 9)
	theme_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	layout_row.add_child(theme_cap)
	var theme_opt := OptionButton.new()
	theme_opt.focus_mode = Control.FOCUS_NONE
	theme_opt.add_theme_font_size_override("font_size", 9)
	theme_opt.tooltip_text = "Library chrome theme (per-window). Includes custom presets from theme file."
	var rebuild_theme_opt := func() -> void:
		while theme_opt.item_count > 0:
			theme_opt.remove_item(0)
		var presets_m := get_library_theme_presets()
		var keys: Array = []
		for bk in PACK_LIBRARY_THEMES:
			keys.append(str(bk))
		for pk in presets_m.keys():
			var pks := str(pk)
			if not keys.has(pks):
				keys.append(pks)
		for ti in keys.size():
			theme_opt.add_item(str(keys[ti]), ti)
			theme_opt.set_item_metadata(ti, str(keys[ti]))
		var want := get_library_theme_for_window(window_idx)
		var found := 0
		for ti2 in theme_opt.item_count:
			if str(theme_opt.get_item_metadata(ti2)) == want:
				found = ti2
				break
		theme_opt.select(found)
	rebuild_theme_opt.call()
	layout_row.add_child(theme_opt)
	theme_opt.item_selected.connect(func(idx_t: int) -> void:
		var tid := str(theme_opt.get_item_metadata(idx_t)) if idx_t >= 0 else "classic"
		tid = _normalize_library_theme(tid)
		set_library_theme_for_window(window_idx, tid)
		apply_library_theme_to_panel(panel, title, tid)
		c.modulate.a = opac_slider.value
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Library theme · %s · win %d" % [tid, window_idx])
	)
	# Pass 58/59/60: theme preset file + color pickers/share (refs for lambda order).
	var sync_theme_picks_ref: Array = [Callable()]
	var theme_name_edit_ref: Array = [null]  # LineEdit filled after create
	var theme_file_btn := Button.new()
	theme_file_btn.text = "Theme File"
	theme_file_btn.focus_mode = Control.FOCUS_NONE
	theme_file_btn.add_theme_font_size_override("font_size", 9)
	theme_file_btn.tooltip_text = "Export built-in theme presets. Ctrl/Alt = import preset file."
	RetrowaveTheme.style_secondary_button(theme_file_btn)
	layout_row.add_child(theme_file_btn)
	theme_file_btn.pressed.connect(func() -> void:
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT):
			var fd_t := FileDialog.new()
			fd_t.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			fd_t.access = FileDialog.ACCESS_FILESYSTEM
			fd_t.use_native_dialog = true
			fd_t.title = "Import library theme presets"
			fd_t.current_dir = ProjectSettings.globalize_path("user://route_packs")
			fd_t.add_filter("*.json", "Theme presets JSON")
			panel.add_child(fd_t)
			fd_t.file_selected.connect(func(p_t: String) -> void:
				var n_t := load_library_theme_presets_file(p_t)
				rebuild_theme_opt.call()
				var tid_fi := get_library_theme_for_window(window_idx)
				apply_library_theme_to_panel(panel, title, tid_fi)
				c.modulate.a = opac_slider.value
				var te_fi = theme_name_edit_ref[0]
				if te_fi is LineEdit and is_instance_valid(te_fi):
					(te_fi as LineEdit).text = tid_fi
				if sync_theme_picks_ref[0] is Callable:
					(sync_theme_picks_ref[0] as Callable).call()
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug(
						"Theme presets · %d themes" % n_t if n_t > 0 else "Theme import failed"
					)
				if is_instance_valid(fd_t):
					fd_t.queue_free()
			)
			fd_t.canceled.connect(func() -> void:
				if is_instance_valid(fd_t):
					fd_t.queue_free()
			)
			fd_t.popup()
		else:
			var path_t := save_library_theme_presets_file()
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"Theme presets · %s" % path_t if not path_t.is_empty() else "Theme export failed"
				)
	)
	# Pass 59: theme color pickers + save-as + EOTM1 share.
	var theme_edit_row := HBoxContainer.new()
	theme_edit_row.add_theme_constant_override("separation", 4)
	vbox.add_child(theme_edit_row)
	var theme_mod_cap := Label.new()
	theme_mod_cap.text = "Chrome"
	theme_mod_cap.add_theme_font_size_override("font_size", 9)
	theme_mod_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	theme_edit_row.add_child(theme_mod_cap)
	var theme_mod_pick := ColorPickerButton.new()
	theme_mod_pick.focus_mode = Control.FOCUS_NONE
	theme_mod_pick.custom_minimum_size = Vector2(28, 20)
	theme_mod_pick.tooltip_text = "Library panel chrome/modulate color (edit + Save Theme)"
	theme_edit_row.add_child(theme_mod_pick)
	var theme_title_cap := Label.new()
	theme_title_cap.text = "Title"
	theme_title_cap.add_theme_font_size_override("font_size", 9)
	theme_title_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	theme_edit_row.add_child(theme_title_cap)
	var theme_title_pick := ColorPickerButton.new()
	theme_title_pick.focus_mode = Control.FOCUS_NONE
	theme_title_pick.custom_minimum_size = Vector2(28, 20)
	theme_title_pick.tooltip_text = "Library title accent color (edit + Save Theme)"
	theme_edit_row.add_child(theme_title_pick)
	var sync_theme_picks := func() -> void:
		var tid_s := get_library_theme_for_window(window_idx)
		var presets_s := get_library_theme_presets()
		var mod_s := Color(1, 1, 1, 1)
		var title_s := RetrowaveTheme.CYAN
		if presets_s.has(tid_s) and presets_s[tid_s] is Dictionary:
			var pe_s: Dictionary = presets_s[tid_s]
			if pe_s.get("modulate") is Color:
				mod_s = pe_s.get("modulate") as Color
			if pe_s.get("title") is Color:
				title_s = pe_s.get("title") as Color
		theme_mod_pick.color = Color(mod_s.r, mod_s.g, mod_s.b, 1.0)
		theme_title_pick.color = Color(title_s.r, title_s.g, title_s.b, 1.0)
	sync_theme_picks_ref[0] = sync_theme_picks
	var live_apply_theme_picks := func() -> void:
		var a_live := c.modulate.a
		var m_live := theme_mod_pick.color
		m_live.a = a_live
		c.modulate = m_live
		title.add_theme_color_override("font_color", theme_title_pick.color)
	theme_mod_pick.color_changed.connect(func(_mc: Color) -> void:
		live_apply_theme_picks.call()
	)
	theme_title_pick.color_changed.connect(func(_tc: Color) -> void:
		live_apply_theme_picks.call()
	)
	# Pass 60/61: typed theme name + autocomplete from presets.
	var theme_name_edit := LineEdit.new()
	theme_name_edit.placeholder_text = "theme id"
	theme_name_edit.custom_minimum_size = Vector2(72, 20)
	theme_name_edit.add_theme_font_size_override("font_size", 9)
	theme_name_edit.tooltip_text = "Theme id for Save (a–z 0–9 _ -). Autocomplete from presets. Empty = current."
	theme_name_edit.text = get_library_theme_for_window(window_idx)
	theme_edit_row.add_child(theme_name_edit)
	theme_name_edit_ref[0] = theme_name_edit
	var theme_ac_menu := PopupMenu.new()
	theme_ac_menu.name = "ThemeIdAutocomplete"
	panel.add_child(theme_ac_menu)
	var theme_ac_guard: Array = [false]  # suppress text_changed while applying pick
	var theme_ac_idx: Array = [0]  # highlighted row in popup
	var theme_ac_matches: Array = [[]]  # last match list [PackedStringArray-as-Array]
	var apply_theme_ac_pick := func(pick: String) -> void:
		if pick.is_empty():
			return
		theme_ac_guard[0] = true
		theme_name_edit.text = pick
		theme_ac_guard[0] = false
		theme_ac_menu.hide()
		set_library_theme_for_window(window_idx, pick)
		for ti_ac in theme_opt.item_count:
			if str(theme_opt.get_item_metadata(ti_ac)) == pick:
				theme_opt.select(ti_ac)
				break
		apply_library_theme_to_panel(panel, title, pick)
		c.modulate.a = opac_slider.value
		sync_theme_picks.call()
	var show_theme_ac := func(q: String) -> void:
		if theme_ac_guard[0]:
			return
		var matches := list_library_theme_id_matches(q, 12)
		theme_ac_matches[0] = matches
		theme_ac_menu.clear()
		if matches.is_empty():
			theme_ac_menu.hide()
			return
		for mi in matches.size():
			theme_ac_menu.add_item(str(matches[mi]), mi)
		theme_ac_idx[0] = clampi(int(theme_ac_idx[0]), 0, matches.size() - 1)
		if theme_ac_menu.has_method("set_focused_item"):
			theme_ac_menu.set_focused_item(int(theme_ac_idx[0]))
		var gp := theme_name_edit.get_global_position()
		var sz := theme_name_edit.size
		theme_ac_menu.position = Vector2i(int(gp.x), int(gp.y + sz.y))
		theme_ac_menu.size = Vector2i(maxi(int(sz.x), 100), 0)
		theme_ac_menu.popup()
	theme_name_edit.text_changed.connect(func(nt: String) -> void:
		theme_ac_idx[0] = 0
		show_theme_ac.call(nt)
	)
	theme_name_edit.focus_entered.connect(func() -> void:
		show_theme_ac.call(theme_name_edit.text)
	)
	# Pass 62: ↑↓ Enter Esc keyboard nav while LineEdit focused.
	theme_name_edit.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventKey and ev.pressed and not ev.echo):
			return
		var k: InputEventKey = ev
		var matches_k = theme_ac_matches[0]
		var n_m := 0
		if matches_k is PackedStringArray:
			n_m = (matches_k as PackedStringArray).size()
		elif matches_k is Array:
			n_m = (matches_k as Array).size()
		if k.keycode == KEY_ESCAPE:
			if theme_ac_menu.visible:
				theme_ac_menu.hide()
				theme_name_edit.accept_event()
			return
		if n_m <= 0:
			return
		if k.keycode == KEY_DOWN:
			if not theme_ac_menu.visible:
				show_theme_ac.call(theme_name_edit.text)
			theme_ac_idx[0] = (int(theme_ac_idx[0]) + 1) % n_m
			if theme_ac_menu.has_method("set_focused_item"):
				theme_ac_menu.set_focused_item(int(theme_ac_idx[0]))
			theme_name_edit.accept_event()
		elif k.keycode == KEY_UP:
			if not theme_ac_menu.visible:
				show_theme_ac.call(theme_name_edit.text)
			theme_ac_idx[0] = (int(theme_ac_idx[0]) - 1 + n_m) % n_m
			if theme_ac_menu.has_method("set_focused_item"):
				theme_ac_menu.set_focused_item(int(theme_ac_idx[0]))
			theme_name_edit.accept_event()
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			var pick_k := ""
			if matches_k is PackedStringArray:
				var psa: PackedStringArray = matches_k
				var ii := clampi(int(theme_ac_idx[0]), 0, psa.size() - 1)
				pick_k = str(psa[ii])
			elif matches_k is Array:
				var arr: Array = matches_k
				var ii2 := clampi(int(theme_ac_idx[0]), 0, arr.size() - 1)
				pick_k = str(arr[ii2])
			if not pick_k.is_empty():
				apply_theme_ac_pick.call(pick_k)
				theme_name_edit.accept_event()
	)
	theme_ac_menu.id_pressed.connect(func(mid: int) -> void:
		theme_ac_idx[0] = mid
		var pick := theme_ac_menu.get_item_text(mid)
		apply_theme_ac_pick.call(pick)
	)
	# Pass 63: mouse hover / focus on popup syncs keyboard index.
	if theme_ac_menu.has_signal("id_focused"):
		theme_ac_menu.id_focused.connect(func(fid: int) -> void:
			theme_ac_idx[0] = fid
		)
	theme_ac_menu.gui_input.connect(func(ev_m: InputEvent) -> void:
		if ev_m is InputEventMouseMotion and theme_ac_menu.item_count > 0:
			# Map mouse Y to item when possible.
			var local_y: float = theme_ac_menu.get_local_mouse_position().y
			var item_h: float = 22.0
			if theme_ac_menu.has_theme_constant("item_height"):
				item_h = float(theme_ac_menu.get_theme_constant("item_height"))
			var approx: int = int(local_y / maxf(item_h, 12.0))
			approx = clampi(approx, 0, theme_ac_menu.item_count - 1)
			theme_ac_idx[0] = approx
			if theme_ac_menu.has_method("set_focused_item"):
				theme_ac_menu.set_focused_item(approx)
	)
	var theme_save_btn := Button.new()
	theme_save_btn.text = "Save Theme"
	theme_save_btn.focus_mode = Control.FOCUS_NONE
	theme_save_btn.add_theme_font_size_override("font_size", 9)
	theme_save_btn.tooltip_text = "Save colors. Uses name field if set; else current. Shift = custom_<hex> when name empty."
	RetrowaveTheme.style_secondary_button(theme_save_btn)
	theme_edit_row.add_child(theme_save_btn)
	theme_save_btn.pressed.connect(func() -> void:
		var typed := _sanitize_library_theme_id(theme_name_edit.text)
		var tid_sv := get_library_theme_for_window(window_idx)
		if not typed.is_empty():
			tid_sv = typed
		elif Input.is_key_pressed(KEY_SHIFT):
			tid_sv = "custom_" + theme_mod_pick.color.to_html(false).substr(0, 6)
		if not upsert_library_theme_preset(tid_sv, theme_mod_pick.color, theme_title_pick.color):
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Theme save failed")
			return
		set_library_theme_for_window(window_idx, tid_sv)
		theme_name_edit.text = tid_sv
		rebuild_theme_opt.call()
		# Reselect saved id.
		for ti_sv in theme_opt.item_count:
			if str(theme_opt.get_item_metadata(ti_sv)) == tid_sv:
				theme_opt.select(ti_sv)
				break
		apply_library_theme_to_panel(panel, title, tid_sv)
		c.modulate.a = opac_slider.value
		sync_theme_picks.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Theme saved · %s" % tid_sv)
	)
	var theme_share_btn := Button.new()
	theme_share_btn.text = " thr↗"
	theme_share_btn.focus_mode = Control.FOCUS_NONE
	theme_share_btn.add_theme_font_size_override("font_size", 9)
	theme_share_btn.tooltip_text = "Copy EOTM1. Ctrl/Alt = import. Shift = theme QR. Ctrl+Shift = theme QR strip."
	RetrowaveTheme.style_secondary_button(theme_share_btn)
	theme_edit_row.add_child(theme_share_btn)
	theme_share_btn.pressed.connect(func() -> void:
		var ctrl := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT)
		var shift := Input.is_key_pressed(KEY_SHIFT)
		if ctrl and shift:
			# Pass 63: batch theme QR strip (all presets).
			var strip_p := export_library_theme_qr_strip_png()
			if not strip_p.is_empty():
				_show_pack_qr_popup(strip_p, "Theme QR Strip")
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"Theme QR strip · %s" % strip_p if not strip_p.is_empty() else "Theme QR strip failed"
				)
		elif ctrl:
			var imp := import_library_theme_share_code()
			if not bool(imp.get("ok", false)):
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Theme share import · %s" % str(imp.get("error", "fail")))
				return
			var id_imp := str(imp.get("id", "shared"))
			set_library_theme_for_window(window_idx, id_imp)
			theme_name_edit.text = id_imp
			rebuild_theme_opt.call()
			for ti_imp in theme_opt.item_count:
				if str(theme_opt.get_item_metadata(ti_imp)) == id_imp:
					theme_opt.select(ti_imp)
					break
			apply_library_theme_to_panel(panel, title, id_imp)
			c.modulate.a = opac_slider.value
			sync_theme_picks.call()
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Theme share · imported %s" % id_imp)
		elif shift:
			# Pass 60: theme share QR.
			var qr_path := export_library_theme_share_qr_png(get_library_theme_for_window(window_idx))
			if not qr_path.is_empty():
				_show_pack_qr_popup(qr_path, "Theme QR")
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"Theme QR · %s" % qr_path if not qr_path.is_empty() else "Theme QR failed"
				)
		else:
			var code_exp := export_library_theme_share_code(get_library_theme_for_window(window_idx))
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"Theme share · copied %s…" % code_exp.substr(0, mini(18, code_exp.length()))
					if not code_exp.is_empty() else "Theme share export failed"
				)
	)
	# Pass 60/61: full chrome snapshot EOCS1 (theme+dock+α+layout+pin SFX).
	var chrome_share_btn := Button.new()
	chrome_share_btn.text = "Snap↗"
	chrome_share_btn.focus_mode = Control.FOCUS_NONE
	chrome_share_btn.add_theme_font_size_override("font_size", 9)
	chrome_share_btn.tooltip_text = "Copy EOCS1 chrome. Ctrl/Alt = import. Shift = chrome QR. Ctrl+Shift = chrome QR strip (win 1–2)."
	RetrowaveTheme.style_secondary_button(chrome_share_btn)
	theme_edit_row.add_child(chrome_share_btn)
	var apply_chrome_import := func(imp_c: Dictionary) -> void:
		if not bool(imp_c.get("ok", false)):
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Chrome share · %s" % str(imp_c.get("error", "fail")))
			return
		var tid_c := str(imp_c.get("theme", get_library_theme_for_window(window_idx)))
		var dock_c := str(imp_c.get("dock", get_library_dock_for_window(window_idx)))
		var opac_c := float(imp_c.get("opacity", get_library_opacity_for_window(window_idx)))
		var layout_c := str(imp_c.get("layout", get_library_layout()))
		theme_ac_guard[0] = true
		theme_name_edit.text = tid_c
		theme_ac_guard[0] = false
		rebuild_theme_opt.call()
		for ti_c in theme_opt.item_count:
			if str(theme_opt.get_item_metadata(ti_c)) == tid_c:
				theme_opt.select(ti_c)
				break
		apply_library_theme_to_panel(panel, title, tid_c)
		opac_slider.value = opac_c
		c.modulate.a = opac_c
		# Apply dock via existing handler if available.
		if dock_c in PACK_LIBRARY_DOCKS:
			var di_c := PACK_LIBRARY_DOCKS.find(dock_c)
			if di_c >= 0:
				dock_opt.select(di_c)
			apply_dock_choice.call(dock_c)
		# Pass 61: layout preset.
		if layout_c in PACK_LIBRARY_LAYOUTS:
			var li_c := layout_ids.find(layout_c)
			if li_c >= 0:
				layout_opt.select(li_c)
			if apply_lib_layout_ref[0] is Callable:
				(apply_lib_layout_ref[0] as Callable).call(layout_c)
		sync_theme_picks.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Chrome · %s · %s · %s · α%.2f" % [tid_c, dock_c, layout_c, opac_c]
			)
	chrome_share_btn.pressed.connect(func() -> void:
		var ctrl_c := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT)
		var shift_c := Input.is_key_pressed(KEY_SHIFT)
		if ctrl_c and shift_c:
			# Pass 63: chrome QR strip for windows 1–2.
			var strip_c := export_library_chrome_qr_strip_png([1, 2, window_idx])
			if not strip_c.is_empty():
				_show_pack_qr_popup(strip_c, "Chrome QR Strip")
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"Chrome QR strip · %s" % strip_c if not strip_c.is_empty() else "Chrome QR strip failed"
				)
		elif ctrl_c:
			apply_chrome_import.call(import_library_chrome_share_code("", window_idx))
		elif shift_c:
			var qr_c := export_library_chrome_share_qr_png(window_idx)
			if not qr_c.is_empty():
				_show_pack_qr_popup(qr_c, "Chrome QR")
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"Chrome QR · %s" % qr_c if not qr_c.is_empty() else "Chrome QR failed"
				)
		else:
			var code_c := export_library_chrome_share_code(window_idx)
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"Chrome share · copied %s…" % code_c.substr(0, mini(18, code_c.length()))
					if not code_c.is_empty() else "Chrome share failed"
				)
	)
	# Pass 61/62: scan theme/chrome QR (engine decoder + zbarimg fallback). Shift = multi-file batch.
	var qr_scan_btn := Button.new()
	qr_scan_btn.text = "QR↙"
	qr_scan_btn.focus_mode = Control.FOCUS_NONE
	qr_scan_btn.add_theme_font_size_override("font_size", 9)
	qr_scan_btn.tooltip_text = "Import EOTM1/EOCS1 from QR image (engine decode, zbarimg fallback). Shift = multi-file batch."
	RetrowaveTheme.style_secondary_button(qr_scan_btn)
	theme_edit_row.add_child(qr_scan_btn)
	qr_scan_btn.pressed.connect(func() -> void:
		var multi := Input.is_key_pressed(KEY_SHIFT)
		var fd_q := FileDialog.new()
		fd_q.file_mode = (
			FileDialog.FILE_MODE_OPEN_FILES if multi else FileDialog.FILE_MODE_OPEN_FILE
		)
		fd_q.access = FileDialog.ACCESS_FILESYSTEM
		fd_q.use_native_dialog = true
		fd_q.title = "Import theme/chrome QR image(s)" if multi else "Import theme/chrome QR image"
		fd_q.current_dir = ProjectSettings.globalize_path("user://")
		fd_q.add_filter("*.png", "PNG image")
		fd_q.add_filter("*.jpg,*.jpeg", "JPEG image")
		fd_q.add_filter("*.*", "All files")
		panel.add_child(fd_q)
		var finish_fd := func() -> void:
			if is_instance_valid(fd_q):
				fd_q.queue_free()
		fd_q.file_selected.connect(func(p_q: String) -> void:
			var imp_q := import_library_share_from_qr_image(p_q, window_idx)
			apply_chrome_import.call(imp_q)
			finish_fd.call()
		)
		fd_q.files_selected.connect(func(paths_q: PackedStringArray) -> void:
			var batch := import_library_shares_from_qr_images(paths_q, window_idx)
			var last_b = batch.get("last", {})
			if last_b is Dictionary and bool((last_b as Dictionary).get("ok", false)):
				apply_chrome_import.call(last_b as Dictionary)
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug(
					"QR batch · %d/%d ok" % [int(batch.get("imported", 0)), int(batch.get("total", 0))]
				)
			finish_fd.call()
		)
		fd_q.canceled.connect(finish_fd)
		fd_q.popup()
	)
	# Seed pickers from current theme; keep in sync when dropdown changes.
	sync_theme_picks.call()
	theme_opt.item_selected.connect(func(idx_tp: int) -> void:
		sync_theme_picks.call()
		var tid_nm := str(theme_opt.get_item_metadata(idx_tp)) if idx_tp >= 0 else ""
		if not tid_nm.is_empty():
			theme_ac_guard[0] = true
			theme_name_edit.text = tid_nm
			theme_ac_guard[0] = false
	)
	# Pass 52: Ctrl+Shift+arrows dock chords (hidden shortcut buttons).
	var dock_chord_map: Array = [
		[KEY_LEFT, "left"],
		[KEY_RIGHT, "right"],
		[KEY_DOWN, "bottom"],
		[KEY_UP, "float"],
	]
	for dcm in dock_chord_map:
		var dkb := Button.new()
		dkb.focus_mode = Control.FOCUS_NONE
		dkb.flat = true
		dkb.modulate = Color(1, 1, 1, 0)
		dkb.custom_minimum_size = Vector2(1, 1)
		var dsc := Shortcut.new()
		var die := InputEventKey.new()
		die.keycode = dcm[0]
		die.ctrl_pressed = true
		die.shift_pressed = true
		dsc.events = [die]
		dkb.shortcut = dsc
		var dval: String = str(dcm[1])
		dkb.pressed.connect(func() -> void:
			apply_dock_choice.call(dval)
		)
		layout_row.add_child(dkb)
	# Pass 49: Ctrl+1..4 layout chords via hidden shortcut buttons.
	var layout_hotkeys: Array = [KEY_1, KEY_2, KEY_3, KEY_4]
	for hi in mini(4, layout_ids.size()):
		var hb := Button.new()
		hb.focus_mode = Control.FOCUS_NONE
		hb.flat = true
		hb.modulate = Color(1, 1, 1, 0)
		hb.custom_minimum_size = Vector2(1, 1)
		var sc := Shortcut.new()
		var ie := InputEventKey.new()
		ie.keycode = layout_hotkeys[hi]
		ie.ctrl_pressed = true
		sc.events = [ie]
		hb.shortcut = sc
		var hidx: int = hi
		hb.pressed.connect(func() -> void:
			layout_opt.select(hidx)
			layout_opt.item_selected.emit(hidx)
		)
		layout_row.add_child(hb)
	# Layout application ref assigned after dual/lists built.
	layout_opt.item_selected.connect(func(idx_l: int) -> void:
		var lid := str(layout_ids[idx_l]) if idx_l >= 0 and idx_l < layout_ids.size() else "standard"
		if apply_lib_layout_ref[0] != null:
			(apply_lib_layout_ref[0] as Callable).call(lid)
		var snap_lo := _snapshot_pack_map_ui_prefs()
		save_pack_risk_heat_prefs(
			bool(snap_lo.get("show", true)),
			float(snap_lo.get("intensity", 1.0)),
			float(snap_lo.get("legend_opacity", 1.0)),
			str(snap_lo.get("heat_ramp", "classic")),
			lid,
			str(snap_lo.get("heat_cool", "")),
			str(snap_lo.get("heat_hot", ""))
		)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Library layout · %s" % lid)
	)
	# Pass 36–41: search + sort + search history.
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	vbox.add_child(filter_row)
	var filter_edit := LineEdit.new()
	filter_edit.placeholder_text = "Search…  #tag  @fav  @group:theater/east"
	filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_edit.add_theme_font_size_override("font_size", 11)
	filter_row.add_child(filter_edit)
	# Pass 44: history search box filters History dropdown.
	var hist_search := LineEdit.new()
	hist_search.placeholder_text = "hist…"
	hist_search.custom_minimum_size = Vector2(64, 0)
	hist_search.add_theme_font_size_override("font_size", 9)
	hist_search.tooltip_text = "Filter history list by substring"
	filter_row.add_child(hist_search)
	var hist_opt := OptionButton.new()
	hist_opt.focus_mode = Control.FOCUS_NONE
	hist_opt.add_theme_font_size_override("font_size", 9)
	hist_opt.tooltip_text = "Recent searches (★ pinned)"
	hist_opt.add_item("History…", 0)
	var _hist_load := func() -> void:
		while hist_opt.item_count > 1:
			hist_opt.remove_item(1)
		var hi := 1
		var hfilter := hist_search.text.strip_edges().to_lower()
		for hq in load_route_pack_search_history():
			var he := _normalize_search_history_entry(hq)
			var hs := str(he.get("q", ""))
			if hs.is_empty():
				continue
			if not hfilter.is_empty() and not hs.to_lower().contains(hfilter):
				continue
			var pin := bool(he.get("pinned", false))
			var label := ("%s %s" % ["★", hs.substr(0, 32)]) if pin else hs.substr(0, 36)
			hist_opt.add_item(label, hi)
			hist_opt.set_item_metadata(hi, {"q": hs, "pinned": pin})
			hi += 1
	_hist_load.call()
	hist_search.text_changed.connect(func(_t: String) -> void:
		_hist_load.call()
	)
	filter_row.add_child(hist_opt)
	# Pass 43: pin current filter into history favorites.
	var hist_pin := Button.new()
	hist_pin.text = "★ Hist"
	hist_pin.focus_mode = Control.FOCUS_NONE
	hist_pin.add_theme_font_size_override("font_size", 9)
	hist_pin.tooltip_text = "Pin/unpin current search in history (Shift+click History entry also toggles)"
	RetrowaveTheme.style_secondary_button(hist_pin)
	hist_pin.modulate = Color(1.1, 0.95, 0.55, 1.0)
	hist_pin.pressed.connect(func() -> void:
		var q_pin := filter_edit.text.strip_edges()
		if q_pin.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("★ Hist · enter a search first")
			return
		push_route_pack_search_history(q_pin)
		var now_p := toggle_route_pack_search_history_pinned(q_pin)
		_hist_load.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("History pin %s · %s" % ["ON" if now_p else "OFF", q_pin.substr(0, 40)])
	)
	filter_row.add_child(hist_pin)
	# Pass 42/43: clear search history (keeps pinned).
	var hist_clear := Button.new()
	hist_clear.text = "Clr Hist"
	hist_clear.focus_mode = Control.FOCUS_NONE
	hist_clear.add_theme_font_size_override("font_size", 9)
	hist_clear.tooltip_text = "Clear unpinned history (pinned ★ queries kept). Shift+click clears all."
	RetrowaveTheme.style_secondary_button(hist_clear)
	hist_clear.pressed.connect(func() -> void:
		var keep := not Input.is_key_pressed(KEY_SHIFT)
		clear_route_pack_search_history(keep)
		_hist_load.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Search history cleared" + (" (kept ★)" if keep else " (all)"))
	)
	filter_row.add_child(hist_clear)
	# Pass 45–48: export history (Ctrl/Alt = native OS save dialog).
	var hist_exp := Button.new()
	hist_exp.text = "Exp Hist"
	hist_exp.focus_mode = Control.FOCUS_NONE
	hist_exp.add_theme_font_size_override("font_size", 9)
	hist_exp.tooltip_text = "Export history → default path. Ctrl/Alt+click = native save dialog."
	RetrowaveTheme.style_secondary_button(hist_exp)
	var packs_abs_dir := ProjectSettings.globalize_path("user://route_packs")
	var do_hist_export := func(path_out: String) -> void:
		var path_h := export_route_pack_search_history(
			path_out if not path_out.is_empty() else "user://route_packs/_search_history_export.json"
		)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"History exported · %s" % path_h if not path_h.is_empty() else "History export failed"
			)
	var make_hist_file_dialog := func(save_mode: bool, title_s: String) -> FileDialog:
		var fd := FileDialog.new()
		fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save_mode else FileDialog.FILE_MODE_OPEN_FILE
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.use_native_dialog = true
		fd.title = title_s
		fd.current_dir = packs_abs_dir
		if save_mode:
			fd.current_file = "_search_history_export.json"
		fd.add_filter("*.json", "JSON history")
		panel.add_child(fd)
		return fd
	hist_exp.pressed.connect(func() -> void:
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT):
			var fd_exp: FileDialog = make_hist_file_dialog.call(true, "Export search history")
			fd_exp.file_selected.connect(func(p: String) -> void:
				do_hist_export.call(p)
				if is_instance_valid(fd_exp):
					fd_exp.queue_free()
			)
			fd_exp.canceled.connect(func() -> void:
				if is_instance_valid(fd_exp):
					fd_exp.queue_free()
			)
			fd_exp.popup()
		else:
			do_hist_export.call("")
	)
	filter_row.add_child(hist_exp)
	# Pass 46–48: import history (union; Shift=replace; Ctrl/Alt=native open dialog).
	var hist_imp := Button.new()
	hist_imp.text = "Imp Hist"
	hist_imp.focus_mode = Control.FOCUS_NONE
	hist_imp.add_theme_font_size_override("font_size", 9)
	hist_imp.tooltip_text = "Import history (union). Shift=replace. Ctrl/Alt+click = native open dialog."
	RetrowaveTheme.style_secondary_button(hist_imp)
	hist_imp.modulate = Color(0.9, 1.05, 0.95, 1.0)
	var do_hist_import := func(path_in: String, mode_i: String) -> void:
		var res_i: Dictionary = import_route_pack_search_history(
			path_in if not path_in.is_empty() else "user://route_packs/_search_history_export.json",
			mode_i
		)
		_hist_load.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			if bool(res_i.get("ok", false)):
				DebugOverlay.toast_map_debug(
					"History import · +%d (%s) total %d" % [
						int(res_i.get("imported", 0)),
						str(res_i.get("mode", mode_i)),
						int(res_i.get("total", 0)),
					]
				)
			else:
				DebugOverlay.toast_map_debug(
					"History import failed · %s" % str(res_i.get("error", "?"))
				)
	hist_imp.pressed.connect(func() -> void:
		var mode_i := "replace" if Input.is_key_pressed(KEY_SHIFT) else "union"
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT):
			var fd_imp: FileDialog = make_hist_file_dialog.call(
				false, "Import search history (%s)" % mode_i
			)
			fd_imp.file_selected.connect(func(p2: String) -> void:
				do_hist_import.call(p2, mode_i)
				if is_instance_valid(fd_imp):
					fd_imp.queue_free()
			)
			fd_imp.canceled.connect(func() -> void:
				if is_instance_valid(fd_imp):
					fd_imp.queue_free()
			)
			fd_imp.popup()
		else:
			do_hist_import.call("", mode_i)
	)
	filter_row.add_child(hist_imp)
	# Pass 46/47: filter progress + cancel during debounce.
	var filter_status := Button.new()
	filter_status.text = ""
	filter_status.focus_mode = Control.FOCUS_NONE
	filter_status.flat = true
	filter_status.add_theme_font_size_override("font_size", 9)
	filter_status.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45, 0.95))
	filter_status.custom_minimum_size = Vector2(72, 0)
	filter_status.disabled = true
	filter_status.tooltip_text = "Updating… click or Esc to cancel pending filter rebuild"
	filter_row.add_child(filter_status)
	var sort_opt := OptionButton.new()
	sort_opt.focus_mode = Control.FOCUS_NONE
	sort_opt.add_theme_font_size_override("font_size", 10)
	sort_opt.add_item("Newest", 0)
	sort_opt.add_item("Name", 1)
	sort_opt.add_item("Size", 2)
	sort_opt.add_item("Tags", 3)
	sort_opt.add_item("★ Fav", 4)
	sort_opt.add_item("Group", 5)
	sort_opt.tooltip_text = "Sort: newest · name · size · tags · favorites · folder groups"
	sort_opt.select(0)
	filter_row.add_child(sort_opt)
	# Pass 37/38: tag cloud chips + AND polish.
	var cloud_head := HBoxContainer.new()
	cloud_head.add_theme_constant_override("separation", 6)
	vbox.add_child(cloud_head)
	var cloud_cap := Label.new()
	cloud_cap.text = "Tag cloud · multi = AND/OR"
	cloud_cap.add_theme_font_size_override("font_size", 9)
	cloud_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	cloud_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cloud_head.add_child(cloud_cap)
	var and_hint := Label.new()
	and_hint.text = ""
	and_hint.add_theme_font_size_override("font_size", 9)
	and_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45, 0.95))
	cloud_head.add_child(and_hint)
	var clear_chips := Button.new()
	clear_chips.text = "Clear tags"
	clear_chips.focus_mode = Control.FOCUS_NONE
	clear_chips.add_theme_font_size_override("font_size", 9)
	clear_chips.tooltip_text = "Clear all active tag chips from filter"
	RetrowaveTheme.style_secondary_button(clear_chips)
	cloud_head.add_child(clear_chips)
	# Pass 49: Tag OR mode (multiple #tags match any).
	var tag_or_chk := CheckBox.new()
	tag_or_chk.text = "Tag OR"
	tag_or_chk.focus_mode = Control.FOCUS_NONE
	tag_or_chk.button_pressed = false
	tag_or_chk.add_theme_font_size_override("font_size", 9)
	tag_or_chk.tooltip_text = "When on, multiple #tag chips OR (match any). Off = AND (match all)."
	cloud_head.add_child(tag_or_chk)
	# Pass 39: favorites-only filter chip.
	var fav_only := Button.new()
	fav_only.text = "★ only"
	fav_only.toggle_mode = true
	fav_only.focus_mode = Control.FOCUS_NONE
	fav_only.add_theme_font_size_override("font_size", 9)
	fav_only.tooltip_text = "Show only favorited packs (@fav filter)"
	RetrowaveTheme.style_secondary_button(fav_only)
	fav_only.modulate = Color(1.1, 0.95, 0.55, 1.0)
	cloud_head.add_child(fav_only)
	# Pass 48/51: bulk chip multi-select bar (shared across library windows).
	var bulk_chip_sel: Array = get_route_pack_bulk_selection()
	var bulk_lbl := Label.new()
	bulk_lbl.text = "Bulk · 0"
	bulk_lbl.add_theme_font_size_override("font_size", 9)
	bulk_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55, 0.95))
	bulk_lbl.tooltip_text = "Ctrl+click chips · shared across library windows"
	cloud_head.add_child(bulk_lbl)
	var bulk_filt_btn := Button.new()
	bulk_filt_btn.text = "Bulk Filt"
	bulk_filt_btn.focus_mode = Control.FOCUS_NONE
	bulk_filt_btn.add_theme_font_size_override("font_size", 9)
	bulk_filt_btn.tooltip_text = "Apply bulk-selected chips as active filters"
	RetrowaveTheme.style_secondary_button(bulk_filt_btn)
	cloud_head.add_child(bulk_filt_btn)
	var bulk_asg_btn := Button.new()
	bulk_asg_btn.text = "Bulk Asg"
	bulk_asg_btn.focus_mode = Control.FOCUS_NONE
	bulk_asg_btn.add_theme_font_size_override("font_size", 9)
	bulk_asg_btn.tooltip_text = "Assign Left packs: tags bulk-tag; first group bulk-group"
	RetrowaveTheme.style_secondary_button(bulk_asg_btn)
	cloud_head.add_child(bulk_asg_btn)
	var bulk_clr_btn := Button.new()
	bulk_clr_btn.text = "Bulk Clr"
	bulk_clr_btn.focus_mode = Control.FOCUS_NONE
	bulk_clr_btn.add_theme_font_size_override("font_size", 9)
	bulk_clr_btn.tooltip_text = "Clear bulk selection (Shift = also remove those from active filters)"
	RetrowaveTheme.style_secondary_button(bulk_clr_btn)
	cloud_head.add_child(bulk_clr_btn)
	# Pass 52: bulk export to clipboard.
	var bulk_exp_btn := Button.new()
	bulk_exp_btn.text = "Bulk Exp"
	bulk_exp_btn.focus_mode = Control.FOCUS_NONE
	bulk_exp_btn.add_theme_font_size_override("font_size", 9)
	bulk_exp_btn.tooltip_text = "Copy bulk (Shift=JSON schema). Ctrl/Alt+click = save file (.txt or .json)."
	RetrowaveTheme.style_secondary_button(bulk_exp_btn)
	bulk_exp_btn.modulate = Color(0.95, 1.05, 0.9, 1.0)
	cloud_head.add_child(bulk_exp_btn)
	bulk_exp_btn.pressed.connect(func() -> void:
		var as_json := Input.is_key_pressed(KEY_SHIFT)
		var txt_b := (
			export_route_pack_bulk_json(true)
			if as_json else export_route_pack_bulk_clipboard(true)
		)
		if txt_b.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Bulk export failed")
			return
		# Pass 55/56: optional file save dialog.
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT):
			var fd_e := FileDialog.new()
			fd_e.file_mode = FileDialog.FILE_MODE_SAVE_FILE
			fd_e.access = FileDialog.ACCESS_FILESYSTEM
			fd_e.use_native_dialog = true
			fd_e.title = "Export bulk selection"
			fd_e.current_dir = ProjectSettings.globalize_path("user://route_packs")
			fd_e.current_file = "_bulk_export.json" if as_json else "_bulk_export.txt"
			if as_json:
				fd_e.add_filter("*.json", "JSON bulk schema")
			else:
				fd_e.add_filter("*.txt", "Text bulk export")
			panel.add_child(fd_e)
			fd_e.file_selected.connect(func(p_e: String) -> void:
				var wf := FileAccess.open(p_e, FileAccess.WRITE)
				if wf != null:
					wf.store_string(txt_b)
					wf.close()
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Bulk exported · %s" % p_e)
				if is_instance_valid(fd_e):
					fd_e.queue_free()
			)
			fd_e.canceled.connect(func() -> void:
				if is_instance_valid(fd_e):
					fd_e.queue_free()
			)
			fd_e.popup()
		elif typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Bulk exported · %s → clipboard" % ("JSON" if as_json else ("%d lines" % txt_b.split("\n").size()))
			)
	)
	# Pass 53: bulk import from clipboard (Shift = replace).
	var bulk_imp_btn := Button.new()
	bulk_imp_btn.text = "Bulk Imp"
	bulk_imp_btn.focus_mode = Control.FOCUS_NONE
	bulk_imp_btn.add_theme_font_size_override("font_size", 9)
	bulk_imp_btn.tooltip_text = "Import bulk from clipboard (union). Shift=replace. Ctrl/Alt=open file dialog."
	RetrowaveTheme.style_secondary_button(bulk_imp_btn)
	bulk_imp_btn.modulate = Color(0.9, 1.05, 0.95, 1.0)
	cloud_head.add_child(bulk_imp_btn)
	# Pass 57: forward-refs for post-import pack selection (set after list_l/fill_lists).
	var select_packs_ref: Array = [null]  # [Callable]
	var fill_lists_early_ref: Array = [null]  # mirrors fill_lists_ref
	var do_bulk_import_text := func(txt_in: String, mode_b: String) -> void:
		var res_b: Dictionary = import_route_pack_bulk_clipboard(txt_in, mode_b)
		var packs_sel: Array = res_b.get("packs", []) if res_b.get("packs") is Array else []
		var n_pack_sel := 0
		if not packs_sel.is_empty():
			if fill_lists_early_ref[0] != null:
				(fill_lists_early_ref[0] as Callable).call()
			if select_packs_ref[0] != null:
				n_pack_sel = int((select_packs_ref[0] as Callable).call(packs_sel))
		if typeof(DebugOverlay) != TYPE_NIL:
			if bool(res_b.get("ok", false)):
				var extra := ""
				if n_pack_sel > 0:
					extra = " · selected %d packs" % n_pack_sel
				elif not packs_sel.is_empty():
					extra = " · %d packs in JSON (not in view)" % packs_sel.size()
				DebugOverlay.toast_map_debug(
					"Bulk import · +%d tags +%d groups · total %d (%s)%s" % [
						int(res_b.get("tags", 0)),
						int(res_b.get("groups", 0)),
						int(res_b.get("total", 0)),
						str(res_b.get("mode", mode_b)),
						extra,
					]
				)
			else:
				DebugOverlay.toast_map_debug(
					"Bulk import failed · %s" % str(res_b.get("error", "?"))
				)
	bulk_imp_btn.pressed.connect(func() -> void:
		var mode_b := "replace" if Input.is_key_pressed(KEY_SHIFT) else "union"
		# Pass 55: Ctrl/Alt opens filesystem file dialog (*.txt / *.json).
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META) or Input.is_key_pressed(KEY_ALT):
			var fd_b := FileDialog.new()
			fd_b.file_mode = FileDialog.FILE_MODE_OPEN_FILE
			fd_b.access = FileDialog.ACCESS_FILESYSTEM
			fd_b.use_native_dialog = true
			fd_b.title = "Import bulk tags/groups (%s)" % mode_b
			fd_b.current_dir = ProjectSettings.globalize_path("user://route_packs")
			fd_b.add_filter("*.txt", "Text bulk export")
			fd_b.add_filter("*.json", "JSON bulk export")
			panel.add_child(fd_b)
			fd_b.file_selected.connect(func(p_b: String) -> void:
				var body := ""
				if FileAccess.file_exists(p_b):
					var bf := FileAccess.open(p_b, FileAccess.READ)
					if bf != null:
						body = bf.get_as_text()
						bf.close()
				do_bulk_import_text.call(body, mode_b)
				if is_instance_valid(fd_b):
					fd_b.queue_free()
			)
			fd_b.canceled.connect(func() -> void:
				if is_instance_valid(fd_b):
					fd_b.queue_free()
			)
			fd_b.popup()
		else:
			do_bulk_import_text.call("", mode_b)
	)
	# Pass 49: bulk OR apply mode + pin focus cycle.
	var bulk_or_chk := CheckBox.new()
	bulk_or_chk.text = "Bulk OR"
	bulk_or_chk.focus_mode = Control.FOCUS_NONE
	bulk_or_chk.button_pressed = false
	bulk_or_chk.add_theme_font_size_override("font_size", 9)
	bulk_or_chk.tooltip_text = "Bulk Filt replaces active chips and enables Tag OR / Grp OR when ≥2"
	cloud_head.add_child(bulk_or_chk)
	var bulk_pin_btn := Button.new()
	bulk_pin_btn.text = "Pin Foc"
	bulk_pin_btn.focus_mode = Control.FOCUS_NONE
	bulk_pin_btn.add_theme_font_size_override("font_size", 9)
	bulk_pin_btn.tooltip_text = "Focus pin (cycles). Soft zoom default · Ctrl=tactical · Alt=keep zoom · Shift=low risk"
	RetrowaveTheme.style_secondary_button(bulk_pin_btn)
	bulk_pin_btn.modulate = Color(1.05, 0.9, 0.75, 1.0)
	cloud_head.add_child(bulk_pin_btn)
	# Pass 56: forward-ref for pin history OptionButton reload.
	var pin_hist_opt_ref: Array = [null]  # [Callable]
	# Pass 54: pin focus history back.
	var pin_back_btn := Button.new()
	pin_back_btn.text = "Pin ◀"
	pin_back_btn.focus_mode = Control.FOCUS_NONE
	pin_back_btn.add_theme_font_size_override("font_size", 9)
	pin_back_btn.tooltip_text = "Go back in pin focus history"
	RetrowaveTheme.style_secondary_button(pin_back_btn)
	pin_back_btn.modulate = Color(0.95, 0.95, 1.08, 1.0)
	cloud_head.add_child(pin_back_btn)
	pin_back_btn.pressed.connect(func() -> void:
		var zm_b := "soft"
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
			zm_b = "tactical"
		elif Input.is_key_pressed(KEY_ALT):
			zm_b = "keep"
		var prev_h: Dictionary = pop_pin_focus_history(zm_b)
		if typeof(DebugOverlay) != TYPE_NIL:
			if prev_h.is_empty():
				DebugOverlay.toast_map_debug("Pin back · empty history")
			else:
				DebugOverlay.toast_map_debug(
					"Pin back · %s · prov %d · hist %d" % [
						str(prev_h.get("label", "?")),
						int(prev_h.get("pid", -1)),
						get_pin_focus_history_size(),
					]
				)
		if pin_hist_opt_ref[0] != null:
			(pin_hist_opt_ref[0] as Callable).call()
	)
	# Pass 56/57: pin history jump list + search filter + clear.
	var pin_hist_search := LineEdit.new()
	pin_hist_search.placeholder_text = "pin…"
	pin_hist_search.custom_minimum_size = Vector2(52, 0)
	pin_hist_search.add_theme_font_size_override("font_size", 9)
	pin_hist_search.tooltip_text = "Filter pin history list by label/source/pid substring"
	cloud_head.add_child(pin_hist_search)
	var pin_hist_opt := OptionButton.new()
	pin_hist_opt.focus_mode = Control.FOCUS_NONE
	pin_hist_opt.add_theme_font_size_override("font_size", 9)
	pin_hist_opt.tooltip_text = "Pin focus history · select to jump (truncates newer)"
	pin_hist_opt.custom_minimum_size = Vector2(96, 0)
	cloud_head.add_child(pin_hist_opt)
	var reload_pin_hist_opt := func() -> void:
		while pin_hist_opt.item_count > 0:
			pin_hist_opt.remove_item(0)
		pin_hist_opt.add_item("Pin hist…", 0)
		var hist: Array = get_pin_focus_history()
		var filt_p := pin_hist_search.text.strip_edges().to_lower()
		# Show newest first in UI.
		var hi := 1
		var shown := 0
		for i in range(hist.size() - 1, -1, -1):
			var he: Dictionary = hist[i]
			var lab := str(he.get("label", ""))
			if lab.is_empty():
				lab = "prov %d" % int(he.get("pid", -1))
			var src := str(he.get("source", ""))
			var pid_s := str(int(he.get("pid", -1)))
			if not filt_p.is_empty():
				var blob := ("%s %s %s" % [lab, src, pid_s]).to_lower()
				if not blob.contains(filt_p):
					continue
			var risk_p := float(he.get("risk", 0.0))
			pin_hist_opt.add_item("%s ·%.0f%%" % [lab.substr(0, 18), risk_p * 100.0], hi)
			pin_hist_opt.set_item_metadata(hi, i)  # absolute index in stack
			hi += 1
			shown += 1
			if shown >= 40:
				break
		pin_hist_opt.select(0)
	pin_hist_opt_ref[0] = reload_pin_hist_opt
	reload_pin_hist_opt.call()
	pin_hist_search.text_changed.connect(func(_t: String) -> void:
		reload_pin_hist_opt.call()
	)
	pin_hist_opt.item_selected.connect(func(idx_h: int) -> void:
		if idx_h <= 0:
			return
		var abs_i := int(pin_hist_opt.get_item_metadata(idx_h))
		var zm_j := "soft"
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
			zm_j = "tactical"
		elif Input.is_key_pressed(KEY_ALT):
			zm_j = "keep"
		var jumped: Dictionary = jump_pin_focus_history(abs_i, zm_j)
		reload_pin_hist_opt.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			if jumped.is_empty():
				DebugOverlay.toast_map_debug("Pin hist jump failed")
			else:
				DebugOverlay.toast_map_debug(
					"Pin hist · %s · prov %d" % [
						str(jumped.get("label", "?")),
						int(jumped.get("pid", -1)),
					]
				)
	)
	var pin_hist_clr := Button.new()
	pin_hist_clr.text = "Clr Pin"
	pin_hist_clr.focus_mode = Control.FOCUS_NONE
	pin_hist_clr.add_theme_font_size_override("font_size", 9)
	pin_hist_clr.tooltip_text = "Clear pin focus history (memory + disk)"
	RetrowaveTheme.style_secondary_button(pin_hist_clr)
	cloud_head.add_child(pin_hist_clr)
	pin_hist_clr.pressed.connect(func() -> void:
		clear_pin_focus_history()
		reload_pin_hist_opt.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Pin history cleared")
	)
	var pin_focus_cycle := [0]
	var cloud := HFlowContainer.new()
	cloud.add_theme_constant_override("h_separation", 4)
	cloud.add_theme_constant_override("v_separation", 3)
	vbox.add_child(cloud)
	var active_chip_tags: Array = []  # currently toggled #tags
	# Pass 46/48: forward-refs for chip menu + rebuild self-calls.
	var open_chip_menu_ref: Array = [null]  # [Callable]
	var rebuild_cloud_ref: Array = [null]  # [Callable]
	var rebuild_group_chips_ref: Array = [null]  # [Callable]
	var refresh_bulk_lbl := func() -> void:
		bulk_lbl.text = "Bulk · %d" % bulk_chip_sel.size()
		if bulk_chip_sel.size() > 0:
			bulk_lbl.modulate = Color(1.15, 1.05, 0.7, 1.0)
		else:
			bulk_lbl.modulate = Color(1, 1, 1, 1)
	var bulk_has := func(kind: String, value: String) -> bool:
		for b in bulk_chip_sel:
			if b is Dictionary and str(b.get("kind", "")) == kind and str(b.get("value", "")) == value:
				return true
		return false
	var push_bulk_shared := func() -> void:
		set_route_pack_bulk_selection(bulk_chip_sel)
	var pull_bulk_shared := func() -> void:
		bulk_chip_sel = get_route_pack_bulk_selection()
		refresh_bulk_lbl.call()
		if rebuild_cloud_ref[0] != null:
			(rebuild_cloud_ref[0] as Callable).call()
		if rebuild_group_chips_ref[0] != null:
			(rebuild_group_chips_ref[0] as Callable).call()
	var bulk_toggle := func(kind: String, value: String) -> void:
		toggle_route_pack_bulk_chip(kind, value)
		# Local mirror updates via watcher; also pull immediately for this window.
		bulk_chip_sel = get_route_pack_bulk_selection()
		refresh_bulk_lbl.call()
	register_route_pack_bulk_watcher(pull_bulk_shared)
	panel.tree_exiting.connect(func() -> void:
		unregister_route_pack_bulk_watcher(pull_bulk_shared)
	)
	refresh_bulk_lbl.call()
	# Pass 42/43: group chips (sync with @group: filters) + OR mode.
	var group_chip_head := HBoxContainer.new()
	group_chip_head.add_theme_constant_override("separation", 6)
	vbox.add_child(group_chip_head)
	var group_chip_cap := Label.new()
	group_chip_cap.text = "Group chips"
	group_chip_cap.add_theme_font_size_override("font_size", 9)
	group_chip_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	group_chip_cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_chip_head.add_child(group_chip_cap)
	var group_or_chk := CheckBox.new()
	group_or_chk.text = "Grp OR"
	group_or_chk.focus_mode = Control.FOCUS_NONE
	group_or_chk.button_pressed = false
	group_or_chk.add_theme_font_size_override("font_size", 9)
	group_or_chk.tooltip_text = "When on, multiple group chips OR (match any). Off = AND (match all)."
	group_chip_head.add_child(group_or_chk)
	var group_cloud := HFlowContainer.new()
	group_cloud.add_theme_constant_override("h_separation", 4)
	group_cloud.add_theme_constant_override("v_separation", 3)
	vbox.add_child(group_cloud)
	var active_group_chips: Array = []  # group paths currently filtered
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	vbox.add_child(name_row)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "pack name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 11)
	if not get_route_compare_slot_label(0).is_empty():
		name_edit.text = get_route_compare_slot_label(0)
	elif not _last_route_compare_data.is_empty():
		name_edit.text = "pack_%s" % str(_last_route_compare_data.get("winner", "ab")).to_lower()
	name_row.add_child(name_edit)
	var tags_edit := LineEdit.new()
	tags_edit.placeholder_text = "tags (comma)"
	tags_edit.custom_minimum_size = Vector2(100, 0)
	tags_edit.add_theme_font_size_override("font_size", 11)
	tags_edit.tooltip_text = "Optional tags: eastern, safe, convoy"
	name_row.add_child(tags_edit)
	# Pass 40: folder group field.
	var group_edit := LineEdit.new()
	group_edit.placeholder_text = "group/path"
	group_edit.custom_minimum_size = Vector2(96, 0)
	group_edit.add_theme_font_size_override("font_size", 11)
	group_edit.tooltip_text = "Nested group path e.g. theater/east/coast (drag pack onto header to move)"
	name_row.add_child(group_edit)
	var save_lib := Button.new()
	save_lib.text = "Save"
	save_lib.focus_mode = Control.FOCUS_NONE
	RetrowaveTheme.style_secondary_button(save_lib)
	name_row.add_child(save_lib)
	# Pass 37: notes editor.
	var note_edit := TextEdit.new()
	note_edit.custom_minimum_size = Vector2(0, 48)
	note_edit.placeholder_text = "Notes for Left selection (saved with Tag L / Note)"
	note_edit.add_theme_font_size_override("font_size", 10)
	note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(note_edit)
	# Dual-pane lists + Pass 42 group tree.
	var dual := HBoxContainer.new()
	dual.add_theme_constant_override("separation", 8)
	dual.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(dual)
	# Pass 42: nested group tree panel.
	var tree_col := VBoxContainer.new()
	tree_col.custom_minimum_size = Vector2(120, 0)
	tree_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dual.add_child(tree_col)
	var tree_cap := Label.new()
	tree_cap.text = "Groups"
	tree_cap.add_theme_font_size_override("font_size", 10)
	tree_cap.add_theme_color_override("font_color", Color(0.85, 0.9, 0.55))
	tree_col.add_child(tree_cap)
	var group_tree := Tree.new()
	group_tree.custom_minimum_size = Vector2(110, 140)
	group_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group_tree.hide_root = true
	group_tree.select_mode = Tree.SELECT_MULTI  # Pass 43: multi-select for bulk group / OR filter
	group_tree.tooltip_text = "Multi-select groups · Assign Sel packs · click filters @group"
	tree_col.add_child(group_tree)
	var tree_assign := Button.new()
	tree_assign.text = "Assign Sel"
	tree_assign.focus_mode = Control.FOCUS_NONE
	tree_assign.add_theme_font_size_override("font_size", 9)
	tree_assign.tooltip_text = "Move multi-selected Left packs into first selected tree group"
	RetrowaveTheme.style_secondary_button(tree_assign)
	tree_col.add_child(tree_assign)
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dual.add_child(left_col)
	var left_cap := Label.new()
	left_cap.text = "Left (A/B)"
	left_cap.add_theme_font_size_override("font_size", 10)
	left_cap.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	left_col.add_child(left_cap)
	var list_l := ItemList.new()
	list_l.custom_minimum_size = Vector2(0, 140)
	list_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_l.add_theme_font_size_override("font_size", 10)
	list_l.select_mode = ItemList.SELECT_MULTI  # Pass 39: multi-select for bulk tag
	list_l.tooltip_text = "Multi-select · drag pack onto group header to reassign group"
	left_col.add_child(list_l)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dual.add_child(right_col)
	var right_cap := Label.new()
	right_cap.text = "Right (C/D)"
	right_cap.add_theme_font_size_override("font_size", 10)
	right_cap.add_theme_color_override("font_color", Color(1.0, 0.5, 0.85))
	right_col.add_child(right_cap)
	var list_r := ItemList.new()
	list_r.custom_minimum_size = Vector2(0, 140)
	list_r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_r.add_theme_font_size_override("font_size", 10)
	right_col.add_child(list_r)
	var preview := Label.new()
	preview.text = "Select packs · peek risks on select"
	preview.add_theme_font_size_override("font_size", 9)
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92, 0.95))
	vbox.add_child(preview)
	var sort_mode_from_opt := func() -> String:
		match sort_opt.selected:
			1: return "name"
			2: return "size"
			3: return "tags"
			4: return "fav"
			5: return "group"
			_: return "mtime"
	var sync_filter_from_chips := func() -> void:
		var base := filter_edit.text
		var kept: PackedStringArray = PackedStringArray()
		for part in base.split(" "):
			var p := str(part).strip_edges()
			if p.is_empty() or p.begins_with("#"):
				continue
			# Drop fav / group tokens; re-add from toggles.
			var pl := p.to_lower()
			if pl in ["@fav", "@favorite", "@favorites", "★", ":fav"]:
				continue
			if pl.begins_with("@group:") or pl.begins_with("@g:"):
				continue
			kept.append(p)
		for at in active_chip_tags:
			kept.append("#" + str(at))
		for gp in active_group_chips:
			var gs := str(gp)
			if gs.is_empty():
				kept.append("@group:")
			else:
				kept.append("@group:" + gs)
		if group_or_chk.button_pressed and active_group_chips.size() >= 2:
			kept.append("@groupor")
		# Pass 49: tag OR token.
		if tag_or_chk.button_pressed and active_chip_tags.size() >= 2:
			kept.append("@tagor")
		if fav_only.button_pressed:
			kept.append("@fav")
		filter_edit.text = " ".join(kept)
		var hints: PackedStringArray = PackedStringArray()
		if fav_only.button_pressed:
			hints.append("★ only")
		if active_group_chips.size() > 0:
			var gp_h: PackedStringArray = PackedStringArray()
			for g2 in active_group_chips:
				var g2s := str(g2)
				gp_h.append("grp:" + (g2s if not g2s.is_empty() else "∅"))
			var joiner := " ∪ " if group_or_chk.button_pressed else " ∩ "
			hints.append(("OR " if group_or_chk.button_pressed else "AND ") + joiner.join(gp_h))
		if active_chip_tags.size() >= 2:
			var ap: PackedStringArray = PackedStringArray()
			for at2 in active_chip_tags:
				ap.append("#" + str(at2))
			var tjoin := " ∪ " if tag_or_chk.button_pressed else " ∩ "
			hints.append(("OR: " if tag_or_chk.button_pressed else "AND: ") + tjoin.join(ap))
		elif active_chip_tags.size() == 1:
			hints.append("filter: #" + str(active_chip_tags[0]))
		and_hint.text = " · ".join(hints)
		filter_edit.text_changed.emit(filter_edit.text)
	var rebuild_cloud := func() -> void:
		for ch in cloud.get_children():
			ch.queue_free()
		for te in list_all_pack_library_tags():
			if not te is Dictionary:
				continue
			var td: Dictionary = te
			var tag := str(td.get("tag", ""))
			var cnt := int(td.get("count", 0))
			if tag.is_empty():
				continue
			var chip := Button.new()
			chip.toggle_mode = true
			chip.focus_mode = Control.FOCUS_NONE
			chip.text = "#%s ·%d" % [tag, cnt]
			chip.add_theme_font_size_override("font_size", 9)
			chip.button_pressed = active_chip_tags.has(tag)
			# Pass 38: multi-tag AND polish — stronger highlight + AND tooltip.
			var n_active := active_chip_tags.size()
			if bool(bulk_has.call("tag", tag)):
				chip.tooltip_text = "In bulk · #%s · Ctrl+click toggle bulk" % tag
				chip.modulate = Color(1.2, 0.75, 0.45, 1.0)
			elif chip.button_pressed and n_active >= 2:
				chip.tooltip_text = "AND filter includes #%s (with %d other tags)" % [tag, n_active - 1]
				chip.modulate = Color(1.15, 0.95, 0.55, 1.0)
			elif chip.button_pressed:
				chip.tooltip_text = "Toggle filter #%s" % tag
				chip.modulate = Color(0.85, 1.1, 1.15, 1.0)
			else:
				chip.tooltip_text = "Add #%s to AND filter" % tag
				chip.modulate = Color(1, 1, 1, 1)
			RetrowaveTheme.style_secondary_button(chip)
			var tag_capture := tag
			chip.toggled.connect(func(on: bool) -> void:
				# Skip filter toggle when Ctrl multi-selecting bulk.
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
					chip.set_pressed_no_signal(active_chip_tags.has(tag_capture))
					return
				if on:
					if not active_chip_tags.has(tag_capture):
						active_chip_tags.append(tag_capture)
				else:
					active_chip_tags.erase(tag_capture)
				sync_filter_from_chips.call()
			)
			# Pass 46/48: RMB menu · Ctrl+click bulk multi-select.
			chip.gui_input.connect(func(ev_t: InputEvent) -> void:
				if ev_t is InputEventMouseButton and ev_t.pressed:
					if ev_t.button_index == MOUSE_BUTTON_RIGHT:
						if open_chip_menu_ref[0] != null:
							(open_chip_menu_ref[0] as Callable).call(
								"tag", tag_capture, chip.get_global_mouse_position()
							)
						chip.accept_event()
					elif ev_t.button_index == MOUSE_BUTTON_LEFT and (
						ev_t.ctrl_pressed or ev_t.meta_pressed
						or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
					):
						bulk_toggle.call("tag", tag_capture)
						if rebuild_cloud_ref[0] != null:
							(rebuild_cloud_ref[0] as Callable).call()
						chip.accept_event()
			)
			if not str(chip.tooltip_text).contains("right-click"):
				chip.tooltip_text = str(chip.tooltip_text) + " · right-click · Ctrl bulk"
			cloud.add_child(chip)
		if active_chip_tags.size() >= 2:
			var ap2: PackedStringArray = PackedStringArray()
			for at3 in active_chip_tags:
				ap2.append("#" + str(at3))
			var tj := " ∪ " if tag_or_chk.button_pressed else " ∩ "
			and_hint.text = ("OR: " if tag_or_chk.button_pressed else "AND: ") + tj.join(ap2)
		elif active_chip_tags.size() == 1:
			and_hint.text = "filter: #" + str(active_chip_tags[0])
		else:
			and_hint.text = ""
	rebuild_cloud_ref[0] = rebuild_cloud
	clear_chips.pressed.connect(func() -> void:
		active_chip_tags.clear()
		active_group_chips.clear()
		sync_filter_from_chips.call()
	)
	fav_only.toggled.connect(func(_on: bool) -> void:
		sync_filter_from_chips.call()
	)
	group_or_chk.toggled.connect(func(_on: bool) -> void:
		sync_filter_from_chips.call()
	)
	tag_or_chk.toggled.connect(func(_on: bool) -> void:
		sync_filter_from_chips.call()
	)
	# Pass 44/45: live counts + fill_lists forward-ref for chip right-click.
	var last_visible_entries: Array = []
	var fill_lists_ref: Array = [null]  # [Callable] set after fill_lists defined
	# Pass 46/47: shared chip context menu (Filter / Assign / Copy / Clear) + key accelerators.
	var chip_menu := PopupMenu.new()
	chip_menu.name = "ChipContextMenu"
	panel.add_child(chip_menu)
	chip_menu.add_item("Filter (F)", 0)
	chip_menu.add_item("Assign (A)", 1)
	chip_menu.add_item("Copy (C)", 2)
	chip_menu.add_item("Clear (X)", 3)
	chip_menu.add_item("Bulk (B)", 4)
	# Accelerators fire while the menu is open.
	chip_menu.set_item_accelerator(0, KEY_F)
	chip_menu.set_item_accelerator(1, KEY_A)
	chip_menu.set_item_accelerator(2, KEY_C)
	chip_menu.set_item_accelerator(3, KEY_X)
	chip_menu.set_item_accelerator(4, KEY_B)
	var chip_menu_ctx: Array = [{"kind": "", "value": ""}]  # kind: tag|group
	var selected_left_packs := func() -> Array:
		var names_sel: Array = []
		for si_s in list_l.get_selected_items():
			var m_s := str(list_l.get_item_metadata(int(si_s)))
			if not m_s.is_empty() and not m_s.begins_with("group:"):
				names_sel.append(m_s)
		return names_sel
	var open_chip_menu := func(kind: String, value: String, at_global: Vector2) -> void:
		chip_menu_ctx[0] = {"kind": kind, "value": value}
		chip_menu.set_item_disabled(1, false)  # Assign always offered; toast if empty sel
		chip_menu.position = Vector2i(int(at_global.x), int(at_global.y))
		chip_menu.popup()
	open_chip_menu_ref[0] = open_chip_menu
	chip_menu.id_pressed.connect(func(id: int) -> void:
		var kind_m := str((chip_menu_ctx[0] as Dictionary).get("kind", ""))
		var val_m := str((chip_menu_ctx[0] as Dictionary).get("value", ""))
		if id == 0:
			# Filter — toggle chip in active set.
			if kind_m == "tag":
				if active_chip_tags.has(val_m):
					active_chip_tags.erase(val_m)
				else:
					active_chip_tags.append(val_m)
			elif kind_m == "group":
				if active_group_chips.has(val_m):
					active_group_chips.erase(val_m)
				else:
					active_group_chips.append(val_m)
			sync_filter_from_chips.call()
		elif id == 1:
			# Assign selected Left packs.
			var names_a2: Array = selected_left_packs.call()
			if names_a2.is_empty():
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Chip Assign · select Left packs first")
				return
			if kind_m == "group":
				var n_ag := bulk_group_route_pack_library(names_a2, val_m)
				if fill_lists_ref[0] != null:
					(fill_lists_ref[0] as Callable).call()
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Chip assign · %d → %s" % [
						n_ag, val_m if not val_m.is_empty() else "(ungrouped)"
					])
			elif kind_m == "tag":
				var n_at := bulk_tag_route_pack_library(names_a2, val_m, false)
				if fill_lists_ref[0] != null:
					(fill_lists_ref[0] as Callable).call()
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Chip tag · %d → #%s" % [n_at, val_m])
		elif id == 2:
			# Copy path / #tag to clipboard.
			var clip_t := ("#" + val_m) if kind_m == "tag" else (
				("@group:" + val_m) if not val_m.is_empty() else "@group:"
			)
			if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
				DisplayServer.clipboard_set(clip_t)
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Copied · %s" % clip_t)
		elif id == 3:
			# Clear this chip from active filter (or clear all of that kind if none active).
			if kind_m == "tag":
				if active_chip_tags.has(val_m):
					active_chip_tags.erase(val_m)
				else:
					active_chip_tags.clear()
			elif kind_m == "group":
				if active_group_chips.has(val_m):
					active_group_chips.erase(val_m)
				else:
					active_group_chips.clear()
			sync_filter_from_chips.call()
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Chip clear · %s" % kind_m)
		elif id == 4:
			# Pass 48: toggle into bulk multi-select set.
			bulk_toggle.call(kind_m, val_m)
			if fill_lists_ref[0] != null:
				(fill_lists_ref[0] as Callable).call()
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Bulk · %d" % bulk_chip_sel.size())
	)
	var count_visible_under_group := func(gpath: String) -> int:
		var n := 0
		for e in last_visible_entries:
			if not e is Dictionary:
				continue
			var eg := _sanitize_pack_library_group(str((e as Dictionary).get("group", "")))
			if gpath.is_empty():
				if eg.is_empty():
					n += 1
			elif _group_is_under(eg, gpath):
				n += 1
		return n
	var rebuild_group_chips := func() -> void:
		for ch in group_cloud.get_children():
			ch.queue_free()
		# Ungrouped chip — live count from visible filter set.
		var ug_n: int = count_visible_under_group.call("")
		var ug := Button.new()
		ug.toggle_mode = true
		ug.focus_mode = Control.FOCUS_NONE
		ug.text = "∅ ·%d" % ug_n
		ug.add_theme_font_size_override("font_size", 9)
		ug.button_pressed = active_group_chips.has("")
		ug.tooltip_text = "Filter ungrouped packs (@group:) · %d live · right-click · Ctrl bulk" % ug_n
		RetrowaveTheme.style_secondary_button(ug)
		if bool(bulk_has.call("group", "")):
			ug.modulate = Color(1.2, 0.75, 0.45, 1.0)
		elif ug.button_pressed:
			ug.modulate = Color(1.1, 1.05, 0.75, 1.0)
		ug.toggled.connect(func(on: bool) -> void:
			if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
				ug.set_pressed_no_signal(active_group_chips.has(""))
				return
			if on:
				if not active_group_chips.has(""):
					active_group_chips.append("")
			else:
				active_group_chips.erase("")
			sync_filter_from_chips.call()
		)
		# Pass 46/48: RMB menu · Ctrl bulk.
		ug.gui_input.connect(func(ev_ug: InputEvent) -> void:
			if ev_ug is InputEventMouseButton and ev_ug.pressed:
				if ev_ug.button_index == MOUSE_BUTTON_RIGHT:
					if open_chip_menu_ref[0] != null:
						(open_chip_menu_ref[0] as Callable).call(
							"group", "", ug.get_global_mouse_position()
						)
					ug.accept_event()
				elif ev_ug.button_index == MOUSE_BUTTON_LEFT and (
					ev_ug.ctrl_pressed or ev_ug.meta_pressed
					or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
				):
					bulk_toggle.call("group", "")
					if rebuild_group_chips_ref[0] != null:
						(rebuild_group_chips_ref[0] as Callable).call()
					ug.accept_event()
		)
		group_cloud.add_child(ug)
		# Paths from full library, counts from visible set (Pass 44 live).
		for ge in list_all_pack_library_groups():
			if not ge is Dictionary:
				continue
			var gd: Dictionary = ge
			var gpath := str(gd.get("group", ""))
			if gpath.is_empty():
				continue
			var cnt_g: int = count_visible_under_group.call(gpath)
			var chip_g := Button.new()
			chip_g.toggle_mode = true
			chip_g.focus_mode = Control.FOCUS_NONE
			var leaf := gpath
			if gpath.contains("/"):
				leaf = gpath.substr(gpath.rfind("/") + 1)
			chip_g.text = "%s ·%d" % [leaf, cnt_g]
			chip_g.add_theme_font_size_override("font_size", 9)
			chip_g.button_pressed = active_group_chips.has(gpath)
			chip_g.tooltip_text = "Filter @group:%s · %d live · right-click · Ctrl bulk" % [gpath, cnt_g]
			RetrowaveTheme.style_secondary_button(chip_g)
			if bool(bulk_has.call("group", gpath)):
				chip_g.modulate = Color(1.2, 0.75, 0.45, 1.0)
			elif chip_g.button_pressed:
				chip_g.modulate = Color(0.95, 1.1, 0.85, 1.0)
			# Dim zero-count chips slightly.
			elif cnt_g <= 0:
				chip_g.modulate = Color(0.75, 0.78, 0.8, 0.75)
			var g_cap := gpath
			chip_g.toggled.connect(func(on: bool) -> void:
				if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
					chip_g.set_pressed_no_signal(active_group_chips.has(g_cap))
					return
				if on:
					if not active_group_chips.has(g_cap):
						active_group_chips.append(g_cap)
				else:
					active_group_chips.erase(g_cap)
				sync_filter_from_chips.call()
			)
			# Pass 46/48: group chip context menu + Ctrl bulk.
			chip_g.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed:
					if ev.button_index == MOUSE_BUTTON_RIGHT:
						if open_chip_menu_ref[0] != null:
							(open_chip_menu_ref[0] as Callable).call(
								"group", g_cap, chip_g.get_global_mouse_position()
							)
						chip_g.accept_event()
					elif ev.button_index == MOUSE_BUTTON_LEFT and (
						ev.ctrl_pressed or ev.meta_pressed
						or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
					):
						bulk_toggle.call("group", g_cap)
						if rebuild_group_chips_ref[0] != null:
							(rebuild_group_chips_ref[0] as Callable).call()
						chip_g.accept_event()
			)
			group_cloud.add_child(chip_g)
	rebuild_group_chips_ref[0] = rebuild_group_chips
	# Pass 48: bulk chip actions (after rebuild helpers exist).
	bulk_filt_btn.pressed.connect(func() -> void:
		bulk_chip_sel = get_route_pack_bulk_selection()
		if bulk_chip_sel.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Bulk Filt · Ctrl+click chips first")
			return
		# Pass 49: Bulk OR replaces active sets and enables OR modes when ≥2 of a kind.
		if bulk_or_chk.button_pressed:
			active_chip_tags.clear()
			active_group_chips.clear()
		var n_tags_b := 0
		var n_grp_b := 0
		for b in bulk_chip_sel:
			if not b is Dictionary:
				continue
			var bk := str(b.get("kind", ""))
			var bv := str(b.get("value", ""))
			if bk == "tag":
				if not active_chip_tags.has(bv):
					active_chip_tags.append(bv)
				n_tags_b += 1
			elif bk == "group":
				if not active_group_chips.has(bv):
					active_group_chips.append(bv)
				n_grp_b += 1
		if bulk_or_chk.button_pressed:
			if n_tags_b >= 2:
				tag_or_chk.set_pressed_no_signal(true)
			if n_grp_b >= 2:
				group_or_chk.set_pressed_no_signal(true)
		sync_filter_from_chips.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Bulk Filt · %d%s" % [
					bulk_chip_sel.size(),
					" (OR)" if bulk_or_chk.button_pressed else "",
				]
			)
	)
	bulk_pin_btn.pressed.connect(func() -> void:
		var high_first := not Input.is_key_pressed(KEY_SHIFT)
		# Pass 51: zoom mode — soft default, Ctrl=tactical, Alt=keep.
		var zm := "soft"
		if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
			zm = "tactical"
		elif Input.is_key_pressed(KEY_ALT):
			zm = "keep"
		# Pass 50/51: filter from shared bulk + Left selection.
		bulk_chip_sel = get_route_pack_bulk_selection()
		var f_tags: Array = []
		var f_groups: Array = []
		for bf in bulk_chip_sel:
			if not bf is Dictionary:
				continue
			var bfk := str(bf.get("kind", ""))
			var bfv := str(bf.get("value", ""))
			if bfk == "tag" and not bfv.is_empty():
				f_tags.append(bfv)
			elif bfk == "group":
				f_groups.append(bfv)
		var f_names: Array = selected_left_packs.call()
		var filt := {
			"tags": f_tags,
			"groups": f_groups,
			"pack_names": f_names,
			"tag_or": bulk_or_chk.button_pressed or tag_or_chk.button_pressed,
			"group_or": bulk_or_chk.button_pressed or group_or_chk.button_pressed,
		}
		var info: Dictionary = focus_pack_pin_by_risk_info(
			int(pin_focus_cycle[0]), high_first, filt, zm
		)
		pin_focus_cycle[0] = int(pin_focus_cycle[0]) + 1
		if pin_hist_opt_ref[0] != null:
			(pin_hist_opt_ref[0] as Callable).call()
		if typeof(DebugOverlay) != TYPE_NIL:
			var pid_f := int(info.get("pid", -1))
			if pid_f >= 0:
				DebugOverlay.toast_map_debug(
					"Pin focus · %s · %d/%d · prov %d · %s · zoom %s" % [
						str(info.get("label", "?")),
						int(info.get("index", 0)) + 1,
						int(info.get("total", 0)),
						pid_f,
						str(info.get("source", "")),
						str(info.get("zoom", zm)),
					]
				)
			else:
				DebugOverlay.toast_map_debug("Pin focus · no matching pins/packs")
	)
	bulk_asg_btn.pressed.connect(func() -> void:
		var names_b: Array = selected_left_packs.call()
		if names_b.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Bulk Asg · select Left packs")
			return
		if bulk_chip_sel.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Bulk Asg · Ctrl+click chips first")
			return
		var n_tags := 0
		var n_grp := 0
		var first_group := ""
		var has_group := false
		var tag_parts: PackedStringArray = PackedStringArray()
		for b2 in bulk_chip_sel:
			if not b2 is Dictionary:
				continue
			var bk2 := str(b2.get("kind", ""))
			var bv2 := str(b2.get("value", ""))
			if bk2 == "tag" and not bv2.is_empty():
				tag_parts.append(bv2)
			elif bk2 == "group":
				if not has_group:
					first_group = bv2
					has_group = true
		if not tag_parts.is_empty():
			n_tags = bulk_tag_route_pack_library(names_b, ",".join(tag_parts), false)
		if has_group:
			n_grp = bulk_group_route_pack_library(names_b, first_group)
		if fill_lists_ref[0] != null:
			(fill_lists_ref[0] as Callable).call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Bulk Asg · tags %d · group %d" % [n_tags, n_grp])
	)
	bulk_clr_btn.pressed.connect(func() -> void:
		var also_active := Input.is_key_pressed(KEY_SHIFT)
		if also_active:
			bulk_chip_sel = get_route_pack_bulk_selection()
			for b3 in bulk_chip_sel:
				if not b3 is Dictionary:
					continue
				var bk3 := str(b3.get("kind", ""))
				var bv3 := str(b3.get("value", ""))
				if bk3 == "tag":
					active_chip_tags.erase(bv3)
				elif bk3 == "group":
					active_group_chips.erase(bv3)
		clear_route_pack_bulk_selection()
		bulk_chip_sel = []
		refresh_bulk_lbl.call()
		if also_active:
			sync_filter_from_chips.call()
		else:
			if rebuild_cloud_ref[0] != null:
				(rebuild_cloud_ref[0] as Callable).call()
			if rebuild_group_chips_ref[0] != null:
				(rebuild_group_chips_ref[0] as Callable).call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Bulk cleared" + (" + filters" if also_active else ""))
	)
	var rebuild_group_tree := func() -> void:
		group_tree.clear()
		var root := group_tree.create_item()
		var all_item := group_tree.create_item(root)
		all_item.set_text(0, "All packs")
		all_item.set_metadata(0, "*")
		var un_item := group_tree.create_item(root)
		un_item.set_text(0, "∅ ungrouped")
		un_item.set_metadata(0, "")
		# Build nested tree from group paths.
		var node_map: Dictionary = {}  # path -> TreeItem
		for ge2 in list_all_pack_library_groups():
			if not ge2 is Dictionary:
				continue
			var gpath2 := str((ge2 as Dictionary).get("group", ""))
			if gpath2.is_empty():
				continue
			var parts_g := gpath2.split("/")
			var acc := ""
			var parent_item: TreeItem = root
			for pi in parts_g.size():
				var seg := str(parts_g[pi])
				acc = seg if acc.is_empty() else (acc + "/" + seg)
				if node_map.has(acc):
					parent_item = node_map[acc] as TreeItem
					continue
				var it := group_tree.create_item(parent_item)
				var cnt_leaf := int((ge2 as Dictionary).get("count", 0)) if pi == parts_g.size() - 1 else 0
				# Recount packs under this path for intermediate nodes.
				if cnt_leaf <= 0 or pi < parts_g.size() - 1:
					var under_n := 0
					for e3 in list_route_pack_library("", "mtime"):
						if e3 is Dictionary and _group_is_under(str((e3 as Dictionary).get("group", "")), acc):
							under_n += 1
					cnt_leaf = under_n
				it.set_text(0, "%s (%d)" % [seg, cnt_leaf])
				it.set_metadata(0, acc)
				it.set_tooltip_text(0, "Filter @group:%s" % acc)
				node_map[acc] = it
				parent_item = it
	var fill_lists := func() -> void:
		var q := filter_edit.text
		# Keep ★ only chip in sync with @fav token in filter text.
		var q_low := q.to_lower()
		var has_fav_tok := "@fav" in q_low or ":fav" in q_low or "★" in q
		if fav_only.button_pressed != has_fav_tok:
			fav_only.set_pressed_no_signal(has_fav_tok)
		var sm: String = str(sort_mode_from_opt.call())
		# Pass 44: live chip counts from base filter WITHOUT group tokens.
		var base_parts: PackedStringArray = PackedStringArray()
		for part_b in q.split(" "):
			var pb := str(part_b).strip_edges()
			if pb.is_empty():
				continue
			var pbl := pb.to_lower()
			if pbl.begins_with("@group:") or pbl.begins_with("@g:") or pbl in [
				"@groupor", "@gor", "@or_groups", "@groups_or",
				"@tagor", "@tor", "@or_tags", "@tags_or",
			]:
				continue
			base_parts.append(pb)
		var base_q := " ".join(base_parts)
		last_visible_entries = list_route_pack_library(base_q, sm)
		var entries: Array = list_route_pack_library(q, sm)
		list_l.clear()
		list_r.clear()
		var last_group_hdr := "\u0001"  # impossible
		for e in entries:
			if not e is Dictionary:
				continue
			var ed: Dictionary = e
			var nm := str(ed.get("name", "?"))
			var kb := int(ed.get("bytes", 0))
			var tags: Array = ed.get("tags", []) if ed.get("tags") is Array else []
			var note := str(ed.get("note", ""))
			var fav := bool(ed.get("favorite", false))
			var grp := _sanitize_pack_library_group(str(ed.get("group", "")))
			# Pass 40/41: nested group headers when sorted by group.
			if sm == "group":
				var gkey := grp if not grp.is_empty() else "(ungrouped)"
				if gkey != last_group_hdr:
					last_group_hdr = gkey
					var depth := _group_depth(grp)
					var indent := ""
					for _di in maxi(0, depth - 1):
						indent += "  "
					var leaf := gkey
					if gkey.contains("/"):
						leaf = gkey.get_file() if gkey.get_file() != gkey else gkey.substr(gkey.rfind("/") + 1)
					var hdr := "%s▸ %s" % [indent, leaf if not grp.is_empty() else "(ungrouped)"]
					list_l.add_item(hdr)
					var hi := list_l.item_count - 1
					list_l.set_item_disabled(hi, true)
					# Metadata: "group:path" for drop targets (Pass 41 drag).
					list_l.set_item_metadata(hi, "group:" + grp)
					list_l.set_item_tooltip(hi, "Group path: %s · drop pack here" % (grp if not grp.is_empty() else "(ungrouped)"))
					list_r.add_item(hdr)
					list_r.set_item_disabled(list_r.item_count - 1, true)
					list_r.set_item_metadata(list_r.item_count - 1, "group:" + grp)
			var tag_s := ""
			if not tags.is_empty():
				var tp: PackedStringArray = PackedStringArray()
				for tg in tags:
					tp.append("#" + str(tg))
				tag_s = " " + " ".join(tp)
			var note_mark := " ✎" if not note.is_empty() else ""
			var fav_mark := "★ " if fav else ""
			var grp_mark := (" [" + grp + "]") if not grp.is_empty() and sm != "group" else ""
			var pack_indent := ""
			if sm == "group" and not grp.is_empty():
				for _di2 in _group_depth(grp):
					pack_indent += "  "
			var line := "%s%s%s (%dB)%s%s%s" % [pack_indent, fav_mark, nm, kb, grp_mark, tag_s, note_mark]
			list_l.add_item(line)
			list_l.set_item_metadata(list_l.item_count - 1, nm)
			list_r.add_item(line)
			list_r.set_item_metadata(list_r.item_count - 1, nm)
		rebuild_cloud.call()
		rebuild_group_chips.call()
		rebuild_group_tree.call()
		# Pass 46/47: clear filter progress once rebuild finishes.
		if is_instance_valid(filter_status):
			filter_status.text = ""
			filter_status.disabled = true
	fill_lists_ref[0] = fill_lists
	fill_lists_early_ref[0] = fill_lists
	# Pass 57: select named packs in Left list (JSON bulk packs[]).
	select_packs_ref[0] = func(names: Array) -> int:
		if names.is_empty():
			return 0
		list_l.deselect_all()
		var n_sel := 0
		var first_idx := -1
		var want: Dictionary = {}
		for nm in names:
			want[str(nm).to_lower()] = true
		for i in list_l.item_count:
			var meta := str(list_l.get_item_metadata(i))
			if meta.is_empty() or meta.begins_with("group:"):
				continue
			if want.has(meta.to_lower()):
				list_l.select(i, false)
				if first_idx < 0:
					first_idx = i
				n_sel += 1
		# Pass 58/59: scroll first selected + highlight pulse.
		if first_idx >= 0:
			list_l.select(first_idx, false)
			list_l.ensure_current_is_visible()
			if list_l.has_method("get_item_rect"):
				var ir: Rect2 = list_l.get_item_rect(first_idx)
				if ir.position.y < 0.0 or ir.end.y > list_l.size.y:
					list_l.ensure_current_is_visible()
			# Pass 60: L-cyan pulse with multi-select stagger.
			pulse_item_list_selection(list_l, 0.9, Color(0.35, 0.95, 1.0, 0.55), 0.04 if n_sel > 1 else 0.0)
		return n_sel
	# Pass 48/50/51: layout chrome + dock + optional saved size.
	var apply_lib_layout := func(layout_id: String, use_saved_size: bool = false) -> void:
		var lid2 := layout_id.strip_edges().to_lower()
		if lid2 not in PACK_LIBRARY_LAYOUTS:
			lid2 = "standard"
		var sx := float(window_idx - 1) * 36.0
		var w_preset := 600.0
		var h_preset := 560.0
		match lid2:
			"compact":
				w_preset = 480.0
				h_preset = 440.0
				list_l.custom_minimum_size = Vector2(0, 100)
				list_r.custom_minimum_size = Vector2(0, 100)
				right_col.visible = true
				tree_col.visible = false
				note_edit.custom_minimum_size = Vector2(0, 32)
			"wide":
				w_preset = 840.0
				h_preset = 600.0
				list_l.custom_minimum_size = Vector2(0, 180)
				list_r.custom_minimum_size = Vector2(0, 180)
				right_col.visible = true
				tree_col.visible = true
				note_edit.custom_minimum_size = Vector2(0, 48)
			"left":
				w_preset = 640.0
				h_preset = 560.0
				list_l.custom_minimum_size = Vector2(0, 160)
				list_r.custom_minimum_size = Vector2(0, 160)
				right_col.visible = false
				tree_col.visible = true
				note_edit.custom_minimum_size = Vector2(0, 48)
			_:
				w_preset = 600.0
				h_preset = 560.0
				list_l.custom_minimum_size = Vector2(0, 140)
				list_r.custom_minimum_size = Vector2(0, 140)
				right_col.visible = true
				tree_col.visible = true
				note_edit.custom_minimum_size = Vector2(0, 48)
		if use_saved_size:
			var prefs_sz := load_pack_risk_heat_prefs()
			w_preset = clampf(float(prefs_sz.get("library_w", w_preset)), 400.0, 1200.0)
			h_preset = clampf(float(prefs_sz.get("library_h", h_preset)), 360.0, 1000.0)
			cur_dock = get_library_dock_for_window(window_idx)
		_apply_library_dock_layout(c, cur_dock, w_preset, h_preset, sx)
		# Persist resulting size + per-window dock.
		var snap_sz := _snapshot_pack_map_ui_prefs()
		var w_now := absf(c.offset_right - c.offset_left)
		var h_now := absf(c.offset_bottom - c.offset_top)
		var prefs_d := load_pack_risk_heat_prefs()
		var docks_m: Dictionary = {}
		if prefs_d.get("library_docks") is Dictionary:
			docks_m = (prefs_d.get("library_docks") as Dictionary).duplicate(true)
		docks_m[str(window_idx)] = cur_dock
		save_pack_risk_heat_prefs(
			bool(snap_sz.get("show", true)),
			float(snap_sz.get("intensity", 1.0)),
			float(snap_sz.get("legend_opacity", 1.0)),
			str(snap_sz.get("heat_ramp", "classic")),
			lid2,
			str(snap_sz.get("heat_cool", "")),
			str(snap_sz.get("heat_hot", "")),
			w_now,
			h_now,
			null,
			cur_dock if window_idx <= 1 else str(prefs_d.get("library_dock", "float")),
			docks_m,
			float(prefs_d.get("library_opacity", 1.0))
		)
	apply_lib_layout_ref[0] = apply_lib_layout
	# Initial: layout chrome + restored drag size.
	apply_lib_layout.call(cur_layout, true)
	# Pass 50: bottom-right resize grip (drag to grow/shrink, persists).
	var grip_row := HBoxContainer.new()
	grip_row.add_theme_constant_override("separation", 4)
	vbox.add_child(grip_row)
	var grip_sp := Control.new()
	grip_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grip_row.add_child(grip_sp)
	var grip_btn := Button.new()
	grip_btn.text = "◢"
	grip_btn.focus_mode = Control.FOCUS_NONE
	grip_btn.flat = true
	grip_btn.custom_minimum_size = Vector2(28, 18)
	grip_btn.add_theme_font_size_override("font_size", 12)
	grip_btn.tooltip_text = "Drag to resize library window (size persisted)"
	grip_btn.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	RetrowaveTheme.style_secondary_button(grip_btn)
	grip_row.add_child(grip_btn)
	var resize_state: Array = [false, Vector2.ZERO, 600.0, 560.0]  # dragging, start_mouse, w, h
	grip_btn.gui_input.connect(func(ev_g: InputEvent) -> void:
		if ev_g is InputEventMouseButton:
			var mb := ev_g as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					resize_state[0] = true
					resize_state[1] = mb.global_position
					resize_state[2] = absf(c.offset_right - c.offset_left)
					resize_state[3] = absf(c.offset_bottom - c.offset_top)
					grip_btn.accept_event()
				else:
					if bool(resize_state[0]):
						resize_state[0] = false
						var snap_g := _snapshot_pack_map_ui_prefs()
						save_pack_risk_heat_prefs(
							bool(snap_g.get("show", true)),
							float(snap_g.get("intensity", 1.0)),
							float(snap_g.get("legend_opacity", 1.0)),
							str(snap_g.get("heat_ramp", "classic")),
							str(snap_g.get("library_layout", "standard")),
							str(snap_g.get("heat_cool", "")),
							str(snap_g.get("heat_hot", "")),
							absf(c.offset_right - c.offset_left),
							absf(c.offset_bottom - c.offset_top)
						)
					grip_btn.accept_event()
		elif ev_g is InputEventMouseMotion and bool(resize_state[0]):
			var mm := ev_g as InputEventMouseMotion
			var delta: Vector2 = mm.global_position - (resize_state[1] as Vector2)
			var nw := clampf(float(resize_state[2]) + delta.x, 400.0, 1200.0)
			var nh := clampf(float(resize_state[3]) + delta.y, 360.0, 1000.0)
			var sx2 := float(window_idx - 1) * 36.0
			_apply_library_dock_layout(c, cur_dock, nw, nh, sx2)
			grip_btn.accept_event()
	)
	fill_lists.call()
	# Pass 45–47: debounced filter (~180ms) + Updating… + cancel token.
	var filter_debounce_gen := [0]
	var cancel_pending_filter := func() -> void:
		filter_debounce_gen[0] = int(filter_debounce_gen[0]) + 1
		if is_instance_valid(filter_status):
			filter_status.text = "Cancelled"
			filter_status.disabled = true
			get_tree().create_timer(0.7).timeout.connect(func() -> void:
				if is_instance_valid(filter_status) and filter_status.text == "Cancelled":
					filter_status.text = ""
			)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Filter update cancelled")
	filter_status.pressed.connect(func() -> void:
		if filter_status.text.begins_with("Updating"):
			cancel_pending_filter.call()
	)
	filter_edit.text_changed.connect(func(_t: String) -> void:
		filter_debounce_gen[0] = int(filter_debounce_gen[0]) + 1
		var gen_now: int = int(filter_debounce_gen[0])
		if is_instance_valid(filter_status):
			filter_status.text = "Updating… ✕"
			filter_status.disabled = false
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if gen_now != int(filter_debounce_gen[0]):
				return
			if not is_instance_valid(panel):
				return
			fill_lists.call()
		)
	)
	filter_edit.text_submitted.connect(func(t: String) -> void:
		# Immediate refresh on Enter (bypass debounce lag).
		filter_debounce_gen[0] = int(filter_debounce_gen[0]) + 1
		if is_instance_valid(filter_status):
			filter_status.text = "Updating… ✕"
			filter_status.disabled = false
		push_route_pack_search_history(t)
		_hist_load.call()
		fill_lists.call()
	)
	# Pass 47: Esc cancels pending debounced filter while search has focus.
	filter_edit.gui_input.connect(func(ev_f: InputEvent) -> void:
		if ev_f is InputEventKey and ev_f.pressed and not ev_f.echo and ev_f.keycode == KEY_ESCAPE:
			if is_instance_valid(filter_status) and filter_status.text.begins_with("Updating"):
				cancel_pending_filter.call()
				filter_edit.accept_event()
	)
	group_tree.multi_selected.connect(func(_item: TreeItem, _col: int, _selected: bool) -> void:
		# Pass 43: multi-selected tree groups → active chips (OR when ≥2 or Grp OR on).
		active_group_chips.clear()
		var sel_item: TreeItem = group_tree.get_next_selected(null)
		while sel_item != null:
			var meta_m := str(sel_item.get_metadata(0))
			if meta_m == "*":
				active_group_chips.clear()
				break
			if not active_group_chips.has(meta_m):
				active_group_chips.append(meta_m)
			sel_item = group_tree.get_next_selected(sel_item)
		if active_group_chips.size() >= 2 and not group_or_chk.button_pressed:
			# Multi tree select implies OR for usability.
			group_or_chk.set_pressed_no_signal(true)
		sync_filter_from_chips.call()
	)
	group_tree.item_activated.connect(func() -> void:
		var it2 := group_tree.get_selected()
		if it2 == null:
			return
		var meta_a := str(it2.get_metadata(0))
		if meta_a == "*":
			group_edit.text = ""
			return
		group_edit.text = meta_a
	)
	tree_assign.pressed.connect(func() -> void:
		var names_a: Array = []
		for si in list_l.get_selected_items():
			var m := str(list_l.get_item_metadata(int(si)))
			if not m.is_empty() and not m.begins_with("group:"):
				names_a.append(m)
		if names_a.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Assign Sel · select Left packs")
			return
		var tgt := ""
		var sit: TreeItem = group_tree.get_next_selected(null)
		if sit != null:
			var mt := str(sit.get_metadata(0))
			if mt != "*":
				tgt = mt
		else:
			tgt = group_edit.text
		var n_as := bulk_group_route_pack_library(names_a, tgt)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Assign Sel · %d → %s" % [
				n_as, tgt if not tgt.is_empty() else "(ungrouped)"
			])
	)
	# Pass 44: tree accepts pack drops (multi-move into group under cursor).
	var tree_drag_fn := func(_at: Vector2) -> Variant:
		var names_td2: Array = []
		for si2 in list_l.get_selected_items():
			var m2 := str(list_l.get_item_metadata(int(si2)))
			if not m2.is_empty() and not m2.begins_with("group:"):
				names_td2.append(m2)
		if names_td2.is_empty():
			return null
		var prev_t := Label.new()
		prev_t.text = "→ tree %d" % names_td2.size()
		group_tree.set_drag_preview(prev_t)
		return {"type": "lib_pack", "names": names_td2}
	var tree_can_fn := func(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and str((data as Dictionary).get("type", "")) == "lib_pack"
	var tree_drop_fn := func(at: Vector2, data: Variant) -> void:
		if not (data is Dictionary):
			return
		var names_td: Array = (data as Dictionary).get("names", []) if (data as Dictionary).get("names") is Array else []
		if names_td.is_empty():
			return
		var item_at: TreeItem = group_tree.get_item_at_position(at)
		var tgt_g := ""
		if item_at != null:
			var mtg := str(item_at.get_metadata(0))
			if mtg != "*":
				tgt_g = mtg
		var n_td := bulk_group_route_pack_library(names_td, tgt_g)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Tree drop · %d → %s" % [
				n_td, tgt_g if not tgt_g.is_empty() else "(ungrouped)"
			])
	group_tree.set_drag_forwarding(tree_drag_fn, tree_can_fn, tree_drop_fn)
	hist_opt.item_selected.connect(func(idx: int) -> void:
		if idx <= 0:
			return
		var meta_h = hist_opt.get_item_metadata(idx)
		var hq2 := ""
		if meta_h is Dictionary:
			hq2 = str((meta_h as Dictionary).get("q", ""))
			# Pass 43: Shift+select toggles pin instead of applying.
			if Input.is_key_pressed(KEY_SHIFT):
				toggle_route_pack_search_history_pinned(hq2)
				_hist_load.call()
				hist_opt.select(0)
				return
		else:
			hq2 = str(meta_h)
		if not hq2.is_empty():
			filter_edit.text = hq2
			filter_edit.text_changed.emit(hq2)
		hist_opt.select(0)
	)
	sort_opt.item_selected.connect(func(_i: int) -> void:
		fill_lists.call()
	)
	# Pass 41: drag pack → group header to reassign nested group.
	var list_drag := func(_at: Vector2) -> Variant:
		var sels := list_l.get_selected_items()
		if sels.is_empty():
			return null
		var names_d: Array = []
		for si in sels:
			var meta_d := str(list_l.get_item_metadata(int(si)))
			if meta_d.is_empty() or meta_d.begins_with("group:"):
				continue
			names_d.append(meta_d)
		if names_d.is_empty():
			return null
		var preview_d := Label.new()
		preview_d.text = "→ %d pack(s)" % names_d.size()
		list_l.set_drag_preview(preview_d)
		return {"type": "lib_pack", "names": names_d}
	var list_can := func(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and str((data as Dictionary).get("type", "")) == "lib_pack"
	var list_drop := func(at: Vector2, data: Variant) -> void:
		if not (data is Dictionary):
			return
		var names_drop: Array = (data as Dictionary).get("names", []) if (data as Dictionary).get("names") is Array else []
		if names_drop.is_empty():
			return
		var idx_drop := list_l.get_item_at_position(at, true)
		if idx_drop < 0:
			return
		var meta_t := str(list_l.get_item_metadata(idx_drop))
		var target_g := ""
		if meta_t.begins_with("group:"):
			target_g = meta_t.substr(6)
		elif not meta_t.is_empty():
			# Dropped on a pack → take that pack's group.
			target_g = str(get_route_pack_library_tags(meta_t).get("group", ""))
		else:
			return
		var n_mv := bulk_group_route_pack_library(names_drop, target_g)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Move → %s · %d pack(s)" % [
				target_g if not target_g.is_empty() else "(ungrouped)", n_mv
			])
	list_l.set_drag_forwarding(list_drag, list_can, list_drop)
	var update_preview := func() -> void:
		var sl := list_l.get_selected_items()
		var sr := list_r.get_selected_items()
		var parts: PackedStringArray = PackedStringArray()
		if not sl.is_empty():
			var nl := str(list_l.get_item_metadata(sl[0]))
			var pl := peek_route_pack_library(nl)
			if bool(pl.get("ok", false)):
				parts.append("L «%s» A %.0f%%/%dh B %.0f%%/%dh" % [
					nl,
					float(pl.get("risk_a", 0.0)) * 100.0, int(pl.get("hops_a", 0)),
					float(pl.get("risk_b", 0.0)) * 100.0, int(pl.get("hops_b", 0)),
				])
				var tgl: Array = pl.get("tags", []) if pl.get("tags") is Array else []
				if not tgl.is_empty():
					var tps: PackedStringArray = PackedStringArray()
					for tgx in tgl:
						tps.append(str(tgx))
					parts.append("tags: " + ", ".join(tps))
				var note_l := str(pl.get("note", ""))
				if not note_l.is_empty():
					parts.append("note: " + note_l.substr(0, 80))
				# Pass 37/38: load notes + favorite state into editor for Left selection.
				var ti := get_route_pack_library_tags(nl)
				note_edit.text = str(ti.get("note", ""))
				if bool(ti.get("favorite", false)):
					parts.append("★ favorite")
				var grp_l := str(ti.get("group", ""))
				if not grp_l.is_empty():
					parts.append("group: " + grp_l)
					if group_edit.text.strip_edges().is_empty():
						group_edit.text = grp_l
				var tgs: Array = ti.get("tags", []) if ti.get("tags") is Array else []
				if not tgs.is_empty() and tags_edit.text.strip_edges().is_empty():
					var tps2: PackedStringArray = PackedStringArray()
					for tg2 in tgs:
						tps2.append(str(tg2))
					tags_edit.text = ", ".join(tps2)
		if not sr.is_empty():
			var nr := str(list_r.get_item_metadata(sr[0]))
			var pr := peek_route_pack_library(nr)
			if bool(pr.get("ok", false)):
				parts.append("R «%s» A %.0f%%/%dh B %.0f%%/%dh" % [
					nr,
					float(pr.get("risk_a", 0.0)) * 100.0, int(pr.get("hops_a", 0)),
					float(pr.get("risk_b", 0.0)) * 100.0, int(pr.get("hops_b", 0)),
				])
		preview.text = "\n".join(parts) if not parts.is_empty() else "Select packs · peek risks on select"
	list_l.item_selected.connect(func(_i: int) -> void:
		update_preview.call()
		# Pass 59/60: L cyan pulse; multi-select cascades.
		var n_l := list_l.get_selected_items().size()
		pulse_item_list_selection(
			list_l, 0.45, Color(0.35, 0.95, 1.0, 0.55), 0.035 if n_l > 1 else 0.0
		)
	)
	list_r.item_selected.connect(func(_i: int) -> void:
		update_preview.call()
		# Pass 60: R magenta/amber pulse.
		var n_r := list_r.get_selected_items().size()
		pulse_item_list_selection(
			list_r, 0.45, Color(1.0, 0.45, 0.85, 0.55), 0.035 if n_r > 1 else 0.0
		)
	)
	save_lib.pressed.connect(func() -> void:
		var path := save_route_pack_to_library(name_edit.text, include_history, tags_edit.text, note_edit.text)
		if not path.is_empty() and not group_edit.text.strip_edges().is_empty():
			set_route_pack_library_group(name_edit.text, group_edit.text)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Library save · %s" % path if not path.is_empty() else "Library save failed"
			)
	)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)
	var load_lib := Button.new()
	load_lib.text = "Load L"
	load_lib.focus_mode = Control.FOCUS_NONE
	load_lib.tooltip_text = "Load left selection into map compare"
	RetrowaveTheme.style_secondary_button(load_lib)
	load_lib.pressed.connect(func() -> void:
		var sels := list_l.get_selected_items()
		var nm := ""
		for si0 in sels:
			var m0 := str(list_l.get_item_metadata(int(si0)))
			if not m0.is_empty():
				nm = m0
				break
		if nm.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Library · select Left pack")
			return
		var ok := load_route_pack_from_library(nm)
		_notify_minimap_pack_pins()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Library load OK · %s" % nm if ok else "Library load failed")
		if ok:
			panel.queue_free()
	)
	btn_row.add_child(load_lib)
	var cmp_lib := Button.new()
	cmp_lib.text = "Compare L|R"
	cmp_lib.focus_mode = Control.FOCUS_NONE
	cmp_lib.tooltip_text = "Dual-pane: Left routes → A/B, Right routes → C/D"
	RetrowaveTheme.style_secondary_button(cmp_lib)
	cmp_lib.modulate = Color(1.05, 0.98, 0.85, 1.0)
	cmp_lib.pressed.connect(func() -> void:
		var sl2 := list_l.get_selected_items()
		var sr2 := list_r.get_selected_items()
		if sl2.is_empty() or sr2.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Library · select Left and Right packs")
			return
		var nl2 := str(list_l.get_item_metadata(sl2[0]))
		var nr2 := str(list_r.get_item_metadata(sr2[0]))
		var n := compare_library_packs(nl2, nr2)
		if typeof(DebugOverlay) != TYPE_NIL and n <= 0:
			DebugOverlay.toast_map_debug("Lib compare failed · need valid packs with ≥2 routes each")
		if n > 0:
			panel.queue_free()
	)
	btn_row.add_child(cmp_lib)
	var tag_btn := Button.new()
	tag_btn.text = "Tag+Note L"
	tag_btn.focus_mode = Control.FOCUS_NONE
	tag_btn.tooltip_text = "Apply tags field + notes editor to Left selection"
	RetrowaveTheme.style_secondary_button(tag_btn)
	tag_btn.pressed.connect(func() -> void:
		var sels3 := list_l.get_selected_items()
		if sels3.is_empty():
			return
		var nm3 := str(list_l.get_item_metadata(sels3[0]))
		var tags := _parse_pack_tags(tags_edit.text)
		set_route_pack_library_tags(nm3, tags, note_edit.text)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Tags+note set · %s" % nm3)
	)
	btn_row.add_child(tag_btn)
	# Pass 38: favorite star toggle for Left selection.
	var fav_btn := Button.new()
	fav_btn.text = "★ Fav L"
	fav_btn.focus_mode = Control.FOCUS_NONE
	fav_btn.tooltip_text = "Toggle favorite star on Left selection"
	RetrowaveTheme.style_secondary_button(fav_btn)
	fav_btn.modulate = Color(1.1, 0.95, 0.55, 1.0)
	fav_btn.pressed.connect(func() -> void:
		var sels_f := list_l.get_selected_items()
		if sels_f.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Library · select Left pack to favorite")
			return
		var nm_f := str(list_l.get_item_metadata(sels_f[0]))
		var now_fav := toggle_route_pack_library_favorite(nm_f)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Favorite %s · %s" % ["ON" if now_fav else "OFF", nm_f])
	)
	btn_row.add_child(fav_btn)
	# Pass 38: export library index JSON+CSV.
	var idx_btn := Button.new()
	idx_btn.text = "Index"
	idx_btn.focus_mode = Control.FOCUS_NONE
	idx_btn.tooltip_text = "Export library index → user://route_packs/_index.json (+ .csv)"
	RetrowaveTheme.style_secondary_button(idx_btn)
	idx_btn.pressed.connect(func() -> void:
		var path_i := export_route_pack_library_index()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Index exported · %s" % path_i if not path_i.is_empty() else "Index export failed"
			)
	)
	btn_row.add_child(idx_btn)
	# Pass 41: risk heatmap export from current map pack pins.
	var heat_btn := Button.new()
	heat_btn.text = "Heat"
	heat_btn.focus_mode = Control.FOCUS_NONE
	heat_btn.tooltip_text = "Export risk heatmap PNG from minimap pack pins → user://route_risk_heatmap.png"
	RetrowaveTheme.style_secondary_button(heat_btn)
	heat_btn.modulate = Color(1.1, 0.55, 0.4, 1.0)
	heat_btn.pressed.connect(func() -> void:
		var hp := export_route_pack_risk_heatmap()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Heatmap · %s" % hp if not hp.is_empty() else "Heatmap failed · no pack pins"
			)
		if not hp.is_empty():
			# Reuse QR popup shell for quick preview if possible.
			_show_pack_qr_popup(hp)
	)
	btn_row.add_child(heat_btn)
	# Pass 39/40: import index merge + replace-mode toggle.
	var merge_replace := CheckBox.new()
	merge_replace.text = "Repl"
	merge_replace.focus_mode = Control.FOCUS_NONE
	merge_replace.button_pressed = false
	merge_replace.add_theme_font_size_override("font_size", 9)
	merge_replace.tooltip_text = "When on, Merge Idx replaces tags/note/fav/group from index (else union)"
	btn_row.add_child(merge_replace)
	var merge_btn := Button.new()
	merge_btn.text = "Merge Idx"
	merge_btn.focus_mode = Control.FOCUS_NONE
	merge_btn.tooltip_text = "Import _index.json into local metadata (union or replace). Skip missing .eorp"
	RetrowaveTheme.style_secondary_button(merge_btn)
	merge_btn.pressed.connect(func() -> void:
		var mode_m := "replace" if merge_replace.button_pressed else "union"
		var res: Dictionary = import_route_pack_library_index("user://route_packs/_index.json", mode_m)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			if bool(res.get("ok", false)):
				DebugOverlay.toast_map_debug(
					"Index %s · %d packs · %d skipped" % [
						mode_m, int(res.get("merged", 0)), int(res.get("skipped", 0))
					]
				)
			else:
				DebugOverlay.toast_map_debug("Index merge failed · %s" % str(res.get("error", "?")))
	)
	btn_row.add_child(merge_btn)
	# Helper: collect selected Left pack names (skip group headers).
	var collect_left_names := func() -> Array:
		var names: Array = []
		var sels_b := list_l.get_selected_items()
		if not sels_b.is_empty():
			for si in sels_b:
				var meta_s := str(list_l.get_item_metadata(int(si)))
				if not meta_s.is_empty():
					names.append(meta_s)
		else:
			for i in list_l.item_count:
				var meta_a := str(list_l.get_item_metadata(i))
				if not meta_a.is_empty():
					names.append(meta_a)
		return names
	# Pass 39: bulk tag selected Left packs (or all visible if none selected).
	var bulk_btn := Button.new()
	bulk_btn.text = "Bulk Tag"
	bulk_btn.focus_mode = Control.FOCUS_NONE
	bulk_btn.tooltip_text = "Apply tags field to multi-selected Left packs (or all visible if none selected)"
	RetrowaveTheme.style_secondary_button(bulk_btn)
	bulk_btn.modulate = Color(0.9, 1.05, 0.95, 1.0)
	bulk_btn.pressed.connect(func() -> void:
		var names: Array = collect_left_names.call()
		if names.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Bulk tag · no packs")
			return
		if tags_edit.text.strip_edges().is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Bulk tag · enter tags first")
			return
		var n_upd := bulk_tag_route_pack_library(names, tags_edit.text, false)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Bulk tag · %d pack(s)" % n_upd)
	)
	btn_row.add_child(bulk_btn)
	# Pass 40: bulk untag (remove tags field tags, or clear all if empty).
	var untag_btn := Button.new()
	untag_btn.text = "Untag"
	untag_btn.focus_mode = Control.FOCUS_NONE
	untag_btn.tooltip_text = "Remove tags field from selected packs; empty field clears all tags"
	RetrowaveTheme.style_secondary_button(untag_btn)
	untag_btn.pressed.connect(func() -> void:
		var names_u: Array = collect_left_names.call()
		if names_u.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Untag · no packs")
			return
		var n_u := bulk_untag_route_pack_library(names_u, tags_edit.text)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Untag · %d pack(s)" % n_u)
	)
	btn_row.add_child(untag_btn)
	# Pass 40: assign folder group to selected packs.
	var grp_btn := Button.new()
	grp_btn.text = "Group"
	grp_btn.focus_mode = Control.FOCUS_NONE
	grp_btn.tooltip_text = "Set group field on selected packs (empty group clears)"
	RetrowaveTheme.style_secondary_button(grp_btn)
	grp_btn.pressed.connect(func() -> void:
		var names_g: Array = collect_left_names.call()
		if names_g.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Group · no packs")
			return
		var n_g := bulk_group_route_pack_library(names_g, group_edit.text)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Group · %d pack(s) → %s" % [
				n_g, group_edit.text.strip_edges() if not group_edit.text.strip_edges().is_empty() else "(none)"
			])
	)
	btn_row.add_child(grp_btn)
	var del_lib := Button.new()
	del_lib.text = "Delete L"
	del_lib.focus_mode = Control.FOCUS_NONE
	RetrowaveTheme.style_secondary_button(del_lib)
	del_lib.pressed.connect(func() -> void:
		var sels4 := list_l.get_selected_items()
		if sels4.is_empty():
			return
		var nm4 := str(list_l.get_item_metadata(sels4[0]))
		var ok4 := delete_route_pack_from_library(nm4)
		fill_lists.call()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Library deleted · %s" % nm4 if ok4 else "Delete failed")
	)
	btn_row.add_child(del_lib)
	var close_lib := Button.new()
	close_lib.text = "Close"
	close_lib.focus_mode = Control.FOCUS_NONE
	RetrowaveTheme.style_secondary_button(close_lib)
	close_lib.pressed.connect(func() -> void:
		panel.queue_free()
	)
	btn_row.add_child(close_lib)
	list_l.item_activated.connect(func(idx: int) -> void:
		var nm5 := str(list_l.get_item_metadata(idx))
		if load_route_pack_from_library(nm5):
			_notify_minimap_pack_pins()
			panel.queue_free()
	)


## Pass 34: swap two pack slots (data + labels + day-history tracks). Returns true if either moved.
func swap_route_compare_slots(slot_a: int, slot_b: int) -> bool:
	if slot_a == slot_b:
		return false
	if slot_a < 0 or slot_a >= 4 or slot_b < 0 or slot_b >= 4:
		return false
	while _route_compare_slots.size() < 4:
		_route_compare_slots.append({})
	while _route_compare_slot_labels.size() < 4:
		_route_compare_slot_labels.append("")
	var tmp_d = _route_compare_slots[slot_a]
	_route_compare_slots[slot_a] = _route_compare_slots[slot_b]
	_route_compare_slots[slot_b] = tmp_d
	var tmp_l = _route_compare_slot_labels[slot_a]
	_route_compare_slot_labels[slot_a] = _route_compare_slot_labels[slot_b]
	_route_compare_slot_labels[slot_b] = tmp_l
	# Swap day-history tracks if present.
	var ka := "slot%d" % slot_a
	var kb := "slot%d" % slot_b
	var ha = _route_risk_day_history.get(ka, null)
	var hb = _route_risk_day_history.get(kb, null)
	if ha != null:
		_route_risk_day_history[kb] = (ha as Dictionary).duplicate(true) if ha is Dictionary else ha
	elif _route_risk_day_history.has(kb):
		_route_risk_day_history.erase(kb)
	if hb != null:
		_route_risk_day_history[ka] = (hb as Dictionary).duplicate(true) if hb is Dictionary else hb
	elif _route_risk_day_history.has(ka):
		_route_risk_day_history.erase(ka)
	_notify_minimap_pack_pins()
	return true


## Pass 34: move slot content from `from_slot` into `to_slot` by swapping along the way (bubble).
func move_route_compare_slot(from_slot: int, to_slot: int) -> bool:
	if from_slot == to_slot:
		return false
	if from_slot < 0 or from_slot >= 4 or to_slot < 0 or to_slot >= 4:
		return false
	var step := 1 if to_slot > from_slot else -1
	var i := from_slot
	while i != to_slot:
		swap_route_compare_slots(i, i + step)
		i += step
	return true


## Pass 34/36: legend entries for minimap/card — one per filled pack slot.
## [{slot, label, color, routes, tooltip, risk_a, risk_b, hops_a, hops_b}]
func get_pack_slot_legend() -> Array:
	var slot_colors := [
		Color(0.45, 0.9, 1.0, 0.95),
		Color(1.0, 0.5, 0.85, 0.95),
		Color(1.0, 0.82, 0.35, 0.95),
		Color(0.45, 0.95, 0.55, 0.95),
	]
	var out: Array = []
	for si in mini(4, _route_compare_slots.size()):
		if not route_compare_slot_filled(si):
			continue
		var sd: Dictionary = _route_compare_slots[si] if _route_compare_slots[si] is Dictionary else {}
		var nrt := 2
		if bool(sd.get("has_d", false)) or int(sd.get("hops_d", 0)) > 0:
			nrt = 4
		elif bool(sd.get("has_c", false)) or int(sd.get("hops_c", 0)) > 0:
			nrt = 3
		var lab := get_route_compare_slot_label(si)
		if lab.is_empty():
			lab = "P%d" % (si + 1)
		var ra := float(sd.get("risk_a", 0.0))
		var rb := float(sd.get("risk_b", 0.0))
		var ha := int(sd.get("hops_a", 0))
		var hb := int(sd.get("hops_b", 0))
		var tip := "Slot %d «%s» · %d routes · A %.0f%%/%dh · B %.0f%%/%dh · click to load" % [
			si + 1, lab, nrt, ra * 100.0, ha, rb * 100.0, hb
		]
		if nrt >= 3:
			tip += " · C %.0f%%" % (float(sd.get("risk_c", 0.0)) * 100.0)
		if nrt >= 4:
			tip += " · D %.0f%%" % (float(sd.get("risk_d", 0.0)) * 100.0)
		out.append({
			"slot": si,
			"label": lab,
			"color": slot_colors[si % slot_colors.size()],
			"routes": nrt,
			"risk_a": ra,
			"risk_b": rb,
			"hops_a": ha,
			"hops_b": hb,
			"tooltip": tip,
		})
	return out


## Pass 31/32: show a popup with the QR texture if available.
func _show_pack_qr_popup(png_path: String, title_text: String = "Pack QR") -> void:
	if png_path.is_empty() or not FileAccess.file_exists(png_path):
		return
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var old := ui.get_node_or_null("PackQRPopup")
	if old != null:
		old.queue_free()
	var panel := PanelContainer.new()
	panel.name = "PackQRPopup"
	RetrowaveTheme.style_world_panel(panel)
	ui.add_child(panel)
	var c := panel as Control
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.offset_left = -140.0
	c.offset_right = 140.0
	c.offset_top = -168.0
	c.offset_bottom = 168.0
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = title_text if not title_text.is_empty() else "Pack QR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	RetrowaveTheme.style_body_label(title)
	title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	vbox.add_child(title)
	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(220, 220)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var img := Image.load_from_file(ProjectSettings.globalize_path(png_path))
	if img != null:
		tex_rect.texture = ImageTexture.create_from_image(img)
	vbox.add_child(tex_rect)
	var path_lbl := Label.new()
	path_lbl.text = png_path + " · engine/CLI"
	path_lbl.add_theme_font_size_override("font_size", 9)
	path_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(path_lbl)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	RetrowaveTheme.style_secondary_button(close_btn)
	close_btn.pressed.connect(func() -> void:
		panel.queue_free()
	)
	vbox.add_child(close_btn)


## Pass 30–32: pins for minimap — multi-pin per pack + polyline world points per route.
func get_pack_slot_pins() -> Array:
	var out: Array = []
	var slot_colors := [
		Color(0.45, 0.9, 1.0, 0.95),
		Color(1.0, 0.5, 0.85, 0.95),
		Color(1.0, 0.82, 0.35, 0.95),
		Color(0.45, 0.95, 0.55, 0.95),
	]
	var route_keys := ["path_a", "path_b", "path_c", "path_d"]
	var route_letters := ["A", "B", "C", "D"]
	var route_tint := [
		Color(0.45, 0.9, 1.0, 0.95),
		Color(1.0, 0.5, 0.85, 0.95),
		Color(1.0, 0.82, 0.35, 0.95),
		Color(0.45, 0.95, 0.55, 0.95),
	]
	for si in mini(4, _route_compare_slots.size()):
		var d = _route_compare_slots[si]
		if not d is Dictionary or (d as Dictionary).is_empty():
			continue
		var sd: Dictionary = d
		var lab := get_route_compare_slot_label(si)
		if lab.is_empty():
			lab = "P%d" % (si + 1)
		var nrt := 0
		for ri in 4:
			var path: Array = sd.get(route_keys[ri], []) as Array if sd.get(route_keys[ri]) is Array else []
			if path.is_empty():
				continue
			nrt += 1
			var mid_pid := int(path[path.size() / 2])
			var pos := Vector2.ZERO
			if province_centroids.has(mid_pid):
				pos = province_centroids[mid_pid] as Vector2
			elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
				pos = MapManager.get_province_centroid(mid_pid)
			if pos == Vector2.ZERO:
				continue
			# Pass 32: world polyline along province centroids (decimated for long paths).
			var poly: Array = _path_to_world_polyline(path, 12)
			# Slight fan-out so multi-pins don't fully stack.
			var fan := Vector2(float(ri) * 8.0 - 12.0, float(si) * 6.0 - 9.0)
			var risk_key := "risk_%s" % route_letters[ri].to_lower()
			var risk_v := float(sd.get(risk_key, 0.0))
			var hops_v := path.size()
			var owner_key := "owner_%s" % route_letters[ri].to_lower()
			var owner_v := str(sd.get(owner_key, ""))
			# Pass 37: pin hover tooltip.
			var tip := "Pack «%s» route %s · %d hops · risk %.0f%%%s · click to load" % [
				lab, route_letters[ri], hops_v, risk_v * 100.0,
				(" · " + owner_v) if not owner_v.is_empty() else ""
			]
			# Pass 38: base route color blended toward hot red by risk intensity.
			var base_col: Color = route_tint[ri].lerp(slot_colors[si % slot_colors.size()], 0.35)
			var risk_col := Color(1.0, 0.28, 0.22, 0.95)
			var col := base_col.lerp(risk_col, clampf(risk_v, 0.0, 1.0) * 0.72)
			out.append({
				"slot": si,
				"route_index": ri,
				"route_letter": route_letters[ri],
				"pos": pos + fan,
				"label": "%s·%s" % [lab.substr(0, 4), route_letters[ri]],
				"routes": 0,  # filled after
				"color": col,
				"base_color": base_col,
				"focus_pid": mid_pid,
				"primary": ri == 0,
				"polyline": poly,
				"tooltip": tip,
				"risk": risk_v,
				"hops": hops_v,
			})
		# Annotate route count on all pins of this slot.
		for pin in out:
			if int(pin.get("slot", -1)) == si:
				pin["routes"] = nrt
	return out


## Pass 32: province path → world centroid polyline (max max_pts, always keeps ends).
func _path_to_world_polyline(path: Array, max_pts: int = 12) -> Array:
	var pts: Array = []
	if path.is_empty():
		return pts
	var step := 1
	if path.size() > max_pts:
		step = maxi(1, int(ceili(float(path.size()) / float(max_pts))))
	var i := 0
	while i < path.size():
		var pid := int(path[i])
		var p := Vector2.ZERO
		if province_centroids.has(pid):
			p = province_centroids[pid] as Vector2
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			p = MapManager.get_province_centroid(pid)
		if p != Vector2.ZERO:
			pts.append(p)
		i += step
	# Ensure last hop included.
	var last_pid := int(path[path.size() - 1])
	var last_p := Vector2.ZERO
	if province_centroids.has(last_pid):
		last_p = province_centroids[last_pid] as Vector2
	elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
		last_p = MapManager.get_province_centroid(last_pid)
	if last_p != Vector2.ZERO and (pts.is_empty() or pts[pts.size() - 1] != last_p):
		pts.append(last_p)
	return pts


## Pass 32/33: merge filled pack slots into A–D compare.
## Slot order weight: earlier slots preferred when risk is close (score = risk + slot*0.04 + route*0.01).
## slot_indices empty → all filled slots. Returns number of routes packed (0 if <2).
func merge_route_compare_slots(slot_indices: Array = []) -> int:
	var indices: Array = []
	if slot_indices.is_empty():
		for si in mini(4, _route_compare_slots.size()):
			if route_compare_slot_filled(si):
				indices.append(si)
	else:
		for v in slot_indices:
			var si2 := int(v)
			if route_compare_slot_filled(si2):
				indices.append(si2)
	if indices.size() < 1:
		return 0
	var route_keys := ["path_a", "path_b", "path_c", "path_d"]
	var risk_keys := ["risk_a", "risk_b", "risk_c", "risk_d"]
	var owner_keys := ["owner_a", "owner_b", "owner_c", "owner_d"]
	var focus_keys := ["focus_a", "focus_b", "focus_c", "focus_d"]
	var seen: Dictionary = {}  # path signature → true
	var ranked: Array = []
	for si in indices:
		var sd: Dictionary = _route_compare_slots[si] if _route_compare_slots[si] is Dictionary else {}
		if sd.is_empty():
			continue
		for ri in 4:
			var path: Array = sd.get(route_keys[ri], []) as Array if sd.get(route_keys[ri]) is Array else []
			if path.size() < 2:
				continue
			var sig := _path_signature(path)
			if seen.has(sig):
				continue
			seen[sig] = true
			var risk := float(sd.get(risk_keys[ri], 0.0))
			var live := estimate_path_interdiction(path)
			if live >= 0.0:
				risk = live
			var focus_pid := int(sd.get(focus_keys[ri], -1))
			if focus_pid < 0:
				focus_pid = int(path[path.size() - 1])
			# Pass 33: slot-order weight (slot 0 preferred).
			var score := risk + float(si) * 0.04 + float(ri) * 0.01
			ranked.append({
				"path": path.duplicate(),
				"interdiction": risk,
				"score": score,
				"slot": si,
				"focus_pid": focus_pid,
				"hops": path.size(),
				"owner_tag": str(sd.get(owner_keys[ri], "")),
			})
	# Also fold current live compare if present (weight between last filled slot).
	if not _last_route_compare_data.is_empty() and indices.size() >= 1:
		var ld: Dictionary = _last_route_compare_data
		var live_slot_w := 0.5  # between slot 0 and 1
		for ri2 in 4:
			var path2: Array = ld.get(route_keys[ri2], []) as Array if ld.get(route_keys[ri2]) is Array else []
			if path2.size() < 2:
				continue
			var sig2 := _path_signature(path2)
			if seen.has(sig2):
				continue
			seen[sig2] = true
			var risk2 := float(ld.get(risk_keys[ri2], 0.0))
			var live2 := estimate_path_interdiction(path2)
			if live2 >= 0.0:
				risk2 = live2
			var score2 := risk2 + live_slot_w * 0.04 + float(ri2) * 0.01
			ranked.append({
				"path": path2.duplicate(),
				"interdiction": risk2,
				"score": score2,
				"slot": -1,
				"focus_pid": int(ld.get(focus_keys[ri2], path2[path2.size() - 1])),
				"hops": path2.size(),
				"owner_tag": str(ld.get(owner_keys[ri2], "")),
			})
	if ranked.size() < 2:
		return 0
	ranked.sort_custom(func(a, b) -> bool:
		var sa := float(a.get("score", a.get("interdiction", 1.0)))
		var sb := float(b.get("score", b.get("interdiction", 1.0)))
		if not is_equal_approx(sa, sb):
			return sa < sb
		return int(a.get("hops", 99)) < int(b.get("hops", 99))
	)
	var paths: Array = []
	var metas: Array = []
	var n := mini(4, ranked.size())
	for i in n:
		var e: Dictionary = ranked[i]
		paths.append((e.get("path", []) as Array).duplicate())
		metas.append({
			"interdiction": float(e.get("interdiction", 0.0)),
			"focus_pid": int(e.get("focus_pid", -1)),
			"owner_tag": str(e.get("owner_tag", "")),
		})
	compare_supply_routes_multi(paths, metas)
	_notify_minimap_pack_pins()
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Pack merge · %d route(s) from %d slot(s) · slot-weighted" % [n, indices.size()])
	return n


## Pass 32: stable signature for path dedupe.
func _path_signature(path: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p in path:
		parts.append(str(int(p)))
	return "|".join(parts)


## Pass 21/28: save last compare into slot 0–3 (supports A–D pack).
func save_route_compare_slot(slot: int) -> bool:
	if slot < 0 or slot >= 4:
		return false
	if _last_route_compare_data.is_empty():
		return false
	while _route_compare_slots.size() < 4:
		_route_compare_slots.append({})
	_route_compare_slots[slot] = _last_route_compare_data.duplicate(true)
	# Pass 25: copy day-history track to slot key.
	if _route_risk_day_history.has("last"):
		_route_risk_day_history["slot%d" % slot] = (_route_risk_day_history["last"] as Dictionary).duplicate(true)
	if typeof(DebugOverlay) != TYPE_NIL:
		var nroutes := 2
		if bool(_last_route_compare_data.get("has_d", false)):
			nroutes = 4
		elif bool(_last_route_compare_data.get("has_c", false)):
			nroutes = 3
		DebugOverlay.toast_map_debug("Compare saved → slot %d (%d routes)" % [slot + 1, nroutes])
	return true


## Pass 21/23/28: reload a saved compare pack (A/B or A–D); recompute live risk.
func load_route_compare_slot(slot: int) -> bool:
	if slot < 0 or slot >= _route_compare_slots.size():
		return false
	var d: Dictionary = _route_compare_slots[slot] if _route_compare_slots[slot] is Dictionary else {}
	if d.is_empty():
		return false
	var path_a: Array = d.get("path_a", []) as Array if d.get("path_a") is Array else []
	var path_b: Array = d.get("path_b", []) as Array if d.get("path_b") is Array else []
	if path_a.is_empty() or path_b.is_empty():
		return false
	var path_c: Array = d.get("path_c", []) as Array if d.get("path_c") is Array else []
	var path_d: Array = d.get("path_d", []) as Array if d.get("path_d") is Array else []
	var saved_a := float(d.get("risk_a", 0.0))
	var saved_b := float(d.get("risk_b", 0.0))
	var saved_c := float(d.get("risk_c", 0.0))
	var saved_d := float(d.get("risk_d", 0.0))
	var live_a := estimate_path_interdiction(path_a)
	var live_b := estimate_path_interdiction(path_b)
	var live_c := estimate_path_interdiction(path_c) if not path_c.is_empty() else -1.0
	var live_d := estimate_path_interdiction(path_d) if not path_d.is_empty() else -1.0
	var meta_a := {
		"interdiction": live_a if live_a >= 0.0 else saved_a,
		"focus_pid": int(d.get("focus_a", -1)),
		"risk_saved": saved_a,
		"risk_live": live_a,
		"risk_recomputed": live_a >= 0.0,
	}
	var meta_b := {
		"interdiction": live_b if live_b >= 0.0 else saved_b,
		"focus_pid": int(d.get("focus_b", -1)),
		"risk_saved": saved_b,
		"risk_live": live_b,
		"risk_recomputed": live_b >= 0.0,
	}
	var meta_c := {
		"interdiction": live_c if live_c >= 0.0 else saved_c,
		"focus_pid": int(d.get("focus_c", -1)),
		"risk_saved": saved_c,
		"risk_live": live_c,
		"risk_recomputed": live_c >= 0.0,
	}
	var meta_d := {
		"interdiction": live_d if live_d >= 0.0 else saved_d,
		"focus_pid": int(d.get("focus_d", -1)),
		"risk_saved": saved_d,
		"risk_live": live_d,
		"risk_recomputed": live_d >= 0.0,
	}
	if live_a >= 0.0:
		d["risk_a"] = live_a
	if live_b >= 0.0:
		d["risk_b"] = live_b
	if live_c >= 0.0:
		d["risk_c"] = live_c
	if live_d >= 0.0:
		d["risk_d"] = live_d
	d["risk_recomputed"] = (live_a >= 0.0 or live_b >= 0.0 or live_c >= 0.0 or live_d >= 0.0)
	_route_compare_slots[slot] = d.duplicate(true)
	var slot_key := "slot%d" % slot
	if _route_risk_day_history.has(slot_key):
		_route_risk_day_history["last"] = (_route_risk_day_history[slot_key] as Dictionary).duplicate(true)
	_ensure_route_risk_history_track(
		"last", path_a, path_b,
		live_a if live_a >= 0.0 else saved_a,
		live_b if live_b >= 0.0 else saved_b,
		path_c, live_c if live_c >= 0.0 else saved_c,
		path_d, live_d if live_d >= 0.0 else saved_d
	)
	var paths: Array = [path_a, path_b]
	var metas: Array = [meta_a, meta_b]
	if not path_c.is_empty():
		paths.append(path_c)
		metas.append(meta_c)
	if not path_d.is_empty():
		paths.append(path_d)
		metas.append(meta_d)
	compare_supply_routes_multi(paths, metas)
	if typeof(DebugOverlay) != TYPE_NIL:
		var delta_note := ""
		if live_a >= 0.0 and live_b >= 0.0:
			delta_note = " · live A %.0f%% B %.0f%%" % [live_a * 100.0, live_b * 100.0]
			if live_c >= 0.0:
				delta_note += " C %.0f%%" % (live_c * 100.0)
			if live_d >= 0.0:
				delta_note += " D %.0f%%" % (live_d * 100.0)
		DebugOverlay.toast_map_debug("Compare loaded · slot %d%s" % [slot + 1, delta_note])
	return true


## Pass 23: live interdiction chance for a province path (0–1), or -1 if unavailable.
func estimate_path_interdiction(path: Array) -> float:
	if path.is_empty():
		return -1.0
	# Prefer matching an active SupplyManager route with same endpoints/path length.
	if typeof(SupplyManager) != TYPE_NIL and SupplyManager.has_method("get_all_routes"):
		var routes: Array = SupplyManager.get_all_routes()
		var path_ids: Array = []
		for p in path:
			path_ids.append(int(p))
		for plan_var in routes:
			if not (plan_var is SupplyRoutePlan):
				continue
			var plan := plan_var as SupplyRoutePlan
			if plan.province_path.size() != path_ids.size():
				continue
			var paths_equal := true
			for i in path_ids.size():
				if int(plan.province_path[i]) != int(path_ids[i]):
					paths_equal = false
					break
			if paths_equal and "interdiction_chance" in plan:
				return clampf(float(plan.interdiction_chance), 0.0, 1.0)
	# Recompute via SupplyInterdictionEstimator when SupplyManager has network state.
	if typeof(SupplyManager) == TYPE_NIL:
		return -1.0
	if SupplyManager.rules == null or SupplyManager.provinces.is_empty():
		return -1.0
	var path_typed: Array[int] = []
	for p2 in path:
		path_typed.append(int(p2))
	var owner := str(SupplyManager.player_tag)
	var presence: Dictionary = {}
	if SupplyManager.has_method("get_enemy_presence"):
		presence = SupplyManager.get_enemy_presence()
	var inter: Dictionary = SupplyInterdictionEstimator.estimate(
		path_typed,
		SupplyManager.provinces,
		SupplyManager.hubs,
		owner,
		SupplyManager.rules,
		presence,
	)
	var chance := float(inter.get("chance", -1.0))
	if chance < 0.0:
		return -1.0
	# Soft storm bump average along path if weather available.
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_storm_interdiction_chance"):
		var storm_max := chance
		for pid_v in path_typed:
			storm_max = maxf(storm_max, float(WeatherManager.get_storm_interdiction_chance(int(pid_v), chance)))
		chance = storm_max
	return clampf(chance, 0.0, 0.95)


func route_compare_slot_filled(slot: int) -> bool:
	if slot < 0 or slot >= _route_compare_slots.size():
		return false
	var d = _route_compare_slots[slot]
	return d is Dictionary and not (d as Dictionary).is_empty()


## Pass 20/21: floating card summarizing last multi-route compare + save slots.
func _show_route_compare_card(data: Dictionary) -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	_last_route_compare_data = data.duplicate(true)
	_route_compare_card_gen += 1
	var card_gen := _route_compare_card_gen
	if _route_compare_card != null and is_instance_valid(_route_compare_card):
		_route_compare_card.queue_free()
	_route_compare_card = PanelContainer.new()
	_route_compare_card.name = "RouteCompareCard"
	RetrowaveTheme.style_world_panel(_route_compare_card)
	ui.add_child(_route_compare_card)
	var c := _route_compare_card as Control
	c.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	c.offset_left = -300.0
	c.offset_right = -12.0
	c.offset_top = 96.0
	c.offset_bottom = 380.0
	c.custom_minimum_size = Vector2(280, 270)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_route_compare_card.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	var title := Label.new()
	title.text = "Route compare"
	RetrowaveTheme.style_body_label(title)
	title.add_theme_color_override("font_color", RetrowaveTheme.CYAN)
	v.add_child(title)
	var hops_a := int(data.get("hops_a", 0))
	var hops_b := int(data.get("hops_b", 0))
	var risk_a := float(data.get("risk_a", 0.0))
	var risk_b := float(data.get("risk_b", 0.0))
	var winner := str(data.get("winner", "A"))
	var owner_a := str(data.get("owner_a", ""))
	var owner_b := str(data.get("owner_b", ""))
	var owner_c := str(data.get("owner_c", ""))
	var owner_d := str(data.get("owner_d", ""))
	var la := Label.new()
	la.text = "A  cyan · %d hops · risk %.0f%%%s" % [
		hops_a, risk_a * 100.0, (" · " + owner_a) if not owner_a.is_empty() else ""
	]
	la.add_theme_font_size_override("font_size", 11)
	la.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	v.add_child(la)
	var lb := Label.new()
	lb.text = "B  magenta · %d hops · risk %.0f%%%s" % [
		hops_b, risk_b * 100.0, (" · " + owner_b) if not owner_b.is_empty() else ""
	]
	lb.add_theme_font_size_override("font_size", 11)
	lb.add_theme_color_override("font_color", Color(1.0, 0.5, 0.85))
	v.add_child(lb)
	var has_c := bool(data.get("has_c", false)) or int(data.get("hops_c", 0)) > 0
	var has_d := bool(data.get("has_d", false)) or int(data.get("hops_d", 0)) > 0
	var hops_c := int(data.get("hops_c", 0))
	var risk_c := float(data.get("risk_c", 0.0))
	var hops_d := int(data.get("hops_d", 0))
	var risk_d := float(data.get("risk_d", 0.0))
	if has_c:
		var lc := Label.new()
		lc.text = "C  amber · %d hops · risk %.0f%%%s" % [
			hops_c, risk_c * 100.0, (" · " + owner_c) if not owner_c.is_empty() else ""
		]
		lc.add_theme_font_size_override("font_size", 11)
		lc.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
		v.add_child(lc)
	if has_d:
		var ld := Label.new()
		ld.text = "D  green · %d hops · risk %.0f%%%s" % [
			hops_d, risk_d * 100.0, (" · " + owner_d) if not owner_d.is_empty() else ""
		]
		ld.add_theme_font_size_override("font_size", 11)
		ld.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
		v.add_child(ld)
	# Pass 23: show when risk was live-recomputed vs saved snapshot.
	if bool(data.get("risk_recomputed", false)):
		var re := Label.new()
		var sa := float(data.get("risk_saved_a", risk_a))
		var sb := float(data.get("risk_saved_b", risk_b))
		re.text = "Live risk · was A %.0f%% / B %.0f%%" % [sa * 100.0, sb * 100.0]
		re.add_theme_font_size_override("font_size", 10)
		re.add_theme_color_override("font_color", Color(0.7, 0.95, 0.75, 0.95))
		v.add_child(re)
	# Pass 24: hop-risk sparklines for A (cyan) and B (magenta).
	var path_a_card: Array = data.get("path_a", []) as Array if data.get("path_a") is Array else []
	var path_b_card: Array = data.get("path_b", []) as Array if data.get("path_b") is Array else []
	var path_c_card: Array = data.get("path_c", []) as Array if data.get("path_c") is Array else []
	var path_d_card: Array = data.get("path_d", []) as Array if data.get("path_d") is Array else []
	# Pass 25/27: seed day-history including optional C/D.
	_ensure_route_risk_history_track(
		"last", path_a_card, path_b_card, risk_a, risk_b, path_c_card, risk_c, path_d_card, risk_d
	)
	var hops_risk_a: Array = estimate_path_hop_risks(path_a_card)
	var hops_risk_b: Array = estimate_path_hop_risks(path_b_card)
	if not hops_risk_a.is_empty() or not hops_risk_b.is_empty():
		var spark_cap := Label.new()
		spark_cap.text = "Hop risk (path-correlated)"
		spark_cap.add_theme_font_size_override("font_size", 9)
		spark_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
		v.add_child(spark_cap)
		var hop_leg := HBoxContainer.new()
		hop_leg.add_theme_constant_override("separation", 8)
		v.add_child(hop_leg)
		_add_risk_legend_swatch(hop_leg, "A", Color(0.45, 0.9, 1.0))
		_add_risk_legend_swatch(hop_leg, "B", Color(1.0, 0.5, 0.85))
		var spark := Control.new()
		spark.custom_minimum_size = Vector2(0, 40)
		spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ha := hops_risk_a.duplicate()
		var hb := hops_risk_b.duplicate()
		spark.draw.connect(func() -> void:
			_draw_compare_risk_sparkline(spark, ha, hb)
		)
		v.add_child(spark)
	# Pass 25/27: multi-day overall risk history sparkline (A/B; C/D if present).
	var hist: Dictionary = _route_risk_day_history.get("last", {}) as Dictionary if _route_risk_day_history.get("last") is Dictionary else {}
	var hist_a: Array = hist.get("samples_a", []) as Array if hist.get("samples_a") is Array else []
	var hist_b: Array = hist.get("samples_b", []) as Array if hist.get("samples_b") is Array else []
	var hist_c: Array = hist.get("samples_c", []) as Array if hist.get("samples_c") is Array else []
	var hist_d: Array = hist.get("samples_d", []) as Array if hist.get("samples_d") is Array else []
	if hist_a.size() >= 2 or hist_b.size() >= 2:
		var dcap := Label.new()
		dcap.text = "Risk over days (%d samples)" % maxi(hist_a.size(), hist_b.size())
		dcap.add_theme_font_size_override("font_size", 9)
		dcap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
		v.add_child(dcap)
		# Pass 28: color legend for multi-series history.
		var legend := HBoxContainer.new()
		legend.add_theme_constant_override("separation", 8)
		v.add_child(legend)
		_add_risk_legend_swatch(legend, "A", Color(0.45, 0.9, 1.0))
		_add_risk_legend_swatch(legend, "B", Color(1.0, 0.5, 0.85))
		if not hist_c.is_empty() or has_c:
			_add_risk_legend_swatch(legend, "C", Color(1.0, 0.82, 0.35))
		if not hist_d.is_empty() or has_d:
			_add_risk_legend_swatch(legend, "D", Color(0.45, 0.95, 0.55))
		var dspark := Control.new()
		dspark.custom_minimum_size = Vector2(0, 36)
		dspark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dspark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hha := hist_a.duplicate()
		var hhb := hist_b.duplicate()
		var hhc := hist_c.duplicate()
		var hhd := hist_d.duplicate()
		dspark.draw.connect(func() -> void:
			_draw_compare_risk_sparkline_multi(dspark, hha, hhb, hhc, hhd)
		)
		v.add_child(dspark)
	var pref := Label.new()
	pref.text = "Prefer route %s (lower risk / shorter)" % winner
	pref.add_theme_font_size_override("font_size", 11)
	pref.add_theme_color_override("font_color", Color(0.95, 0.9, 0.55))
	v.add_child(pref)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	var btn_a := Button.new()
	btn_a.text = "Focus A"
	btn_a.focus_mode = Control.FOCUS_NONE
	btn_a.custom_minimum_size = Vector2(0, 24)
	RetrowaveTheme.style_secondary_button(btn_a)
	var fa := int(data.get("focus_a", -1))
	btn_a.pressed.connect(func() -> void:
		if fa >= 0 and has_method("focus_province_by_id"):
			focus_province_by_id(fa)
	)
	row.add_child(btn_a)
	var btn_b := Button.new()
	btn_b.text = "Focus B"
	btn_b.focus_mode = Control.FOCUS_NONE
	btn_b.custom_minimum_size = Vector2(0, 24)
	RetrowaveTheme.style_secondary_button(btn_b)
	var fb := int(data.get("focus_b", -1))
	btn_b.pressed.connect(func() -> void:
		if fb >= 0 and has_method("focus_province_by_id"):
			focus_province_by_id(fb)
	)
	row.add_child(btn_b)
	if has_c:
		var btn_c := Button.new()
		btn_c.text = "Focus C"
		btn_c.focus_mode = Control.FOCUS_NONE
		btn_c.custom_minimum_size = Vector2(0, 24)
		RetrowaveTheme.style_secondary_button(btn_c)
		var fc := int(data.get("focus_c", -1))
		btn_c.pressed.connect(func() -> void:
			if fc >= 0 and has_method("focus_province_by_id"):
				focus_province_by_id(fc)
		)
		row.add_child(btn_c)
	if has_d:
		var btn_d := Button.new()
		btn_d.text = "Focus D"
		btn_d.focus_mode = Control.FOCUS_NONE
		btn_d.custom_minimum_size = Vector2(0, 24)
		RetrowaveTheme.style_secondary_button(btn_d)
		var fd := int(data.get("focus_d", -1))
		btn_d.pressed.connect(func() -> void:
			if fd >= 0 and has_method("focus_province_by_id"):
				focus_province_by_id(fd)
		)
		row.add_child(btn_d)
	# Pass 26/27: export multi-day risk history (clipboard + user:// file).
	var btn_exp := Button.new()
	btn_exp.text = "Export"
	btn_exp.focus_mode = Control.FOCUS_NONE
	btn_exp.custom_minimum_size = Vector2(0, 24)
	btn_exp.tooltip_text = "Export risk history CSV (A–D) to clipboard and user://route_risk_history.csv"
	RetrowaveTheme.style_secondary_button(btn_exp)
	btn_exp.pressed.connect(func() -> void:
		var path_written := export_route_risk_history_csv("last")
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Risk history exported%s" % ((" · " + path_written) if not path_written.is_empty() else "")
			)
	)
	row.add_child(btn_exp)
	var btn_x := Button.new()
	btn_x.text = "Dismiss"
	btn_x.focus_mode = Control.FOCUS_NONE
	btn_x.custom_minimum_size = Vector2(0, 24)
	RetrowaveTheme.style_secondary_button(btn_x)
	btn_x.pressed.connect(func() -> void:
		_route_compare_card_gen += 1
		if _route_compare_card != null and is_instance_valid(_route_compare_card):
			_route_compare_card.queue_free()
			_route_compare_card = null
		if supply_map_layer != null and supply_map_layer.has_method("clear_route_compare"):
			supply_map_layer.call("clear_route_compare")
	)
	row.add_child(btn_x)
	# Pass 21/28/29: save / load compare slots + names + auto-pack.
	var slot_cap := Label.new()
	slot_cap.text = "Pack slots (A–D)"
	slot_cap.add_theme_font_size_override("font_size", 10)
	slot_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	v.add_child(slot_cap)
	# Pass 29: name field applies to next Save N.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	v.add_child(name_row)
	var name_lbl := Label.new()
	name_lbl.text = "Name"
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_row.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Slot label (optional)"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 10)
	name_edit.custom_minimum_size = Vector2(0, 22)
	name_row.add_child(name_edit)
	var player_only_chk := CheckBox.new()
	player_only_chk.text = "Mine"
	player_only_chk.focus_mode = Control.FOCUS_NONE
	player_only_chk.button_pressed = false
	player_only_chk.tooltip_text = "Auto pack only routes majority player-controlled."
	player_only_chk.add_theme_font_size_override("font_size", 10)
	name_row.add_child(player_only_chk)
	# Pass 31: optional owner tag filter for auto pack.
	var owner_edit := LineEdit.new()
	owner_edit.placeholder_text = "Owner"
	owner_edit.custom_minimum_size = Vector2(52, 22)
	owner_edit.add_theme_font_size_override("font_size", 10)
	owner_edit.tooltip_text = "Optional owner filter (fuzzy: exact, contains, 1-edit). e.g. US→USA. Empty = any."
	name_row.add_child(owner_edit)
	var auto_btn := Button.new()
	auto_btn.text = "Auto pack"
	auto_btn.focus_mode = Control.FOCUS_NONE
	auto_btn.custom_minimum_size = Vector2(0, 22)
	auto_btn.add_theme_font_size_override("font_size", 10)
	auto_btn.tooltip_text = "Build A–D compare from up to 4 open supply routes (lowest risk first)."
	RetrowaveTheme.style_secondary_button(auto_btn)
	auto_btn.modulate = Color(0.9, 1.05, 0.95, 1.0)
	auto_btn.pressed.connect(func() -> void:
		var n := auto_pack_open_supply_routes(4, player_only_chk.button_pressed, owner_edit.text)
		if typeof(DebugOverlay) != TYPE_NIL:
			var scope := " (mine)" if player_only_chk.button_pressed else ""
			if not owner_edit.text.strip_edges().is_empty():
				scope += " · " + owner_edit.text.strip_edges().to_upper()
			DebugOverlay.toast_map_debug(
				("Auto pack%s · %d route(s)" % [scope, n]) if n > 0 else ("Auto pack%s · no open routes" % scope)
			)
		_notify_minimap_pack_pins()
	)
	name_row.add_child(auto_btn)
	# Pass 30/31: share code export / import (+ history, QR).
	var hist_chk := CheckBox.new()
	hist_chk.text = "Hist"
	hist_chk.focus_mode = Control.FOCUS_NONE
	hist_chk.button_pressed = true
	hist_chk.tooltip_text = "Include multi-day risk history samples in share code (EORP2)."
	hist_chk.add_theme_font_size_override("font_size", 10)
	name_row.add_child(hist_chk)
	var share_btn := Button.new()
	share_btn.text = "Share"
	share_btn.focus_mode = Control.FOCUS_NONE
	share_btn.custom_minimum_size = Vector2(0, 22)
	share_btn.add_theme_font_size_override("font_size", 10)
	share_btn.tooltip_text = "Copy EORP3 share code + show QR preview toast. Hist includes day samples."
	RetrowaveTheme.style_secondary_button(share_btn)
	share_btn.pressed.connect(func() -> void:
		var code := export_route_pack_share_code(hist_chk.button_pressed, true)
		if code.is_empty():
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Nothing to share")
			return
		var prefix := "EORP3" if code.begins_with("EORP3.") else ("EORP2" if code.begins_with("EORP2.") else "EORP1")
		# Pass 35: QR preview toast with share.
		_show_share_with_qr_toast(code, prefix)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Share %s · %d chars + QR" % [prefix, code.length()])
	)
	name_row.add_child(share_btn)
	# Pass 34: write share code to file.
	var file_btn := Button.new()
	file_btn.text = "File"
	file_btn.focus_mode = Control.FOCUS_NONE
	file_btn.custom_minimum_size = Vector2(0, 22)
	file_btn.add_theme_font_size_override("font_size", 10)
	file_btn.tooltip_text = "Write pack share code to user://route_pack_share.eorp (also copies clipboard)."
	RetrowaveTheme.style_secondary_button(file_btn)
	file_btn.modulate = Color(0.95, 1.05, 0.9, 1.0)
	file_btn.pressed.connect(func() -> void:
		var path := export_route_pack_share_file(hist_chk.button_pressed, true)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"Share file · %s" % path if not path.is_empty() else "Share file failed"
			)
	)
	name_row.add_child(file_btn)
	# Pass 35: multi-file pack library browser.
	# Pass 44/45: minimap pack risk heat toggle + intensity on compare card.
	var heat_chk := CheckBox.new()
	heat_chk.text = "Heat"
	heat_chk.focus_mode = Control.FOCUS_NONE
	heat_chk.add_theme_font_size_override("font_size", 10)
	heat_chk.tooltip_text = "Toggle soft risk heat discs under pack pins on minimap"
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_show_pack_risk_heat"):
		heat_chk.button_pressed = bool(_map_minimap.call("get_show_pack_risk_heat"))
	else:
		heat_chk.button_pressed = true
	# Seed from persisted prefs then minimap.
	var heat_prefs := load_pack_risk_heat_prefs()
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_show_pack_risk_heat"):
		heat_chk.button_pressed = bool(_map_minimap.call("get_show_pack_risk_heat"))
	else:
		heat_chk.button_pressed = bool(heat_prefs.get("show", true))
	heat_chk.toggled.connect(func(on: bool) -> void:
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_show_pack_risk_heat"):
			_map_minimap.call("set_show_pack_risk_heat", on)
		var snap := _snapshot_pack_map_ui_prefs()
		save_pack_risk_heat_prefs(
			on, float(snap.get("intensity", 1.0)), float(snap.get("legend_opacity", 1.0)),
			str(snap.get("heat_ramp", "classic")), str(snap.get("library_layout", "standard"))
		)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Minimap heat · %s" % ("ON" if on else "OFF"))
	)
	name_row.add_child(heat_chk)
	var heat_slider := HSlider.new()
	heat_slider.min_value = 0.0
	heat_slider.max_value = 2.0
	heat_slider.step = 0.05
	heat_slider.custom_minimum_size = Vector2(72, 18)
	heat_slider.tooltip_text = "Heat intensity 0–2 (radius + alpha; persisted)"
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_risk_heat_intensity"):
		heat_slider.value = float(_map_minimap.call("get_pack_risk_heat_intensity"))
	else:
		heat_slider.value = float(heat_prefs.get("intensity", 1.0))
	heat_slider.value_changed.connect(func(v: float) -> void:
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_risk_heat_intensity"):
			_map_minimap.call("set_pack_risk_heat_intensity", v)
		var snap_v := _snapshot_pack_map_ui_prefs()
		save_pack_risk_heat_prefs(
			heat_chk.button_pressed, v, float(snap_v.get("legend_opacity", 1.0)),
			str(snap_v.get("heat_ramp", "classic")), str(snap_v.get("library_layout", "standard"))
		)
	)
	name_row.add_child(heat_slider)
	# Pass 47: pack pin legend opacity slider.
	var leg_slider := HSlider.new()
	leg_slider.min_value = 0.0
	leg_slider.max_value = 1.0
	leg_slider.step = 0.05
	leg_slider.custom_minimum_size = Vector2(56, 18)
	leg_slider.tooltip_text = "Pack legend opacity 0–1 (minimap pin labels; persisted)"
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_legend_opacity"):
		leg_slider.value = float(_map_minimap.call("get_pack_legend_opacity"))
	else:
		leg_slider.value = float(heat_prefs.get("legend_opacity", 1.0))
	leg_slider.value_changed.connect(func(lv: float) -> void:
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_legend_opacity"):
			_map_minimap.call("set_pack_legend_opacity", lv)
		var snap_l := _snapshot_pack_map_ui_prefs()
		save_pack_risk_heat_prefs(
			heat_chk.button_pressed, heat_slider.value, lv,
			str(snap_l.get("heat_ramp", "classic")), str(snap_l.get("library_layout", "standard"))
		)
	)
	name_row.add_child(leg_slider)
	# Pass 48: heat color ramp picker.
	var ramp_opt := OptionButton.new()
	ramp_opt.focus_mode = Control.FOCUS_NONE
	ramp_opt.add_theme_font_size_override("font_size", 9)
	ramp_opt.tooltip_text = "Heat color ramp: classic · inferno · viridis · mono"
	var ramp_ids: PackedStringArray = PACK_HEAT_RAMPS
	for ri in ramp_ids.size():
		ramp_opt.add_item(str(ramp_ids[ri]), ri)
	var cur_ramp := str(heat_prefs.get("heat_ramp", "classic"))
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_heat_ramp"):
		cur_ramp = str(_map_minimap.call("get_pack_heat_ramp"))
	var ramp_idx := ramp_ids.find(cur_ramp)
	ramp_opt.select(ramp_idx if ramp_idx >= 0 else 0)
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_heat_ramp"):
		_map_minimap.call("set_pack_heat_ramp", cur_ramp)
	# Pass 49: custom cool/hot color pickers (active when ramp = custom).
	var cool_pick := ColorPickerButton.new()
	cool_pick.focus_mode = Control.FOCUS_NONE
	cool_pick.custom_minimum_size = Vector2(28, 20)
	cool_pick.tooltip_text = "Custom heat cool color (use ramp = custom)"
	cool_pick.color = _pack_heat_hex_to_color(
		str(heat_prefs.get("heat_cool", "59d9ff")), Color(0.35, 0.85, 1.0)
	)
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_heat_cool"):
		cool_pick.color = _map_minimap.call("get_pack_heat_cool") as Color
	var hot_pick := ColorPickerButton.new()
	hot_pick.focus_mode = Control.FOCUS_NONE
	hot_pick.custom_minimum_size = Vector2(28, 20)
	hot_pick.tooltip_text = "Custom heat hot color (use ramp = custom)"
	hot_pick.color = _pack_heat_hex_to_color(
		str(heat_prefs.get("heat_hot", "ff4026")), Color(1.0, 0.25, 0.15)
	)
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_heat_hot"):
		hot_pick.color = _map_minimap.call("get_pack_heat_hot") as Color
	var refresh_custom_picks := func() -> void:
		var is_custom := ramp_opt.get_item_text(ramp_opt.selected) == "custom"
		cool_pick.modulate = Color(1, 1, 1, 1) if is_custom else Color(0.7, 0.7, 0.75, 0.65)
		hot_pick.modulate = Color(1, 1, 1, 1) if is_custom else Color(0.7, 0.7, 0.75, 0.65)
	var persist_heat_ui := func(extra_ramp: String = "") -> void:
		var rid2 := extra_ramp if not extra_ramp.is_empty() else str(ramp_ids[ramp_opt.selected] if ramp_opt.selected >= 0 and ramp_opt.selected < ramp_ids.size() else "classic")
		var snap_r := _snapshot_pack_map_ui_prefs()
		save_pack_risk_heat_prefs(
			heat_chk.button_pressed,
			heat_slider.value,
			leg_slider.value,
			rid2,
			str(snap_r.get("library_layout", "standard")),
			cool_pick.color.to_html(false),
			hot_pick.color.to_html(false)
		)
	var sync_ramp_opt_from_id := func(rid_s: String) -> void:
		var ix_s := ramp_ids.find(rid_s)
		if ix_s >= 0:
			ramp_opt.select(ix_s)
		refresh_custom_picks.call()
	ramp_opt.item_selected.connect(func(idx_r: int) -> void:
		var rid := str(ramp_ids[idx_r]) if idx_r >= 0 and idx_r < ramp_ids.size() else "classic"
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_heat_ramp"):
			_map_minimap.call("set_pack_heat_ramp", rid)
		if rid == "custom" and _map_minimap != null and is_instance_valid(_map_minimap):
			if _map_minimap.has_method("set_pack_heat_cool"):
				_map_minimap.call("set_pack_heat_cool", cool_pick.color)
			if _map_minimap.has_method("set_pack_heat_hot"):
				_map_minimap.call("set_pack_heat_hot", hot_pick.color)
		refresh_custom_picks.call()
		persist_heat_ui.call(rid)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Heat ramp · %s" % rid)
	)
	name_row.add_child(ramp_opt)
	# Pass 52: ramp cycle buttons on compare card (same as minimap swatch).
	var ramp_next := Button.new()
	ramp_next.text = "↻"
	ramp_next.focus_mode = Control.FOCUS_NONE
	ramp_next.custom_minimum_size = Vector2(22, 20)
	ramp_next.add_theme_font_size_override("font_size", 11)
	ramp_next.tooltip_text = "Next heat ramp (persisted)"
	RetrowaveTheme.style_secondary_button(ramp_next)
	ramp_next.pressed.connect(func() -> void:
		var nxt_r := cycle_pack_heat_ramp(1)
		sync_ramp_opt_from_id.call(nxt_r)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Heat ramp · %s" % nxt_r)
	)
	name_row.add_child(ramp_next)
	var ramp_prev := Button.new()
	ramp_prev.text = "↺"
	ramp_prev.focus_mode = Control.FOCUS_NONE
	ramp_prev.custom_minimum_size = Vector2(22, 20)
	ramp_prev.add_theme_font_size_override("font_size", 11)
	ramp_prev.tooltip_text = "Previous heat ramp (persisted)"
	RetrowaveTheme.style_secondary_button(ramp_prev)
	ramp_prev.pressed.connect(func() -> void:
		var prv_r := cycle_pack_heat_ramp(-1)
		sync_ramp_opt_from_id.call(prv_r)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Heat ramp · %s" % prv_r)
	)
	name_row.add_child(ramp_prev)
	# Pass 53/54: heat ramp preview strip (cool→hot) on compare card.
	var ramp_strip := Control.new()
	ramp_strip.custom_minimum_size = Vector2(48, 14)
	ramp_strip.tooltip_text = "Heat ramp preview (follows current cool→hot)"
	ramp_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	var paint_ramp_strip := func() -> void:
		ramp_strip.queue_redraw()
	ramp_strip.draw.connect(func() -> void:
		var cool_s := cool_pick.color
		var hot_s := hot_pick.color
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_pack_heat_ramp_colors"):
			var rc: Array = _map_minimap.call("get_pack_heat_ramp_colors")
			if rc.size() >= 2:
				cool_s = rc[0] as Color
				hot_s = rc[1] as Color
		var rs := ramp_strip.size
		if rs.x < 2.0 or rs.y < 2.0:
			rs = ramp_strip.custom_minimum_size
		var segs_s := 10
		for si_s in segs_s:
			var t_s := float(si_s) / float(maxi(segs_s - 1, 1))
			var col_s := cool_s.lerp(hot_s, t_s)
			col_s.a = 0.95
			var x0 := float(si_s) * (rs.x / float(segs_s))
			ramp_strip.draw_rect(Rect2(x0, 1.0, rs.x / float(segs_s) + 0.5, rs.y - 2.0), col_s, true)
		ramp_strip.draw_rect(Rect2(0.5, 0.5, rs.x - 1.0, rs.y - 1.0), Color(1, 1, 1, 0.35), false, 1.0)
	)
	# Click strip to cycle ramp (Shift = prev).
	ramp_strip.gui_input.connect(func(ev_rs: InputEvent) -> void:
		if ev_rs is InputEventMouseButton and ev_rs.pressed and ev_rs.button_index == MOUSE_BUTTON_LEFT:
			var dir_rs := -1 if Input.is_key_pressed(KEY_SHIFT) else 1
			var nxt_rs := cycle_pack_heat_ramp(dir_rs)
			sync_ramp_opt_from_id.call(nxt_rs)
			paint_ramp_strip.call()
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Heat ramp · %s" % nxt_rs)
			ramp_strip.accept_event()
	)
	name_row.add_child(ramp_strip)
	ramp_strip.resized.connect(paint_ramp_strip)
	ramp_opt.item_selected.connect(func(_i2: int) -> void:
		paint_ramp_strip.call()
	)
	cool_pick.color_changed.connect(func(cc: Color) -> void:
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_heat_cool"):
			_map_minimap.call("set_pack_heat_cool", cc)
		# Auto-switch to custom when user edits colors.
		var cidx := ramp_ids.find("custom")
		if cidx >= 0 and ramp_opt.selected != cidx:
			ramp_opt.select(cidx)
			if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_heat_ramp"):
				_map_minimap.call("set_pack_heat_ramp", "custom")
		refresh_custom_picks.call()
		persist_heat_ui.call("custom")
		paint_ramp_strip.call()
	)
	hot_pick.color_changed.connect(func(hc: Color) -> void:
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_heat_hot"):
			_map_minimap.call("set_pack_heat_hot", hc)
		var cidx2 := ramp_ids.find("custom")
		if cidx2 >= 0 and ramp_opt.selected != cidx2:
			ramp_opt.select(cidx2)
			if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_pack_heat_ramp"):
				_map_minimap.call("set_pack_heat_ramp", "custom")
		refresh_custom_picks.call()
		persist_heat_ui.call("custom")
		paint_ramp_strip.call()
	)
	# Also paint when ↻/↺ cycle (they already call sync_ramp_opt which selects).
	paint_ramp_strip.call()
	name_row.add_child(cool_pick)
	name_row.add_child(hot_pick)
	refresh_custom_picks.call()
	# Pass 50: heat ramp swatch legend toggle on minimap.
	var ramp_leg_chk := CheckBox.new()
	ramp_leg_chk.text = "Swatch"
	ramp_leg_chk.focus_mode = Control.FOCUS_NONE
	ramp_leg_chk.add_theme_font_size_override("font_size", 9)
	ramp_leg_chk.tooltip_text = "Show heat ramp swatch legend on minimap (top-right)"
	ramp_leg_chk.button_pressed = bool(heat_prefs.get("heat_ramp_legend", true))
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("get_show_heat_ramp_legend"):
		ramp_leg_chk.button_pressed = bool(_map_minimap.call("get_show_heat_ramp_legend"))
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_show_heat_ramp_legend"):
		_map_minimap.call("set_show_heat_ramp_legend", ramp_leg_chk.button_pressed)
	ramp_leg_chk.toggled.connect(func(on_rl: bool) -> void:
		if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_show_heat_ramp_legend"):
			_map_minimap.call("set_show_heat_ramp_legend", on_rl)
		var snap_rl := _snapshot_pack_map_ui_prefs()
		save_pack_risk_heat_prefs(
			bool(snap_rl.get("show", true)),
			float(snap_rl.get("intensity", 1.0)),
			float(snap_rl.get("legend_opacity", 1.0)),
			str(snap_rl.get("heat_ramp", "classic")),
			str(snap_rl.get("library_layout", "standard")),
			str(snap_rl.get("heat_cool", "")),
			str(snap_rl.get("heat_hot", "")),
			-1.0,
			-1.0,
			on_rl
		)
	)
	name_row.add_child(ramp_leg_chk)
	# Pass 56/57: mute pin-focus pulse SFX + volume.
	var pin_sfx_chk := CheckBox.new()
	pin_sfx_chk.text = "Pin SFX"
	pin_sfx_chk.focus_mode = Control.FOCUS_NONE
	pin_sfx_chk.add_theme_font_size_override("font_size", 9)
	pin_sfx_chk.tooltip_text = "Play soft Map.wav ping when pin focus pulse spawns"
	pin_sfx_chk.button_pressed = get_pin_focus_sfx_enabled()
	pin_sfx_chk.toggled.connect(func(on_ps: bool) -> void:
		set_pin_focus_sfx_enabled(on_ps)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Pin focus SFX · %s" % ("ON" if on_ps else "OFF"))
	)
	name_row.add_child(pin_sfx_chk)
	var pin_sfx_vol := HSlider.new()
	pin_sfx_vol.min_value = -40.0
	pin_sfx_vol.max_value = 0.0
	pin_sfx_vol.step = 1.0
	pin_sfx_vol.custom_minimum_size = Vector2(56, 16)
	pin_sfx_vol.value = get_pin_focus_sfx_volume_db()
	pin_sfx_vol.tooltip_text = "Pin focus SFX volume (dB, -40 silent … 0 loud)"
	pin_sfx_vol.value_changed.connect(func(db: float) -> void:
		set_pin_focus_sfx_volume_db(db)
	)
	name_row.add_child(pin_sfx_vol)
	# Pass 58: preview pin focus SFX at current volume (ignores mute).
	var pin_sfx_prev := Button.new()
	pin_sfx_prev.text = "▶"
	pin_sfx_prev.focus_mode = Control.FOCUS_NONE
	pin_sfx_prev.custom_minimum_size = Vector2(22, 18)
	pin_sfx_prev.add_theme_font_size_override("font_size", 10)
	pin_sfx_prev.tooltip_text = "Preview pin focus SFX at current volume (ignores mute)"
	RetrowaveTheme.style_secondary_button(pin_sfx_prev)
	pin_sfx_prev.pressed.connect(func() -> void:
		preview_pin_focus_sfx()
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Pin SFX preview · %.0f dB" % get_pin_focus_sfx_volume_db())
	)
	name_row.add_child(pin_sfx_prev)
	# Pass 59: pin focus SFX audio bus routing.
	var pin_sfx_bus_opt := OptionButton.new()
	pin_sfx_bus_opt.focus_mode = Control.FOCUS_NONE
	pin_sfx_bus_opt.add_theme_font_size_override("font_size", 9)
	pin_sfx_bus_opt.tooltip_text = "Audio bus for pin focus SFX (AudioServer buses)"
	var bus_names := list_audio_bus_names()
	var cur_bus := get_pin_focus_sfx_bus()
	var bus_sel := 0
	for bi in bus_names.size():
		pin_sfx_bus_opt.add_item(str(bus_names[bi]), bi)
		if str(bus_names[bi]) == cur_bus:
			bus_sel = bi
	pin_sfx_bus_opt.select(bus_sel)
	pin_sfx_bus_opt.item_selected.connect(func(idx_b: int) -> void:
		var bn := pin_sfx_bus_opt.get_item_text(idx_b) if idx_b >= 0 else "Master"
		set_pin_focus_sfx_bus(bn)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("Pin SFX bus · %s" % bn)
	)
	name_row.add_child(pin_sfx_bus_opt)
	# Pass 62: live-refresh mute/volume/bus when chrome EOCS1 import lands.
	var refresh_pin_sfx_ui := func() -> void:
		if not is_instance_valid(pin_sfx_chk):
			return
		pin_sfx_chk.set_pressed_no_signal(get_pin_focus_sfx_enabled())
		if is_instance_valid(pin_sfx_vol):
			pin_sfx_vol.set_value_no_signal(get_pin_focus_sfx_volume_db())
		if is_instance_valid(pin_sfx_bus_opt):
			var want_bus := get_pin_focus_sfx_bus()
			for bi2 in pin_sfx_bus_opt.item_count:
				if pin_sfx_bus_opt.get_item_text(bi2) == want_bus:
					pin_sfx_bus_opt.select(bi2)
					break
	register_pin_sfx_ui_watcher(refresh_pin_sfx_ui)
	# Apply stored cool/hot to minimap on card open.
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("set_pack_heat_cool"):
			_map_minimap.call("set_pack_heat_cool", cool_pick.color)
		if _map_minimap.has_method("set_pack_heat_hot"):
			_map_minimap.call("set_pack_heat_hot", hot_pick.color)
	var lib_btn := Button.new()
	lib_btn.text = "Lib"
	lib_btn.focus_mode = Control.FOCUS_NONE
	lib_btn.custom_minimum_size = Vector2(0, 22)
	lib_btn.add_theme_font_size_override("font_size", 10)
	lib_btn.tooltip_text = "Pack library (user://route_packs/). Shift+click opens a second window."
	RetrowaveTheme.style_secondary_button(lib_btn)
	lib_btn.modulate = Color(0.95, 0.98, 1.08, 1.0)
	lib_btn.pressed.connect(func() -> void:
		_show_pack_library_popup(hist_chk.button_pressed, Input.is_key_pressed(KEY_SHIFT))
	)
	name_row.add_child(lib_btn)
	var qr_btn := Button.new()
	qr_btn.text = "QR"
	qr_btn.focus_mode = Control.FOCUS_NONE
	qr_btn.custom_minimum_size = Vector2(0, 22)
	qr_btn.add_theme_font_size_override("font_size", 10)
	qr_btn.tooltip_text = "Export pack QR PNG (auto module size ~248px; qrencode fallback). user://route_pack_qr.png"
	RetrowaveTheme.style_secondary_button(qr_btn)
	qr_btn.modulate = Color(1.05, 0.98, 0.85, 1.0)
	qr_btn.pressed.connect(func() -> void:
		var path := export_route_pack_qr_png(hist_chk.button_pressed)
		if not path.is_empty():
			_show_pack_qr_popup(path)
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug(
				"QR exported · %s" % path if not path.is_empty() else "QR export failed (qrencode?)"
			)
	)
	name_row.add_child(qr_btn)
	var import_btn := Button.new()
	import_btn.text = "Import"
	import_btn.focus_mode = Control.FOCUS_NONE
	import_btn.custom_minimum_size = Vector2(0, 22)
	import_btn.add_theme_font_size_override("font_size", 10)
	import_btn.tooltip_text = "Import pack share from clipboard (EORP1/2/3). Shift+click loads user://route_pack_share.eorp"
	RetrowaveTheme.style_secondary_button(import_btn)
	import_btn.pressed.connect(func() -> void:
		var ok := false
		# Pass 34: Shift+Import loads from file.
		if Input.is_key_pressed(KEY_SHIFT):
			ok = import_route_pack_share_file()
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Pack file import OK" if ok else "Pack file import failed")
		else:
			var clip := ""
			if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
				clip = DisplayServer.clipboard_get()
			ok = import_route_pack_share_code(clip)
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Pack import OK" if ok else "Pack import failed")
		if ok:
			_notify_minimap_pack_pins()
	)
	name_row.add_child(import_btn)
	# Pass 32: merge all filled pack slots into best A–D compare.
	var merge_btn := Button.new()
	merge_btn.text = "Merge"
	merge_btn.focus_mode = Control.FOCUS_NONE
	merge_btn.custom_minimum_size = Vector2(0, 22)
	merge_btn.add_theme_font_size_override("font_size", 10)
	merge_btn.tooltip_text = "Merge filled slots (+ current) into A–D. Slot order weighted: S1 preferred when risk is close."
	RetrowaveTheme.style_secondary_button(merge_btn)
	merge_btn.modulate = Color(1.05, 0.95, 1.05, 1.0)
	merge_btn.pressed.connect(func() -> void:
		var n := merge_route_compare_slots([])
		if typeof(DebugOverlay) != TYPE_NIL and n <= 0:
			DebugOverlay.toast_map_debug("Pack merge · need ≥2 unique routes in slots")
	)
	name_row.add_child(merge_btn)
	# Pass 34/35: pack pin / slot legend — clickable load on card.
	var leg_entries: Array = get_pack_slot_legend()
	if not leg_entries.is_empty():
		var leg_cap := Label.new()
		leg_cap.text = "Pack pins · click to load"
		leg_cap.add_theme_font_size_override("font_size", 9)
		leg_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
		v.add_child(leg_cap)
		var leg_row := HBoxContainer.new()
		leg_row.add_theme_constant_override("separation", 6)
		v.add_child(leg_row)
		for le in leg_entries:
			if not le is Dictionary:
				continue
			var led: Dictionary = le
			var leg_slot: int = int(led.get("slot", -1))
			var leg_btn := Button.new()
			leg_btn.text = "%s×%d" % [str(led.get("label", "?")).substr(0, 5), int(led.get("routes", 0))]
			leg_btn.focus_mode = Control.FOCUS_NONE
			leg_btn.custom_minimum_size = Vector2(0, 20)
			leg_btn.add_theme_font_size_override("font_size", 9)
			leg_btn.tooltip_text = "Load pack slot %d" % (leg_slot + 1)
			RetrowaveTheme.style_secondary_button(leg_btn)
			var lcol: Color = led.get("color", Color(0.7, 0.85, 1.0)) as Color
			leg_btn.modulate = Color(lcol.r + 0.1, lcol.g + 0.1, lcol.b + 0.1, 1.0)
			leg_btn.pressed.connect(func() -> void:
				if leg_slot >= 0:
					load_route_compare_slot(leg_slot)
					_notify_minimap_pack_pins()
			)
			leg_row.add_child(leg_btn)
	var save_hint := Label.new()
	save_hint.text = "Save · drag S# onto S#/Load to reorder"
	save_hint.add_theme_font_size_override("font_size", 9)
	save_hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85, 0.85))
	v.add_child(save_hint)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	v.add_child(save_row)
	for si in 4:
		var slot_i: int = si
		var sb := Button.new()
		var cur_lab := get_route_compare_slot_label(slot_i)
		sb.text = "S%d" % (slot_i + 1) if cur_lab.is_empty() else cur_lab.substr(0, 8)
		sb.focus_mode = Control.FOCUS_NONE
		sb.custom_minimum_size = Vector2(0, 22)
		sb.add_theme_font_size_override("font_size", 10)
		RetrowaveTheme.style_secondary_button(sb)
		sb.tooltip_text = "Save pack into slot %d · drag onto another S#/Load to reorder%s" % [
			slot_i + 1,
			(" · " + cur_lab) if not cur_lab.is_empty() else ""
		]
		sb.pressed.connect(func() -> void:
			var lab := name_edit.text.strip_edges()
			if not lab.is_empty():
				set_route_compare_slot_label(slot_i, lab)
			if save_route_compare_slot(slot_i):
				_route_compare_card_gen += 1  # keep card alive after save
				_show_route_compare_card(_last_route_compare_data)
				_notify_minimap_pack_pins()
		)
		# Pass 35: free-slot drag-drop reorder (drag filled S# onto target).
		var sb_drag := func(_at: Vector2) -> Variant:
			if not route_compare_slot_filled(slot_i):
				return null
			var preview := Button.new()
			preview.text = sb.text
			preview.custom_minimum_size = Vector2(48, 22)
			sb.set_drag_preview(preview)
			return {"type": "pack_slot", "slot": slot_i}
		var sb_can := func(_at: Vector2, data: Variant) -> bool:
			return data is Dictionary and str((data as Dictionary).get("type", "")) == "pack_slot"
		var sb_drop := func(_at: Vector2, data: Variant) -> void:
			if not (data is Dictionary):
				return
			var from_s := int((data as Dictionary).get("slot", -1))
			if from_s < 0 or from_s == slot_i:
				return
			if move_route_compare_slot(from_s, slot_i):
				if not _last_route_compare_data.is_empty():
					_route_compare_card_gen += 1
					_show_route_compare_card(_last_route_compare_data)
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Slot drag · %d → %d" % [from_s + 1, slot_i + 1])
		sb.set_drag_forwarding(sb_drag, sb_can, sb_drop)
		save_row.add_child(sb)
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 4)
	v.add_child(load_row)
	for li in 4:
		var slot_l: int = li
		var lb_btn := Button.new()
		var filled := route_compare_slot_filled(slot_l)
		var lab_l := get_route_compare_slot_label(slot_l)
		if filled and not lab_l.is_empty():
			lb_btn.text = "L:%s" % lab_l.substr(0, 8)
		else:
			lb_btn.text = "Load %d%s" % [slot_l + 1, " ●" if filled else ""]
		lb_btn.focus_mode = Control.FOCUS_NONE
		lb_btn.custom_minimum_size = Vector2(0, 22)
		lb_btn.add_theme_font_size_override("font_size", 10)
		# Enabled even when empty so drops work; click only loads if filled.
		lb_btn.disabled = false
		RetrowaveTheme.style_secondary_button(lb_btn)
		if filled:
			var sd: Dictionary = _route_compare_slots[slot_l] if _route_compare_slots[slot_l] is Dictionary else {}
			var nrt := 2
			if bool(sd.get("has_d", false)) or int(sd.get("hops_d", 0)) > 0:
				nrt = 4
			elif bool(sd.get("has_c", false)) or int(sd.get("hops_c", 0)) > 0:
				nrt = 3
			lb_btn.tooltip_text = "Load «%s» · %d routes · A %dh / B %dh · drop pack here to move" % [
				lab_l if not lab_l.is_empty() else ("slot %d" % (slot_l + 1)),
				nrt, int(sd.get("hops_a", 0)), int(sd.get("hops_b", 0))
			]
			lb_btn.modulate = Color(0.85, 1.05, 0.95, 1.0)
		else:
			lb_btn.tooltip_text = "Slot %d empty · drop pack here to move" % (slot_l + 1)
			lb_btn.modulate = Color(0.75, 0.78, 0.85, 0.85)
		var filled_click: bool = filled
		lb_btn.pressed.connect(func() -> void:
			if not filled_click and not route_compare_slot_filled(slot_l):
				return
			load_route_compare_slot(slot_l)
			_notify_minimap_pack_pins()
		)
		# Pass 35: accept drops on Load buttons (including empty targets).
		var lb_drag := func(_at2: Vector2) -> Variant:
			if not route_compare_slot_filled(slot_l):
				return null
			var preview2 := Button.new()
			preview2.text = lb_btn.text
			preview2.custom_minimum_size = Vector2(56, 22)
			lb_btn.set_drag_preview(preview2)
			return {"type": "pack_slot", "slot": slot_l}
		var lb_can := func(_at2: Vector2, data2: Variant) -> bool:
			return data2 is Dictionary and str((data2 as Dictionary).get("type", "")) == "pack_slot"
		var lb_drop := func(_at2: Vector2, data2: Variant) -> void:
			if not (data2 is Dictionary):
				return
			var from2 := int((data2 as Dictionary).get("slot", -1))
			if from2 < 0 or from2 == slot_l:
				return
			if move_route_compare_slot(from2, slot_l):
				if not _last_route_compare_data.is_empty():
					_route_compare_card_gen += 1
					_show_route_compare_card(_last_route_compare_data)
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Slot drag · %d → %d" % [from2 + 1, slot_l + 1])
		lb_btn.set_drag_forwarding(lb_drag, lb_can, lb_drop)
		load_row.add_child(lb_btn)
	# Pass 34: slot reorder — move filled slot left/right (updates merge weight order).
	var reorder_row := HBoxContainer.new()
	reorder_row.add_theme_constant_override("separation", 4)
	v.add_child(reorder_row)
	var re_cap := Label.new()
	re_cap.text = "Reorder"
	re_cap.add_theme_font_size_override("font_size", 10)
	re_cap.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 0.9))
	reorder_row.add_child(re_cap)
	for ri in 4:
		var slot_r: int = ri
		var filled_r := route_compare_slot_filled(slot_r)
		var left_btn := Button.new()
		left_btn.text = "◀%d" % (slot_r + 1)
		left_btn.focus_mode = Control.FOCUS_NONE
		left_btn.custom_minimum_size = Vector2(0, 22)
		left_btn.add_theme_font_size_override("font_size", 9)
		left_btn.disabled = not filled_r or slot_r <= 0
		left_btn.tooltip_text = "Move slot %d left (higher merge priority)" % (slot_r + 1)
		RetrowaveTheme.style_secondary_button(left_btn)
		left_btn.pressed.connect(func() -> void:
			if swap_route_compare_slots(slot_r, slot_r - 1):
				if not _last_route_compare_data.is_empty():
					_route_compare_card_gen += 1
					_show_route_compare_card(_last_route_compare_data)
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Slot reorder · %d ↔ %d" % [slot_r + 1, slot_r])
		)
		reorder_row.add_child(left_btn)
		var right_btn := Button.new()
		right_btn.text = "%d▶" % (slot_r + 1)
		right_btn.focus_mode = Control.FOCUS_NONE
		right_btn.custom_minimum_size = Vector2(0, 22)
		right_btn.add_theme_font_size_override("font_size", 9)
		right_btn.disabled = not filled_r or slot_r >= 3
		right_btn.tooltip_text = "Move slot %d right (lower merge priority)" % (slot_r + 1)
		RetrowaveTheme.style_secondary_button(right_btn)
		right_btn.pressed.connect(func() -> void:
			if swap_route_compare_slots(slot_r, slot_r + 1):
				if not _last_route_compare_data.is_empty():
					_route_compare_card_gen += 1
					_show_route_compare_card(_last_route_compare_data)
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Slot reorder · %d ↔ %d" % [slot_r + 1, slot_r + 2])
		)
		reorder_row.add_child(right_btn)
	# Auto-dismiss (gen-guarded so save rebuild / dismiss cancel cleanly)
	get_tree().create_timer(12.0).timeout.connect(func() -> void:
		if card_gen != _route_compare_card_gen:
			return
		if _route_compare_card != null and is_instance_valid(_route_compare_card):
			_route_compare_card.queue_free()
			_route_compare_card = null
	)


func _ensure_munitions_desk() -> void:
	if _munitions_desk != null and is_instance_valid(_munitions_desk):
		return
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var scr = load("res://scripts/ui/MunitionsDeskChip.gd")
	if scr == null:
		return
	_munitions_desk = PanelContainer.new()
	_munitions_desk.set_script(scr)
	_munitions_desk.name = "MunitionsDeskChip"
	_munitions_desk.visible = false
	ui.add_child(_munitions_desk)
	if _munitions_desk is Control:
		var c := _munitions_desk as Control
		c.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		c.offset_left = -290.0
		c.offset_right = -12.0
		c.offset_top = -300.0
		c.offset_bottom = -96.0
	if _munitions_desk.has_signal("open_production_requested"):
		_munitions_desk.open_production_requested.connect(_on_munitions_open_production)
	if _munitions_desk.has_signal("munitions_cargo_set"):
		_munitions_desk.munitions_cargo_set.connect(func() -> void:
			if _munitions_desk.has_method("refresh"):
				_munitions_desk.call("refresh")
		)
	if _munitions_desk.has_signal("munitions_map_filter_changed"):
		_munitions_desk.munitions_map_filter_changed.connect(_on_munitions_map_filter_changed)
	if _munitions_desk.has_signal("munitions_occupation_filter_changed"):
		_munitions_desk.munitions_occupation_filter_changed.connect(_on_munitions_occupation_filter_changed)


func set_munitions_desk_visible(show: bool) -> void:
	_ensure_munitions_desk()
	if _munitions_desk == null:
		return
	_munitions_desk.visible = show
	if show and _munitions_desk.has_method("refresh"):
		_munitions_desk.call("refresh")


## Pass 24: munitions desk → minimap player-only filter.
func _on_munitions_map_filter_changed(player_only: bool) -> void:
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_munitions_pips_player_only"):
		_map_minimap.call("set_munitions_pips_player_only", player_only)


## Pass 27: munitions occupation filter for minimap + mapmode emphasis.
var munitions_occupation_filter: String = "all"  # all | occupied | mine


func _on_munitions_occupation_filter_changed(mode: String) -> void:
	munitions_occupation_filter = mode.strip_edges().to_lower()
	if munitions_occupation_filter not in ["all", "occupied", "mine"]:
		munitions_occupation_filter = "all"
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("set_munitions_occupation_filter"):
			_map_minimap.call("set_munitions_occupation_filter", munitions_occupation_filter)
		if _map_minimap.has_method("set_munitions_pips_player_only"):
			_map_minimap.call("set_munitions_pips_player_only", munitions_occupation_filter == "mine")
	if current_map_mode == "munitions" or debug_tint_mode == "munitions":
		_refresh_province_fill_colors(true)


## Pass 22: theater-wide repair queue panel (player damaged special sites).
func _ensure_repair_queue_chip() -> void:
	if _repair_queue_chip != null and is_instance_valid(_repair_queue_chip):
		return
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var scr = load("res://scripts/ui/SiteRepairQueueChip.gd")
	if scr == null:
		return
	_repair_queue_chip = PanelContainer.new()
	_repair_queue_chip.set_script(scr)
	_repair_queue_chip.name = "SiteRepairQueueChip"
	_repair_queue_chip.visible = false
	ui.add_child(_repair_queue_chip)
	if _repair_queue_chip is Control:
		var c := _repair_queue_chip as Control
		# Sit right of minimap (bottom-left chrome).
		c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		c.offset_left = 212.0
		c.offset_right = 520.0
		c.offset_top = -300.0
		c.offset_bottom = -96.0
	if _repair_queue_chip.has_method("bind_map_renderer"):
		_repair_queue_chip.call("bind_map_renderer", self)
	if _repair_queue_chip.has_signal("focus_province_requested"):
		_repair_queue_chip.focus_province_requested.connect(func(pid: int) -> void:
			if pid >= 0 and has_method("focus_province_by_id"):
				focus_province_by_id(pid)
		)
	if _repair_queue_chip.has_signal("repair_site_requested"):
		_repair_queue_chip.repair_site_requested.connect(_on_repair_queue_site)
	if _repair_queue_chip.has_signal("repair_batch_requested"):
		_repair_queue_chip.repair_batch_requested.connect(_on_repair_queue_batch)


func set_repair_queue_visible(show: bool) -> void:
	_ensure_repair_queue_chip()
	if _repair_queue_chip == null:
		return
	_repair_queue_chip.visible = show
	if show and _repair_queue_chip.has_method("refresh"):
		_repair_queue_chip.call("refresh")


## Pass 22–24: collect damaged special sites for player / formal allies / CRS partners.
## ally_scope: "none" | "treaty" | "partner"  (treaty = formal alliance/guarantee; partner = CRS band)
## Returns Array of {province_id, site_id, damage, owner_tag, is_ally, ally_kind}.
func collect_damaged_player_sites(include_allies: bool = false, ally_scope: String = "partner") -> Array:
	var out: Array = []
	var player := ""
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		player = str(LeaderManager.get_player_country_tag()).to_upper()
	var scope := ally_scope.strip_edges().to_lower()
	if include_allies and scope.is_empty():
		scope = "partner"
	if not include_allies:
		scope = "none"
	for pid_v in provinces.keys():
		var p: Province = provinces[pid_v] as Province
		if p == null or p.special_sites.is_empty():
			continue
		var owner := str(p.owner_tag).to_upper()
		var is_player := (player.is_empty() or owner == player)
		var is_ally := false
		var ally_kind := ""
		if not is_player:
			if scope == "none":
				continue
			ally_kind = classify_ally_tag(owner, player)
			if ally_kind.is_empty():
				continue
			if scope == "treaty" and ally_kind != "treaty":
				continue
			# partner scope includes treaty + CRS partner
			is_ally = true
		for site in p.special_sites:
			if site == null:
				continue
			if site.has_method("is_damaged") and site.is_damaged():
				out.append({
					"province_id": int(p.id),
					"site_id": str(site.id),
					"damage": int(site.damage_level),
					"owner_tag": owner,
					"is_ally": is_ally,
					"ally_kind": ally_kind,
				})
	out.sort_custom(func(a, b) -> bool:
		# Player first, formal treaty allies next, then CRS partners; then by damage.
		var rank_a := _ally_sort_rank(a)
		var rank_b := _ally_sort_rank(b)
		if rank_a != rank_b:
			return rank_a < rank_b
		return int(a.get("damage", 0)) > int(b.get("damage", 0))
	)
	return out


func _ally_sort_rank(entry: Dictionary) -> int:
	if not bool(entry.get("is_ally", false)):
		return 0
	if str(entry.get("ally_kind", "")) == "treaty":
		return 1
	return 2


## Pass 24: "treaty" formal alliance/guarantee, "partner" CRS band, "" neither.
func classify_ally_tag(owner_tag: String, player_tag: String = "") -> String:
	var o := owner_tag.strip_edges().to_upper()
	var p := player_tag.strip_edges().to_upper()
	if p.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		p = str(LeaderManager.get_player_country_tag()).to_upper()
	if o.is_empty() or p.is_empty() or o == p:
		return ""
	if typeof(RelationsManager) != TYPE_NIL:
		if RelationsManager.has_method("is_formal_ally_or_guaranteed"):
			if bool(RelationsManager.is_formal_ally_or_guaranteed(p, o)):
				return "treaty"
		elif RelationsManager.has_method("is_allied") and bool(RelationsManager.is_allied(p, o)):
			return "treaty"
	if is_crs_partner_tag(o, p):
		return "partner"
	return ""


## Pass 23: partner / ally-ready band via RelationsManager (CRS bands) OR formal treaty.
func is_ally_or_partner_tag(owner_tag: String, player_tag: String = "") -> bool:
	return not classify_ally_tag(owner_tag, player_tag).is_empty()


## Pass 24: CRS partner/ally_ready only (no formal treaty required).
func is_crs_partner_tag(owner_tag: String, player_tag: String = "") -> bool:
	var o := owner_tag.strip_edges().to_upper()
	var p := player_tag.strip_edges().to_upper()
	if p.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		p = str(LeaderManager.get_player_country_tag()).to_upper()
	if o.is_empty() or p.is_empty() or o == p:
		return false
	if typeof(RelationsManager) != TYPE_NIL:
		if RelationsManager.has_method("get_band"):
			var band: Dictionary = RelationsManager.get_band(p, o)
			var bid := str(band.get("id", "")).to_lower()
			if bid in ["partner", "ally_ready", "ally", "allied"]:
				return true
		if RelationsManager.has_method("get_crs"):
			if float(RelationsManager.get_crs(p, o)) >= 55.0:
				return true
	return false


## Pass 25/27: ensure a history track exists and append current overall risks (A–D).
func _ensure_route_risk_history_track(
	key: String,
	path_a: Array,
	path_b: Array,
	risk_a: float,
	risk_b: float,
	path_c: Array = [],
	risk_c: float = -1.0,
	path_d: Array = [],
	risk_d: float = -1.0
) -> void:
	var k := key if not key.is_empty() else "last"
	if not _route_risk_day_history.has(k) or not (_route_risk_day_history[k] is Dictionary):
		_route_risk_day_history[k] = {
			"path_a": path_a.duplicate(),
			"path_b": path_b.duplicate(),
			"path_c": path_c.duplicate(),
			"path_d": path_d.duplicate(),
			"samples_a": [],
			"samples_b": [],
			"samples_c": [],
			"samples_d": [],
		}
	var track: Dictionary = _route_risk_day_history[k]
	# Reset samples if path identity changed.
	var pa0: Array = track.get("path_a", []) as Array if track.get("path_a") is Array else []
	var pb0: Array = track.get("path_b", []) as Array if track.get("path_b") is Array else []
	var pc0: Array = track.get("path_c", []) as Array if track.get("path_c") is Array else []
	var pd0: Array = track.get("path_d", []) as Array if track.get("path_d") is Array else []
	if not _paths_equal(pa0, path_a) or not _paths_equal(pb0, path_b) \
			or not _paths_equal(pc0, path_c) or not _paths_equal(pd0, path_d):
		track["path_a"] = path_a.duplicate()
		track["path_b"] = path_b.duplicate()
		track["path_c"] = path_c.duplicate()
		track["path_d"] = path_d.duplicate()
		track["samples_a"] = []
		track["samples_b"] = []
		track["samples_c"] = []
		track["samples_d"] = []
	_append_risk_sample(track, risk_a, risk_b, risk_c, risk_d)
	_route_risk_day_history[k] = track


func _paths_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if int(a[i]) != int(b[i]):
			return false
	return true


func _append_risk_sample(
	track: Dictionary,
	risk_a: float,
	risk_b: float,
	risk_c: float = -1.0,
	risk_d: float = -1.0
) -> void:
	var sa: Array = track.get("samples_a", []) as Array if track.get("samples_a") is Array else []
	var sb: Array = track.get("samples_b", []) as Array if track.get("samples_b") is Array else []
	var sc: Array = track.get("samples_c", []) as Array if track.get("samples_c") is Array else []
	var sd: Array = track.get("samples_d", []) as Array if track.get("samples_d") is Array else []
	# Avoid duplicate consecutive equal samples within same frame.
	if not sa.is_empty() and is_equal_approx(float(sa[sa.size() - 1]), risk_a) \
			and not sb.is_empty() and is_equal_approx(float(sb[sb.size() - 1]), risk_b):
		track["samples_a"] = sa
		track["samples_b"] = sb
		track["samples_c"] = sc
		track["samples_d"] = sd
		return
	sa.append(clampf(risk_a, 0.0, 1.0))
	sb.append(clampf(risk_b, 0.0, 1.0))
	if risk_c >= 0.0:
		sc.append(clampf(risk_c, 0.0, 1.0))
	if risk_d >= 0.0:
		sd.append(clampf(risk_d, 0.0, 1.0))
	while sa.size() > ROUTE_RISK_HISTORY_MAX:
		sa.pop_front()
	while sb.size() > ROUTE_RISK_HISTORY_MAX:
		sb.pop_front()
	while sc.size() > ROUTE_RISK_HISTORY_MAX:
		sc.pop_front()
	while sd.size() > ROUTE_RISK_HISTORY_MAX:
		sd.pop_front()
	track["samples_a"] = sa
	track["samples_b"] = sb
	track["samples_c"] = sc
	track["samples_d"] = sd


func _sample_route_risk_day_history() -> void:
	if _route_risk_day_history.is_empty():
		return
	for k in _route_risk_day_history.keys():
		var track = _route_risk_day_history[k]
		if not track is Dictionary:
			continue
		var t: Dictionary = track
		var pa: Array = t.get("path_a", []) as Array if t.get("path_a") is Array else []
		var pb: Array = t.get("path_b", []) as Array if t.get("path_b") is Array else []
		var pc: Array = t.get("path_c", []) as Array if t.get("path_c") is Array else []
		var pd: Array = t.get("path_d", []) as Array if t.get("path_d") is Array else []
		if pa.is_empty() or pb.is_empty():
			continue
		var ra := estimate_path_interdiction(pa)
		var rb := estimate_path_interdiction(pb)
		var rc := estimate_path_interdiction(pc) if not pc.is_empty() else -1.0
		var rd := estimate_path_interdiction(pd) if not pd.is_empty() else -1.0
		if ra < 0.0 and rb < 0.0:
			continue
		if ra < 0.0:
			ra = 0.0
		if rb < 0.0:
			rb = 0.0
		_append_risk_sample(t, ra, rb, rc, rd)
		_route_risk_day_history[k] = t


## Pass 26/27: export multi-day risk history as CSV (clipboard + user:// file). Returns path or "".
func export_route_risk_history_csv(track_key: String = "last") -> String:
	var k := track_key if not track_key.is_empty() else "last"
	var track: Dictionary = {}
	if _route_risk_day_history.has(k) and _route_risk_day_history[k] is Dictionary:
		track = _route_risk_day_history[k] as Dictionary
	elif _route_risk_day_history.has("last") and _route_risk_day_history["last"] is Dictionary:
		track = _route_risk_day_history["last"] as Dictionary
		k = "last"
	var sa: Array = track.get("samples_a", []) as Array if track.get("samples_a") is Array else []
	var sb: Array = track.get("samples_b", []) as Array if track.get("samples_b") is Array else []
	var sc: Array = track.get("samples_c", []) as Array if track.get("samples_c") is Array else []
	var sd: Array = track.get("samples_d", []) as Array if track.get("samples_d") is Array else []
	if sa.is_empty() and sb.is_empty():
		return ""
	var lines: PackedStringArray = PackedStringArray()
	lines.append("sample,risk_a,risk_b,risk_c,risk_d,path_a_hops,path_b_hops,path_c_hops,path_d_hops,track")
	var n := maxi(sa.size(), sb.size())
	n = maxi(n, sc.size())
	n = maxi(n, sd.size())
	var pa: Array = track.get("path_a", []) as Array if track.get("path_a") is Array else []
	var pb: Array = track.get("path_b", []) as Array if track.get("path_b") is Array else []
	var pc: Array = track.get("path_c", []) as Array if track.get("path_c") is Array else []
	var pd: Array = track.get("path_d", []) as Array if track.get("path_d") is Array else []
	for i in n:
		var a := float(sa[i]) if i < sa.size() else 0.0
		var b := float(sb[i]) if i < sb.size() else 0.0
		var c := float(sc[i]) if i < sc.size() else -1.0
		var d := float(sd[i]) if i < sd.size() else -1.0
		lines.append("%d,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%d,%s" % [
			i + 1, a, b, c, d, pa.size(), pb.size(), pc.size(), pd.size(), k
		])
	var csv := "\n".join(lines) + "\n"
	# Clipboard
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(csv)
	# user:// file
	var out_path := "user://route_risk_history.csv"
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(csv)
		f.close()
		return out_path
	return ""


## Pass 28: legend swatch for risk history series.
func _add_risk_legend_swatch(parent: HBoxContainer, label: String, col: Color) -> void:
	if parent == null:
		return
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 3)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(10, 10)
	sw.color = col
	cell.add_child(sw)
	var lb := Label.new()
	lb.text = label
	lb.add_theme_font_size_override("font_size", 9)
	lb.add_theme_color_override("font_color", col)
	cell.add_child(lb)
	parent.add_child(cell)


## Pass 24: draw dual hop-risk sparklines (A cyan, B magenta) into a Control.
func _draw_compare_risk_sparkline(ctrl: Control, hops_a: Array, hops_b: Array) -> void:
	_draw_compare_risk_sparkline_multi(ctrl, hops_a, hops_b, [], [])


## Pass 27: draw up to four risk series.
func _draw_compare_risk_sparkline_multi(
	ctrl: Control,
	hops_a: Array,
	hops_b: Array,
	hops_c: Array = [],
	hops_d: Array = []
) -> void:
	if ctrl == null:
		return
	var sz := ctrl.size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	ctrl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.08, 0.12, 0.92), true)
	for i in 3:
		var gy := sz.y * float(i + 1) / 4.0
		ctrl.draw_line(Vector2(0, gy), Vector2(sz.x, gy), Color(0.2, 0.25, 0.35, 0.4), 1.0)
	_draw_risk_polyline(ctrl, hops_a, Color(0.45, 0.9, 1.0, 0.95), sz)
	_draw_risk_polyline(ctrl, hops_b, Color(1.0, 0.5, 0.85, 0.95), sz)
	if not hops_c.is_empty():
		_draw_risk_polyline(ctrl, hops_c, Color(1.0, 0.82, 0.35, 0.95), sz)
	if not hops_d.is_empty():
		_draw_risk_polyline(ctrl, hops_d, Color(0.45, 0.95, 0.55, 0.95), sz)


func _draw_risk_polyline(ctrl: Control, hops: Array, col: Color, sz: Vector2) -> void:
	if hops.is_empty():
		return
	var n := hops.size()
	var pts: PackedVector2Array = PackedVector2Array()
	for i in n:
		var t := 0.0 if n <= 1 else float(i) / float(n - 1)
		var x := 2.0 + t * (sz.x - 4.0)
		var y := sz.y - 2.0 - clampf(float(hops[i]), 0.0, 1.0) * (sz.y - 4.0)
		pts.append(Vector2(x, y))
	for i in range(pts.size() - 1):
		ctrl.draw_line(pts[i], pts[i + 1], col, 2.0)
	if pts.size() == 1:
		ctrl.draw_circle(pts[0], 2.0, col)
	elif pts.size() > 1:
		ctrl.draw_circle(pts[pts.size() - 1], 2.2, col)


## Pass 24/25: per-hop interdiction risk — path-correlated (marginal risk along prefixes).
## Hop i ≈ max(local, risk(path[0..i]) − risk(path[0..i-1])) with residual survival dampening.
func estimate_path_hop_risks(path: Array) -> Array:
	var hops: Array = []
	if path.is_empty() or typeof(SupplyManager) == TYPE_NIL:
		return hops
	if SupplyManager.rules == null or SupplyManager.provinces.is_empty():
		var overall := estimate_path_interdiction(path)
		if overall < 0.0:
			return hops
		var n := maxi(path.size(), 1)
		var per := overall / float(n)
		for _i in n:
			hops.append(per)
		return hops
	var presence: Dictionary = {}
	if SupplyManager.has_method("get_enemy_presence"):
		presence = SupplyManager.get_enemy_presence()
	var owner := str(SupplyManager.player_tag)
	var path_typed: Array[int] = []
	for p0 in path:
		path_typed.append(int(p0))
	var prev_cum := 0.0
	var residual := 1.0  # surviving fraction so far
	for i in path_typed.size():
		# Local hop risk
		var single: Array[int] = [path_typed[i]]
		var local_inter: Dictionary = SupplyInterdictionEstimator.estimate(
			single, SupplyManager.provinces, SupplyManager.hubs, owner, SupplyManager.rules, presence
		)
		var local_c := clampf(float(local_inter.get("chance", 0.0)), 0.0, 1.0)
		if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_storm_interdiction_chance"):
			local_c = maxf(local_c, float(WeatherManager.get_storm_interdiction_chance(path_typed[i], local_c)))
		# Prefix cumulative risk
		var prefix: Array[int] = []
		for j in range(i + 1):
			prefix.append(path_typed[j])
		var pref_inter: Dictionary = SupplyInterdictionEstimator.estimate(
			prefix, SupplyManager.provinces, SupplyManager.hubs, owner, SupplyManager.rules, presence
		)
		var cum := clampf(float(pref_inter.get("chance", 0.0)), 0.0, 1.0)
		var marginal := maxf(0.0, cum - prev_cum)
		# Path-correlated blend: residual amplifies later high-risk hops slightly.
		var correlated := clampf(maxf(local_c, marginal) * (0.85 + 0.25 * (1.0 - residual)), 0.0, 1.0)
		# Friendly consecutive hop dampen: if local very low and previous low, shrink further.
		if i > 0 and local_c < 0.05 and float(hops[i - 1]) < 0.05:
			correlated *= 0.7
		hops.append(correlated)
		prev_cum = cum
		residual = clampf(residual * (1.0 - correlated * 0.55), 0.15, 1.0)
	return hops


func _on_repair_queue_site(province_id: int, site_id: String) -> void:
	if not provinces.has(province_id):
		return
	var p: Province = provinces[province_id] as Province
	if p == null:
		return
	for site in p.special_sites:
		if site != null and str(site.id) == site_id and site.is_damaged():
			_on_repair_special_site_pressed(province_id, site)
			break
	if _repair_queue_chip != null and _repair_queue_chip.has_method("refresh"):
		_repair_queue_chip.call("refresh")


func _on_repair_queue_batch(limit: int) -> void:
	var cap := clampi(limit, 1, 40)
	var include_allies := false
	var ally_scope := "partner"
	if _repair_queue_chip != null:
		if "include_allies" in _repair_queue_chip:
			include_allies = bool(_repair_queue_chip.include_allies)
		if "ally_scope" in _repair_queue_chip:
			ally_scope = str(_repair_queue_chip.ally_scope)
	var entries: Array = collect_damaged_player_sites(include_allies, ally_scope)
	var repaired := 0
	for e in entries:
		if repaired >= cap:
			break
		var pid := int(e.get("province_id", -1))
		var sid := str(e.get("site_id", ""))
		if not provinces.has(pid):
			continue
		var p: Province = provinces[pid] as Province
		if p == null:
			continue
		for site in p.special_sites:
			if site == null or str(site.id) != sid:
				continue
			if not site.is_damaged():
				continue
			var amount := 1
			var mgr = _get_infra_manager()
			if mgr != null and mgr.has_method("get_engineer_brigades_in_province"):
				if float(mgr.get_engineer_brigades_in_province(pid)) > 0.5:
					amount += 1
			site.repair_damage(amount)
			repaired += 1
			if typeof(MapManager) != TYPE_NIL:
				MapManager.notify_province_changed(pid, "special_site")
			break
	var remaining := collect_damaged_player_sites(include_allies, ally_scope).size()
	call_deferred("_refresh_feature_progress_rings")
	if _repair_queue_chip != null and _repair_queue_chip.has_method("refresh"):
		_repair_queue_chip.call("refresh")
	if selected_province_id >= 0 and provinces.has(selected_province_id):
		show_info_panel(provinces[selected_province_id])
	if typeof(DebugOverlay) != TYPE_NIL:
		var scope_note := ""
		if include_allies:
			scope_note = " · +%s" % ally_scope
		DebugOverlay.toast_map_debug(
			"Theater repair · fixed %d · %d still damaged%s" % [repaired, remaining, scope_note]
		)


func _on_munitions_open_production() -> void:
	# Best-effort open production assignment if scene exists.
	var path := "res://scenes/ui/ProductionAssignmentScreen.tscn"
	if not ResourceLoader.exists(path):
		path = "res://scripts/ui/ProductionAssignmentScreen.gd"
	if ResourceLoader.exists("res://scenes/ui/ProductionAssignmentScreen.tscn"):
		var packed: PackedScene = load("res://scenes/ui/ProductionAssignmentScreen.tscn") as PackedScene
		if packed != null:
			var screen = packed.instantiate()
			if screen != null:
				screen.name = "ProductionAssignmentScreen"
				get_tree().root.add_child(screen)
				if typeof(DebugOverlay) != TYPE_NIL:
					DebugOverlay.toast_map_debug("Opened production assignment")
				return
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Production screen unavailable — munitions cargo set via desk")


## Pass 15–17: multi-mode preset stacks — secondary overlays/tints on top of primary mapmode.
## stack items: "supply", "weather", "naval", "strain", "vitality", "loyalty", "development", "convoy_minimap".
func apply_mapmode_preset_stack(primary_mode: String, stack: Array = []) -> void:
	var pm := primary_mode.strip_edges().to_lower()
	var want_supply := "supply" in stack or pm == "supply"
	var want_weather_fx := "weather" in stack or pm == "weather"
	var want_convoy_mm := "convoy_minimap" in stack or want_supply or pm == "supply"
	# Pass 17: collect ALL secondary tints (not just first).
	debug_tint_mode_secondaries.clear()
	debug_tint_mode_secondary = ""
	for s in stack:
		var sk := str(s).strip_edges().to_lower()
		if sk in ["strain", "vitality", "development", "loyalty"] and sk != pm and sk != debug_tint_mode:
			if sk not in debug_tint_mode_secondaries:
				debug_tint_mode_secondaries.append(sk)
	if not debug_tint_mode_secondaries.is_empty():
		debug_tint_mode_secondary = str(debug_tint_mode_secondaries[0])
	# Primary mode already applied by toolbar set_mode; only adjust overlays that mode alone wouldn't keep.
	if want_supply:
		if not supply_mode:
			_toggle_supply_overlay()
	else:
		# Leaving stacked supply: only turn off if primary is not supply.
		if supply_mode and pm != "supply":
			_toggle_supply_overlay()
	_sync_weather_mapmode_particles(want_weather_fx)
	# Pass 16: convoy pips on minimap when logistics-like.
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_show_convoy_pips"):
		_map_minimap.call("set_show_convoy_pips", want_convoy_mm)
	# Pass 23: munitions depot pips when primary is munitions or stack asks for it.
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_show_munitions_pips"):
		_map_minimap.call("set_show_munitions_pips", pm == "munitions" or "munitions" in stack)
	# Pass 28: munitions occupation filter from stack flags.
	var mun_filt := "all"
	if "munitions_occupied" in stack:
		mun_filt = "occupied"
	elif "munitions_mine" in stack:
		mun_filt = "mine"
	elif "munitions_all" in stack or pm == "munitions":
		mun_filt = "all"
	if pm == "munitions" or "munitions_occupied" in stack or "munitions_mine" in stack or "munitions_all" in stack:
		_on_munitions_occupation_filter_changed(mun_filt)
		# Sync desk chip if present.
		if _munitions_desk != null and is_instance_valid(_munitions_desk):
			if "map_occupation_filter" in _munitions_desk:
				_munitions_desk.map_occupation_filter = mun_filt
			if "map_pips_player_only" in _munitions_desk:
				_munitions_desk.map_pips_player_only = (mun_filt == "mine")
			if _munitions_desk.has_method("_sync_map_filter_btn"):
				_munitions_desk.call("_sync_map_filter_btn")
			if _munitions_desk.has_method("_sync_occ_filter_btn"):
				_munitions_desk.call("_sync_occ_filter_btn")
	# Pass 19/22: munitions desk for supply stacks / munitions primary.
	set_munitions_desk_visible(want_supply or pm == "supply" or pm == "munitions" or supply_mode)
	set_repair_queue_visible(want_supply or pm in ["supply", "munitions", "infra"] or supply_mode)
	if not debug_tint_mode_secondaries.is_empty() or debug_tint_mode_secondary != "" or pm == "munitions":
		_refresh_province_fill_colors(true)
	if typeof(DebugOverlay) != TYPE_NIL and not stack.is_empty():
		var parts: PackedStringArray = PackedStringArray()
		for s2 in stack:
			parts.append(str(s2))
		DebugOverlay.toast_map_debug("Preset stack: %s + %s" % [primary_mode, "+".join(parts)])


func set_map_mode(mode: String = "political") -> void:
	var m := mode.strip_edges().to_lower()
	if m == "chokepoints":
		m = "naval"
	if not m in ["political", "strain", "vitality", "development", "supply", "munitions", "loyalty", "infra", "naval", "weather", "resources", "states", "terrain"]:
		m = "political"
	if m == current_map_mode and m != "infra" and m != "naval":
		return
	current_map_mode = m
	# Clear secondary stack tints unless re-applied by preset.
	debug_tint_mode_secondary = ""
	debug_tint_mode_secondaries.clear()
	if m == "supply" or m == "munitions":
		if not supply_mode and m == "supply":
			_toggle_supply_overlay()
		elif m == "munitions" and not supply_mode:
			# Munitions heatmap does not force route overlay; routes optional via Ammo preset stack.
			pass
		elif m != "supply" and m != "munitions" and supply_mode:
			_toggle_supply_overlay()
	elif supply_mode:
		_toggle_supply_overlay()
	# Convoy minimap pips follow supply mode.
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_show_convoy_pips"):
		_map_minimap.call("set_show_convoy_pips", m == "supply" or supply_mode)
	# Pass 23: munitions depot pips on minimap in munitions (and ammo logistics) mode.
	if _map_minimap != null and is_instance_valid(_map_minimap) and _map_minimap.has_method("set_show_munitions_pips"):
		_map_minimap.call("set_show_munitions_pips", m == "munitions")
	# Pass 19/22: munitions desk in supply / munitions modes.
	set_munitions_desk_visible(m == "supply" or m == "munitions" or supply_mode)
	# Pass 22: repair queue chip for infra / munitions / supply ops.
	set_repair_queue_visible(m in ["infra", "munitions", "supply"] or supply_mode)
	# Infra mode: show roads/rails + numbers. Supply: sparse muted roads (not full spiderweb).
	# Political (default): hide for clean fills.
	var ol_infra := get_overlay_layer("InfrastructureOverlayLayer")
	if m == "infra":
		if ol_infra and ol_infra.has_method("_schedule_rebuild_all_infra_layers"):
			ol_infra.call("_schedule_rebuild_all_infra_layers")
		elif ol_infra and ol_infra.has_method("rebuild_all_infra_layers"):
			ol_infra.call_deferred("rebuild_all_infra_layers")
		if ol_infra and ol_infra.has_method("set_show_roads"):
			ol_infra.set_show_roads(true)
			ol_infra.set_show_rails(true)
		if ol_infra and ol_infra.has_method("set_show_sites"):
			ol_infra.set_show_sites(true)
	elif m == "supply" or m == "munitions":
		# Corridor-only: roads off by default; G/highlight paints the single path.
		# (Was: set_show_roads true + full mesh = yellow spiderweb.)
		if ol_infra and ol_infra.has_method("set_show_rails"):
			ol_infra.set_show_rails(false)
		if ol_infra and ol_infra.has_method("set_show_roads"):
			ol_infra.set_show_roads(false)
		if supply_map_layer != null:
			supply_map_layer.corridor_focus_only = true
	elif m == "political" and ol_infra:
		if ol_infra.has_method("set_show_roads"):
			ol_infra.set_show_roads(false)
		if ol_infra.has_method("set_show_rails"):
			ol_infra.set_show_rails(false)
		if ol_infra.has_method("set_show_sites"):
			ol_infra.set_show_sites(false)
		if ol_infra.has_method("clear_supply_corridor_path"):
			ol_infra.call("clear_supply_corridor_path")
		if supply_map_layer != null:
			supply_map_layer.corridor_focus_only = false
			if supply_map_layer.has_method("clear_route_highlight"):
				supply_map_layer.call("clear_route_highlight")
		if ol_infra.has_method("queue_redraw"):
			ol_infra.queue_redraw()
	if m == "naval":
		var ol_n := get_overlay_layer("InfrastructureOverlayLayer")
		if ol_n and ol_n.has_method("queue_redraw"):
			ol_n.queue_redraw()
	if m == "weather":
		debug_tint_mode = "weather"
	elif m == "munitions":
		debug_tint_mode = "munitions"
	elif m == "resources":
		debug_tint_mode = "resources"
	elif m == "states":
		debug_tint_mode = "states"
	elif m == "terrain":
		debug_tint_mode = "terrain"
	else:
		debug_tint_mode = "strain" if m == "strain" else ("vitality" if m == "vitality" else ("development" if m == "development" else ("loyalty" if m == "loyalty" else ("infra" if m == "infra" else ("region_control" if m == "region_control" else ("naval" if m == "naval" else ""))))))
	# Stream 2: state name labels on states mapmode (operational zoom).
	if _political_labels_layer != null and is_instance_valid(_political_labels_layer):
		if _political_labels_layer.has_method("set_map_mode_context"):
			_political_labels_layer.call("set_map_mode_context", m)
	# Pass 22: restore remembered primary intensity for linked modes.
	if m in INTENSITY_LINKED_MODES and primary_mapmode_intensity.has(m):
		secondary_tint_intensity[m] = clampf(float(primary_mapmode_intensity[m]), 0.25, 2.0)
	if not _map_mode_apply_scheduled:
		_map_mode_apply_scheduled = true
		call_deferred("_apply_map_mode_visuals")


func _apply_map_mode_visuals() -> void:
	_map_mode_apply_scheduled = false
	var m := current_map_mode
	# Nuclear: kill batched mesh on every mapmode switch. Mesh is owner-only and used to
	# leave land polys at a≈0.02 → F2–F4 looked like Europe vanished when mesh went off.
	_batched_mesh_active = false
	_batched_mesh_fills_forced = false
	if _province_mesh_layer != null and is_instance_valid(_province_mesh_layer):
		if _province_mesh_layer.has_method("set_enabled"):
			_province_mesh_layer.call("set_enabled", false)
		_province_mesh_layer.visible = false
	# Viewport cull can leave most of Europe node.visible=false; mapmode must not inherit holes.
	_force_all_province_nodes_visible()
	_refresh_province_fill_colors(true)
	_restore_land_poly_visibility()
	# Capitals on every mode; F1 especially must show full star set.
	_ensure_capital_stars_visible()
	# Choke diamonds redraw so Danish/English Channel stay at correct sea centroids.
	var ol_infra2 := get_overlay_layer("InfrastructureOverlayLayer")
	if ol_infra2 != null and ol_infra2.has_method("queue_redraw"):
		ol_infra2.queue_redraw()
	if info_panel and info_panel is CanvasItem and info_panel.visible and selected_province_id >= 0 and provinces.has(selected_province_id):
		show_info_panel(provinces[selected_province_id])
	if m in ["occupation", "resistance", "compliance"]:
		show_occupation_overlay = true
		_setup_occupation_layer()
		if _occupation_layer != null and _occupation_layer.has_method("set_mapmode"):
			_occupation_layer.set_mapmode(m)
			if m != "occupation" and _occupation_layer.get("include_non_contested_heatmap") != null:
				_occupation_layer.include_non_contested_heatmap = true
	# Pass 11: weather mapmode enables lightweight particle cues on WeatherOverlayLayer.
	_sync_weather_mapmode_particles(m == "weather")
	print("MapRenderer: map_mode set to '%s' (current_map_mode=%s, debug_tint_mode='%s')." % [m, current_map_mode, debug_tint_mode])
	if typeof(DebugOverlay) != TYPE_NIL:
		var mode_label := "Political (default · F1)"
		if m == "strain": mode_label = "Strain (F2) · social/economic stress heatmap — redder = more strain; still shows ownership"
		elif m == "vitality": mode_label = "Vitality · settlement/pop green (F3)"
		elif m == "development": mode_label = "Development · low amber → high cream (F4)"
		elif m == "supply": mode_label = "Supply overlay (F5)"
		elif m == "munitions": mode_label = "Munitions: per-depot stockpile heatmap"
		elif m == "loyalty": mode_label = "Loyalty (foreign mil % tint)"
		elif m == "infra": mode_label = "Infra/Road Density"
		elif m == "naval": mode_label = "Naval: sea zones + chokepoints + coast"
		elif m == "weather": mode_label = "Weather: dry / mud / snow / storm + particles"
		elif m == "resources": mode_label = "Resources · oil green · rubber lime · steel grey · coal dark · empty=dim land (F9)"
		elif m == "states": mode_label = "States · colored fills by state · names @ operational zoom (Shift+F9)"
		elif m == "terrain": mode_label = "Terrain · plains/forest/mtn/desert · sea blue (Ctrl+F9)"
		DebugOverlay.toast_map_debug("Map mode: %s — %s" % [m, mode_label])
	call_deferred("_ensure_capital_stars_visible")
	if m == "political":
		# F1: always re-assert full capital star set after any mesh/cull path.
		call_deferred("_force_all_province_nodes_visible")
		call_deferred("_ensure_capital_stars_visible")


## Mapmode / F1: every province node visible (undo viewport cull holes).
func _force_all_province_nodes_visible() -> void:
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


## After mapmode / mesh toggles: land polys must be opaque; sea below land z.
func _restore_land_poly_visibility() -> void:
	for pid in province_nodes.keys():
		var node: Node2D = province_nodes[pid] as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var province: Province = provinces.get(pid) as Province if provinces.has(pid) else null
		var poly: Polygon2D = _get_province_polygon(node)
		if poly == null:
			continue
		var is_water := false
		if province != null:
			is_water = bool(province.is_sea)
			var terr := str(province.terrain).to_lower()
			if terr in ["sea", "ocean", "water", "strait"]:
				is_water = true
		# Sea IDs on this board are 950000+
		if int(pid) >= 950000:
			is_water = true
		node.z_index = _province_draw_z_index(int(pid), is_water)
		if is_water:
			var sc := poly.color
			sc.a = 1.0
			poly.color = sc
		else:
			var col := poly.color
			if col.a < 0.85:
				col.a = 0.96
			# Never leave land near-black (looks "deleted")
			if col.r + col.g + col.b < 0.12:
				col = Color(0.35, 0.38, 0.42, 0.96)
			poly.color = col
		# Capital stars: always on top of land (all mapmodes including F2–F4)
		for child in node.get_children():
			if child is Label and (child as Label).has_meta(META_MAP_GLYPH_CAPITAL):
				var lbl := child as Label
				lbl.visible = true
				lbl.modulate = Color(1.0, 1.0, 1.0, 1.0)
				lbl.z_as_relative = false
				lbl.z_index = 40
				lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.15, 1.0))
				lbl.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05, 1.0))
				lbl.add_theme_constant_override("outline_size", 8)


func _ensure_capital_stars_visible() -> void:
	_restore_land_poly_visibility()
	# Re-stamp stars if missing (mapmode / mesh paths must never drop capitals).
	var n_stars := 0
	for pid in province_nodes.keys():
		var node: Node2D = province_nodes[pid] as Node2D
		if node == null:
			continue
		var province: Province = provinces.get(pid) as Province if provinces.has(pid) else null
		if province == null or not province.has_feature("capital"):
			continue
		var has_star := false
		for child in node.get_children():
			if child is Label and (child as Label).has_meta(META_MAP_GLYPH_CAPITAL):
				has_star = true
				n_stars += 1
				break
		if not has_star:
			_add_capital_star_to_node(node, int(pid))
			n_stars += 1
	if n_stars > 0:
		print("MapRenderer: capital stars visible n=%d" % n_stars)


func _add_capital_star_to_node(node: Node2D, pid: int) -> void:
	var center: Vector2 = province_centroids.get(pid, Vector2.ZERO) as Vector2
	if center == Vector2.ZERO:
		return
	var star := Label.new()
	star.text = "★"
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.z_as_relative = false
	star.z_index = 40
	star.add_theme_font_size_override("font_size", 30)
	# Bright gold fill + thick dark+white outline so stars read on yellow (BEL) and light paints.
	star.add_theme_color_override("font_color", Color(1.0, 0.92, 0.15, 1.0))
	star.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.05, 1.0))
	star.add_theme_constant_override("outline_size", 8)
	star.modulate = Color(1.0, 1.0, 1.0, 1.0)
	star.set_meta(META_MAP_GLYPH_PX, 30)
	star.set_meta(META_MAP_GLYPH_CAPITAL, true)
	star.reset_size()
	var sms := star.get_minimum_size()
	star.position = center - sms * 0.5
	node.add_child(star)


func _sync_weather_mapmode_particles(enable: bool) -> void:
	_setup_weather_overlay_layer()
	if weather_layer != null:
		# Ensure overlay can read province_centroids for per-province particle density.
		if "map_renderer" in weather_layer:
			weather_layer.map_renderer = self
		if weather_layer.has_method("set_particle_mode"):
			weather_layer.call("set_particle_mode", enable)
		elif weather_layer.has_method("set_show_weather"):
			# Fallback: full weather layer toggle when particle API missing.
			if enable:
				weather_layer.call("set_show_weather", true)
		if enable:
			_sync_weather_particle_filter()
		elif weather_layer.has_method("set_particle_ground_filter"):
			weather_layer.call("set_particle_ground_filter", "")
	# Pass 15: minimap weather dots track weather mapmode / Climate preset.
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("set_show_weather_dots"):
			_map_minimap.call("set_show_weather_dots", enable)
		elif _map_minimap.has_method("invalidate_weather_cache"):
			_map_minimap.call("invalidate_weather_cache")


func hide_info_panel() -> void:
	if info_panel and info_panel is CanvasItem:
		info_panel.visible = false
	elif info_panel != null:
		push_warning("MapRenderer: hide_info_panel called on non-CanvasItem (got " + str(info_panel.get_script() if info_panel.get_script() else info_panel.get_class()) + ")")
	if _province_id_badge != null:
		_province_id_badge.visible = false
	_selected_coarse_id = 0


## Top-right province id chip on the inspector (playtest callouts: "look at #710569").
func _ensure_province_id_badge() -> void:
	if _province_id_badge != null and is_instance_valid(_province_id_badge):
		return
	if info_panel == null or not (info_panel is Control):
		return
	_province_id_badge = Label.new()
	_province_id_badge.name = "ProvinceIdBadge"
	_province_id_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_province_id_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_province_id_badge.add_theme_font_size_override("font_size", 13)
	_province_id_badge.add_theme_color_override("font_color", Color(0.92, 0.86, 0.55, 1.0))
	_province_id_badge.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08, 0.95))
	_province_id_badge.add_theme_constant_override("outline_size", 3)
	_province_id_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_province_id_badge.visible = false
	(info_panel as Control).add_child(_province_id_badge)
	_clear_selection()
	_hide_oob_strip()


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
		_sync_strategic_flow_lod(tier)
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

		var label_budget := int(MapZoomLODScript.max_province_labels_for_board(provinces.size()))
		var labels_shown := 0
		for id in _province_name_labels:
			var lbl: Variant = _province_name_labels[id]
			if lbl is Label and is_instance_valid(lbl):
				var show_lbl := show_prov_names and show_details
				if show_lbl:
					if labels_shown >= label_budget:
						show_lbl = false
					else:
						labels_shown += 1
				(lbl as Label).visible = show_lbl
				if show_lbl:
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
			var is_capital := lbl.has_meta(META_MAP_GLYPH_CAPITAL)
			# Capital gold stars stay visible at all zoom levels (Washington/Tokyo were
			# hidden when detail glyphs culled at strategic zoom).
			lbl.visible = true if is_capital else show_glyphs
			if show_glyphs or is_capital:
				var zsc := _zoom_detail_scale_smooth(zoom_metric, 1.8)
				var fs := clampi(int(round(float(base_px) * zsc)), maxi(8, base_px - 6), 40)
				if is_capital:
					fs = clampi(int(round(28.0 * maxf(0.85, zsc))), 18, 36)
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
			if is_capital:
				# Keep gold capital star (do not wash to white like feature glyphs).
				lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.18, 1.0))
				lbl.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.02, 0.92))
				lbl.add_theme_constant_override("outline_size", 6)
				lbl.z_index = ProvinceMapVisuals.Z_MAP_GLYPH + 2
			else:
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
			if is_capital:
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
	# Accurate board: full political paint + capitals on first frame (no lazy holes).
	call_deferred("_boot_political_map_complete")


## Async init for loading screen: yields so progress/UI can update (avoids freeze at ~50%).
func initialize_async(p_provinces: Dictionary, p_geometry: Dictionary, p_adjacency: AdjacencySystem, p_countries: Dictionary = {}, progress_cb: Callable = Callable()) -> void:
	provinces = MapScenarioData.coerce_provinces(p_provinces)
	geometry = p_geometry
	adjacency = p_adjacency
	countries = MapScenarioData.coerce_countries(p_countries)
	await render_provinces_async(progress_cb)
	_fit_background_to_bounds()
	call_deferred("_boot_political_map_complete")


## After first render: paint every province + capital stars (fixes NOR/SWE/FIN/UK-north missing until F2).
func _boot_political_map_complete() -> void:
	_force_all_province_nodes_visible()
	_refresh_province_fill_colors(true)
	_restore_land_poly_visibility()
	_ensure_capital_stars_visible()
	var ol := get_overlay_layer("InfrastructureOverlayLayer")
	if ol != null and ol.has_method("queue_redraw"):
		ol.queue_redraw()


var _render_restore_pid: int = -1


func render_provinces():
	# Sync path (tests / tools). Prefer render_provinces_async during F5 load.
	if container == null:
		push_error("MapRenderer: container not assigned")
		return
	var raster_preserved: Dictionary = _render_provinces_begin()
	_render_provinces_create_all_sync()
	_render_provinces_finish(raster_preserved)


func render_provinces_async(progress_cb: Callable = Callable()) -> void:
	if container == null:
		push_error("MapRenderer: container not assigned")
		return
	var raster_preserved: Dictionary = _render_provinces_begin()
	await _render_provinces_create_all_async(progress_cb)
	_render_provinces_finish(raster_preserved)


func _render_provinces_begin() -> Dictionary:
	_render_restore_pid = selected_province_id if info_panel != null and info_panel is CanvasItem and info_panel.visible else -1
	_clear_selection()
	# Preserve rasters and weather layer so map images (WorldBackground/ProvinceMap) and weather visuals survive the render clear.
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
	return raster_preserved


func _render_provinces_create_all_sync() -> void:
	for id in provinces.keys():
		var province: Province = provinces[id]
		if not geometry.has(id):
			continue
		var geo = geometry[id]
		var node := _create_province_node(province, geo)
		container.add_child(node)
		province_nodes[id] = node


func _render_provinces_create_all_async(progress_cb: Callable) -> void:
	var total := provinces.size()
	var done := 0
	var batch := 80 if total >= 800 else 200
	for id in provinces.keys():
		var province: Province = provinces[id]
		if not geometry.has(id):
			done += 1
			continue
		var geo = geometry[id]
		var node := _create_province_node(province, geo)
		container.add_child(node)
		province_nodes[id] = node
		done += 1
		if done % batch == 0:
			if progress_cb.is_valid():
				progress_cb.call(done, total)
			if get_tree():
				await get_tree().process_frame


func _render_provinces_finish(raster_preserved: Dictionary) -> void:
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

	# Europe-local boards only: apply grand theater raster. GIS world_accurate must NEVER
	# replace world equirect with Europe 5k×2k (that was the dual-map card vs giant polys).
	if not _is_gis_board_active():
		call_deferred("apply_phase1_europe_background")
	else:
		# Re-assert world underlay after poly render (defeats any late Europe bg path).
		call_deferred("load_world_grand_underlay")
		call_deferred("ensure_world_navigation_ready")

	# GIS world_accurate: solid ownership fills by default (clean political). Terrain ON = dimmer.
	# Grand Europe-only stylized: low alpha so raster terrain shows through when terrain ON.
	var fill_a := 0.96 if not show_terrain_layer else 0.78
	if is_using_grand_stylized_map() and not is_using_world_grand_map():
		fill_a = 0.06 if show_terrain_layer else 0.96
	elif is_using_world_grand_map() or (typeof(MapManager) != TYPE_NIL and MapManager.has_method("is_geometry_world_native") and bool(MapManager.is_geometry_world_native())):
		fill_a = 0.72 if show_terrain_layer else 0.96
	for id in province_nodes:
		var n = province_nodes[id]
		if n:
			for ch in n.get_children():
				if ch is Polygon2D:
					var c := (ch as Polygon2D).color
					# Sea: force continuous ocean alpha (no void-hex underlay bleed).
					var is_sea_node := false
					if provinces.has(int(id)):
						var pv: Province = provinces[int(id)] as Province
						if pv != null and pv.is_sea:
							is_sea_node = true
							c = continuous_sea_fill_color(c, sea_political_trace)
					c.a = 1.0 if is_sea_node else fill_a
					(ch as Polygon2D).color = c
	# Lock unified canvas after every render (defeats late TestRunner dual-scale).
	_unify_map_canvas_transform()
	_fit_background_to_bounds()
	_ensure_ocean_floor()
	_apply_terrain_layer_visibility()
	_apply_clean_political_clear_color()

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
	_setup_occupation_layer()
	_setup_strategic_flow_layer()
	_setup_battle_indicator_layer()
	_setup_land_battle_bubble_layer()
	_refresh_next_hook_chip()
	_setup_domain_ops_layer()
	_setup_leader_station_layer()
	_setup_construction_progress_layer()
	_setup_agent_layer()
	_setup_infrastructure_overlay_layer()
	call_deferred("_setup_terrain_layer_stack")
	call_deferred("_setup_weather_overlay_layer")
	_refresh_supply_highlights()
	_update_compare_hint_label()
	print("✅ Map rendered with real polygons")

	if _render_restore_pid >= 0 and provinces.has(_render_restore_pid):
		var restored: Province = provinces[_render_restore_pid] as Province
		var restored_node: Node2D = _province_node(_render_restore_pid)
		if restored != null and restored_node != null:
			_select_province(restored, restored_node)
			show_info_panel(restored)
	_render_restore_pid = -1

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
	_sync_unit_counter_visibility()  # strategic zoom starts clean (pins off until zoom in / Shift+U)
	call_deferred("_rebuild_province_mesh_layer")
	call_deferred("_sync_batched_mesh_fills", true)


# ====================== PHASE E: BATCHED MESH FILLS ======================

func set_batched_mesh_fills_forced(on: bool) -> void:
	_batched_mesh_fills_forced = on
	_sync_batched_mesh_fills(true)


func is_batched_mesh_fills_active() -> bool:
	return _batched_mesh_active


func get_batched_mesh_stats() -> Dictionary:
	var tier := MapZoomLODScript.tier_for_zoom(_get_camera_zoom())
	var board_n := provinces.size()
	var prefer := MapZoomLODScript.use_batched_mesh_fills_for_board(tier, board_n)
	var tier_label := MapZoomLODScript.tier_name(tier)
	if _province_mesh_layer != null and _province_mesh_layer.has_method("get_stats"):
		var stats: Dictionary = _province_mesh_layer.call("get_stats")
		stats["active"] = _batched_mesh_active
		stats["zoom"] = _get_camera_zoom()
		stats["tier"] = tier_label
		stats["province_count"] = board_n
		stats["batch_preferred"] = prefer
		stats["forced"] = _batched_mesh_fills_forced
		return stats
	return {
		"active": _batched_mesh_active,
		"polygons": 0,
		"buckets": 0,
		"zoom": _get_camera_zoom(),
		"tier": tier_label,
		"province_count": board_n,
		"batch_preferred": prefer,
		"forced": _batched_mesh_fills_forced,
	}


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
	var wn := false
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("is_geometry_world_native"):
		wn = bool(MapManager.is_geometry_world_native())
	# Same transform as Polygon2D nodes — never draw raw 8192-space against THEATER_SCALE underlay.
	_province_mesh_layer.call(
		"rebuild_from_provinces",
		provinces,
		geometry,
		owner_resolver,
		_is_world_canvas_active(),
		wn
	)


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


func _schedule_political_labels_rebuild() -> void:
	if _political_labels_rebuild_pending:
		return
	_political_labels_rebuild_pending = true
	call_deferred("_flush_political_labels_rebuild")


func _flush_political_labels_rebuild() -> void:
	_political_labels_rebuild_pending = false
	_rebuild_political_labels()


func _rebuild_political_labels() -> void:
	var layer := _ensure_political_labels_layer()
	if layer == null:
		return
	if layer.has_method("rebuild_from_map_data"):
		layer.call("rebuild_from_map_data", province_centroids, provinces)
	if layer.has_method("set_map_mode_context"):
		layer.call("set_map_mode_context", current_map_mode)
	if layer.has_method("sync_tier"):
		layer.call("sync_tier", _map_lod_tier)


func _sync_political_labels_tier(tier: int) -> void:
	if _political_labels_layer != null and is_instance_valid(_political_labels_layer):
		if _political_labels_layer.has_method("set_map_mode_context"):
			_political_labels_layer.call("set_map_mode_context", current_map_mode)
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
	# Rebuild when internal-border policy changes (strategic/operational hide, tactical shows).
	var want_internal := MapZoomLODScript.show_province_internal_borders(tier)
	var had_internal := MapZoomLODScript.show_province_internal_borders(_border_lod_tier_built) if _border_lod_tier_built >= 0 else false
	if _border_lod_tier_built < 0 or want_internal != had_internal or border_layer.get_child_count() == 0:
		_update_country_borders()
		_border_lod_tier_built = tier
	var w: float = MapZoomLODScript.country_border_width(tier)
	var a: float = MapZoomLODScript.country_border_alpha(tier)
	var cw: float = MapZoomLODScript.coast_border_width(tier)
	var iw: float = MapZoomLODScript.province_internal_border_width(tier)
	for child in border_layer.get_children():
		if not (child is Line2D):
			continue
		var nm := str(child.name)
		var seg := child as Line2D
		if nm.begins_with(COUNTRY_FRONTIER_PREFIX):
			seg.width = w
			var c := seg.default_color
			c.a = a
			seg.default_color = c
		elif nm.begins_with(COAST_FRONTIER_PREFIX):
			seg.width = cw
		elif nm.begins_with(PROVINCE_EDGE_PREFIX):
			seg.width = iw
			seg.visible = want_internal


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
	var prov_count := province_nodes.size()
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_count"):
		prov_count = maxi(prov_count, int(MapManager.get_province_count()))
	var use_cull := MapZoomLODScript.use_viewport_culling_for_board(_map_lod_tier, prov_count)
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
	var cull_margin := MapZoomLODScript.cull_rect_margin_px(prov_count)
	var visible_pids: Dictionary = {}
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_in_rect"):
		for pid in MapManager.get_provinces_in_rect(world_rect, cull_margin):
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
	# Accurate GIS board (~3.5k): never batch — even if forced. Mesh is owner-only and left
	# land polys at a≈0.02 so F2–F4 looked like Europe vanished when mesh disabled.
	var board_n := maxi(provinces.size(), province_nodes.size())
	if board_n >= MapZoomLODScript.ACCURATE_BOARD_CULL_THRESHOLD:
		return false
	if _batched_mesh_fills_forced:
		return true
	if not _batched_mesh_fills_prefer:
		return false
	if current_map_mode != "political" and not str(current_map_mode).is_empty():
		return false
	if debug_tint_mode != "":
		return false
	if supply_mode:
		return false
	if show_terrain_layer:
		return false
	var tier := MapZoomLODScript.tier_for_zoom(_get_camera_zoom())
	return MapZoomLODScript.use_batched_mesh_fills_for_board(tier, board_n)


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
		# Keep land polys readable even under mesh (was a=0.02 → land "vanished" if mesh failed).
		for pid in province_nodes.keys():
			var node: Node2D = province_nodes[pid] as Node2D
			if node == null:
				continue
			var poly := _get_province_polygon(node)
			if poly == null:
				continue
			var prov: Province = provinces.get(pid) as Province if provinces.has(pid) else null
			var c := poly.color
			var is_w := (prov != null and bool(prov.is_sea)) or int(pid) >= 950000
			if is_w:
				c.a = 0.85
			else:
				c.a = 0.55  # mesh paints solid; poly still shows if mesh gaps
			node.z_index = _province_draw_z_index(int(pid), is_w)
			poly.color = c
	else:
		if _province_mesh_layer.has_method("set_enabled"):
			_province_mesh_layer.call("set_enabled", false)
		_refresh_province_fill_colors(true)
		_restore_land_poly_visibility()


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

	# Expensive chunk/theater swaps: skip while full world underlay is already active on large boards.
	# load_world_chunk_underlay mid-pan (decode + re-seed all snow provinces) was freezing/crashing F5.
	var board_n := maxi(provinces.size(), province_nodes.size())
	var world_active := bool(get_meta("full_world_underlay_active", false))
	var allow_chunk_swap := not world_active or board_n < 800
	if allow_chunk_swap and z > CHUNK_LOAD_ZOOM_MIN:
		var ci := _compute_world_chunk_index(p)
		var tid := "chunk%d_demo" % ci
		if tid != _active_theater_id:
			load_theater(tid)
	elif z < 0.55:
		if MapCanvasConfig.is_world_mode(_current_theater_bounds):
			if tls and tls.has_method("set_layer_alphas"):
				tls.call("set_layer_alphas", 0.75, 0.65)
			if not world_active and board_n < 800:
				load_theater("world")
		elif allow_chunk_swap and _active_theater_id != "europe":
			load_theater("europe")
	elif z < 0.8 and tls and tls.has_method("set_layer_alphas") and _last_lod_band != 1:
		_last_lod_band = 1
		tls.call("set_layer_alphas", 0.85, 0.75)

	if _theater_print_count % 48 == 0 and OS.is_stdout_verbose():
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
	var z := maxf(0.04, cam.zoom.x if cam else 1.0)
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1920, 1080)
	# Viewport-aware limits: camera center may sit so that map edges can reach screen edges.
	# (Old clamp kept center inside map AABB only — with high zoom that felt fine, but
	# combined with wrong/short theater bounds blocked pan to Europe/Asia.)
	var half := Vector2(vp.x / (2.0 * z), vp.y / (2.0 * z))
	var min_c := b.position + half
	var max_c := b.position + b.size - half
	if min_c.x > max_c.x:
		pos.x = b.get_center().x
	else:
		pos.x = clampf(pos.x, min_c.x, max_c.x)
	if min_c.y > max_c.y:
		pos.y = b.get_center().y
	else:
		pos.y = clampf(pos.y, min_c.y, max_c.y)
	return pos


## Call after world_accurate (or any full GIS board) finishes loading polys.
## Lowers min zoom, syncs pan AABB to MapManager, refits underlay, keeps Europe reachable by pan.
func ensure_world_navigation_ready() -> void:
	_unify_map_canvas_transform()
	if _is_gis_board_active():
		enable_map_wrap = false
		# Zoom out enough to fit full equirect (Americas→Asia→Australia) on common 1080p/1440p.
		world_min_zoom = minf(world_min_zoom, 0.035)
		min_zoom = minf(min_zoom, world_min_zoom)
		pan_speed = maxf(pan_speed, 2600.0)
		edge_scroll_speed = maxf(edge_scroll_speed, 2600.0)
	# Fit underlay to equirect WORLD_CANONICAL and set pan theater (do NOT replace with
	# centroid-only AABB — that recreated the dual-map / clipped-Asia look).
	_fit_background_to_bounds()
	_reassert_gis_single_canvas()
	_clamp_camera_to_theater()
	print("MapRenderer: world nav ready · theater=%s · min_zoom=%.3f · pan=%.0f · container_scale=%s" % [
		str(_current_theater_bounds), min_zoom, pan_speed,
		str(container.scale) if container else "?",
	])


## Runtime dual-map guard: container identity + underlay display size == WORLD_CANONICAL for GIS.
func _reassert_gis_single_canvas() -> void:
	if not _is_gis_board_active():
		return
	if container == null:
		container = get_node_or_null("ProvinceContainers") as Node2D
	if container == null:
		return
	var dirty := false
	if container.scale != Vector2.ONE:
		container.scale = Vector2.ONE
		dirty = true
	if container.position != Vector2.ZERO:
		container.position = Vector2.ZERO
		dirty = true
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg == null:
		return
	if bg.get_parent() != container:
		_unify_map_canvas_transform()
		dirty = true
	# If Europe grand leaked in, restore world equirect (never stretch 5k×2k to world canvas).
	if bg.texture:
		var rp := str(bg.texture.resource_path).to_lower()
		var is_world_tex := ("world_grand" in rp) or rp.ends_with("world_map.png") or ("world_grand_theater" in rp)
		var is_europe_tex := ("europe_grand" in rp) or (("grand_theater" in rp) and not is_world_tex)
		if is_europe_tex or not is_world_tex:
			var wpath := "res://assets/maps/layers/world_grand_theater_clean.png"
			if ResourceLoader.exists(wpath):
				var wtex := load(wpath) as Texture2D
				if wtex:
					bg.texture = wtex
					set_meta("full_world_underlay_active", true)
					dirty = true
	if bg.texture == null:
		return
	var want := WORLD_CANONICAL_BOUNDS
	var img := Vector2(float(bg.texture.get_width()), float(bg.texture.get_height()))
	if img.x <= 0.0 or img.y <= 0.0:
		return
	var want_scale := Vector2(want.size.x / img.x, want.size.y / img.y)
	if bg.centered or bg.position.distance_to(want.position) > 0.5:
		bg.centered = false
		bg.position = want.position
		dirty = true
	if absf(bg.scale.x - want_scale.x) > 0.001 or absf(bg.scale.y - want_scale.y) > 0.001:
		bg.scale = want_scale
		dirty = true
	# Aspect must stay equirect 2:1 — non-uniform scale is a dual-map smell.
	if absf(bg.scale.x - bg.scale.y) > 0.02:
		bg.scale = Vector2(want_scale.x, want_scale.x)
		dirty = true
	if dirty and terrain_layer_stack and terrain_layer_stack.has_method("fit_to_bounds"):
		terrain_layer_stack.fit_to_bounds(want)


## Single canvas: WorldBackground (+ terrain) share ProvinceContainers transform.
## Camera2D alone pans/zooms — never scale only polys (causes dual map).
func _unify_map_canvas_transform() -> void:
	if container == null:
		container = get_node_or_null("ProvinceContainers") as Node2D
	if container == null:
		return
	# Hard-lock identity transform for GIS / all boards driven by MapCamera.
	if container.scale != Vector2.ONE or container.position != Vector2.ZERO:
		container.scale = Vector2.ONE
		container.position = Vector2.ZERO
		container.rotation = 0.0
	else:
		container.rotation = 0.0
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg == null:
		bg = get_node_or_null("WorldBackground") as Sprite2D
	if bg == null:
		return
	# Reparent underlay under poly container (local coords = province coords).
	if bg.get_parent() != container:
		if bg.get_parent():
			bg.get_parent().remove_child(bg)
		container.add_child(bg)
		container.move_child(bg, 0)
		print("MapRenderer: WorldBackground reparented under ProvinceContainers (unified canvas)")
	bg.z_index = -20
	bg.centered = false
	bg.rotation = 0.0
	# Terrain stack under same parent.
	if terrain_layer_stack != null and is_instance_valid(terrain_layer_stack):
		if terrain_layer_stack.get_parent() != container:
			if terrain_layer_stack.get_parent():
				terrain_layer_stack.get_parent().remove_child(terrain_layer_stack)
			container.add_child(terrain_layer_stack)
		terrain_layer_stack.z_index = -15


## Zoom out to show full content AABB (all continents).
func fit_camera_to_full_world() -> void:
	ensure_world_navigation_ready()
	var b := _current_theater_bounds
	if b.size.x <= 0.0:
		b = WORLD_CANONICAL_BOUNDS
	fit_camera_to_bounds(b, b.get_center(), 0.92)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Map: full world view · pan/zoom free across all land")


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
		# Still re-assert clean political (early return used to leave void-hex underlay visible).
		_ensure_ocean_floor()
		_apply_terrain_layer_visibility()
		_apply_clean_political_clear_color()
		return
	if bg:
		bg.texture = tex
		bg.centered = false
		# Keep texture for terrain-on mode; clean political must NOT force underlay visible
		# (void-hex ocean misalignment vs GIS coastlines).
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		bg.remove_meta("grand_fitted")
	set_meta("full_world_underlay_active", true)
	# Fit underlay + theater to live MapManager AABB when ready (GIS world_accurate).
	_sync_theater_bounds_to_map_data()
	_fit_background_to_bounds()
	_clamp_camera_to_theater()
	_apply_world_terrain_layers()
	_position_terrain_above_background()
	_suppress_old_background_maps()
	_ensure_ocean_floor()
	_apply_terrain_layer_visibility()
	_apply_clean_political_clear_color()
	print("MapRenderer: Loaded WORLD grand underlay (", path, ") + content-bounds fit. terrain=", show_terrain_layer)
	_refresh_province_fill_colors()
	_setup_coarse_world_territories(true)
	# Second fit after province render may expand AABB — deferred once MapManager has data.
	call_deferred("_sync_theater_bounds_to_map_data")
	call_deferred("_fit_background_to_bounds")
	call_deferred("_ensure_ocean_floor")
	call_deferred("_apply_terrain_layer_visibility")

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
	# GIS-aware Europe focus + full-world pan AABB (Europe/Asia reachable).
	ensure_world_navigation_ready()
	center_europe_in_world_view()
	if not provinces.is_empty():
		force_full_map_refresh()
	# After polys exist, re-expand theater to full MapManager AABB (load-order race).
	call_deferred("ensure_world_navigation_ready")
	_world_class_bootstrapped = true
	print("MapRenderer: bootstrap_world_class_map complete (world ultra + GIS Europe focus + full pan).")


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
## [param focus_camera]: only true on explicit user click / F10 focus — never on panel refresh.
## Auto-teleport on every refresh was thrashing the camera (Africa re-select on each data_changed) and hard-crashing while panning.
func _show_coarse_territory_info(terr_id: int, focus_camera: bool = false) -> void:
	if not _coarse_territories.has(terr_id) or info_panel == null:
		return
	var info: Dictionary = _coarse_territories[terr_id]
	var first_select := _selected_coarse_id != terr_id
	_selected_coarse_id = terr_id
	selected_province_id = -1  # clear detailed
	_layout_map_ui()
	info_panel.visible = true
	_layout_info_panel_inner()
	var dname := str(info.get("display_name", info.get("name", "Territory")))
	if info_name:
		info_name.text = dname
	if info_owner:
		info_owner.text = "World Overview Territory (coarse/strategic)"
	if info_population:
		info_population.text = "Type: Strategic Region (expandable)"
	if info_terrain:
		info_terrain.text = "Part of stitched world grand map. Toggle H for elevation/mountains."
	if info_factories:
		info_factories.text = "No detailed factories yet (Europe scenario focus)"
	if info_dev:
		info_dev.text = "Dev/Infra: N/A (use world layers or zoom to Europe for test)"
	if info_resources:
		info_resources.text = "Resources: See world_layer for overview"
	if info_core:
		info_core.text = "Core: None (future nations)"
	if info_special:
		info_special.text = "Special: " + str(info.get("desc", "Grand strategy scrollable territory."))
	if info_combat:
		info_combat.text = "Coarse territory — no combat data. Zoom into a detailed theater (e.g. Europe) or load a chunk for layers."
	if info_logistics:
		info_logistics.text = "Logistics: N/A for coarse strategic regions."
	if info_modifiers:
		info_modifiers.text = (
			"World map base active. Scroll and pan for the full grand-strategy view.\n"
			+ "Click Europe areas for detailed provinces. Other continents use this stitched "
			+ "world base until fine province data is available.\n"
			+ "Open National Spirits from a detailed province owned by a country."
		)
	if info_national:
		info_national.text = "Inspector: Coarse World Territory. F10 can focus the camera on this region."
	# Camera only on explicit focus (user click once). Re-shows must not re-teleport.
	if focus_camera and first_select:
		var cam := get_viewport().get_camera_2d() if get_viewport() else null
		if cam:
			var r: Rect2 = info.rect
			# Gentle nudge only — keep current zoom so pan/zoom state is not destroyed.
			cam.global_position = r.position + r.size * 0.5
			_clamp_camera_to_theater()
	if first_select or focus_camera:
		print("[COARSE TERRITORY] Clicked/entered: ", dname, " id=", terr_id)

## Center camera + "enter" a coarse territory (for F10 or future UI).
func debug_focus_coarse_territory(terr_name: String = "Africa") -> void:
	for tid in _coarse_territories:
		if str(_coarse_territories[tid].get("name", "")).to_lower() == terr_name.to_lower():
			_show_coarse_territory_info(tid, true)
			return
	print("No coarse terr named ", terr_name)

## Center camera on Europe within the full world canvas.
## world_accurate GIS: use live province centroids (GER/FRA capitals), not legacy Europe-theater rect
## (legacy BASE_EU_* was for old 471-prov overlay and mis-aimed the GIS board).
func center_europe_in_world_view() -> void:
	_sync_theater_bounds_to_map_data()
	set_meta("full_world_underlay_active", true)
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam:
		var focus := _resolve_europe_focus_center()
		var frame := _resolve_europe_focus_rect(focus)
		if fill_viewport_on_load:
			fit_camera_to_bounds(frame, focus, MapCanvasConfig.EUROPE_VIEW_FILL_RATIO)
		else:
			cam.global_position = _apply_camera_bounds(focus)
			cam.zoom = Vector2.ONE * (0.35 * MapCanvasConfig.THEATER_SCALE)
	_clamp_camera_to_theater()
	print("MapRenderer: centered on Europe (GIS-aware focus) inside world view")


## Sync pan theater + underlay for GIS boards (equirect underlay, full Asia pan).
func _sync_theater_bounds_to_map_data() -> void:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("is_geometry_world_native"):
		if bool(MapManager.is_geometry_world_native()):
			enable_map_wrap = false
	# Always re-fit underlay to equirect WORLD_CANONICAL for GIS (not centroid AABB).
	_fit_background_to_bounds()


func _resolve_europe_focus_center() -> Vector2:
	# Capitals known on world_accurate (scaled by MapManager centroids if available).
	var candidates: Array[int] = [710300, 710707, 711414, 710963]  # GER FRA ENG ITA
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
		for pid in candidates:
			var c: Vector2 = MapManager.get_province_centroid(pid)
			if c != Vector2.ZERO and c.length_squared() > 1.0:
				return c
	if province_centroids.has(710300):
		return province_centroids[710300] as Vector2
	# Fallback legacy Europe theater center (pre-GIS boards).
	return MapCanvasConfig.europe_world_center()


func _resolve_europe_focus_rect(center: Vector2) -> Rect2:
	# ~continental Europe framing around focus (GIS world canvas units, post-scale).
	var half := Vector2(2200.0, 1600.0) * 0.5
	var r := Rect2(center - half, half * 2.0)
	# Clamp into theater so fit_camera never frames outside the map.
	var b := _current_theater_bounds
	if b.size.x > 0.0:
		r = r.intersection(b)
		if r.size.x < 100.0 or r.size.y < 100.0:
			r = b
	return r


func _focus_asia_view() -> void:
	# JAP capital / East Asia sample on world_accurate
	var focus := Vector2.ZERO
	var candidates: Array[int] = [903995, 903986, 904007, 903534]  # JAP hubs + SOV sample
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
		for pid in candidates:
			var c: Vector2 = MapManager.get_province_centroid(pid)
			if c != Vector2.ZERO and c.length_squared() > 1.0:
				focus = c
				break
	if focus == Vector2.ZERO:
		# East side of content bounds
		var b := _current_theater_bounds
		focus = Vector2(b.position.x + b.size.x * 0.78, b.position.y + b.size.y * 0.42)
	var half := Vector2(2800.0, 2000.0) * 0.5
	var frame := Rect2(focus - half, half * 2.0)
	if _current_theater_bounds.size.x > 0.0:
		frame = frame.intersection(_current_theater_bounds)
		if frame.size.x < 100.0:
			frame = _current_theater_bounds
	fit_camera_to_bounds(frame, focus, 0.9)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Map: Asia focus · Home=Europe · Shift+Home=full world")

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

	# Re-seed WM only on small boards — full world_full pass freezes pan after chunk swap.
	var _chunk_board_n := provinces.size()
	if _chunk_board_n < 800 and typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("initialize_province"):
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


## Land draw order: Europe NUTS on top of RoW sparse megablobs (prevents SOV red covering FIN/Baltics).
func _province_draw_z_index(pid: int, is_water: bool) -> int:
	if is_water or pid >= 950000:
		return 0
	if pid >= 710000 and pid < 800000:
		return 4  # Europe NUTS — densest theater
	if pid >= 800000 and pid < 900000:
		return 3  # US playable
	if pid >= 900000 and pid < 950000:
		return 1  # RoW sparse (may be oversized)
	return 2


func _create_province_node(province: Province, geo: Dictionary) -> Node2D:
	var node := Node2D.new()
	node.name = "Prov_%d" % province.id

	var points: PackedVector2Array = ProvincePolygonUtil.from_variant_points(geo.get("points", []))
	if points.size() < 3:
		return node

	# Scale to tactical canvas (+44% global) + island inflation; optionally remap onto world underlay.
	var _wn := false
	if MapManager != null and MapManager.has_method("is_geometry_world_native"):
		_wn = MapManager.is_geometry_world_native()
	points = MapCanvasConfig.transform_province_points(points, _is_world_canvas_active(), true, _wn)
	# Sanitize at create time so every clickable province is drawable / collidable (world_full).
	points = ProvincePolygonUtil.make_drawable(points)
	if points.size() < 3:
		return node

	var poly := Polygon2D.new()
	points = ProvincePolygonUtil.assign_polygon2d(poly, points)
	poly.color = _get_province_color(province)
	poly.antialiased = true

	# Area2D is now completely optional.
	# In the recommended production pure-spatial configuration (use_spatial_picking=true AND
	# create_area_nodes_for_fallback=false), no Area2D nodes are ever created.
	if create_area_nodes_for_fallback or not use_spatial_picking:
		var area := Area2D.new()
		var collision := CollisionPolygon2D.new()
		ProvincePolygonUtil.assign_collision_polygon(collision, points)
		if collision.polygon.size() >= 3:
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

	# Land above sea; Europe NUTS above RoW sparse megablobs (SOV red no longer covers FIN/Baltics).
	var is_water := bool(province.is_sea) or int(province.id) >= 950000
	node.z_index = _province_draw_z_index(int(province.id), is_water)
	if province.has_feature("capital"):
		_add_capital_star_to_node(node, province.id)

	var icon_dirs := _feature_icon_offsets_radial(_count_special_icons(province), feature_icon_ring_radius)
	var icon_i := 0
	for feature in province.special_features.keys():
		var fk := str(feature)
		if fk == "capital" or icon_i >= icon_dirs.size():
			continue
		var offs: Vector2 = icon_dirs[icon_i]
		# Pass 9–13: fort/port/airfield use retrowave Sprite2D chips; other features keep emoji Labels.
		var feat_lv := 0
		if province.special_features.has(feature):
			feat_lv = int(province.special_features[feature])
		var feat_damaged := _province_feature_is_damaged(province, fk)
		var tex_path := _special_feature_sprite_path(fk, feat_lv, feat_damaged)
		if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
			var spr := Sprite2D.new()
			spr.texture = load(tex_path) as Texture2D
			spr.centered = true
			spr.z_index = ProvinceMapVisuals.Z_MAP_GLYPH
			# ~16px on-map footprint (source is 32px); hangar/heavy/major slightly larger.
			var base_px := 16.0
			if "hangar" in tex_path or "heavy" in tex_path or "major" in tex_path:
				base_px = 18.0
			elif "strip" in tex_path or "bunker" in tex_path or "jetty" in tex_path:
				base_px = 14.0
			if feat_damaged:
				spr.modulate = Color(1.0, 0.82, 0.75, 1.0)

			if spr.texture != null:
				var tw := float(spr.texture.get_width())
				if tw > 1.0:
					spr.scale = Vector2.ONE * (base_px / tw)
			spr.position = center + offs
			spr.set_meta(META_MAP_GLYPH_OFFS, offs)
			spr.set_meta(&"_map_feature_sprite", true)
			spr.set_meta(&"_map_feature_key", fk)
			spr.set_meta(&"_map_feature_level", feat_lv)
			node.add_child(spr)
			# Pass 16/17: airfield repair / construction progress ring (live-refreshed on day tick).
			if _feature_key_is_airfield(fk):
				var ring_p := _airfield_progress_for_province(province, feat_damaged)
				if ring_p >= 0.0:
					_attach_feature_progress_ring(node, center + offs, ring_p, feat_damaged, province.id)
		else:
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
	var clean := _wants_clean_political_fills()
	var c := _characterize_province_fill(base, province, _overlay_base_character_blend())
	# Clean political (default): solid land ownership + continuous sea (no underlay bleed / void hex).
	if clean:
		if province != null and province.is_sea:
			c = continuous_sea_fill_color(base, sea_political_trace)
			c.a = 1.0
		else:
			c.a = 0.96
		return c
	if is_using_grand_stylized_map() or (not show_terrain_layer):
		if show_terrain_layer:
			# Terrain raster underlay: thin fills so art shows (Europe-theater style).
			c.a = 0.06 if (is_using_grand_stylized_map() and not is_using_world_grand_map()) else 0.72
		else:
			c.a = 0.92
	return c


## Default / political readability stack: solid fills, no photo underlay double-layer.
func _wants_clean_political_fills() -> bool:
	if show_terrain_layer:
		return false
	var m := str(current_map_mode).strip_edges().to_lower()
	if m.is_empty() or m == "political":
		return true
	# Mapmodes that still want solid ownership under tints
	if m in ["strain", "vitality", "development", "loyalty", "infra"]:
		return true
	return false


## Continuous ocean fill (hides void-hex underlay + coarse sea tile seams). Pure-test aligned.
## `zone_hue_shift` 0..1 adds slight per-zone variance so sea zones remain continuous but readable.
static func continuous_sea_fill_color(base: Color = Color(0.16, 0.33, 0.47, 0.88), political_trace: float = 0.08, zone_hue_shift: float = 0.0) -> Color:
	var deep := Color(0.05, 0.14, 0.28, 1.0)
	var mix := clampf(political_trace * 0.28, 0.0, 0.4)
	var col := deep.lerp(base, mix)
	col = col.lerp(deep, 0.62)
	# Subtle zone separation (HOI naval zones): keep blue family, tiny hue/value drift.
	if zone_hue_shift > 0.001:
		var h := col.h
		var s := col.s
		var v := col.v
		h = fposmod(h + (zone_hue_shift - 0.5) * 0.04, 1.0)
		s = clampf(s + (zone_hue_shift - 0.5) * 0.06, 0.28, 0.72)
		v = clampf(v + (zone_hue_shift - 0.5) * 0.05, 0.12, 0.42)
		col = Color.from_hsv(h, s, v, 1.0)
	col.a = 1.0
	return col


## Stable 0..1 hash from sea zone / theater name for continuous_sea_fill zone tint.
static func sea_zone_hue_shift(zone_name: String) -> float:
	var z := zone_name.strip_edges().to_lower()
	if z.is_empty():
		return 0.5
	return float(absi(z.hash()) % 1000) / 1000.0


## Viewport clear + ocean floor plate so uncovered canvas is continuous deep water (not grey/void hex).
func _apply_clean_political_clear_color() -> void:
	var deep := continuous_sea_fill_color()
	var vp := get_viewport()
	if vp:
		# Godot 4: SubViewport / root clear via environment or clear_color when available.
		if vp is SubViewport:
			(vp as SubViewport).render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		# Project clear color is global; set only when clean political is active.
		if not show_terrain_layer:
			RenderingServer.set_default_clear_color(Color(deep.r, deep.g, deep.b, 1.0))
		else:
			RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.11, 1.0))


## Opaque continuous ocean under all provinces (z below WorldBackground). Closes poly gaps.
func _ensure_ocean_floor() -> void:
	if container == null:
		container = get_node_or_null("ProvinceContainers") as Node2D
	if container == null:
		return
	var b := _current_theater_bounds
	if b.size.x <= 1.0 or b.size.y <= 1.0:
		b = WORLD_CANONICAL_BOUNDS
	# Pad so pan edges never show clear-color seams.
	var pad := maxf(b.size.x, b.size.y) * 0.08
	var rect := b.grow(pad)
	var pts := PackedVector2Array([
		rect.position,
		Vector2(rect.position.x + rect.size.x, rect.position.y),
		rect.position + rect.size,
		Vector2(rect.position.x, rect.position.y + rect.size.y),
	])
	var col := continuous_sea_fill_color()
	col.a = 1.0
	if _ocean_floor == null or not is_instance_valid(_ocean_floor):
		_ocean_floor = Polygon2D.new()
		_ocean_floor.name = "OceanFloorContinuous"
		_ocean_floor.z_index = -30
		_ocean_floor.z_as_relative = false
		container.add_child(_ocean_floor)
		container.move_child(_ocean_floor, 0)
	if _ocean_floor.get_parent() != container:
		if _ocean_floor.get_parent():
			_ocean_floor.get_parent().remove_child(_ocean_floor)
		container.add_child(_ocean_floor)
		container.move_child(_ocean_floor, 0)
	_ocean_floor.polygon = pts
	_ocean_floor.color = col
	_ocean_floor.visible = true
	# Keep under WorldBackground when both exist
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if bg and bg.get_parent() == container:
		var bi := bg.get_index()
		if _ocean_floor.get_index() > bi:
			container.move_child(_ocean_floor, 0)


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


## M1: HOI resources mapmode color from Province.resources (mirrors map_resources_mapmode_product.py).
static func resources_mapmode_color_from_dict(resources: Dictionary, is_sea: bool = false, base: Color = Color(0.5, 0.5, 0.55)) -> Color:
	if is_sea:
		return Color(0.08, 0.14, 0.28, 1.0)
	var weights := {
		"oil": 3.0, "rubber": 2.5, "chromium": 2.0, "tungsten": 2.0,
		"aluminum": 1.8, "steel": 1.4, "coal": 1.0, "iron": 1.2,
	}
	var hues := {
		"oil": Color(0.12, 0.55, 0.28),
		"rubber": Color(0.45, 0.72, 0.22),
		"chromium": Color(0.55, 0.35, 0.85),
		"tungsten": Color(0.75, 0.55, 0.20),
		"aluminum": Color(0.70, 0.78, 0.90),
		"steel": Color(0.45, 0.50, 0.58),
		"coal": Color(0.22, 0.20, 0.18),
		"iron": Color(0.55, 0.32, 0.28),
	}
	var best_key := ""
	var best_score := 0.0
	var best_amt := 0.0
	for k in resources.keys():
		var key := str(k).strip_edges().to_lower()
		var amt := float(resources[k]) if typeof(resources[k]) in [TYPE_FLOAT, TYPE_INT] else 0.0
		if amt <= 0.0:
			continue
		var w := float(weights.get(key, 0.5))
		var sc := amt * w
		if sc > best_score:
			best_score = sc
			best_key = key
			best_amt = amt
	if best_key.is_empty():
		# Visible muted land (not near-black) so F9 never "deletes" the political map.
		return base.lerp(Color(0.32, 0.34, 0.38, 1.0), 0.55)
	var hue: Color = hues.get(best_key, Color(0.5, 0.5, 0.45))
	# Stronger saturation so resource provinces pop vs empty land.
	var intensity := clampf(0.55 + 0.18 * best_amt, 0.55, 1.0)
	var col := Color(hue.r * intensity, hue.g * intensity, hue.b * intensity, 1.0)
	# Light political blend keeps owner identity without washing out the good tint.
	return col.lerp(base, 0.12)


func _resources_mapmode_color_for_province(province: Province, base: Color) -> Color:
	if province == null:
		return Color(0.18, 0.20, 0.24, 1.0)
	if bool(province.is_sea):
		return resources_mapmode_color_from_dict({}, true, base)
	var res: Dictionary = {}
	if "resources" in province and province.resources is Dictionary:
		res = province.resources
	return resources_mapmode_color_from_dict(res, false, base)


## M2: V3-style state fills from state_id (mirrors map_states_mapmode_product.states_mapmode_rgb).
static func states_mapmode_color_from_id(state_id: int, is_sea: bool = false, base: Color = Color(0.5, 0.5, 0.55)) -> Color:
	if is_sea:
		return Color(0.08, 0.14, 0.28, 1.0)
	var sid := int(state_id)
	if sid <= 0:
		# Unassigned land: keep readable political grey (not black "missing province").
		return base.lerp(Color(0.28, 0.30, 0.34, 1.0), 0.4)
	const GOLDEN := 0.618033988749895
	var h := fmod(float(sid) * GOLDEN, 1.0)
	if h < 0.0:
		h += 1.0
	var s := 0.48 + 0.22 * float((sid * 7) % 5) / 4.0
	var v := 0.58 + 0.22 * float((sid * 3) % 4) / 3.0
	var col := Color.from_hsv(h, s, v, 1.0)
	# Light political blend for owner readability
	return col.lerp(base, 0.12)


## M3: clean terrain mapmode palette (mirrors map_states_mapmode_product.terrain_mapmode_rgb).
static func terrain_mapmode_color_from_key(terrain: String, is_sea: bool = false) -> Color:
	if is_sea:
		return Color(0.08, 0.14, 0.28, 1.0)
	var key := str(terrain).strip_edges().to_lower()
	match key:
		"plains", "grassland":
			return Color(0.55, 0.68, 0.38, 1.0)
		"forest":
			return Color(0.18, 0.42, 0.22, 1.0)
		"woods":
			return Color(0.22, 0.48, 0.26, 1.0)
		"jungle":
			return Color(0.12, 0.38, 0.20, 1.0)
		"mountains":
			return Color(0.48, 0.45, 0.42, 1.0)
		"hills":
			return Color(0.52, 0.50, 0.36, 1.0)
		"desert":
			return Color(0.78, 0.68, 0.42, 1.0)
		"tundra":
			return Color(0.62, 0.68, 0.70, 1.0)
		"marsh":
			return Color(0.32, 0.42, 0.30, 1.0)
		"urban":
			return Color(0.45, 0.45, 0.48, 1.0)
		"sea", "ocean", "water":
			return Color(0.08, 0.14, 0.28, 1.0)
		"lake":
			return Color(0.15, 0.28, 0.40, 1.0)
		_:
			return Color(0.50, 0.52, 0.40, 1.0)


func _resolve_province_state_id(province_id: int) -> int:
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_hierarchy_for_province_live"):
		var h: Dictionary = GameData.get_hierarchy_for_province_live(province_id)
		var sid := int(h.get("state_id", 0))
		if sid > 0:
			return sid
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_state_id"):
		return int(MapManager.get_province_state_id(province_id))
	var tree := get_tree()
	if tree != null:
		var loader: Node = tree.root.find_child("ScenarioLoader", true, false)
		if loader != null and loader.has_method("get_province_state_id"):
			return int(loader.get_province_state_id(province_id))
	var loader_root = get_node_or_null("/root/ScenarioLoader")
	if loader_root != null and loader_root.has_method("get_province_state_id"):
		return int(loader_root.get_province_state_id(province_id))
	return 0


func _states_mapmode_color_for_province(province: Province, base: Color) -> Color:
	if province == null:
		return Color(0.16, 0.17, 0.20, 1.0)
	if bool(province.is_sea):
		return states_mapmode_color_from_id(0, true, base)
	var sid := _resolve_province_state_id(int(province.id))
	return states_mapmode_color_from_id(sid, false, base)


func _terrain_mapmode_color_for_province(province: Province) -> Color:
	if province == null:
		return Color(0.50, 0.52, 0.40, 1.0)
	if bool(province.is_sea):
		return terrain_mapmode_color_from_key("ocean", true)
	return terrain_mapmode_color_from_key(str(province.terrain), false)


## Terrain + development hues sit on top of political color; overlays tint afterward.
## `character_blend` pulls toward raw political fills when < 1 (used under Supply / heavy tinting).
func _characterize_province_fill(base: Color, province: Province, character_blend: float = 1.0) -> Color:
	var cb := clampf(character_blend, 0.2, 1.0)
	if province.is_sea:
		# Always continuous ocean — never show underlay hex tiles through sea polys.
		var sea_col := _shade_sea_province_fill(base, province)
		return sea_col
	var clean := _wants_clean_political_fills()
	var mul := _terrain_palette_multipliers(province.terrain)
	# Clean political: pure ownership hues (no terrain mul / pack tint muddy stack).
	if clean:
		mul = Vector3(1.0, 1.0, 1.0)
	var toned := Color(
		clampf(base.r * mul.x, 0.02, 1.0),
		clampf(base.g * mul.y, 0.02, 1.0),
		clampf(base.b * mul.z, 0.02, 1.0),
		base.a,
	)
	# Pack seamless-tile palette — skip when clean political (muddy double-stack).
	if not clean:
		var pack_tint: Color = _TerrainTiles.terrain_tint_for_key(str(province.terrain))
		toned = toned.lerp(pack_tint, 0.18)
		# Pass 3: soft plains↔hills transition when a neighbor is the other class (live use of transition pack).
		var edge_mix := _terrain_transition_edge_mix(province)
		if edge_mix > 0.001:
			var edge_tint: Color = _TerrainTiles.terrain_tint_for_key("plains").lerp(
				_TerrainTiles.terrain_tint_for_key("hills"), 0.5
			)
			toned = toned.lerp(edge_tint, clampf(edge_mix * 0.35, 0.0, 0.28))
	# Clean political: keep pure ownership; no terrain characterization lerp.
	var k := 0.0 if clean else (_terrain_tone_strength_for_current_zoom() * cb)
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

	# Pass 22: primary mapmode intensity scales tint strength for linked modes.
	var pi := 1.0
	if debug_tint_mode in INTENSITY_LINKED_MODES:
		pi = clampf(float(primary_mapmode_intensity.get(debug_tint_mode, secondary_tint_intensity.get(debug_tint_mode, 1.0))), 0.25, 2.0)
	var pcb := cb * pi

	# Dedicated mapmodes must read at a glance (F2/F3/F4). Prior versions only tinted when
	# welfare/settlement data was non-zero — most start provinces looked identical to political.
	if debug_tint_mode == "strain":
		# Full-mode red/gray stress scale. Welfare burden amplifies when present.
		var wnorm := 0.0
		if typeof(GameData) != TYPE_NIL:
			var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			var wbur := float(ps.get("welfare_burden", {}).get(province.owner_tag if province.owner_tag else "player", 0.0))
			if wbur > 0.0:
				wnorm = clampf(wbur / 55.0, 0.0, 1.0)
		# Proxy strain from low development / high infra gap so empty boards still show a gradient.
		var dev_s := clampf(float(clampi(province.development_level, 0, 50)) / 12.0, 0.0, 1.0)
		var proxy := clampf(1.0 - dev_s, 0.0, 1.0) * 0.45
		var sn := clampf(maxf(wnorm, proxy), 0.08, 1.0)
		var strain_col := Color(0.72, 0.22, 0.28, 1.0).lerp(Color(0.42, 0.40, 0.42, 1.0), 1.0 - sn)
		if province.is_sea:
			col = col.lerp(Color(0.12, 0.14, 0.20, 1.0), 0.55 * cb)
		else:
			col = col.lerp(strain_col, clampf(0.72 * sn * pcb, 0.35, 0.88))
	elif debug_tint_mode == "vitality":
		# F3: cool teal→lime by settlement + population (living land / people density).
		var s := clampf(float(province.settlement_level), 0.0, 1.5)
		var pop_proxy := 0.0
		if "population" in province:
			pop_proxy = clampf(float(province.population) / 1_800_000.0, 0.0, 1.0)
		# Factories/cities as vitality signal when settlement unset.
		var fac_proxy := clampf(float(province.factories) / 6.0, 0.0, 0.55)
		var vn := clampf(maxf(s / 1.1, maxf(pop_proxy * 0.85, fac_proxy)), 0.0, 1.0)
		if vn < 0.06:
			vn = 0.10
		# Deep teal (sparse) → bright lime (dense/settled) — strong separation from F1 political.
		var vit_col := Color(0.10, 0.28, 0.32, 1.0).lerp(Color(0.55, 0.98, 0.55, 1.0), vn)
		if province.is_sea:
			col = col.lerp(Color(0.06, 0.14, 0.26, 1.0), 0.70 * cb)
		else:
			col = col.lerp(vit_col, clampf(0.88 * pcb, 0.55, 0.95))
	elif debug_tint_mode == "development":
		# F4: warm brown→gold by development_level (+ factories boost). Hubs pop as cream.
		var dev_n2 := clampf(float(clampi(province.development_level, 0, 50)) / 10.0, 0.0, 1.0)
		dev_n2 = sqrt(dev_n2)
		var fac_boost := clampf(float(province.factories) / 8.0, 0.0, 0.35)
		dev_n2 = clampf(dev_n2 + fac_boost, 0.0, 1.0)
		if dev_n2 < 0.08:
			dev_n2 = 0.12
		# Sparse = muted brown-olive; rich hubs = bright gold/cream.
		var dev_col := Color(0.38, 0.34, 0.28, 1.0).lerp(Color(1.0, 0.94, 0.55, 1.0), dev_n2)
		if province.is_sea:
			col = col.lerp(Color(0.06, 0.12, 0.24, 1.0), 0.70 * cb)
		else:
			col = col.lerp(dev_col, clampf(0.86 * pcb, 0.50, 0.94))
			col = col.lightened(clampf(dev_n2 * 0.14 * pcb, 0.0, 0.20))
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
				col = col.lerp(Color(0.98, 0.90, 0.72, 1.0), clampf(lnorm * 0.16 * pcb, 0.0, 0.18))
	elif debug_tint_mode == "resources":
		# M1 HOI resources mapmode: tint from province.resources (oil/rubber/steel/coal…).
		# Pure rules mirrored in tools/map_generation/lib/map_resources_mapmode_product.py
		var res_col := _resources_mapmode_color_for_province(province, base)
		col = col.lerp(res_col, clampf(0.82 * cb, 0.55, 0.92))
	elif debug_tint_mode == "states":
		# M2 V3-style state fills from hierarchy membership (ScenarioLoader.province_state_by_id).
		# Pure rules mirrored in tools/map_generation/lib/map_states_mapmode_product.py
		var st_col := _states_mapmode_color_for_province(province, base)
		col = col.lerp(st_col, clampf(0.88 * cb, 0.65, 0.95))
	elif debug_tint_mode == "terrain":
		# M3 clean terrain mapmode (plains/forest/mountains/desert…) without killing other modes.
		# Pure rules mirrored in tools/map_generation/lib/map_states_mapmode_product.py terrain_mapmode_rgb
		var terr_col := _terrain_mapmode_color_for_province(province)
		col = col.lerp(terr_col, clampf(0.90 * cb, 0.70, 0.96))
	elif debug_tint_mode == "munitions":
		# Pass 22: per-depot munitions stockpile heatmap (full = cyan-blue, empty = red, no depot = dim).
		var mun_r := -1.0
		if typeof(SupplyManager) != TYPE_NIL:
			if SupplyManager.has_method("get_depot_munitions_ratio"):
				mun_r = float(SupplyManager.get_depot_munitions_ratio(province.id))
			elif "depot_states" in SupplyManager:
				var dep = SupplyManager.depot_states.get(province.id)
				if dep != null and dep.has_method("munitions_ratio"):
					mun_r = float(dep.munitions_ratio())
		var own := str(province.owner_tag).to_upper() if "owner_tag" in province else ""
		var ctrl := str(province.controller_tag).to_upper() if "controller_tag" in province else ""
		var is_occ := not ctrl.is_empty() and not own.is_empty() and ctrl != own
		var player_tag := ""
		if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
			player_tag = str(LeaderManager.get_player_country_tag()).to_upper()
		var effective_ctrl := ctrl if not ctrl.is_empty() else own
		# Pass 27: occupation / mine filter dims non-matching provinces.
		var ofilt := munitions_occupation_filter
		var dim_out := false
		if ofilt == "occupied" and not is_occ:
			dim_out = true
		elif ofilt == "mine" and not player_tag.is_empty() and effective_ctrl != player_tag:
			dim_out = true
		if dim_out:
			col = col.lerp(Color(0.12, 0.13, 0.16, 1.0), clampf(0.45 * pcb, 0.2, 0.6))
		elif mun_r < 0.0:
			# No depot: slight cool desat so depots still pop.
			col = col.lerp(Color(0.22, 0.24, 0.30, 1.0), clampf(0.22 * pcb, 0.08, 0.32))
		else:
			var mr := clampf(mun_r, 0.0, 1.0)
			var heat := Color(0.92, 0.32, 0.28, 1.0).lerp(Color(0.35, 0.78, 1.0, 1.0), mr)
			col = col.lerp(heat, clampf(0.42 * pcb, 0.18, 0.62))
			if mr < 0.25:
				col = col.lerp(Color(0.95, 0.25, 0.22, 1.0), clampf((0.25 - mr) * 0.55 * pcb, 0.0, 0.22))
		# Pass 26: occupation munitions tint — controller ≠ owner (amber occupation cast).
		if is_occ and not dim_out:
			var occ_amt := clampf(0.16 * pcb, 0.06, 0.28)
			col = col.lerp(Color(0.95, 0.72, 0.28, 1.0), occ_amt)
			# Slight desat so occupation reads over fill heat.
			col = col.lerp(Color(col.r, col.g * 0.92, col.b * 0.85, 1.0), 0.25 * pcb)
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
	elif debug_tint_mode == "naval":
		# Naval mapmode: sea-zone theater tints + bright chokepoints + coastal land rim.
		var is_water := province.is_sea or str(province.domain).to_lower() in ["sea", "strait", "lake"]
		var is_choke := false
		if typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
			is_choke = bool(MapManager.has_strategic_chokepoint(province.id))
		if is_choke:
			col = col.lerp(Color(0.22, 0.78, 1.0, 1.0), clampf(0.48 * cb, 0.28, 0.62))
			col = col.lightened(clampf(0.10 * cb, 0.0, 0.14))
		elif is_water and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_sea_zone_name"):
			var zname := str(MapManager.get_sea_zone_name(province.id)).strip_edges()
			if not zname.is_empty():
				var zcol := _sea_zone_theater_color(zname)
				col = col.lerp(zcol, clampf(0.38 * cb, 0.2, 0.48))
			else:
				col = col.lerp(Color(0.06, 0.14, 0.26, 1.0), clampf(0.28 * cb, 0.14, 0.36))
		elif is_water:
			col = col.lerp(Color(0.08, 0.16, 0.28, 1.0), clampf(0.22 * cb, 0.1, 0.3))
		elif _province_is_coastal_land(province):
			col = col.lerp(Color(0.35, 0.72, 0.78, 1.0), clampf(0.12 * cb, 0.05, 0.16))
	elif debug_tint_mode == "weather":
		# Pass 10: province fill tint from live WeatherManager ground_state / storm precip.
		col = _apply_weather_mapmode_tint(col, province, cb)
	# Always-on subtle chokepoint trace in political mode so straits stay readable without mapmode toggle.
	elif debug_tint_mode == "" and typeof(MapManager) != TYPE_NIL and MapManager.has_method("has_strategic_chokepoint"):
		if MapManager.has_strategic_chokepoint(province.id):
			col = col.lerp(Color(0.35, 0.78, 0.98, 1.0), clampf(0.12 * cb, 0.05, 0.16))

	# Pass 16/17: secondary stacked tints (multi).
	var secs: Array = debug_tint_mode_secondaries
	if secs.is_empty() and debug_tint_mode_secondary != "":
		secs = [debug_tint_mode_secondary]
	for sec_v in secs:
		var sec := str(sec_v).strip_edges().to_lower()
		if sec.is_empty() or sec == debug_tint_mode:
			continue
		col = _apply_secondary_debug_tint(col, province, cb, sec)

	# Always-on damage/sabotage visual from live province/site/agent state (not demo pids).
	col = _apply_map_damage_visual_tint(col, province, cb)
	# Hidden Hand monthly map signal highlight (province targeted this month).
	col = _apply_hh_map_signal_tint(col, province, cb)
	return col


## Soft secondary mapmode tint for stacked presets (does not replace primary).
## Pass 20: intensity scales blend strength via secondary_tint_intensity.
func _apply_secondary_debug_tint(col: Color, province: Province, cb: float, mode: String) -> Color:
	var m := mode.strip_edges().to_lower()
	var intensity := clampf(float(secondary_tint_intensity.get(m, 1.0)), 0.25, 2.0)
	var icb := cb * intensity
	if m == "strain":
		if typeof(GameData) != TYPE_NIL:
			var ps: Dictionary = GameData.get_peace_state() if GameData.has_method("get_peace_state") else {}
			var wbur := float(ps.get("welfare_burden", {}).get(province.owner_tag if province.owner_tag else "player", 0.0))
			if wbur > 5.0:
				var wnorm := clampf((wbur - 5.0) / 50.0, 0.0, 1.0)
				col = col.lerp(Color(0.95, 0.75, 0.78, 1.0), 0.12 * wnorm * icb)
	elif m == "vitality" and province.settlement_level > 0.01:
		var s := clampf(province.settlement_level, 0.0, 1.5)
		col = col.lerp(Color(0.82, 1.08, 0.92, 1.0), clampf(s * 0.06 * icb, 0.0, 0.28))
	elif m == "development":
		var dev_n2 := clampf(float(clampi(province.development_level, 0, 50)) / 9.0, 0.0, 1.0)
		dev_n2 = sqrt(dev_n2)
		if dev_n2 > 0.05:
			col = col.lightened(clampf(dev_n2 * 0.08 * icb, 0.0, 0.24))
	elif m == "loyalty":
		if typeof(GameData) != TYPE_NIL and GameData.has_method("get_military_loyalty_multiplier"):
			var loy: float = GameData.get_military_loyalty_multiplier(province.owner_tag if province.owner_tag else "player")
			if loy < 0.92:
				col = col.lerp(Color(0.98, 0.90, 0.72, 1.0), clampf((0.92 - loy) * 0.12 * icb, 0.0, 0.24))
	return col


## Pass 10/13: weather mapmode fill colors (dry / mud / snow / storm). Optional filter dim.
func set_weather_ground_filter(key: String) -> void:
	var k := key.strip_edges().to_lower()
	if k in ["dry", "mud", "snow", "storm"]:
		# Toggle off if same key clicked again.
		if weather_ground_filter == k:
			weather_ground_filter = ""
		else:
			weather_ground_filter = k
	else:
		weather_ground_filter = ""
	if current_map_mode == "weather" or debug_tint_mode == "weather":
		_refresh_province_fill_colors(true)
	# Pass 14: keep particle field in sync with legend filter.
	_sync_weather_particle_filter()
	# Pass 15: minimap weather dots respect filter.
	if _map_minimap != null and is_instance_valid(_map_minimap):
		if _map_minimap.has_method("invalidate_weather_cache"):
			_map_minimap.call("invalidate_weather_cache")
		if _map_minimap.has_method("set_show_weather_dots") and (current_map_mode == "weather" or debug_tint_mode == "weather"):
			# Rebuild with new filter.
			_map_minimap.call("set_show_weather_dots", false)
			_map_minimap.call("set_show_weather_dots", true)


func _sync_weather_particle_filter() -> void:
	_setup_weather_overlay_layer()
	if weather_layer == null:
		return
	if "map_renderer" in weather_layer:
		weather_layer.map_renderer = self
	if weather_layer.has_method("set_particle_ground_filter"):
		weather_layer.call("set_particle_ground_filter", weather_ground_filter)


func _apply_weather_mapmode_tint(col: Color, province: Province, cb: float = 1.0) -> Color:
	if province == null:
		return col
	var ground := "dry"
	var precip := 0.0
	if typeof(WeatherManager) != TYPE_NIL and WeatherManager.has_method("get_province_weather"):
		var w: Variant = WeatherManager.call("get_province_weather", province.id)
		if w is Dictionary:
			ground = str(w.get("ground_state", "dry")).to_lower()
			precip = float(w.get("precip_intensity", 0.0))
	var key := ground
	if precip >= 0.55:
		key = "storm"
	elif "snow" in ground or ground in ["frozen", "ice"]:
		key = "snow"
	elif "mud" in ground or ground in ["wet", "muddy"]:
		key = "mud"
	elif key not in ["dry", "mud", "snow", "storm"]:
		key = "dry"
	# Pass 13: legend click filter — non-matching provinces desaturate / dim.
	var filt := weather_ground_filter.strip_edges().to_lower()
	if not filt.is_empty() and key != filt:
		var dim := col.darkened(0.22)
		dim = dim.lerp(Color(0.12, 0.14, 0.18, 1.0), 0.35)
		return col.lerp(dim, clampf(0.55 * cb, 0.25, 0.7))
	var tint := Color(0.92, 0.88, 0.72, 1.0)  # dry — warm sand
	var strength := 0.22
	match key:
		"mud":
			tint = Color(0.42, 0.32, 0.22, 1.0)
			strength = 0.32
		"snow":
			tint = Color(0.78, 0.88, 0.98, 1.0)
			strength = 0.36
		"storm":
			tint = Color(0.28, 0.22, 0.48, 1.0)
			strength = 0.40
		_:
			tint = Color(0.92, 0.88, 0.72, 1.0)
			strength = 0.18
	# Filtered match: boost strength so the selected state pops.
	if not filt.is_empty() and key == filt:
		strength = minf(0.55, strength * 1.35)
	if province.is_sea or str(province.domain).to_lower() in ["sea", "strait", "lake"]:
		# Sea: storm = purple-gray chop; else cooler blue bias.
		if key == "storm":
			tint = Color(0.18, 0.16, 0.32, 1.0)
			strength = 0.42
		else:
			tint = Color(0.12, 0.28, 0.42, 1.0)
			strength = 0.20
	return col.lerp(tint, clampf(strength * cb, 0.08, 0.48))


func _apply_map_damage_visual_tint(col: Color, province: Province, cb: float = 1.0) -> Color:
	if province == null:
		return col
	var dmg: Dictionary = ProvinceInsight.classify_province_map_damage(province)
	if not bool(dmg.get("is_damaged", false)):
		return col
	var strength := clampf(float(dmg.get("strength", 0.0)) * cb, 0.0, 0.7)
	var key := str(dmg.get("tint_key", ""))
	match key:
		"infra_sabotage", "project_sabotage":
			col = col.lerp(ProvinceMapVisuals.FILL_INFRA_SABOTAGE_ACTIVE, strength)
		"depot_sabotage", "supply_pressure":
			col = col.lerp(ProvinceMapVisuals.FILL_AGENT_DISRUPT_BASE, strength)
		"site_damage":
			col = col.lerp(Color(1.0, 0.42, 0.28, 1.0), strength)
		_:
			col = col.lerp(ProvinceMapVisuals.FILL_AGENT_SABOTAGE_BASE, strength * 0.8)
	return col


func _apply_hh_map_signal_tint(col: Color, province: Province, cb: float = 1.0) -> Color:
	if province == null or typeof(GameData) == TYPE_NIL or not GameData.has_method("get_peace_state"):
		return col
	var ps: Dictionary = GameData.get_peace_state()
	var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
	if sig.is_empty() or not bool(sig.get("active", false)):
		return col
	if int(sig.get("province_id", -1)) != province.id:
		return col
	var strength := clampf(float(sig.get("strength", 0.25)) * cb, 0.08, 0.55)
	var key := str(sig.get("tint_key", "hh_influence"))
	if key == "infra_sabotage":
		col = col.lerp(ProvinceMapVisuals.FILL_INFRA_SABOTAGE_ACTIVE, strength)
	elif key == "supply_pressure":
		col = col.lerp(Color(1.0, 0.55, 0.18, 1.0), strength)
	elif key == "loyalty_strain":
		# Amber institutional strain for infiltration (third HH map class)
		col = col.lerp(Color(0.95, 0.72, 0.28, 1.0), strength)
	else:
		# Violet hand-influence tint (distinct from agent purple)
		col = col.lerp(Color(0.62, 0.35, 0.92, 1.0), strength)
	# Also tint secondary concurrent HH pulse when present.
	var sig2: Dictionary = ps.get("hh_secondary_map_signal", {}) if ps is Dictionary else {}
	if bool(sig2.get("active", false)) and int(sig2.get("province_id", -1)) == province.id:
		var s2 := clampf(float(sig2.get("strength", 0.2)) * cb, 0.06, 0.45)
		var k2 := str(sig2.get("tint_key", "hh_influence"))
		if k2 == "infra_sabotage":
			col = col.lerp(ProvinceMapVisuals.FILL_INFRA_SABOTAGE_ACTIVE, s2)
		elif k2 == "supply_pressure":
			col = col.lerp(Color(1.0, 0.55, 0.18, 1.0), s2)
		elif k2 == "loyalty_strain":
			col = col.lerp(Color(0.95, 0.72, 0.28, 1.0), s2)
		else:
			col = col.lerp(Color(0.62, 0.35, 0.92, 1.0), s2)
	return col


func _shade_sea_province_fill(base: Color, province: Province = null) -> Color:
	# Continuous sea with slight zone variance (readable theaters, still one ocean family).
	var zone := ""
	if province != null:
		if province.strategic_region_id > 0:
			zone = "sr_%d" % province.strategic_region_id
		elif not province.name.is_empty():
			zone = province.name
		else:
			zone = "sea_%d" % province.id
	var shift := sea_zone_hue_shift(zone)
	return continuous_sea_fill_color(base, sea_political_trace, shift)


## Stable blue/cyan/teal palette per sea-zone theater name (naval mapmode underlay).
func _sea_zone_theater_color(zone_name: String) -> Color:
	var z := zone_name.strip_edges().to_lower()
	if z.is_empty():
		return Color(0.12, 0.32, 0.48, 1.0)
	# Prefer readable water hues; hash spreads 19 zones without looking random-neon.
	var h := float(absi(z.hash()) % 1000) / 1000.0
	var hue := 0.48 + h * 0.22  # ~173°–252° (teal → blue → indigo)
	var sat := 0.42 + fmod(h * 3.7, 1.0) * 0.18
	var val := 0.48 + fmod(h * 5.3, 1.0) * 0.22
	return Color.from_hsv(hue, sat, val, 1.0)


## Land province abutting sea/strait or tagged coastal/port — for naval mapmode rim + select flair.
func _province_is_coastal_land(province: Province) -> bool:
	if province == null or province.is_sea:
		return false
	if province.has_method("resolve_has_port") and bool(province.resolve_has_port()):
		return true
	var terr := str(province.terrain).to_lower()
	if terr in ["coastal", "coast", "harbor", "port"] or str(province.domain).to_lower() in ["coastal_land", "coast"]:
		return true
	if province.has_method("has_feature"):
		if province.has_feature("coastal") or province.has_feature("port") or province.has_feature("harbor"):
			return true
	# Use full adjacency (land+sea). get_adjacent_provinces(only_land) omits sea edges.
	var adjs: Array = []
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacency_system"):
		var adj_sys: Variant = MapManager.get_adjacency_system()
		if adj_sys != null and adj_sys.has_method("get_neighbors"):
			adjs = adj_sys.get_neighbors(province.id)
	if adjs.is_empty() and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_adjacent_provinces"):
		adjs = MapManager.get_adjacent_provinces(province.id, true)
	for aid in adjs:
		var ap: Province = null
		if provinces.has(int(aid)):
			ap = provinces[int(aid)]
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			ap = MapManager.get_province(int(aid))
		if ap != null and (ap.is_sea or str(ap.domain).to_lower() in ["sea", "strait"]):
			return true
	return false


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
		_select_province(resolved_province, resolved_node)
		_center_camera_on_province(resolved_province.id, "soft")
		show_info_panel(resolved_province)


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
## Pass 51: zoom_mode = tactical | soft | keep (pan only).
func focus_province_by_id(province_id: int, zoom_mode: String = "tactical") -> bool:
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
	if cam == null:
		cam = get_viewport().get_camera_2d() if get_viewport() else null
	if cam != null and pos != Vector2.ZERO:
		var tactical_z := clampf(2.4 * MapCanvasConfig.THEATER_SCALE, min_zoom, max_zoom)
		cam.global_position = _apply_camera_bounds(pos)
		var zm := zoom_mode.strip_edges().to_lower()
		if zm == "keep":
			pass  # pan only
		elif zm == "soft":
			var cur_z := absf(cam.zoom.x)
			var soft_z := clampf(lerpf(cur_z, tactical_z, 0.5), min_zoom, max_zoom)
			cam.zoom = Vector2(soft_z, soft_z)
		else:
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
	# Do not rebuild inspector here — caller opens it once after select (avoids double hang).
	if _hover_province != null:
		_refresh_hover_tooltip(_hover_province)
	else:
		_clear_compare_preview_outline()
	_refresh_supply_highlights()
	_refresh_compare_candidate_outlines()
	_update_supply_legend_text()
	_update_compare_hint_label()
	_play_map_action_flair_select(province)


## Pan/zoom so the province sits in the free map area (right of left-docked inspector).
## zoom_mode: "soft" (gentle zoom-in) | "keep" (pan only) | "tactical" (closer).
func _center_camera_on_province(province_id: int, zoom_mode: String = "soft") -> void:
	if province_id < 0:
		return
	var pos: Vector2 = province_centroids.get(province_id, Vector2.ZERO) as Vector2
	if pos == Vector2.ZERO and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
		pos = MapManager.get_province_centroid(province_id)
	if pos == Vector2.ZERO:
		return
	var cam := get_node_or_null("MapCamera") as Camera2D
	if cam == null and get_viewport():
		cam = get_viewport().get_camera_2d()
	if cam == null:
		return
	var zm := zoom_mode.strip_edges().to_lower()
	var cur_z := maxf(absf(cam.zoom.x), 0.01)
	if zm == "tactical":
		cur_z = clampf(2.2 * MapCanvasConfig.THEATER_SCALE, min_zoom, max_zoom)
		cam.zoom = Vector2(cur_z, cur_z)
	elif zm == "soft":
		var soft_target := clampf(maxf(cur_z, 0.9), min_zoom, max_zoom)
		if cur_z < 0.75:
			soft_target = clampf(lerpf(cur_z, 1.15, 0.55), min_zoom, max_zoom)
		cam.zoom = Vector2(soft_target, soft_target)
		cur_z = soft_target
	# else keep zoom
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var panel_w := 0.0
	if info_panel is Control and (info_panel as Control).visible:
		panel_w = maxf(absf((info_panel as Control).offset_right - (info_panel as Control).offset_left), 480.0)
	else:
		# Assault / pin paths no longer open the inspector; do not fake a left dock.
		panel_w = 0.0
	# Place province at horizontal center of the free map band (right of panel).
	var free_left := panel_w + 16.0
	var free_right := vp.x - 12.0
	var target_screen_x := (free_left + free_right) * 0.5
	var target_screen_y := vp.y * 0.52
	var z := maxf(absf(cam.zoom.x), 0.01)
	var cam_x := pos.x - (target_screen_x - vp.x * 0.5) / z
	var cam_y := pos.y - (target_screen_y - vp.y * 0.5) / z
	cam.global_position = _apply_camera_bounds(Vector2(cam_x, cam_y))


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
	if _is_mouse_over_blocking_ui():
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


func _is_mouse_over_blocking_ui() -> bool:
	## True when cursor is over a screen/popup so map hover text must not bleed through.
	var vp := get_viewport()
	if vp == null:
		return false
	var hov: Control = vp.gui_get_hovered_control()
	if hov == null:
		return false
	var n: Node = hov
	while n != null:
		if n is Window and (n as Window).visible:
			return true
		if n is DraggablePanel and (n as CanvasItem).visible:
			return true
		var nn := str(n.name)
		if nn in [
			"TechnologyScreen",
			"InfoPanel",
			"MainMenu",
			"DebugOverlay",
			"OrderCommandPanel",
			"DiplomacyView",
			"TradeMarketView",
			"ProductionAssignmentScreen",
			"LeaderAssignmentScreen",
			"AgentAssignmentScreen",
			"NationalSpiritsScreen",
			"ProvinceHoverTooltip",
		]:
			return true
		if nn.ends_with("Screen") or nn.ends_with("Popup") or nn.ends_with("View"):
			return true
		if nn == "TopInfoBar":
			return true
		n = n.get_parent()
	return false


func _refresh_hover_tooltip(province: Province) -> void:
	if hover_tooltip == null or province == null:
		return
	if _is_mouse_over_blocking_ui():
		_hide_hover_tooltip()
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

	# Don't show map province tooltips while the cursor is over a UI window/popup.
	if _is_mouse_over_blocking_ui():
		if _hover_province != null or (hover_tooltip != null and hover_tooltip.visible):
			_clear_hover_state()
		return

	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return

	var world_pos := _screen_to_world(mouse_screen)

	var pid := -1
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_at_world_pos"):
		pid = MapManager.get_province_at_world_pos(world_pos, true)
		if MapManager.has_method("resolve_pick_province_id"):
			pid = MapManager.resolve_pick_province_id(pid)
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
	# Real province always wins — never redirect back to coarse (that re-teleported camera every
	# data_changed/air tick after clicking Africa and hard-crashed while panning).
	if province != null:
		_selected_coarse_id = 0
	elif _selected_coarse_id != 0:
		_show_coarse_territory_info(_selected_coarse_id, false)
		return
	if info_panel == null or province == null:
		return
	if not (info_panel is CanvasItem):
		push_warning("MapRenderer: info_panel is not a CanvasItem (type=" + str(info_panel.get_class()) + ", script=" + str(info_panel.get_script()) + ") — cannot show inspector. Check scene NodePath exports for the MapRenderer or wiring in _wire_info_panel_refs.")
		return

	_layout_map_ui()
	info_panel.visible = true
	_layout_info_panel_inner()
	# After panel is visible, nudge camera so selection sits in free map band (right of panel).
	if not info_panel.has_meta("user_moved") and selected_province_id == province.id:
		call_deferred("_center_camera_on_province", province.id, "keep")
	# Second + third pass after size settles so wrap width matches real scroll viewport.
	call_deferred("_layout_info_panel_inner")
	get_tree().create_timer(0.05).timeout.connect(_layout_info_panel_inner, CONNECT_ONE_SHOT)

	# Top-line: name / owner / region / sea zone (always present when data exists).
	var topline: Dictionary = ProvinceInsight.build_inspector_topline(province)
	var name_text := str(topline.get("title", province.name))
	if selected_province_id >= 0 and selected_province_id != province.id:
		var other := _battle_counterpart_for_hover(province)
		if other != null:
			name_text += "  ⚔ vs " + other.name
	info_name.text = name_text
	# Province ID badge (top-right of panel, left of Close) for easy playtest callouts.
	_ensure_province_id_badge()
	if _province_id_badge != null:
		_province_id_badge.text = "#%d" % int(province.id)
		_province_id_badge.visible = true
		_province_id_badge.tooltip_text = "Province id %d · use this number when reporting map issues" % int(province.id)
	var ctrl_note := ""
	if ProvinceInsight.is_province_contested(province):
		ctrl_note = "  ⚑ held by %s" % province.controller_tag
	elif province.controller_tag != province.owner_tag and not province.controller_tag.is_empty():
		ctrl_note = " (controlled by %s)" % province.controller_tag
	info_owner.text = str(topline.get("owner_line", "Owner: Unowned")) + ctrl_note
	info_population.text = "Population: %s" % str(province.population)
	var terrain_bits: PackedStringArray = ["Terrain: " + province.terrain.capitalize()]
	var region_line := str(topline.get("region_line", ""))
	if not region_line.is_empty():
		terrain_bits.append(region_line)
	var sea_line := str(topline.get("sea_zone_line", ""))
	if not sea_line.is_empty():
		terrain_bits.append(sea_line)
	info_terrain.text = " · ".join(terrain_bits)
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
	_refresh_oob_strip_for_province(province)


func _ensure_oob_strip() -> void:
	if _oob_strip != null and is_instance_valid(_oob_strip):
		return
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var strip_script = load("res://scripts/ui/ProvinceOOBStrip.gd")
	if strip_script == null:
		return
	_oob_strip = PanelContainer.new()
	_oob_strip.set_script(strip_script)
	_oob_strip.name = "ProvinceOOBStrip"
	_oob_strip.visible = false
	ui.add_child(_oob_strip)
	# Dock under info panel area (left).
	if _oob_strip is Control:
		var c := _oob_strip as Control
		c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		c.offset_left = 12.0
		c.offset_right = 420.0
		c.offset_top = -160.0
		c.offset_bottom = -80.0
	if _oob_strip.has_signal("formation_focused"):
		_oob_strip.formation_focused.connect(_on_oob_strip_formation_focused)
	if _oob_strip.has_signal("filter_mode_changed"):
		_oob_strip.filter_mode_changed.connect(_on_oob_strip_filter_mode_changed)


func _hide_oob_strip() -> void:
	if _oob_strip != null and is_instance_valid(_oob_strip) and _oob_strip.has_method("clear_strip"):
		_oob_strip.call("clear_strip")
	elif _oob_strip != null and is_instance_valid(_oob_strip):
		_oob_strip.visible = false


func _refresh_oob_strip_for_province(province: Province) -> void:
	if province == null:
		_hide_oob_strip()
		return
	_ensure_oob_strip()
	if _oob_strip == null:
		return
	var forms: Array = _collect_formations_at_province(province.id)
	# Pass 9/10: default player filter; "All" toggle can show foreign stacks.
	var player_tag := _player_country_tag_for_oob()
	var player_only := true
	if "player_only" in _oob_strip:
		player_only = bool(_oob_strip.player_only)
	var player_forms: Array = []
	if not player_tag.is_empty():
		for fo in forms:
			if fo is Object and "country_tag" in fo:
				if str(fo.country_tag).strip_edges().to_upper() == player_tag:
					player_forms.append(fo)
			elif fo is Dictionary:
				var d: Dictionary = fo
				var t := str(d.get("country_tag", d.get("owner_tag", ""))).strip_edges().to_upper()
				if t == player_tag:
					player_forms.append(fo)
	else:
		player_forms = forms
	# Show when 2+ visible units under current filter, or 2+ total so All toggle is useful.
	var visible_n := player_forms.size() if player_only else forms.size()
	if visible_n <= 1 and forms.size() <= 1:
		_hide_oob_strip()
		return
	if player_only and player_forms.size() <= 1 and forms.size() < 2:
		_hide_oob_strip()
		return
	if _oob_strip.has_method("show_for_province"):
		_oob_strip.call("show_for_province", province.id, forms, player_tag)
	# Keep above minimap but below top bar chrome.
	if _oob_strip is Control and info_panel is Control:
		var ip := info_panel as Control
		var c := _oob_strip as Control
		c.offset_left = ip.offset_left
		c.offset_right = ip.offset_left + 400.0
		c.offset_top = ip.offset_bottom + 8.0
		c.offset_bottom = c.offset_top + 96.0


func _on_oob_strip_filter_mode_changed(_player_only: bool) -> void:
	if selected_province_id >= 0 and provinces.has(selected_province_id):
		_refresh_oob_strip_for_province(provinces[selected_province_id] as Province)


func _player_country_tag_for_oob() -> String:
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		return str(LeaderManager.get_player_country_tag()).strip_edges().to_upper()
	return ""


func _collect_formations_at_province(province_id: int) -> Array:
	var out: Array = []
	if typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
		for fid_v in LeaderManager.formations.keys():
			var f: Variant = LeaderManager.formations[fid_v]
			if f == null or not (f is Object):
				continue
			var fo: Object = f as Object
			if "stationed_province_id" in fo and int(fo.stationed_province_id) == province_id:
				out.append(fo)
	return out


func _on_oob_strip_formation_focused(formation_id: String) -> void:
	if formation_id.is_empty():
		return
	if typeof(LeaderManager) == TYPE_NIL:
		return
	var f: Formation = LeaderManager.get_formation(formation_id) if LeaderManager.has_method("get_formation") else null
	if f == null:
		return
	var pid := int(f.stationed_province_id) if "stationed_province_id" in f else -1
	if pid >= 0 and has_method("focus_province_by_id"):
		focus_province_by_id(pid)
	_show_unit_detail_popup(f)
	print("MapRenderer: OOB strip focus ", formation_id)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Unit: %s" % formation_id)


## Click navy/armor/infantry map counters → select unit for move/assault + detail card.
func _try_open_unit_at_world(world_pos: Vector2) -> bool:
	var fo := _pick_unit_formation_at_world(world_pos)
	if fo == null:
		return false
	_select_map_unit(fo)
	_show_unit_detail_popup(fo)
	# Stage host province only — pin click must not open inspector (hang class).
	var pid := -1
	if "stationed_province_id" in fo:
		pid = int(fo.stationed_province_id)
	if pid >= 0 and provinces.has(pid):
		var p: Province = provinces[pid] as Province
		_select_province(p, _province_node(pid))
		attack_staging_province_id = pid
		debug_combat_attacker_province_id = pid
	return true


## Select grey pin unit for movement / assault staging.
func _select_map_unit(formation: Object) -> void:
	if formation == null:
		return
	var fid := ""
	if "formation_id" in formation:
		fid = str(formation.formation_id)
	selected_formation_id = fid
	_refresh_selected_unit_chip()
	var name_s := str(formation.name) if "name" in formation else fid
	var pid := int(formation.stationed_province_id) if "stationed_province_id" in formation else -1
	if pid >= 0:
		attack_staging_province_id = pid
		debug_combat_attacker_province_id = pid
	var toast := "Unit selected · %s · click friendly province to MARCH (days) · Ctrl+click enemy to ASSAULT · Esc clears" % name_s
	_show_inspector_toast(toast, 5.5)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(toast)


## Selected-chip ring via nation-frame helper. One pin per province — match by station pid
## (stack cycle keeps ring on the province pin even when selected_formation_id is not the rep).
func _refresh_selected_unit_chip() -> void:
	if _demo_unit_icon_pids.is_empty():
		return
	var gold := Color(1.0, 0.85, 0.25, 1.0)
	# Resolve selected formation's station province (stack cycle: fid changes, pin stays).
	var sel_pid := -1
	if not selected_formation_id.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
		var sel_f: Formation = LeaderManager.get_formation(selected_formation_id)
		if sel_f != null and "stationed_province_id" in sel_f:
			sel_pid = int(sel_f.stationed_province_id)
	for id_v in _demo_unit_icon_pids:
		var id := int(id_v)
		if not province_nodes.has(id):
			continue
		var n: Node2D = province_nodes[id] as Node2D
		if n == null:
			continue
		var counter: Node2D = n.get_node_or_null("DemoUnitIcon_" + str(id)) as Node2D
		if counter == null or not is_instance_valid(counter):
			continue
		# free() same-frame so re-add is not renamed SelectedFrame2 (queue_free leaves sibling).
		var old_sel: Node = counter.get_node_or_null("SelectedFrame")
		if old_sel != null:
			counter.remove_child(old_sel)
			old_sel.free()
		if selected_formation_id.is_empty() or sel_pid < 0:
			continue
		# Province pin match (one DemoUnitIcon per pid); formation_id equality is optional fast path.
		var pin_pid := int(counter.get_meta("province_id", id))
		var cfid := str(counter.get_meta("formation_id", ""))
		var match_pin := pin_pid == sel_pid or (not cfid.is_empty() and cfid == selected_formation_id)
		if not match_pin:
			continue
		var frame := _make_unit_nation_frame(gold)
		frame.name = "SelectedFrame"
		frame.z_index = 20
		counter.add_child(frame)


## Cycle stack at selected unit's province ([ ] keys / unit card buttons). One pin per province.
func _cycle_selected_stack_unit(delta: int) -> bool:
	if selected_formation_id.is_empty() or delta == 0:
		return false
	if typeof(LeaderManager) == TYPE_NIL or not LeaderManager.has_method("get_formation"):
		return false
	var cur: Formation = LeaderManager.get_formation(selected_formation_id)
	if cur == null:
		return false
	var pid := int(cur.stationed_province_id) if "stationed_province_id" in cur else -1
	var tag := str(cur.country_tag).strip_edges().to_upper() if "country_tag" in cur else ""
	if pid < 0 or tag.is_empty():
		return false
	if typeof(BattleManager) == TYPE_NIL or not BattleManager.has_method("get_divisions_at_province"):
		return false
	var divs: Array = BattleManager.get_divisions_at_province(pid, tag)
	if divs.size() <= 1:
		return false
	var idx := 0
	for i in divs.size():
		if str(divs[i].get("formation_id", "")) == selected_formation_id:
			idx = i
			break
	var n := divs.size()
	idx = posmod(idx + delta, n)
	var next_fid := str(divs[idx].get("formation_id", ""))
	if next_fid.is_empty():
		return false
	var next_f: Formation = LeaderManager.get_formation(next_fid)
	if next_f == null:
		return false
	_select_map_unit(next_f)
	_show_unit_detail_popup(next_f)
	return true


## Order selected unit to a friendly (or owned) province. Returns true if handled.
## Enqueues own-land march (calendar hops). Instant move_formation_to_province is hop-commit only.
func _try_move_selected_unit_to_province(province: Province) -> bool:
	if province == null or selected_formation_id.is_empty():
		return false
	var p_tag := _player_tag()
	if p_tag.is_empty():
		return false
	# Only move own units onto own/controlled land (not enemy assault — that is Ctrl+click).
	if not _province_controlled_by(province, p_tag):
		return false
	var fid := selected_formation_id
	var dest := province.id
	if typeof(FormationMovement) == TYPE_NIL or not FormationMovement.has_method("enqueue_own_land_march"):
		return false
	var res: Dictionary = FormationMovement.enqueue_own_land_march(fid, dest, p_tag)
	if bool(res.get("already_here", false)):
		_show_inspector_toast("Already at %s" % province.name, 2.5)
		return true
	if not bool(res.get("ok", false)):
		var reason := str(res.get("reason", ""))
		_show_inspector_toast(
			"March blocked · %s" % (reason if not reason.is_empty() else "no own-land path"),
			3.5,
			true
		)
		return true
	var hops_n := int(res.get("hops", 1))
	var cal := int(res.get("calendar_days", 1))
	var path: Array = res.get("path", []) as Array
	_highlight_march_path(path)
	_show_inspector_toast(
		"March · %d hop%s · arrives in %d day%s · unpause to walk · %s"
		% [hops_n, "s" if hops_n != 1 else "", cal, "s" if cal != 1 else "", province.name],
		5.0
	)
	return true


func _highlight_march_path(province_path: Array) -> void:
	if _march_path_line != null and is_instance_valid(_march_path_line):
		_march_path_line.queue_free()
		_march_path_line = null
	if province_path.size() < 2:
		return
	var pts := PackedVector2Array()
	for pid_v in province_path:
		var pid := int(pid_v)
		if province_centroids.has(pid):
			pts.append(province_centroids[pid] as Vector2)
		elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_centroid"):
			var c: Vector2 = MapManager.get_province_centroid(pid)
			if c != Vector2.ZERO:
				pts.append(c)
	if pts.size() < 2:
		return
	var line := Line2D.new()
	line.name = "MarchPathLine"
	line.width = 3.2
	line.default_color = Color(1.0, 0.82, 0.22, 0.88)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.points = pts
	line.z_index = 24
	add_child(line)
	_march_path_line = line


func _on_march_hop_ui(to_pid: int, arrived: bool, dest_id: int = -1, hop: Dictionary = {}) -> void:
	var pname := "province %d" % to_pid
	if provinces.has(to_pid):
		var p: Province = provinces[to_pid] as Province
		if p != null:
			pname = p.name
	var rf: Dictionary = hop.get("reinforce", {}) as Dictionary if hop is Dictionary else {}
	if bool(rf.get("joined", false)):
		_sync_land_battle_bubbles()
		_play_map_sfx("confirm")
		_show_inspector_toast(
			"Reinforced front · %dv%d · lean %s · est. %d days"
			% [int(rf.get("att_n", 1)), int(rf.get("def_n", 1)), str(rf.get("lean", "even")), int(rf.get("est_days", 0))],
			4.5
		)
		if arrived:
			attack_staging_province_id = to_pid
			debug_combat_attacker_province_id = to_pid
		return
	if arrived:
		if _march_path_line != null and is_instance_valid(_march_path_line):
			_march_path_line.queue_free()
			_march_path_line = null
		_show_inspector_toast("Arrived · %s · Ctrl+click enemy to assault" % pname, 4.0)
		attack_staging_province_id = to_pid
		debug_combat_attacker_province_id = to_pid
	else:
		_show_inspector_toast("Marching · now at %s" % pname, 2.8)


func _pick_unit_formation_at_world(world_pos: Vector2) -> Object:
	if _demo_unit_icon_pids.is_empty():
		return null
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	var z := 1.0
	if cam:
		z = maxf(cam.zoom.x, cam.zoom.y)
	# ~48px screen radius in world units; floor so tactical zoom stays finger-sized.
	var hit_r := maxf(48.0 / maxf(z, 0.05), 20.0)
	var hit_r2 := hit_r * hit_r
	var best_player: Object = null
	var best_player_d := INF
	var best_any: Object = null
	var best_any_d := INF
	var p_tag := _player_tag()
	for id_v in _demo_unit_icon_pids:
		var id := int(id_v)
		if not province_nodes.has(id):
			continue
		var n: Node2D = province_nodes[id] as Node2D
		if n == null:
			continue
		var counter: Node2D = n.get_node_or_null("DemoUnitIcon_" + str(id)) as Node2D
		if counter == null or not is_instance_valid(counter):
			continue
		# Hidden pins (strategic LOD) must not steal hex clicks.
		if not counter.visible:
			continue
		var d := world_pos.distance_squared_to(counter.global_position)
		if d > hit_r2:
			continue
		var fo: Object = null
		if counter.has_meta("formation"):
			var fmeta: Variant = counter.get_meta("formation")
			if fmeta is Object and is_instance_valid(fmeta as Object):
				fo = fmeta as Object
		if fo == null:
			var fid := str(counter.get_meta("formation_id", ""))
			if not fid.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_formation"):
				var f2: Variant = LeaderManager.get_formation(fid)
				if f2 is Object:
					fo = f2 as Object
		if fo == null:
			continue
		# Inclusive disk: accept boundary (d == hit_r2) as a valid best.
		if d <= best_any_d:
			best_any_d = d
			best_any = fo
		# Prefer player-tag pins; closest player pin wins on overlap.
		if not p_tag.is_empty() and "country_tag" in fo:
			if str(fo.country_tag).strip_edges().to_upper() == p_tag and d <= best_player_d:
				best_player_d = d
				best_player = fo
	if best_player != null:
		return best_player
	return best_any


func _show_unit_detail_popup(formation: Object) -> void:
	if formation == null:
		return
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	# Replace previous card.
	var old := ui.get_node_or_null("UnitDetailPopup")
	if old != null:
		old.queue_free()

	var name_s := "Unit"
	if "name" in formation:
		name_s = str(formation.name)
	var fid := ""
	if "formation_id" in formation:
		fid = str(formation.formation_id)
	var tag := ""
	if "country_tag" in formation:
		tag = str(formation.country_tag)
	var ftype := ""
	if formation.has_method("get_category"):
		ftype = str(formation.call("get_category"))
	elif "formation_type" in formation:
		ftype = str(formation.formation_type)
	var dsn := ""
	if "design_id" in formation and str(formation.design_id) != "":
		dsn = str(formation.design_id)
	elif "naval_design_id" in formation and str(formation.naval_design_id) != "":
		dsn = str(formation.naval_design_id)
	elif "air_design_id" in formation and str(formation.air_design_id) != "":
		dsn = str(formation.air_design_id)
	var pid := int(formation.stationed_province_id) if "stationed_province_id" in formation else -1
	var org_v := clampf(float(formation.organization) if "organization" in formation else 1.0, 0.0, 1.5)
	var str_v := clampf(float(formation.strength) if "strength" in formation else 1.0, 0.0, 1.5)
	var rdy_v := clampf(float(formation.readiness) if "readiness" in formation else 1.0, 0.0, 1.5)
	var xp_v := 0.0
	if "combat_experience" in formation:
		xp_v = clampf(float(formation.combat_experience) / 100.0, 0.0, 1.0)
	var fuel_v := -1.0
	if "fuel_level" in formation:
		fuel_v = clampf(float(formation.fuel_level), 0.0, 1.5)
	var leader_s := "—"
	if "leader_id" in formation and str(formation.leader_id) != "" and typeof(LeaderManager) != TYPE_NIL:
		if LeaderManager.has_method("get_leader"):
			var L: Variant = LeaderManager.get_leader(str(formation.leader_id))
			if L != null and L is Object and "name" in L:
				leader_s = str(L.name)
			else:
				leader_s = str(formation.leader_id)
	var prov_name := "Province %d" % pid
	if pid >= 0 and provinces.has(pid):
		var p: Province = provinces[pid] as Province
		if p != null:
			prov_name = p.name

	var panel := PanelContainer.new()
	panel.name = "UnitDetailPopup"
	panel.z_index = 70
	panel.clip_contents = true
	panel.custom_minimum_size = Vector2(320, 220)
	RetrowaveTheme.style_detail_panel_flat(panel)
	# Docked HOI-style unit card (bottom-left). UNIT_CARD_DOCK / unit_card_dock — not a mouse popup.
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var dock := Vector2(18.0, maxf(64.0, vp.y - 276.0))
	panel.position = dock
	panel.set_meta("unit_card_dock", true)
	ui.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)
	var title := Label.new()
	title.text = name_s
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_title(title, RetrowaveTheme.CYAN)
	title.add_theme_font_size_override("font_size", 16)
	title_row.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	RetrowaveTheme.style_secondary_button(close_btn)
	close_btn.pressed.connect(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free()
	)
	title_row.add_child(close_btn)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(290, 0)
	var lines: PackedStringArray = []
	if not tag.is_empty():
		lines.append("Nation: %s" % tag)
	if not ftype.is_empty():
		lines.append("Type: %s" % ftype.replace("_", " ").capitalize())
	if not dsn.is_empty():
		lines.append("Design: %s" % dsn)
	lines.append("Stationed: %s" % prov_name)
	lines.append("Leader: %s" % leader_s)
	lines.append(
		"Org %.0f%% · Str %.0f%% · Rdy %.0f%% · XP %.0f%%"
		% [org_v * 100.0, str_v * 100.0, rdy_v * 100.0, xp_v * 100.0]
	)
	if fuel_v >= 0.0:
		lines.append("Fuel: %.0f%%" % (fuel_v * 100.0))
	if typeof(UnitCardCombatStrip) != TYPE_NIL and UnitCardCombatStrip.has_method("lines_for"):
		lines.append_array(UnitCardCombatStrip.lines_for(formation))
	if not fid.is_empty():
		lines.append("ID: %s" % fid)
	# Stack at this province (one pin; cycle via [ ] or card buttons).
	var stack_divs: Array = []
	var stack_idx := 0
	if pid >= 0 and not tag.is_empty() and typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_divisions_at_province"):
		stack_divs = BattleManager.get_divisions_at_province(pid, tag)
		for si in stack_divs.size():
			if str(stack_divs[si].get("formation_id", "")) == fid:
				stack_idx = si
				break
	if stack_divs.size() > 1:
		lines.append("Stack %d/%d · [ ] or buttons to cycle" % [stack_idx + 1, stack_divs.size()])
	body.text = "\n".join(lines)
	RetrowaveTheme.style_body_label(body)
	vbox.add_child(body)

	var cmd_row := HBoxContainer.new()
	cmd_row.add_theme_constant_override("separation", 6)
	vbox.add_child(cmd_row)
	var marching := typeof(FormationMovement) != TYPE_NIL and FormationMovement.has_method("has_march") \
		and bool(FormationMovement.has_march(fid))
	if marching:
		var halt_btn := Button.new()
		halt_btn.text = "Halt march"
		halt_btn.focus_mode = Control.FOCUS_NONE
		halt_btn.tooltip_text = "Cancel the queued own-land march; stay on the current hex."
		RetrowaveTheme.style_secondary_button(halt_btn)
		halt_btn.pressed.connect(func() -> void:
			if typeof(FormationMovement) != TYPE_NIL:
				FormationMovement.clear_march(fid)
			if _march_path_line != null and is_instance_valid(_march_path_line):
				_march_path_line.queue_free()
				_march_path_line = null
			_show_inspector_toast("March halted · %s" % name_s, 3.0)
			_show_unit_detail_popup(formation)
		)
		cmd_row.add_child(halt_btn)
	var bat: Dictionary = {}
	if typeof(BattleManager) != TYPE_NIL:
		if BattleManager.has_method("get_land_battle_for_formation"):
			bat = BattleManager.get_land_battle_for_formation(fid)
		if bat.is_empty() and BattleManager.has_method("get_land_battle_at"):
			bat = BattleManager.get_land_battle_at(pid)
	var in_battle := not bat.is_empty()
	if in_battle:
		var hook := str(bat.get("next_hook", ""))
		if hook.is_empty() and BattleManager.has_method("land_battle_next_hook"):
			hook = str(BattleManager.land_battle_next_hook(bat))
		if not hook.is_empty():
			lines.append(hook)
			body.text = "\n".join(lines)
		var stance_row := HBoxContainer.new()
		stance_row.add_theme_constant_override("separation", 6)
		vbox.add_child(stance_row)
		var cur_st := str(bat.get("att_stance", "press"))
		if BattleManager.has_method("set_land_battle_stance"):
			var press_btn := Button.new()
			press_btn.text = "Press" if cur_st != "press" else "Press ●"
			press_btn.focus_mode = Control.FOCUS_NONE
			press_btn.tooltip_text = "Hit harder, spend more org and equipment. Use to finish a breaking front."
			RetrowaveTheme.style_secondary_button(press_btn)
			press_btn.pressed.connect(func() -> void:
				var r: Dictionary = BattleManager.set_land_battle_stance(fid, "press")
				_show_inspector_toast(str(r.get("next_hook", "Stance: Press")), 3.5)
				_show_unit_detail_popup(formation)
			)
			stance_row.add_child(press_btn)
			var hold_btn := Button.new()
			hold_btn.text = "Hold" if cur_st != "hold" else "Hold ●"
			hold_btn.focus_mode = Control.FOCUS_NONE
			hold_btn.tooltip_text = "Ease off. Less loss, slower fight. Wait for a reinforcing march."
			RetrowaveTheme.style_secondary_button(hold_btn)
			hold_btn.pressed.connect(func() -> void:
				var r2: Dictionary = BattleManager.set_land_battle_stance(fid, "hold")
				_show_inspector_toast(str(r2.get("next_hook", "Stance: Hold")), 3.5)
				_show_unit_detail_popup(formation)
			)
			stance_row.add_child(hold_btn)
	if in_battle and typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("withdraw_from_land_battle"):
		var wd_btn := Button.new()
		wd_btn.text = "Withdraw"
		wd_btn.focus_mode = Control.FOCUS_NONE
		wd_btn.tooltip_text = "Disengage this unit from the open land battle."
		RetrowaveTheme.style_secondary_button(wd_btn)
		wd_btn.pressed.connect(func() -> void:
			var wr: Dictionary = BattleManager.withdraw_from_land_battle(fid)
			_sync_land_battle_bubbles()
			_play_map_sfx("error")
			_show_inspector_toast(
				"Withdraw · %s" % str(wr.get("reason", wr.get("ok", "done"))),
				3.5
			)
			_show_unit_detail_popup(formation)
		)
		cmd_row.add_child(wd_btn)
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_available_leaders"):
		var avail: Array = LeaderManager.get_available_leaders(tag)
		if avail.size() > 0:
			var L: Variant = avail[0]
			var lname := str(L.name) if L is Object and "name" in L else "leader"
			var as_btn := Button.new()
			as_btn.text = "Assign %s" % lname
			as_btn.focus_mode = Control.FOCUS_NONE
			as_btn.tooltip_text = "Assign an unused leader of this tag."
			RetrowaveTheme.style_secondary_button(as_btn)
			as_btn.pressed.connect(func() -> void:
				if formation != null and formation.has_method("assign_leader") and L is Object:
					formation.assign_leader(L as Object)
				_show_inspector_toast("Leader assigned · %s" % lname, 3.0)
				_show_unit_detail_popup(formation)
			)
			cmd_row.add_child(as_btn)

	if stack_divs.size() > 1:
		var stack_row := HBoxContainer.new()
		stack_row.add_theme_constant_override("separation", 6)
		vbox.add_child(stack_row)
		var prev_btn := Button.new()
		prev_btn.text = "["
		prev_btn.focus_mode = Control.FOCUS_NONE
		prev_btn.tooltip_text = "Previous unit in stack"
		RetrowaveTheme.style_secondary_button(prev_btn)
		prev_btn.pressed.connect(func() -> void:
			_cycle_selected_stack_unit(-1)
		)
		stack_row.add_child(prev_btn)
		var next_btn := Button.new()
		next_btn.text = "]"
		next_btn.focus_mode = Control.FOCUS_NONE
		next_btn.tooltip_text = "Next unit in stack"
		RetrowaveTheme.style_secondary_button(next_btn)
		next_btn.pressed.connect(func() -> void:
			_cycle_selected_stack_unit(1)
		)
		stack_row.add_child(next_btn)

	var hint := Label.new()
	hint.text = "SELECTED · click friendly land to MARCH (arrives in N days) · Ctrl+click enemy to ASSAULT · Esc clears"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(290, 0)
	RetrowaveTheme.style_body_label(hint)
	hint.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			ui.move_child(panel, ui.get_child_count() - 1)
	)


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
	var v := ui.get_node_or_null("InfoPanel/InfoScroll/InfoContentMargin/InfoContent") as VBoxContainer
	if v != null:
		return v
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
		_label_invest_status.custom_minimum_size = Vector2(0, 0)
		_label_invest_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label_invest_status.add_theme_font_size_override("font_size", 11)
		content.add_child(_label_invest_status)

	if _progress_invest == null or not is_instance_valid(_progress_invest):
		_progress_invest = ProgressBar.new()
		_progress_invest.name = "ProgressInvest"
		_progress_invest.custom_minimum_size = Vector2(0, 14)
		_progress_invest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		_label_invest_modifiers.custom_minimum_size = Vector2(0, 0)
		_label_invest_modifiers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# Pure panel formatter (progress / cancel / sabo) — same contract as map_polish_formatters.py
	var cur_infra := province.infrastructure
	var cur_dev := province.development_level
	var panel: Dictionary = _MapPolishFormatters.format_invest_panel_state(status, cur_infra, cur_dev)
	var has_project: bool = bool(panel.get("has_project", false))
	var sabotaged: bool = bool(panel.get("sabotaged", false))

	_label_invest_status.text = str(panel.get("label", ""))
	_label_invest_status.modulate = (
		Color(1.0, 0.85, 0.4) if sabotaged else (Color(0.6, 0.95, 0.85) if has_project else Color(0.85, 0.9, 0.95))
	)

	if has_project:
		if _progress_invest:
			_progress_invest.visible = bool(panel.get("show_progress", true))
			_progress_invest.value = float(panel.get("progress_pct", 0))
			_progress_invest.modulate = Color(1.0, 0.6, 0.4, 0.95) if sabotaged else Color(0.6, 0.95, 0.85, 0.95)
		if _label_invest_modifiers:
			_label_invest_modifiers.text = str(panel.get("modifiers_label", ""))
			_label_invest_modifiers.visible = true
			_label_invest_modifiers.modulate = Color(1.0, 0.72, 0.55) if sabotaged else Color(0.9, 0.95, 0.8)
		_btn_invest_infra.text = str(panel.get("button_text", "Project Active"))
		_btn_invest_infra.disabled = bool(panel.get("button_disabled", true))
		if _btn_cancel_invest:
			_btn_cancel_invest.visible = bool(panel.get("show_cancel", true))
			_btn_cancel_invest.disabled = false
			_btn_cancel_invest.tooltip_text = (
				"Cancel the active infrastructure investment (no refund, progress lost)."
				+ (" Project is under sabotage — cancel or clear agents to stop the slowdown." if sabotaged else "")
			)
	else:
		if _progress_invest:
			_progress_invest.visible = false
		if _btn_cancel_invest:
			_btn_cancel_invest.visible = false
		if _label_invest_modifiers:
			_label_invest_modifiers.visible = false
		_btn_invest_infra.text = str(panel.get("button_text", "Invest in Infrastructure"))
		_btn_invest_infra.disabled = false
		# Cost/ETA preview on button tooltip when no project.
		if mgr.has_method("can_start_project"):
			var preview: Dictionary = mgr.can_start_project(province.id, "infrastructure", player_tag)
			if bool(preview.get("ok", false)):
				_btn_invest_infra.tooltip_text = (
					"Start provincial infrastructure project → Lv.%d. Cost ~%d Mandate, ETA ~%d days."
					% [cur_infra + 1, int(preview.get("cost_pp", 0)), int(preview.get("eta_days", 0))]
				)
			else:
				_btn_invest_infra.tooltip_text = str(preview.get("reason", "Cannot invest here."))
				_btn_invest_infra.disabled = true


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
		var flair: Dictionary = _MapNextListHelpers.format_infra_project_flair(
			pname, "start", 0, eta, cost
		)
		_show_inspector_toast(str(flair.get("toast", "Investment started")), float(flair.get("duration", 3.0)))
		_play_map_sfx(str(flair.get("sfx", "confirm")))
		if provinces.has(selected_province_id):
			show_info_panel(provinces[selected_province_id])
	else:
		_show_inspector_toast(
			str(result.get("reason", "Cannot start infrastructure investment")),
			3.5,
			true,
		)
		_play_map_sfx("error")


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

func _on_infra_completed_for_inspector(pid: int, new_level: int, _axis: String, _proj: Variant) -> void:
	var pname := ""
	if provinces.has(pid):
		pname = provinces[pid].name
	var flair: Dictionary = _MapNextListHelpers.format_infra_project_flair(pname, "complete", new_level)
	_show_inspector_toast(str(flair.get("toast", "Infrastructure complete")), float(flair.get("duration", 3.0)))
	_play_map_sfx(str(flair.get("sfx", "achievement")))
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("post_news"):
		LeaderEventUI.post_news(str(flair.get("news_headline", "Infrastructure complete")), str(flair.get("news_body", "")), "infrastructure")
	if pid == selected_province_id and info_panel != null and info_panel.visible and provinces.has(pid):
		show_info_panel(provinces[pid])  # full refresh for new infra level effects on combat/supply
		force_refresh_tints_for_owner(provinces[pid].owner_tag)
	elif provinces.has(pid):
		force_refresh_tints_for_owner(provinces[pid].owner_tag)


func _connect_infra_signals_for_inspector() -> void:
	if typeof(InfrastructureDevelopmentManager) == TYPE_NIL:
		return
	if not InfrastructureDevelopmentManager.project_progress_updated.is_connected(_on_infra_progress_for_inspector):
		InfrastructureDevelopmentManager.project_progress_updated.connect(_on_infra_progress_for_inspector)
	if not InfrastructureDevelopmentManager.project_completed.is_connected(_on_infra_completed_for_inspector):
		InfrastructureDevelopmentManager.project_completed.connect(_on_infra_completed_for_inspector)
	if InfrastructureDevelopmentManager.has_signal("project_sabotaged"):
		if not InfrastructureDevelopmentManager.project_sabotaged.is_connected(_on_infra_sabotaged_for_inspector):
			InfrastructureDevelopmentManager.project_sabotaged.connect(_on_infra_sabotaged_for_inspector)
	if InfrastructureDevelopmentManager.has_signal("project_cancelled"):
		if not InfrastructureDevelopmentManager.project_cancelled.is_connected(_on_infra_cancelled_for_inspector):
			InfrastructureDevelopmentManager.project_cancelled.connect(_on_infra_cancelled_for_inspector)


func _on_infra_sabotaged_for_inspector(pid: int, work_lost: float, severity: String) -> void:
	if pid == selected_province_id and info_panel != null and info_panel.visible and provinces.has(pid):
		_update_infrastructure_investment_ui(provinces[pid])
		_show_inspector_toast(
			"Infrastructure project sabotaged (%.1f work lost · %s)" % [work_lost, severity],
			3.0,
			true,
		)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("notify_province_changed"):
		MapManager.notify_province_changed(pid, "infrastructure_project")
	var ol := get_overlay_layer("InfrastructureOverlayLayer")
	if ol and ol.has_method("queue_redraw"):
		ol.queue_redraw()


func _on_infra_cancelled_for_inspector(pid: int, reason: String) -> void:
	if pid == selected_province_id and info_panel != null and info_panel.visible and provinces.has(pid):
		show_info_panel(provinces[pid])
		if reason != "player_cancelled":
			_show_inspector_toast("Infrastructure project cancelled (%s)." % reason, 2.5)


func _show_inspector_toast(message: String, duration: float = 2.5, is_error: bool = false) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(message, duration, is_error)
	else:
		print(message)


## Select flair: short toast + sfx from pure formatter (damage/HH context when present).
func _play_map_action_flair_select(province: Province) -> void:
	if province == null:
		return
	var region := ""
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province_region_id"):
		var rid: int = province.strategic_region_id if province.strategic_region_id > 0 else MapManager.get_province_region_id(province.id)
		if rid > 0 and MapManager.has_method("get_strategic_region_name"):
			region = MapManager.get_strategic_region_name(rid)
	var dmg_label := ""
	var dmg: Dictionary = ProvinceInsight.classify_province_map_damage(province)
	if bool(dmg.get("is_damaged", false)):
		dmg_label = str(dmg.get("label", ""))
	var hh_here := false
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state"):
		var ps: Dictionary = GameData.get_peace_state()
		var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
		hh_here = bool(sig.get("active", false)) and int(sig.get("province_id", -1)) == province.id
	var is_choke := false
	var sea_zone := ""
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("has_strategic_chokepoint"):
			is_choke = bool(MapManager.has_strategic_chokepoint(province.id))
		if MapManager.has_method("get_sea_zone_name"):
			sea_zone = str(MapManager.get_sea_zone_name(province.id))
	var is_coastal := _province_is_coastal_land(province)
	var flair: Dictionary = _MapNextListHelpers.format_province_select_flair(
		province.name,
		province.owner_tag,
		region,
		province.terrain,
		dmg_label,
		hh_here,
		is_choke,
		sea_zone,
		is_coastal,
	)
	# Brief toast — avoid spam if rapid re-select of same province
	if _last_select_flair_pid != province.id or Time.get_ticks_msec() - _last_select_flair_msec > 900:
		_show_inspector_toast(str(flair.get("toast", province.name)), float(flair.get("duration", 1.8)))
		_play_map_sfx(str(flair.get("sfx", "select")))
		_last_select_flair_pid = province.id
		_last_select_flair_msec = Time.get_ticks_msec()


func _play_map_sfx(kind: String) -> void:
	# Pass 56–59: pin focus mute / volume / bus.
	if kind == "pin_focus" and not get_pin_focus_sfx_enabled():
		return
	var path := str(_SFX_PATHS.get(kind, _SFX_PATHS["select"]))
	if not ResourceLoader.exists(path):
		return
	var stream = load(path)
	if stream == null:
		return
	if _map_sfx_player == null or not is_instance_valid(_map_sfx_player):
		_map_sfx_player = AudioStreamPlayer.new()
		_map_sfx_player.name = "MapActionSfx"
		_map_sfx_player.volume_db = -8.0
		add_child(_map_sfx_player)
	if kind == "pin_focus":
		_map_sfx_player.bus = get_pin_focus_sfx_bus()
		_map_sfx_player.volume_db = get_pin_focus_sfx_volume_db()
	else:
		_map_sfx_player.bus = "Master"
		_map_sfx_player.volume_db = -8.0
	_map_sfx_player.stream = stream
	_map_sfx_player.play()


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


## Ctrl+click confirm: first click = preview, second click same target = execute (no more instant surprise capture).
var _assault_confirm_target_id: int = -1
var _assault_confirm_msec: int = 0
const _ASSAULT_CONFIRM_WINDOW_MS: int = 5000
## Prevent re-entrant execute / border storms that freeze the main thread (2nd Ctrl+click hang).
var _assault_execute_busy: bool = false
## Player-selected map unit (grey pin click) for move / assault staging.
var selected_formation_id: String = ""
## One-shot toast when hex-click happens while pins are hidden (strategic / master-off).
var _unit_pick_strategic_hint_shown: bool = false


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

	# First Ctrl+click: preview only. Second within 5s on same target: execute.
	var now_ms := Time.get_ticks_msec()
	var confirm := (
		target_pid == _assault_confirm_target_id
		and now_ms - _assault_confirm_msec < _ASSAULT_CONFIRM_WINDOW_MS
	)
	if not confirm:
		_assault_confirm_target_id = target_pid
		_assault_confirm_msec = now_ms
		var atk_p := float(pre.get("attack_power", 0.0)) if pre else 0.0
		var def_p := float(pre.get("defense_power", 0.0)) if pre else 0.0
		var odds := float(pre.get("odds_attacker_win", 0.0)) if pre else 0.0
		var att_n := int(pre.get("attacker_divisions", 0)) if pre else 0
		var def_n := int(pre.get("defender_divisions", 0)) if pre else 0
		var can_ok := bool(can_pre.get("ok", false))
		var intel_note := "intel rough"
		if att_n <= 0:
			intel_note = "no friendly divs staged here — move units first"
		var prev_toast := "Assault PREVIEW · %s #%d (%d div) → %s #%d (%d div) · power %.0f vs %.0f · odds ~%.0f%% · %s · %s · Ctrl+click AGAIN to start a multi-day battle" % [
			p_tag, from_pid, att_n, str(target_province.owner_tag), target_pid, def_n,
			atk_p, def_p, odds,
			("ready" if can_ok else str(can_pre.get("reason", "blocked"))),
			intel_note,
		]
		_show_inspector_toast(prev_toast, 6.0)
		return true
	_assault_confirm_target_id = -1
	_assault_confirm_msec = 0

	# Guard: never run two executes back-to-back on the same frame path (hang on 2nd Ctrl+click).
	if _assault_execute_busy:
		_show_inspector_toast("Assault still resolving — wait a moment", 2.0, true)
		return true
	_assault_execute_busy = true
	var assault: Dictionary = {}
	# Multi-day open (HOI front) when start_land_battle exists; execute_province_assault is resolve-only.
	if BattleManager.has_method("start_land_battle"):
		assault = BattleManager.start_land_battle(p_tag, target_pid, from_pid)
	else:
		assault = BattleManager.execute_province_assault(p_tag, target_pid, from_pid)
	push_map_assault_marker(target_pid, "engage", 0.75)
	if bool(assault.get("opened", false)):
		_assault_execute_busy = false
		var bat: Dictionary = assault.get("battle", {}) as Dictionary
		var est := int(bat.get("est_days", 4))
		_sync_land_battle_bubbles()
		_play_map_sfx("confirm")
		_show_inspector_toast(
			"Battle opened · %s · est. %d days · unpause to fight · withdraw from unit card"
			% [target_province.name, est],
			5.5
		)
		return true
	if not bool(assault.get("success", false)):
		_assault_execute_busy = false
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

	# Capture/assault player feedback via pure flair helper (toast + sfx distinguishable from select/invest/HH).
	var cap_flair: Dictionary = _MapNextListHelpers.format_capture_assault_flair(
		target_province.name, atk, def, captured, outcome, winner
	)
	var cap_toast := str(cap_flair.get("toast", "Battle resolved"))
	if captured:
		cap_toast += " (def_bonus=%.0f%% used)" % ((s_def_b - 1.0) * 100.0)
	_show_inspector_toast(cap_toast, float(cap_flair.get("duration", 3.5)))
	_play_map_sfx(str(cap_flair.get("sfx", "map")))
	if provinces.has(target_pid):
		# Soft center without full inspector rebuild when possible (inspector can be heavy).
		call_deferred("_center_camera_on_province", target_pid, "soft")
	# Success-path busy-clear lives in deferred light UI only.
	var retreat_pid := int(result.get("retreat_province_id", -1))
	call_deferred("_assault_post_ui_light", target_pid, from_pid, retreat_pid)
	return true


## Capture/assault success: pid-only fill + pins. Busy clears here, not in the execute tail.
func _assault_post_ui_light(target_pid: int, from_pid: int = -1, retreat_pid: int = -1) -> void:
	var pids: Array = []
	for v in [target_pid, from_pid, retreat_pid]:
		var pid := int(v)
		if pid >= 0 and not pids.has(pid):
			pids.append(pid)
	_refresh_province_fill_pids(pids)
	_update_unit_icons_for_pids(pids)
	_assault_execute_busy = false


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
	var panel_open := info_panel != null and info_panel is CanvasItem and info_panel.visible
	var non_friendly := not _province_controlled_by(province, p_tag)
	# Inspector on enemy: keep Attack visible; disable with can_assault reason (strip Assault is OOB).
	if panel_open and non_friendly:
		_btn_attack.visible = true
		_btn_attack.disabled = not can_attack
		if can_attack:
			_btn_attack.text = "Attack from %s" % str(preview.get("from_province_name", "adjacent"))
			_btn_attack.tooltip_text = (
				"Launch assault on %s using %s.\nCtrl+click works from the map too."
				% [province.name, str(preview.get("division_name", preview.get("formation_id", "division")))]
			)
		else:
			var reason := str(preview.get("reason", "")).strip_edges()
			if reason.is_empty():
				reason = "no friendly divs staged here — move units first"
			_btn_attack.text = "Attack"
			_btn_attack.tooltip_text = reason
		return
	_btn_attack.visible = can_attack
	_btn_attack.disabled = false
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

	# Pass 21: multi-site bulk repair when 2+ damaged sites in province.
	var damaged_sites: Array = []
	for site_scan in sites:
		if site_scan != null and site_scan.has_method("is_damaged") and site_scan.is_damaged():
			damaged_sites.append(site_scan)
	if damaged_sites.size() >= 2:
		var bulk_row := HBoxContainer.new()
		bulk_row.add_theme_constant_override("separation", 6)
		_special_sites_container.add_child(bulk_row)
		var bulk_btn := Button.new()
		bulk_btn.text = "🛠 Repair all (%d sites)" % damaged_sites.size()
		bulk_btn.tooltip_text = "Repair every damaged special site in this province (−1 dmg each; engineers +1)."
		bulk_btn.custom_minimum_size = Vector2(160, 26)
		RetrowaveTheme.style_secondary_button(bulk_btn)
		bulk_btn.modulate = Color(1.05, 0.92, 0.55, 1.0)
		bulk_btn.pressed.connect(_on_repair_all_special_sites_pressed.bind(province.id))
		bulk_row.add_child(bulk_btn)
		var bulk_hint := Label.new()
		bulk_hint.text = "%d damaged" % damaged_sites.size()
		bulk_hint.add_theme_font_size_override("font_size", 10)
		bulk_hint.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
		bulk_row.add_child(bulk_hint)

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
			# Pass 20: stronger repair CTA + progress hint.
			var repair_btn := Button.new()
			var max_d := maxi(1, int(site.max_damage_level) if "max_damage_level" in site else 3)
			var dmg_lv := int(site.damage_level)
			repair_btn.text = "🛠 Repair (−1 dmg)"
			repair_btn.tooltip_text = (
				"Repair %s · damage %d/%d · %d steps to full.\nEngineers in province add +1 repair."
				% [str(site.id), dmg_lv, max_d, dmg_lv]
			)
			repair_btn.custom_minimum_size = Vector2(110, 26)
			RetrowaveTheme.style_secondary_button(repair_btn)
			repair_btn.modulate = Color(1.05, 0.9, 0.65, 1.0)
			repair_btn.pressed.connect(_on_repair_special_site_pressed.bind(province.id, site))
			row.add_child(repair_btn)
			var rp := ProgressBar.new()
			rp.min_value = 0.0
			rp.max_value = float(max_d)
			rp.value = float(max_d - dmg_lv)
			rp.show_percentage = false
			rp.custom_minimum_size = Vector2(56, 10)
			rp.tooltip_text = "Repair progress · %d remaining" % dmg_lv
			var rbg := StyleBoxFlat.new()
			rbg.bg_color = Color(0.12, 0.14, 0.18, 0.9)
			rbg.set_corner_radius_all(2)
			var rfg := StyleBoxFlat.new()
			rfg.bg_color = Color(0.45, 0.92, 0.7, 0.95)
			rfg.set_corner_radius_all(2)
			rp.add_theme_stylebox_override("background", rbg)
			rp.add_theme_stylebox_override("fill", rfg)
			row.add_child(rp)

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

		# Show key effects (live site + JSON definition extras for tooltip/readout polish)
		var effects_label := Label.new()
		var eff_parts: PackedStringArray = []
		var def_fx: Dictionary = {}
		if ssm != null and ssm.has_method("get_site_definition"):
			var sdef: Dictionary = ssm.get_site_definition(site.id)
			if sdef.has("name"):
				name_label.text = "%s %s (T%d)%s" % [state_icon, str(sdef["name"]), site.tier, dmg]
			def_fx = sdef.get("effects", {}) as Dictionary if sdef else {}
			if sdef.has("description"):
				name_label.tooltip_text = str(sdef["description"])
		var supply_b := float(site.supply_bonus)
		var trade_b := float(site.trade_capacity)
		if supply_b <= 0.0 and def_fx.has("supply_throughput_bonus"):
			supply_b = float(def_fx["supply_throughput_bonus"])
		if trade_b <= 0.0 and def_fx.has("trade_capacity"):
			trade_b = float(def_fx["trade_capacity"])
		if supply_b > 0:
			eff_parts.append("+%d Supply" % int(supply_b))
		if trade_b > 0:
			eff_parts.append("+%d Trade" % int(trade_b))
		for k in def_fx.keys():
			var key := str(k)
			if key in ["supply_throughput_bonus", "trade_capacity"]:
				continue
			var val = def_fx[k]
			if (val is float or val is int) and float(val) > 0.0:
				eff_parts.append("+%d %s" % [int(val), key.replace("_", " ").capitalize()])
		effects_label.text = " · ".join(eff_parts) if not eff_parts.is_empty() else ""
		effects_label.tooltip_text = effects_label.text
		effects_label.add_theme_font_size_override("font_size", 10)
		effects_label.modulate = Color(0.7, 0.92, 0.8)
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

	var before := int(site.damage_level)
	site.repair_damage(repair_amount)
	var after := int(site.damage_level)

	# Notify systems
	if typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(province_id, "special_site")

	# Pass 20: live ring refresh after site repair.
	call_deferred("_refresh_feature_progress_rings")

	# Refresh the panel
	if provinces.has(province_id):
		show_info_panel(provinces[province_id])

	print("Repaired special site %s in province %d (amount %d)" % [site.id, province_id, repair_amount])
	if typeof(DebugOverlay) != TYPE_NIL:
		var done := not site.is_damaged()
		DebugOverlay.toast_map_debug(
			"Repaired %s · dmg %d→%d%s" % [str(site.id), before, after, " · fully restored" if done else ""]
		)


## Pass 21: repair every damaged special site in the province.
func _on_repair_all_special_sites_pressed(province_id: int) -> void:
	if not provinces.has(province_id):
		return
	var province: Province = provinces[province_id] as Province
	if province == null or province.special_sites.is_empty():
		return
	var repair_amount := 1
	var mgr = _get_infra_manager()
	if mgr != null and mgr.has_method("get_engineer_brigades_in_province"):
		var engineers: float = float(mgr.get_engineer_brigades_in_province(province_id))
		if engineers > 0.5:
			repair_amount += 1
	var repaired := 0
	var remaining_dmg := 0
	for site in province.special_sites:
		if site == null or not site.has_method("is_damaged") or not site.is_damaged():
			continue
		site.repair_damage(repair_amount)
		repaired += 1
		if site.is_damaged():
			remaining_dmg += int(site.damage_level)
	if repaired <= 0:
		if typeof(DebugOverlay) != TYPE_NIL:
			DebugOverlay.toast_map_debug("No damaged sites to repair")
		return
	if typeof(MapManager) != TYPE_NIL:
		MapManager.notify_province_changed(province_id, "special_site")
	call_deferred("_refresh_feature_progress_rings")
	show_info_panel(province)
	if typeof(DebugOverlay) != TYPE_NIL:
		var tail := " · all clear"
		if remaining_dmg > 0:
			tail = " · %d dmg left" % remaining_dmg
		DebugOverlay.toast_map_debug(
			"Bulk repair · %d site(s) (−%d each)%s" % [repaired, repair_amount, tail]
		)


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
	var formations: Array = SupplyManager.get_engineer_capable_formations(country_tag)
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
		var formations: Array = SupplyManager.get_engineer_capable_formations(country_tag)
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


func _setup_occupation_layer() -> void:
	if not show_occupation_overlay or container == null:
		remove_overlay_layer("OccupationOverlay")
		_occupation_layer = null
		return
	if _occupation_layer == null or not is_instance_valid(_occupation_layer):
		_occupation_layer = _OccupationOverlayLayerScr.new()
	var centroids := province_centroids
	var provs := provinces
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("get_all_centroids"):
			centroids = MapManager.get_all_centroids()
		if MapManager.has_method("get_all_provinces"):
			provs = MapManager.get_all_provinces()
	# Large boards: force safe centroid fills in the layer (avoids triangulation spam).
	if provinces.size() >= 800 and _occupation_layer.get("prefer_centroid_fills_on_large_boards") != null:
		_occupation_layer.prefer_centroid_fills_on_large_boards = true
		_occupation_layer.max_fill_polys = mini(int(_occupation_layer.max_fill_polys), 48)
	_occupation_layer.setup_with_map(container, centroids, provs, geometry)
	add_overlay_layer("OccupationOverlay", _occupation_layer, 0)


func setup_demo_occupation_overlay() -> void:
	_setup_occupation_layer()


func set_occupation_overlay_visible(on: bool) -> void:
	show_occupation_overlay = on
	_setup_occupation_layer()
	if _occupation_layer != null and is_instance_valid(_occupation_layer):
		_occupation_layer.enabled = on
		_occupation_layer.refresh()


func toggle_occupation_overlay() -> bool:
	set_occupation_overlay_visible(not show_occupation_overlay)
	return show_occupation_overlay


func get_occupation_overlay_stats() -> Dictionary:
	if _occupation_layer != null and is_instance_valid(_occupation_layer) and _occupation_layer.has_method("get_draw_stats"):
		return _occupation_layer.get_draw_stats()
	return {"draw_n": 0, "icon_n": 0, "enabled": false}


func _ensure_perf() -> void:
	if _perf == null:
		_perf = _MapRendererPerfScr.new()
	var want: bool = enable_perf_profile or (_perf.env_wants_profile() if _perf.has_method("env_wants_profile") else OS.get_environment("EOA_MAP_PERF") == "1")
	_perf.set_enabled(want)
	enable_perf_profile = want


func set_perf_profile_enabled(on: bool) -> void:
	enable_perf_profile = on
	_ensure_perf()
	if _perf != null:
		_perf.set_enabled(on)


func dump_perf_profile() -> Dictionary:
	_ensure_perf()
	if _perf == null:
		return {"ok": false, "empty": true}
	_perf.set_enabled(true)
	enable_perf_profile = true
	var rep: Dictionary = _perf.force_report()
	# M5: also export session samples for pure harness ingest
	if _perf.has_method("export_session_json"):
		var n_prov := provinces.size() if provinces is Dictionary else 0
		var land_n := 0
		if provinces is Dictionary:
			for pid in provinces.keys():
				var p: Province = provinces[pid] as Province
				if p != null and not bool(p.is_sea):
					land_n += 1
		_perf.pilot_tag = "world_accurate" if n_prov >= 7000 else ("world_full" if n_prov >= 2000 else "custom")
		_perf.measure_kind = "renderer_frame"
		var exp: Dictionary = _perf.export_session_json(
			"/tmp/eoa-map-perf-world-accurate.json", n_prov, land_n
		)
		rep["m5_export"] = exp
		# Also write under project output when possible (absolute path from res://)
		var repo_path := ProjectSettings.globalize_path("res://tools/map_generation/output/map_perf_world_accurate_samples.json")
		if not repo_path.is_empty():
			_perf.export_session_json(repo_path, n_prov, land_n)
	return rep


func get_perf_last_report() -> Dictionary:
	if _perf == null:
		return {}
	return _perf.get_last_report()


## M5: export accumulated frame samples (mean/p50/p95) for map_perf_fps_harness_product.
func export_map_perf_session(path: String = "/tmp/eoa-map-perf-world-accurate.json") -> Dictionary:
	_ensure_perf()
	if _perf == null or not _perf.has_method("export_session_json"):
		return {"ok": false, "empty": true, "path": path}
	_perf.set_enabled(true)
	var n_prov := provinces.size() if provinces is Dictionary else 0
	var land_n := 0
	if provinces is Dictionary:
		for pid in provinces.keys():
			var p: Province = provinces[pid] as Province
			if p != null and not bool(p.is_sea):
				land_n += 1
	_perf.pilot_tag = "world_accurate" if n_prov >= 7000 else ("world_full" if n_prov >= 2000 else "custom")
	_perf.measure_kind = "renderer_frame"
	return _perf.export_session_json(path, n_prov, land_n)



func _setup_strategic_flow_layer() -> void:
	if not show_strategic_flow_overlay or container == null:
		remove_overlay_layer("StrategicFlowOverlay")
		_strategic_flow_layer = null
		return
	if _strategic_flow_layer == null or not is_instance_valid(_strategic_flow_layer):
		_strategic_flow_layer = _StrategicFlowOverlayLayerScr.new()
	var centroids := province_centroids
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_centroids"):
		centroids = MapManager.get_all_centroids()
	var pc := provinces.size()
	if _strategic_flow_layer.has_method("setup"):
		_strategic_flow_layer.setup(centroids)
	if "max_routes" in _strategic_flow_layer:
		_strategic_flow_layer.max_routes = MapZoomLOD.max_flow_routes_for_board(pc)
	if "show_equipment_flows" in _strategic_flow_layer:
		_strategic_flow_layer.show_equipment_flows = true
	if _strategic_flow_layer.has_method("set_equipment_flow_glyphs_enabled"):
		_strategic_flow_layer.set_equipment_flow_glyphs_enabled(show_equipment_flow_glyphs)
	elif "equipment_flow_glyphs_enabled" in _strategic_flow_layer:
		_strategic_flow_layer.equipment_flow_glyphs_enabled = show_equipment_flow_glyphs
	_sync_strategic_flow_lod(_map_lod_tier)
	add_overlay_layer("StrategicFlowOverlay", _strategic_flow_layer, 4)


func _sync_strategic_flow_lod(tier: int) -> void:
	if _strategic_flow_layer == null or not is_instance_valid(_strategic_flow_layer):
		return
	if _strategic_flow_layer.has_method("set_zoom_tier"):
		_strategic_flow_layer.set_zoom_tier(tier)
	elif "zoom_tier" in _strategic_flow_layer:
		_strategic_flow_layer.zoom_tier = tier
	var pc := provinces.size()
	if "max_equipment_glyphs" in _strategic_flow_layer:
		_strategic_flow_layer.max_equipment_glyphs = MapZoomLODScript.max_equipment_flow_glyphs_for_board(tier, pc)
	if _strategic_flow_layer.has_method("refresh"):
		_strategic_flow_layer.refresh()


func toggle_strategic_flow_overlay() -> bool:
	show_strategic_flow_overlay = not show_strategic_flow_overlay
	_setup_strategic_flow_layer()
	return show_strategic_flow_overlay


func toggle_equipment_flow_glyphs() -> bool:
	show_equipment_flow_glyphs = not show_equipment_flow_glyphs
	if _strategic_flow_layer != null and is_instance_valid(_strategic_flow_layer):
		if _strategic_flow_layer.has_method("set_equipment_flow_glyphs_enabled"):
			_strategic_flow_layer.set_equipment_flow_glyphs_enabled(show_equipment_flow_glyphs)
		elif "equipment_flow_glyphs_enabled" in _strategic_flow_layer:
			_strategic_flow_layer.equipment_flow_glyphs_enabled = show_equipment_flow_glyphs
		if _strategic_flow_layer.has_method("refresh"):
			_strategic_flow_layer.refresh()
	elif show_strategic_flow_overlay:
		_setup_strategic_flow_layer()
	return show_equipment_flow_glyphs


## Force EquipmentFlow glyphs ON and master flow overlay visible (first-session war path).
func ensure_equipment_flow_glyphs_on() -> Dictionary:
	show_equipment_flow_glyphs = true
	if not show_strategic_flow_overlay:
		show_strategic_flow_overlay = true
	_setup_strategic_flow_layer()
	if _strategic_flow_layer != null and is_instance_valid(_strategic_flow_layer):
		if _strategic_flow_layer.has_method("set_equipment_flow_glyphs_enabled"):
			_strategic_flow_layer.set_equipment_flow_glyphs_enabled(true)
		elif "equipment_flow_glyphs_enabled" in _strategic_flow_layer:
			_strategic_flow_layer.equipment_flow_glyphs_enabled = true
		if _strategic_flow_layer.has_method("refresh"):
			_strategic_flow_layer.refresh()
	return get_equipment_flow_glyph_query()


## First-session help toast (? / Shift+/) — mirrors first_session_hotkeys_product.
func _toast_first_session_help() -> void:
	var toast := (
		"Help · B Fronts · Shift+I WarLoop · I flow · G corridor · Ctrl+click assault · "
		+ "F1–F9 mapmodes · Ctrl+S save · Ctrl+L load · Home Europe"
	)
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(toast)
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(toast, 6.0)


## First-session assault surface toast — first_session_assault_surface_product.
func toast_assault_surface(
	from_id: int = -1,
	to_id: int = -1,
	defender_tag: String = ""
) -> void:
	var tag := ""
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		tag = str(LeaderManager.get_player_country_tag()).to_upper()
	if tag.is_empty():
		tag = "GER"
	var def_t := defender_tag.strip_edges().to_upper()
	var toast: String
	if from_id > 0 and to_id > 0:
		toast = "Assault ready · %s #%d → %s #%d · Ctrl+click enemy or strip Assault" % [
			tag, from_id, def_t if not def_t.is_empty() else "?", to_id
		]
	else:
		toast = "Assault · select friendly formation · B fronts · Ctrl+click enemy adj · strip Assault"
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(toast)
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(toast, 5.0)


## Stream 2: first-session war/command path — flow + live fronts + assault brief (not F10-only).
## Hotkey Shift+I · toolbar WarLoop. Returns {ok, toast, flow_on, best_province_id, fronts}.
func show_first_session_war_path(country_tag: String = "") -> Dictionary:
	var tag := country_tag.strip_edges().to_upper()
	if tag.is_empty() and typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		tag = str(LeaderManager.get_player_country_tag()).to_upper()
	if tag.is_empty():
		tag = "GER"
	var flow_q: Dictionary = ensure_equipment_flow_glyphs_on()
	var fronts_res: Dictionary = {}
	if has_method("show_live_border_fronts"):
		fronts_res = show_live_border_fronts(tag, 6)
	var best := int(fronts_res.get("best_province_id", -1))
	var n_fronts := int(fronts_res.get("count", 0))
	var toast := "WarLoop · %s · flow ON · fronts %d · target #%s · B cycle · Ctrl+click Assault · G corridor" % [
		tag,
		n_fronts,
		str(best) if best > 0 else "?",
	]
	var result := {
		"ok": true,
		"empty": n_fronts <= 0,
		"country_tag": tag,
		"flow_on": true,
		"flow_query": flow_q,
		"fronts": fronts_res.get("targets", []),
		"front_count": n_fronts,
		"best_province_id": best,
		"toast": toast,
		"action": "show_first_session_war_path",
		"steps": [
			"Select friendly formation province",
			"B / Fronts → enemy border",
			"Inspector Attack or Ctrl+click enemy",
			"I toggles EquipmentFlow glyphs",
			"G capital→front corridor",
		],
	}
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug(toast)
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast(toast, 5.0)
	if _map_mode_toolbar != null and _map_mode_toolbar.has_method("set_fronts_legend"):
		var lines: PackedStringArray = PackedStringArray()
		lines.append(toast)
		lines.append("WarLoop: B fronts · I flow · G corridor · Ctrl+click assault")
		_map_mode_toolbar.call("set_fronts_legend", "\n".join(lines))
	return result


func get_equipment_flow_glyph_query() -> Dictionary:
	if _strategic_flow_layer != null and is_instance_valid(_strategic_flow_layer) \
			and _strategic_flow_layer.has_method("get_equipment_flow_glyph_query"):
		var q: Dictionary = _strategic_flow_layer.get_equipment_flow_glyph_query()
		q["renderer_toggle"] = show_equipment_flow_glyphs
		q["flow_overlay_on"] = show_strategic_flow_overlay
		return q
	# Offline query without live layer (duals / headless)
	var pol: Dictionary = MapZoomLODScript.equipment_flow_glyph_policy(_map_lod_tier) as Dictionary
	return {
		"ok": true,
		"equipment_flow_glyphs_enabled": show_equipment_flow_glyphs,
		"visible": show_equipment_flow_glyphs and show_strategic_flow_overlay and bool(pol.get("show", true)),
		"zoom_tier": _map_lod_tier,
		"tier_name": MapZoomLODScript.tier_name(_map_lod_tier),
		"lod_policy": pol,
		"renderer_toggle": show_equipment_flow_glyphs,
		"flow_overlay_on": show_strategic_flow_overlay,
		"layer_live": false,
		"model": "equipment_flow_compact_ledger",
	}


func _setup_land_battle_bubble_layer() -> void:
	const BUBBLE_SCR := "res://scripts/map/LandBattleBubbleLayer.gd"
	if not ResourceLoader.exists(BUBBLE_SCR):
		return
	if _land_battle_bubble_layer == null or not is_instance_valid(_land_battle_bubble_layer):
		var scr: Script = load(BUBBLE_SCR) as Script
		if scr == null:
			return
		_land_battle_bubble_layer = scr.new() as Node2D
		if _land_battle_bubble_layer == null:
			return
		_land_battle_bubble_layer.name = "LandBattleBubbleLayer"
		_land_battle_bubble_layer.z_index = 25
		add_child(_land_battle_bubble_layer)
	if _land_battle_bubble_layer.has_method("setup"):
		_land_battle_bubble_layer.call("setup", province_centroids)
	_sync_land_battle_bubbles()


func _refresh_next_hook_chip() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	if _next_hook_chip == null or not is_instance_valid(_next_hook_chip):
		_next_hook_chip = Button.new()
		_next_hook_chip.name = "PlayNextHookChip"
		_next_hook_chip.focus_mode = Control.FOCUS_NONE
		_next_hook_chip.z_index = 80
		_next_hook_chip.position = Vector2(18, 52)
		_next_hook_chip.custom_minimum_size = Vector2(420, 28)
		if typeof(RetrowaveTheme) != TYPE_NIL:
			RetrowaveTheme.style_secondary_button(_next_hook_chip)
		ui.add_child(_next_hook_chip)
		_next_hook_chip.pressed.connect(func() -> void:
			if typeof(PlayNextHook) != TYPE_NIL and PlayNextHook.has_method("apply"):
				var out: Dictionary = PlayNextHook.apply()
				_show_inspector_toast(str(out.get("summary", "Next")), 3.5)
				_refresh_next_hook_chip()
		)
	var rec: Dictionary = {}
	if typeof(PlayNextHook) != TYPE_NIL and PlayNextHook.has_method("recommend"):
		rec = PlayNextHook.recommend()
	var hint := str(rec.get("hint", "Unpause a day"))
	_next_hook_chip.text = "NEXT · %s" % str(rec.get("label", "Unpause a day"))
	_next_hook_chip.tooltip_text = hint


func _sync_land_battle_bubbles() -> int:
	if _land_battle_bubble_layer == null or not is_instance_valid(_land_battle_bubble_layer):
		_setup_land_battle_bubble_layer()
	if _land_battle_bubble_layer == null or not _land_battle_bubble_layer.has_method("set_battles"):
		return 0
	var battles: Array = []
	if typeof(BattleManager) != TYPE_NIL and BattleManager.has_method("get_open_land_battles"):
		battles = BattleManager.get_open_land_battles()
	_land_battle_bubble_layer.call("set_battles", battles)
	_refresh_next_hook_chip()
	return battles.size()


func _setup_battle_indicator_layer() -> void:
	if not show_battle_indicator_overlay or container == null:
		remove_overlay_layer("BattleIndicatorOverlay")
		_battle_indicator_layer = null
		return
	if _battle_indicator_layer == null or not is_instance_valid(_battle_indicator_layer):
		_battle_indicator_layer = _BattleIndicatorOverlayLayerScr.new()
	var centroids := province_centroids
	var provs := provinces
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("get_all_centroids"):
			centroids = MapManager.get_all_centroids()
		if MapManager.has_method("get_all_provinces"):
			provs = MapManager.get_all_provinces()
	_battle_indicator_layer.setup_with_map(container, centroids, provs)
	if "max_markers" in _battle_indicator_layer:
		_battle_indicator_layer.max_markers = MapZoomLOD.max_battle_markers_for_board(provs.size())
	add_overlay_layer("BattleIndicatorOverlay", _battle_indicator_layer, 5)


func toggle_battle_indicator_overlay() -> bool:
	show_battle_indicator_overlay = not show_battle_indicator_overlay
	_setup_battle_indicator_layer()
	return show_battle_indicator_overlay


func push_map_assault_marker(province_id: int, phase: String = "engage", strength: float = 0.7) -> void:
	if _battle_indicator_layer != null and is_instance_valid(_battle_indicator_layer) and _battle_indicator_layer.has_method("push_assault_marker"):
		_battle_indicator_layer.push_assault_marker(province_id, phase, strength)


func _setup_domain_ops_layer() -> void:
	if not show_domain_ops_overlay or container == null:
		remove_overlay_layer("DomainOpsOverlay")
		_domain_ops_layer = null
		return
	if _domain_ops_layer == null or not is_instance_valid(_domain_ops_layer):
		_domain_ops_layer = _DomainOpsOverlayLayerScr.new()
	var centroids := province_centroids
	var provs := provinces
	if typeof(MapManager) != TYPE_NIL:
		if MapManager.has_method("get_all_centroids"):
			centroids = MapManager.get_all_centroids()
		if MapManager.has_method("get_all_provinces"):
			provs = MapManager.get_all_provinces()
	_domain_ops_layer.setup(centroids, provs)
	if "max_icons" in _domain_ops_layer:
		_domain_ops_layer.max_icons = MapZoomLOD.max_overlay_icons_for_board(provs.size())
	add_overlay_layer("DomainOpsOverlay", _domain_ops_layer, 6)


func toggle_domain_ops_overlay() -> bool:
	show_domain_ops_overlay = not show_domain_ops_overlay
	_setup_domain_ops_layer()
	return show_domain_ops_overlay


func _setup_leader_station_layer() -> void:
	if not show_leader_station_overlay or container == null:
		remove_overlay_layer("LeaderStationOverlay")
		_leader_station_layer = null
		return
	if _leader_station_layer == null or not is_instance_valid(_leader_station_layer):
		_leader_station_layer = _LeaderStationOverlayLayerScr.new()
	var centroids := province_centroids
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_centroids"):
		centroids = MapManager.get_all_centroids()
	_leader_station_layer.setup(centroids)
	add_overlay_layer("LeaderStationOverlay", _leader_station_layer, 7)


func toggle_leader_station_overlay() -> bool:
	show_leader_station_overlay = not show_leader_station_overlay
	_setup_leader_station_layer()
	return show_leader_station_overlay


func _setup_construction_progress_layer() -> void:
	if not show_construction_progress_overlay or container == null:
		remove_overlay_layer("ConstructionProgressOverlay")
		_construction_progress_layer = null
		return
	if _construction_progress_layer == null or not is_instance_valid(_construction_progress_layer):
		_construction_progress_layer = _ConstructionProgressOverlayLayerScr.new()
	var centroids := province_centroids
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_all_centroids"):
		centroids = MapManager.get_all_centroids()
	_construction_progress_layer.setup(centroids)
	add_overlay_layer("ConstructionProgressOverlay", _construction_progress_layer, 3)


func toggle_construction_progress_overlay() -> bool:
	show_construction_progress_overlay = not show_construction_progress_overlay
	_setup_construction_progress_layer()
	return show_construction_progress_overlay


func get_phase23_overlay_stats() -> Dictionary:
	return {
		"occupation": get_occupation_overlay_stats(),
		"flow": _strategic_flow_layer.get_draw_stats() if _strategic_flow_layer and _strategic_flow_layer.has_method("get_draw_stats") else {},
		"battle": _battle_indicator_layer.get_draw_stats() if _battle_indicator_layer and _battle_indicator_layer.has_method("get_draw_stats") else {},
		"domain": _domain_ops_layer.get_draw_stats() if _domain_ops_layer and _domain_ops_layer.has_method("get_draw_stats") else {},
		"leader": _leader_station_layer.get_draw_stats() if _leader_station_layer and _leader_station_layer.has_method("get_draw_stats") else {},
		"construction": _construction_progress_layer.get_draw_stats() if _construction_progress_layer and _construction_progress_layer.has_method("get_draw_stats") else {},
		"lower_vert": MapZoomLOD.use_lower_vert_fallback(MapZoomLOD.tier_for_zoom(MapZoomLOD.read_camera_zoom(get_viewport())), provinces.size()),
		"target_frame_ms": MapZoomLOD.target_frame_ms_mid_hardware(),
	}


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


## Esc / Close affordance: dismiss overlays that trap playtest (supply legend, tech, inspector).
func _dismiss_map_overlays_esc() -> bool:
	var dismissed := false
	if supply_mode:
		_toggle_supply_overlay()
		_show_map_layer_toast("Supply legend closed (Esc)")
		dismissed = true
	# Unit detail card (map navy/armor icons) closes first.
	var ui_layer := get_node_or_null("UI") as CanvasLayer
	if ui_layer != null:
		var unit_pop := ui_layer.get_node_or_null("UnitDetailPopup")
		if unit_pop != null:
			unit_pop.queue_free()
			_show_map_layer_toast("Unit detail closed (Esc)")
			return true
	var tree := get_tree()
	if tree:
		for screen_name in ["TechnologyScreen", "AgentAssignmentScreen", "NationalSpiritsScreen", "MainMenu"]:
			var n := tree.root.get_node_or_null(screen_name)
			if n == null and tree.current_scene:
				var ui := tree.current_scene.get_node_or_null("UILayer/%s" % screen_name)
				n = ui
			if n != null:
				if n is Window:
					(n as Window).hide()
				n.queue_free()
				_show_map_layer_toast("%s closed (Esc)" % screen_name)
				dismissed = true
		# Also free screens parented under UILayer
		if tree.current_scene:
			var layer := tree.current_scene.get_node_or_null("UILayer")
			if layer:
				for child in layer.get_children():
					var cn := str(child.name)
					if cn in ["TechnologyScreen", "AgentAssignmentScreen", "NationalSpiritsScreen"]:
						child.queue_free()
						dismissed = true
	if info_panel != null and info_panel is CanvasItem and (info_panel as CanvasItem).visible:
		if info_panel.has_method("hide"):
			info_panel.hide()
		elif info_panel is CanvasItem:
			(info_panel as CanvasItem).visible = false
		dismissed = true
		_show_map_layer_toast("Inspector closed (Esc)")
	if not dismissed:
		_show_map_layer_toast("Nothing to close — L toggles supply legend; Tech toggles tech panel")
	return dismissed


func _toggle_supply_overlay() -> void:
	var sm := _supply_manager()
	if sm == null:
		return
	sm.toggle_overlay()
	supply_mode = sm.overlay_visible
	if supply_map_layer:
		supply_map_layer.visible = supply_mode
		# G playtest: one corridor highlight only — never bulk route spiderweb.
		supply_map_layer.corridor_focus_only = supply_mode
	# Roads stay OFF on G (corridor via SupplyMapLayer highlight + optional path edges).
	var ol_infra := get_overlay_layer("InfrastructureOverlayLayer")
	if ol_infra != null:
		if ol_infra.has_method("set_show_roads"):
			ol_infra.call("set_show_roads", false)
		if ol_infra.has_method("set_show_rails"):
			ol_infra.call("set_show_rails", false)
		if not supply_mode and ol_infra.has_method("clear_supply_corridor_path"):
			ol_infra.call("clear_supply_corridor_path")
		if ol_infra.has_method("queue_redraw"):
			ol_infra.queue_redraw()
	if supply_mode:
		_setup_supply_layer()
		# Auto capital→selected (or capital→front) corridor — single path, not mesh.
		var corr := highlight_corridor_capital_to_selected()
		if not bool(corr.get("ok", false)) and selected_province_id < 0:
			# No selection: toast only; click a province then G again / click while G is on.
			if typeof(DebugOverlay) != TYPE_NIL:
				DebugOverlay.toast_map_debug("Supply G · select a province then G for capital→front corridor")
			_show_inspector_toast("Supply corridor · click a front province (G) · sea if no land transit rights", 4.0)
		_update_supply_overlay_legend()
	else:
		_end_supply_reroute()
		if supply_map_layer != null and supply_map_layer.has_method("clear_route_highlight"):
			supply_map_layer.call("clear_route_highlight")
	# Skip full fill recolor on toggle — was expensive; tint handles on next mapmode.
	_refresh_supply_highlights()
	_update_supply_overlay_legend()
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
	# M4: pulse corridor polyline for capital/hub → selected front (player-visible path)
	if plan != null and plan.path_length() >= 2:
		var path: Array = []
		for pid_v in plan.province_path:
			path.append(int(pid_v))
		highlight_supply_route_path(path, 8.0)
	elif plan != null and plan.source_province_id > 0 and plan.target_province_id > 0:
		# Fallback adjacency corridor when multimodal plan empty
		var tag := str(sm.player_tag) if "player_tag" in sm else ""
		highlight_supply_corridor(plan.source_province_id, plan.target_province_id, 8.0, tag)


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


## Recolor only listed provinces (capture / assault). Never the accurate-board full scan.
func _refresh_province_fill_pids(pids: Array) -> void:
	if pids.is_empty():
		return
	if container != null:
		_zoom_fill_characterization_scale = absf(container.scale.x)
	var seen: Dictionary = {}
	for v in pids:
		var pid := int(v)
		if pid < 0 or seen.has(pid):
			continue
		seen[pid] = true
		if not province_nodes.has(pid) or not provinces.has(pid):
			continue
		var node: Variant = province_nodes[pid]
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		var province: Province = provinces[pid] as Province
		var poly: Polygon2D = _get_province_polygon(node as Node2D)
		if poly == null:
			continue
		var col := _get_province_color(province)
		if supply_mode:
			var fill := ProvinceInsight.depot_fill_ratio(pid)
			if fill >= 0.0:
				col = col.lerp(_supply_depot_tint_color(fill), _supply_depot_mix_amount())
		col = _apply_agent_pressure_base_tint(col, province)
		if typeof(GameData) != TYPE_NIL and GameData.has_method("has_active_riot") and GameData.has_active_riot(pid):
			col = col.lerp(Color(0.85, 0.25, 0.25, 0.55), 0.40)
		poly.color = col


func _refresh_province_fill_colors(refresh_all: bool = false) -> void:
	if container != null:
		_zoom_fill_characterization_scale = absf(container.scale.x)
	# Accurate board (~3.5k): ALWAYS paint every province. Lazy "interesting" cull (~180 pids)
	# left NOR/SWE/FIN/UK-north/Vestjylland unpainted until F2 forced a full repaint.
	var board_n := maxi(provinces.size(), province_nodes.size())
	var use_all := (
		refresh_all
		or debug_tint_mode != ""
		or current_map_mode != "political"
		or board_n >= MapZoomLODScript.ACCURATE_BOARD_CULL_THRESHOLD
	)
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
	var board_n := maxi(provinces.size(), province_nodes.size())
	# Cap set size — including all major-owned pids on world_full (ENG alone ~1275) made
	# "lazy" fill + viewport cull touch almost the whole board every pan frame.
	var hard_cap := 180 if board_n >= 800 else 600
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_provinces_with_active_riots"):
		for pid in GameData.get_provinces_with_active_riots():
			ints[int(pid)] = true
			if ints.size() >= hard_cap:
				return ints
	# Player tag provinces (priority)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_player_tag"):
		var ptag = MapManager.get_player_tag()
		if ptag and MapManager.has_method("get_provinces_by_owner"):
			for pp in MapManager.get_provinces_by_owner(ptag):
				ints[int(pp)] = true
				if ints.size() >= hard_cap:
					return ints
	# Sparse sample of major ownership (not full country dumps)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_provinces_by_owner"):
		for mt in ["GER", "FRA", "ENG", "SOV", "USA", "ITA", "JAP"]:
			var owned: Array = MapManager.get_provinces_by_owner(mt)
			var step := maxi(1, owned.size() / 12)
			var i := 0
			while i < owned.size():
				ints[int(owned[i])] = true
				if ints.size() >= hard_cap:
					return ints
				i += step
	if selected_province_id >= 0:
		ints[selected_province_id] = true
	if _hover_province != null:
		ints[_hover_province.id] = true
	if ints.is_empty() and board_n < 800:
		for pid in province_nodes.keys():
			ints[int(pid)] = true
	return ints


## Prefer world-class retrowave unit chips when available; fall back to nato/ww2|modern paths.
func _prefer_retrowave_unit_icon(tex_path: String) -> String:
	var p := tex_path.strip_edges()
	if p.is_empty():
		return p
	# Already a retrowave path (e.g. frigate).
	if p.begins_with("res://assets/graphics/units/retrowave/") and ResourceLoader.exists(p):
		return p
	var file := p.get_file()  # e.g. infantry_32.png
	# Map cruiser nato path → retrowave cruiser (file may not exist under nato/cruiser).
	if "battleship" in file:
		var bb := "res://assets/graphics/units/retrowave/battleship_32.png"
		if ResourceLoader.exists(bb):
			return bb
	if "cruiser" in file:
		var cru := "res://assets/graphics/units/retrowave/cruiser_32.png"
		if ResourceLoader.exists(cru):
			return cru
	if "frigate" in file:
		var fri := "res://assets/graphics/units/retrowave/frigate_32.png"
		if ResourceLoader.exists(fri):
			return fri
	var rw := "res://assets/graphics/units/retrowave/" + file
	if ResourceLoader.exists(rw):
		return rw
	# Try 32 if path was 64 and vice versa
	if file.ends_with("_64.png"):
		var rw32 := "res://assets/graphics/units/retrowave/" + file.replace("_64.png", "_32.png")
		if ResourceLoader.exists(rw32):
			return rw32
	elif file.ends_with("_32.png"):
		var rw64 := "res://assets/graphics/units/retrowave/" + file.replace("_32.png", "_64.png")
		if ResourceLoader.exists(rw64):
			return rw64
	return p


## Pass 7: unit counter world scale vs camera zoom (screen-stable-ish size).
func _unit_counter_scale_for_zoom(z_override: float = -1.0) -> float:
	var z := z_override
	if z < 0.0:
		var cam := get_viewport().get_camera_2d() if get_viewport() else null
		z = 1.0
		if cam:
			z = maxf(cam.zoom.x, cam.zoom.y)
		elif container:
			z = absf(container.scale.x)
	# zoom high = close-up → larger counters; zoom low = compact but still readable (org/str bars).
	var t := clampf((z - 0.35) / 2.2, 0.0, 1.0)
	return lerpf(0.72, 1.15, t)


func _sync_unit_counter_scales(z: float = -1.0) -> void:
	if _demo_unit_icon_pids.is_empty():
		return
	var s := _unit_counter_scale_for_zoom(z)
	var sv := Vector2(s, s)
	for id_v in _demo_unit_icon_pids:
		var id := int(id_v)
		if not province_nodes.has(id):
			continue
		var node: Node2D = province_nodes[id] as Node2D
		if node == null:
			continue
		for c in node.get_children():
			if c is Node2D and str(c.name).begins_with("DemoUnitIcon_"):
				(c as Node2D).scale = sv


func _unit_counters_want_visible(z: float = -1.0) -> bool:
	var zz := z
	if zz < 0.0:
		zz = _get_camera_zoom() if has_method("_get_camera_zoom") else 1.0
	var tier: int = MapZoomLODScript.tier_for_zoom(zz)
	return MapZoomLODScript.show_unit_counters(tier, show_unit_counters)


func _sync_unit_counter_visibility(z: float = -1.0) -> void:
	if _demo_unit_icon_pids.is_empty():
		return
	var vis := _unit_counters_want_visible(z)
	for id_v in _demo_unit_icon_pids:
		var id := int(id_v)
		if not province_nodes.has(id):
			continue
		var node: Node2D = province_nodes[id] as Node2D
		if node == null:
			continue
		for c in node.get_children():
			if c is Node2D and str(c.name).begins_with("DemoUnitIcon_"):
				(c as Node2D).visible = vis


func toggle_unit_counters() -> bool:
	show_unit_counters = not show_unit_counters
	_sync_unit_counter_visibility()
	var z := _get_camera_zoom() if has_method("_get_camera_zoom") else 1.0
	var shown := _unit_counters_want_visible(z)
	var msg := "Unit counters OFF (master)" if not show_unit_counters else (
		"Unit counters ON · visible at this zoom" if shown else "Unit counters ON · hidden (Shift+U)"
	)
	if has_method("_show_map_layer_toast"):
		_show_map_layer_toast(msg)
	else:
		print("MapRenderer: ", msg)
	return show_unit_counters


## Nation-color frame around map unit counters (keeps retrowave chip colors intact).
func _make_unit_nation_frame(col: Color) -> Node2D:
	var root := Node2D.new()
	root.name = "NationFrame"
	var s := 17.0
	var pts := PackedVector2Array([
		Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s), Vector2(-s, -s),
	])
	var glow := Line2D.new()
	glow.name = "Glow"
	glow.width = 4.5
	glow.default_color = Color(col.r, col.g, col.b, 0.32)
	glow.joint_mode = Line2D.LINE_JOINT_ROUND
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow.points = pts
	root.add_child(glow)
	var line := Line2D.new()
	line.name = "Frame"
	line.width = 1.8
	line.default_color = Color(col.r, col.g, col.b, 0.95)
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.points = pts
	root.add_child(line)
	return root


## HOI-style nation color plate behind the NATO glyph (readable at compact zoom).
func _make_unit_nation_plate(col: Color) -> ColorRect:
	var plate := ColorRect.new()
	plate.name = "NationPlate"
	plate.size = Vector2(40, 34)
	plate.position = Vector2(-20, -16)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.color = Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.92)
	return plate


## Org (green) + strength (amber) bars on the chip itself.
func _make_unit_stat_bars(org_v: float, str_v: float) -> Node2D:
	var root := Node2D.new()
	root.name = "StatBars"
	root.position = Vector2(-20, 18)
	var org_c := clampf(org_v, 0.0, 1.0)
	var str_c := clampf(str_v, 0.0, 1.0)
	var bg := ColorRect.new()
	bg.name = "BarBg"
	bg.size = Vector2(40, 11)
	bg.position = Vector2(0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.06, 0.07, 0.1, 0.88)
	root.add_child(bg)
	var org_bar := ColorRect.new()
	org_bar.name = "OrgBar"
	org_bar.size = Vector2(maxf(2.0, 40.0 * org_c), 5)
	org_bar.position = Vector2(0, 0)
	org_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	org_bar.color = Color(0.28, 0.82, 0.42, 0.95)
	root.add_child(org_bar)
	var str_bar := ColorRect.new()
	str_bar.name = "StrBar"
	str_bar.size = Vector2(maxf(2.0, 40.0 * str_c), 5)
	str_bar.position = Vector2(0, 6)
	str_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	str_bar.color = Color(0.95, 0.72, 0.22, 0.95)
	root.add_child(str_bar)
	return root


## Plate + org/str on every DemoUnitIcon (call from rebuild; sprites stay on top).
func _attach_unit_counter_chrome(counter: Node2D, ff: Object, nation_col: Color) -> void:
	if counter == null:
		return
	var old_plate := counter.get_node_or_null("NationPlate")
	if old_plate != null:
		counter.remove_child(old_plate)
		old_plate.free()
	var old_bars := counter.get_node_or_null("StatBars")
	if old_bars != null:
		counter.remove_child(old_bars)
		old_bars.free()
	var plate := _make_unit_nation_plate(nation_col)
	counter.add_child(plate)
	counter.move_child(plate, 0)
	var org_v := 1.0
	var str_v := 1.0
	if ff != null:
		if "organization" in ff:
			org_v = float(ff.organization)
		if "strength" in ff:
			str_v = float(ff.strength)
	counter.add_child(_make_unit_stat_bars(org_v, str_v))
	if ff != null and "formation_id" in ff:
		counter.set_meta("formation_id", str(ff.formation_id))
		counter.set_meta("formation", ff)


## 0..1 how strongly this land province sits on a plains↔hills/mountains transition front.
func _terrain_transition_edge_mix(province: Province) -> float:
	if province == null or province.is_sea:
		return 0.0
	var t := str(province.terrain).strip_edges().to_lower()
	var is_plains := t in ["plains", "plain", "grass", "grassland"]
	var is_high := t in ["hills", "hill", "highland", "mountain", "mountains", "alpine"]
	var is_forest := t in ["forest", "woods"]
	var is_jungle := t in ["jungle"]
	var is_desert := t in ["desert", "arid"]
	var is_cold := t in ["tundra", "arctic", "snow", "ice"]
	var is_marsh := t in ["marsh", "swamp", "wetland"]
	var is_coast := t in ["coastal", "coast", "harbor"]
	if not is_plains and not is_high and not is_forest and not is_jungle and not is_desert and not is_cold and not is_marsh and not is_coast:
		return 0.0
	if typeof(MapManager) == TYPE_NIL or not MapManager.has_method("get_adjacent_provinces"):
		return 0.0
	var adj: Array = MapManager.get_adjacent_provinces(province.id, true)
	if adj.is_empty():
		return 0.0
	var hits := 0
	var checked := 0
	for pid_v in adj:
		if checked >= 8:
			break
		checked += 1
		var op: Province = provinces.get(int(pid_v)) as Province
		if op == null and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			op = MapManager.get_province(int(pid_v)) as Province
		if op == null or op.is_sea:
			continue
		var ot := str(op.terrain).strip_edges().to_lower()
		var o_plains := ot in ["plains", "plain", "grass", "grassland"]
		var o_high := ot in ["hills", "hill", "highland", "mountain", "mountains", "alpine"]
		var o_forest := ot in ["forest", "woods"]
		var o_jungle := ot in ["jungle"]
		var o_desert := ot in ["desert", "arid"]
		var o_cold := ot in ["tundra", "arctic", "snow", "ice"]
		var o_marsh := ot in ["marsh", "swamp", "wetland"]
		var o_coast := ot in ["coastal", "coast", "harbor"]
		# Classic plains↔hills front plus forest/jungle/desert/tundra/marsh/coast edges.
		if is_plains and (o_high or o_forest or o_jungle or o_desert or o_cold or o_marsh or o_coast):
			hits += 1
		elif is_high and o_plains:
			hits += 1
		elif is_forest and (o_plains or o_desert or o_cold or o_marsh or o_jungle):
			hits += 1
		elif is_jungle and (o_plains or o_forest or o_marsh):
			hits += 1
		elif is_desert and (o_plains or o_forest):
			hits += 1
		elif is_cold and (o_plains or o_forest or o_high):
			hits += 1
		elif is_marsh and (o_plains or o_forest or o_jungle or o_coast):
			hits += 1
		elif is_coast and (o_plains or o_marsh or o_high):
			hits += 1
	if hits <= 0:
		return 0.0
	return clampf(float(hits) / float(maxi(checked, 1)), 0.0, 1.0)


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


func _ensure_select_outline_layer() -> void:
	if _select_outline_layer != null and is_instance_valid(_select_outline_layer):
		return
	_select_outline_layer = Node2D.new()
	_select_outline_layer.name = "ProvinceSelectionOutlineLayer"
	_select_outline_layer.z_index = 80
	_select_outline_layer.z_as_relative = false
	var host: Node = container if container != null else self
	host.add_child(_select_outline_layer)
	_select_outline_glow = Line2D.new()
	_select_outline_glow.name = "SelectGlow"
	_select_outline_glow.closed = true
	_select_outline_glow.antialiased = true
	_select_outline_glow.joint_mode = Line2D.LINE_JOINT_ROUND
	_select_outline_glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_select_outline_glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	_select_outline_glow.z_index = 0
	_select_outline_layer.add_child(_select_outline_glow)
	_select_outline_line = Line2D.new()
	_select_outline_line.name = "SelectLine"
	_select_outline_line.closed = true
	_select_outline_line.antialiased = true
	_select_outline_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_select_outline_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_select_outline_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	_select_outline_line.z_index = 1
	_select_outline_layer.add_child(_select_outline_line)


func _selection_outline_width() -> float:
	# Keep ~3–5 screen px across zoom so shape stays obvious when zoomed out.
	var z := 1.0
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam != null:
		z = maxf(absf(cam.zoom.x), 0.08)
	return clampf(4.5 / z, 2.5, 48.0)


func _map_space_province_polygon(province_id: int) -> PackedVector2Array:
	# Convert province poly into SelectionOutlineLayer local space.
	_ensure_select_outline_layer()
	var node := _province_node(province_id)
	var local := PackedVector2Array()
	if node != null:
		local = _province_polygon(node)
	if local.size() < 3:
		local = _province_polygon_points(province_id)
	if local.size() < 3:
		return PackedVector2Array()
	if node != null and is_instance_valid(node) and is_instance_valid(_select_outline_layer):
		var out := PackedVector2Array()
		out.resize(local.size())
		for i in local.size():
			out[i] = _select_outline_layer.to_local(node.to_global(local[i]))
		return out
	# Geometry-only path already in map/canvas coords matching container.
	return local


func _set_selection_outline(province_id: int, visible: bool) -> void:
	var node := _province_node(province_id)
	if not visible:
		if node != null:
			ProvinceMapVisuals.hide_polished_outline(node, ProvinceMapVisuals.NODE_SELECT)
		if _select_outline_line != null:
			_select_outline_line.visible = false
		if _select_outline_glow != null:
			_select_outline_glow.visible = false
		return
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
	# Per-node outline (when poly exists on node).
	if node != null:
		var poly_local := _province_polygon(node)
		if poly_local.size() >= 3:
			var w_node := _selection_outline_width()
			ProvinceMapVisuals.ensure_polished_outline(
				node,
				poly_local,
				ProvinceMapVisuals.NODE_SELECT,
				sel_col,
				w_node,
				sel_glow,
				w_node * 1.35,
				ProvinceMapVisuals.Z_SELECT,
			)
	# Map-space layer outline (always-on backup so shape is visible even if node poly missing/thin).
	var map_pts := _map_space_province_polygon(province_id)
	if map_pts.size() >= 3:
		_ensure_select_outline_layer()
		var w := _selection_outline_width()
		if _select_outline_glow != null:
			_select_outline_glow.points = map_pts
			_select_outline_glow.default_color = sel_glow
			_select_outline_glow.width = w * 1.8
			_select_outline_glow.visible = true
		if _select_outline_line != null:
			_select_outline_line.points = map_pts
			_select_outline_line.default_color = sel_col
			_select_outline_line.width = w
			_select_outline_line.visible = true


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
	if _perf != null and _perf.enabled:
		_perf.begin("force_full_map_refresh")
	if not is_inside_tree() or container == null or provinces.is_empty():
		return
	# Ensure riot markers live on full refresh (for 50T harness events + F10 mapmodes)
	_update_riot_markers()
	if _occupation_layer != null and is_instance_valid(_occupation_layer):
		_occupation_layer.refresh()
	for _lyr in [_strategic_flow_layer, _battle_indicator_layer, _domain_ops_layer, _leader_station_layer, _construction_progress_layer]:
		if _lyr != null and is_instance_valid(_lyr) and _lyr.has_method("refresh"):
			_lyr.refresh()
	_force_all_province_nodes_visible()
	_refresh_province_fill_colors(true)
	_restore_land_poly_visibility()
	_ensure_capital_stars_visible()
	# If inspector open, re-pull live settlement/welfare numbers into it
	if info_panel and info_panel is CanvasItem and info_panel.visible and selected_province_id >= 0 and provinces.has(selected_province_id):
		show_info_panel(provinces[selected_province_id])
	if _perf != null and _perf.enabled:
		_perf.end("force_full_map_refresh")
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
		var pre_divs: Array = BattleManager.get_divisions_at_province(staging_pid, p_tag) if BattleManager and BattleManager.has_method("get_divisions_at_province") else []
		if pre_divs.size() > 0:
			att_fid_pre = str(pre_divs[0].get("formation_id", ""))
		if att_fid_pre.is_empty() and preview.has("formation_id"):
			att_fid_pre = str(preview.get("formation_id", ""))
		var def_divs: Array = BattleManager.get_divisions_at_province(target_pid, target_p.owner_tag if target_p else "") if BattleManager and BattleManager.has_method("get_divisions_at_province") else []
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
		var sel_col := ProvinceMapVisuals.OUTLINE_SELECT
		var sel_glow := ProvinceMapVisuals.OUTLINE_SELECT_GLOW
		var sel_node := _province_node(selected_province_id)
		if sel_node != null:
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
				_selection_outline_width(),
				sel_glow,
				_selection_outline_width() * 1.5,
				_outline_pulse_phase + 0.8,
				0.3,
				3.2 * _map_overlay_pulse_speed_scale(),
			)
		# Pulse map-space selection layer (primary visible ring).
		if _select_outline_line != null and _select_outline_line.visible:
			var base_w := _selection_outline_width()
			var phase := _outline_pulse_phase + 0.8
			var t := 0.5 + 0.5 * sin(phase * 3.2)
			_select_outline_line.width = base_w * (1.0 + 0.18 * t)
			_select_outline_line.default_color = sel_col
			if _select_outline_glow != null and _select_outline_glow.visible:
				_select_outline_glow.width = base_w * 1.7 * (1.0 + 0.12 * t)
				_select_outline_glow.default_color = sel_glow
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
	# Skip orange rings when cursor is over inspector/menus the player is using.
	if _is_mouse_over_blocking_ui():
		return
	# Hovered province gets soft orange (neighbor preferred; any land province ok for scouting).
	# Pink select outline stays the primary read.
	if _hover_outline_province_id >= 0 and _hover_outline_province_id != selected_province_id:
		var hid := _hover_outline_province_id
		if hid == _compare_preview_province_id:
			return
		var is_nb := false
		for nid in adjacency.get_neighbors(selected_province_id):
			if int(nid) == hid:
				is_nb = true
				break
		# Neighbors get strong orange; other provinces get a lighter scout ring only if adjacent-ish via region later.
		if is_nb:
			_compare_candidate_ids.append(hid)
			_set_compare_candidate_outline(hid, true, true)
		else:
			# Still show hover orange on non-neighbors when something is selected (explore map).
			_compare_candidate_ids.append(hid)
			_set_compare_candidate_outline(hid, true, false)


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
		# STOP so Close is clickable; body text stays IGNORE so wheel passes to map when over text.
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		panel.offset_left = 10.0
		panel.offset_top = 56.0  # below top bar
		panel.custom_minimum_size = Vector2(480, 0)
		panel.z_index = 40
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.08, 0.14, 0.92)
		style.border_color = Color(0.35, 0.55, 0.85, 0.75)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		panel.add_theme_stylebox_override("panel", style)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)
		# Header: title + Close (user reported no way out of this panel)
		var header := HBoxContainer.new()
		header.mouse_filter = Control.MOUSE_FILTER_STOP
		vbox.add_child(header)
		var title := Label.new()
		title.text = "Supply map legend"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header.add_child(title)
		var close_btn := Button.new()
		close_btn.name = "CloseSupplyLegend"
		close_btn.text = "Close ✕"
		close_btn.tooltip_text = "Hide supply legend (or press L / Esc)"
		close_btn.custom_minimum_size = Vector2(88, 28)
		close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		close_btn.pressed.connect(_on_close_supply_legend_pressed)
		header.add_child(close_btn)
		var hint := Label.new()
		hint.text = "Press L or Esc to hide · wheel zooms map outside this panel"
		hint.add_theme_font_size_override("font_size", 10)
		hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(hint)
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(margin)
		_supply_overlay_legend = RichTextLabel.new()
		_supply_overlay_legend.bbcode_enabled = true
		_supply_overlay_legend.fit_content = true
		_supply_overlay_legend.scroll_active = true
		_supply_overlay_legend.custom_minimum_size = Vector2(460, 0)
		_supply_overlay_legend.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# Cap height so it doesn't eat the whole screen with no close affordance.
		_supply_overlay_legend.custom_minimum_size.y = 120
		_supply_overlay_legend.mouse_filter = Control.MOUSE_FILTER_STOP  # allow text scroll; Close still above
		_supply_overlay_legend.add_theme_font_size_override("normal_font_size", 11)
		margin.add_child(_supply_overlay_legend)
		ui.add_child(panel)
	_update_supply_legend_text()


func _on_close_supply_legend_pressed() -> void:
	## Explicit dismiss — turns off supply map mode so legend hides and map input is clean.
	if supply_mode:
		_toggle_supply_overlay()
	else:
		_set_supply_legend_visible(false)
	_show_map_layer_toast("Supply legend closed (L to show again)")
	print("MapRenderer: SupplyOverlayLegend closed by user")


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


## Pass 9–13: retrowave chip path for fort/port/airfield special_features map markers.
## Airfield: 1=strip, 2=std, 3+=hangar. Fort: 1=bunker, 2=std, 3+=heavy (damaged overrides).
## Port: 1=jetty, 2=std, 3+/major_port=major.
func _special_feature_sprite_path(feature: String, level: int = 0, damaged: bool = false) -> String:
	var fk := feature.to_lower().strip_edges()
	match fk:
		"bunker", "field_bunker", "fort_bunker":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/fort_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/fort_damaged_32.png"
			return "res://assets/graphics/units/retrowave/fort_bunker_32.png"
		"fort_heavy", "fortress", "citadel":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/fort_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/fort_damaged_32.png"
			return "res://assets/graphics/units/retrowave/fort_heavy_32.png"
		"fort", "coastal_fort":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/fort_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/fort_damaged_32.png"
			if level <= 1:
				return "res://assets/graphics/units/retrowave/fort_bunker_32.png"
			if level >= 3:
				return "res://assets/graphics/units/retrowave/fort_heavy_32.png"
			return "res://assets/graphics/units/retrowave/fort_32.png"
		"port_jetty", "jetty", "minor_port":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/port_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/port_damaged_32.png"
			return "res://assets/graphics/units/retrowave/port_jetty_32.png"
		"port_major", "major_port":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/port_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/port_damaged_32.png"
			return "res://assets/graphics/units/retrowave/port_major_32.png"
		"port", "harbor", "dock":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/port_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/port_damaged_32.png"
			if level <= 1:
				return "res://assets/graphics/units/retrowave/port_jetty_32.png"
			if level >= 3:
				return "res://assets/graphics/units/retrowave/port_major_32.png"
			return "res://assets/graphics/units/retrowave/port_32.png"
		"airstrip", "landing_strip", "airfield_strip":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/airfield_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/airfield_damaged_32.png"
			return "res://assets/graphics/units/retrowave/airfield_strip_32.png"
		"airfield_hangar", "hangar":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/airfield_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/airfield_damaged_32.png"
			return "res://assets/graphics/units/retrowave/airfield_hangar_32.png"
		"airfield", "airbase", "runway", "airport":
			if damaged and ResourceLoader.exists("res://assets/graphics/units/retrowave/airfield_damaged_32.png"):
				return "res://assets/graphics/units/retrowave/airfield_damaged_32.png"
			if level <= 1:
				return "res://assets/graphics/units/retrowave/airfield_strip_32.png"
			if level >= 3:
				return "res://assets/graphics/units/retrowave/airfield_hangar_32.png"
			return "res://assets/graphics/units/retrowave/airfield_32.png"
		_:
			return ""


func _feature_key_is_airfield(fk: String) -> bool:
	var k := fk.to_lower()
	return k in ["airfield", "airbase", "airstrip", "runway", "airport", "airfield_strip", "landing_strip", "airfield_hangar", "hangar"]


## Pass 16: 0–1 progress for ring; -1 = no ring. Damaged → repair remaining; building → construction.
func _airfield_progress_for_province(province: Province, damaged: bool) -> float:
	if province == null:
		return -1.0
	# Prefer live SpecialSite data when available.
	if typeof(SpecialSiteManager) != TYPE_NIL and SpecialSiteManager.has_method("get_all_sites"):
		var sites = SpecialSiteManager.get_all_sites()
		if sites is Array:
			for s in sites:
				if s is Dictionary:
					var d: Dictionary = s
					if int(d.get("province_id", -1)) != province.id:
						continue
					var sid := str(d.get("id", d.get("site_type", ""))).to_lower()
					if not ("air" in sid or "runway" in sid or "airstrip" in sid):
						continue
					var bp := float(d.get("build_progress", d.get("construction_progress", -1.0)))
					if bp >= 0.0 and bp < 0.99:
						return clampf(bp, 0.0, 1.0)
					var dmg_lv := int(d.get("damage_level", 0))
					var max_d := maxi(1, int(d.get("max_damage_level", 3)))
					if dmg_lv > 0:
						return clampf(1.0 - float(dmg_lv) / float(max_d), 0.05, 0.95)
	if damaged:
		var dmg: Dictionary = ProvinceInsight.classify_province_map_damage(province)
		var strength := clampf(float(dmg.get("strength", 0.45)), 0.15, 0.9)
		# Ring shows remaining health / repair progress toward full.
		return clampf(1.0 - strength * 0.85, 0.08, 0.92)
	return -1.0


func _attach_feature_progress_ring(parent: Node2D, world_pos: Vector2, progress: float, is_repair: bool, province_id: int = -1) -> void:
	if parent == null:
		return
	var ring_script = load("res://scripts/map/FeatureProgressRing.gd")
	if ring_script == null:
		return
	var ring := Node2D.new()
	ring.set_script(ring_script)
	ring.name = "FeatureProgressRing"
	ring.position = world_pos
	ring.set_meta(&"_ring_province_id", province_id)
	ring.set_meta(&"_ring_is_repair", is_repair)
	if "province_id" in ring:
		ring.province_id = province_id
	parent.add_child(ring)
	if ring.has_method("set_progress"):
		ring.call("set_progress", progress, is_repair)
	# Pass 18: hover tooltip with province + progress.
	if ring.has_method("set_tooltip_text"):
		var pname := "province %d" % province_id
		if province_id >= 0 and provinces.has(province_id):
			var pp: Province = provinces[province_id] as Province
			if pp != null and str(pp.name) != "":
				pname = str(pp.name)
		var kind := "Repair" if is_repair else "Construction"
		ring.call(
			"set_tooltip_text",
			"Airfield %s · %s · %d%% · click site" % [kind.to_lower(), pname, int(round(progress * 100.0))]
		)
	# Pass 19: click opens province inspector focused on special sites.
	if ring.has_signal("ring_clicked"):
		if not ring.ring_clicked.is_connected(_on_feature_ring_clicked):
			ring.ring_clicked.connect(_on_feature_ring_clicked)


func _on_feature_ring_clicked(province_id: int) -> void:
	if province_id < 0:
		return
	if has_method("focus_province_by_id"):
		focus_province_by_id(province_id)
	if provinces.has(province_id):
		show_info_panel(provinces[province_id] as Province)
		# Nudge special sites section into view if present.
		if _special_sites_container != null and is_instance_valid(_special_sites_container):
			_special_sites_container.visible = true
		if _label_special_sites_header != null and is_instance_valid(_label_special_sites_header):
			_label_special_sites_header.visible = true
	if typeof(DebugOverlay) != TYPE_NIL:
		DebugOverlay.toast_map_debug("Airfield site · province %d" % province_id)


## Pass 17: update existing FeatureProgressRing nodes from live damage/construction state.
func _refresh_feature_progress_rings() -> void:
	if province_nodes.is_empty():
		return
	for pid_v in province_nodes.keys():
		var node: Node2D = province_nodes[pid_v] as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var pid := int(pid_v)
		var province: Province = provinces.get(pid) as Province if provinces.has(pid) else null
		if province == null and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_province"):
			province = MapManager.get_province(pid) as Province
		for child in node.get_children():
			if child == null or not is_instance_valid(child):
				continue
			if str(child.name) != "FeatureProgressRing" and not child.has_meta(&"_ring_province_id"):
				continue
			if not child.has_method("set_progress"):
				continue
			var is_repair := true
			if child.has_meta(&"_ring_is_repair"):
				is_repair = bool(child.get_meta(&"_ring_is_repair"))
			var damaged := false
			if province != null:
				damaged = _province_feature_is_damaged(province, "airfield")
			var p := _airfield_progress_for_province(province, damaged) if province != null else -1.0
			if p < 0.0:
				# Fully repaired / no project — hide ring.
				child.visible = false
				continue
			child.visible = true
			child.set_meta(&"_ring_is_repair", damaged)
			child.call("set_progress", p, damaged or is_repair)
			if child.has_method("set_tooltip_text"):
				var pname := "province %d" % pid
				if province != null and str(province.name) != "":
					pname = str(province.name)
				var kind := "Repair" if (damaged or is_repair) else "Construction"
				child.call(
					"set_tooltip_text",
					"Airfield %s · %s · %d%%" % [kind.to_lower(), pname, int(round(p * 100.0))]
				)


## Pass 13–15: fort/port/airfield site damage from ProvinceInsight map damage classifier.
func _province_feature_is_damaged(province: Province, feature_key: String) -> bool:
	if province == null:
		return false
	var fk := feature_key.to_lower()
	# Fort-like + port-like + airfield features use damaged art.
	var is_fort := fk in ["fort", "coastal_fort", "bunker", "field_bunker", "fort_bunker", "fort_heavy", "fortress", "citadel"]
	var is_port := fk in ["port", "major_port", "harbor", "dock", "port_jetty", "jetty", "minor_port", "port_major"]
	var is_air := fk in ["airfield", "airbase", "airstrip", "runway", "airport", "airfield_strip", "landing_strip", "airfield_hangar", "hangar"]
	if not is_fort and not is_port and not is_air:
		return false
	# ProvinceInsight is static helpers (class_name) — call directly, no has_method on class.
	var dmg: Dictionary = ProvinceInsight.classify_province_map_damage(province)
	if dmg.is_empty() or not bool(dmg.get("is_damaged", false)):
		return false
	var key := str(dmg.get("tint_key", "")).to_lower()
	var strength := float(dmg.get("strength", 0.0))
	# Site damage or meaningful sabotage → damaged fort/port glyph.
	if key in ["site_damage", "infra_sabotage", "project_sabotage"] or strength >= 0.28:
		return true
	return false


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
	# GIS world underlay texture is equirectangular 8192×4096 (same as lonlat_to_canvas).
	# It MUST map to WORLD_CANONICAL_BOUNDS (= that canvas × THEATER_SCALE). Stretching it to
	# MapManager centroid AABB (non-2:1, Y-shifted) desyncs art from province polys and looks
	# like a small "world card" with a second larger poly map floating beside it.
	_unify_map_canvas_transform()
	var bg := find_child("WorldBackground", true, false) as Sprite2D
	if not bg or not bg.texture:
		return
	if bg.has_meta("grand_fitted") and is_using_grand_stylized_map() and not is_using_world_grand_map():
		_suppress_old_background_maps()
		return
	var b := _resolve_underlay_fit_bounds()
	bg.centered = false
	bg.offset = Vector2.ZERO
	bg.position = b.position
	bg.rotation = 0.0
	var img_size := Vector2(float(bg.texture.get_width()), float(bg.texture.get_height()))
	if img_size.x > 0.0 and img_size.y > 0.0:
		# Hard lock: display size must equal fit bounds (THEATER_SCALE for GIS equirect).
		bg.scale = Vector2(b.size.x / img_size.x, b.size.y / img_size.y)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bg.visible = true
	# Pan theater = full underlay rect (always covers Americas→Asia→Australia on GIS).
	_current_theater_bounds = b.grow(80.0)
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_world_bounds"):
		var wb: Rect2 = MapManager.get_world_bounds()
		if wb.size.x > 2000.0:
			# Expand theater if any province centroid sits slightly outside equirect rect.
			_current_theater_bounds = _current_theater_bounds.merge(wb.grow(40.0))
	# Southern GIS outliers (raw Y past 4096) need extra pan room for Australia/Antarctic sea.
	if _is_gis_board_active():
		_current_theater_bounds = _current_theater_bounds.merge(
			Rect2(WORLD_CANONICAL_BOUNDS.position, WORLD_CANONICAL_BOUNDS.size + Vector2(0, 1800.0))
		)
	_suppress_old_background_maps()
	if is_using_grand_stylized_map() and not is_using_world_grand_map():
		bg.set_meta("grand_fitted", true)
	else:
		bg.remove_meta("grand_fitted")
	if terrain_layer_stack and terrain_layer_stack.has_method("fit_to_bounds"):
		terrain_layer_stack.fit_to_bounds(b)
	_sync_peak_snow_overlay()
	var cscale := container.scale if container else Vector2.ONE
	print(
		"MapRenderer: Fitted underlay to equirect bounds %s · theater=%s · container_scale=%s · bg_scale=%s · bg_parent=%s"
		% [
			str(b),
			str(_current_theater_bounds),
			str(cscale),
			str(bg.scale),
			bg.get_parent().name if bg.get_parent() else "?",
		]
	)
	_refresh_terrain_zoom_aware()


## Underlay fit rect: GIS world = fixed equirect 2:1 canvas. Europe-local = grand theater.
func _resolve_underlay_fit_bounds() -> Rect2:
	if _is_gis_board_active() or is_using_world_grand_map():
		return WORLD_CANONICAL_BOUNDS
	if is_using_grand_stylized_map():
		return GRAND_THEATER_CANONICAL_BOUNDS
	var rb := get_rendered_province_bounds()
	if rb.size.x > 500.0 and rb.size.y > 250.0:
		return rb
	return WORLD_CANONICAL_BOUNDS


## True for world_accurate / world_full GIS boards (equirect geometry + THEATER_SCALE only).
func _is_gis_board_active() -> bool:
	if typeof(MapManager) != TYPE_NIL and MapManager.has_method("is_geometry_world_native"):
		if bool(MapManager.is_geometry_world_native()):
			return true
	if get_meta("full_world_underlay_active", false):
		return true
	return is_using_world_grand_map()


## Pan AABB (may be larger than underlay if outliers exist).
func _resolve_map_content_bounds() -> Rect2:
	return _resolve_underlay_fit_bounds()

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
	# Hard block: GIS world boards keep equirect world underlay forever.
	if _is_gis_board_active() or is_using_world_grand_map():
		print("MapRenderer: GIS/world underlay active — skip europe-only phase1 bg replace (prevents dual map).")
		set_meta("full_world_underlay_active", true)
		_fit_background_to_bounds()
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
	# Full repaint so sea/land alphas match clean vs terrain stack immediately.
	_refresh_province_fill_colors(true)
	print("MapRenderer: Terrain layer ", "ON (detailed high-res bg + thin outlines)" if enabled else "OFF (CLEAN POLITICAL VIEW - solid fills, continuous sea, no void-hex underlay)")
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
	# Ocean floor always on in clean political (gaps = continuous sea, never void hex).
	if _ocean_floor != null and is_instance_valid(_ocean_floor):
		_ocean_floor.visible = true
		if not show_terrain_layer:
			var oc := continuous_sea_fill_color()
			oc.a = 1.0
			_ocean_floor.color = oc
	_apply_clean_political_clear_color()
	# Force repaint of fills with correct alpha (low for terrain visible, higher for clean political)
	_fill_color_zoom_bucket = -999999999

func _refresh_terrain_zoom_aware() -> void:
	## Full/expensive path — prefer _refresh_terrain_zoom_light for wheel input.
	## Do not loop all provinces here (world_full 2665 fills froze scroll).
	_refresh_terrain_zoom_light()
	_suppress_old_background_maps()
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


## Province ids that currently have a DemoUnitIcon_* child (avoids full-board clear).
var _demo_unit_icon_pids: Array = []
var _oob_strip: PanelContainer = null
## Pass 19: munitions production/logistics desk chip.
var _munitions_desk: PanelContainer = null
## Pass 22: theater-wide site repair queue chip.
var _repair_queue_chip: PanelContainer = null
## Pass 20: route compare summary card.
var _route_compare_card: PanelContainer = null
## Pass 21: last compare payload + up to 3 saved A/B pairs.
var _last_route_compare_data: Dictionary = {}
var _route_compare_slots: Array = [{}, {}, {}, {}]  # Pass 28: 4 pack slots
## Pass 29: optional display names for pack slots.
var _route_compare_slot_labels: Array = ["", "", "", ""]
var _route_compare_card_gen: int = 0
## Pass 25: multi-day overall risk history for last compare (and per slot).
## key "last" | "slot0".."slot2" -> { samples_a: [], samples_b: [], path_a, path_b }
var _route_risk_day_history: Dictionary = {}
const ROUTE_RISK_HISTORY_MAX := 16
var _stack_badge_pulse_nodes: Array = []
var _stack_pulse_phase: float = 0.0


## Demo: adds NATO symbol sprites (using generated assets) to province nodes that have
## stationed formations (from the test spawns in TestRunner / phase1 loads).
## Replaces previous ColorRect fallback now that proper symbol suite exists.
##
## CRITICAL PERF (F5 hang): never call get_formations_stationed_at_province per province.
## That path re-parsed division templates + scanned all deployments per province (world_full
## ≈ 2665×) and froze pan/zoom after markers appeared, then hard-crashed Godot.
func _update_unit_icons_for_test() -> void:
	_rebuild_demo_unit_icons({})


## Capture/move: rebuild pins for listed pids only (not the full board).
func _update_unit_icons_for_pids(pids: Array) -> void:
	var only: Dictionary = {}
	for v in pids:
		var pid := int(v)
		if pid >= 0:
			only[pid] = true
	if only.is_empty():
		return
	_rebuild_demo_unit_icons(only)


func _rebuild_demo_unit_icons(only_pids: Dictionary) -> void:
	var scoped := not only_pids.is_empty()
	# Clear previous demo icons only where we placed them (or only listed pids).
	var kept: Array = []
	for id_v in _demo_unit_icon_pids:
		var id_clear := int(id_v)
		if scoped and not only_pids.has(id_clear):
			kept.append(id_clear)
			continue
		if not province_nodes.has(id_clear):
			continue
		var n_clear: Node2D = province_nodes[id_clear] as Node2D
		if n_clear == null:
			continue
		for c in n_clear.get_children():
			if c.name.begins_with("DemoUnitIcon_"):
				c.queue_free()
	_demo_unit_icon_pids.clear()
	for k in kept:
		_demo_unit_icon_pids.append(int(k))
	if not scoped:
		_stack_badge_pulse_nodes.clear()

	# province_id -> representative formation (Object) or country_tag String fallback
	var by_pid: Dictionary = _build_stationed_formation_index_for_icons()
	if by_pid.is_empty():
		if not scoped:
			_update_riot_markers()
		return
	var stack_counts: Dictionary = {}
	var stack_samples: Dictionary = {}
	if by_pid.has("_counts") and by_pid["_counts"] is Dictionary:
		stack_counts = by_pid["_counts"] as Dictionary
		by_pid.erase("_counts")
	if by_pid.has("_samples") and by_pid["_samples"] is Dictionary:
		stack_samples = by_pid["_samples"] as Dictionary
		by_pid.erase("_samples")

	var tex_cache: Dictionary = {}  # path -> Texture2D
	var icons_placed := 0
	for pid_v in by_pid.keys():
		var id := int(pid_v)
		if scoped and not only_pids.has(id):
			continue
		if not province_nodes.has(id):
			continue
		var n: Node2D = province_nodes[id] as Node2D
		if n == null:
			continue
		var p: Province = provinces.get(id) as Province
		var entry: Variant = by_pid[pid_v]
		var ff: Object = entry as Object if entry is Object else null
		var force_tag := ""
		if entry is String:
			force_tag = str(entry)
		elif ff != null and "country_tag" in ff:
			force_tag = str(ff.country_tag)
		var stack_n := int(stack_counts.get(id, 1))
		var samples: Array = stack_samples.get(id, []) as Array

		var counter := Node2D.new()
		counter.name = "DemoUnitIcon_" + str(id)
		counter.position = Vector2(0, -8)
		# Pass 7: zoom-scaled counters — larger when zoomed in, smaller at strategic view.
		counter.scale = Vector2.ONE * _unit_counter_scale_for_zoom()
		# LOD: compact at strategic zoom; hidden only when master toggle off (U).
		counter.visible = _unit_counters_want_visible()
		# Store formation ref so map clicks can open unit detail.
		if ff != null:
			if "formation_id" in ff:
				counter.set_meta("formation_id", str(ff.formation_id))
			counter.set_meta("formation", ff)
		counter.set_meta("province_id", id)
		n.add_child(counter)

		# Use actual NATO symbol if available, type-aware for starting/buildable units.
		# Driven primarily by visual_archetype from the design template.
		var tex_path := "res://assets/graphics/units/nato/modern/infantry_32.png"
		var ftype := ""
		var arch := ""
		var dsn := ""
		if ff != null:
			if ff.has_method("get_category"):
				ftype = str(ff.call("get_category"))
			elif "formation_type" in ff:
				ftype = str(ff.formation_type)
			if "design_id" in ff and str(ff.design_id) != "":
				dsn = str(ff.design_id).to_lower()
			if "naval_design_id" in ff and str(ff.naval_design_id) != "":
				dsn = str(ff.naval_design_id).to_lower()
			if "air_design_id" in ff and (dsn == "" or "air" in ftype):
				dsn = str(ff.air_design_id).to_lower()
			if dsn != "" and typeof(GameData) != TYPE_NIL and GameData.design_data != null:
				var tpl = GameData.design_data.get_template(dsn)
				if tpl != null:
					arch = str(tpl.visual_archetype).to_lower().strip_edges()
		var era_folder := "modern"
		if "ww1" in arch or "ww2" in arch or "interwar" in arch or "191" in dsn or "193" in dsn or "194" in dsn:
			era_folder = "ww2"
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
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"
			elif "jet_bomber" in arch:
				tex_path = "res://assets/graphics/units/nato/modern/bomber_32.png"
			elif "truck" in arch or "logistics" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/logistics_32.png"
			elif "armored_vehicle" in arch or "apc" in arch or "ifv" in arch or "recon" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/medium_tank_32.png"
			elif "amphib_tank" in arch or "amphib_vehicle" in arch or "amphib" in arch:
				tex_path = "res://assets/graphics/units/retrowave/amphib_32.png"
			elif "apc" in arch or "ifv" in arch:
				tex_path = "res://assets/graphics/units/retrowave/apc_32.png"
			elif "recon" in arch or "scout" in arch:
				tex_path = "res://assets/graphics/units/retrowave/recon_32.png"
			elif "anti_air" in arch or "antiair" in arch or "flak" in arch or "aa_" in arch:
				tex_path = "res://assets/graphics/units/retrowave/aa_32.png"
			elif "anti_tank" in arch or "antitank" in arch or "pak" in arch or "tank_destroyer" in arch:
				tex_path = "res://assets/graphics/units/retrowave/at_32.png"
			elif "fort_damaged" in arch or ("damaged" in arch and "fort" in arch):
				tex_path = "res://assets/graphics/units/retrowave/fort_damaged_32.png"
			elif "fort_heavy" in arch or "citadel" in arch or "fortress" in arch:
				tex_path = "res://assets/graphics/units/retrowave/fort_heavy_32.png"
			elif "fort_bunker" in arch or ("bunker" in arch and "fort" not in arch):
				tex_path = "res://assets/graphics/units/retrowave/fort_bunker_32.png"
			elif "fort" in arch or "bunker" in arch:
				tex_path = "res://assets/graphics/units/retrowave/fort_32.png"
			elif "port_damaged" in arch or ("damaged" in arch and "port" in arch):
				tex_path = "res://assets/graphics/units/retrowave/port_damaged_32.png"
			elif "port_major" in arch or "major_port" in arch:
				tex_path = "res://assets/graphics/units/retrowave/port_major_32.png"
			elif "port_jetty" in arch or "jetty" in arch or "minor_port" in arch:
				tex_path = "res://assets/graphics/units/retrowave/port_jetty_32.png"
			elif "port" in arch or "harbor" in arch:
				tex_path = "res://assets/graphics/units/retrowave/port_32.png"
			elif "airfield_damaged" in arch or ("damaged" in arch and ("airfield" in arch or "airbase" in arch)):
				tex_path = "res://assets/graphics/units/retrowave/airfield_damaged_32.png"
			elif "hangar" in arch or "airfield_hangar" in arch:
				tex_path = "res://assets/graphics/units/retrowave/airfield_hangar_32.png"
			elif "airstrip" in arch or "airfield_strip" in arch:
				tex_path = "res://assets/graphics/units/retrowave/airfield_strip_32.png"
			elif "airfield" in arch or "airbase" in arch or "runway" in arch:
				tex_path = "res://assets/graphics/units/retrowave/airfield_32.png"
			elif "convoy" in arch or "sealane" in arch or "merchant" in arch or "armed_merchant" in arch:
				tex_path = "res://assets/graphics/units/retrowave/convoy_32.png"
			elif "naval_transport" in arch:
				tex_path = "res://assets/graphics/units/retrowave/convoy_32.png"
			elif "submarine" in arch or "sub" in arch or "uboat" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/submarine_32.png"
			elif "battleship" in arch:
				tex_path = "res://assets/graphics/units/retrowave/battleship_32.png"
			elif "cruiser" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/cruiser_32.png"
			elif "frigate" in arch:
				tex_path = "res://assets/graphics/units/retrowave/frigate_32.png"
			elif "destroyer" in arch or "patrol" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/destroyer_32.png"
			elif "convoy" in arch or "merchant" in arch:
				tex_path = "res://assets/graphics/units/retrowave/convoy_32.png"
			elif "transport" in arch or "logistics" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/logistics_32.png"
			elif "rocket" in arch or "mlrs" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/rocket_32.png"
			elif "artillery" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/artillery_32.png"
			elif "infantry" in arch:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/infantry_32.png"
		if "naval" in ftype or "ship" in ftype or "sub" in ftype.to_lower():
			if "carrier" in ftype or "carrier" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/carrier_32.png"
			elif "sub" in ftype.to_lower() or "submarine" in dsn or "uboat" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/submarine_32.png"
			elif "battleship" in ftype.to_lower() or "battleship" in dsn or "bismarck" in dsn or "king_george" in dsn:
				tex_path = "res://assets/graphics/units/retrowave/battleship_32.png"
			elif "cruiser" in ftype.to_lower() or "cruiser" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/cruiser_32.png"
			elif "frigate" in ftype.to_lower() or "frigate" in dsn:
				tex_path = "res://assets/graphics/units/retrowave/frigate_32.png"
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
		if dsn != "":
			if "panzer" in dsn or "sherman" in dsn or "tiger" in dsn or "medium_tank" in dsn or "t34" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/medium_tank_32.png"
			elif "bismarck" in dsn or "king_george" in dsn or "battleship" in dsn:
				tex_path = "res://assets/graphics/units/retrowave/battleship_32.png"
			elif "u_boat" in dsn or "fletcher" in dsn or "destroyer" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/destroyer_32.png"
			elif "bf109" in dsn or "p51" in dsn or "spitfire" in dsn or "zero" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/fighter_32.png"
			elif "b17" in dsn or "bomber" in dsn:
				tex_path = "res://assets/graphics/units/nato/" + era_folder + "/bomber_32.png"

		# Prefer retrowave unit chips when present (world-class map counters).
		tex_path = _prefer_retrowave_unit_icon(tex_path)
		var tex: Texture2D = null
		if tex_cache.has(tex_path):
			tex = tex_cache[tex_path] as Texture2D
		else:
			if ResourceLoader.exists(tex_path):
				tex = load(tex_path) as Texture2D
			tex_cache[tex_path] = tex
		var owner_for_sheet := force_tag
		if owner_for_sheet.is_empty() and p != null:
			owner_for_sheet = p.owner_tag
		# Sheet atlas only when retrowave chip missing (legacy NATO sheet path).
		var using_retrowave := tex_path.begins_with("res://assets/graphics/units/retrowave/")
		if not using_retrowave and _nato_sheet_tex != null and tex != null and (owner_for_sheet in ["GER", "SOV", "FRA", "ENG", "USA"] or "tank" in arch or "armor" in arch or "medium" in arch or "heavy" in arch):
			var reg := _get_nato_sheet_region(owner_for_sheet, arch, era_folder)
			if reg.size.x > 0:
				var atlas := AtlasTexture.new()
				atlas.atlas = _nato_sheet_tex
				atlas.region = reg
				tex = atlas as Texture2D
		var nation_tag := force_tag
		if nation_tag.is_empty() and p != null:
			nation_tag = p.owner_tag
		var nation_col := Color(0.85, 0.88, 0.95, 1.0)
		if not nation_tag.is_empty() and typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_country_color"):
			nation_col = MapManager.get_country_color(nation_tag)
		if tex:
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = true
			# Retrowave chips keep full-color art; nation identity is a frame, not a full modulate wash.
			if using_retrowave:
				spr.modulate = Color.WHITE
			else:
				var use_nation_color = (
					"tank" in arch or "armored" in arch or "truck" in arch or "infantry" in arch
					or "light_tank" in arch or "medium_tank" in arch or "heavy_tank" in arch
					or "amphib" in arch or ftype.is_empty() or "division" in ftype.to_lower()
					or "garrison" in ftype.to_lower()
				)
				if use_nation_color and not nation_tag.is_empty():
					spr.modulate = nation_col
			# Pass 6: fan-out 2–4 icons when stack is modest; large stacks use primary + badge.
			var fan := mini(stack_n, 4) if stack_n > 1 else 1
			if fan <= 1:
				counter.add_child(spr)
				if not nation_tag.is_empty():
					counter.add_child(_make_unit_nation_frame(nation_col))
			else:
				_add_unit_stack_fanout(counter, spr, tex, tex_cache, samples, fan, nation_tag, nation_col, using_retrowave, era_folder)
			_attach_unit_counter_chrome(counter, ff, nation_col)
			if stack_n > 1:
				counter.add_child(_make_formation_stack_badge(stack_n))
		else:
			var bg := ColorRect.new()
			bg.size = Vector2(20, 16)
			bg.position = Vector2(-10, -8)
			bg.color = Color(0.1, 0.12, 0.18, 0.9)
			counter.add_child(bg)
			_attach_unit_counter_chrome(counter, ff, nation_col)
			if stack_n > 1:
				counter.add_child(_make_formation_stack_badge(stack_n))
		_demo_unit_icon_pids.append(id)
		icons_placed += 1

	if not scoped and icons_placed > 0:
		print("[MapRenderer] Unit icons placed=%d (indexed formations, no per-province template reload)" % icons_placed)
	if not scoped:
		_update_riot_markers()
	# Re-apply selected-chip chrome after pin rebuild (do not rebuild all pins for selection).
	if not selected_formation_id.is_empty():
		_refresh_selected_unit_chip()


## O(formations + deployments) index for unit icons.
## Returns { province_id: Formation|String, "_counts": {...}, "_samples": {pid: Array} }.
func _build_stationed_formation_index_for_icons() -> Dictionary:
	var by_pid: Dictionary = {}
	var counts: Dictionary = {}
	var samples: Dictionary = {}
	# Prefer full Formation objects from LeaderManager (all countries, land/air/naval).
	if typeof(LeaderManager) != TYPE_NIL and "formations" in LeaderManager:
		for fid_v in LeaderManager.formations.keys():
			var f: Variant = LeaderManager.formations[fid_v]
			if f == null or not (f is Object):
				continue
			var fo: Object = f as Object
			if not ("stationed_province_id" in fo):
				continue
			var sid := int(fo.stationed_province_id)
			if sid < 0:
				continue
			counts[sid] = int(counts.get(sid, 0)) + 1
			if not by_pid.has(sid):
				by_pid[sid] = fo
			var arr: Array = samples.get(sid, []) as Array
			if arr.size() < 4:
				arr.append(fo)
				samples[sid] = arr
	# division_deployments may station engineers/templates without a full Formation object.
	if typeof(SupplyManager) != TYPE_NIL and "division_deployments" in SupplyManager:
		var deps: Dictionary = SupplyManager.division_deployments as Dictionary
		for fid_v2 in deps.keys():
			var dep: Dictionary = deps[fid_v2] as Dictionary
			var pid2 := int(dep.get("province_id", -1))
			if pid2 < 0:
				continue
			# Avoid double-counting if already seen as a Formation with same id.
			if typeof(LeaderManager) != TYPE_NIL:
				var existing: Formation = LeaderManager.get_formation(str(fid_v2))
				if existing != null:
					# Already counted via formations loop if present.
					if by_pid.has(pid2) and samples.has(pid2):
						continue
					counts[pid2] = int(counts.get(pid2, 0)) + 1
					if not by_pid.has(pid2):
						by_pid[pid2] = existing
					var arr2: Array = samples.get(pid2, []) as Array
					if arr2.size() < 4:
						arr2.append(existing)
						samples[pid2] = arr2
					continue
			var tag2 := str(dep.get("country_tag", "")).strip_edges().to_upper()
			counts[pid2] = int(counts.get(pid2, 0)) + 1
			if not by_pid.has(pid2):
				by_pid[pid2] = tag2 if not tag2.is_empty() else "UNK"
	by_pid["_counts"] = counts
	by_pid["_samples"] = samples
	return by_pid


## Fan-out up to 4 unit chips in a small arc; reuses primary tex when samples lack variety.
func _add_unit_stack_fanout(
	counter: Node2D,
	primary_spr: Sprite2D,
	primary_tex: Texture2D,
	tex_cache: Dictionary,
	samples: Array,
	fan: int,
	nation_tag: String,
	nation_col: Color,
	using_retrowave: bool,
	era_folder: String,
) -> void:
	var n := clampi(fan, 2, 4)
	var offsets: Array[Vector2] = [
		Vector2(-10, 4),
		Vector2(10, 4),
		Vector2(0, -8),
		Vector2(0, 12),
	]
	if n == 2:
		offsets = [Vector2(-8, 2), Vector2(8, 2)]
	elif n == 3:
		offsets = [Vector2(-10, 4), Vector2(10, 4), Vector2(0, -8)]
	for i in n:
		var spr: Sprite2D
		if i == 0:
			spr = primary_spr
		else:
			spr = Sprite2D.new()
			spr.centered = true
			var sample_tex := primary_tex
			if i - 1 < samples.size():
				var fo: Object = samples[i - 1] as Object if samples[i - 1] is Object else null
				if fo != null:
					var path2 := _unit_tex_path_for_formation_object(fo, era_folder)
					path2 = _prefer_retrowave_unit_icon(path2)
					if tex_cache.has(path2):
						sample_tex = tex_cache[path2] as Texture2D
					elif ResourceLoader.exists(path2):
						sample_tex = load(path2) as Texture2D
						tex_cache[path2] = sample_tex
			spr.texture = sample_tex if sample_tex else primary_tex
			if using_retrowave:
				spr.modulate = Color.WHITE
			else:
				spr.modulate = nation_col
		spr.position = offsets[i]
		spr.z_index = i
		counter.add_child(spr)
	if not nation_tag.is_empty():
		var frame := _make_unit_nation_frame(nation_col)
		frame.z_index = n + 1
		counter.add_child(frame)


func _unit_tex_path_for_formation_object(fo: Object, era_folder: String) -> String:
	var arch := ""
	var dsn := ""
	var ftype := ""
	if fo.has_method("get_category"):
		ftype = str(fo.call("get_category"))
	elif "formation_type" in fo:
		ftype = str(fo.formation_type)
	if "design_id" in fo:
		dsn = str(fo.design_id).to_lower()
	if dsn != "" and typeof(GameData) != TYPE_NIL and GameData.design_data != null:
		var tpl = GameData.design_data.get_template(dsn)
		if tpl != null:
			arch = str(tpl.visual_archetype).to_lower()
	# Lightweight keyword path — UnitIconLibrary for full fidelity when available.
	const UIL = preload("res://scripts/ui/UnitIconLibrary.gd")
	var stem: String = UIL.resolve_stem(ftype, ftype, arch, dsn)
	var p := UIL.icon_path(stem, 32)
	if not p.is_empty():
		return p
	return "res://assets/graphics/units/nato/" + era_folder + "/infantry_32.png"


## Pass 5/8: stack badge when multiple formations share a province (+ pulse meta).
func _make_formation_stack_badge(count: int) -> Node2D:
	var root := Node2D.new()
	root.name = "StackBadge"
	root.position = Vector2(14, -14)
	root.scale = Vector2(0.85, 0.85)
	root.set_meta("eoa_stack_pulse", true)
	root.set_meta("eoa_stack_base_scale", 0.85)
	var badge_path := "res://assets/graphics/icons/hud/stack_badge_circle_24.png"
	if not ResourceLoader.exists(badge_path):
		badge_path = "res://assets/graphics/icons/hud/stack_badge_diamond_24.png"
	if ResourceLoader.exists(badge_path):
		var spr := Sprite2D.new()
		spr.texture = load(badge_path) as Texture2D
		spr.centered = true
		root.add_child(spr)
	else:
		var disc := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 12:
			var a := TAU * float(i) / 12.0
			pts.append(Vector2(cos(a), sin(a)) * 10.0)
		disc.polygon = pts
		disc.color = Color(0.08, 0.1, 0.18, 0.92)
		root.add_child(disc)
	var lbl := Label.new()
	lbl.text = str(mini(count, 99))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.2, 0.95, 1.0, 1.0))
	lbl.position = Vector2(-10, -9)
	lbl.size = Vector2(20, 18)
	root.add_child(lbl)
	_stack_badge_pulse_nodes.append(root)
	return root


func _pulse_stack_badges(delta: float) -> void:
	if _stack_badge_pulse_nodes.is_empty():
		return
	_stack_pulse_phase += delta * 3.2
	var alive: Array = []
	for node_v in _stack_badge_pulse_nodes:
		if node_v == null or not is_instance_valid(node_v):
			continue
		var node: Node2D = node_v as Node2D
		if node == null or not node.is_inside_tree():
			continue
		alive.append(node)
		var base_s := float(node.get_meta("eoa_stack_base_scale", 0.85))
		var pulse := 1.0 + 0.12 * sin(_stack_pulse_phase + float(node.get_instance_id() % 7) * 0.4)
		# Parent DemoUnitIcon may already scale for zoom — only pulse local badge scale.
		node.scale = Vector2.ONE * (base_s * pulse)
		var a := 0.78 + 0.22 * (0.5 + 0.5 * sin(_stack_pulse_phase * 1.15))
		node.modulate = Color(1.0, 1.0, 1.0, a)
	_stack_badge_pulse_nodes = alive


## Riot / crisis event overlay markers (simple Node2D sprites on province nodes for provinces with GameData.active_riots).
## Uses riot_crowd_64 (or generated riot_marker) + small red tint hint. Called on unit refresh + data_changed for live.
## Visible on political map mode or any; inspector hover gets tint from fill.
## Tracked riot marker pids so clear is O(riots) not O(all provinces) on every data_changed.
var _riot_marker_pids: Array = []


func _update_riot_markers() -> void:
	# Clear only previously placed riot markers (not full board scan).
	for id_v in _riot_marker_pids:
		var id := int(id_v)
		if not province_nodes.has(id):
			continue
		var n := province_nodes[id]
		if n == null:
			continue
		for c in n.get_children():
			if c.name.begins_with("RiotMarker_"):
				c.queue_free()
	_riot_marker_pids.clear()

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
		_riot_marker_pids.append(pid)

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

## Full border rebuild is O(all polygon edges) on ~3520 — freezes the main thread.
## Busy-guarded + deferred so combat / capture never calls it synchronously.
var _border_rebuild_busy: bool = false
var _border_rebuild_pending: bool = false


func force_border_update() -> void:
	if _border_rebuild_busy:
		_border_rebuild_pending = true
		return
	_border_rebuild_busy = true
	call_deferred("_force_border_update_deferred")


func _force_border_update_deferred() -> void:
	_update_country_borders()
	_border_rebuild_busy = false
	if _border_rebuild_pending:
		_border_rebuild_pending = false
		# Coalesce: one more pass next idle frame only if still requested.
		call_deferred("force_border_update")


## Light post-capture: recolor + pins for the passed pids only. Skips full-board work.
func refresh_after_capture_light(province_id: int = -1, from_province_id: int = -1, retreat_pid: int = -1) -> void:
	var pids: Array = []
	for v in [province_id, from_province_id, retreat_pid]:
		var pid := int(v)
		if pid >= 0 and not pids.has(pid):
			pids.append(pid)
	_refresh_province_fill_pids(pids)
	_update_unit_icons_for_pids(pids)


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
	_border_lod_tier_built = _map_lod_tier


func _sync_shared_edge_frontiers(_scan_pids: Array) -> void:
	for child in border_layer.get_children():
		var cname := str(child.name)
		if (
			cname.begins_with(COUNTRY_FRONTIER_PREFIX)
			or cname.begins_with(COAST_FRONTIER_PREFIX)
			or cname.begins_with(PROVINCE_EDGE_PREFIX)
		):
			child.queue_free()

	# Build edge map including sea as "__SEA__" so coasts resolve without painting every GIS edge.
	var edge_map: Dictionary = {}
	for pid_var in province_nodes.keys():
		var pid := int(pid_var)
		var owner := _live_owner_tag(pid)
		var is_sea := false
		if provinces.has(pid):
			var pv: Province = provinces[pid] as Province
			if pv != null:
				is_sea = bool(pv.is_sea)
		if owner.is_empty() and not is_sea:
			continue
		if is_sea:
			owner = "__SEA__"
		var pts := _province_polygon_points(pid)
		if pts.size() < 3:
			continue
		for i in pts.size():
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[(i + 1) % pts.size()]
			var key := _canonical_edge_key(a, b)
			if not edge_map.has(key):
				edge_map[key] = {"a": a, "b": b, "owners": {}, "count": 0, "has_sea": false, "has_land": false}
			var rec: Dictionary = edge_map[key]
			rec["owners"][owner] = true
			rec["count"] = int(rec.get("count", 0)) + 1
			if is_sea:
				rec["has_sea"] = true
			else:
				rec["has_land"] = true

	var show_internal := MapZoomLODScript.show_province_internal_borders(_map_lod_tier)
	var intl_w: float = MapZoomLODScript.country_border_width(_map_lod_tier)
	var intl_a: float = MapZoomLODScript.country_border_alpha(_map_lod_tier)
	var coast_w: float = MapZoomLODScript.coast_border_width(_map_lod_tier)
	var internal_w: float = MapZoomLODScript.province_internal_border_width(_map_lod_tier)
	var seg_idx := 0
	var coast_idx := 0
	var internal_idx := 0
	for key in edge_map.keys():
		var rec: Dictionary = edge_map[key]
		var owners: Dictionary = rec.get("owners", {})
		var has_sea: bool = bool(rec.get("has_sea", false))
		var has_land: bool = bool(rec.get("has_land", false))
		# Land owners only (exclude synthetic sea tag)
		var land_owners: Array = []
		for o in owners.keys():
			if str(o) != "__SEA__":
				land_owners.append(str(o))
		var is_international := land_owners.size() >= 2
		var is_coast := has_land and has_sea
		var is_internal_same := land_owners.size() == 1 and not has_sea and int(rec.get("count", 0)) >= 2
		# Unmatched GIS edges (count=1, land only): never draw as country color
		# (that was the Germany spiderweb). Coasts = land↔sea shared edges only.

		var a: Vector2 = rec.get("a", Vector2.ZERO)
		var b: Vector2 = rec.get("b", Vector2.ZERO)
		if is_international:
			var seg := Line2D.new()
			seg.name = COUNTRY_FRONTIER_PREFIX + str(seg_idx)
			seg.points = PackedVector2Array([a, b])
			# Dark frontier (fills = nation color). Slight owner-tint kept tiny for readability.
			var use_color := COUNTRY_BORDER_COLOR
			use_color.a = intl_a
			seg.default_color = use_color
			seg.width = intl_w
			seg.antialiased = true
			seg.joint_mode = Line2D.LINE_JOINT_ROUND
			seg.begin_cap_mode = Line2D.LINE_CAP_ROUND
			seg.end_cap_mode = Line2D.LINE_CAP_ROUND
			seg.z_index = 2
			border_layer.add_child(seg)
			seg_idx += 1
		elif is_coast:
			var cseg := Line2D.new()
			cseg.name = COAST_FRONTIER_PREFIX + str(coast_idx)
			cseg.points = PackedVector2Array([a, b])
			var cc := COAST_BORDER_COLOR
			cseg.default_color = cc
			cseg.width = coast_w
			cseg.antialiased = true
			cseg.joint_mode = Line2D.LINE_JOINT_ROUND
			cseg.begin_cap_mode = Line2D.LINE_CAP_ROUND
			cseg.end_cap_mode = Line2D.LINE_CAP_ROUND
			cseg.z_index = 1
			border_layer.add_child(cseg)
			coast_idx += 1
		elif show_internal and is_internal_same:
			var iseg := Line2D.new()
			iseg.name = PROVINCE_EDGE_PREFIX + str(internal_idx)
			iseg.points = PackedVector2Array([a, b])
			iseg.default_color = PROVINCE_INTERNAL_BORDER_COLOR
			iseg.width = internal_w
			iseg.antialiased = true
			iseg.joint_mode = Line2D.LINE_JOINT_ROUND
			iseg.begin_cap_mode = Line2D.LINE_CAP_ROUND
			iseg.end_cap_mode = Line2D.LINE_CAP_ROUND
			iseg.z_index = 0
			border_layer.add_child(iseg)
			internal_idx += 1



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
			var _wn2 := false
			if MapManager != null and MapManager.has_method("is_geometry_world_native"):
				_wn2 = MapManager.is_geometry_world_native()
			return MapCanvasConfig.transform_province_points(pts, _is_world_canvas_active(), true, _wn2)
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
