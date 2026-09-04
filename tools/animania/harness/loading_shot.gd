# Renders the loading screen once per background: the suffix comes off the SONG,
# so shooting one song per branch of the mod's own switch covers all five.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/loading_shot.tscn
extends Node2D

const LOADING := "res://animania_mod/menus/loading/loading_screen.tscn"
## Something real to point at, so the progress the noodle draws is a real one.
const TARGET := "res://songs/bopeebo/bopeebo.tscn"

## name -> song id. "carga" is the only one that actually loads; the rest are
## posed at the finished state, which is where the per-song art is worth seeing.
const SHOTS: Array = [
	["carga", "bopeebo"],
	["week1", "bopeebo"],
	["dadbattle", "dadbattle"],
	["komi", "phone-call"],
	["wh", "winter-horrorland"],
	["default", "nada-de-nada"],
]

var _current: Node
var _frames: int = 0
var _pending: String = ""
var _at: int = 0


func _ready() -> void:
	_open()


func _open() -> void:
	if _current != null:
		remove_child(_current)
		_current.free()
	# Only the first shot loads anything: with no target the screen takes its own
	# "nothing to load" path straight to onLoaded, which is the state to look at,
	# and nothing is left in flight when the harness quits.
	LoadingScreen.target_scene = TARGET if _at == 0 else ""
	LoadingScreen.target_song = String(SHOTS[_at][1])
	_current = load(LOADING).instantiate()
	add_child(_current)
	_frames = 0
	if _at > 0:
		_current.set(&"_progress", 1.0)


func _process(_delta: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		_pending = ""
		_at += 1
		if _at >= SHOTS.size():
			get_tree().quit()
			return
		_open()
		return

	_frames += 1
	# Long enough for the two-second black sheet to be out of the way.
	if _frames < 150:
		return
	_pending = "user://loading_%s.png" % String(SHOTS[_at][0])
