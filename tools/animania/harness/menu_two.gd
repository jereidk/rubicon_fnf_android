# Menu settled, then again after the particles have had time to spread.
extends Node2D
const MENU := "res://animania_mod/menus/main/main_menu.tscn"
var _menu: Node
var _t: float = 0.0
var _stage: int = 0
var _pending: String = ""

func _ready() -> void:
	_menu = load(MENU).instantiate()
	add_child(_menu)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false

func _process(delta: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		_pending = ""
		_stage += 1
		if _stage > 1:
			get_tree().quit()
		return
	_menu.set("_intro", 2.0)
	_menu.call("_advance_intro", 0.0)
	_t += delta
	if _stage == 0 and _t < 1.5:
		return
	if _stage == 1 and _t < 6.0:
		return
	_pending = "user://particles%d.png" % _stage
