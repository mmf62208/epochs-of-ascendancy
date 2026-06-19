@tool
class_name EventNodeWait
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Wait"
	title       = "Wait"
	category    = "Flow"
	description = "Pauses execution for a set duration (seconds)."
	properties  = { "duration": 1.0 }


func get_trigger_inputs() -> Array[String]:
	return ["In"]

func get_trigger_outputs() -> Array[String]:
	return ["Out"]

func get_variable_inputs() -> Array[Dictionary]:
	return [{"name": "duration", "type": TYPE_FLOAT}]

func get_variable_outputs() -> Array[Dictionary]:
	return []


func _execute(_port_name: String) -> void:
	var duration: float = float(properties.get("duration", 1.0))
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var timer := tree.create_timer(duration)
		timer.timeout.connect(func() -> void:
			trigger_output("Out")
		)
	else:
		# Fallback: immediate
		trigger_output("Out")
