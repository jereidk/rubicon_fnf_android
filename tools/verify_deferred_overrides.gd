extends SceneTree

## La consola diferida contra la consola INLINE original, nodo a nodo.
##
## Esta es la comprobacion que la herramienta de extraccion anterior no hizo, y
## por eso no vio que su salida estaba rota. Comparaba el arbol vivo contra si
## mismo. Aqui se compara contra la OTRA cosa: el .tscn de la tienda de antes de
## sacar la consola, que la tenia instanciada dentro, y que es la unica
## referencia que dice como tiene que quedar.
##
## Lo que caza, medido sobre la version que reemplaza:
##
##     console.tscn        382 nodos    0 padres con hijos repetidos
##     console_shop.tscn   582 nodos   43 padres,  68 hijos sobrantes   (pack)
##     console_shop.tscn   382 nodos    0 padres,   0 sobrantes         (overrides)
##
## Los 200 nodos de mas venian de que `pack()` reescribe los hijos de una
## subescena instanciada SIN `index=`, y sin `index` Godot los anade en vez de
## sobreescribirlos. En pantalla eran dos marcas de verificacion una sobre otra
## en cada toggle.
##
## Los seis NodePath que salen de la consola NO se comparan: no se pueden
## escribir en ningun fichero y los pone console_deferred_loader.gd, que es lo
## que comprueba tools/harness/probe_console_deferred.tscn contra el arbol vivo.
##
## Necesita el .tscn de la tienda de antes DENTRO del proyecto, porque Godot solo
## carga desde res://. Se pone y se quita:
##
##   git show 1dcde58b~1:lullaby_mod/rooms/env_collector_shop.tscn \
##     > tools/_ref_shop_before.tscn
##   godot --headless --path . --script tools/verify_console_overrides.gd
##   rm tools/_ref_shop_before.tscn
##
## No se deja en el arbol: `export_filter="all_resources"` se lo llevaria al APK.

const REF := "res://tools/_ref_shop_before.tscn"

## Las dos escenas diferidas: donde estaban inline en la tienda, y el fichero
## que las sustituye.
const TARGETS: Array = [
	["Viewports/ConsoleSubViewport/Console",
		"res://lullaby_mod/resources/console/console_shop.tscn"],
	["Viewports/KollectadexSubViewport/Kollectadex",
		"res://lullaby_mod/resources/kollectadex/kollectadex_shop.tscn"],
]

## Las propiedades de los 21 bloques de override, para compararlas una a una.
## Sin los seis de cruce, que no viven en el fichero.
const OVERRIDDEN: Array[String] = [
	"modulate", "scale", "offset_left", "offset_top", "offset_right",
	"offset_bottom", "anchor_left", "anchor_top", "anchor_right", "anchor_bottom",
	"transform", "volume_db", "bus", "bind_label", "visible", "current_tab",
	"is_activated", "surface_material_override/0",
]

var _failures: int = 0
var _checks: int = 0

## Acumulados entre escenas. Exigir una muestra no vacia POR escena era falso: el
## kollectadex no tiene ni un NodePath interno en un nodo con script, y la
## comprobacion fallaba por no encontrar lo que no existe. Lo que hay que
## garantizar es que la comparacion se ejecuto de verdad en alguna parte, no en
## todas.
var _props_compared: int = 0
var _paths_compared: int = 0


func _initialize() -> void:
	if not ResourceLoader.exists(REF):
		printerr("FALTA %s - ver la cabecera de este fichero" % REF)
		quit(2)
		return

	var ref_packed: PackedScene = load(REF) as PackedScene
	if not _check(ref_packed != null, "la tienda de referencia carga"):
		_finish()
		return
	var ref_shop: Node = ref_packed.instantiate()

	for target: Array in TARGETS:
		_compare(ref_shop, target[0], target[1])

	ref_shop.free()
	_finish()


func _compare(ref_shop: Node, inline_path: String, packed_path: String) -> void:
	print("--- %s" % packed_path.get_file())
	var ref: Node = ref_shop.get_node_or_null(NodePath(inline_path))
	if not _check(ref != null, "la tienda de referencia la trae inline en %s" % inline_path):
		return

	var new_packed: PackedScene = load(packed_path) as PackedScene
	if not _check(new_packed != null, "%s carga" % packed_path.get_file()):
		return
	var got: Node = new_packed.instantiate()

	# 1. El arbol: mismas rutas, mismas clases, mismo numero.
	var ref_map: Dictionary = {}
	var got_map: Dictionary = {}
	_walk(ref, ref, ref_map)
	_walk(got, got, got_map)

	_check(ref_map.size() == got_map.size(),
		"mismo numero de nodos (referencia %d, nuevo %d)" % [ref_map.size(), got_map.size()])

	var missing: PackedStringArray = []
	var extra: PackedStringArray = []
	var wrong_class: PackedStringArray = []
	for p: String in ref_map:
		if not got_map.has(p):
			missing.append(p)
		elif got_map[p] != ref_map[p]:
			wrong_class.append("%s (%s vs %s)" % [p, ref_map[p], got_map[p]])
	for p: String in got_map:
		if not ref_map.has(p):
			extra.append(p)

	_check(missing.is_empty(), "no falta ningun nodo%s" % _list(missing))
	_check(extra.is_empty(), "ni sobra ninguno%s" % _list(extra))
	_check(wrong_class.is_empty(), "y las clases coinciden%s" % _list(wrong_class))

	# 2. Hijos de nombre repetido: cero, que es el fallo concreto de pack().
	_check(_dup_children(got) == 0,
		"ningun nodo tiene hijos de nombre repetido (%d)" % _dup_children(got))
	_check(_dup_children(ref) == 0,
		"y la referencia tampoco los tenia (%d)" % _dup_children(ref))

	# 3. Las propiedades sobreescritas, nodo por nodo.
	var diffs: PackedStringArray = []
	var compared: int = 0
	for p: String in ref_map:
		if not got_map.has(p):
			continue
		var a: Node = ref.get_node_or_null(NodePath(p)) if p != "." else ref
		var b: Node = got.get_node_or_null(NodePath(p)) if p != "." else got
		if a == null or b == null:
			continue
		for prop: String in OVERRIDDEN:
			if not (prop in a) or not (prop in b):
				continue
			compared += 1
			var va: Variant = a.get(prop)
			var vb: Variant = b.get(prop)
			# Un @export tipado como Node vale un OBJETO distinto en cada
			# instancia, asi que compararlo con `==` nunca coincide: son dos
			# arboles. Lo que tiene que ser igual es a QUE nodo apunta, o sea su
			# ruta desde la raiz de cada consola. Es el caso de
			# `TabContainer.bind_label`, el unico @export de nodo que sobrevive
			# dentro de la consola.
			if va is Node or vb is Node:
				var pa: String = str(ref.get_path_to(va as Node)) if va is Node else "<null>"
				var pb: String = str(got.get_path_to(vb as Node)) if vb is Node else "<null>"
				if pa != pb:
					diffs.append("%s.%s: referencia=%s nuevo=%s" % [p, prop, pa, pb])
				continue
			if not _same(va, vb):
				diffs.append("%s.%s: referencia=%s nuevo=%s" % [p, prop, va, vb])

	_props_compared += compared
	print("  ..   propiedades sobreescritas comparadas: %d" % compared)
	_check(diffs.is_empty(), "todas las propiedades coinciden%s" % _list(diffs))

	# 4. Y los NodePath internos, que SI viven en el fichero y son los que un
	#    aplanado rompe sin avisar.
	var np_diffs: PackedStringArray = []
	var np_n: int = 0
	for p: String in ref_map:
		if not got_map.has(p):
			continue
		var a: Node = ref.get_node_or_null(NodePath(p)) if p != "." else ref
		var b: Node = got.get_node_or_null(NodePath(p)) if p != "." else got
		if a == null or b == null or a.get_script() == null:
			continue
		for entry: Dictionary in a.get_property_list():
			if int(entry.get("type", 0)) != TYPE_NODE_PATH:
				continue
			var prop: String = str(entry.get("name", ""))
			var va: NodePath = a.get(prop)
			var vb: NodePath = b.get(prop)
			# Los que salen de la consola llegan vacios a proposito.
			if _escapes(p, va):
				continue
			np_n += 1
			if va != vb:
				np_diffs.append("%s.%s: referencia=%s nuevo=%s" % [p, prop, va, vb])

	_paths_compared += np_n
	print("  ..   NodePath internos comparados: %d" % np_n)
	_check(np_diffs.is_empty(), "y todos coinciden%s" % _list(np_diffs))

	got.free()


## Un NodePath sale de la consola si sube mas niveles de los que tiene el nodo.
func _escapes(node_path: String, value: NodePath) -> bool:
	if value.is_empty():
		return true
	var depth: int = 0 if node_path == "." else node_path.split("/").size()
	var ups: int = 0
	for i: int in range(value.get_name_count()):
		if value.get_name(i) == "..":
			ups += 1
		else:
			break
	return ups > depth


func _walk(root: Node, node: Node, out: Dictionary) -> void:
	var p: String = "." if node == root else str(root.get_path_to(node))
	out[p] = node.get_class()
	for child in node.get_children():
		_walk(root, child, out)


func _dup_children(root: Node) -> int:
	var n: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var seen: Dictionary = {}
		for child in node.get_children():
			stack.append(child)
			if seen.has(child.name):
				n += 1
			seen[child.name] = true
	return n


## Comparar con tolerancia donde toca: un Transform3D que pasa por el .tscn como
## texto decimal no vuelve bit a bit, y fallar por el ultimo digito seria ruido.
func _same(a: Variant, b: Variant) -> bool:
	if a is Transform3D and b is Transform3D:
		return (a as Transform3D).is_equal_approx(b as Transform3D)
	if a is Vector2 and b is Vector2:
		return (a as Vector2).is_equal_approx(b as Vector2)
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b as Color)
	if a is float and b is float:
		return is_equal_approx(a as float, b as float)
	return a == b


func _list(items: PackedStringArray) -> String:
	if items.is_empty():
		return ""
	var shown: PackedStringArray = items.slice(0, 8)
	return " - %d: %s%s" % [items.size(), ", ".join(shown),
		"..." if items.size() > 8 else ""]


func _finish() -> void:
	# Que la comparacion se ejecutara de verdad, una vez y no por escena.
	_check(_props_compared > 0,
		"se compararon propiedades sobreescritas (%d en total)" % _props_compared)
	_check(_paths_compared > 0,
		"y NodePath internos (%d en total)" % _paths_compared)
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - la consola diferida es la consola inline original")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
