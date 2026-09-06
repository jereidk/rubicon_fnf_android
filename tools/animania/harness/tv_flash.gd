# Sigue el brillo del tubo durante el encendido, fotograma a fotograma.
#
# La captura del mod sobre tutorial tiene el tubo BLANCO -luma media 225.7, contra 122.5 en
# la del disco aleatorio- y con el mismo ruido debajo, solo que lavado. La unica cosa blanca
# que hay ahi dentro es `tvSpriteFlash`, el rectangulo 0xffffffff que buildBg 1300 pone a
# zIndex 29, por encima de las dos capas de ruido y de la caratula, y que doIntroAnim
# 1641-1642 enciende opaco y apaga en 0.75 s con circOut.
#
# O sea que aquella captura no es un estado distinto: es un fotograma del encendido, tomado
# unos 20-30 ms despues de que el destello empiece. Cuadra con todo lo demas que se ve en
# ella -la cabecera encendida y los personajes puestos son las lineas 1645-1648, que van
# justo detras del destello-.
#
# Esto lo comprueba en el puerto: si la curva pasa por 225 y baja, es lo mismo.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/tv_flash.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
## La misma ventana con la que se midieron las dos capturas del mod.
const WINDOW := Rect2(190.0, 200.0, 290.0, 200.0)
const UNTIL := 2.6

var _t: float = 0.0
var _screen: Node = null
var _rows: Array[String] = []


func _ready() -> void:
	_screen = load(SCREEN).instantiate()
	add_child(_screen)


func _process(delta: float) -> void:
	_t += delta
	if _t > UNTIL:
		set_process(false)
		for row: String in _rows:
			print(row)
		get_tree().quit()
		return
	if _t < 0.85:
		return
	var flash := _screen.get_node_or_null("TvSpriteFlash") as ColorRect
	_rows.append("OUT t=%.3f  luma %6.1f  destello %s" % [_t, _luma(),
		"ausente" if flash == null
		else "visible=%s a=%.3f" % [flash.visible, flash.modulate.a]])


## Luma media de la ventana del tubo, en la escala 0..255 de las capturas.
func _luma() -> float:
	var image: Image = get_viewport().get_texture().get_image()
	var total: float = 0.0
	var count: int = 0
	for y: int in range(int(WINDOW.position.y * FUNKIN_TO_RUBICON),
			int(WINDOW.end.y * FUNKIN_TO_RUBICON), 4):
		for x: int in range(int(WINDOW.position.x * FUNKIN_TO_RUBICON),
				int(WINDOW.end.x * FUNKIN_TO_RUBICON), 4):
			var c: Color = image.get_pixel(x, y)
			total += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			count += 1
	return 255.0 * total / float(maxi(count, 1))
