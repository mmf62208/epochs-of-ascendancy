# scripts/ui/UnitIconLibrary.gd
## Shared retrowave unit chip resolution for map counters + OOB / formation lists.
class_name UnitIconLibrary
extends RefCounted

const RW_DIR := "res://assets/graphics/units/retrowave/"


static func _load(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func icon_path(stem: String, px: int = 32) -> String:
	var s := stem.strip_edges().to_lower()
	if s.is_empty():
		return ""
	var p := "%s%s_%d.png" % [RW_DIR, s, px]
	if ResourceLoader.exists(p):
		return p
	if px != 64:
		var p64 := "%s%s_64.png" % [RW_DIR, s]
		if ResourceLoader.exists(p64):
			return p64
	return ""


static func icon_for_stem(stem: String, px: int = 32) -> Texture2D:
	return _load(icon_path(stem, px))


## Resolve a unit chip from type / category / archetype / design id keywords.
static func resolve_stem(
	formation_type: String = "",
	category: String = "",
	archetype: String = "",
	design_id: String = "",
) -> String:
	var hay := (
		"%s %s %s %s"
		% [formation_type, category, archetype, design_id]
	).to_lower()
	# Capital / major types first
	if "battleship" in hay or "bismarck" in hay or "king_george" in hay:
		return "battleship"
	if "carrier" in hay:
		return "carrier"
	if "submarine" in hay or "uboat" in hay or "u_boat" in hay or " sub" in hay:
		return "submarine"
	if "cruiser" in hay:
		return "cruiser"
	if "frigate" in hay:
		return "frigate"
	if "destroyer" in hay or "patrol" in hay:
		return "destroyer"
	if "amphib" in hay or "landing" in hay:
		return "amphib"
	# Pass 12/13: fort level / damage stems before generic fort
	if "fort_damaged" in hay or "ruined_fort" in hay or ("damaged" in hay and "fort" in hay):
		return "fort_damaged"
	if "fort_heavy" in hay or "citadel" in hay or "fortress" in hay:
		return "fort_heavy"
	if "fort_bunker" in hay or ("bunker" in hay and "fort" not in hay) or "field_bunker" in hay:
		return "fort_bunker"
	if "fort" in hay or "bunker" in hay or "coastal_fort" in hay:
		return "fort"
	if "port_damaged" in hay or ("damaged" in hay and "port" in hay) or "ruined_port" in hay:
		return "port_damaged"
	if "port_major" in hay or "major_port" in hay or "deepwater" in hay:
		return "port_major"
	if "port_jetty" in hay or "jetty" in hay or "minor_port" in hay:
		return "port_jetty"
	if "port" in hay or "harbor" in hay or "dock" in hay:
		return "port"
	# Pass 11/15: hangar / strip / damaged before generic airfield
	if "airfield_damaged" in hay or ("damaged" in hay and ("airfield" in hay or "airbase" in hay or "runway" in hay)):
		return "airfield_damaged"
	if "hangar" in hay or "airbase_major" in hay or "airfield_hangar" in hay:
		return "airfield_hangar"
	if "airstrip" in hay or "airfield_strip" in hay or "landing_strip" in hay:
		return "airfield_strip"
	if "airfield" in hay or "airbase" in hay or "runway" in hay or "airport" in hay:
		return "airfield"
	if "apc" in hay or "ifv" in hay or "armored_vehicle" in hay:
		return "apc"
	if "recon" in hay or "scout" in hay:
		return "recon"
	if "helicopter" in hay or "helo" in hay:
		return "helicopter"
	if "bomber" in hay:
		return "bomber"
	if "fighter" in hay or "plane" in hay or "air" in hay:
		return "fighter"
	if "heavy_tank" in hay or ("heavy" in hay and "tank" in hay):
		return "heavy_tank"
	if "light_tank" in hay or ("light" in hay and "tank" in hay):
		return "light_tank"
	if "medium_tank" in hay or "panzer" in hay or "sherman" in hay or "tiger" in hay or "t34" in hay or "tank" in hay or "armor" in hay:
		return "medium_tank"
	if "anti_air" in hay or "antiair" in hay or "aa_" in hay or " flak" in hay or "aa gun" in hay or hay.begins_with("aa") or " aaa" in hay or "sam_" in hay:
		return "aa"
	if "anti_tank" in hay or "antitank" in hay or "at_" in hay or " at gun" in hay or "pak" in hay or "tank_destroyer" in hay or "td_" in hay:
		return "at"
	if "rocket" in hay or "mlrs" in hay:
		return "rocket"
	if "artillery" in hay or "howitzer" in hay:
		return "artillery"
	# Pass 9: convoy sealane / merchant escort chips
	if "convoy" in hay or "sealane" in hay or "merchant" in hay or "armed_merchant" in hay:
		return "convoy"
	if "logistics" in hay or "truck" in hay or "transport" in hay:
		return "logistics"
	if "naval" in hay or "ship" in hay:
		return "destroyer"
	if "infantry" in hay or "division" in hay or "garrison" in hay or "land" in hay:
		return "infantry"
	return "infantry"


static func icon_for_formation_dict(formation: Dictionary, px: int = 32) -> Texture2D:
	var stem := resolve_stem(
		str(formation.get("type", "")),
		str(formation.get("category", "")),
		str(formation.get("visual_archetype", formation.get("archetype", ""))),
		str(formation.get("design_id", formation.get("formation_id", ""))),
	)
	return icon_for_stem(stem, px)


static func icon_for_keywords(haystack: String, px: int = 32) -> Texture2D:
	return icon_for_stem(resolve_stem(haystack, "", "", ""), px)


static func icon_for_design_id(design_id: String, px: int = 32) -> Texture2D:
	var did := design_id.strip_edges()
	var arch := ""
	var domain := ""
	if not did.is_empty() and typeof(GameData) != TYPE_NIL and GameData.design_data != null:
		var tpl = GameData.design_data.get_template(did)
		if tpl != null:
			if "visual_archetype" in tpl:
				arch = str(tpl.visual_archetype)
			if "design_domain" in tpl:
				domain = str(tpl.design_domain)
			elif "domain" in tpl:
				domain = str(tpl.domain)
	return icon_for_stem(resolve_stem(domain, domain, arch, did), px)
