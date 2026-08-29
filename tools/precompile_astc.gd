extends SceneTree

## Comprime a ASTC fuera del editor, para no pagarlo en la build.
##
## El addon astc_sprite comprime a calidad EXHAUSTIVE, y eso lo paga entera
## cualquier build que se encuentre una textura suya sin salida precompilada:
## la cache de Actions no salva, porque su clave hashea todos los png/tscn/tres/
## gd del proyecto y falla en cualquier commit. Por eso existe
## precompiled_astc_imports/ - y por eso esto existe, para poder rellenarlo sin
## esperar a que una build lo sufra primero.
##
## Lo que hace es lo que hace sprite_importer.gd en su _import(), replicado
## paso por paso, porque un EditorImportPlugin NO se puede instanciar sin
## editor: `.new()` devuelve null en --headless, verificado. Correr Godot con
## --editor si lo permitiria, pero eso arrastra un import del proyecto entero,
## que es la espera de la que va todo esto.
##
## Replicar tiene el riesgo obvio - que las dos versiones se separen - asi que
## la comprobacion no es "confia en que esto esta igual": lo que se escribe se
## valida despues con tools/verify_precompiled_astc.gd, que compara la salida
## contra el PNG que su sidecar dice, dimensiones incluidas. Esa es exactamente
## la comprobacion que hace falta despues de repaquetar un atlas.
##
## Los ajustes NO se inventan aqui: se leen del [params] de cada .import, que
## es la misma fuente que leeria el importador.
##
## Uso:
##   godot --headless --script tools/precompile_astc.gd -- <subcadena de ruta>
##   godot --headless --script tools/precompile_astc.gd -- chimera/gameover

const IMPORTER := "lullaby.astc_sprite"
const TOOL := "res://tools/astc_compress/astc_compress"

## Image.Format por tamano de bloque, igual que en el addon.
const FORMAT_BY_BLOCK := {
	4: Image.FORMAT_ASTC_4x4,
	8: Image.FORMAT_ASTC_8x8,
}

var _done: int = 0
var _skipped: int = 0
var _errors: int = 0


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var needle: String = args[0] if args.size() > 0 else ""
	if needle.is_empty():
		printerr("hace falta una subcadena de ruta, o esto recomprimiria el proyecto entero")
		quit(1)
		return

	if not FileAccess.file_exists(TOOL):
		printerr("falta el compresor en %s - compilalo (ver tools/astc_compress/)" % TOOL)
		quit(1)
		return

	# Sin esto, lo que se guarda son 362 bytes de nada.
	#
	# PortableCompressedTexture2D SUELTA su buffer comprimido en cuanto lo ha
	# subido, salvo que se le diga que no. El editor pone esta bandera al
	# arrancar, asi que el importador del addon nunca se topa con ello; un
	# --headless no la pone, y entonces create_from_image() devuelve una textura
	# con el tamano correcto -por eso enganaba- y ResourceSaver escribe un
	# recurso vacio, porque para cuando le toca ya no queda buffer que escribir.
	#
	# Es la bandera ESTATICA y no la propiedad de la instancia a proposito: la
	# propiedad viajaria dentro del .res y haria que el juego se guardase la
	# copia comprimida en RAM tambien, que es memoria de mas en el dispositivo
	# por una necesidad que solo existe aqui, al guardar.
	PortableCompressedTexture2D.set_keep_all_compressed_buffers(true)

	var started: int = Time.get_ticks_msec()
	for src: String in _sources(needle):
		_compile(src)

	print("\n%d comprimidas, %d saltadas, %d errores, %.1f min" % [
		_done, _skipped, _errors, (Time.get_ticks_msec() - started) / 60000.0])
	quit(1 if _errors > 0 else 0)


## Los PNG bajo `needle` cuyo .import declara el importador del addon. Se filtra
## por el importador y no por la extension: un PNG que caiga en el importador de
## serie no tiene nada que precompilar aqui.
func _sources(needle: String) -> PackedStringArray:
	var out: PackedStringArray = []
	_scan("res://", needle, out)
	out.sort()
	return out


func _scan(dir_path: String, needle: String, out: PackedStringArray) -> void:
	if dir_path.begins_with("res://.godot") or dir_path.begins_with("res://precompiled"):
		return

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan(full, needle, out)
		elif name.ends_with(".png.import") and full.contains(needle):
			if FileAccess.get_file_as_string(full).contains('importer="%s"' % IMPORTER):
				out.append(full.trim_suffix(".import"))
		name = dir.get_next()
	dir.list_dir_end()


func _compile(source: String) -> void:
	var params: Dictionary = _params(source + ".import")
	var block: int = int(params.get("compress/block_size", 8))
	var quality: float = float(params.get("compress/quality", 100.0))
	var want_mipmaps: bool = str(params.get("mipmaps/generate", "false")) == "true"

	if not FORMAT_BY_BLOCK.has(block):
		printerr("  bloque %d no soportado: %s" % [block, source])
		_errors += 1
		return

	# Sin path= declarado, se deriva. Godot construye la salida como
	# <basename>-<md5 de la RUTA res:// del fuente>.res, y esa formula reproduce
	# la ruta declarada en las 505 texturas ASTC del proyecto, 505 de 505 - es la
	# misma que usa tools/harvest_precompiled_imports.py.
	#
	# Hace falta porque repack_atlas.py escribe .import sin [remap] completo: deja
	# que lo rellene el primer import. Los .tres repaquetados apuntan a ESOS PNG,
	# asi que sin esto lo unico que se podria precompilar seria justo lo que el
	# repaquetado acaba de dejar sin usar.
	var dest: String = str(params.get("_dest", ""))
	if dest.is_empty():
		dest = "res://.godot/imported/%s-%s.res" % [source.get_file(), source.md5_text()]

	if FileAccess.file_exists(dest):
		_skipped += 1
		return

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(source)
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		printerr("  no decodifica: %s" % source)
		_errors += 1
		return
	img.convert(Image.FORMAT_RGBA8)

	# PAD, nunca resize: un resize reescala la imagen entera unas milesimas y
	# cada region de un atlas -que va en pixeles exactos- pasa a apuntar un poco
	# fuera. El addon lleva el mismo comentario y la misma cicatriz.
	var w: int = img.get_width()
	var h: int = img.get_height()
	var pw: int = w if w % block == 0 else w + (block - (w % block))
	var ph: int = h if h % block == 0 else h + (block - (h % block))
	if pw != w or ph != h:
		var padded := Image.create_empty(pw, ph, false, img.get_format())
		padded.blit_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
		img = padded

	if want_mipmaps:
		img.generate_mipmaps()
	var mips: int = img.get_mipmap_count() if want_mipmaps else 0

	var raw: PackedByteArray = img.get_data()
	var tmp_dir: String = ProjectSettings.globalize_path("res://.godot/astc_tmp/")
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var tag: String = "%d_%d" % [source.hash(), Time.get_ticks_usec()]
	var tmp_in: String = tmp_dir + tag + ".rgba"
	var tmp_out: String = tmp_dir + tag + ".astc"

	var began: int = Time.get_ticks_msec()
	var compressed := PackedByteArray()
	for i in range(mips + 1):
		var mw: int = maxi(1, pw >> i)
		var mh: int = maxi(1, ph >> i)
		var from: int = img.get_mipmap_offset(i) if i > 0 else 0
		var to: int = img.get_mipmap_offset(i + 1) if i < mips else raw.size()

		var fh := FileAccess.open(tmp_in, FileAccess.WRITE)
		fh.store_buffer(raw.slice(from, to))
		fh.close()

		var output: Array = []
		var code: int = OS.execute(ProjectSettings.globalize_path(TOOL), [
			tmp_in, str(mw), str(mh), str(block), str(block), str(quality), "color", tmp_out,
		], output, true)
		if code != 0:
			printerr("  compresor fallo en mip %d de %s: %s" % [i, source, output])
			_errors += 1
			return

		var of := FileAccess.open(tmp_out, FileAccess.READ)
		compressed.append_array(of.get_buffer(of.get_length()))
		of.close()

	DirAccess.remove_absolute(tmp_in)
	DirAccess.remove_absolute(tmp_out)

	var final_img := Image.new()
	final_img.set_data(pw, ph, want_mipmaps, FORMAT_BY_BLOCK[block], compressed)

	var tex := PortableCompressedTexture2D.new()
	tex.create_from_image(final_img, PortableCompressedTexture2D.COMPRESSION_MODE_ASTC, false, 0.8)

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(dest).get_base_dir())
	var err: int = ResourceSaver.save(tex, dest)
	if err != OK:
		printerr("  no guarda (%d): %s" % [err, dest])
		_errors += 1
		return

	_done += 1
	print("  %4.0fs  %dx%d -> %s" % [
		(Time.get_ticks_msec() - began) / 1000.0, pw, ph, dest.get_file()])


## El [params] del .import, mas `_dest` con el path= del [remap], que es donde
## el importador dejaria la salida y por tanto donde tiene que dejarla esto.
func _params(import_path: String) -> Dictionary:
	var out: Dictionary = {}
	for line: String in FileAccess.get_file_as_string(import_path).split("\n"):
		if line.begins_with("path="):
			out["_dest"] = line.substr(5).strip_edges().trim_prefix('"').trim_suffix('"')
			continue
		if not (line.begins_with("compress/") or line.begins_with("mipmaps/")):
			continue
		var at: int = line.find("=")
		if at <= 0:
			continue
		out[line.substr(0, at)] = line.substr(at + 1).strip_edges()
	return out
