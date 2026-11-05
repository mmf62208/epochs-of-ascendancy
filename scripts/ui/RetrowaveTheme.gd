# scripts/ui/RetrowaveTheme.gd
class_name RetrowaveTheme
extends RefCounted

const BG_DARK := Color("#1a1a2e")
const BG_DEEP := Color("#0f0f1e")
const BG_PANEL := Color("#16213e")
const CYAN := Color("#33e6ff")
const MAGENTA := Color("#ff33cc")
const TEXT_PRIMARY := Color("#eef2ff")
const TEXT_DIM := Color("#9aa8c7")
const WARNING := Color("#ff6666")
const SUCCESS := Color("#55ff99")
const TOOLTIP_MAX_WIDTH := 320
const TOOLTIP_FONT_SIZE := 14
const TOOLTIP_TITLE_FONT_SIZE := 15
const TOOLTIP_TITLE_PREFIX := "# "
const TOOLTIP_HOTKEY_SEP := " · "
const TOOLTIP_EDGE_MARGIN := 4.0
## Camera motion above this (px²) means the world under a still cursor changed.
const TOOLTIP_PAN_CLEAR_PX2 := 0.25
const TOOLTIP_RULE_COLOR := Color("#2a3a5c")
## One process_frame callback per open tip. Keyed by popup instance id.
static var _tooltip_pan_poll_cbs: Dictionary = {}


static func style_top_info_bar(bar: Control) -> void:
	var bg := bar.get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = BG_DEEP


static func style_info_bar_label(label: Label, accent: Color = TEXT_PRIMARY) -> void:
	label.add_theme_color_override("font_color", accent)
	label.add_theme_font_size_override("font_size", 14)


static func style_nav_button(button: Button) -> void:
	style_secondary_button(button)
	button.add_theme_font_size_override("font_size", 13)


static func style_speed_button(button: Button, active: bool = false) -> void:
	if active:
		style_primary_button(button)
	else:
		style_secondary_button(button)


static func style_production_screen(screen: Control) -> void:
	var bg := screen.get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = BG_DEEP


static func style_summary_metric(label: Label, accent: Color = TEXT_PRIMARY) -> void:
	label.add_theme_color_override("font_color", accent)
	label.add_theme_font_size_override("font_size", 17)


static func style_column_header(label: Label) -> void:
	label.add_theme_color_override("font_color", CYAN)
	label.add_theme_font_size_override("font_size", 13)
	# Labels ignore stylebox content margins, so the 4 px top pad is extra height
	# with the glyphs sitting on the bottom of that rect.
	var line := 18.0
	var font := ThemeDB.fallback_font
	if font != null:
		line = float(font.get_height(13))
	var ms := label.custom_minimum_size
	label.custom_minimum_size = Vector2(ms.x, maxf(ms.y, line + 4.0))
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


static func style_row_label(label: Label) -> void:
	label.add_theme_color_override("font_color", TEXT_PRIMARY)
	label.add_theme_font_size_override("font_size", 14)


static func style_detail_panel(panel: PanelContainer) -> void:
	# Prefer generated 9-slice retrowave frame when present.
	var framed := _panel_texture_style()
	if framed != null:
		panel.add_theme_stylebox_override("panel", framed)
	else:
		panel.add_theme_stylebox_override("panel", _panel_style())


static func style_detail_panel_flat(panel: PanelContainer) -> void:
	## Clean inset panel without ornamented corner chrome (avoids L/R clip on scroll/lists).
	if panel == null:
		return
	var style := _panel_style()
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)


static func style_world_panel(control: Control) -> void:
	## Style any Panel / PanelContainer with the world-class framed chrome.
	if control == null:
		return
	var framed_tex := _panel_texture_style()
	var box: StyleBox = framed_tex if framed_tex != null else _panel_style()
	if control is PanelContainer or control is Panel:
		control.add_theme_stylebox_override("panel", box)


static func style_info_panel_flat(control: Control) -> void:
	## Province/region inspector: light cyan outline, no magenta corner ornaments.
	if control == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = BG_DEEP
	var border := CYAN
	border.a = 0.85
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.shadow_size = 8
	style.shadow_offset = Vector2(4, 4)
	style.shadow_color = Color(0, 0, 0, 0.35)
	# Zero style content margins — Panel children use explicit layout pads (avoids double-inset mismatch).
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	if control is PanelContainer or control is Panel:
		control.add_theme_stylebox_override("panel", style)
	else:
		control.add_theme_stylebox_override("panel", style)


static func style_menu_panel(control: Control) -> void:
	## Slightly richer chrome for Main Menu / command center surfaces.
	if control == null:
		return
	var tex := _load_tex("res://assets/graphics/ui/menu_panel_frame_512.png")
	if tex == null:
		style_world_panel(control)
		return
	var style := StyleBoxTexture.new()
	style.texture = tex
	style.texture_margin_left = 48
	style.texture_margin_right = 48
	style.texture_margin_top = 48
	style.texture_margin_bottom = 48
	style.content_margin_left = 40
	style.content_margin_right = 40
	style.content_margin_top = 44
	style.content_margin_bottom = 40
	if control is PanelContainer or control is Panel:
		control.add_theme_stylebox_override("panel", style)
	else:
		# Generic Control fallback (PanelContainer is the usual target).
		style_world_panel(control)


static func style_progress_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	var bg_tex := _load_tex("res://assets/graphics/ui/progress_bar_frame.png")
	var fill_tex := _load_tex("res://assets/graphics/ui/progress_bar_fill.png")
	if bg_tex != null:
		var bg := StyleBoxTexture.new()
		bg.texture = bg_tex
		bg.texture_margin_left = 24
		bg.texture_margin_right = 24
		bg.texture_margin_top = 12
		bg.texture_margin_bottom = 12
		bg.content_margin_left = 4
		bg.content_margin_right = 4
		bg.content_margin_top = 2
		bg.content_margin_bottom = 2
		bar.add_theme_stylebox_override("background", bg)
	if fill_tex != null:
		var fill := StyleBoxTexture.new()
		fill.texture = fill_tex
		fill.texture_margin_left = 8
		fill.texture_margin_right = 8
		fill.texture_margin_top = 4
		fill.texture_margin_bottom = 4
		bar.add_theme_stylebox_override("fill", fill)
	else:
		var fill_flat := StyleBoxFlat.new()
		fill_flat.bg_color = CYAN
		fill_flat.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill_flat)


static func style_detail_label(label: Label) -> void:
	label.add_theme_color_override("font_color", TEXT_DIM)
	label.add_theme_font_size_override("font_size", 14)


static func style_filter_option(option: OptionButton) -> void:
	option.add_theme_stylebox_override("normal", _input_style(BG_PANEL, CYAN, 1))
	option.add_theme_color_override("font_color", TEXT_PRIMARY)


static func style_popup_root(popup: Window) -> void:
	if popup == null:
		return

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.12)
	panel_style.border_color = CYAN
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	popup.add_theme_stylebox_override("panel", panel_style)

	var bg := popup.get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.color = BG_DARK


static func style_title(label: Label, accent: Color = CYAN) -> void:
	label.add_theme_color_override("font_color", accent)
	label.add_theme_font_size_override("font_size", 20)


static func style_body_label(label: Label) -> void:
	label.add_theme_color_override("font_color", TEXT_DIM)
	label.add_theme_font_size_override("font_size", 14)


static func style_rich_text(label: RichTextLabel) -> void:
	label.add_theme_color_override("default_color", TEXT_PRIMARY)
	label.add_theme_font_size_override("normal_font_size", 15)


static func style_search(line_edit: LineEdit) -> void:
	line_edit.add_theme_stylebox_override("normal", _input_style(BG_PANEL, CYAN, 1))
	line_edit.add_theme_stylebox_override("focus", _input_style(BG_PANEL, MAGENTA, 2))
	line_edit.add_theme_color_override("font_color", TEXT_PRIMARY)
	line_edit.add_theme_color_override("font_placeholder_color", TEXT_DIM)
	line_edit.placeholder_text = "Search designs..."


static func style_item_list(item_list: ItemList) -> void:
	item_list.add_theme_stylebox_override("panel", _panel_style())
	item_list.add_theme_color_override("font_color", TEXT_PRIMARY)
	item_list.add_theme_color_override("font_selected_color", BG_DARK)
	item_list.add_theme_stylebox_override("selected", _selected_style())


static func style_primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style(BG_PANEL, CYAN))
	button.add_theme_stylebox_override("hover", _button_style(Color("#1f2a44"), MAGENTA))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#0f1528"), CYAN))
	button.add_theme_color_override("font_color", CYAN)
	button.add_theme_font_size_override("font_size", 15)


static func style_secondary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style(BG_DARK, TEXT_DIM))
	button.add_theme_stylebox_override("hover", _button_style(BG_PANEL, CYAN))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#0f1528"), TEXT_DIM))
	button.add_theme_color_override("font_color", TEXT_DIM)
	button.add_theme_font_size_override("font_size", 15)


static func style_danger_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_style(Color("#2a1520"), WARNING))
	button.add_theme_stylebox_override("hover", _button_style(Color("#3a1a28"), MAGENTA))
	button.add_theme_stylebox_override("pressed", _button_style(Color("#1a0f14"), WARNING))
	button.add_theme_color_override("font_color", WARNING)
	button.add_theme_font_size_override("font_size", 15)


static func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _panel_texture_style() -> StyleBoxTexture:
	var tex := _load_tex("res://assets/graphics/ui/panel_frame_512.png")
	if tex == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = tex
	# Corner ornaments live in ~48px; edges uniform for 9-slice.
	style.texture_margin_left = 48
	style.texture_margin_right = 48
	style.texture_margin_top = 48
	style.texture_margin_bottom = 48
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


static func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG_PANEL
	var border_color := CYAN
	border_color.a = 0.35
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


static func _selected_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CYAN
	style.set_corner_radius_all(3)
	return style


static func _input_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


## Theme for the engine TooltipPanel / TooltipLabel. Merged once into the
## default theme so every tooltip_text picks it up. Not assigned as
## gui/theme/custom — that replaces the engine theme and strips button styles.
static func style_tooltip() -> Theme:
	return make_tooltip_theme()


static func make_tooltip_theme() -> Theme:
	var theme := Theme.new()
	var panel := StyleBoxFlat.new()
	var bg := BG_PANEL
	bg.a = 0.96
	panel.bg_color = bg
	var border := CYAN
	border.a = 0.85
	panel.border_color = border
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(4)
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 4
	panel.shadow_offset = Vector2(2, 2)
	theme.set_stylebox("panel", "TooltipPanel", panel)
	theme.set_color("font_color", "TooltipLabel", TEXT_PRIMARY)
	theme.set_font_size("font_size", "TooltipLabel", TOOLTIP_FONT_SIZE)
	theme.set_constant("max_width", "TooltipLabel", TOOLTIP_MAX_WIDTH)
	return theme


static func install_tooltip_theme(tree: SceneTree = null) -> void:
	var base := ThemeDB.get_default_theme()
	if base != null and not bool(base.get_meta("eoa_tooltip_theme", false)):
		base.merge_with(make_tooltip_theme())
		base.set_meta("eoa_tooltip_theme", true)
	if tree == null or tree.root == null:
		return
	if bool(tree.root.get_meta("eoa_tooltip_dress", false)):
		return
	tree.root.set_meta("eoa_tooltip_dress", true)
	# Headless perf/seed runs must not pay a callback per node.
	if DisplayServer.get_name() == "headless":
		return
	if not tree.node_added.is_connected(_on_tooltip_node_added):
		tree.node_added.connect(_on_tooltip_node_added)


static func _on_tooltip_node_added(node: Node) -> void:
	if node == null or not (node is PopupPanel):
		return
	var pop := node as PopupPanel
	if str(pop.theme_type_variation) != "TooltipPanel":
		return
	if bool(pop.get_meta("eoa_tooltip_dress_queued", false)):
		return
	pop.set_meta("eoa_tooltip_dress_queued", true)
	# Defer: Node is still propagating enter_tree, so adding children here
	# would enter them twice. The engine sizes the popup after add_child
	# returns; _deferred_dress_tooltip refits before the first draw.
	_deferred_dress_tooltip.call_deferred(pop)


static func _deferred_dress_tooltip(node: Node) -> void:
	if not is_instance_valid(node):
		return
	dress_tooltip_popup(node)
	if not (node is PopupPanel):
		return
	var pop := node as PopupPanel
	_connect_tooltip_placement(pop)
	if pop.visible:
		pop.reset_size()
		place_tooltip_popup(pop)
	_arm_tooltip_pan_clear(pop)


## Wrap the engine tooltip label at 320px. A leading "# " line becomes the
## title. A trailing hotkey line splits on " · " into right-aligned chips.
## Does not free the engine Label.
static func dress_tooltip_popup(node: Node) -> void:
	if node == null or not (node is PopupPanel):
		return
	var pop := node as PopupPanel
	if str(pop.theme_type_variation) != "TooltipPanel":
		return
	if bool(pop.get_meta("eoa_tooltip_dressed", false)):
		return
	var label: Label = null
	for c in pop.get_children():
		if c is Label:
			label = c as Label
			break
	if label == null:
		return
	pop.set_meta("eoa_tooltip_dressed", true)
	var raw := label.text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.add_theme_font_size_override("font_size", TOOLTIP_FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_PRIMARY)
	var box := VBoxContainer.new()
	box.name = "EoaTooltipBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	pop.add_child(box)
	label.reparent(box)
	_apply_tooltip_content(box, label, raw)


## PopupPanel is a Window, so pop.get_viewport() is the popup itself. Its mouse
## and visible rect sit at the popup origin, which Play saw as the top-left.
## The cursor and the game window live on the parent viewport.
static func _host_viewport(pop: Node) -> Viewport:
	if pop == null:
		return null
	var parent := pop.get_parent()
	while parent != null:
		if parent is Viewport and parent != pop:
			return parent as Viewport
		parent = parent.get_parent()
	var tree := pop.get_tree()
	if tree != null and tree.root != null and tree.root != pop:
		return tree.root
	return null


## Zero anchor means "unset". A known cursor wins over the engine popup
## position, including when the cursor is the top-left pixel.
static func resolve_tooltip_anchor(
	anchor: Rect2,
	cursor: Vector2,
	popup_position: Vector2,
	cursor_known: bool
) -> Rect2:
	if anchor.size != Vector2.ZERO or anchor.position != Vector2.ZERO:
		return anchor
	if cursor_known:
		return Rect2(cursor, Vector2(1, 1))
	return Rect2(popup_position, Vector2(1, 1))


static func tooltip_should_clear_for_pan(from_pose: Vector2, to_pose: Vector2) -> bool:
	return from_pose.distance_squared_to(to_pose) > TOOLTIP_PAN_CLEAR_PX2


static func _tooltip_max_width() -> int:
	var max_w := TOOLTIP_MAX_WIDTH
	var base := ThemeDB.get_default_theme()
	if base != null:
		var themed := int(base.get_constant("max_width", "TooltipLabel"))
		if themed > 0:
			max_w = themed
	return max_w


static func _hotkey_chip_texts(line: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for part in line.split(TOOLTIP_HOTKEY_SEP):
		var s := str(part).strip_edges()
		if not s.is_empty():
			out.append(s)
	return out


static func _hotkey_chip_is_danger(text: String) -> bool:
	return text.contains("Ctrl+Click") or text.contains("Del")


static func _tooltip_chip_font() -> Font:
	var theme := ThemeDB.get_default_theme()
	if theme != null and theme.has_font("font", "CodeEdit"):
		var mono := theme.get_font("font", "CodeEdit")
		if mono != null:
			return mono
	return ThemeDB.fallback_font


static func _apply_tooltip_content(box: Node, label: Label, raw: String) -> void:
	if box == null or label == null:
		return
	_clear_tooltip_chrome(box)
	var lines: PackedStringArray = raw.split("\n")
	var hotkeys := PackedStringArray()
	if lines.size() >= 2 and _hotkey_line(str(lines[lines.size() - 1])):
		hotkeys = _hotkey_chip_texts(str(lines[lines.size() - 1]))
		lines.remove_at(lines.size() - 1)
		while lines.size() > 0 and str(lines[lines.size() - 1]).strip_edges().is_empty():
			lines.remove_at(lines.size() - 1)
	var title := ""
	if lines.size() > 0:
		var first := str(lines[0]).strip_edges()
		if first.begins_with(TOOLTIP_TITLE_PREFIX):
			title = first.substr(TOOLTIP_TITLE_PREFIX.length()).strip_edges()
			lines.remove_at(0)
			while lines.size() > 0 and str(lines[0]).strip_edges().is_empty():
				lines.remove_at(0)
	var body_lines := lines
	var max_w := _tooltip_max_width()
	label.text = "\n".join(body_lines)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = false
	# y < 0 means no max height (0 would crush the label).
	label.custom_maximum_size = Vector2(float(max_w), -1)
	var wrap_size := _tooltip_body_size(label, body_lines, max_w)
	if not title.is_empty():
		var title_font := ThemeDB.fallback_font
		if title_font != null:
			var title_w := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, TOOLTIP_TITLE_FONT_SIZE).x
			wrap_size.x = minf(maxf(wrap_size.x, title_w), float(max_w))
	label.custom_minimum_size = wrap_size
	if box is Control:
		(box as Control).custom_minimum_size = Vector2(wrap_size.x, 0)
	var insert_at := 0
	if not title.is_empty():
		var title_lab := Label.new()
		title_lab.name = "EoaTooltipTitle"
		title_lab.text = title
		title_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_lab.clip_text = false
		title_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title_lab.custom_maximum_size = Vector2(float(max_w), -1)
		title_lab.add_theme_font_size_override("font_size", TOOLTIP_TITLE_FONT_SIZE)
		title_lab.add_theme_color_override("font_color", CYAN)
		var bold := FontVariation.new()
		bold.base_font = ThemeDB.fallback_font
		bold.variation_embolden = 0.85
		title_lab.add_theme_font_override("font", bold)
		box.add_child(title_lab)
		box.move_child(title_lab, insert_at)
		insert_at += 1
		var rule := HSeparator.new()
		rule.name = "EoaTooltipRule"
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var line := StyleBoxLine.new()
		line.color = TOOLTIP_RULE_COLOR
		line.thickness = 1
		rule.add_theme_stylebox_override("separator", line)
		rule.custom_minimum_size = Vector2(0, 1)
		box.add_child(rule)
		box.move_child(rule, insert_at)
	if hotkeys.is_empty():
		return
	var row := HBoxContainer.new()
	row.name = "EoaHotkeyRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var chip_font := _tooltip_chip_font()
	for chip_text in hotkeys:
		# Duplicate sibling names are uniquified. Readable form keeps the
		# HotkeyChip hook (HotkeyChip, HotkeyChip2, …) instead of @Class@id.
		row.add_child(_make_hotkey_chip(chip_text, chip_font), true)


static func _clear_tooltip_chrome(box: Node) -> void:
	var drop: Array[Node] = []
	for c in box.get_children():
		var n := str(c.name)
		if n == "EoaTooltipTitle" or n == "EoaTooltipRule" or n == "EoaHotkeyRow":
			drop.append(c)
	for c in drop:
		box.remove_child(c)
		c.free()


static func _make_hotkey_chip(chip_text: String, chip_font: Font) -> PanelContainer:
	var danger := _hotkey_chip_is_danger(chip_text)
	var chip_bg := StyleBoxFlat.new()
	var cbg := BG_PANEL
	cbg.a = 0.96
	chip_bg.bg_color = cbg
	var cb := MAGENTA if danger else CYAN
	if not danger:
		cb.a = 0.6
	chip_bg.border_color = cb
	chip_bg.set_border_width_all(1)
	chip_bg.set_corner_radius_all(3)
	chip_bg.content_margin_left = 6
	chip_bg.content_margin_right = 6
	chip_bg.content_margin_top = 1
	chip_bg.content_margin_bottom = 1
	var chip_panel := PanelContainer.new()
	chip_panel.name = "HotkeyChip"
	chip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip_panel.add_theme_stylebox_override("panel", chip_bg)
	var chip := Label.new()
	chip.text = chip_text
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.clip_text = false
	if chip_font != null:
		chip.add_theme_font_override("font", chip_font)
	chip.add_theme_font_size_override("font_size", 12)
	chip.add_theme_color_override("font_color", MAGENTA if danger else CYAN)
	chip_panel.add_child(chip)
	return chip_panel


## Body size for the engine tooltip label. Width is the longest line, capped
## at max_w. Height is the wrapped block so the popup cannot clip it.
static func _tooltip_body_size(label: Label, lines: PackedStringArray, max_w: int) -> Vector2:
	var font := label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var widest := 48.0
	for line in lines:
		var s := str(line)
		if s.is_empty():
			continue
		widest = maxf(widest, font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, TOOLTIP_FONT_SIZE).x)
	var wrap_w := minf(widest, float(max_w))
	var block := font.get_multiline_string_size("\n".join(lines), HORIZONTAL_ALIGNMENT_LEFT, wrap_w, TOOLTIP_FONT_SIZE)
	return Vector2(wrap_w, maxf(block.y, float(TOOLTIP_FONT_SIZE)))


static func _hotkey_line(line: String) -> bool:
	var s := line.strip_edges()
	if s.is_empty() or not s.begins_with("["):
		return false
	if not s.contains("]"):
		return false
	if s.ends_with("."):
		return false
	return true


## Keep a tooltip fully inside the viewport. Prefer below-left of the anchor;
## flip above / to the left when that side would clip, then clamp leftovers.
static func clamp_tooltip_rect(
	tip_size: Vector2,
	viewport: Rect2,
	anchor: Rect2,
	margin: float = TOOLTIP_EDGE_MARGIN
) -> Rect2:
	var m := maxf(margin, 0.0)
	var vp := Rect2(
		viewport.position + Vector2(m, m),
		Vector2(maxf(viewport.size.x - m * 2.0, 1.0), maxf(viewport.size.y - m * 2.0, 1.0))
	)
	var w := minf(maxf(tip_size.x, 1.0), vp.size.x)
	var h := minf(maxf(tip_size.y, 1.0), vp.size.y)
	var gap := 4.0
	var x := anchor.position.x
	var y := anchor.position.y + maxf(anchor.size.y, 1.0) + gap
	if y + h > vp.position.y + vp.size.y:
		y = anchor.position.y - h - gap
	if y < vp.position.y:
		var room_below: float = (vp.position.y + vp.size.y) - (anchor.position.y + maxf(anchor.size.y, 0.0))
		var room_above: float = anchor.position.y - vp.position.y
		if room_below >= room_above:
			y = anchor.position.y + maxf(anchor.size.y, 0.0) + gap
		y = clampf(y, vp.position.y, vp.position.y + vp.size.y - h)
	if x + w > vp.position.x + vp.size.x:
		x = anchor.position.x + maxf(anchor.size.x, 0.0) - w
	if x < vp.position.x:
		x = vp.position.x
	if x + w > vp.position.x + vp.size.x:
		x = vp.position.x + vp.size.x - w
	return Rect2(Vector2(x, y), Vector2(w, h))


static func place_tooltip_popup(
	pop: PopupPanel,
	viewport_rect: Rect2 = Rect2(),
	anchor: Rect2 = Rect2()
) -> Rect2:
	if pop == null or not is_instance_valid(pop):
		return Rect2()
	pop.reset_size()
	var sz := Vector2(pop.size)
	if sz.x < 8.0 or sz.y < 8.0:
		sz = pop.get_contents_minimum_size()
	if sz.x < 8.0:
		sz.x = 48.0
	if sz.y < 8.0:
		sz.y = 24.0
	var host := _host_viewport(pop)
	var vp := viewport_rect
	if vp.size.x < 1.0 or vp.size.y < 1.0:
		if host != null:
			vp = host.get_visible_rect()
		if vp.size.x < 1.0 or vp.size.y < 1.0:
			vp = Rect2(0.0, 0.0, 1280.0, 800.0)
	var cursor := Vector2.ZERO
	# Headless has no cursor. Live play uses the host mouse even at (0, 0)
	# so a top-bar tip does not fall back to the engine's top-left position.
	var cursor_known := host != null and DisplayServer.get_name() != "headless"
	if cursor_known:
		cursor = host.get_mouse_position()
	var anc := resolve_tooltip_anchor(anchor, cursor, Vector2(pop.position), cursor_known)
	var placed := clamp_tooltip_rect(sz, vp, anc)
	pop.position = Vector2i(int(round(placed.position.x)), int(round(placed.position.y)))
	if placed.size.x + 0.5 < sz.x or placed.size.y + 0.5 < sz.y:
		pop.size = Vector2i(int(ceil(placed.size.x)), int(ceil(placed.size.y)))
	return placed


static func _connect_tooltip_placement(pop: PopupPanel) -> void:
	if pop == null or bool(pop.get_meta("eoa_tooltip_place_hook", false)):
		return
	pop.set_meta("eoa_tooltip_place_hook", true)
	if not pop.visibility_changed.is_connected(_on_tooltip_place_needed):
		pop.visibility_changed.connect(_on_tooltip_place_needed.bind(pop))
	if pop.has_signal("size_changed") and not pop.size_changed.is_connected(_on_tooltip_place_needed):
		pop.size_changed.connect(_on_tooltip_place_needed.bind(pop))


static func _on_tooltip_place_needed(pop: PopupPanel) -> void:
	if pop == null or not is_instance_valid(pop) or not pop.visible:
		return
	if bool(pop.get_meta("eoa_tooltip_placing", false)):
		return
	pop.set_meta("eoa_tooltip_placing", true)
	place_tooltip_popup(pop)
	pop.set_meta("eoa_tooltip_placing", false)
	_arm_tooltip_pan_clear(pop)


static func find_visible_tooltip_popup(from: Node) -> PopupPanel:
	if from == null:
		return null
	if from is PopupPanel:
		var pop := from as PopupPanel
		if pop.visible and str(pop.theme_type_variation) == "TooltipPanel":
			return pop
	for c in from.get_children():
		var found := find_visible_tooltip_popup(c)
		if found != null:
			return found
	return null


static func tooltip_body_label(pop: PopupPanel) -> Label:
	if pop == null:
		return null
	var box: Node = pop.find_child("EoaTooltipBox", true, false)
	if box != null:
		for c in box.get_children():
			if c is Label and str(c.name) != "EoaTooltipTitle":
				return c as Label
	for c in pop.get_children():
		if c is Label:
			return c as Label
	return null


## Cheap in-place refresh while a tooltip is already up (date / speed).
static func refresh_open_tooltip_text(tree: SceneTree, text: String) -> void:
	if tree == null or tree.root == null:
		return
	var pop := find_visible_tooltip_popup(tree.root)
	if pop == null:
		var vp: Viewport = tree.root.get_viewport()
		if vp != null:
			pop = find_visible_tooltip_popup(vp)
	if pop == null:
		return
	var label := tooltip_body_label(pop)
	if label == null:
		return
	var box: Node = pop.find_child("EoaTooltipBox", true, false)
	if box != null:
		_apply_tooltip_content(box, label, text)
	else:
		label.text = text
	pop.reset_size()
	place_tooltip_popup(pop)


## Pan-clear while a tip is open. One SceneTree.process_frame connection,
## so a visible tip costs at most one check per frame. Stop when the tip is
## gone, hidden, or the viewport has no camera. An idle self-requeue grows
## the message queue without a bound and live-crashes (SIGSEGV).
static func _arm_tooltip_pan_clear(pop: PopupPanel) -> void:
	if pop == null or not is_instance_valid(pop):
		return
	if DisplayServer.get_name() == "headless":
		return
	_start_tooltip_pan_poll(pop)


## Headless skips _arm_tooltip_pan_clear. Tests call this directly so the
## same one-callback poll runs under a headless DisplayServer.
static func _start_tooltip_pan_poll(pop: PopupPanel) -> void:
	if pop == null or not is_instance_valid(pop):
		return
	if not pop.visible:
		return
	if bool(pop.get_meta("eoa_tooltip_pan_poll", false)):
		return
	var tree := pop.get_tree()
	if tree == null:
		return
	pop.set_meta("eoa_tooltip_pan_poll", true)
	pop.set_meta("eoa_tooltip_pan_poll_ticks", 0)
	if pop.has_meta("eoa_tooltip_cam_pose"):
		pop.remove_meta("eoa_tooltip_cam_pose")
	var cb := _poll_tooltip_pan.bind(pop)
	_tooltip_pan_poll_cbs[pop.get_instance_id()] = cb
	if not tree.process_frame.is_connected(cb):
		tree.process_frame.connect(cb)
	var exit_cb := _on_tooltip_pan_poll_exiting.bind(pop)
	if not pop.tree_exiting.is_connected(exit_cb):
		pop.tree_exiting.connect(exit_cb, CONNECT_ONE_SHOT)


static func _on_tooltip_pan_poll_exiting(pop: PopupPanel) -> void:
	_stop_tooltip_pan_poll(pop)


static func _stop_tooltip_pan_poll(pop: PopupPanel) -> void:
	if pop == null or not is_instance_valid(pop):
		return
	var id := pop.get_instance_id()
	var cb: Callable = _tooltip_pan_poll_cbs.get(id, Callable())
	var tree := pop.get_tree()
	if tree != null and cb.is_valid() and tree.process_frame.is_connected(cb):
		tree.process_frame.disconnect(cb)
	_tooltip_pan_poll_cbs.erase(id)
	pop.set_meta("eoa_tooltip_pan_poll", false)
	if pop.has_meta("eoa_tooltip_pan_poll_cb"):
		pop.remove_meta("eoa_tooltip_pan_poll_cb")


static func tooltip_pan_poll_active(pop: PopupPanel) -> bool:
	if pop == null or not is_instance_valid(pop):
		return false
	if not bool(pop.get_meta("eoa_tooltip_pan_poll", false)):
		return false
	var cb: Callable = _tooltip_pan_poll_cbs.get(pop.get_instance_id(), Callable())
	var tree := pop.get_tree()
	return tree != null and cb.is_valid() and tree.process_frame.is_connected(cb)


static func tooltip_pan_poll_tracked(instance_id: int) -> bool:
	return _tooltip_pan_poll_cbs.has(instance_id)


static func _poll_tooltip_pan(pop: PopupPanel) -> void:
	if pop == null or not is_instance_valid(pop):
		return
	var ticks := int(pop.get_meta("eoa_tooltip_pan_poll_ticks", 0)) + 1
	pop.set_meta("eoa_tooltip_pan_poll_ticks", ticks)
	if not pop.visible:
		_stop_tooltip_pan_poll(pop)
		return
	var host := _host_viewport(pop)
	var cam: Camera2D = host.get_camera_2d() if host != null else null
	# No camera: stop. Do not keep polling until one appears.
	if cam == null:
		_stop_tooltip_pan_poll(pop)
		return
	var now := cam.global_position
	if pop.has_meta("eoa_tooltip_cam_pose"):
		var prev: Vector2 = pop.get_meta("eoa_tooltip_cam_pose")
		if tooltip_should_clear_for_pan(prev, now):
			pop.hide()
			_stop_tooltip_pan_poll(pop)
			return
	pop.set_meta("eoa_tooltip_cam_pose", now)
