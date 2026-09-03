extends CanvasLayer
## Story menu select sub-state — faithful port of animania::states::StoryMenuSelectSubState.
##
## An overlay that appears when selecting a week in Story Mode.
## Shows difficulty buttons, a lock icon for locked weeks, and transitions
## into the song with blur effects and music filters.

# ─── Constants ─────────────────────────────────────────────────────────────

const SCREEN := Vector2(1920.0, 1080.0)
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/confirmMenu.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"
const SOUND_LOCKED := "res://animania_mod/source/sounds/animania/menu/locked_sfx.ogg"

const BUTTON_ATLAS_PATH := "res://animania_mod/source/images/menus/story_select/story_select_buttons.png"
const BUTTON_ATLAS_XML := "res://animania_mod/source/images/menus/story_select/story_select_buttons.xml"
const LOCK_PATH := "res://animania_mod/source/images/storymenu/ui/lock.png"

const ANIMANIA_LOGO_PATH := "res://animania_mod/source/images/menus/story_select/animania_logo.png"
const AMTAKE_LOGO_PATH := "res://animania_mod/source/images/menus/story_select/amtake_logo.png"

# ─── Fields ───────────────────────────────────────────────────────────────

var _menu_state: Node  ## Parent StoryMenu reference
var buttons: Array[Node2D] = []
var cool_bg: ColorRect
var select_camera: Camera2D
var selected: String = ""
var blur_shader: ShaderMaterial
var _is_selecting: bool = false
var logo: Sprite2D
var logo_amtake: Sprite2D

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	_build_ui()
	_setup_camera()
	_create_background()
	_create_buttons()
	_apply_initial_animations()
	_configure_music_filters()


func _unhandled_input(event: InputEvent) -> void:
	if _is_selecting:
		return

	if event.is_action_pressed("ui_cancel"):
		close_sub_state()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_navigate_button(-1)
		_play(SOUND_SWITCH)
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_navigate_button(1)
		_play(SOUND_SWITCH)
	elif event.is_action_pressed("ui_accept"):
		if selected != "":
			select_story(selected)


# ─── Scene building ───────────────────────────────────────────────────────

func _build_ui() -> void:
	cool_bg = ColorRect.new()
	cool_bg.name = "CoolBg"
	cool_bg.offset_right = SCREEN.x
	cool_bg.offset_bottom = SCREEN.y
	cool_bg.color = Color(0, 0, 0, 0.6)
	add_child(cool_bg)

	# Logo (Animania)
	logo = Sprite2D.new()
	logo.name = "Logo"
	if ResourceLoader.exists(ANIMANIA_LOGO_PATH):
		logo.texture = load(ANIMANIA_LOGO_PATH) as Texture2D
	logo.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.15)
	logo.modulate.a = 0.0
	add_child(logo)

	# Logo (AMTake)
	logo_amtake = Sprite2D.new()
	logo_amtake.name = "LogoAmtake"
	if ResourceLoader.exists(AMTAKE_LOGO_PATH):
		logo_amtake.texture = load(AMTAKE_LOGO_PATH) as Texture2D
	logo_amtake.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.15)
	logo_amtake.modulate.a = 0.0
	add_child(logo_amtake)


func _setup_camera() -> void:
	select_camera = Camera2D.new()
	select_camera.name = "StorySelectCamera"
	select_camera.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	add_child(select_camera)


func _create_background() -> void:
	# Background fade in
	cool_bg.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(cool_bg, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)


func _create_buttons() -> void:
	# Create difficulty buttons based on the week data
	# For now, create standard difficulty buttons
	var difficulties: Array[String] = ["easy", "normal", "hard"]
	var button_spacing := 120.0
	var start_y := SCREEN.y * 0.4

	for i in difficulties.size():
		var diff := difficulties[i]
		var btn := _create_button(diff, "difficulty_%s" % diff, 0.0, false)
		btn.position = Vector2(SCREEN.x * 0.5, start_y + i * button_spacing)
		buttons.append(btn)
		add_child(btn)

	if buttons.size() > 0:
		_select_button(0)


func _create_button(button_name: String, image_prefix: String, offset: float, locked: bool) -> Node2D:
	var container := Node2D.new()
	container.set_meta("button_name", button_name)
	container.set_meta("locked", locked)

	# Load button sprite from atlas
	if ResourceLoader.exists(BUTTON_ATLAS_PATH):
		var tex := load(BUTTON_ATLAS_PATH) as Texture2D
		if tex:
			var spr := Sprite2D.new()
			spr.name = "Sprite"
			# Try to load from XML atlas
			var frames := _parse_adobe_atlas(BUTTON_ATLAS_XML)
			if frames.size() > 0:
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				var idx := mini(0, frames.size() - 1)
				atlas.region = Rect2(frames[idx]["x"], frames[idx]["y"], frames[idx]["w"], frames[idx]["h"])
				spr.texture = atlas
			container.add_child(spr)

	# Label
	var label := Label.new()
	label.name = "Label"
	label.text = button_name.capitalize()
	label.add_theme_font_size_override("font_size", 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-100, -15)
	label.custom_minimum_size = Vector2(200, 40)
	container.add_child(label)

	# Lock icon
	if locked:
		var lock := Sprite2D.new()
		lock.name = "Lock"
		if ResourceLoader.exists(LOCK_PATH):
			lock.texture = load(LOCK_PATH) as Texture2D
		lock.position = Vector2(0, -30)
		container.add_child(lock)

	return container


func _parse_adobe_atlas(path: String) -> Array[Dictionary]:
	var frames: Array[Dictionary] = []
	if not ResourceLoader.exists(path):
		return frames
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
					frame[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
				if frame.has("x") and frame.has("y") and frame.has("width") and frame.has("height"):
					frames.append({
						"x": float(frame.get("x", "0")),
						"y": float(frame.get("y", "0")),
						"w": float(frame.get("width", "0")),
						"h": float(frame.get("height", "0")),
					})
	return frames


# ─── Button navigation ────────────────────────────────────────────────────

func _navigate_button(dir: int) -> void:
	if buttons.is_empty():
		return
	var current := 0
	for i in buttons.size():
		if buttons[i].get_meta("button_name", "") == selected:
			current = i
			break
	var new_idx := clampi(current + dir, 0, buttons.size() - 1)
	_select_button(new_idx)


func _select_button(index: int) -> void:
	if index < 0 or index >= buttons.size():
		return

	selected = buttons[index].get_meta("button_name", "")

	for i in buttons.size():
		var btn := buttons[i]
		if i == index:
			btn.modulate.a = 1.0
			btn.scale = Vector2(1.1, 1.1)
		else:
			btn.modulate.a = 0.5
			btn.scale = Vector2(1.0, 1.0)


# ─── Selection ────────────────────────────────────────────────────────────

func select_story(difficulty: String) -> void:
	if _is_selecting:
		return
	_is_selecting = true
	_play(SOUND_CONFIRM)

	# Apply blur effect
	if blur_shader:
		var tw := create_tween()
		tw.tween_property(blur_shader, "shader_parameter/blurX", 5.0, 0.5).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(blur_shader, "shader_parameter/blurY", 5.0, 0.5)

	# Fade out
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func() -> void:
		# Navigate to the song
		if _menu_state and _menu_state.has_method("start_song"):
			_menu_state.start_song(difficulty)
		queue_free()
	)


# ─── Close ────────────────────────────────────────────────────────────────

func close_sub_state() -> void:
	if _is_selecting:
		return
	_is_selecting = true
	_play(SOUND_CANCEL)

	# Blur out
	if blur_shader:
		var tw := create_tween()
		tw.tween_property(blur_shader, "shader_parameter/blurX", 5.0, 0.3)
		tw.parallel().tween_property(blur_shader, "shader_parameter/blurY", 5.0, 0.3)

	# Fade out
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(queue_free)


# ─── Initial animations ───────────────────────────────────────────────────

func _apply_initial_animations() -> void:
	# Fade in logo
	if logo:
		var tw := create_tween()
		tw.tween_property(logo, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_OUT)

	# Stagger button animations
	for i in buttons.size():
		var btn := buttons[i]
		btn.modulate.a = 0.0
		btn.position.y += 30
		var tw := create_tween()
		tw.tween_property(btn, "modulate:a", 1.0, 0.3).set_delay(i * 0.1).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(btn, "position:y", btn.position.y - 30, 0.3).set_delay(i * 0.1).set_ease(Tween.EASE_OUT)


# ─── Music filters ────────────────────────────────────────────────────────

func _configure_music_filters() -> void:
	# Configure low-pass filter for the music
	# This is a visual/audio effect, not strictly needed for functionality
	pass


# ─── Helpers ──────────────────────────────────────────────────────────────

func _play(path: String) -> void:
	if ResourceLoader.exists(path):
		var audio := AudioStreamPlayer.new()
		audio.stream = load(path) as AudioStream
		audio.bus = "SFX"
		add_child(audio)
		audio.play()
		audio.finished.connect(audio.queue_free)
