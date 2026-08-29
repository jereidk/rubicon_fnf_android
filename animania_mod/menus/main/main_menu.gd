extends Node2D
## The main menu.
##
## `animania.states.MainMenuScreen` is compiled, so unlike the title's intro this is read
## out of the Linux build rather than transcribed. What ships as data, and is therefore
## exact, is the LAYOUT: every button has a `butts/<name>.json` with an id and a rect, and
## the eight animations come out of one Adobe atlas. See animania_mod/source/README.md.

## MainMenuScreen.BUTTONS_LIST, in order. Its array lives in .bss and is filled at runtime,
## so it is read out of the global initialiser for MainMenuScreen.cpp, which writes one
## 16-byte String per entry - length first, pointer second. The lengths alone nearly name
## them (9, 4, 8, 7, 7, 7, 6, 4) and the pointers close it. It matches the ids 0..7 the
## JSONs carry, which is a second source agreeing.
const BUTTONS: PackedStringArray = [
	"storymode", "shop", "freeplay", "website", "options", "credits", "awards", "exit",
]

## MainMenuScreen.BLOCKED_BUTTONS - three names, sharing pointers with BUTTONS_LIST[1], [3]
## and [6]. `button_lock.png` is the art for them. They are SKIPPED by the walk rather than
## merely refused, which is what changeItem's loop over BUTTONS_LIST is doing.
const BLOCKED: PackedStringArray = ["shop", "website", "awards"]

## Which of the eight this port can actually reach. The rest are menus that do not exist
## here yet; a button that leads nowhere is left selectable and does nothing, because
## hiding it would change a layout that is measured.
const DESTINATIONS := {
	"freeplay": "res://songs/phone-call/phone_call.tscn",
}

## `changeItem(amount:Int, playSound:Bool)`. NOT a direction pair, which is what the two
## `Dynamic` parameters first suggested: handleInput passes `Dynamic(-1), Dynamic(true)` on
## one branch and `Dynamic(-FlxG.mouse.wheel), Dynamic(true)` on the other, so the second is
## a bool and the walk is over the LIST, not over the grid the rects draw.
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
## doSelect's own sound, and the one a blocked button gets.
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"

## The confirm animation is 18 frames at 24fps. The transition waits it out.
const CONFIRM_SECONDS := 18.0 / 24.0

@export var buttons: Node2D
@export var sfx: AudioStreamPlayer

var _selected: int = 0
var _confirmed: bool = false


func _ready() -> void:
	_refresh()


## The walk skips blocked buttons rather than stopping on them, and wraps.
func change_item(amount: int, play_sound: bool = true) -> void:
	if _confirmed or amount == 0:
		return
	var step: int = signi(amount)
	var at: int = _selected
	# At most one full lap: if every other button were blocked this would otherwise spin.
	for _i: int in BUTTONS.size():
		at = wrapi(at + step, 0, BUTTONS.size())
		if not BLOCKED.has(BUTTONS[at]):
			break
	if at == _selected:
		return
	_selected = at
	_refresh()
	if play_sound:
		_play(SOUND_SWITCH)


## doSelect: the chosen button plays its `confirm` animation and the menu leaves.
func do_select() -> void:
	if _confirmed:
		return
	var name: String = BUTTONS[_selected]
	if BLOCKED.has(name):
		_play(SOUND_LOCKED)
		return

	_confirmed = true
	_play(SOUND_CONFIRM)
	_animate(name, "confirm")

	if not DESTINATIONS.has(name):
		# Nowhere to go yet. The confirm still plays out, then the menu comes back, so a
		# button that is not ported reads as "not yet" instead of as a freeze.
		await get_tree().create_timer(CONFIRM_SECONDS).timeout
		_confirmed = false
		_refresh()
		return

	await get_tree().create_timer(CONFIRM_SECONDS).timeout
	get_tree().change_scene_to_file(String(DESTINATIONS[name]))


## The selected button shows `white` and every other one `basic`.
func _refresh() -> void:
	for i: int in BUTTONS.size():
		_animate(BUTTONS[i], "white" if i == _selected else "basic")


func _animate(name: String, state: String) -> void:
	if buttons == null:
		return
	var node: Node = buttons.get_node_or_null(NodePath(name.capitalize()))
	if node == null:
		return
	var player: AnimationPlayer = node.get_node_or_null(^"AnimationPlayer")
	if player == null:
		return
	var animation := StringName("menu_buttons_%s_%s" % [name, state])
	if player.has_animation(animation):
		player.play(animation)


func _play(path: String) -> void:
	if sfx == null:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		return
	sfx.stream = stream
	sfx.play()


func _unhandled_input(event: InputEvent) -> void:
	if _confirmed or not event.is_pressed():
		return

	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_UP, KEY_LEFT, KEY_W, KEY_A:
				change_item(-1)
			KEY_DOWN, KEY_RIGHT, KEY_S, KEY_D:
				change_item(1)
			KEY_ENTER, KEY_SPACE, KEY_KP_ENTER:
				do_select()
		return

	# handleInput reads FlxG.mouse.wheel straight into changeItem, negated.
	if event is InputEventMouseButton:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			change_item(-1)
			return
		if button == MOUSE_BUTTON_WHEEL_DOWN:
			change_item(1)
			return
		if button == MOUSE_BUTTON_LEFT:
			_touch((event as InputEventMouseButton).position)
		return

	if event is InputEventScreenTouch:
		_touch((event as InputEventScreenTouch).position)


## On a phone the buttons ARE the controls: there are no lane hitboxes on this screen, and
## the eight rects the mod ships are exactly the areas to aim at.
##
## A tap on a button selects it and confirms it in one go, which is what a tap on a menu
## item means. A tap that lands on nothing does nothing - the background is not a button.
func _touch(at: Vector2) -> void:
	var hit: int = _button_at(at)
	if hit < 0:
		return
	if hit != _selected:
		_selected = hit
		_refresh()
		_play(SOUND_SWITCH)
	do_select()


## Which button's rect contains a point, or -1. The rects are set on the nodes by
## build_main_menu.gd, from the same JSON and the same mapping that place the art.
func _button_at(at: Vector2) -> int:
	if buttons == null:
		return -1
	for i: int in BUTTONS.size():
		var node: Node = buttons.get_node_or_null(NodePath(BUTTONS[i].capitalize()))
		if node == null or not node.has_meta(&"touch_rect"):
			continue
		if (node.get_meta(&"touch_rect") as Rect2).has_point(at):
			return i
	return -1
