# Renders the main menu at the moments this session's audit changed.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/menu_states.tscn
extends Node2D

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

var _menu: Node
var _step: int = 0
var _t: float = 0.0
var _pending: String = ""
var _wait: float = 0.0


func _ready() -> void:
	_menu = load(MENU).instantiate()
	add_child(_menu)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false


func _shoot(tag: String) -> void:
	_pending = tag


func _flush() -> void:
	if _pending.is_empty():
		return
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("user://menu_%s.png" % _pending)
	var order: Array = []
	for name: String in _menu.BUTTONS:
		var n: Node = _menu._button_node(name)
		if n != null:
			order.append("%s:%s" % [name.substr(0, 4), n.get_index()])
	print("OUT %-10s sel=%-10s intro=%5.2f salida=%5.2f zoom=%.3f disco=%-3s orden=%s" % [
		_pending,
		_menu.BUTTONS[_menu._selected] if _menu._selected >= 0 else "-nada-",
		_menu._intro, _menu._exit, _menu.camera.zoom.x,
		"si" if _menu._social_open else "no", " ".join(order)])
	_pending = ""


func _process(delta: float) -> void:
	_flush()
	_t += delta
	if _wait > 0.0:
		_wait -= delta
		return

	match _step:
		0:
			if _menu._intro < 0.35:
				return
			_shoot("01intro")
		1:
			if _menu._intro >= 0.0:
				return
			_shoot("02settled")
		2:
			# Two steps down the list: storymode -> (shop blocked) -> freeplay.
			_menu.change_item(1, true)
			_menu.change_item(1, true)
			_shoot("03walked")
		3:
			# The desktop hover path, which had no port at all before this session.
			var seat: Rect2 = _menu._button_node("credits").get_meta(&"touch_rect")
			_menu._hover(seat.get_center())
			_shoot("04hover")
		4:
			# changeItem(-444): the pointer leaves the selected plaque and nothing is lit.
			_menu._hover(Vector2(-500.0, -500.0))
			_shoot("05deselected")
		5:
			_menu.change_item(2, true)
			_menu._toggle_social()
			_wait = 0.45
			_shoot("06ost_opening")
		6:
			_wait = 1.2
			_shoot("07ost_open")
		7:
			_menu._toggle_social()
			_menu.do_select()
			_wait = 0.6
			_shoot("08confirm")
		8:
			_wait = 1.0
			_shoot("09exit")
		_:
			get_tree().quit()
			return
	_step += 1
