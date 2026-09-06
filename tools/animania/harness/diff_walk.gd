# Recorre el carrusel y, en cada hueco, gira la dificultad entera.
#
# Desde que `currentDifficulty` es la CADENA que es en el mod, lo que hay que ver es que
# cada cancion trae su propia lista -phone-call solo `standart`-, que la dificultad que se
# traia se conserva cuando la cancion la ofrece y cae en la ultima cuando no, y que la
# capsula ensena el RATING y no el nombre.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/diff_walk.tscn
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
		_line("  al llegar")
		for _j: int in 4:
			_screen.call("change_diff", 1, false)
			await get_tree().process_frame
			_line("  +1")
	get_tree().quit()


func _line(what: String) -> void:
	var diff := _screen.get_node_or_null("UI/InfoDifficulty") as Label
	var stars: Node = _screen.get("difficulty_stars")
	var on: int = 0
	if stars != null:
		for star: Node in stars.get_children():
			if (star as AnimatedSprite2D).animation == &"difficulty star":
				on += 1
	print("OUT %-12s %-10s diff=%-9s lista=%s  capsula='%s'  estrellas=%d" % [
		str(_screen.get("cur_selected")), what,
		str(_screen.get("current_difficulty")),
		str(_screen.get("current_diffs_ids")),
		"" if diff == null else diff.text, on])
