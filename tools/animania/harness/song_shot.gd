# Runs a song scene for a moment and shoots it, to see that a newly built level actually
# plays rather than merely packing.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
#       --path . res://tools/animania/harness/song_shot.tscn
extends Node2D

## Por defecto bopeebo; se le pasa otra por `-- <id>`, que es como se mira una recien
## construida sin tocar el arnes.
const SONG := "res://songs/bopeebo/bopeebo.tscn"

var _song: String = SONG
## Cuando disparar, en segundos de escena. `-- at=1.5` para ver el arranque.
var _shoot_at: float = 31.0
var _level: Node
var _pending: bool = false
var _elapsed: float = 0.0
## Where the camera was aimed the last time it was looked at, so a target that never moves
## is visible as a number rather than as a feeling about the screenshot.
var _seen: Array[Vector2] = []
var _next_sample: float = 1.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.ends_with(".tscn"):
			_song = arg
		elif arg.begins_with("at="):
			_shoot_at = arg.substr(3).to_float()
		elif arg.contains("="):
			# Cualquier otra bandera con `=` no es un nombre de cancion. Sin esto, `hide=...`
			# se tomaba por el id y el arnes cargaba una escena que no existe.
			continue
		elif not arg.is_empty():
			_song = "res://songs/%s/%s.tscn" % [arg, arg.replace("-", "_")]
	print("OUT %s" % _song)
	_level = load(_song).instantiate()
	add_child(_level)
	# `-- hide=A,B` para apagar nodos y ver que queda. Es lo unico que aisla de donde sale
	# algo que se dibuja encima.
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("hide="):
			continue
		for path: String in arg.substr(5).split(","):
			# Node y no CanvasItem: un CanvasLayer NO es un CanvasItem, y castearlo daba
			# null, asi que apagar `UILayer` no apagaba nada y el arnes decia que no existia.
			var node: Node = _level.get_node_or_null(NodePath(path))
			if node == null or not (node is CanvasItem or node is CanvasLayer):
				print("OUT hide: no existe o no se puede apagar %s" % path)
				continue
			node.set(&"visible", false)
			print("OUT apagado %s" % path)


func _process(delta: float) -> void:
	if _pending:
		var shot: String = "user://song_%s.png" % _song.get_file().get_basename()
		get_viewport().get_texture().get_image().save_png(shot)
		var clock: Node = _level.get_node_or_null("RubiconLevelClock")
		var at: float = clock.animation_player.current_animation_position \
			if clock != null and clock.animation_player != null else -1.0
		print("OUT reloj=%.2fs sonando=%s -> %s" % [at,
			clock != null and clock.animation_player != null
				and clock.animation_player.is_playing(),
			ProjectSettings.globalize_path(shot)])
		get_tree().quit()
		return
	_elapsed += delta
	if _elapsed >= _next_sample:
		_next_sample += 1.0
		for who: String in ["Bf", "Dad", "DadBeast", "Gf"]:
			var c: Node2D = _level.get_node_or_null("Stage/%s" % who)
			if c != null:
				print("OUT %.0fs %-3s %s" % [_elapsed, who,
					c.animation_player.current_animation])
		var camera: Camera2D = _level.get_node_or_null("RubiconInterpolatedCamera2D")
		if camera != null:
			var aim: Vector2 = camera.get(&"position_interpolate_target")
			if _seen.is_empty() or not _seen[-1].is_equal_approx(aim):
				_seen.append(aim)
	if _elapsed > _shoot_at:
		print("OUT la camara apunto a %d sitios: %s" % [_seen.size(), _seen])
		_pending = true
