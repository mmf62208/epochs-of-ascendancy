# scripts/map/TerrainLayerStack.gd
## Composites real-world map layers (NASA + Natural Earth).
## Default aesthetic (when vegetation off): clean stylized parchment + directional hillshade relief + rivers + subtle coasts.
## Vegetation layer is a *very faint* pastel green wash (toggle with V). Kept off by default for readability and "world class clean" grand strategy feel (inspired by classic map design + player preference for uncluttered political/terrain views).
## Built by tools/map_generation/scripts/build_real_world_map_layers.py
## Aligns with MapRenderer grand/world bounds (6000×2400 / 9830×4915 @ THEATER_SCALE).
## Future: vegetation (and snow) can auto-modulate alpha based on camera zoom for "detail only when zoomed".

class_name TerrainLayerStack
extends Node2D

const LAYER_DIR := "res://assets/maps/layers/"
const METADATA_PATH := "res://data/map/layer_metadata.json"
const METADATA_WORLD_PATH := "res://data/map/layer_metadata_world.json"

@export var show_base_layer: bool = true
@export var show_rivers_layer: bool = true
@export var show_elevation_layer: bool = true
@export var show_vegetation_layer: bool = false  # Intentionally default OFF for clean parchment + rivers + directional hills aesthetic. V key reveals the very faint pastel veg tint (subtle, toggleable, optional at zoom).
@export var show_snow_mask_layer: bool = false  # for reference "snow potential" on high elev from layers (winter mix); main snow via WeatherOverlayLayer dynamic.

var _base: Sprite2D
var _rivers: Sprite2D
var _elevation: Sprite2D
var _vegetation: Sprite2D
var _snow_mask: Sprite2D
var _loaded: bool = false
var _world_layers_loaded: bool = false
var _loaded_chunk_index: int = -1


func _ready() -> void:
	name = "TerrainLayerStack"
	z_index = -100
	add_to_group("terrain_layer_stack")


func try_load_from_metadata(prefix: String = "europe") -> bool:
	if _loaded:
		return true
	var paths := {
		"base": LAYER_DIR + prefix + "_base_stylized.png",
		"rivers": LAYER_DIR + prefix + "_layer_rivers.png",
		"elevation": LAYER_DIR + prefix + "_layer_elevation.png",
		"vegetation": LAYER_DIR + prefix + "_layer_vegetation.png",
		"snow_mask": LAYER_DIR + "europe_snow_mask.png",  # or world_snow_mask.png for global; or chunk variant; loaded from metadata if present for snow potential ref
	}
	if ResourceLoader.exists(METADATA_PATH):
		var f := FileAccess.open(METADATA_PATH, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			if data is Dictionary and data.has("layers"):
				var layers: Dictionary = data["layers"]
				for key in layers.keys():
					var rel := str(layers[key])
					if rel.begins_with("assets/"):
						paths[key] = "res://" + rel
	# Prefer world snow for global when not chunk (from full world --only-snow build)
	if not paths.has("snow_mask") or not ResourceLoader.exists(paths.get("snow_mask", "")):
		if ResourceLoader.exists("res://assets/maps/layers/world_snow_mask.png"):
			paths["snow_mask"] = "res://assets/maps/layers/world_snow_mask.png"

	_ensure_sprites()
	_ensure_snow_additive_blend()
	var any := false
	any = _set_tex(_base, paths["base"]) or any
	any = _set_tex(_rivers, paths["rivers"]) or any
	any = _set_tex(_elevation, paths["elevation"]) or any
	any = _set_tex(_vegetation, paths["vegetation"]) or any
	any = _set_tex(_snow_mask, paths.get("snow_mask", "")) or any
	_apply_visibility()
	_loaded = any
	if any:
		print("TerrainLayerStack: loaded real-world layers (base/rivers/elevation/vegetation — veg defaults OFF for clean look, S snow_mask ref for high elev snow potential) from ", LAYER_DIR)
	return any


func try_load_world_from_metadata() -> bool:
	if _world_layers_loaded and _rivers != null and _rivers.texture != null:
		_apply_visibility()
		return true
	_ensure_sprites()
	var paths := _resolve_world_layer_paths()
	var any := false
	any = _set_tex(_base, paths["base"]) or any
	any = _set_tex(_rivers, paths["rivers"]) or any
	any = _set_tex(_elevation, paths["elevation"]) or any
	any = _set_tex(_vegetation, paths["vegetation"]) or any
	any = _set_tex(_snow_mask, paths.get("snow_mask", "")) or any
	_apply_visibility()
	_loaded = any
	if any:
		_world_layers_loaded = true
		print("TerrainLayerStack: loaded WORLD layers (rivers/lakes + elevation/mountains) from metadata_world")
	return any


func _resolve_world_layer_paths() -> Dictionary:
	var paths := {
		"base": LAYER_DIR + "world_base_stylized.png",
		"rivers": LAYER_DIR + "world_layer_rivers.png",
		"elevation": LAYER_DIR + "world_layer_elevation.png",
		"vegetation": LAYER_DIR + "world_layer_vegetation.png",
		"snow_mask": LAYER_DIR + "world_snow_mask.png",
	}
	if ResourceLoader.exists(METADATA_WORLD_PATH):
		var f := FileAccess.open(METADATA_WORLD_PATH, FileAccess.READ)
		if f:
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			if data is Dictionary and data.has("layers"):
				var layers: Dictionary = data["layers"]
				for key in layers.keys():
					var rel := str(layers[key])
					if rel.begins_with("assets/"):
						paths[key] = "res://" + rel
	return paths


func configure_for_world_launch() -> void:
	show_base_layer = false
	show_rivers_layer = true
	show_elevation_layer = true
	show_vegetation_layer = false
	show_snow_mask_layer = false  # Press S to overlay peak snow (additive — black mask areas stay transparent).
	visible = true
	_ensure_sprites()
	if _elevation:
		_elevation.modulate = Color(1.03, 1.0, 0.95, 0.72)
	if _rivers:
		# High alpha so Great Lakes, major rivers, and lake chains read clearly over the photo underlay.
		_rivers.modulate = Color(1.0, 1.0, 1.0, 0.95)
	if _snow_mask:
		_snow_mask.modulate = Color(1.0, 1.0, 1.0, 0.78)
	_apply_visibility()


func _ensure_sprites() -> void:
	if _base == null:
		_base = _make_sprite("BaseLayer", -4)
		_rivers = _make_sprite("RiversLayer", -2)
		_elevation = _make_sprite("ElevationLayer", -3)
		_vegetation = _make_sprite("VegetationLayer", -1)
		_snow_mask = _make_sprite("SnowMaskLayer", 15)  # additive peak snow overlay (S key); black in mask = transparent
	_ensure_snow_additive_blend()


func _ensure_snow_additive_blend() -> void:
	if _snow_mask == null:
		return
	if _snow_mask.material == null:
		var mat := CanvasItemMaterial.new()
		# ADD: white peak mask brightens map; black mask pixels add nothing (stay transparent).
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_snow_mask.material = mat


func _make_sprite(sprite_name: String, z: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = sprite_name
	s.centered = false
	s.z_index = z
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(s)
	return s


func _set_tex(sprite: Sprite2D, path: String) -> bool:
	if not ResourceLoader.exists(path):
		sprite.visible = false
		return false
	var tex := load(path) as Texture2D
	if tex == null:
		sprite.visible = false
		return false
	sprite.texture = tex
	sprite.visible = true
	return true


func fit_to_bounds(bounds: Rect2) -> void:
	_ensure_sprites()
	for s in [_base, _rivers, _elevation, _vegetation]:
		if s and s.texture:
			s.position = bounds.position
			var img_size := Vector2(s.texture.get_width(), s.texture.get_height())
			if img_size.x > 0 and img_size.y > 0:
				s.scale = bounds.size / img_size
	# Peak snow aligns to WorldBackground (same 8192 canvas), not ProvinceContainers (camera zoom target).
	if _snow_mask and _snow_mask.texture and _peak_snow_bg == null:
		_snow_mask.position = bounds.position
		var snow_size := Vector2(_snow_mask.texture.get_width(), _snow_mask.texture.get_height())
		if snow_size.x > 0 and snow_size.y > 0:
			_snow_mask.scale = bounds.size / snow_size
	sync_peak_snow_transform()


## Load per-chunk layers (for world portion / multi-theater testing).
## Expects chunk files like world_chunk_XX_world_layer_*.png + world_chunk_XX_snow_mask.png in world_chunks/.
## When active, toggles H/V/S will show the chunk-specific relief/veg/snow ref aligned to that visual underlay.
func load_world_chunk_layers(chunk_index: int) -> bool:
	if chunk_index == _loaded_chunk_index:
		return _loaded
	_ensure_sprites()
	var cdir := "res://assets/maps/world_chunks/"
	var cidx := "%02d" % chunk_index
	var paths := {
		"base": cdir + "world_chunk_%s_world_base_stylized.png" % cidx,
		"rivers": cdir + "world_chunk_%s_world_layer_rivers.png" % cidx,
		"elevation": cdir + "world_chunk_%s_world_layer_elevation.png" % cidx,
		"vegetation": cdir + "world_chunk_%s_world_layer_vegetation.png" % cidx,
		"snow_mask": cdir + "world_chunk_%s_snow_mask.png" % cidx,  # normalized name from splitter
	}
	var any := false
	any = _set_tex(_base, paths["base"]) or any
	any = _set_tex(_rivers, paths["rivers"]) or any
	any = _set_tex(_elevation, paths["elevation"]) or any
	any = _set_tex(_vegetation, paths["vegetation"]) or any
	any = _set_tex(_snow_mask, paths["snow_mask"]) or any
	_apply_visibility()
	_loaded = any
	if any:
		_loaded_chunk_index = chunk_index
		print("TerrainLayerStack: loaded WORLD CHUNK ", chunk_index, " layers (base/rivers/elev/veg/snow for H/V/S toggles aligned to chunk underlay)")
	elif ResourceLoader.exists(cdir + "world_chunk_%s_world_grand_theater_clean.png" % cidx):
		# fallback: at least note that chunk underlay exists even if per-chunk layers not split for all
		print("TerrainLayerStack: chunk ", chunk_index, " underlay present but no full per-chunk layer set (using europe layers for toggles; snow may still work via weather)")
	return any


func set_layer_visible(which: String, visible: bool) -> void:
	match which:
		"base", "terrain":
			show_base_layer = visible
		"rivers":
			show_rivers_layer = visible
		"elevation", "hills", "mountains":
			show_elevation_layer = visible
		"vegetation", "forest", "jungle", "swamp":
			show_vegetation_layer = visible
		"snow", "snow_mask", "winter", "snow potential":
			show_snow_mask_layer = visible
	_apply_visibility()


func has_base_texture() -> bool:
	return _base != null and _base.texture != null


func _apply_visibility() -> void:
	if _base:
		_base.visible = show_base_layer and _base.texture != null
	if _rivers:
		_rivers.visible = show_rivers_layer and _rivers.texture != null
	if _elevation:
		_elevation.visible = show_elevation_layer and _elevation.texture != null
	if _vegetation:
		_vegetation.visible = show_vegetation_layer and _vegetation.texture != null
	if _snow_mask:
		_snow_mask.visible = show_snow_mask_layer and _snow_mask.texture != null

## LOD / zoom polish: fade veg (V) and snow ref (S) at close zoom for clean default (per design: very subtle, zoom-gated or off at tactical for readability).
## Call from MapRenderer on zoom change / repaint. 1.0 = full, lower = fade toward invisible.
func set_layer_alphas(veg_alpha: float = 1.0, snow_alpha: float = 1.0) -> void:
	if _vegetation and _vegetation.texture:
		var col := _vegetation.modulate
		col.a = clampf(veg_alpha, 0.0, 1.0)
		_vegetation.modulate = col
	if _snow_mask and _snow_mask.texture:
		var col := _snow_mask.modulate
		var target_a := snow_alpha
		if _snow_forced_on_by_toggle:
			target_a = maxf(target_a, 0.78)
		col.a = clampf(target_a, 0.0, 1.0)
		_snow_mask.modulate = col


func toggle_rivers() -> void:
	show_rivers_layer = not show_rivers_layer
	_apply_visibility()


func toggle_elevation() -> void:
	show_elevation_layer = not show_elevation_layer
	_apply_visibility()


func toggle_vegetation() -> void:
	show_vegetation_layer = not show_vegetation_layer
	_veg_forced_on_by_toggle = show_vegetation_layer
	_apply_visibility()

func toggle_snow_mask() -> void:
	show_snow_mask_layer = not show_snow_mask_layer
	_snow_forced_on_by_toggle = show_snow_mask_layer
	_ensure_snow_additive_blend()
	sync_peak_snow_transform()
	if show_snow_mask_layer and _snow_mask:
		_snow_mask.modulate = Color(1.0, 1.0, 1.0, 0.82)
	_apply_visibility()
	print("TerrainLayerStack: peak snow layer ", ("ON (persistent peaks overlay — NASA/DEM mask)" if show_snow_mask_layer else "OFF"))

var _veg_forced_on_by_toggle: bool = false
var _snow_forced_on_by_toggle: bool = false
var _peak_snow_map_root: Node2D = null
var _peak_snow_bg: Sprite2D = null
var _peak_snow_host_z: int = 8


## Draw peak/permafrost snow above province tints but locked to WorldBackground transform (8192 world canvas).
func mount_peak_snow_on_map(map_root: Node2D, background: Sprite2D, z_index: int = 8) -> void:
	_peak_snow_map_root = map_root
	_peak_snow_bg = background
	_peak_snow_host_z = z_index
	_ensure_sprites()
	if _snow_mask == null or map_root == null:
		return
	if _snow_mask.get_parent() != map_root:
		if _snow_mask.get_parent() != null:
			_snow_mask.reparent(map_root)
		else:
			map_root.add_child(_snow_mask)
	sync_peak_snow_transform()
	_ensure_snow_additive_blend()
	_apply_visibility()


func sync_peak_snow_transform() -> void:
	if _snow_mask == null or _peak_snow_bg == null or not is_instance_valid(_peak_snow_bg):
		return
	_snow_mask.global_transform = _peak_snow_bg.global_transform
	_snow_mask.z_index = _peak_snow_host_z
	_snow_mask.centered = false


func is_snow_mask_user_visible() -> bool:
	return show_snow_mask_layer

## Allows MapRenderer to hide the (very faint) vegetation layer at low zoom for an even cleaner default view,
## while still letting explicit V toggle force it visible. "Subtle detail only when you zoom in."
## Threshold tuned around 0.62 (roughly when province names and fine overlays become useful).
func apply_zoom_level(current_zoom: float) -> void:
	if _veg_forced_on_by_toggle:
		_apply_visibility()
	elif _vegetation:
		var want_veg := show_vegetation_layer and current_zoom > 0.62
		_vegetation.visible = want_veg and _vegetation.texture != null
	if _snow_forced_on_by_toggle and _snow_mask:
		_snow_mask.visible = show_snow_mask_layer and _snow_mask.texture != null
