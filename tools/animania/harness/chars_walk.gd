# Recorre el carrusel y dice si bf y gf estan puestos en cada hueco.
#
# La skin de freeplay va POR CANCION: `changeSelection` 842-843 llama a changeCharacter con
# `songData.songGFSkin` y `songData.songPlayerSkin`, que salen del nivel superior del
# metadata de cada cancion. phone-call declara 'none' en las dos, y 'none' es la skin vacia
# -la misma con la que el hueco aleatorio deja la cama pelada-, asi que phone-call tiene que
# salir SIN los dos personajes.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/chars_walk.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5

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
	var total: int = (_screen.get("current_filtered_songs") as Array).size()
	for i: int in total:
		if i > 0:
			_screen.call("change_selection", 1, false)
		await get_tree().process_frame
		var songs: Array = _screen.get("current_filtered_songs") as Array
		var song: Dictionary = songs[i]
		var gf := _screen.get_node_or_null("ShadowsOnBed/Girlfriend") as CanvasItem
		var bf := _screen.get_node_or_null("ShadowsOnBed/Player2") as CanvasItem
		print("OUT %d %-12s skins=%s/%s  gf=%s bf=%s" % [i,
			str(song.get("id", "<aleatorio>")),
			str(_screen.get("current_player")), str(_screen.get("current_girlfriend")),
			gf != null and gf.visible, bf != null and bf.visible])
	get_tree().quit()
