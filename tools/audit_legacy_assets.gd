extends SceneTree

## Quien usa todavia el arbol `res://assets/`, el de antes de mover el mod.
##
## Hay dos arboles de assets en el proyecto: `res://assets/` (78 ficheros, 94MB)
## y `res://lullaby_mod/assets/` (1338 ficheros, 709MB). El segundo es donde vive
## el mod ahora; el primero mezcla lo del juego base (`assets/levels/...`, que es
## Rubicon) con restos de Lullaby de antes de la mudanza
## (`assets/funkin/chimera/...`, `assets/collector/shop/...`).
##
## Ninguno de los dos esta en `exclude_filter` y el preset exporta
## `all_resources`, asi que TODO lo alcanzable viaja en el APK. Saber cuanto de
## esos 94MB sigue alcanzandose es lo unico que dice si se puede recortar.
##
## POR QUE NO VALE UN grep. Es el error que esta herramienta reemplaza. Un
## barrido de cadenas sobre los ficheros del proyecto daba 32 ficheros "sin
## ninguna referencia", 93,6MB - y el .error del dispositivo PRUEBA que ocho de
## ellos se cargan:
##
##     'res://lullaby_mod/assets/menus/console/options/portrait/settings_icons.res':
##     In external resource #0, invalid UID: 'uid://ca0j4knw2tj61'
##     - using text path instead:
##     'res://assets/collector/shop/console ui/Options/settings_icons.png'
##
## La razon es que esos .res empiezan por `RSCC` y no por `RSRC`: son recursos
## binarios COMPRIMIDOS con zstd, y las rutas que contienen viven dentro del
## bloque comprimido. Ninguna busqueda de bytes las ve. `get_dependencies()` si,
## porque lo pregunta al motor.
##
## Y las cuenta por las DOS vias, porque las referencias de este proyecto llegan
## de las dos: por uid:// y por ruta textual. Los ocho de arriba son justo el caso
## mixto - un uid rancio que ya no existe y una ruta textual que sigue valiendo -
## y contar solo uids los habria declarado huerfanos igual que el grep.
##
## Run with:
##   godot --headless --path . --script tools/audit_legacy_assets.gd

const LEGACY := "res://assets"

## Donde buscar referencias. Todo menos el propio arbol legado, para no contar
## que un fichero de dentro se referencie a si mismo.
const SEARCH_ROOTS: Array[String] = [
	"res://lullaby_mod", "res://menus", "res://resources", "res://levels",
	"res://addons", "res://scripts", "res://scenes",
]

const CARRIERS := ["tscn", "tres", "res", "scn"]


func _initialize() -> void:
	# 1. Cada fichero del arbol legado, con su uid si lo tiene.
	var legacy: Dictionary = {}          # res path -> bytes
	var uid_to_path: Dictionary = {}     # "uid://..." -> res path
	_collect_legacy(LEGACY, legacy, uid_to_path)
	print("arbol legado: %d ficheros, %.1f MB" % [legacy.size(), _sum(legacy) / 1e6])
	print("de ellos con uid propio: %d" % uid_to_path.size())

	# 2. Todos los portadores de referencias fuera del arbol legado.
	var carriers: PackedStringArray = []
	for root: String in SEARCH_ROOTS:
		_collect_carriers(root, carriers)
	print("portadores a revisar: %d" % carriers.size())

	# 3. Preguntarle al motor por las dependencias de cada uno.
	var hits: Dictionary = {}            # res path del legado -> veces
	var scanned: int = 0
	for carrier: String in carriers:
		scanned += 1
		for dep: String in ResourceLoader.get_dependencies(carrier):
			# El formato es "uid::tipo::ruta" o "ruta", segun como se escribiera.
			var parts: PackedStringArray = dep.split("::")
			var candidates: PackedStringArray = [parts[parts.size() - 1]]
			if parts.size() > 1:
				candidates.append(parts[0])

			for c: String in candidates:
				var target: String = ""
				if c.begins_with("uid://"):
					if uid_to_path.has(c):
						target = uid_to_path[c]
				elif legacy.has(c):
					target = c
				if target != "":
					hits[target] = int(hits.get(target, 0)) + 1

	print("dependencias leidas de %d portadores" % scanned)
	print("")

	# 4. El reparto.
	var used: Array = []
	var unused: Array = []
	for path: String in legacy:
		if hits.has(path):
			used.append([path, legacy[path], hits[path]])
		else:
			unused.append([path, legacy[path]])

	used.sort_custom(func(a, b): return a[1] > b[1])
	unused.sort_custom(func(a, b): return a[1] > b[1])

	var used_bytes: int = 0
	for e: Array in used:
		used_bytes += int(e[1])
	var unused_bytes: int = 0
	for e: Array in unused:
		unused_bytes += int(e[1])

	print("ALCANZADOS: %d ficheros, %.1f MB" % [used.size(), used_bytes / 1e6])
	for e: Array in used:
		print("   %8.2f MB  x%-3d %s" % [int(e[1]) / 1e6, int(e[2]), e[0]])

	print("")
	print("SIN DEPENDENCIA DECLARADA: %d ficheros, %.1f MB"
		% [unused.size(), unused_bytes / 1e6])
	for e: Array in unused:
		print("   %8.2f MB  %s" % [int(e[1]) / 1e6, e[0]])

	print("")
	print("AVISO: \"sin dependencia declarada\" NO es \"se puede borrar\". Un script")
	print("que construya la ruta en tiempo de ejecucion - load(\"res://assets/\" + x)")
	print("- no aparece aqui, y esta herramienta no lo puede ver. Antes de borrar")
	print("nada hay que buscar tambien las cadenas parciales en los .gd.")
	quit(0)


func _collect_legacy(dir_path: String, out: Dictionary, uids: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect_legacy(full, out, uids)
		elif not name.ends_with(".import") and not name.ends_with(".md5"):
			out[full] = FileAccess.get_file_as_bytes(full).size()
			var import_path: String = full + ".import"
			if FileAccess.file_exists(import_path):
				var cfg := ConfigFile.new()
				if cfg.load(import_path) == OK:
					var u: String = str(cfg.get_value("remap", "uid", ""))
					if u.begins_with("uid://"):
						uids[u] = full
		name = dir.get_next()
	dir.list_dir_end()


func _collect_carriers(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect_carriers(full, out)
		elif CARRIERS.has(name.get_extension().to_lower()):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _sum(d: Dictionary) -> int:
	var n: int = 0
	for k: Variant in d:
		n += int(d[k])
	return n
