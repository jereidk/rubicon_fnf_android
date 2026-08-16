extends SceneTree

## The book's SubViewport renders while the book is open, and not otherwise.
##
## KollectadexSubViewport is 620x464 - 0.288 megapixels, the same count as the
## whole game at its 800x360 render scale - and the device log has it rendering
## in 62 of 78 shop samples. The shop's six live SubViewports come to 1.38
## megapixels against the main viewport's 0.288, and its GPU totals 16.24ms at
## the median against a 16.7ms budget.
##
## Three things have to hold, and each of them is a way this could ship broken:
##
##   - it renders one frame at startup. The texture is shown by a prop standing
##     in the room, and a viewport that never rendered has nothing to show, so
##     switching it straight off would leave that screen blank.
##   - it comes back on when the book opens.
##   - it stays on through the closing animation. close() drops focused
##     immediately and then plays `return`, so switching off on the flag alone
##     freezes the book mid-close, which is the one moment the player is
##     looking straight at it.
##
## Run with:
##   godot --headless --path . --script tools/test_kollectadex_render_gate.gd

const KOLLECTADEX := "res://lullaby_mod/scripts/lullaby/collectors_shop/kollectadex/kollectadex.gd"
const AREA := "res://lullaby_mod/scripts/lullaby/collectors_shop/areas/focus_area.gd"

var _failures: int = 0
var _checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame

	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var anims := AnimationPlayer.new()
	viewport.add_child(anims)

	var book: Control = Control.new()
	book.set_script(load(KOLLECTADEX))
	book.kollectadex_anims = anims
	# _ready() walks these, so they have to exist even though the gate does
	# not care what is in them.
	book.inputs_container = Control.new()
	# close() reaches for these two without a null guard, and the point of
	# this test is that the real close() is what runs.
	var music := AudioStreamPlayer.new()
	viewport.add_child(music)
	book.music = music
	var area: Node = Area3D.new()
	area.set_script(load(AREA))
	root.add_child(area)
	book.focus_left_area = area
	viewport.add_child(book)
	await process_frame

	_check("al arrancar pinta un frame y se apaga",
		viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"modo %d" % viewport.render_target_update_mode)

	# Godot resolves UPDATE_ONCE to DISABLED after it has drawn.
	await process_frame
	await process_frame

	book.open()
	_check("abrir el libro lo enciende",
		viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"modo %d" % viewport.render_target_update_mode)

	# The real close(), not a simulation of it: it is what drops focused and
	# starts the return animation, and it is where switching the render off
	# too early would live.
	book.close()
	_check("close() no lo apaga de inmediato",
		viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"sigue pintando mientras se cierra")

	anims.animation_finished.emit(&"kollectadex_animations/return")
	_check("y se apaga cuando acaba la animacion de cierre",
		viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"modo %d" % viewport.render_target_update_mode)

	# The same player drives the opening animation, and that one finishing
	# must not switch anything off.
	book.open()
	anims.animation_finished.emit(&"kollectadex_animations/open")
	_check("acabar una animacion con el libro abierto no lo apaga",
		viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS)

	book.inputs_container.free()
	area.queue_free()
	viewport.queue_free()
	await process_frame

	print("")
	if _checks < 5:
		print("FALLO: solo %d de 5 comprobaciones" % _checks)
		quit(1)
		return
	if _failures == 0:
		print("todo OK - el Kollectadex solo se renderiza cuando esta abierto")
	else:
		print("%d fallo(s)" % _failures)
	quit(0 if _failures == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		print("  ok    %-50s%s" % [label, "  (%s)" % detail if detail else ""])
	else:
		_failures += 1
		print("  FALLO %-50s%s" % [label, "  (%s)" % detail if detail else ""])
