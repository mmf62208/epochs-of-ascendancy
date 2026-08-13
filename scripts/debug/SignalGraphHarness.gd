class_name SignalGraphHarness
extends Node
## F11 / F10 harness entry for SignalGraphVisualizer — live signal graph for MapManager,
## day-package emissions, overlay updates, OrderCommandPanel routes.
## Does not pollute map scene hierarchy; spawns a Window like the visualizer itself.

const VISUALIZER_SCRIPT := preload("res://SignalGraphVisualizer.gd")

static var instance = null
var _visualizer: Window = null
var _last_scan_summary: Dictionary = {}


static func ensure() -> Node:
	if instance != null and is_instance_valid(instance):
		return instance as Node
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var existing: Node = tree.root.get_node_or_null("SignalGraphHarness")
	if existing != null:
		instance = existing
		return existing
	var h: Node = (load("res://scripts/debug/SignalGraphHarness.gd") as GDScript).new() as Node
	h.name = "SignalGraphHarness"
	tree.root.add_child(h)
	instance = h
	return h


static func toggle() -> void:
	var h: Node = ensure() as Node
	if h == null:
		return
	if h.has_method("toggle_window"):
		h.call("toggle_window")


static func show_graph() -> void:
	var h: Node = ensure() as Node
	if h == null:
		return
	if h.has_method("open_window"):
		h.call("open_window")


static func is_open() -> bool:
	return instance != null and is_instance_valid(instance) and instance._visualizer != null \
		and is_instance_valid(instance._visualizer) and instance._visualizer.visible


func toggle_window() -> void:
	if _visualizer != null and is_instance_valid(_visualizer) and _visualizer.visible:
		_visualizer.hide()
		return
	open_window()


func open_window() -> void:
	if OS.get_environment("EOA_HEADLESS_EVIDENCE") == "1":
		# Still allow programmatic scan summary for evidence without spawning UI.
		_last_scan_summary = scan_signal_summary()
		print("[SignalGraphHarness] headless scan nodes=%d connections=%d map_signals=%d panel_signals=%d"
			% [
				int(_last_scan_summary.get("node_n", 0)),
				int(_last_scan_summary.get("connection_n", 0)),
				int(_last_scan_summary.get("map_manager_signals", 0)),
				int(_last_scan_summary.get("order_panel_signals", 0)),
			])
		return
	if _visualizer == null or not is_instance_valid(_visualizer):
		_visualizer = VISUALIZER_SCRIPT.new() as Window
		_visualizer.name = "SignalGraphVisualizerWindow"
		_visualizer.auto_open_on_ready = true
		_visualizer.scan_on_open = true
		_visualizer.print_scan_summary = true
		_visualizer.window_title = "EOA Signal Graph — Map / Day / Panel"
		add_child(_visualizer)
	_visualizer.visible = true
	_visualizer.popup_centered()
	if _visualizer.has_method("_scan_and_rebuild"):
		_visualizer.call("_scan_and_rebuild")
	elif _visualizer.has_method("scan"):
		_visualizer.call("scan")
	_last_scan_summary = scan_signal_summary()
	print("[SignalGraphHarness] open nodes=%d connections=%d" % [
		int(_last_scan_summary.get("node_n", 0)),
		int(_last_scan_summary.get("connection_n", 0)),
	])


## Inventory-style summary for CI / headless (no screenshot required).
func scan_signal_summary() -> Dictionary:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return {"ok": false, "node_n": 0, "connection_n": 0, "empty": true}
	var acc: Dictionary = {
		"node_n": 0, "connection_n": 0, "map_manager_signals": 0,
		"order_panel_signals": 0, "overlay_signals": 0, "day_package_signals": 0,
	}
	_walk_signals_acc(tree.root, acc)
	var node_n: int = int(acc["node_n"])
	var connection_n: int = int(acc["connection_n"])
	return {
		"ok": connection_n > 0 or node_n > 0,
		"node_n": node_n,
		"connection_n": connection_n,
		"map_manager_signals": int(acc["map_manager_signals"]),
		"order_panel_signals": int(acc["order_panel_signals"]),
		"overlay_signals": int(acc["overlay_signals"]),
		"day_package_signals": int(acc["day_package_signals"]),
		"empty": false,
		"summary": "Signal graph · nodes %d · connections %d · map %d · panel %d"
			% [node_n, connection_n, int(acc["map_manager_signals"]), int(acc["order_panel_signals"])],
	}


func get_last_scan_summary() -> Dictionary:
	if _last_scan_summary.is_empty():
		_last_scan_summary = scan_signal_summary()
	return _last_scan_summary.duplicate(true)


func _walk_signals_acc(node: Node, acc: Dictionary) -> void:
	for sig_info in node.get_signal_list():
		var sig_name: String = str(sig_info.get("name", ""))
		var conns: Array = node.get_signal_connection_list(sig_name)
		if conns.is_empty():
			continue
		var conn_n: int = conns.size()
		acc["node_n"] = int(acc["node_n"]) + 1
		acc["connection_n"] = int(acc["connection_n"]) + conn_n
		var path := str(node.get_path()).to_lower()
		var sn := sig_name.to_lower()
		if path.contains("mapmanager") or node.name == "MapManager":
			acc["map_manager_signals"] = int(acc["map_manager_signals"]) + conn_n
		if path.contains("ordercommand") or path.contains("order_command"):
			acc["order_panel_signals"] = int(acc["order_panel_signals"]) + conn_n
		if path.contains("overlay") or sn.contains("overlay") or sn.contains("layer"):
			acc["overlay_signals"] = int(acc["overlay_signals"]) + conn_n
		if sn.contains("day") or sn.contains("package") or sn.contains("province_data"):
			acc["day_package_signals"] = int(acc["day_package_signals"]) + conn_n
	for child in node.get_children():
		if child is Node:
			_walk_signals_acc(child as Node, acc)
