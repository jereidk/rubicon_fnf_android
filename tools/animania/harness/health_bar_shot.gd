# Shoots the health bar at several health values, because which way it grows is the one
# thing about it a still cannot show.
#
# It is also how the bar's own wiring gets checked: the first version of this port's bar
# came out with no `value_changed` connection at all - PackedScene.pack() drops a connect()
# that is not CONNECT_PERSIST - and sat frozen at 50% for the whole song. Frozen looks
# exactly like working in any single frame.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/health_bar_shot.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
const VALUES := [15.0, 50.0, 85.0]

var _level: Node
var _frames: int = 0
var _index: int = 0


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)


func _process(_delta: float) -> void:
	_frames += 1
	# Every frame, not once in _ready: the HUD starts invisible - camHUD's alpha is 0 until
	# beat 31 - and `opening` sets it to 0 again on the clock's first frame, after _ready.
	_level.get_node("UILayer/UI").modulate.a = 1.0
	_level.get_node("Stage/ScreenSpace/IntroCover").color.a = 0.0
	if _frames < 6:
		return
	if _index >= VALUES.size():
		get_tree().quit()
		return

	var health: Node = _level.get_node("RubiconHealthModule")
	var bar: Control = _level.get_node("UILayer/UI/HealthBar")
	if _frames % 2 == 0:
		health.health = VALUES[_index]
		return

	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "user://health_%03d.png" % int(VALUES[_index])
	image.save_png(path)
	print("OUT vida=%3.0f  ratio=%.2f  ancho del lado del jugador=%.0f -> %s" % [
		VALUES[_index], bar.get_as_ratio(),
		(bar.get_node("Art/PlayerFill") as Sprite2D).region_rect.size.x,
		ProjectSettings.globalize_path(path)])
	_index += 1
