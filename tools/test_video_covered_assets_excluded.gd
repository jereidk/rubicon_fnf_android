extends SceneTree

## NADIE excluye del APK un recurso que una escena empaquetada sigue
## referenciando.
##
## Este guard existia para lo contrario: aprobaba excluir los sprites que tapan
## los videos de Chimera, y su razonamiento era que ningun script los
## desreferencia, asi que la propiedad se quedaria en null y un AnimatedSprite
## tapado con `sprite_frames = null` no dibuja nada. Se construyo la build, y
## Chimera no arranco:
##
##     ERROR Can't load dependency: '.../serena/back_up/spr_back_up_2.png'
##           resource_format_binary.cpp:444 parse_variant
##     ERROR Failed loading resource: .../export-...-sng_chimera.scn
##           resource_loader.cpp:317 _load
##
## El fallo no es una desreferencia desde codigo. Es que **el cargador de
## escenas resuelve cada `ExtResource` al construir la escena**: si uno no esta
## en el .pck, `parse_variant` falla y la escena ENTERA no carga. Nunca se llega
## a tener una propiedad en null que nadie mire. Probar "ningun script lo toca"
## no dice absolutamente nada sobre esto.
##
## Asi que la regla es la de arriba, sin matices: mientras la escena lleve el
## `ExtResource`, el fichero viaja. Excluirlo solo seria seguro quitando tambien
## la referencia de la escena, que es otro trabajo y con otro riesgo.
##
## Lo que si sigue siendo cierto, y queda anotado porque costo medirlo: esos dos
## directorios son 30.15 MB de texturas importadas que el jugador no ve nunca,
## porque los clips que las dibujan caen enteros bajo una ventana de video con
## `disable_3d_while_playing`. El ahorro es real; la via para cogerlo no es el
## `exclude_filter`.
##
## Run with:
##   godot --headless --path . --script tools/test_video_covered_assets_excluded.gd

const CHIMERA := "res://lullaby_mod/songs/chimera/sng_chimera.tscn"
const PRESETS := "res://export_presets.cfg"

const EXCLUDED_DIRS: Array[String] = [
	"lullaby_mod/assets/funkin/chimera/textures/serena/back_up",
	"lullaby_mod/assets/funkin/chimera/textures/serena/intro",
]

## Los nodos que llevan esos recursos, y para cada uno los clips que lo tocan
## FUERA de una ventana de video. Todos tienen que escribirle solo `:visible`.
const LIVE_TOUCHES: Dictionary = {
	"SerenaJumpscared": ["103_stroll", "start"],
	"SerenaTakingPictures": ["117_heartbeat", "jumpscare", "running_away", "start"],
	"SerenaShock": [],
	"SerenaWalkingOut": [],
	"SerenaCamera": [],
}

## Nombres de nodo que ningun script menciona por ruta. Se comprueba todavia,
## pero que quede claro lo que vale: NO es lo que hace segura una exclusion. Eso
## fue justo el error - el cargador de escenas resuelve el ExtResource antes de
## que ningun script llegue a mirar nada.
const NODE_NAMES: Array[String] = [
	"SerenaJumpscared", "SerenaShock", "SerenaTakingPictures", "SerenaWalkingOut",
	"SerenaCine2D", "serenacamera", "CameraFlash", "CameraRise",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_preset_checks()
	_repo_reference_checks()
	_live_touch_checks()
	_still_in_repo_checks()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK - nada que la escena referencia esta excluido del APK")
	quit(1 if _failures > 0 else 0)


## Ningun preset excluye un directorio que sng_chimera.tscn referencia.
func _preset_checks() -> void:
	var cfg: String = _read(PRESETS)
	if not _check(not cfg.is_empty(), "export_presets.cfg se lee"):
		return

	var filters: int = 0
	for line in cfg.split("\n"):
		if not line.begins_with("exclude_filter="):
			continue
		filters += 1
		for dir in EXCLUDED_DIRS:
			_check(not line.contains("%s/*" % dir),
				"preset %d NO excluye %s - la escena lo referencia" % [filters, dir.get_file()])
	_check(filters == 5, "siguen siendo cinco presets (%d)" % filters)


## Nadie fuera de la escena de Chimera nombra esos ficheros, y ningun script los
## carga por ruta.
func _repo_reference_checks() -> void:
	for dir in EXCLUDED_DIRS:
		var files: PackedStringArray = _files_in("res://%s" % dir)
		_check(not files.is_empty(), "%s tiene ficheros (%d)" % [dir.get_file(), files.size()])
		for file in files:
			var referrers: PackedStringArray = _referrers_of(file, dir)
			var bad := PackedStringArray()
			for r in referrers:
				if r != "res://lullaby_mod/songs/chimera/sng_chimera.tscn" and not r.begins_with("res://%s/" % dir):
					bad.append(r)
			_check(bad.is_empty(),
				"%s solo lo referencia la escena de Chimera%s" % [
					file.get_file(), "" if bad.is_empty() else " (tambien %s)" % ", ".join(bad)])

	# Y el mismo corte desde el otro lado: nada de codigo.
	for name in NODE_NAMES:
		var hits: PackedStringArray = _scripts_mentioning(name)
		_check(hits.is_empty(),
			"ningun script nombra %s%s" % [name, "" if hits.is_empty() else " (%s)" % ", ".join(hits)])


## Los clips en vivo solo apagan esos nodos. Quedo del analisis original y se
## mantiene porque sigue siendo el dato que haria falta si algun dia se quita la
## referencia de la escena - pero por si solo NO autoriza a excluir nada.
func _live_touch_checks() -> void:
	var scene: String = _read(CHIMERA)
	var lib: String = _section(scene, '[sub_resource type="AnimationLibrary" id="AnimationLibrary_mao22"]')
	if not _check(not lib.is_empty(), "la biblioteca de secuencias se encuentra"):
		return

	for node: String in LIVE_TOUCHES:
		for clip: String in LIVE_TOUCHES[node]:
			var sid: String = _sub_id_for(lib, clip)
			if not _check(not sid.is_empty(), "%s existe en la biblioteca" % clip):
				continue
			var body: String = _section(scene, '[sub_resource type="Animation" id="%s"]' % sid)
			var writes: PackedStringArray = _track_paths(body, node)
			var only_visible := true
			for path in writes:
				if not path.ends_with(":visible"):
					only_visible = false
			_check(not writes.is_empty() and only_visible,
				"%s solo le escribe :visible a %s (%s)" % [clip, node, ", ".join(writes)])


## Y la otra mitad de la regla de esta casa: excluir NO es borrar.
func _still_in_repo_checks() -> void:
	for dir in EXCLUDED_DIRS:
		_check(DirAccess.dir_exists_absolute("res://%s" % dir),
			"%s sigue en el repo" % dir.get_file())


func _files_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name: String = d.get_next()
	while not name.is_empty():
		var full: String = "%s/%s" % [dir, name]
		if d.current_is_dir():
			out.append_array(_files_in(full))
		elif not name.ends_with(".import"):
			out.append(full)
		name = d.get_next()
	return out


## Quien nombra este fichero, buscando por nombre de fichero en los sitios donde
## una referencia puede vivir.
func _referrers_of(file: String, _dir: String) -> PackedStringArray:
	var needle: String = file.get_file()
	var out := PackedStringArray()
	for candidate in _text_files("res://lullaby_mod"):
		if candidate == file:
			continue
		if _read(candidate).contains(needle):
			out.append(candidate)
	return out


func _scripts_mentioning(name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in _text_files("res://lullaby_mod"):
		if not f.ends_with(".gd"):
			continue
		for line in _read(f).split("\n"):
			var trimmed: String = line.strip_edges()
			# Los comentarios no desreferencian nada. `lullaby_preload_camera.gd`
			# nombra `Sequences/SerenaTakingPictures` cuatro veces explicando por
			# que sus padres van apagados, y eso no es codigo.
			if trimmed.begins_with("#"):
				continue
			if line.contains(name):
				out.append(f.get_file())
				break
	return out


var _cache: PackedStringArray = []

func _text_files(root: String) -> PackedStringArray:
	if not _cache.is_empty():
		return _cache
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var name: String = d.get_next()
		while not name.is_empty():
			var full: String = "%s/%s" % [dir, name]
			if d.current_is_dir():
				stack.append(full)
			elif name.ends_with(".gd") or name.ends_with(".tscn") or name.ends_with(".tres"):
				_cache.append(full)
			name = d.get_next()
	return _cache


func _sub_id_for(lib: String, clip: String) -> String:
	var at: int = lib.find('"%s": SubResource("' % clip)
	if at < 0:
		return ""
	var start: int = lib.find('SubResource("', at) + 13
	var close: int = lib.find('"', start)
	return "" if close < 0 else lib.substr(start, close - start)


## El texto de una seccion `[...]` hasta la siguiente.
func _section(text: String, header: String) -> String:
	var at: int = text.find(header)
	if at < 0:
		return ""
	var start: int = at + header.length()
	var close: int = text.find("\n[", start)
	return text.substr(start, -1 if close < 0 else close - start)


func _track_paths(body: String, node: String) -> PackedStringArray:
	var out := PackedStringArray()
	var at: int = 0
	while true:
		at = body.find('/path = NodePath("', at)
		if at < 0:
			break
		var start: int = at + 18
		var close: int = body.find('"', start)
		if close < 0:
			break
		var path: String = body.substr(start, close - start)
		if path.contains(node):
			out.append(path)
		at = close
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _check(ok: bool, what: String) -> bool:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
	return ok
