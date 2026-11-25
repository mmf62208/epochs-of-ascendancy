extends SceneTree

## LOAD-SCREEN-1: Loading Screen prefers the alpha wordmark.
## Fails on base e0388c58 (opaque WORDMARK_PATH). Passes when the alpha 768
## is preferred and the 0.30 chapter pin still holds.
##
##   XDG_DATA_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) tools/run_godot.sh --headless --path . \
##     -s res://scripts/core/HeadlessLoadScreen1Test.gd

const _LoadingScreen := preload("res://scripts/ui/LoadingScreen.gd")
const ALPHA_768 := "res://assets/graphics/branding/epochs_wordmark_alpha.png"
const ALPHA_512 := "res://assets/graphics/branding/epochs_wordmark_512_alpha.png"
const OPAQUE_768 := "res://assets/graphics/branding/epochs_wordmark.png"
const OPAQUE_512 := "res://assets/graphics/branding/epochs_wordmark_512.png"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var script := _LoadingScreen as GDScript
	if script == null:
		_fail("LoadingScreen script missing")
		_finish()
		return
	var src := FileAccess.get_file_as_string("res://scripts/ui/LoadingScreen.gd")
	var cmap: Dictionary = script.get_script_constant_map()
	var preferred := str(cmap.get("WORDMARK_PATH", ""))
	if preferred != ALPHA_768:
		_fail("WORDMARK_PATH %s want %s" % [preferred, ALPHA_768])
	if str(cmap.get("WORDMARK_PATH_512", "")) != ALPHA_512:
		_fail("WORDMARK_PATH_512 %s want %s" % [str(cmap.get("WORDMARK_PATH_512", "")), ALPHA_512])
	if not _source_prefers_alpha(src):
		_fail("load order is not alpha 768, alpha 512, opaque 768, opaque 512")
	if not ResourceLoader.exists(ALPHA_768):
		_fail("alpha 768 missing on disk")

	var loading := _LoadingScreen.new()
	if loading == null:
		_fail("LoadingScreen did not construct")
		_finish()
		return
	loading.name = "LoadScreen1"
	root.add_child(loading)
	loading.show_loading("cycle", "Loading the epoch")
	loading.update_progress(0.30, "Agents")
	await _frames(3)

	if not loading.is_in_group("loading_screen"):
		_fail("missing group loading_screen")
	if int(loading.layer) != 80:
		_fail("layer %s want 80" % str(loading.layer))
	var chapter: Label = loading.title_label
	var title_text := chapter.text if chapter != null else ""
	if title_text != "THE AGENT'S EPOCH":
		_fail("title %s" % title_text)
	var wordmark := loading.find_child("Wordmark", true, false) as TextureRect
	var tex_path := ""
	if wordmark == null or wordmark.texture == null:
		_fail("Wordmark texture missing")
	else:
		tex_path = _texture_path(wordmark.texture)
		if ResourceLoader.exists(ALPHA_768) and tex_path != ALPHA_768:
			_fail("loaded texture %s want %s" % [tex_path, ALPHA_768])
	print(
		"LOAD_SCREEN_1 WORDMARK_PATH=%s texture=%s title=%s group=%s layer=%s"
		% [
			preferred,
			tex_path,
			title_text,
			str(loading.is_in_group("loading_screen")),
			str(loading.layer),
		]
	)

	loading.hide_and_free()
	await _frames(3)
	if is_instance_valid(loading) and loading.is_inside_tree():
		_fail("hide_and_free left the screen in the tree")
	else:
		print("LOAD_SCREEN_1 hide_and_free dismissed")
	_finish()


func _finish() -> void:
	if _failures == 0:
		print("RESULT=PASS")
		quit(0)
	else:
		print("RESULT=FAIL failures=%d" % _failures)
		quit(1)


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL %s" % msg)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _texture_path(tex: Texture2D) -> String:
	var path := str(tex.resource_path)
	if path.is_empty():
		path = str(tex.get_path())
	return path


func _source_prefers_alpha(src: String) -> bool:
	if src.find('const WORDMARK_PATH := "%s"' % ALPHA_768) < 0:
		return false
	if src.find('const WORDMARK_PATH_512 := "%s"' % ALPHA_512) < 0:
		return false
	var keys: PackedStringArray = [ALPHA_768, ALPHA_512, OPAQUE_768, OPAQUE_512]
	var prev := -1
	for key in keys:
		var at := src.find(key)
		if at < 0 or at <= prev:
			return false
		prev = at
	var loader := src.find("func _load_wordmark_texture")
	if loader < 0:
		return false
	var body := src.substr(loader, 800)
	var names: PackedStringArray = [
		"WORDMARK_PATH,",
		"WORDMARK_PATH_512,",
		"WORDMARK_PATH_OPAQUE,",
		"WORDMARK_PATH_512_OPAQUE,",
	]
	prev = -1
	for name in names:
		var at_body := body.find(name)
		if at_body < 0 or at_body <= prev:
			return false
		prev = at_body
	if body.find("ResourceLoader.exists") < 0:
		return false
	return true
