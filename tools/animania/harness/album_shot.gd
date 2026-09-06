# Mide la caratula del freeplay dejandola SOLA en la pantalla.
#
# La toma normal no sirve para comprobar su geometria: el ruido del televisor va encima
# con alfa 0.45 y el frontal del aparato le tapa medio titulo, asi que los pixeles que se
# ven no son los del album. Aqui se apaga todo lo demas y se mide el rectangulo opaco de
# cada pieza, que es lo unico que se puede comparar contra el binario.
#
# La ventana del proyecto es 1366x768 sobre un lienzo de 1920x1080, asi que la toma sale
# a escala 0.711 si no se pide la resolucion entera. Con --resolution 1920x1080 un pixel
# del render es un pixel del lienzo y la division por 1.5 da coordenadas de Funkin.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/album_shot.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const SETTLE := 2.5

var _frames: int = 0
var _t: float = 0.0
var _screen: Node = null
## _process sigue corriendo mientras los `await` de abajo esperan fotogramas, asi que sin
## esto la medida se repite cuatro veces y cada pasada apaga lo que la anterior encendio.
var _done: bool = false


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	if _done:
		return
	_frames += 1
	_t += delta
	if _frames < 6 or _t < SETTLE:
		return
	_done = true

	var album := _screen.get_node_or_null("UI/AlbumRoll") as Node2D
	if album == null:
		print("OUT FALLO no hay UI/AlbumRoll")
		get_tree().quit()
		return

	# Todo lo demas fuera. Los ANTEPASADOS del album no: apagar `UI` -que es quien lo
	# cuelga- deja la pantalla negra entera y la medida sale vacia sin decir por que.
	var keep: Array[Node] = []
	var walk: Node = album
	while walk != null:
		keep.append(walk)
		walk = walk.get_parent()
	for node: Node in _screen.find_children("*", "CanvasItem", true, false):
		if not keep.has(node):
			(node as CanvasItem).visible = false
	for node: Node in keep:
		if node is CanvasItem:
			(node as CanvasItem).visible = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 1))

	for piece: String in ["AlbumArt", "AlbumTitle"]:
		for other: String in ["AlbumArt", "AlbumTitle"]:
			var node := album.get_node_or_null(other) as CanvasItem
			if node != null:
				node.visible = other == piece
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		# get_used_rect() mira el ALFA y el render de la ventana es opaco entero, asi que
		# devolveria la pantalla completa siempre. Se mide por color: lo que no sea el
		# negro del fondo.
		var rect: Rect2i = _ink(image)
		if rect.size == Vector2i.ZERO:
			print("OUT %-11s nada visible" % piece)
			continue
		print("OUT %-11s device %s  funkin (%.1f, %.1f) %.1fx%.1f" % [piece, str(rect),
			rect.position.x / FUNKIN_TO_RUBICON, rect.position.y / FUNKIN_TO_RUBICON,
			rect.size.x / FUNKIN_TO_RUBICON, rect.size.y / FUNKIN_TO_RUBICON])

	for piece: String in ["AlbumArt", "AlbumTitle"]:
		var node := album.get_node_or_null(piece) as CanvasItem
		if node != null:
			node.visible = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://album.png")
	print("OUT %s" % ProjectSettings.globalize_path("user://album.png"))
	get_tree().quit()


## El rectangulo de todo lo que no es fondo negro.
func _ink(image: Image) -> Rect2i:
	var min_x: int = image.get_width()
	var min_y: int = image.get_height()
	var max_x: int = -1
	var max_y: int = -1
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			if c.r + c.g + c.b < 0.02:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
