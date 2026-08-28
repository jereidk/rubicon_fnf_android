# Renders animania_mod/menus/title/title_screen.tscn at four moments.
#
# The title runs on real time rather than on a clock that can be seeked, so this one plays:
# about twenty-one seconds for the 31-beat intro at 102bpm plus the title itself.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/title_shot.tscn
extends Node2D

const TITLE := "res://animania_mod/menus/title/title_screen.tscn"

## Beat N lands at N * 60/102 seconds: beat 3 is the presents card, beat 18 is mid-sequence,
## beat 31 is the finale, and after it the title itself takes over.
const MOMENTS := [2.0, 10.7, 18.4, 21.0]

var _screen: Node
var _index: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	_screen = load(TITLE).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	_elapsed += delta
	if _index >= MOMENTS.size():
		get_tree().quit()
		return
	if _elapsed < float(MOMENTS[_index]):
		return

	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "user://title_%02d.png" % int(MOMENTS[_index])
	image.save_png(path)

	var text: RichTextLabel = _screen.get_node("IntroLayer/IntroText")
	print("OUT t=%5.1fs beat=%-3d titulo=%-3s texto=%-40s -> %s" % [
		_elapsed, _screen._beat, "si" if _screen.get_node("Title").visible else "no",
		text.text.substr(0, 38).replace("\n", "\\n"),
		ProjectSettings.globalize_path(path)])
	_index += 1
