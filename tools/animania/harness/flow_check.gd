# Boots the game the way a device does and walks title -> song.
#
# The point is the seam: change_scene_to_file replaces the running scene, so a level that
# instantiates fine in a harness can still fail as a scene change. This drives the real
# path.
#
#   godot --headless --path . --script tools/animania/harness/flow_check.gd
extends SceneTree

const TITLE := "res://animania_mod/menus/title/title_screen.tscn"
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

	var level: Node = current_scene
	_check(level != null and level != title, "el confirm no cambio de escena")
	if level == null or level == title:
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

	_report()


func _report() -> void:
	print("todo OK" if _failures == 0 else "%d comprobaciones fallaron" % _failures)
	quit(1 if _failures > 0 else 0)
