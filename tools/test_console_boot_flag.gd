extends SceneTree

## The console's `booting` flag has to clear even if nobody is watching at the
## right instant.
##
## It gates back_out(), home_button, gallery_button and cartridges_enter_label,
## and it has exactly one writer outside console.gd - power_console.gd setting
## it true when the player switches the console on. So if the one place that
## clears it ever misses, the console stops responding for the life of the
## scene and nothing says why.
##
## The clear used to require three things at once: booting, the animation
## still playing, and its position already past 13.34s. That can only happen
## on a frame that lands inside the window between 13.34 and the end of the
## animation. Any frame that steps over it misses, and this project has frames
## seconds long - 11,489ms measured on the device.
##
## The last device log carries 22 consecutive ui_cancel presses with the
## console focused and nothing happening, which is what a stuck flag looks
## like from the player's side. That is consistent with this and does not
## prove it; what is provable is that the window is missable, which is what
## this pins.
##
## Driven by moving a real AnimationPlayer rather than by setting fields,
## because the bug is entirely about when _process happens to look.
##
## Run with:
##   godot --headless --path . --script tools/test_console_boot_flag.gd

const CONSOLE := "res://lullaby_mod/scripts/lullaby/collectors_shop/console/console.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	await _window_hit_case()
	await _window_missed_case()

	print("")
	if _checks < 6:
		print("FALLO: solo %d de 6 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el arranque termina aunque nadie mire en el instante justo")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

## The path that always worked: a frame lands past 13.34 while still playing.
func _window_hit_case() -> void:
	var console := _console()
	var player: AnimationPlayer = console.main_animation_player

	console.booting = true
	var fired: Array[bool] = [false]
	console.boot_finished.connect(func(): fired[0] = true)

	player.play(&"boot")
	player.seek(1.0, true)
	console._process(0.016)
	_check("a mitad del arranque sigue booting", console.booting)

	player.seek(14.0, true)
	console._process(0.016)
	_check("pasado 13.34 se limpia", not console.booting)
	_check("y emite boot_finished", fired[0])

	console.queue_free()
	await process_frame

## The path that did not: the animation ends before any frame looks.
func _window_missed_case() -> void:
	var console := _console()
	var player: AnimationPlayer = console.main_animation_player

	console.booting = true
	var fired: Array[bool] = [false]
	console.boot_finished.connect(func(): fired[0] = true)

	player.play(&"boot")
	player.seek(1.0, true)
	console._process(0.016)
	_check("empieza booting", console.booting)

	# The frame that never happens on a device under load: the animation runs
	# out and stops, and the next _process arrives with it no longer playing.
	player.stop()
	console._process(0.016)

	_check("una animacion parada tambien termina el arranque", not console.booting)
	_check("y tambien emite boot_finished", fired[0])

	console.queue_free()
	await process_frame

## The smallest console that _process can run against: the flag logic reads
## main_animation_player and nothing else, and building the real scene would
## drag in the whole shop.
func _console() -> Node:
	var console := Control.new()
	console.set_script(load(CONSOLE))

	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	var anim := Animation.new()
	anim.length = 16.0
	library.add_animation(&"boot", anim)
	player.add_animation_library(&"", library)

	console.add_child(player)
	root.add_child(console)
	# _ready() runs on add_child and calls boot(false), which needs children
	# this double does not have, so main_animation_player is set afterwards -
	# whatever _ready managed to do, the field this test drives is this one.
	console.main_animation_player = player
	console.booting = false
	return console

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-52s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-52s%s" % [label, "  (%s)" % detail if detail else ""])
