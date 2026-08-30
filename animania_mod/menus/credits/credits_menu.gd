extends Node2D
## The credits.
##
## `animania.states.CreditsMenu` is compiled, but what it SHOWS is not: `data/credits.json`
## carries all 36 entries with their names, roles, portraits, social links and the typed
## text each one says. That file is vendored, so this list is data and not a transcription.
##
## What is here is the roll: every contributor and what they did, walked and scrolled. What
## is NOT here, and is a deliberate slice rather than an oversight: the portraits (one image
## per person under `menus/credits/pictures/`), the typed-out text with its per-entry speed
## and pitch and its embedded `<img>` tags, the social buttons, and the stickers. Those are
## the screen's character and they want the mod's own bitmap fonts, which this port does not
## have yet. See tools/animania/PORTING.md.

const MENU := "res://animania_mod/menus/main/main_menu.tscn"
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"

## How far the list slides per entry, and where the selected one sits.
const ROW_HEIGHT := 78.0
const LIST_CENTRE := Vector2(560.0, 540.0)
## Funkin's own smoothLerpPrecision, the same half-life shape freeplay's carousel uses.
const SCROLL_HALFLIFE := 0.12

@export var rows: Node2D
@export var sfx: AudioStreamPlayer

var _selected: int = 0
var _leaving: bool = false


func _ready() -> void:
	_refresh(true)


func _process(delta: float) -> void:
	if rows == null:
		return
	var want: float = LIST_CENTRE.y - ROW_HEIGHT * float(_selected)
	rows.position.y = want + (rows.position.y - want) * pow(2.0, -delta / SCROLL_HALFLIFE)


func entry_count() -> int:
	return rows.get_child_count() if rows != null else 0


func change_entry(amount: int, play_sound: bool = true) -> void:
	if _leaving or amount == 0 or entry_count() < 2:
		return
	_selected = wrapi(_selected + amount, 0, entry_count())
	_refresh(false)
	if play_sound:
		_play(SOUND_SWITCH)


func _refresh(snap: bool) -> void:
	for i: int in entry_count():
		(rows.get_child(i) as CanvasItem).modulate.a = 1.0 if i == _selected else 0.45
	if snap and rows != null:
		rows.position.y = LIST_CENTRE.y - ROW_HEIGHT * float(_selected)


func back() -> void:
	if _leaving:
		return
	_leaving = true
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
	if _leaving or not event.is_pressed():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				change_entry(-1)
			KEY_DOWN, KEY_S:
				change_entry(1)
			KEY_ESCAPE, KEY_BACKSPACE, KEY_ENTER, KEY_KP_ENTER:
				back()
		return

	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_entry(-1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			change_entry(1)
		elif button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		_touch((event as InputEventScreenTouch).position)


## On a phone the rows are the controls, like everywhere else in this port: a tap on a row
## selects it. There is nothing to confirm here, so a tap on the selected one does nothing.
func _touch(at: Vector2) -> void:
	var hit: int = entry_at(at)
	if hit >= 0 and hit != _selected:
		change_entry(hit - _selected)


func entry_at(at: Vector2) -> int:
	if rows == null:
		return -1
	var local: Vector2 = at - rows.position
	for i: int in entry_count():
		var row: Node2D = rows.get_child(i)
		if (row.get_meta(&"hitbox") as Rect2).has_point(local - row.position):
			return i
	return -1
