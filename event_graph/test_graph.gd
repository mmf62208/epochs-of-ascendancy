@tool
extends SceneTree
func _init():
	var ge = GraphEdit.new()
	print("has get_closest_connection_at_point: ", ge.has_method("get_closest_connection_at_point"))
	quit()
