# Saca a cada personaje del dormitorio SOLO, sobre negro, y da su caja en pixeles.
#
# Existe porque el alineador por bordes no vale para esto: sobre la pareja de la captura
# del mod devuelve escalas 1.15, 0.88 y 0.87 segun la caja que se le de, con correlaciones
# de 0.23, 0.19 y 0.12. Arte blando, con brillo verde encima y los dos personajes pisandose
# no da bordes que casar. Lo que si se puede hacer es medir por PUNTOS: sacar el recorte
# limpio de cada uno aqui y buscarlo en la captura por correlacion normalizada.
#
# De paso da lo que hace falta para el otro lado de la cuenta: donde cae hoy cada personaje
# en pantalla, que es lo que hay que mover.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/char_solo.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const SETTLE := 2.5
const WHO: Array[String] = ["Player2", "Girlfriend"]
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0

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
	# Todo fuera menos el grupo de la cama, y dentro de el solo uno cada vez.
	for child: Node in _screen.get_children():
		var item := child as CanvasItem
		if item != null and child.name != "ShadowsOnBed":
			item.visible = false
	var shadows: Node = _screen.get_node("ShadowsOnBed")
	for child: Node in shadows.get_children():
		var item := child as CanvasItem
		if item != null:
			item.visible = false
	for who: String in WHO:
		var node := shadows.get_node_or_null(who) as CanvasItem
		if node == null:
			print("OUT %s ausente" % who)
			continue
		node.visible = true
		# La pose se CONGELA. Los dos personajes tienen su idle en marcha, y la caja de lo
		# pintado cambia de un fotograma a otro -el brazo de bf la mueve unos 20 px en x-,
		# asi que sin esto la medida no repite y la esquina local que sale de ella no vale
		# para despejar nada.
		var anims := node.get_node_or_null("Anims") as AnimationPlayer
		if anims != null:
			anims.play(anims.autoplay)
			anims.seek(0.0, true)
			anims.pause()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "user://solo_%s.png" % who
		image.save_png(path)
		print("OUT %-11s nodo %s  caja %s  %s" % [who, str((node as Node2D).position),
			str(_box(image)), ProjectSettings.globalize_path(path)])
		node.visible = false
	get_tree().quit()


## La caja de lo que se ha pintado, en coordenadas de Funkin, que es en las que estan
## escritas GF_AT y BF_AT en el builder.
func _box(image: Image) -> Rect2:
	var x0: int = image.get_width()
	var y0: int = image.get_height()
	var x1: int = -1
	var y1: int = -1
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var c: Color = image.get_pixel(x, y)
			if c.r + c.g + c.b < 0.06:
				continue
			x0 = mini(x0, x); y0 = mini(y0, y)
			x1 = maxi(x1, x); y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2()
	return Rect2(x0 / FUNKIN_TO_RUBICON, y0 / FUNKIN_TO_RUBICON,
		(x1 - x0) / FUNKIN_TO_RUBICON, (y1 - y0) / FUNKIN_TO_RUBICON)
