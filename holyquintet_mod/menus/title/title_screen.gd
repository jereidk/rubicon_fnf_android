extends Control
## HQ Title screen — star intro, then key art with logo and "press start"

@onready var star: TextureRect = $Star
@onready var glow: TextureRect = $StarGlow
@onready var keyart: TextureRect = $KeyArt
@onready var logo: TextureRect = $Logo
@onready var press_bg: TextureRect = $PressStartBG
@onready var press_txt: Label = $PressStartTxt
@onready var fade_rect: ColorRect = $FadeRect
@onready var music_player: AudioStreamPlayer = $MusicPlayer

var can_continue: bool = false
var transitioning: bool = false
var elapsed: float = 0.0

func _ready() -> void:
	star.modulate.a = 0.0
	glow.modulate.a = 0.0
	keyart.visible = false
	logo.visible = false
	press_bg.visible = false
	press_txt.visible = false
	press_txt.modulate.a = 0.0
	fade_rect.modulate.a = 1.0
	
	# Fade in from black
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_start_intro)

func _start_intro() -> void:
	# Star appears
	var tw = create_tween()
	tw.tween_property(star, "modulate:a", 1.0, 0.2)
	
	# Glow fades in
	var tw2 = create_tween()
	tw2.tween_property(glow, "modulate:a", 1.0, 2.3).set_ease(Tween.EASE_OUT).set_delay(0.7)
	
	# Camera zoom
	var tw3 = create_tween()
	tw3.tween_property(self, "scale", Vector2(6, 6), 1.75).set_ease(Tween.EASE_IN).set_delay(0.5)
	tw3.tween_callback(_show_title)

func _show_title() -> void:
	scale = Vector2.ONE
	star.visible = false
	glow.visible = false
	keyart.visible = true
	logo.visible = true
	press_bg.visible = true
	press_txt.visible = true
	
	# Flash effect
	fade_rect.modulate.a = 1.0
	var tw = create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 0.75).set_ease(Tween.EASE_OUT)
	
	# Zoom settle
	var tw2 = create_tween()
	tw2.tween_property(self, "scale", Vector2(1, 1), 1.5).set_ease(Tween.EASE_OUT).from(Vector2(1.25, 1.25))
	tw2.tween_callback(func(): can_continue = true)
	
	# Press start fade in
	var tw3 = create_tween()
	tw3.tween_property(press_txt, "modulate:a", 1.0, 0.75).set_delay(1.5)
	
	# Music
	if music_player.stream:
		music_player.play()

func _process(_delta: float) -> void:
	if can_continue and not transitioning and Input.is_action_just_pressed("ui_accept"):
		transitioning = true
		# Zoom and fade to main menu
		var tw = create_tween()
		tw.tween_property(fade_rect, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): get_tree().change_scene_to_file("res://holyquintet_mod/menus/main/main_menu.tscn"))
