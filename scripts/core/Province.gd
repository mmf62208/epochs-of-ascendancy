class_name Province
extends Resource

@export var id: int = 0
@export var name: String = "Unnamed Province"
@export var owner_tag: String = ""
@export var controller_tag: String = ""
@export var resources: Dictionary = {}           # e.g. {"coal": 950, "oil": 680}
@export var population: int = 1000000
@export var factories: int = 5
@export var development_level: float = 5.0
@export var infrastructure: int = 5
@export var terrain: String = "plains"
@export var victory_points: int = 0
@export var core_for_tags: Array = []
@export var special_features: Array = []
@export var special_levels: Dictionary = {}
