# Mide el brillo de la pantalla del televisor capa a capa.
#
# La superposicion contra el mod dice que la pantalla del puerto sale a luma 74 donde la del
# mod sale a 119, y eso NO es el juego de fotogramas: los 24 de TVNOISE del puerto promedian
# 96.9 contra los 95.4 de los 111 originales, con el mismo recorte de 373x301. Asi que lo
# que hay que saber es cual de las capas que van dentro del tubo aporta menos de lo que
# deberia, y para eso hay que apagarlas de una en una y medir.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/tv_layers.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5
## La ventana de medida, en coordenadas de Funkin, bien dentro del agujero del tubo.
const WINDOW := Rect2(160.0, 170.0, 300.0, 230.0)
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
## Las cuatro que se dibujan dentro del tubo, de atras a delante con su zIndex.
const LAYERS: Array[String] = ["TvBg", "TvBackBG", "TvNoiseBack", "TvNoiseForward"]

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

	print("OUT estado inicial:")
	for name: String in LAYERS:
		var node := _screen.get_node_or_null(name) as CanvasItem
		print("OUT   %-15s %s" % [name, "ausente" if node == null
			else "visible=%s modulate=%s" % [node.visible, str(node.modulate)]])

	# El ruido ANIMA a 24 fps y sus fotogramas van de un brillo medio de 66 a uno de 173,
	# asi que una medida suelta no dice nada: hay que recorrer varios y dar el rango.
	var samples: Array[float] = []
	for i: int in 40:
		samples.append(await _luma())
	samples.sort()
	print("OUT luma de la pantalla en %d fotogramas: min %.1f  mediana %.1f  max %.1f"
		% [samples.size(), samples[0], samples[samples.size() / 2],
		samples[samples.size() - 1]])
	for off: String in LAYERS:
		var node := _screen.get_node_or_null(off) as CanvasItem
		if node == null or not node.visible:
			continue
		node.visible = false
		var without: Array[float] = []
		for i: int in 20:
			without.append(await _luma())
		without.sort()
		print("OUT sin %-15s min %.1f  mediana %.1f  max %.1f"
			% [off, without[0], without[without.size() / 2], without[without.size() - 1]])
		node.visible = true
	get_tree().quit()


## Luma media de la ventana, en la escala 0..255 con la que se midio la captura del mod.
func _luma() -> float:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var total: float = 0.0
	var count: int = 0
	var x0: int = int(WINDOW.position.x * FUNKIN_TO_RUBICON)
	var y0: int = int(WINDOW.position.y * FUNKIN_TO_RUBICON)
	var x1: int = int(WINDOW.end.x * FUNKIN_TO_RUBICON)
	var y1: int = int(WINDOW.end.y * FUNKIN_TO_RUBICON)
	for y: int in range(y0, y1, 2):
		for x: int in range(x0, x1, 2):
			var c: Color = image.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			count += 1
	return 255.0 * total / float(maxi(count, 1))
