# scripts/ui/LoadingScreen.gd
# Full-screen loading screen for Epochs of Ascendancy.
# Cycles four concept artworks at 0–24%, 25–49%, 50–74%, 75–100% load progress.
extends CanvasLayer

const LOADING_ART_QUARTERS: Array[Dictionary] = [
	{
		"texture": "res://assets/loading_screens/ascendant_globe.jpg",
		"title": "THE ASCENDANT GLOBE",
		"subtitle": "Stitched world • Pillars of power • Global ascendancy",
	},
	{
		"texture": "res://assets/loading_screens/agents_epoch.jpg",
		"title": "THE AGENT'S EPOCH",
		"subtitle": "Agents of Will • Doctrines • Timeline 1890s–1936",
	},
	{
		"texture": "res://assets/loading_screens/pillars_hidden_hand.jpg",
		"title": "PILLARS OF THE HIDDEN HAND",
		"subtitle": "Mandate • Cohesion • Ascendancy • Intrigue",
	},
	{
		"texture": "res://assets/loading_screens/epochs_unfolding.jpg",
		"title": "EPOCHS UNFOLDING",
		"subtitle": "Map evolution • Tech branches • Rise to power",
	},
]

var _hero_art: TextureRect
var _bottom_scrim: ColorRect
var _fade_root: Control
var title_label: Label
var subtitle_label: Label
var progress_bar: ProgressBar
var tip_label: Label
var tween: Tween
var current_progress: float = 0.0
var _art_index: int = -1
var _max_art_quarter: int = -1
var _ui_built := false
var _hiding := false
var _input_blocker: ColorRect


func _ready() -> void:
	layer = 100
	follow_viewport_enabled = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("loading_screen")
	visible = false


func _ensure_built() -> void:
	if _ui_built:
		return
	_build_fullscreen_ui()
	_ui_built = true


func _build_fullscreen_ui() -> void:
	_input_blocker = ColorRect.new()
	_input_blocker.name = "InputBlocker"
	_input_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_input_blocker.color = Color(0, 0, 0, 0)
	_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_input_blocker)

	_fade_root = Control.new()
	_fade_root.name = "FadeRoot"
	_fade_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade_root)

	# Full-viewport hero artwork (cycles every 25% load).
	_hero_art = TextureRect.new()
	_hero_art.name = "HeroArt"
	_hero_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hero_art.offset_left = 0
	_hero_art.offset_top = 0
	_hero_art.offset_right = 0
	_hero_art.offset_bottom = 0
	_hero_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_hero_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_root.add_child(_hero_art)

	# Dark base so we never flash empty before first texture decodes.
	var base_veil := ColorRect.new()
	base_veil.name = "BaseVeil"
	base_veil.color = Color(0.03, 0.03, 0.05, 1.0)
	base_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_root.add_child(base_veil)
	_fade_root.move_child(base_veil, 0)

	# Bottom scrim for readable text over bright artwork.
	_bottom_scrim = ColorRect.new()
	_bottom_scrim.name = "BottomScrim"
	_bottom_scrim.anchor_left = 0.0
	_bottom_scrim.anchor_top = 0.45
	_bottom_scrim.anchor_right = 1.0
	_bottom_scrim.anchor_bottom = 1.0
	_bottom_scrim.offset_left = 0
	_bottom_scrim.offset_top = 0
	_bottom_scrim.offset_right = 0
	_bottom_scrim.offset_bottom = 0
	_bottom_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_scrim.color = Color(0.02, 0.02, 0.05, 0.88)
	_fade_root.add_child(_bottom_scrim)

	var bottom := MarginContainer.new()
	bottom.name = "BottomUI"
	bottom.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.add_theme_constant_override("margin_left", 48)
	bottom.add_theme_constant_override("margin_right", 48)
	bottom.add_theme_constant_override("margin_bottom", 40)
	bottom.add_theme_constant_override("margin_top", 0)
	_fade_root.add_child(bottom)

	var outer_v := VBoxContainer.new()
	outer_v.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	outer_v.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(outer_v)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_v.add_child(spacer)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	outer_v.add_child(vbox)

	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "EPOCHS OF ASCENDANCY"
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.45))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.name = "SubtitleLabel"
	subtitle_label.text = "Forging the epoch..."
	subtitle_label.add_theme_font_size_override("font_size", 16)
	subtitle_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.9))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle_label)

	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.custom_minimum_size = Vector2(0, 22)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.max_value = 100.0
	vbox.add_child(progress_bar)

	var pct_label := Label.new()
	pct_label.name = "PercentLabel"
	pct_label.text = "0%"
	pct_label.add_theme_font_size_override("font_size", 13)
	pct_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
	pct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pct_label)
	set_meta("pct_label", pct_label)

	tip_label = Label.new()
	tip_label.name = "TipLabel"
	tip_label.text = "Loading..."
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.add_theme_font_size_override("font_size", 13)
	tip_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.82))
	tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tip_label)


func show_loading(_option: String = "cycle", initial_tip: String = "Forging the Epochs of Ascendancy...") -> void:
	_ensure_built()
	_hiding = false
	visible = true
	if _input_blocker:
		_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		_input_blocker.visible = true
	set_process_input(false)
	current_progress = 0.0
	_art_index = -1
	_max_art_quarter = -1
	if _fade_root:
		_fade_root.modulate = Color(1, 1, 1, 1)
	_apply_loading_art_for_progress(0.0)
	if progress_bar:
		progress_bar.value = 0.0
	if tip_label:
		tip_label.text = initial_tip
	var pl := get_meta("pct_label", null) as Label
	if pl:
		pl.text = "0.0%"
	if title_label:
		title_label.modulate.a = 1.0
	print("LoadingScreen: fullscreen cycle mode active (4 artworks @ 25% each).")


func update_progress(progress: float, tip: String = "") -> void:
	if _hiding:
		return
	_ensure_built()
	current_progress = clampf(progress, 0.0, 1.0)
	_apply_loading_art_for_progress(current_progress)
	if progress_bar:
		progress_bar.value = current_progress * 100.0
		progress_bar.queue_redraw()
	if tip_label and tip != "":
		tip_label.text = tip
		tip_label.queue_redraw()
	var pl := get_meta("pct_label", null) as Label
	if pl:
		pl.text = "%.1f%%" % (current_progress * 100.0)
		pl.queue_redraw()


func _apply_loading_art_for_progress(progress: float) -> void:
	var quarter_idx := clampi(int(progress * 4.0), 0, 3)
	if progress >= 0.999:
		quarter_idx = 3
	if quarter_idx <= _max_art_quarter:
		return
	_max_art_quarter = quarter_idx
	_art_index = quarter_idx
	var art: Dictionary = LOADING_ART_QUARTERS[quarter_idx]
	if _hero_art:
		var tex := load(str(art.get("texture", ""))) as Texture2D
		if tex:
			_hero_art.texture = tex
	if title_label:
		title_label.text = str(art.get("title", "EPOCHS OF ASCENDANCY"))
	if subtitle_label:
		subtitle_label.text = str(art.get("subtitle", ""))
	print("LoadingScreen: art quarter %d/4 (%.0f%% band) — %s" % [quarter_idx + 1, float(quarter_idx) * 25.0, art.get("title", "")])


func hide_and_free() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	# Always run full teardown (idempotent). Do NOT early-return when _hiding — update_progress used to set
	# _hiding before a timer fired, which made hide_and_free a no-op and left the 100% overlay stuck forever.
	_hiding = true
	if has_meta("ls_auto_hide_scheduled"):
		remove_meta("ls_auto_hide_scheduled")
	print("LoadingScreen: HIDE_AND_FREE — dismissing now.")
	set_process_input(false)
	set_process(false)
	if _input_blocker:
		_input_blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_input_blocker.visible = false
	if tween:
		tween.kill()
		tween = null
	_ensure_built()
	if _fade_root:
		_fade_root.modulate = Color(1, 1, 1, 0)
		_fade_root.visible = false
	visible = false
	layer = -128
	if is_inside_tree():
		queue_free()
