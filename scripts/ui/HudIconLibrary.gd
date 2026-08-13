# scripts/ui/HudIconLibrary.gd
## Retrowave HUD / map-mode / resource icons (generated 2026-07 via game-asset skills).
class_name HudIconLibrary
extends RefCounted

const HUD_DIR := "res://assets/graphics/icons/hud/"
const MODE_DIR := "res://assets/graphics/icons/map_modes/"
const RES_DIR := "res://assets/graphics/icons/resources/"

const NAV_KEYS := {
	"production": "production",
	"leaders": "leaders",
	"technology": "technology",
	"diplomacy": "diplomacy",
	"agents": "agents",
	"trade": "trade",
	"space": "space",
	"map": "map",
	"pause": "pause",
	"play": "play",
	"speed1": "speed1",
	"speed2": "speed2",
	"speed3": "speed3",
	"speed4": "speed4",
}

const MODE_KEYS := {
	"political": "political",
	"strain": "strain",
	"vitality": "vitality",
	"development": "development",
	"supply": "supply",
	"munitions": "munitions",  # Pass 23: dedicated munitions mapmode icon
	"loyalty": "loyalty",
	"infra": "infra",
	"naval": "naval",
	"weather": "weather",
	"resources": "resources",  # dedicated multi-goods mapmode icon (not fuel alias)
	"states": "states",
	"terrain": "terrain",
	"fronts": "fronts",
	"war_loop": "war_loop",
	"warloop": "war_loop",
}

const RES_KEYS := {
	"steel": "steel",
	"aluminum": "aluminum",
	"fuel": "fuel",
	"rubber": "rubber",
	"coal": "coal",
	"chromium": "chromium",
	"tungsten": "tungsten",
	"oil": "fuel",
}


static func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res as Texture2D


static func hud_icon(key: String, px: int = 32) -> Texture2D:
	var k := key.strip_edges().to_lower()
	var stem := str(NAV_KEYS.get(k, k))
	var path := "%s%s_%d.png" % [HUD_DIR, stem, px]
	var tex := _load_tex(path)
	if tex == null and px != 64:
		tex = _load_tex("%s%s_64.png" % [HUD_DIR, stem])
	return tex


static func map_mode_icon(mode: String, px: int = 32) -> Texture2D:
	var m := mode.strip_edges().to_lower()
	var stem := str(MODE_KEYS.get(m, m))
	var path := "%s%s_%d.png" % [MODE_DIR, stem, px]
	var tex := _load_tex(path)
	if tex == null and px != 64:
		tex = _load_tex("%s%s_64.png" % [MODE_DIR, stem])
	# Soft fallback: resources → fuel resource glyph if dedicated mapmode missing
	if tex == null and stem == "resources":
		tex = resource_icon("fuel", px if px in [24, 64] else 64)
	return tex


static func resource_icon(resource_id: String, px: int = 24) -> Texture2D:
	var r := resource_id.strip_edges().to_lower()
	if r in ["oil", "energy", "petroleum"]:
		r = "fuel"
	var stem := str(RES_KEYS.get(r, r))
	var path := "%s%s_%d.png" % [RES_DIR, stem, px]
	var tex := _load_tex(path)
	if tex == null and px != 64:
		tex = _load_tex("%s%s_64.png" % [RES_DIR, stem])
	return tex


static func hud_icon_state(key: String, state: String = "normal", px: int = 32) -> Texture2D:
	## state: normal | hover | pressed
	var k := key.strip_edges().to_lower()
	var stem := str(NAV_KEYS.get(k, k))
	var st := state.strip_edges().to_lower()
	if st == "normal" or st.is_empty():
		return hud_icon(k, px)
	var path := "%s%s_%s_%d.png" % [HUD_DIR, stem, st, px]
	var tex := _load_tex(path)
	if tex == null and px != 64:
		tex = _load_tex("%s%s_%s_64.png" % [HUD_DIR, stem, st])
	if tex == null:
		return hud_icon(k, px)
	return tex


static func apply_button_icon(btn: Button, tex: Texture2D, keep_text: bool = true) -> void:
	if btn == null or tex == null:
		return
	btn.icon = tex
	btn.expand_icon = true
	# Keep short labels for accessibility; icon leads.
	if not keep_text:
		btn.text = ""
	# Match retrowave bar heights
	if btn.custom_minimum_size.y < 24.0:
		btn.custom_minimum_size.y = 26.0


static func wire_icon_hover_states(btn: Button, key: String, px: int = 32) -> void:
	## Swap icon texture on mouse enter/exit/press for world-class feedback.
	if btn == null:
		return
	var normal := hud_icon(key, px)
	var hover := hud_icon_state(key, "hover", px)
	var pressed := hud_icon_state(key, "pressed", px)
	if normal == null:
		return
	apply_button_icon(btn, normal, true)
	btn.set_meta("eoa_icon_key", key)
	btn.set_meta("eoa_icon_normal", normal)
	btn.set_meta("eoa_icon_hover", hover if hover else normal)
	btn.set_meta("eoa_icon_pressed", pressed if pressed else normal)
	# Lambdas avoid static-callable disconnect ambiguity across re-theme passes.
	if not btn.has_meta("eoa_icon_signals_wired"):
		btn.set_meta("eoa_icon_signals_wired", true)
		btn.mouse_entered.connect(func() -> void: _on_icon_btn_hover(btn))
		btn.mouse_exited.connect(func() -> void: _on_icon_btn_unhover(btn))
		btn.button_down.connect(func() -> void: _on_icon_btn_down(btn))
		btn.button_up.connect(func() -> void: _on_icon_btn_up(btn))


static func _on_icon_btn_hover(btn: Button) -> void:
	if btn == null or not btn.has_meta("eoa_icon_hover"):
		return
	if btn.button_pressed:
		return
	btn.icon = btn.get_meta("eoa_icon_hover") as Texture2D


static func _on_icon_btn_unhover(btn: Button) -> void:
	if btn == null or not btn.has_meta("eoa_icon_normal"):
		return
	btn.icon = btn.get_meta("eoa_icon_normal") as Texture2D


static func _on_icon_btn_down(btn: Button) -> void:
	if btn == null or not btn.has_meta("eoa_icon_pressed"):
		return
	btn.icon = btn.get_meta("eoa_icon_pressed") as Texture2D


static func _on_icon_btn_up(btn: Button) -> void:
	if btn == null:
		return
	if btn.is_hovered() and btn.has_meta("eoa_icon_hover"):
		btn.icon = btn.get_meta("eoa_icon_hover") as Texture2D
	elif btn.has_meta("eoa_icon_normal"):
		btn.icon = btn.get_meta("eoa_icon_normal") as Texture2D


static func decorate_label_with_icon(label: Label, tex: Texture2D, icon_size: int = 18) -> void:
	## Puts a TextureRect sibling before the label when parent is an HBox; otherwise sets a simple icon meta.
	if label == null or tex == null:
		return
	var parent := label.get_parent()
	if parent is HBoxContainer:
		var existing := parent.get_node_or_null("Icon_%s" % label.name) as TextureRect
		if existing == null:
			var tr := TextureRect.new()
			tr.name = "Icon_%s" % label.name
			tr.texture = tex
			tr.custom_minimum_size = Vector2(icon_size, icon_size)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(tr)
			parent.move_child(tr, label.get_index())
		else:
			existing.texture = tex
	else:
		label.set_meta("eoa_resource_icon", tex)
