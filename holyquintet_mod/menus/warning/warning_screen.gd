extends Control
## CNE's built-in WarningState — NOT mod content. The HolyQuintet build has
## Flags.DISABLE_WARNING_SCREEN=false (measured in the exe's Flags static
## initializer at file offset for 0x147abae67, a literal movb $0,... — the
## opposite of upstream CodenameEngine's default of true) and the mod ships
## no data/states/WarningState.hx override, so this generic engine screen
## with its default placeholder text plays before HQSetup.
## Ports funkin.menus.WarningState from CodenameEngine v1.0.1.

@onready var title_label: Label = $TitleLabel
@onready var disclaimer_label: RichTextLabel = $DisclaimerLabel
@onready var flash_rect: ColorRect = $FlashRect
@onready var fade_rect: ColorRect = $FadeRect

var transitioning: bool = false

# Ports WarningState.hx's applyMarkup([*-pair -> 0xFFFF4444 red, #-pair ->
# 0xFFFFFF44 yellow]) which the .tscn's plain-text default still carries as
# literal '*'/'#' markers.
func _ready() -> void:
	disclaimer_label.text = _apply_markup(disclaimer_label.text)

func _apply_markup(text: String) -> String:
	# Yellow (#) must run first: its own replacement inserts '#' characters
	# ([color=#ffff44]), which the same pass would then re-match as markers
	# if it ran after — so red (*), which never emits '#', goes second.
	var yellow := RegEx.new()
	yellow.compile("#(.+?)#")
	text = yellow.sub(text, "[color=#ffff44]$1[/color]", true)

	var red := RegEx.new()
	red.compile("\\*(.+?)\\*")
	text = red.sub(text, "[color=#ff4444]$1[/color]", true)

	return text

func _unhandled_input(event: InputEvent) -> void:
	# Event-driven rather than polling is_action_just_pressed() in _process():
	# established elsewhere in this port as the fix for input silently getting
	# missed under irregular frame pacing. Touch tap is our own Android
	# addition — the real WarningState only has keyboard.
	if transitioning:
		return
	var tapped := event.is_action_pressed("ui_accept")
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	if tapped:
		_confirm()

func _confirm() -> void:
	transitioning = true
	var tw := create_tween()
	tw.tween_property(flash_rect, "modulate:a", 1.0, 0.05)
	tw.tween_property(flash_rect, "modulate:a", 0.0, 0.95)
	tw.tween_property(fade_rect, "modulate:a", 1.0, 2.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(_go_to_title)

func _go_to_title() -> void:
	# CNE: goToTitle() -> FlxG.switchState(new TitleState())
	# TitleState is immediately redirected by the mod's global.hx to HQSetup.
	# Every state switch in the real mod goes through HQTransition (global.hx
	# sets MusicBeatTransition.script to it) — not just the boot chain.
	HQTransition.switch_scene("res://holyquintet_mod/menus/setup/setup_screen.tscn")
