# Mide el CONTRASTE del ruido del tubo fotograma a fotograma, con el destello sujeto.
#
# Comparar el tubo con la captura del mod a un solo fotograma no dice nada: el ruido son 24
# fotogramas a 24 fps y unos llevan bandas horizontales gruesas y otros son grano fino. Lo
# que hay que ver es si el RANGO del puerto cubre lo que mide la captura -media 225.7 con
# p5 154 y p95 255, o sea unos 100 de recorrido-, no si un fotograma suelto coincide.
#
#   xvfb-run -a --server-args="-screen 0 1920x1080x24" godot --resolution 1920x1080 \
#       --rendering-driver opengl3 --path . res://tools/animania/harness/tv_grain.tscn
extends Node2D

const SCREEN := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
const FUNKIN_TO_RUBICON := 1920.0 / 1280.0
const WINDOW := Rect2(190.0, 200.0, 290.0, 200.0)
const SETTLE := 2.5
const FRAMES := 60
const FLASH_ALPHA := 0.78

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
	_screen.call("change_selection", 1, false)
	var flash := _screen.get_node_or_null("TvSpriteFlash") as ColorRect
	if flash != null:
		flash.visible = true
		flash.modulate.a = FLASH_ALPHA
	var best: Array[float] = []
	for i: int in FRAMES:
		await RenderingServer.frame_post_draw
		if flash != null:
			flash.modulate.a = FLASH_ALPHA
		var s: Array[float] = _stats()
		best.append(s[3])
		if i % 10 == 0 or s[3] > 80.0:
			print("OUT %2d  media %6.1f  p5 %5.1f  p95 %5.1f  recorrido %5.1f"
				% [i, s[0], s[1], s[2], s[3]])
	best.sort()
	print("OUT recorrido en %d fotogramas: min %.1f  mediana %.1f  max %.1f  (mod 101)"
		% [FRAMES, best[0], best[best.size() / 2], best[best.size() - 1]])
	get_tree().quit()


## Media, percentil 5, percentil 95 y recorrido de la ventana del tubo.
func _stats() -> Array[float]:
	var image: Image = get_viewport().get_texture().get_image()
	var vals: Array[float] = []
	for y: int in range(int(WINDOW.position.y * FUNKIN_TO_RUBICON),
			int(WINDOW.end.y * FUNKIN_TO_RUBICON), 4):
		for x: int in range(int(WINDOW.position.x * FUNKIN_TO_RUBICON),
				int(WINDOW.end.x * FUNKIN_TO_RUBICON), 4):
			var c: Color = image.get_pixel(x, y)
			vals.append(255.0 * (c.r * 0.299 + c.g * 0.587 + c.b * 0.114))
	vals.sort()
	var total: float = 0.0
	for v: float in vals:
		total += v
	var p5: float = vals[int(vals.size() * 0.05)]
	var p95: float = vals[int(vals.size() * 0.95)]
	return [total / float(vals.size()), p5, p95, p95 - p5]
