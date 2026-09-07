# Comprueba que el mando del menu de pausa NO se ve mientras se juega.
#
# El de pausa cuelga de un CanvasLayer que nace con `visible = false`, y la visibilidad de
# un CanvasLayer NO baja a otro CanvasLayer hijo: son capas hermanas para el servidor de
# render. O sea que un mando metido ahi dentro puede quedarse pintado encima de la partida
# con el menu cerrado. Esto lo mira en una cancion de verdad.
extends Node2D

const SONG := "res://songs/tutorial/tutorial.tscn"
var _done := false
var _t := 0.0

func _ready() -> void:
	Engine.set_meta(&"force_menu_pad", true)
	add_child((load(SONG) as PackedScene).instantiate())

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < 2.0:
		return
	_done = true
	_run()

func _run() -> void:
	var pause: Node = get_child(0).find_child("PauseMenu", true, false)
	var pad: Node = pause.find_child("MenuVirtualPad", true, false) if pause != null else null
	print("OUT pausa visible=%s   mando=%s" % [str(pause.visible) if pause else "?",
		"no esta" if pad == null else "visible=%s" % str((pad as CanvasLayer).visible)])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pad_leak.png")
	print("OUT /root/.local/share/godot/app_userdata/Animania/pad_leak.png")
	get_tree().quit()
