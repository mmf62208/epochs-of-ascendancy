# scripts/ui/CloseReleaseSwallow.gd
## One-shot leftover left-up swallow after a press-mode Close / × hide.
## Arm only while LMB is down (never frame × after release, never keyboard Close).
## A new left press clears without consuming. Expires after ~250 ms.
class_name CloseReleaseSwallow
extends Node

const NODE_NAME := "CloseReleaseSwallow"
const EXPIRE_MS := 250

var _armed: bool = true
var _armed_msec: int = 0


static func arm_from(origin: Node) -> void:
	# Frame × emits close_requested after the release; keyboard Close has no mouse.
	# Arming then would eat the next unrelated button-up / map select.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var host: Node = _host_for(origin)
	if host == null:
		return
	if host.get_node_or_null(NODE_NAME) != null:
		return
	var swallow := CloseReleaseSwallow.new()
	swallow.name = NODE_NAME
	host.add_child(swallow)


static func _host_for(origin: Node) -> Node:
	if origin == null:
		return null
	var tree: SceneTree = origin.get_tree()
	if tree != null and tree.root != null:
		return tree.root
	if origin.get_parent() != null:
		return origin.get_parent()
	return origin


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process(true)
	_armed_msec = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if not _armed:
		return
	if Time.get_ticks_msec() - _armed_msec >= EXPIRE_MS:
		_disarm()


func _disarm() -> void:
	_armed = false
	queue_free()


func _input(event: InputEvent) -> void:
	if not _armed:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		# Fresh press is a new gesture — drop leftover, do not eat this event.
		_disarm()
		return
	_armed = false
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()
	queue_free()
