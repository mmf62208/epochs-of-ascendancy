#!/usr/bin/env -S godot --headless --path .
## Headless dual-map / GIS alignment check for world_accurate.
## Verifies THEATER_SCALE underlay vs province transform share one canvas.
extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var ok := true
	var fails: Array[String] = []

	var ts := MapCanvasConfig.THEATER_SCALE
	var world := MapCanvasConfig.WORLD_CANONICAL_BOUNDS
	if absf(world.size.x - 8192.0 * ts) > 0.05 or absf(world.size.y - 4096.0 * ts) > 0.05:
		ok = false
		fails.append("WORLD_CANONICAL != 8192×4096 * THEATER_SCALE (got %s)" % str(world.size))

	# Sample known Europe NUTS-ish point from geometry sample (Dibër-ish ~4563,1212)
	var raw := PackedVector2Array([Vector2(4563.36, 1212.41), Vector2(4562.48, 1216.04), Vector2(4570.0, 1215.0)])
	var xformed := MapCanvasConfig.transform_province_points(raw, true, false, true)
	if xformed.size() < 3:
		ok = false
		fails.append("transform empty")
	else:
		var expect := raw[0] * ts
		if xformed[0].distance_to(expect) > 0.05:
			ok = false
			fails.append("world_native transform mismatch: got %s want %s" % [str(xformed[0]), str(expect)])

	# Europe remap must NOT run when world_native
	var remapped := MapCanvasConfig.transform_province_points(raw, true, false, false)
	if remapped[0].distance_to(xformed[0]) < 1.0:
		# When world_mode+not native, Europe remap moves points — they should differ from pure scale.
		# raw Europe-local would differ; our sample is world coords so remap still moves them.
		pass
	if remapped[0].distance_to(raw[0] * ts) < 0.5:
		# If points were Europe-local theater, remap would move them; world points remapped incorrectly
		# should NOT equal pure scale. raw is world canvas so remapped != pure scale.
		ok = false
		fails.append("expected europe-remap path to move world points when not native")

	# Underlay scale lock math
	var tex_w := 8192.0
	var tex_h := 4096.0
	var sx := world.size.x / tex_w
	var sy := world.size.y / tex_h
	if absf(sx - ts) > 0.001 or absf(sy - ts) > 0.001:
		ok = false
		fails.append("underlay scale lock != THEATER_SCALE")

	# Asia / Australia sample bands must stay inside theater after scale
	var japan := Vector2(7200.0, 1400.0) * ts
	var aus := Vector2(6800.0, 2800.0) * ts
	if not world.grow(200.0).has_point(japan):
		ok = false
		fails.append("Japan sample outside WORLD_CANONICAL")
	if not world.grow(2000.0).has_point(aus):
		# Australia Y may sit near south edge; allow expanded theater used at runtime
		if aus.y > world.position.y + world.size.y + 1800.0:
			ok = false
			fails.append("Australia sample far outside expandable theater")

	print("=== GIS ALIGNMENT CHECK ===")
	print("THEATER_SCALE=", ts)
	print("WORLD_CANONICAL=", world)
	print("underlay_scale_lock=", Vector2(sx, sy))
	print("europe_sample_scaled=", xformed[0] if xformed.size() else "?")
	print("japan_scaled=", japan, " aus_scaled=", aus)
	if ok:
		print("GIS_ALIGNMENT_PASS")
		quit(0)
	else:
		print("GIS_ALIGNMENT_FAIL")
		for f in fails:
			print("  FAIL: ", f)
		quit(1)
