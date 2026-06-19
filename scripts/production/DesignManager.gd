# scripts/production/DesignManager.gd
## Per-country design lifecycle for production UI (active / previously used / obsolete).
## Modules inherit parent design status; no separate module obsolescence.
##
## Map Build Eligibility integration (Phase 1):
##   _eligible_design_ids and get_tech_eligible_design_ids now filter by technology
##   (via _is_tech_buildable + TechnologyManager gates).
##   Map callers should use MapTechnologyContext.is_design_buildable_in_province()
##   for the full province + controller context + future extensions (dev level, terrain, etc.).
##
## Nation-Specific Designs + Runtime Acquisition (Trade / Capture foundation)
##
## Data-driven ownership:
##   - UnitTemplate / design JSON can specify "owner_countries": ["GER", "FRA"] (or empty/"all" for universal/exportable).
##   - "exportable": true for future trade/licensing.
##
## Acquisition (grant_acquired_design is the SINGLE SOURCE OF TRUTH):
##   - grant_acquired_design(country_tag, design_id, kind = "captured" | "purchased" | "licensed")
##     This is the only method future systems should call:
##       • Capture on conquest (see FactoryManager.capture_province_factories)
##       • Espionage / agent missions (technology theft, prototype capture)
##       • Trade deals, licensing agreements, black market, war reparations, events
##   - Internally writes to the primary _acquired_designs[country][design_id] = kind
##   - Also maintains a legacy _acquired_foreign_designs shim (for backward compat during transition).
##   - has_acquired_design / _country_may_use_design / is_design_foreign_for now treat the grant path as authoritative.
##
## Picker / Production integration:
##   - _country_may_use_design + _catalog_design_ids + _buildable_design_ids filter the catalog.
##   - Foreign acquired designs appear in DesignPickerPopup under the "foreign" buckets (Active / Previously Used / Obsolete)
##     with proper icons (⚔ Captured, 💰 Purchased, 📜 Licensed) + source nation badges.
##   - format_origin_badge / format_origin_tooltip / acquisition_* helpers provide rich UI text.
##
## Conquest flow (current implementation):
##   1. MapManager.update_province_owner or combat logic changes province owner.
##   2. FactoryManager.capture_province_factories(province_id, new_owner) is called for the territory.
##   3. For each factory, we inspect current_production_design + previous_design.
##   4. Any foreign design the factory was actively producing is granted via grant_acquired_design(..., ACQUISITION_CAPTURED).
##   5. A lightweight toast is shown ("⚔ New design acquired: Panzer IV (Captured from GER)").
##   6. Next time the player opens the DesignPicker, the design appears in the Foreign Acquired section and can be produced (subject to tech + factory compatibility).
##
## Extension points for future sessions:
##   - Trade UI / black market: call grant_acquired_design(..., ACQUISITION_PURCHASED)
##   - Licensing deals / tech sharing: ACQUISITION_LICENSED
##   - Agent "Technology Theft" or "Prototype Capture" missions: direct call to grant_acquired_design
##   - War reparations / peace deals: batch grants
##   - Province trade / intelligence sharing: same API
##
## Save/load:
##   Primary key is "acquired_designs". Legacy "acquired_foreign_designs" is migrated on load.
##   mark_design_acquired is legacy (kept for now); new code should use grant_acquired_design.
extends Node

enum DesignStatus {
	ACTIVE,
	PREVIOUSLY_USED,
	OBSOLETE,
}

# Design Doctrines (hybrid Option 1+2 from assessment): ... (see full above, but placed here for syntax)
const DESIGN_DOCTRINES = {
	"rugged_redundancy": {
		"name": "Rugged Redundancy (P-47 style)",
		"description": "Extra tough with backups. +Durability/reliability vs damage. Higher weight/cost/time. Memorable 'tough' designs that survive hits.",
		"stat_mods": {"reliability": 1.2, "durability": 1.3, "weight": 1.15, "cost": 1.1, "production_time": 1.2},
		"module_tags": ["redundancy", "rugged_armor"],
		"real_world": "P-47 Thunderbolt: armored, redundant systems, survived heavy flak."
	},
	"lightweight_performance": {
		"name": "Lightweight Performance (Zero style)",
		"description": "Minimal structure for max speed/agility/range. Low cost/weight but low durability (fragile, no armor). High risk.",
		"stat_mods": {"speed": 1.25, "agility": 1.2, "weight": 0.85, "cost": 0.9, "durability": 0.7, "reliability": 0.9},
		"module_tags": ["lightweight", "high_performance"],
		"real_world": "Mitsubishi A6M Zero: exceptional maneuverability and range, but no pilot armor or self-sealing tanks."
	},
	"compartmentalized_survivability": {
		"name": "Compartmentalized Survivability (Ship style)",
		"description": "Internal compartments, damage control, fire suppression. +Survivability (less likely to sink/crit from hit/fire). +Weight/complexity. Ideal for capital ships and carriers.",
		"stat_mods": {"survivability": 1.4, "fire_resist": 1.3, "weight": 1.1, "cost": 1.05, "production_time": 1.15},
		"module_tags": ["compartment", "damage_control", "fire_suppression", "hull_reinforcement"],
		"real_world": "WWII BB/CV: watertight bulkheads, counter-flooding. +50%+ chance to survive torpedo hit without catastrophic loss."
	}
}

const OBSOLETE_AGE_YEARS := 30

const DOMAIN_ALL := "all"
const DOMAIN_LAND := "land"
const DOMAIN_NAVAL := "naval"
const DOMAIN_AIR := "air"
const DOMAIN_SPACE := "space"
const DOMAIN_SUPPORT := "support"

const DOMAIN_FILTER_LABELS: PackedStringArray = [
	"All",
	"Land",
	"Naval",
	"Air",
	"Space",
	"Support",
]

const DOMAIN_FILTER_DISPLAY: PackedStringArray = [
	"◇ All",
	"🚜 Land",
	"⚓ Naval",
	"✈ Air",
	"🛰 Space",
	"🔧 Support",
]

enum DesignOwnership {
	DOMESTIC,
	FOREIGN_ACQUIRED,
	UNIVERSAL,
}

const ACQUISITION_CAPTURED := "captured"
const ACQUISITION_PURCHASED := "purchased"
const ACQUISITION_LICENSED := "licensed"

## country_tag (upper) -> design_id -> acquisition kind (captured / purchased / licensed)
var _acquired_designs: Dictionary = {}

const SPACE_VISUAL_ARCHETYPES: Array[String] = [
	"satellite",
	"space_station",
	"spacecraft",
	"launch_vehicle",
	"orbital_vehicle",
	"crew_vehicle",
	"super_heavy",
]

const SPACE_ICON_MAP: Dictionary = {
	"satellite": "res://assets/graphics/icons/space/satellite_recon.png",
	"space_station": "res://assets/graphics/icons/space/space_station_hab.png",
	"spacecraft": "res://assets/graphics/icons/space/ship_expanse.png",
	"corvette": "res://assets/graphics/icons/space/ship_corvette.png",
	"carrier": "res://assets/graphics/icons/space/ship_carrier.png",
	"cruiser": "res://assets/graphics/icons/space/ship_cruiser.png",
	"destroyer": "res://assets/graphics/icons/space/ship_destroyer.png",
}
func get_space_icon_for_template(template: UnitTemplate, design_id: String = "") -> String:
	var arch := str(template.visual_archetype if template else "").to_lower()
	if arch in SPACE_ICON_MAP:
		return SPACE_ICON_MAP[arch]
	for key in SPACE_ICON_MAP:
		if key in design_id.to_lower() or key in arch:
			return SPACE_ICON_MAP[key]
	# fallback new icons
	if "sat" in design_id.to_lower() or "gps" in design_id.to_lower() or "starlink" in design_id.to_lower():
		return "res://assets/graphics/icons/space/satellite_comms.png"
	if "station" in design_id.to_lower() or "mir" in design_id.to_lower():
		return "res://assets/graphics/icons/space/space_station_shipyard.png"
	return "res://assets/graphics/icons/space/ship_corvette.png"

## country_tag (upper) -> design_id -> true
var _used_designs: Dictionary = {}

## country_tag -> design_id -> last_used_year
var _last_used_year: Dictionary = {}

## Nation-specific designs: designs a country has acquired (via capture, purchase, etc.)
## country_tag -> design_id -> true
var _acquired_foreign_designs: Dictionary = {}


func _ready() -> void:
	if typeof(TimeManager) != TYPE_NIL:
		if not TimeManager.game_year_advanced.is_connected(_on_game_year_advanced):
			TimeManager.game_year_advanced.connect(_on_game_year_advanced)


func _on_game_year_advanced(_year: int) -> void:
	# Classification is recomputed on demand; yearly hook reserved for future stockpile/trade rules.
	pass


func get_current_year() -> int:
	if typeof(TimeManager) != TYPE_NIL:
		return TimeManager.get_current_year()
	if typeof(LeaderManager) != TYPE_NIL:
		return LeaderManager.get_current_year()
	return 2026


func mark_design_used(country_tag: String, design_id: String, year: int = -1) -> void:
	var tag := _norm_tag(country_tag)
	var did := design_id.strip_edges()
	if tag.is_empty() or did.is_empty():
		return
	if not _used_designs.has(tag):
		_used_designs[tag] = {}
	(_used_designs[tag] as Dictionary)[did] = true
	if not _last_used_year.has(tag):
		_last_used_year[tag] = {}
	var y := year if year > 0 else get_current_year()
	(_last_used_year[tag] as Dictionary)[did] = y


func has_used_design(country_tag: String, design_id: String) -> bool:
	var tag := _norm_tag(country_tag)
	var bucket: Variant = _used_designs.get(tag, {})
	if typeof(bucket) != TYPE_DICTIONARY:
		return false
	return bool((bucket as Dictionary).get(design_id, false))


func get_design_status(country_tag: String, design_id: String) -> DesignStatus:
	var info := _classify_design(country_tag, design_id)
	return int(info.get("status", DesignStatus.ACTIVE)) as DesignStatus


func get_active_designs(country_tag: String, domain: String = DOMAIN_ALL) -> Array[String]:
	return _filter_ids_by_status(country_tag, DesignStatus.ACTIVE, domain)


func get_previously_used_designs(country_tag: String, domain: String = DOMAIN_ALL) -> Array[String]:
	return _filter_ids_by_status(country_tag, DesignStatus.PREVIOUSLY_USED, domain)


func get_obsolete_designs(country_tag: String, domain: String = DOMAIN_ALL) -> Array[String]:
	return _filter_ids_by_status(country_tag, DesignStatus.OBSOLETE, domain)


func get_designs_for_picker(
	country_tag: String,
	domain: String = DOMAIN_ALL,
	show_obsolete: bool = false,
	factory: Factory = null,
	include_locked: bool = true,
) -> Dictionary:
	var tag := _norm_tag(country_tag)
	var buckets := _empty_picker_buckets()

	for design_id in _catalog_design_ids(tag, factory):
		if not _matches_domain(design_id, domain):
			continue
		if not _is_tech_buildable(tag, design_id):
			if include_locked:
				_push_locked_design(buckets, tag, design_id)
			continue
		var status := get_design_status(tag, design_id)
		var owner_key := _ownership_bucket_key(tag, design_id)
		match status:
			DesignStatus.ACTIVE:
				(buckets[owner_key]["active"] as Array).append(design_id)
			DesignStatus.PREVIOUSLY_USED:
				if show_obsolete:
					(buckets[owner_key]["previously_used"] as Array).append(design_id)
			DesignStatus.OBSOLETE:
				if show_obsolete:
					(buckets[owner_key]["obsolete"] as Array).append(design_id)

	for key in ["domestic", "foreign"]:
		for section in ["active", "previously_used", "obsolete"]:
			_sort_design_ids(buckets[key][section] as Array)

	_sort_design_ids(buckets["locked_domestic"] as Array)
	_sort_design_ids(buckets["locked_foreign"] as Array)

	var domestic: Dictionary = buckets["domestic"]
	var foreign: Dictionary = buckets["foreign"]
	return {
		"domestic": domestic,
		"foreign": foreign,
		"locked_domestic": buckets["locked_domestic"],
		"locked_foreign": buckets["locked_foreign"],
		"active": _merge_ids(domestic["active"], foreign["active"]),
		"previously_used": _merge_ids(domestic["previously_used"], foreign["previously_used"]),
		"obsolete": _merge_ids(domestic["obsolete"], foreign["obsolete"]),
	}

## Public helper for Map Build Eligibility and other map systems.
## Returns only designs the country has the technology to build (lightweight Phase 1).
## This is the improved source for picker catalogs, production assignment, etc.
##
## Map callers should prefer:
##   MapTechnologyContext.is_design_buildable_in_province(province_id, design_id)
## for the full province + controller + future extension logic.
func get_tech_eligible_design_ids(country_tag: String, factory: Factory = null) -> Array[String]:
	return _eligible_design_ids(country_tag, factory)


func get_unlock_year(design_id: String) -> int:
	if GameData.design_data == null:
		return 1936
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	if template == null:
		return _year_from_id(design_id)
	if template.unlock_year > 0:
		return template.unlock_year
	return _era_to_year(template.get_inferred_production_era(), design_id)


func get_lifecycle_role(design_id: String) -> String:
	if GameData.design_data == null:
		return "unknown"
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	if template == null:
		return "unknown"
	if not template.lifecycle_role.is_empty():
		return template.lifecycle_role.strip_edges().to_lower()
	if not template.lifecycle_category.is_empty():
		return template.lifecycle_category.strip_edges().to_lower()
	return ProductionCostCalculator.infer_category(template)


func get_design_domain(design_id: String) -> String:
	if GameData.design_data == null:
		return DOMAIN_LAND
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	if template == null:
		return DOMAIN_LAND
	if not template.design_domain.is_empty():
		return template.design_domain.strip_edges().to_lower()
	return _infer_domain_from_template(template, design_id)


func is_only_design_in_role(country_tag: String, design_id: String) -> bool:
	var tag := _norm_tag(country_tag)
	var role := get_lifecycle_role(design_id)
	var count := 0
	for did in _buildable_design_ids(tag, null):
		if get_lifecycle_role(did) != role:
			continue
		if _is_tech_buildable(tag, did):
			count += 1
	return count <= 1


func get_design_nation_tag(design_id: String) -> String:
	if GameData.design_data == null:
		return ""
	var template: UnitTemplate = GameData.design_data.get_template(design_id)
	if template == null:
		return _infer_nation_from_id(design_id)
	var explicit := template.design_nation.strip_edges().to_upper()
	if not explicit.is_empty():
		return explicit
	return _infer_nation_from_template(template, design_id)


func get_design_ownership(country_tag: String, design_id: String) -> DesignOwnership:
	var tag := _norm_tag(country_tag)
	var nation := get_design_nation_tag(design_id)
	if nation.is_empty():
		return DesignOwnership.UNIVERSAL
	if nation == tag:
		return DesignOwnership.DOMESTIC
	if has_acquired_design(tag, design_id):
		return DesignOwnership.FOREIGN_ACQUIRED
	return DesignOwnership.UNIVERSAL


func is_design_domestic_for(country_tag: String, design_id: String) -> bool:
	var o := get_design_ownership(country_tag, design_id)
	return o == DesignOwnership.DOMESTIC or o == DesignOwnership.UNIVERSAL


func is_design_foreign_for(country_tag: String, design_id: String) -> bool:
	return get_design_ownership(country_tag, design_id) == DesignOwnership.FOREIGN_ACQUIRED


func country_may_use_design(country_tag: String, design_id: String) -> bool:
	return _country_may_use_design(country_tag, design_id)


func has_acquired_design(country_tag: String, design_id: String) -> bool:
	## Single source of truth check (grant_acquired_design is authoritative).
	## Checks the modern _acquired_designs dict first, then falls back to the legacy shim.
	var tag := _norm_tag(country_tag)
	var did := design_id.strip_edges()

	# Modern path (grant_acquired_design writes here with kind)
	var modern_bucket: Variant = _acquired_designs.get(tag, {})
	if typeof(modern_bucket) == TYPE_DICTIONARY and (modern_bucket as Dictionary).has(did):
		return true

	# Legacy shim (for saves created before grant was the single source, and mark_design_acquired calls)
	var legacy_bucket: Variant = _acquired_foreign_designs.get(tag, {})
	if typeof(legacy_bucket) == TYPE_DICTIONARY:
		return bool((legacy_bucket as Dictionary).get(did, false))

	return false


func get_acquisition_kind(country_tag: String, design_id: String) -> String:
	var tag := _norm_tag(country_tag)
	var bucket: Variant = _acquired_designs.get(tag, {})
	if typeof(bucket) != TYPE_DICTIONARY:
		return ""
	return str((bucket as Dictionary).get(design_id, "")).strip_edges().to_lower()


func grant_acquired_design(
	country_tag: String,
	design_id: String,
	kind: String = ACQUISITION_CAPTURED,
) -> void:
	## THE single public entry point for all acquisition (capture, purchase, licensing, future trade/espionage/etc.).
	## Callers should never touch the internal dicts directly.
	var tag := _norm_tag(country_tag)
	var did := design_id.strip_edges()
	if tag.is_empty() or did.is_empty():
		return

	# Primary modern store (with kind for rich UI)
	if not _acquired_designs.has(tag):
		_acquired_designs[tag] = {}
	var k := kind.strip_edges().to_lower()
	if k not in [ACQUISITION_CAPTURED, ACQUISITION_PURCHASED, ACQUISITION_LICENSED]:
		k = ACQUISITION_CAPTURED
	(_acquired_designs[tag] as Dictionary)[did] = k

	# Pragmatic legacy shim so that existing has_acquired_design / picker / _country_may_use_design
	# immediately see the design (transition period only).
	if not _acquired_foreign_designs.has(tag):
		_acquired_foreign_designs[tag] = {}
	(_acquired_foreign_designs[tag] as Dictionary)[did] = true

	# Note: mark_design_acquired is legacy and now just forwards here for safety.
	# Future code should call grant_acquired_design directly with the appropriate kind.


func revoke_acquired_design(country_tag: String, design_id: String) -> void:
	var tag := _norm_tag(country_tag)
	var bucket: Variant = _acquired_designs.get(tag, {})
	if typeof(bucket) != TYPE_DICTIONARY:
		return
	(bucket as Dictionary).erase(design_id)
	var legacy_bucket: Variant = _acquired_foreign_designs.get(tag, {})
	if typeof(legacy_bucket) == TYPE_DICTIONARY:
		(legacy_bucket as Dictionary).erase(design_id)


func acquisition_kind_label(kind: String) -> String:
	match kind.strip_edges().to_lower():
		ACQUISITION_PURCHASED:
			return "Purchased"
		ACQUISITION_LICENSED:
			return "Licensed"
		ACQUISITION_CAPTURED:
			return "Captured"
		_:
			return "Acquired"


func acquisition_icon(kind: String) -> String:
	match kind.strip_edges().to_lower():
		ACQUISITION_CAPTURED:
			return "⚔"
		ACQUISITION_PURCHASED:
			return "💰"
		ACQUISITION_LICENSED:
			return "📜"
		_:
			return "🌐"


## Short row prefix for picker lists: "🏠 Domestic", "🌐 ⚔ Captured · FRA", "◇ Universal".
func format_origin_badge(country_tag: String, design_id: String) -> String:
	var tag := _norm_tag(country_tag)
	if is_design_foreign_for(tag, design_id):
		return _format_foreign_badge(tag, design_id, true)
	var nation := get_design_nation_tag(design_id)
	if nation.is_empty():
		return "◇ Universal"
	if nation == tag:
		return "🏠 Domestic"
	return "🏠 %s" % nation


## Longer tooltip line for picker rows and inspectors.
func format_origin_tooltip(country_tag: String, design_id: String) -> String:
	var tag := _norm_tag(country_tag)
	if is_design_foreign_for(tag, design_id):
		return _format_foreign_badge(tag, design_id, false)
	var nation := get_design_nation_tag(design_id)
	if nation.is_empty():
		return "Universal design — any nation may produce when unlocked."
	if nation == tag:
		return "Domestic design — native to %s." % tag
	return "Domestic to %s (shown for %s)." % [nation, tag]


## Subtle list-row tint by how the design was acquired (foreign rows only).
func acquisition_row_color(country_tag: String, design_id: String) -> Color:
	if not is_design_foreign_for(country_tag, design_id):
		return Color("#c8d8f0")
	match get_acquisition_kind(country_tag, design_id):
		ACQUISITION_CAPTURED:
			return Color("#f0b8c0")
		ACQUISITION_PURCHASED:
			return Color("#f0d080")
		ACQUISITION_LICENSED:
			return Color("#98e0ff")
		_:
			return Color("#a8c8f0")


func _format_foreign_badge(country_tag: String, design_id: String, compact: bool) -> String:
	var kind := get_acquisition_kind(country_tag, design_id)
	var label := acquisition_kind_label(kind)
	var icon := acquisition_icon(kind)
	var source := get_design_nation_tag(design_id)
	if compact:
		if source.is_empty():
			return "🌐 %s %s" % [icon, label]
		return "🌐 %s %s · %s" % [icon, label, source]
	if source.is_empty():
		return "Foreign acquired (%s) — source nation unknown." % label.to_lower()
	return "Foreign design from %s — %s." % [source, label.to_lower()]


## === Runtime Acquisition (Capture / Trade / Future Systems) ===

## Helper called by conquest/capture systems (primarily FactoryManager).
## Inspects a captured factory's current/previous designs and grants any foreign ones
## the new owner does not already possess.
## Returns the number of *newly* acquired designs (0 if nothing new).
func try_grant_captured_designs_from_factory(factory: Factory, new_owner_tag: String) -> int:
	if factory == null or typeof(DesignManager) == TYPE_NIL:
		return 0
	if new_owner_tag.is_empty():
		return 0

	var candidates: Array[String] = []
	if not factory.current_production_design.is_empty():
		candidates.append(factory.current_production_design)
	if not factory.previous_design.is_empty() and factory.previous_design not in candidates:
		candidates.append(factory.previous_design)

	# Future: we could also scan assigned_lines / production lines for more designs,
	# but current/previous is the high-signal "what this factory was actually producing".

	return _try_grant_design_list(candidates, new_owner_tag, ACQUISITION_CAPTURED)


## Internal worker used by the public try_ helper and (in future) by trade/espionage paths.
func _try_grant_design_list(design_ids: Array, new_owner_tag: String, kind: String) -> int:
	var tag := _norm_tag(new_owner_tag)
	var newly_acquired := 0

	for raw in design_ids:
		var did := str(raw).strip_edges()
		if did.is_empty():
			continue
		if has_acquired_design(tag, did):
			continue  # already own it (domestic or previously acquired)

		var source_nation := get_design_nation_tag(did)
		grant_acquired_design(tag, did, kind)
		newly_acquired += 1
		_fire_acquisition_toast(tag, did, source_nation, kind)

	return newly_acquired


## Public convenience for MapManager (and any other province-level owner change).
## Queries FactoryManager for factories in the province and runs the per-factory grant logic.
## Safe to call even if FactoryManager is not ready.
func try_grant_from_captured_province(province_id: int, new_owner_tag: String) -> int:
	if typeof(FactoryManager) == TYPE_NIL:
		return 0
	var factories := FactoryManager.get_factories_in_province(province_id)
	var total := 0
	for f in factories:
		total += try_grant_captured_designs_from_factory(f, new_owner_tag)
	return total


## Lightweight non-intrusive toast using the established LeaderEventUI pattern.
## Message is intentionally rich so the player immediately understands what they gained and from whom.
func _fire_acquisition_toast(country_tag: String, design_id: String, source_nation: String, kind: String) -> void:
	if typeof(LeaderEventUI) == TYPE_NIL or not LeaderEventUI.has_method("show_toast"):
		return

	var display_name := design_id
	if GameData.design_data != null:
		var tmpl: UnitTemplate = GameData.design_data.get_template(design_id)
		if tmpl != null and not tmpl.display_name.is_empty():
			display_name = tmpl.display_name

	var icon := acquisition_icon(kind)
	var source := source_nation if not source_nation.is_empty() else "?"

	var msg := "%s New design acquired: %s (%s from %s)" % [
		icon,
		display_name,
		acquisition_kind_label(kind),
		source
	]

	# 5 seconds, non-error style
	LeaderEventUI.show_toast(msg, 5.0)


func design_row_search_blob(country_tag: String, design_id: String) -> String:
	var parts: PackedStringArray = [design_id.to_lower(), design_id.replace("_", " ").to_lower()]
	if GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(design_id)
		if template != null:
			if not template.display_name.is_empty():
				parts.append(template.display_name.to_lower())
			for extra in [
				template.base_type,
				template.production_category,
				template.lifecycle_role,
				template.lifecycle_category,
				template.design_family,
				template.design_domain,
			]:
				var s := str(extra).strip_edges().to_lower()
				if not s.is_empty():
					parts.append(s.replace("_", " "))
	var badge := format_origin_badge(country_tag, design_id).to_lower()
	parts.append(badge)
	if is_design_foreign_for(country_tag, design_id):
		var kind := get_acquisition_kind(country_tag, design_id)
		parts.append(kind)
		parts.append(acquisition_kind_label(kind).to_lower())
		var source := get_design_nation_tag(design_id)
		if not source.is_empty():
			parts.append(source.to_lower())
	parts.append(str(get_unlock_year(design_id)))
	parts.append(get_design_domain(design_id))
	return " ".join(parts)


func sort_design_ids_for_display(ids: Array) -> Array[String]:
	var copy: Array[String] = []
	for raw in ids:
		copy.append(str(raw))
	_sort_design_ids(copy)
	return copy


func get_save_data() -> Dictionary:
	# Primary save key is now "acquired_designs" (populated exclusively by grant_acquired_design).
	# We also persist the legacy dict for maximum backward compat during the transition period.
	return {
		"used_designs": _used_designs.duplicate(true),
		"last_used_year": _last_used_year.duplicate(true),
		"acquired_designs": _acquired_designs.duplicate(true),
		"acquired_foreign_designs": _acquired_foreign_designs.duplicate(true),
	}


func apply_save_data(data: Dictionary) -> void:
	_used_designs = (data.get("used_designs", {}) as Dictionary).duplicate(true)
	_last_used_year = (data.get("last_used_year", {}) as Dictionary).duplicate(true)

	# Load modern data (preferred)
	if data.has("acquired_designs"):
		_acquired_designs = (data.get("acquired_designs", {}) as Dictionary).duplicate(true)

	# Migrate legacy data (old saves or anything that used mark_design_acquired directly)
	if data.has("acquired_foreign_designs"):
		var legacy := (data.get("acquired_foreign_designs", {}) as Dictionary).duplicate(true)
		_acquired_foreign_designs = legacy
		# One-time migration: promote legacy entries into the modern dict as "captured"
		for tag in legacy.keys():
			var bucket: Dictionary = legacy[tag]
			if not _acquired_designs.has(tag):
				_acquired_designs[tag] = {}
			for did in bucket.keys():
				if not (_acquired_designs[tag] as Dictionary).has(str(did)):
					(_acquired_designs[tag] as Dictionary)[str(did)] = ACQUISITION_CAPTURED

## === Nation-Specific Design Support (for Map Build Eligibility + future trade/capture) ===

func mark_design_acquired(country_tag: String, design_id: String) -> void:
	# Legacy compatibility shim — forwards to the single source of truth.
	# New code must call grant_acquired_design(..., ACQUISITION_CAPTURED) directly.
	grant_acquired_design(country_tag, design_id, ACQUISITION_CAPTURED)

# (duplicate legacy has_acquired_design removed — the strengthened version above that prefers
# the modern grant path is now the single implementation)


func domain_from_filter_index(index: int) -> String:
	match clampi(index, 0, DOMAIN_FILTER_LABELS.size() - 1):
		1:
			return DOMAIN_LAND
		2:
			return DOMAIN_NAVAL
		3:
			return DOMAIN_AIR
		4:
			return DOMAIN_SPACE
		5:
			return DOMAIN_SUPPORT
		_:
			return DOMAIN_ALL


func is_design_factory_compatible(design_id: String, factory: Factory) -> bool:
	if factory == null:
		return true
	if ProductionNavalRules.is_naval_design(design_id):
		return ProductionNavalRules.factory_can_build_naval(factory)
	return true


# --- Internal classification ---


func _filter_ids_by_status(
	country_tag: String,
	status: DesignStatus,
	domain: String,
) -> Array[String]:
	var out: Array[String] = []
	for design_id in _buildable_design_ids(_norm_tag(country_tag), null):
		if get_design_status(country_tag, design_id) != status:
			continue
		if not _matches_domain(design_id, domain):
			continue
		out.append(design_id)
	_sort_design_ids(out)
	return out


func _classify_design(country_tag: String, design_id: String) -> Dictionary:
	var tag := _norm_tag(country_tag)
	var role := get_lifecycle_role(design_id)
	var unlock_year := get_unlock_year(design_id)
	var current_year := get_current_year()
	var in_use := _is_design_in_active_production(tag, design_id)
	var used := has_used_design(tag, design_id) or in_use

	var peers: Array[Dictionary] = []
	for did in _buildable_design_ids(tag, null):
		if get_lifecycle_role(did) != role:
			continue
		if not _is_tech_buildable(tag, did):
			continue
		peers.append({
			"id": did,
			"year": get_unlock_year(did),
			"used": has_used_design(tag, did) or _is_design_in_active_production(tag, did),
		})

	peers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("year", 0)) > int(b.get("year", 0))
	)

	if peers.is_empty():
		return {"status": DesignStatus.ACTIVE, "only_in_role": true}

	var newest_year := int(peers[0].get("year", unlock_year))
	var has_newer_peer := false
	for peer in peers:
		if str(peer.get("id", "")) == design_id:
			continue
		if int(peer.get("year", 0)) > unlock_year:
			has_newer_peer = true
			break

	var only_in_role := peers.size() == 1
	var is_newest := unlock_year >= newest_year

	if only_in_role or is_newest or in_use:
		return {"status": DesignStatus.ACTIVE, "only_in_role": only_in_role}

	if not has_newer_peer:
		return {"status": DesignStatus.ACTIVE, "only_in_role": false}

	var age := current_year - unlock_year
	if age < OBSOLETE_AGE_YEARS:
		if used:
			return {"status": DesignStatus.PREVIOUSLY_USED, "only_in_role": false}
		return {"status": DesignStatus.ACTIVE, "only_in_role": false}

	if used:
		return {"status": DesignStatus.PREVIOUSLY_USED, "only_in_role": false}
	return {"status": DesignStatus.OBSOLETE, "only_in_role": false}


func _eligible_design_ids(country_tag: String, factory: Factory = null) -> Array[String]:
	return _buildable_design_ids(country_tag, factory)


func _buildable_design_ids(country_tag: String, factory: Factory = null) -> Array[String]:
	var out: Array[String] = []
	for design_id in _catalog_design_ids(country_tag, factory):
		if _is_tech_buildable(_norm_tag(country_tag), design_id):
			out.append(design_id)
	return out


func _catalog_design_ids(country_tag: String, factory: Factory = null) -> Array[String]:
	## Nation-visible designs (domestic, universal, or acquired foreign) — tech not applied.
	var tag := _norm_tag(country_tag)
	var out: Array[String] = []
	if GameData.design_data == null:
		return out
	for template_id in GameData.design_data.templates.keys():
		var did := str(template_id)
		var template: UnitTemplate = GameData.design_data.get_template(did)
		if template == null or template.is_infantry_equipment():
			continue
		if not _country_may_use_design(tag, did):
			continue
		if factory != null and not is_design_factory_compatible(did, factory):
			continue
		out.append(did)
	return out


func _country_may_use_design(country_tag: String, design_id: String) -> bool:
	var tag := _norm_tag(country_tag)
	var nation := get_design_nation_tag(design_id)
	if nation.is_empty():
		return true
	if nation == tag:
		return true
	return has_acquired_design(tag, design_id)


func _ownership_bucket_key(country_tag: String, design_id: String) -> String:
	if is_design_foreign_for(country_tag, design_id):
		return "foreign"
	return "domestic"


func _empty_picker_buckets() -> Dictionary:
	return {
		"domestic": {
			"active": [] as Array[String],
			"previously_used": [] as Array[String],
			"obsolete": [] as Array[String],
		},
		"foreign": {
			"active": [] as Array[String],
			"previously_used": [] as Array[String],
			"obsolete": [] as Array[String],
		},
		"locked_domestic": [] as Array[String],
		"locked_foreign": [] as Array[String],
	}


func _push_locked_design(buckets: Dictionary, country_tag: String, design_id: String) -> void:
	if is_design_foreign_for(country_tag, design_id):
		(buckets["locked_foreign"] as Array).append(design_id)
	else:
		(buckets["locked_domestic"] as Array).append(design_id)


func _merge_ids(a: Array, b: Array) -> Array[String]:
	var out: Array[String] = []
	for id in a:
		out.append(str(id))
	for id in b:
		var sid := str(id)
		if sid not in out:
			out.append(sid)
	return out


func _infer_nation_from_template(template: UnitTemplate, design_id: String) -> String:
	var family := template.design_family.strip_edges().to_lower()
	if family.is_empty():
		return _infer_nation_from_id(design_id)
	return _nation_from_family_token(family)


func _infer_nation_from_id(design_id: String) -> String:
	var id_lower := design_id.strip_edges().to_lower()
	const PREFIX_TAGS: Array[Dictionary] = [
		{"prefix": "german_", "tag": "GER"},
		{"prefix": "ger_", "tag": "GER"},
		{"prefix": "us_", "tag": "USA"},
		{"prefix": "sov_", "tag": "SOV"},
		{"prefix": "russian_", "tag": "SOV"},
		{"prefix": "fra_", "tag": "FRA"},
		{"prefix": "french_", "tag": "FRA"},
		{"prefix": "uk_", "tag": "ENG"},
		{"prefix": "eng_", "tag": "ENG"},
		{"prefix": "british_", "tag": "ENG"},
		{"prefix": "ita_", "tag": "ITA"},
		{"prefix": "italian_", "tag": "ITA"},
		{"prefix": "jap_", "tag": "JAP"},
		{"prefix": "japanese_", "tag": "JAP"},
		{"prefix": "chinese_", "tag": "CHN"},
		{"prefix": "chn_", "tag": "CHN"},
		{"prefix": "ottoman_", "tag": "TUR"},
		{"prefix": "swedish_", "tag": "SWE"},
	]
	for entry in PREFIX_TAGS:
		if id_lower.begins_with(str(entry.get("prefix", ""))):
			return str(entry.get("tag", ""))
	return _nation_from_family_token(id_lower)


func _nation_from_family_token(token: String) -> String:
	var t := token.strip_edges().to_lower()
	if t.is_empty():
		return ""
	for universal in ["generic_", "multinational", "experimental_", "infantry_equipment"]:
		if universal in t or t == "generic":
			return ""
	const RULES: Array[Dictionary] = [
		{"need": "german", "tag": "GER"},
		{"need": "us_", "tag": "USA"},
		{"need": "american", "tag": "USA"},
		{"need": "soviet", "tag": "SOV"},
		{"need": "russian", "tag": "SOV"},
		{"need": "italian", "tag": "ITA"},
		{"need": "japanese", "tag": "JAP"},
		{"need": "uk_", "tag": "ENG"},
		{"need": "british", "tag": "ENG"},
		{"need": "french", "tag": "FRA"},
		{"need": "chinese", "tag": "CHN"},
		{"need": "ottoman", "tag": "TUR"},
		{"need": "swedish", "tag": "SWE"},
	]
	for rule in RULES:
		if str(rule.get("need", "")) in t:
			return str(rule.get("tag", ""))
	return ""


func _is_design_in_active_production(country_tag: String, design_id: String) -> bool:
	if typeof(ProductionManager) == TYPE_NIL:
		return false
	for factory in ProductionManager.get_all_factories_for_country(country_tag):
		if factory == null:
			continue
		if factory.current_production_design == design_id:
			return true
		for line_id in factory.assigned_lines:
			var line := ProductionManager.get_line(str(line_id))
			if line != null and line.design_id == design_id:
				return true
	return false


func _is_tech_buildable(country_tag: String, design_id: String) -> bool:
	if typeof(TechnologyManager) == TYPE_NIL:
		return true
	return TechnologyManager.is_unit_design_available(country_tag, design_id)


func _matches_domain(design_id: String, domain: String) -> bool:
	var d := domain.strip_edges().to_lower()
	if d.is_empty() or d == DOMAIN_ALL:
		return true
	return get_design_domain(design_id) == d


func _infer_domain_from_template(template: UnitTemplate, design_id: String) -> String:
	if template.is_infantry_equipment():
		return DOMAIN_SUPPORT
	if _is_space_template(template, design_id):
		return DOMAIN_SPACE
	var bt := template.base_type.strip_edges().to_lower()
	if ProductionNavalRules.is_naval_template(template):
		return DOMAIN_NAVAL
	var cat := ProductionCostCalculator.infer_category(template).to_lower()
	if ProductionNavalRules.is_naval_category(cat):
		return DOMAIN_NAVAL
	if bt == "air":
		return DOMAIN_AIR
	if cat in ["aa", "radar", "logistics", "drone", "support", "sam", "ew"]:
		return DOMAIN_SUPPORT
	if cat == "rocket":
		return DOMAIN_SUPPORT
	if cat.contains("helicopter") or cat.contains("cas"):
		return DOMAIN_AIR
	return DOMAIN_LAND


func _is_space_template(template: UnitTemplate, design_id: String) -> bool:
	var bt := template.base_type.strip_edges().to_lower()
	if bt == "space":
		return true
	var cat := ProductionCostCalculator.infer_category(template).to_lower()
	if cat == "space":
		return true
	var arch := template.visual_archetype.strip_edges().to_lower()
	if not arch.is_empty():
		if arch in SPACE_VISUAL_ARCHETYPES:
			return true
		if arch.contains("satellite") or arch.contains("space_station") or arch.contains("spacecraft"):
			return true
		if arch.contains("launch_vehicle") or arch.contains("orbital"):
			return true
	var id_lower := design_id.strip_edges().to_lower()
	var family := template.design_family.strip_edges().to_lower()
	for token in [
		"satellite",
		"space_station",
		"space_shuttle",
		"spacecraft",
		"launch_vehicle",
		"crew_vehicle",
		"starship",
		"soyuz",
		"shenzhou",
		"artemis",
		"sls_",
		"space_force",
		"orbital",
		"tiangong",
		"starlink",
	]:
		if token in id_lower or token in family:
			return true
	# Ground MLRS / tactical rockets are not space production.
	if arch.contains("rocket_launcher") or arch.contains("mlrs") or arch.contains("icbm_launcher"):
		return false
	if "icbm" in id_lower and bt != "space":
		return false
	return false


func _era_to_year(era: String, design_id: String) -> int:
	var e := era.strip_edges().to_lower()
	match e:
		"ww1", "great_war":
			return 1918
		"interwar":
			return 1936
		"ww2", "world_war_2":
			return 1942
		"early_cold_war":
			return 1955
		"late_cold_war":
			return 1975
		"modern":
			return 2005
		"future", "space":
			return 2030
	var from_id := _year_from_id(design_id)
	if from_id != 1936:
		return from_id
	return 1940

# Apply design doctrine (from 3-option assessment hybrid): sets base mods and tags for module filtering. Called when player selects base model in designer.
# Returns modified stats or loads suggested modules. Keeps fun/memorable (doctrine choice) + trade-offs (explicit in UI/modules).
func apply_design_doctrine(design_id: String, doctrine_key: String) -> Dictionary:
	if not DESIGN_DOCTRINES.has(doctrine_key):
		return {}
	var doctrine = DESIGN_DOCTRINES[doctrine_key]
	var result = {"mods": doctrine.get("stat_mods", {}), "suggested_modules": [], "flavor": doctrine.get("description", ""), "real_world": doctrine.get("real_world", "")}
	# In full designer: apply mods to base stats, filter available modules by tags.
	# Example: for "rugged_redundancy", unlock redundancy modules, +durability.
	print("[DESIGN DOCTRINE] Applied %s to %s: %s (trade-offs: weight/cost for protection)" % [doctrine_key, design_id, doctrine.get("name")])
	return result

# Get available doctrines for a domain/era (for designer UI).
func get_available_doctrines(domain: String = "", era: String = "") -> Array:
	var avail = []
	for key in DESIGN_DOCTRINES:
		# Filter by domain if needed (e.g. compartmentalized great for naval).
		avail.append({"key": key, "name": DESIGN_DOCTRINES[key]["name"], "desc": DESIGN_DOCTRINES[key]["description"]})
	return avail

# Integrate service doctrine with unit design (high-level guideline for agents/AI in picker/design).
# E.g., if army "blitzkrieg", prefer mobile armor modules, apply bonuses to designs.
# Player micro overrides in designer; doctrine gives direction + national bonuses.
func get_designs_filtered_by_service_doctrine(country_tag: String, service: String, base_catalog: Array) -> Array:
	var doctrine := ""
	if typeof(LeaderManager) != TYPE_NIL:
		doctrine = LeaderManager.get_service_doctrine(country_tag, service)
	if doctrine.is_empty() or not DESIGN_DOCTRINES.has(doctrine):
		return base_catalog
	var def := DESIGN_DOCTRINES[doctrine] as Dictionary
	var filtered := []
	var bonus_tags: Array = def.get("module_tags", [])
	for d in base_catalog:
		var tpl: UnitTemplate = null
		if typeof(GameData) != TYPE_NIL and GameData.design_data != null:
			tpl = GameData.design_data.get_template(str(d))
		if tpl == null:
			filtered.append(d)
			continue
		var arch := str(tpl.visual_archetype).to_lower()
		# Prefer matching archetype (e.g. mobile for blitz)
		if "blitz" in doctrine and ("tank" in arch or "mobile" in arch):
			filtered.append(d)
		elif "attrition" in doctrine and ("artillery" in arch or "infantry" in arch):
			filtered.append(d)
		else:
			filtered.append(d)  # all, but AI would weight
	# In real: weight by doctrine, or auto-apply mods.
	print("[SERVICE DOCTRINE FILTER] For %s %s doctrine '%s': filtered designs prefer %s archetypes" % [country_tag, service, doctrine, bonus_tags])
	return filtered

func _year_from_id(design_id: String) -> int:
	var id := design_id.to_lower()
	for decade in [2040, 2030, 2026, 2020, 2010, 2000, 1990, 1980, 1970, 1960, 1950, 1945, 1940, 1939, 1936, 1918]:
		if str(decade) in id:
			return decade
	return 1936


func _sort_design_ids(ids: Array[String]) -> void:
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ya := get_unlock_year(a)
		var yb := get_unlock_year(b)
		if ya != yb:
			return ya > yb
		return a < b
	)


func _norm_tag(country_tag: String) -> String:
	return country_tag.strip_edges().to_upper()
