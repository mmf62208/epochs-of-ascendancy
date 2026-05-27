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


func _ready() -> void:
	_ensure_toast_layer()
	_connect_leader_signals()


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
func show_toast(message: String, duration_sec: float = 3.0, is_error: bool = false) -> void:
	_ensure_toast_layer()
	var entry := {
		"title": "Notice" if not is_error else "Error",
		"body": message,
		"category": "error" if is_error else "system",
	}
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	if is_error:
		var err_style := StyleBoxFlat.new()
		err_style.bg_color = Color("#2a1520")
		err_style.border_color = RetrowaveTheme.WARNING
		err_style.set_border_width_all(2)
		err_style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", err_style)
	else:
		RetrowaveTheme.style_detail_panel(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = str(entry.get("title", "Notice"))
	RetrowaveTheme.style_column_header(title_label)
	if is_error:
		title_label.add_theme_color_override("font_color", RetrowaveTheme.WARNING)
	vbox.add_child(title_label)

	var body_label := Label.new()
	body_label.text = str(entry.get("body", ""))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	RetrowaveTheme.style_body_label(body_label)
	vbox.add_child(body_label)

	_toast_container.add_child(panel)
	while _toast_container.get_child_count() > 4:
		_dismiss_toast(_toast_container.get_child(0) as PanelContainer)

	var timer := get_tree().create_timer(maxf(1.0, duration_sec))
	timer.timeout.connect(_on_toast_timer_expired.bind(panel), CONNECT_ONE_SHOT)


func post_news(title: String, body: String, category: String = "general") -> void:
	var entry := {
		"title": title,
		"body": body,
		"category": category,
		"year": LeaderManager.get_current_year(),
		"time": Time.get_unix_time_from_system(),
	}
	news_history.append(entry)
	if news_history.size() > MAX_NEWS_ITEMS:
		news_history.pop_front()
	news_posted.emit(entry)
	_show_toast(entry)


func get_recent_news(limit: int = 10) -> Array[Dictionary]:
	var count := mini(limit, news_history.size())
	if count <= 0:
		return []
	return news_history.slice(news_history.size() - count, news_history.size())


func _show_toast(entry: Dictionary) -> void:
	_ensure_toast_layer()
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	RetrowaveTheme.style_detail_panel(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title_label := Label.new()
	title_label.text = str(entry.get("title", "News"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RetrowaveTheme.style_column_header(title_label)
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
