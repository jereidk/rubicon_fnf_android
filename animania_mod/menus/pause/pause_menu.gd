extends CanvasLayer
## The pause menu.
##
## Until this existed a song could not be left: once you were in, the only way out was
## killing the app. On a phone that is a functional hole, not a missing nicety.
##
## The art is the mod's - `menus/pause/menuleft`, `lightcircle`, `skull` and one sparrow
## atlas per option under `buttons/eng/`, each with a `<name> basic` and a `<name> white`
## frame, the same idle/selected convention the main menu's buttons use. The music is
## `breakfast-phonecall`, which is what this song's pause plays.
##
## What is NOT read from the mod is the layout: `PauseSubState` is base Funkin and the
## mod's own subclass is compiled, and neither was recovered. The panel and the list are
## placed against the art's own sizes and marked as such. See tools/animania/PORTING.md.

## The options, in the order the mod's own button folder gives them. `change_difficulty`
## and `options` have art but nowhere to go in this port, so they say "not yet" the same way
## a freeplay disk without a scene does.
const OPTIONS: PackedStringArray = [
	"resume", "restart", "change_difficulty", "options", "exit",
]
const BLOCKED: PackedStringArray = ["change_difficulty", "options"]

const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"

## Where "exit" goes. Freeplay, because that is where the song was chosen.
const FREEPLAY := "res://animania_mod/menus/freeplay/freeplay_screen.tscn"

@export var dim: ColorRect
@export var buttons: Node2D
@export var sfx: AudioStreamPlayer
@export var music: AudioStreamPlayer

var _selected: int = 0
var _leaving: bool = false


func _ready() -> void:
	# The whole point: this layer keeps running while the tree is paused, and nothing else
	# does - which is what stops the chart, the notes, the characters and the song's audio
	# in one move instead of five.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	if visible or _leaving:
		return
	visible = true
	_selected = 0
	_refresh()
	get_tree().paused = true
	if music != null:
		music.play()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = false
	if music != null:
		music.stop()


func change_option(amount: int, play_sound: bool = true) -> void:
	if not visible or _leaving or amount == 0:
		return
	_selected = wrapi(_selected + amount, 0, OPTIONS.size())
	_refresh()
	if play_sound:
		_play(SOUND_SWITCH)


## The selected option shows `white` and the rest `basic`, which is the pair each atlas
## ships and the same convention the main menu's buttons use.
func _refresh() -> void:
	for i: int in buttons.get_child_count():
		var button: AnimatedSprite2D = buttons.get_child(i)
		var want := StringName(
			"%s white" % button.get_meta(&"prefix") if i == _selected
			else "%s basic" % button.get_meta(&"prefix"))
		if button.sprite_frames.has_animation(want):
			button.animation = want


func confirm() -> void:
	if not visible or _leaving:
		return
	var option: String = OPTIONS[_selected]
	if BLOCKED.has(option):
		_play(SOUND_LOCKED)
		return

	_play(SOUND_CONFIRM)
	match option:
		"resume":
			close()
		"restart":
			_leaving = true
			# Apply blur transition like Animania
			if MusicFilter.instance:
				MusicFilter.instance.apply_song_end_filter(0.2)
			get_tree().paused = false
			await get_tree().create_timer(0.1).timeout
			get_tree().reload_current_scene()
		"exit":
			_leaving = true
			# Apply blur + filter transition like Animania
			if MusicFilter.instance:
				MusicFilter.instance.apply_song_end_filter(0.3)
			get_tree().paused = false
			# Small delay for the filter to take effect
			await get_tree().create_timer(0.15).timeout
			get_tree().change_scene_to_file(FREEPLAY)


func _play(path: String) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()


func _notification(what: int) -> void:
	# Android's back button: it opens the pause, and closes it again if it is already up.
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or not event.is_pressed():
		return

	if event is InputEventKey:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			close() if visible else open()
			return
		if not visible:
			return
		match key:
			KEY_UP, KEY_W:
				change_option(-1)
			KEY_DOWN, KEY_S:
				change_option(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				confirm()
		return

	if not visible:
		return
	if event is InputEventScreenTouch:
		_touch((event as InputEventScreenTouch).position)
	elif event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_touch((event as InputEventMouseButton).position)


## On a phone the options are the controls, the same as everywhere else in this port: a tap
## on one selects it, a tap on the selected one goes in.
func _touch(at: Vector2) -> void:
	var hit: int = option_at(at)
	if hit < 0:
		return
	if hit != _selected:
		change_option(hit - _selected)
		return
	confirm()


func option_at(at: Vector2) -> int:
	if buttons == null:
		return -1
	for i: int in buttons.get_child_count():
		var button: Node2D = buttons.get_child(i)
		if (button.get_meta(&"hitbox") as Rect2).has_point(at - button.position):
			return i
	return -1
