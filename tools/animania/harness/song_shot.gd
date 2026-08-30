# Runs a song scene for a moment and shoots it, to see that a newly built level actually
# plays rather than merely packing.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
#       --path . res://tools/animania/harness/song_shot.tscn
extends Node2D

const SONG := "res://songs/tutorial/tutorial.tscn"

var _level: Node
var _pending: bool = false
var _elapsed: float = 0.0


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
	if _elapsed > 6.0:
		_pending = true
