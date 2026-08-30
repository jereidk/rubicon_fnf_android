extends Node2D
## Freeplay.
##
## `animania.states.FreeplayScreen` is compiled, so this is read out of the Linux build the
## way the main menu was. It is a big screen there - a TV diorama, a disk carousel, an album
## roll, difficulty sprites, stickers, a rank panel, a skin selector and a help page - and
## what is here is the diorama and the carousel. See animania_mod/source/README.md for what
## was read and what is deliberately left.
##
## The port has one song, so the list has one entry. Everything about the walk is written
## against a list rather than against that one entry, because the day a second song is
## charted is the day this has to keep working without being rewritten.

## The disks are `animania-freeplay/disks/<name>`, loaded by DiskSpr.changeDisk from the
## song's own id. `phone call.png` is the one the port has art for.
const SONGS: Array[Dictionary] = [
	{
		"id": "phone-call",
		"disk": "phone call",
		"scene": "res://songs/phone-call/phone_call.tscn",
	},
]

## changeSelection plays `freeplay/song switch` through FunkinSound.playOnce at 0.4.
const SOUND_SWITCH := "res://animania_mod/source/sounds/freeplay/song switch.ogg"
const SWITCH_VOLUME := 0.4
## doSelect's, and the one a locked disk gets.
const SOUND_CONFIRM := "res://animania_mod/source/sounds/freeplay/diskConfirm.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/freeplay/diskLocked.ogg"

## Where BACK goes. The mod goes back to the main menu and so does this.
const MENU := "res://animania_mod/menus/main/main_menu.tscn"

## DiskSpr.updateDiskPos does not move a disk to its place, it eases:
##
##     x = MathUtil.smoothLerpPrecision(x, target.x, elapsed, 0.256)
##     y = MathUtil.smoothLerpPrecision(y, target.y, elapsed, 0.192)
##
## Funkin's smoothLerpPrecision(from, to, dt, halfLife) is
## `to + (from - to) * pow(2, -dt / halfLife)` - a half-life in seconds, so the y trails the
## x by a quarter and the carousel arrives with a slight roll rather than square.
const DISK_HALFLIFE_X := 0.256
const DISK_HALFLIFE_Y := 0.192

## Where the selected disk sits and how far apart the rest are, in this project's pixels.
## NOT the mod's: DiskSpr eases toward a point another object owns, and what writes that
## point is not recovered. These were placed by looking at the diorama.
const DISK_CENTRE := Vector2(1390.0, 560.0)
const DISK_SPACING := Vector2(0.0, 210.0)
## The unselected disks are smaller and dimmer, which is what the carousel reads as.
const DISK_SCALE_ON := 1.0
const DISK_SCALE_OFF := 0.72
const DISK_ALPHA_OFF := 0.55

@export var disks: Node2D
@export var sfx: AudioStreamPlayer
@export var bed: AnimatedSprite2D

var _selected: int = 0
var _confirmed: bool = false


func _ready() -> void:
	_refresh(true)


func _process(delta: float) -> void:
	for i: int in disks.get_child_count():
		var disk: Node2D = disks.get_child(i)
		var target: Vector2 = disk.get_meta(&"target") as Vector2
		disk.position = Vector2(
			_ease(disk.position.x, target.x, delta, DISK_HALFLIFE_X),
			_ease(disk.position.y, target.y, delta, DISK_HALFLIFE_Y))
		var wants: float = float(disk.get_meta(&"scale"))
		var at: float = _ease(disk.scale.x, wants, delta, DISK_HALFLIFE_X)
		disk.scale = Vector2(at, at)
		disk.modulate.a = _ease(
			disk.modulate.a, float(disk.get_meta(&"alpha")), delta, DISK_HALFLIFE_X)


## MathUtil.smoothLerpPrecision, which is a half-life and not a rate: the fraction left
## after `half` seconds is a half, whatever the frame rate is.
func _ease(from: float, to: float, delta: float, half: float) -> float:
	return to + (from - to) * pow(2.0, -delta / half)


## changeSelection. FlxMath.wrap, so it goes round rather than stopping at the ends.
func change_selection(amount: int, play_sound: bool = true) -> void:
	if _confirmed or SONGS.size() < 2:
		return
	_selected = wrapi(_selected + amount, 0, SONGS.size())
	_refresh(false)
	if play_sound:
		_play(SOUND_SWITCH, SWITCH_VOLUME)


## Where each disk is heading and how it should look getting there. The positions are set as
## targets rather than written straight, so _process eases into them.
func _refresh(snap: bool) -> void:
	for i: int in disks.get_child_count():
		var disk: Node2D = disks.get_child(i)
		var away: int = i - _selected
		var chosen: bool = away == 0
		disk.set_meta(&"target", DISK_CENTRE + DISK_SPACING * float(away))
		disk.set_meta(&"scale", DISK_SCALE_ON if chosen else DISK_SCALE_OFF)
		disk.set_meta(&"alpha", 1.0 if chosen else DISK_ALPHA_OFF)
		# The bottom disk draws over the one above it, and the selected one over both.
		disks.move_child(disk, disk.get_index())
		if not snap:
			continue
		disk.position = disk.get_meta(&"target") as Vector2
		var at: float = float(disk.get_meta(&"scale"))
		disk.scale = Vector2(at, at)
		disk.modulate.a = float(disk.get_meta(&"alpha"))
	if disks.get_child_count() > _selected:
		disks.move_child(disks.get_child(_selected), disks.get_child_count() - 1)


func confirm() -> void:
	if _confirmed:
		return
	var song: Dictionary = SONGS[_selected]
	if not ResourceLoader.exists(String(song["scene"])):
		_play(SOUND_LOCKED, 1.0)
		return

	_confirmed = true
	_play(SOUND_CONFIRM, 1.0)
	get_tree().change_scene_to_file(String(song["scene"]))


func back() -> void:
	if _confirmed:
		return
	_confirmed = true
	get_tree().change_scene_to_file(MENU)


func _play(path: String, volume: float) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.volume_db = linear_to_db(volume)
	sfx.play()


func _notification(what: int) -> void:
	# Android's own back button, which is the gesture a player reaches for first.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or not event.is_pressed():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_W:
				change_selection(-1)
			KEY_DOWN, KEY_S:
				change_selection(1)
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				confirm()
			KEY_ESCAPE, KEY_BACKSPACE:
				back()
		return

	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_selection(-1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			change_selection(1)
		elif button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		_touch((event as InputEventScreenTouch).position)


## On a phone the disks are the controls: a tap on one selects it, and a tap on the one
## already selected goes in. A tap that lands on nothing does nothing.
func _touch(at: Vector2) -> void:
	var hit: int = disk_at(at)
	if hit < 0:
		return
	if hit != _selected:
		change_selection(hit - _selected)
		return
	confirm()


func disk_at(at: Vector2) -> int:
	if disks == null:
		return -1
	# Back to front, so the disk drawn on top is the one a tap in an overlap lands on.
	for i: int in range(disks.get_child_count() - 1, -1, -1):
		var disk: Node2D = disks.get_child(i)
		if (disk.get_meta(&"hitbox") as Rect2).has_point(at - disk.position):
			return int(disk.get_meta(&"index"))
	return -1
