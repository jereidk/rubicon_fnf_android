extends ResourceFormatLoader

## Carga .tres/.tscn/.scn que viven dentro de un .pck montado.
##
## El ResourceFormatLoaderText nativo tiene esta trampa:
##
##     void ResourceFormatLoaderText::get_recognized_extensions_for_type(
##             const String &p_type, List<String> *p_extensions) const {
##         ...
##         if (ClassDB::is_parent_class("PackedScene", p_type)) {
##             p_extensions->push_back("tscn");
##         }
##         // Don't allow .tres for PackedScenes or GDExtension.
##         if (p_type != "PackedScene" && p_type != "GDExtension") {
##             p_extensions->push_back("tres");
##         }
##     }
##
## O sea: cuando el analyzer de GDScript hace preload("res://x.tres"), le
## pasa un type_hint al ResourceLoader, y si ese hint es "PackedScene" el
## text loader se descarta a si mismo para .tres. Ningun otro loader
## nativo maneja .tres, y Godot tira:
##
##     No loader found for resource: res://x.tres (expected type: PackedScene)
##
## Este loader se registra at_front. Solo intercepta paths que ModLoader
## registro como provenientes de un mod (.tres/.tscn/.scn dentro del
## pck). Para todo lo demas devuelve null y Godot delega al text loader
## nativo, que funciona bien para archivos del APK.
##
## El truco de _load: el text loader nativo SI sabe parsear un .tres si
## el hint es vacio (con hint vacio usa get_recognized_extensions
## completo, que incluye tres). Pero si le pasamos el path a
## ResourceLoader.load con hint "", volveria a matchearnos a nosotros
## primero (porque _recognize_path siempre devuelve true para mods y
## no mira el hint). Para evitarlo: sacarnos del array temporalmente,
## llamar load, volvernos a poner.

var mod_resource_paths: Dictionary = {}

## Bypass thread-safe para la delegacion al text loader nativo. En vez
## de tocar la lista GLOBAL de loaders (add/remove_resource_format_loader
## mutan loader[] sin lock, y con threaded load el main thread puede estar
## iterando esa misma lista en paralelo -> crash), marcamos el path en
## este diccionario para que _recognize_path() devuelva false durante
## la carga. El mutex protege las lecturas/escrituras concurrentes.
##
## mod_resource_paths se setea UNA SOLA VEZ por ModLoader al registrar
## el loader y nunca se muta, asi que leerlo desde cualquier thread es
## seguro. El unico shared mutable es _bypass_paths.
var _bypass_mutex := Mutex.new()
var _bypass_paths: Dictionary = {}

## Igual que en los otros runtime loaders: ModLoader lo inyecta al
## registrar el loader. Los .tscn/.tres SI van al pck (el text loader
## nativo los abre con FileAccess directo), asi que este loader no
## necesita el mapeo para _load, pero lo recibe igual para que el log
## de diagnostico lo pueda leer.
var mod_all_paths: Dictionary = {}


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["tres", "tscn", "scn"])


func _recognize_path(path: String, for_type: StringName) -> bool:
	# Solo reclamamos .tres. El bug original era el text loader nativo
	# rechazando .tres cuando el type_hint era PackedScene (por su
	# get_recognized_extensions_for_type). Para .tscn/.scn NO hay ese
	# bug: el text loader los maneja bien.
	#
	# Ademas, delegar .tscn/.scn al text loader desde _load() causa un
	# ciclo de dependencia en threaded load: el worker thread pide
	# ResourceLoader.load(tscn) mientras el padre esta cargando el mismo
	# tscn, el engine detecta el ciclo y devuelve null anti-deadlock, y
	# el loader reintenta en bucle (cientos de veces por frame, visto en
	# el log de 22:05).
	if not mod_resource_paths.has(path):
		return false
	var ext := path.get_extension().to_lower()
	if ext != "tres":
		return false
	var hint := String(for_type)
	# Reclamamos si el hint es PackedScene o GDExtension (los casos
	# donde el text loader nativo falla para .tres), o si viene vacio
	# (llamada generica de ResourceLoader.load sin hint explicito).
	return hint == "PackedScene" or hint == "GDExtension" or hint.is_empty()


func _get_resource_type(path: String) -> String:
	if not mod_resource_paths.has(path):
		return ""
	var ext := path.get_extension().to_lower()
	if ext == "tscn" or ext == "scn":
		return "PackedScene"
	# .tres: leer el header [gd_resource type="X" ...] y devolver X.
	# Si no se puede, "Resource" generico (el text loader lo acepta).
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "Resource"
	var header := f.get_line()
	f.close()
	var marker := header.find("type=\"")
	if marker == -1:
		return "Resource"
	var start := marker + 6
	var end := header.find("\"", start)
	if end == -1:
		return "Resource"
	return header.substr(start, end - start)


func _handles_type(_type: StringName) -> bool:
	return true


func _exists(path: String) -> bool:
	# El analyzer llama exists() al resolver preload() de .tscn/.tres.
	# Aunque estos van al pck (y por lo tanto res:// los ve), el analyzer
	# consulta primero los loaders custom. Devolviendo true evitamos que
	# la cadena aborte por el filtro de type_hint del text loader nativo.
	return mod_resource_paths.has(path)


func _load(path: String, _orig: String, _sub: bool, _cache: int) -> Variant:
	DebugLog.log("[res_loader._load] path=%s in_mod_res=%s in_mod_all=%s" % [
		path, mod_resource_paths.has(path), mod_all_paths.has(path),
	])
	if not mod_resource_paths.has(path):
		return null
	if path.get_extension().to_lower() != "tres":
		# .tscn/.scn no los tocamos: el text loader nativo los maneja
		# bien. Delegarlos desde aca causaba el ciclo de dependencia en
		# threaded load (ver comentario en _recognize_path).
		return null
	# Delegar con hint "": el text loader nativo acepta .tres con ese
	# hint (get_recognized_extensions_for_type sin PackedScene). Como
	# nuestro _recognize_path ahora devuelve false para .tres sin
	# PackedScene/GDExtension hint, no hay bucle.
	DebugLog.log("[res_loader._load] delegando .tres al text loader: %s" % path)
	var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DebugLog.log("[res_loader._load] text loader devolvio %s" % str(res))
	return res

