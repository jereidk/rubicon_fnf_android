# Recorre el carrusel hueco a hueco y saca una toma de cada uno.
#
# Existe por el disco ALEATORIO. Con el hueco 0 elegido -que es el suyo- updateDataStuff
# se va a su rama sin cancion y la cabecera entera queda a alfa 0.0001, asi que una unica
# toma del arranque no dice nada de si el resto funciona: hay que mover la seleccion y
# mirar que la cabecera vuelve, que el disco elegido cambia y que el tema suena.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/carousel_shot.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5
const HOLD := 0.6

var _t: float = 0.0
var _screen: Node = null
var _done: bool = false


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _t < SETTLE:
		return
	_done = true
	await _shoot(0)
	var total: int = (_screen.get("current_filtered_songs") as Array).size()
	for i: int in range(1, total):
		_screen.call("change_selection", 1, false)
		var wait: float = 0.0
		while wait < HOLD:
			await get_tree().process_frame
			wait += get_process_delta_time()
		await _shoot(i)
	get_tree().quit()


func _shoot(index: int) -> void:
	await RenderingServer.frame_post_draw
	var songs: Array = _screen.get("current_filtered_songs") as Array
	var song: Dictionary = songs[index] as Dictionary if index < songs.size() else {}
	var title := _screen.get_node_or_null("UI/InfoTitle") as Label
	var path: String = "user://carousel_%d.png" % index
	get_viewport().get_texture().get_image().save_png(path)
	print("OUT %d  cur=%s  song=%s  titulo=%s  visible=%s  %s" % [index,
		str(_screen.get("cur_selected")), str(song.get("id", "<aleatorio>")),
		"" if title == null else title.text,
		"-" if title == null else str(title.visible),
		ProjectSettings.globalize_path(path)])
