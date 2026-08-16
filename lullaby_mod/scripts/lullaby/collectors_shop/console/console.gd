class_name Console
extends Control

signal boot_finished
signal play_sound(filename: String)

static var boot_enabled: bool = false:
	set(v):
		if boot_enabled != v:
			boot_enabled = v
			SaveData.set_flag(&"console_on", v)
			SaveData.save()

static var has_booted: bool = false

@export var shop: CollectorShop
@export var tab_container: TabContainer
@export var startup_sound: AudioStreamPlayer
@export var other_sounds: AudioStreamPlayer

@export var background_anim: AnimationPlayer
@export var sequences: ShopSequences

@onready var main_animation_player: AnimationPlayer
@onready var music: AudioStreamPlayer = %Music
@onready var music_fader: AnimationPlayer = %MusicFader

@export var focus_right_area: FocusArea3D

var in_submenu: bool = false

## Process frame of the last accepted back_out(), so a single press cannot
## step out two levels. See back_out().
var _last_back_frame: int = -1
var backout_focus: Button

var in_home: bool
var time: float = 0.0
var booting: bool = false
var focused: bool = false


func _ready() -> void :
	main_animation_player = $AnimationPlayer
	boot(false)

	if background_anim:
		background_anim.animation_finished.connect(_on_background_anim_finished)

	other_sounds.volume_linear = 0.0
	music.volume_linear = 0.0


## Boot ends when the animation has passed 13.34s OR has stopped.
##
## It used to require both booting and is_playing() and the position being
## past 13.34, which means the flag can only clear on a frame that lands
## inside that window. Any frame that steps over the end of the animation
## skips it, and this project has frames that are seconds long - the device
## log measured 11,489ms on one - so the window is genuinely missable.
##
## Nothing clears it afterwards. booting has one writer outside this file,
## power_console.gd setting it true, so once the window is missed it stays
## true for the life of the scene, and it is checked by back_out(),
## home_button, gallery_button and cartridges_enter_label - the whole console
## stops responding, not just Back. The last device log has 22 consecutive
## ui_cancel presses with the console focused and nothing happening, which is
## what that looks like from the player's side.
##
## Adding "or it stopped playing" makes the exit unmissable: an animation that
## reaches its end is finished by definition, and one that is interrupted has
## no other chance to say so.
func _process(_delta: float) -> void :
	if not booting:
		return
	var past_boot: bool = (main_animation_player.is_playing()
			and main_animation_player.current_animation_position >= 13.34)
	if past_boot or not main_animation_player.is_playing():
		booting = false
		boot_finished.emit()


func _input(event: InputEvent) -> void :
	if event.is_action_pressed(&"ui_cancel"):
		back_out()


func back_out() -> void :
	if not focused:
		return
	if booting:
		return

	# One level per frame. ui_cancel can reach here from more than one place
	# at once - the on-screen Back button dispatches a synthetic
	# InputEventAction, and native_back_button_handler.gd dispatches the same
	# action on Android's hardware Back - and two in one frame would step out
	# two levels, e.g. straight past the category list to the Home tab.
	#
	# Insurance rather than a diagnosis: the reported "one press, two levels"
	# is most likely the freeze fixed below, which delayed the first press's
	# result long enough to invite a second. This costs nothing either way.
	var frame: int = Engine.get_process_frames()
	if frame == _last_back_frame:
		return
	_last_back_frame = frame

	play_sound.emit("sfx_soulroom_back")

	if in_submenu:
		in_submenu = false
		backout_focus.grab_focus()
		# save() only. The apply_settings() that used to sit here was a
		# redundant full re-apply and it is what froze the console for about
		# a second every time you left a category: it rebuilds every viewport
		# setting, erases and re-adds every InputMap action, and runs
		# _apply_shader_effects_setting(), which on Very Low walks the whole
		# scene tree - and the Collector's Shop tree is enormous.
		#
		# Nothing is left unapplied without it. Every settings row applies its
		# own change the moment it is made: list_button.gd:35/48,
		# toggle_button.gd:26, incremental_button.gd:38, input_button.gd:31
		# and quality_preset_button.gd:99 all call apply_settings() directly,
		# and the rows that do not (check_box.gd is only the tick's
		# animation, window_mode_button.gd defers to ListButton via super)
		# never mutate a setting themselves. quality_preset_button.gd's own
		# comment already called this "the only other apply_settings() caller
		# here", which is exactly the redundancy.
		Settings.save()
	else:
		if tab_container.current_tab == 0 and sequences:
			music_fader.play(&"fade_out")
			sequences.animation_player.play(&"focus_right")
			focus_right_area.can_interact = true
			focus_right_area.register_trigger()

			# Whichever Home icon has GUI focus (grabbed via
			# ConsoleTab.default_focus/focus_console.gd when the console
			# opened) never gets a _focus_exited() call otherwise, since
			# leaving the console just pans the camera away instead of
			# removing the Control from the tree - so its own `focused`
			# tracking bool (see ConsoleHomeButton) would stay stuck true
			# forever, e.g. leaving the touch overlay's "F / Switch
			# Cartridge" button's visibility gated only by console.focused
			# instead of both conditions actually being false as intended.
			get_viewport().gui_release_focus()
			focused = false
		else:
			tab_container.change_tab(0)


func boot(with_intro: bool) -> void :
	if with_intro:
		main_animation_player.play(&"RESET")
		main_animation_player.seek(0.0, true)
		main_animation_player.play(&"collector intro")
		main_animation_player.seek(0.0, true)
	else:
		startup_sound.volume_linear = 0.0

		main_animation_player.play(&"bg_startup")
		main_animation_player.seek(13.43, true)

		background_anim.play(&"Scene")
		background_anim.seek(13.43, true)
		background_anim.queue(&"loop")


func _on_background_anim_finished(anim_name: StringName) -> void :
	if anim_name == &"Scene":
		background_anim.play(&"loop")
