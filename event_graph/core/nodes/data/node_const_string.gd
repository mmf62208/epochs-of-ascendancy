@tool
class_name EventNodeConstString2
extends EventNodeResource

func _init() -> void:
	ensure_node_id()
	node_name   = "ConstString"
	title       = "String"
	category    = "Data"
	description = "Pure Node: Outputs a constant string value."
	properties  = { "value": "" }

func get_trigger_inputs() -> Array[String]: return []
func get_trigger_outputs() -> Array[String]: return []

func get_variable_inputs() -> Array[Dictionary]: return []
func get_variable_outputs() -> Array[Dictionary]:
	return [{"name": "Value", "type": TYPE_STRING}]

func is_pure() -> bool: return true

func evaluate(port_name: String) -> Variant:
	if port_name == "Value":
		return str(properties.get("value", ""))
	return null

func _execute(_port_name: String) -> void: pass
