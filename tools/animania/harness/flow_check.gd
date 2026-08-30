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
const STORY := "res://animania_mod/menus/story/story_menu.tscn"
const FREEPLAY := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"
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

	# Story mode is a screen now, and it is built from the mod's own level JSONs: three
	# weeks are offered and KomiCantCommunicate is not, because its file says
	# `visible: false`. The port can only play that hidden one, so every week it DOES list
	# is one whose songs are not built - and it says so rather than pretending.
	var story: PackedScene = load(STORY)
	var story_menu: Node = story.instantiate()
	root.add_child(story_menu)
	await process_frame
	_check(story_menu.week_count() == 3,
		"story tendria que ofrecer 3 semanas y ofrece %d" % story_menu.week_count())
	var first: Node2D = story_menu.titles.get_child(0)
	_check(story_menu.week_at(first.position) == 0,
		"tocar el titulo tendria que dar con la semana")
	# The touch branch itself, called directly - see the note on the pause's below.
	var story_tap := InputEventScreenTouch.new()
	story_tap.pressed = true
	story_tap.position = story_menu.titles.get_child(2).position
	story_menu._unhandled_input(story_tap)
	_check(story_menu._selected == 2,
		"el toque no selecciona en story: sigue en %d" % story_menu._selected)
	story_menu.change_week(-2, false)
	# BASIC RHYTHM is `tutorial`, and tutorial is built now - so story mode leads
	# somewhere. The check moved with it: the first week has to have a playable first song,
	# and the others (DADDY DEAREST, RED SNOW) still must not, because their songs are not
	# built. confirm() is NOT called here - it would change the scene out from under the
	# rest of this walk - and freeplay's own confirm covers that path below.
	var week_playable: Array[bool] = []
	for i: int in story_menu.week_count():
		var songs: PackedStringArray = story_menu.titles.get_child(i).get_meta(&"songs")
		week_playable.append(not songs.is_empty()
			and ResourceLoader.exists(String(story_menu.SONG_SCENES.get(songs[0], ""))))
	# BASIC RHYTHM is tutorial and DADDY DEAREST opens on bopeebo; both are built. RED SNOW
	# is week5 and none of its three songs are.
	_check(week_playable[0], "la primera semana de story tendria que ser jugable ya")
	_check(week_playable[1], "DADDY DEAREST abre con bopeebo y bopeebo ya esta")
	# And that week's song is a real level, not just a file that exists: it comes out of
	# the generic builder, so this is the check that the pipeline produces something
	# playable and not merely something that packs.
	var tutorial: Node = load("res://songs/tutorial/tutorial.tscn").instantiate()
	root.add_child(tutorial)
	await process_frame
	for side: String in ["Opponent", "Player"]:
		var controller: Node = tutorial.get_node("UILayer/UI/%s" % side)
		_check(controller.chart != null, "tutorial: %s sin carta" % side)
		# Four lanes each, or the chart has nothing to draw itself on - which is exactly
		# what the first build of tutorial was.
		_check(controller.get_child_count() >= 4,
			"tutorial: %s tiene %d carriles" % [side, controller.get_child_count()])
	_check(tutorial.get_node_or_null("Stage/Bf") != null
		and tutorial.get_node_or_null("Stage/Gf") != null,
		"tutorial: falta alguien del reparto")
	_check(tutorial.get_node_or_null("PauseMenu") != null,
		"tutorial: sin pausa no se puede salir de la cancion")
	# The wire that makes a character play anything at all. Without it both stand frozen
	# with an empty current_animation - no singing and no idle either.
	for who: String in ["Bf", "Gf"]:
		_check((tutorial.get_node("Stage/%s" % who) as Node2D).level_note_controller != null,
			"tutorial: %s sin level_note_controller, no baila ni canta" % who)
	_check(tutorial.get_node_or_null("SongCamera") != null,
		"tutorial: sin camara de cancion no sigue a quien canta")
	tutorial.queue_free()
	await process_frame
	for i: int in range(2, week_playable.size()):
		_check(not week_playable[i],
			"la semana %d dice ser jugable y sus canciones no estan construidas" % i)
	story_menu.queue_free()
	await process_frame

	# Credits: 36 entries straight out of the mod's own credits.json, and the same touch
	# shape as every other list here.
	var credits: Node = load(
		"res://animania_mod/menus/credits/credits_menu.tscn").instantiate()
	root.add_child(credits)
	await process_frame
	_check(credits.entry_count() == 36,
		"credits tendria que traer 36 entradas y trae %d" % credits.entry_count())
	var row_tap := InputEventScreenTouch.new()
	row_tap.pressed = true
	row_tap.position = credits.rows.position + credits.rows.get_child(3).position
	credits._unhandled_input(row_tap)
	_check(credits._selected == 3,
		"el toque no selecciona en credits: sigue en %d" % credits._selected)
	credits.queue_free()
	await process_frame

	# The walk skips the three blocked buttons rather than stopping on them.
	_check(String(menu.BUTTONS[menu._selected]) == "storymode",
		"el menu no empieza en storymode")

	# startIntroAnimation: the menu is deaf until its camera tween lands, and the curtains
	# still cover the screen while it does.
	# Still opening: somewhere between covering the screen and the band they settle at.
	# This used to assert a threshold picked off one run, which measures how many frames
	# went by rather than what the curtains do - and it started failing the day the walk
	# got a heavier scene to load before it. What matters is that they are en route.
	_check(menu._intro >= 0.0, "el intro del menu ya se acabo antes de mirarlo")
	var open_by: float = -(menu.curtain_up.size.y - menu.INTRO_BAND)
	_check(menu.curtain_up.position.y <= 0.0 and menu.curtain_up.position.y >= open_by,
		"la cortina de arriba esta en %.0f, fuera de [%.0f, 0]"
			% [menu.curtain_up.position.y, open_by])
	_check(menu.curtain_down.position.y >= 0.0
		and menu.curtain_down.position.y <= -open_by,
		"la cortina de abajo esta en %.0f, fuera de [0, %.0f]"
			% [menu.curtain_down.position.y, -open_by])
	menu.change_item(1, false)
	_check(String(menu.BUTTONS[menu._selected]) == "storymode",
		"el menu no tendria que responder durante el intro")
	var intro_until: int = Time.get_ticks_msec() + 1400
	while Time.get_ticks_msec() < intro_until:
		await process_frame
	_check(menu.curtain_up.position.y < -900.0 and menu.curtain_down.position.y > 900.0,
		"las cortinas se quedaron en %.0f y %.0f"
			% [menu.curtain_up.position.y, menu.curtain_down.position.y])
	_check(is_equal_approx(menu.camera.rotation, 0.0)
		and menu.camera.offset.is_zero_approx(),
		"la camara no volvio a su sitio tras el intro")

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

	# startTransitionToMenu runs while the confirm animation does: the curtains close back
	# onto each other, the dude walks off to the left and the camera pulls back out to the
	# three-times zoom it came in at.
	var dude_at: float = menu.dude.position.x
	menu.do_select()
	await process_frame
	_check(menu._exit >= 0.0, "doSelect no arranco la transicion de salida")
	var closing: int = Time.get_ticks_msec() + 700
	while is_instance_valid(menu) and current_scene == menu \
			and Time.get_ticks_msec() < closing:
		await process_frame
	if is_instance_valid(menu) and current_scene == menu:
		_check(menu.curtain_up.position.y > -560.0
			and menu.curtain_down.position.y < 560.0,
			"las cortinas no se cerraron: %.0f y %.0f"
				% [menu.curtain_up.position.y, menu.curtain_down.position.y])
		_check(menu.dude.position.x < dude_at - 700.0,
			"el que baila no se fue: %.0f -> %.0f" % [dude_at, menu.dude.position.x])
		_check(menu.camera.zoom.x > 3.0,
			"la camara no se alejo, esta en %.2f" % menu.camera.zoom.x)

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

	var freeplay: Node = current_scene
	_check(freeplay != null and freeplay != menu, "freeplay no cambio de escena")
	if freeplay == null or freeplay == menu:
		_report()
		return

	# The menu's freeplay button goes to the freeplay SCREEN. It used to go straight into
	# the song while there was no screen to go to.
	_check(String(freeplay.scene_file_path) == FREEPLAY,
		"entro en %s en vez de freeplay" % freeplay.scene_file_path)
	if String(freeplay.scene_file_path) != FREEPLAY:
		_report()
		return

	_check_controls("freeplay", 0)

	# The disks are freeplay's controls on a phone, the way the buttons are the menu's.
	# Found by its `index` meta and NOT by child order: the carousel reorders children so
	# the selected disk draws on top, so once there is more than one song get_child(0) is
	# whichever disk happens to be furthest back.
	var disk: Node2D = null
	for child: Node2D in freeplay.disks.get_children():
		if int(child.get_meta(&"index")) == 0:
			disk = child
	_check(disk != null and freeplay.disk_at(disk.position) == 0,
		"tocar el disco tendria que dar con el disco")
	_check(freeplay.disk_at(Vector2(120.0, 900.0)) == -1,
		"la cama de freeplay no es un disco")

	freeplay.confirm()
	for i: int in 8:
		await process_frame

	var level: Node = current_scene
	_check(level != null and level != freeplay, "el disco no cambio de escena")
	if level == null or level == freeplay:
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

	# The pause menu, which is what makes a song leavable at all. Until it existed the only
	# way out of a song was killing the app.
	var pause: Node = level.get_node("PauseMenu")
	_check(not pause.is_open(), "la pausa no tendria que estar abierta al empezar")
	pause.open()
	await process_frame
	# `paused` is a property of the tree, and this harness IS the tree.
	_check(pause.is_open() and paused, "abrir la pausa tendria que parar el arbol")
	# It has to keep running while everything else is stopped, or nothing could close it.
	_check(pause.process_mode == Node.PROCESS_MODE_WHEN_PAUSED,
		"la pausa se para con el resto y no se podria cerrar")
	# Touch, end to end and not just the hitbox lookup: a real InputEventScreenTouch has to
	# reach the pause and land on an option. The lane hitboxes are the risk here - they sit
	# on the same screen and eat taps - but they stop processing when the tree pauses and
	# the pause menu does not, so the pause is the only thing listening.
	var exit_button: Node2D = pause.buttons.get_child(4)
	_check(pause.option_at(exit_button.position) == 4,
		"tocar exit tendria que dar con exit")
	_check(pause.option_at(Vector2(1700.0, 80.0)) == -1,
		"el fondo de la pausa no es una opcion")
	# The handler is called directly rather than pushed through the viewport: headless runs
	# on the dummy display server and it does not dispatch input, so push_input() proves
	# nothing here (neither a touch nor a click reaches _unhandled_input). What this DOES
	# check is the port's own path - the touch branch, _touch, option_at and the selection.
	# Whether the event arrives at all is the engine's job and only the device can say.
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	tap.position = exit_button.position
	pause._unhandled_input(tap)
	_check(pause._selected == 4,
		"el toque no selecciona en la pausa: sigue en %d" % pause._selected)

	# The walk, while it is open - change_option is deaf when it is not. Back to the top
	# first, since the tap above moved the selection.
	pause.change_option(-pause._selected, false)
	pause.change_option(2, false)
	_check(String(pause.OPTIONS[pause._selected]) == "change_difficulty",
		"la lista de la pausa no camina")
	# A blocked option says "not yet" and stays put instead of going nowhere silently.
	pause.confirm()
	await process_frame
	_check(pause.is_open(), "change_difficulty no tendria que hacer nada todavia")
	# `resume` is the first option, and confirming it closes the pause and lets go.
	pause.change_option(-2, false)
	pause.confirm()
	await process_frame
	_check(not pause.is_open() and not paused, "reanudar tendria que soltar el arbol")

	# And dying leads back into the song. The mod goes through a StickerSubState and there
	# is none here, so the level reloads - which only works when the level IS the running
	# scene, and this is the only place that is true.
	var death: Node = level.get_node("DeathSequence")
	level.get_node("RubiconHealthModule").health = 0.0
	await process_frame
	_check(not level.get_node("MobileControls").visible,
		"al morir los hitboxes siguen puestos")
	death.confirm()
	var wait: int = Time.get_ticks_msec() \
		+ int(death.retry_seconds(death.is_standing()) * 1000.0) + 2500
	while is_instance_valid(level) and current_scene == level \
			and Time.get_ticks_msec() < wait:
		await process_frame
	for i: int in 6:
		await process_frame
	_check(current_scene != null and current_scene != level
		and String(current_scene.scene_file_path) == SONG,
		"el reintento no recargo la cancion: %s" % [current_scene])

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
