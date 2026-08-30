extends SceneTree

## Ninguna escena escribe una propiedad de script ANTES de su `script =`.
##
## Godot aplica las propiedades de un nodo en el orden en que estan guardadas,
## con una sola rama especial para `script` (scene/resources/packed_scene.cpp).
## No las reordena. Asi que una propiedad exportada por el script, escrita por
## encima de la linea que asigna ese script, se aplica a un nodo que todavia no
## la tiene: `set()` falla, y falla EN SILENCIO. Ni error, ni aviso, ni nada en
## el log. La propiedad se queda con su valor por defecto para siempre.
##
## Comprobado contra este motor con una escena minima:
##
##     [node name="Root" type="Node"]
##     material_select = SubResource("M")     -> queda <null>
##     script = ExtResource("1")
##     material_idle = SubResource("M")       -> queda puesta
##
## Lo que costo, que es lo que justifica la guarda: los iconos 3D del Home de
## la consola se quedaban NEGROS al moverse por el menu. home_button.gd hace
## `icon_mesh.mesh.surface_set_material(0, material_select)` al recibir el
## foco, y surface_set_material escribe en el recurso Mesh, que es COMPARTIDO -
## asi que un material null no deja el icono como estaba, lo deja sin material.
## Su SubViewport tiene own_world_3d sin una sola luz ni WorldEnvironment (a
## proposito: todo lo que se dibuja ahi es unshaded), de modo que el material
## por defecto de Godot, que si se sombrea, sale negro.
##
## Tres botones del Home y las flechas de Creditos tenian su material_select
## escrito antes del script. El de Hacks no, y por eso era el unico que se
## comportaba - una pista que solo tiene sentido una vez sabes esto.
##
## Y no era solo eso: la pantalla de resultados perdia `show_binding` y
## `binding_font_size` de su boton de volver por la misma via, asi que nunca
## enseno su tecla.
##
## Este fallo no se puede ver leyendo la escena ni jugando con atencion: se ve
## comparando el orden de dos lineas. De ahi que se compruebe aqui.
##
## Run with:
##   godot --headless --path . --script tools/test_script_props_after_script.gd

var _failures: int = 0
var _scenes: int = 0
var _nodes: int = 0
var _exports: Dictionary = {}
var _classes: Dictionary = {}


func _initialize() -> void:
	var scenes: PackedStringArray = []
	_collect("res://", scenes)

	for scene: String in scenes:
		_check_scene(scene)

	print("\n%d escenas, %d nodos con script, %d fallos" % [
		_scenes, _nodes, _failures])
	if _failures == 0:
		print("todo OK - ninguna propiedad de script se pierde por el orden")
	quit(1 if _failures > 0 else 0)


func _collect(path: String, out: PackedStringArray) -> void:
	# reference/ es el material del pck original y no se construye.
	if path.begins_with("res://.godot") or path.begins_with("res://reference"):
		return

	var dir := DirAccess.open(path)
	if dir == null:
		return

	for sub: String in dir.get_directories():
		if not sub.begins_with("."):
			_collect(path.path_join(sub), out)

	for file: String in dir.get_files():
		if file.ends_with(".tscn"):
			out.append(path.path_join(file))


func _check_scene(scene: String) -> void:
	var text: String = FileAccess.get_file_as_string(scene)
	if text.is_empty():
		return
	_scenes += 1

	# id del ext_resource -> ruta del script
	var scripts: Dictionary = {}
	for m: RegExMatch in RegEx.create_from_string(
			'\\[ext_resource type="Script"[^\\]]*path="([^"]+)"[^\\]]*id="([^"]+)"\\]'
			).search_all(text):
		scripts[m.get_string(2)] = m.get_string(1)

	if scripts.is_empty():
		return

	# Cada bloque [node ...] hasta el siguiente.
	var heads: Array[RegExMatch] = RegEx.create_from_string(
		'(?m)^\\[node .*?\\]').search_all(text)
	for i: int in heads.size():
		var from: int = heads[i].get_end()
		var to: int = heads[i + 1].get_start() if i + 1 < heads.size() else text.length()
		_check_node(scene, heads[i].get_string(), text.substr(from, to - from), scripts)


func _check_node(scene: String, head: String, body: String, scripts: Dictionary) -> void:
	var lines: PackedStringArray = body.split("\n")
	var script_at: int = -1
	var script_id: String = ""
	for j: int in lines.size():
		if not lines[j].begins_with("script = ExtResource("):
			continue
		var m: RegExMatch = RegEx.create_from_string(
			'ExtResource\\("([^"]+)"\\)').search(lines[j])
		if m != null:
			script_at = j
			script_id = m.get_string(1)
		break

	if script_at < 0 or not scripts.has(script_id):
		return
	_nodes += 1

	var names: Dictionary = _exports_of(scripts[script_id])
	if names.is_empty():
		return

	for j: int in script_at:
		var m: RegExMatch = RegEx.create_from_string(
			'^([A-Za-z_][A-Za-z0-9_]*) = ').search(lines[j])
		if m == null:
			continue
		var prop: String = m.get_string(1)
		if not names.has(prop):
			continue

		_failures += 1
		var name_m: RegExMatch = RegEx.create_from_string('name="([^"]+)"').search(head)
		printerr("  FALLO %s: nodo %s escribe %s ANTES de script= (%s), se pierde" % [
			scene.get_file(),
			name_m.get_string(1) if name_m != null else "?",
			prop, scripts[script_id].get_file()])


## Los nombres que exporta un script, SUBIENDO por la herencia.
##
## La primera version leia solo el fichero en si, y lo dejo escrito como una
## limitacion aceptable: "lo que se pierde son falsos negativos, no falsos
## positivos". El falso negativo llego. `console.tscn` escribia `material_select`
## antes de `script =` en el boton Gallery, esta guarda daba verde sobre 128
## escenas, y el icono se quedaba negro en el telefono - porque
## `gallery_button.gd` hace `extends ConsoleHomeButton` y el export esta
## declarado en la clase padre, no en el.
##
## No hace falta resolver la herencia entera: basta seguir `extends <ClaseGlobal>`
## por el registro de clases del proyecto, que es como se declaran todas las de
## este arbol. Un `extends "res://..."` por ruta tambien vale. Lo que sigue sin
## cubrirse es heredar de un tipo del MOTOR, y ahi no hay export de usuario que
## perder.
func _exports_of(path: String) -> Dictionary:
	if _exports.has(path):
		return _exports[path]

	# Antes de recorrer, para que un ciclo de herencia no cuelgue esto.
	_exports[path] = {}

	var names: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(path)
	for m: RegExMatch in RegEx.create_from_string(
			'(?m)^@export(?:_[a-z_]+)?(?:\\([^)]*\\))?\\s+var\\s+([A-Za-z_][A-Za-z0-9_]*)'
			).search_all(text):
		names[m.get_string(1)] = true

	var base: String = _base_script_of(text)
	if not base.is_empty() and base != path:
		for inherited: String in _exports_of(base):
			names[inherited] = true

	_exports[path] = names
	return names


## La ruta del script del que hereda `text`, o "" si hereda de un tipo del motor.
func _base_script_of(text: String) -> String:
	var m: RegExMatch = RegEx.create_from_string(
		'(?m)^extends\\s+"([^"]+)"').search(text)
	if m != null:
		return m.get_string(1)

	var by_name: RegExMatch = RegEx.create_from_string(
		'(?m)^extends\\s+([A-Za-z_][A-Za-z0-9_]*)').search(text)
	if by_name == null:
		return ""
	return _class_paths().get(by_name.get_string(1), "")


## Nombre de clase global -> fichero, del registro del proyecto.
func _class_paths() -> Dictionary:
	if not _classes.is_empty():
		return _classes
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_classes[String(entry.get("class", ""))] = String(entry.get("path", ""))
	return _classes
