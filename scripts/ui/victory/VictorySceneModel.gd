# scripts/ui/victory/VictorySceneModel.gd
## Pure mapper for the victory / defeat scenes. Reads public state and
## res:// data only. No RNG, no save writes, no owner-index rebuild.
class_name VictorySceneModel
extends RefCounted

const DATA_PATH := "res://data/campaign/victory_scene.json"
const CLOTH_AREA := 86400.0
const SEA_ID := 950000

static var _table: Dictionary = {}
static var _table_loaded: bool = false
static var _owners_cache: Dictionary = {}
static var _data_dir: String = ""
static var _px: Texture2D
static var _cpu_pool: Array = []
static var _cpu_holder: Node = null
static var _cpu_warm: bool = false


static func scene_enabled() -> bool:
	return OS.get_environment("EOA_VICTORY_SCENE") != "0"


static func load_table() -> Dictionary:
	if _table_loaded:
		return _table
	_table_loaded = true
	_table = {}
	if not FileAccess.file_exists(DATA_PATH):
		return _table
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if parsed is Dictionary:
		_table = parsed
	return _table


static func res_exists(path: String) -> bool:
	if path.is_empty():
		return false
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)


static func backdrop_kind(path: String) -> String:
	if OS.get_environment("EOA_VICTORY_SCENE_MISS_SKY") == "1":
		return "procedural"
	if path.is_empty() or not res_exists(path):
		return "procedural"
	return "texture"


static func fallback_texture() -> Texture2D:
	if _px != null:
		return _px
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.10, 0.16, 1.0))
	_px = ImageTexture.create_from_image(img)
	return _px


static func template_key(source: String, outcome: String, reason: String, detail: Dictionary = {}) -> Dictionary:
	# CPUParticles2D's constructor calls Math::rand(). Warm the pool on the
	# first mapper call so a later defeat open does not move the global RNG.
	warm_cpu_particles()
	var src := source.strip_edges().to_lower()
	var outc := outcome.strip_edges().to_lower()
	var why := reason.strip_edges()
	var path_id := str(detail.get("path_id", "")).strip_edges().to_lower()
	var kind := str(detail.get("kind", "")).strip_edges().to_lower()
	if kind.is_empty():
		kind = why.to_lower()
	var info := {
		"template": "SHEET",
		"mode": "",
		"headline_key": "",
		"restrained": false,
		"fallback": "",
	}
	if src == "cl1":
		return _cl1_key(outc, kind, info)
	if src == "vp" or not path_id.is_empty():
		return _vp_key(outc, path_id, info)
	if outc == "loss" or outc == "defeat" or src == "gamedata":
		info["template"] = "DEFEAT"
		info["mode"] = "burning"
		info["headline_key"] = "capitulation"
		return info
	return _ink_win_key(why, info)


static func build(source: String, outcome: String, tag: String, reason: String, detail: Dictionary = {}) -> Dictionary:
	var info := template_key(source, outcome, reason, detail)
	var t := tag.strip_edges().to_upper()
	var table := load_table()
	var bucket := "loss" if str(info.get("template", "")) == "DEFEAT" else "win"
	var headline := lookup_headline(table, bucket, t, str(info.get("headline_key", "")))
	var row := nation_row(table, t)
	var vars := _fill_vars(t, row, detail)
	var filled_head := fill(str(headline.get("headline", "")), vars)
	var filled_sub := fill(str(headline.get("sub", "")), vars)
	var filled_eye := fill(str(headline.get("eyebrow", "")), vars)
	return {
		"template": str(info.get("template", "SHEET")),
		"mode": str(info.get("mode", "")),
		"headline_key": str(info.get("headline_key", "")),
		"restrained": bool(info.get("restrained", false)),
		"fallback": str(headline.get("fallback", info.get("fallback", ""))),
		"eyebrow": filled_eye,
		"headline": filled_head,
		"sub": filled_sub,
		"vars": vars,
		"recap_rows": _recap(t, str(info.get("headline_key", "")), str(info.get("template", "")), detail),
		"assets": _resolve_assets(table, t, row, str(info.get("template", "")), str(info.get("mode", ""))),
		"tag": t,
		"source": source,
		"outcome": outcome,
	}


static func lookup_headline(table: Dictionary, outcome: String, tag: String, key: String) -> Dictionary:
	var bucket := "win"
	var o := outcome.strip_edges().to_lower()
	if o == "loss" or o == "defeat" or o == "defeated":
		bucket = "loss"
	var headlines: Dictionary = _dict(table.get("headlines", {}))
	var side: Dictionary = _dict(headlines.get(bucket, {}))
	var tag_block: Dictionary = _dict(side.get(tag.strip_edges().to_upper(), {}))
	var def_block: Dictionary = _dict(side.get("_default", {}))
	var primary := _headline_entry(tag_block, key)
	if primary.is_empty():
		primary = _headline_entry(def_block, key)
	var fallback_key := str(primary.get("fallback", "")).strip_edges()
	var base: Dictionary = {}
	if not fallback_key.is_empty():
		base = _headline_entry(tag_block, fallback_key)
		if base.is_empty():
			base = _headline_entry(def_block, fallback_key)
	var merged := base.duplicate(true)
	for k in primary.keys():
		if str(k) == "fallback":
			continue
		if str(primary[k]).strip_edges().is_empty():
			continue
		merged[k] = primary[k]
	if not fallback_key.is_empty():
		merged["fallback"] = fallback_key
	var hard := "VICTORY" if bucket == "win" else "DEFEAT"
	if str(merged.get("headline", "")).strip_edges().is_empty():
		merged["headline"] = hard
	if str(merged.get("eyebrow", "")).strip_edges().is_empty():
		merged["eyebrow"] = hard
	if not merged.has("sub"):
		merged["sub"] = ""
	return merged


static func nation_row(table: Dictionary, tag: String) -> Dictionary:
	var nations := _dict(table.get("nations", {}))
	var row := _dict(nations.get(tag.strip_edges().to_upper(), {})).duplicate(true)
	var base := _dict(nations.get("_default", {}))
	for k in base.keys():
		if not row.has(k):
			row[k] = base[k]
	return row


static func resolve_flag(table: Dictionary, tag: String) -> Dictionary:
	var t := tag.strip_edges().to_upper()
	var row := nation_row(table, t)
	var generic := "res://assets/graphics/flags/generic.png"
	var chosen := ""
	var from_table := str(row.get("flag", ""))
	if res_exists(from_table):
		chosen = from_table
	else:
		var by_tag := "res://assets/graphics/flags/%s.png" % t.to_lower()
		if res_exists(by_tag):
			chosen = by_tag
		elif res_exists(generic):
			chosen = generic
	var is_generic := chosen.ends_with("/generic.png")
	var tint_mix := 0.0
	var apply := 0.0
	var col := Color(0.5, 0.5, 0.6, 0.9)
	if is_generic:
		tint_mix = float(row.get("tint_with_nation_colour", 0.35))
		if tint_mix <= 0.0:
			tint_mix = 0.35
		col = _country_color(t)
		apply = 0.0 if _is_stub_color(col) else 1.0
	var ratio := float(row.get("flag_ratio", 1.5))
	if ratio < 0.2:
		ratio = 1.5
	var cloth_w := sqrt(CLOTH_AREA * ratio)
	var cloth_h := cloth_w / ratio
	var shared := _dict(table.get("shared", {}))
	var mask := str(shared.get("field_mask", "res://assets/graphics/flags/generic_field_mask.png"))
	var use_mask := 1.0 if res_exists(mask) else 0.0
	return {
		"path": chosen,
		"tint_mix": tint_mix,
		"apply_tint": apply,
		"nation_colour": col,
		"use_mask": use_mask,
		"mask": mask if use_mask > 0.5 else "",
		"cloth_w": cloth_w,
		"cloth_h": cloth_h,
		"ratio": ratio,
		"generic": is_generic,
	}


static func provinces_at_start(tag: String) -> Dictionary:
	var t := tag.strip_edges().to_upper()
	var snap := _snapshot_owned(t)
	if bool(snap.get("found", false)):
		return {"count": int(snap.get("count", 0)), "source": "snapshot"}
	var from_file := _scenario_count(t)
	if from_file >= 0:
		return {"count": from_file, "source": "scenario"}
	return {"count": int(live_held(t).get("held", 0)), "source": "now"}


static func warm_cpu_particles() -> void:
	if _cpu_warm:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_cpu_warm = true
	_cpu_holder = Node.new()
	_cpu_holder.name = "Vs1CpuParticlePool"
	tree.root.add_child(_cpu_holder)
	for _i in 32:
		var cpu := CPUParticles2D.new()
		cpu.use_fixed_seed = true
		cpu.one_shot = false
		cpu.emitting = false
		_cpu_holder.add_child(cpu)
		_cpu_pool.append(cpu)


static func acquire_cpu_particle() -> CPUParticles2D:
	warm_cpu_particles()
	var cpu: CPUParticles2D
	if _cpu_pool.is_empty():
		cpu = CPUParticles2D.new()
		cpu.use_fixed_seed = true
		cpu.one_shot = false
		cpu.emitting = false
	else:
		cpu = _cpu_pool.pop_back() as CPUParticles2D
	cpu.emitting = false
	if cpu.get_parent() != null:
		cpu.get_parent().remove_child(cpu)
	return cpu


static func release_cpu_particle(cpu: CPUParticles2D) -> void:
	if cpu == null or not is_instance_valid(cpu):
		return
	cpu.emitting = false
	if cpu.get_parent() != null:
		cpu.get_parent().remove_child(cpu)
	if _cpu_holder != null and is_instance_valid(_cpu_holder):
		_cpu_holder.add_child(cpu)
	if not _cpu_pool.has(cpu):
		_cpu_pool.append(cpu)


static func reclaim_dying_cpu_particles() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var found: Array = []
	_collect_dying_cpu(tree.root, found)
	for item in found:
		release_cpu_particle(item as CPUParticles2D)


static func _collect_dying_cpu(n: Node, found: Array) -> void:
	if n == null or n == _cpu_holder:
		return
	if n is CPUParticles2D and _node_dying(n):
		found.append(n)
		return
	for c in n.get_children():
		_collect_dying_cpu(c, found)


static func _node_dying(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


static func _node(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(autoload_name)


static func live_held(tag: String) -> Dictionary:
	var held := 0
	var points := 0
	var t := tag.strip_edges().to_upper()
	var map := _node("MapManager")
	if t.is_empty() or map == null or not map.has_method("get_all_provinces"):
		return {"held": 0, "vp": 0}
	var provinces: Dictionary = map.call("get_all_provinces")
	for pid in provinces.keys():
		var prov: Variant = provinces[pid]
		if prov == null:
			continue
		if "is_sea" in prov and bool(prov.is_sea):
			continue
		var ctrl := ""
		if "controller_tag" in prov:
			ctrl = str(prov.controller_tag).strip_edges().to_upper()
		if ctrl != t:
			continue
		held += 1
		points += int(prov.victory_points) if "victory_points" in prov else 0
	return {"held": held, "vp": points}


static func fill(template: String, vars: Dictionary) -> String:
	var out := template
	for k in vars.keys():
		out = out.replace("{%s}" % str(k), str(vars[k]))
	return out


static func _cl1_key(outc: String, kind: String, info: Dictionary) -> Dictionary:
	if outc == "neutral" or outc == "observer":
		return info
	if kind == "decisive":
		info["template"] = "WIN"
		info["headline_key"] = "conquest"
		return info
	if kind == "time":
		if outc == "victory":
			info["template"] = "WIN"
			info["headline_key"] = "ascendant"
			info["fallback"] = "score"
			return info
		info["template"] = "DEFEAT"
		info["mode"] = "eclipsed"
		info["headline_key"] = "eclipsed"
		return info
	if kind == "defeat" or outc == "defeat":
		info["template"] = "DEFEAT"
		info["mode"] = "burning"
		info["headline_key"] = "capitulation"
		return info
	return info


static func _vp_key(outc: String, path_id: String, info: Dictionary) -> Dictionary:
	if outc == "loss" or outc == "defeat":
		info["template"] = "DEFEAT"
		info["mode"] = "burning"
		info["headline_key"] = "rival_path"
		return info
	var key := path_id
	if key != "conquest" and key != "atomic" and key != "arsenal" and key != "score":
		key = "score"
	info["template"] = "WIN"
	info["headline_key"] = key
	return info


static func _ink_win_key(why: String, info: Dictionary) -> Dictionary:
	if why.find("enemy_capitals") >= 0:
		info["template"] = "WIN"
		info["headline_key"] = "enemy_capitals"
		info["fallback"] = "conquest"
		return info
	if _only_reason(why, "end_date"):
		info["template"] = "WIN"
		info["headline_key"] = "endured"
		info["restrained"] = true
		return info
	info["template"] = "WIN"
	info["headline_key"] = "score"
	if not why.strip_edges().is_empty():
		print("VictorySceneModel: unknown win reason '%s' mapped to score" % why)
	return info


static func _only_reason(raw: String, code: String) -> bool:
	var saw := false
	for part in raw.split(","):
		var c := part.strip_edges()
		if c.is_empty():
			continue
		if c != code:
			return false
		saw = true
	return saw


static func _headline_entry(block: Dictionary, key: String) -> Dictionary:
	if key.is_empty() or not (block.get(key) is Dictionary):
		return {}
	return (block[key] as Dictionary).duplicate(true)


static func _fill_vars(tag: String, row: Dictionary, detail: Dictionary) -> Dictionary:
	var name := _tag_name(tag)
	var adj := str(row.get("adj", "")).strip_edges()
	if adj.is_empty():
		adj = name
	var winner_tag := str(detail.get("winner", "")).strip_edges().to_upper()
	var winner_name := _tag_name(winner_tag) if not winner_tag.is_empty() else ""
	var title := str(detail.get("path_title", detail.get("title", "")))
	var rank_n := int(detail.get("rank", 0))
	var date := _today_label()
	return {
		"NAME": name.to_upper(),
		"name": name,
		"ADJ": adj.to_upper(),
		"adj": adj,
		"WINNER": winner_name.to_upper() if not winner_name.is_empty() else winner_tag,
		"winner": winner_name if not winner_name.is_empty() else winner_tag.to_lower(),
		"TITLE": title.to_upper(),
		"title": title,
		"held": int(detail.get("held", 0)),
		"total": int(detail.get("total", 0)),
		"pct": int(detail.get("pct", 0)),
		"rank": _ordinal(rank_n),
		"date": date,
		"CAPITAL": str(row.get("capital_display", "")),
	}


static func _recap(tag: String, key: String, template: String, detail: Dictionary) -> Array:
	var days := 0
	var clock := _node("TimeManager")
	if clock != null and "total_days_elapsed" in clock:
		days = int(clock.total_days_elapsed)
	var start: Dictionary = provinces_at_start(tag)
	var live: Dictionary = live_held(tag)
	var year := 1936
	if clock != null and "scenario_start_year" in clock:
		year = int(clock.scenario_start_year)
	var rows: Array = []
	if template == "DEFEAT" and key == "capitulation":
		rows.append({"label": "FALLEN", "value": _today_label()})
	elif key == "rival_path":
		rows.append({"label": "WINNER", "value": str(detail.get("winner", ""))})
	else:
		rows.append({"label": "DAYS", "value": str(days)})
	rows.append({
		"label": "PROVINCES",
		"value": "%d → %d" % [int(start.get("count", 0)), int(live.get("held", 0))],
		"note": "%d → now" % year,
	})
	rows.append({"label": "NATIONS DEFEATED", "value": str(_nations_defeated(tag))})
	rows.append(_fourth(tag, key, detail, live))
	return rows


static func _fourth(tag: String, key: String, detail: Dictionary, live: Dictionary) -> Dictionary:
	if key == "conquest" or key == "enemy_capitals":
		var held := int(detail.get("held", 0))
		var total := int(detail.get("total", 0))
		var value := "%d / %d" % [held, total] if total > 0 else str(held)
		return {"label": "CAPITALS", "value": value}
	if key == "atomic":
		return {"label": "HOLD", "value": str(int(detail.get("hold", 0)))}
	if key == "arsenal" or key == "ascendant" or key == "eclipsed":
		var share := 0.0
		var end_dom := load("res://scripts/core/CampaignEndDomain.gd") as GDScript
		if end_dom != null and end_dom.has_method("factory_share"):
			share = float(end_dom.call("factory_share", tag))
		return {"label": "INDUSTRY", "value": "%.1f%%" % (share * 100.0)}
	if key == "score":
		return {"label": "SCORE", "value": str(detail.get("score", "0"))}
	if key == "rival_path" or key == "capitulation":
		var clock := _node("TimeManager")
		var days := int(clock.total_days_elapsed) if clock != null and "total_days_elapsed" in clock else 0
		return {"label": "DAYS", "value": str(days)}
	return {"label": "VICTORY POINTS", "value": str(int(live.get("vp", 0)))}


static func _resolve_assets(table: Dictionary, tag: String, row: Dictionary, template: String, mode: String) -> Dictionary:
	var sky_path := str(row.get("skyline", ""))
	var kind := backdrop_kind(sky_path)
	if kind == "procedural":
		var fallback := str(nation_row(table, "_default").get("skyline", ""))
		if OS.get_environment("EOA_VICTORY_SCENE_MISS_SKY") != "1" and backdrop_kind(fallback) == "texture":
			sky_path = fallback
			kind = "texture"
	var roof := str(row.get("roof", ""))
	if not res_exists(roof):
		roof = ""
	var shared := _dict(table.get("shared", {}))
	var ruin := 0.0
	if template == "DEFEAT" and mode == "eclipsed":
		ruin = 0.15
	elif template == "DEFEAT":
		ruin = 1.0
	return {
		"flag": resolve_flag(table, tag),
		"skyline": sky_path,
		"backdrop": kind,
		"roof": roof,
		"shared": shared,
		"fire_points": row.get("fire_points", []),
		"ruin": ruin,
		"palette": _palette(template, mode),
	}


static func _palette(template: String, mode: String) -> Dictionary:
	if template == "DEFEAT" and mode == "eclipsed":
		return {
			"far": Color(120.0 / 255.0, 94.0 / 255.0, 114.0 / 255.0),
			"mid": Color(22.0 / 255.0, 24.0 / 255.0, 44.0 / 255.0),
			"rim": Color(255.0 / 255.0, 206.0 / 255.0, 128.0 / 255.0),
		}
	if template == "DEFEAT":
		return {
			"far": Color(104.0 / 255.0, 96.0 / 255.0, 102.0 / 255.0),
			"mid": Color(26.0 / 255.0, 24.0 / 255.0, 30.0 / 255.0),
			"rim": Color(255.0 / 255.0, 130.0 / 255.0, 60.0 / 255.0),
		}
	return {
		"far": Color(214.0 / 255.0, 156.0 / 255.0, 140.0 / 255.0),
		"mid": Color(38.0 / 255.0, 38.0 / 255.0, 66.0 / 255.0),
		"rim": Color(255.0 / 255.0, 206.0 / 255.0, 128.0 / 255.0),
	}


static func _snapshot_owned(tag: String) -> Dictionary:
	var gd := _node("GameData")
	if gd == null or not ("peace_state" in gd):
		return {"found": false}
	var cap: Variant = gd.peace_state.get("campaign_capitulation", {})
	if not (cap is Dictionary):
		return {"found": false}
	if not bool((cap as Dictionary).get("snapshotted", false)):
		return {"found": false}
	var owned: Variant = (cap as Dictionary).get("start_owned", {})
	if not (owned is Dictionary):
		return {"found": true, "count": 0}
	var row: Variant = (owned as Dictionary).get(tag, [])
	if row is Array:
		return {"found": true, "count": (row as Array).size()}
	return {"found": true, "count": 0}


static func _scenario_count(tag: String) -> int:
	var data_dir := _province_data_dir()
	var year := _era_year(data_dir)
	var path := "res://data/%s/province_ownership_%d.json" % [data_dir, year]
	var owners := _load_owners(path)
	if owners.is_empty() and not FileAccess.file_exists(path):
		return -1
	var n := 0
	for k in owners.keys():
		var pid := int(str(k))
		if _is_sea_id(pid):
			continue
		if str(owners[k]).strip_edges().to_upper() == tag:
			n += 1
	return n


static func _load_owners(path: String) -> Dictionary:
	if _owners_cache.has(path):
		return _owners_cache[path]
	if not FileAccess.file_exists(path):
		_owners_cache[path] = {}
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var owners: Dictionary = {}
	if parsed is Dictionary:
		var raw: Variant = (parsed as Dictionary).get("owners", {})
		if raw is Dictionary:
			owners = raw
	_owners_cache[path] = owners
	return owners


static func _province_data_dir() -> String:
	if not _data_dir.is_empty():
		return _data_dir
	var scen := OS.get_environment("EOA_SCENARIO").strip_edges()
	if scen.is_empty():
		scen = "world_accurate"
	var path := "res://data/scenarios/%s.json" % scen
	var dir := "provinces_world_accurate"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			var got := str((parsed as Dictionary).get("use_province_data_dir", "")).strip_edges()
			if not got.is_empty():
				dir = got
	_data_dir = dir
	return dir


static func _era_year(data_dir: String) -> int:
	var y := 1936
	var clock := _node("TimeManager")
	if clock != null and "scenario_start_year" in clock:
		y = int(clock.scenario_start_year)
	var eras: Array = [1910, 1918, 1936, 1945, 2026]
	var chosen := 1910
	for e in eras:
		if int(e) <= y:
			chosen = int(e)
	var path := "res://data/%s/province_ownership_%d.json" % [data_dir, chosen]
	if FileAccess.file_exists(path):
		return chosen
	for e2 in [2026, 1945, 1936, 1918, 1910]:
		path = "res://data/%s/province_ownership_%d.json" % [data_dir, int(e2)]
		if FileAccess.file_exists(path):
			return int(e2)
	return 1936


static func _is_sea_id(pid: int) -> bool:
	if pid >= SEA_ID:
		return true
	var map := _node("MapManager")
	if map == null or not map.has_method("get_province"):
		return false
	if map.has_method("has_province_data") and not bool(map.call("has_province_data")):
		return false
	var prov: Variant = map.call("get_province", pid)
	if prov == null or not ("is_sea" in prov):
		return false
	return bool(prov.is_sea)


static func _nations_defeated(tag: String) -> int:
	var gd := _node("GameData")
	if gd == null or not ("peace_state" in gd):
		return 0
	var cap: Variant = gd.peace_state.get("campaign_capitulation", {})
	if not (cap is Dictionary):
		return 0
	var caps: Variant = (cap as Dictionary).get("capitulated", {})
	if not (caps is Dictionary):
		return 0
	var n := 0
	for k in (caps as Dictionary).keys():
		var row: Variant = (caps as Dictionary)[k]
		if not (row is Dictionary):
			continue
		var enemies: Variant = (row as Dictionary).get("enemies", [])
		if not (enemies is Array):
			continue
		for e in enemies:
			if str(e).strip_edges().to_upper() == tag:
				n += 1
				break
	return n


static func _country_color(tag: String) -> Color:
	var map := _node("MapManager")
	if map != null and map.has_method("get_country_color"):
		return map.call("get_country_color", tag)
	return Color(0.5, 0.5, 0.6, 0.9)


static func _is_stub_color(c: Color) -> bool:
	return _near_rgb(c, Color(0.45, 0.55, 0.65)) or _near_rgb(c, Color(0.5, 0.5, 0.6))


static func _near_rgb(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


static func _tag_name(tag: String) -> String:
	if tag.is_empty():
		return ""
	# load() at call time. A class_name reference here is compiled before autoloads
	# exist when the headless test is the entry script, and that poisons the domain.
	var war := load("res://scripts/core/WarStateDomain.gd") as GDScript
	if war != null and war.has_method("tag_name"):
		var named := str(war.call("tag_name", tag)).strip_edges()
		if not named.is_empty():
			return named
	return tag


static func _today_label() -> String:
	var end_dom := load("res://scripts/core/CampaignEndDomain.gd") as GDScript
	if end_dom != null and end_dom.has_method("format_end_date") and end_dom.has_method("date_string"):
		return str(end_dom.call("format_end_date", end_dom.call("date_string")))
	var clock := _node("TimeManager")
	if clock == null:
		return ""
	return "%04d-%02d-%02d" % [int(clock.current_year), int(clock.current_month), int(clock.current_day)]


static func _ordinal(n: int) -> String:
	if n <= 0:
		return ""
	var teen := n % 100
	if teen >= 11 and teen <= 13:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
		_:
			return "%dth" % n


static func _dict(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return raw
	return {}
