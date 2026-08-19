# scripts/audio/LandBattleSfx.gd
## Battle cue aliases → existing MapRenderer._SFX_PATHS files.
## Director plays via MapRenderer._play_map_sfx(LandBattleSfx.key_for(event)).
## No new binaries — Sound FX Starter Pack Vol. 1 only.

class_name LandBattleSfx
extends RefCounted

const PACK := "res://Sound FX Starter Pack Vol. 1/UI & Menus"

## Existing _SFX_PATHS keys (Director must use these — MapRenderer has no clash/bounce keys).
const KEY_ORDER_CONFIRM := "confirm"
const KEY_DAILY_CLASH := "map"
const KEY_CAPTURE := "achievement"
const KEY_BOUNCE := "error"

const PATH_ORDER_CONFIRM := PACK + "/Click Bounce.wav"
const PATH_DAILY_CLASH := PACK + "/Map.wav"
const PATH_CAPTURE := PACK + "/Achievement.wav"
const PATH_BOUNCE := PACK + "/Error.wav"


static func key_for(event: String) -> String:
	match event.strip_edges().to_lower():
		"order_confirm", "confirm":
			return KEY_ORDER_CONFIRM
		"daily_clash", "clash":
			return KEY_DAILY_CLASH
		"capture":
			return KEY_CAPTURE
		"bounce", "repulse":
			return KEY_BOUNCE
		_:
			return "select"


## Type-flavored cues still map to existing _SFX_PATHS keys (no new wavs).
static func key_for_unit(event: String, unit_kind: String = "infantry") -> String:
	var ev := event.strip_edges().to_lower()
	var kind := unit_kind.strip_edges().to_lower()
	var armor := "armor" in kind or "tank" in kind or "panzer" in kind
	var arty := "artillery" in kind or "rocket" in kind
	var air := "air" in kind or "fighter" in kind or "bomber" in kind
	if ev == "move" or ev == "march" or ev == "hop":
		if armor:
			return KEY_ORDER_CONFIRM
		if arty:
			return KEY_DAILY_CLASH
		return "select"
	if ev == "clash" or ev == "combat" or ev == "battle":
		if armor:
			return KEY_CAPTURE
		if arty:
			return KEY_BOUNCE
		if air:
			return "select"
		return KEY_DAILY_CLASH
	if ev == "arrive":
		return KEY_ORDER_CONFIRM
	return key_for(ev)


static func path_for(event: String) -> String:
	match key_for(event):
		KEY_ORDER_CONFIRM:
			return PATH_ORDER_CONFIRM
		KEY_DAILY_CLASH:
			return PATH_DAILY_CLASH
		KEY_CAPTURE:
			return PATH_CAPTURE
		KEY_BOUNCE:
			return PATH_BOUNCE
		_:
			return PACK + "/Select.wav"
