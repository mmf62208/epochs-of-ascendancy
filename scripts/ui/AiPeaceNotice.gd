# scripts/ui/AiPeaceNotice.gd
## Small accept / decline notice for an AI peace offer to the player.
## Freed on the press, and mouse_filter is cleared first, so the release
## cannot sit on the map the way a leftover full-screen control did.
class_name AiPeaceNotice
extends PanelContainer

var _offer: Dictionary = {}


static func present(parent: Node, offer: Dictionary) -> AiPeaceNotice:
	if parent == null:
		return null
	var existing := parent.get_node_or_null("AiPeaceNotice")
	if existing is AiPeaceNotice:
		(existing as AiPeaceNotice).setup(offer)
		return existing
	var notice := AiPeaceNotice.new()
	notice.name = "AiPeaceNotice"
	parent.add_child(notice)
	notice.setup(offer)
	return notice


func setup(offer: Dictionary) -> void:
	_offer = offer.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2(12, 12)
	size = Vector2(320, 96)
	custom_minimum_size = Vector2(320, 96)
	for child in get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = "Peace offer %s – %s (%s)" % [
		str(offer.get("a", "")),
		str(offer.get("b", "")),
		str(offer.get("reason", "ai_peace")),
	]
	box.add_child(label)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var accept := Button.new()
	accept.name = "AcceptPeace"
	accept.text = "Accept peace"
	accept.pressed.connect(_on_accept)
	row.add_child(accept)
	var decline := Button.new()
	decline.name = "DeclinePeace"
	decline.text = "Decline"
	decline.pressed.connect(_on_decline)
	row.add_child(decline)


func _on_accept() -> void:
	_release_and_close()
	AiCredibleDomain.accept_player_offer()


func _on_decline() -> void:
	_release_and_close()
	AiCredibleDomain.decline_player_offer()


func _release_and_close() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_free()
