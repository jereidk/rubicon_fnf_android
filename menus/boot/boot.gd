extends Node2D
class_name RubiconBoot

## Port of Lullaby's scn_boot.tscn: a brief black screen before handing off
## to the GPU-compatibility check (desktop-relevant, still ported for
## fidelity) and then the content warning screen.

const WARNING_SCENE := "res://menus/warning/warning.tscn"
const SHITTY_GPU_SCENE := "res://menus/shitty_gpu/shitty_gpu.tscn"

func _on_timer_end() -> void:
	if _has_bad_gpu():
		SceneChanger.change_to(SHITTY_GPU_SCENE, &"hypno")
	else:
		SceneChanger.change_to(WARNING_SCENE, &"hypno")

func _has_bad_gpu() -> bool:
	var adapter_name: String = RenderingServer.get_video_adapter_name()
	return adapter_name.findn("ANGLE") != -1
