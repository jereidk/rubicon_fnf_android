extends SceneTree

## El aviso de primera ejecucion sale con la cache fria y no sale con la
## caliente, y no rompe la pantalla de carga en ningun caso.
##
## Por que existe: la primera vez que se abre el juego tras instalarlo no es
## un poco mas lento, es otra experiencia. Dos logs del mismo Redmi sobre
## 10154-8d1ee1ac, misma build, dos arranques:
##
##     arranque 1   tienda: 52014ms de carga + 30089ms de precache = 82s
##     arranque 2   tienda:  5998ms de carga +  1270ms de precache =  7s
##
## con bench comparable en los dos tramos -o sea que no es el gobernador- y
## con el MISMO recuento de pipelines (233 contra 243). Es el driver
## compilando shaders que no ha visto nunca y guardandolos despues. Minuto y
## medio de pantalla de carga sin explicacion se lee como un cuelgue, y el log
## tiene a un jugador pulsando Atras nueve veces en una pantalla que
## simplemente estaba ocupada.
##
## Tres formas de romperlo, y ninguna da error:
##
##   se anade dos veces      - start() puede llamarse mas de una vez
##   se anade con la cache   - el aviso mentiria en todas las partidas menos
##     caliente                la primera
##   se come el toque        - un Control a pantalla completa por encima de la
##                             barra que no ignore el raton
##
## Run with:
##   godot --headless --path . --script tools/test_first_run_notice.gd

const SCREENS := [
	"res://lullaby_mod/resources/loading/load_hypno.tscn",
	"res://lullaby_mod/resources/loading/load_default.tscn",
]

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	for path in SCREENS:
		_case(path, true)
		_case(path, false)

	_guard_case()

	print("")
	if _checks < 15:
		print("FALLO: solo %d de 15 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el aviso sale solo con la cache fria")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## La puerta que el caso de arriba no puede recorrer, comprobada sobre el
## texto: que el aviso sale SOLO con la cache fria, y que no se cuelga de
## get_parent() - este script vive en la RAIZ de las dos pantallas de carga,
## que es un ColorRect a pantalla completa.
func _guard_case() -> void:
	var src := FileAccess.open(
		"res://lullaby_mod/scripts/lullaby/loading/lullaby_loading_screen.gd", FileAccess.READ)
	var text: String = src.get_as_text() if src != null else ""
	if src != null:
		src.close()

	_check("la puerta consulta shader_cache_cold",
		text.contains("if not Settings.shader_cache_cold:"))
	_check("y se rinde si Settings no lo trae",
		text.contains('not ("shader_cache_cold" in Settings)'))
	# Sobre las lineas de codigo, no sobre el fichero entero: el comentario de
	# arriba nombra get_parent() a proposito, para explicar por que no se usa.
	var code: String = ""
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	_check("el aviso se cuelga de self, no del padre",
		code.contains("add_child(_notice)") and not code.contains("get_parent()"))

func _case(path: String, cold: bool) -> void:
	var label: String = "%s cache=%s" % [path.get_file(), "fria" if cold else "caliente"]
	if not ResourceLoader.exists(path):
		_check("%s existe" % label, false)
		return

	var screen: Node = (load(path) as PackedScene).instantiate()
	get_root().add_child(screen)

	# build_notice() en vez de _show_notice_if_cold(): --script no da los
	# autoloads, asi que la mitad que consulta Settings no se puede recorrer
	# aqui. Que la consulta EXISTE y como esta escrita se comprueba abajo,
	# sobre el texto del fichero.
	if cold:
		screen.call("build_notice")
		# Dos veces, porque start() puede correr mas de una vez por sesion.
		screen.call("build_notice")

	var found: Array[Node] = screen.find_children("FirstRunNotice", "Label", true, false)
	if cold:
		_check("%s: sale una sola vez" % label, found.size() == 1, "%d" % found.size())
		if found.size() == 1:
			var notice: Label = found[0] as Label
			_check("%s: no se come el toque" % label,
				notice.mouse_filter == Control.MOUSE_FILTER_IGNORE)
			_check("%s: dice que es una sola vez" % label,
				notice.text.to_lower().contains("once"))
	else:
		_check("%s: sin llamar, no hay aviso" % label, found.is_empty(), "%d" % found.size())
		_check("%s: la pantalla sigue en pie" % label, is_instance_valid(screen))
		_check("%s: y conserva sus hijos" % label, screen.get_child_count() > 0)

	get_root().remove_child(screen)
	screen.free()

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
