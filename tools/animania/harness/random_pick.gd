# Sortea el disco aleatorio muchas veces y ensena que dificultad se lleva cada eleccion.
#
# capsuleOnConfirmRandom filtra por dificultad (linea 560), asi que lo que hay que ver es
# que nunca sale una pareja cancion/dificultad que la cancion no ofrezca.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/random_pick.tscn
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
	for want: String in ["hard", "standart", "easy", "nightmare"]:
		var seen: Dictionary = {}
		for _i: int in 40:
			_screen.set("current_difficulty", want)
			_screen.set("cur_selected", 0)
			_screen.set("_confirmed", false)
			_screen.set("allow_input", true)
			_screen.call("_capsule_on_confirm_random")
			var songs: Array = _screen.get("current_filtered_songs") as Array
			var index: int = _screen.get("cur_selected")
			var id: String = "<ninguna>" if index == 0 \
				else String((songs[index] as Dictionary).get("id", ""))
			seen["%s / %s" % [id, _screen.get("current_difficulty")]] = true
		print("OUT llevando '%-9s' -> %s" % [want, ", ".join(seen.keys())])
	get_tree().quit()
