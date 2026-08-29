# Renders tadano's four sing symbols frame by frame so the face layer can be read off the
# image instead of reasoned about. `facessing` is ONE symbol holding four directions x two
# poses, and each direction picks its pose with a firstFrame plus a play-once loop mode -
# which advances. Whether that advance walks into the NEXT direction's face is a thing a
# contact sheet answers and a JSON dump does not.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/sing_sheet.tscn
extends Node2D

const CHARACTER := "res://animania_mod/characters/chr_tadano.tscn"
const OUT_DIR := "user://sing_sheet"
const SYMBOLS: Array[String] = [
	"chars render/tadano 1/tadano left",
	"chars render/tadano 1/tadano down",
	"chars render/tadano 1/tadano up",
	"chars render/tadano 1/tadano right",
]
const FRAMES := 15

var _symbol: AnimateSymbol
var _jobs: Array[Array] = []
var _at: int = -1
var _settle: int = 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# The debug overlay is an autoload CanvasLayer at layer 128; it would print itself over
	# every capture and poison any bounding box measured off one.
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
	var character: Node2D = load(CHARACTER).instantiate()
	add_child(character)
	character.get_node("RootAnimationPlayer").active = false
	_symbol = character.get_node("AnimateSymbol")
	_symbol.get_node("AnimationPlayer").active = false
	_symbol.playing = false
	# The character sits around (543, 876) in his own space; pull him into view and shrink
	# him so a whole 15-frame row fits one capture each.
	character.position = Vector2(700.0, 1000.0)
	for name: String in SYMBOLS:
		for f: int in FRAMES:
			_jobs.append([name, f])


func _process(_delta: float) -> void:
	if _at >= 0:
		_settle += 1
		if _settle < 2:
			return
		var image: Image = get_viewport().get_texture().get_image()
		var job: Array = _jobs[_at]
		var short: String = String(job[0]).get_file().replace(" ", "_")
		image.save_png("%s/%s_%02d.png" % [OUT_DIR, short, int(job[1])])
	_at += 1
	_settle = 0
	if _at >= _jobs.size():
		print("OUT wrote %d frames to %s" % [_jobs.size(), ProjectSettings.globalize_path(OUT_DIR)])
		get_tree().quit()
		return
	_symbol.symbol = _jobs[_at][0]
	_symbol.frame = _jobs[_at][1]
