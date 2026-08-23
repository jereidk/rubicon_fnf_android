extends SceneTree

## `over=` tiene que contar capas que la GPU dibuja, no nodos del arbol.
##
## Godot salta un CanvasItem cuyo modulate **heredado** tiene alfa cero, y con
## el subarbol entero, antes de llegar al rasterizador. Medido en la ruta del
## telefono con ocho rects a pantalla completa:
##
##     opaco              28.8ms   draws=1 prims=16
##     modulate.a = 0      0.79ms  draws=0 prims=0     <- no es una capa
##     color.a = 0        30.5ms   draws=1 prims=16    <- SI es una capa, y cara
##     visible = false     0.90ms  draws=0 prims=0
##
## `_screen_area()` solo miraba `is_visible_in_tree()`, asi que sumaba como
## capa entera cualquier rect transparente. No es hipotetico: Training
## registro `over=7.2x top=.../MissVignette@1.0x` para un vignette a rect
## completo que entre fallos esta en `modulate = Color(1, 1, 1, 0)`, o sea que
## la GPU no lo toca nunca.
##
## Y explica por que este fichero tenia escrito que `over=` no correlaciona con
## `gpu=` - 3.0x a 33.4ms contra 3.1x a 18.2ms: parte de lo que contaba no se
## dibujaba.
##
## Lo que este guard fija, ademas del arreglo, es su **limite**:
## `self_modulate` y el `color` de un ColorRect NO entran en la prueba, porque
## los dos son por item y Godot dibuja el item igual - y el mismo banco mide
## `color.a = 0` mas caro que opaco.
##
##   godot --headless --path . --script tools/test_overdraw_modulate.gd

const LOG := "res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var src: String = _read(LOG)
	_check(src != "", "el log se lee")

	_check(_has_statement(src, "if _inherited_modulate_alpha(node) <= 0.0:"),
		"_screen_area descarta un item con el modulate heredado a cero")
	_check(_has_statement(src, "alpha *= item.modulate.a"),
		"y lo calcula multiplicando la cadena, no leyendo solo el nodo")
	_check(_has_statement(src, "walk = walk.get_parent()"),
		"subiendo por los padres")
	_check(not _has_statement(src, "alpha *= item.self_modulate.a"),
		"self_modulate NO entra: Godot dibuja el item igual")

	# Y el comportamiento, sobre nodos reales, que es lo que un guard textual
	# no puede ver: la cadena tiene que multiplicar de verdad.
	var root := Control.new()
	var mid := Control.new()
	var leaf := ColorRect.new()
	root.add_child(mid)
	mid.add_child(leaf)

	var probe: GDScript = load(LOG)
	_check(probe != null, "el script del log carga como recurso")

	# El helper es privado y el autoload no existe bajo --script, asi que la
	# cadena se reproduce aqui con la misma regla y se comprueba contra los
	# casos que importan. Lo que el guard de arriba fija es que el fichero
	# use esa regla; esto fija que la regla sea la correcta.
	_check(_chain_alpha(leaf) == 1.0, "cadena opaca -> 1.0")
	mid.modulate.a = 0.0
	_check(_chain_alpha(leaf) == 0.0,
		"un padre a alfa 0 apaga al hijo (es lo que hace Godot)")
	mid.modulate.a = 0.5
	leaf.modulate.a = 0.5
	_check(is_equal_approx(_chain_alpha(leaf), 0.25), "y se multiplica, no se toma el minimo")
	mid.modulate.a = 1.0
	leaf.modulate.a = 1.0
	leaf.self_modulate.a = 0.0
	_check(_chain_alpha(leaf) == 1.0,
		"self_modulate a 0 NO apaga: el item se dibuja igual")
	leaf.color = Color(0, 0, 0, 0)
	_check(_chain_alpha(leaf) == 1.0,
		"color.a = 0 tampoco: medido MAS caro que opaco")
	root.free()

	_rank_checks(src)

	_finish()


## `relleno=`: the same field, but naming who pays it.
##
## `over=` has been the most useful number in this log for a 2D scene and the
## least actionable, because it named exactly one contributor. Safety Lullaby
## measures `gpu=32.48ms` against Chimera's `15.27ms` while drawing 592
## primitives to Chimera's 15645 and no 3D at all, and the only counter that
## separates them is `over=5.0x` against `1.1x`. Across the two pure-2D scenes
## in that log - credits at `over=2.0x`/`gpu=7.41ms` and Safety at
## `over=5.0x`/`gpu=32.48ms` - the slope is about 8ms of GPU per screen of 2D
## fill at 1600x720, so four wasted screens is the entire frame budget of the
## song. Knowing which four is the whole difference between a measurement and
## a fix.
##
## The alpha travels with each name on purpose. Everything above this function
## is about the one case Godot really does skip (inherited modulate); the case
## it does NOT skip is a full-screen item that paints nothing anyway, and that
## is measured twice in this repo - `color.a = 0` at 30.5ms against 28.8ms
## opaque in the bench above, and `trance_shaders.gd`'s identity pass at 20.0ms
## against 6.7ms hidden. `a=0.00` next to `@1.00x` is that item, named.
func _rank_checks(src: String) -> void:
	_check(_has_statement(src, "_rank_overdraw(overdraw_rank, area, node)"),
		"cada item con area entra en el ranking")
	_check(_has_statement(src, "relleno=[%s]"),
		"y el CENSUS lleva un campo relleno=")
	_check(src.contains("const OVERDRAW_RANK := 6"),
		"acotado a seis nombres, que es lo que cabe en la linea")
	_check(_has_statement(src, "and not _alpha_is_knowable(node) else \"%.2f\" % opacity"),
		"cada nombre lleva su alfa, y '?' cuando no se puede leer")

	# El ranking corre dentro del mismo paseo del censo, que en la tienda
	# recorre miles de CanvasItems: por insercion acotada, no ordenando la
	# lista entera.
	_check(not _has_statement(src, "overdraw_rank.sort"),
		"sin ordenar la lista completa dentro del paseo")

	# Y el comportamiento: los seis mayores, de mayor a menor.
	var probe: GDScript = load(LOG)
	if probe == null:
		return
	var node := Node.new()
	node.set_script(probe)
	var rank: Array = []
	var made: Array[ColorRect] = []
	for i in 9:
		var rect := ColorRect.new()
		rect.name = "Rect%d" % i
		made.append(rect)
		node.call("_rank_overdraw", rank, float(i + 1), rect)
	_check(rank.size() == 6, "se quedan seis (son %d)" % rank.size())
	var names: PackedStringArray = []
	for pair in rank:
		names.append(str((pair[1] as Node).name))
	_check(", ".join(names) == "Rect8, Rect7, Rect6, Rect5, Rect4, Rect3",
		"y son los seis mayores, de mayor a menor (%s)" % ", ".join(names))
	for rect in made:
		rect.free()
	node.free()


func _chain_alpha(node: CanvasItem) -> float:
	var alpha: float = 1.0
	var walk: Node = node
	while walk != null:
		var item := walk as CanvasItem
		if item == null:
			break
		alpha *= item.modulate.a
		if alpha <= 0.0:
			return 0.0
		walk = walk.get_parent()
	return alpha


func _has_statement(src: String, needle: String) -> bool:
	for line: String in src.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text
