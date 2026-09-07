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
	# Segundo argumento opcional: el alfa al que dejar `tvSpriteFlash`, el rectangulo blanco
	# del encendido. Sirve para comparar contra una captura del mod tomada DURANTE el
	# destello -la de tutorial lo esta, a un alfa de 0.78 medido por el brillo del tubo-,
	# que si no es imposible de reproducir a mano: el destello dura 0.75 s con circOut y
	# pasa por ese valor en los primeros 25 ms.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Repetibilidad: NO congelar nada aqui. Dos tomas seguidas del mismo codigo no
	# coincidian -el cabecero salio a 87.0 y a 99.3, el tubo a 126.5 y a 117.8- porque las
	# animaciones avanzan con el tiempo real. La primera idea, poner cada AnimatedSprite2D
	# en el frame 0, es peor que el problema: el frame 0 del televisor es el APAGADO, asi
	# que la toma sale con el tubo a 26 y el mueble a 15 y ya no compara nada. Lo que si
	# vale es lanzar godot con `--fixed-fps 60`: el delta deja de depender del reloj y dos
	# pasadas dan el mismo tubo (109.3 y 109.3) sin tocar el estado de la escena.
	# TODOS los ajustes van aqui y con UN SOLO `await` detras, se hayan usado o no.
	#
	# Esto no es manía: cada `await process_frame` adelanta un fotograma la nieve del
	# televisor, y esa animacion cambia mucho de un fotograma al siguiente. Con un `await`
	# dentro de cada bloque, una toma con `hide=` y otra sin el salian con la nieve en
	# fases distintas y la comparacion entre las dos medía eso ademas de la capa. Costo
	# real: el primer barrido del radio del desenfoque salio con las tomas de referencia
	# desfasadas y hubo que tirarlo entero. Dos tomas solo son comparables si han corrido
	# el mismo numero de fotogramas.
	#
	# `blur=N`   el radio del shader de `ShadowsOnBed`, para barrerlo sin reconstruir.
	# `hide=A,B` nodos a ocultar: es lo unico que aisla lo que aporta una capa concreta.
	# El segundo argumento suelto, si es un numero, es el alfa de `tvSpriteFlash`.
	for a: String in args:
		if a.begins_with("blur="):
			var n := _screen.get_node_or_null(^"ShadowsOnBed") as CanvasItem
			var mat := (n.material if n != null else null) as ShaderMaterial
			if mat == null:
				push_warning("blur: ShadowsOnBed no tiene ShaderMaterial")
				continue
			var v: float = a.substr(5).to_float()
			mat.set_shader_parameter(&"radius", Vector2(v, v))
		elif a.begins_with("tvbg="):
			# El fotograma de `TvBg`. TVBACK son 98 y su brillo en una zona dada va de 9 a
			# 160, asi que comparar contra una captura sin fijarlo compara fases.
			var bg := _screen.get_node_or_null(^"TvBg") as AnimatedSprite2D
			if bg == null:
				push_warning("tvbg: no existe TvBg")
				continue
			bg.pause()
			bg.frame = a.substr(5).to_int()
		elif a.begins_with("hide="):
			for nm: String in a.substr(5).split(",", false):
				var n := _screen.get_node_or_null(NodePath(nm)) as CanvasItem
				if n == null:
					push_warning("hide: no existe %s" % nm)
					continue
				n.visible = false
	if args.size() > 1 and args[1].is_valid_float():
		var flash := _screen.get_node_or_null("TvSpriteFlash") as ColorRect
		if flash != null:
			flash.visible = true
			flash.modulate.a = args[1].to_float()
	await get_tree().process_frame
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
