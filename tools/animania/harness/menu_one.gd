# One settled shot of the main menu plus one with the OST widget open.
extends Node2D

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

var _menu: Node
var _frames: int = 0
var _stage: int = 0
var _pending: String = ""


func _ready() -> void:
	_menu = load(MENU).instantiate()
	add_child(_menu)
	for node: Node in get_tree().root.get_children():
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false


func _process(_delta: float) -> void:
	if _pending != "":
		get_viewport().get_texture().get_image().save_png(_pending)
		print("OUT %s" % ProjectSettings.globalize_path(_pending))
		_pending = ""
		_stage += 1
		if _stage > 1:
			get_tree().quit()
			return
		_menu.set("_intro", -1.0)
		_menu.call("_toggle_social")
		_frames = 0
		return
	_frames += 1
	if _stage == 0:
		_menu.set("_intro", 2.0)
		_menu.call("_advance_intro", 0.0)
	if _frames < 6:
		return
	_pending = "user://menu_stage%d.png" % _stage
