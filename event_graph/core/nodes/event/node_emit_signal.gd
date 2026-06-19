@tool
class_name EventNodeEmitSignal
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "EmitSignal"
	title       = "Emit Signal"
	category    = "Event"
	description = "Emits a signal on the owning Node by name."
	properties  = { "signal_name": "" }


func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return [{"name": "signal_name", "type": TYPE_STRING}]

func get_variable_outputs() -> Array[Dictionary]:
	return []


func _execute(_port_name: String) -> void:
	var sig: String = properties.get("signal_name", "")
	# Note: owner_node access would need to be passed through the processor
	# For now, just emit the trigger output
	if not sig.is_empty():
		push_warning("[EventGraph] EmitSignal: '%s' (owner resolution not yet wired)" % sig)
	trigger_output("Out")
