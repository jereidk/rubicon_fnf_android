extends SceneTree

## Un reinicio tiene que anunciarse como cualquier otro cambio de escena.
##
## Reportado: "al reiniciar, la hitbox de mecánica que debería estar por abajo
## siempre va arriba, es como si se sobreescribiera al reiniciar". No se
## sobreescribe - es que nadie la vuelve a colocar.
##
## `get_tree().reload_current_scene()` es el mecanismo correcto para un retry
## (conserva estáticos, no pasa por la pantalla de carga, no puede competir
## con una segunda carga) y es **invisible**: no pasa por SceneChanger, así
## que `scene_change_finished` no se emite y los cinco autoloads que lo
## escuchan no se enteran. La escena recargada se queda con lo que autora.
##
## Solo se reportó uno de los cuatro efectos:
##
##   lullaby_mobile_controls_applier   la banda del péndulo vuelve a la tira
##                                     de arriba que autora la escena
##   lullaby_note_layout_applier       VSlice vuelve a Classic
##   lullaby_light_budget_applier      ni luces horneadas ni cheap_shading, y
##                                     sus cachés siguen con las luces
##                                     liberadas de la escena anterior
##   lullaby_diagnostics_log           el retry no deja SCENE_OUT/SCENE_IN
##
## Este guard fija las dos mitades: que el reload viva en SceneChanger y
## emita, y que nadie mas llame al crudo.
##
## Correr con:
##   godot --headless --path . --script tools/test_retry_announces_scene_change.gd

const CHANGER := "res://menus/scene_changer.gd"
const RAW_CALL := "get_tree().reload_current_scene()"

## Los autoloads cuyo trabajo se pierde si un retry no se anuncia. Cada uno
## esta aqui porque conecta la señal, no porque alguien lo recordase.
const LISTENERS: PackedStringArray = [
	"res://lullaby_mod/scripts/lullaby/settings/lullaby_mobile_controls_applier.gd",
	"res://lullaby_mod/scripts/lullaby/settings/lullaby_note_layout_applier.gd",
	"res://lullaby_mod/scripts/lullaby/settings/lullaby_light_budget_applier.gd",
	"res://lullaby_mod/scripts/lullaby/debug/lullaby_diagnostics_log.gd",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	var changer: String = _read(CHANGER)
	_check(changer != "", "scene_changer.gd se lee")

	_check(_has_statement(changer, "func reload_current() -> void:"),
		"SceneChanger expone un reload propio")
	_check(_has_statement(changer, "scene_change_finished.emit(scene.scene_file_path)"),
		"...que anuncia el cambio")
	_check(_has_statement(changer, RAW_CALL),
		"...y sigue usando el mecanismo de siempre por debajo")

	# El orden importa y es el mismo que usa `_complete()`: los appliers
	# esperan un frame despues de la señal para caer sobre la escena nueva
	# antes de que dibuje. Emitir despues del swap los dejaria un frame
	# tarde, que en el applier de luces vale un juego entero de pipelines.
	# Buscado por linea de codigo, no por posicion en el texto: el docstring
	# de arriba nombra la llamada cruda antes de que aparezca de verdad, asi
	# que un find() sobre el fichero entero la encuentra en el comentario.
	var emit_at: int = _statement_line(changer, "scene_change_finished.emit(scene.scene_file_path)")
	var reload_at: int = _statement_line(changer, RAW_CALL)
	_check(emit_at != -1 and reload_at != -1 and emit_at < reload_at,
		"y emite ANTES de recargar, como hace _complete()")

	# Y no decide sobre un current_scene nulo.
	_check(_has_statement(changer, "if scene == null:"),
		"con guarda por si no hay escena")

	_check_no_raw_callers()
	_check_listeners()

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


## Nadie fuera de SceneChanger puede llamar al crudo. Es la mitad que impide
## que esto vuelva: el sitio que lo hacia parecia perfectamente razonable.
func _check_no_raw_callers() -> void:
	var offenders: PackedStringArray = []
	for path: String in _gd_files("res://"):
		if path == CHANGER:
			continue
		# tools/ nombra la llamada a proposito - este mismo fichero la lleva
		# como constante, y un audit que no puede escribir el nombre de lo
		# que prohibe no puede comprobarlo.
		if path.begins_with("res://tools/"):
			continue
		var src: String = _read(path)
		if src.is_empty():
			continue
		if _has_statement(src, RAW_CALL):
			offenders.append(path)
	_check(offenders.is_empty(),
		"nadie fuera de SceneChanger recarga a pelo (%s)" % (
			", ".join(offenders) if not offenders.is_empty() else "ninguno"))

	# Y el sitio que lo hacia usa el nuevo, en vez de haber perdido el retry.
	var module: String = _read(
		"res://lullaby_mod/scripts/lullaby/gameover/safety_lullaby_gameover_module.gd")
	_check(_has_statement(module, "SceneChanger.reload_current()"),
		"el retry de Safety Lullaby pasa por SceneChanger")


## Y la razon por la que esto importa, comprobada y no recordada: los cuatro
## siguen conectados a la señal. Si alguno deja de estarlo, esta lista deja
## de describir el coste y hay que rehacerla en vez de arrastrarla.
func _check_listeners() -> void:
	for path: String in LISTENERS:
		var src: String = _read(path)
		_check(_has_statement(src, "scene_change_finished.connect"),
			"%s sigue escuchando el cambio de escena" % path.get_file())


func _gd_files(root: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var stack: PackedStringArray = [root]
	while not stack.is_empty():
		var dir_path: String = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if entry.begins_with("."):
				entry = dir.get_next()
				continue
			var full: String = dir_path.path_join(entry)
			if dir.current_is_dir():
				stack.append(full)
			elif entry.ends_with(".gd"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found


## Numero de linea de la primera linea de CODIGO que contiene needle, o -1.
func _statement_line(src: String, needle: String) -> int:
	var lines: PackedStringArray = src.split("\n")
	for index: int in lines.size():
		var trimmed: String = lines[index].strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return index
	return -1


func _has_statement(src: String, needle: String) -> bool:
	for line: String in src.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if trimmed.contains(needle):
			return true
	return false


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  OK   %s" % label)
		return
	_failures += 1
	print("  FAIL %s" % label)
