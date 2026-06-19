@tool
extends EditorPlugin

## EventGraph Plugin v2 entry point.
## Registers custom resource types, adds the editor panel to the bottom dock,
## and handles Inspector integration for EventGraphResource files.

const EditorPanelScript := preload("res://addons/event_graph/editor/event_graph_editor.gd")

var _editor_panel: Control = null
var _bottom_button: Button = null


func _enter_tree() -> void:
	# Register core resource classes
	add_custom_type("EventNodeResource", "Resource",
		preload("res://addons/event_graph/core/event_node_resource.gd"), null)
	add_custom_type("EventGraphResource", "Resource",
		preload("res://addons/event_graph/core/event_graph_resource.gd"), null)

	# Register built-in node data types
	add_custom_type("EventNodeStart", "EventNodeResource",
		preload("res://addons/event_graph/core/nodes/flow/node_start.gd"), null)
	add_custom_type("EventNodeFinish", "EventNodeResource",
		preload("res://addons/event_graph/core/nodes/flow/node_finish.gd"), null)
	add_custom_type("EventNodeWait", "EventNodeResource",
		preload("res://addons/event_graph/core/nodes/action/node_wait.gd"), null)
	add_custom_type("EventNodeBranch", "EventNodeResource",
		preload("res://addons/event_graph/core/nodes/logic/node_branch.gd"), null)
	add_custom_type("EventNodePrint", "EventNodeResource",
		preload("res://addons/event_graph/core/nodes/action/node_print.gd"), null)
	add_custom_type("EventNodeEmitSignal", "EventNodeResource",
		preload("res://addons/event_graph/core/nodes/event/node_emit_signal.gd"), null)
	add_custom_type("EventNodeCallMethod", "EventNodeResource",
		preload("res://addons/event_graph/core/nodes/action/node_call_method.gd"), null)

	# Register runtime nodes
	add_custom_type("EventGraphPlayer", "Node",
		preload("res://addons/event_graph/event_graph_player.gd"), null)
	add_custom_type("EventGraphProcessor", "Node",
		preload("res://addons/event_graph/core/event_graph_processor.gd"), null)

	# Build and add the editor panel
	_editor_panel = EditorPanelScript.new()
	_editor_panel.name = "EventGraph"
	_bottom_button = add_control_to_bottom_panel(_editor_panel, "EventGraph")

	# Trigger initial registry build (scans custom_nodes/ directory)
	EventNodeRegistry.rebuild()

	# Listen for file changes to rescan custom nodes
	get_editor_interface().get_resource_filesystem().filesystem_changed.connect(
		_on_filesystem_changed)


func _exit_tree() -> void:
	if _editor_panel:
		remove_control_from_bottom_panel(_editor_panel)
		_editor_panel.queue_free()
		_editor_panel = null

	remove_custom_type("EventNodeResource")
	remove_custom_type("EventGraphResource")
	remove_custom_type("EventNodeStart")
	remove_custom_type("EventNodeFinish")
	remove_custom_type("EventNodeWait")
	remove_custom_type("EventNodeBranch")
	remove_custom_type("EventNodePrint")
	remove_custom_type("EventNodeEmitSignal")
	remove_custom_type("EventNodeCallMethod")
	remove_custom_type("EventGraphPlayer")
	remove_custom_type("EventGraphProcessor")


## Called by Godot when a resource file is double-clicked in the FileSystem dock.
func _handles(object: Object) -> bool:
	return object is EventGraphResource


func _edit(object: Object) -> void:
	if object is EventGraphResource:
		make_bottom_panel_item_visible(_editor_panel)
		_editor_panel.load_graph(object as EventGraphResource)


func _on_filesystem_changed() -> void:
	# Rescan custom nodes directory when files change
	EventNodeRegistry.rebuild()
