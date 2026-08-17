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
