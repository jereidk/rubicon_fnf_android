# Runs a song scene for a moment and shoots it, to see that a newly built level actually
# plays rather than merely packing.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
#       --path . res://tools/animania/harness/song_shot.tscn
extends Node2D

const SONG := "res://songs/dadbattle/dadbattle.tscn"

var _level: Node
var _pending: bool = false
var _elapsed: float = 0.0
## Where the camera was aimed the last time it was looked at, so a target that never moves
## is visible as a number rather than as a feeling about the screenshot.
var _seen: Array[Vector2] = []
var _next_sample: float = 1.0


func _ready() -> void:
	_level = load(SONG).instantiate()
	add_child(_level)


func _process(delta: float) -> void:
	if _pending:
		get_viewport().get_texture().get_image().save_png("user://song.png")
		var clock: Node = _level.get_node_or_null("RubiconLevelClock")
		var at: float = clock.animation_player.current_animation_position \
			if clock != null and clock.animation_player != null else -1.0
		print("OUT reloj=%.2fs sonando=%s -> %s" % [at,
			clock != null and clock.animation_player != null
				and clock.animation_player.is_playing(),
			ProjectSettings.globalize_path("user://song.png")])
		get_tree().quit()
		return
	_elapsed += delta
	if _elapsed >= _next_sample:
		_next_sample += 1.0
		for who: String in ["Bf", "DadBeast"]:
			var c: Node2D = _level.get_node_or_null("Stage/%s" % who)
			if c != null:
				print("OUT %.0fs %-3s %s" % [_elapsed, who,
					c.animation_player.current_animation])
		var camera: Camera2D = _level.get_node_or_null("RubiconInterpolatedCamera2D")
		if camera != null:
			var aim: Vector2 = camera.get(&"position_interpolate_target")
			if _seen.is_empty() or not _seen[-1].is_equal_approx(aim):
				_seen.append(aim)
	if _elapsed > 22.0:
		print("OUT la camara apunto a %d sitios: %s" % [_seen.size(), _seen])
		_pending = true
