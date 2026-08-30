# Renders the story menu and the pause menu so they can be looked at instead of assumed.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/menus_shot.tscn
extends Node2D

const STORY := "res://animania_mod/menus/story/story_menu.tscn"
const PAUSE := "res://animania_mod/menus/pause/pause_menu.tscn"

var _shots: Array[String] = ["story", "pause"]
var _at: int = 0
var _current: Node
var _frames: int = 0
var _pending: String = ""


func _ready() -> void:
	# The pause menu pauses the tree, and this harness has to keep running through it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_open()


func _open() -> void:
	if _current != null:
		_current.queue_free()
	_frames = 0
	if _shots[_at] == "story":
		_current = load(STORY).instantiate()
		add_child(_current)
		return
	_current = load(PAUSE).instantiate()
	add_child(_current)
	_current.open()


func _process(_delta: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		_pending = ""
		_at += 1
		if _at >= _shots.size():
			get_tree().paused = false
			get_tree().quit()
			return
		_open()
		return

	_frames += 1
	if _frames < 8:
		return
	# Queued for the NEXT frame: the viewport's texture is the last frame drawn.
	_pending = "user://%s_menu.png" % _shots[_at]
