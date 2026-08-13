# scripts/ui/TradeMarketView.gd
class_name TradeMarketView
extends Window

## Trade Market View
##
## Core list view for browsing and interacting with Trade offers.
## Connects directly to the excellent UI helpers in TradeManager:
##   - get_market_offers_display_data(...) for populating Public vs Black lists
##   - get_offer_display_data(...) for rich per-offer info
##   - request_offer_details(...) (emits signal for future details panel)
##   - accept_offer, reject_offer_from_ui, etc.
##
## This view is intentionally lightweight and code-driven (matching the style
## of MainMenu and other popups) to get a functional market browser quickly.
## Future sessions can add:
##   - Dedicated TradeOfferRow scene/component
##   - Full details panel (listening to offer_details_requested signal)
##   - Counter-offer flow
##   - Better search/sort UI controls
##   - Icons, better formatting, drag & drop, etc.
##
## How to open from elsewhere (e.g. TopInfoBar or future Diplomacy screen):
##   var view = preload("res://scenes/ui/TradeMarketView.tscn").instantiate()
##   get_tree().root.add_child(view)
##   view.show_market()
##
## Documentation on the data side lives in TradeManager's "TRADE UI INTEGRATION GUIDE".

const PLAYER_COUNTRY_FALLBACK := "USA"

var _current_mode: String = "PUBLIC"  # "PUBLIC", "BLACK", or "MY_OFFERS"
var _player_country: String = PLAYER_COUNTRY_FALLBACK
var _pending_bilateral_filter: String = ""   # Used for strong handoff from DiplomacyView

@onready var background: ColorRect = $Background
@onready var margin: MarginContainer = $Margin
@onready var main_vbox: VBoxContainer = $Margin/MainVBox
@onready var title_label: Label = $Margin/MainVBox/TitleLabel
@onready var mode_hbox: HBoxContainer = $Margin/MainVBox/ModeHBox
var public_button: Button
var black_button: Button
var my_offers_button: Button
var desk_button: Button
@onready var list_scroll: ScrollContainer = $Margin/MainVBox/ListScroll
@onready var list_vbox: VBoxContainer = $Margin/MainVBox/ListScroll/ListVBox
@onready var button_hbox: HBoxContainer = $Margin/MainVBox/ButtonHBox
@onready var refresh_button: Button = $Margin/MainVBox/ButtonHBox/RefreshButton
@onready var close_button: Button = $Margin/MainVBox/ButtonHBox/CloseButton

# Persistent convoys section for active protected trade flows (high-value: shows regional convoy protection from full naval regions)
var convoys_vbox: VBoxContainer = null
## Bilateral desk partner (from Diplomacy handoff or default ENG)
var _desk_partner: String = "ENG"

func _ready() -> void:
	# Try to get the real player country
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		_player_country = LeaderManager.get_player_country_tag()
	elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_player_country_tag_fallback"):
		_player_country = MapManager.get_player_country_tag_fallback()

	# Mode buttons (created dynamically for flexibility)
	public_button = Button.new()
	public_button.text = "Public Market"
	public_button.pressed.connect(_on_public_pressed)
	mode_hbox.add_child(public_button)

	black_button = Button.new()
	black_button.text = "Black Market"
	black_button.pressed.connect(_on_black_pressed)
	mode_hbox.add_child(black_button)

	my_offers_button = Button.new()
	my_offers_button.text = "My Offers"
	my_offers_button.pressed.connect(_on_my_offers_pressed)
	mode_hbox.add_child(my_offers_button)

	desk_button = Button.new()
	desk_button.text = "Trade Desk"
	desk_button.pressed.connect(_on_desk_pressed)
	mode_hbox.add_child(desk_button)

	# Styling (after buttons exist)
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label)
	RetrowaveTheme.style_secondary_button(public_button)
	RetrowaveTheme.style_secondary_button(black_button)
	RetrowaveTheme.style_secondary_button(my_offers_button)
	RetrowaveTheme.style_secondary_button(desk_button)
	RetrowaveTheme.style_primary_button(refresh_button)
	RetrowaveTheme.style_secondary_button(close_button)

	# Title
	title_label.text = "Trade Market"

	# Bottom buttons
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(_refresh_current_mode)
	close_button.text = "Close"
	close_button.pressed.connect(_on_close_pressed)

	# Start in Public Market
	_set_mode("PUBLIC")

	# Create persistent convoys section at top (always visible, above the scroll list for offers)
	convoys_vbox = VBoxContainer.new()
	main_vbox.add_child(convoys_vbox)
	# Position it after mode_hbox, before scroll (index 2 or 3)
	main_vbox.move_child(convoys_vbox, 3)
	_update_convoys_section()

	# Optional: Listen to TradeManager changes to auto-refresh (nice to have)
	if typeof(TradeManager) != TYPE_NIL:
		if not TradeManager.offer_created.is_connected(_on_trade_manager_changed):
			TradeManager.offer_created.connect(_on_trade_manager_changed)
		if not TradeManager.deal_accepted.is_connected(_on_trade_manager_changed):
			TradeManager.deal_accepted.connect(_on_trade_manager_changed)
		if not TradeManager.deal_rejected.is_connected(_on_trade_manager_changed):
			TradeManager.deal_rejected.connect(_on_trade_manager_changed)
		if not TradeManager.trade_flow_interdicted.is_connected(_on_trade_manager_changed):
			TradeManager.trade_flow_interdicted.connect(_on_trade_manager_changed)
		if not TradeManager.trade_flow_created.is_connected(_on_trade_manager_changed):
			TradeManager.trade_flow_created.connect(_on_trade_manager_changed)
			TradeManager.deal_rejected.connect(_on_trade_manager_changed)
		if not TradeManager.counter_offer_requested.is_connected(_on_counter_created):
			TradeManager.counter_offer_requested.connect(_on_counter_created)

func _on_trade_manager_changed(_a = null, _b = null, _c = null, _d = null) -> void:
	# Simple auto-refresh when offers change
	_refresh_current_mode()
	_update_convoys_section()

func _set_mode(new_mode: String) -> void:
	_current_mode = new_mode

	# Visual toggle for buttons
	RetrowaveTheme.style_secondary_button(public_button)
	RetrowaveTheme.style_secondary_button(black_button)
	RetrowaveTheme.style_secondary_button(my_offers_button)
	if desk_button:
		RetrowaveTheme.style_secondary_button(desk_button)

	if new_mode == "PUBLIC":
		RetrowaveTheme.style_primary_button(public_button)
	elif new_mode == "BLACK":
		RetrowaveTheme.style_primary_button(black_button)
	elif new_mode == "DESK":
		if desk_button:
			RetrowaveTheme.style_primary_button(desk_button)
	else:  # MY_OFFERS
		RetrowaveTheme.style_primary_button(my_offers_button)

	_refresh_current_mode()

func _on_public_pressed() -> void:
	_set_mode("PUBLIC")

func _on_black_pressed() -> void:
	_set_mode("BLACK")

func _on_my_offers_pressed() -> void:
	_set_mode("MY_OFFERS")

func _on_desk_pressed() -> void:
	_set_mode("DESK")

func _refresh_current_mode() -> void:
	_clear_list()

	if _current_mode == "DESK":
		_refresh_trade_desk()
		_update_convoys_section()
		return

	var visibility_filter = null
	if _current_mode == "PUBLIC":
		visibility_filter = TradeManager.TradeVisibility.PUBLIC
	elif _current_mode == "BLACK":
		visibility_filter = TradeManager.TradeVisibility.BLACK
	# For MY_OFFERS we fetch all and filter client-side

	var offers: Array = []
	if typeof(TradeManager) != TYPE_NIL:
		offers = TradeManager.get_market_offers_display_data(
			"",
			visibility_filter,
			_player_country
		)

	# Client-side filter for "My Offers" — expanded nice-to-have:
	# Now shows BOTH offers you initiated (SENT) and offers addressed to you (RECEIVED).
	# Role is attached so _add_offer_row can render a visible badge.
	if _current_mode == "MY_OFFERS":
		var filtered := []
		for o in offers:
			var from_me = o.get("from_tag") == _player_country
			var to_me = o.get("to_tag") == _player_country
			if from_me or to_me:
				var enriched = o.duplicate(true)
				if from_me and to_me:
					enriched["_my_role"] = "SENT/REC"
				elif from_me:
					enriched["_my_role"] = "SENT"
				else:
					enriched["_my_role"] = "RECEIVED"
				filtered.append(enriched)
		offers = filtered

	# Strong bilateral pre-filter support for DiplomacyView handoff
	if not _pending_bilateral_filter.is_empty():
		var f := _pending_bilateral_filter.to_upper()
		var filtered := []
		for o in offers:
			var from_t := str(o.get("from_tag", "")).to_upper()
			var to_t := str(o.get("to_tag", "")).to_upper()
			if from_t == f or to_t == f:
				filtered.append(o)
		offers = filtered
		_pending_bilateral_filter = ""  # consume after use

	# Gentle visual feedback on refresh
	list_vbox.modulate.a = 0.6
	var tw := create_tween()
	tw.tween_property(list_vbox, "modulate:a", 1.0, 0.18)

	for offer_data in offers:
		_add_offer_row(offer_data)

	_update_convoys_section()

func _clear_list() -> void:
	for child in list_vbox.get_children():
		child.queue_free()

func _add_offer_row(offer_data: Dictionary) -> void:
	var is_black = offer_data.get("visibility") == "BLACK"

	var row_panel := PanelContainer.new()
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.custom_minimum_size = Vector2(0, 58)

	if is_black:
		# Stronger "risky" visual treatment for Black Market
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.22, 0.06, 0.10, 0.92)
		style.border_color = Color(0.95, 0.25, 0.35)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		row_panel.add_theme_stylebox_override("panel", style)
	else:
		if typeof(RetrowaveTheme) != TYPE_NIL:
			RetrowaveTheme.style_detail_panel(row_panel)

	# Main content row
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	row_panel.add_child(content)

	# Left group: Parties + Expiry
	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 2)
	content.add_child(left_vbox)

	var parties_label := Label.new()
	parties_label.text = "%s → %s" % [offer_data.get("from_display", offer_data.from_tag), offer_data.get("to_display", offer_data.to_tag)]
	parties_label.custom_minimum_size.x = 200
	RetrowaveTheme.style_row_label(parties_label)
	left_vbox.add_child(parties_label)

	# My Offers role badge (SENT / RECEIVED) — nice-to-have expansion
	if offer_data.has("_my_role"):
		var role := str(offer_data.get("_my_role", ""))
		var badge := Label.new()
		badge.text = "[%s]" % role
		if role == "SENT":
			badge.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))  # cyan-ish (outgoing)
		elif role == "RECEIVED":
			badge.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))  # warm (incoming)
		else:
			badge.add_theme_color_override("font_color", Color(0.9, 0.6, 0.9))
		RetrowaveTheme.style_body_label(badge)
		left_vbox.add_child(badge)

	# Simple diplomatic status indicator for My Offers (and useful elsewhere)
	var status := str(offer_data.get("status", ""))
	if status != "" and status != "PROPOSED":
		var status_label := Label.new()
		var status_text := status.capitalize()
		if status == "ACCEPTED":
			status_text = "Accepted"
			status_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
		elif status == "REJECTED":
			status_text = "Rejected"
			status_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
		elif status == "EXPIRED":
			status_text = "Expired"
			status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		elif status == "CANCELLED":
			status_text = "Cancelled"
			status_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.8))
		status_label.text = "• " + status_text
		RetrowaveTheme.style_body_label(status_label)
		left_vbox.add_child(status_label)
	elif offer_data.has("_my_role") and offer_data.get("_my_role") == "RECEIVED":
		# Helpful diplomatic context for open incoming offers
		var waiting := Label.new()
		waiting.text = "• Waiting for your response"
		waiting.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		RetrowaveTheme.style_body_label(waiting)
		left_vbox.add_child(waiting)

	var expiry_label := Label.new()
	var expires := int(offer_data.get("expires_turn", -1))
	expiry_label.text = "Expires: %d" % expires if expires > 0 else "No expiry"
	RetrowaveTheme.style_detail_label(expiry_label)
	left_vbox.add_child(expiry_label)

	# Center: Items + Fairness/Risk
	var center_vbox := VBoxContainer.new()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.add_theme_constant_override("separation", 4)
	content.add_child(center_vbox)

	var items_label := Label.new()
	var offered_summary := _summarize_items(offer_data.get("offered", []))
	var requested_summary := _summarize_items(offer_data.get("requested", []))
	items_label.text = "%s  →  %s" % [offered_summary, requested_summary]
	items_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_row_label(items_label)
	center_vbox.add_child(items_label)

	# Fairness + Risk row
	var metrics_hbox := HBoxContainer.new()
	metrics_hbox.add_theme_constant_override("separation", 16)
	center_vbox.add_child(metrics_hbox)

	var fairness_label := Label.new()
	var fairness = offer_data.get("fairness", {})
	if not fairness.is_empty():
		var score := float(fairness.get("score", 1.0))
		fairness_label.text = "Fairness: %.2f" % score
		if score > 1.15:
			fairness_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		elif score < 0.9:
			fairness_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	else:
		fairness_label.text = ""
	RetrowaveTheme.style_row_label(fairness_label)
	metrics_hbox.add_child(fairness_label)

	if is_black:
		var risk_label := Label.new()
		var risk_cat = offer_data.get("risk_category", "medium")
		risk_label.text = "Risk: " + risk_cat.to_upper()
		if risk_cat == "extreme":
			risk_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.35))
		elif risk_cat == "high":
			risk_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
		else:
			risk_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
		RetrowaveTheme.style_row_label(risk_label)
		metrics_hbox.add_child(risk_label)

	# Right: Action buttons (grouped)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	content.add_child(actions)

	var details_btn := Button.new()
	details_btn.text = "Details"
	details_btn.custom_minimum_size.x = 72
	details_btn.pressed.connect(_on_details_pressed.bind(offer_data.id))
	RetrowaveTheme.style_secondary_button(details_btn)
	actions.add_child(details_btn)

	var accept_btn := Button.new()
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size.x = 68
	accept_btn.pressed.connect(_on_accept_pressed.bind(offer_data.id))
	RetrowaveTheme.style_primary_button(accept_btn)
	actions.add_child(accept_btn)

	var reject_btn := Button.new()
	reject_btn.text = "Reject"
	reject_btn.custom_minimum_size.x = 68
	reject_btn.pressed.connect(_on_reject_pressed.bind(offer_data.id))
	RetrowaveTheme.style_secondary_button(reject_btn)
	actions.add_child(reject_btn)

	list_vbox.add_child(row_panel)

	# Thin separator
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 1
	sep.modulate.a = 0.3
	list_vbox.add_child(sep)

func _summarize_items(items: Array) -> String:
	if items.is_empty():
		return "Nothing"
	var first = items[0]
	var name = first.get("display_short", first.get("id", "?"))
	if items.size() > 1:
		return name + " +%d" % (items.size() - 1)
	return name

func _on_details_pressed(offer_id: String) -> void:
	_open_details_panel(offer_id)

func _open_details_panel(offer_id: String) -> void:
	if typeof(TradeManager) != TYPE_NIL:
		# Prefer opening our own details panel instance
		var panel_scene := load("res://scenes/ui/TradeOfferDetailsPanel.tscn")
		if panel_scene:
			var panel = panel_scene.instantiate()
			get_tree().root.add_child(panel)
			panel.show_details(offer_id, _player_country)
		else:
			# Fallback to the signal
			TradeManager.request_offer_details(offer_id, _player_country)

func _on_accept_pressed(offer_id: String) -> void:
	if typeof(TradeManager) != TYPE_NIL:
		# Check if still valid before acting
		var current := TradeManager.get_offer_display_data(offer_id)
		if current.get("status") != "PROPOSED" or current.get("is_expired", false):
			LeaderEventUI.show_toast("This offer is no longer available.", 2.5, true)
			_refresh_current_mode()
			return

		var success := TradeManager.accept_offer(offer_id)
		if success and typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Offer accepted!", 2.5)
		_refresh_current_mode()

func _on_reject_pressed(offer_id: String) -> void:
	if typeof(TradeManager) != TYPE_NIL:
		var current := TradeManager.get_offer_display_data(offer_id)
		if current.get("status") != "PROPOSED" or current.get("is_expired", false):
			LeaderEventUI.show_toast("This offer is no longer available.", 2.5, true)
			_refresh_current_mode()
			return

		TradeManager.reject_offer_from_ui(offer_id, "Rejected from Trade Market")
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Offer rejected.", 2.0)
		_refresh_current_mode()

func _on_close_pressed() -> void:
	hide()

func _refresh_trade_desk() -> void:
	title_label.text = "Trade Desk — %s ↔ %s" % [_player_country, _desk_partner]
	if typeof(TradeManager) == TYPE_NIL or not TradeManager.has_method("build_trade_desk_board"):
		var err := Label.new()
		err.text = "Trade Desk API unavailable."
		RetrowaveTheme.style_body_label(err)
		list_vbox.add_child(err)
		return
	var board: Dictionary = TradeManager.build_trade_desk_board(_player_country, _desk_partner)
	var hdr := Label.new()
	hdr.text = "Strategic Compact Ledger · CRS %.0f · %s" % [
		float(board.get("crs", 0.0)),
		str((board.get("band", {}) as Dictionary).get("label", "Neutral")) if board.get("band") is Dictionary else "Neutral",
	]
	RetrowaveTheme.style_title(hdr)
	list_vbox.add_child(hdr)
	for w in board.get("warnings", []):
		var wl := Label.new()
		wl.text = "⚠ %s" % str(w)
		wl.modulate = Color(1.0, 0.75, 0.4)
		RetrowaveTheme.style_body_label(wl)
		list_vbox.add_child(wl)
	var power: Dictionary = board.get("power", {}) as Dictionary if board.get("power") is Dictionary else {}
	var mu: Dictionary = power.get("matchup", {}) as Dictionary if power.get("matchup") is Dictionary else {}
	var pl := Label.new()
	pl.text = "Power: %s (ratio %.2f)%s" % [
		str(mu.get("label", "peer")),
		float(mu.get("ratio", 1.0)),
		" · NUCLEAR ASYMMETRY" if bool(mu.get("nuclear_asymmetry", false)) else "",
	]
	RetrowaveTheme.style_body_label(pl)
	list_vbox.add_child(pl)
	var tr := Label.new()
	tr.text = "Transit: %s" % str(board.get("transit_plain", ""))
	RetrowaveTheme.style_body_label(tr)
	list_vbox.add_child(tr)
	var disc: Dictionary = board.get("discounts", {}) as Dictionary if board.get("discounts") is Dictionary else {}
	var dl := Label.new()
	dl.text = "Discounts: trade ×%.2f · tech ×%.2f%s · tariff treasury %.0f SUU" % [
		float(disc.get("trade_suu_mult", 1.0)),
		float(disc.get("tech_share_suu_mult", 1.0)),
		" · long-term" if bool(disc.get("long_term", false)) else "",
		float(board.get("tariff_treasury", 0.0)),
	]
	RetrowaveTheme.style_body_label(dl)
	list_vbox.add_child(dl)
	var pol: Dictionary = board.get("policy", {}) as Dictionary if board.get("policy") is Dictionary else {}
	var pol_l := Label.new()
	pol_l.text = "Policy: import tariff %.0f%% · export tariff %.0f%% · embargo %s · MFN %s" % [
		float(pol.get("import_tariff", 0.0)) * 100.0,
		float(pol.get("export_tariff", 0.0)) * 100.0,
		str(bool(pol.get("embargo", false))),
		str(bool(pol.get("mfn", false))),
	]
	RetrowaveTheme.style_body_label(pol_l)
	list_vbox.add_child(pol_l)
	var flags: Array = board.get("flags", []) as Array if board.get("flags") is Array else []
	if not flags.is_empty():
		var fl := Label.new()
		fl.text = "Concern flags: %s" % ", ".join(PackedStringArray(flags))
		RetrowaveTheme.style_body_label(fl)
		list_vbox.add_child(fl)
	# Quick partner chips for common majors
	var chip_row := HBoxContainer.new()
	for tag in ["ENG", "GER", "FRA", "SOV", "JAP", "ITA"]:
		if tag == _player_country:
			continue
		var b := Button.new()
		b.text = tag
		var tcopy: String = str(tag)
		b.pressed.connect(func():
			_desk_partner = tcopy
			_refresh_trade_desk()
		)
		RetrowaveTheme.style_secondary_button(b)
		chip_row.add_child(b)
	list_vbox.add_child(chip_row)


func _update_convoys_section() -> void:
	if convoys_vbox == null:
		return
	for child in convoys_vbox.get_children():
		child.queue_free()
	if typeof(TradeManager) == TYPE_NIL:
		return
	var active_flows: Array = TradeManager.get_active_trade_flows() if TradeManager.has_method("get_active_trade_flows") else []
	if active_flows.is_empty():
		var lbl := Label.new()
		lbl.text = "No active protected convoys."
		RetrowaveTheme.style_body_label(lbl)
		convoys_vbox.add_child(lbl)
		return
	var header := Label.new()
	header.text = "Active Convoys (%d) — delivery %% & attack reasons" % active_flows.size()
	RetrowaveTheme.style_title(header)
	convoys_vbox.add_child(header)
	for f in active_flows:
		if not (f is TradeFlow):
			continue
		var prot := float(f.metadata.get("regional_convoy_protection", 0.0))
		var lost: float = float(f.total_lost_to_interdiction)
		var ratio := float(f.metadata.get("last_delivery_ratio", 1.0))
		if ratio <= 0.0 and f.metadata.has("baseline_quantity_per_turn"):
			var base := float(f.metadata.get("baseline_quantity_per_turn", 0.0))
			if base > 0.001:
				ratio = clampf(f.quantity_per_turn / base, 0.0, 1.0)
		var reason := str(f.metadata.get("last_interdiction_plain", ""))
		var line := Label.new()
		if reason.is_empty():
			line.text = "  %s→%s: %.1f %s/turn · delivery %d%% · lost %.1f · prot %.0f%%" % [
				f.from_tag, f.to_tag, f.quantity_per_turn, f.item_id, int(ratio * 100.0), lost, prot * 100.0,
			]
		else:
			line.text = "  %s→%s: %d%% through — %s" % [f.from_tag, f.to_tag, int(ratio * 100.0), reason]
			line.modulate = Color(1.0, 0.7, 0.55)
		RetrowaveTheme.style_body_label(line)
		convoys_vbox.add_child(line)
	# Demo interdict with province attribution (harness)
	var demo_btn := Button.new()
	demo_btn.text = "Demo: Sub attack (prov attribution)"
	demo_btn.pressed.connect(func():
		if active_flows.size() > 0:
			var tf: TradeFlow = active_flows[0]
			if typeof(TradeManager) != TYPE_NIL:
				TradeManager.interdict_trade_flow(tf.flow_id, "submarine", 0.5, {
					"province_id": 42, "attacker_tag": "GER",
				})
				_update_convoys_section()
				if typeof(LeaderEventUI) != TYPE_NIL:
					LeaderEventUI.show_toast(TradeManager.format_transit_issue_plain(tf.from_tag, tf.to_tag), 4.0)
	)
	RetrowaveTheme.style_secondary_button(demo_btn)
	convoys_vbox.add_child(demo_btn)

func show_market(initial_mode: String = "PUBLIC", filter_country: String = "") -> void:
	_set_mode(initial_mode)
	popup_centered(Vector2(1100, 700))

	_update_convoys_section()

	# Strong pre-filtering support for DiplomacyView handoff
	if not filter_country.is_empty():
		_pending_bilateral_filter = filter_country
		_desk_partner = filter_country.strip_edges().to_upper()
		# The actual filter will be applied on first refresh via _refresh_current_mode
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Bilateral view: deals with " + filter_country + ". Open Trade Desk for power/transit/CRS.", 3.5)

# Optional: Call this from outside to show as a proper popup
func open_as_popup() -> void:
	show_market(_current_mode)

func _on_counter_created(_base_id: String, _from: String, _to: String) -> void:
	if typeof(LeaderEventUI) != TYPE_NIL:
		LeaderEventUI.show_toast("Counter-offer created! It is now visible in the market for the other party.", 3.0)
	_refresh_current_mode()

	# Stronger new counter-offer highlight (nice-to-have polish)
	# Walk backwards to find the most recent real row (skips separators)
	if list_vbox.get_child_count() > 0:
		for i in range(list_vbox.get_child_count() - 1, -1, -1):
			var child = list_vbox.get_child(i)
			if child is PanelContainer:
				var original_mod = child.modulate
				child.modulate = Color(1.4, 1.35, 0.6)  # warmer, more noticeable flash
				var tw := create_tween()
				tw.tween_property(child, "modulate", original_mod, 1.2)
				break
