extends SceneTree

## The Collector's 32 voiceline groups are held by path, not by reference.
##
## The shop's cold load is bound by per-file cost rather than by bandwidth -
## roughly 53ms a file on the device - and users report two minutes to enter the
## room. VoicelineEntry already moved the audio out of the dependency graph for
## exactly this reason, taking 109 files off the load. The 32 group resources
## that pointed at those files stayed behind, and in the device trace of a slow
## load they are the first eighty dependencies to arrive:
##
##     +vox_himself_group.tres +vox_hat_group.tres
##     +vox_monochrome_passed_return_group.tres ...
##
## They are metadata - a name and a list of paths - so nothing about them is
## needed for the room to appear.
##
## What this pins is the part that can rot silently. A path is a string: nothing
## checks it at import time, nothing fails at load, and a typo shows up as the
## Collector going quiet in one situation months later. So every entry is
## resolved here, and its `group_name` is checked to match the key the game
## looks it up by - a group whose name disagrees with its key is unreachable
## through get_voiceline_group() even though both halves exist.
##
## The scene is read as text rather than instantiated: env_collector_shop.tscn
## pulls in the whole room, which cannot load in a checkout with an incomplete
## import, and none of that is needed to check a dictionary of paths.
##
## Run with:
##   godot --headless --path . --script tools/test_voiceline_groups_deferred.gd

const SCENE := "res://lullaby_mod/rooms/env_collector_shop.tscn"
const SHOP := "res://lullaby_mod/scripts/lullaby/collectors_shop/env_collector_shop.gd"
const EXPECTED_GROUPS := 32

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var scene: String = _read(SCENE)
	var code: String = _read(SHOP)

	# Nada de la sala debe seguir arrastrando los grupos como dependencia.
	_check(not scene.contains("_group.tres\" id="),
		"la escena ya no declara ext_resource de ningun grupo")
	_check(scene.contains("voiceline_groups = []"),
		"y el array de referencias directas queda vacio")

	var map: Dictionary = _parse_map(scene)
	_check(map.size() == EXPECTED_GROUPS,
		"el mapa lleva los %d grupos (lleva %d)" % [EXPECTED_GROUPS, map.size()])

	# Cada ruta tiene que existir, cargar, y llamarse como su clave.
	var missing: PackedStringArray = []
	var mismatched: PackedStringArray = []
	for key: String in map:
		var path: String = map[key]
		if not ResourceLoader.exists(path):
			missing.append("%s -> %s" % [key, path])
			continue
		var group: Resource = load(path)
		if group == null:
			missing.append("%s -> %s (no carga)" % [key, path])
			continue
		if String(group.get("group_name")) != key:
			mismatched.append("%s -> group_name=\"%s\"" % [key, group.get("group_name")])

	_check(missing.is_empty(), "las %d rutas existen y cargan%s"
		% [map.size(), "" if missing.is_empty() else ": " + ", ".join(missing.slice(0, 3))])
	_check(mismatched.is_empty(),
		"y cada grupo se llama como la clave por la que se busca%s"
			% ["" if mismatched.is_empty() else ": " + ", ".join(mismatched.slice(0, 3))])

	# Y que ninguno quede inalcanzable por una clave repetida - el .tscn no
	# puede tenerlas, pero el conteo lo confirma contra el numero de rutas.
	var unique_paths: Dictionary = {}
	for key: String in map:
		unique_paths[map[key]] = true
	_check(unique_paths.size() == map.size(),
		"no hay dos claves apuntando al mismo fichero (%d rutas para %d claves)"
			% [unique_paths.size(), map.size()])

	_code_checks(code)

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _code_checks(code: String) -> void:
	_check(code.contains("@export var voiceline_group_paths: Dictionary[String, String]"),
		"el export existe y esta tipado")

	var getter: String = _func_body(code, "get_voiceline_group")
	_check(getter.contains("_loaded_groups.has(group_name)"),
		"get_voiceline_group cachea, para no recargar por llamada")
	_check(getter.contains("_loaded_groups[group_name] = loaded"),
		"...guardando incluso el fallo, o una ruta mala carga en cada linea")
	_check(getter.contains("for group in voiceline_groups:"),
		"y sigue respetando una referencia directa antes que el mapa")

	# El calentado en segundo plano tiene que cubrir tambien los diferidos, o
	# la primera reproduccion de cada linea pagaria su propia carga.
	var warm: String = _func_body(code, "_warm_one_voiceline")
	_check(warm.contains("_warm_names"), "el calentado recorre tambien los grupos diferidos")
	_check(warm.contains("get_voiceline_group(deferred_name)") and warm.contains("return"),
		"cargando un fichero de grupo por frame, sin encadenar dos")
	_check(warm.contains("warm_next()"),
		"y despues sus lineas, una por frame, como antes")


## The dictionary literal out of the .tscn, without instantiating the room.
func _parse_map(scene: String) -> Dictionary:
	var head: int = scene.find("voiceline_group_paths = Dictionary[String, String]({")
	if head < 0:
		_check(false, "la escena declara voiceline_group_paths")
		return {}
	var from: int = scene.find("{", head)
	var to: int = scene.find("})", from)
	if to < 0:
		_check(false, "el literal del mapa esta cerrado")
		return {}

	var out: Dictionary = {}
	var body: String = scene.substr(from + 1, to - from - 1)
	var re := RegEx.create_from_string('"([^"]+)"\\s*:\\s*"([^"]+)"')
	for m in re.search_all(body):
		out[m.get_string(1)] = m.get_string(2)
	return out


func _func_body(text: String, name: String) -> String:
	var head: int = text.find("func %s(" % name)
	if head < 0:
		_check(false, "%s() existe" % name)
		return ""
	var tail: int = text.find("\nfunc ", head + 1)
	return text.substr(head, tail - head if tail > head else -1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	_check(not text.is_empty(), "%s se lee" % path.get_file())
	return text
