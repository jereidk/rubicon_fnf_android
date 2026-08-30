# Measures a character scene's drawn bounding box, in its own local space.
#
# This exists because Funkin does not place a character by its top-left: Stage.addCharacter
# anchors it by `characterOrigin`, which is (width / 2, height) - horizontal centre,
# vertical BOTTOM - so a stage position is where the character's feet go, not its corner.
# Reproducing that needs the drawn size, and for an Adobe Animate atlas there is no
# authored size to read: gdanimate draws it out of a symbol tree. So it gets rendered and
# the opaque pixels get counted, which is the same technique the console-icon work used.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/measure_character.tscn
extends Node2D

const SCENES := {
	"komi": "res://animania_mod/characters/chr_komi.tscn",
	"tadano": "res://animania_mod/characters/chr_tadano.tscn",
	"bf": "res://animania_mod/characters/chr_bf.tscn",
	"gf": "res://animania_mod/characters/chr_gf.tscn",
	"dad": "res://animania_mod/characters/chr_dad.tscn",
	"dad_beast": "res://animania_mod/characters/chr_dad_beast.tscn",
}
const PAD := Vector2(1400, 1400)

var _pending: Array = []
var _frames: int = 0
var _current: SubViewport = null
var _name: String = ""


func _ready() -> void:
	for character_name: String in SCENES:
		_pending.append(character_name)


func _process(_delta: float) -> void:
	if _current != null:
		_frames += 1
		if _frames < 3:
			return
		_measure()
		_current.queue_free()
		_current = null

	if _pending.is_empty():
		get_tree().quit()
		return

	_name = _pending.pop_front()
	_current = SubViewport.new()
	_current.size = Vector2i(3000, 3000)
	_current.transparent_bg = true
	_current.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_current)

	var character: Node2D = load(SCENES[_name]).instantiate()
	character.position = PAD
	_current.add_child(character)
	_frames = 0


func _measure() -> void:
	var image: Image = _current.get_texture().get_image()
	var min_point := Vector2i(image.get_width(), image.get_height())
	var max_point := Vector2i(-1, -1)

	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a <= 0.004:
				continue
			min_point.x = mini(min_point.x, x)
			min_point.y = mini(min_point.y, y)
			max_point.x = maxi(max_point.x, x)
			max_point.y = maxi(max_point.y, y)

	if max_point.x < 0:
		print("OUT %s drew nothing" % _name)
		return

	var size := Vector2(max_point - min_point) + Vector2.ONE
	var origin := Vector2(min_point) - PAD
	print("OUT %-8s drawn=%.0fx%.0f  local_topleft=%s  origin=(%.1f, %.1f)" % [
		_name, size.x, size.y, origin, origin.x + size.x * 0.5, origin.y + size.y])
