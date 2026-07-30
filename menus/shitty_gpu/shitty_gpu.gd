extends Control

const WARNING_SCENE := "res://menus/warning/warning.tscn"

@onready var poop_sound: AudioStreamPlayer = $PoopSound

func request_continue() -> void:
	poop_sound.play()
	SceneChanger.change_scene(WARNING_SCENE)

func request_back() -> void:
	get_tree().quit()
