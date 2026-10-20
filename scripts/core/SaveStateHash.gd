# scripts/core/SaveStateHash.gd
## Canonical hash of a gathered save blob.
## A float on the 4-decimal grid that lands on an integer hashes as that int
## (JSON parses 10607 as 10607.0). Numeric string keys ("904797") match the
## int key. Other key types stay distinct. Dictionary keys are sorted.
class_name SaveStateHash
extends RefCounted

const _VOLATILE_META := ["timestamp", "last_played", "play_time_seconds", "wall_time"]
const _VOLATILE_SECTIONS := ["map_ui", "province_editor"]
## Wall-clock samples stored inside the multi-AI day audit. Nothing in the sim
## reads them back; the next day overwrites the whole audit. They differ across
## processes and must not change the identity hash.
const _VOLATILE_TIMING_KEYS := ["ms", "total_ms"]


## JSON stringify/parse moves a double in the last bits. Four decimal places
## keeps stockpile identity without treating 0.0001 as a different world.
static func _round_sim(fv: float) -> float:
	return round(fv * 10000.0) / 10000.0


static func _whole_float(fv: float) -> bool:
	if is_nan(fv) or is_inf(fv):
		return false
	if abs(fv) > 9007199254740992.0:
		return false
	return fv == floor(fv)


static func md5_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


static func state_hash(data: Dictionary) -> String:
	return md5_hex(canonical(data))


static func canonical(data: Dictionary) -> PackedByteArray:
	return _enc(_strip(data))


static func section_hashes(data: Dictionary) -> Dictionary:
	var stripped := _strip(data)
	var out := {}
	var keys: Array = stripped.keys()
	keys.sort_custom(_key_less)
	for k in keys:
		out[str(k)] = md5_hex(_enc(stripped[k]))
	return out


## Snap a float onto the 4-decimal grid. A value that lands on an integer
## becomes that int, so JSON's 10607.0 and a live 10607.0000001 hash together.
static func _norm(v: Variant) -> Variant:
	if typeof(v) != TYPE_FLOAT:
		return v
	var r := _round_sim(float(v))
	if _whole_float(r):
		return int(r)
	return r


## JSON object keys are strings. A province id 904797 and the key "904797"
## are the same map entry after a save round-trip.
static func _key_norm(k: Variant) -> Variant:
	var n: Variant = _norm(k)
	if typeof(n) == TYPE_STRING:
		var s := str(n)
		if s.is_valid_int() and str(int(s)) == s:
			return int(s)
	return n


static func _norm_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d.keys():
		out[_key_norm(k)] = d[k]
	return out


static func first_diff(a: Variant, b: Variant, path: String = "") -> String:
	a = _norm(a)
	b = _norm(b)
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		if _round_sim(float(a)) == _round_sim(float(b)):
			return ""
	if typeof(a) != typeof(b):
		return "%s type %s vs %s (%s vs %s)" % [path, typeof(a), typeof(b), str(a), str(b)]
	match typeof(a):
		TYPE_DICTIONARY:
			var da: Dictionary = _norm_dict(a)
			var db: Dictionary = _norm_dict(b)
			var keys: Array = []
			for k in da.keys():
				if k not in keys:
					keys.append(k)
			for k2 in db.keys():
				if k2 not in keys:
					keys.append(k2)
			keys.sort_custom(_key_less)
			for k3 in keys:
				var here := path + _key_name(k3) + "."
				if not da.has(k3):
					return "%s missing on left" % here
				if not db.has(k3):
					return "%s missing on right" % here
				var nested := first_diff(da[k3], db[k3], here)
				if not nested.is_empty():
					return nested
			return ""
		TYPE_ARRAY:
			var aa: Array = a
			var bb: Array = b
			if aa.size() != bb.size():
				return "%s length %d vs %d" % [path, aa.size(), bb.size()]
			for i in aa.size():
				var nested_a := first_diff(aa[i], bb[i], "%s[%d]." % [path, i])
				if not nested_a.is_empty():
					return nested_a
			return ""
		_:
			if a != b:
				return "%s %s vs %s" % [path, str(a), str(b)]
			return ""


static func _strip(data: Dictionary) -> Dictionary:
	var d: Dictionary = data.duplicate(true)
	for sec in _VOLATILE_SECTIONS:
		d.erase(sec)
	if d.get("metadata") is Dictionary:
		var meta: Dictionary = d["metadata"]
		for k in _VOLATILE_META:
			meta.erase(k)
		d["metadata"] = meta
	# Load always pauses the clock after restore. Pause is player control,
	# not world identity, so a forced pause does not change the hash.
	if d.get("time") is Dictionary:
		var time_block: Dictionary = d["time"]
		time_block.erase("paused")
		d["time"] = time_block
	_strip_timing(d)
	return d


static func _strip_timing(v: Variant) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		for key in _VOLATILE_TIMING_KEYS:
			d.erase(key)
		for child in d.values():
			_strip_timing(child)
	elif v is Array:
		for item in v:
			_strip_timing(item)


static func _enc(v: Variant) -> PackedByteArray:
	v = _norm(v)
	var out := PackedByteArray()
	var t := typeof(v)
	out.append(t)
	match t:
		TYPE_NIL:
			return out
		TYPE_BOOL:
			out.append(1 if bool(v) else 0)
			return out
		TYPE_INT:
			var ib := PackedByteArray()
			ib.resize(8)
			ib.encode_s64(0, int(v))
			out.append_array(ib)
			return out
		TYPE_FLOAT:
			var fb := PackedByteArray()
			fb.resize(8)
			fb.encode_double(0, _round_sim(float(v)))
			out.append_array(fb)
			return out
		TYPE_STRING:
			return _enc_bytes(out, str(v).to_utf8_buffer())
		TYPE_DICTIONARY:
			var d: Dictionary = _norm_dict(v)
			var keys: Array = d.keys()
			keys.sort_custom(_key_less)
			out.append_array(_u32(keys.size()))
			for k in keys:
				out.append_array(_enc(k))
				out.append_array(_enc(d[k]))
			return out
		TYPE_ARRAY:
			var a: Array = v
			out.append_array(_u32(a.size()))
			for item in a:
				out.append_array(_enc(item))
			return out
		_:
			return _enc_bytes(out, str(v).to_utf8_buffer())


static func _enc_bytes(out: PackedByteArray, payload: PackedByteArray) -> PackedByteArray:
	out.append_array(_u32(payload.size()))
	out.append_array(payload)
	return out


static func _u32(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, n)
	return b


static func _key_less(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return typeof(a) < typeof(b)
	match typeof(a):
		TYPE_INT, TYPE_FLOAT:
			return float(a) < float(b)
		TYPE_STRING:
			return str(a) < str(b)
		TYPE_BOOL:
			return (not bool(a)) and bool(b)
		_:
			return str(a) < str(b)


static func _key_name(k: Variant) -> String:
	return "%s:%s" % [typeof(k), str(k)]
