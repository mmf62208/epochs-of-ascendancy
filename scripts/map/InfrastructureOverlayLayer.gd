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

@export var infra_icon_size: float = 16.0
@export var site_icon_size: float = 20.0
@export var construction_ring_radius: float = 24.0

# === Phase 1 Map Generation Debug Visualization ===
@export var show_proposed_splits: bool = false  # Only meaningful in debug builds

## Toggleable layers for infrastructure visuals (roads, rails, cities, sites).
## These can be toggled in game/UI/Debug to focus on different map aspects.
## "Editable" via projects in InfrastructureDevelopmentManager which upgrade infra/dev/special sites,
## triggering redraws and visual updates (roads thicken, cities grow, new sites appear with rings).
var show_roads: bool = true
var show_rails: bool = true
var show_cities: bool = true
var show_sites: bool = true  # airfields/ports/shipyards etc. vector elements (runways, docks) on the SitesLayer
var proposed_children: Array = []
var proposed_data_loaded: bool = false
const PROPOSED_SPLIT_PATH := "res://tools/map_generation/output/phase1_europe/proposed_children_geometry.json"

var infrastructure_manager: Node
var special_site_manager: Node
var map_manager: Node

# Sub-layers for toggleable/editable infrastructure visuals.
# These are Node2D children holding Line2D / other nodes for roads/rails/cities.
# Toggling: set their .visible
# Editing: add/remove/modify child nodes (e.g. Line2D for a new road).
# Rebuilt on demand via rebuild_*_layer() when data changes (e.g. project complete).
var road_layer: Node2D
var rail_layer: Node2D
var city_layer: Node2D
var sites_layer: Node2D  # For airfields, ports, shipyards etc. as toggleable/editable vector elements (runways, docks) in addition to the icon drawing in _draw.

func _ready():
    infrastructure_manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
    special_site_manager = get_node_or_null("/root/SpecialSiteManager")
    map_manager = get_node_or_null("/root/MapManager")
    z_index = 8

    add_to_group("infrastructure_overlay")

    # Setup sub-layers as children (for true layer toggling and node-based editing)
    _ensure_sub_layers()

    if map_manager and map_manager.has_signal("province_data_changed"):
        if not map_manager.province_data_changed.is_connected(_on_province_data_changed):
            map_manager.province_data_changed.connect(_on_province_data_changed)

    call_deferred("refresh_all")
    call_deferred("_try_load_proposed_splits")
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
    _update_sub_layer_visibilities()

func _update_sub_layer_visibilities() -> void:
    var z := _get_current_zoom()
    # Zoom thresholds so that at the test's initial auto-frame (~0.40) the layers are visible,
    # but they hide when zoomed far out (you zoom in to province to see fine roads/buildings/sites).
    # User toggles still control the "enabled" state.
    if road_layer:
        road_layer.visible = show_roads and z > 0.18
    if rail_layer:
        rail_layer.visible = show_rails and z > 0.22
    if city_layer:
        city_layer.visible = show_cities and z > 0.28
    if sites_layer:
        sites_layer.visible = show_sites and z > 0.32

# Simple view culling helper: only consider provinces near the current camera for node population.
# This keeps node count reasonable (important for resource usage on larger maps or during many updates).
func _get_visible_provinces() -> Dictionary:
    if map_manager == null:
        return {}
    var cam := get_viewport().get_camera_2d()
    if cam == null:
        return map_manager.get_all_provinces()  # fallback full
    var center := cam.get_screen_center_position()
    var radius: float = 1200.0 / max(_get_current_zoom(), 0.1)  # larger radius when zoomed out
    var all: Dictionary = map_manager.get_all_provinces()
    var visible := {}
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
    return visible

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

    var provinces = _get_visible_provinces()
    var adjacency = map_manager.get_adjacency_system()
    if adjacency == null or provinces.is_empty():
        return

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
            if not has_explicit and avg_infra < 3:
                continue
            var c2 = map_manager.get_province_centroid(nid)
            var line := Line2D.new()
            line.points = [c1, c2]
            line.width = 3.0 if has_explicit or avg_infra >= 6 else 1.5
            line.default_color = Color(0.4, 0.38, 0.35, 0.85) if has_explicit else Color(0.42, 0.40, 0.37, 0.6)
            line.z_index = 1
            line.set_meta("p1", pid)
            line.set_meta("p2", nid)
            line.set_meta("explicit", has_explicit)
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

    var provinces = _get_visible_provinces()
    var adjacency = map_manager.get_adjacency_system()
    if adjacency == null or provinces.is_empty():
        return

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
            if not has_explicit and avg_infra < 6:
                continue
            var c2 = map_manager.get_province_centroid(nid)
            var line := Line2D.new()
            line.points = [c1, c2]
            line.width = 2.5
            line.default_color = Color(0.2, 0.2, 0.25, 0.9)
            line.z_index = 2
            line.set_meta("p1", pid)
            line.set_meta("p2", nid)
            line.set_meta("explicit", has_explicit)
            rail_layer.add_child(line)
            # Simple ties for rail look
            var dist = c1.distance_to(c2)
            var steps = max(2, int(dist / 30))
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

    if not show_cities:
        return

    if map_manager == null:
        return

    var provinces = _get_visible_provinces()
    for pid in provinces:
        var p: Province = provinces[pid]
        if p == null or p.is_sea:
            continue
        var center = map_manager.get_province_centroid(pid)
        var dev = p.development_level
        var fact = p.factories
        if dev < 3:
            continue
        var pop_factor = clampf(p.population / 500000.0, 0.5, 4.0)
        var num = min(10, int(2 + dev * 0.8 + fact * 0.3 + pop_factor))
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

    var provinces = _get_visible_provinces()
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
    rebuild_road_layer()
    rebuild_rail_layer()
    rebuild_city_layer()
    rebuild_sites_layer()
    queue_redraw()  # in case any immediate draw still used
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
                print("InfrastructureOverlayLayer: Dynamic infra layers built (roads:%d rail-ties:%d cities:%d sites:%d). Toggle with R/T/C/Y or F10." % [road_count, rail_count, city_count, site_count])

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
        # Rebuild node-based road/rail/city/sites layers when data that affects them changes (projects complete, dev upgrades, explicit builds, special sites like airfields/ports).
        # This makes the map "come alive": new roads appear as Line2D children, cities densify, runways/docks added to SitesLayer, etc.
        if what in ["infrastructure", "development", "infrastructure_project", "special_site", "all"]:
            rebuild_all_infra_layers()
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
    queue_redraw()

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

    # NOTE: Roads, rails, and cities are now primarily rendered via dedicated sub-layers
    # (RoadLayer / RailLayer / CityLayer as Node2D children with Line2D/ColorRect nodes).
    # This enables:
    # - Toggling via .visible (set_show_*/toggle_* now affect child visibility)
    # - Editing: external code (MapManager.build_road_connection etc) mutates province built_* lists,
    #   then calls rebuild_*_layer which adds/removes/modifies child nodes.
    # The old draw methods below are kept for fallback/debug/proposed but skipped here to prevent
    # duplicate geometry when sub-layers are present and visible.
    # Special sites, infra markers, resources, and proposed splits still use immediate _draw.

    # Sub-layers (roads/rails/cities/sites) draw their Node2D children when .visible.
    # _draw_* are kept as fallback / for elements that are not (yet) node-ified (icons, resources, proposed splits).
    # To avoid double visuals for cities when the sub-layer is populated, skip the draw path.
    if show_cities:
        if not (city_layer and city_layer.get_child_count() > 0):
            _draw_cities(zoom)

    # Draw simple resource icons (visible at reasonable zoom)
    _draw_resource_icons(zoom)

    # Phase 1 Map Generation debug visualization (debug builds only)
    if show_proposed_splits and OS.is_debug_build():
        _draw_proposed_splits(zoom)

    var provinces = map_manager.get_all_provinces()

    for province_id in provinces:
        var province: Province = provinces[province_id]
        if province == null:
            continue

        var center = map_manager.get_province_centroid(province_id)

        # === Province Infrastructure Level ===
        var infra_level = province.infrastructure
        if infra_level >= 1:
            _draw_infrastructure_marker(center, infra_level)

        # === Special Sites ===
        for i in range(province.special_sites.size()):
            var site: SpecialSite = province.special_sites[i]
            if site == null:
                continue
            var offset = Vector2(0, -28 - (i * 22))  # Stack sites above the province
            _draw_special_site(center + offset, site)


func _draw_infrastructure_marker(center: Vector2, level: int):
    var pos = center - Vector2(0, infra_icon_size * 0.6)
    draw_circle(pos, 6.5, Color(0.6, 0.6, 0.6, 0.85))
    
    var font = ThemeDB.fallback_font
    draw_string(font, pos - Vector2(4, -4), str(level), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)


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
        _:
            icon = "◆"

    # State-based coloring and effects
    if site.construction_state == SpecialSite.ConstructionState.UNDER_CONSTRUCTION:
        color = Color(0.35, 0.75, 1.0, 0.95)
        _draw_construction_ring(pos, color)
    elif site.is_damaged():
        color = Color(1.0, 0.45, 0.3, 0.95)
    elif site.tier >= 3:
        color = Color(1.0, 0.92, 0.5, 1.0)  # Gold for Tier 3
    elif site.tier == 2:
        color = Color(0.7, 0.95, 0.7, 1.0)

    var font = ThemeDB.fallback_font
    draw_string(font, pos, icon, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, color)

    # Tier indicator for higher tiers
    if site.tier >= 2:
        draw_string(font, pos + Vector2(11, -7), str(site.tier), HORIZONTAL_ALIGNMENT_CENTER, -1, 9, color)

    # Damage cracks (visual feedback for sabotage/attack)
    if site.is_damaged():
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
func _draw_cities(zoom: float = 1.0):
    if not map_manager or not show_cities:
        return

    if zoom < 0.5:
        return

    var provinces = map_manager.get_all_provinces()

    for province_id in provinces:
        var province: Province = provinces[province_id]
        if province == null or province.is_sea:
            continue

        var center = map_manager.get_province_centroid(province_id)
        var dev = province.development_level
        var pop_factor = clampf(province.population / 500000.0, 0.5, 4.0)
        var fact = province.factories
        var num_buildings = int(2 + dev * 0.8 + fact * 0.3 + pop_factor)

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
func _draw_resource_icons(zoom: float = 1.0):
    if not map_manager:
        return

    # Only show resource icons when reasonably zoomed in
    if zoom < 0.75:
        return

    var provinces = map_manager.get_all_provinces()

    for province_id in provinces:
        var province: Province = provinces[province_id]
        if province == null or province.is_sea or province.resources.is_empty():
            continue

        var center = map_manager.get_province_centroid(province_id)
        var primary = province.get("primary_resource") if province else ""
        if primary == null or str(primary) == "":
            for k in province.resources:
                primary = k
                break

        if primary == "":
            continue

        var symbol = "●"
        var col = Color(0.8, 0.8, 0.6, 0.9)

        match primary.to_lower():
            "iron", "steel":
                symbol = "⚙"
                col = Color(0.55, 0.6, 0.68, 0.95)
            "coal":
                symbol = "⬛"
                col = Color(0.25, 0.25, 0.27, 0.9)
            "oil", "fuel":
                symbol = "🛢"
                col = Color(0.15, 0.15, 0.15, 0.9)
            "rare_earths", "semiconductors":
                symbol = "◆"
                col = Color(0.35, 0.85, 0.65, 0.95)
            _:
                symbol = "●"
                col = Color(0.7, 0.65, 0.5, 0.85)

        var icon_pos = center + Vector2(11, 11)
        draw_circle(icon_pos, 4.5, col)
        var font = ThemeDB.fallback_font
        draw_string(font, icon_pos - Vector2(3.5, -2.5), symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, Color.WHITE)


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

        var poly: PackedVector2Array = []
        for p in pts_raw:
            if p is Array and p.size() >= 2:
                poly.append(Vector2(p[0], p[1]))

        if poly.size() < 3:
            continue

        var naval_imp: float = float(child.get("naval_importance", 0.0))
        var use_color := high_naval_color if naval_imp > 1.2 else base_color

        draw_polygon(poly, [fill_color])
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
