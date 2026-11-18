# scripts/ui/victory/VictorySceneLayers.gd
## Shared picture: sky, skyline, foreground, flag, particles.
## Timeline uses real deltas. Seeds are constants. No randf/randi.
class_name VictorySceneLayers
extends Control

const REF := Vector2(1280, 800)
const POLE_BASE_Y := 600.0
const FLAG_TOP_Y := 64.0
const BURN_START := 0.75
const BURN_END := 13.0
const WIN_INPUT := 6.6
const WIN_FADE := 6.15
const LOSS_INPUT := 5.0

const SEED_BIRD := 24011
const SEED_FLAME := 24021
const SEED_EMBER := 24031
const SEED_ASH := 24041
const SEED_SMOKE := 24051

var flag_material: ShaderMaterial
var skyline_material: ShaderMaterial
var mode: String = "win"
var restrained: bool = false

var _time: float = 0.0
var _skipped: bool = false
var _built: Dictionary = {}
var _flag_node: Node2D
var _cloth_h: float = 240.0
var _driven: bool = false


func configure(built: Dictionary) -> void:
	_built = built
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = REF
	custom_minimum_size = REF
	var template := str(built.get("template", "WIN"))
	mode = "win"
	if template == "DEFEAT":
		mode = str(built.get("mode", "burning"))
		if mode != "eclipsed":
			mode = "burning"
	restrained = bool(built.get("restrained", false))
	var assets: Dictionary = built.get("assets", {}) if built.get("assets") is Dictionary else {}
	var flag: Dictionary = assets.get("flag", {}) if assets.get("flag") is Dictionary else {}
	_cloth_h = float(flag.get("cloth_h", 240.0))
	_build_sky(assets)
	_build_skyline(assets)
	_build_foreground(assets)
	_build_flag(assets)
	_build_particles(assets)
	_build_copy(built)
	_build_fade()
	_apply()


func tick(delta: float) -> void:
	_driven = true
	if not _skipped:
		_time += maxf(0.0, delta)
	_apply()


func _process(delta: float) -> void:
	if _driven:
		return
	tick(delta)


func _exit_tree() -> void:
	var fx := get_node_or_null("FxParticles")
	if fx == null:
		return
	for c in fx.get_children():
		if c is CPUParticles2D:
			VictorySceneModel.release_cpu_particle(c)


func skip() -> void:
	_skipped = true
	if mode == "burning":
		_time = BURN_END
	elif mode == "win":
		_time = WIN_INPUT
	else:
		_time = LOSS_INPUT
	_apply()


func input_live() -> bool:
	if _skipped:
		return true
	if mode == "win":
		return _time >= WIN_INPUT
	return _time >= LOSS_INPUT


func button_alpha() -> float:
	if _skipped:
		return 1.0
	if mode == "win":
		if _time <= WIN_FADE:
			return 0.0
		return clampf((_time - WIN_FADE) / 0.45, 0.0, 1.0)
	if _time < LOSS_INPUT:
		return 0.0
	return 1.0


func burn_amount() -> float:
	if mode != "burning":
		return 0.0
	if _skipped:
		return 0.5
	if _time <= BURN_START:
		return 0.0
	return clampf(0.5 * (_time - BURN_START) / (BURN_END - BURN_START), 0.0, 0.5)


func _apply() -> void:
	var burn := burn_amount()
	var pose := _flag_pose()
	if flag_material != null:
		if mode == "burning":
			flag_material.set_shader_parameter("burn", burn)
		flag_material.set_shader_parameter("time_s", _time)
		if mode != "burning":
			flag_material.set_shader_parameter("furled", float(pose.get("furled", 0.0)))
	if skyline_material != null:
		skyline_material.set_shader_parameter("time_s", _time)
		var assets: Dictionary = _built.get("assets", {}) if _built.get("assets") is Dictionary else {}
		skyline_material.set_shader_parameter("ruin", float(assets.get("ruin", 0.0)))
	var sky := get_node_or_null("SkyGrade")
	if sky == null:
		sky = get_node_or_null("ProceduralBackdrop")
	if sky != null and sky.material is ShaderMaterial:
		var sm := sky.material as ShaderMaterial
		sm.set_shader_parameter("time_s", _time)
		sm.set_shader_parameter("light", _light())
		sm.set_shader_parameter("rays", 0.15 if mode == "win" and not restrained else 0.0)
	if _flag_node != null:
		_flag_node.position = pose.get("pos", Vector2.ZERO)
	var fade := get_node_or_null("FadeBlack") as CanvasItem
	if fade != null:
		var dur := 0.6 if restrained else 0.2
		fade.modulate.a = 0.0 if _skipped else clampf(1.0 - _time / dur, 0.0, 1.0)


func _flag_pose() -> Dictionary:
	var furled := 0.0
	var y := FLAG_TOP_Y
	if mode == "burning":
		return {"furled": 0.0, "pos": Vector2(220, 560)}
	if mode == "eclipsed":
		return {"furled": 1.0, "pos": Vector2(248, 592)}
	var climb := 1.0
	if restrained:
		climb = clampf(_time / 4.25, 0.0, 1.0)
	elif _time < 0.54:
		climb = 0.0
	elif _time < 3.0:
		climb = (_time - 0.54) / (3.0 - 0.54)
	furled = 1.0 - climb
	var rest_y := POLE_BASE_Y - _cloth_h - 30.0
	y = lerpf(rest_y, FLAG_TOP_Y, climb)
	return {"furled": furled, "pos": Vector2(193, y)}


func _light() -> float:
	if mode != "win":
		return 0.55 if mode == "eclipsed" else 0.35
	if restrained:
		return clampf(0.25 + _time / 6.6, 0.25, 0.85)
	return clampf(_time / 3.62, 0.15, 1.0)


func _build_sky(assets: Dictionary) -> void:
	var shared: Dictionary = assets.get("shared", {}) if assets.get("shared") is Dictionary else {}
	var procedural := str(assets.get("backdrop", "")) == "procedural"
	var rect := ColorRect.new()
	rect.name = "ProceduralBackdrop" if procedural else "SkyGrade"
	rect.position = Vector2.ZERO
	rect.size = REF
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := load("res://assets/shaders/victory/sky_grade.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var sky_key := "sky_dawn"
		if mode == "burning":
			sky_key = "sky_defeat"
		elif mode == "eclipsed":
			sky_key = "sky_eclipsed"
		mat.set_shader_parameter("grad_a", _tex(str(shared.get("sky_predawn", ""))))
		mat.set_shader_parameter("grad_b", _tex(str(shared.get(sky_key, ""))))
		mat.set_shader_parameter("clouds", _tex(str(shared.get("noise_clouds", ""))))
		mat.set_shader_parameter("light", 0.2)
		mat.set_shader_parameter("rays", 0.0)
		mat.set_shader_parameter("time_s", 0.0)
		rect.material = mat
	add_child(rect)


func _build_skyline(assets: Dictionary) -> void:
	if str(assets.get("backdrop", "")) == "procedural":
		return
	var path := str(assets.get("skyline", ""))
	var tex := _tex(path)
	var rect := TextureRect.new()
	rect.name = "Skyline"
	rect.position = Vector2(0, 200)
	rect.size = Vector2(1280, 480)
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shader := load("res://assets/shaders/victory/skyline_ruin.gdshader") as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var roof := str(assets.get("roof", ""))
		var shared: Dictionary = assets.get("shared", {}) if assets.get("shared") is Dictionary else {}
		var pal: Dictionary = assets.get("palette", {}) if assets.get("palette") is Dictionary else {}
		mat.set_shader_parameter("skyline_tex", tex)
		mat.set_shader_parameter("roof_tex", _tex(roof) if not roof.is_empty() else VictorySceneModel.fallback_texture())
		mat.set_shader_parameter("noise_tex", _tex(str(shared.get("noise_fine", ""))))
		mat.set_shader_parameter("use_roof", 0.0 if roof.is_empty() else 1.0)
		mat.set_shader_parameter("ruin", float(assets.get("ruin", 0.0)))
		mat.set_shader_parameter("seed", 2.0)
		mat.set_shader_parameter("far_color", pal.get("far", Color(0.55, 0.42, 0.4)))
		mat.set_shader_parameter("mid_color", pal.get("mid", Color(0.15, 0.15, 0.26)))
		mat.set_shader_parameter("rim_color", pal.get("rim", Color(1.0, 0.8, 0.5)))
		mat.set_shader_parameter("ember_amt", 1.0 if mode == "burning" else 0.0)
		rect.material = mat
		skyline_material = mat
	add_child(rect)


func _build_foreground(assets: Dictionary) -> void:
	var shared: Dictionary = assets.get("shared", {}) if assets.get("shared") is Dictionary else {}
	if mode == "burning":
		_sprite("Foreground", str(shared.get("rubble", "")), Vector2(0, 616))
		_sprite("Pole", str(shared.get("pole_broken", "")), Vector2(0, 636))
	else:
		_sprite("Foreground", str(shared.get("parapet", "")), Vector2(0, 592))
		_sprite("ParapetRim", str(shared.get("parapet_rim", "")), Vector2(0, 592))
		_sprite("Pole", str(shared.get("pole", "")), Vector2(178, 40))


func _build_flag(assets: Dictionary) -> void:
	var flag: Dictionary = assets.get("flag", {}) if assets.get("flag") is Dictionary else {}
	var shared: Dictionary = assets.get("shared", {}) if assets.get("shared") is Dictionary else {}
	var w := float(flag.get("cloth_w", 360.0))
	var h := float(flag.get("cloth_h", 240.0))
	var mesh_node := MeshInstance2D.new()
	mesh_node.name = "FlagCloth"
	mesh_node.mesh = _grid_mesh(w, h, 24, 8)
	mesh_node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var shader_path := "res://assets/shaders/victory/flag_burn.gdshader" if mode == "burning" else "res://assets/shaders/victory/flag_wave.gdshader"
	var shader := load(shader_path) as Shader
	if shader != null:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var flag_tex := _tex(str(flag.get("path", "")))
		mat.set_shader_parameter("flag_tex", flag_tex)
		var mask_path := str(flag.get("mask", ""))
		mat.set_shader_parameter("field_mask", _tex(mask_path) if not mask_path.is_empty() else VictorySceneModel.fallback_texture())
		mat.set_shader_parameter("tint_mix", float(flag.get("tint_mix", 0.0)))
		mat.set_shader_parameter("apply_tint", float(flag.get("apply_tint", 0.0)))
		mat.set_shader_parameter("use_mask", float(flag.get("use_mask", 0.0)))
		mat.set_shader_parameter("nation_colour", flag.get("nation_colour", Color.WHITE))
		mat.set_shader_parameter("time_s", 0.0)
		if mode == "burning":
			mat.set_shader_parameter("noise_tex", _tex(str(shared.get("noise_burn", ""))))
			mat.set_shader_parameter("burn", 0.0)
			mat.set_shader_parameter("seed", 1.7)
		else:
			mat.set_shader_parameter("furled", 1.0 if mode == "eclipsed" else 0.0)
			mat.set_shader_parameter("amp_px", h * 0.085)
		mesh_node.material = mat
		flag_material = mat
	_flag_node = mesh_node
	add_child(mesh_node)


func _build_particles(assets: Dictionary) -> void:
	VictorySceneModel.reclaim_dying_cpu_particles()
	if mode == "eclipsed":
		return
	var fx := Node2D.new()
	fx.name = "FxParticles"
	add_child(fx)
	var shared: Dictionary = assets.get("shared", {}) if assets.get("shared") is Dictionary else {}
	var tier := _tier()
	var half := tier != "gpu"
	var emit := tier == "gpu" or tier == "cpu"
	if mode == "win":
		if not restrained:
			_particles(fx, "BirdParticles", str(shared.get("bird", "")), 8, SEED_BIRD, half, emit, Vector2(640, 180), Vector2(40, 0), 6.0)
		return
	var points: Array = assets.get("fire_points", []) if assets.get("fire_points") is Array else []
	if points.is_empty():
		points = [[640, 581]]
	var n := mini(points.size(), 6)
	for i in n:
		var pt: Variant = points[i]
		var at := Vector2(640, 581)
		if pt is Array and (pt as Array).size() >= 2:
			at = Vector2(float(pt[0]), float(pt[1]))
		var flames := maxi(1, int(round(18.0 / float(n))))
		var embers := maxi(1, int(round(24.0 / float(n))))
		var ash := maxi(1, int(round(20.0 / float(n))))
		var smoke := maxi(1, int(round(24.0 / float(n))))
		_particles(fx, "FlameParticles%d" % i, str(shared.get("flame", "")), flames, SEED_FLAME + i, half, emit, at, Vector2(0, -1), 0.8)
		_particles(fx, "EmberParticles%d" % i, str(shared.get("ember", "")), embers, SEED_EMBER + i, half, emit, at, Vector2(0, -1), 1.4)
		_particles(fx, "AshParticles%d" % i, str(shared.get("ash", "")), ash, SEED_ASH + i, half, emit, at + Vector2(0, -20), Vector2(0, -1), 2.2)
		_particles(fx, "SmokeParticles%d" % i, str(shared.get("smoke", "")), smoke, SEED_SMOKE + i, half, emit, at + Vector2(0, -30), Vector2(0, -1), 3.0)


func _build_copy(built: Dictionary) -> void:
	var eye := _label("SceneEyebrow", str(built.get("eyebrow", "")), Vector2(690, 78), 18, Color(0.86, 0.78, 0.58))
	var head := _label("SceneHeadline", str(built.get("headline", "")).replace(" / ", "\n"), Vector2(690, 112), 46, Color(0.97, 0.93, 0.84))
	head.custom_minimum_size = Vector2(540, 120)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sub := _label("SceneSubline", str(built.get("sub", "")), Vector2(690, 250), 18, Color(0.9, 0.86, 0.78))
	sub.custom_minimum_size = Vector2(540, 72)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var when := _date_line(built)
	var date_l := _label("SceneDate", when, Vector2(690, 336), 16, Color(0.78, 0.74, 0.66))
	_apply_fonts(eye, head, sub, date_l)
	var grid := Control.new()
	grid.name = "RecapGrid"
	grid.position = Vector2(690, 390)
	grid.size = Vector2(540, 120)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grid)
	var rows: Array = built.get("recap_rows", []) if built.get("recap_rows") is Array else []
	for i in mini(rows.size(), 4):
		var row: Dictionary = rows[i] if rows[i] is Dictionary else {}
		var tile := Label.new()
		tile.name = "Recap%d" % i
		tile.text = "%s\n%s" % [str(row.get("label", "")), str(row.get("value", ""))]
		tile.position = Vector2(float(i) * 136.0, 0)
		tile.add_theme_font_size_override("font_size", 14)
		tile.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82))
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(tile)
	var shared: Dictionary = {}
	if built.get("assets") is Dictionary:
		var assets: Dictionary = built.get("assets")
		if assets.get("shared") is Dictionary:
			shared = assets.get("shared")
	var mark := TextureRect.new()
	mark.name = "Wordmark"
	mark.texture = _tex(str(shared.get("wordmark", "res://assets/graphics/branding/epochs_wordmark_512_alpha.png")))
	mark.position = Vector2(36, 700)
	mark.size = Vector2(220, 72)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(mark)


func _build_fade() -> void:
	var fade := ColorRect.new()
	fade.name = "FadeBlack"
	fade.color = Color(0, 0, 0, 1)
	fade.position = Vector2.ZERO
	fade.size = REF
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)


func _label(node_name: String, text: String, pos: Vector2, size_px: int, col: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", col)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _date_line(built: Dictionary) -> String:
	var tag := str(built.get("tag", ""))
	var name := tag
	if typeof(WarStateDomain) != TYPE_NIL:
		name = str(WarStateDomain.tag_name(tag))
	var start := ""
	var today := ""
	var clock := _clock()
	if clock != null:
		start = str(clock.get("scenario_start_date"))
		today = "%04d-%02d-%02d" % [int(clock.get("current_year")), int(clock.get("current_month")), int(clock.get("current_day"))]
	if typeof(CampaignEndDomain) != TYPE_NIL:
		if start.length() >= 10:
			start = CampaignEndDomain.format_end_date(start)
		today = CampaignEndDomain.format_end_date(today)
	return "%s · %s – %s" % [name, start, today]


func _apply_fonts(eye: Label, head: Label, sub: Label, date_l: Label) -> void:
	var display := load("res://assets/fonts/Cinzel-VariableFont_wght.ttf") as Font
	if display != null:
		head.add_theme_font_override("font", display)
	var sans := _axis_font("res://assets/fonts/montserrat/Montserrat[wght].ttf", 560)
	if sans != null:
		eye.add_theme_font_override("font", sans)
		date_l.add_theme_font_override("font", sans)
	var italic := _axis_font("res://assets/fonts/gelasio/Gelasio-Italic[wght].ttf", 400)
	if italic != null:
		sub.add_theme_font_override("font", italic)


func _axis_font(path: String, weight: int) -> Font:
	if not VictorySceneModel.res_exists(path):
		return null
	var base := load(path) as Font
	if base == null:
		return null
	var varied := FontVariation.new()
	varied.base_font = base
	varied.variation_opentype = {0x77676874: weight}
	return varied


func _sprite(node_name: String, path: String, pos: Vector2) -> void:
	if path.is_empty():
		return
	var tex := _tex(path)
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = tex
	rect.position = pos
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if tex != null:
		rect.size = tex.get_size()
	add_child(rect)


func _tex(path: String) -> Texture2D:
	if VictorySceneModel.res_exists(path):
		var loaded: Variant = load(path)
		if loaded is Texture2D:
			return loaded
	return VictorySceneModel.fallback_texture()


func _tier() -> String:
	if OS.get_environment("EOA_VICTORY_SCENE_CPU") == "1":
		return "cpu"
	if DisplayServer.get_name() == "headless":
		return "headless"
	var adapter := ""
	if RenderingServer.has_method("get_video_adapter_name"):
		adapter = str(RenderingServer.get_video_adapter_name()).to_lower()
	for part in OS.get_video_adapter_driver_info():
		adapter += " " + str(part).to_lower()
	if adapter.find("llvmpipe") >= 0 or adapter.find("lavapipe") >= 0 or adapter.find("softpipe") >= 0:
		return "cpu"
	return "gpu"


func _particles(parent: Node, node_name: String, tex_path: String, amount: int, seed_n: int, half: bool, emit: bool, at: Vector2, direction: Vector2, life: float) -> void:
	var count := amount
	if half:
		count = maxi(1, int(ceil(float(amount) / 2.0)))
	var use_cpu := _tier() != "gpu"
	if use_cpu:
		var cpu := VictorySceneModel.acquire_cpu_particle()
		cpu.name = node_name
		cpu.amount = count
		cpu.use_fixed_seed = true
		cpu.one_shot = false
		cpu.seed = seed_n
		cpu.randomness = 0.0
		cpu.lifetime = life
		cpu.explosiveness = 0.0
		cpu.direction = direction
		cpu.spread = 0.0
		cpu.gravity = Vector2(0, -8)
		cpu.initial_velocity_min = 18.0
		cpu.initial_velocity_max = 18.0
		cpu.scale_amount_min = 0.45
		cpu.scale_amount_max = 0.45
		cpu.emitting = emit and DisplayServer.get_name() != "headless"
		cpu.position = at
		cpu.texture = _tex(tex_path)
		parent.add_child(cpu)
		return
	var gpu := GPUParticles2D.new()
	gpu.name = node_name
	gpu.amount = count
	gpu.use_fixed_seed = true
	gpu.seed = seed_n
	gpu.randomness = 0.0
	gpu.lifetime = life
	gpu.explosiveness = 0.0
	gpu.visibility_rect = Rect2(-200, -200, 400, 400)
	gpu.emitting = emit and DisplayServer.get_name() != "headless"
	gpu.position = at
	gpu.texture = _tex(tex_path)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(direction.x, direction.y, 0)
	mat.spread = 0.0
	mat.initial_velocity_min = 18.0
	mat.initial_velocity_max = 18.0
	mat.gravity = Vector3(0, -8, 0)
	mat.scale_min = 0.45
	mat.scale_max = 0.45
	gpu.process_material = mat
	gpu.use_fixed_seed = true
	gpu.seed = seed_n
	parent.add_child(gpu)


func _grid_mesh(w: float, h: float, cols: int, rows: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in rows:
		for x in cols:
			var u := float(x) / float(cols - 1)
			var v := float(y) / float(rows - 1)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(u * w, v * h, 0.0))
	for y in rows - 1:
		for x in cols - 1:
			var i := y * cols + x
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + cols)
			st.add_index(i + 1)
			st.add_index(i + cols + 1)
			st.add_index(i + cols)
	return st.commit()


func _clock() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("TimeManager")
