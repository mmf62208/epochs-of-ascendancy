# scripts/core/Country.gd
class_name Country
extends Resource

@export var tag: String = "XXX"           # Three-letter country tag (e.g. "GER", "USA")
@export var name: String = "Unnamed Nation"
@export var color: Color = Color(0.5, 0.5, 0.5)  # Default gray — we'll set real colors later
@export var capital_province_id: int = 0
@export var ideology: String = "neutral"
@export var current_tech_level: int = 1
@export var focus_tree_path: String = ""   # Path to the JSON file for this nation's focus tree
@export var starting_focuses_completed: Array = []
@export var stability: float = 80.0        # 0–100
@export var war_support: float = 30.0      # 0–100

# We'll add more properties as we build (research points, manpower, etc.)extends Node
