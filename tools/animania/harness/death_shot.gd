# Renders tadano's death sequence, in both forms.
#
# It cannot be reached by seeking - it is driven by health_depleted, not by the chart - so
# this drops the health to zero and lets the tweens run in real time, which is the only way
# the dark wash, the sliding panels and the retry text are anywhere but their start values.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/death_shot.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
## Long enough for the dark wash (1.25s after half a second) and the retry text's loop.
const SETTLE := 3.0

var _level: Node
var _standing: bool = false
var _elapsed: float = 0.0
var _shot: bool = false


func _ready() -> void:
	_start(false)


func _start(standing: bool) -> void:
	if _level != null:
		remove_child(_level)
		_level.queue_free()

	_standing = standing
	_elapsed = 0.0
	_shot = false
	_level = load(LEVEL).instantiate()
	add_child(_level)

	# Wound to a point the song actually reaches first, so the camera is where a real death
	# would find it. Dropped on frame zero the camera is still at its opening target and the
	# shot is of the characters' shoes.
	var clock: AnimationPlayer = _level.get_node("RubiconLevelClock/AnimationPlayer")
	var target: float = 95.0 if standing else 45.0
	while clock.current_animation_position < target:
		clock.seek(minf(clock.current_animation_position + 0.5, target), true)
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		camera.position = camera.position_interpolate_target
		camera.zoom = camera.zoom_interpolate_target

	if standing:
		_level.get_node("PhoneCallEvents").stand_up()
	_level.get_node("RubiconHealthModule").health = 0.0


func _process(delta: float) -> void:
	if _shot:
		return

	_elapsed += delta
	if _elapsed < SETTLE:
		return

	_shot = true
	var name: String = "standing" if _standing else "phone"
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("user://death_%s.png" % name)

	var retry: AnimationPlayer = _level.find_child(
		"RetryText", true, false).get_node("AnimationPlayer")
	print("OUT %-9s oscuro=%.2f  retry=%-6s  panel=%s -> %s" % [
		name, _level.get_node("Death/Dark").color.a, retry.current_animation,
		_level.get_node("Death/LeftPanel").visible,
		ProjectSettings.globalize_path("user://death_%s.png" % name)])

	if not _standing:
		_start(true)
		return
	get_tree().quit()
