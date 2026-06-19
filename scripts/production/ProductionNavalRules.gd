## Naval production geography: shipyards and naval lines require port access.
class_name ProductionNavalRules
extends RefCounted

const NAVAL_CATEGORIES: Array[String] = [
	"destroyer",
	"cruiser",
	"battleship",
	"carrier",
	"submarine",
	"frigate",
	"corvette",
	"patrol",
	"gunboat",
	"lpd",
	"lhd",
	"lph",
	"lha",
	"amphib",
	"auxiliary",
	"ship",
	"naval",
]

const NAVAL_VISUAL_ARCHETYPES: Array[String] = [
	"destroyer",
	"frigate",
	"cruiser",
	"battleship",
	"carrier",
	"submarine",
	"patrol",
	"gunboat",
	"transport",
	"lpd",
	"lhd",
	"lph",
	"lha",
	"amphib",
]


static func is_naval_category(category: String) -> bool:
	var c: String = category.strip_edges().to_lower()
	if c.is_empty():
		return false
	if c in NAVAL_CATEGORIES:
		return true
	return c.contains("ship") or c.contains("naval")


static func is_naval_template(template: UnitTemplate) -> bool:
	if template == null:
		return false
	var bt: String = template.base_type.strip_edges().to_lower()
	if bt in ["naval", "submarine"]:
		return true
	var arch: String = template.visual_archetype.strip_edges().to_lower()
	if not arch.is_empty():
		for token in NAVAL_VISUAL_ARCHETYPES:
			if arch == token or arch.contains(token):
				return true
		if arch.contains("carrier") or arch.contains("cruiser") or arch.contains("destroyer"):
			return true
	var id_lower := template.id.strip_edges().to_lower()
	if (
		"_dd" in id_lower
		or "_bb" in id_lower
		or "_cv" in id_lower
		or "_ca" in id_lower
		or "frigate" in id_lower
		or "destroyer" in id_lower
		or "battleship" in id_lower
		or "carrier" in id_lower
		or "submarine" in id_lower
		or "cruiser" in id_lower
	):
		return true
	return is_naval_category(ProductionCostCalculator.infer_category(template))


static func is_naval_design(design_id: String) -> bool:
	if design_id.is_empty() or GameData.design_data == null:
		return false
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	return is_naval_template(template)


static func factory_can_build_naval(factory: Factory) -> bool:
	if factory == null:
		return false
	return factory.factory_type == "shipyard"


static func province_allows_shipyard(province: Province) -> bool:
	return province != null and province.resolve_has_port()
