# scripts/ui/LeaderEventUI.gd
extends Node

## Connects LeaderManager signals to retirement popups and on-screen news toasts.

signal news_posted(entry: Dictionary)

const MAX_NEWS_ITEMS := 40
const TOAST_DURATION_SEC := 6.0

var news_history: Array[Dictionary] = []
var _retirement_queue: Array[String] = []
var _active_retirement_popup: RetirementOfferPopup = null
var _replacement_queue: Array[String] = []
var _active_replacement_popup: LeaderReplacementPickerPopup = null
var _toast_layer: CanvasLayer
var _toast_container: VBoxContainer

# Preloaded custom icons for event toasts (beyond unicode); riot for crisis/riot cats per graphics wiring.
var _riot_crowd_icon: Texture2D = null
var _space_icon: Texture2D = null
var _secret_space_icon: Texture2D = null
var _mech_icon: Texture2D = null
var _versailles_icon: Texture2D = null


func _ready() -> void:
	_ensure_toast_layer()
	_connect_leader_signals()
	if _riot_crowd_icon == null:
		_riot_crowd_icon = load("res://assets/graphics/icons/events/riot_crowd_64.png") as Texture2D
		if _riot_crowd_icon == null:
			push_warning("LeaderEventUI: Failed to load riot_crowd_64.png for custom toast icons")
	if _space_icon == null:
		_space_icon = load("res://assets/graphics/icons/space_race/space_race_milestones_graph_64.png") as Texture2D
		if _space_icon == null:
			_space_icon = load("res://assets/graphics/icons/space_race/first_spaceflight.png") as Texture2D  # fallback
	if _secret_space_icon == null:
		_secret_space_icon = load("res://assets/graphics/icons/space_race/secret_space_fleet_warship_64.png") as Texture2D
		if _secret_space_icon == null:
			_secret_space_icon = load("res://assets/graphics/icons/space_race/secret_space.png") as Texture2D
	if _mech_icon == null:
		_mech_icon = load("res://assets/graphics/units/mechs/mech_designer_hangar_64.png") as Texture2D
		if _mech_icon == null:
			_mech_icon = load("res://assets/graphics/units/mechs/mech_designer_icon.png") as Texture2D
	if _versailles_icon == null:
		_versailles_icon = load("res://assets/graphics/icons/peace/versailles_alt_1919_peace_64.png") as Texture2D
		if _versailles_icon == null:
			_versailles_icon = load("res://assets/graphics/icons/peace/versailles_treaty.png") as Texture2D


func _connect_leader_signals() -> void:
	if typeof(LeaderManager) == TYPE_NIL:
		return
	LeaderManager.leader_retirement_offered.connect(_on_retirement_offered)
	LeaderManager.leader_replacement_needed.connect(_on_leader_replacement_needed)
	LeaderManager.leader_died.connect(_on_leader_died)
	LeaderManager.leader_captured.connect(_on_leader_captured)
	LeaderManager.leader_introduced.connect(_on_leader_introduced)
	LeaderManager.officer_training_quality_notice.connect(_on_officer_training_quality_notice)


func _ensure_toast_layer() -> void:
	if _toast_layer != null:
		return
	_toast_layer = CanvasLayer.new()
	_toast_layer.name = "LeaderNewsLayer"
	_toast_layer.layer = 90
	add_child(_toast_layer)

	_toast_container = VBoxContainer.new()
	_toast_container.name = "ToastContainer"
	_toast_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toast_container.offset_left = -420.0
	_toast_container.offset_top = -280.0
	_toast_container.offset_right = -16.0
	_toast_container.offset_bottom = -16.0
	_toast_container.add_theme_constant_override("separation", 8)
	_toast_layer.add_child(_toast_container)


## Simple toast for save/menu/system feedback (non-news).
# Enhanced for important messages (toasts first): Always has close/dismiss X. For is_important, adds "Respond" button (e.g. opens PolicyLawScreen or launches dialogue for welfare/crisis choices).
# Clean, interactive, fun: Player informed immediately, can dismiss or act on cultural war / policy decisions.
func show_toast(message: String, duration_sec: float = 3.0, is_error: bool = false, is_important: bool = false, on_respond: Callable = Callable()) -> void:
	_ensure_toast_layer()
	var entry := {
		"title": "Notice" if not is_error else "Error",
		"body": message,
		"category": "error" if is_error else "system",
	}
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var icon2 := "📢" if not is_error else "⛔"
	var cat2 := "system" if not is_error else "error"
	# Flat panels only — ornamented 9-slice frame (panel_frame_512) eats ~48px corners
	# with unreadable "scroll" chrome; notices must stay legible.
	if is_error:
		var err_style := StyleBoxFlat.new()
		err_style.bg_color = Color("#2a1520")
		err_style.border_color = RetrowaveTheme.WARNING
		err_style.set_border_width_all(2)
		err_style.set_corner_radius_all(4)
		err_style.content_margin_left = 12
		err_style.content_margin_right = 12
		err_style.content_margin_top = 10
		err_style.content_margin_bottom = 10
		panel.add_theme_stylebox_override("panel", err_style)
	else:
		RetrowaveTheme.style_detail_panel_flat(panel)
	if entry.get("category") == "hand":
		var hand_style := StyleBoxFlat.new()
		hand_style.bg_color = Color(0.1, 0.05, 0.15)
		hand_style.border_color = Color(0.6, 0.4, 0.8, 0.6)
		hand_style.set_border_width_all(2)
		hand_style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", hand_style)
		# Add simple icon for system toasts
		icon2 = "ℹ️"

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title_row := HBoxContainer.new()
	# Custom riot icon TextureRect support also in simple show_toast path (e.g. direct "Riots: ..." calls from GameData)
	if ("riot" in message.to_lower() or is_important) and _riot_crowd_icon != null:
		var tr := TextureRect.new()
		tr.texture = _riot_crowd_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(16, 16)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(tr)
	elif ("space" in message.to_lower() or "moon" in message.to_lower() or "mars" in message.to_lower() or "secret space" in message.to_lower()) and (_space_icon != null or _secret_space_icon != null):
		var tr := TextureRect.new()
		tr.texture = _secret_space_icon if "secret" in message.to_lower() else _space_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(16, 16)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(tr)
	elif "mech" in message.to_lower() and _mech_icon != null:
		var tr := TextureRect.new()
		tr.texture = _mech_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(16, 16)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(tr)
	elif ("versailles" in message.to_lower() or "1919" in message.to_lower() or "1918 peace" in message.to_lower()) and _versailles_icon != null:
		var tr := TextureRect.new()
		tr.texture = _versailles_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(16, 16)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(tr)
	else:
		var icon_lbl := Label.new()
		icon_lbl.text = icon2 + " "
		icon_lbl.add_theme_font_size_override("font_size", 13)
		title_row.add_child(icon_lbl)
	var title_label := Label.new()
	title_label.text = str(entry.get("title", "Notice"))
	RetrowaveTheme.style_column_header(title_label)
	if is_error:
		title_label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
	title_row.add_child(title_label)

	# Close/dismiss X for all toasts (user request for important messages).
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.custom_minimum_size = Vector2(20, 20)
	close_btn.pressed.connect(func(): 
		if panel.get_parent():
			panel.get_parent().remove_child(panel)
			panel.queue_free()
	)
	title_row.add_child(close_btn)
	vbox.add_child(title_row)

	var body_label := Label.new()
	body_label.text = str(entry.get("body", ""))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(body_label)
	vbox.add_child(body_label)

	# For important (e.g. welfare/cultural crisis, depop narratives): Respond button for interactive play (opens policy or dialogue).
	if is_important:
		var respond_btn := Button.new()
		respond_btn.text = "Respond / View Policies"
		respond_btn.custom_minimum_size = Vector2(150, 24)
		respond_btn.pressed.connect(func():
			if on_respond.is_valid():
				on_respond.call()
			else:
				# Default: open PolicyLawScreen if available (via TopInfoBar or direct).
				if typeof(TopInfoBar) != TYPE_NIL:
					var bar = TopInfoBar.find_in_tree(get_tree())
					if bar and bar.has_method("_on_policies_pressed"):  # if wired
						bar._on_policies_pressed()
				# Fallback: toast reminder.
				show_toast("Open Policy / Law screen to adjust welfare/social services and respond to the cultural decision.", 4.0)
			# Dismiss after respond.
			if panel.get_parent():
				panel.get_parent().remove_child(panel)
				panel.queue_free()
		)
		vbox.add_child(respond_btn)

	_toast_container.add_child(panel)
	while _toast_container.get_child_count() > 4:
		_dismiss_toast(_toast_container.get_child(0) as PanelContainer)

	var timer := get_tree().create_timer(maxf(1.0, duration_sec))
	timer.timeout.connect(_on_toast_timer_expired.bind(panel), CONNECT_ONE_SHOT)


func post_news(title: String, body: String, category: String = "general") -> void:
	var year := 1936
	if typeof(LeaderManager) != TYPE_NIL and LeaderManager.has_method("get_current_year"):
		year = LeaderManager.get_current_year()
	var entry := {
		"title": title,
		"body": body,
		"category": category,
		"year": year,
		"time": Time.get_unix_time_from_system(),
	}
	news_history.append(entry)
	if news_history.size() > MAX_NEWS_ITEMS:
		news_history.pop_front()
	news_posted.emit(entry)
	if _should_skip_toast_ui():
		return
	_show_toast(entry)


func _should_skip_toast_ui() -> bool:
	# Headless Maginot / -s harness: toast timers + CanvasLayer hung quit after RESULT=PASS.
	# Graphical F5 1x still shows capture toasts (PLAYTEST item 14).
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return true
	if typeof(TimeManager) != TYPE_NIL and bool(TimeManager.get("_living_playtest_clock")):
		return true
	return false


func get_recent_news(limit: int = 10) -> Array[Dictionary]:
	var count := mini(limit, news_history.size())
	if count <= 0:
		return []
	return news_history.slice(news_history.size() - count, news_history.size())


func _show_toast(entry: Dictionary) -> void:
	_ensure_toast_layer()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(400, 0)
	# Start flat; category StyleBoxFlat below replaces — never use ornamented frame.

	# Better per-category styling + icons (unicode for event visual polish; tie to portraits later in lists)
	var cat := str(entry.get("category", "general")).to_lower()
	var icon := "📰"
	match cat:
		"war", "combat", "military": icon = "⚔️"
		"diplomatic", "espionage", "hand_event", "revelation": icon = "🤝"
		"crisis", "death", "capture": icon = "⚠️"
		"infrastructure", "econ": icon = "🏗️"
		"technology", "training": icon = "🔬"
		"hand_glimmer", "revelation_aid_player", "targeted", "narrative_escalation": icon = "👁️"
		"system", "golden": icon = "✨"
		"retirement", "intro": icon = "👤"
		"separatism", "independence": icon = "🏴"
		"sabotage", "sabotage_event": icon = "🛠️"
		"scandal", "manufactured": icon = "📰"
		"mutiny", "naval", "coastal": icon = "⚓"
		"famine", "weather_extreme": icon = "🌾"
	var cat_color := Color(0.8, 0.85, 0.95)
	if cat in ["war", "combat", "crisis", "death"]: cat_color = Color(0.95, 0.6, 0.55)
	elif cat in ["diplomatic", "revelation", "golden"]: cat_color = Color(0.5, 0.85, 0.7)
	elif "hand" in cat or "espionage" in cat: cat_color = Color(0.9, 0.7, 0.4)
	elif cat in ["separatism", "mutiny", "famine"]: cat_color = Color(0.85, 0.55, 0.55)
	elif cat in ["sabotage", "scandal"]: cat_color = Color(0.75, 0.65, 0.45)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.11, 0.16, 0.96)
	style.border_color = cat_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	# Custom TextureRect for crisis/riot category (use riot crowd asset instead of pure unicode for high-value events)
	var used_custom_icon := false
	if (cat == "crisis" or "riot" in cat or "riot" in str(entry.get("title","")).to_lower() or "riot" in str(entry.get("body","")).to_lower()) and _riot_crowd_icon != null:
		var tr := TextureRect.new()
		tr.texture = _riot_crowd_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(18, 18)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(tr)
		used_custom_icon = true
	elif ("space" in cat or "technology" in cat or "moon" in str(entry.get("title","")).to_lower() or "mars" in str(entry.get("title","")).to_lower() or "secret" in str(entry.get("title","")).to_lower() or "space" in str(entry.get("body","")).to_lower()) and (_space_icon != null or _secret_space_icon != null):
		var tr := TextureRect.new()
		tr.texture = _secret_space_icon if ("secret" in str(entry.get("title","")).to_lower() or "covert" in str(entry.get("body","")).to_lower()) else _space_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(18, 18)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(tr)
		used_custom_icon = true
	elif ("mech" in str(entry.get("title","")).to_lower() or "mech" in str(entry.get("body","")).to_lower() or "diesel" in str(entry.get("title","")).to_lower()) and _mech_icon != null:
		var tr := TextureRect.new()
		tr.texture = _mech_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(18, 18)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(tr)
		used_custom_icon = true
	elif ("versailles" in str(entry.get("title","")).to_lower() or "1919" in str(entry.get("title","")).to_lower() or "peace" in str(entry.get("title","")).to_lower() or "1918" in str(entry.get("title","")).to_lower()) and _versailles_icon != null:
		var tr := TextureRect.new()
		tr.texture = _versailles_icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.custom_minimum_size = Vector2(18, 18)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(tr)
		used_custom_icon = true
	if not used_custom_icon:
		var icon_label := Label.new()
		icon_label.text = icon + " "
		icon_label.add_theme_font_size_override("font_size", 14)
		header.add_child(icon_label)

	var title_label := Label.new()
	title_label.text = str(entry.get("title", "News"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_column_header(title_label)
	title_label.add_theme_color_override("font_color", cat_color)
	header.add_child(title_label)

	var dismiss_button := Button.new()
	dismiss_button.text = "×"
	dismiss_button.tooltip_text = "Dismiss notification"
	dismiss_button.custom_minimum_size = Vector2(32, 28)
	RetrowaveTheme.style_secondary_button(dismiss_button)
	header.add_child(dismiss_button)

	var body_label := Label.new()
	body_label.text = str(entry.get("body", ""))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(body_label)
	vbox.add_child(body_label)

	_toast_container.add_child(panel)
	while _toast_container.get_child_count() > 4:
		_dismiss_toast(_toast_container.get_child(0) as PanelContainer)

	var timer := get_tree().create_timer(TOAST_DURATION_SEC)
	timer.timeout.connect(_on_toast_timer_expired.bind(panel), CONNECT_ONE_SHOT)
	dismiss_button.pressed.connect(_dismiss_toast.bind(panel))


func _dismiss_toast(panel: PanelContainer) -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()


func _on_toast_timer_expired(panel: PanelContainer) -> void:
	_dismiss_toast(panel)


func _on_retirement_offered(leader_id: String) -> void:
	if leader_id.is_empty():
		return
	if leader_id not in _retirement_queue:
		_retirement_queue.append(leader_id)
	_try_show_next_retirement()


func _try_show_next_retirement() -> void:
	if _active_retirement_popup != null and is_instance_valid(_active_retirement_popup):
		return
	if _retirement_queue.is_empty():
		return

	var next_id: String = _retirement_queue[0]
	_retirement_queue.remove_at(0)
	var popup := RetirementOfferPopup.open_for_leader(next_id)
	if popup == null:
		return
	_active_retirement_popup = popup
	popup.retirement_completed.connect(_on_retirement_popup_completed)


func _on_retirement_popup_completed(resolved_leader_id: String, outcome: String) -> void:
	_active_retirement_popup = null
	var leader_name := _leader_display_name(resolved_leader_id)

	match outcome:
		"honors", "retired_anyway":
			post_news(
				"%s Retires" % leader_name,
				"%s has retired with honors. The nation gains prestige."
				% leader_name,
				"retirement",
			)
		"stayed":
			post_news(
				"%s Stays in Command" % leader_name,
				"\"Your country still needs you…\" %s will remain for one more year."
				% leader_name,
				"retirement",
			)
	_try_show_next_retirement()
	_try_show_next_replacement()


func _on_leader_replacement_needed(request: Dictionary) -> void:
	# Only player countries emit this signal (AI vacancies auto-resolve in LeaderManager).
	var request_id := str(request.get("request_id", ""))
	var country_tag := str(request.get("country_tag", ""))
	if request_id.is_empty() or not LeaderManager.is_player_country(country_tag):
		return
	if request_id not in _replacement_queue:
		_replacement_queue.append(request_id)
	_try_show_next_replacement()


func _try_show_next_replacement() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _active_retirement_popup != null and is_instance_valid(_active_retirement_popup):
		return
	if _active_replacement_popup != null and is_instance_valid(_active_replacement_popup):
		return
	if _replacement_queue.is_empty():
		return

	var next_id: String = _replacement_queue[0]
	_replacement_queue.remove_at(0)
	if LeaderManager.get_leader_replacement_request(next_id).is_empty():
		_try_show_next_replacement()
		return

	var popup := LeaderReplacementPickerPopup.open_for_request(next_id)
	if popup == null:
		return
	_active_replacement_popup = popup
	popup.replacement_completed.connect(_on_replacement_popup_completed)


func _on_replacement_popup_completed(
	request: Dictionary,
	new_leader_id: String,
	left_vacant: bool,
) -> void:
	_active_replacement_popup = null
	var vacancy_label := str(request.get("target_label", "command"))
	if left_vacant:
		post_news(
			"Command Vacant",
			"%s remains without a permanent commander for now." % vacancy_label,
			"military",
		)
	elif not new_leader_id.is_empty():
		var new_name := _leader_display_name(new_leader_id)
		post_news(
			"New Commander Assigned",
			"%s now leads %s." % [new_name, vacancy_label],
			"military",
		)
	_try_show_next_replacement()


func _on_leader_died(leader_id: String, cause: String) -> void:
	var leader_name := _leader_display_name(leader_id)
	var cause_text := cause.replace("_", " ")
	post_news(
		"%s Killed in Action" % leader_name if cause != "natural" else "%s Has Died" % leader_name,
		"%s is no longer with us (%s)." % [leader_name, cause_text],
		"death",
	)


func _on_leader_captured(leader_id: String, cause: String) -> void:
	var leader_name := _leader_display_name(leader_id)
	post_news(
		"%s Captured" % leader_name,
		"%s has been captured (%s)." % [leader_name, cause.replace("_", " ")],
		"capture",
	)


func _on_leader_introduced(leader_id: String) -> void:
	var leader_name := _leader_display_name(leader_id)
	post_news(
		"New Commander: %s" % leader_name,
		"%s has entered national command in %d."
		% [leader_name, LeaderManager.get_current_year()],
		"intro",
	)


func _on_officer_training_quality_notice(
	country_tag: String,
	message: String,
	severity: String,
) -> void:
	var title := "Officer Training — %s" % country_tag
	var category := "training"
	match severity:
		"success":
			title = "Training Excellence — %s" % country_tag
			category = "training_success"
		"warning":
			title = "Training Warning — %s" % country_tag
			category = "training_warning"
		"critical":
			title = "Training Crisis — %s" % country_tag
			category = "training_critical"
	post_news(title, message, category)


func _leader_display_name(leader_id: String) -> String:
	var summary := LeaderManager.get_leader_summary(leader_id)
	if summary.is_empty():
		return leader_id
	return str(summary.get("name", leader_id))
