# scripts/core/SaveFormat.gd
## Save format v2: JSON header + zstd var_to_bytes body, checksum, migrate, validate.
## Loaders must not apply state until validate() returns ok.
class_name SaveFormat
extends RefCounted

const MAGIC := "EOASAVE2"
const FORMAT_ID := "eoa-save"
const VERSION := 2
const HEADER_MAX := 1048576

## Test hooks. Production stays false. See HeadlessSaveReload1CorruptTest.
static var test_fail_write: bool = false
static var test_stop_after_tmp: bool = false


static func md5_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func encode(body: Dictionary, header_fields: Dictionary) -> Dictionary:
	var raw := var_to_bytes(body)
	if raw.is_empty():
		return {"ok": false, "error": "body encode failed (non-serializable value)"}
	var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if compressed.is_empty() and not raw.is_empty():
		return {"ok": false, "error": "zstd compress failed"}
	var header := header_fields.duplicate(true)
	header["format"] = FORMAT_ID
	header["save_version"] = VERSION
	header["body_md5"] = md5_hex(compressed)
	header["body_bytes"] = compressed.size()
	header["raw_bytes"] = raw.size()
	var header_bytes := JSON.stringify(header).to_utf8_buffer()
	if header_bytes.is_empty() or header_bytes.size() > HEADER_MAX:
		return {"ok": false, "error": "header encode failed"}
	var out := PackedByteArray()
	out.append_array(MAGIC.to_utf8_buffer())
	out.append_array(_u32le(header_bytes.size()))
	out.append_array(header_bytes)
	out.append_array(compressed)
	return {"ok": true, "bytes": out, "header": header, "body_md5": header["body_md5"]}


static func read_header(path: String) -> Dictionary:
	var decoded := decode_file(path, false)
	if not bool(decoded.get("ok", false)):
		return {"ok": false, "error": str(decoded.get("error", "unreadable")), "damaged": true}
	return {"ok": true, "header": decoded.get("header", {}), "damaged": false}


static func decode_file(path: String, with_body: bool = true) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "File not found: %s" % path, "missing": true}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Cannot open %s" % path, "damaged": true}
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return decode_bytes(bytes, with_body)


static func decode_bytes(bytes: PackedByteArray, with_body: bool = true) -> Dictionary:
	if bytes.is_empty():
		return {"ok": false, "error": "Empty save file", "damaged": true}
	if bytes.size() < 12:
		return {"ok": false, "error": "Truncated save (shorter than envelope)", "damaged": true}
	var magic := bytes.slice(0, 8).get_string_from_utf8()
	if magic != MAGIC:
		return {"ok": false, "error": "Bad save magic", "damaged": true}
	var header_len := int(bytes.decode_u32(8))
	if header_len <= 0 or header_len > HEADER_MAX:
		return {"ok": false, "error": "Bad header length", "damaged": true}
	if bytes.size() < 12 + header_len:
		return {"ok": false, "error": "Truncated header", "damaged": true}
	var header_text := bytes.slice(12, 12 + header_len).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(header_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Header is not JSON", "damaged": true}
	var header: Dictionary = parsed
	if str(header.get("format", "")) != FORMAT_ID:
		return {"ok": false, "error": "Unknown save format", "damaged": true, "header": header}
	var ver := int(header.get("save_version", 0))
	if ver != VERSION:
		return {
			"ok": false,
			"error": "Unsupported save version %d" % ver,
			"damaged": true,
			"header": header,
		}
	var body_len := int(header.get("body_bytes", -1))
	var body_bytes := bytes.slice(12 + header_len, bytes.size())
	if body_len < 0 or body_bytes.size() != body_len:
		return {"ok": false, "error": "Truncated body", "damaged": true, "header": header}
	var got := md5_hex(body_bytes)
	if got != str(header.get("body_md5", "")):
		return {"ok": false, "error": "Checksum mismatch", "damaged": true, "header": header}
	if not with_body:
		return {"ok": true, "header": header}
	var raw_size := int(header.get("raw_bytes", 0))
	var raw := body_bytes.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return {"ok": false, "error": "Decompress failed", "damaged": true, "header": header}
	var variant: Variant = bytes_to_var(raw)
	if typeof(variant) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Body is not a save dictionary", "damaged": true, "header": header}
	return {"ok": true, "header": header, "body": variant}


static func migrate(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return data
	var v := int(data.get("save_version", 0))
	if not data.has("metadata") or typeof(data["metadata"]) != TYPE_DICTIONARY:
		data["metadata"] = {}
	if not data.has("time") or typeof(data["time"]) != TYPE_DICTIONARY:
		data["time"] = {}
	# Wrong types stay wrong so validate() can reject them. Only fill holes.
	if not data.has("land_war"):
		data["land_war"] = {"version": 1, "open_battles": [], "marches": {}, "next_seq": 1, "last_aar": {}}
	if data.get("land_war") is Dictionary:
		var lw: Dictionary = data["land_war"]
		if not lw.has("open_battles"):
			lw["open_battles"] = []
		if not lw.has("marches"):
			lw["marches"] = {}
		if not lw.has("next_seq"):
			lw["next_seq"] = 1
		if not lw.has("last_aar"):
			lw["last_aar"] = {}
		data["land_war"] = lw
	for key in ["technology", "agents", "supply", "national_modifiers", "leaders", "production", "factories", "game_data", "relations", "session_players", "national_spirits"]:
		if not data.has(key):
			data[key] = {}
	if not data.has("infrastructure_projects"):
		data["infrastructure_projects"] = {"version": 1, "active_projects": {}}
	if data.get("time") is Dictionary:
		var time_block: Dictionary = data["time"]
		if not time_block.has("current_hour"):
			time_block["current_hour"] = 0
			data["time"] = time_block
	_ensure_metadata_tag(data)
	if v < VERSION and data.get("land_war") is Dictionary and data.get("map") is Dictionary:
		data["save_version"] = VERSION
	elif v < VERSION and not data.has("save_version"):
		data["save_version"] = VERSION
	return data


static func _ensure_metadata_tag(data: Dictionary) -> void:
	var meta: Dictionary = data.get("metadata", {}) if data.get("metadata") is Dictionary else {}
	var tag := str(meta.get("player_tag", "")).strip_edges()
	if tag.is_empty() or tag == "USA":
		var leaders: Dictionary = data.get("leaders", {}) if data.get("leaders") is Dictionary else {}
		var from_leaders := str(leaders.get("player_country_tag", "")).strip_edges()
		if not from_leaders.is_empty():
			meta["player_tag"] = from_leaders
			data["metadata"] = meta


static func validate(data: Dictionary, scenario_guard: String = "") -> Dictionary:
	var errors: Array[String] = []
	if typeof(data) != TYPE_DICTIONARY or data.is_empty():
		return {"ok": false, "errors": ["empty save"]}
	if int(data.get("save_version", 0)) > VERSION:
		errors.append("save version %d is newer than %d" % [int(data.get("save_version", 0)), VERSION])
	if not data.has("time") or typeof(data["time"]) != TYPE_DICTIONARY:
		errors.append("time section missing")
	if not data.has("map") or typeof(data["map"]) != TYPE_DICTIONARY:
		errors.append("map section missing")
	else:
		var map_check: Dictionary = _validate_map(data["map"], data)
		if not bool(map_check.get("ok", false)):
			errors.append("map payload invalid: %s" % str(map_check.get("missing", [])))
	if not data.has("land_war"):
		errors.append("land_war section missing")
	elif typeof(data["land_war"]) != TYPE_DICTIONARY:
		errors.append("land_war must be a dictionary")
	else:
		var lw: Dictionary = data["land_war"]
		if not (lw.get("open_battles") is Array):
			errors.append("land_war.open_battles must be an array")
		if lw.has("marches") and typeof(lw["marches"]) != TYPE_DICTIONARY:
			errors.append("land_war.marches must be a dictionary")
	var guard := scenario_guard.strip_edges()
	if not guard.is_empty():
		var meta: Dictionary = data.get("metadata", {}) if data.get("metadata") is Dictionary else {}
		var saved := str(meta.get("scenario_id", "")).strip_edges()
		if not saved.is_empty() and saved != guard:
			errors.append("scenario mismatch: save is %s, game is %s" % [saved, guard])
	return {"ok": errors.is_empty(), "errors": errors}


static func atomic_write(final_user_path: String, bytes: PackedByteArray) -> Dictionary:
	var final_path := ProjectSettings.globalize_path(final_user_path)
	var tmp_path := final_path + ".tmp"
	var bak_path := final_path + ".bak"
	_remove_if_exists(tmp_path)
	# Failure is injected inside _store_bytes, after the bytes hit the path
	# that was opened. A direct-to-final mutant therefore corrupts the
	# previous save. The atomic path only stores the tmp.
	var stored := _store_bytes(tmp_path, bytes)
	if not stored.get("ok", false):
		_remove_if_exists(tmp_path)
		return {"ok": false, "error": str(stored.get("error", "tmp write failed")), "path": final_user_path}
	var verify := decode_file(tmp_path, false)
	if not bool(verify.get("ok", false)):
		_remove_if_exists(tmp_path)
		return {"ok": false, "error": "Tmp failed header check: %s" % str(verify.get("error", "")), "path": final_user_path}
	if test_stop_after_tmp:
		return {
			"ok": false,
			"error": "Injected crash after tmp",
			"crashed_after_tmp": true,
			"path": final_user_path,
		}
	var had_final := FileAccess.file_exists(final_path)
	if had_final:
		_remove_if_exists(bak_path)
		var bak_err := DirAccess.rename_absolute(final_path, bak_path)
		if bak_err != OK:
			_remove_if_exists(tmp_path)
			return {"ok": false, "error": "Could not rotate previous save (err %d)" % bak_err, "path": final_user_path}
	var ren_err := DirAccess.rename_absolute(tmp_path, final_path)
	if ren_err != OK:
		if had_final and FileAccess.file_exists(bak_path):
			DirAccess.rename_absolute(bak_path, final_path)
		_remove_if_exists(tmp_path)
		return {"ok": false, "error": "Could not commit save (err %d)" % ren_err, "path": final_user_path}
	_remove_if_exists(tmp_path)
	return {"ok": true, "path": final_user_path, "absolute_path": final_path, "bytes": bytes.size()}


static func _validate_map(map_data: Dictionary, full_save: Dictionary) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var slm: Node = tree.root.get_node_or_null("SaveLoadManager") if tree != null else null
	if slm != null and slm.has_method("validate_map_save_payload"):
		return slm.call("validate_map_save_payload", map_data, full_save)
	if not map_data.has("provinces"):
		return {"ok": false, "missing": ["map.provinces"]}
	return {"ok": true, "missing": []}


static func _store_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "Cannot open %s (err %d)" % [path, FileAccess.get_open_error()]}
	f.store_buffer(bytes)
	f.close()
	if test_fail_write:
		_remove_if_exists(path)
		return {"ok": false, "error": "Injected write failure"}
	return {"ok": true}


static func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _u32le(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, n)
	return b
