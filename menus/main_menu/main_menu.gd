extends Control

const TEST_SONG_SCENE := "res://songs/test/test.tscn"
const OPTIONS_SCENE := "res://menus/options/options_menu.tscn"

## Total vertical distance (px) the background drifts from the top item to the bottom
## one — a Control-based stand-in for Psych Engine's menuBG.png + camera-follow
## parallax (there's no world-space camera behind this UI to attach that to).
const BG_PAN_RANGE := 90.0

@onready var test_button: Button = %TestButton
@onready var mods_button: Button = %ModsButton
@onready var options_button: Button = %OptionsButton
@onready var exit_button: Button = %ExitButton
@onready var background_image: TextureRect = %BackgroundImage

var _buttons: Array[Button] = []
var _bg_tween: Tween

func _ready() -> void:
	test_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(TEST_SONG_SCENE))
	mods_button.pressed.connect(Mods.open_menu)
	options_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(OPTIONS_SCENE))
	exit_button.pressed.connect(get_tree().quit)

	_buttons = [test_button, mods_button, options_button, exit_button]
	for i in _buttons.size():
		_buttons[i].focus_entered.connect(_on_item_focused.bind(i))

	test_button.grab_focus()
	_pan_background_to(0, false)

	# This screen has its own "MODS" entry, so the always-on-top corner button (the
	# Mods autoload's stand-in for when there's no main menu) would be redundant here.
	Mods.set_entry_button_visible(false)

func _exit_tree() -> void:
	Mods.set_entry_button_visible(true)

func _on_item_focused(index: int) -> void:
	_pan_background_to(index, true)

func _pan_background_to(index: int, animate: bool) -> void:
	var t := float(index) / float(maxi(_buttons.size() - 1, 1)) # 0..1, top to bottom
	var target_y := lerpf(-BG_PAN_RANGE * 0.5, BG_PAN_RANGE * 0.5, t)

	if _bg_tween != null and _bg_tween.is_valid():
		_bg_tween.kill()

	if not animate:
		background_image.position.y = target_y
		return

	_bg_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_bg_tween.tween_property(background_image, "position:y", target_y, 0.6)
