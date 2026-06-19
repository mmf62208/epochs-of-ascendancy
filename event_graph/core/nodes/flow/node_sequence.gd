@tool
class_name EventNodeSequence2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Sequence"
	title       = "Sequence"
	category    = "Flow"
	description = "Fires the next output in sequence each time 'In' is triggered."
	properties  = { 
		"_output_count": 2,
		"_current_step": 0,
		"reset_on_start": true,
		"loop": false
	}


func get_trigger_inputs() -> Array[String]:
	return ["In", "Reset"]

func get_trigger_outputs() -> Array[String]:
	var count: int = properties.get("_output_count", 2)
	var outputs: Array[String] = []
	for i in range(count):
		outputs.append("Out " + str(i + 1))
	return outputs


func get_variable_inputs() -> Array[Dictionary]:
	return []

func get_variable_outputs() -> Array[Dictionary]:
	return [{"name": "current_step", "type": TYPE_INT}]


func get_custom_actions() -> Array:
	return [
		{"label": "Add Output", "method": "add_output_port"},
		{"label": "Remove Output", "method": "remove_output_port"}
	]

func add_output_port() -> void:
	var count: int = properties.get("_output_count", 2)
	properties["_output_count"] = count + 1

func remove_output_port() -> void:
	var count: int = properties.get("_output_count", 2)
	if count > 2:
		properties["_output_count"] = count - 1
		# If the current step is now out of bounds, adjust it
		var step: int = properties.get("_current_step", 0)
		if step >= count - 1:
			properties["_current_step"] = count - 2


func on_flow_start() -> void:
	if properties.get("reset_on_start", true):
		properties["_current_step"] = 0
		emit_changed()


func get_variable_value(port_name: String) -> Variant:
	if port_name == "current_step":
		return properties.get("_current_step", 0)
	return super.get_variable_value(port_name)


func _execute(port_name: String) -> void:
	if port_name == "Reset":
		properties["_current_step"] = 0
		emit_changed()
		return
		
	var count: int = properties.get("_output_count", 2)
	var step: int = int(properties.get("_current_step", 0))
	var loop: bool = properties.get("loop", false)
	
	if step >= count:
		if loop:
			step = 0
		else:
			# Not looping and reached the end, do nothing
			return
			
	# Fire the current step
	var out_port = "Out " + str(step + 1)
	
	# Increment for next time
	step += 1
	properties["_current_step"] = step
	emit_changed()
	
	trigger_output(out_port)
