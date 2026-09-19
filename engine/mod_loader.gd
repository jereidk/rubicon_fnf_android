extends Node
const GDCompileHelper := preload("res://engine/gd_compile.gd")
## Carga mods externos desde multiples raices, para que funcione tanto el
## scoped storage de Android (donde la app escribe sin permisos) como el
## storage compartido (donde el usuario pone mods con un gestor de
## archivos).
##
## Raices escaneadas, en orden de prioridad:
##   user://mods
##     = /storage/emulated/0/Android/data/<pkg>/files/mods
##     La app puede leer y escribir siempre, sin permisos. Es donde la
##     app misma instala mods descargados.
##   /storage/emulated/0/WashosEngine/mods
##     Storage compartido, sin punto inicial (Android 11+ bloquea
##     FileAccess sobre archivos dentro de carpetas ocultas).
##     Requiere MANAGE_EXTERNAL_STORAGE, que el engine pide al arrancar.
##   /storage/emulated/0/.WashosEngine/mods
##     Ruta historica con punto, por compatibilidad. En la mayoria de
##     dispositivos Android 11+ falla por scoped storage sobre carpetas
##     ocultas, pero se intenta igual.
##
## Si un mod con el mismo nombre existe en varias raices, gana el de la
## primera raiz en esta lista.
##
## El estado (activo/inactivo, orden) se guarda en config/mods.json, en
## la raiz primaria. Cada mod tiene un campo root para saber de donde
## vino.

## Escribe al debug log general (DebugLog autoload). Reemplaza al sistema
## viejo que escribia a user://mod_loader_debug.log - inalcanzable desde
## Termux - y a print(), que no se ve en Android release sin logcat.
func _log(msg: String) -> void:
	# get_node_or_null en vez de DebugLog directo: si por alguna razon el
	# autoload no esta (orden mal, error de parseo en debug_log.gd, etc),
	# esto no rompe ModLoader - que es mas importante que el log.
	var dl := get_node_or_null("/root/DebugLog")
	if dl != null:
		dl.log("[ModLoader] " + msg)


const MODS_ROOT_CANDIDATES: Array[String] = [
	"user://mods",
	"/storage/emulated/0/WashosEngine/mods",
	"/storage/emulated/0/.WashosEngine/mods",
]
const ANDROID_STORAGE_PERMISSION := "android.permission.MANAGE_EXTERNAL_STORAGE"
const CACHE_DIR := "user://mods_cache"
const MANIFEST_NAME := "mod.json"
const CONFIG_DIR_NAME := "config"
const CONFIG_FILE_NAME := "mods.json"

signal mods_changed
## Emitido cuando un reload automatico (vuelta del background) encontro
## cambios. La UI lo escucha para refrescar sin que el usuario tenga que
## tocar "Releer".
signal mods_reloaded(changed_folders: Array)

## Cada mod: {name, version, main_scene, enabled, folder, path, root}
var mods: Array[Dictionary] = []
## Raices legibles en este dispositivo, en orden de prioridad.
var mods_roots: Array[String] = []
## Raiz principal (primera legible). Se usa para config/ y para la UI.
var mods_root: String = ""
var _config: Dictionary = {"enabled": {}, "order": []}
var _loaders: Array[ResourceFormatLoader] = []
## Cuando la app vuelve del background marcamos para recargar en el
## proximo frame donde la escena actual sea segura (ModSelector o
## ModManager). No recargamos durante gameplay: cambiar el .pck de un mod
## mientras corre una cancion rompe las referencias cargadas.
var _pending_rescan: bool = false
## Escena actual, para detectar el cambio y solo actuar en pantallas
## seguras.
var _last_scene_path: String = ""
## Nombres de carpeta cuyo mtime cambio desde el ultimo escaneo.
var _changed_on_resume: Array[String] = []
## Mods con el mismo nombre de carpeta en mas de una raiz. Cada entrada:
## {name, roots: [root1, root2, ...], winner: root}.
var duplicates: Array[Dictionary] = []
## Colisiones entre mods habilitados: res://path -> [folder1, folder2].
## Se recalcula en cada scan() y en cada cambio de enabled/order.
var collisions: Dictionary = {}
## Autoloads instalados por mod: name -> folder. Se usa para no pisar
## autoloads del engine ni de otro mod, y para reportar en logs.
var _installed_autoloads: Dictionary = {}

## Referencia fuerte a los nodos instalados, por si el arbol
## los deja sin parent y algo los recolecta. node.name y el
## nodo quedan vivos aca mientras dure ModLoader.
var _installed_autoload_nodes: Dictionary = {}

## True cuando las colisiones cacheadas son viejas. scan() y los cambios
## de enabled/orden lo ponen en true. recompute_collisions_if_dirty() lo
## limpia cuando el ModManager lo pide.
var _collisions_dirty: bool = true

## Paths res:// de cada .gd que trae algun mod activo. El
## runtime_gd_loader.gd lo comparte por referencia y solo
## intercepta estos paths, para no pisar los .gd del APK.
var _mod_gd_paths: Dictionary = {}

## Igual que _mod_gd_paths pero para .tres/.tscn/.scn. Compartido
## por referencia con runtime_resource_loader.gd.
var _mod_resource_paths: Dictionary = {}

## TODOS los paths de todos los mods (incluye assets crudos).
## Los runtime loaders lo consultan para saber si un archivo es
## de un mod y hay que leerlo crudo ignorando su .import hermano.
var _mod_all_paths: Dictionary = {}
var _resource_loader: ResourceFormatLoader = null
var _gd_loader: ResourceFormatLoader = null

## Cache del walk del arbol de un mod: {folder -> {fingerprint, files, time}}.
## needs_bake() y bake_mod() comparten el resultado: sin esto el walk de
## 3070 archivos corria 4 veces por _launch (needs_bake + fingerprint
## interno de bake_mod + _build_pck + _register_mod_gd_paths).
var _scan_cache: Dictionary = {}

## Folder -> true mientras un walk de _scan_mod_tree esta en curso.
## Un segundo caller para el mismo folder espera con await
## process_frame en vez de arrancar otro walk. Sin esto, con HQ
## (18s por walk, SCAN_CACHE_MS de 5s) 4 callers concurrentes
## arrancaban 4 walks solapados = ~50s.
var _scanning: Dictionary = {}
const SCAN_CACHE_MS := 5000

## Autoloads que no pudieron entrar al arbol durante el _ready de
## ModLoader (Window rechaza add_child en esa fase). El flush corre
## una sola vez, en el primer process_frame, y los mete a todos juntos
## para que el orden sea consistente.
var _pending_autoloads: Array[Dictionary] = []
var _pending_flush_connected: bool = false


func _ready() -> void:
	# Conectar primero: OS.request_permission es asincrono (dispara el
	# Intent y sigue), asi que si el permiso esta pendiente hay que
	# re-escanear cuando el usuario responda. Sin esto, el primer scan()
	# corre con el permiso todavia no otorgado y solo ve user://mods.
	if OS.get_name() == "Android":
		var tree := get_tree()
		if tree != null and tree.has_signal("on_request_permissions_result"):
			tree.on_request_permissions_result.connect(_on_android_permission_result)

	_request_android_permissions()

	# Setup sincronico PRIMERO. Tiene que estar listo antes de que
	# ModSelector (main_scene) corra su _ready: Godot marca este nodo
	# como "ready" en cuanto _ready() retorna, y no espera a una
	# coroutine pendiente. Si await _register_runtime_loaders() fuera
	# lo primero, el resto de _ready() (roots, config, scan) correria
	# ~7 frames despues, y ModSelector ya se habria instanciado con
	# ModLoader.mods vacio.
	mods_roots = _resolve_mods_roots()
	mods_root = mods_roots[0] if not mods_roots.is_empty() else MODS_ROOT_CANDIDATES[0]
	if DirAccess.make_dir_recursive_absolute(CACHE_DIR) != OK and not DirAccess.dir_exists_absolute(CACHE_DIR):
		push_warning("[ModLoader] no puedo crear CACHE_DIR %s" % CACHE_DIR)
	_load_config()
	scan()

	# Los loaders async van AL FINAL, sin await. Tardan ~7 frames pero
	# no bloquean nada: para cuando ModSelector llame a bake_mod (que
	# requiere input del usuario), los 9 loaders ya estan listos.
	# Ningun flujo de arranque necesita loaders en los primeros frames.
	_register_runtime_loaders()
	# NO se empaquetan los mods aca. Con HQ (351 MB) el arranque tardaba
	# minutos en el splash. Los mods se empaquetan y montan on-demand desde
	# ModSelector._launch() -> bake_mod(). El arranque queda en ~2s con
	# cualquier cantidad de mods.


## Llamado por el SceneTree cuando el usuario responde al dialogo de
## permisos de Android. Si el que respondio es MANAGE_EXTERNAL_STORAGE y
## la respuesta fue positiva, hay que re-escanear: la primera pasada de
## _ready() corrio con el permiso todavia no otorgado, y por eso las
## raices compartidas (WashosEngine/mods) no se veian.
func _on_android_permission_result(permission: String, granted: bool) -> void:
	if permission != ANDROID_STORAGE_PERMISSION or not granted:
		return
	_log("permiso de storage otorgado, re-escaneando")
	mods_roots = _resolve_mods_roots()
	mods_root = mods_roots[0] if not mods_roots.is_empty() else MODS_ROOT_CANDIDATES[0]
	# Recargar el config del root nuevo. En _ready() se cargo del root
	# viejo (probablemente user://mods, sin permiso). Si no recargamos,
	# _config tiene el estado del root viejo pero save_config() escribe
	# al nuevo, y el estado enabled/order se mezcla.
	_load_config()
	scan()
	# Sin _load_all_enabled: los mods se empaquetan on-demand desde
	# ModSelector. Empaquetar todos aca bloquearia la app varios minutos
	# con un mod grande (HQ son 351 MB).
	mods_changed.emit()


## Pide MANAGE_EXTERNAL_STORAGE en Android. Sin esto, la app no puede
## leer archivos que el usuario dejo en el storage compartido, y cada mod
## aparece con "no define main_scene" aunque el archivo exista.
##
## Best-effort: si el permiso ya esta otorgado, no hace nada. Si no,
## Android abre la pantalla de "Acceso a todos los archivos" del sistema;
## el usuario la acepta o la rechaza, y el ModLoader sigue con las raices
## que si puede leer.
func _request_android_permissions() -> void:
	if OS.get_name() != "Android":
		return
	var granted := OS.get_granted_permissions()
	if ANDROID_STORAGE_PERMISSION in granted:
		_log("permiso de storage ya otorgado")
		return
	_log("pidiendo permiso de storage")
	OS.request_permission(ANDROID_STORAGE_PERMISSION)


func _notification(what: int) -> void:
	# Android y iOS suspenden la app cuando el usuario la deja en segundo
	# plano. Al volver, NOTIFICATION_APPLICATION_RESUMED llega antes que
	# cualquier _process, y es el punto correcto para chequear si el
	# usuario edito algun mod mientras estaba afuera.
	if what == NOTIFICATION_APPLICATION_RESUMED:
		_pending_rescan = true


func _process(_delta: float) -> void:
	# Solo procesamos si hay un rescan pendiente. El costo en idle es una
	# comparacion de bool, invisible.
	if not _pending_rescan:
		return

	var scene := get_tree().current_scene
	if scene == null:
		return
	var path: String = scene.scene_file_path

	# Solo recargamos si estamos en una pantalla de gestion. Si el usuario
	# estaba jugando, dejamos el flag prendido y esperamos a que vuelva.
	if not (path.ends_with("mod_selector.tscn") or path.ends_with("mod_manager.tscn")):
		return

	_pending_rescan = false
	await reload_changed_mods()


## Chequea que mods cambiaron desde el ultimo scan y, si hay alguno,
## re-escanea la carpeta, reconstruye los .pck cambiados y emite
## mods_reloaded con la lista. Llamado automaticamente al volver del
## background en pantallas seguras, o manualmente desde el ModManager.
func reload_changed_mods() -> void:
	var changed: Array[String] = []
	for m in mods:
		var folder: String = m["folder"]
		var scan: Dictionary = await _scan_mod_tree(folder, m["path"])
		var cached := _cached_fingerprint(folder)
		if String(scan["fingerprint"]) != cached:
			changed.append(folder)

	if changed.is_empty():
		return

	_log("reload: %d mods cambiaron (%s)" % [changed.size(), ", ".join(changed)])
	scan()
	# Reconstruir solo los .pck cambiados. load_mod() ya chequea mtime y
	# saltea el empaquetado si nada cambio, asi que llamamos a los de la
	# lista + los que estan enabled.
	for m in mods:
		if m["folder"] in changed and is_enabled(m["folder"]):
			await load_mod(m)
	_changed_on_resume = changed
	mods_changed.emit()
	mods_reloaded.emit(changed)


## Ultimo fingerprint guardado en disco para ese mod, "" si no hay cache.
## Devuelve string porque el fingerprint es "mtime|count" (ver
## _mod_fingerprint); el int viejo no se puede comparar contra el formato
## nuevo y forzaria un rebuild unico en cada arranque.
func _cached_fingerprint(folder: String) -> String:
	var p := CACHE_DIR + "/" + folder + ".mtime"
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()


func _register_runtime_loaders() -> void:
	var scripts := [
		"res://engine/runtime_texture_loader.gd",
		"res://engine/runtime_font_loader.gd",
		"res://engine/runtime_video_loader.gd",
		"res://engine/runtime_ktx_loader.gd",
		"res://engine/runtime_model_loader.gd",
		"res://engine/runtime_shader_loader.gd",
		"res://engine/runtime_audio_loader.gd",
	]
	_gd_loader = load("res://engine/runtime_gd_loader.gd").new()
	_gd_loader.mod_gd_paths = _mod_gd_paths
	_gd_loader.mod_all_paths = _mod_all_paths
	ResourceLoader.add_resource_format_loader(_gd_loader, true)
	_loaders.append(_gd_loader)
	# Ceder el frame: si el limite de "N load() por frame" aplica a estos
	# tambien, saltarlo antes del loop.
	await get_tree().process_frame

	_resource_loader = load("res://engine/runtime_resource_loader.gd").new()
	_resource_loader.mod_resource_paths = _mod_resource_paths
	_resource_loader.mod_all_paths = _mod_all_paths
	ResourceLoader.add_resource_format_loader(_resource_loader, true)
	_loaders.append(_resource_loader)
	await get_tree().process_frame

	# Cargar cada loader en un frame distinto.
	#
	# Los tests mostraron: los primeros 5 load() en un mismo frame
	# funcionan (source_code.length>0), del 6to en adelante devuelven
	# stub con source_code.length=0 aunque el archivo exista. El orden
	# del array no importa: con solo 3 elementos, los 3 funcionan; con
	# 7, los ultimos 2 fallan.
	#
	# Hipotesis: el parser de GDScript o GDScriptCache tiene un limite
	# de scripts que puede compilar en un solo frame durante _ready()
	# de un autoload. Con await process_frame entre cada load, el engine
	# tiene oportunidad de asentar el estado.
	for s in scripts:
		DebugLog.log("[_register_loaders] --- %s ---" % s)
		var script: GDScript = ResourceLoader.load(s, "", ResourceLoader.CACHE_MODE_IGNORE)
		if script == null:
			DebugLog.log("[_register_loaders]   ABORTA: load() devolvio null")
			await get_tree().process_frame
			continue
		DebugLog.log("[_register_loaders]   load() -> base=%s src=%d methods=%d" % [
			script.get_instance_base_type(), script.source_code.length(),
			script.get_script_method_list().size(),
		])
		if not script.can_instantiate():
			DebugLog.log("[_register_loaders]   ABORTA: no compila")
			await get_tree().process_frame
			continue
		var loader = script.new()
		if not (loader is ResourceFormatLoader):
			DebugLog.log("[_register_loaders]   ABORTA: no es ResourceFormatLoader (es %s)" % loader.get_class())
			await get_tree().process_frame
			continue
		loader.mod_all_paths = _mod_all_paths
		ResourceLoader.add_resource_format_loader(loader, true)
		_loaders.append(loader)
		DebugLog.log("[_register_loaders]   OK registrado, _loaders.size=%d" % _loaders.size())
		# Ceder el frame antes del siguiente load.
		await get_tree().process_frame
	_log("%d runtime loaders registrados" % _loaders.size())


## Devuelve todas las raices legibles en este dispositivo, en orden.
##
## Ademas de existir, cada candidata tiene que poder LEER un archivo real
## de adentro. Android 11+ lista carpetas ocultas con DirAccess pero
## bloquea FileAccess sobre su contenido, y sin esta comprobacion el
## ModLoader elegiria una raiz que despues no puede leer.
func _resolve_mods_roots() -> Array[String]:
	var out: Array[String] = []
	for candidate in MODS_ROOT_CANDIDATES:
		# Intentar crear la carpeta es best-effort: si falla porque no
		# existe permiso, igual probamos leer y escribir.
		DirAccess.make_dir_recursive_absolute(candidate)

		if not _can_read_from(candidate):
			_log("raiz NO legible, se omite: %s" % candidate)
			continue
		out.append(candidate)
		_log("raiz legible: %s" % candidate)
	if out.is_empty():
		out.append(MODS_ROOT_CANDIDATES[0])
	return out


## Comprueba lectura real: crea un archivo temporal, lo escribe y lo lee
## de vuelta. Si alguna parte de la cadena falla, la raiz no sirve.
func _can_read_from(dir_path: String) -> bool:
	var probe := dir_path.path_join(".read_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		_log("  no puedo escribir en %s (err=%d)" % [probe, FileAccess.get_open_error()])
		return false
	f.store_string("ok")
	f.close()
	var back := FileAccess.open(probe, FileAccess.READ)
	if back == null:
		_log("  escribi pero no puedo leer %s" % probe)
		DirAccess.remove_absolute(probe)
		return false
	var txt := back.get_as_text()
	back.close()
	DirAccess.remove_absolute(probe)
	return txt == "ok"


## Recalcula que paths de res:// estan definidos por mas de un mod
## habilitado al mismo tiempo. El resultado va a `collisions`, que la UI
## usa para avisar al usuario. No bloquea nada: solo informa.
##
## Es O(total de archivos de los mods habilitados), y corre en cada
## scan() + cada cambio de enabled. En una lista de 10 mods con 500
## archivos cada uno son 5000 lookups de path, ~10 ms. Se podria cachear
## por (folder, mtime) pero no hace falta por ahora.
## Recalcula solo si hace falta. Llamar desde ModManager al mostrar la
## lista. Idempotente.
func recompute_collisions_if_dirty() -> void:
	if not _collisions_dirty:
		return
	await _recompute_collisions()
	_collisions_dirty = false


func _recompute_collisions() -> void:
	collisions.clear()
	var paths: Dictionary = {}  # "res://path" -> [folder]
	for m in mods:
		if not is_enabled(m["folder"]):
			continue
		var scan: Dictionary = await _scan_mod_tree(m["folder"], m["path"])
		var files: Array = scan["files"]
		for rel in files:
			var res_path: String = "res://" + String(rel)
			if not paths.has(res_path):
				paths[res_path] = []
			paths[res_path].append(m["folder"])
	for res_path in paths:
		if paths[res_path].size() > 1:
			collisions[res_path] = paths[res_path]


## Devuelve los paths de res:// que define este mod y que tambien define
## otro. Usado por el ModManager para mostrar "choca con world" en la
## fila de cada mod.
func collisions_for(folder: String) -> Array[String]:
	var out: Array[String] = []
	for res_path in collisions:
		var folders: Array = collisions[res_path]
		if folder in folders:
			out.append(res_path)
	return out


## Desinstala un mod: borra su carpeta, su .pck y su entrada en la
## config. No pide confirmacion: es responsabilidad de la UI preguntar
## antes.
func uninstall_mod(folder: String) -> bool:
	var found: Dictionary = {}
	for m in mods:
		if m["folder"] == folder:
			found = m
			break
	if found.is_empty():
		push_warning("[ModLoader] uninstall: no existe %s" % folder)
		return false

	# Borrar la carpeta recursivamente
	var err := _remove_recursive(found["path"])
	if err != OK:
		push_error("[ModLoader] uninstall: no pude borrar %s (err %d)" % [found["path"], err])
		return false

	# Borrar cache del .pck
	DirAccess.remove_absolute(CACHE_DIR + "/" + folder + ".pck")
	DirAccess.remove_absolute(CACHE_DIR + "/" + folder + ".mtime")

	# Sacar de la config
	var en: Dictionary = _config.get("enabled", {})
	en.erase(folder)
	_config["enabled"] = en
	var order: Array = _config.get("order", [])
	order.erase(folder)
	_config["order"] = order
	save_config()

	# Remover autoloads que hubiera instalado este mod.
	_remove_mod_autoloads(folder)

	# Rescan para que la lista quede actualizada
	scan()
	mods_changed.emit()
	_log("uninstalled: %s" % folder)
	return true


## DirAccess.remove_absolute() solo borra archivos, no directorios con
## contenido. Hay que caminar el arbol y borrar de abajo hacia arriba.
func _remove_recursive(path: String) -> int:
	var dir := DirAccess.open(path)
	if dir == null:
		return DirAccess.remove_absolute(path)

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := path + "/" + name
			if dir.current_is_dir():
				_remove_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		name = dir.get_next()
	dir.list_dir_end()
	return DirAccess.remove_absolute(path)


## DIAGNOSTICO TEMPORAL. Chequea los 3 eslabones de la cadena que el
## analyzer de GDScript usa para resolver el tipo de un autoload:
##   1. ProjectSettings.has_setting("autoload/<name>")
##   2. ResourceLoader.get_resource_type(res_path) == "GDScript"
##   3. GDScriptCache::get_parser(res_path) devuelve un parser valido
##
## El paso 3 no es accesible desde GDScript directo, pero se aproxima con
## un load() que dispara el mismo camino. Si load() devuelve un script
## con source_code.length() > 0, el parser lo pudo leer.
##
## Se saca cuando se identifique el eslabon roto del bug del mod HQ.
func _debug_autoload_chain(name: String, res_path: String, phase: String = "pre-compile") -> void:
	DebugLog.log("[autoload][check %s] %s:" % [phase, name])
	DebugLog.log("  has_setting = %s" % ProjectSettings.has_setting("autoload/" + name))
	DebugLog.log("  get_setting = '%s'" % str(ProjectSettings.get_setting("autoload/" + name, "")))
	DebugLog.log("  mod_gd_paths.has(res_path) = %s" % _mod_gd_paths.has(res_path))
	DebugLog.log("  FileAccess.file_exists(res_path) = %s" % FileAccess.file_exists(res_path))

	# ResourceLoader.get_resource_type() no es estatico en Godot 4.7.
	# Aproximamos con extension + exists, que es lo que el loader va a
	# usar de todas formas.
	var ext: String = res_path.get_extension().to_lower()
	var exists: bool = ResourceLoader.exists(res_path)
	DebugLog.log("  extension = '%s', ResourceLoader.exists = %s" % [ext, exists])

	# Cargar con CACHE_MODE_IGNORE para forzar el parseo real. Si el
	# analyzer puede resolver el tipo, este load tambien deberia.
	var loaded = ResourceLoader.load(res_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null:
		DebugLog.log("  ResourceLoader.load() -> null")
	else:
		var src_len: int = 0
		if loaded is GDScript:
			src_len = loaded.source_code.length()
		DebugLog.log("  ResourceLoader.load() -> %s (source_code len = %d)" % [
			loaded.get_class(), src_len,
		])


## Instala los autoloads que declara el mod en mod.json, campo "autoloads":
##
##   "autoloads": {
##     "HQSaves": "res://holyquintet_mod/scripts/hq_saves.gd",
##     "HQTransition": "res://holyquintet_mod/menus/transition/hq_transition.gd"
##   }
##
## Godot resuelve un autoload en dos pasos:
##   1. GDScript acepta "HQSaves" como identificador global si
##      ProjectSettings tiene la clave "autoload/HQSaves".
##   2. En runtime, el codigo se traduce a get_node("/root/HQSaves"), asi
##      que el nodo tiene que existir.
##
## Los dos pasos se hacen aca. Se llama despues de load_resource_pack()
## y antes de que el ModSelector cargue la escena del mod: como los
## scripts del mod no se parsean hasta que la escena se carga, la
## registracion llega a tiempo.
##
## Si otro mod o el engine ya tiene un autoload con ese nombre, se omite
## con un warning: gana el primero.
func _install_mod_autoloads(m: Dictionary) -> void:
	var autoloads: Dictionary = m.get("autoloads", {})
	DebugLog.log("[autoload] === %s ===" % m.get("folder", "?"))
	if autoloads.is_empty():
		return

	var tree := get_tree()
	if tree == null:
		DebugLog.log("[autoload] get_tree() null, salgo")
		return
	var root := tree.root
	var folder: String = m["folder"]

	for name in autoloads:
		if root.has_node(NodePath(name)):
			DebugLog.log("[autoload] %s ya existe en /root, skip" % name)
			continue
		var path: String = autoloads[name]
		# Con el split de pck, los .gd del mod NO van al pck. Mapear a su
		# path fisico antes de tocar FileAccess. Si no esta en el mapeo,
		# es un archivo del APK y se usa el path tal cual.
		var src_path: String = path
		if _mod_all_paths.has(path):
			src_path = String(_mod_all_paths[path])
		if not FileAccess.file_exists(src_path):
			DebugLog.log("[autoload] SKIP %s: FileAccess dice que no existe (%s)" % [name, src_path])
			continue

		ProjectSettings.set_setting("autoload/" + name, "*" + path)

		# DIAGNOSTICO TEMPORAL del bug 'Cannot infer the type of "unlocked"'
		# en achievements_screen.gd del mod Holy Quintet. Verifica que la
		# cadena has_autoload -> get_resource_type -> get_depended_parser_for
		# esta completa. Se saca cuando se identifique el eslabon roto.
		_debug_autoload_chain(name, path)

		# Compilar con el resource_path res:// (no el fisico) para que
		# GDScriptCache::shallow_gdscript_cache quede poblado con la key
		# correcta. Sin esto, el analyzer de GDScript no puede resolver
		# el tipo de retorno de las funciones del autoload cuando OTRO
		# script del mod hace:
		#   var x := HQSaves.foo()
		# y dispara 'Cannot infer the type of "x"' como error duro.
		#
		# El src_path fisico sirve para leer el archivo (los .gd no
		# estan en el pck, estan en el filesystem del mod). El res_path
		# es para que el engine lo reconozca por su path res://.
		var script: GDScript = GDCompileHelper.from_path_with_res_path(src_path, path)
		if script == null or not script.can_instantiate():
			DebugLog.log("[autoload] SKIP %s: no compila (%s)" % [name, path])
			continue

		# Post-compilacion: volver a chequear las 3 piezas de la cadena.
		# Si aca cambia algo respecto al check previo, el orden importa.
		_debug_autoload_chain(name, path, "post-compile")

		var node = script.new()
		if not (node is Node):
			DebugLog.log("[autoload] SKIP %s: el script no extiende Node" % name)
			continue

		node.name = name
		# Referencia fuerte antes del add_child: si el arbol no cuaja el
		# parent, evita que el nodo se libere por no tener quien lo sostenga.
		_installed_autoload_nodes[name] = node
		root.add_child(node)

		if root.has_node(NodePath(name)):
			# Camino normal: el arbol acepto el add_child en el mismo frame.
			_installed_autoloads[name] = folder
			DebugLog.log("[autoload] instalado %s -> %s" % [name, path])
		else:
			# Window rechaza add_child durante el _ready de un autoload.
			# Encolar para el flush del proximo frame. NO await: la funcion
			# retorna ya, y el caller sabe que la parte sincronica termino.
			_pending_autoloads.append({"name": name, "node": node, "folder": folder})
			_installed_autoloads[name] = folder
			DebugLog.log("[autoload] encolado para flush: %s (%s)" % [name, path])

	_ensure_flush_connected()


## Conecta el flush al primer process_frame, una sola vez por sesion.
## Separado del loop para poder llamarlo desde varios sitios sin duplicar
## la conexion.
func _ensure_flush_connected() -> void:
	if _pending_flush_connected:
		return
	var tree := get_tree()
	if tree == null:
		return
	_pending_flush_connected = true
	tree.process_frame.connect(_flush_pending_autoloads, CONNECT_ONE_SHOT)


## Instala de una sola vez los autoloads que quedaron encolados por el
## rechazo silencioso de Window durante el _ready de ModLoader.
##
## Corre en el primer process_frame del SceneTree, cuando el arbol ya
## acepta add_child. Los nodos ya tienen parent=null pero estan vivos
## por la referencia fuerte en _installed_autoload_nodes.
func _flush_pending_autoloads() -> void:
	if _pending_autoloads.is_empty():
		_pending_flush_connected = false
		return

	var tree := get_tree()
	if tree == null:
		_pending_flush_connected = false
		return
	var root := tree.root

	DebugLog.log("[autoload] flush de %d autoloads encolados" % _pending_autoloads.size())
	for item in _pending_autoloads:
		var node: Node = item["node"]
		var name: String = item["name"]
		if not is_instance_valid(node):
			DebugLog.log("[autoload] %s ya no existe, salteando" % name)
			continue
		if root.has_node(NodePath(name)):
			DebugLog.log("[autoload] %s ya esta en /root, salteando" % name)
			continue
		root.add_child(node)
		DebugLog.log("[autoload] flush OK: %s -> %s has_node=%s" % [
			name, str(node.get_path()), root.has_node(NodePath(name)),
		])
	_pending_autoloads.clear()
	_pending_flush_connected = false


## Remueve los autoloads que instalo un mod. Se llama solo en desinstalar:
## al desactivar, el .pck sigue montado hasta el proximo arranque (Godot
## no expone unload_resource_pack), asi que remover los nodos dejaria el
## mod en un estado inconsistente. En la practica desactivar y desinstalar
## toman efecto completo al reiniciar.
func _remove_mod_autoloads(folder: String) -> void:
	var to_remove: Array = []
	for name in _installed_autoloads:
		if _installed_autoloads[name] == folder:
			to_remove.append(name)

	# Sacar del pending tambien: si el mod se desinstala antes del flush,
	# no queremos que el flush lo instale igual.
	var kept: Array[Dictionary] = []
	for item in _pending_autoloads:
		if item["folder"] == folder:
			DebugLog.log("[autoload] descartado del flush: %s" % item["name"])
		else:
			kept.append(item)
	_pending_autoloads = kept

	var tree := get_tree()
	if tree == null:
		return
	for name in to_remove:
		var node := tree.root.get_node_or_null(NodePath(name))
		if node != null:
			node.queue_free()
		if ProjectSettings.has_setting("autoload/" + name):
			ProjectSettings.clear("autoload/" + name)
		_installed_autoloads.erase(name)
		_installed_autoload_nodes.erase(name)
		_log("autoload removido: %s (mod %s)" % [name, folder])


func _config_path() -> String:
	return mods_root.get_base_dir() + "/" + CONFIG_DIR_NAME + "/" + CONFIG_FILE_NAME


func _load_config() -> void:
	_config = {"enabled": {}, "order": []}
	var p := _config_path()
	if not FileAccess.file_exists(p):
		return
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_warning("[ModLoader] config/mods.json invalido, usando defaults")
		return
	if parsed is Dictionary:
		_config = parsed
	if not (_config.get("enabled") is Dictionary):
		_config["enabled"] = {}
	if not (_config.get("order") is Array):
		_config["order"] = []


func save_config() -> void:
	var p := _config_path()
	if DirAccess.make_dir_recursive_absolute(p.get_base_dir()) != OK and not DirAccess.dir_exists_absolute(p.get_base_dir()):
		push_warning("[ModLoader] no puedo crear dir de %s" % p)
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		push_error("[ModLoader] no puedo escribir %s" % p)
		return
	f.store_string(JSON.stringify(_config, "  "))


func is_enabled(folder: String) -> bool:
	var en: Dictionary = _config.get("enabled", {})
	if en.has(folder):
		return bool(en[folder])
	for m in mods:
		if m["folder"] == folder:
			return bool(m.get("enabled", true))
	return true


func set_enabled(folder: String, enabled: bool) -> void:
	var en: Dictionary = _config.get("enabled", {})
	en[folder] = enabled
	_config["enabled"] = en
	save_config()
	_collisions_dirty = true
	mods_changed.emit()


func toggle_enabled(folder: String) -> void:
	set_enabled(folder, not is_enabled(folder))


func move_mod(folder: String, direction: int) -> void:
	var idx := -1
	for i in mods.size():
		if mods[i]["folder"] == folder:
			idx = i
			break
	if idx < 0:
		return
	var new_idx := clampi(idx + direction, 0, mods.size() - 1)
	if new_idx == idx:
		return
	var m = mods.pop_at(idx)
	mods.insert(new_idx, m)
	var order: Array = []
	for mm in mods:
		order.append(mm["folder"])
	_config["order"] = order
	save_config()
	_collisions_dirty = true
	mods_changed.emit()


## Escanea TODAS las raices legibles y combina los mods encontrados.
##
## Si el mismo folder aparece en varias raices, gana el de la primera
## raiz en `mods_roots` (que respeta el orden de MODS_ROOT_CANDIDATES).
func scan() -> void:
	mods.clear()
	duplicates.clear()
	var seen: Dictionary = {}  # folder -> root del ganador
	var seen_roots: Dictionary = {}  # folder -> [roots donde aparece]
	for root in mods_roots:
		_scan_root(root, seen, seen_roots)
	# Armar duplicados: folders que aparecen en mas de una raiz.
	for folder in seen_roots:
		var roots: Array = seen_roots[folder]
		if roots.size() > 1:
			duplicates.append({
				"name": folder,
				"roots": roots.duplicate(),
				"winner": roots[0],  # gana la primera raiz en mods_roots
			})
	_apply_order()
	# NO recalcular colisiones aca. Es O(archivos de todos los mods
	# habilitados) y solo lo usa el ModManager. Con HQ (3070 archivos)
	# eran 15s en cada arranque. Se marca dirty y se recomputa on-demand.
	_collisions_dirty = true


func _scan_root(root: String, seen: Dictionary, seen_roots: Dictionary) -> void:
	var dir := DirAccess.open(root)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != ".." and dir.current_is_dir():
			# Registrar siempre en seen_roots, para saber si el folder
			# aparece tambien en otra raiz.
			if not seen_roots.has(name):
				seen_roots[name] = []
			seen_roots[name].append(root)
			if not seen.has(name):
				var m := _read_manifest(root + "/" + name)
				if not m.is_empty():
					m["folder"] = name
					m["path"] = root + "/" + name
					m["root"] = root
					mods.append(m)
					seen[name] = true
		name = dir.get_next()
	dir.list_dir_end()


func _read_manifest(path: String) -> Dictionary:
	var mf := path + "/" + MANIFEST_NAME
	if not FileAccess.file_exists(mf):
		var d := {"name": path.get_file()}
		# Autodeteccion: main.gd gana si existe; main.tscn si no.
		if FileAccess.file_exists(path + "/main.gd"):
			d["main_scene"] = "res://main.gd"
		elif FileAccess.file_exists(path + "/main.tscn"):
			d["main_scene"] = "res://main.tscn"
		return d
	var f := FileAccess.open(mf, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


## Resuelve el path fisico del icon del mod. Devuelve "" si no
## encuentra ninguno.
##
## Orden de busqueda:
##   1. mod.json["icon"]                       (explicito, acepta
##                                              "Icon.png" o
##                                              "res://Icon.png")
##   2. <mod>/Icon.png                         (capital, estilo Godot)
##   3. <mod>/icon.png / .ktx / .webp / .svg   (lowercase, estilo web)
##
## Todos los paths se prueban contra el filesystem fisico del mod
## (no res://), asi funciona con mods desactivados (sin pck montado)
## y con la app sin permiso de storage (cuando el mod esta en user://).
func resolve_icon_path(m: Dictionary) -> String:
	var mod_path: String = str(m.get("path", ""))
	if mod_path.is_empty():
		return ""

	# 1. Icon declarado en mod.json.
	var declared: String = str(m.get("icon", ""))
	if not declared.is_empty():
		var rel := declared
		if rel.begins_with("res://"):
			rel = rel.substr(6)
		var abs1 := mod_path.path_join(rel)
		if FileAccess.file_exists(abs1):
			return abs1

	# 2. Icon.png con mayuscula en la raiz.
	var abs2 := mod_path.path_join("Icon.png")
	if FileAccess.file_exists(abs2):
		return abs2

	# 3. icon.* en minuscula.
	for ext in ["png", "ktx", "webp", "svg"]:
		var abs3 := mod_path.path_join("icon." + ext)
		if FileAccess.file_exists(abs3):
			return abs3

	return ""


## Content scale del Window, capturados la PRIMERA vez que un mod pide
## settings. Si nunca se aplican settings, quedan en -1 y
## restore_default_settings() es no-op. Lazy para no depender del orden
## de _ready entre autoloads y la creacion del Window.
var _default_stretch_mode: int = -1
var _default_stretch_aspect: int = -1
## True cuando ya aplicamos settings de un mod y todavia no restauramos.
var _settings_overridden: bool = false

## Whitelist de settings que un mod puede overridear via mod.json.
##
## El schema del mod.json es:
##
##   {
##     "name": "Holy Quintet",
##     "version": "1.0.7",
##     "author": "jereidk",
##     "description": "...",
##     "icon": "Icon.png",           // opcional, ver resolve_icon_path()
##     "main_scene": "res://...",
##     "autoloads": { ... },
##     "settings": {                 // opcional
##       "display/window/stretch/mode": "canvas_items",
##       "display/window/stretch/aspect": "keep"
##     }
##   }
##
## Del lado del runtime, cada clave se mapea a una propiedad del Window
## (get_tree().root). Los valores son strings del export preset de Godot
## ("canvas_items", "keep", etc.), no ints.
##
## Por que whitelist y no ProjectSettings.set_setting() generico: la
## mayoria de los settings de proyecto se leen UNA vez al startup y no
## se re-aplican en runtime. Si los cambiarmos con set_setting(), no
## pasaria nada (el valor se guarda pero nadie lo vuelve a leer). Los
## unicos que valen en runtime son los de content_scale, que tienen
## property en el Window.
const SUPPORTED_SETTINGS: Dictionary = {
	"display/window/stretch/mode": "content_scale_mode",
	"display/window/stretch/aspect": "content_scale_aspect",
}

## Valores validos para stretch/mode. Espejo del enum
## ContentScaleMode de scene/main/window.h:
##   DISABLED=0, CANVAS_ITEMS=1, VIEWPORT=2
const STRETCH_MODE_VALUES: Dictionary = {
	"disabled": 0,
	"canvas_items": 1,
	"viewport": 2,
}

## Valores validos para stretch/aspect. Espejo del enum
## ContentScaleAspect de scene/main/window.h:
##   IGNORE=0, KEEP=1, KEEP_WIDTH=2, KEEP_HEIGHT=3, EXPAND=4
const STRETCH_ASPECT_VALUES: Dictionary = {
	"ignore": 0,
	"keep": 1,
	"keep_width": 2,
	"keep_height": 3,
	"expand": 4,
}


## Aplica los settings que el mod declara en mod.json["settings"].
## Llamar justo antes de change_scene_to_file() / add_child() del mod.
##
## Idempotente y no-op si el mod no tiene "settings" o si ninguna clave
## esta en la whitelist. Captura los defaults del Window la primera vez,
## asi restore_default_settings() los puede devolver tal cual estaban.
func apply_mod_settings(m: Dictionary) -> void:
	var settings: Dictionary = m.get("settings", {})
	if settings.is_empty():
		return
	var root := get_tree().root
	if root == null:
		push_warning("[ModLoader] apply_mod_settings: get_tree().root null")
		return

	# Captura de defaults lazy: solo la primera vez que un mod pide settings.
	# El valor real del Window depende de display/window/stretch/* en
	# project.godot, que puede cambiar entre versiones. Leer al vuelo es
	# mas robusto que hardcodear.
	if _default_stretch_mode == -1:
		_default_stretch_mode = root.content_scale_mode
		_default_stretch_aspect = root.content_scale_aspect

	var folder: String = str(m.get("folder", "?"))
	var applied: int = 0
	for key in settings:
		var raw: Variant = settings[key]
		var raw_str: String = str(raw).to_lower()
		match key:
			"display/window/stretch/mode":
				if STRETCH_MODE_VALUES.has(raw_str):
					root.content_scale_mode = STRETCH_MODE_VALUES[raw_str]
					applied += 1
				else:
					push_warning("[ModLoader] %s: stretch/mode invalido: %s" % [folder, raw])
			"display/window/stretch/aspect":
				if STRETCH_ASPECT_VALUES.has(raw_str):
					root.content_scale_aspect = STRETCH_ASPECT_VALUES[raw_str]
					applied += 1
				else:
					push_warning("[ModLoader] %s: stretch/aspect invalido: %s" % [folder, raw])
			_:
				push_warning("[ModLoader] %s: setting no soportado (whitelist): %s" % [folder, key])

	if applied > 0:
		_settings_overridden = true
		_log("settings aplicados (%s): %s" % [folder, str(settings)])


## Vuelve el Window a los values que tenia antes de aplicar settings de
## algun mod. Llamar al entrar al ModSelector o ModManager.
##
## No-op si nunca se aplicaron settings. Idempotente.
func restore_default_settings() -> void:
	if not _settings_overridden:
		return
	var root := get_tree().root
	if root == null:
		return
	if _default_stretch_mode != -1:
		root.content_scale_mode = _default_stretch_mode
		root.content_scale_aspect = _default_stretch_aspect
	_settings_overridden = false
	_log("settings restaurados a defaults")


## Color de fondo default del selector (el amarillo actual).
## Los mods pueden overridearlo via mod.json["background_color"].
const DEFAULT_BG_COLOR_HEX := "f5d24a"


## Devuelve el color de fondo que el mod declaro en
## mod.json["background_color"], o el default si no hay.
##
## Formatos aceptados: "#RRGGBB", "RRGGBB", "#RRGGBBAA", "RRGGBBAA".
## Color.html() de Godot los parsea todos. Si el string es invalido,
## Color.html() devuelve negro (r=g=b=a=0) y caemos al default con
## un warning.
func resolve_background_color(m: Dictionary) -> Color:
	var raw: String = str(m.get("background_color", "")).strip_edges()
	if raw.is_empty():
		return get_default_bg_color()
	var c := Color.html(raw)
	# Color.html() devuelve Color(0,0,0,1) si el string no parsea.
	# No hay forma de distinguirlo de un "#000000" valido con la API,
	# asi que si el input era distinto a negro y devolvio negro, es
	# invalido. Aceptable: nadie va a poner "#000000" como bg.
	if c == Color(0, 0, 0, 1) and raw.to_lower().lstrip("#") != "000000":
		push_warning("[ModLoader] background_color invalido: %s" % raw)
		return get_default_bg_color()
	return c


func get_default_bg_color() -> Color:
	return Color.html(DEFAULT_BG_COLOR_HEX)


func _apply_order() -> void:
	var explicit: Array = _config.get("order", [])
	# `mods` es Array[Dictionary] y `ordered` tiene que ser del mismo tipo:
	# asignar un Array sin tipo a un Array[Dictionary] es error de runtime
	# en GDScript, y cortaba scan() antes de que devolviera los mods.
	var ordered: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	rest.assign(mods)
	for folder in explicit:
		for m in rest:
			if m["folder"] == folder:
				ordered.append(m)
				rest.erase(m)
				break
	rest.sort_custom(func(a, b): return a["folder"] < b["folder"])
	ordered.append_array(rest)
	mods.clear()
	mods.append_array(ordered)


## Walk unico del arbol de un mod. Devuelve {fingerprint, files, time}.
## - fingerprint: "mtime_max|count", para needs_bake
## - files: paths relativos (los que van al pck y al registro de .gd)
##
## Cacheado por SCAN_CACHE_MS: needs_bake y bake_mod comparten el mismo
## resultado. Sin esto el walk corria 4 veces por cada _launch.
## Extensiones que un runtime loader propio lee del filesystem del mod.
## Todo lo demas (incluye .tscn/.tres/.scn/.res + .xml + .json + .txt +
## .cfg + lo que sea) va al pck, porque sin pck res:// no lo ve y ninguna
## API de lectura directa (XMLParser, JSON, ConfigFile, FileAccess sobre
## res://) funciona.
##
## El criterio es "tiene runtime loader propio?" y NO "que extension es".
## Los .tscn/.tres van al pck aunque tengan loader porque el text loader
## nativo los abre con FileAccess directo y sin pck falla.
const RUNTIME_EXTENSIONS: PackedStringArray = [
	# "gd" NO esta aca a proposito. El parser de GDScript resuelve
	# preload() de otro .gd con FileAccess::open("res://...") directo,
	# sin pasar por ResourceLoader. Sin el .gd en el pck, esa lectura
	# falla y el preload devuelve null:
	#   Parse Error: Could not find script "res://...gen_util.gd".
	#
	# Con .gd en el pck: editar un .gd dispara rebake del pck. Pero el
	# pck es chico (~10 MB en HQ, 200 KB son scripts) asi que el rebake
	# es de ~1.5s, no de 60s.
	"png", "jpg", "jpeg", "webp", "svg",
	"ttf", "otf",
	"ogv",
	"ktx", "astc",
	"glb", "gltf",
	"gdshader",
	"ogg", "mp3", "wav",
]

func _scan_mod_tree(folder: String, mod_path: String, on_progress: Callable = Callable()) -> Dictionary:
	if _scan_cache.has(folder):
		var cached: Dictionary = _scan_cache[folder]
		if Time.get_ticks_msec() - int(cached.get("time", 0)) < SCAN_CACHE_MS:
			DebugLog.log("[scan] %s: cache hit" % folder)
			return cached

	# Si ya hay un walk en curso para este folder, esperar a que termine en
	# vez de arrancar otro. Antes, si 2+ callers consultaban al mismo
	# tiempo y el walk tardaba mas que SCAN_CACHE_MS (5s), cada uno arrancaba
	# su propio walk y con await se solapaban. Con HQ (18s por walk) eran
	# 4 walks = ~50s perdidos.
	while _scanning.has(folder):
		await get_tree().process_frame
		if _scan_cache.has(folder):
			var cached: Dictionary = _scan_cache[folder]
			if Time.get_ticks_msec() - int(cached.get("time", 0)) < SCAN_CACHE_MS:
				return cached

	_scanning[folder] = true
	DebugLog.log("[scan] %s: iniciando walk de %s" % [folder, mod_path])
	var t0: int = Time.get_ticks_msec()

	# Walk iterativo (BFS) con await cada 100 archivos. Antes era recursivo
	# y sincronico, y los 1869 archivos bloqueaban el thread ~10s sin que el
	# overlay se actualizara - el callback se llamaba pero el frame no se
	# redibujaba. Con await la UI muestra el count en vivo.
	var files: Array[String] = []
	var dirs: Array[String] = [""]
	var last_yield: int = 0
	while not dirs.is_empty():
		var sub: String = dirs.pop_front()
		var path: String = mod_path if sub.is_empty() else mod_path + "/" + sub
		var dir := DirAccess.open(path)
		if dir == null:
			continue
		for name in dir.get_files():
			if name.ends_with(".import") or name.ends_with(".uid") or name == MANIFEST_NAME:
				continue
			files.append(name if sub.is_empty() else sub + "/" + name)
			if files.size() - last_yield >= 100:
				last_yield = files.size()
				if on_progress.is_valid():
					on_progress.call(files.size(), 0, "scan")
				await get_tree().process_frame
		for name in dir.get_directories():
			dirs.append(name if sub.is_empty() else sub + "/" + name)

	var t_collect: int = Time.get_ticks_msec()
	DebugLog.log("[scan] %s: %d archivos en %dms" % [folder, files.size(), t_collect - t0])

	# Separar los que van al pck (todo lo que no tiene runtime loader)
	var pack_files: Array[String] = []
	for rel in files:
		if not (rel.get_extension().to_lower() in RUNTIME_EXTENSIONS):
			pack_files.append(rel)

	var total: int = pack_files.size()
	var max_mtime: int = 0
	for i in range(total):
		var rel: String = pack_files[i]
		var mt: int = int(FileAccess.get_modified_time(mod_path + "/" + rel))
		if mt > max_mtime:
			max_mtime = mt
		if on_progress.is_valid() and (i % 20 == 0 or i == total - 1):
			on_progress.call(i + 1, total, "fingerprint")
			await get_tree().process_frame

	var t_fp: int = Time.get_ticks_msec()

	# El fingerprint incluye un hash de RUNTIME_EXTENSIONS. Sin esto, si
	# cambia la constante (por ejemplo, si agregamos/quitamos una
	# extension), el count total puede seguir siendo el mismo y el cache
	# no se invalida - el pck queda viejo y no refleja el cambio.
	# Sintoma real: agregamos "gd" a RUNTIME_EXTENSIONS, despues lo
	# revertimos, y el pck viejo (generado con la version previa de la
	# constante) seguia cacheado y se montaba igual.
	#
	# String.hash() da un int estable para el mismo contenido. Se agrega
	# al fingerprint como string.
	var ext_sig: String = "|".join(RUNTIME_EXTENSIONS)
	var ext_hash: int = abs(ext_sig.hash())
	var fingerprint_str := "%d|%d|%d" % [max_mtime, total, ext_hash]

	DebugLog.log("[scan] %s: fingerprint de %d archivos en %dms | total %dms | fp=%s (ext_hash=%d)" % [
		folder, total, t_fp - t_collect, t_fp - t0,
		fingerprint_str, ext_hash,
	])

	var result := {
		"fingerprint": fingerprint_str,
		"files": files,
		"pack_files": pack_files,
		"time": Time.get_ticks_msec(),
	}
	_scan_cache[folder] = result
	_scanning.erase(folder)
	return result


## Devuelve true si el pck del mod falta o esta desactualizado respecto
## al contenido en disco. Se llama desde ModSelector antes de arrancar un
## mod, para decidir si hay que mostrar la pantalla de carga.
func needs_bake(folder: String, on_progress: Callable = Callable()) -> bool:
	var m: Dictionary = {}
	for mod in mods:
		if mod.get("folder", "") == folder:
			m = mod
			break
	if m.is_empty():
		return false
	var cache_path := CACHE_DIR + "/" + folder + ".pck"
	if not FileAccess.file_exists(cache_path):
		DebugLog.log("[needs_bake] %s: no hay pck cacheado, true" % folder)
		return true
	var scan: Dictionary = await _scan_mod_tree(folder, m["path"], on_progress)
	var cached_fp := _cached_fingerprint(folder)
	var need: bool = String(scan["fingerprint"]) != cached_fp
	DebugLog.log("[needs_bake] %s: need=%s (fp=%s, cache=%s)" % [
		folder, need, scan["fingerprint"], cached_fp,
	])
	return need


## Empaqueta el pck del mod si hace falta, lo monta y registra los paths.
##
## on_progress(done: int, total: int, phase: String) es opcional. Se llama
## desde el main thread cada ~100 archivos durante el empaquetado, para que
## la UI pueda actualizar una barra. phase es "count" (contando archivos
## para el fingerprint) o "pack" (empaquetando).
##
## Cede el frame con await cada tanto para que la UI respire. No corre en
## thread aparte: PCKPacker no es thread-safe.
func bake_mod(m: Dictionary, on_progress: Callable = Callable()) -> bool:
	var folder: String = m["folder"]
	var cache_path := CACHE_DIR + "/" + folder + ".pck"
	var mtime_path := CACHE_DIR + "/" + folder + ".mtime"

	if on_progress.is_valid():
		on_progress.call(0, 1, "count")

	# Un solo walk: fingerprint + files. needs_bake ya lo hizo hace un
	# instante, asi que la cache lo devuelve sin recorrer de nuevo.
	var scan: Dictionary = await _scan_mod_tree(folder, m["path"], on_progress)
	var fingerprint: String = scan["fingerprint"]
	var files: Array = scan["files"]
	var pack_files: Array = scan["pack_files"]

	var cached_fp := ""
	if FileAccess.file_exists(mtime_path):
		cached_fp = FileAccess.open(mtime_path, FileAccess.READ).get_as_text().strip_edges()

	if not FileAccess.file_exists(cache_path) or cached_fp != fingerprint:
		if not await _build_pck(m, pack_files, cache_path, on_progress):
			push_error("[ModLoader] no se pudo empaquetar %s" % folder)
			return false
		FileAccess.open(mtime_path, FileAccess.WRITE).store_string(fingerprint)

	DebugLog.log("[bake_mod] %s: registrando %d paths ANTES del pck" % [
		folder, files.size(),
	])
	_register_mod_gd_paths(files, m["path"])
	DebugLog.log("[bake_mod] %s: paths registrados, montando pck..." % folder)

	var ok := ProjectSettings.load_resource_pack(cache_path, true)
	DebugLog.log("[bake_mod] %s: load_resource_pack=%s" % [folder, ok])
	if not ok:
		push_error("[ModLoader] load_resource_pack fallo para %s" % folder)
		return false

	# Test post-pack: confirmar que un .gd del mod es accesible por res://
	# DESPUES de montar el pck. Esto valida que el pck incluyo los .gd
	# (van al pck porque su extension NO esta en RUNTIME_EXTENSIONS). Si
	# esto falla, el analyzer de GDScript tampoco puede leer el source
	# de los scripts del mod, y dispara errores de inferencia de tipo.
	#
	# Solo hace el test si el mod tiene algun .gd conocido - el path es
	# especifico de Holy Quintet, mods sin ese path simplemente saltean.
	if folder == "holyquintet":
		var test_path := "res://holyquintet_mod/scripts/hq_saves.gd"
		var test_exists := FileAccess.file_exists(test_path)
		var test_len := 0
		if test_exists:
			var tf := FileAccess.open(test_path, FileAccess.READ)
			if tf != null:
				test_len = tf.get_length()
				tf.close()
		DebugLog.log("[bake_mod] CHECK post-pack %s exists=%s len=%d" % [
			test_path, test_exists, test_len,
		])

	_install_mod_autoloads(m)
	_log("bake_mod: %s listo (%d archivos)" % [folder, files.size()])
	return true


## Wrapper de bake_mod sin callback de progreso. bake_mod es coroutine
## (cede el frame cada PROGRESS_EVERY archivos para que la UI respire),
## asi que load_mod tambien lo es: los callers deben hacer await.
##
## Existe por compatibilidad con los callers que ya usaban load_mod
## (_load_all_enabled, reload_changed_mods). El cuerpo real esta en
## bake_mod desde el refactor de bake on-demand.
func load_mod(m: Dictionary) -> bool:
	return await bake_mod(m, Callable())
const PROGRESS_EVERY := 100

func _build_pck(m: Dictionary, files: Array, out: String, on_progress: Callable = Callable()) -> bool:
	var packer := PCKPacker.new()
	if packer.pck_start(out) != OK:
		return false
	var total: int = files.size()
	if on_progress.is_valid():
		on_progress.call(0, total, "pack")
	var i: int = 0
	for rel in files:
		var err := packer.add_file("res://" + rel, m["path"] + "/" + rel)
		if err != OK:
			_log("add_file %s fallo: %d" % [rel, err])
		i += 1
		if i % PROGRESS_EVERY == 0:
			if on_progress.is_valid():
				on_progress.call(i, total, "pack")
			await get_tree().process_frame
	if on_progress.is_valid():
		on_progress.call(total, total, "pack")
	return packer.flush(true) == OK


## Recorre el arbol del mod en disco y registra cada .gd en
## _mod_gd_paths. Compartido con runtime_gd_loader.gd, que solo
## compila a mano los paths registrados aca. Se llama SIEMPRE,
## aunque el pck este en cache, porque el registro no se persiste.
func _register_mod_gd_paths(files: Array, mod_path: String = "") -> void:
	# Limpiar los mapas antes de llenarlos. Sin esto, los paths del mod
	# anterior quedan acumulados y un loader custom puede confundir un
	# archivo nuevo con uno viejo si comparten el path res://. Bug real
	# visto en el log: cargar test_lua (1 path) y despues holyquintet
	# daba "mod_all_paths (size=1872)" cuando HQ tiene 1871 archivos -
	# el path extra era res://main.lua del mod anterior.
	_mod_gd_paths.clear()
	_mod_resource_paths.clear()
	_mod_all_paths.clear()

	var n_gd: int = 0
	var n_res: int = 0
	var n_other: int = 0
	for rel in files:
		var s: String = String(rel)
		var res_path: String = "res://" + s
		var physical: Variant = true
		if not mod_path.is_empty():
			physical = mod_path + "/" + s
		_mod_all_paths[res_path] = physical
		if s.ends_with(".gd"):
			_mod_gd_paths[res_path] = true
			n_gd += 1
		elif s.ends_with(".tres") or s.ends_with(".tscn") or s.ends_with(".scn") or s.ends_with(".res"):
			_mod_resource_paths[res_path] = true
			n_res += 1
		else:
			n_other += 1
	DebugLog.log("[register_paths] mod_path=%s total=%d gd=%d res=%d other=%d" % [
		mod_path, files.size(), n_gd, n_res, n_other,
	])
	# Check especifico de gen_util: si esto es false con el pck ya montado,
	# el preload del .gd va a fallar.
	var test_path := "res://holyquintet_mod/scripts/gen_util.gd"
	DebugLog.log("[register_paths] CHECK %s: in_mod_gd=%s in_mod_all=%s" % [
		test_path, _mod_gd_paths.has(test_path), _mod_all_paths.has(test_path),
	])

	# CRITICO: reasignar el mapa a TODOS los loaders ya registrados.
	#
	# En GDScript, un Dictionary es un tipo POR VALOR en asignacion de
	# property. Cuando hicimos "loader.mod_all_paths = _mod_all_paths" en
	# _register_runtime_loaders, el Dictionary todavia estaba vacio, y
	# Godot copio (shallow) esa copia vacia en la property. Los cambios
	# posteriores a _mod_all_paths en ModLoader NO se reflejan en los
	# loaders.
	#
	# Consecuencia: cuando el text loader pide "res://...gdshader", el
	# shader loader tiene mod_all_paths.has(path)=false, el check de
	# ".import" hermano pasa, y devuelve null. Godot sigue con el loader
	# nativo, que falla porque sin pck res:// no ve el mod.
	#
	# Fix: reasignar la referencia actual DESPUES de llenarla. Los
	# loaders ahora ven el mapa con los 1869 paths.
	for l in _loaders:
		# Sin check de "mod_all_paths" in l: ese operador solo mira
		# metodos, no variables de script. Todos los loaders declaran
		# mod_all_paths, asi que asignacion directa sin preguntar.
		l.mod_all_paths = _mod_all_paths
	DebugLog.log("[register_paths] reasignado mod_all_paths (size=%d) a %d loaders" % [
		_mod_all_paths.size(), _loaders.size(),
	])


## Publico para debug externo.
func get_loaders() -> Array:
	return _loaders
