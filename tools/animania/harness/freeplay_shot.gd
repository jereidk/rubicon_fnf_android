# Renders freeplay so the diorama can be looked at instead of argued about.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/freeplay_shot.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"

# doIntroAnim reproduce la animacion del televisor, asi que una toma a los seis frames
# pilla el tele a medio encender y en el fotograma equivocado. Se espera a que termine.
const SETTLE := 2.5
var _frames: int = 0
var _t: float = 0.0


func _ready() -> void:
	add_child(load(SCREEN).instantiate())


func _process(_delta: float) -> void:
	_frames += 1
	_t += _delta
	if _frames < 6 or _t < SETTLE:
		return
	get_viewport().get_texture().get_image().save_png("user://freeplay.png")
	print("OUT %s" % ProjectSettings.globalize_path("user://freeplay.png"))
	get_tree().quit()
