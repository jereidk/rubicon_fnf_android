extends SceneTree

## `resize/max_size` no puede caer nunca sobre una textura con regiones.
##
## Los dos importadores ASTC de este proyecto RELLENAN en vez de redimensionar,
## y el comentario que lo explica en `sprite_importer.gd` nombra el fallo: las
## regiones de un atlas se escriben en pixeles exactos del original, asi que
## reescalar la textura las deja todas apuntando ligeramente mal. Es lo que
## rompio la intro de espaldas de Gold en Monochrome y afecto en silencio a 28
## texturas, y no da ningun error - sale un sprite descuadrado y nadie sabe por
## que.
##
## La opcion `resize/max_size` reabre esa puerta a proposito, porque es la unica
## palanca que quedaba contra la carga en frio de la tienda: los mismos 460
## recursos cuestan 45.856ms en frio y 5.998ms en caliente, o sea que los
## cuarenta segundos son sacar bytes de la flash, y esas texturas ya estan en
## ASTC 8x8, el bloque mas barato que hay. Bajar de 2048 a 1024 los mapas PBR y
## las base-color de modelo 3D lleva la tienda de 71,5MB a 47,3MB.
##
## Donde es seguro es donde no hay regiones: un modelo 3D va por UV en 0-1 y no
## le importa la resolucion. Donde NO lo es queda fijado aqui, y el caso vivo es
## `coin.png`, que `resources/collector_shop/coin.tres` trocea con
## `region = Rect2(0, 0, 304, 290)` y catorce hermanas.
##
## Run with:
##   godot --headless --path . --script tools/test_resize_never_breaks_atlases.gd

const ROOTS: Array[String] = ["res://lullaby_mod", "res://assets", "res://resources", "res://menus"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var regioned: Dictionary = {}
	var scanned: int = 0
	for root: String in ROOTS:
		scanned += _scan(root, regioned)

	_check(scanned > 0, "se recorrieron ficheros de escena/recurso (%d)" % scanned)
	_check(regioned.size() > 0,
		"y se encontraron texturas troceadas por region (%d)" % regioned.size())

	# El caso vivo, nombrado. Si alguien reorganiza la moneda y esta prueba deja
	# de encontrarla, lo que hay que revisar es el detector, no borrar la linea.
	_check(regioned.has("res://lullaby_mod/assets/collector/shop/coin.png"),
		"coin.png sigue detectandose como atlas troceado")

	var offenders: PackedStringArray = []
	for path: String in regioned:
		if _max_size_of(path) > 0:
			offenders.append(path)

	_check(offenders.is_empty(),
		"ninguna textura con regiones lleva resize/max_size%s"
			% ("" if offenders.is_empty() else ": " + ", ".join(offenders)))

	# Y los mipmaps, que son el mismo fallo por otra puerta.
	#
	# Un nivel de mip promedia texeles vecinos, y en una hoja troceada los
	# vecinos de una region son la region de al lado: al alejarse, un fotograma
	# empieza a mostrar pedazos del siguiente. No da error, se ve como halos y
	# bordes sucios, y es exactamente el mismo desastre silencioso que
	# redimensionar - por eso vive en la misma prueba y no en una aparte.
	var mipped: PackedStringArray = []
	for path: String in regioned:
		if _mipmaps_on(path):
			mipped.append(path)

	_check(mipped.is_empty(),
		"ni mipmaps%s" % ("" if mipped.is_empty() else ": " + ", ".join(mipped)))

	# Y al reves: que la opcion se este usando de verdad en alguna parte. Una
	# prueba que solo comprueba una ausencia pasa en verde el dia que alguien
	# borra la opcion entera.
	var users: int = 0
	for root: String in ROOTS:
		users += _count_users(root)
	_check(users >= 20,
		"y la opcion se usa donde si es segura (%d ficheros)" % users)

	_finish()


## Texturas que algo trocea por region, como claves.
##
## Dos formas de trocear en este proyecto: un AtlasTexture con `region` (lo que
## generan las SpriteFrames) y un `.json` hermano con las regiones en pixeles,
## que es como llegaron las hojas del mod original.
func _scan(dir_path: String, out: Dictionary) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var seen: int = 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				seen += _scan(full, out)
		elif name.ends_with(".tres") or name.ends_with(".tscn"):
			seen += 1
			_collect_atlas_sources(full, out)
		elif name.ends_with(".png") and FileAccess.file_exists(full.get_basename() + ".json"):
			out[full] = true
		name = dir.get_next()
	dir.list_dir_end()
	return seen


## Las rutas ext_resource que un AtlasTexture con `region` usa como `atlas`.
##
## Textual y no cargando el recurso: cargar cada .tres del proyecto para mirar
## un campo cuesta minutos y arrastra los scripts, y lo que hace falta saber -
## que ESTE fichero declara un AtlasTexture con region sobre AQUELLA textura -
## esta escrito literalmente en el texto.
func _collect_atlas_sources(path: String, out: Dictionary) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if not text.contains("AtlasTexture"):
		return

	# id de ext_resource -> ruta
	var by_id: Dictionary = {}
	for line: String in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var p: String = _quoted_after(line, "path=")
		# ` id="` con el espacio delante, no `id="`: la linea lleva antes un
		# `uid="uid://..."` y buscar sin el espacio devolvia el uid como si fuera
		# el id. Con eso el mapa quedaba con las claves cambiadas, ningun
		# AtlasTexture resolvia su textura, y esta prueba pasaba en verde
		# encontrando 76 atlas y perdiendose justo el que la motiva.
		var id: String = _quoted_after(line, " id=")
		if not p.is_empty() and not id.is_empty():
			by_id[id] = p

	# Cada bloque de sub_resource, y si es un AtlasTexture con region, su atlas.
	var blocks: PackedStringArray = text.split("[sub_resource")
	for i: int in range(1, blocks.size()):
		var block: String = blocks[i]
		var head: int = block.find("\n[")
		if head > 0:
			block = block.substr(0, head)
		if not block.contains("AtlasTexture") or not block.contains("region ="):
			continue
		var at: int = block.find("atlas = ExtResource(")
		if at < 0:
			continue
		var id: String = _quoted_after(block.substr(at, 48), "ExtResource(")
		if by_id.has(id):
			out[by_id[id]] = true


func _count_users(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	var n: int = 0
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				n += _count_users(full)
		elif name.ends_with(".import"):
			if FileAccess.get_file_as_string(full).contains("resize/max_size=") \
					and not FileAccess.get_file_as_string(full).contains("resize/max_size=0"):
				n += 1
		name = dir.get_next()
	dir.list_dir_end()
	return n


func _max_size_of(texture_path: String) -> int:
	var import_path: String = texture_path + ".import"
	if not FileAccess.file_exists(import_path):
		return 0
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return 0
	return int(cfg.get_value("params", "resize/max_size", 0))


## Solo cuenta para los importadores ASTC de este proyecto. El importador de
## texturas del motor genera mipmaps para cosas que no son hojas troceadas y no
## es asunto de esta prueba.
func _mipmaps_on(texture_path: String) -> bool:
	var import_path: String = texture_path + ".import"
	if not FileAccess.file_exists(import_path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return false
	if not str(cfg.get_value("remap", "importer", "")).begins_with("lullaby."):
		return false
	return bool(cfg.get_value("params", "mipmaps/generate", false))


## El contenido de las comillas que siguen a `key` en `line`.
func _quoted_after(line: String, key: String) -> String:
	var at: int = line.find(key)
	if at < 0:
		return ""
	var open_quote: int = line.find("\"", at)
	if open_quote < 0:
		return ""
	var close_quote: int = line.find("\"", open_quote + 1)
	if close_quote < 0:
		return ""
	return line.substr(open_quote + 1, close_quote - open_quote - 1)


func _finish() -> void:
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - redimensionar no toca ninguna textura con regiones")
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
