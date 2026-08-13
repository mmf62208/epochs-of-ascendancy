# scripts/ui/WeatherIconLibrary.gd
## Pass 9: retrowave ground-state / storm weather icons for legend + inspector chips.
class_name WeatherIconLibrary
extends RefCounted

const WX_DIR := "res://assets/graphics/icons/weather/"

## ground_state / precip key → asset stem
const STEM_MAP := {
	"dry": "dry",
	"clear": "dry",
	"fair": "dry",
	"mud": "mud",
	"muddy": "mud",
	"wet": "mud",
	"snow": "snow",
	"snow_covered": "snow",
	"frozen": "snow",
	"ice": "snow",
	"storm": "storm",
	"stormy": "storm",
	"heavy_rain": "storm",
	"tempest": "storm",
}


static func _load(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func resolve_stem(ground_or_key: String) -> String:
	var k := ground_or_key.strip_edges().to_lower()
	if k.is_empty():
		return "dry"
	if STEM_MAP.has(k):
		return str(STEM_MAP[k])
	if "storm" in k or "thunder" in k or "gale" in k:
		return "storm"
	if "snow" in k or "ice" in k or "frozen" in k or "blizzard" in k:
		return "snow"
	if "mud" in k or "wet" in k or "rain" in k:
		return "mud"
	return "dry"


static func icon_path(ground_or_key: String, px: int = 32) -> String:
	var stem := resolve_stem(ground_or_key)
	var p := "%s%s_%d.png" % [WX_DIR, stem, px]
	if ResourceLoader.exists(p):
		return p
	if px != 64:
		var p64 := "%s%s_64.png" % [WX_DIR, stem]
		if ResourceLoader.exists(p64):
			return p64
	if px != 32:
		var p32 := "%s%s_32.png" % [WX_DIR, stem]
		if ResourceLoader.exists(p32):
			return p32
	return ""


static func icon_for(ground_or_key: String, px: int = 32) -> Texture2D:
	return _load(icon_path(ground_or_key, px))


## Godot RichTextLabel [img] tag for weather chip prefixes.
static func bbcode_img(ground_or_key: String, px: int = 16) -> String:
	var path := icon_path(ground_or_key, 32 if px <= 32 else 64)
	if path.is_empty():
		return ""
	return "[img=%dx%d]%s[/img]" % [px, px, path]


## Short plain label for tooltips / toolbar (no BBCode).
static func plain_label(ground_or_key: String) -> String:
	match resolve_stem(ground_or_key):
		"mud":
			return "mud"
		"snow":
			return "snow"
		"storm":
			return "storm"
		_:
			return "dry"


## Prefer storm when precip is high even if ground is dry.
static func key_from_weather(ground_state: String, precip_intensity: float = 0.0) -> String:
	if precip_intensity >= 0.55:
		return "storm"
	return resolve_stem(ground_state)
