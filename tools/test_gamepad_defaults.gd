extends SceneTree

## A connected gamepad has to work without visiting the console first.
##
## What shipped: the four note lanes came from
## addons/rubicon_mania/resources/default_input_map.tres, which is D/F/J/K and
## nothing else, and project.godot's whole [input] block has zero
## InputEventJoypad. Godot's own defaults cover ui_left/right/up/down with the
## D-pad but - checked against the running binary - **not ui_accept or
## ui_cancel**, which are Enter/Kp Enter/Space and Escape. So a pad could move
## through every menu in the game and neither confirm nor go back, and could
## not hit a single note.
##
## The machinery was always there: RubiconLevelNoteInputMap matches with
## InputEvent.is_match(), which is type-agnostic, and the console's rebind row
## accepts any event that reports pressed. Only the defaults were missing.
##
## What this pins, in order of how badly each would bite:
##
##   1. ui_accept KEEPS Enter and Space. The reason these are added at runtime
##      instead of written into project.godot is that overriding a built-in
##      action there replaces its entire event list - a joypad-only entry would
##      silently take the keyboard off ui_accept for every player.
##   2. an existing binding is never overridden, so a player who rebinds a lane
##      does not get the default put back on the next boot
##   3. running twice does not stack duplicates, which it must not, because it
##      runs on every load
##
## Run with:
##   godot --headless --path . --script tools/test_gamepad_defaults.gd

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var s: Node = root.get_node_or_null(^"Settings")
	if s == null:
		print("FALLO: no existe el autoload Settings")
		quit(1)
		return

	s.reset_input_map()

	# 1. Los cuatro carriles.
	for lane: int in 4:
		var action: StringName = &"mania_lane%d" % lane
		_check("%s tiene mando" % action,
			_gamepad_buttons(s.input_game.get(action, [])).size() == 1,
			_describe(s.input_game.get(action, [])))

	_check("y la cruceta va en el orden de las flechas",
		_gamepad_buttons(s.input_game[&"mania_lane0"])[0] == JOY_BUTTON_DPAD_LEFT
			and _gamepad_buttons(s.input_game[&"mania_lane1"])[0] == JOY_BUTTON_DPAD_DOWN
			and _gamepad_buttons(s.input_game[&"mania_lane2"])[0] == JOY_BUTTON_DPAD_UP
			and _gamepad_buttons(s.input_game[&"mania_lane3"])[0] == JOY_BUTTON_DPAD_RIGHT)

	_check("las teclas del carril siguen ahi",
		_has_key(s.input_game[&"mania_lane0"]),
		_describe(s.input_game[&"mania_lane0"]))

	# 2. Las acciones del proyecto.
	for action: StringName in [&"lullaby_special", &"funkin_pause", &"open_cartridge_bag"]:
		_check("%s tiene mando" % action,
			_gamepad_buttons(s.input_map.get(action, [])).size() == 1,
			_describe(s.input_map.get(action, [])))

	# 3. Los ui_, que es donde estaba el agujero de verdad.
	for action: StringName in [&"ui_accept", &"ui_cancel"]:
		_check("%s tiene mando" % action,
			_gamepad_buttons(InputMap.action_get_events(action)).size() == 1,
			_describe(InputMap.action_get_events(action)))

	_check("ui_accept NO perdio Enter ni Espacio",
		_has_key(InputMap.action_get_events(&"ui_accept")),
		_describe(InputMap.action_get_events(&"ui_accept")))
	_check("ui_cancel NO perdio Escape",
		_has_key(InputMap.action_get_events(&"ui_cancel")),
		_describe(InputMap.action_get_events(&"ui_cancel")))

	# 4. Idempotente: corre en cada carga.
	var before: int = s.input_game[&"mania_lane0"].size()
	s.ensure_gamepad_defaults()
	s.ensure_gamepad_defaults()
	_check("correrlo de nuevo no duplica nada",
		s.input_game[&"mania_lane0"].size() == before
			and _gamepad_buttons(InputMap.action_get_events(&"ui_accept")).size() == 1,
		"carril=%d ui_accept=%d" % [s.input_game[&"mania_lane0"].size(),
			_gamepad_buttons(InputMap.action_get_events(&"ui_accept")).size()])

	# 5. Y no pisa lo que el jugador eligio.
	var mine := InputEventJoypadButton.new()
	mine.device = -1
	mine.button_index = JOY_BUTTON_Y
	s.input_game[&"mania_lane0"] = [mine]
	s.ensure_gamepad_defaults()
	_check("un binding del jugador no se sobrescribe",
		s.input_game[&"mania_lane0"].size() == 1
			and _gamepad_buttons(s.input_game[&"mania_lane0"])[0] == JOY_BUTTON_Y,
		_describe(s.input_game[&"mania_lane0"]))

	print("")
	if _checks < 15:
		print("FALLO: solo %d de 15 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - un mando conectado juega y navega sin tocar la consola")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _gamepad_buttons(events: Array) -> Array[int]:
	var out: Array[int] = []
	for event: InputEvent in events:
		if event is InputEventJoypadButton:
			out.append((event as InputEventJoypadButton).button_index)
	return out

func _has_key(events: Array) -> bool:
	for event: InputEvent in events:
		if event is InputEventKey:
			return true
	return false

func _describe(events: Array) -> String:
	var out: PackedStringArray = PackedStringArray()
	for event: InputEvent in events:
		out.append(event.as_text())
	return ", ".join(out) if out.size() > 0 else "(vacio)"

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-46s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-46s%s" % [label, "  (%s)" % detail if detail else ""])
