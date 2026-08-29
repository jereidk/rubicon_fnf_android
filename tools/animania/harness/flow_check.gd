# Boots the game the way a device does and walks title -> main menu -> song.
#
# The point is the seam: change_scene_to_file replaces the running scene, so a level that
# instantiates fine in a harness can still fail as a scene change. This drives the real
# path.
#
#   godot --headless --path . --script tools/animania/harness/flow_check.gd
extends SceneTree

const TITLE := "res://animania_mod/menus/title/title_screen.tscn"
const MENU := "res://animania_mod/menus/main/main_menu.tscn"
const SONG := "res://songs/phone-call/phone_call.tscn"

var _failures: int = 0


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	printerr("FALLO: %s" % message)
	_failures += 1


func _init() -> void:
	root.call_deferred("set", "disable_3d", true)
	await process_frame
	change_scene_to_file(TITLE)
	await process_frame
	await process_frame

	var title: Node = current_scene
	_check(title != null and title.get_script() != null
		and String(title.get_script().resource_path).ends_with("title_screen.gd"),
		"el juego no arranca en el titulo: %s" % [title])
	if title == null:
		quit(1)
		return

	# The lane hitboxes belong to a SONG and to nothing else. On the title the way in is a
	# tap anywhere, and four hitboxes over the screen only stand between that tap and the
	# title. They used to be an autoload, which put them on every screen in the game.
	_check_controls("el titulo", 0)

	# The intro is skippable, and skipping it is what a player does.
	_check(not title.get_node("Title").visible, "el titulo no tendria que verse aun")
	title._finish()
	await process_frame
	_check(title.get_node("Title").visible, "tras saltar el intro tendria que verse el titulo")

	# The confirm is deliberately deaf for a moment, so the keystroke that skips the intro
	# does not also confirm it.
	var deaf_for: float = title.CONFIRM_DELAY
	title.confirm()
	await process_frame
	_check(current_scene == title,
		"el confirm no tendria que entrar antes de %.2fs" % deaf_for)
	if current_scene != title:
		_report()
		return

	title._elapsed = title._ready_at + 1.0
	title.confirm()
	for i: int in 6:
		await process_frame

	var menu: Node = current_scene
	_check(menu != null and menu != title, "el confirm no cambio de escena")
	if menu == null or menu == title:
		_report()
		return

	# moveToMain goes to the MAIN MENU, which is where the mod sends it. It used to go
	# straight into the song while there was no menu to go to.
	_check(String(menu.scene_file_path) == MENU,
		"entro en %s en vez del menu" % menu.scene_file_path)
	if String(menu.scene_file_path) != MENU:
		_report()
		return

	_check_controls("el menu", 0)

	# On a phone the menu's own buttons are the controls: a tap has to land on a button's
	# own rect, and the background is not one.
	var freeplay_rect: Rect2 = menu.buttons.get_node("Freeplay").get_meta(&"touch_rect")
	_check(menu._button_at(freeplay_rect.get_center()) == 2,
		"tocar el centro de freeplay tendria que dar con freeplay")
	_check(menu._button_at(Vector2(100.0, 540.0)) == -1,
		"el fondo del menu no es un boton")

	# The walk skips the three blocked buttons rather than stopping on them.
	_check(String(menu.BUTTONS[menu._selected]) == "storymode",
		"el menu no empieza en storymode")
	menu.change_item(1, false)
	await process_frame
	_check(String(menu.BUTTONS[menu._selected]) == "freeplay",
		"desde storymode tendria que saltarse shop y caer en freeplay, no en %s"
			% menu.BUTTONS[menu._selected])

	# updateButtonsAnimation drives every idle off ONE clock, so two buttons in the same
	# state show the same frame - including one that has just been switched back to `basic`
	# by the walk above. With each button on its own AnimationPlayer that is exactly what
	# breaks: the restarted one goes back to frame 0 while the rest carry on.
	var was_frame: int = int(menu._button_node("storymode").frame)
	var settle: int = Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < settle:
		await process_frame
	var walked: int = int(menu._button_node("storymode").frame)
	_check(walked == int(menu._button_node("exit").frame),
		"storymode va por el cuadro %d y exit por el %d, tendrian que ir juntos"
			% [walked, menu._button_node("exit").frame])
	# 150ms at 25fps is between three and four frames of a six-frame cycle, so it cannot
	# land back where it started.
	_check(walked != was_frame, "el ciclo de reposo de los botones no avanza")

	menu.do_select()
	# doSelect waits out the 18-frame confirm animation before it leaves, on a SceneTree
	# timer - so this waits in WALL CLOCK. Accumulating get_process_delta_time() does not
	# work here: headless runs frames as fast as it can and the sum outruns the timer.
	var until: int = Time.get_ticks_msec() + 4000
	while is_instance_valid(menu) and current_scene == menu \
			and Time.get_ticks_msec() < until:
		await process_frame
	# change_scene_to_file frees the old scene and installs the new one across frames, so
	# current_scene is briefly neither. Let it land.
	for i: int in 6:
		await process_frame

	var level: Node = current_scene
	_check(level != null and level != menu, "freeplay no cambio de escena")
	if level == null or level == menu:
		_report()
		return

	_check(String(level.scene_file_path) == SONG,
		"entro en %s en vez de la cancion" % level.scene_file_path)
	var clock: Node = level.get_node_or_null("RubiconLevelClock")
	_check(clock != null and clock.animation_player != null
		and clock.animation_player.is_playing(), "la cancion no esta sonando")

	# And it is actually running, not frozen on frame one.
	var was: float = clock.animation_player.current_animation_position
	for i: int in 12:
		await process_frame
	_check(clock.animation_player.current_animation_position > was,
		"el reloj de la cancion no avanza")

	# The touch controls are an AUTOLOAD, and the level scene instances a second copy. The
	# addon has no singleton guard, so both run _setup_buttons and both draw - which stacks
	# their alpha and is why the hitboxes read as opaque on a device however low the
	# opacity is set on either one.
	var controls: Array[Node] = []
	_collect_controls(root, controls)
	_check_controls("la cancion", 1)
	for control: Node in controls:
		_check(is_equal_approx(float(control.opacity), 0.4),
			"los controles tactiles estan a opacity %.2f" % control.opacity)

	_check(root.has_node("DebugOverlay"), "falta el overlay de debug")

	_report()


## How many sets of lane hitboxes are alive right now. The addon has no singleton guard, so
## two of them draw on top of each other and their alpha stacks - which is what made them
## read as a slab on a device however low either one was set.
func _check_controls(where: String, expected: int) -> void:
	var found: Array[Node] = []
	_collect_controls(root, found)
	_check(found.size() == expected,
		"en %s hay %d juegos de hitboxes y tendria que haber %d"
			% [where, found.size(), expected])


func _collect_controls(node: Node, into: Array[Node]) -> void:
	var script: Script = node.get_script()
	if script != null and String(script.resource_path).ends_with(
			"rubicon_mobile_controls.gd"):
		into.append(node)
	for child: Node in node.get_children():
		_collect_controls(child, into)


func _report() -> void:
	print("todo OK" if _failures == 0 else "%d comprobaciones fallaron" % _failures)
	quit(1 if _failures > 0 else 0)
