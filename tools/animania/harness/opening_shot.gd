# Shoots the opening at three moments, which is where onCreatePost's own letterbox lives.
#
# t=0.1 the script's hundred-pixel bars are up and the chart's have not started moving;
# t=12.9 just before beat 33, both sets up; t=14.5 just after, only the chart's.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/opening_shot.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
const MOMENTS := [0.1, 12.0, 14.5]
const WIND_SPEED := 20.0

var _level: Node
var _clock: Node
var _frames: int = 0
var _index: int = 0
var _settle: int = 0


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	if _index >= MOMENTS.size():
		get_tree().quit()
		return
	_clock = _level.get_node("RubiconLevelClock")
	var player: AnimationPlayer = _clock.animation_player
	if player.current_animation_position < MOMENTS[_index]:
		player.speed_scale = WIND_SPEED
		return
	player.speed_scale = 1.0
	_settle += 1
	if _settle < 3:
		return
	_settle = 0
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "user://opening_%03d.png" % int(MOMENTS[_index] * 10)
	image.save_png(path)
	var lanes: Control = _level.get_node("UILayer/UI/Player")
	var opp: Control = _level.get_node("UILayer/UI/Opponent")
	# The REAL position, not the requested one: winding at 20x lands wherever the step
	# falls, which can be past the moment asked for - and beat 33 sits 0.13s after the
	# second sample, close enough to be jumped over.
	print("OUT pedido=%.1f real=%.2f  jugador=%.3f oponente=%.3f  teclas=%s  barras=%s -> %s" % [
		MOMENTS[_index], player.current_animation_position, lanes.scale.x, opp.scale.x,
		"muertas" if lanes.disable_inputs else "vivas",
		"puestas" if _level.get_node("CinematicBars/ScriptBars").visible else "quitadas",
		ProjectSettings.globalize_path(path)])
	_index += 1
