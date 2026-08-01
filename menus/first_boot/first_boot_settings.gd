extends Control

const INTRO_SCENE := "res://menus/intro/intro.tscn"

## Uses the same LullabyQualityPreset resources (render_scale, shadows,
## ssao/ssil, post-processing, shader effects) the console's Settings
## screen applies - this used to only flip 2D MSAA/screen-space AA via the
## long-dead apply_quality_preset()/QualityPreset enum (removed from
## settings.gd, this was its only caller), which barely changed anything
## and was never saved, so picking a preset here didn't survive past this
## screen.
func _on_preset_changed(index: int) -> void:
	var preset: LullabyQualityPreset
	match index:
		1: preset = Settings.PRESET_VERY_LOW
		2: preset = Settings.PRESET_LOW
		3: preset = Settings.PRESET_MEDIUM
		4: preset = Settings.PRESET_HIGH
		_: return

	preset.apply(Settings)
	Settings.apply_settings()
	Settings.save()

func apply_and_continue() -> void:
	SceneChanger.change_to(INTRO_SCENE, &"hypno")
