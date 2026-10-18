extends SceneTree

## ROADS-1 quiet roads: width table, mode alpha, casing-before-fill, z order, stub filter.
## Each real mutant below must fail this guard:
##   (a) highway_casing_px far floor of 20
##   (b) casing and fill interleaved per edge in build_road_draw_plan
##   (c) ROAD_BELOW_UNITS_Z back to 21
##   (d) road_tier_mode_alpha always 1
##   (e) highway_endpoints_in_rings always true, or the overlay stops calling it
##
##   tools/run_godot.sh --headless -s res://scripts/core/HeadlessRoads1QuietGuard.gd

const RoadTierVisualScript = preload("res://scripts/map/RoadTierVisual.gd")
const SRC_OL := "res://scripts/map/InfrastructureOverlayLayer.gd"
const SRC_REN := "res://scripts/map/MapRenderer.gd"
const SRC_RHINE := "res://scripts/map/Rx1RhineLayer.gd"

var _failures := 0


func _init() -> void:
	call_deferred("_run_and_quit")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessRoads1QuietGuard: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessRoads1QuietGuard: ", msg)


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _const_int(src: String, name: String) -> int:
	var needle := "const %s := " % name
	var i := src.find(needle)
	if i < 0:
		return -1
	var rest := src.substr(i + needle.length(), 8)
	var digits := ""
	for ch in rest:
		if ch < "0" or ch > "9":
			break
		digits += ch
	return int(digits) if digits != "" else -1


func _run_and_quit() -> void:
	_test_widths()
	_test_modes()
	_test_casing_order()
	_test_stub_filter()
	_test_z_order()
	var ok := _failures == 0
	print("HeadlessRoads1QuietGuard: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessRoads1QuietGuard: RESULT=", "PASS" if ok else "FAIL")
	if OS.has_method("flush_stdout"):
		OS.call("flush_stdout")
	quit(0 if ok else 1)


func _test_widths() -> void:
	var zooms: Array = [0.45, 0.70, 1.0, 1.6, 2.4, 2.8, 4.0, 6.0]
	var prev := -1.0
	for z_v in zooms:
		var z: float = float(z_v)
		var case_px: float = RoadTierVisualScript.highway_casing_px(z)
		var outer: float = RoadTierVisualScript.tier_outer_px(RoadTierVisualScript.TIER_HIGHWAY, z)
		if outer + 0.001 < prev:
			_fail("highway outer not monotonic at z=%.2f (%.2f < %.2f)" % [z, outer, prev])
			return
		if outer < 0.99:
			_fail("highway outer %.2f < 1 px at z=%.2f" % [outer, z])
			return
		if z <= 1.0 and case_px > 4.01:
			_fail("casing %.2f > 4 at z=%.2f (20 px floor mutant)" % [case_px, z])
			return
		if (is_equal_approx(z, 1.6) or is_equal_approx(z, 2.4)) and case_px > 6.01:
			_fail("casing %.2f > 6 at z=%.2f" % [case_px, z])
			return
		if z >= 2.8 and case_px > 9.01:
			_fail("casing %.2f > 9 at z=%.2f" % [case_px, z])
			return
		prev = outer
	if absf(RoadTierVisualScript.highway_casing_px(1.0) - 2.6) > 0.05:
		_fail("z1 casing want 2.6 got %.3f" % RoadTierVisualScript.highway_casing_px(1.0))
		return
	if absf(RoadTierVisualScript.highway_casing_px(4.0) - 8.0) > 0.05:
		_fail("z4 casing want 8 got %.3f" % RoadTierVisualScript.highway_casing_px(4.0))
		return
	if RoadTierVisualScript.road_zoom_ramp(RoadTierVisualScript.TIER_DIRT, 2.40) > 0.001:
		_fail("dirt ramp must be 0 at z2.40")
		return
	if RoadTierVisualScript.road_zoom_ramp(RoadTierVisualScript.TIER_DIRT, 3.0) < 0.999:
		_fail("dirt ramp must be 1 at z3")
		return
	if not RoadTierVisualScript.dirt_hidden_at_zoom(0.55):
		_fail("dirt_hidden_at_zoom(0.55) must stay true")
		return
	_pass("width table within caps, monotonic, no 20 px floor")


func _test_modes() -> void:
	if RoadTierVisualScript.road_mode_bucket("munitions", false) != "other":
		_fail("munitions must sit in the other bucket")
		return
	if RoadTierVisualScript.road_mode_bucket("political", true) != "logistics":
		_fail("L-on political must be logistics")
		return
	if RoadTierVisualScript.road_mode_bucket("supply", false) != "logistics":
		_fail("supply must be logistics")
		return
	if RoadTierVisualScript.road_mode_bucket("infra", false) != "logistics":
		_fail("infra must be logistics")
		return
	if RoadTierVisualScript.road_mode_bucket("resources", false) != "logistics":
		_fail("resources must be logistics")
		return
	if RoadTierVisualScript.road_mode_bucket("terrain", false) != "terrain":
		_fail("terrain bucket")
		return
	if RoadTierVisualScript.road_mode_bucket("weather", false) != "other":
		_fail("weather must be other")
		return
	var pol := RoadTierVisualScript.road_tier_mode_alpha("political", RoadTierVisualScript.TIER_HIGHWAY, 2.4)
	var ter := RoadTierVisualScript.road_tier_mode_alpha("terrain", RoadTierVisualScript.TIER_HIGHWAY, 2.4)
	var oth := RoadTierVisualScript.road_tier_mode_alpha("other", RoadTierVisualScript.TIER_HIGHWAY, 2.4)
	if absf(pol - 0.18) > 0.011 or absf(ter - 0.25) > 0.011 or absf(oth - 0.12) > 0.011:
		_fail("z2.4 highway alpha political=%.3f terrain=%.3f other=%.3f" % [pol, ter, oth])
		return
	if RoadTierVisualScript.road_tier_mode_alpha("political", RoadTierVisualScript.TIER_HIGHWAY, 0.7) > 0.001:
		_fail("political highway must be 0 at z0.7")
		return
	if RoadTierVisualScript.road_tier_mode_alpha("political", RoadTierVisualScript.TIER_PAVED, 2.4) > 0.001:
		_fail("political paved must be 0")
		return
	if RoadTierVisualScript.road_tier_mode_alpha("other", RoadTierVisualScript.TIER_DIRT, 2.4) > 0.001:
		_fail("other dirt must be 0")
		return
	if absf(RoadTierVisualScript.road_tier_mode_alpha("logistics", RoadTierVisualScript.TIER_DIRT, 0.5) - 1.0) > 0.001:
		_fail("logistics tier alpha must stay 1 even when the zoom ramp is 0")
		return
	_pass("mode buckets and highway alphas")


func _test_casing_order() -> void:
	var edges: Array = [
		{"p1": 1, "p2": 2, "c1": Vector2(0, 0), "c2": Vector2(100, 0), "display_tier": 2},
		{"p1": 2, "p2": 3, "c1": Vector2(100, 0), "c2": Vector2(100, 80), "display_tier": 2},
		{"p1": 3, "p2": 4, "c1": Vector2(100, 80), "c2": Vector2(180, 80), "display_tier": 2},
	]
	var chains: Array = RoadTierVisualScript.build_road_chains(edges)
	if chains.size() != 1:
		_fail("bent highway should be one chain, got %d" % chains.size())
		return
	var pts: PackedVector2Array = chains[0].get("pts", PackedVector2Array())
	if pts.size() != 4:
		_fail("chain should have 4 vertices, got %d" % pts.size())
		return
	var plan: Array = RoadTierVisualScript.build_road_draw_plan(chains, 4.0, true)
	if not RoadTierVisualScript.road_plan_casing_before_fill(plan):
		_fail("casing ops must all precede fill ops")
		return
	var discs := RoadTierVisualScript.road_plan_interior_casing_discs(plan)
	if discs != 2:
		_fail("want one casing disc per interior vertex (2), got %d" % discs)
		return
	var saw_case := false
	var saw_fill := false
	for op_v in plan:
		var kind := str((op_v as Dictionary).get("op", ""))
		if kind.begins_with("casing"):
			saw_case = true
		elif kind.begins_with("fill"):
			saw_fill = true
	if not saw_case or not saw_fill:
		_fail("logistics z4 plan missing casing or fill")
		return
	var political: Array = RoadTierVisualScript.build_road_draw_plan(chains, 4.0, false)
	for op_v2 in political:
		var kind2 := str((op_v2 as Dictionary).get("op", ""))
		if kind2.begins_with("casing") or kind2.begins_with("stripe"):
			_fail("non-logistics plan must skip casing and stripe")
			return
	_pass("casing before fill, 2 interior discs, no casing outside logistics")


func _test_stub_filter() -> void:
	var ring := PackedVector2Array([
		Vector2(-10, -10), Vector2(10, -10), Vector2(10, 10), Vector2(-10, 10),
	])
	var rings: Array = [ring]
	if not RoadTierVisualScript.highway_endpoints_in_rings(Vector2(0, 0), Vector2(1, 1), rings):
		_fail("both endpoints inside the ring must draw")
		return
	if RoadTierVisualScript.highway_endpoints_in_rings(Vector2(0, 0), Vector2(50, 0), rings):
		_fail("an endpoint outside the ring must drop (stub mutant)")
		return
	if not RoadTierVisualScript.highway_endpoints_in_rings(Vector2(0, 0), Vector2(50, 0), []):
		_fail("empty ring list must fail open")
		return
	var ol := _read(SRC_OL)
	if "highway_endpoints_in_rings" not in ol or "func _highway_edge_drawable" not in ol:
		_fail("overlay must filter highway edges through highway_endpoints_in_rings")
		return
	_pass("highway stub filter drops an endpoint outside drawn rings")


func _test_z_order() -> void:
	var ol := _read(SRC_OL)
	var ren := _read(SRC_REN)
	var rhine := _read(SRC_RHINE)
	var casing := _const_int(ol, "ROAD_CASING_Z")
	var fill := _const_int(ol, "ROAD_FILL_Z")
	var road := _const_int(ol, "ROAD_BELOW_UNITS_Z")
	var gold := _const_int(ol, "GOLD_SPINE_Z")
	var spine := _const_int(ol, "SPINE_BELOW_UNITS_Z")
	var river := _const_int(rhine, "MAP_BELOW_UNITS_Z")
	if casing != 10 or fill != 11 or road != 11:
		_fail("road z want casing 10 fill 11 below-units 11, got %d %d %d" % [casing, fill, road])
		return
	if river != 9 or not (river < casing and casing < 15):
		_fail("want river 9 < casing 10 < BorderLayer 15, river=%d" % river)
		return
	if gold <= 18 or gold >= 28 or spine <= 15:
		_fail("gold spine %d and preview %d must stay above borders" % [gold, spine])
		return
	if "func _sync_road_quiet_mode" not in ren or "apply_road_map_mode" not in ren:
		_fail("MapRenderer must call apply_road_map_mode from _sync_road_quiet_mode")
		return
	if "build_road_draw_plan" not in ol or "_draw_road_quad" not in ol:
		_fail("overlay must paint quads from build_road_draw_plan")
		return
	var setup_i := ren.find("func _setup_rx1_rhine_layer")
	var setup := ren.substr(setup_i, 900) if setup_i >= 0 else ""
	if "z_index = 22" in setup or ", 9)" not in setup:
		_fail("Rhine spawn in MapRenderer must be z=9")
		return
	_pass("river < roads < borders; gold spine stays above borders")
