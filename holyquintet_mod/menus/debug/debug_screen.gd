extends Control
## HQ Debug — minimal debug screen. Ports the mod's HQDebug state.
## Z -> Title, X -> Main Menu, Esc -> Main Menu.

var can_control: bool = false
var elapsed: float = 0.0

@onready var debug_label: Label = $DebugLabel
@onready var fade_rect: ColorRect = $FadeRect

func _ready() -> void:
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): can_control = true)

func _process(delta: float) -> void:
	elapsed += delta
	if not can_control:
		return
	if Input.is_action_just_pressed("ui_cancel"):
		_go_main()
	if Input.is_key_pressed(KEY_Z):
		_go_title()
	elif Input.is_key_pressed(KEY_X):
		_go_main()

func _go_title() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/title/title_screen.tscn"))

func _go_main() -> void:
	can_control = false
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))
