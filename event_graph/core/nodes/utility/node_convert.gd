@tool
class_name EventNodeConvert2
extends EventNodeResource

var type_options = ["Int", "String", "Float", "Bool"]

func _init() -> void:
	ensure_node_id()
	node_name   = "Convert"
	title       = "Convert Type"
	category    = "Utility"
	description = "Pure Node: Converts a variable to a different type. Connect data ports without execution triggers."
	properties  = { 
		"from_type": {"options": type_options, "selected": 0},
		"to_type": {"options": type_options, "selected": 1}
	}


func get_trigger_inputs() -> Array[String]:
	return []

func get_trigger_outputs() -> Array[String]:
	return []


func get_variable_inputs() -> Array[Dictionary]:
	var from_idx = int(properties.get("from_type", {}).get("selected", 0))
	var t = _idx_to_type(from_idx)
	return [{"name": "Value", "type": t}]

func get_variable_outputs() -> Array[Dictionary]:
	var to_idx = int(properties.get("to_type", {}).get("selected", 1))
	var t = _idx_to_type(to_idx)
	return [{"name": "Result", "type": t}]


# Flags this node as a Pure Data Node, so the processor evaluates it recursively.
func is_pure() -> bool:
	return true


# Evaluates the output dynamically based on connected inputs.
func evaluate(port_name: String) -> Variant:
	if port_name != "Result":
		return null
		
	# The processor guarantees 'Value' is resolved before calling evaluate()
	var val = get_variable_value("Value") 
	if val == null:
		return null
		
	var to_idx = int(properties.get("to_type", {}).get("selected", 1))
	var to_type = _idx_to_type(to_idx)
	
	match to_type:
		TYPE_INT:
			if typeof(val) == TYPE_STRING:
				return val.to_int()
			return int(val)
		TYPE_FLOAT:
			if typeof(val) == TYPE_STRING:
				return val.to_float()
			return float(val)
		TYPE_STRING:
			return str(val)
		TYPE_BOOL:
			return bool(val)
			
	return val


func _idx_to_type(idx: int) -> int:
	match idx:
		0: return TYPE_INT
		1: return TYPE_STRING
		2: return TYPE_FLOAT
		3: return TYPE_BOOL
	return TYPE_NIL


func _execute(_port_name: String) -> void:
	# Pure nodes do not execute through the flow system.
	pass
