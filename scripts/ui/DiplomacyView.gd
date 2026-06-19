# scripts/ui/DiplomacyView.gd
class_name DiplomacyView
extends Window

## Diplomacy View
##
## A lightweight central hub for diplomatic activity.
## Designed to sit alongside the Trade system and consume its excellent
## diplomacy hooks (get_offers_between, other_party_tag, trade_deal_outcome, etc.).
##
## === Future Extension Points (for Opinion / Events / Packages) ===
## - Add opinion/relations data via a future RelationsManager or NationalModifierManager queries.
##   Example hook: _populate_relations_metrics could call a new get_opinion_with() method.
##   The "Pulse" line is a natural place to surface opinion deltas.
##
## - Listen to new diplomacy event signals when they exist (e.g., on_diplomatic_event).
##   Could trigger highlights or toasts in the bilateral list.
##
## - Support "Diplomatic Packages" by grouping offers that share metadata["diplomatic_package_id"].
##   The current _add_bilateral_offer_row could be extended with package badges/grouping.
##
## - The bilateral filter row (_bilateral_filter) + _add_bilateral_filter_button pattern
##   is designed to be easily extended (e.g., "High Value Only", "Expiring Soon", "Strategic Only").
##
## - Override or extend _refresh_view() and _add_bilateral_offer_row() for richer visuals
##   (e.g., adding opinion bars per row when data becomes available).
##
## - The _pending_bilateral_filter pattern in TradeMarketView shows how external views
##   (Diplomacy, future Relations screens) can drive strong pre-filtered context.
##
## See TradeManager.gd "Future Diplomacy / Relations Layer Integration" section for the backend contract.
##
## Current scope (minimal foundation):
## - Country selector (hardcoded majors for demo)
## - Bilateral trade activity pulled live from TradeManager
## - SENT/RECEIVED + status indicators (reusing Trade patterns)
## - Easy navigation to Trade Market pre-filtered for the selected country
## - Placeholder sections for future Relations / Opinion / Events
##
## How to open:
##   var view = preload("res://scenes/ui/DiplomacyView.tscn").instantiate()
##   get_tree().root.add_child(view)
##   view.popup_centered()
##
## Integration points (already wired in TopInfoBar):
##   - TopInfoBar DiplomacyButton now opens this view.
##   - Future: MainMenu entry, hotkey, etc.
##
## Trade ↔ Diplomacy connection:
##   - Uses TradeManager.get_market_offers_display_data(..., other_party_tag)
##   - Listens to trade_deal_outcome for live refresh
##   - "View in Trade Market" button uses search "involves:TAG" pattern

const PLAYER_COUNTRY_FALLBACK := "USA"
const MAJOR_POWERS := ["USA", "GER", "SOV", "ENG", "FRA", "JAP", "ITA"]

var _player_country: String = PLAYER_COUNTRY_FALLBACK
var _selected_country: String = ""

@onready var background: ColorRect = $Background
@onready var margin: MarginContainer = $Margin
@onready var main_vbox: VBoxContainer = $Margin/MainVBox
@onready var title_label: Label = $Margin/MainVBox/TitleLabel

var country_selector: OptionButton
var player_label: Label
var bilateral_title: Label
var bilateral_filter_hbox: HBoxContainer
var offers_scroll: ScrollContainer
var offers_vbox: VBoxContainer
var relations_metrics: HBoxContainer   # Dynamically populated metrics for Relations Overview

var _bilateral_filter: String = "ALL"  # ALL, SENT, RECEIVED

@onready var button_hbox: HBoxContainer = $Margin/MainVBox/ButtonHBox
@onready var refresh_btn: Button = $Margin/MainVBox/ButtonHBox/RefreshButton
@onready var trade_btn: Button = $Margin/MainVBox/ButtonHBox/TradeButton
@onready var close_btn: Button = $Margin/MainVBox/ButtonHBox/CloseButton

func _ready() -> void:
	RetrowaveTheme.style_popup_root(self)
	RetrowaveTheme.style_title(title_label)

	# Player country
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		_player_country = LeaderManager.get_player_country_tag()
	elif typeof(MapManager) != TYPE_NIL and MapManager.has_method("get_player_country_tag_fallback"):
		_player_country = MapManager.get_player_country_tag_fallback()

	title_label.text = "Diplomacy"

	_build_dynamic_ui()

	# Connect Trade signals for live updates
	if typeof(TradeManager) != TYPE_NIL:
		if not TradeManager.trade_deal_outcome.is_connected(_on_trade_outcome):
			TradeManager.trade_deal_outcome.connect(_on_trade_outcome)

	refresh_btn.pressed.connect(_refresh_view)
	trade_btn.pressed.connect(_open_trade_market_filtered)
	close_btn.pressed.connect(_on_close_pressed)

	# Default selection
	_selected_country = "GER" if _player_country != "GER" else "SOV"
	_populate_country_selector()
	_refresh_view()

	popup_centered(Vector2(1000, 620))

	# Subtle open animation
	margin.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(margin, "modulate:a", 1.0, 0.12)

func _build_dynamic_ui() -> void:
	# Player info
	player_label = Label.new()
	player_label.text = "Your Nation: " + _player_country
	RetrowaveTheme.style_row_label(player_label)
	main_vbox.add_child(player_label)

	# Country selector
	var selector_hbox := HBoxContainer.new()
	selector_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(selector_hbox)

	var sel_label := Label.new()
	sel_label.text = "View Relations With:"
	RetrowaveTheme.style_body_label(sel_label)
	selector_hbox.add_child(sel_label)

	country_selector = OptionButton.new()
	country_selector.custom_minimum_size.x = 140
	RetrowaveTheme.style_filter_option(country_selector)
	country_selector.item_selected.connect(_on_country_selected)
	selector_hbox.add_child(country_selector)

	# Bilateral section header
	bilateral_title = Label.new()
	bilateral_title.text = "Bilateral Trade Activity"
	RetrowaveTheme.style_column_header(bilateral_title)
	main_vbox.add_child(bilateral_title)

	# Simple filter row for bilateral offers (lightweight polish)
	bilateral_filter_hbox = HBoxContainer.new()
	bilateral_filter_hbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(bilateral_filter_hbox)

	var filter_label := Label.new()
	filter_label.text = "Show:"
	RetrowaveTheme.style_body_label(filter_label)
	bilateral_filter_hbox.add_child(filter_label)

	_add_bilateral_filter_button("All", "ALL")
	_add_bilateral_filter_button("Sent by you", "SENT")
	_add_bilateral_filter_button("Received by you", "RECEIVED")

	# Offers list
	offers_scroll = ScrollContainer.new()
	offers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	offers_scroll.custom_minimum_size.y = 220
	main_vbox.add_child(offers_scroll)

	offers_vbox = VBoxContainer.new()
	offers_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_vbox.add_theme_constant_override("separation", 4)
	offers_scroll.add_child(offers_vbox)

	# === Relations Overview (improved lightweight summary) ===
	var relations_panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(relations_panel)
	main_vbox.add_child(relations_panel)

	var rel_vbox := VBoxContainer.new()
	rel_vbox.add_theme_constant_override("separation", 4)
	relations_panel.add_child(rel_vbox)

	var rel_header := Label.new()
	rel_header.text = "Relations Overview"
	RetrowaveTheme.style_column_header(rel_header)
	rel_vbox.add_child(rel_header)

	# Metrics row (will be updated in _refresh_view)
	relations_metrics = HBoxContainer.new()
	relations_metrics.add_theme_constant_override("separation", 16)
	rel_vbox.add_child(relations_metrics)

	# Future extension point comment
	var rel_note := Label.new()
	rel_note.text = "Future: Opinion, prestige, diplomatic events, and national focus effects will integrate here via Relations system."
	rel_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(rel_note)
	rel_note.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	rel_vbox.add_child(rel_note)

	# 1918 Peace / Armistice Treaty Status (Phase 2+ surface in Diplomacy per DESIGN_1918_ARMISTICE... ; live leverage/terms/grievance for 50+ turn playtest feedback)
	var treaty_panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(treaty_panel)
	main_vbox.add_child(treaty_panel)
	var treaty_vbox := VBoxContainer.new()
	treaty_vbox.add_theme_constant_override("separation", 3)
	treaty_panel.add_child(treaty_vbox)
	var treaty_header := Label.new()
	treaty_header.text = "1918 Armistice Treaty Status + Ripples"
	RetrowaveTheme.style_column_header(treaty_header)
	treaty_vbox.add_child(treaty_header)
	var treaty_label := Label.new()
	treaty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if typeof(GameData) != TYPE_NIL and GameData.has_method("get_peace_state"):
		var ps: Dictionary = GameData.get_peace_state()
		var ptag := _player_country
		var lev := GameData.get_inclusion_leverage(ptag) if GameData.has_method("get_inclusion_leverage") else 0
		var gr := int(ps.get("grievance", {}).get(ptag, 0))
		var completed := ps.get("conference_1918_completed", false)
		var terms: Dictionary = ps.get("term_choices", {})
		var seat := str(terms.get("central_powers_seating", "pre-conference" if not completed else "resolved"))
		if completed:
			treaty_label.text = "Resolved. Lev used:%d Grievance:%d Seating:%s | %d terms recorded. Follow-ons (1919-1925) via TimeManager/year advance. Tech gates + spirits active. Use Agent diplomacy pre-resolve in replays for alt-history." % [lev, gr, seat, terms.size()]
		else:
			treaty_label.text = "Pre-conference. Inclusion leverage:%d (Central Powers: run 'Secure Seat', 'Honeypot', 'Bribe Minister' via Agents screen — high influence skill). Grievance:%d. F10 > Peace Conf to design deal. Ripples to tech/spirits/agents/leaders." % [lev, gr]
	else:
		treaty_label.text = "Peace state unavailable (init on 1918 scenario)."
	RetrowaveTheme.style_body_label(treaty_label)
	treaty_vbox.add_child(treaty_label)

	# === New: Agent Networks Status + Diplomatic Actions (flesh out beyond trade/1918 stub; persistent effects + detection surfaced)
	var agent_panel := PanelContainer.new()
	RetrowaveTheme.style_detail_panel(agent_panel)
	main_vbox.add_child(agent_panel)
	var agent_vbox := VBoxContainer.new()
	agent_vbox.add_theme_constant_override("separation", 3)
	agent_panel.add_child(agent_vbox)
	var agent_header := Label.new()
	agent_header.text = "Agent Networks & Operations (Persistent Effects + Detection)"
	RetrowaveTheme.style_column_header(agent_header)
	agent_vbox.add_child(agent_header)
	var agent_status := Label.new()
	if typeof(AgentManager) != TYPE_NIL:
		var nets := AgentManager.get_networks_for_country(_player_country) if AgentManager.has_method("get_networks_for_country") else []
		var net_text := "Your active networks: %d (supply/infra sabotage + intel; daily effects via Time)" % nets.size()
		if nets.size() > 0:
			net_text += " — Focuses: " + str(nets[0].focus if nets[0].has("focus") else "mixed")
		agent_status.text = net_text
		# Detection risk surface (polish persistent detection)
		if nets.size() > 0 and "detection_risk_accumulated" in nets[0]:
			agent_status.text += " | Detection risk accum: %.1f%%" % (float(nets[0].detection_risk_accumulated) * 100)
	else:
		agent_status.text = "Agent networks: use Agents screen to establish for persistent province pressure (effects persist, detection can dismantle)."
	RetrowaveTheme.style_body_label(agent_status)
	agent_vbox.add_child(agent_status)
	var net_note := Label.new()
	net_note.text = "Networks apply daily sabotage (depot throughput down, infra chip). Counter via missions or time decay. Detection posts news + reduces strength."
	net_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(net_note)
	net_note.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	agent_vbox.add_child(net_note)

	# Diplomatic Action buttons (flesh more features: actions launch toasts/news + optional dialogue; stub opinion/alliances)
	var dip_actions := HBoxContainer.new()
	dip_actions.add_theme_constant_override("separation", 8)
	agent_vbox.add_child(dip_actions)
	var guarantee_btn := Button.new()
	guarantee_btn.text = "Guarantee Independence"
	guarantee_btn.custom_minimum_size.x = 140
	RetrowaveTheme.style_secondary_button(guarantee_btn)
	guarantee_btn.pressed.connect(func():
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.post_news("Diplomatic Guarantee", "You guarantee %s independence. +Prestige for player, tension with rivals. (Agent ops can enforce or sabotage.)" % _selected_country, "diplomatic")
			LeaderEventUI.show_toast("Guarantee issued to " + _selected_country + " — relations shifted.", 4.0)
	)
	dip_actions.add_child(guarantee_btn)

	var alliance_btn := Button.new()
	alliance_btn.text = "Propose Alliance"
	alliance_btn.custom_minimum_size.x = 120
	RetrowaveTheme.style_secondary_button(alliance_btn)
	alliance_btn.pressed.connect(func():
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.post_news("Alliance Proposal", "Alliance offer to %s sent. Trade + mutual defense hooks. Success depends on current relations/leverage (use agents)." % _selected_country, "diplomatic")
			LeaderEventUI.show_toast("Alliance proposal to " + _selected_country, 3.0)
		# Optional dialogue launch for flavor
		if typeof(DialogueManager) != TYPE_NIL:
			var dip_res = load("res://data/peace/population_policies.dialogue")  # reuse any; real would have dip specific
			if dip_res:
				DialogueManager.show_dialogue_balloon(dip_res, "welfare_burden_crisis")  # placeholder branch for demo; future dedicated
	)
	dip_actions.add_child(alliance_btn)

	var intel_btn := Button.new()
	intel_btn.text = "Request Intel Share"
	intel_btn.custom_minimum_size.x = 120
	RetrowaveTheme.style_secondary_button(intel_btn)
	intel_btn.pressed.connect(func():
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Intel request to " + _selected_country + " (agent networks boost success chance).", 3.0)
			LeaderEventUI.post_news("Intel Exchange", "Requesting shared intel from %s via diplomatic channel + agent support." % _selected_country, "espionage")
	)
	dip_actions.add_child(intel_btn)

	# Stub opinion/relations display (flesh; future real RelationsManager, now heuristic from trade + hand)
	var opinion_label := Label.new()
	opinion_label.text = "Opinion (stub): Neutral (+0; future: deltas from deals, guarantees, agent influence, hand exposure)"
	RetrowaveTheme.style_body_label(opinion_label)
	agent_vbox.add_child(opinion_label)

	# Bottom buttons (reuse existing nodes from .tscn)
	refresh_btn.text = "Refresh"
	trade_btn.text = "View Deals in Trade Market"
	close_btn.text = "Close"

func _populate_country_selector() -> void:
	country_selector.clear()
	var idx := 0
	var selected_idx := 0
	for tag in MAJOR_POWERS:
		if tag == _player_country:
			continue
		country_selector.add_item(tag)
		if tag == _selected_country:
			selected_idx = idx
		idx += 1
	country_selector.selected = selected_idx

func _on_country_selected(_index: int) -> void:
	_selected_country = country_selector.get_item_text(_index)
	_refresh_view()

# Lightweight helper for bilateral offer filters
func _add_bilateral_filter_button(label: String, mode: String) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size.x = 90
	RetrowaveTheme.style_secondary_button(btn)

	if mode == _bilateral_filter:
		RetrowaveTheme.style_primary_button(btn)

	btn.pressed.connect(func():
		_bilateral_filter = mode
		_refresh_view()
	)

	bilateral_filter_hbox.add_child(btn)

func _refresh_view() -> void:
	if _selected_country.is_empty():
		return

	bilateral_title.text = "Bilateral Trade Activity — " + _selected_country

	for child in offers_vbox.get_children():
		child.queue_free()

	var offers := []
	if typeof(TradeManager) != TYPE_NIL:
		offers = TradeManager.get_market_offers_display_data(
			_player_country,
			_selected_country,
			_player_country
		)

	# Apply lightweight bilateral filter
	if _bilateral_filter != "ALL":
		var filtered := []
		for o in offers:
			var is_sent := str(o.get("from_tag", "")) == _player_country
			if _bilateral_filter == "SENT" and is_sent:
				filtered.append(o)
			elif _bilateral_filter == "RECEIVED" and not is_sent:
				filtered.append(o)
		offers = filtered

	if offers.is_empty():
		var empty := Label.new()
		empty.text = "No active proposed offers between " + _player_country + " and " + _selected_country + "."
		RetrowaveTheme.style_body_label(empty)
		offers_vbox.add_child(empty)
		return

	# Lightweight grouping for clarity when viewing "All"
	if _bilateral_filter == "ALL":
		var sent_offers := []
		var received_offers := []

		for o in offers:
			if str(o.get("from_tag", "")) == _player_country:
				sent_offers.append(o)
			else:
				received_offers.append(o)

		if sent_offers.size() > 0:
			var sent_header := Label.new()
			sent_header.text = "Your outgoing offers"
			sent_header.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
			RetrowaveTheme.style_body_label(sent_header)
			offers_vbox.add_child(sent_header)

			for o in sent_offers:
				_add_bilateral_offer_row(o)

		if received_offers.size() > 0:
			if sent_offers.size() > 0:
				var sep := HSeparator.new()
				sep.modulate.a = 0.3
				offers_vbox.add_child(sep)

			var recv_header := Label.new()
			recv_header.text = "Incoming offers"
			recv_header.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
			RetrowaveTheme.style_body_label(recv_header)
			offers_vbox.add_child(recv_header)

			for o in received_offers:
				_add_bilateral_offer_row(o)
	else:
		for offer in offers:
			_add_bilateral_offer_row(offer)

	# Populate improved Relations Overview metrics
	if typeof(TradeManager) != TYPE_NIL:
		_populate_relations_metrics(_player_country, _selected_country, offers)

		# === Interdiction Feedback: Show active/suspended TradeFlows for this bilateral pair ===
		var flows := TradeManager.get_active_trade_flows_between(_player_country, _selected_country)
		if flows.size() > 0:
			var flows_label := Label.new()
			var active_count := 0
			var suspended_count := 0
			for f in flows:
				if f.active:
					active_count += 1
				else:
					suspended_count += 1

			var text := "Active Trade Flows: %d" % active_count
			if suspended_count > 0:
				text += "  |  Suspended: %d" % suspended_count
				flows_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
			else:
				flows_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.6))

			# Show convoy protection from full regional control (trade/convoy wiring)
			if flows.size() > 0:
				var tf = flows[0]
				if tf.total_lost_to_interdiction > 0.01 or tf.metadata.has("regional_convoy_protection"):
					text += " | prot: %.0f%% lost: %.1f" % [100.0 * float(tf.metadata.get("regional_convoy_protection", 0.0)), tf.total_lost_to_interdiction]

			flows_label.text = text
			RetrowaveTheme.style_body_label(flows_label)
			relations_metrics.add_child(flows_label)
	else:
		_clear_relations_metrics()
		var fallback := Label.new()
		fallback.text = "Relations data unavailable"
		RetrowaveTheme.style_body_label(fallback)
		relations_metrics.add_child(fallback)

func _add_bilateral_offer_row(offer_data: Dictionary) -> void:
	var panel := PanelContainer.new()

	var from_tag := str(offer_data.get("from_tag", ""))
	var to_tag := str(offer_data.get("to_tag", ""))
	var is_from_me := from_tag == _player_country

	# Visual distinction: tint panels based on direction from player's perspective
	if is_from_me:
		# Outgoing / SENT — slight cyan tint
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.18, 0.22, 0.92)
		style.border_color = Color(0.3, 0.65, 0.85)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
	else:
		# Incoming / RECEIVED — warmer tint
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.14, 0.12, 0.92)
		style.border_color = Color(0.85, 0.55, 0.35)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	# Left: Direction + status
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	content.add_child(left)

	var dir_label := Label.new()
	dir_label.text = ("You → " + to_tag) if is_from_me else (from_tag + " → You")
	RetrowaveTheme.style_row_label(dir_label)
	left.add_child(dir_label)

	# Role badge (SENT / RECEIVED)
	var role := "SENT" if is_from_me else "RECEIVED"
	var badge := Label.new()
	badge.text = "[" + role + "]"
	if role == "SENT":
		badge.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	else:
		badge.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	RetrowaveTheme.style_body_label(badge)
	left.add_child(badge)

	# Status (reuse logic from TradeMarketView)
	var status := str(offer_data.get("status", ""))
	if status != "PROPOSED":
		var s_label := Label.new()
		s_label.text = "• " + status.capitalize()
		if status == "ACCEPTED":
			s_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
		elif status == "REJECTED":
			s_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
		else:
			s_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		RetrowaveTheme.style_body_label(s_label)
		left.add_child(s_label)

	# Expiry warning (lightweight improvement for clarity)
	var expires := int(offer_data.get("expires_turn", -1))
	if expires > 0:
		# Simple heuristic: warn if expires soon (within ~2 turns of typical game pace)
		var exp_label := Label.new()
		exp_label.text = "Expires turn " + str(expires)
		if expires <= 1940:  # rough "soon" threshold for demo
			exp_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		RetrowaveTheme.style_body_label(exp_label)
		left.add_child(exp_label)

	# Center: Items summary
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(center)

	var items_label := Label.new()
	var offered := _summarize_items(offer_data.get("offered", []))
	var requested := _summarize_items(offer_data.get("requested", []))
	items_label.text = offered + "  →  " + requested
	RetrowaveTheme.style_row_label(items_label)
	center.add_child(items_label)

	var fairness: Dictionary = offer_data.get("fairness", {})
	if not fairness.is_empty():
		var f_label := Label.new()
		var score := float(fairness.get("score", 1.0))
		f_label.text = "Fairness: %.2f" % score
		if score > 1.15:
			f_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		elif score < 0.9:
			f_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
		RetrowaveTheme.style_body_label(f_label)
		center.add_child(f_label)

	# Right: Actions
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	content.add_child(actions)

	var details_btn := Button.new()
	details_btn.text = "Details"
	details_btn.custom_minimum_size.x = 70
	RetrowaveTheme.style_secondary_button(details_btn)
	details_btn.pressed.connect(_on_offer_details.bind(offer_data.get("id", "")))
	actions.add_child(details_btn)

	# Quick action: Jump to Trade Market filtered for this bilateral pair
	var market_btn := Button.new()
	market_btn.text = "Market"
	market_btn.custom_minimum_size.x = 60
	RetrowaveTheme.style_secondary_button(market_btn)
	market_btn.pressed.connect(_open_trade_market_for_country.bind(_selected_country))
	actions.add_child(market_btn)

	offers_vbox.add_child(panel)

	# Thin separator
	var sep := HSeparator.new()
	sep.modulate.a = 0.25
	offers_vbox.add_child(sep)

func _summarize_items(items: Array) -> String:
	if items.is_empty():
		return "Nothing"
	var first: Dictionary = items[0]
	var name := str(first.get("display_short", first.get("id", "?")))
	if items.size() > 1:
		return name + " +" + str(items.size() - 1)
	return name

# === Relations Overview Helpers (lightweight, Trade-driven) ===
func _clear_relations_metrics() -> void:
	if relations_metrics:
		for child in relations_metrics.get_children():
			child.queue_free()

func _populate_relations_metrics(player_tag: String, other_tag: String, current_offers: Array) -> void:
	_clear_relations_metrics()

	if typeof(TradeManager) == TYPE_NIL:
		return

	var summary := TradeManager.get_diplomatic_summary_with(player_tag, other_tag)

	# Metric 1: Active Deals
	var deals_label := Label.new()
	deals_label.text = "Active Deals: %d" % summary.get("active_offers", 0)
	RetrowaveTheme.style_row_label(deals_label)
	relations_metrics.add_child(deals_label)

	# Metric 2: Direction
	var dir_label := Label.new()
	dir_label.text = "You sent: %d  |  Received: %d" % [
		summary.get("sent_by_player", 0),
		summary.get("received_by_player", 0)
	]
	RetrowaveTheme.style_body_label(dir_label)
	relations_metrics.add_child(dir_label)

	# Metric 3: Diplomatic Activity (counters as engagement signal)
	var counter_count := 0
	for o in current_offers:
		if o.get("metadata", {}).get("is_counter", false):
			counter_count += 1

	var activity_label := Label.new()
	if counter_count > 0:
		activity_label.text = "Recent diplomatic engagement: %d counters" % counter_count
		activity_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	else:
		activity_label.text = "Steady diplomatic channel"
		activity_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.7))
	RetrowaveTheme.style_body_label(activity_label)
	relations_metrics.add_child(activity_label)

	# Metric 4: Simple Activity Level (lightweight heuristic)
	var total_activity: int = int(summary.get("active_offers", 0)) + counter_count
	var level_label := Label.new()
	var level_text := ""
	var level_color := Color(0.7, 0.75, 0.85)

	if total_activity >= 5:
		level_text = "High diplomatic activity"
		level_color = Color(0.4, 1.0, 0.6)
	elif total_activity >= 2:
		level_text = "Moderate diplomatic activity"
		level_color = Color(1.0, 0.9, 0.5)
	else:
		level_text = "Low diplomatic activity"

	level_label.text = level_text
	level_label.add_theme_color_override("font_color", level_color)
	RetrowaveTheme.style_body_label(level_label)
	relations_metrics.add_child(level_label)

	# Metric 5: Strategic Items in play (lightweight, high-value context)
	var strategic_count := 0
	for o in current_offers:
		for item in o.get("offered", []) + o.get("requested", []):
			var itype := str(item.get("type", ""))
			if itype in ["PROVINCE", "DESIGN"]:
				strategic_count += 1

	if strategic_count > 0:
		var strat_label := Label.new()
		strat_label.text = "Strategic items involved: %d" % strategic_count
		strat_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		RetrowaveTheme.style_body_label(strat_label)
		relations_metrics.add_child(strat_label)

	# New lightweight metric: Expiring Soon
	var expiring_soon := 0
	for o in current_offers:
		var exp := int(o.get("expires_turn", -1))
		if exp > 0 and exp <= 1942:  # rough "soon" threshold for the era
			expiring_soon += 1

	if expiring_soon > 0:
		var exp_label := Label.new()
		exp_label.text = "Expiring soon: %d" % expiring_soon
		exp_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		RetrowaveTheme.style_body_label(exp_label)
		relations_metrics.add_child(exp_label)

	# Relationship Pulse (lightweight textual summary) - made more prominent
	var pulse_label := Label.new()
	var pulse_text := ""
	var pulse_color := Color(0.7, 0.75, 0.85)

	if total_activity >= 5 or counter_count >= 2:
		pulse_text = "Active diplomatic channel with recent engagement"
		pulse_color = Color(0.4, 1.0, 0.7)
	elif total_activity >= 2:
		pulse_text = "Steady bilateral relationship"
		pulse_color = Color(0.7, 0.85, 0.7)
	else:
		pulse_text = "Low current diplomatic activity"

	pulse_label.text = "● Pulse: " + pulse_text
	pulse_label.add_theme_color_override("font_color", pulse_color)
	RetrowaveTheme.style_body_label(pulse_label)
	relations_metrics.add_child(pulse_label)

func _on_offer_details(offer_id: String) -> void:
	if typeof(TradeManager) != TYPE_NIL and not offer_id.is_empty():
		TradeManager.request_offer_details(offer_id, _player_country)

func _open_trade_market_filtered() -> void:
	_open_trade_market_for_country(_selected_country)

func _open_trade_market_for_country(country: String) -> void:
	if country.is_empty():
		return

	var packed := load("res://scenes/ui/TradeMarketView.tscn")
	if packed:
		var view = packed.instantiate()
		get_tree().root.add_child(view)
		if view.has_method("show_market"):
			view.show_market("PUBLIC", country)
		else:
			view.popup_centered(Vector2i(1100, 700))
	else:
		if typeof(LeaderEventUI) != TYPE_NIL:
			LeaderEventUI.show_toast("Trade Market not available.", 2.0, true)

func _on_trade_outcome(offer_id: String, from: String, to: String, _status: int, _vis, _meta) -> void:
	# Refresh if this deal involves the currently viewed bilateral pair
	if _selected_country.is_empty():
		return
	if from == _selected_country or to == _selected_country or from == _player_country or to == _player_country:
		_refresh_view()

func _on_close_pressed() -> void:
	hide()
	queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		hide()

# === Future Extension Points ===
# These stubs make it obvious where future features (opinion, events, packages) should live.

func _build_future_relations_section(parent: VBoxContainer) -> void:
	# Future: Add opinion bar, recent events list, package summary, etc.
	# Example:
	# var opinion_bar = ...
	# parent.add_child(opinion_bar)
	pass

# Example hook for future systems:
# func on_diplomatic_event_received(event: Dictionary) -> void:
#     if event.get("involves", "") == _selected_country:
#         _refresh_view()
#     pass
