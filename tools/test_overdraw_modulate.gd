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

	_finish()


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
