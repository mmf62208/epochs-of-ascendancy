extends SceneTree

## Read-only dump of a v2 .eoasave (header plus sorted body JSON).
##   tools/run_godot.sh --headless --path . -s res://tools/eoa_save_dump.gd -- /path/to/slot.eoasave
const _Fmt = preload("res://scripts/core/SaveFormat.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: eoa_save_dump.gd -- <file.eoasave|file.json>")
		quit(2)
		return
	var path := str(args[0])
	if path.ends_with(".json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		print(_sorted_json(parsed))
		quit(0)
		return
	var decoded: Dictionary = _Fmt.decode_file(path, true)
	if not bool(decoded.get("ok", false)):
		print("ERROR ", str(decoded.get("error", "unreadable")))
		quit(1)
		return
	print("HEADER")
	print(_sorted_json(decoded.get("header", {})))
	print("BODY")
	print(_sorted_json(decoded.get("body", {})))
	quit(0)


func _sorted_json(value: Variant) -> String:
	return JSON.stringify(_sort(value), "\t")


func _sort(value: Variant) -> Variant:
	if value is Dictionary:
		var src: Dictionary = value
		var keys: Array = src.keys()
		keys.sort_custom(func(a, b): return str(typeof(a)) + ":" + str(a) < str(typeof(b)) + ":" + str(b))
		var out := {}
		for k in keys:
			out[k] = _sort(src[k])
		return out
	if value is Array:
		var src_a: Array = value
		var out_a: Array = []
		for item in src_a:
			out_a.append(_sort(item))
		return out_a
	return value
