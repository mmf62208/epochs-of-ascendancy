@tool
extends SceneTree

func _init():
	print("--- TEST START ---")
	
	var dir_path = "res://addons/event_graph/core/nodes/"
	print("dir_exists_absolute: ", DirAccess.dir_exists_absolute(dir_path))
	
	var dir = DirAccess.open(dir_path)
	print("dir open: ", dir != null)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			print("Found: ", file_name)
			if file_name.ends_with(".gd"):
				var full = dir_path.path_join(file_name)
				var script = load(full)
				print("Loaded script: ", script)
				if script:
					var inst = script.new()
					print("Inst: ", inst, " is EventNodeResource: ", inst is EventNodeResource)
			file_name = dir.get_next()
		dir.list_dir_end()
	
	EventNodeRegistry.rebuild()
	print("Registry size: ", EventNodeRegistry._cached_registry.size())
	for k in EventNodeRegistry._cached_registry:
		print(" - ", k)
	print("--- TEST END ---")
	quit()
