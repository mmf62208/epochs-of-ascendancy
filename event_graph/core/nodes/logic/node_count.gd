@tool
class_name EventNodeCount2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "Count"
	title       = "Count"
	category    = "Logic"
	description = "Limits execution to a set number of times. Output stops firing when the limit is reached."
	properties  = { 
		"limit": 3, 
		"reset_on_start": true,
		"_current_count": 0
	}


func get_trigger_inputs() -> Array[String]:
	return ["In", "Reset"]

func get_trigger_outputs() -> Array[String]:
	return ["Out", "Finished"]

func get_variable_inputs() -> Array[Dictionary]:
	return []

func get_variable_outputs() -> Array[Dictionary]:
	return [{"name": "count", "type": TYPE_INT}]


func on_flow_start() -> void:
	if properties.get("reset_on_start", true):
		properties["_current_count"] = 0
		emit_changed()


func get_variable_value(port_name: String) -> Variant:
	if port_name == "count":
		return properties.get("_current_count", 0)
	return super.get_variable_value(port_name)


func _execute(port_name: String) -> void:
	if port_name == "Reset":
		properties["_current_count"] = 0
		emit_changed()
		return
		
	var limit: int = int(properties.get("limit", 3))
	var count: int = int(properties.get("_current_count", 0))
	
	if count < limit:
		count += 1
		properties["_current_count"] = count
		emit_changed()
		trigger_output("Out")
	else:
		trigger_output("Finished")
