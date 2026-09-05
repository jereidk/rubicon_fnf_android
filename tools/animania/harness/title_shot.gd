# Renders animania_mod/menus/title/title_screen.tscn at six moments.
#
# The title runs on real time rather than on a clock that can be seeked, so this one plays:
# about twenty-one seconds for the 31-beat intro at 102bpm, the title itself, and then the
# confirm - which is not a scene change but a 1.8s outro, so two of the shots are inside it.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/title_shot.tscn
extends Node2D

const TITLE := "res://animania_mod/menus/title/title_screen.tscn"

## Beat N lands at N * 60/102 seconds: beat 3 is the presents card, beat 18 is mid-sequence,
## beat 31 is the finale, and after it the title itself takes over - logo, press-enter, the
## two FallCharacters, the two texts and the props.
const MOMENTS := [2.0, 10.7, 18.4, 21.0, 22.5]
## The confirm fires at this point, and the two shots after it land inside the 1.8s outro:
## the pieces flung on y and the camera swung to outroAngle.
const CONFIRM_AT := 4
const OUTRO_SHOTS := [0.5, 1.4]

var _screen: Node
var _index: int = 0
var _elapsed: float = 0.0
var _outro_at: float = -1.0
var _outro_index: int = 0


func _ready() -> void:
	_screen = load(TITLE).instantiate()
	add_child(_screen)


func _shot(tag: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "user://title_%s.png" % tag
	image.save_png(path)
	var text: RichTextLabel = _screen.get_node("IntroLayer/IntroText")
	var non_intro: Node2D = _screen.get_node_or_null(^"NonIntro")
	print("OUT t=%5.1fs beat=%-3d titulo=%-3s props=%-2d caida=%-3s giro=%5.2f texto=%-30s -> %s" % [
		_elapsed, _screen._beat,
		"si" if _screen.get_node("Title").visible else "no",
		_screen.get_node("Props").get_child_count(),
		"si" if non_intro != null and non_intro.visible else "no",
		rad_to_deg(_screen.camera.rotation) if _screen.camera != null else 0.0,
		text.text.substr(0, 28).replace("\n", "\\n"),
		ProjectSettings.globalize_path(path)])


func _process(delta: float) -> void:
	_elapsed += delta

	if _outro_at >= 0.0:
		if _outro_index >= OUTRO_SHOTS.size():
			get_tree().quit()
			return
		if _elapsed - _outro_at >= float(OUTRO_SHOTS[_outro_index]):
			_shot("outro%d" % _outro_index)
			_outro_index += 1
		return

	if _index >= MOMENTS.size():
		return
	if _elapsed < float(MOMENTS[_index]):
		return

	_shot("%02d" % int(MOMENTS[_index]))
	if _index == CONFIRM_AT:
		# The intro's skip already consumed one press, so this drives confirm() directly.
		_screen._elapsed = _screen._ready_at + 1.0
		_screen.confirm()
		_outro_at = _elapsed
	_index += 1
