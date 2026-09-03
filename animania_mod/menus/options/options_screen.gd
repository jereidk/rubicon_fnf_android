extends Node2D
## Options screen — faithful port of animania::states::OptionsScreen.
##
## The hub screen that shows the background, decorative gears, and a list of
## sub-menus (Options, Gameplay, Appearance, Misc, Experemental). Each sub-menu
## is a BaseSubMenu subclass with its own options.

# ─── Constants ─────────────────────────────────────────────────────────────

const MENU := "res://animania_mod/menus/main/main_menu.tscn"
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/animania/options/confirm.ogg"

const SCREEN := Vector2(1920.0, 1080.0)
const ARROWS_PAD := 40.0

## Sub-menu names in order, matching the binary's SUBMENUS array.
const SUBMENUS := ["Options", "Gameplay", "Appearance", "Misc", "Experemental"]

## Title image paths for each sub-menu (loaded from menus/options/eng/).
const TITLE_IMAGES := {
	"Options": "res://animania_mod/source/images/menus/options/eng/options.png",
	"Gameplay": "res://animania_mod/source/images/menus/options/eng/gameplay-title.png",
	"Appearance": "res://animania_mod/source/images/menus/options/eng/appearance-title.png",
	"Misc": "res://animania_mod/source/images/menus/options/eng/misc-title.png",
	"Experemental": "res://animania_mod/source/images/menus/options/eng/experemental-title.png",
}

const EXIT_IMAGE := "res://animania_mod/source/images/menus/options/eng/exit.png"

## Music
const MUSIC_TRACK := "res://animania_mod/source/music/SF_MANIA.ogg"

## Gear animation
const GEAR_FRAMES := 8
const GEAR_FPS := 24.0

# ─── Exports ──────────────────────────────────────────────────────────────

@export var sfx: AudioStreamPlayer

# ─── Fields ───────────────────────────────────────────────────────────────

var bg: Sprite2D
var decorations: Node2D
var gear_main: AnimatedSprite2D
var gear_side: AnimatedSprite2D
var bd_asses: Sprite2D
var social_buttons: Node2D
var sub_menu_container: Node2D
var left_arrow: Sprite2D
var right_arrow: Sprite2D
var current_sub_menu_index: int = 0
var current_sub_menu: Node2D
var is_transitioning: bool = false
var _gear_frames: SpriteFrames

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_scene()
	_create_background()
	_create_decorations()
	_load_music()
	_open_initial_sub_menu()
	do_trans_in()


func _process(_delta: float) -> void:
	pass  # Gear animations are handled by AnimatedSprite2D.play()


func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	if event.is_action_pressed("ui_left"):
		change_sub_menu(-1)
	elif event.is_action_pressed("ui_right"):
		change_sub_menu(1)
	elif event.is_action_pressed("ui_cancel"):
		_exit_to_menu()
	elif event.is_action_pressed("ui_accept"):
		if current_sub_menu and current_sub_menu.has_method("do_selection"):
			current_sub_menu.do_selection()


# ─── Scene building ───────────────────────────────────────────────────────

func _build_scene() -> void:
	bg = Sprite2D.new()
	bg.name = "Bg"
	bg.z_index = -10
	add_child(bg)

	decorations = Node2D.new()
	decorations.name = "Decorations"
	add_child(decorations)

	# Gear main (center)
	gear_main = AnimatedSprite2D.new()
	gear_main.name = "GearMain"
	_load_gear_frames(gear_main)
	gear_main.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	gear_main.modulate.a = 0.15
	decorations.add_child(gear_main)

	# Gear side (right)
	gear_side = AnimatedSprite2D.new()
	gear_side.name = "GearSide"
	_load_gear_side_frames(gear_side)
	gear_side.position = Vector2(SCREEN.x * 0.85, SCREEN.y * 0.5)
	gear_side.modulate.a = 0.1
	decorations.add_child(gear_side)

	# BD asses decoration
	bd_asses = Sprite2D.new()
	bd_asses.name = "BdAsses"
	bd_asses.texture = load("res://animania_mod/source/images/menus/options/bd-asses.png") as Texture2D
	bd_asses.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	bd_asses.modulate.a = 0.3
	decorations.add_child(bd_asses)

	# Social buttons container
	social_buttons = Node2D.new()
	social_buttons.name = "SocialButtons"
	add_child(social_buttons)

	# Sub-menu container
	sub_menu_container = Node2D.new()
	sub_menu_container.name = "SubMenuContainer"
	add_child(sub_menu_container)

	# Left/Right arrows
	left_arrow = Sprite2D.new()
	left_arrow.name = "LeftArrow"
	left_arrow.position = Vector2(ARROWS_PAD, SCREEN.y * 0.5)
	left_arrow.modulate.a = 0.6
	add_child(left_arrow)

	right_arrow = Sprite2D.new()
	right_arrow.name = "RightArrow"
	right_arrow.position = Vector2(SCREEN.x - ARROWS_PAD, SCREEN.y * 0.5)
	right_arrow.modulate.a = 0.6
	add_child(right_arrow)


# ─── createBackground ─────────────────────────────────────────────────────

func _create_background() -> void:
	bg.texture = load("res://animania_mod/source/images/menus/options/bg.png") as Texture2D
	bg.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)


# ─── createDecorations ────────────────────────────────────────────────────

func _create_decorations() -> void:
	if gear_main:
		gear_main.play()
	if gear_side:
		gear_side.play()


# ─── Gear frame loading ───────────────────────────────────────────────────

func _load_gear_frames(sprite: AnimatedSprite2D) -> void:
	var sf := SpriteFrames.new()
	sf.add_animation(&"spin")
	var atlas_tex := load("res://animania_mod/source/images/menus/options/gear.png") as Texture2D
	if atlas_tex == null:
		return
	var xml_path := "res://animania_mod/source/images/menus/options/gear.xml"
	var xml := _parse_adobe_atlas(xml_path)
	for frame_data in xml:
		var region := Rect2(frame_data["x"], frame_data["y"], frame_data["w"], frame_data["h"])
		var atlas := AtlasTexture.new()
		atlas.atlas = atlas_tex
		atlas.region = region
		sf.add_frame(&"spin", atlas)
	sprite.sprite_frames = sf
	sprite.animation = &"spin"
	sprite.speed_scale = 0.6


func _load_gear_side_frames(sprite: AnimatedSprite2D) -> void:
	var sf := SpriteFrames.new()
	sf.add_animation(&"spin")
	var atlas_tex := load("res://animania_mod/source/images/menus/options/gearSide.png") as Texture2D
	if atlas_tex == null:
		return
	var xml_path := "res://animania_mod/source/images/menus/options/gearSide.xml"
	var xml := _parse_adobe_atlas(xml_path)
	for frame_data in xml:
		var region := Rect2(frame_data["x"], frame_data["y"], frame_data["w"], frame_data["h"])
		var atlas := AtlasTexture.new()
		atlas.atlas = atlas_tex
		atlas.region = region
		sf.add_frame(&"spin", atlas)
	sprite.sprite_frames = sf
	sprite.animation = &"spin"
	sprite.speed_scale = 0.5


func _parse_adobe_atlas(path: String) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	var xml_text := FileAccess.get_file_as_string(path)
	if xml_text.is_empty():
		return frames
	var parser := XMLParser.new()
	parser.open_buffer(xml_text.to_utf8_buffer())
	while parser.read() != ERR_FILE_EOF:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			if parser.get_node_name() == "SubTexture":
				var frame := {}
				for i in range(parser.get_attribute_count()):
					var attr_name := parser.get_attribute_name(i)
					frame[attr_name] = parser.get_attribute_value(i)
				if frame.has("x") and frame.has("y") and frame.has("width") and frame.has("height"):
					frames.append({
						"x": float(frame.get("x", "0")),
						"y": float(frame.get("y", "0")),
						"w": float(frame.get("width", "0")),
						"h": float(frame.get("height", "0")),
					})
	return frames


# ─── Music ────────────────────────────────────────────────────────────────

func _load_music() -> void:
	# SF_MANIA is the background music for options
	if sfx != null:
		var stream := load(MUSIC_TRACK) as AudioStream
		if stream:
			sfx.stream = stream
			sfx.play()


# ─── Sub-menu navigation ──────────────────────────────────────────────────

func _open_initial_sub_menu() -> void:
	change_sub_menu(0, true)


func change_sub_menu(amount: int, _instant: bool = false) -> void:
	if is_transitioning:
		return

	var old_index := current_sub_menu_index
	current_sub_menu_index = clampi(current_sub_menu_index + amount, 0, SUBMENUS.size() - 1)
	if current_sub_menu_index == old_index and not _instant:
		return

	open_new_sub_menu(SUBMENUS[current_sub_menu_index])


func open_new_sub_menu(sub_menu_name: String) -> void:
	is_transitioning = true

	# Remove old sub-menu
	if current_sub_menu != null:
		var old := current_sub_menu
		current_sub_menu = null
		var tw := create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.15)
		tw.tween_callback(old.queue_free)

	# Create new sub-menu
	match sub_menu_name:
		"Options":
			current_sub_menu = _create_options_sub_menu()
		"Gameplay":
			current_sub_menu = _create_gameplay_sub_menu()
		"Appearance":
			current_sub_menu = _create_appearance_sub_menu()
		"Misc":
			current_sub_menu = _create_misc_sub_menu()
		"Experemental":
			current_sub_menu = _create_experemental_sub_menu()

	if current_sub_menu != null:
		current_sub_menu.modulate.a = 0.0
		sub_menu_container.add_child(current_sub_menu)
		var tw := create_tween()
		tw.tween_property(current_sub_menu, "modulate:a", 1.0, 0.15)
		tw.tween_callback(func() -> void: is_transitioning = false)

	_play(SOUND_SWITCH)


# ─── Sub-menu creation ────────────────────────────────────────────────────

func _create_options_sub_menu() -> Node2D:
	var sub := OptionsSubMenu.new()
	sub.options_screen = self
	return sub


func _create_gameplay_sub_menu() -> Node2D:
	var sub := GameplaySubMenu.new()
	sub.options_screen = self
	return sub


func _create_appearance_sub_menu() -> Node2D:
	var sub := AppearanceSubMenu.new()
	sub.options_screen = self
	return sub


func _create_misc_sub_menu() -> Node2D:
	var sub := MiscSubMenu.new()
	sub.options_screen = self
	return sub


func _create_experemental_sub_menu() -> Node2D:
	var sub := ExperementalSubMenu.new()
	sub.options_screen = self
	return sub


# ─── doTransIn ────────────────────────────────────────────────────────────

func do_trans_in() -> void:
	# Fade in the whole screen
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)


# ─── Exit ─────────────────────────────────────────────────────────────────

func _exit_to_menu() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_play(SOUND_CONFIRM)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(MENU))


# ─── Helpers ──────────────────────────────────────────────────────────────

func _play(path: String) -> void:
	if sfx != null and ResourceLoader.exists(path):
		sfx.stream = load(path) as AudioStream
		sfx.play()
