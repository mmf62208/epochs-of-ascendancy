# scripts/map/InfrastructureOverlayLayer.gd
## Infrastructure & Development visual layer.
##
## Renders via a combination of immediate _draw (icons, rings, resources, proposed debug) and
## dedicated toggleable/editable sub-layers (Node2D children):
##   RoadLayer  - Line2D for roads (explicit built_road_neighbors or high infra)
##   RailLayer  - Line2D + ties for rails
##   CityLayer  - ColorRect "buildings" + occasional stubs (grows with dev/factories)
##   SitesLayer - runways (airfields), docks/piers (ports/shipyards) as vector elements
##
## All sub-layers support .visible toggle (R/T/C/Y or F10) and are rebuilt on relevant
## province_data_changed signals (projects, explicit builds via MapManager, special sites).
## Nodes carry meta (province_id etc.) making them inspectable/editable from code or tools.
##
## Designed to be lightweight and sit above the base province map
## but below heavier overlays (Conflict, AgentNetwork, Supply, etc.).

class_name InfrastructureOverlayLayer
extends Node2D

const ProvincePolygonUtil = preload("res://scripts/map/ProvincePolygonUtil.gd")

const _MapPolishFormatters := preload("res://scripts/map/MapPolishFormatters.gd")
const _MapNextListHelpers := preload("res://scripts/map/MapNextListHelpers.gd")

@export var infra_icon_size: float = 16.0
@export var site_icon_size: float = 20.0
@export var construction_ring_radius: float = 24.0

# === Phase 1 Map Generation Debug Visualization ===
@export var show_proposed_splits: bool = false  # Only meaningful in debug builds

## Toggleable layers for infrastructure visuals (roads, rails, cities, sites).
## These can be toggled in game/UI/Debug to focus on different map aspects.
## "Editable" via projects in InfrastructureDevelopmentManager which upgrade infra/dev/special sites,
## triggering redraws and visual updates (roads thicken, cities grow, new sites appear with rings).
## Default OFF for clean political readability (HOI-style). Toggle R/T or Infra mapmode.
var show_roads: bool = false
## Edge keys "min_max" on the active supply corridor (bright yellow when G is on).
var _supply_corridor_edges: Dictionary = {}
var show_rails: bool = false
var show_cities: bool = false  # Off by default — toggle C or F10; draw fallback was grey-box spam at playtest zoom.
var show_sites: bool = false  # Off by default on political; enable via Y / Infra mapmode / F10
var proposed_children: Array = []
var proposed_data_loaded: bool = false
const PROPOSED_SPLIT_PATH := "res://tools/map_generation/output/phase1_europe/proposed_children_geometry.json"

var infrastructure_manager: Node
var special_site_manager: Node
var map_manager: Node
var game_data: Node = null  # for active_riots / pending_research culling (include event pids even if not visible)

# Sub-layers for toggleable/editable infrastructure visuals.
# These are Node2D children holding Line2D / other nodes for roads/rails/cities.
# Toggling: set their .visible
# Editing: add/remove/modify child nodes (e.g. Line2D for a new road).
# Rebuilt on demand via rebuild_*_layer() when data changes (e.g. project complete).
var road_layer: Node2D
var rail_layer: Node2D
var city_layer: Node2D
var sites_layer: Node2D  # For airfields, ports, shipyards etc. as toggleable/editable vector elements (runways, docks) in addition to the icon drawing in _draw.

## Era band for sparse 1918 vs default 1936 vs dense 2026+ infra visualization.
var _last_era_band: int = -1
var _infra_rebuild_scheduled: bool = false
var _infra_light_rebuild_scheduled: bool = false
var _last_infra_rebuild_msec: int = 0
const INFRA_REBUILD_MIN_INTERVAL_MS := 1200
## ColorRect city nodes (4500+) freeze pan/zoom; _draw fallback is cheaper for playtest.
const BUILD_CITY_NODES := false
const DRAW_CITY_FALLBACK := false  # When BUILD_CITY_NODES off, skip per-province grey rect fallback (was 472×N rects per redraw).
const MAX_LAYER_PROVINCES := 120
const MAX_CITY_BUILDINGS_PER_PROVINCE := 4

func _ready():
    infrastructure_manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
    special_site_manager = get_node_or_null("/root/SpecialSiteManager")
    map_manager = get_node_or_null("/root/MapManager")
    if typeof(GameData) != TYPE_NIL:
        game_data = GameData
    z_index = 8

    add_to_group("infrastructure_overlay")

    # Setup sub-layers as children (for true layer toggling and node-based editing)
    _ensure_sub_layers()

    if map_manager and map_manager.has_signal("province_data_changed"):
        if not map_manager.province_data_changed.is_connected(_on_province_data_changed):
            map_manager.province_data_changed.connect(_on_province_data_changed)

    if typeof(TimeManager) != TYPE_NIL:
        if TimeManager.has_signal("game_year_advanced") and not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
            TimeManager.game_year_advanced.connect(_on_game_year_advanced)

    call_deferred("refresh_all")
    # Do NOT auto-load proposed Phase1 split JSON on F5 — that data is map-gen debug only.
    # Load on demand when show_proposed_splits is toggled (F10 / Debug).
    call_deferred("rebuild_all_infra_layers")  # initial build of road/rail/city nodes

    # Apply initial visibility to sub-layers (node children handle drawing when visible)
    _apply_layer_visibilities()

    set_process(true)  # track zoom to auto-show/hide detail layers (roads at mid zoom, sites/cities at high zoom) so you can see buildings/roads when zoomed in to a province

func _ensure_sub_layers():
    if road_layer == null:
        road_layer = get_node_or_null("RoadLayer")
        if road_layer == null:
            road_layer = Node2D.new()
            road_layer.name = "RoadLayer"
            road_layer.z_index = 1
            add_child(road_layer)
    if rail_layer == null:
        rail_layer = get_node_or_null("RailLayer")
        if rail_layer == null:
            rail_layer = Node2D.new()
            rail_layer.name = "RailLayer"
            rail_layer.z_index = 2
            add_child(rail_layer)
    if city_layer == null:
        city_layer = get_node_or_null("CityLayer")
        if city_layer == null:
            city_layer = Node2D.new()
            city_layer.name = "CityLayer"
            city_layer.z_index = 3
            add_child(city_layer)
    if sites_layer == null:
        sites_layer = get_node_or_null("SitesLayer")
        if sites_layer == null:
            sites_layer = Node2D.new()
            sites_layer.name = "SitesLayer"
            sites_layer.z_index = 4
            add_child(sites_layer)

func _apply_layer_visibilities():
    _update_sub_layer_visibilities()

func _process(_delta: float) -> void:
    # Only recompute sub-layer visibility every few frames (was every frame on world_full).
    if Engine.get_process_frames() % 8 != 0:
        return
    _update_sub_layer_visibilities()

func _update_sub_layer_visibilities() -> void:
    var z := _get_current_zoom()
    # Zoom thresholds so that at the test's initial auto-frame (~0.40) the layers are visible,
    # but they hide when zoomed far out (you zoom in to province to see fine roads/buildings/sites).
    # User toggles still control the "enabled" state.
    # Operational zoom: roads appear earlier so arteries are readable without deep zoom.
    # World-class pass: slightly earlier road/rail visibility for theater-scale reading.
    if road_layer:
        road_layer.visible = show_roads and z > 0.10
    if rail_layer:
        rail_layer.visible = show_rails and z > 0.14
    if city_layer or sites_layer:
        # Dense GIS boards: cities/factories only at operational zoom (plan A3 LOD).
        var board_n := 0
        if map_manager and map_manager.has_method("get_province_count"):
            board_n = int(map_manager.get_province_count())
        const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")
        if city_layer:
            var city_z := float(MapZoomLODScript.city_marker_min_zoom_for_board(board_n))
            city_layer.visible = show_cities and z > city_z
        if sites_layer:
            var site_z := float(MapZoomLODScript.site_marker_min_zoom_for_board(board_n))
            sites_layer.visible = show_sites and z > site_z
    elif sites_layer:
        sites_layer.visible = show_sites and z > 0.32
    _maybe_rebuild_for_era_change()


func _get_map_year() -> int:
    if typeof(TimeManager) != TYPE_NIL and TimeManager.has_method("get_current_year"):
        return int(TimeManager.get_current_year())
    return 1936


func _get_era_band(year: int) -> int:
    if year <= 1924:
        return 0  # sparse interwar / 1918
    if year >= 2000:
        return 2  # modern dense network
    return 1  # 1925–1999 baseline (1936 theater default)


## Thresholds and colors for era-appropriate road/rail/city density (same geometry, different visual era).
func _get_era_infra_profile() -> Dictionary:
    var year := _get_map_year()
    var band := _get_era_band(year)
    match band:
        0:
            return {
                "label": "sparse_1918",
                "year": year,
                "road_infra_min": 5.0,
                "rail_infra_min": 9.0,
                "city_dev_min": 5.0,
                "road_width_explicit": 2.0,
                "road_width_implicit": 1.0,
                "road_color_explicit": Color(0.52, 0.46, 0.36, 0.72),
                "road_color_implicit": Color(0.58, 0.52, 0.42, 0.45),
                "rail_color": Color(0.28, 0.24, 0.22, 0.75),
                "rail_width": 1.8,
                "rail_tie_step": 45.0,
            }
        2:
            return {
                "label": "dense_2026",
                "year": year,
                "road_infra_min": 2.0,
                "rail_infra_min": 4.0,
                "city_dev_min": 2.0,
                "road_width_explicit": 4.0,
                "road_width_implicit": 2.5,
                "road_color_explicit": Color(0.32, 0.34, 0.38, 0.92),
                "road_color_implicit": Color(0.38, 0.40, 0.44, 0.78),
                "rail_color": Color(0.12, 0.14, 0.18, 0.95),
                "rail_width": 3.0,
                "rail_tie_step": 22.0,
            }
        _:
            return {
                "label": "standard_1936",
                "year": year,
                "road_infra_min": 3.0,
                "rail_infra_min": 6.0,
                "city_dev_min": 3.0,
                "road_width_explicit": 3.6,
                "road_width_implicit": 2.0,
                "road_color_explicit": Color(0.42, 0.36, 0.28, 0.92),
                "road_color_implicit": Color(0.45, 0.40, 0.32, 0.72),
                "rail_color": Color(0.18, 0.20, 0.28, 0.95),
                "rail_width": 2.9,
                "rail_tie_step": 28.0,
            }


func _maybe_rebuild_for_era_change() -> void:
    var band := _get_era_band(_get_map_year())
    if band == _last_era_band:
        return
    _last_era_band = band
    rebuild_all_infra_layers()


func _on_game_year_advanced(_year: int) -> void:
    _maybe_rebuild_for_era_change()


## Public readout for harness / inspector (1918 sparse vs 1936 vs 2026 dense).
func get_era_infra_profile() -> Dictionary:
    return _get_era_infra_profile()


## Pure year→band helper (testable without TimeManager).
static func era_band_for_year(year: int) -> int:
    if year <= 1924:
        return 0
    if year >= 2000:
        return 2
    return 1


## Pure year→profile (mirrors match in _get_era_infra_profile; no TimeManager).
static func era_infra_profile_for_year(year: int) -> Dictionary:
    var band := era_band_for_year(year)
    match band:
        0:
            return {
                "label": "sparse_1918",
                "year": year,
                "band": 0,
                "road_infra_min": 5.0,
                "rail_infra_min": 9.0,
                "city_dev_min": 5.0,
                "road_width_explicit": 2.0,
                "road_width_implicit": 1.0,
                "rail_width": 1.8,
                "rail_tie_step": 45.0,
            }
        2:
            return {
                "label": "dense_2026",
                "year": year,
                "band": 2,
                "road_infra_min": 2.0,
                "rail_infra_min": 4.0,
                "city_dev_min": 2.0,
                "road_width_explicit": 4.0,
                "road_width_implicit": 2.5,
                "rail_width": 3.0,
                "rail_tie_step": 22.0,
            }
        _:
            return {
                "label": "standard_1936",
                "year": year,
                "band": 1,
                "road_infra_min": 3.0,
                "rail_infra_min": 6.0,
                "city_dev_min": 3.0,
                "road_width_explicit": 3.6,
                "road_width_implicit": 2.0,
                "rail_width": 2.9,
                "rail_tie_step": 28.0,
            }

# Simple view culling helper: only consider provinces near the current camera for node population.
# Enhanced for perf/scale: also force-include "active" provinces (player/major owned, border-ish via adj, high pop/econ if data, + crucially GameData active_riots / pending research ethics pids).
# Keeps draw/node count low for 50T scale while event visuals (riots) always show when active.
func _get_visible_provinces() -> Dictionary:
    if map_manager == null:
        return {}
    var cam := get_viewport().get_camera_2d()
    var all: Dictionary = map_manager.get_all_provinces()
    var visible := {}
    if cam == null:
        # fallback but still apply event culling if possible
        visible = all.duplicate()
    else:
        var center := cam.get_screen_center_position()
        var radius: float = 1200.0 / max(_get_current_zoom(), 0.1)  # larger radius when zoomed out
        for pid in all:
            var p = all[pid]
            # Use safe centroid from MapManager (Province Resource has .coordinates, not .center; avoids "Invalid access on Resource (Province)")
            var pc: Vector2 = map_manager.get_province_centroid(pid) if map_manager else Vector2.ZERO
            if p and pc.distance_to(center) < radius:
                visible[pid] = p
        # also include direct neighbors of visible for connections that cross the edge
        var adj = map_manager.get_adjacency_system()
        if adj:
            for pid in visible.keys():
                for nb in adj.get_land_neighbors(pid):
                    if all.has(nb) and not visible.has(nb):
                        visible[nb] = all[nb]
    # Perf culling enhancement: force active event provinces (riots from GameData, pending research tags' capitals or owned) + majors/player for 50T scale (skip rand light provinces)
    if game_data and game_data.has_method("get_provinces_with_active_riots"):
        for pid in game_data.get_provinces_with_active_riots():
            if all.has(pid) and not visible.has(pid):
                visible[pid] = all[pid]
    if game_data and game_data.has_method("get_tags_with_pending_research"):
        for tag in game_data.get_tags_with_pending_research():
            if map_manager and map_manager.has_method("get_provinces_by_owner"):
                for opid in map_manager.call("get_provinces_by_owner", tag):
                    if all.has(opid) and not visible.has(opid):
                        visible[opid] = all[opid]
    # Always include at least player tag if known (assume GER as default major for evidence)
    var player_tags := ["GER", "FRA", "ENG", "SOV"]
    for ptag in player_tags:
        if map_manager and map_manager.has_method("get_provinces_by_owner"):
            for pp in map_manager.call("get_provinces_by_owner", ptag):
                if all.has(pp) and not visible.has(pp):
                    visible[pp] = all[pp]
                    if visible.size() > 80: break  # cap for headless perf
    return visible


## Stable province set for road/rail/city node layers (never depends on camera — pan/zoom must not trigger rebuild storms).
func _get_provinces_for_layers() -> Dictionary:
    if map_manager == null:
        return {}
    var all: Dictionary = map_manager.get_all_provinces()
    var out: Dictionary = {}
    var major_tags: Array[String] = ["GER", "FRA", "ENG", "SOV", "USA", "ITA", "POL", "JAP"]
    for tag in major_tags:
        if map_manager.has_method("get_provinces_by_owner"):
            for pid in map_manager.get_provinces_by_owner(tag):
                if all.has(pid) and not out.has(pid):
                    out[pid] = all[pid]
    if game_data and game_data.has_method("get_provinces_with_active_riots"):
        for pid in game_data.get_provinces_with_active_riots():
            if all.has(pid):
                out[pid] = all[pid]
    if out.size() < MAX_LAYER_PROVINCES:
        var ranked: Array[Dictionary] = []
        for pid in all:
            var p: Province = all[pid]
            if p == null or p.is_sea or out.has(pid):
                continue
            ranked.append({
                "pid": pid,
                "score": p.development_level + p.factories * 2 + int(p.infrastructure),
            })
        ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            return int(a.get("score", 0)) > int(b.get("score", 0))
        )
        for entry in ranked:
            if out.size() >= MAX_LAYER_PROVINCES:
                break
            var pick_pid: int = int(entry.get("pid", -1))
            if all.has(pick_pid):
                out[pick_pid] = all[pick_pid]
    return out

## Rebuild the road layer using explicit built roads from provinces (or fallback to infra level).
## Call this after any "build road" decision or project complete.
func rebuild_road_layer():
    if road_layer == null:
        _ensure_sub_layers()
    # Robust clear: remove immediately then queue_free to prevent accumulation on rapid successive rebuilds (e.g. many data updates in test harness)
    var kids = road_layer.get_children()
    for k in kids:
        road_layer.remove_child(k)
        k.queue_free()

    if not show_roads:
        return  # don't populate nodes for hidden layer (saves resources when toggled off)

    if map_manager == null:
        return

    var provinces = _get_provinces_for_layers()
    var adjacency = map_manager.get_adjacency_system()
    if adjacency == null or provinces.is_empty():
        return

    var era: Dictionary = _get_era_infra_profile()
    var road_min: float = float(era.get("road_infra_min", 3.0))

    var drawn := {}
    for pid in provinces:
        var p: Province = provinces[pid]
        if p == null or p.is_sea:
            continue
        var neighbors = adjacency.get_land_neighbors(pid)
        var c1 = map_manager.get_province_centroid(pid)
        for nid in neighbors:
            if not provinces.has(nid):
                continue  # culling
            var key = "%d_%d" % [min(pid, nid), max(pid, nid)]
            if drawn.has(key):
                continue
            drawn[key] = true
            var n: Province = provinces.get(nid)
            if n == null or n.is_sea:
                continue
            # Check explicit built_roads or fallback to high infra
            var has_explicit = (nid in p.built_road_neighbors) or (pid in (n.built_road_neighbors if n else []))
            var avg_infra = (p.infrastructure + n.infrastructure) / 2.0
            if not has_explicit and avg_infra < road_min:
                continue
            var c2 = map_manager.get_province_centroid(nid)
            # Art-team road palette (F5/G spiderweb fix):
            # Supply mode draws ONLY corridor edges (bright). No adjacency mesh, no spines.
            # Empty corridor set → draw nothing (SupplyMapLayer highlight owns the path).
            var supply_on := false
            var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
            if mr != null and bool(mr.get("supply_mode")):
                supply_on = true
            # Also treat map_mode supply/munitions as "supply styling" if property lags rebuild.
            if mr != null and str(mr.get("current_map_mode")) in ["supply", "munitions"]:
                supply_on = true
            var on_corridor := _edge_on_supply_corridor(pid, nid, mr)
            var tier := 0  # 0 low, 1 mid, 2 high
            if has_explicit or avg_infra >= road_min + 3.0:
                tier = 2 if avg_infra >= road_min + 6.0 or has_explicit else 1
            elif avg_infra >= road_min:
                tier = 1
            # Supply / F5 / G: corridor-only. Skip every non-corridor edge (kills spiderweb).
            if supply_on and not on_corridor:
                continue
            if supply_on and on_corridor:
                var glow := Line2D.new()
                glow.points = [c1, c2]
                glow.antialiased = true
                glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
                glow.end_cap_mode = Line2D.LINE_CAP_ROUND
                glow.default_color = Color(1.00, 0.78, 0.12, 0.28)
                glow.width = 5.0
                glow.z_index = 3
                glow.set_meta("p1", pid)
                glow.set_meta("p2", nid)
                glow.set_meta("glow", true)
                road_layer.add_child(glow)
            var line := Line2D.new()
            line.points = [c1, c2]
            line.antialiased = true
            if supply_on:
                # Corridor only (non-corridor already continue'd).
                line.default_color = Color(1.00, 0.92, 0.28, 0.88)
                line.width = 2.8
                line.z_index = 4
                line.begin_cap_mode = Line2D.LINE_CAP_ROUND
                line.end_cap_mode = Line2D.LINE_CAP_ROUND
            else:
                # Infra mapmode only (political never rebuilds roads): dust roads, never neon.
                if tier >= 2:
                    line.default_color = Color(0.40, 0.34, 0.22, 0.38)
                    line.width = 2.0
                    line.z_index = 2
                elif tier >= 1:
                    line.default_color = Color(0.36, 0.32, 0.24, 0.26)
                    line.width = 1.5
                    line.z_index = 1
                else:
                    line.default_color = Color(0.32, 0.30, 0.26, 0.16)
                    line.width = 1.1
                    line.z_index = 0
            line.set_meta("p1", pid)
            line.set_meta("p2", nid)
            line.set_meta("explicit", has_explicit)
            line.set_meta("tier", tier)
            line.set_meta("corridor", on_corridor)
            road_layer.add_child(line)

## Similar for rails - higher threshold, distinct style (e.g. dashed via multiple segments or color)
func rebuild_rail_layer():
    if rail_layer == null:
        _ensure_sub_layers()
    var kids = rail_layer.get_children()
    for k in kids:
        rail_layer.remove_child(k)
        k.queue_free()

    if not show_rails:
        return

    if map_manager == null:
        return

    var provinces = _get_provinces_for_layers()
    var adjacency = map_manager.get_adjacency_system()
    if adjacency == null or provinces.is_empty():
        return

    var era: Dictionary = _get_era_infra_profile()
    var rail_min: float = float(era.get("rail_infra_min", 6.0))
    var tie_step: float = float(era.get("rail_tie_step", 30.0))

    var drawn := {}
    for pid in provinces:
        var p: Province = provinces[pid]
        if p == null or p.is_sea:
            continue
        var neighbors = adjacency.get_land_neighbors(pid)
        var c1 = map_manager.get_province_centroid(pid)
        for nid in neighbors:
            if not provinces.has(nid):
                continue
            var key = "%d_%d" % [min(pid, nid), max(pid, nid)]
            if drawn.has(key):
                continue
            drawn[key] = true
            var n: Province = provinces.get(nid)
            if n == null or n.is_sea:
                continue
            var has_explicit = (nid in p.built_rail_neighbors) or (pid in (n.built_rail_neighbors if n else []))
            var avg_infra = (p.infrastructure + n.infrastructure) / 2.0
            if not has_explicit and avg_infra < rail_min:
                continue
            var c2 = map_manager.get_province_centroid(nid)
            var line := Line2D.new()
            line.points = [c1, c2]
            line.width = float(era.get("rail_width", 2.5))
            line.default_color = era.get("rail_color", Color(0.2, 0.2, 0.25, 0.9))
            line.z_index = 2
            line.set_meta("p1", pid)
            line.set_meta("p2", nid)
            line.set_meta("explicit", has_explicit)
            rail_layer.add_child(line)
            # Simple ties for rail look
            var dist = c1.distance_to(c2)
            var steps = max(2, int(dist / tie_step))
            for s in range(1, steps):
                var t = float(s) / steps
                var mid = c1.lerp(c2, t)
                var perp = (c2 - c1).normalized().rotated(PI/2) * 5
                var tie := Line2D.new()
                tie.points = [mid - perp, mid + perp]
                tie.width = 1.5
                tie.default_color = Color(0.15, 0.15, 0.18, 0.8)
                tie.z_index = 2
                rail_layer.add_child(tie)

## City/urban layer: populates Node2D children (ColorRect building proxies) so the layer is fully
## toggleable (.visible) and editable (add/remove/modify per-province building nodes, attach metadata).
## We still keep a fallback/improved _draw_cities for cases where sub-layer is empty or for very dense detail.
func rebuild_city_layer():
    if city_layer == null:
        _ensure_sub_layers()
    var kids = city_layer.get_children()
    for k in kids:
        city_layer.remove_child(k)
        k.queue_free()

    if not show_cities or not BUILD_CITY_NODES:
        return

    if map_manager == null:
        return

    var provinces = _get_provinces_for_layers()
    var era: Dictionary = _get_era_infra_profile()
    var city_dev_min: float = float(era.get("city_dev_min", 3.0))
    for pid in provinces:
        var p: Province = provinces[pid]
        if p == null or p.is_sea:
            continue
        var center = map_manager.get_province_centroid(pid)
        var dev = p.development_level
        var fact = p.factories
        if dev < city_dev_min:
            continue
        var pop_factor = clampf(p.population / 500000.0, 0.5, 4.0)
        var num = mini(MAX_CITY_BUILDINGS_PER_PROVINCE, min(10, int(2 + dev * 0.8 + fact * 0.3 + pop_factor)))
        for i in range(num):
            var angle = (i * 2.3) + (pid % 5) * 0.5
            var dist = 4.0 + (i % 4) * 2.5 + (2.0 if dev > 6 else 0.0)
            var off = Vector2(cos(angle), sin(angle)) * dist
            var bsize = 2.5 + (dev / 4.0) + (1.0 if fact > 2 else 0.0)
            var bcol = Color(0.22, 0.22, 0.26, 0.65 + (dev * 0.02))
            if fact > 3:
                bcol = Color(0.18, 0.20, 0.25, 0.75)
            var b := ColorRect.new()
            b.size = Vector2(bsize, bsize)
            b.position = center + off - Vector2(bsize * 0.5, bsize * 0.5)
            b.color = bcol
            b.set_meta("province_id", pid)
            b.set_meta("building_index", i)
            city_layer.add_child(b)
            # occasional road stub from the building cluster
            if i % 3 == 0 and dev > 4:
                var stub_dir = off.normalized() * (bsize + 3)
                var stub := Line2D.new()
                stub.points = [center + off, center + off + stub_dir * 0.6]
                stub.width = 1.0
                stub.default_color = Color(0.35, 0.33, 0.30, 0.4)
                stub.z_index = 3
                city_layer.add_child(stub)

## Sites layer: vector elements for special infrastructure (airfields = runways, ports = docks/anchors, etc.).
## These sit on their own toggleable Node2D child so they can be edited (add/remove Line2D shapes) independently
## of the fancy unicode icon + ring drawing that stays in _draw for readability.
func rebuild_sites_layer():
    if sites_layer == null:
        _ensure_sub_layers()
    var kids = sites_layer.get_children()
    for k in kids:
        sites_layer.remove_child(k)
        k.queue_free()

    if not show_sites:
        return

    if map_manager == null:
        return

    var provinces = _get_provinces_for_layers()
    for pid in provinces:
        var p: Province = provinces[pid]
        if p == null or p.is_sea:
            continue
        var center = map_manager.get_province_centroid(pid)
        var has_air := false
        var has_port := false
        var has_factory := false
        var has_refinery := false
        for site in p.special_sites:
            if site and site.construction_state != SpecialSite.ConstructionState.NOT_BUILT:
                if site.site_type == SpecialSite.SiteType.AIRFIELD:
                    has_air = true
                elif site.site_type == SpecialSite.SiteType.PORT or site.site_type == SpecialSite.SiteType.NAVAL_SHIPYARD:
                    has_port = true
                elif site.site_type == SpecialSite.SiteType.FACTORY:
                    has_factory = true
                elif site.site_type == SpecialSite.SiteType.OIL_REFINERY:
                    has_refinery = true
        if has_air:
            # Simple crossed runway
            var rlen := 18.0
            var rw1 := Line2D.new()
            rw1.points = [center + Vector2(-rlen, 0), center + Vector2(rlen, 0)]
            rw1.width = 2.0
            rw1.default_color = Color(0.25, 0.25, 0.35, 0.9)
            rw1.z_index = 4
            rw1.set_meta("province_id", pid)
            rw1.set_meta("type", "runway")
            sites_layer.add_child(rw1)
            var rw2 := Line2D.new()
            rw2.points = [center + Vector2(0, -rlen*0.6), center + Vector2(0, rlen*0.6)]
            rw2.width = 2.0
            rw2.default_color = Color(0.25, 0.25, 0.35, 0.9)
            rw2.z_index = 4
            rw2.set_meta("province_id", pid)
            rw2.set_meta("type", "runway")
            sites_layer.add_child(rw2)
        if has_port:
            # Simple dock / pier representation
            var dock := Line2D.new()
            dock.points = [center + Vector2(-12, 8), center + Vector2(12, 8), center + Vector2(8, 14), center + Vector2(-8, 14), center + Vector2(-12, 8)]
            dock.width = 2.5
            dock.default_color = Color(0.3, 0.28, 0.25, 0.85)
            dock.z_index = 4
            dock.set_meta("province_id", pid)
            dock.set_meta("type", "dock")
            sites_layer.add_child(dock)
            # Small anchor-ish mark
            var anc := Line2D.new()
            anc.points = [center + Vector2(0, 4), center + Vector2(0, 12)]
            anc.width = 1.5
            anc.default_color = Color(0.2, 0.2, 0.22, 0.9)
            anc.z_index = 4
            anc.set_meta("province_id", pid)
            anc.set_meta("type", "anchor")
            sites_layer.add_child(anc)
        if has_factory:
            # Factory: main building + chimney
            var fact := ColorRect.new()
            fact.size = Vector2(10, 8)
            fact.position = center - fact.size * 0.5
            fact.color = Color(0.2, 0.2, 0.22, 0.8)
            fact.z_index = 4
            fact.set_meta("province_id", pid)
            fact.set_meta("type", "factory")
            sites_layer.add_child(fact)
            var chim := Line2D.new()
            chim.points = [center + Vector2(2, -4), center + Vector2(2, -10)]
            chim.width = 1.5
            chim.default_color = Color(0.15, 0.15, 0.15, 0.9)
            chim.z_index = 4
            chim.set_meta("province_id", pid)
            chim.set_meta("type", "chimney")
            sites_layer.add_child(chim)
        if has_refinery:
            # Refinery: a couple of tank circles (approximated with small rects + line) + pipe
            var t1 := ColorRect.new()
            t1.size = Vector2(6, 6)
            t1.position = center + Vector2(-8, -3)
            t1.color = Color(0.18, 0.18, 0.2, 0.85)
            t1.z_index = 4
            t1.set_meta("province_id", pid)
            t1.set_meta("type", "tank")
            sites_layer.add_child(t1)
            var t2 := ColorRect.new()
            t2.size = Vector2(5, 5)
            t2.position = center + Vector2(3, -2)
            t2.color = Color(0.18, 0.18, 0.2, 0.85)
            t2.z_index = 4
            t2.set_meta("province_id", pid)
            t2.set_meta("type", "tank")
            sites_layer.add_child(t2)
            var pipe := Line2D.new()
            pipe.points = [center + Vector2(-5, 0), center + Vector2(5, 1)]
            pipe.width = 1.2
            pipe.default_color = Color(0.25, 0.25, 0.28, 0.8)
            pipe.z_index = 4
            pipe.set_meta("province_id", pid)
            pipe.set_meta("type", "pipe")
            sites_layer.add_child(pipe)

func rebuild_all_infra_layers():
    _last_era_band = _get_era_band(_get_map_year())
    rebuild_road_layer()
    rebuild_rail_layer()
    if BUILD_CITY_NODES:
        rebuild_city_layer()
    rebuild_sites_layer()
    queue_redraw()
    _last_infra_rebuild_msec = Time.get_ticks_msec()
    # Helpful confirmation for tests/demos (visible in headless logs too). Only logs when counts actually change, to show evolution (e.g. sites ramping up after spawns) without spam.
    if OS.is_debug_build() or Engine.is_editor_hint():
        var road_count := road_layer.get_child_count() if road_layer else 0
        var rail_count := rail_layer.get_child_count() if rail_layer else 0
        var city_count := city_layer.get_child_count() if city_layer else 0
        var site_count := sites_layer.get_child_count() if sites_layer else 0
        var total = road_count + rail_count + city_count + site_count
        if total > 0:
            var last = get_meta("last_infra_layer_counts", Vector4i(-1,-1,-1,-1))
            var curr = Vector4i(road_count, rail_count, city_count, site_count)
            if curr != last:
                set_meta("last_infra_layer_counts", curr)
                var era_label := str(_get_era_infra_profile().get("label", "standard"))
                print("InfrastructureOverlayLayer: Dynamic infra layers built (era=%s roads:%d rail-ties:%d cities:%d sites:%d). Toggle with R/T/C/Y or F10." % [era_label, road_count, rail_count, city_count, site_count])


func rebuild_roads_rails_sites_only() -> void:
    rebuild_road_layer()
    rebuild_rail_layer()
    rebuild_sites_layer()
    queue_redraw()
    _last_infra_rebuild_msec = Time.get_ticks_msec()


func _schedule_rebuild_all_infra_layers() -> void:
    _queue_infra_rebuild(false)


func _schedule_rebuild_light_infra_layers() -> void:
    _queue_infra_rebuild(true)


func _queue_infra_rebuild(light_only: bool) -> void:
    if light_only:
        if _infra_light_rebuild_scheduled or _infra_rebuild_scheduled:
            return
    elif _infra_rebuild_scheduled:
        return
    var now := Time.get_ticks_msec()
    var elapsed := now - _last_infra_rebuild_msec
    if elapsed >= INFRA_REBUILD_MIN_INTERVAL_MS:
        if light_only:
            _deferred_rebuild_light_infra_layers()
        else:
            _deferred_rebuild_all_infra_layers()
        return
    if light_only:
        _infra_light_rebuild_scheduled = true
    else:
        _infra_rebuild_scheduled = true
    var wait_sec := maxf(float(INFRA_REBUILD_MIN_INTERVAL_MS - elapsed) / 1000.0, 0.05)
    var cb := _deferred_rebuild_light_infra_layers if light_only else _deferred_rebuild_all_infra_layers
    get_tree().create_timer(wait_sec).timeout.connect(cb, CONNECT_ONE_SHOT)


func _deferred_rebuild_all_infra_layers() -> void:
    _infra_rebuild_scheduled = false
    _infra_light_rebuild_scheduled = false
    rebuild_all_infra_layers()


func _deferred_rebuild_light_infra_layers() -> void:
    _infra_light_rebuild_scheduled = false
    rebuild_roads_rails_sites_only()

## Public API for external editing/inspection of the layers (supports "editable as needed").
## E.g. from UI, AI, or debug tools: find a specific road node by pids and modify its width/color/points directly.
## Note: for data consistency, prefer MapManager.build_* / remove_* which update Province data and trigger rebuild.
func get_road_layer() -> Node2D: return road_layer
func get_rail_layer() -> Node2D: return rail_layer
func get_city_layer() -> Node2D: return city_layer
func get_sites_layer() -> Node2D: return sites_layer

func find_road_node(p1: int, p2: int) -> Line2D:
    if not road_layer: return null
    for child in road_layer.get_children():
        if child is Line2D and child.get_meta("p1", -1) in [p1, p2] and child.get_meta("p2", -1) in [p1, p2]:
            return child
    return null

func find_rail_node(p1: int, p2: int) -> Line2D:
    if not rail_layer: return null
    for child in rail_layer.get_children():
        if child is Line2D and child.get_meta("p1", -1) in [p1, p2] and child.get_meta("p2", -1) in [p1, p2]:
            return child
    return null

func find_site_nodes(province_id: int) -> Array:
    if not sites_layer: return []
    var res := []
    for child in sites_layer.get_children():
        if child.get_meta("province_id", -1) == province_id:
            res.append(child)
    return res


func _on_province_data_changed(_pid: int, what: String):
    if what in ["infrastructure", "development", "special_site", "infrastructure_project", "effects", "all"]:
        if what in ["development", "special_site", "all"]:
            _schedule_rebuild_all_infra_layers()
        elif what in ["infrastructure", "infrastructure_project"]:
            _schedule_rebuild_light_infra_layers()
        else:
            queue_redraw()


func refresh_all():
    queue_redraw()


# === Proposed Splits (Phase 1 Map Gen Debug) ===
func _try_load_proposed_splits():
    if not OS.is_debug_build():
        return

    var file = FileAccess.open(PROPOSED_SPLIT_PATH, FileAccess.READ)
    if file == null:
        # Also try a few common dev paths outside res:// (very useful when iterating on the Python splitter)
        var alt_paths = [
            "tools/map_generation/output/phase1_europe/proposed_children_geometry.json",
            "../tools/map_generation/output/phase1_europe/proposed_children_geometry.json",
            "../../tools/map_generation/output/phase1_europe/proposed_children_geometry.json"
        ]
        for alt in alt_paths:
            if FileAccess.file_exists(alt):
                file = FileAccess.open(alt, FileAccess.READ)
                if file != null:
                    break

    if file == null:
        push_warning("InfrastructureOverlayLayer: Could not load proposed_children_geometry.json")
        return

    var text = file.get_as_text()
    file.close()

    var data = JSON.parse_string(text)
    if data == null or not data.has("proposed_children"):
        push_warning("InfrastructureOverlayLayer: Invalid proposed split JSON format")
        return

    proposed_children = data["proposed_children"]
    proposed_data_loaded = true
    print("InfrastructureOverlayLayer: Loaded %d proposed Phase 1 child provinces (raw generator output)." % proposed_children.size())


func toggle_proposed_splits():
    if not OS.is_debug_build():
        return
    show_proposed_splits = not show_proposed_splits
    if show_proposed_splits and not proposed_data_loaded:
        _try_load_proposed_splits()
    queue_redraw()


func set_show_proposed_splits(enabled: bool):
    if not OS.is_debug_build():
        return
    show_proposed_splits = enabled
    if enabled:
        _try_load_proposed_splits()
    queue_redraw()

## Toggle infrastructure sub-layers. Called from DebugOverlay, options, or hotkeys.
## Now properly controls the Node2D sub-layer visibility (RoadLayer etc) for true toggle + node editing.
func set_show_roads(enabled: bool):
    var was_on = show_roads
    show_roads = enabled
    if road_layer:
        road_layer.visible = show_roads
    if show_roads and not was_on:
        rebuild_road_layer()
    elif not show_roads:
        # Political F1 / hide: wipe Line2D children so faint roads cannot linger.
        _clear_road_layer_children()
    queue_redraw()


func _clear_road_layer_children() -> void:
    if road_layer == null:
        return
    var kids = road_layer.get_children()
    for k in kids:
        road_layer.remove_child(k)
        k.queue_free()


## Mark capital→front path edges for bright yellow corridor styling (supply mode).
func set_supply_corridor_path(province_path: Array) -> void:
    _supply_corridor_edges.clear()
    if province_path.size() < 2:
        if show_roads:
            rebuild_road_layer()
        return
    for i in range(province_path.size() - 1):
        var a := int(province_path[i])
        var b := int(province_path[i + 1])
        if a <= 0 or b <= 0:
            continue
        var key := "%d_%d" % [mini(a, b), maxi(a, b)]
        _supply_corridor_edges[key] = true
    if show_roads:
        rebuild_road_layer()
    queue_redraw()


func clear_supply_corridor_path() -> void:
    if _supply_corridor_edges.is_empty():
        return
    _supply_corridor_edges.clear()
    if show_roads:
        rebuild_road_layer()
    queue_redraw()


func _edge_on_supply_corridor(pid: int, nid: int, _mr: Variant = null) -> bool:
    if _supply_corridor_edges.is_empty():
        return false
    var key := "%d_%d" % [mini(pid, nid), maxi(pid, nid)]
    return _supply_corridor_edges.has(key)

func set_show_rails(enabled: bool):
    var was_on = show_rails
    show_rails = enabled
    if rail_layer:
        rail_layer.visible = show_rails
    if show_rails and not was_on:
        rebuild_rail_layer()
    queue_redraw()

func set_show_cities(enabled: bool):
    var was_on = show_cities
    show_cities = enabled
    if city_layer:
        city_layer.visible = show_cities
    if show_cities and not was_on:
        rebuild_city_layer()
    queue_redraw()

func set_show_sites(enabled: bool):
    var was_on = show_sites
    show_sites = enabled
    if sites_layer:
        sites_layer.visible = show_sites
    if show_sites and not was_on:
        rebuild_sites_layer()
    queue_redraw()

func toggle_roads():
    set_show_roads(not show_roads)

func toggle_rails():
    set_show_rails(not show_rails)

func toggle_cities():
    set_show_cities(not show_cities)

func toggle_sites():
    set_show_sites(not show_sites)


func reload_proposed_splits():
    """Force reload the latest raw proposed children from disk.
    Call this after editing subdivision_utils.py and re-running the Python generator."""
    proposed_data_loaded = false
    proposed_children.clear()
    _try_load_proposed_splits()
    queue_redraw()
    print("InfrastructureOverlayLayer: Reloaded raw proposed splits from disk.")


func force_full_refresh():
    """Called by DebugOverlay and other tools to force a complete redraw."""
    _try_load_proposed_splits()
    rebuild_all_infra_layers()
    queue_redraw()


func toggle_legend():
    """Minimal implementation to satisfy existing DebugOverlay calls.
    In a fuller version this would show/hide the full legend panel."""
    # For now we just force a refresh so any legend elements redraw.
    queue_redraw()


func _draw():
    if not map_manager:
        return

    var zoom := _get_current_zoom()
    var draw_provs: Dictionary = _get_provinces_for_layers()

    # Sub-layer Node2D children handle roads/rails/sites when visible. Cities only via nodes or explicit fallback.
    if show_cities and DRAW_CITY_FALLBACK:
        if not (city_layer and city_layer.get_child_count() > 0):
            _draw_cities_culled(zoom, draw_provs)

    _draw_resource_icons_culled(zoom, draw_provs)

    if show_proposed_splits and OS.is_debug_build():
        _draw_proposed_splits(zoom)

    # Infra level numbers ("4" circle spam) only on infra mapmode or when roads layer is on.
    # Political default stays clean solid fills (player playtest 2026-07-28).
    var show_infra_nums := false
    if show_roads or show_rails:
        show_infra_nums = zoom >= 0.85
    if typeof(MapManager) != TYPE_NIL:
        pass
    # MapRenderer may set meta when current_map_mode == infra
    var mr := get_tree().get_first_node_in_group("map_renderer") if get_tree() else null
    if mr != null and str(mr.get("current_map_mode")) == "infra":
        show_infra_nums = zoom >= 0.45

    var drawn_chokes: Dictionary = {}
    for province_id in draw_provs:
        var province: Province = draw_provs[province_id]
        if province == null:
            continue

        var center = map_manager.get_province_centroid(province_id)

        var infra_level = province.infrastructure
        if show_infra_nums and infra_level >= 1 and not province.is_sea:
            _draw_infrastructure_marker(center, infra_level)

        if infrastructure_manager and infrastructure_manager.has_method("has_active_project") and infrastructure_manager.has_active_project(province_id):
            var proj_prog := 0.0
            if infrastructure_manager.has_method("get_project_progress"):
                proj_prog = infrastructure_manager.get_project_progress(province_id)
            var sabotaged := false
            if infrastructure_manager.has_method("is_project_sabotaged"):
                sabotaged = infrastructure_manager.is_project_sabotaged(province_id)
            _draw_active_project_marker(center, proj_prog, sabotaged, infra_level)

        # Damage/sabotage marker from live state (infra sabo, depot, site damage, project sabo).
        if zoom > 0.10:
            var dmg: Dictionary = ProvinceInsight.classify_province_map_damage(province)
            if bool(dmg.get("is_damaged", false)):
                _draw_damage_sabotage_marker(center, dmg)

        # Naval chokepoint marker: contest-aware color (cyan controlled, amber contested, dim unowned).
        if map_manager and map_manager.has_method("has_strategic_chokepoint") and map_manager.has_strategic_chokepoint(province_id):
            if zoom > 0.10:
                _draw_chokepoint_for_pid(province_id, province, center)
                drawn_chokes[int(province_id)] = true

        # HH monthly map signal marker on targeted province (+ secondary concurrent pulse).
        if zoom > 0.08 and typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state"):
            var ps: Dictionary = GameData.get_peace_state()
            var sig: Dictionary = ps.get("hh_last_map_signal", {}) if ps is Dictionary else {}
            if bool(sig.get("active", false)) and int(sig.get("province_id", -1)) == province_id:
                _draw_hh_map_signal_marker(center, sig)
            var sig2: Dictionary = ps.get("hh_secondary_map_signal", {}) if ps is Dictionary else {}
            if bool(sig2.get("active", false)) and int(sig2.get("province_id", -1)) == province_id:
                # Offset so primary + secondary don't fully stack when same province (rare).
                var off := Vector2(10, -10) if int(sig.get("province_id", -2)) == province_id else Vector2.ZERO
                _draw_hh_map_signal_marker(center + off, sig2)

        for i in range(province.special_sites.size()):
            var site: SpecialSite = province.special_sites[i]
            if site == null:
                continue
            var offset = Vector2(0, -28 - (i * 22))
            _draw_special_site(center + offset, site)

    # Always draw every data-driven choke (Danish Straits, English Channel, …) even if
    # viewport cull omitted that sea zone from draw_provs — diamonds must sit on correct seas.
    if zoom > 0.08 and map_manager and map_manager.has_method("get_naval_chokepoint_provinces"):
        var all_chokes: Array = map_manager.get_naval_chokepoint_provinces()
        for cid_v in all_chokes:
            var cid := int(cid_v)
            if drawn_chokes.has(cid):
                continue
            var ccent: Vector2 = map_manager.get_province_centroid(cid) if map_manager.has_method("get_province_centroid") else Vector2.ZERO
            if ccent == Vector2.ZERO:
                continue
            var cp: Province = map_manager.get_province(cid) if map_manager.has_method("get_province") else null
            _draw_chokepoint_for_pid(cid, cp, ccent)
            drawn_chokes[cid] = true


func _draw_chokepoint_for_pid(province_id: int, province: Province, center: Vector2) -> void:
    var choke_col := Color(0.35, 0.82, 1.0, 0.92)
    var contest: Dictionary = {}
    if map_manager and map_manager.has_method("get_chokepoint_contest_state"):
        contest = map_manager.get_chokepoint_contest_state(province_id)
    if bool(contest.get("contested", false)):
        choke_col = Color(1.0, 0.62, 0.22, 0.95)
    elif bool(contest.get("unowned", false)):
        choke_col = Color(0.45, 0.55, 0.62, 0.88)
    else:
        var ctrl_tag := str(contest.get("controller", "")).strip_edges()
        if ctrl_tag.is_empty() and map_manager and map_manager.has_method("get_province_controller"):
            ctrl_tag = str(map_manager.get_province_controller(province_id)).strip_edges()
        if ctrl_tag.is_empty() and province != null:
            ctrl_tag = str(province.owner_tag).strip_edges()
        if not ctrl_tag.is_empty() and map_manager and map_manager.has_method("get_country_color"):
            var gc: Color = map_manager.get_country_color(ctrl_tag)
            choke_col = gc.lerp(Color(0.35, 0.82, 1.0, 1.0), 0.35)
            choke_col.a = 0.95
    if map_manager and map_manager.has_method("sealane_contest_visual_for_province"):
        var svis: Dictionary = map_manager.sealane_contest_visual_for_province(province_id)
        if svis is Dictionary and not bool(svis.get("empty", false)):
            var tk := str(svis.get("tint_key", ""))
            var strength := clampf(float(svis.get("strength", 0.5)), 0.15, 1.0)
            match tk:
                "hostile_sealane":
                    choke_col = Color(0.91, 0.36, 0.36, 0.55 + 0.4 * strength)
                "contested_sealane":
                    choke_col = Color(0.91, 0.75, 0.38, 0.55 + 0.4 * strength)
                "friendly_sealane":
                    choke_col = Color(0.37, 0.78, 1.0, 0.55 + 0.4 * strength)
                "neutral_sealane":
                    choke_col = Color(0.53, 0.6, 0.67, 0.55 + 0.35 * strength)
                _:
                    pass
    _draw_naval_chokepoint_marker(center, choke_col)


func _draw_infrastructure_marker(center: Vector2, level: int):
    var pos = center - Vector2(0, infra_icon_size * 0.6)
    draw_circle(pos, 6.5, Color(0.6, 0.6, 0.6, 0.85))
    
    var font = ThemeDB.fallback_font
    draw_string(font, pos - Vector2(4, -4), str(level), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)


## Draws pulsing build/construction marker + dashed progress ring for an active provincial investment project.
## Uses real manager progress (0-1) and sabotage flag for color. Distinct from special_site rings but reuses dashed helper.
func _draw_active_project_marker(center: Vector2, progress: float, sabotaged: bool, current_infra: int):
    var base_pos := center + Vector2(0, -infra_icon_size * 1.35)  # stack above infra number marker
    var col := Color(0.35, 0.85, 0.95, 0.95) if not sabotaged else Color(1.0, 0.55, 0.35, 0.95)
    var icon := "⚒" if not sabotaged else "⚠"
    var font := ThemeDB.fallback_font

    # Pulsing background circle (breathing construction feel)
    var pulse := 0.75 + sin(Time.get_ticks_msec() / 420.0) * 0.18
    draw_circle(base_pos, 9.0 * pulse, Color(col, 0.12 * pulse))

    # Main icon
    draw_string(font, base_pos - Vector2(5, 6), icon, HORIZONTAL_ALIGNMENT_CENTER, -1, 15, col)

    # Progress ring (dashed, partial by progress) using existing helper logic
    var ring_r := 13.5
    _draw_dashed_circle(base_pos, ring_r, col, 1.8, 10, clampf(progress, 0.0, 1.0))

    # Small % label near
    var pct := int(round(clampf(progress, 0.0, 1.0) * 100.0))
    draw_string(font, base_pos + Vector2(10, -4), str(pct) + "%", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(col, 0.9))


func _draw_naval_chokepoint_marker(center: Vector2, col: Color = Color(0.35, 0.82, 1.0, 0.92)) -> void:
    ## Soft diamond + anchor glyph for data-driven naval straits (MapManager chokepoint IDs).
    ## Draw ON the sea centroid — no +Y offset (was sliding English Channel onto Pas-de-Calais).
    var pos := center
    var pulse := 0.85 + sin(Time.get_ticks_msec() / 520.0) * 0.12
    draw_circle(pos, 11.0 * pulse, Color(col.r, col.g, col.b, 0.12 * pulse))
    # Diamond outline
    var d := 9.0
    var pts := PackedVector2Array([
        pos + Vector2(0, -d),
        pos + Vector2(d, 0),
        pos + Vector2(0, d),
        pos + Vector2(-d, 0),
        pos + Vector2(0, -d),
    ])
    draw_polyline(pts, col, 1.85, true)
    # Inner fill hint (control readability at strategic zoom)
    draw_circle(pos, 3.2, Color(col.r, col.g, col.b, 0.55))
    var font := ThemeDB.fallback_font
    draw_string(font, pos - Vector2(6, 6), "⚓", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, col)


func _draw_damage_sabotage_marker(center: Vector2, dmg: Dictionary) -> void:
    ## Distinct map marker for live sabotage/depot/site damage (classify_map_damage).
    var pos := center + Vector2(-16, -8)
    var key := str(dmg.get("tint_key", ""))
    var col := Color(1.0, 0.35, 0.28, 0.95)
    if key in ["depot_sabotage", "supply_pressure"]:
        col = Color(1.0, 0.55, 0.18, 0.95)
    elif key == "site_damage":
        col = Color(1.0, 0.48, 0.35, 0.95)
    var pulse := 0.8 + sin(Time.get_ticks_msec() / 380.0) * 0.15
    draw_circle(pos, 10.0 * pulse, Color(col.r, col.g, col.b, 0.14 * pulse))
    var font := ThemeDB.fallback_font
    var marker := str(dmg.get("marker", "⚠"))
    if marker.is_empty():
        marker = "⚠"
    draw_string(font, pos - Vector2(6, 6), marker, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, col)


func _draw_hh_map_signal_marker(center: Vector2, sig: Dictionary) -> void:
    ## Monthly Hidden Hand background action marker on the targeted province.
    var pos := center + Vector2(16, -10)
    var col := Color(0.72, 0.42, 1.0, 0.95)
    if str(sig.get("tint_key", "")) == "infra_sabotage":
        col = Color(1.0, 0.4, 0.55, 0.95)
    var pulse := 0.82 + sin(Time.get_ticks_msec() / 450.0) * 0.14
    draw_circle(pos, 11.0 * pulse, Color(col.r, col.g, col.b, 0.12 * pulse))
    var font := ThemeDB.fallback_font
    var marker := str(sig.get("marker", "👁"))
    draw_string(font, pos - Vector2(6, 6), marker, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, col)


func _draw_special_site(pos: Vector2, site: SpecialSite):
    if not site or site.construction_state == SpecialSite.ConstructionState.NOT_BUILT:
        return

    var icon := "◆"
    var color := Color(0.9, 0.9, 0.9, 1.0)

    # Choose icon based on site type
    match site.site_type:
        SpecialSite.SiteType.PORT:
            icon = "⚓"
        SpecialSite.SiteType.AIRFIELD:
            icon = "✈"
        SpecialSite.SiteType.NAVAL_SHIPYARD:
            icon = "🚢"
        SpecialSite.SiteType.FACTORY:
            icon = "🏭"
        SpecialSite.SiteType.OIL_REFINERY:
            icon = "🛢"
        SpecialSite.SiteType.ICBM_SITE:
            icon = "🚀"
        SpecialSite.SiteType.RADAR_STATION, SpecialSite.SiteType.FLAK_BATTERY, SpecialSite.SiteType.MISSILE_DEFENSE:
            icon = "📡"
        SpecialSite.SiteType.SPECIAL_PROJECT:
            icon = "⚗"
        SpecialSite.SiteType.FORTIFICATION:
            icon = "🏰"
        _:
            icon = "◆"

    # State-based coloring and effects via pure visual contract (distinct UC / complete / damaged).
    var vis: Dictionary = _MapPolishFormatters.special_site_map_visual(
        site.is_completed(),
        site.construction_state == SpecialSite.ConstructionState.UNDER_CONSTRUCTION,
        site.is_damaged(),
        float(site.construction_progress),
    )
    var tint_key := str(vis.get("tint_key", ""))
    if tint_key == "under_construction":
        color = Color(0.35, 0.75, 1.0, 0.95)
        if bool(vis.get("progress_ring", false)):
            var prog := clampf(float(vis.get("ring_progress", 0.05)), 0.05, 1.0)
            _draw_dashed_circle(pos, construction_ring_radius, color, 2.2, 12, prog)
        if bool(vis.get("pulse", false)):
            var pulse_uc = sin(Time.get_ticks_msec() / 300.0) * 0.18 + 0.82
            draw_circle(pos, construction_ring_radius * 0.5, Color(color, 0.12 * pulse_uc))
    elif tint_key == "damaged":
        color = Color(1.0, 0.45, 0.3, 0.95)
        # Soft damage halo (distinct from completion pulse)
        var pulse_dmg = sin(Time.get_ticks_msec() / 260.0) * 0.10 + 0.75
        draw_circle(pos, construction_ring_radius * 0.55, Color(1.0, 0.28, 0.18, 0.14 * pulse_dmg))
    elif tint_key == "complete":
        if site.tier >= 3:
            color = Color(1.0, 0.92, 0.5, 1.0)  # Gold for Tier 3
        elif site.tier == 2:
            color = Color(0.7, 0.95, 0.7, 1.0)
        else:
            color = Color(0.85, 0.95, 0.88, 1.0)
        # Completion pulse — healthy complete sites breathe (sabotaged never reach here)
        if bool(vis.get("completion_pulse", false)):
            var pulse_done = sin(Time.get_ticks_msec() / 520.0) * 0.12 + 0.88
            draw_circle(pos, construction_ring_radius * 0.42, Color(color, 0.10 * pulse_done))
    elif site.tier >= 3:
        color = Color(1.0, 0.92, 0.5, 1.0)
    elif site.tier == 2:
        color = Color(0.7, 0.95, 0.7, 1.0)

    var font = ThemeDB.fallback_font
    draw_string(font, pos, icon, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, color)

    # Tier indicator for higher tiers
    if site.tier >= 2:
        draw_string(font, pos + Vector2(11, -7), str(site.tier), HORIZONTAL_ALIGNMENT_CENTER, -1, 9, color)

    # Compact effect chip (supply / trade) via MapPolishFormatters pure helper.
    if bool(vis.get("show_effect_chip", false)):
        var chip: String = _MapPolishFormatters.format_overlay_effect_chip(
            float(site.supply_bonus), float(site.trade_capacity)
        )
        if not chip.is_empty():
            draw_string(font, pos + Vector2(-10, 14), chip, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(color, 0.85))

    # Damage cracks (visual feedback for sabotage/attack) — only when contract says so
    if bool(vis.get("show_damage_cracks", false)) and site.is_damaged():
        var dmg = site.damage_level
        for i in range(dmg):
            var crack_angle = -TAU * 0.3 + i * 0.45
            var c1 = pos + Vector2(cos(crack_angle), sin(crack_angle)) * 7
            var c2 = pos + Vector2(cos(crack_angle + 0.8), sin(crack_angle + 0.8)) * 11
            draw_line(c1, c2, Color(0.95, 0.25, 0.25, 0.9), 1.6)


func _draw_construction_ring(pos: Vector2, color: Color):
    var progress = 0.65  # Can be made dynamic via infrastructure_manager later
    _draw_dashed_circle(pos, construction_ring_radius, color, 2.2, 12, progress)
    
    # Subtle breathing/pulse effect
    var pulse = sin(Time.get_ticks_msec() / 300.0) * 0.18 + 0.82
    draw_circle(pos, construction_ring_radius * 0.5, Color(color, 0.1 * pulse))


func _draw_dashed_circle(center: Vector2, radius: float, color: Color, width: float, segments: int, progress: float):
    for i in range(segments):
        if float(i) / segments > progress:
            break
        if i % 2 == 0:
            var a1 = (float(i) / segments) * TAU
            var a2 = (float(i + 1) / segments) * TAU
            var p1 = center + Vector2(cos(a1), sin(a1)) * radius
            var p2 = center + Vector2(cos(a2), sin(a2)) * radius
            draw_line(p1, p2, color, width)


# === Cities / Urban Layer (fallback) ===
# The primary city visuals are now via the CityLayer sub-nodes (editable rects).
# This _draw_cities is kept as fallback when sub-layer has no children yet (e.g. before first rebuild or in some zoom/debug cases).
# It is skipped in _draw if city_layer has children.
# Visual "cities" that grow with development_level, population, factories.
# Makes provinces feel alive with urban development. Toggleable/updated on dev changes.
func _draw_cities(zoom: float = 1.0) -> void:
    _draw_cities_culled(zoom, _get_provinces_for_layers())


func _draw_cities_culled(zoom: float, provinces: Dictionary) -> void:
    if not map_manager or not show_cities or not DRAW_CITY_FALLBACK:
        return

    if zoom < 0.5:
        return

    for province_id in provinces:
        var province: Province = provinces[province_id]
        if province == null or province.is_sea:
            continue

        var center = map_manager.get_province_centroid(province_id)
        var dev = province.development_level
        var pop_factor = clampf(province.population / 500000.0, 0.5, 4.0)
        var fact = province.factories
        var num_buildings = mini(int(2 + dev * 0.8 + fact * 0.3 + pop_factor), MAX_CITY_BUILDINGS_PER_PROVINCE)

        for i in range(num_buildings):
            var angle = (i * 2.3) + (province_id % 5) * 0.5
            var dist = 4.0 + (i % 4) * 2.5 + (2.0 if dev > 6 else 0.0)
            var off = Vector2(cos(angle), sin(angle)) * dist
            var bsize = 2.5 + (dev / 4.0) + (1.0 if fact > 2 else 0.0)
            var bcol = Color(0.22, 0.22, 0.26, 0.65 + (dev * 0.02))
            if fact > 3:
                bcol = Color(0.18, 0.20, 0.25, 0.75)  # more industrial look
            draw_rect(Rect2(center + off - Vector2(bsize*0.5, bsize*0.5), Vector2(bsize, bsize)), bcol)

            # Small "road" stubs from city
            if i % 3 == 0 and dev > 4:
                var stub_dir = (center + off - center).normalized() * (bsize + 3)
                draw_line(center + off, center + off + stub_dir * 0.6, Color(0.35, 0.33, 0.30, 0.5), 1.2)


# === Simple Resource Icons (map improvement for visibility) ===
# Draws small indicators for primary resources when zoomed in.
func _draw_resource_icons(zoom: float = 1.0) -> void:
    _draw_resource_icons_culled(zoom, _get_provinces_for_layers())


## Zoom gates for resource glyphs (strategic earlier, bulk later).
const RESOURCE_ZOOM_STRATEGIC := 0.38  ## oil/coal/uranium/rare_earths - earlier for ops
const RESOURCE_ZOOM_BULK := 0.48       ## food/grain and generic commodities


func resource_icon_min_zoom_for(primary: String) -> float:
    ## Pure helper for tests + draw path: when a resource type becomes visible.
    var key := primary.strip_edges().to_lower()
    match key:
        "oil", "fuel", "coal", "uranium", "rare_earths", "semiconductors", "rubber":
            return RESOURCE_ZOOM_STRATEGIC
        "iron", "steel", "aluminum", "aluminium", "fissiles", "helium3", "antimatter", "energy":
            return RESOURCE_ZOOM_STRATEGIC
        _:
            return RESOURCE_ZOOM_BULK


func _draw_resource_icons_culled(zoom: float, provinces: Dictionary) -> void:
    if not map_manager:
        return

    # Earliest strategic glyph zoom; bulk food/generic gated higher inside loop.
    if zoom < RESOURCE_ZOOM_STRATEGIC:
        return

    var board_n := provinces.size()
    if map_manager.has_method("get_province_count"):
        board_n = maxi(board_n, int(map_manager.get_province_count()))
    # Cap glyph count on world_full boards (MapZoomLOD pure helper).
    const MapZoomLODScript = preload("res://scripts/map/MapZoomLOD.gd")
    var icon_budget := int(MapZoomLODScript.max_resource_icons_for_board(board_n))
    var drawn := 0

    for province_id in provinces:
        if drawn >= icon_budget:
            break
        var province: Province = provinces[province_id]
        if province == null or province.is_sea:
            continue
        if province.resources.is_empty():
            continue

        var center = map_manager.get_province_centroid(province_id)
        var primary := ""
        if "primary_resource" in province and str(province.primary_resource) != "":
            primary = str(province.primary_resource)
        else:
            # Prefer strategic resources when present.
            for key in ["oil", "coal", "iron", "steel", "uranium", "rare_earths", "rubber", "aluminum"]:
                if province.resources.has(key) and float(province.resources[key]) > 0.0:
                    primary = key
                    break
            if primary == "":
                for k in province.resources:
                    if float(province.resources[k]) > 0.0:
                        primary = str(k)
                        break

        if primary == "":
            continue
        if zoom < resource_icon_min_zoom_for(primary):
            continue

        drawn += 1
        var symbol = "●"
        var col = Color(0.8, 0.8, 0.6, 0.9)
        var ring := Color(0.05, 0.05, 0.08, 0.55)

        match primary.to_lower():
            "iron", "steel":
                symbol = "⚙"
                col = Color(0.55, 0.6, 0.68, 0.95)
            "coal":
                symbol = "⬛"
                col = Color(0.22, 0.22, 0.24, 0.95)
            "oil", "fuel":
                symbol = "🛢"
                col = Color(0.12, 0.12, 0.14, 0.95)
            "uranium":
                symbol = "☢"
                col = Color(0.45, 0.85, 0.35, 0.95)
            "rubber":
                symbol = "●"
                col = Color(0.35, 0.28, 0.22, 0.95)
            "aluminum", "aluminium":
                symbol = "◇"
                col = Color(0.75, 0.78, 0.85, 0.95)
            "rare_earths", "semiconductors":
                symbol = "◆"
                col = Color(0.35, 0.85, 0.65, 0.95)
            "food", "grain", "agriculture":
                symbol = "🌾"
                col = Color(0.75, 0.7, 0.25, 0.9)
            _:
                symbol = "●"
                col = Color(0.7, 0.65, 0.5, 0.85)

        var icon_pos = center + Vector2(12, 12)
        # Halo for contrast on light parchment underlay.
        draw_circle(icon_pos, 6.0, ring)
        draw_circle(icon_pos, 4.8, col)
        var font := ThemeDB.fallback_font
        if font:
            draw_string(font, icon_pos + Vector2(-5, 4), symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color(1, 1, 1, 0.92))


func _get_current_zoom() -> float:
    # Try viewport camera first (most reliable in Godot 4)
    var cam := get_viewport().get_camera_2d()
    if cam:
        return max(cam.zoom.x, cam.zoom.y)

    # Fallback: parent container scale (common pattern for map containers)
    var p := get_parent()
    if p:
        var s = p.get("scale")
        if s is Vector2:
            return max(s.x, s.y)
        if p.has_method("get_scale"):
            s = p.get_scale()
            if s is Vector2:
                return max(s.x, s.y)

    # Last resort
    return 1.0


# === Proposed Phase 1 Split Visualization (Map Generation Pipeline) ===
func _draw_proposed_splits(zoom: float = 1.0):
    if not show_proposed_splits or proposed_children.is_empty():
        return

    # Zoom gate — only useful when the player can actually read the small polygons
    if zoom < 0.55:
        return

    var font := ThemeDB.fallback_font
    var base_color := Color(0.2, 0.85, 0.9, 0.9)      # Bright cyan/teal for "proposed"
    var high_naval_color := Color(0.95, 0.7, 0.2, 0.95)  # Gold/orange for high naval importance children
    var fill_color := Color(0.2, 0.85, 0.9, 0.12)
    var label_color := Color(0.85, 0.95, 1.0, 0.95)
    var parent_label_color := Color(0.65, 0.72, 0.78, 0.75)

    for child in proposed_children:
        var pts_raw: Array = child.get("points", [])
        if pts_raw.size() < 3:
            continue

        var poly: PackedVector2Array = ProvincePolygonUtil.from_variant_points(pts_raw)
        poly = ProvincePolygonUtil.make_drawable(poly)
        if poly.size() < 3:
            continue

        var naval_imp: float = float(child.get("naval_importance", 0.0))
        var use_color := high_naval_color if naval_imp > 1.2 else base_color

        ProvincePolygonUtil.draw_fill(self, poly, fill_color)
        draw_polyline(poly, use_color, 2.4, true)
        draw_polyline(poly, Color(use_color, 0.35), 1.0, true)

        var cx := 0.0
        var cy := 0.0
        for pt in poly:
            cx += pt.x
            cy += pt.y
        if poly.size() > 0:
            cx /= poly.size()
            cy /= poly.size()

        var child_id: String = str(child.get("id", "child"))
        var parent_id = child.get("parent_id", "?")
        var label_pos := Vector2(cx, cy)

        draw_string(font, label_pos - Vector2(18, 0), child_id, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, label_color)

        var parent_str := "← p" + str(parent_id)
        if naval_imp > 0.5:
            parent_str += "  naval:" + str(naval_imp)
        draw_string(font, label_pos + Vector2(-14, 11), parent_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 7, parent_label_color)

    if zoom > 0.9:
        var hint := "RAW PROPOSED SPLITS (from Python generator) — orange = high naval value"
        draw_string(font, Vector2(80, 48), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.9, 0.95, 0.6))
