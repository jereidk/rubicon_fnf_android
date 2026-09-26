extends ResourceFormatLoader

## Compila .gd desde mods montados en pck.
##
## El ResourceFormatLoaderGDScript nativo devuelve un GDScript hueco
## (base RefCounted, sin metodos) cuando el .gd vive dentro de un pck
## montado con load_resource_pack(). El sintoma es "Script is invalid"
## o "Script inherits from native type 'RefCounted'" al asignarlo a
## un nodo, y "Identifier not found" para los identificadores que el
## script hueco no declara.
##
## Este loader se registra at_front=true, antes que el nativo. Solo
## intercepta paths que ModLoader registro como provenientes de un mod
## activo. Para todo lo demas devuelve null y Godot delega al nativo.
##
## El registro mod_gd_paths es un Dictionary compartido con ModLoader.
## En GDScript los Dictionary se pasan por referencia, asi que mutarlo
## desde ModLoader se ve aca sin sincronizacion.

## Paths .gd que vienen de algun mod activo. Lo llena ModLoader en
## _register_mod_gd_paths, uno por cada archivo .gd dentro de cada mod.
## Compartido por referencia - no copiar.
var mod_gd_paths: Dictionary = {}

## Igual que mod_gd_paths pero con el path fisico como valor.
## Con el split de pck, los .gd NO van al pck: se leen directo
## del filesystem del mod. Este mapeo dice a donde apuntar.
var mod_all_paths: Dictionary = {}


## Cache propio: path -> GDScript ya compilado. Godot cachea los
## recursos con resource_path via ResourceLoader, pero como devolvemos
## un GDScript.new() custom, el cache nativo puede no retenerlo. Con
## este mapa, la segunda llamada al mismo path no recompila.
##
## Es ademas lo que le permite al parser de GDScript resolver tipos:
## cuando compila OTRO script del mod que hace `HQSaves.foo()`, busca
## hq_saves.gd con GDScriptCache::get_cached_script(). Si no lo
## encuentra, no puede resolver el tipo de retorno de foo() y asume
## Variant -> error 'Cannot infer the type of "x" variable' en
## cualquier `var x := HQSaves.foo()`.
##
## La clave para poblar ese cache nativo es gd.take_over_path(path)
## ANTES de gd.reload(). El reload, al ver resource_path seteado,
## registra el script en GDScriptCache::shallow_gdscript_cache
## (verificado en modules/gdscript/gdscript.cpp:781-783).
var _cache: Dictionary = {}

## Mutex que protege _cache. Con threaded load, varios worker threads
## pueden pedir el mismo .gd al mismo tiempo; sin lock, la escritura
## al Dictionary corrompe el hashmap interno de Godot.
var _cache_mutex := Mutex.new()


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["gd"])


func _get_resource_type(path: String) -> String:
	if path.begins_with("res://addons/"):
		DebugLog.log("[gd_loader._get_resource_type] %s -> %s" % [path, mod_gd_paths.has(path)])
	if mod_gd_paths.has(path):
		return "GDScript"
	return ""


func _handles_type(type: StringName) -> bool:
	return type == &"GDScript" or type == &"Script"


## Override explicito de recognize_path. Necesario porque Godot llama a
## recognize_path() con el type_hint que el analyzer le pasa al preload()
## - y para un preload("res://helper.gd") en un script analizado como
## posible PackedScene, el hint llega como "PackedScene".
##
## En ese caso el filtro por defecto de ResourceFormatLoader llama a
## get_recognized_extensions_for_type("PackedScene"), que a su vez usa
## handles_type("PackedScene"), que devuelve false para un loader de
## GDScript. Resultado: el loader se descarta y Godot tira "No loader
## found for resource" sin importar que _load() hubiera funcionado.
##
## _recognize_path corre ANTES del filtro por extensiones (verificado en
## ResourceFormatLoader::recognize_path), asi que devolviendo true para
## nuestros paths ignoramos el type_hint por completo.
func _recognize_path(path: String, _for_type: StringName) -> bool:
	if path.begins_with("res://addons/"):
		DebugLog.log("[gd_loader._recognize_path] %s -> %s" % [path, mod_gd_paths.has(path)])
	return mod_gd_paths.has(path)


func _exists(path: String) -> bool:
	if path.begins_with("res://addons/"):
		DebugLog.log("[gd_loader._exists] %s -> %s" % [path, mod_gd_paths.has(path)])
	return mod_gd_paths.has(path)


func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	# No es un .gd de un mod: devolver null para que Godot siga con el
	# loader nativo. El ciclo de ResourceLoader::_load() chequea
	# res.is_valid() y continua si no lo es.
	# LOG: entrada y estado de los 3 diccionarios + original_path.
	# _original_path es "" cuando ResourceLoader::load(path) llama directo,
	# y != "" cuando es un remap (por ejemplo, .import de un .tscn que
	# referencia un .gd).
	DebugLog.log("[gd_loader._load] path=%s orig=%s in_mod_gd=%s in_mod_all=%s threads=%s mode=%d" % [
		path, _original_path, mod_gd_paths.has(path), mod_all_paths.has(path),
		str(_use_sub_threads), _cache_mode,
	])
	if not mod_gd_paths.has(path):
		DebugLog.log("[gd_loader._load] RECHAZA: no esta en mod_gd_paths")
		return null

	# Cache propio: si ya compilamos este path, devolver la misma
	# instancia. Ademas de ahorrar trabajo, es lo que el parser de
	# GDScript espera: la misma Ref<GDScript> para el mismo path.
	_cache_mutex.lock()
	if _cache.has(path):
		var cached: Variant = _cache[path]
		_cache_mutex.unlock()
		DebugLog.log("[gd_loader._load] cache hit: %s" % path)
		return cached
	_cache_mutex.unlock()

	var src_path: String = path
	if mod_all_paths.has(path):
		src_path = String(mod_all_paths[path])
	DebugLog.log("[gd_loader._load] src_path=%s exists=%s" % [
		src_path, FileAccess.file_exists(src_path),
	])
	if not FileAccess.file_exists(src_path):
		return null

	var src := FileAccess.get_file_as_string(src_path)
	if src.is_empty():
		push_warning("[RuntimeGDLoader] %s esta vacio" % path)
		return null
	if path.begins_with("res://addons/"):
		DebugLog.log("[gd_loader._load] ADDON compilando %s (%d bytes)" % [path, src.length()])

	var gd := GDScript.new()
	gd.source_code = src
	# Setear el resource_path ANTES del reload para que Godot registre
	# el script en GDScriptCache::shallow_gdscript_cache. Sin esto, el
	# parser no puede resolver tipos de retorno cuando OTRO script del
	# mod hace `HQSaves.foo()`.
	#
	# El orden importa: si hacemos take_over_path despues del reload,
	# el reload ya corrio sin path y no poblo el cache de GDScript.
	gd.take_over_path(path)
	if gd.reload() != OK:
		push_warning("[RuntimeGDLoader] reload fallo para %s" % path)
		if path.begins_with("res://addons/"):
			DebugLog.log("[gd_loader._load] ADDON reload FALLO %s" % path)
		return null
	if path.begins_with("res://addons/"):
		DebugLog.log("[gd_loader._load] ADDON reload OK %s" % path)

	# Guardar en el cache propio. Solo si no es CACHE_MODE_IGNORE (0);
	# los demas modos (REUSE=1 es el default) cachean normal.
	if _cache_mode != ResourceLoader.CACHE_MODE_IGNORE:
		_cache_mutex.lock()
		_cache[path] = gd
		_cache_mutex.unlock()
	return gd


## Vacia el cache de scripts compilados. Llamar cuando un mod se
## desinstala o cuando el mtime de sus .gd cambio, para forzar recompilar
## la proxima vez que se pida.
##
## Público para que ModLoader lo llame desde uninstall_mod() o cuando
## haga falta. No se llama automaticamente por ahora: los .gd cambian
## solo si el usuario edita el mod, y eso requiere reiniciar la app
## para que se note (los scripts ya cargados no se recomputan).
func clear_cache() -> void:
	_cache_mutex.lock()
	_cache.clear()
	_cache_mutex.unlock()
