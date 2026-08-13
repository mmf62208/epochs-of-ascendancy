# scripts/map/TerrainTileLibrary.gd
## Seamless terrain tiles (game-tilesets pack) for overlays / future terrain stack.
class_name TerrainTileLibrary
extends RefCounted

const TILE_DIR := "res://assets/graphics/tiles/"

const KEYS := {
	"ocean": "ocean_seamless.png",
	"sea": "ocean_seamless.png",
	"water": "ocean_seamless.png",
	"plains": "plains_seamless.png",
	"plain": "plains_seamless.png",
	"grass": "plains_seamless.png",
	"hills": "hills_seamless.png",
	"hill": "hills_seamless.png",
	"mountain": "hills_seamless.png",
	"forest": "forest_seamless.png",
	"woods": "forest_seamless.png",
	"jungle": "jungle_seamless.png",
	"desert": "desert_seamless.png",
	"arid": "desert_seamless.png",
	"tundra": "tundra_seamless.png",
	"arctic": "tundra_seamless.png",
	"snow": "snow_seamless.png",
	"ice": "snow_seamless.png",
	"marsh": "marsh_seamless.png",
	"swamp": "marsh_seamless.png",
	"wetland": "marsh_seamless.png",
	"coastal": "coastal_seamless.png",
	"coast": "coastal_seamless.png",
	"harbor": "coastal_seamless.png",
	"port_terrain": "coastal_seamless.png",
	## Transition pack (plains ↔ hills)
	"plains_hills_blend": "transitions/plains_hills_blend.png",
	"plains_hills_edge": "transitions/plains_hills_edge.png",
	"plains_fill_from_blend": "transitions/plains_fill_from_blend.png",
	"hills_fill_from_blend": "transitions/hills_fill_from_blend.png",
}


static func tile_path(key: String) -> String:
	var k := key.strip_edges().to_lower()
	var file := str(KEYS.get(k, ""))
	if file.is_empty():
		return ""
	return TILE_DIR + file


static func load_tile(key: String) -> Texture2D:
	var path := tile_path(key)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Soft terrain-tint helper for province fill colors (cheap, no per-pixel sampling).
static func terrain_tint_for_key(terrain: String) -> Color:
	match terrain.strip_edges().to_lower():
		"sea", "ocean", "water", "lake":
			return Color(0.12, 0.22, 0.38, 1.0)
		"plains", "plain", "grassland", "grass":
			return Color(0.35, 0.42, 0.22, 1.0)
		"hills", "hill", "highland":
			return Color(0.42, 0.38, 0.30, 1.0)
		"mountain", "mountains", "alpine":
			return Color(0.45, 0.45, 0.48, 1.0)
		"forest", "woods":
			return Color(0.18, 0.32, 0.18, 1.0)
		"jungle":
			return Color(0.10, 0.28, 0.14, 1.0)
		"desert", "arid":
			return Color(0.55, 0.48, 0.28, 1.0)
		"tundra", "arctic":
			return Color(0.72, 0.78, 0.88, 1.0)
		"snow", "ice":
			return Color(0.82, 0.88, 0.95, 1.0)
		"marsh", "swamp", "wetland":
			return Color(0.28, 0.36, 0.26, 1.0)
		"coastal", "coast", "harbor", "port_terrain":
			return Color(0.22, 0.48, 0.52, 1.0)
		"urban", "city":
			return Color(0.35, 0.35, 0.40, 1.0)
		"plains_hills_edge", "plains_hills_blend":
			return Color(0.38, 0.40, 0.26, 1.0)
		_:
			return Color(0.30, 0.32, 0.28, 1.0)


## Midpoint tint for plains↔hills fronts (uses transition pack palette).
static func plains_hills_edge_tint() -> Color:
	return terrain_tint_for_key("plains").lerp(terrain_tint_for_key("hills"), 0.5)
