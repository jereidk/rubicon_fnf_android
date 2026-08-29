# Renders the main menu so the layout can be looked at instead of argued about.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/menu_shot.tscn
extends Node2D

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

var _frames: int = 0


func _ready() -> void:
	add_child(load(MENU).instantiate())
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 8:
		return
	var path: String = "user://main_menu.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("OUT %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
