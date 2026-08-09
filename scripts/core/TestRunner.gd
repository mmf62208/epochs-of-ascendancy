# scripts/core/TestRunner.gd
extends Node

@onready var loader: ScenarioLoader = $ScenarioLoader
@onready var map_renderer: MapRenderer = $WorldMap as MapRenderer   # cast to the script class (avoids Node2D base assign in scene instance)
@onready var camera_controller: CameraController = $WorldMap/CameraInput

var player_tag: String = "USA"


func _ready() -> void:
	print("=== Epochs of Ascendancy Test Starting ===")
	var success := loader.load_scenario("phase1_europe_test")

	if not success:
		print("Failed to load scenario.")
		return

	_wire_factory_province_lookup()

	print("Scenario loaded. Initializing map renderer...")
	var map_data := loader.get_map_data()
	map_renderer.initialize(
		map_data.provinces,
		map_data.geometry,
		map_data.adjacency_system,
		map_data.countries,
	)

	# Also feed MapManager so it is authoritative even in test runner flows
	var mm := get_node_or_null("/root/MapManager")
	if mm != null and mm.has_method("initialize_from_map_data"):
		mm.initialize_from_map_data(map_data)
	elif mm != null and mm.has_method("force_initialize"):
		mm.force_initialize(map_data.provinces, map_data.geometry, map_data.adjacency_system, map_data.countries)

	if camera_controller and map_renderer.container:
		camera_controller.target = map_renderer.container

	# Wire InfrastructureDevelopmentManager to the central clock (it has auto but explicit is safer in test flows).
	var idm := get_node_or_null("/root/InfrastructureDevelopmentManager")
	if idm and idm.has_method("initialize_with_time"):
		idm.initialize_with_time()
		print("TestRunner: InfrastructureDevelopmentManager wired to daily tick")

	# Auto-frame the camera for the phase1 test map so the map is immediately visible and centered.
	if camera_controller:
		# Safe early default frame. The grand-specific nice large view (for the upscaled styled image) is forced later
		# in the phase1 block (after map_variant / bg_path are known) so it always uses the high-res 8K+ coordinates.
		camera_controller.set_initial_view(Vector2(1800, 650), 2.0, true)
		print("TestRunner: Auto-framed camera to reasonable start (grand high-res large view forced later if applicable)")

	# Note: conflict/agent/supply overlays are set up inside map_renderer.initialize() / render_provinces for phase1.
	# Additional demo overlays can be toggled via F10 DebugOverlay if present.

	# Phase1 bg image so map images load along with outlines (the grid/borders).
	# Uses extremely detailed generated regional composite (no borders, clear rivers/water, baked roads/buildings/cities for zoom).
	# Supports variants for different eras/themes.
	if loader and ("phase1" in loader.current_province_data_dir or loader.current_province_data_dir == "provinces_phase1_test"):
		var map_variant := "grand"  # Use the requested latest grand theater stylized detailed map (image 45 equivalent) as default for high quality no-borders zoomable look
		var bg_path := "res://assets/maps/europe_grand_theater_ultra_1936.jpg"
		if map_variant == "winter":
			bg_path = "res://assets/maps/europe_winter_ultra_1936.png"
		elif map_variant == "1944" or map_variant == "1945":
			bg_path = "res://assets/maps/europe_1945_heavily_damaged_ultra_1936.png"
		elif map_variant == "2026":
			bg_path = "res://assets/maps/europe_2026_modern_high_detail.png"
		elif map_variant == "2026_advanced":
			bg_path = "res://assets/maps/europe_2026_advanced_infra_ultra.png"
		elif map_variant == "ultra":
			bg_path = "res://assets/maps/europe_ultra_detail_1936.png"
		elif map_variant == "ultra_4k":
			bg_path = "res://assets/maps/europe_ultra_detail_1936_4k.png"
		elif map_variant == "grand":
			bg_path = "res://assets/maps/europe_grand_theater_ultra_high.jpg"  # high quality larger version for closer zoom (the requested up-res map); falls back in load logic if not present yet

		if map_renderer and map_renderer.has_method("apply_phase1_europe_background"):
			map_renderer.apply_phase1_europe_background()  # will use updated default
			# Override texture for variant if not base
			var bg := map_renderer.find_child("WorldBackground", true, false) as Sprite2D
			if bg and map_variant != "base":
				var vtex := load(bg_path) as Texture2D
				if vtex:
					bg.texture = vtex
		else:
			if map_renderer:
				var bg := map_renderer.find_child("WorldBackground", true, false) as Sprite2D
				if bg:
					var tex := load(bg_path) as Texture2D
					if tex:
						bg.texture = tex
					bg.visible = true
					bg.modulate = Color(0.85, 0.85, 0.9, 0.65)
				var old := map_renderer.find_child("ProvinceMap", true, false) as Sprite2D
				if old:
					old.visible = false
			# Fit so it covers the geo of the 180 (prevents tiny or no image under the outlines).
			if map_renderer:
				var bg2 := map_renderer.find_child("WorldBackground", true, false) as Sprite2D
				if bg2:
					bg2.centered = false
					# For the high-quality larger grand theater map (the one requested for closer zoom views), use large canonical rect so it is the full underlay, not a small overlay.
					# This allows counters, lines, weather, objects to look good when zoomed close on the detailed terrain.
					if map_variant == "grand" or "grand" in bg_path.to_lower():
						bg2.position = Vector2(0, 0)
						# Scale will be computed in _fit using actual texture size and canonical bounds (larger for high res).
						bg2.scale = Vector2(1, 1)  # will be overridden by fit
						print("TestRunner: grand high-res map set (full underlay for close zoom)")
					else:
						bg2.position = Vector2(562, 281)
						bg2.scale = Vector2(3508.0 / 4096.0, 1259.0 / 1465.0)
				if map_renderer and map_renderer.has_method("set_show_terrain_layer"):
					map_renderer.set_show_terrain_layer(true)  # ensure terrain (high-res detailed) visible by default; user can toggle clean via Debug
				# Suppress any old under map in case
				if map_renderer and map_renderer.has_method("_suppress_old_background_maps"):
					map_renderer.call("_suppress_old_background_maps")
					bg2.set_meta("phase1_custom_bg", true)
					bg2.texture_filter = 2  # linear mipmap for zoom detail
					print("TestRunner: phase1 bg image set + scaled for map underlay (variant: ", map_variant, ")")

					# For grand stylized, do not add conflicting small detail overlay (the main bg is the detailed map). For other variants, add the roads one if wanted.
					if map_variant != "grand" and "grand" not in bg_path.to_lower():
						var detail := map_renderer.container.get_node_or_null("DetailOverlay")
						if detail == null:
							detail = Sprite2D.new()
							detail.name = "DetailOverlay"
							detail.texture = load("res://assets/maps/europe_roads_cities_detail_overlay_4k.png") as Texture2D
							detail.position = bg2.position
							detail.scale = bg2.scale
							detail.z_index = -3
							detail.modulate = Color(1,1,1,0.65)
							map_renderer.container.add_child(detail)
							print("TestRunner: Added roads/cities detail overlay for zoom-in details")

		# Add map legend sprite (dimmed, in geo space corner) for reference during zoom/test of rivers/water/buildings etc.
		# (works for both apply and fallback paths)
		if map_renderer and map_renderer.container:
			var leg := map_renderer.container.get_node_or_null("MapLegend")
			if leg == null:
				leg = Sprite2D.new()
				leg.name = "MapLegend"
				leg.texture = load("res://assets/maps/europe_map_legend_1936.png") as Texture2D
				leg.position = Vector2(6200, 150)
				leg.scale = Vector2(0.35, 0.35)
				leg.modulate = Color(1,1,1,0.55)
				map_renderer.container.add_child(leg)
				print("TestRunner: Added map legend for detailed feature reference (rivers, roads, cities etc)")
				# For grand high-res stylized map, hide the small legend if it interferes with the full underlay (can re-enable or move in editor).
				if map_variant == "grand" or "grand" in bg_path.to_lower():
					leg.visible = false

		# When using the grand high-res 8K+ map (even if the phase1 180-prov subset is active for splitter viz),
		# force the large canonical view so the styled image is the playable base and placements/camera use the full image space.
		# The 180 small polys / proposed children are debug overlay on top of the large pretty map.
		if map_renderer and (map_variant == "grand" or "grand" in bg_path.to_lower()):
			if map_renderer.has_method("apply_phase1_europe_background"):
				map_renderer.apply_phase1_europe_background()
			if map_renderer.has_method("_fit_background_to_bounds"):
				map_renderer.call("_fit_background_to_bounds")
			if map_renderer.has_method("_suppress_old_background_maps"):
				map_renderer.call("_suppress_old_background_maps")
			# Force a nice starting camera view centered on the large grand theater image (UK/central Europe visible, room to pan to high north and south).
			var cam_ctrl := get_tree().get_first_node_in_group("camera_controller") as Node
			if cam_ctrl and cam_ctrl.has_method("set_initial_view"):
				cam_ctrl.call("set_initial_view", Vector2(1800, 650), 2.5, true)
			else:
				# Fallback: directly adjust the ProvinceContainers if we can find it
				if map_renderer.container:
					map_renderer.container.position = Vector2(1800, 650)
					map_renderer.container.scale = Vector2(2.5, 2.5)
			print("TestRunner: Forced large grand high-res camera + underlay view (even for 180-prov phase1 test data)")

		# Graphics & visual test harness for phase1 map: NATO symbol unit preview for size QC vs provinces.
		if map_renderer and map_renderer.container:
			if not map_renderer.container.find_child("IconPreviewTest", true, false):
				var p: Node2D = load("res://scenes/IconPreviewTest.tscn").instantiate()
				p.name = "IconPreviewTest"
				p.position = Vector2(3800, 650)
				map_renderer.container.add_child(p)
				print("TestRunner: Auto-loaded IconPreviewTest (NATO wargame counters + sample provinces) for immediate unit size QC vs phase1 content")

		# Demo owners for political colors on provinces (helps see the map as countries).
		if typeof(MapManager) != TYPE_NIL:
			for tag in ["GER", "FRA", "ENG", "SOV", "USA", "ITA", "JAP", "YUG", "SRB", "CRO", "SLO", "HUN", "BGR"]:
				if MapManager.has_method("ensure_country_stub"):
					MapManager.ensure_country_stub(tag)
			# Assign a few provinces to different owners for visual variety and borders if supported.
			var demo_owners := {1: "GER", 2: "FRA", 10: "USA", 20: "ENG"}
			for pid in demo_owners:
				if map_renderer and map_renderer.province_nodes.has(pid):
					MapManager.update_province_owner(pid, demo_owners[pid], demo_owners[pid], true)
			# Balkans-style cluster on phase1 ids (9000+) for BorderLayer demo without manual setup.
			var border_cluster := [9000, 9001, 9002, 9003, 9004, 9005]
			var border_tags := ["YUG", "YUG", "SRB", "SRB", "CRO", "CRO"]
			for i in border_cluster.size():
				if MapManager.get_province(border_cluster[i]) != null:
					MapManager.update_province_owner(
						border_cluster[i], border_tags[i], border_tags[i], true
					)
			if map_renderer and map_renderer.has_method("force_border_update"):
				map_renderer.force_border_update()
				print("TestRunner: YUG/SRB/CRO border demo cluster seeded + BorderLayer refreshed")
			_seed_combat_playtest_divisions()

		# For the phase1 test map: auto-start a demo investment project (active, with some progress)
		# so the investment UI (Invest button state, status label with %, ETA) and any project-related effects
		# are immediately visible/testable in inspector and map.
		if idm and idm.has_method("start_infrastructure_project") and loader and ("phase1" in loader.current_province_data_dir or loader.current_province_data_dir == "provinces_phase1_test"):
			var demo_pid := 1
			var demo_tag := "GER"
			if typeof(MapManager) != TYPE_NIL:
				var dp := MapManager.get_province(demo_pid)
				if dp:
					if dp.owner_tag.is_empty():
						MapManager.update_province_owner(demo_pid, demo_tag, demo_tag, true)
					else:
						demo_tag = dp.owner_tag
			if idm.has_method("ensure_political_power_seed"):
				idm.ensure_political_power_seed(demo_tag)
			# Demo project skips PP spend so harness always shows an active investment.
			var proj = idm.start_infrastructure_project(demo_pid, 2, demo_tag, false)
			if proj:
				print("TestRunner: Demo investment project started on pid ", demo_pid, " for ", demo_tag)

			# Advance a bit for visible progress (leave active).
			if idm and idm.has_method("advance_daily_projects") and proj:
				for i in 5:
					idm.advance_daily_projects(1936, 1, 1 + i)
				print("TestRunner: Advanced demo project ~5 days for visible progress in UI.")

			# Refresh the invest section in case inspector is open or for any live UI.
			if map_renderer and map_renderer.has_method("_update_infrastructure_investment_ui"):
				var p = MapManager.get_province(demo_pid) if typeof(MapManager) != TYPE_NIL else null
				if p:
					map_renderer._update_infrastructure_investment_ui(p)

		# Place example NATO unit counter sprites on the map using the generated symbol suite
		# (for visible graphics on provinces with/without formations in test).
		if map_renderer and map_renderer.container:
			var demo_icons := [
				{"pid": 1, "tex": "res://assets/graphics/units/nato/ww2/infantry_32.png"},
				{"pid": 2, "tex": "res://assets/graphics/units/nato/modern/artillery_32.png"},
				{"pid": 10, "tex": "res://assets/graphics/units/nato/ww2/helicopter_32.png"},
			]
			for di in demo_icons:
				var pid = di.pid
				if not map_renderer.province_nodes.has(pid): continue
				var node = map_renderer.province_nodes[pid]
				# clear old
				for c in node.get_children():
					if c.name.begins_with("DemoNATO_"): c.queue_free()
				var spr := Sprite2D.new()
				spr.name = "DemoNATO_" + str(pid)
				spr.texture = load(di.tex) as Texture2D
				spr.position = Vector2(0, -10)
				spr.scale = Vector2(0.5, 0.5)
				node.add_child(spr)
			print("TestRunner: Placed demo NATO unit symbols on map provinces for graphics visibility.")

			# Simple demo of data-tied objects at gen positions (from province_city_layer) so provinces have objects precisely tied to their areas on the background image.
			if map_renderer and map_renderer.container:
				var op = map_renderer.container.get_node_or_null("DemoDataObjects")
				if op == null:
					op = Node2D.new()
					op.name = "DemoDataObjects"
					map_renderer.container.add_child(op)
				# Use example position from gen data (Berlin area for pid ~2)
				var dpos = Vector2(157, 63)
				var r = ColorRect.new()
				r.size = Vector2(8,8)
				r.position = dpos - r.size*0.5
				r.color = Color(0.9,0.85,0.7)
				op.add_child(r)
				print("TestRunner: Demo data-tied object placed at gen position (tied to province area on the detailed background image).")

			# Place data-driven objects from the map gen city_layer so provinces have tied objects at exact areas.
			# This levels up the playtest: objects are not just procedural at center but use the pre-placed positions from the splitter (tied to the geometry and the background image terrain).
			# The big background image provides the world-class detailed ground (rivers, terrain); vectors + these objects + dynamic infra layers complete the picture.
			if typeof(ScenarioLoader) != TYPE_NIL and loader and loader.province_city_layer:
				var cdata = loader.province_city_layer
				if cdata.has("provinces"):
					var pcity = cdata["provinces"]
					var obj_parent = null
					if map_renderer and map_renderer.container:
						obj_parent = map_renderer.container.get_node_or_null("DataObjects")
						if obj_parent == null:
							obj_parent = Node2D.new()
							obj_parent.name = "DataObjects"
							map_renderer.container.add_child(obj_parent)
					var placed_c = 0
					for ps in pcity:
						var pp = pcity[ps]
						for cc in pp.get("cities", []):
							var pppos = cc.get("position", [0,0])
							var ppos = Vector2(pppos[0], pppos[1]) if pppos is Array else Vector2(0,0)
							var crect = ColorRect.new()
							crect.size = Vector2(7,7)
							crect.position = ppos - crect.size*0.5
							crect.color = Color(0.95,0.9,0.8)
							if obj_parent:
								obj_parent.add_child(crect)
							placed_c += 1
							if placed_c > 12: break
						if placed_c > 12: break
					if placed_c > 0:
						print("TestRunner: Placed ", placed_c, " data-tied city objects at precise positions from province_city_layer (tied to map areas + background image).")

			# === Data-driven province objects (cities etc.) tied to exact areas from map gen ===
			# Uses province_city_layer positions (computed inside province polys by the Python tools).
			# This "levels up" the provinces visually: objects are precisely located relative to the
			# background image terrain/rivers and vector province shapes. The dynamic infra layers
			# (roads etc.) overlay on top for player changes. World-class GS feel: detailed baked
			# environment + tied objects + reactive vectors.
			if loader and loader.province_city_layer and loader.province_city_layer.has("provinces"):
				var city_provs: Dictionary = loader.province_city_layer.get("provinces", {})
				var static_objs: Node2D = null
				if map_renderer and map_renderer.container:
					static_objs = map_renderer.container.get_node_or_null("StaticProvinceObjects")
					if static_objs == null:
						static_objs = Node2D.new()
						static_objs.name = "StaticProvinceObjects"
						map_renderer.container.add_child(static_objs)
				else:
					static_objs = Node2D.new()
					static_objs.name = "StaticProvinceObjects"
					add_child(static_objs)

				var count := 0
				for pid_s in city_provs:
					var pid := int(pid_s)
					var entry: Dictionary = city_provs[pid_s]
					for c in entry.get("cities", []):
						var p = c.get("position", [0,0])
						var pos := Vector2(p[0] if p is Array else 0, p[1] if p is Array and p.size()>1 else 0)
						var sz: float = 5.0 + min(12.0, float(c.get("population", 10000)) / 80000.0)
						var rect := ColorRect.new()
						rect.size = Vector2(sz, sz)
						rect.position = pos - rect.size * 0.5
						rect.color = Color(0.9, 0.85, 0.7, 0.85) if c.get("industry_slots", 0) > 0 else Color(0.7, 0.65, 0.55, 0.8)
						rect.set_meta("name", c.get("name", "?"))
						rect.set_meta("pid", pid)
						static_objs.add_child(rect)
						count += 1
						if count >= 15: break
					if count >= 15: break
				print("TestRunner: Placed %d static objects/cities from province_city_layer data at precise world positions (tied to province areas on the background image + vectors)." % count)

		# Demo "building" infrastructure to make map come alive: upgrade some infra/dev to trigger
		# visible roads (thick lines), rails (tied lines), growing cities (building clusters).
		# These are "player decisions" via infra projects (in real play: spend PP/time to upgrade).
		# Layers are toggleable in F10 DebugOverlay (Infrastructure Projects section).
		if typeof(MapManager) != TYPE_NIL:
			# High infra -> visible roads + rails between this and neighbors
			MapManager.update_province_infrastructure(1, 9)   # GER core: thick roads + rails
			MapManager.update_province_development(1, 8)
			MapManager.update_province_infrastructure(2, 7)   # FRA: roads + some rails, cities
			MapManager.update_province_development(2, 6)
			MapManager.update_province_infrastructure(10, 6) # USA demo: basic roads, growing city
			MapManager.update_province_development(10, 5)
			print("TestRunner: Demo infra/dev upgrades applied - roads/rails/cities should now be visible on map (toggle in F10 infra section).")

			# Explicit "player decision" road/rail builds: these populate the built_*_neighbors arrays on provinces.
			# The MapManager.build_* APIs + overlay rebuild create actual editable Line2D nodes in sub-layers.
			# This demonstrates the map "coming alive" from specific construction choices (not just level thresholds).
			if typeof(MapManager) != TYPE_NIL and MapManager.has_method("build_road_connection"):
				MapManager.build_road_connection(1, 5)   # GER core explicit road
				MapManager.build_road_connection(2, 4)
				MapManager.build_rail_connection(1, 10) # cross demo rail link (visible when toggled + zoomed)
				print("TestRunner: Explicit road/rail connections built via MapManager API (demo of editable infra links).")

				# Demo live *editing* of the layers (add/remove connections updates the sub-layer nodes immediately via rebuild).
				# This shows "editable as needed": roads/rails can be added/removed by player/AI decisions and the map visuals update.
				var ol_edit = get_tree().get_first_node_in_group("infrastructure_overlay")
				MapManager.remove_road_connection(2, 4)
				print("TestRunner: Removed explicit road 2-4 (demo edit).")
				if ol_edit and ol_edit.has_method("rebuild_all_infra_layers"):
					ol_edit.rebuild_all_infra_layers()
				MapManager.build_road_connection(2, 4)
				print("TestRunner: Re-added road 2-4 (edit complete; Dynamic print above should have shown the road count delta).")

			# Force refresh the infra overlay layers (now fully node-based sub-layers for roads/rails + cities buildings + sites runways/docks).
			# This demonstrates the map "coming alive": explicit built roads/rails appear as Line2D children, cities densify with editable rect nodes,
			# airfields/ports/factories add vector runways, docks, chimneys, tanks on the SitesLayer. All toggle with R/T/C/Y (or F10).
			var infra_overlay = get_tree().get_first_node_in_group("infrastructure_overlay")
			if infra_overlay:
				if infra_overlay.has_method("set_show_roads"):
					infra_overlay.set_show_roads(true)
					infra_overlay.set_show_rails(true)
				if infra_overlay.has_method("set_show_cities"):
					infra_overlay.set_show_cities(true)
				if infra_overlay.has_method("set_show_sites"):
					infra_overlay.set_show_sites(true)
				if infra_overlay.has_method("force_full_refresh"):
					infra_overlay.force_full_refresh()
				elif infra_overlay.has_method("rebuild_all_infra_layers"):
					infra_overlay.rebuild_all_infra_layers()

			# Ensure the layer is created in this path too (renderer setup may be after or for custom load)
			if map_renderer and map_renderer.has_method("_setup_infrastructure_overlay_layer"):
				map_renderer._setup_infrastructure_overlay_layer()

			# Demo direct node editing via public API (get_road_layer + pick first Line2D and modify).
			# This is "editable as needed": external code (UI click, AI, inspector) can tweak visuals without full rebuild.
			# Placed after force so layer is populated and visible.
			var ol_for_edit2 = get_tree().get_first_node_in_group("infrastructure_overlay")
			var road_node = null
			if ol_for_edit2 and ol_for_edit2.has_method("get_road_layer"):
				var rlayer = ol_for_edit2.get_road_layer()
				if rlayer and rlayer.get_child_count() > 0:
					road_node = rlayer.get_child(0) as Line2D
			if road_node:
				var orig_w = road_node.width
				var orig_col = road_node.default_color
				road_node.width = 6.0
				road_node.default_color = Color(1, 0.3, 0.3, 0.9)  # highlight a built connection
				print("TestRunner: Temporarily highlighted a road node via get_road_layer (width+color edit demo).")
				# revert after short "demo"
				road_node.width = orig_w
				road_node.default_color = orig_col

			# Demo "player decision": build an airfield (special site) on a demo province.
			# This adds the ✈ icon + construction ring (if under const) or tier visuals.
			# In full game: choose site type in UI, spend resources/time via projects.
			if idm and idm.has_method("start_special_site_project"):
				var af_proj = idm.start_special_site_project(2, "airfield_tier_1", "FRA")
				if af_proj:
					print("TestRunner: Demo 'build airfield' special site project started on 2 (FRA) - visual should appear in infra layer.")
				# Advance the project fully so the site completes and ✈ icon + effects appear immediately in test.
				if af_proj and not af_proj.modifiers.has("special_site_id"):
					af_proj.modifiers["special_site_id"] = "airfield_tier_1"
				if idm.has_method("advance_daily_projects") and af_proj:
					for i in range(40):
						idm.advance_daily_projects(1936, 1, 10 + i)
					print("TestRunner: Advanced airfield project to completion for immediate special site visual (port/airfield/etc demos).")

			# Extra "other things": spawn a completed port + a factory to show variety on the SitesLayer (runways, docks, chimneys, tanks).
			if idm and idm.has_method("debug_spawn_special_site"):
				idm.debug_spawn_special_site(10, "port_tier_2")
				print("TestRunner: Demo port special site spawned on 10 (USA demo province).")
				idm.debug_spawn_special_site(5, "factory_tier_1")
				print("TestRunner: Demo factory special site spawned on 5 for SitesLayer vector elements (chimney, building).")

			print("TestRunner: [MAP VISUALS] Demo data-tied object placement for playtest (provinces leveled with objects at gen positions on bg image + vectors + layers).")

			# Print final layer node counts (after all spawns and rebuilds) so test logs visibly prove the editable sub-layers were populated
			# (roads/rail Line2D, city building rects, sites runways/docks/chimneys/tanks). Toggle with R/T/C/Y or F10.
			var infra_overlay2 = get_tree().get_first_node_in_group("infrastructure_overlay")
			if infra_overlay2:
				# Remove the one-time print guard so the "Dynamic infra layers built" message (from rebuild) will log the final counts including sites.
				if infra_overlay2.has_method("remove_meta"):
					infra_overlay2.remove_meta("logged_infra_layer_build")
				if infra_overlay2.has_method("rebuild_all_infra_layers"):
					infra_overlay2.rebuild_all_infra_layers()
				if infra_overlay2.has_method("get_node_or_null"):
					var r = infra_overlay2.get_node_or_null("RoadLayer")
					var rl = infra_overlay2.get_node_or_null("RailLayer")
					var c = infra_overlay2.get_node_or_null("CityLayer")
					var s = infra_overlay2.get_node_or_null("SitesLayer")
					print("TestRunner: Final infra sub-layer counts - roads:%d rails:%d cities:%d sites:%d (toggle R/T/C/Y)" % [
						r.get_child_count() if r else 0,
						rl.get_child_count() if rl else 0,
						c.get_child_count() if c else 0,
						s.get_child_count() if s else 0
					])

					# Continued iteration demos (use F10 Debug for full interactive):
					# Province Editor: persistent via SaveLoadManager, auto-suggest borders, separate snaps (grid/pop), conflict HL, live picking.
					# Aircraft: AirMissionProfile, status tracker, agent assign for R&D, formation link, ADS modifiers in mission eff.
					print("TestRunner: Continued systems demos ready in Debug (editor persistent/snaps, aircraft profile/tracker).")

					# Real demo hooks for continued systems (deferred — avoid add_child during _ready tree setup).
					call_deferred("_run_continued_system_demos")

					# Demo data-tied placement for better map playtest (objects tied to province areas on the bg image).
					if map_renderer and map_renderer.container:
						var op = map_renderer.container.get_node_or_null("DataTiedDemo")
						if op == null:
							op = Node2D.new()
							op.name = "DataTiedDemo"
							map_renderer.container.add_child(op)
						var dp = Vector2(157, 63)
						var rr = ColorRect.new()
						rr.size = Vector2(8,8)
						rr.position = dp - rr.size*0.5
						rr.color = Color(0.9,0.85,0.7)
						op.add_child(rr)
						print("TestRunner: Demo data-tied object at gen position (tied to province + detailed background image for world class GS).")

	# Force demo of data-tied objects for better playtest visuals (provinces with objects at exact gen positions on the bg image).
	if map_renderer and map_renderer.container:
		var op = map_renderer.container.get_node_or_null("DemoDataObjects2")
		if op == null:
			op = Node2D.new()
			op.name = "DemoDataObjects2"
			map_renderer.container.add_child(op)
		var dpos = Vector2(157, 63)
		var r = ColorRect.new()
		r.size = Vector2(8,8)
		r.position = dpos - r.size*0.5
		r.color = Color(0.9,0.85,0.7)
		op.add_child(r)
		print("TestRunner: Demo data-tied object placed at gen position (tied to province area on the detailed background image for world-class GS playtest).")

	print("TestRunner: [MAP VISUALS] Demo data-tied object placement for playtest (provinces leveled with objects at gen positions on bg image + vectors + layers).")
	if map_renderer and map_renderer.container:
		var op = map_renderer.container.get_node_or_null("DataTiedFinal")
		if op == null:
			op = Node2D.new()
			op.name = "DataTiedFinal"
			map_renderer.container.add_child(op)
		var dp = Vector2(157, 63)
		var rr = ColorRect.new()
		rr.size = Vector2(8,8)
		rr.position = dp - rr.size*0.5
		rr.color = Color(0.9,0.85,0.7)
		op.add_child(rr)
	player_tag = _resolve_player_tag()

	if map_renderer and loader:
		map_renderer.build_supply_network(loader.get_city_layer(), player_tag)
		var sm := get_node_or_null("/root/SupplyManager")
		if sm:
			sm.record_attrition("us_infantry_div_ww2", 120, {"m4_sherman_medium": 2.0})
			sm.advance_supply_day(1.0)
		print("Supply network ready (toggle overlay with L)")

	# Keep the normal playtest loop interactive: TopInfoBar drives TimeManager via its 1s timer.
	# Constrained smoke runs can opt back into the older manual-only mode with EOA_FREEZE_TIME=1.
	var top_bar := get_node_or_null("UILayer/TopInfoBar")
	var tm := get_node_or_null("/root/TimeManager")
	if OS.get_environment("EOA_FREEZE_TIME") == "1":
		if top_bar:
			top_bar.set_process(false)
			top_bar.set_process_internal(false)
			for ch in top_bar.get_children():
				if ch is Timer:
					(ch as Timer).stop()
		if tm:
			if "real_time_accumulator" in tm:
				tm.real_time_accumulator = 0.0
			tm.set_process(false)
			if tm.has_method("set_process_mode"):
				# 4 == PROCESS_MODE_DISABLED
				tm.set_process_mode(4)
		print("TestRunner: Time simulation frozen by EOA_FREEZE_TIME=1 (manual advances only).")
	else:
		if top_bar:
			top_bar.set_process(true)
			top_bar.set_process_internal(true)
			for ch in top_bar.get_children():
				if ch is Timer:
					(ch as Timer).start()
		if tm:
			tm.set_process(true)
			if tm.has_method("set_process_mode"):
				# 0 == PROCESS_MODE_INHERIT
				tm.set_process_mode(0)
		print("TestRunner: Time simulation enabled for interactive playtest (pause/speed controls drive calendar).")

	if mm != null and mm.has_method("has_province_data") and mm.has_province_data():
		print("✅ MapManager ready with %d provinces (ProvinceEffects now centralized)" % mm.get_province_count())

	_configure_top_info_bar(player_tag)
	if typeof(LeaderManager) != TYPE_NIL:
		LeaderManager.set_player_country_tag(player_tag)

	print("TestRunner: Playtest map bootstrapped — production line tests run next frame (map visible first).")
	call_deferred("_run_production_line_tests")


func _run_continued_system_demos() -> void:
	if map_renderer == null or map_renderer.container == null:
		return

	var pe_real: ProvinceEditor = load("res://scripts/map/ProvinceEditor.gd").new()
	pe_real.name = "ProvinceEditorRealDemo"
	map_renderer.container.add_child(pe_real)
	pe_real.set_active(true)
	pe_real._current_points = [Vector2(1800, 550), Vector2(1900, 500), Vector2(1950, 600)]
	pe_real._finish_current_province()
	pe_real.apply_temporary_to_map()
	pe_real.save_session()
	print("TestRunner: Real demo - editor province created/applied/saved (with snaps/persistence).")
	pe_real.set_active(false)

	var ads_real: AircraftDesignSystem = load("res://scripts/air/AircraftDesignSystem.gd").new()
	ads_real.name = "AircraftDesignSystemRealDemo"
	get_tree().root.add_child(ads_real)
	ads_real.get_or_create_design_state("demo_air_test", {"id": "demo_air"})
	ads_real.add_combat_experience("demo_air_test", 500.0)
	if typeof(SupplyManager) != TYPE_NIL:
		print("TestRunner: ADS demo - prototype + XP applied (link to air formations for profiles/missions).")
	var prof := AirMissionProfile.new("demo_wing", "demo_air_test", "COMBAT_LOAD")
	print("TestRunner: Air profile demo: range=", prof.get_effective_range(1000), " mod=", prof.get_mission_modifier())


func _resolve_player_tag() -> String:
	var tag := player_tag
	if loader == null:
		return tag
	if loader.get_country(tag) != null:
		return tag
	for c in loader.countries.values():
		if c is Country:
			return (c as Country).tag
	return tag


func _configure_top_info_bar(player_tag: String) -> void:
	var top_bar: TopInfoBar = get_node_or_null("UILayer/TopInfoBar") as TopInfoBar
	if top_bar != null:
		top_bar.player_country_tag = player_tag
		if top_bar.has_method("_sync_player_country_tag"):
			top_bar._sync_player_country_tag(false)


func _wire_factory_province_lookup() -> void:
	var fm := get_node_or_null("/root/FactoryManager")
	if fm == null or loader == null:
		return
	fm.set_province_lookup(func(province_id: int) -> Province:
		return loader.provinces.get(province_id) as Province
	)


func _run_production_line_tests() -> void:
	var started_ms := Time.get_ticks_msec()
	print("=== Production Line Tests (deferred) ===")
	var passed := ProductionLineTest.run_all(GameData.design_data)
	var elapsed_s := (Time.get_ticks_msec() - started_ms) / 1000.0
	print("✅ Production line tests passed (%.1fs)" % elapsed_s if passed else "❌ Production line tests failed (%.1fs)" % elapsed_s)


func _seed_combat_playtest_divisions() -> void:
	if typeof(SupplyManager) == TYPE_NIL or typeof(MapManager) == TYPE_NIL:
		return

	# GER vs FRA: province 1 → adjacent enemy (demo owners already set GER/FRA on 1/2 when adjacent).
	if MapManager.get_province(1) != null:
		MapManager.update_province_owner(1, "GER", "GER", true)
		var ger := SupplyManager.move_formation_to_province("german_infantry_division_1943", 1, "GER")
		if bool(ger.get("ok", false)):
			print(
				"TestRunner: GER division on province 1 — set TopInfoBar to GER, click 1 to stage, Ctrl+click FRA neighbor"
			)

	# USA player default: division on province 10.
	var usa := SupplyManager.move_formation_to_province("us_infantry_div_ww2", 10, "USA")
	if bool(usa.get("ok", false)):
		print("TestRunner: USA infantry on province 10 — stage friendly province, Ctrl+click enemy neighbor")

	if map_renderer and map_renderer.has_method("_update_unit_icons_for_test"):
		map_renderer.call_deferred("_update_unit_icons_for_test")
