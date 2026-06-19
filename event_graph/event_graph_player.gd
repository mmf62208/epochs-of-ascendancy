class_name EventGraphPlayer
extends Node

## Runtime node that executes a EventGraphResource.
## Add this node under an owner Node, assign `event_graph`, then call `start_flow()`.

@export var event_graph: EventGraphResource = null
@export var auto_start: bool = false

signal flow_started
signal flow_finished
signal node_executed(node_id: String)

var _processor: EventGraphProcessor = null


func _ready() -> void:
	if auto_start:
		start_flow()


func start_flow() -> void:
	if event_graph == null:
		push_error("[EventGraphPlayer] No EventGraphResource assigned on " + str(get_path()))
		return

	if is_running():
		push_warning("[EventGraphPlayer] Flow already running on " + str(get_path()))
		return

	var owner_ref: Node = get_parent()

	_processor = EventGraphProcessor.new(event_graph, owner_ref)
	add_child(_processor)

	_processor.flow_started.connect(func() -> void: flow_started.emit())
	_processor.flow_finished.connect(_on_finished)
	_processor.node_executed.connect(func(nid: String) -> void:
		node_executed.emit(nid)
	)

	_processor.execute()


func stop_flow() -> void:
	if _processor:
		_processor.stop()


func is_running() -> bool:
	return _processor != null and _processor.is_running()


func _on_finished() -> void:
	flow_finished.emit()
	if _processor:
		_processor.queue_free()
		_processor = null
