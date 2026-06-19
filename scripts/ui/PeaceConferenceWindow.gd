# scripts/ui/PeaceConferenceWindow.gd
class_name PeaceConferenceWindow
extends Window

## Minimal but functional Peace Conference UI for 1918 Armistice.
## Builds dynamically (no heavy .tscn dependency for Phase 2).
## Features:
## - Shows current player + accumulated inclusion leverage from agent diplomacy missions.
## - Key term buckets with HISTORICAL badges.
## - "Resolve" that calls the Phase 1 applicator in GameData.
## - Outcome summary + toasts.
## - If pending_continuation (e.g. Ottoman historical partition), shows successor choice buttons.
##   This directly supports the user's request: after historical path for TUR, player can switch to any successor (or stashed nation like Romania).
##
## Usage (from debug, ScenarioLoader hook, or button):
##   var w = PeaceConferenceWindow.new()
##   get_tree().root.add_child(w)
##   w.popup_centered(Vector2(1100, 720))
##
## Ties into existing patterns: RetrowaveTheme, LeaderEventUI toasts, GameData.peace_state,
## AgentManager for leverage, LeaderManager for player tag.

const PLAYER_FALLBACK := "USA"

var _player_tag: String = PLAYER_FALLBACK
var _current_leverage: int = 0
var _selected_terms: Dictionary = {}

@onready var main_vbox: VBoxContainer = $Margin/MainVBox   # Will be created in code if needed

var title_label: Label
var leverage_label: Label
var delegation_label: Label
var terms_vbox: VBoxContainer
var resolve_btn: Button
var summary_label: Label
var continuation_vbox: VBoxContainer
var close_btn: Button

func _ready() -> void:
	# Make it a proper popup window
	title = "1918 Armistice Peace Conference"
	min_size = Vector2(1000, 650)
	RetrowaveTheme.style_popup_root(self)  # if available

	_build_ui()

	# Determine player
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_player_country_tag"):
		_player_tag = LeaderManager.get_player_country_tag()
	elif typeof(GameData) != TYPE_NIL:
		var ps: Dictionary = GameData.get_peace_state()
		if ps.has("player"):
			_player_tag = ps["player"]

	_current_leverage = 0
	if typeof(GameData) != TYPE_NIL:
		_current_leverage = GameData.get_inclusion_leverage(_player_tag)

	_populate_initial_state()
	popup_centered()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# Title
	title_label = Label.new()
	title_label.text = "Armistice & Peace Conference — November 1918"
	RetrowaveTheme.style_title(title_label)
	main_vbox.add_child(title_label)

	# Player + Leverage
	var player_hbox := HBoxContainer.new()
	main_vbox.add_child(player_hbox)

	var p_label := Label.new()
	p_label.text = "Your Nation: "
	RetrowaveTheme.style_body_label(p_label)
	player_hbox.add_child(p_label)

	var player_val := Label.new()
	player_val.text = _player_tag
	RetrowaveTheme.style_row_label(player_val)
	player_hbox.add_child(player_val)

	leverage_label = Label.new()
	leverage_label.text = " |  Inclusion Leverage from Agents: %d" % _current_leverage
	RetrowaveTheme.style_body_label(leverage_label)
	player_hbox.add_child(leverage_label)

	# Delegation note
	delegation_label = Label.new()
	delegation_label.text = "Agents with high 'influence' skill + committed leaders increase leverage before/during the conference (see Agent screen)."
	delegation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(delegation_label)
	main_vbox.add_child(delegation_label)

	# Terms section
	var terms_header := Label.new()
	terms_header.text = "Key Peace Terms (HISTORICAL options clearly marked — alt-history requires agent effort)"
	RetrowaveTheme.style_column_header(terms_header)
	main_vbox.add_child(terms_header)

	terms_vbox = VBoxContainer.new()
	terms_vbox.add_theme_constant_override("separation", 6)
	main_vbox.add_child(terms_vbox)

	# Add term bucket UIs
	_add_term_bucket("central_powers_seating", "Treatment of Central Powers at the Table", [
		{"id": "full_exclusion", "label": "HISTORICAL — Full Exclusion (Germany, Austria-Hungary, Ottomans dictated to)", "historical": true},
		{"id": "limited_observers", "label": "Limited Observers", "historical": false},
		{"id": "full_participants", "label": "Full Participants (Major Alt-History — requires heavy agent work)", "historical": false}
	])

	_add_term_bucket("reparations_germany", "German Reparations", [
		{"id": "harsh_versailles", "label": "HISTORICAL — Harsh (Full liability + heavy schedule)", "historical": true},
		{"id": "moderate", "label": "Moderate", "historical": false},
		{"id": "lenient_reconstruction", "label": "Lenient / Reconstruction-tied", "historical": false}
	])

	_add_term_bucket("military_restrictions", "Military Restrictions", [
		{"id": "strict_historical", "label": "HISTORICAL — Strict limits + demilitarized zones", "historical": true},
		{"id": "moderate_inspections", "label": "Moderate limits + inspections", "historical": false},
		{"id": "minimal", "label": "Minimal / Symbolic", "historical": false}
	])

	_add_term_bucket("territorial_adjustments", "Territorial & Colonial Adjustments", [
		{"id": "historical_versailles", "label": "HISTORICAL — Full Alsace-Lorraine, Polish Corridor, mandates", "historical": true},
		{"id": "moderate_revisions", "label": "Moderate Revisions (plebiscites/retained cores)", "historical": false}
	])

	_add_term_bucket("league_structure", "League of Nations / International Order", [
		{"id": "weak_league", "label": "HISTORICAL — Weak League (US absent, limited enforcement)", "historical": true},
		{"id": "stronger_pact", "label": "Stronger Structure / Regional Pacts", "historical": false}
	])

	_add_term_bucket("war_guilt", "War Guilt Language & Symbolic Terms", [
		{"id": "harsh_guilt", "label": "HISTORICAL — Explicit War Guilt + Article 231", "historical": true},
		{"id": "no_guilt_clause", "label": "No Explicit Guilt / Shared Responsibility", "historical": false}
	])

	# Real Dialogue integration (using the plugin the user enabled)
	var dialogue_btn := Button.new()
	dialogue_btn.text = "Use Real Dialogue for Central Powers Seating (Dialogue Manager sample)"
	RetrowaveTheme.style_primary_button(dialogue_btn)
	dialogue_btn.pressed.connect(_on_launch_dialogue_pressed)
	main_vbox.add_child(dialogue_btn)

	# Pre-conference leverage demo (agents first per design: Central Powers invest to force seat)
	var pre_btn := Button.new()
	pre_btn.text = "Simulate Pre-Conference Agent Leverage (secure_inclusion / honeypot / bribes — boosts for alt-history)"
	RetrowaveTheme.style_secondary_button(pre_btn)
	pre_btn.pressed.connect(func():
		if typeof(GameData) != TYPE_NIL:
			# Simulate outcomes from new diplomacy missions (high for Central Powers player)
			GameData.add_inclusion_leverage(_player_tag, 35, "preconf_secure_inclusion")
			_current_leverage = GameData.get_inclusion_leverage(_player_tag)
			_update_leverage_preview()
			summary_label.text = "Pre-conference leverage now %d (run high-influence agents before resolve for real effect). Alt terms now viable." % _current_leverage
	)
	main_vbox.add_child(pre_btn)

	var dialogue_note := Label.new()
	dialogue_note.text = "The dialogue will call GameData.record_term_choice live. Close the balloon, then Resolve the conference to see the full outcome + any successor options."
	dialogue_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(dialogue_note)
	main_vbox.add_child(dialogue_note)

	# Resolve
	resolve_btn = Button.new()
	resolve_btn.text = "Resolve Conference (Apply Terms + Agent Leverage)"
	RetrowaveTheme.style_primary_button(resolve_btn)
	resolve_btn.pressed.connect(_on_resolve_pressed)
	main_vbox.add_child(resolve_btn)

	# Summary area
	summary_label = Label.new()
	summary_label.text = "Conference not yet resolved. Choose terms above and resolve."
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(summary_label)
	main_vbox.add_child(summary_label)

	# Continuation section (populated after resolve if applicable)
	continuation_vbox = VBoxContainer.new()
	continuation_vbox.add_theme_constant_override("separation", 4)
	main_vbox.add_child(continuation_vbox)

	# Follow-on policies / ensuing years (PeaceTreatyPhasesDemo removed — use PolicyLawScreen).
	var policy_followup_btn := Button.new()
	policy_followup_btn.text = "Open Policy/Law Screen (1919+ follow-on policies)"
	RetrowaveTheme.style_secondary_button(policy_followup_btn)
	policy_followup_btn.pressed.connect(_open_policy_law_screen)
	main_vbox.add_child(policy_followup_btn)

	var cont_header := Label.new()
	cont_header.text = "Continuation / Successor Choice (after historical empire dissolution or defeat)"
	RetrowaveTheme.style_column_header(cont_header)
	continuation_vbox.add_child(cont_header)

	var cont_note := Label.new()
	cont_note.text = "Historical paths for collapsing powers (e.g. Ottoman) open the option to continue playing as a successor state or a nation where you stashed assets via agents."
	cont_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(cont_note)
	continuation_vbox.add_child(cont_note)

	# Close
	close_btn = Button.new()
	close_btn.text = "Close"
	RetrowaveTheme.style_secondary_button(close_btn)
	close_btn.pressed.connect(_on_close_pressed)
	main_vbox.add_child(close_btn)

func _add_term_bucket(bucket_id: String, header_text: String, options: Array) -> void:
	var bucket_vbox := VBoxContainer.new()
	bucket_vbox.add_theme_constant_override("separation", 2)

	var h := Label.new()
	h.text = header_text
	RetrowaveTheme.style_body_label(h)
	bucket_vbox.add_child(h)

	for opt in options:
		var btn := Button.new()
		var label_text := str(opt.get("label", opt.get("id")))
		if opt.get("historical", false):
			label_text = "[HISTORICAL] " + label_text
		btn.text = label_text
		btn.custom_minimum_size.x = 600
		RetrowaveTheme.style_secondary_button(btn)

		var bid := bucket_id
		var oid := str(opt.get("id"))
		btn.pressed.connect(func():
			_selected_terms[bid] = oid
			_update_term_button_styles(bucket_vbox, btn)
			_update_leverage_preview()
		)
		bucket_vbox.add_child(btn)

	terms_vbox.add_child(bucket_vbox)

func _update_term_button_styles(parent: VBoxContainer, selected_btn: Button) -> void:
	for child in parent.get_children():
		if child is Button:
			if child == selected_btn:
				RetrowaveTheme.style_primary_button(child)
			else:
				RetrowaveTheme.style_secondary_button(child)

func _populate_initial_state() -> void:
	# Default to some historical-ish choices for quick testing
	if _selected_terms.is_empty():
		_selected_terms = {
			"central_powers_seating": "full_exclusion",
			"reparations_germany": "harsh_versailles",
			"military_restrictions": "strict_historical",
			"territorial_adjustments": "historical_versailles",
			"league_structure": "weak_league",
			"war_guilt": "harsh_guilt"
		}
	_update_leverage_preview()

func _update_leverage_preview() -> void:
	leverage_label.text = " |  Inclusion Leverage from Agents: %d  (affects resolution strength)" % _current_leverage

func _on_resolve_pressed() -> void:
	if typeof(GameData) == TYPE_NIL:
		summary_label.text = "Error: GameData not available."
		return

	var result := GameData.apply_conference_resolution_1918(_player_tag, _selected_terms, _current_leverage)

	var text := "Conference Resolved for %s\n" % _player_tag
	text += "Leverage used: %d\n" % result.get("leverage_used", 0)
	text += "Modifiers applied: %s\n" % str(result.get("modifiers_applied", []))
	text += "Notes: %s\n" % " | ".join(result.get("notes", []))

	if result.get("pending_continuation"):
		text += "\nEMPIRE PARTITION / CONTINUATION AVAILABLE — see options below.\n"
		_populate_continuation_ui(result["pending_continuation"])

	summary_label.text = text

	# Toast via existing system
	if typeof(LeaderEventUI) != TYPE_NIL and LeaderEventUI.has_method("show_toast"):
		LeaderEventUI.show_toast("1918 Peace Conference resolved. Check summary.", 6.0)

	resolve_btn.disabled = true

	# Post-resolve: open Policy/Law for ensuing-years policy work (replaces removed PeaceTreatyPhasesDemo).
	_open_policy_law_screen()

func _populate_continuation_ui(pending: Dictionary) -> void:
	# Clear previous
	for c in continuation_vbox.get_children():
		if c != continuation_vbox.get_child(0) and c != continuation_vbox.get_child(1):  # keep header + note
			c.queue_free()

	var reason_label := Label.new()
	reason_label.text = "Reason: " + str(pending.get("reason", ""))
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(reason_label)
	continuation_vbox.add_child(reason_label)

	var old := str(pending.get("old_tag", ""))
	var opts: Array = pending.get("options", [])

	var choice_label := Label.new()
	choice_label.text = "Choose nation to continue playing as (or close window to observe the old tag under AI control):"
	RetrowaveTheme.style_body_label(choice_label)
	continuation_vbox.add_child(choice_label)

	for opt in opts:
		var b := Button.new()
		b.text = "Continue as " + str(opt)
		RetrowaveTheme.style_primary_button(b)
		var chosen := str(opt)
		b.pressed.connect(func():
			if typeof(GameData) != TYPE_NIL:
				var ok := GameData.execute_player_switch_to(chosen, "1918 peace continuation / successor")
				if ok:
					summary_label.text += "\n\nSWITCHED: You are now playing as %s." % chosen
					if typeof(LeaderEventUI) != TYPE_NIL:
						LeaderEventUI.show_toast("Player nation changed to %s" % chosen, 5.0)
			# Disable all choice buttons after one pick
			for child in continuation_vbox.get_children():
				if child is Button:
					child.disabled = true
		)
		continuation_vbox.add_child(b)

	var observe_note := Label.new()
	observe_note.text = "To observe without switching or restart the scenario, use the Main Menu."
	RetrowaveTheme.style_body_label(observe_note)
	continuation_vbox.add_child(observe_note)

func _open_policy_law_screen() -> void:
	var packed: PackedScene = load("res://scenes/ui/PolicyLawScreen.tscn") as PackedScene
	if packed == null:
		push_warning("PeaceConferenceWindow: PolicyLawScreen.tscn not found.")
		return
	var screen: Node = packed.instantiate()
	get_tree().root.add_child(screen)
	if screen.has_method("set_player_tag"):
		screen.call_deferred("set_player_tag", _player_tag)
	elif screen is Window:
		(screen as Window).popup_centered()

func _on_close_pressed() -> void:
	hide()
	queue_free()

func _on_launch_dialogue_pressed() -> void:
	if typeof(GameData) != TYPE_NIL:
		GameData.start_peace_term_dialogue_example(_player_tag, _current_leverage)
	else:
		summary_label.text = "GameData not available for dialogue."

	# After the user makes a choice in the balloon, the do lines will have updated the terms in GameData.
	# User can then click the main Resolve button.
	summary_label.text = "Dialogue launched. Make your choice in the balloon (the HISTORICAL path is marked). The choice calls back to GameData. Then click Resolve Conference above."

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		hide()
		queue_free()
