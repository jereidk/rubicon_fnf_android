# Dispara el puerto en el MISMO instante del encendido que la captura del mod.
#
# La captura de tutorial esta tomada con el destello del tubo todavia arriba (8aa), y eso
# no es un detalle del televisor: el destello arranca en la linea 1642 y las 1645-1648 -los
# personajes, el marcador y el changeSelection que enciende la cabecera- van justo detras.
# O sea que en esa captura TODO lo que se mueve esta a medio camino: el velo oscuro sigue
# bajando (1639, 0.65 s), el titulo de la capsula sigue con su glitch (1104-1107), el ruido
# acaba de recibir su golpe de alfa (1100-1102) y los discos siguen viajando.
#
# Comparar eso contra un render asentado mezcla diferencias de verdad con cosas a medio
# hacer. Esto espera a que el alfa del destello baje del valor que se le midio a la captura
# -0.40, ajustado por su histograma- y dispara ahi.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/intro_at.tscn -- 0.40
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
## El mismo 0.75 s de doIntroAnim 1642.
const INTRO_FLASH := 0.75

var _screen: Node = null
var _done: bool = false
var _want: float = 0.40


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.is_valid_float():
			_want = arg.to_float()
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


var _t0: float = -1.0
var _t: float = 0.0


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var flash := _screen.get_node_or_null("TvSpriteFlash") as ColorRect
	if flash == null or not flash.visible:
		return
	if _t0 < 0.0:
		_t0 = _t
		return
	# El destello cae con circOut en 0.75 s, o sea alfa = 1 - sqrt(1 - (t-1)^2) con t
	# normalizado. Se despeja el instante que corresponde al alfa pedido y se espera a el,
	# en vez de mirar el alfa fotograma a fotograma: el tween se mueve tan rapido al
	# principio que un paso de fotograma se salta medio recorrido.
	var target_t: float = (1.0 - sqrt(1.0 - (1.0 - _want) * (1.0 - _want))) * INTRO_FLASH
	if _t - _t0 < target_t:
		return
	_done = true
	# Y ya puestos, el destello se clava en el valor exacto, que asi el tubo no depende de
	# donde cayera el fotograma.
	flash.modulate.a = _want
	await RenderingServer.frame_post_draw
	var path: String = "user://intro_at.png"
	get_viewport().get_texture().get_image().save_png(path)
	var dark := _screen.get_node_or_null("DarkOverlay") as CanvasItem
	var title := _screen.get_node_or_null("UI/InfoTitle") as Label
	print("OUT destello a=%.3f  velo=%s  titulo='%s'  %s" % [flash.modulate.a,
		"ausente" if dark == null else "a=%.3f" % dark.modulate.a,
		"" if title == null else title.text,
		ProjectSettings.globalize_path(path)])
	get_tree().quit()
