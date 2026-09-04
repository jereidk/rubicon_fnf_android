# Renders the loading screen twice: mid-load, with the noodle part-grown, and
# after onLoaded, with "press to start" up.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/loading_shot.tscn
extends Node2D

const LOADING := "res://animania_mod/menus/loading/loading_screen.tscn"
## Something real to point at, so the progress the noodle draws is a real one.
const TARGET := "res://songs/bopeebo/bopeebo.tscn"

var _current: Node
var _frames: int = 0
var _pending: String = ""
var _shots: Array[String] = ["carga", "listo"]
var _at: int = 0


func _ready() -> void:
	_open()


func _open() -> void:
	if _current != null:
		remove_child(_current)
		_current.free()
	# The second shot is the finished state. It points at nothing on purpose:
	# with no target the screen takes its own "nothing to load" path straight to
	# onLoaded, which is the state to look at, and no threaded request is left
	# in flight when the harness quits.
	LoadingScreen.target_scene = TARGET if _shots[_at] == "carga" else ""
	LoadingScreen.target_variant = "week1"
	_current = load(LOADING).instantiate()
	add_child(_current)
	_frames = 0
	if _shots[_at] == "listo":
		_current.set(&"_progress", 1.0)


func _process(_delta: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		_pending = ""
		_at += 1
		if _at >= _shots.size():
			get_tree().quit()
			return
		_open()
		return

	_frames += 1
	if _frames < 8:
		return
	_pending = "user://loading_%s.png" % _shots[_at]
