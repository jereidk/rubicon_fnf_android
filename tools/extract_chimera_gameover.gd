extends SceneTree

## Saca del pck original el gameover de Chimera, que nunca se porto.
##
## El modulo SI esta cableado en la escena de la cancion:
##
##     paths = {
##       &"step_0": "uid://1f1eqjg3yuyi", ... &"step_4": "uid://b34e6rl7fyiwr"
##     }
##
## y ChimeraGameoverModule.switch_to_gameover() hace change_scene_to_file() con
## una de esas cinco. Ninguna de las cinco existe en el port: los UID no
## resuelven contra nada, asi que morir en Chimera no llevaba a ningun sitio.
## En el original son res://songs/chimera/scenes/step_0..4.tscn, y con ellas
## viene todo un arbol de assets que tampoco se porto - ni las imagenes, ni los
## sfx, ni el video de step_4.
##
## Esto no reconstruye nada a mano. Carga del pck y vuelve a guardar, que es lo
## unico que garantiza que las animaciones, los tiempos y las propiedades salgan
## como estaban en vez de como uno se acuerda de que estaban.
##
## Que hace con cada tipo, y por que:
##
##   texturas    el pck las trae ya importadas, asi que se decodifican y se
##               guardan como PNG. Es sin perdida respecto a lo que el juego de
##               PC mostraba - que no es lo mismo que respecto al PNG del
##               artista, porque el original las importo con compresion con
##               perdida y eso ya no se puede deshacer desde aqui. El PNG pesa
##               mas que el .jpg de origen y da igual: lo que acaba en el
##               dispositivo lo decide el importador del port, no el fichero
##               fuente, y el tamano del repositorio no tiene cuota.
##
##   ogg         no hay forma de reconstruir el contenedor Ogg desde el
##               OggPacketSequence que guarda el importado, asi que se guarda el
##               propio AudioStreamOggVorbis como .res. Suena igual y se salta
##               la reimportacion; un AudioStreamPlayer acepta cualquier
##               AudioStream, venga de un importador o no.
##
##   mp3         AudioStreamMP3 si expone los bytes originales en `data`, asi
##               que ese sale como .mp3 de verdad.
##
##   ogv         Godot no importa video: en el pck esta tal cual, se copia byte
##               a byte.
##
##   .tres/.res  SpriteFrames y AnimationLibrary se vuelven a guardar como texto.
##
## Y despues reescribe las rutas. El pck tiene la raiz del mod en res://; el
## port lo re-aloja bajo res://lullaby_mod/. Los uid= de los ext_resource se
## quitan en vez de traducirse, porque un uid del pck no resuelve aqui y Godot
## responde a eso con un aviso por linea y cayendo a la ruta de texto - que es
## justo lo que ya ensucia el arranque de este proyecto. Sin uid, resuelve por
## ruta en silencio y se los vuelve a poner el siguiente import.
##
## El uid de la ESCENA si se fija a mano, y ahi no hay eleccion: es el que el
## modulo tiene escrito en `paths`. Si no coincide, esto no arregla nada.
##
## Uso:
##   godot --headless --script tools/extract_chimera_gameover.gd
##   godot --headless --script tools/extract_chimera_gameover.gd -- --dry-run

const PCK := "res://lullaby_mod/original_pck/Lullaby.pck"

## Lo que el modulo espera encontrar, copiado de sng_chimera.tscn. Que esten
## aqui a mano es a proposito: si alguien reordena esa tabla, esto tiene que
## dejar de coincidir de forma ruidosa en vez de generar cinco escenas con uid
## nuevos que no apunta nadie.
const SCENE_UIDS := {
	0: "uid://1f1eqjg3yuyi",
	1: "uid://c2881f3gscpwo",
	2: "uid://3mvedi7vvpie",
	3: "uid://be5fvajhp7xny",
	4: "uid://b34e6rl7fyiwr",
}

var _dry: bool = false
var _seen: Dictionary = {}

## Ruta de origen -> que importador le toca, rellenado segun se van escribiendo
## los ficheros. Se lleva aparte porque el .import solo se puede escribir cuando
## ya se sabe el nombre definitivo del fuente: un .jpg del pck acaba siendo .png
## aqui, y el md5 que va en la ruta del importado es el de ESA ruta.
var _imports_wanted: Dictionary = {}

## Todo fichero de texto que este tool escribe, para la pasada final de rutas.
## Va aparte de la escritura porque un .tres solo se puede reescribir cuando ya
## esta en disco, y porque haciendolo en UN solo sitio no hay forma de que una
## clase de fichero se quede sin traducir - que es como se colo la primera vez.
var _text_written: PackedStringArray = []
var _written: int = 0
var _bytes: int = 0
var _errors: int = 0


func _init() -> void:
	_dry = OS.get_cmdline_user_args().has("--dry-run")

	if not ProjectSettings.load_resource_pack(PCK, false):
		printerr("no se pudo montar %s" % PCK)
		quit(1)
		return

	for step: int in SCENE_UIDS:
		_walk("res://songs/chimera/scenes/step_%d.tscn" % step)

	# Las escenas van al final, cuando todo lo que cuelga de ellas ya existe en
	# el arbol del port - si no, se guardan apuntando a ficheros que no estan.
	for step: int in SCENE_UIDS:
		_save_scene(step)

	_sweep_paths()
	_write_imports()

	print("\n%d ficheros, %.1f MB, %d errores%s" % [
		_written, _bytes / 1048576.0, _errors, "  (DRY RUN)" if _dry else ""])
	quit(1 if _errors > 0 else 0)


## La ruta equivalente en el port. El pck tiene addons/ donde el port lo tiene,
## asi que ese prefijo se deja en paz; todo lo demas baja un nivel.
func _port_path(pck_path: String) -> String:
	if pck_path.begins_with("res://addons/") or pck_path.begins_with("res://lullaby_mod/"):
		return pck_path
	return pck_path.replace("res://", "res://lullaby_mod/")


## Y la extension que le toca al fichero que se va a escribir de verdad. Un
## .jpg del original sale como .png porque lo que se guarda es la imagen
## decodificada; un .ogg sale como .res porque lo que se guarda es el recurso.
func _dest_path(pck_path: String, kind: String) -> String:
	var out: String = _port_path(pck_path)
	match kind:
		"texture":
			return out.get_basename() + ".png"
		"ogg":
			return out.get_basename() + ".res"
		"tres":
			# Forzado a texto aunque el original fuese .res binario.
			#
			# skullface.res es un SpriteFrames, y un SpriteFrames apunta a sus
			# hojas por ruta. Guardado en binario esas rutas quedan dentro y no
			# hay forma de traducirlas del res:// del pck al res://lullaby_mod/
			# de aqui - que es exactamente el fallo que tuvo la primera version
			# de esto: las escenas quedaron bien y los .tres siguieron apuntando
			# a ficheros que no existen.
			return out.get_basename() + ".tres"
		_:
			return out


func _walk(pck_path: String) -> void:
	if _seen.has(pck_path):
		return
	_seen[pck_path] = true

	# Lo que el port ya tiene se deja: el script del gameover, los addons, y
	# cualquier cosa que el pck y el port compartan ruta.
	if pck_path.begins_with("res://lullaby_mod/") or pck_path.begins_with("res://addons/"):
		return

	for dep: String in ResourceLoader.get_dependencies(pck_path):
		var parts: PackedStringArray = dep.split("::")
		_walk(parts[parts.size() - 1])

	# Las escenas se guardan en la segunda pasada.
	if pck_path.ends_with(".tscn"):
		return

	_extract(pck_path)


func _extract(pck_path: String) -> void:
	# El .ogv no es un recurso importado: esta crudo en el pck.
	if pck_path.get_extension().to_lower() == "ogv":
		_copy_raw(pck_path)
		return

	var res: Resource = ResourceLoader.load(pck_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		printerr("  no carga: %s" % pck_path)
		_errors += 1
		return

	# Si Godot resolvio esto contra un fichero del port, el port YA lo tiene y
	# aqui no hay nada que traer.
	#
	# Sin esta linea, este extractor VACIO chimera_gameover.gd. El pck lista la
	# dependencia como res://scripts/... -que no empieza por lullaby_mod/, asi
	# que el filtro de _walk() no la para- pero su uid resuelve contra el fichero
	# del port, y lo que se cargo fue el .gdc COMPILADO del pck. Un GDScript
	# compilado no lleva source_code, asi que volver a guardarlo escribio veinte
	# lineas de nada encima del original. Se noto porque git lo dijo; en un arbol
	# sucio no se habria notado.
	#
	# El sintoma general que cubre: cualquier dependencia que el port comparta
	# con el original saldria del pck y pisaria la version portada, que es
	# justamente la que lleva los arreglos.
	if res.resource_path != pck_path:
		return

	# Y los scripts no se portan nunca por esta via, resuelvan donde resuelvan.
	if res is Script:
		return

	if res is Texture2D:
		_save_texture(pck_path, res)
	elif res is AudioStreamMP3:
		var mp3_dest: String = _dest_path(pck_path, "mp3")
		_save_bytes(mp3_dest, (res as AudioStreamMP3).data)
		_imports_wanted[mp3_dest] = "mp3"
	elif res is AudioStream:
		_save_resource(_dest_path(pck_path, "ogg"), res)
	else:
		var dest: String = _dest_path(pck_path, "tres")
		_save_resource(dest, res)
		_text_written.append(dest)


func _save_texture(pck_path: String, tex: Texture2D) -> void:
	var img: Image = tex.get_image()
	if img == null:
		printerr("  sin imagen: %s" % pck_path)
		_errors += 1
		return

	var dest: String = _dest_path(pck_path, "texture")
	if _dry:
		_note(dest, img.get_width() * img.get_height() * 4)
		return

	_mkdir(dest)
	var err: int = img.save_png(ProjectSettings.globalize_path(dest))
	if err != OK:
		printerr("  save_png fallo (%d): %s" % [err, dest])
		_errors += 1
		return
	_imports_wanted[dest] = "astc"
	_note(dest, _size_of(dest))


func _save_resource(dest: String, res: Resource) -> void:
	if _dry:
		_note(dest, 0)
		return

	_mkdir(dest)
	# Sin la ruta puesta, ResourceSaver escribe las sub-referencias contra la
	# ruta del pck y la escena que las use apunta fuera del port.
	res.take_over_path(dest)
	var err: int = ResourceSaver.save(res, dest)
	if err != OK:
		printerr("  save fallo (%d): %s" % [err, dest])
		_errors += 1
		return
	_note(dest, _size_of(dest))


func _copy_raw(pck_path: String) -> void:
	var dest: String = _port_path(pck_path)
	var src := FileAccess.open(pck_path, FileAccess.READ)
	if src == null:
		printerr("  no se abre: %s" % pck_path)
		_errors += 1
		return
	var data: PackedByteArray = src.get_buffer(src.get_length())
	src.close()
	_save_bytes(dest, data)


func _save_bytes(dest: String, data: PackedByteArray) -> void:
	if _dry:
		_note(dest, data.size())
		return

	_mkdir(dest)
	var fh := FileAccess.open(dest, FileAccess.WRITE)
	if fh == null:
		printerr("  no se escribe: %s" % dest)
		_errors += 1
		return
	fh.store_buffer(data)
	fh.close()
	_note(dest, data.size())


## La escena, con las rutas del pck traducidas a las del port.
##
## Se guarda primero tal cual y se reescribe el texto despues, en vez de
## reasignar resource_path en cada dependencia antes de guardar. Las dos cosas
## valen; esta deja un diff que se puede leer.
func _save_scene(step: int) -> void:
	var pck_path: String = "res://songs/chimera/scenes/step_%d.tscn" % step
	var dest: String = _port_path(pck_path)

	var scene: PackedScene = ResourceLoader.load(pck_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if scene == null:
		printerr("  no carga la escena: %s" % pck_path)
		_errors += 1
		return

	if _dry:
		_note(dest, 0)
		return

	_mkdir(dest)
	var err: int = ResourceSaver.save(scene, dest)
	if err != OK:
		printerr("  save escena fallo (%d): %s" % [err, dest])
		_errors += 1
		return

	_text_written.append(dest)

	var text: String = FileAccess.get_file_as_string(dest)
	text = _rewrite(text, step)

	var fh := FileAccess.open(dest, FileAccess.WRITE)
	fh.store_string(text)
	fh.close()
	_note(dest, _size_of(dest))


## Traduce las rutas de TODOS los ficheros de texto escritos, escenas incluidas.
##
## Una sola pasada, al final, sobre todo lo que se ha escrito. La primera
## version traducia solo las .tscn y dejaba los .tres con las rutas del pck
## dentro: las escenas cargaban, los SpriteFrames tambien, y las hojas no
## estaban. Eso no da error al arrancar - da un gameover sin dibujo.
func _sweep_paths() -> void:
	for path: String in _text_written:
		var text: String = FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue

		var out: PackedStringArray = []
		for line: String in text.split("\n"):
			if line.begins_with("[ext_resource"):
				line = RegEx.create_from_string('\\s*uid="[^"]*"').sub(line, "")
				line = _rewrite_path(line)
			out.append(line)

		var fh := FileAccess.open(path, FileAccess.WRITE)
		if fh == null:
			printerr("  no se reescribe: %s" % path)
			_errors += 1
			continue
		fh.store_string("\n".join(out))
		fh.close()


func _rewrite(text: String, step: int) -> String:
	var out: PackedStringArray = []
	for line: String in text.split("\n"):
		if line.begins_with("[gd_scene"):
			# El uid que el modulo tiene escrito, no el que acabe de salir.
			line = RegEx.create_from_string('uid="[^"]*"').sub(
				line, 'uid="%s"' % SCENE_UIDS[step])
			if not line.contains("uid="):
				line = line.replace("[gd_scene ",
					'[gd_scene uid="%s" ' % SCENE_UIDS[step])
		elif line.begins_with("[ext_resource"):
			# Un uid del pck no resuelve aqui, y Godot responde con un aviso por
			# linea cayendo a la ruta. Fuera; el siguiente import los repone.
			line = RegEx.create_from_string('\\s*uid="[^"]*"').sub(line, "")
			line = _rewrite_path(line)
		out.append(line)
	return "\n".join(out)


func _rewrite_path(line: String) -> String:
	var m: RegExMatch = RegEx.create_from_string('path="([^"]+)"').search(line)
	if m == null:
		return line

	var pck_path: String = m.get_string(1)

	# Idempotente, porque la pasada final vuelve a ver las escenas que ya se
	# tradujeron al guardarlas. Sin esta linea la segunda vuelta leia el .res de
	# un audio ya traducido, le aplicaba la regla .res -> .tres pensada para
	# skullface, y las cinco escenas acababan pidiendo un sfx_step_N.tres que no
	# existe. Lo pillo la guarda; a ojo no se ve.
	if pck_path.begins_with("res://lullaby_mod/"):
		return line

	var kind: String = "res"
	match pck_path.get_extension().to_lower():
		"jpg", "jpeg", "png":
			kind = "texture"
		"ogg":
			kind = "ogg"
		"mp3":
			kind = "mp3"
		"ogv":
			kind = "ogv"
		"tres", "res":
			# En una ruta DEL PCK, un .res solo puede ser skullface.res, que
			# aqui sale como texto. Las .res que escribe este tool son los
			# audios, y esas nunca aparecen dentro de un fichero del pck.
			kind = "tres"
	var dest: String = _port_path(pck_path) if kind in ["mp3", "ogv"] \
		else _dest_path(pck_path, kind)
	return line.replace('path="%s"' % pck_path, 'path="%s"' % dest)


## Los .import de lo que si pasa por un importador.
##
## Hay que escribirlos a mano, y el motivo esta en el propio addon:
## sprite_importer.gd devuelve _get_priority() = 0.0, por debajo del importador
## de texturas de serie, asi que un PNG nuevo NO cae en el ASTC por si solo. Se
## elige por fichero, aqui, o estas once hojas de 4096x4096 entran por la ruta
## por defecto sin que nadie se entere.
##
## Los ajustes son los que ya usa el resto del port (block 8, calidad 100), y
## mipmaps a false porque estas se dibujan a pantalla completa: un mip nunca se
## llega a muestrear y cuesta un tercio mas de memoria y de compresion.
##
## La ruta del importado es determinista - .godot/imported/<fichero>-<md5 de la
## RUTA de origen>.<ext> - comprobado contra los .import que ya estaban en el
## arbol, asi que se puede escribir sin haber importado todavia.
##
## Ojo con lo que esto cuesta la primera vez: la calidad 100 del addon es
## EXHAUSTIVE y aqui entran doce texturas de 16.8 Mpx. Esa compilacion se paga
## una vez, porque el propio CI cosecha la salida a precompiled_astc_imports/ y
## se la commitea a la rama; a partir de ahi ninguna build vuelve a comprimir.
##
## Los .res, .tres y el .ogv no llevan .import: no pasan por ningun importador.
func _write_imports() -> void:
	for src: String in _imports_wanted:
		var kind: String = _imports_wanted[src]
		var stamp: String = "%s-%s" % [src.get_file(), src.md5_text()]
		var dest_ext: String = "res" if kind == "astc" else "mp3str"
		var imported: String = "res://.godot/imported/%s.%s" % [stamp, dest_ext]

		var params: String = ""
		var importer: String = ""
		var type: String = ""
		if kind == "astc":
			importer = "lullaby.astc_sprite"
			type = "Texture2D"
			params = "compress/block_size=8\ncompress/quality=100.0\nmipmaps/generate=false\n"
		else:
			importer = "mp3"
			type = "AudioStreamMP3"
			params = "loop=false\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n"

		var text: String = "[remap]\n\nimporter=\"%s\"\ntype=\"%s\"\nuid=\"%s\"\npath=\"%s\"\n\n[deps]\n\nsource_file=\"%s\"\ndest_files=[\"%s\"]\n\n[params]\n\n%s" % [
			importer, type, ResourceUID.id_to_text(ResourceUID.create_id()),
			imported, src, imported, params,
		]

		if _dry:
			_note(src + ".import", text.length())
			continue

		var fh := FileAccess.open(src + ".import", FileAccess.WRITE)
		if fh == null:
			printerr("  no se escribe: %s.import" % src)
			_errors += 1
			continue
		fh.store_string(text)
		fh.close()
		_note(src + ".import", text.length())


## Sobre la ruta del sistema, no sobre res://.
##
## Con un pck montado, el DirAccess de res:// pasa a ser el del paquete y es de
## SOLO LECTURA, asi que make_dir_recursive_absolute("res://...") no crea nada
## y no dice por que: lo unico que se ve despues es un save_png devolviendo
## ERR_FILE_NOT_FOUND sobre una carpeta que nunca existio. Los ficheros cuya
## carpeta ya estaba en el arbol se guardaban bien, que es lo que hacia el
## sintoma parcial y confuso.
func _mkdir(dest: String) -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(dest).get_base_dir())


func _size_of(path: String) -> int:
	var fh := FileAccess.open(path, FileAccess.READ)
	if fh == null:
		return 0
	var n: int = fh.get_length()
	fh.close()
	return n


func _note(dest: String, size: int) -> void:
	_written += 1
	_bytes += size
	print("  %8.2f MB  %s" % [size / 1048576.0, dest])
