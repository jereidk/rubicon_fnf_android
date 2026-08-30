extends Node2D
## Story mode's week list.
##
## `animania.states.StoryMenu` is compiled, but the part that decides WHAT this screen shows
## is not: it is `assets/data/levels/*.json`, one file per week, and those are vendored under
## animania_mod/source/data/levels. So the list here is read from data rather than
## transcribed, and adding a week is dropping in its JSON.
##
## Each file gives `name`, `titleAsset`, `songs` and `visible`. `visible: false` means the
## week is not offered - Animania hides `KomiCantCommunicate`, which is the very week this
## port can play - and that flag is respected rather than worked around. What that means in
## practice is on the screen: the weeks it lists are ones whose songs are not built yet, so
## confirming gives the locked sound, the same way freeplay treats dadbattle.
##
## See animania_mod/source/README.md for what is read and tools/animania/PORTING.md for how.

## Where a week's songs live once they are built. Same shape freeplay uses, and the two
## agree on purpose: a song is playable when its scene exists and not before.
const SONG_SCENES := {
	"phone-call": "res://songs/phone-call/phone_call.tscn",
	"tutorial": "res://songs/tutorial/tutorial.tscn",
	"bopeebo": "res://songs/bopeebo/bopeebo.tscn",
	"dadbattle": "res://songs/dadbattle/dadbattle.tscn",
}

const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"

const MENU := "res://animania_mod/menus/main/main_menu.tscn"

## The titles are a vertical list that scrolls under a fixed selection. Placed rather than
## read: StoryMenu is compiled and its layout was not recovered, so this is the classic
## Funkin shape - the chosen week in the middle, the rest above and below it.
const TITLE_CENTRE := Vector2(960.0, 540.0)
const TITLE_SPACING := 180.0
const TITLE_ALPHA_OFF := 0.6

@export var titles: Node2D
@export var sfx: AudioStreamPlayer

var _selected: int = 0
var _confirmed: bool = false


func _ready() -> void:
	_refresh()


## The weeks this screen offers, in the order the builder laid them out. Each carries its
## JSON's `name` and `songs` as metadata so nothing here has to know their names.
func week_count() -> int:
	return titles.get_child_count() if titles != null else 0


func change_week(amount: int, play_sound: bool = true) -> void:
	if _confirmed or amount == 0 or week_count() < 2:
		return
	_selected = wrapi(_selected + amount, 0, week_count())
	_refresh()
	if play_sound:
		_play(SOUND_SWITCH)


func _refresh() -> void:
	for i: int in week_count():
		var title: Node2D = titles.get_child(i)
		title.position = TITLE_CENTRE + Vector2(0.0, TITLE_SPACING * float(i - _selected))
		title.modulate.a = 1.0 if i == _selected else TITLE_ALPHA_OFF


## The week's first song, if it is built. A week whose songs are not ported yet is not
## hidden - it says "not yet", which is the truth and is what freeplay does too.
func confirm() -> void:
	if _confirmed or week_count() == 0:
		return
	var songs: PackedStringArray = titles.get_child(_selected).get_meta(&"songs")
	var scene: String = "" if songs.is_empty() \
		else String(SONG_SCENES.get(songs[0], ""))
	if scene.is_empty() or not ResourceLoader.exists(scene):
		_play(SOUND_LOCKED)
		return

	_confirmed = true
	_play(SOUND_CONFIRM)
	get_tree().change_scene_to_file(scene)


func back() -> void:
	if _confirmed:
		return
	_confirmed = true
	get_tree().change_scene_to_file(MENU)


func _play(path: String) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or not event.is_pressed():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				change_week(-1)
			KEY_DOWN, KEY_S:
				change_week(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				confirm()
			KEY_ESCAPE, KEY_BACKSPACE:
				back()
		return

	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_week(-1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			change_week(1)
		elif button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		_touch((event as InputEventScreenTouch).position)


## On a phone the titles are the controls: a tap on one selects it, and a tap on the one
## already selected goes in.
func _touch(at: Vector2) -> void:
	var hit: int = week_at(at)
	if hit < 0:
		return
	if hit != _selected:
		change_week(hit - _selected)
		return
	confirm()


func week_at(at: Vector2) -> int:
	if titles == null:
		return -1
	for i: int in week_count():
		var title: Node2D = titles.get_child(i)
		if (title.get_meta(&"hitbox") as Rect2).has_point(at - title.position):
			return i
	return -1
