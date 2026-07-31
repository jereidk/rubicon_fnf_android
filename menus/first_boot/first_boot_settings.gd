extends Control

const INTRO_SCENE := "res://menus/intro/intro.tscn"

func _on_preset_changed(index: int) -> void:
	match index:
		1:
			Settings.apply_quality_preset(Settings.QualityPreset.LOW)
		2:
			Settings.apply_quality_preset(Settings.QualityPreset.MEDIUM)
		3:
			Settings.apply_quality_preset(Settings.QualityPreset.HIGH)

func apply_and_continue() -> void:
	SceneChanger.change_to(INTRO_SCENE, &"hypno")
