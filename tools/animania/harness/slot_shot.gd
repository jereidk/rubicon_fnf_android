# Una toma de un hueco concreto del carrusel, con tiempo de sobra para que todo asiente.
#
# carousel_shot.gd recorre y dispara a los 0.6 s de cada salto, que sirve para ver que la
# seleccion se mueve pero no para comparar contra una captura: los discos siguen viajando,
# el tema esta subiendo de volumen y los personajes acaban de entrar. Esto se planta en un
# hueco y espera.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/slot_shot.tscn -- 1
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5
const HOLD := 3.0

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
	var want: int = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_int():
			want = arg.to_int()
	for _i: int in want:
		_screen.call("change_selection", 1, false)
	var wait: float = 0.0
	while wait < HOLD:
		await get_tree().process_frame
		wait += get_process_delta_time()
	await RenderingServer.frame_post_draw
	var songs: Array = _screen.get("current_filtered_songs") as Array
	var song: Dictionary = songs[_screen.get("cur_selected")]
	var path: String = "user://slot_%d.png" % want
	get_viewport().get_texture().get_image().save_png(path)
	var dots := _screen.get_node_or_null("UI/DotsGrp") as Node2D
	var shown: PackedStringArray = []
	if dots != null:
		for d: Node in dots.get_children():
			if (d as Sprite2D).visible:
				shown.append("%s@%.1f" % [String(d.get_meta(&"diff", "")),
					(d as Sprite2D).global_position.x / 1.5])
	print("OUT hueco %d  cancion=%s  diff=%s  puntos=%s" % [want,
		str(song.get("id", "<aleatorio>")), str(_screen.get("current_difficulty")),
		", ".join(shown)])
	print("OUT %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
