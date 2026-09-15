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

func _process(_delta: float) -> void:
	if transitioning:
		return
	if Input.is_action_just_pressed("ui_accept"):
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
	get_tree().change_scene_to_file("res://holyquintet_mod/menus/setup/setup_screen.tscn")
