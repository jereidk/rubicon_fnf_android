extends SceneTree

## Los sprites que solo se ven bajo un video se quedan fuera del APK - y siguen
## en el repo.
##
## Chimera dibuja dos de sus cutscenes con video pre-renderizado. Los sprites 3D
## y 2D que esas cutscenes usaban siguen en la escena (hacen falta: el harness de
## render los necesita en vivo para volver a hacer el video, y las secuencias no
## se pueden quitar porque son SubResources del propio .tscn y la pista de clips
## del reloj las despacha por nombre), pero el jugador no los ve nunca. Van al
## `exclude_filter`, no a la papelera.
##
## Dos directorios, 19 MB de fuente:
##
##     serena/back_up   3 png   12.82 MB
##     serena/intro    13 files  6.25 MB
##
## Excluir un recurso que la escena sigue referenciando deja la propiedad en
## `null` al cargar. Eso es inofensivo para un AnimatedSprite que ademas esta
## tapado, y es un crash si alguien lo desreferencia. Por eso lo que se prueba
## aqui no es "sobran", es la CADENA ENTERA que hace que sobrar sea seguro:
##
##   1. Cada fichero de esos dos directorios solo lo referencia
##      `sng_chimera.tscn` (o un .tres hermano del mismo directorio). Ningun
##      script hace load()/preload() de ninguno.
##   2. Ningun script menciona por ruta los nodos que los llevan.
##   3. Los clips que tocan esos nodos fuera de las ventanas de video les
##      escriben `visible = false` y nada mas: ni los encienden, ni les cambian
##      `animation`, ni les leen un frame.
##
## El punto 3 es el que hace la diferencia entre "parece huerfano" y "esta
## probado". `SerenaJumpscared` lo toca `103_stroll`, que es 3D en vivo, y
## `SerenaTakingPictures` lo tocan `117_heartbeat`, `jumpscare` y `running_away`,
## tambien en vivo - leyendo solo la lista de clips esto parecia inseguro. Lo
## unico que le escriben es el apagado.
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

## Nombres de nodo que ningun script puede mencionar por ruta: si uno aparece en
## codigo, alguien puede desreferenciar el recurso ausente.
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
		print("todo OK - lo que tapa el video no viaja en el APK, y sigue en el repo")
	quit(1 if _failures > 0 else 0)


## Los cuatro presets excluyen los dos directorios.
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
			_check(line.contains("%s/*" % dir),
				"preset %d excluye %s" % [filters, dir.get_file()])
	# Cinco: Android Debug, iOS, Android Release, Linux y Windows Desktop. Se
	# cuenta para que añadir un preset nuevo sin la exclusion falle aqui en vez
	# de irse callado a un APK.
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


## Lo que hace segura la exclusion: los clips en vivo solo apagan esos nodos.
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
			"%s sigue en el repo - el harness de render lo necesita en vivo" % dir.get_file())


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
