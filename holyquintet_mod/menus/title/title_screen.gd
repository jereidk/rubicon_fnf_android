extends Control
## Ports HQTitle.hx: the star-zoom intro (camera zooms/spins into a star,
## the star's glow flashes, a white flash reveals the title), then a title
## idle loop (bopping logo, scrolling "press start" backdrops), then on
## ACCEPT a reverse zoom into a white/black flash before HQMainMenu.
##
## Flixel's FlxG.camera.zoom/angle affects every sprite added to the state
## uniformly; ported here as the scale/rotation of a single "World" Node2D
## (pivoted at screen center, 960,540 in this port's 1920x1080 canvas) that
## every title sprite is nested under, instead of a real Camera2D — scaling
## the content around its own center is visually identical to zooming a
## camera looking at it, without needing a separate viewport.
##
## PressStartBGTxt (a repeating backdrop of the same text bitmap, alpha 0.5,
## FlxBackdrop-tiled) is approximated with a handful of repeated real Label
## copies scrolling together rather than rasterizing FlxText to a texture
## and tiling that — same visual effect, far simpler, and this is a minor
## background decoration under the much more prominent foreground text.
##
## DiscordUtil / FlxG.sound.music.stop() are not ported: no Discord presence
## system exists in this port, and nothing plays music this early in the
## boot chain to stop.

const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

const SCREEN_W := 1920.0
const SCREEN_H := 1080.0
const BGTXT_TEXT := "Press Confirm to Continue"
const BGTXT_GAP := 25.0
const BG_SCROLL_SPEED := 25.0
const MAIN_MENU_SCENE := "res://holyquintet_mod/menus/main/main_menu.tscn"

@onready var world: Node2D = $World
@onready var white_overlay: ColorRect = $World/WhiteOverlay
@onready var press_start_bg: TextureRect = $World/PressStartBG
@onready var press_start_bg_txt: Control = $World/PressStartBGTxt
@onready var star_start: Sprite2D = $World/StarStart
@onready var star_start_glow: Sprite2D = $World/StarStartGlow
@onready var hq_spr: Sprite2D = $World/HqSpr
@onready var bg_logo: Sprite2D = $World/BgLogo
@onready var press_start_txt: Label = $World/PressStartTxt

var _start1: AudioStreamPlayer
var _start2: AudioStreamPlayer
var _menu_music: AudioStreamPlayer

var _can_continue: bool = false
var _transitioning: bool = false
var _bg_txt_labels: Array[Label] = []
var _zoom_tween: Tween


func _ready() -> void:
	_start1 = _make_player("res://holyquintet_mod/source/sounds/ui/ui_start1.ogg")
	_start2 = _make_player("res://holyquintet_mod/source/sounds/ui/ui_start2.ogg")
	_start1.finished.connect(_on_start1_finished)

	_build_bg_txt_labels()

	world.scale = Vector2.ONE
	world.rotation = 0.0

	await get_tree().create_timer(1.0).timeout
	_start_intro()


func _make_player(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	add_child(player)
	return player


func _build_bg_txt_labels() -> void:
	# Enough repeats plus one extra to always cover the screen width while
	# scrolling and wrapping, matching the wide tiling strip below.
	var label_w := 500.0
	var stride := label_w + BGTXT_GAP
	var count := int(ceil(SCREEN_W / stride)) + 2
	for i in count:
		var lbl := Label.new()
		lbl.text = BGTXT_TEXT
		lbl.add_theme_font_size_override("font_size", 32)
		lbl.add_theme_color_override("font_color", Color.BLACK)
		lbl.position = Vector2(-SCREEN_W / 2.0 - stride + i * stride, 0.0)
		lbl.size = Vector2(label_w, 40.0)
		press_start_bg_txt.add_child(lbl)
		_bg_txt_labels.append(lbl)


func _process(delta: float) -> void:
	if press_start_bg.visible:
		var tex_w: float = press_start_bg.texture.get_width()
		press_start_bg.offset_left -= BG_SCROLL_SPEED * delta
		if press_start_bg.offset_left <= -1034.0 - tex_w:
			press_start_bg.offset_left += tex_w
		press_start_bg.offset_right = press_start_bg.offset_left + (1108.0 - -1034.0)

	if press_start_bg_txt.visible:
		var stride: float = 500.0 + BGTXT_GAP
		for lbl in _bg_txt_labels:
			lbl.position.x -= BG_SCROLL_SPEED * delta
			if lbl.position.x <= -SCREEN_W / 2.0 - stride:
				lbl.position.x += stride * _bg_txt_labels.size()


func _unhandled_input(event: InputEvent) -> void:
	if not _can_continue or _transitioning:
		return
	var tapped := event.is_action_pressed("ui_accept")
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	if tapped:
		_transitioning = true
		GenUtil.play_ui_sound(self, "confirm")
		_go_into_menu()


func _start_intro() -> void:
	_start1.play()

	create_tween().tween_property(star_start, "modulate:a", 1.0, 0.20) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var bop := create_tween()
	bop.set_loops()
	bop.tween_property(bg_logo, "position:y", bg_logo.position.y + 5.0, 5.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	bop.tween_property(bg_logo, "position:y", bg_logo.position.y, 5.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	world.scale = Vector2.ONE
	_zoom_tween = create_tween()
	_zoom_tween.tween_interval(0.5)
	_zoom_tween.tween_property(world, "scale", Vector2(6.0, 6.0), 1.75) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_zoom_tween.parallel().tween_property(world, "rotation", deg_to_rad(90.0), 1.75) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)

	var glow_tw := create_tween()
	glow_tw.tween_interval(0.7)
	glow_tw.tween_property(star_start_glow, "modulate:a", 1.0, 2.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if ProjectSettings.get_setting("application/run/flashing", true):
		var flash_tw := create_tween()
		flash_tw.tween_interval(1.85)
		flash_tw.tween_property(white_overlay, "modulate:a", 1.0, 0.35) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)


func _on_start1_finished() -> void:
	_start2.play()

	_menu_music = _make_player("res://holyquintet_mod/source/music/menu.ogg")
	if _menu_music.stream is AudioStreamOggVorbis:
		_menu_music.stream.loop = true
	_menu_music.volume_db = linear_to_db(0.7)
	_menu_music.play()

	_show_title()


func _show_title() -> void:
	hq_spr.visible = true
	bg_logo.visible = true
	world.rotation = 0.0

	press_start_bg.visible = true
	press_start_bg_txt.visible = true

	if ProjectSettings.get_setting("application/run/flashing", true):
		white_overlay.modulate.a = 1.0
		create_tween().tween_property(white_overlay, "modulate:a", 0.0, 0.75) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	star_start.visible = false
	star_start_glow.visible = false

	if _zoom_tween:
		_zoom_tween.kill()
	world.scale = Vector2(1.25, 1.25)
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(world, "scale", Vector2.ONE, 1.5) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_callback(func(): _can_continue = true)

	var txt_tw := create_tween()
	txt_tw.tween_interval(1.5)
	txt_tw.tween_property(press_start_txt, "modulate:a", 1.0, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _go_into_menu() -> void:
	world.scale = Vector2(1.05, 1.05)
	var zoom_tw := create_tween()
	zoom_tw.tween_property(world, "scale", Vector2.ONE, 0.75) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	zoom_tw.tween_callback(func():
		white_overlay.color = Color.BLACK
		white_overlay.modulate.a = 0.0
		create_tween().tween_property(white_overlay, "modulate:a", 1.0, 1.0) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

		var zoom2 := create_tween()
		zoom2.tween_property(world, "scale", Vector2(2.5, 2.5), 1.0) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		zoom2.tween_callback(func(): HQTransition.switch_scene(MAIN_MENU_SCENE))
	)
