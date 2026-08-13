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
	label.add_theme_font_size_override("font_size", 14)


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
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
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
