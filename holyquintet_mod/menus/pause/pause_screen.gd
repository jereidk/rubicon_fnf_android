extends Control
## HQ Pause — port of HQPause.hx for the non-meguca songs.
## Resume / Restart / Settings / Quit over a dad-colored ADD background, drifting
## spots, flipped back, pause character art, song credits panels and scrolling
## banners. Quit destinations follow story/gauntlet/freeplay mode.

const OPTIONS: Array[String] = ["Resume", "Restart", "Settings", "Quit"]
const PAUSE_CHAR_FRAMES := "res://holyquintet_mod/ui/pause_chars/pause_%s_frames.tres"
const MAIN_MENU := "res://holyquintet_mod/menus/main/main_menu.tscn"
const FREE_PLAY := "res://holyquintet_mod/menus/freeplay/freeplay_screen.tscn"
const GAUNTLET := "res://holyquintet_mod/menus/gauntlet/gauntlet_screen.tscn"
const SETTINGS := "res://holyquintet_mod/menus/settings/settings_screen.tscn"
const FONT := "res://holyquintet_mod/source/fonts/shingo.otf"
const META_PATH := "res://holyquintet_mod/source/songs/%s/meta.json"

## dad.iconColor per pause character (HQPause.hx colours its bg with it).
const CHAR_COLORS: Dictionary = {
	"gf": Color("a5004d"),
	"sayaka": Color("72aeda"),
	"madoka": Color("fba8bc"),
	"kyoko": Color("a5395a"),
	"mami": Color("ffed76"),
	"homura": Color("3a3a3a"),
}

const ADD_BLEND := preload("res://holyquintet_mod/menus/pause/pause_blend_add.tres")
const MUL_BLEND := preload("res://holyquintet_mod/menus/pause/pause_blend_mul.tres")
const SCROLL_SHADER := preload("res://holyquintet_mod/menus/pause/pause_scroll_shader.gdshader")
const SCROLL_ADD_SHADER := preload("res://holyquintet_mod/menus/pause/pause_scroll_add_shader.gdshader")

@export var pause_char: String = "gf"

var cur_sel: int = 0
var open_: bool = false
var _leaving: bool = false
var _banner_scroll: float = 0.0
var _spots_scroll: Vector2 = Vector2.ZERO
var _button_positions: Array[Vector2] = []
var _button_tweens: Array[Tween] = []

@onready var bg: ColorRect = $BG
@onready var spots: TextureRect = $Spots
@onready var back: TextureRect = $Back
@onready var top_banner: TextureRect = $TopBanner
@onready var bottom_banner: TextureRect = $BottomBanner
@onready var char_sprite: AnimatedSprite2D = $Char
@onready var buttons: Control = $Buttons
@onready var credits_bottom: TextureRect = $CreditsBottom
@onready var credits_text: Label = $CreditsText
@onready var credits_top: TextureRect = $CreditsTop
@onready var name_label: Label = $NameLabel
@onready var comp_label: Label = $CompLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	bg.material = ADD_BLEND
	spots.material = ADD_BLEND
	back.material = MUL_BLEND
	back.flip_h = true
	top_banner.flip_h = true
	bottom_banner.flip_v = true
	_setup_scroll_materials()
	_setup_char()
	_setup_credits()
	_setup_button_positions()
	_store_base_positions()
	_refresh()


func _process(delta: float) -> void:
	if not open_:
		if Input.is_action_just_pressed("ui_cancel"):
			_open()
		return
	if _leaving:
		return
	_banner_scroll += delta * 5.0
	_spots_scroll += Vector2(15.0, 25.0) * delta
	_apply_scrolls()
	if Input.is_action_just_pressed("ui_up"):
		cur_sel = (cur_sel - 1 + OPTIONS.size()) % OPTIONS.size()
		_refresh()
	elif Input.is_action_just_pressed("ui_down"):
		cur_sel = (cur_sel + 1) % OPTIONS.size()
		_refresh()
	elif Input.is_action_just_pressed("ui_accept"):
		_confirm()
	elif Input.is_action_just_pressed("ui_cancel"):
		_resume()


func _setup_char() -> void:
	var frames_path := PAUSE_CHAR_FRAMES % pause_char
	if ResourceLoader.exists(frames_path):
		var frames: SpriteFrames = load(frames_path)
		char_sprite.sprite_frames = frames
		if frames.has_animation(&"bop"):
			char_sprite.play(&"bop")
	var frame_size := Vector2(865.0, 819.0)
	char_sprite.scale = Vector2(0.9, 0.9)
	var size := frame_size * 0.9
	var viewport := get_viewport().get_visible_rect().size
	char_sprite.position = Vector2((viewport.x - size.x / 2.0) * 0.5, (viewport.y - size.y / 2.0) * 0.25)
	if pause_char == "gf":
		char_sprite.position.y += 125.0


func _setup_scroll_materials() -> void:
	var scroll := ShaderMaterial.new()
	scroll.shader = SCROLL_ADD_SHADER
	scroll.set_shader_parameter("u_tile", 1920.0 / 1311.0)
	scroll.set_shader_parameter("v_tile", 1080.0 / 712.0)
	spots.material = scroll
	var top_mat := ShaderMaterial.new()
	top_mat.shader = SCROLL_SHADER
	top_mat.set_shader_parameter("u_tile", 1920.0 / 30.0)
	top_mat.set_shader_parameter("v_tile", 1.0)
	top_banner.material = top_mat
	var bottom_mat := ShaderMaterial.new()
	bottom_mat.shader = SCROLL_SHADER
	bottom_mat.set_shader_parameter("u_tile", 1920.0 / 30.0)
	bottom_mat.set_shader_parameter("v_tile", 1.0)
	bottom_banner.material = bottom_mat


func _setup_credits() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var song_name := _normalize_song_name(scene.name)
	var meta_path := META_PATH % song_name
	if not FileAccess.file_exists(meta_path):
		return
	var file := FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data: Dictionary = json.data
	var custom: Dictionary = data.get("customValues", {})
	var artists: String = str(custom.get("artists", "Unknown")) + " - Art"
	var coders: String = str(custom.get("coders", "Unknown")) + " - Code"
	var charters: String = str(custom.get("charters", "Unknown")) + " - Chart"
	credits_text.text = "%s\n%s\n%s" % [artists, coders, charters]
	name_label.text = str(data.get("displayName", song_name))
	comp_label.text = str(custom.get("composers", ""))


func _normalize_song_name(raw: String) -> String:
	var lowered := raw.to_lower()
	if lowered == "outoftime":
		return "out-of-time"
	if lowered == "eternalstar":
		return "eternalstar"
	return lowered


func _setup_button_positions() -> void:
	for i in OPTIONS.size():
		var btn: Control = buttons.get_node_or_null("Btn%d" % i)
		if btn == null:
			continue
		_button_positions.append(btn.position)


func _refresh() -> void:
	for i in OPTIONS.size():
		var btn: Control = buttons.get_node_or_null("Btn%d" % i)
		if btn == null:
			continue
		var selected := i == cur_sel
		var sprite: TextureRect = btn.get_node("Sprite")
		var label: Label = btn.get_node("Label")
		var highlight: TextureRect = btn.get_node("Highlight")
		sprite.region_rect = Rect2(0, 139.0 if selected else 0.0, 450.0, 139.0)
		label.add_theme_color_override("font_color", Color.WHITE if selected else Color(0.5, 0.5, 0.5))
		label.add_theme_constant_override("outline_size", 3 if selected else 2)
		if _button_tweens.size() > i and _button_tweens[i] != null and _button_tweens[i].is_valid():
			_button_tweens[i].kill()
		highlight.visible = selected
		if selected:
			highlight.scale = Vector2.ONE
			highlight.modulate.a = 1.0
			var tw := create_tween().set_loops()
			tw.tween_property(highlight, "scale", Vector2(1.05, 1.05), 1.0).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(highlight, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_OUT)
			_ensure_tween_slot(i, tw)


func _ensure_tween_slot(i: int, tw: Tween) -> void:
	while _button_tweens.size() <= i:
		_button_tweens.append(null)
	_button_tweens[i] = tw


func _apply_scrolls() -> void:
	if top_banner.material is ShaderMaterial:
		top_banner.material.set_shader_parameter("u_scroll", (_banner_scroll / 30.0))
	if bottom_banner.material is ShaderMaterial:
		bottom_banner.material.set_shader_parameter("u_scroll", -(_banner_scroll / 30.0))
	if spots.material is ShaderMaterial:
		spots.material.set_shader_parameter("u_scroll", _spots_scroll.x / 1311.0)
		spots.material.set_shader_parameter("v_scroll", _spots_scroll.y / 712.0)


func _open() -> void:
	if open_ or _leaving:
		return
	open_ = true
	cur_sel = 0
	visible = true
	get_tree().paused = true
	# Base layout.
	bg.color = CHAR_COLORS.get(pause_char, Color.BLACK)
	bg.modulate.a = 0.0
	spots.modulate.a = 0.0
	back.modulate.a = 0.0
	back.position.x = -100.0
	top_banner.modulate.a = 0.0
	bottom_banner.modulate.a = 0.0
	credits_bottom.modulate.a = 0.0
	credits_bottom.position.x = _base_x(credits_bottom) + 250.0
	credits_top.modulate.a = 0.0
	credits_top.position.x = _base_x(credits_top) + 250.0
	credits_text.modulate.a = 0.0
	credits_text.position.x = _base_x(credits_text) + 250.0
	name_label.modulate.a = 0.0
	name_label.position.x = _base_x(name_label) + 250.0
	comp_label.modulate.a = 0.0
	comp_label.position.x = _base_x(comp_label) + 250.0
	char_sprite.modulate.a = 0.0
	top_banner.position.y = -101.0
	bottom_banner.position.y = get_viewport().get_visible_rect().size.y
	for i in _button_positions.size():
		var btn: Control = buttons.get_node_or_null("Btn%d" % i)
		if btn != null:
			btn.position = _button_positions[i] + Vector2(-100.0, 0.0)
	_refresh()
	# Fade-in tweens (1s expoOut, mirroring HQPause.hx).
	var tw := create_tween()
	tw.tween_property(bg, "modulate:a", 0.5, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spots, "modulate:a", 0.4, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(back, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(back, "position:x", 0.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(top_banner, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(top_banner, "position:y", 0.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(bottom_banner, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(bottom_banner, "position:y", get_viewport().get_visible_rect().size.y - 101.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(credits_bottom, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(credits_bottom, "position:x", _base_x(credits_bottom), 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(credits_top, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(credits_top, "position:x", _base_x(credits_top), 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(credits_text, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(credits_text, "position:x", _base_x(credits_text), 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(name_label, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(name_label, "position:x", _base_x(name_label), 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(comp_label, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(comp_label, "position:x", _base_x(comp_label), 1.0).set_ease(Tween.EASE_OUT)
	for i in _button_positions.size():
		var btn: Control = buttons.get_node_or_null("Btn%d" % i)
		if btn != null:
			tw.parallel().tween_property(btn, "position", _button_positions[i], 1.0).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		var tw2 := create_tween()
		tw2.tween_property(char_sprite, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(char_sprite, "position:y", char_sprite.position.y - 50.0, 0.3).set_ease(Tween.EASE_OUT)
		tw2.tween_property(char_sprite, "position:y", char_sprite.position.y + 50.0, 0.3).set_ease(Tween.EASE_IN)
	)


func _store_base_positions() -> void:
	for node: Control in [credits_bottom, credits_top, credits_text, name_label, comp_label]:
		if not node.has_meta("hq_pause_base_x"):
			node.set_meta("hq_pause_base_x", node.position.x)


func _base_x(node: Control) -> float:
	return float(node.get_meta("hq_pause_base_x", node.position.x))


func _confirm() -> void:
	if _leaving:
		return
	_leaving = true
	match cur_sel:
		0:
			_resume()
		1:
			HQSaves.death_counter += 1
			get_tree().paused = false
			get_tree().reload_current_scene()
		2:
			get_tree().paused = false
			var scene = get_tree().current_scene
			HQSaves.settings_return_scene = scene.scene_file_path if scene != null else ""
			get_tree().change_scene_to_file(SETTINGS)
		3:
			get_tree().paused = false
			HQSaves.goduka_enabled = false
			HQSaves.goduka_cooldown = -1
			if HQSaves.is_story_mode:
				get_tree().change_scene_to_file(MAIN_MENU)
			elif HQSaves.is_gauntlet_mode:
				get_tree().change_scene_to_file(GAUNTLET)
			else:
				get_tree().change_scene_to_file(FREE_PLAY)


func _resume() -> void:
	open_ = false
	_leaving = false
	visible = false
	get_tree().paused = false
