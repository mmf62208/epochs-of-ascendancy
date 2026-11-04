# scripts/core/SystemTogglesDomain.gd
## Campaign setup toggles. Data lives in data/settings/system_toggles.json.
## A modder adds an object there (id, label, default, env). The setup screen,
## save blob, and is_enabled() pick it up. The system itself only calls
## is_enabled(id). Precedence: env "1" or "0", then the campaign choice,
## then the registry default. Defaults in the file stay false.
class_name SystemTogglesDomain
extends RefCounted

const PATH := "res://data/settings/system_toggles.json"
const KEY := "system_toggles"

static var _loaded: bool = false
static var _by_id: Dictionary = {}
static var _order: Array = []
static var _campaign: Dictionary = {}


static func entries() -> Array:
	_load()
	var out: Array = []
	for raw in _order:
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


static func is_enabled(id: String) -> bool:
	_load()
	var key := id.strip_edges()
	if not _by_id.has(key):
		return false
	var entry: Dictionary = _by_id[key]
	var env_name := str(entry.get("env", "")).strip_edges()
	if not env_name.is_empty():
		var env := OS.get_environment(env_name).strip_edges()
		if env == "1":
			return true
		if env == "0":
			return false
	if _campaign.has(key):
		return bool(_campaign[key])
	return bool(entry.get("default", false))


## New-campaign checkboxes. Stores only values that differ from the registry default.
static func apply_setup(chosen: Dictionary) -> Dictionary:
	_load()
	_campaign = {}
	for raw in _order:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var id := str(entry.get("id", "")).strip_edges()
		if id.is_empty() or not chosen.has(id):
			continue
		var on := bool(chosen[id])
		if on == bool(entry.get("default", false)):
			continue
		_campaign[id] = on
	return _campaign.duplicate(true)


static func export_save_blob() -> Dictionary:
	_load()
	var out := {}
	for id_v in _campaign.keys():
		var id := str(id_v)
		if not _by_id.has(id):
			continue
		var entry: Dictionary = _by_id[id]
		var on := bool(_campaign[id])
		if on == bool(entry.get("default", false)):
			continue
		out[id] = on
	return out


static func import_save_blob(data: Dictionary) -> void:
	_load()
	_campaign = {}
	if data.is_empty():
		return
	for id_v in data.keys():
		var id := str(id_v).strip_edges()
		if not _by_id.has(id):
			continue
		var entry: Dictionary = _by_id[id]
		var on := bool(data[id_v])
		if on == bool(entry.get("default", false)):
			continue
		_campaign[id] = on


static func load_missing_save() -> void:
	_campaign = {}


static func reset_for_test() -> void:
	_campaign = {}
	_loaded = false
	_by_id = {}
	_order = []
	_load()


static func set_registry_for_test(rows: Array) -> void:
	_campaign = {}
	_loaded = true
	_by_id = {}
	_order = []
	_ingest(rows)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id = {}
	_order = []
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var rows: Array = []
	if parsed is Dictionary:
		var raw: Variant = (parsed as Dictionary).get("toggles", [])
		if raw is Array:
			rows = raw
	elif parsed is Array:
		rows = parsed
	_ingest(rows)


static func _ingest(rows: Array) -> void:
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var row: Dictionary = raw
		var id := str(row.get("id", "")).strip_edges()
		if id.is_empty() or _by_id.has(id):
			continue
		var label := str(row.get("label", id)).strip_edges()
		if label.is_empty():
			label = id
		var entry := {
			"id": id,
			"label": label,
			"default": bool(row.get("default", false)),
			"env": str(row.get("env", "")).strip_edges(),
		}
		_by_id[id] = entry
		_order.append(entry)
