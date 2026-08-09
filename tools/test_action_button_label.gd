extends SceneTree

## No RubiconActionButton may render as nothing.
##
## These buttons are a rectangle of 7%-white with a label on top, so a label
## that comes out empty is not a button with missing text - it is no button
## at all. That is what happened on the device: the results screen's way out
## and the death screens' prompts were both reported as simply absent.
##
## The cause was showing a key binding as the label. A key name is not a
## label on a phone, and when the action resolves to no binding at all there
## is nothing left to draw.
##
## Run with:
##   godot --headless --path . --script tools/test_action_button_label.gd

const BUTTON := "res://addons/rubicon_mobile_controls/action_button.gd"
const RESULTS := "res://lullaby_mod/resources/funkin/ui/results/lullaby_results_screen.tscn"

var _failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _case("verbo y binding", "BACK", true, &"ui_accept", "")
	await _case("solo verbo", "BACK", false, &"ui_accept", "")
	await _case("solo binding, con tecla", "", true, &"ui_accept", "")
	# The device case: nothing bound, nothing authored, nothing to draw.
	await _case("solo binding, sin tecla", "", true, &"nada_ligado_a_esto", "")
	# And the same with the scene's own text as the last resort.
	await _case("sin binding util, con text", "", true, &"nada_ligado_a_esto", "SALIR")

	await _scene_case()

	print("")
	if _failures == 0:
		print("todo OK - ningun boton se queda en blanco")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## Builds one button and reports what a player would actually read on it.
func _case(label: String, verb: String, show_binding: bool, action: StringName,
		authored: String) -> void:
	var button: Button = load(BUTTON).new()
	button.action = action
	button.verb = verb
	button.show_binding = show_binding
	button.text = authored
	root.add_child(button)

	await process_frame
	await process_frame

	var shown: String = _visible_text(button)
	if shown.is_empty():
		_failures += 1
		print("  FALLO %-28s no se lee nada" % label)
	else:
		print("  ok    %-28s se lee \"%s\"" % [label, shown])

	button.queue_free()
	await process_frame

## Everything a player could read on the button: its own text plus any
## generated label that is actually visible.
func _visible_text(button: Button) -> String:
	var parts: Array[String] = []
	if not button.text.is_empty():
		parts.append(button.text)

	var column: Node = button.get_node_or_null("GeneratedLabel")
	if column != null:
		for child: Node in column.get_children():
			if child is Label and child.visible and not child.text.is_empty():
				parts.append(child.text)

	return " ".join(parts)

## The button the device actually reported missing.
func _scene_case() -> void:
	var packed: PackedScene = load(RESULTS)
	if packed == null:
		_failures += 1
		print("  FALLO no pude cargar la pantalla de resultados")
		return

	var screen: Node = packed.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame

	var button: Node = screen.get_node_or_null("BackButton")
	if button == null:
		_failures += 1
		print("  FALLO la pantalla de resultados no tiene BackButton")
	else:
		var shown: String = _visible_text(button)
		if shown.is_empty():
			_failures += 1
			print("  FALLO BackButton de resultados          no se lee nada")
		else:
			print("  ok    BackButton de resultados          se lee \"%s\"" % shown)

	screen.queue_free()
	await process_frame
