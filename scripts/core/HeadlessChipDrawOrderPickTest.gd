extends SceneTree

## Overlapping chips: the click must open the ink Godot draws on top.
## DNK AW3 StatBars / designation sit on the NLD Div 1 plate. Bars and
## text are z=3; the plate is z=-1. A bar or label pixel returns DNK.
## Bare NLD plate (local 0, 12), clear of DNK ink, returns NLD.
## Zoom 0.318 is the Home band where painted pick runs (z < 0.65).
## Headless is NOT live Play. Never set EOA_SKIP_TITLE.
##
##   tools/run_godot.sh --headless --path . -s res://scripts/core/HeadlessChipDrawOrderPickTest.gd

const NLD_FID := "NLD_formation_1"
const DNK_FID := "DNK_formation_3"
const NLD_PID := 710385
const DNK_PID := 710380
const ZOOM := 0.318

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _fail(msg: String) -> void:
	_failures += 1
	print("  [FAIL] HeadlessChipDrawOrderPickTest: ", msg)


func _pass(msg: String) -> void:
	print("  [PASS] HeadlessChipDrawOrderPickTest: ", msg)


func _finish() -> void:
	var ok := _failures == 0
	print("HeadlessChipDrawOrderPickTest: ", "PASS" if ok else "FAIL", " (failures=", _failures, ")")
	print("HeadlessChipDrawOrderPickTest: RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _fid(fo: Object) -> String:
	if fo != null and "formation_id" in fo:
		return str(fo.formation_id)
	return ""


func _make_formation(fid: String, tag: String, kind: String, fname: String, pid: int) -> Object:
	var fscr: Script = load("res://scripts/formations/Formation.gd") as Script
	if fscr == null:
		return null
	var fo: Object = fscr.new()
	fo.set("formation_id", fid)
	fo.set("country_tag", tag)
	fo.set("formation_type", kind)
	fo.set("name", fname)
	fo.set("stationed_province_id", pid)
	fo.set("strength", 1.0)
	fo.set("organization", 1.0)
	return fo


func _host(container: Node2D, mr: Node, pid: int) -> Node2D:
	var host := Node2D.new()
	host.name = "Province_%d" % pid
	container.add_child(host)
	if "province_nodes" in mr:
		mr.province_nodes[pid] = host
	return host


func _chip(host: Node2D, pid: int, fo: Object, origin: Vector2, scale: float) -> Node2D:
	var icon := Node2D.new()
	icon.name = "DemoUnitIcon_%d" % pid
	icon.visible = true
	icon.z_index = 28
	icon.z_as_relative = false
	host.add_child(icon)
	icon.global_position = origin
	icon.scale = Vector2(scale, scale)
	icon.set_meta("formation", fo)
	icon.set_meta("formation_id", str(fo.formation_id))
	icon.set_meta("province_id", pid)
	icon.set_meta("sea_nation_disk", false)
	return icon


func _label_on_nld_plate(mr: Node, dnk: Node2D, nld: Node2D) -> Vector2:
	var desig: Node2D = dnk.get_node_or_null("Designation") as Node2D
	if desig == null:
		return Vector2(INF, INF)
	var r: Rect2 = mr.call("_chip_text_glyph_local_rect", desig)
	r = r.grow(0.75)
	if r.size.x <= 0.0 and r.size.y <= 0.0:
		return Vector2(INF, INF)
	var on_face := Vector2(INF, INF)
	for iy in range(7):
		for ix in range(7):
			var lx: float = r.position.x + r.size.x * (float(ix) + 0.5) / 7.0
			var ly: float = r.position.y + r.size.y * (float(iy) + 0.5) / 7.0
			var world: Vector2 = desig.get_global_transform() * Vector2(lx, ly)
			if not bool(mr.call("_world_in_chip_text_node", world, desig)):
				continue
			if bool(mr.call("_world_in_unit_plate_interior", world, nld)):
				return world
			if on_face.x > 1.0e8 and bool(mr.call("_world_in_unit_nation_plate", world, nld)):
				on_face = world
	return on_face


func _assert_both(mr: Node, world: Vector2, want: String, label: String) -> bool:
	var drawn: Object = mr.call("_pick_drawn_land_air_body_at_world", world, ZOOM)
	var formed: Object = mr.call("_pick_unit_formation_at_world", world)
	var got_d := _fid(drawn)
	var got_f := _fid(formed)
	if got_d != want or got_f != want:
		_fail("%s drawn=%s formation=%s want %s" % [label, got_d, got_f, want])
		return false
	return true


func _run() -> void:
	var mr_script: Script = load("res://scripts/map/MapRenderer.gd") as Script
	if mr_script == null:
		_fail("MapRenderer.gd missing")
		_finish()
		return
	var mr: Node = mr_script.new()
	var ui := CanvasLayer.new()
	ui.name = "UI"
	mr.add_child(ui)
	var cam := Camera2D.new()
	cam.name = "MapCamera"
	cam.position = Vector2(2000, 2000)
	cam.zoom = Vector2(ZOOM, ZOOM)
	mr.add_child(cam)
	var container := Node2D.new()
	container.name = "ProvinceContainers"
	mr.add_child(container)
	if "container" in mr:
		mr.container = container
	root.add_child(mr)
	cam.make_current()
	await process_frame
	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.make_current()
	var lm: Node = root.get_node_or_null("LeaderManager")
	if lm != null and lm.has_method("set_player_country_tag"):
		lm.call("set_player_country_tag", "GER")
	if "show_unit_counters" in mr:
		mr.show_unit_counters = true

	var nld_fo: Object = _make_formation(NLD_FID, "NLD", "division", "NLD Div 1", NLD_PID)
	var dnk_fo: Object = _make_formation(DNK_FID, "DNK", "air_wing", "DNK AW3", DNK_PID)
	if nld_fo == null or dnk_fo == null:
		_fail("Formation create failed")
		_finish()
		return
	if lm != null and "formations" in lm:
		lm.formations[NLD_FID] = nld_fo
		lm.formations[DNK_FID] = dnk_fo

	var scale: float = float(mr.call("_unit_counter_scale_for_zoom", ZOOM))
	if scale < 1.0:
		_fail("Home scale %.3f at z %.3f" % [scale, ZOOM])
		_finish()
		return
	var nld_origin := Vector2(2000, 2000)
	# StatBars centre is counter-local (0, 27). Park DNK so that centre
	# is the NLD plate origin: DNK bars on the NLD inner face.
	var dnk_origin: Vector2 = nld_origin - Vector2(0.0, 27.0) * scale
	var nld_host: Node2D = _host(container, mr, NLD_PID)
	var dnk_host: Node2D = _host(container, mr, DNK_PID)
	var nld: Node2D = _chip(nld_host, NLD_PID, nld_fo, nld_origin, scale)
	var dnk: Node2D = _chip(dnk_host, DNK_PID, dnk_fo, dnk_origin, scale)
	if "_demo_unit_icon_pids" in mr:
		mr._demo_unit_icon_pids = [NLD_PID, DNK_PID]
	mr.call("_attach_unit_counter_chrome", nld, nld_fo, Color(0.2, 0.45, 0.72, 1.0))
	mr.call("_attach_unit_counter_chrome", dnk, dnk_fo, Color(0.75, 0.15, 0.18, 1.0))
	nld.z_index = 28
	nld.z_as_relative = false
	dnk.z_index = 28
	dnk.z_as_relative = false
	nld.scale = Vector2(scale, scale)
	dnk.scale = Vector2(scale, scale)

	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.make_current()
	var seen_z: float = float(mr.call("_get_camera_zoom"))
	if seen_z >= 0.65:
		_fail("camera zoom %.3f is outside the painted-pick band" % seen_z)
		_finish()
		return
	var bars_node: Node = dnk.get_node_or_null("StatBars")
	var plate_node: Node = nld.get_node_or_null("NationPlate")
	var text_node: Node = dnk.get_node_or_null("Designation")
	if bars_node == null or plate_node == null or text_node == null:
		_fail("chrome missing bars/plate/designation")
		_finish()
		return
	var z_bars: int = int(mr.call("_canvas_item_effective_z", bars_node))
	var z_text: int = int(mr.call("_canvas_item_effective_z", text_node))
	var z_plate: int = int(mr.call("_canvas_item_effective_z", plate_node))
	if z_bars <= z_plate or z_text <= z_plate:
		_fail("draw z bars=%d text=%d plate=%d (bars/text must beat the plate)" % [z_bars, z_text, z_plate])
		_finish()
		return
	_pass("draw z bars %d text %d above plate %d" % [z_bars, z_text, z_plate])

	var bar_pt: Vector2 = dnk.get_global_transform() * Vector2(0.0, 27.0)
	if not bool(mr.call("_world_in_unit_stat_bars", bar_pt, dnk)):
		_fail("bar pixel is not in DNK StatBars")
		_finish()
		return
	if not bool(mr.call("_world_in_unit_plate_interior", bar_pt, nld)):
		_fail("bar pixel is not on the NLD inner face")
		_finish()
		return
	if not bool(mr.call("_unit_counter_painted_wins", dnk, nld, bar_pt, 0.0, 0.0)):
		_fail("painted_wins let the NLD plate beat DNK bars")
		_finish()
		return
	if bool(mr.call("_unit_counter_painted_wins", nld, dnk, bar_pt, 0.0, 0.0)):
		_fail("painted_wins(NLD, DNK) true on DNK bar ink")
		_finish()
		return
	if not _assert_both(mr, bar_pt, DNK_FID, "DNK bar on NLD inner face"):
		_finish()
		return
	_pass("bar pixel opens DNK AW3")

	var label_pt: Vector2 = _label_on_nld_plate(mr, dnk, nld)
	if label_pt.x > 1.0e8:
		_fail("DNK designation does not sit on the NLD plate")
		_finish()
		return
	if bool(mr.call("_world_in_unit_stat_bars", label_pt, dnk)):
		_fail("label sample landed in DNK StatBars")
		_finish()
		return
	if not _assert_both(mr, label_pt, DNK_FID, "DNK label on NLD plate"):
		_finish()
		return
	_pass("label pixel opens DNK AW3")

	var bare: Vector2 = nld.get_global_transform() * Vector2(0.0, 12.0)
	if bool(mr.call("_world_in_unit_painted_rect", bare, dnk)):
		var dnk_local: Vector2 = dnk.get_global_transform().affine_inverse() * bare
		_fail("bare NLD plate is inside DNK paint (dnk local %.1f,%.1f)" % [dnk_local.x, dnk_local.y])
		_finish()
		return
	if not bool(mr.call("_world_in_unit_plate_interior", bare, nld)):
		_fail("bare point is not the NLD inner face")
		_finish()
		return
	if not _assert_both(mr, bare, NLD_FID, "bare NLD plate"):
		_finish()
		return
	_pass("bare NLD plate opens NLD Div 1")
	_finish()
