extends SceneTree

## Cronometra cargar una escena, y luego cada una de sus dependencias de primer
## nivel por separado, para encontrar cual se lleva el tiempo.
##
## El dato que obliga a esto, del log 10235-2bb423f2 cruzado con el auditor de
## dependencias:
##
##     Safety Lullaby   203 recursos   39.8 MB    2.831 ms
##     tienda           460 recursos   47.3 MB   37.790 ms
##
## Trece veces mas lenta con el 84% de los bytes. Y las explicaciones obvias
## estan medidas y descartadas: no son los bytes (cortar un 34% no movio el
## reloj), no es el numero de recursos (2,3x no da 13x), no es la geometria (la
## tienda entera son 6,0MB de buffers y 79 mil vertices) y no son las pipelines
## (eso es el precache, que se mide aparte).
##
## Asi que se cronometra en vez de razonar. Los tiempos absolutos de aqui no son
## los del telefono - hay caché de páginas caliente y un disco distinto - pero
## una diferencia ESTRUCTURAL de trece veces tiene que reproducirse como
## proporcion, y si se reproduce se puede bisecar. Si no se reproduce, eso
## tambien es informacion: seria del dispositivo y no de la escena.
##
## Run with:
##   godot --headless --path . --script tools/audit_load_time.gd [ruta.tscn]

const SCENES: Array[String] = [
	"res://lullaby_mod/songs/safety_lullaby/sng_safety_lullaby.tscn",
	"res://lullaby_mod/rooms/env_collector_shop.tscn",
]


func _initialize() -> void:
	var targets: Array[String] = SCENES.duplicate()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		targets = []
		for a: String in args:
			targets.append(a)

	print("--- escena completa, en frio dentro de esta sesion ---")
	for path: String in targets:
		if not ResourceLoader.exists(path):
			print("  (no existe) %s" % path)
			continue
		var t0: int = Time.get_ticks_usec()
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		print("  %9.1f ms  %s%s" % [ms, path.get_file(), "" if res != null else "  (FALLO)"])

	# Y el desglose de la que mas tarde, por dependencia directa. Cada una se
	# carga sola, con la cache ignorada, para que el numero sea suyo y no del
	# orden en que la escena las pide.
	var worst: String = targets[targets.size() - 1]
	print("\n--- dependencias directas de %s ---" % worst.get_file())
	var deps: PackedStringArray = ResourceLoader.get_dependencies(worst)
	var rows: Array = []
	for dep: String in deps:
		var real: String = ""
		for part: String in dep.split("::"):
			if part.begins_with("res://") or part.begins_with("uid://"):
				real = part
		if real.begins_with("uid://"):
			var id: int = ResourceUID.text_to_id(real)
			real = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
		if real.is_empty() or not ResourceLoader.exists(real):
			continue
		var t0: int = Time.get_ticks_usec()
		ResourceLoader.load(real, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		rows.append([float(Time.get_ticks_usec() - t0) / 1000.0, real])

	rows.sort_custom(func(a, b): return a[0] > b[0])
	var total: float = 0.0
	for row: Array in rows:
		total += float(row[0])
	print("  %d dependencias directas, %.1f ms sumados" % [rows.size(), total])
	for i: int in mini(25, rows.size()):
		print("  %9.1f ms  %s" % [rows[i][0], String(rows[i][1]).replace("res://", "")])

	quit(0)
