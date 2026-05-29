# scripts/map/InfrastructureOverlayLayer.gd
## Infrastructure & Development visual layer.
##
## Renders:
## - Province infrastructure level markers
## - Special Sites with proper icons by type, tier coloring, construction rings, and damage visuals
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
var proposed_children: Array = []
var proposed_data_loaded: bool = false
const PROPOSED_SPLIT_PATH := "res://tools/map_generation/output/phase1_europe/proposed_children_geometry.json"

var infrastructure_manager: Node
var special_site_manager: Node
var map_manager: Node

func _ready():
    infrastructure_manager = get_node_or_null("/root/InfrastructureDevelopmentManager")
    special_site_manager = get_node_or_null("/root/SpecialSiteManager")
    map_manager = get_node_or_null("/root/MapManager")
    z_index = 8

    add_to_group("infrastructure_overlay")

    if map_manager and map_manager.has_signal("province_data_changed"):
        if not map_manager.province_data_changed.is_connected(_on_province_data_changed):
            map_manager.province_data_changed.connect(_on_province_data_changed)

    call_deferred("refresh_all")
    call_deferred("_try_load_proposed_splits")


func _on_province_data_changed(_pid: int, what: String):
    if what in ["infrastructure", "development", "special_site", "infrastructure_project", "effects", "all"]:
        queue_redraw()


func refresh_all():
    queue_redraw()


# === Proposed Splits (Phase 1 Map Gen Debug) ===
func _try_load_proposed_splits():
    if proposed_data_loaded:
        return
    if not OS.is_debug_build():
        return

    var file = FileAccess.open(PROPOSED_SPLIT_PATH, FileAccess.READ)
    if file == null:
        # Also try a few common dev paths outside res://
        var alt_paths = [
            "tools/map_generation/output/phase1_europe/proposed_children_geometry.json",
            "../tools/map_generation/output/phase1_europe/proposed_children_geometry.json"
        ]
        for alt in alt_paths:
            file = FileAccess.open(alt, FileAccess.READ)
            if file != null:
                break

    if file == null:
        push_warning("InfrastructureOverlayLayer: Could not load proposed_children_geometry.json (expected in debug)")
        return

    var text = file.get_as_text()
    file.close()

    var data = JSON.parse_string(text)
    if data == null or not data.has("proposed_children"):
        push_warning("InfrastructureOverlayLayer: Invalid proposed split JSON format")
        return

    proposed_children = data["proposed_children"]
    proposed_data_loaded = true
    print("InfrastructureOverlayLayer: Loaded %d proposed Phase 1 child provinces for debug visualization." % proposed_children.size())


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
    if enabled and not proposed_data_loaded:
        _try_load_proposed_splits()
    queue_redraw()


func force_full_refresh():
    """Called by DebugOverlay and other tools to force a complete redraw."""
    _try_load_proposed_splits()
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

    # Draw basic roads first (under other elements)
    _draw_basic_roads(zoom)

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


# === Basic Roads (infrastructure visualization improvement) ===
# Draws simple lines between adjacent provinces, thickness and visibility based on infrastructure.
# This makes the map feel more connected and "real" without heavy performance cost.
# Naval-aware: coastal connections are slightly emphasized (foreshadowing future naval supply importance).
func _draw_basic_roads(zoom: float = 1.0):
    if not map_manager:
        return

    # Zoom gating – don't draw tiny roads when zoomed out
    if zoom < 0.6:
        return

    var adjacency = map_manager.get_adjacency_system()
    if adjacency == null:
        return

    var provinces = map_manager.get_all_provinces()
    var drawn_pairs := {}  # avoid double drawing

    for province_id in provinces:
        var province: Province = provinces[province_id]
        if province == null or province.is_sea:
            continue

        var neighbors = adjacency.get_land_neighbors(province_id)
        var center1 = map_manager.get_province_centroid(province_id)
        var infra1 = province.infrastructure
        var is_coastal = province.has_port or province.has_feature("port") or province.has_feature("harbor")

        for neighbor_id in neighbors:
            var key = str(min(province_id, neighbor_id)) + "_" + str(max(province_id, neighbor_id))
            if drawn_pairs.has(key):
                continue
            drawn_pairs[key] = true

            var neighbor: Province = provinces.get(neighbor_id)
            if neighbor == null or neighbor.is_sea:
                continue

            var center2 = map_manager.get_province_centroid(neighbor_id)
            var infra2 = neighbor.infrastructure
            var neighbor_coastal = neighbor.has_port or neighbor.has_feature("port") or neighbor.has_feature("harbor")

            var avg_infra = (infra1 + infra2) / 2.0
            if avg_infra < 2:
                continue

            var thickness = clampf(1.0 + (avg_infra - 2) * 0.28, 1.2, 6.0)

            var road_color = Color(0.42, 0.40, 0.37, 0.6)
            if avg_infra >= 7:
                road_color = Color(0.32, 0.32, 0.36, 0.9)
            elif avg_infra >= 5:
                road_color = Color(0.38, 0.36, 0.34, 0.75)

            # Slight visual boost for coastal-to-coastal or coastal connections (naval importance)
            if (is_coastal and neighbor_coastal) or (is_coastal or neighbor_coastal):
                road_color = road_color.lightened(0.08)
                thickness *= 1.15

            draw_line(center1, center2, road_color, thickness)


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
        var primary = province.get("primary_resource", "")
        if primary == "":
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
        var s := p.get("scale")
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
    var fill_color := Color(0.2, 0.85, 0.9, 0.12)
    var label_color := Color(0.85, 0.95, 1.0, 0.95)
    var parent_label_color := Color(0.65, 0.72, 0.78, 0.75)

    for child in proposed_children:
        var pts_raw: Array = child.get("points", [])
        if pts_raw.size() < 3:
            continue

        # Convert to Vector2 array
        var poly: PackedVector2Array = []
        for p in pts_raw:
            if p is Array and p.size() >= 2:
                poly.append(Vector2(p[0], p[1]))

        if poly.size() < 3:
            continue

        # Light fill + prominent outline (proposed = "future" visual language)
        draw_polygon(poly, [fill_color])
        draw_polyline(poly, base_color, 2.4, true)
        # Subtle inner highlight for readability at different zooms
        draw_polyline(poly, Color(base_color, 0.35), 1.0, true)

        # Small centroid label
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

        # Child ID (main label)
        draw_string(font, label_pos - Vector2(18, 0), child_id, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, label_color)

        # Parent reference (smaller, below)
        var parent_str := "← p" + str(parent_id)
        draw_string(font, label_pos + Vector2(-14, 11), parent_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 7, parent_label_color)

    # Subtle header hint when active (top-leftish area of the map view)
    if zoom > 0.9:
        var hint := "PHASE 1 PROPOSED SPLITS (debug)"
        draw_string(font, Vector2(80, 48), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.3, 0.9, 0.95, 0.6))
