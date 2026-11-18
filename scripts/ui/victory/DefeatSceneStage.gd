# scripts/ui/victory/DefeatSceneStage.gd
## Burning or folded (eclipsed) picture. Same button bar as the winner stage.
class_name DefeatSceneStage
extends VictorySceneStage


func configure(built: Dictionary, buttons: Array) -> void:
	super.configure(built, buttons)
	name = "DefeatSceneStage"
