extends SceneTree

## The RETRY / EXIT buttons on the two death screens that have them: that they
## are really there, and that a finger can really use them.
##
## Both screens took "a tap anywhere" and nothing said so, which on a phone is
## an invisible affordance - LullabyGameoverPrompt exists to make it visible.
## But a prompt is a chain with six links and every one of them fails quietly:
## the node can be missing from the scene, its `available_source` can point at a
## property that no longer exists, it can build zero buttons, the buttons can
## come out disabled or transparent to touch, the action they dispatch can be
## one the death screen does not handle, and the layer can put them under
## something that eats the tap. None of that raises an error - it just leaves a
## screen the player cannot leave.
##
## So this instances both scenes for real and walks the chain.
##
## Run with:
##   godot --headless --path . --script tools/test_gameover_prompt_usable.gd

const SCREENS := {
	"safety": {
		"scene": "res://lullaby_mod/songs/safety_lullaby/scenes/gameover_module.tscn",
		"script": "res://lullaby_mod/scripts/lullaby/gameover/safety_lullaby_gameover_module.gd",
		"blocker": &"_retrying",
	},
	"monochrome": {
		"scene": "res://lullaby_mod/songs/monochrome/scenes/gameover.tscn",
		"script": "res://lullaby_mod/scripts/lullaby/gameover/monochrome_gameover.gd",
		"blocker": &"_transitioning",
	},
}
const WANTED := [&"ui_accept", &"ui_cancel"]

var _failures: int = 0
var _checks: int = 0
var _frames: int = 0


func _initialize() -> void:
	for key: String in SCREENS:
		_script_checks(key, SCREENS[key]["script"])


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 2:
		return false

	for key: String in SCREENS:
		_scene_checks(key, SCREENS[key]["scene"])

	print("%d comprobaciones, %d fallos" % [_checks, _failures])
	if _failures == 0:
		print("todo OK")
	quit(1 if _failures > 0 else 0)
	return true


## A button that dispatches an action nothing handles is a button that does
## nothing, and looks exactly like one that works.
func _script_checks(key: String, path: String) -> void:
	var code: String = FileAccess.get_file_as_string(path)
	_check(not code.is_empty(), "[%s] el script se lee" % key)
	for action: StringName in WANTED:
		_check(code.contains('&"%s"' % action),
			"[%s] la pantalla maneja %s" % [key, action])

	# Y la mano contraria: mientras el prompt esta a la vista, el "toca donde
	# sea" tiene que callarse, o _input() se adelanta al GUI y un toque sobre
	# EXIT dispara el retry antes de que el boton llegue a emitir.
	_check(code.contains("retry_prompt.visible"),
		"[%s] el toque-en-cualquier-parte se calla mientras hay botones" % key)


func _scene_checks(key: String, path: String) -> void:
	var packed: PackedScene = load(path)
	_check(packed != null, "[%s] la escena carga" % key)
	if packed == null:
		return

	var screen: Node = packed.instantiate()
	root.add_child(screen)

	var prompt: CanvasLayer = screen.get_node_or_null(^"RetryPrompt") as CanvasLayer
	_check(prompt != null, "[%s] RetryPrompt esta en la escena" % key)
	if prompt == null:
		screen.queue_free()
		return

	# Encima del arte de muerte (Node2D, capa 0) y debajo de la pantalla de
	# carga, que se queda la 128.
	_check(prompt.layer > 0 and prompt.layer < 128,
		"[%s] su capa (%d) esta por encima del arte y por debajo de la carga"
			% [key, prompt.layer])

	# El gate: available_source/available_property tienen que apuntar a una
	# propiedad que exista de verdad, o el prompt no aparece nunca - o peor,
	# aparece siempre.
	var source: Node = prompt.get("available_source")
	var property: StringName = prompt.get("available_property")
	_check(source != null and not String(property).is_empty(),
		"[%s] el prompt tiene fuente y propiedad de disponibilidad" % key)
	if source != null:
		var found: bool = false
		for entry in source.get_property_list():
			if StringName(entry["name"]) == property:
				found = true
		_check(found, "[%s] `%s` existe de verdad en %s"
			% [key, property, source.get_class()])

	var column: Node = prompt.get_node_or_null(^"Prompts")
	_check(column != null, "[%s] el prompt construyo su columna" % key)
	if column == null:
		screen.queue_free()
		return

	var actions: PackedStringArray = []
	for child in column.get_children():
		var button := child as BaseButton
		if button == null:
			continue
		actions.append(String(button.get("action")))
		_check(not button.disabled, "[%s] el boton %s no sale deshabilitado" % [key, button.name])
		_check(button.mouse_filter == Control.MOUSE_FILTER_STOP,
			"[%s] el boton %s acepta el toque (mouse_filter=%d)"
				% [key, button.name, button.mouse_filter])
		_check(button.custom_minimum_size.x >= 100.0 and button.custom_minimum_size.y >= 44.0,
			"[%s] el boton %s es de un tamaño tocable (%s)"
				% [key, button.name, button.custom_minimum_size])

	for action: StringName in WANTED:
		_check(actions.has(String(action)),
			"[%s] hay un boton para %s (hay: %s)" % [key, action, ", ".join(actions)])

	# Y que el gate mueva de verdad la visibilidad, no solo que exista.
	#
	# `can_retry` es un getter calculado sin setter, asi que escribirle no hace
	# nada - la primera version de esto lo intentaba y fallaba por su cuenta,
	# no por el juego. Se mueve el estado que el getter lee, que es ademas lo
	# que hace la pantalla de verdad: Safety sale de `activated and not
	# _retrying`, Monochrome de `not _transitioning and boyfriend_scene.visible`.
	var blocker: StringName = SCREENS[key]["blocker"]
	if source != null:
		if key == "safety":
			source.set(&"activated", true)
		source.set(blocker, false)
		prompt.call("_process", 0.0)
		var shown: bool = prompt.visible

		source.set(blocker, true)
		prompt.call("_process", 0.0)
		_check(shown and not prompt.visible,
			"[%s] el prompt aparece cuando %s acepta y se va cuando no (%s)"
				% [key, property, blocker])

	screen.queue_free()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ok   %s" % what)
	else:
		_failures += 1
		printerr("  FALLO %s" % what)
