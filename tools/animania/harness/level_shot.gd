# Renders songs/phone-call/phone_call.tscn mid-song: stage, characters, strumlines, notes,
# health bar and judgment, all at once.
#
# The clock reads its time off RubiconLevelClock/AnimationPlayer, so this seeks straight to
# a moment with notes on screen instead of waiting for the song to get there.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/level_shot.tscn
extends Node2D

const LEVEL := "res://songs/phone-call/phone_call.tscn"
# Moments the chart is busy at: after the intro, mid-song, and past the idleSuffix switch
# at 65.5s that puts tadano into his -alt pose for the rest of the song.
const MOMENTS := [20.0, 45.0, 70.0, 100.0]

var _level: Node
var _clock: Node
var _frames: int = 0


func _ready() -> void:
	_level = load(LEVEL).instantiate()
	add_child(_level)
	_clock = _level.get_node("RubiconLevelClock")
	for side: String in ["Opponent", "Player"]:
		_level.get_node("UILayer/UI/%s" % side).autoplay = true


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return

	# Three frames per moment: seek, settle, shoot. The settle frame matters - the notes
	# and the camera both interpolate, and shooting on the seek frame catches neither.
	var index: int = (_frames - 4) / 3
	if index >= MOMENTS.size():
		get_tree().quit()
		return

	var step: int = (_frames - 4) % 3
	if step == 0:
		_clock.animation_player.seek(MOMENTS[index], true)
	elif step == 2:
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "user://level_%03d.png" % int(MOMENTS[index])
		image.save_png(path)
		print("OUT t=%.0fs -> %s" % [
			MOMENTS[index], ProjectSettings.globalize_path(path)])
