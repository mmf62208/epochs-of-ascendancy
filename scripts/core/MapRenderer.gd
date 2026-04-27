class_name MapRenderer
extends Node2D

@export var container: Node2D
@export var info_panel: Panel
@export var info_name: Label
@export var info_owner: Label
@export var info_population: Label
@export var info_terrain: Label
@export var info_factories: Label
@export var info_dev: Label
@export var info_resources: Label
@export var info_core: Label
@export var info_special: Label
@export var btn_close: Button

var province_nodes: Dictionary = {}
var current_hover: Node2D = null

func _ready():
	if btn_close:
		btn_close.pressed.connect(hide_info_panel)

func render_provinces(loader: ScenarioLoader):
	for child in container.get_children():
		child.queue_free()
	province_nodes.clear()

	var provinces = loader.provinces.values()
	print("Rendering polished map with ", provinces.size(), " provinces")

	for province in provinces:
		var prov_node = Node2D.new()
		prov_node.name = "Prov_" + str(province.id)
		
		var column = (province.id - 1) % 13
		var row = (province.id - 1) / 13
		prov_node.position = Vector2(column * 118, row * 82)

		# Background colored tile
		var bg = ColorRect.new()
		bg.size = Vector2(112, 72)
		bg.color = Color(0.18, 0.18, 0.22, 0.85)
		if province.owner_tag != "":
			var country = loader.get_country(province.owner_tag)
			if country:
				bg.color = country.color
				bg.color.a = 0.92
		
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		bg.gui_input.connect(_on_province_clicked.bind(province))
		bg.mouse_entered.connect(_on_mouse_entered.bind(prov_node))
		bg.mouse_exited.connect(_on_mouse_exited.bind(prov_node))
		
		prov_node.add_child(bg)

		# Capital star (smaller)
		if "capital" in province.special_features:
			var star = Label.new()
			star.text = "⭐"
			star.add_theme_font_size_override("font_size", 28)   # ← smaller
			star.position = Vector2(6, 2)
			prov_node.add_child(star)

		# Other icons (moved up 2 pixels)
		var icon_x = 8
		var count = 0
		for feature in province.special_features:
			if feature == "capital": continue
			if count >= 5: break
			var icon = Label.new()
			icon.text = get_feature_icon(feature)
			icon.add_theme_font_size_override("font_size", 24)
			icon.position = Vector2(icon_x, 40)   # ← moved up 2px
			prov_node.add_child(icon)
			icon_x += 26
			count += 1

		container.add_child(prov_node)
		province_nodes[province.id] = prov_node

	print("✅ Polished map rendered with hover support")

func _on_mouse_entered(prov_node: Node2D):
	current_hover = prov_node
	prov_node.scale = Vector2(1.08, 1.08)

func _on_mouse_exited(prov_node: Node2D):
	if current_hover == prov_node:
		prov_node.scale = Vector2(1.0, 1.0)
		current_hover = null

func _on_province_clicked(event: InputEvent, province):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		show_info_panel(province)

# ==================== INFO PANEL FUNCTIONS ====================
func show_info_panel(province):
	if not info_panel: return
	info_name.text = province.name
	info_owner.text = "Owner: " + province.owner_tag if province.owner_tag != "" else "Owner: None"
	info_population.text = "Population: " + str(province.population)
	info_terrain.text = "Terrain: " + province.terrain.capitalize()
	info_factories.text = "Factories: " + str(province.factories)
	info_dev.text = "Development: " + str(province.development_level)
	
	var res_text = "Resources: "
	if province.resources.size() > 0:
		for key in province.resources:
			res_text += key.capitalize() + ": " + str(province.resources[key]) + " "
	else:
		res_text += "None"
	info_resources.text = res_text.strip_edges()
	
	var core_text = "Core For: "
	if province.core_for_tags.size() > 0:
		core_text += ", ".join(province.core_for_tags)
	else:
		core_text += "None"
	info_core.text = core_text
	
	var special_list = []
	for feature in province.special_features:
		var icon = get_feature_icon(feature)
		var nice_name = feature.capitalize().replace("_", " ")
		var level = province.special_levels.get(feature, 1)
		if level > 1:
			special_list.append(icon + " " + nice_name + " (Lv." + str(level) + ")")
		else:
			special_list.append(icon + " " + nice_name)
	
	var special_text = "Special: "
	if special_list.size() > 0:
		special_text += ", ".join(special_list)
	else:
		special_text += "None"
	info_special.text = special_text
	
	info_panel.visible = true

func get_feature_icon(feature: String) -> String:
	match feature.to_lower():
		"capital": return "⭐"
		"port": return "⚓"
		"naval_shipyard": return "⚙️"
		"airfield": return "✈️"
		"fort": return "🛡️"
		"research_center": return "🔬"
		"coal_plant": return "🏭"
		"gas_plant": return "🔥"
		"oil_rig": return "⛽"
		"major_factory": return "🏗️"
		"nuclear_plant": return "☢️"
		"fusion_plant": return "⚡"
		"mission_control": return "📡"
		"spaceport": return "🚀"
		"dam": return "🌊"
		_: return "📍"

func hide_info_panel():
	if info_panel:
		info_panel.visible = false
