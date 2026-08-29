# Renders the main menu so the layout can be looked at instead of argued about.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/menu_shot.tscn
extends Node2D

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

## Seconds into startIntroAnimation to shoot at. The last one is after both its tweens have
## landed, which is the menu as it sits.
const AT: PackedFloat32Array = [0.0, 0.35, 0.8, 1.6]

var _shot: int = 0
var _menu: Node


func _ready() -> void:
	_menu = load(MENU).instantiate()
	add_child(_menu)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false


# Off the MENU's own intro clock, not off a second one accumulated here: a render pass in
# xvfb is nowhere near a frame long, so two clocks counting the same frames disagree badly.
func _process(_delta: float) -> void:
	var at: float = _menu._intro if _menu._intro >= 0.0 else 99.0
	while _shot < AT.size() and at >= AT[_shot]:
		var path: String = "user://main_menu_%.2f.png" % AT[_shot]
		get_viewport().get_texture().get_image().save_png(path)
		print("OUT %s (intro %.2fs)" % [ProjectSettings.globalize_path(path), at])
		_shot += 1
	if _shot >= AT.size():
		get_tree().quit()
