@tool
class_name EventNodeRegistry
extends RefCounted

## Auto-scans directories for EventNodeResource subclass scripts and builds
## a registry used by the palette and graph resource for node creation.

# Built-in nodes are now automatically scanned from res://addons/event_graph/core/nodes/

static var _cached_registry: Dictionary = {}
static var _scanned: bool = false


## Get the full registry (builtins + scanned custom nodes).
static func get_registry() -> Dictionary:
	if not _scanned or _cached_registry.is_empty():
		_rebuild()
	return _cached_registry


## Force a rebuild of the registry (call when files change).
static func rebuild() -> void:
	_rebuild()


static func _rebuild() -> void:
	_cached_registry.clear()

	# Scan node directories
	var scan_dirs := ["res://addons/event_graph/core/nodes", "res://addons/event_graph/core/nodes/event","res://addons/event_graph/core/nodes/flow","res://addons/event_graph/core/nodes/logic","res://addons/event_graph/core/nodes/action","res://addons/event_graph/core/nodes/data","res://addons/event_graph/core/nodes/utility"]
	for dir_path in scan_dirs:
		_scan_directory(dir_path)

	_scanned = true


static func _scan_directory(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("."):
			pass # skip
		elif dir.current_is_dir():
			_scan_directory(dir_path.path_join(file_name))
		elif file_name.ends_with(".gd"):
			var full_path := dir_path.path_join(file_name)
			_try_register_script(full_path)
			
		file_name = dir.get_next()
	dir.list_dir_end()


static func _try_register_script(script_path: String) -> void:
	var script := load(script_path) as Script
	if script == null:
		push_warning("[EventGraph] Failed to load script or not a script: " + script_path)
		return

	var instance = script.new()
	if instance == null:
		push_warning("[EventGraph] Failed to instantiate script: " + script_path)
		return

	# Duck typing: instead of `is EventNodeResource`, check for a known method
	if not instance.has_method("get_trigger_inputs"):
		return

	var name_key: String = instance.get("node_name")
	if name_key == null or name_key.is_empty():
		name_key = script_path.get_file().get_basename()

	var title_val = instance.get("title")
	var label_str: String = str(title_val) if title_val != null and str(title_val) != "" else name_key

	_cached_registry[name_key] = {
		"label": label_str,
		"category": str(instance.get("category")),
		"script": script_path,
		"description": str(instance.get("description"))
	}


## Create a EventNodeResource instance by node_name key.
static func create_node(name_key: String) -> Resource:
	var registry := get_registry()
	if registry.has(name_key):
		var info: Dictionary = registry[name_key]
		var script_path: String = info.get("script", "")
		if not script_path.is_empty():
			var script := load(script_path) as Script
			if script:
				return script.new() as Resource

	push_error("[EventGraph] Unknown node type: " + name_key)
	return null
