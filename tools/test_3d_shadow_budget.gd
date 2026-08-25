extends SceneTree

## "Sombras: off" tambien tiene que apagar el shadow_enabled de las luces.
##
## El log del dispositivo del 2026-08-24 (moto g60s, preset Very Low) trae una
## cascada de miles de errores desde el segundo 354.59:
##
##     Parameter "framebuffer" is null.   rendering_device.cpp:5556 draw_list_begin
##     ... (x10) ... (x100) ... (x1000)
##
## La cadena, entera:
##
##   1. Very Low trae shadows_enabled = false, asi que settings.gd calcula
##      shadow_size = 0 y llama a directional_shadow_atlas_set_size(0, true).
##      Eso es global, no del viewport.
##   2. La pantalla de resultados tiene un DirectionalLight3D con
##      shadow_enabled = true dentro de un SubViewport con own_world_3d.
##   3. Ese SubViewport vive en render_target_update_mode = DISABLED - por eso
##      no molestaba - hasta que lullaby_results_screen.gd lo pone en
##      UPDATE_ALWAYS al mostrar los resultados.
##   4. El motor abre un draw list contra un atlas de sombras de tamano cero.
##
## Se arregla por el lado de la luz y no subiendo el atlas: una luz que no pide
## sombra tampoco la paga, mientras que un atlas minimo habria escondido los
## errores y conservado el trabajo.
##
## Run with:
##   godot --headless --path . --script tools/test_3d_shadow_budget.gd

const SETTINGS := "res://menus/settings.gd"
const RESULTS := "res://lullaby_mod/resources/funkin/ui/results/lullaby_results_screen.tscn"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_wiring_checks()
	await _behaviour_checks()
	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)


func _wiring_checks() -> void:
	var code: String = FileAccess.get_file_as_string(SETTINGS)
	_check(code.contains("directional_shadow_atlas_set_size(shadow_size, true)"),
		"sigue poniendo el atlas direccional a shadow_size")
	_check(code.contains("func _apply_3d_shadow_budget"),
		"...y ahora tambien apaga el shadow_enabled de las luces")
	_check(code.contains("_apply_3d_shadow_budget()\n") and
			code.find("_apply_3d_shadow_budget()") < code.find("func _apply_3d_shadow_budget"),
		"...llamado desde apply_settings, no solo definido")
	_check(code.contains("AUTHORED_SHADOW_ENABLED"),
		"guarda el valor authoreado para poder restaurarlo")

	# Y la escena que lo destapo sigue teniendo la forma que lo provoca, o esta
	# prueba dejaria de significar algo sin avisar.
	var results: String = FileAccess.get_file_as_string(RESULTS)
	_check(results.contains("own_world_3d = true"),
		"la pantalla de resultados sigue con su propio World3D")
	_check(results.contains("shadow_enabled = true"),
		"...y su DirectionalLight3D sigue pidiendo sombra en la escena")


## Manejado de verdad, con la forma exacta del bug: una luz dentro de un
## SubViewport con su propio mundo, que es donde ningun barrido de la escena
## principal la habria encontrado.
func _behaviour_checks() -> void:
	var script: GDScript = load(SETTINGS)
	_check(script != null, "settings.gd carga")
	if script == null:
		return

	var settings: Node = root.get_node_or_null(^"Settings")
	var propio: bool = settings == null
	if propio:
		settings = script.new()
		settings.name = "SettingsPrueba"
		root.add_child(settings)

	var sub := SubViewport.new()
	sub.own_world_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(sub)

	var dir := DirectionalLight3D.new()
	dir.shadow_enabled = true
	sub.add_child(dir)

	var suelta := OmniLight3D.new()
	suelta.shadow_enabled = false   # authoreada en false: no debe "encenderse"
	root.add_child(suelta)

	await process_frame

	settings.set("graphics_shadows_enabled", false)
	settings.call("_apply_3d_shadow_budget")
	_check(not dir.shadow_enabled,
		"sombras off: la luz del SubViewport deja de pedir sombra")
	_check(not suelta.shadow_enabled, "...y la que ya estaba en false sigue igual")

	settings.set("graphics_shadows_enabled", true)
	settings.call("_apply_3d_shadow_budget")
	_check(dir.shadow_enabled,
		"sombras on: recupera el valor AUTHOREADO, no un true fijo")
	_check(not suelta.shadow_enabled,
		"...y la authoreada en false NO se enciende sola")

	# Una luz que llega despues, que es como aparece la pantalla de resultados.
	settings.set("graphics_shadows_enabled", false)
	settings.call("_apply_3d_shadow_budget")
	var tarde := DirectionalLight3D.new()
	tarde.shadow_enabled = true
	sub.add_child(tarde)
	await process_frame
	_check(not tarde.shadow_enabled,
		"una luz instanciada despues tambien queda cubierta (node_added)")

	settings.set("graphics_shadows_enabled", true)
	settings.call("_apply_3d_shadow_budget")
	sub.queue_free()
	suelta.queue_free()
	if propio:
		settings.queue_free()
	await process_frame


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
