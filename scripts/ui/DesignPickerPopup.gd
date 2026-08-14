# scripts/ui/DesignPickerPopup.gd
class_name DesignPickerPopup
extends Window

const _UnitIcons = preload("res://scripts/ui/UnitIconLibrary.gd")

const MAX_WINDOW_SIZE := Vector2i(600, 680)
const ROW_DOMESTIC := Color("#d8f4ff")
const MIN_LIST_HEIGHT := 200
const MAX_LIST_HEIGHT := 400
const ROW_INDENT := "    "
const DISPLAY_NAME_MAX_LEN := 36
const DESIGN_LIST_LABEL_MAX_LEN := 64

const TIER_COLOR_ACTIVE := Color("#33e6ff")
const TIER_COLOR_ARCHIVE := Color("#ffb85a")
const TIER_COLOR_LOCKED := Color("#8a9ab8")
const HEADER_DOMESTIC := Color("#33e6ff")
const HEADER_FOREIGN := Color("#88b8ff")
const HEADER_PREVIOUS := Color("#e8b060")
const HEADER_OBSOLETE := Color("#8a92a8")
const HEADER_LOCKED := Color("#7a8aa4")
const ROW_UNIVERSAL := Color("#b8c8e0")
const LOCKED_ROW_BASE := Color("#9aa8c0")
const DIVIDER_COLOR := Color("#3a4460")

const DOMAIN_FILTER_TOOLTIPS: PackedStringArray = [
	"All equipment domains",
	"Land — armor, infantry, artillery",
	"Naval — ships and submarines",
	"Air — aircraft and air wings",
	"Space — orbital and strategic assets",
	"Support — logistics and auxiliary",
]

@export var factory_id: int = 0
@export var province_id: int = 0
@export var country_tag: String = "GER"
## When set (with factory_id == 0), confirm assigns a design to a unit — no factory retool.
var assign_callback: Callable = Callable()

signal design_chosen(design_id: String)

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var context_label: Label = $MarginContainer/VBoxContainer/ContextLabel
@onready var domain_filter: OptionButton = $MarginContainer/VBoxContainer/FilterRow/DomainFilter
@onready var show_obsolete_check: CheckBox = (
	$MarginContainer/VBoxContainer/FilterRow/ShowObsoleteCheck
)
@onready var search_edit: LineEdit = $MarginContainer/VBoxContainer/SearchEdit
@onready var legend_label: Label = $MarginContainer/VBoxContainer/LegendLabel
@onready var list_scroll: ScrollContainer = $MarginContainer/VBoxContainer/ListScroll
@onready var design_list: ItemList = $MarginContainer/VBoxContainer/ListScroll/DesignList
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CancelButton
@onready var lock_hint_label: Label = $MarginContainer/VBoxContainer/LockHintLabel

var _list_entries: Array[Dictionary] = []
var _visible_design_count: int = 0
var selected_design: String = ""
var _relocate_map_button: Button = null
var _relocate_target_pid: int = -1
var _relocate_target_name: String = ""


func _is_assign_mode() -> bool:
	return factory_id == 0


func _ready() -> void:
	title = "Assign Design to Unit" if _is_assign_mode() else "Select Production Design"
	close_requested.connect(_on_cancel_pressed)
	_clamp_window_to_viewport()

	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label, RetrowaveTheme.CYAN)
	RetrowaveTheme.style_body_label(context_label)
	context_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_search(search_edit)
	RetrowaveTheme.style_item_list(design_list)
	RetrowaveTheme.style_primary_button(confirm_button)
	RetrowaveTheme.style_secondary_button(cancel_button)
	RetrowaveTheme.style_body_label(lock_hint_label)
	RetrowaveTheme.style_body_label(legend_label)
	lock_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lock_hint_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	legend_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)

	var tag := country_tag.strip_edges().to_upper()
	if _is_assign_mode():
		title_label.text = "Assign design — %s" % tag if not tag.is_empty() else "Assign design"
		confirm_button.text = "Assign"
	else:
		title_label.text = "Production design — %s" % tag if not tag.is_empty() else "Production design"
	_sync_province_from_factory()
	if not _is_assign_mode():
		_ensure_relocate_map_button()
	_update_factory_context_label()
	if _is_assign_mode():
		context_label.visible = true
		context_label.text = "Designs you produce show up here — assign to this unit."
	search_edit.placeholder_text = "Search name, nation, captured, role, year…"
	search_edit.tooltip_text = (
		"All words must match (e.g. panzer captured). "
		+ "Use clear (×) or Esc. Enter selects the first match."
	)
	search_edit.clear_button_enabled = true
	legend_label.text = _legend_key_text()
	show_obsolete_check.button_pressed = false

	_setup_domain_filter()
	_update_filter_labels()
	_update_default_lock_hint()

	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	design_list.item_selected.connect(_on_design_selected)
	search_edit.text_changed.connect(_on_search_changed)
	search_edit.text_submitted.connect(_on_search_submitted)
	domain_filter.item_selected.connect(_on_filters_changed)
	show_obsolete_check.toggled.connect(_on_filters_changed)
	design_list.item_activated.connect(_on_design_activated)

	_rebuild_list()
	_update_legend_visibility()
	search_edit.call_deferred("grab_focus")
	popup_centered()


func _legend_key_text() -> String:
	return (
		"ACTIVE: buildable domestic & foreign acquired  ·  "
		+ "ARCHIVE: older lines (toggle above)  ·  LOCKED: needs research\n"
		+ "🏠 Domestic  ·  🌐 ⚔/💰/📜 Foreign  ·  ◇ Universal  ·  ★ sole role  ·  ↺/⏳ archive\n"
		+ "📉/🏔/🔒 on rows = dev / terrain / tech lock  ·  Good for/Weak for in context  ·  ↻ retool here  ·  ↗ relocate line"
	)


func _update_legend_visibility() -> void:
	var searching := not search_edit.text.strip_edges().is_empty()
	legend_label.visible = not searching
	if searching:
		legend_label.tooltip_text = _legend_key_text()
	else:
		legend_label.tooltip_text = ""


func _clamp_window_to_viewport() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var max_w := mini(MAX_WINDOW_SIZE.x, int(vp_size.x * 0.9))
	var max_h := mini(MAX_WINDOW_SIZE.y, int(vp_size.y * 0.85))
	max_size = Vector2i(max_w, max_h)
	min_size = Vector2i(mini(420, max_w), mini(460, max_h))
	if size.x > max_w or size.y > max_h:
		size = Vector2i(mini(size.x, max_w), mini(size.y, max_h))
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	design_list.tooltip_text = (
		"Hover for origin, province fit (good/weak), lock kind, and retool vs relocate guidance"
	)


func _setup_domain_filter() -> void:
	domain_filter.clear()
	var labels := DesignManager.DOMAIN_FILTER_DISPLAY
	if labels.is_empty():
		labels = DesignManager.DOMAIN_FILTER_LABELS
	for i in labels.size():
		domain_filter.add_item(labels[i])
		if i < DOMAIN_FILTER_TOOLTIPS.size():
			domain_filter.set_item_tooltip(i, DOMAIN_FILTER_TOOLTIPS[i])
	domain_filter.tooltip_text = "Filter designs by equipment domain"
	RetrowaveTheme.style_filter_option(domain_filter)
	domain_filter.custom_minimum_size.x = 168.0


func _get_factory() -> Factory:
	if FactoryManager == null:
		return null
	return FactoryManager.get_factory(factory_id)


func _sync_province_from_factory() -> void:
	if province_id > 0:
		return
	var factory := _get_factory()
	if factory != null:
		province_id = factory.province_id


func _get_province() -> Province:
	if province_id <= 0 or typeof(MapManager) == TYPE_NIL:
		return null
	return MapManager.get_province(province_id)


func _update_factory_context_label() -> void:
	if context_label == null:
		return
	var factory := _get_factory()
	var plain := ""
	if typeof(MapTechnologyContext) != TYPE_NIL and factory != null:
		plain = MapTechnologyContext.build_factory_picker_context_plain(factory, country_tag)
	if plain.is_empty() and factory != null:
		plain = "%s factory" % factory.factory_type.replace("_", " ")
	if plain.is_empty():
		context_label.visible = false
		context_label.text = ""
		return
	if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
		var prov := _get_province()
		if prov != null:
			var banner := MapTechnologyContext.build_design_picker_province_banner_plain(
				prov, country_tag,
			)
			if not banner.is_empty():
				plain += "\n" + banner
			var domain_hint := _domain_province_fit_hint(prov)
			if not domain_hint.is_empty():
				plain += "\n" + domain_hint
			if factory != null:
				var tid_banner := str(factory.current_production_design).strip_edges()
				if not tid_banner.is_empty():
					var act := MapTechnologyContext.build_production_action_plain(
						prov, tid_banner, country_tag, factory,
					)
					if not act.is_empty():
						plain += "\nAction: " + act
	context_label.visible = true
	context_label.text = plain
	var tip_lines: PackedStringArray = [
		"Designs must match factory type, research, province development, and terrain.",
		"Hover rows for fit, lock kind, and retool vs relocate guidance.",
	]
	if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
		var prov_tip := _get_province()
		if prov_tip != null:
			var invest_panel := MapTechnologyContext.build_invest_vs_reloc_panel_plain(
				prov_tip, country_tag,
			)
			if not invest_panel.is_empty():
				tip_lines.append(invest_panel)
			var dev_ctx := MapTechnologyContext.build_development_context_plain(prov_tip, true)
			if not dev_ctx.is_empty():
				tip_lines.append(dev_ctx)
	if province_id > 0 and factory != null:
		var tid_ctx := str(factory.current_production_design).strip_edges()
		if not tid_ctx.is_empty():
			var action := MapTechnologyContext.build_production_action_plain(
				_get_province(), tid_ctx, country_tag, factory,
			)
			if not action.is_empty():
				tip_lines.append("Current line: " + action)
	context_label.tooltip_text = "\n".join(tip_lines)
	_update_relocate_map_button()


func _ensure_relocate_map_button() -> void:
	if _relocate_map_button != null or context_label == null:
		return
	_relocate_map_button = Button.new()
	_relocate_map_button.visible = false
	RetrowaveTheme.style_secondary_button(_relocate_map_button)
	_relocate_map_button.pressed.connect(_on_relocate_map_pressed)
	var vbox := context_label.get_parent()
	if vbox != null:
		vbox.add_child(_relocate_map_button)
		vbox.move_child(_relocate_map_button, context_label.get_index() + 1)


func _update_relocate_map_button() -> void:
	if _relocate_map_button == null:
		return
	_relocate_target_pid = -1
	_relocate_target_name = ""
	var target_name := ""
	if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
		var prov := _get_province()
		if prov != null:
			var design_for_target := selected_design
			if design_for_target.is_empty() and _get_factory() != null:
				design_for_target = str(_get_factory().current_production_design).strip_edges()
			var target: Dictionary = MapTechnologyContext.get_primary_relocate_target(
				prov, country_tag, design_for_target,
			)
			target_name = str(target.get("name", ""))
			_relocate_target_pid = int(target.get("province_id", -1))
			_relocate_target_name = target_name
	var choice: Dictionary = {}
	if province_id > 0:
		var prov_btn := _get_province()
		if prov_btn != null and typeof(MapTechnologyContext) != TYPE_NIL:
			choice = MapTechnologyContext.assess_invest_reloc_choice(prov_btn, country_tag)
	var reloc_strength := str(choice.get("reloc_strength", ""))
	var show_map := (
		_relocate_target_pid > 0
		and _relocate_target_pid != province_id
		and not reloc_strength.is_empty()
	)
	_relocate_map_button.visible = show_map
	if show_map:
		if reloc_strength == "strong":
			_relocate_map_button.text = "★ Show ↗ %s on map" % target_name
		else:
			_relocate_map_button.text = "Show ↗ %s on map" % target_name
		var headline := str(choice.get("headline", "")).strip_edges()
		var tip := "Opens the world map on %s (#%d) to assign production." % [
			target_name, _relocate_target_pid,
		]
		if not headline.is_empty():
			tip += "\n" + headline
		if reloc_strength == "strong":
			tip += "\n★ Recommended relocate for blocked lines here."
		_relocate_map_button.tooltip_text = tip


func _on_relocate_map_pressed() -> void:
	if _relocate_target_pid < 0 or typeof(MapTechnologyContext) == TYPE_NIL:
		return
	if not MapTechnologyContext.focus_province_on_map(_relocate_target_pid):
		push_warning("DesignPickerPopup: could not focus map on province #%d" % _relocate_target_pid)
		return
	var toast_name := _relocate_target_name
	if toast_name.is_empty():
		toast_name = "province #%d" % _relocate_target_pid
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		var choice_toast: Dictionary = {}
		var prov_toast := _get_province()
		if prov_toast != null and typeof(MapTechnologyContext) != TYPE_NIL:
			choice_toast = MapTechnologyContext.assess_invest_reloc_choice(prov_toast, country_tag)
		var toast_msg := "Map focused on %s (#%d)" % [toast_name, _relocate_target_pid]
		if str(choice_toast.get("reloc_strength", "")) == "strong":
			toast_msg = "★ Map focused on %s — assign production there" % toast_name
		LeaderEventUI.show_toast(toast_msg, 3.5)


func _evaluate_design_gate(design_id: String) -> Dictionary:
	if typeof(MapTechnologyContext) == TYPE_NIL or province_id <= 0:
		return {"allowed": true}
	var prov := _get_province()
	if prov == null:
		return {"allowed": true}
	return MapTechnologyContext.evaluate_province_design_gate(
		prov, design_id, country_tag, _get_factory(),
	)


func _design_lock_reason(design_id: String) -> String:
	if typeof(MapTechnologyContext) != TYPE_NIL and province_id > 0:
		var reason := MapTechnologyContext.get_province_build_lock_reason(
			province_id, design_id, country_tag, _get_factory(),
		)
		if not reason.is_empty():
			return reason
	if typeof(DesignManager) != TYPE_NIL and not DesignManager.country_may_use_design(country_tag, design_id):
		return "Foreign design — not in national catalog"
	if typeof(TechnologyManager) == TYPE_NIL:
		return "Research required"
	var availability: Dictionary = TechnologyManager.get_design_availability(country_tag, design_id)
	return str(availability.get("reason", "Research required"))


func _design_lock_action(design_id: String) -> String:
	if typeof(MapTechnologyContext) != TYPE_NIL and province_id > 0:
		var action := MapTechnologyContext.get_province_build_lock_action(
			province_id, design_id, country_tag, _get_factory(),
		)
		if not action.is_empty():
			return action
	if typeof(TechnologyManager) == TYPE_NIL:
		return ""
	var availability: Dictionary = TechnologyManager.get_design_availability(country_tag, design_id)
	if not bool(availability.get("available", true)):
		return "Complete %s on the Technology screen." % str(
			availability.get("tech_name", "required research"),
		)
	return ""


func _design_lock_kind_icon(design_id: String) -> String:
	var gate := _evaluate_design_gate(design_id)
	if bool(gate.get("allowed", true)):
		return "🔒"
	match str(gate.get("kind", "tech")):
		"development":
			return "📉"
		"terrain":
			return "🏔"
		"factory":
			return "🏭"
		"catalog":
			return "🌐"
		_:
			return "🔒"


func _is_searching() -> bool:
	return not search_edit.text.strip_edges().is_empty()


func _count_visible_in_list(design_ids: Array, needle: String) -> int:
	var n := 0
	for raw in design_ids:
		if _matches_search(str(raw), needle):
			n += 1
	return n


func _rebuild_list() -> void:
	design_list.clear()
	_list_entries.clear()
	selected_design = ""
	_visible_design_count = 0

	var catalog := _fetch_catalog()
	var needle := search_edit.text.strip_edges().to_lower()
	var searching := _is_searching()
	_update_legend_visibility()

	var domestic: Dictionary = catalog.get("domestic", {}) as Dictionary
	var foreign: Dictionary = catalog.get("foreign", {}) as Dictionary
	var locked_domestic: Array = catalog.get("locked_domestic", []) as Array
	var locked_foreign: Array = catalog.get("locked_foreign", []) as Array
	var show_foreign_empty := not searching

	var search_banner_idx := -1
	if searching:
		search_banner_idx = design_list.add_item("  🔍 Searching…")
		design_list.set_item_disabled(search_banner_idx, true)
		design_list.set_item_custom_fg_color(search_banner_idx, RetrowaveTheme.CYAN)
		_list_entries.append(_header_entry())

	var active_domestic: Array = domestic.get("active", []) as Array
	var active_foreign: Array = foreign.get("active", []) as Array
	var active_visible := _count_visible_in_list(active_domestic, needle) + _count_visible_in_list(
		active_foreign,
		needle,
	)
	if active_visible > 0 or not searching:
		_append_tier_header("ACTIVE — BUILDABLE", TIER_COLOR_ACTIVE)
		if not searching:
			_append_active_tier_hint()
		var had_domestic_active := _append_design_section(
			"🏠 DOMESTIC",
			active_domestic,
			DesignManager.DesignStatus.ACTIVE,
			needle,
			false,
			false,
			false,
			HEADER_DOMESTIC,
		)
		if had_domestic_active:
			_append_section_divider()
		_append_design_section(
			"🌐 FOREIGN ACQUIRED",
			active_foreign,
			DesignManager.DesignStatus.ACTIVE,
			needle,
			true,
			false,
			show_foreign_empty,
			HEADER_FOREIGN,
		)

	if show_obsolete_check.button_pressed:
		var arch_dom_pu: Array = domestic.get("previously_used", []) as Array
		var arch_for_pu: Array = foreign.get("previously_used", []) as Array
		var arch_dom_ob: Array = domestic.get("obsolete", []) as Array
		var arch_for_ob: Array = foreign.get("obsolete", []) as Array
		var archive_visible := (
			_count_visible_in_list(arch_dom_pu, needle)
			+ _count_visible_in_list(arch_for_pu, needle)
			+ _count_visible_in_list(arch_dom_ob, needle)
			+ _count_visible_in_list(arch_for_ob, needle)
		)
		if archive_visible > 0 or not searching:
			_append_tier_header("ARCHIVE — OLDER LINES", TIER_COLOR_ARCHIVE)
			if not searching:
				_append_archive_tier_hint()
			var had_archive := false
			var section_added := _append_design_section(
				"↺ PREVIOUSLY USED · 🏠 DOMESTIC",
				arch_dom_pu,
				DesignManager.DesignStatus.PREVIOUSLY_USED,
				needle,
				false,
				false,
				false,
				HEADER_PREVIOUS,
			)
			if section_added:
				_append_section_divider()
			had_archive = section_added
			section_added = _append_design_section(
				"↺ PREVIOUSLY USED · 🌐 FOREIGN",
				arch_for_pu,
				DesignManager.DesignStatus.PREVIOUSLY_USED,
				needle,
				true,
				false,
				false,
				HEADER_PREVIOUS,
			)
			if section_added:
				_append_section_divider()
			had_archive = had_archive or section_added
			section_added = _append_design_section(
				"⏳ OBSOLETE · 🏠 DOMESTIC",
				arch_dom_ob,
				DesignManager.DesignStatus.OBSOLETE,
				needle,
				false,
				false,
				false,
				HEADER_OBSOLETE,
			)
			if section_added:
				_append_section_divider()
			had_archive = had_archive or section_added
			section_added = _append_design_section(
				"⏳ OBSOLETE · 🌐 FOREIGN",
				arch_for_ob,
				DesignManager.DesignStatus.OBSOLETE,
				needle,
				true,
				false,
				false,
				HEADER_OBSOLETE,
			)
			had_archive = had_archive or section_added
			if not had_archive and not searching:
				var note_idx := design_list.add_item("      No archive entries match the current filters")
				design_list.set_item_disabled(note_idx, true)
				design_list.set_item_custom_fg_color(note_idx, RetrowaveTheme.TEXT_DIM)
				_list_entries.append(_header_entry())

	var locked_visible := _count_visible_in_list(locked_domestic, needle) + _count_visible_in_list(
		locked_foreign,
		needle,
	)
	if locked_visible > 0 or (not searching and (not locked_domestic.is_empty() or not locked_foreign.is_empty())):
		_append_tier_header("LOCKED — RESEARCH REQUIRED", TIER_COLOR_LOCKED)
		if not searching:
			_append_locked_tier_hint()
		var had_locked_domestic := _append_design_section(
			"🔒 LOCKED · 🏠 DOMESTIC",
			locked_domestic,
			DesignManager.DesignStatus.ACTIVE,
			needle,
			false,
			true,
			false,
			HEADER_LOCKED,
		)
		if had_locked_domestic:
			_append_section_divider()
		_append_design_section(
			"🔒 LOCKED · 🌐 FOREIGN",
			locked_foreign,
			DesignManager.DesignStatus.ACTIVE,
			needle,
			true,
			true,
			false,
			HEADER_LOCKED,
		)

	if search_banner_idx >= 0:
		var q := search_edit.text.strip_edges()
		design_list.set_item_text(
			search_banner_idx,
			"  🔍 «%s» — %d shown" % [q, _visible_design_count] if _visible_design_count > 0
			else "  🔍 «%s» — no matches (clear search or change filters)" % q,
		)

	if not _list_has_design_rows():
		for line in _global_empty_lines(needle, catalog):
			var idx := design_list.add_item(line)
			design_list.set_item_disabled(idx, true)
			design_list.set_item_custom_fg_color(idx, RetrowaveTheme.TEXT_DIM)
			_list_entries.append(_header_entry())

	_clamp_window_to_viewport()
	_sync_list_scroll_size()
	_scroll_list_to_top()
	confirm_button.disabled = true
	_update_summary_hint(catalog)
	_update_lock_hint()


func _header_entry() -> Dictionary:
	return {"design_id": "", "is_header": true, "status": -1, "foreign": false, "locked": false}


func _list_has_design_rows() -> bool:
	for entry in _list_entries:
		if bool(entry.get("is_header", true)):
			continue
		if not str(entry.get("design_id", "")).is_empty():
			return true
	return false


func _update_summary_hint(catalog: Dictionary) -> void:
	var domestic: Dictionary = catalog.get("domestic", {}) as Dictionary
	var foreign: Dictionary = catalog.get("foreign", {}) as Dictionary
	var active_n := (domestic.get("active", []) as Array).size() + (foreign.get("active", []) as Array).size()
	var foreign_n := (foreign.get("active", []) as Array).size()
	var locked_n := (catalog.get("locked_domestic", []) as Array).size() + (
		catalog.get("locked_foreign", []) as Array
	).size()
	var parts: PackedStringArray = ["%d buildable" % active_n]
	if foreign_n > 0:
		parts.append("%d foreign" % foreign_n)
	if locked_n > 0:
		parts.append("%d locked" % locked_n)
	if show_obsolete_check.button_pressed:
		var arch := (domestic.get("previously_used", []) as Array).size()
		arch += (foreign.get("previously_used", []) as Array).size()
		arch += (domestic.get("obsolete", []) as Array).size()
		arch += (foreign.get("obsolete", []) as Array).size()
		if arch > 0:
			parts.append("%d archive" % arch)
	var domain_label := _domain_filter_label()
	var needle := search_edit.text.strip_edges() if _is_searching() else ""
	var summary := "%s · %s" % [" · ".join(parts), domain_label]
	if not needle.is_empty():
		if _visible_design_count == 0:
			summary = "Search «%s» · no matches · %s" % [needle, domain_label]
		else:
			summary = "Search «%s» · %d shown · %s" % [needle, _visible_design_count, domain_label]
	lock_hint_label.text = summary
	if not needle.is_empty() and _visible_design_count == 0:
		lock_hint_label.add_theme_color_override("font_color", RetrowaveTheme.MAGENTA)
	else:
		lock_hint_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)


func _domain_filter_label() -> String:
	var labels := DesignManager.DOMAIN_FILTER_DISPLAY
	if labels.is_empty():
		labels = DesignManager.DOMAIN_FILTER_LABELS
	var idx := domain_filter.selected
	if idx >= 0 and idx < labels.size():
		return labels[idx]
	return "All domains"


func _design_fit_sort_key(design_id: String) -> int:
	var prov := _get_province()
	if prov == null or typeof(MapTechnologyContext) == TYPE_NIL:
		return 50
	var fit: Dictionary = MapTechnologyContext.evaluate_design_province_fit(
		prov, design_id, country_tag, _get_factory(),
	)
	match str(fit.get("rating", "")):
		"good":
			return 0
		"fair":
			return 1
		"poor":
			return 2
		"blocked":
			return 3
		_:
			return 4


func _domain_province_fit_hint(province: Province) -> String:
	if province == null or typeof(DesignManager) == TYPE_NIL or typeof(MapTechnologyContext) == TYPE_NIL:
		return ""
	if domain_filter.selected <= 0:
		return ""
	var domain := DesignManager.domain_from_filter_index(domain_filter.selected)
	if domain.is_empty():
		return ""
	var profile: Dictionary = MapTechnologyContext.assess_province_production_profile(province)
	for g in profile.get("good", []) as Array:
		if domain in str(g).to_lower():
			return "Filtered %s: strong province for this domain" % domain
	for w in profile.get("weak", []) as Array:
		if domain in str(w).to_lower():
			return "Filtered %s: weak here — use ↗ rows or another province" % domain
	return "Filter %s: acceptable for production here" % domain


func _global_empty_lines(needle: String, catalog: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if not needle.is_empty():
		lines.append("  No designs match «%s»" % needle)
		lines.append("      Try fewer words, a design id fragment, or clear search (×)")
		lines.append("      Search matches name, nation, captured/purchased, role, and year")
		if not show_obsolete_check.button_pressed:
			lines.append("      Enable «Show older designs» for archive lines")
		return lines
	var domain := _domain_filter_label()
	lines.append("  No buildable designs for %s" % domain)
	lines.append("      Change domain filter or unlock lines in Technology")
	if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
		var prov_empty := _get_province()
		if prov_empty != null:
			var rec: Dictionary = MapTechnologyContext.get_relocate_recommendation(
				prov_empty, country_tag,
			)
			var tgt := MapTechnologyContext.normalize_relocate_label(
				str(rec.get("primary_target", "")),
			)
			if not tgt.is_empty():
				lines.append(
					"      Nothing buildable here — try ↗ %s or raise development" % tgt
				)
			var growth := MapTechnologyContext.build_development_growth_plain(prov_empty)
			if not growth.is_empty():
				lines.append("      " + growth)
	var foreign_n := (catalog.get("foreign", {}) as Dictionary).get("active", []) as Array
	if foreign_n.is_empty():
		lines.append("      Foreign lines appear after capture, trade, or licensing")
	return lines


func _append_tier_header(title: String, accent: Color) -> bool:
	var idx := design_list.add_item("▌ %s" % title)
	design_list.set_item_disabled(idx, true)
	design_list.set_item_custom_fg_color(idx, accent)
	_list_entries.append(_header_entry())
	return true


func _append_active_tier_hint() -> void:
	var idx := design_list.add_item("      Buildable domestic and foreign-acquired lines")
	design_list.set_item_disabled(idx, true)
	design_list.set_item_custom_fg_color(idx, RetrowaveTheme.TEXT_DIM)
	_list_entries.append(_header_entry())


func _append_archive_tier_hint() -> void:
	var idx := design_list.add_item("      Previously used and obsolete lines (domestic & foreign)")
	design_list.set_item_disabled(idx, true)
	design_list.set_item_custom_fg_color(idx, RetrowaveTheme.TEXT_DIM)
	_list_entries.append(_header_entry())


func _append_locked_tier_hint() -> void:
	var idx := design_list.add_item("      Unlock via Technology — rows are preview-only")
	design_list.set_item_disabled(idx, true)
	design_list.set_item_custom_fg_color(idx, RetrowaveTheme.TEXT_DIM)
	_list_entries.append(_header_entry())


func _append_foreign_empty_block(section_title: String, header_color: Color) -> void:
	var header_idx := design_list.add_item("  %s  (0)" % section_title)
	design_list.set_item_disabled(header_idx, true)
	design_list.set_item_custom_fg_color(header_idx, header_color)
	_list_entries.append(_header_entry())
	for hint in [
		"      No captured, purchased, or licensed designs for this filter.",
		"      ⚔ Capture in war  ·  💰 Purchase on the market  ·  📜 License from allies.",
		"      Completed acquisitions appear here automatically.",
	]:
		var hint_idx := design_list.add_item(hint)
		design_list.set_item_disabled(hint_idx, true)
		design_list.set_item_custom_fg_color(hint_idx, RetrowaveTheme.TEXT_DIM)
		_list_entries.append(_header_entry())


func _append_section_divider() -> void:
	var idx := design_list.add_item("  ─── domestic / foreign ───")
	design_list.set_item_disabled(idx, true)
	design_list.set_item_custom_fg_color(idx, DIVIDER_COLOR)
	_list_entries.append(_header_entry())


func _append_design_section(
	title: String,
	design_ids: Array,
	status: DesignManager.DesignStatus,
	needle: String,
	is_foreign: bool,
	locked_section: bool,
	show_empty_note: bool,
	header_color: Color,
) -> bool:
	var sorted: Array[String] = []
	if typeof(DesignManager) != TYPE_NIL:
		sorted = DesignManager.sort_design_ids_for_display(design_ids)
	var visible: Array[String] = []
	for design_id in sorted:
		if _matches_search(design_id, needle):
			visible.append(design_id)
	if (
		not locked_section
		and province_id > 0
		and typeof(MapTechnologyContext) != TYPE_NIL
		and visible.size() > 1
	):
		visible.sort_custom(func(a: String, b: String) -> bool:
			return _design_fit_sort_key(a) < _design_fit_sort_key(b)
		)

	if visible.is_empty():
		if not show_empty_note:
			return false
		if is_foreign:
			_append_foreign_empty_block(title, header_color)
		else:
			var empty_idx := design_list.add_item("  %s  (0)" % title)
			design_list.set_item_disabled(empty_idx, true)
			design_list.set_item_custom_fg_color(empty_idx, RetrowaveTheme.TEXT_DIM)
			_list_entries.append(_header_entry())
			var hint_idx := design_list.add_item("      No designs in this section for the current filter.")
			design_list.set_item_disabled(hint_idx, true)
			design_list.set_item_custom_fg_color(hint_idx, RetrowaveTheme.TEXT_DIM)
			_list_entries.append(_header_entry())
		return false

	var header_idx := design_list.add_item("  %s  (%d)" % [title, visible.size()])
	design_list.set_item_disabled(header_idx, true)
	design_list.set_item_custom_fg_color(header_idx, header_color)
	_list_entries.append(_header_entry())

	var sub := _section_subtitle(status, is_foreign, locked_section)
	if not sub.is_empty():
		var sub_idx := design_list.add_item("      %s" % sub)
		design_list.set_item_disabled(sub_idx, true)
		design_list.set_item_custom_fg_color(sub_idx, RetrowaveTheme.TEXT_DIM)
		_list_entries.append(_header_entry())

	for design_id in visible:
		var row_idx := design_list.add_item(
			ROW_INDENT + _design_list_label(design_id, status, is_foreign, locked_section),
		)
		design_list.set_item_tooltip(row_idx, _design_row_tooltip(design_id, status, locked_section))
		var dtex: Texture2D = _UnitIcons.icon_for_design_id(str(design_id), 32)
		if dtex != null:
			design_list.set_item_icon(row_idx, dtex)
		_list_entries.append({
			"design_id": design_id,
			"is_header": false,
			"status": status,
			"foreign": is_foreign,
			"locked": locked_section,
		})
		_apply_row_color(row_idx, design_id, status, is_foreign, locked_section)
		design_list.set_item_disabled(row_idx, locked_section or not _is_design_selectable(design_id))
		_visible_design_count += 1
	return true


func _design_row_tooltip(
	design_id: String,
	status: DesignManager.DesignStatus,
	locked_section: bool,
) -> String:
	var lines: PackedStringArray = []
	if GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(design_id)
		if template != null and not template.display_name.is_empty():
			lines.append(template.display_name)
	lines.append(design_id)
	if typeof(DesignManager) != TYPE_NIL:
		lines.append(DesignManager.format_origin_tooltip(country_tag, design_id))
		lines.append("Service: %s" % DesignManager.get_unlock_year(design_id))
		var role := DesignManager.get_lifecycle_role(design_id)
		if not role.is_empty():
			lines.append("Role: %s" % role.replace("_", " "))
	# Visual model flavor for choosing base in designer (different models for #engines, fighter/bomber types, carrier variants, jets vs prop, biplanes, ship sizes/types/eras, tank light/med/heavy per era, helos/transports)
	if GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(design_id)
		if template != null and not template.visual_archetype.is_empty():
			lines.append("Base Visual Model: " + template.visual_archetype + " (affects map icons + designer flavor; modules customize further for special variants)")
		# Doctrine suggestions (from 3-option assessment): choose for memorable trade-offs (rugged vs lightweight vs compartmentalized) then tune armor/hull.
		if typeof(DesignManager) != TYPE_NIL:
			var doctrines = DesignManager.get_available_doctrines()
			if doctrines.size() > 0:
				var doctrine_names: PackedStringArray = []
				for d in doctrines.slice(0, 3):
					doctrine_names.append(str(d.get("name", "")))
				lines.append("Design Doctrines available: " + ", ".join(doctrine_names))
	match status:
		DesignManager.DesignStatus.PREVIOUSLY_USED:
			lines.append("Previously used in this role — still authorized for production.")
		DesignManager.DesignStatus.OBSOLETE:
			lines.append("Obsolete line — suitable for export stock or emergency runs.")
	if locked_section:
		lines.append(_lock_suffix(design_id).replace("🔒 ", "Requires research: "))
		if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
			var prov_locked := _get_province()
			if prov_locked != null:
				var fit_locked := MapTechnologyContext.build_design_province_fit_plain(
					prov_locked, design_id, country_tag, _get_factory(),
				)
				if not fit_locked.is_empty():
					lines.append(fit_locked)
	else:
		var lock_reason := _design_lock_reason(design_id)
		var has_province_lock := (
			not lock_reason.is_empty() and lock_reason != "Research required"
		)
		if has_province_lock:
			lines.append(lock_reason)
			var lock_action := _design_lock_action(design_id)
			if not lock_action.is_empty():
				lines.append("→ %s" % lock_action)
		if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
			var prov := _get_province()
			if prov != null:
				lines.append(
					"Province: dev %d · %s%s"
					% [
						prov.development_level,
						str(prov.terrain).capitalize(),
						" · port" if prov.resolve_has_port() else "",
					]
				)
				var profile := MapTechnologyContext.build_province_production_profile_plain(prov)
				if not profile.is_empty():
					lines.append(profile)
				var fit_line := MapTechnologyContext.build_design_province_fit_plain(
					prov, design_id, country_tag, _get_factory(),
				)
				if not fit_line.is_empty():
					lines.append(fit_line)
				var action := MapTechnologyContext.build_production_action_plain(
					prov, design_id, country_tag, _get_factory(),
				)
				if not action.is_empty():
					lines.append("Action: " + action)
				if has_province_lock:
					var strategic := MapTechnologyContext.build_design_strategic_action_plain(
						prov, design_id, country_tag, _get_factory(),
					)
					if not strategic.is_empty() and strategic not in fit_line:
						lines.append(strategic)
	if (
		typeof(DesignManager) != TYPE_NIL
		and not DesignManager.is_design_factory_compatible(design_id, _get_factory())
	):
		lines.append("Needs a shipyard factory at a port.")
	if (
		typeof(DesignManager) != TYPE_NIL
		and DesignManager.is_only_design_in_role(country_tag, design_id)
	):
		lines.append("Only design remaining in this equipment role.")
	return "\n".join(lines)


func _matches_search(design_id: String, needle: String) -> bool:
	if needle.is_empty():
		return true
	var blob := ""
	if typeof(DesignManager) != TYPE_NIL:
		blob = DesignManager.design_row_search_blob(country_tag, design_id)
	else:
		blob = design_id.replace("_", " ").to_lower()
	for token in needle.split(" ", false):
		var t := token.strip_edges().to_lower()
		if t.is_empty():
			continue
		if blob.contains(t):
			continue
		# Allow searching "captured" / "purchased" style tokens against badge text
		if t in ["cap", "capture", "captured"] and ("captured" in blob or "⚔" in blob):
			continue
		if t in ["buy", "bought", "purchase", "purchased"] and ("purchased" in blob or "💰" in blob):
			continue
		if t in ["license", "licensed"] and ("licensed" in blob or "📜" in blob):
			continue
		return false
	return true


func _fetch_catalog() -> Dictionary:
	if typeof(DesignManager) == TYPE_NIL:
		return {
			"domestic": {"active": [], "previously_used": [], "obsolete": []},
			"foreign": {"active": [], "previously_used": [], "obsolete": []},
			"locked_domestic": [],
			"locked_foreign": [],
		}
	return DesignManager.get_designs_for_picker(
		country_tag,
		DesignManager.domain_from_filter_index(domain_filter.selected),
		show_obsolete_check.button_pressed,
		_get_factory(),
		true,
	)


func _section_subtitle(
	status: DesignManager.DesignStatus,
	is_foreign: bool,
	locked_section: bool,
) -> String:
	if locked_section:
		if is_foreign:
			return "Complete research to produce this acquired design"
		return "Complete research to unlock domestic production"
	if is_foreign:
		match status:
			DesignManager.DesignStatus.PREVIOUSLY_USED:
				return "Superseded in role — still buildable for reserves"
			DesignManager.DesignStatus.OBSOLETE:
				return "Legacy foreign stock — emergency or export runs"
			_:
				return "Captured, purchased, or licensed equipment"
	match status:
		DesignManager.DesignStatus.ACTIVE:
			return "Current lines for your nation and filter"
		DesignManager.DesignStatus.PREVIOUSLY_USED:
			return "Older domestic lines — rebuilds and reserves"
		DesignManager.DesignStatus.OBSOLETE:
			return "Aged out — export or emergency production"
		_:
			return ""


func _truncate_list_label(text: String, max_len: int = DESIGN_LIST_LABEL_MAX_LEN) -> String:
	if text.length() <= max_len:
		return text
	return text.left(maxi(1, max_len - 1)) + "…"


func _design_list_label(
	design_id: String,
	status: DesignManager.DesignStatus,
	is_foreign: bool,
	locked_section: bool,
) -> String:
	var display := design_id
	if GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(design_id)
		if template != null and not template.display_name.is_empty():
			display = template.display_name

	var origin := "◇ Universal"
	if typeof(DesignManager) != TYPE_NIL:
		origin = DesignManager.format_origin_badge(country_tag, design_id)

	var status_mark := ""
	match status:
		DesignManager.DesignStatus.PREVIOUSLY_USED:
			status_mark = "↺ "
		DesignManager.DesignStatus.OBSOLETE:
			status_mark = "⏳ "

	var role_mark := ""
	if (
		not locked_section
		and typeof(DesignManager) != TYPE_NIL
		and DesignManager.is_only_design_in_role(country_tag, design_id)
	):
		role_mark = "★ "

	display = _truncate_list_label(display, DISPLAY_NAME_MAX_LEN)
	var badge := "[%s]" % origin
	var ship := ""
	if typeof(DesignManager) != TYPE_NIL and not DesignManager.is_design_factory_compatible(
		design_id,
		_get_factory(),
	):
		ship = "  ·  ⚓"

	# Add visual model flavor for base model choice in designer (different fighters/bombers by engines, carrier variants, jets vs prop, biplanes, ship sizes, tank classes/eras etc.)
	var vis := ""
	if GameData.design_data != null:
		var template: UnitTemplate = GameData.design_data.get_template(design_id)
		if template != null and not template.visual_archetype.is_empty():
			vis = " · " + _truncate_list_label(template.visual_archetype, 18)

	if locked_section:
		var line := "%s  ·  %s  ·  %s%s%s" % [
			_truncate_list_label(_lock_suffix(design_id), 24),
			display,
			badge,
			ship,
			vis,
		]
		return _truncate_list_label(line)

	var line := "%s%s%s  ·  %s%s" % [role_mark, status_mark, display, badge, ship]
	if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
		var prov_row := _get_province()
		if prov_row != null:
			var fit: Dictionary = MapTechnologyContext.evaluate_design_province_fit(
				prov_row, design_id, country_tag, _get_factory(),
			)
			var fit_lbl := str(fit.get("label", "")).strip_edges()
			if not fit_lbl.is_empty():
				line += "  ·  " + _truncate_list_label(fit_lbl, 14)
			var rec_badge := MapTechnologyContext.build_design_row_recommendation_plain(
				prov_row, design_id, country_tag, _get_factory(),
			)
			if not rec_badge.is_empty():
				line += "  ·  " + _truncate_list_label(rec_badge, 18)
			else:
				var reloc_tgt := str(fit.get("relocate_target", "")).strip_edges()
				if not reloc_tgt.is_empty() and str(fit.get("rating", "")) in ["blocked", "poor", "fair"]:
					line += "  ·  ↗ " + _truncate_list_label(reloc_tgt, 12)
	var lock_reason := _design_lock_reason(design_id)
	if not lock_reason.is_empty() and lock_reason != "Research required":
		line += "  ·  %s %s" % [_design_lock_kind_icon(design_id), _truncate_list_label(lock_reason, 14)]

	return _truncate_list_label(line)


func _lock_prefix(design_id: String) -> String:
	return _lock_suffix(design_id).replace("🔒 ", "🔒 RESEARCH: ")


func _lock_suffix(design_id: String) -> String:
	var reason := _design_lock_reason(design_id)
	if reason.is_empty():
		return "🔒 Research required"
	return "%s %s" % [_design_lock_kind_icon(design_id), reason]


func _apply_row_color(
	row_idx: int,
	design_id: String,
	status: DesignManager.DesignStatus,
	is_foreign: bool,
	locked_section: bool,
) -> void:
	if locked_section:
		var locked_base := LOCKED_ROW_BASE
		if is_foreign and typeof(DesignManager) != TYPE_NIL:
			locked_base = locked_base.lerp(
				DesignManager.acquisition_row_color(country_tag, design_id),
				0.35,
			)
		design_list.set_item_custom_fg_color(row_idx, locked_base.lerp(RetrowaveTheme.TEXT_PRIMARY, 0.12))
		return
	if (
		not is_foreign
		and typeof(DesignManager) != TYPE_NIL
		and DesignManager.is_only_design_in_role(country_tag, design_id)
	):
		design_list.set_item_custom_fg_color(row_idx, RetrowaveTheme.SUCCESS)
		return
	if is_foreign and typeof(DesignManager) != TYPE_NIL:
		design_list.set_item_custom_fg_color(
			row_idx,
			DesignManager.acquisition_row_color(country_tag, design_id),
		)
		return
	if typeof(DesignManager) != TYPE_NIL:
		var nation := DesignManager.get_design_nation_tag(design_id)
		if nation.is_empty():
			design_list.set_item_custom_fg_color(row_idx, ROW_UNIVERSAL)
			return
		if status == DesignManager.DesignStatus.ACTIVE:
			design_list.set_item_custom_fg_color(row_idx, ROW_DOMESTIC)
			return
	match status:
		DesignManager.DesignStatus.PREVIOUSLY_USED:
			design_list.set_item_custom_fg_color(row_idx, HEADER_PREVIOUS)
		DesignManager.DesignStatus.OBSOLETE:
			design_list.set_item_custom_fg_color(row_idx, HEADER_OBSOLETE)
		_:
			if (
				typeof(DesignManager) != TYPE_NIL
				and DesignManager.get_design_domain(design_id) == DesignManager.DOMAIN_SPACE
			):
				design_list.set_item_custom_fg_color(row_idx, RetrowaveTheme.MAGENTA)
			else:
				design_list.set_item_custom_fg_color(row_idx, RetrowaveTheme.TEXT_PRIMARY)


func _sync_list_scroll_size() -> void:
	var row_h := float(design_list.get_theme_constant("v_separation", "ItemList")) + 22.0
	var content_h := float(maxi(design_list.get_item_count(), 1)) * row_h
	var vp_size := get_viewport().get_visible_rect().size
	var viewport_budget := clampf(float(vp_size.y) * 0.85 - 320.0, float(MIN_LIST_HEIGHT), float(MAX_LIST_HEIGHT))
	design_list.custom_minimum_size.y = content_h
	list_scroll.custom_minimum_size.y = clampf(content_h, float(MIN_LIST_HEIGHT), viewport_budget)


func _scroll_list_to_top() -> void:
	list_scroll.set_deferred("scroll_vertical", 0)


func _is_design_selectable(design_id: String) -> bool:
	if typeof(DesignManager) != TYPE_NIL:
		if not DesignManager.is_design_factory_compatible(design_id, _get_factory()):
			return false
	if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
		var prov := _get_province()
		if prov != null:
			var gate := MapTechnologyContext.evaluate_province_design_gate(
				prov, design_id, country_tag, _get_factory(),
			)
			return bool(gate.get("allowed", true))
	return _factory_allows_design(design_id)


func _factory_allows_design(design_id: String) -> bool:
	if typeof(TechnologyManager) == TYPE_NIL:
		return true
	return bool(
		TechnologyManager.factory_can_build_design(country_tag, _get_factory(), design_id).get(
			"allowed",
			true,
		)
	)


func _on_search_changed(_new_text: String) -> void:
	_update_legend_visibility()
	_rebuild_list()


func _on_search_submitted(_new_text: String) -> void:
	var idx := _first_selectable_index()
	if idx < 0:
		return
	design_list.select(idx)
	_on_design_selected(idx)


func _first_selectable_index() -> int:
	for i in _list_entries.size():
		var entry: Dictionary = _list_entries[i]
		if bool(entry.get("is_header", false)) or bool(entry.get("locked", false)):
			continue
		var did := str(entry.get("design_id", ""))
		if did.is_empty():
			continue
		if _is_design_selectable(did):
			return i
	return -1


func _on_design_activated(index: int) -> void:
	if index < 0 or index >= _list_entries.size():
		return
	var entry: Dictionary = _list_entries[index]
	if bool(entry.get("is_header", false)) or bool(entry.get("locked", false)):
		return
	var did := str(entry.get("design_id", ""))
	if did.is_empty() or not _is_design_selectable(did):
		return
	selected_design = did
	_on_confirm_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _is_searching():
			search_edit.text = ""
			get_viewport().set_input_as_handled()


func _on_filters_changed(_value: Variant = null) -> void:
	_update_filter_labels()
	_update_factory_context_label()
	_rebuild_list()


func _update_filter_labels() -> void:
	show_obsolete_check.text = (
		"Showing older designs" if show_obsolete_check.button_pressed else "Show older designs"
	)
	show_obsolete_check.tooltip_text = (
		"Show Previously Used and Obsolete sections (domestic and foreign)"
		if not show_obsolete_check.button_pressed
		else "Hide Previously Used and Obsolete sections"
	)


func _update_default_lock_hint() -> void:
	if not selected_design.is_empty():
		return
	_update_summary_hint(_fetch_catalog())


func _update_lock_hint() -> void:
	if selected_design.is_empty():
		_update_default_lock_hint()
		_update_relocate_map_button()
		return

	var parts: PackedStringArray = []
	if GameData.design_data != null:
		var sel_t: UnitTemplate = GameData.design_data.get_template(selected_design)
		if sel_t != null and not sel_t.display_name.is_empty():
			parts.append(sel_t.display_name)
	if typeof(DesignManager) != TYPE_NIL:
		parts.append(DesignManager.format_origin_badge(country_tag, selected_design))
		match DesignManager.get_design_status(country_tag, selected_design):
			DesignManager.DesignStatus.PREVIOUSLY_USED:
				parts.append("Previously used — still buildable")
			DesignManager.DesignStatus.OBSOLETE:
				parts.append("Obsolete — export or emergency OK")

	if (
		typeof(DesignManager) != TYPE_NIL
		and not DesignManager.is_design_factory_compatible(selected_design, _get_factory())
	):
		lock_hint_label.text = " · ".join(parts) + " · Requires shipyard factory at a port."
		return

	var lock_reason := _design_lock_reason(selected_design)
	if lock_reason.is_empty():
		if (
			typeof(DesignManager) != TYPE_NIL
			and DesignManager.is_only_design_in_role(country_tag, selected_design)
		):
			parts.append("★ Only design in this role")
		parts.append("Ready to assign")
		if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
			var prov_ok := _get_province()
			if prov_ok != null:
				var fit_ok := MapTechnologyContext.build_design_province_fit_plain(
					prov_ok, selected_design, country_tag, _get_factory(),
				)
				if not fit_ok.is_empty():
					parts.append(fit_ok)
		lock_hint_label.text = " · ".join(parts)
		lock_hint_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
		_update_relocate_map_button()
		return
	else:
		if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
			var prov := _get_province()
			if prov != null:
				var fit: Dictionary = MapTechnologyContext.evaluate_design_province_fit(
					prov, selected_design, country_tag, _get_factory(),
				)
				var reloc := str(fit.get("relocate_target", "")).strip_edges()
				if reloc.is_empty():
					var rec: Dictionary = MapTechnologyContext.get_relocate_recommendation(
						prov, country_tag,
					)
					if bool(rec.get("should_relocate", false)):
						reloc = str(rec.get("primary_target", ""))
				if not reloc.is_empty():
					parts.append("↗ " + reloc)
		if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
			var prov := _get_province()
			if prov != null:
				var action_sel := MapTechnologyContext.build_production_action_plain(
					prov, selected_design, country_tag, _get_factory(),
				)
				if not action_sel.is_empty():
					parts.append(action_sel)
		parts.append(_lock_suffix(selected_design))
		if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
			var prov := _get_province()
			if prov != null:
				var fit_plain := MapTechnologyContext.build_design_province_fit_plain(
					prov, selected_design, country_tag, _get_factory(),
				)
				if not fit_plain.is_empty():
					parts.append(fit_plain)
				var choice := MapTechnologyContext.build_invest_vs_reloc_panel_plain(
					prov, country_tag,
				)
				if not choice.is_empty():
					parts.append(choice.replace("\n", " · "))
		else:
			var lock_action := _design_lock_action(selected_design)
			if not lock_action.is_empty():
				parts.append("→ " + lock_action)
		lock_hint_label.text = " · ".join(parts)
		lock_hint_label.add_theme_color_override("font_color", RetrowaveTheme.MAGENTA)
		_update_relocate_map_button()
		return
	if province_id > 0 and typeof(MapTechnologyContext) != TYPE_NIL:
		var prov := _get_province()
		if prov != null:
			var snap := MapTechnologyContext.collect_province_build_eligibility(prov, country_tag)
			var locked: Array = snap.get("locked_lines", [])
			if locked.size() > 0 and lock_reason.is_empty():
				parts.append("%d other locked line(s) in province" % locked.size())
				lock_hint_label.text = " · ".join(parts)
	lock_hint_label.add_theme_color_override("font_color", RetrowaveTheme.TEXT_DIM)
	_update_relocate_map_button()


func _on_design_selected(index: int) -> void:
	if index < 0 or index >= _list_entries.size():
		selected_design = ""
		confirm_button.disabled = true
		_update_lock_hint()
		return

	var entry: Dictionary = _list_entries[index]
	if bool(entry.get("is_header", false)) or bool(entry.get("locked", false)):
		selected_design = ""
		confirm_button.disabled = true
		design_list.deselect(index)
		_update_lock_hint()
		return

	selected_design = str(entry.get("design_id", ""))
	confirm_button.disabled = not _is_design_selectable(selected_design)
	_update_lock_hint()


func _on_confirm_pressed() -> void:
	if selected_design.is_empty() or not _is_design_selectable(selected_design):
		return
	# Assign mode: factory_id == 0 means unit design assign — never retool a factory.
	if _is_assign_mode():
		var did := selected_design
		if assign_callback.is_valid():
			assign_callback.call(did)
		design_chosen.emit(did)
		hide()
		call_deferred("queue_free")
		return
	var warning_scene: PackedScene = load("res://scenes/ui/RetoolingWarningPopup.tscn")
	if warning_scene == null:
		return
	var warning: RetoolingWarningPopup = warning_scene.instantiate() as RetoolingWarningPopup
	if warning == null:
		return
	warning.factory_id = factory_id
	warning.new_design = selected_design
	get_tree().root.add_child(warning)
	warning.popup_centered()
	hide()
	call_deferred("queue_free")


func _on_cancel_pressed() -> void:
	hide()
	call_deferred("queue_free")
