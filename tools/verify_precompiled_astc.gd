extends SceneTree

## Checks that every .res in precompiled_astc_imports/ really is the compiled
## form of the source PNG its .md5 sidecar claims.
##
## This matters because of how the workflow uses these files. Godot decides
## whether to skip reimporting by comparing the current source's MD5 against
## source_md5 in the sidecar - so a sidecar written against the current PNG
## makes Godot trust the .res next to it, whatever that .res actually
## contains. Get the pairing wrong and the build silently ships the wrong
## texture, with nothing in the log to say so.
##
## Dimensions are the check that catches the failure that can actually
## happen here: an atlas sheet repacked to a different layout, whose old
## compiled output still carries the old sheet's size.
##
## Run with:
##   godot --headless --path . --script tools/verify_precompiled_astc.gd

const DIR := "res://precompiled_astc_imports"

var _checked: int = 0
var _failures: int = 0
var _skipped: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Indexado por el HASH DE LA RUTA, no por el nombre del fichero.
	#
	# El nombre solo no basta y el proyecto ya tiene el caso: hay dos
	# hypnosis-0.png, uno en res://assets/ y otro que estuvo en
	# res://lullaby_mod/assets/ y ya no esta. Con un indice por nombre, la
	# entrada del que desaparecio encuentra al otro, compara su source_md5
	# contra un PNG que no es el suyo y se reporta como fallo - cuando lo que
	# es, es una entrada huerfana que Godot no va a mirar jamas.
	#
	# La salida del importador se llama <fichero>-<md5 de la RUTA res://>.res,
	# asi que el hash del nombre identifica la ruta EXACTA sin ambiguedad.
	var by_hash: Dictionary = {}
	_index_sources("res://", by_hash)

	var dir := DirAccess.open(DIR)
	if dir == null:
		print("FALLO: no pude abrir %s" % DIR)
		quit(1)
		return

	for file: String in dir.get_files():
		if not file.ends_with(".res"):
			continue
		_check(file, by_hash)

	print("")
	print("comprobados %d, saltados %d, fallos %d" % [_checked, _skipped.size(), _failures])
	for name: String in _skipped:
		print("  saltado (sin fuente en el arbol): %s" % name)
	if _failures == 0:
		print("todo OK - cada .res coincide en tamano con su PNG rellenado")
	quit(0 if _failures == 0 else 1)

## hash de la ruta -> ruta, para cada PNG que posean los importadores ASTC.
func _index_sources(path: String, out: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	for sub: String in dir.get_directories():
		if sub.begins_with("."):
			continue
		_index_sources(path.path_join(sub), out)

	for file: String in dir.get_files():
		if file.ends_with(".png"):
			var full: String = path.path_join(file)
			out[full.md5_text()] = full

func _check(res_file: String, by_hash: Dictionary) -> void:
	var base: String = res_file.substr(0, res_file.length() - 4)
	# "foo.png-<hash>" -> "foo.png" y el hash de la ruta
	var dash: int = base.rfind("-")
	if dash == -1:
		_fail(res_file, "el nombre no tiene la forma fuente.png-hash")
		return

	var png_name: String = base.substr(0, dash)
	var path_hash: String = base.substr(dash + 1)
	if not by_hash.has(path_hash):
		# Ninguna ruta del arbol produce este nombre: la fuente se movio o se
		# borro. Godot nunca va a pedir este .res, asi que sobra, pero no es un
		# fallo: no puede hacer que se envie una textura equivocada.
		_skipped.append("%s (%s ya no esta en el arbol)" % [res_file, png_name])
		return

	var png_path: String = by_hash[path_hash]

	var md5_path: String = DIR.path_join(base + ".md5")
	if not FileAccess.file_exists(md5_path):
		_fail(res_file, "no tiene .md5 al lado")
		return

	# The sidecar has to describe the PNG that is in the tree right now,
	# otherwise Godot reimports and the .res was pointless.
	var sidecar: String = FileAccess.get_file_as_string(md5_path)
	var claimed: String = ""
	for line: String in sidecar.split("\n"):
		if line.begins_with("source_md5="):
			claimed = line.get_slice("\"", 1)
	var actual: String = FileAccess.get_md5(png_path)
	if claimed != actual:
		_fail(res_file, "source_md5 no es el del PNG actual\n          sidecar %s\n          real    %s" % [claimed, actual])
		return

	var image := Image.load_from_file(png_path)
	if image == null:
		_fail(res_file, "no pude leer el PNG %s" % png_path)
		return

	var texture: Resource = ResourceLoader.load(DIR.path_join(res_file))
	if texture == null or not (texture is Texture2D):
		_fail(res_file, "el .res no carga como Texture2D")
		return

	# Contra el tamano RELLENADO, no contra el del PNG.
	#
	# El importador rellena hasta el multiplo del bloque ASTC - nunca reescala,
	# porque reescalar corre las regiones de un atlas unas milesimas y las deja
	# apuntando fuera. Asi que una fuente de 1680x1260 sale legitimamente como
	# 1680x1264 con bloque 8, y exigir igualdad exacta convierte eso en un
	# fallo. El addon dice que 28 texturas del proyecto necesitan relleno; esta
	# comprobacion no podia validar ninguna.
	var block: int = _block_size(png_path)
	var want := Vector2i(
		_pad_to(image.get_width(), block), _pad_to(image.get_height(), block))
	var got := Vector2i(texture.get_width(), texture.get_height())
	_checked += 1
	if got != want:
		_fail(res_file, "tamano %s, el PNG rellenado a bloque %d es %s" % [
			got, block, want])
		return

	print("  ok    %-52s %s" % [png_name, got])

func _pad_to(value: int, block: int) -> int:
	return value if value % block == 0 else value + (block - (value % block))


## El bloque que declara el .import de la fuente. 8 si no lo dice, que es el
## valor por defecto del addon.
func _block_size(png_path: String) -> int:
	for line: String in FileAccess.get_file_as_string(png_path + ".import").split("\n"):
		if line.begins_with("compress/block_size="):
			return int(line.substr(line.find("=") + 1).strip_edges())
	return 8


func _fail(res_file: String, why: String) -> void:
	_failures += 1
	print("  FALLO %s\n          %s" % [res_file, why])
