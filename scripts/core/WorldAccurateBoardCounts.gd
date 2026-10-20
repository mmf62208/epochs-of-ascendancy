extends RefCounted

## Live world_accurate board size. Tests preload this instead of pinning
## 3536 / 3196, which went stale when later GAP slices appended provinces.

const BASE_PATH := "res://data/provinces_world_accurate/provinces_base.json"


static func rows() -> Array:
	if not FileAccess.file_exists(BASE_PATH):
		return []
	var f := FileAccess.open(BASE_PATH, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var provs: Variant = (parsed as Dictionary).get("provinces", [])
	if typeof(provs) != TYPE_ARRAY:
		return []
	return provs


static func province_count() -> int:
	return rows().size()


static func land_count() -> int:
	var n := 0
	for row_v in rows():
		if typeof(row_v) != TYPE_DICTIONARY:
			continue
		if str((row_v as Dictionary).get("domain", "")) == "land":
			n += 1
	return n
