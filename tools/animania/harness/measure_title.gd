# Measures the title screen's two Adobe compositions, the same way measure_character.gd
# measures a character: render it into a padded SubViewport at scale 1 and count the opaque
# pixels.
#
# It exists because placing them by hand went wrong twice - once too small and off in a
# corner, once filling the screen - and an Animate composition has no authored size to read.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/measure_title.tscn
extends Node2D

const PIECES := {
	"logo": ["res://animania_mod/menus/title/logo_atlas.tres", "Logolol"],
	"press_enter": ["res://animania_mod/menus/title/press_enter_atlas.tres", "main"],
}
const PAD := Vector2(2000, 2000)
const VIEW := 4200

var _pending: Array = []
var _frames: int = 0
var _current: SubViewport = null
var _name: String = ""


func _ready() -> void:
	for piece: String in PIECES:
		_pending.append(piece)


func _process(_delta: float) -> void:
	if _current != null:
		_frames += 1
		if _frames < 4:
			return
		_measure()
		_current.queue_free()
		_current = null

	if _pending.is_empty():
		get_tree().quit()
		return

	_name = _pending.pop_front()
	_current = SubViewport.new()
	_current.size = Vector2i(VIEW, VIEW)
	_current.transparent_bg = true
	_current.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_current)

	var entry: Array = PIECES[_name]
	var symbol := Node2D.new()
	symbol.set_script(load("res://addons/gdanimate/animate_symbol.gd"))
	symbol.set(&"centered", false)
	symbol.set(&"symbol", String(entry[1]))
	var atlases: Array = symbol.get(&"atlases")
	atlases.append(load(String(entry[0])))
	symbol.set(&"atlases", atlases)
	symbol.position = PAD
	_current.add_child(symbol)
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
		print("OUT %s no dibujo nada" % _name)
		return
	var size := Vector2(max_point - min_point) + Vector2.ONE
	var origin := Vector2(min_point) - PAD
	print("OUT %-12s dibuja=%.0fx%.0f  esquina_local=(%.0f, %.0f)" % [
		_name, size.x, size.y, origin.x, origin.y])
