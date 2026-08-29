# Renders the main menu so the layout can be looked at instead of argued about.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/menu_shot.tscn
extends Node2D

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

## Seconds into startIntroAnimation to shoot at. The last one is after both its tweens have
## landed, which is the menu as it sits.
const AT: PackedFloat32Array = [0.0, 0.35, 0.8, 1.6]

## And the same for startTransitionToMenu, driven off a button that leads nowhere so the
## scene stays put and the exit can be looked at.
const LEAVING: PackedFloat32Array = [0.2, 0.5, 0.74]

var _shot: int = 0
var _leaving: int = 0
var _menu: Node
## A capture queued for the next frame, so the picture is of the moment it names.
var _pending: String = ""


func _ready() -> void:
	_menu = load(MENU).instantiate()
	add_child(_menu)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false


# Off the MENU's own intro clock, not off a second one accumulated here: a render pass in
# xvfb is nowhere near a frame long, so two clocks counting the same frames disagree badly.
#
# The capture waits a frame after the threshold is crossed, because the viewport's texture
# is the LAST frame drawn - and in xvfb a frame can be half a second, which is enough to
# save a picture of a completely different moment.
func _process(_delta: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		_pending = ""
		if _shot >= AT.size() and _leaving >= LEAVING.size():
			get_tree().quit()
		return

	var at: float = _menu._intro if _menu._intro >= 0.0 else 99.0
	if _shot < AT.size():
		if at < AT[_shot]:
			return
		print("OUT intro %.2fs" % at)
		_pending = "user://main_menu_%.2f.png" % AT[_shot]
		_shot += 1
		return

	# `options` is in BUTTONS but not in DESTINATIONS, so doSelect plays the whole exit and
	# then comes back instead of changing scene.
	if _menu._exit < 0.0 and _leaving == 0:
		_menu._selected = 4
		_menu._refresh()
		_menu.do_select()
		return
	while _leaving < LEAVING.size() and _menu._exit >= LEAVING[_leaving]:
		var out: String = "user://main_menu_out_%.2f.png" % LEAVING[_leaving]
		get_viewport().get_texture().get_image().save_png(out)
		print("OUT %s (salida %.2fs)" % [ProjectSettings.globalize_path(out), _menu._exit])
		_leaving += 1
	if _leaving >= LEAVING.size():
		get_tree().quit()
