# scripts/ui/TradeOfferDetailsPanel.gd
class_name TradeOfferDetailsPanel
extends Window

## Offer Details Panel
##
## Shows rich information for a single offer using TradeManager.get_offer_display_data().
## Listens to TradeManager.offer_details_requested by default when added to the tree.
##
## Usage:
##   var panel = preload("res://scenes/ui/TradeOfferDetailsPanel.tscn").instantiate()
##   get_tree().root.add_child(panel)
##   panel.show_details(offer_id, player_tag)
##
## Or just add it once and let it react to the global signal.

var _current_offer_id: String = ""
var _player_country: String = "USA"

@onready var title_label: Label = $Margin/MainVBox/TitleLabel
@onready var parties_label: Label = $Margin/MainVBox/PartiesLabel
@onready var risk_label: Label = $Margin/MainVBox/RiskLabel
@onready var expiry_label: Label = $Margin/MainVBox/ExpiryLabel
@onready var items_vbox: VBoxContainer = $Margin/MainVBox/ItemsVBox
@onready var fairness_label: Label = $Margin/MainVBox/FairnessLabel
@onready var recommendation_label: Label = $Margin/MainVBox/RecommendationLabel
@onready var button_hbox: HBoxContainer = $Margin/MainVBox/ButtonHBox
@onready var accept_btn: Button = $Margin/MainVBox/ButtonHBox/AcceptButton
@onready var reject_btn: Button = $Margin/MainVBox/ButtonHBox/RejectButton
@onready var counter_btn: Button = $Margin/MainVBox/ButtonHBox/CounterButton
@onready var close_btn: Button = $Margin/MainVBox/ButtonHBox/CloseButton

var _counter_preview_label: Label   # Dynamic preview for counter-offer

# State for live counter-offer editing
var _counter_original_data: Dictionary = {}
var _counter_edited_offered: Array = []
var _counter_edited_requested: Array = []
var _counter_preview_container: VBoxContainer   # Container for the full editable preview UI
var _saved_counter_preset: Dictionary = {}      # Lightweight session-only custom preset (nice-to-have)

func _ready() -> void:
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label)

	# Try to get player country
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		_player_country = LeaderManager.get_player_country_tag()

	accept_btn.pressed.connect(_on_accept_pressed)
	reject_btn.pressed.connect(_on_reject_pressed)
	counter_btn.pressed.connect(_on_counter_pressed)
	close_btn.pressed.connect(_on_close_pressed)

	# Auto-connect to the global signal so any view can request details
	if typeof(TradeManager) != TYPE_NIL:
		if not TradeManager.offer_details_requested.is_connected(_on_details_requested):
			TradeManager.offer_details_requested.connect(_on_details_requested)

	hide()

func _on_details_requested(offer_id: String, for_country: String) -> void:
	if for_country != "":
		_player_country = for_country
	show_details(offer_id, _player_country)

func show_details(offer_id: String, for_country: String = "") -> void:
	if for_country != "":
		_player_country = for_country

	_current_offer_id = offer_id

	var data := {}
	if typeof(TradeManager) != TYPE_NIL:
		data = TradeManager.get_offer_display_data(offer_id, _player_country)

	if data.get("error") or data.get("status") != "PROPOSED" or data.get("is_expired", false):
		_show_stale_offer_message()
		return

	_populate_from_data(data)

	# Visual distinction for Black Market in the details window
	if data.get("visibility") == "BLACK":
		if typeof(RetrowaveTheme) != TYPE_NIL:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.18, 0.06, 0.09, 0.95)
			style.border_color = Color(0.85, 0.25, 0.35)
			style.set_border_width_all(2)
			style.set_corner_radius_all(6)
			add_theme_stylebox_override("panel", style)
	else:
		RetrowaveTheme.style_popup_root(self)

	popup_centered(Vector2(800, 600))

	# Subtle open animation for better feel
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.12)

func _populate_from_data(data: Dictionary) -> void:
	title_label.text = "Offer Details"

	# Parties
	parties_label.text = "%s  →  %s" % [
		data.get("from_display", data.get("from_tag", "?")),
		data.get("to_display", data.get("to_tag", "?"))
	]

	# Risk (Black Market)
	if data.get("visibility") == "BLACK":
		var risk_cat := data.get("risk_category", "medium")
		risk_label.text = "Risk Level: %s (%.0f%%)" % [risk_cat.capitalize(), data.get("risk_level", 0) * 100]
		if risk_cat == "extreme":
			risk_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		elif risk_cat == "high":
			risk_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		else:
			risk_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
		risk_label.tooltip_text = "Higher risk = more attractive terms but greater chance of exposure or scandal (AgentManager hooks exist for future detection)."
		risk_label.show()
	else:
		risk_label.hide()

	# Expiry
	var expires := int(data.get("expires_turn", -1))
	if expires > 0:
		expiry_label.text = "Expires Turn: %d" % expires
	else:
		expiry_label.text = "No expiry date"
	expiry_label.show()

	# Clear previous item rows
	for child in items_vbox.get_children():
		child.queue_free()

	# Offered section with stronger visual weight
	var offered_panel := PanelContainer.new()
	if typeof(RetrowaveTheme) != TYPE_NIL:
		RetrowaveTheme.style_detail_panel(offered_panel)
	items_vbox.add_child(offered_panel)

	var offered_vbox := VBoxContainer.new()
	offered_vbox.add_theme_constant_override("separation", 4)
	offered_panel.add_child(offered_vbox)

	var offered_header := Label.new()
	offered_header.text = "▲ OFFERED"
	RetrowaveTheme.style_column_header(offered_header)
	offered_vbox.add_child(offered_header)

	for item in data.get("offered", []):
		_add_item_row(offered_vbox, item)

	# Requested section (visually distinct)
	var requested_panel := PanelContainer.new()
	if typeof(RetrowaveTheme) != TYPE_NIL:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.18, 0.22, 0.9)
		style.border_color = Color(0.3, 0.65, 0.85)
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		requested_panel.add_theme_stylebox_override("panel", style)
	items_vbox.add_child(requested_panel)

	var requested_vbox := VBoxContainer.new()
	requested_vbox.add_theme_constant_override("separation", 4)
	requested_panel.add_child(requested_vbox)

	var requested_header := Label.new()
	requested_header.text = "▼ REQUESTED"
	RetrowaveTheme.style_column_header(requested_header)
	requested_vbox.add_child(requested_header)

	for item in data.get("requested", []):
		_add_item_row(requested_vbox, item)

	# Fairness & Risk section with better hierarchy
	var fairness := data.get("fairness", {})
	if not fairness.is_empty():
		var score := float(fairness.get("score", 1.0))
		fairness_label.text = "Fairness: %.2f" % score
		if score > 1.15:
			fairness_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
		elif score < 0.85:
			fairness_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		else:
			fairness_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.7))
		fairness_label.tooltip_text = "1.0 = fair. >1.0 good for you. The recommendation below explains strategic value (especially for PROVINCE/INTEL)."

		recommendation_label.text = fairness.get("recommendation", "")
		recommendation_label.show()
		fairness_label.show()
	else:
		fairness_label.hide()
		recommendation_label.hide()

	# Special Site Trade Capacity context (makes ports etc. feel impactful)
	var trade_bonus := float(data.get("trade_capacity_bonus", 0.0))
	if trade_bonus > 0.0:
		var trade_label := Label.new()
		trade_label.text = "Your Special Sites Trade Bonus: +%d" % int(trade_bonus)
		trade_label.add_theme_font_size_override("font_size", 11)
		trade_label.modulate = Color(0.5, 0.85, 0.6)
		trade_label.tooltip_text = "Developed ports and special sites increase your effective trade capacity and deal quality."
		# Insert after fairness if possible
		if fairness_label.get_parent():
			fairness_label.get_parent().add_child(trade_label)
		else:
			add_child(trade_label)

	# Enable/disable action buttons based on status
	var is_proposed := data.get("status") == "PROPOSED"
	accept_btn.disabled = not is_proposed
	reject_btn.disabled = not is_proposed
	counter_btn.disabled = not is_proposed

func _add_section_header(text: String) -> void:
	var header := Label.new()
	header.text = text
	RetrowaveTheme.style_column_header(header)
	items_vbox.add_child(header)

func _add_item_row(parent: VBoxContainer, item: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = "•  " + item.get("display_name", item.get("id", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_row_label(name_label)
	row.add_child(name_label)

	parent.add_child(row)

func _on_accept_pressed() -> void:
	if typeof(TradeManager) != TYPE_NIL and _current_offer_id != "":
		var success := TradeManager.accept_offer(_current_offer_id)
		if success and typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Offer accepted!", 2.5)
		hide()
		# The market view should refresh via its own listeners

func _on_reject_pressed() -> void:
	if typeof(TradeManager) != TYPE_NIL and _current_offer_id != "":
		TradeManager.reject_offer_from_ui(_current_offer_id, "Rejected from details panel")
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Offer rejected.", 2.0)
		hide()

func _on_counter_pressed() -> void:
	if typeof(TradeManager) == TYPE_NIL or _current_offer_id.is_empty():
		return

	var data := TradeManager.get_offer_display_data(_current_offer_id, _player_country)
	if data.is_empty() or data.get("error"):
		return

	# First click: show preview of the counter-offer
	if counter_btn.text == "Counter":
		_show_counter_preview(data)
		counter_btn.text = "Confirm Counter"
		counter_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		return

	# Second click: actually create it
	_create_reversed_counter(data)

func _show_counter_preview(data: Dictionary) -> void:
	# Clear any previous preview UI
	if _counter_preview_label and is_instance_valid(_counter_preview_label):
		_counter_preview_label.queue_free()
	if _counter_preview_container and is_instance_valid(_counter_preview_container):
		_counter_preview_container.queue_free()

	# Store original data for comparison
	_counter_original_data = data
	_counter_edited_offered = data.get("requested", []).map(func(i): return i.duplicate(true))
	_counter_edited_requested = data.get("offered", []).map(func(i): return i.duplicate(true))

	# Main preview container
	_counter_preview_container = VBoxContainer.new()
	_counter_preview_container.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = "COUNTER-OFFER EDITOR — You are creating a new offer with reversed terms. Adjust below before confirming."
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	RetrowaveTheme.style_body_label(header)
	header.tooltip_text = "Edit quantities freely. Use Bulk or Presets for quick strategic adjustments. Changes create a brand new visible counter-offer."
	_counter_preview_container.add_child(header)

	# Header row with Reset button
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	_counter_preview_container.add_child(header_row)

	var comparison := Label.new()
	comparison.text = "Original: They offered %s for %s" % [
		_format_items_summary(data.get("offered", [])),
		_format_items_summary(data.get("requested", []))
	]
	comparison.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	RetrowaveTheme.style_body_label(comparison)
	header_row.add_child(comparison)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Pure Reversal"
	reset_btn.pressed.connect(_reset_counter_to_original)
	RetrowaveTheme.style_secondary_button(reset_btn)
	header_row.add_child(reset_btn)

	# Bulk quantity adjust toolbar (nice-to-have)
	var bulk_hbox := HBoxContainer.new()
	bulk_hbox.add_theme_constant_override("separation", 4)
	_counter_preview_container.add_child(bulk_hbox)

	var bulk_label := Label.new()
	bulk_label.text = "Bulk:"
	RetrowaveTheme.style_body_label(bulk_label)
	bulk_label.tooltip_text = "Scale all quantities on both sides at once. Great for quick fairness tweaks."
	bulk_hbox.add_child(bulk_label)

	for mode in ["+10%", "-10%", "Halve", "Double", "50%"]:
		var b := Button.new()
		b.text = mode
		b.custom_minimum_size.x = 58
		b.pressed.connect(func(): _apply_bulk_scale(mode))
		RetrowaveTheme.style_secondary_button(b)
		b.tooltip_text = "Apply " + mode + " to every item in the counter"
		bulk_hbox.add_child(b)

	# Lightweight counter presets / templates row (nice-to-have)
	# Quick strategic starting points + session "save/load custom" support.
	var preset_hbox := HBoxContainer.new()
	preset_hbox.add_theme_constant_override("separation", 4)
	_counter_preview_container.add_child(preset_hbox)

	var preset_label := Label.new()
	preset_label.text = "Presets:"
	RetrowaveTheme.style_body_label(preset_label)
	preset_label.tooltip_text = "Quick strategic starting points or your own saved custom template (session only)."
	preset_hbox.add_child(preset_label)

	for p in ["Fair Split", "Aggressive", "Min Ask"]:
		var pb := Button.new()
		pb.text = p
		pb.custom_minimum_size.x = 72
		pb.pressed.connect(func(): _apply_counter_preset(p))
		RetrowaveTheme.style_secondary_button(pb)
		pb.tooltip_text = "Apply " + p + " preset to current counter"
		preset_hbox.add_child(pb)

	var save_btn := Button.new()
	save_btn.text = "Save Current"
	save_btn.custom_minimum_size.x = 78
	save_btn.pressed.connect(_save_current_preset)
	RetrowaveTheme.style_secondary_button(save_btn)
	save_btn.tooltip_text = "Remember this exact counter configuration for the rest of the session"
	preset_hbox.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load Saved"
	load_btn.custom_minimum_size.x = 78
	load_btn.pressed.connect(_load_saved_preset)
	RetrowaveTheme.style_secondary_button(load_btn)
	load_btn.tooltip_text = "Restore the last counter you saved with 'Save Current'"
	preset_hbox.add_child(load_btn)

	# Two sections
	var offer_section := _build_counter_side_section("You will OFFER these items:", _counter_edited_offered, true)
	_counter_preview_container.add_child(offer_section)

	var request_section := _build_counter_side_section("You will REQUEST these items:", _counter_edited_requested, false)
	_counter_preview_container.add_child(request_section)

	# Insert before the buttons
	var idx := button_hbox.get_index()
	$Margin/MainVBox.add_child(_counter_preview_container)
	$Margin/MainVBox.move_child(_counter_preview_container, idx)

func _format_items_summary(items: Array) -> String:
	if items.is_empty():
		return "nothing"
	var names := []
	for it in items:
		names.append(it.get("display_short", it.get("id", "?")))
	var result := ", ".join(names)
	if names.size() > 2:
		result = names[0] + " + " + str(names.size() - 1) + " more"
	return result

# Builds one side of the counter editor (either "You will offer" or "You will request")
func _build_counter_side_section(header_text: String, items: Array, is_offering_side: bool) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.name = "SideSection" + ( "Offer" if is_offering_side else "Request" )
	section.add_theme_constant_override("separation", 4)

	var header := Label.new()
	header.text = header_text
	header.add_theme_color_override("font_color", is_offering_side ? Color(0.5, 0.85, 1.0) : Color(1.0, 0.7, 0.5))
	RetrowaveTheme.style_body_label(header)
	section.add_child(header)

	for i in items.size():
		var item_row := _build_counter_item_row(items, i, is_offering_side)
		section.add_child(item_row)

	return section

# Builds a single editable item row with quantity controls and remove
func _build_counter_item_row(items: Array, index: int, is_offering_side: bool) -> HBoxContainer:
	var item = items[index]
	var original_item = null

	# Find matching original item for comparison (by id)
	var original_list = is_offering_side ? _counter_original_data.get("requested", []) : _counter_original_data.get("offered", [])
	for orig in original_list:
		if orig.get("id") == item.get("id"):
			original_item = orig
			break

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = item.get("display_short", item.get("id", "?"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_row_label(name_label)
	row.add_child(name_label)

	# Quantity controls
	var minus_btn := Button.new()
	minus_btn.text = "−"
	minus_btn.custom_minimum_size = Vector2(28, 26)
	minus_btn.pressed.connect(func(): _adjust_counter_quantity(items, index, -1, is_offering_side))
	RetrowaveTheme.style_secondary_button(minus_btn)
	row.add_child(minus_btn)

	var qty_edit := LineEdit.new()
	qty_edit.text = str(int(item.get("quantity", 0)))
	qty_edit.custom_minimum_size.x = 48
	qty_edit.text_changed.connect(func(new_text): _set_counter_quantity(items, index, new_text, is_offering_side))
	RetrowaveTheme.style_search(qty_edit)
	row.add_child(qty_edit)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(28, 26)
	plus_btn.pressed.connect(func(): _adjust_counter_quantity(items, index, +1, is_offering_side))
	RetrowaveTheme.style_secondary_button(plus_btn)
	row.add_child(plus_btn)

	# Enhanced color-coded diff visualization (nice-to-have)
	# Green (SUCCESS) for favorable change from your perspective (offering more or requesting less);
	# red for the opposite. Clear "orig → curr (Δ)" format with sign.
	if original_item:
		var orig_qty := int(original_item.get("quantity", 0))
		var curr_qty := int(item.get("quantity", 0))
		if orig_qty != curr_qty:
			var delta := curr_qty - orig_qty
			var sign := "+" if delta > 0 else "−"
			var delta_label := Label.new()
			delta_label.text = "(%d → %d  %s%d)" % [orig_qty, curr_qty, sign, abs(delta)]
			var is_favorable := (is_offering_side and delta > 0) or (not is_offering_side and delta < 0)
			var col := RetrowaveTheme.SUCCESS if is_favorable else Color(1.0, 0.55, 0.55)
			delta_label.add_theme_color_override("font_color", col)
			RetrowaveTheme.style_body_label(delta_label)
			row.add_child(delta_label)

	# Remove button (with light constraint)
	var remove_btn := Button.new()
	remove_btn.text = "×"
	remove_btn.custom_minimum_size = Vector2(28, 26)
	remove_btn.pressed.connect(func(): _remove_counter_item(items, index, is_offering_side))
	RetrowaveTheme.style_danger_button(remove_btn)
	row.add_child(remove_btn)

	return row

func _adjust_counter_quantity(items: Array, index: int, delta: int, is_offering_side: bool) -> void:
	var current_qty := float(items[index].get("quantity", 0))
	var new_qty := max(0.0, current_qty + delta)
	items[index]["quantity"] = new_qty
	_refresh_counter_preview_ui()

func _set_counter_quantity(items: Array, index: int, text: String, is_offering_side: bool) -> void:
	var new_qty := max(0.0, text.to_float())
	items[index]["quantity"] = new_qty

func _remove_counter_item(items: Array, index: int, is_offering_side: bool) -> void:
	if items.size() <= 1:
		LeaderEventUI.show_toast("Cannot remove the last item from this side of the counter.", 2.0, true)
		return
	items.remove_at(index)
	_refresh_counter_preview_ui()

# Rebuilds the preview UI after an edit (more robust)
func _refresh_counter_preview_ui() -> void:
	if not _counter_preview_container or not is_instance_valid(_counter_preview_container):
		return

	# Remove only the dynamic sections (keep the header and reset row)
	var children_to_remove := []
	for child in _counter_preview_container.get_children():
		if child is VBoxContainer and child.name.begins_with("SideSection"):
			children_to_remove.append(child)

	for child in children_to_remove:
		child.queue_free()

	# Re-add the two sections with current edited data
	var offer_section := _build_counter_side_section("You will OFFER these items:", _counter_edited_offered, true)
	offer_section.name = "SideSectionOffer"
	_counter_preview_container.add_child(offer_section)

	var request_section := _build_counter_side_section("You will REQUEST these items:", _counter_edited_requested, false)
	request_section.name = "SideSectionRequest"
	_counter_preview_container.add_child(request_section)

func _reset_counter_to_original() -> void:
	if _counter_original_data.is_empty():
		return

	_counter_edited_offered = _counter_original_data.get("requested", []).map(func(i): return i.duplicate(true))
	_counter_edited_requested = _counter_original_data.get("offered", []).map(func(i): return i.duplicate(true))

	_refresh_counter_preview_ui()

	if typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.show_toast("Counter reset to original reversal.", 1.5)


# Bulk scale helper for the counter editor toolbar (nice-to-have)
func _apply_bulk_scale(mode: String) -> void:
	if _counter_edited_offered.is_empty() and _counter_edited_requested.is_empty():
		return

	var factor := 1.0
	match mode:
		"+10%": factor = 1.10
		"-10%": factor = 0.90
		"Halve": factor = 0.5
		"Double": factor = 2.0
		"50%": factor = 0.5
		_:
			return

	for arr in [_counter_edited_offered, _counter_edited_requested]:
		for it in arr:
			var q := float(it.get("quantity", 0))
			it["quantity"] = max(0.0, q * factor)

	_refresh_counter_preview_ui()


# Lightweight preset helpers for the counter editor (nice-to-have)
func _apply_counter_preset(mode: String) -> void:
	if _counter_edited_offered.is_empty() and _counter_edited_requested.is_empty():
		return

	match mode:
		"Fair Split":
			# Halve quantities on both sides of the counter (balanced middle ground)
			for arr in [_counter_edited_offered, _counter_edited_requested]:
				for it in arr:
					it["quantity"] = max(0.0, float(it.get("quantity", 0)) * 0.5)
		"Aggressive":
			# Scale up what you are offering (more generous from your side)
			for it in _counter_edited_offered:
				it["quantity"] = float(it.get("quantity", 0)) * 1.5
		"Min Ask":
			# Scale down what you are requesting (easier for the other party to accept)
			for it in _counter_edited_requested:
				it["quantity"] = max(0.0, float(it.get("quantity", 0)) * 0.5)
		_:
			return

	_refresh_counter_preview_ui()

	if typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.show_toast("Preset applied: " + mode, 1.2)


func _save_current_preset() -> void:
	if _counter_edited_offered.is_empty() and _counter_edited_requested.is_empty():
		return
	_saved_counter_preset = {
		"offered": _counter_edited_offered.map(func(i): return i.duplicate(true)),
		"requested": _counter_edited_requested.map(func(i): return i.duplicate(true))
	}
	if typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.show_toast("Current counter saved as preset (session only).", 1.8)


func _load_saved_preset() -> void:
	if _saved_counter_preset.is_empty():
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("No saved preset yet. Use 'Save Current' first.", 2.0, true)
		return

	_counter_edited_offered = _saved_counter_preset.get("offered", []).map(func(i): return i.duplicate(true))
	_counter_edited_requested = _saved_counter_preset.get("requested", []).map(func(i): return i.duplicate(true))
	_refresh_counter_preview_ui()

	if typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.show_toast("Loaded your saved counter preset.", 1.5)

func _create_reversed_counter(data: Dictionary) -> void:
	# Use the live edited arrays if they exist (from the new editor)
	var final_offered := _counter_edited_offered if _counter_edited_offered.size() > 0 else data.get("requested", [])
	var final_requested := _counter_edited_requested if _counter_edited_requested.size() > 0 else data.get("offered", [])

	# Convert back to plain dicts for the manager (in case they have extra UI keys)
	var clean_offered := final_offered.map(func(i): return {
		"type": i.get("type"),
		"id": i.get("id"),
		"quantity": i.get("quantity"),
		"quality_modifier": i.get("quality_modifier", 1.0),
		"metadata": i.get("metadata", {})
	})
	var clean_requested := final_requested.map(func(i): return {
		"type": i.get("type"),
		"id": i.get("id"),
		"quantity": i.get("quantity"),
		"quality_modifier": i.get("quality_modifier", 1.0),
		"metadata": i.get("metadata", {})
	})

	var new_id := TradeManager.create_counter_offer(_current_offer_id, clean_offered, clean_requested)
	if new_id != "":
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Counter-offer created and added to the market!", 3.0)
		hide()
	else:
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Could not create counter-offer (offer may no longer be valid).", 2.5, true)

func _on_close_pressed() -> void:
	hide()

func _show_stale_offer_message() -> void:
	# Clear content
	for child in $Margin/MainVBox.get_children():
		if child != button_hbox and child != close_btn.get_parent():
			child.queue_free()

	var msg := Label.new()
	msg.text = "This offer is no longer available (it may have been accepted, rejected, or expired)."
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))
	$Margin/MainVBox.add_child(msg)

	# Disable actions
	accept_btn.disabled = true
	reject_btn.disabled = true
	counter_btn.disabled = true

	# Auto close after a few seconds
	await get_tree().create_timer(2.8).timeout
	if is_instance_valid(self):
		hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		hide()