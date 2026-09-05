extends Node
## HQ Stage Events — handles song-specific stage visual effects.
## Connects to HQEventDispatcher.stage_event and applies per-song effects.
##
## Each song's effects are defined in the _stage_events dictionary.
## The handler manages visibility, position, and animation of stage props.

@export var song_name: String = ""

var _dispatcher: Node
var _stage: Node2D
var _ui_layer: CanvasLayer

## Meguca state
var _meguca_top_text: Label
var _meguca_bottom_text: Label
var _meguca_top_bar: ColorRect
var _meguca_bottom_bar: ColorRect
var _meguca_bf: Node2D

## Initium state
var _initium_image_stages: Array[TextureRect] = []
var _initium_outside: TextureRect
var _initium_stars: TextureRect

## Reconnect state
var _reconnect_logo: TextureRect


func _ready() -> void:
	await get_tree().process_frame
	var scene = get_tree().current_scene
	if scene == null:
		return
	_dispatcher = scene.get_node_or_null("HQEventDispatcher")
	_stage = scene.get_node_or_null("Stage")
	_ui_layer = scene.get_node_or_null("UILayer")
	if _dispatcher == null:
		return
	_dispatcher.stage_event.connect(_on_stage_event)
	_setup_song()


func _setup_song() -> void:
	match song_name:
		"meguca":
			_setup_meguca()
		"initium":
			_setup_initium()
		"reconnect":
			_setup_reconnect()


func _on_stage_event(params: Array) -> void:
	if params.is_empty():
		return
	var action: String = params[0]
	match song_name:
		"meguca":
			_handle_meguca(action, params)
		"initium":
			_handle_initium(action, params)
		"reconnect":
			_handle_reconnect(action, params)
		"out-of-time":
			_handle_out_of_time(action, params)
		"partea":
			_handle_partea(action, params)
		"vexation":
			_handle_vexation(action, params)


## ─── Meguca ────────────────────────────────────────────────────────────────

func _setup_meguca() -> void:
	if _stage == null:
		return
	# Find or create the text overlays
	_meguca_top_text = Label.new()
	_meguca_top_text.position = Vector2(1120, 15)
	_meguca_top_text.size = Vector2(600, 50)
	_meguca_top_text.text = "being Meguca is suffering..."
	_meguca_top_text.add_theme_font_size_override("font_size", 36)
	_ui_layer.add_child(_meguca_top_text) if _ui_layer != null else null

	_meguca_bottom_text = Label.new()
	_meguca_bottom_text.position = Vector2(-395, 538)
	_meguca_bottom_text.size = Vector2(600, 100)
	_meguca_bottom_text.text = "Meguca"
	_meguca_bottom_text.add_theme_font_size_override("font_size", 36)
	_meguca_bottom_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui_layer.add_child(_meguca_bottom_text) if _ui_layer != null else null

	# Top/bottom black bars
	_meguca_top_bar = ColorRect.new()
	_meguca_top_bar.color = Color.BLACK
	_meguca_top_bar.position = Vector2(0, -540)
	_meguca_top_bar.size = Vector2(1920, 1080)
	_ui_layer.add_child(_meguca_top_bar) if _ui_layer != null else null

	_meguca_bottom_bar = ColorRect.new()
	_meguca_bottom_bar.color = Color.BLACK
	_meguca_bottom_bar.position = Vector2(0, 1620)
	_meguca_bottom_bar.size = Vector2(1920, 1080)
	_ui_layer.add_child(_meguca_bottom_bar) if _ui_layer != null else null


func _handle_meguca(action: String, params: Array) -> void:
	match action:
		"Update Text":
			if params.size() >= 3:
				_meguca_top_text.text = str(params[1])
				_meguca_bottom_text.text = str(params[2])
		"Random Border":
			if _meguca_top_bar != null:
				_meguca_top_bar.position.y = randf_range(-300, -200)
			if _meguca_bottom_bar != null:
				_meguca_bottom_bar.position.y = randf_range(1350, 1450)
		"Remove Border":
			if _meguca_top_bar != null:
				_meguca_top_bar.visible = false
			if _meguca_bottom_bar != null:
				_meguca_bottom_bar.visible = false
		"Swap Char":
			# Show BF variant
			if _stage != null:
				var bf = _stage.get_node_or_null("Boyfriend")
				if bf != null:
					bf.visible = true


## ─── Initium ───────────────────────────────────────────────────────────────

func _setup_initium() -> void:
	if _stage == null:
		return
	# Create the stage switcher images
	for i in range(1, 9):
		var tex_path := "res://holyquintet_mod/source/images/stages/initium/week%d.png" % i
		if ResourceLoader.exists(tex_path):
			var rect := TextureRect.new()
			rect.texture = load(tex_path)
			rect.position = Vector2(-850, -100 - (i * 100))
			rect.size = Vector2(1920, 1080)
			rect.visible = false
			_stage.add_child(rect)
			_initium_image_stages.append(rect)

	# Outside background
	var outside_path := "res://holyquintet_mod/source/images/stages/initium/building.png"
	if ResourceLoader.exists(outside_path):
		_initium_outside = TextureRect.new()
		_initium_outside.texture = load(outside_path)
		_initium_outside.position = Vector2(-1550, -200)
		_initium_outside.size = Vector2(1920, 1080)
		_initium_outside.visible = false
		_stage.add_child(_initium_outside)

	# Stars backdrop
	var stars_path := "res://holyquintet_mod/source/images/stages/initium/stars.png"
	if ResourceLoader.exists(stars_path):
		_initium_stars = TextureRect.new()
		_initium_stars.texture = load(stars_path)
		_initium_stars.position = Vector2(0, 0)
		_initium_stars.size = Vector2(1920, 1080)
		_initium_stars.modulate.a = 0.0
		_stage.add_child(_initium_stars)


func _handle_initium(action: String, params: Array) -> void:
	match action:
		"New Stage":
			if params.size() > 1:
				var idx: int = int(params[1])
				for i in _initium_image_stages.size():
					_initium_image_stages[i].visible = (i == idx)
		"Star BG":
			if _initium_stars != null and params.size() > 1:
				if params[1] == "On":
					var dur: float = float(params[2]) if params.size() > 2 and params[2] != "" else 0.0
					if dur <= 0:
						_initium_stars.modulate.a = 1.0
					else:
						var tw := create_tween()
						tw.tween_property(_initium_stars, "modulate:a", 1.0, dur * _step_crochet())
		"Outside":
			for s in _initium_image_stages:
				s.visible = false
			if _initium_outside != null:
				_initium_outside.visible = true


## ─── Reconnect ─────────────────────────────────────────────────────────────

func _setup_reconnect() -> void:
	if _stage == null:
		return
	var logo_path := "res://holyquintet_mod/source/images/stages/reconnect/logo.png"
	if ResourceLoader.exists(logo_path):
		_reconnect_logo = TextureRect.new()
		_reconnect_logo.texture = load(logo_path)
		_reconnect_logo.position = Vector2(400, 200)
		_reconnect_logo.size = Vector2(1920, 1080)
		_reconnect_logo.visible = false
		_stage.add_child(_reconnect_logo)


func _handle_reconnect(action: String, params: Array) -> void:
	match action:
		"Logo":
			if _reconnect_logo != null:
				_reconnect_logo.visible = (params.size() > 0 and params[0] == "Show")
		"Spots", "Transition Sphere", "Transition Video", "OG":
			pass  # Visual-only, simplified for now


## ─── Out of Time ───────────────────────────────────────────────────────────

func _handle_out_of_time(action: String, params: Array) -> void:
	match action:
		"Rain":
			pass  # Rain is a particle effect, simplified
		"Aurora":
			pass  # Aurora is a shader effect, simplified
		"Flashback":
			pass  # Flashback is a video transition, simplified
		"Clock":
			pass  # Clock overlay, simplified
		"Dad Alt Animation":
			if params.size() > 0:
				AnimaniaModule.set_idle_suffix(&"opponent", str(params[0]))
		"Kyubey Layer", "Kyubey Mid-Anim":
			pass  # Character layering, simplified


## ─── Partea ────────────────────────────────────────────────────────────────

func _handle_partea(action: String, params: Array) -> void:
	match action:
		"Char Visible":
			# params: [char1_visible, char2_visible]
			if _stage != null and params.size() >= 2:
				var chars = _stage.get_children()
				for i in mini(2, chars.size()):
					if chars[i] is Node2D:
						chars[i].visible = bool(params[i])
		"Intro", "Mid Intro", "End Intro", "Pre Partea", "Partea", "End Partea":
			pass  # Complex stage transitions, simplified
		"Move Spotlight", "Move Center Spotlight", "Move Back Spotlight", "Spotlight Stop":
			pass  # Spotlight positioning, simplified
		"Start Retro", "Stop Retro":
			pass  # Retro effect, simplified
		"Nagisa Cycle":
			pass  # Character cycling, simplified
		"Setup Position":
			pass  # Camera positioning, simplified
		"Rain":
			pass  # Rain particle effect, simplified


## ─── Vexation ──────────────────────────────────────────────────────────────

func _handle_vexation(action: String, params: Array) -> void:
	match action:
		"FX 1", "FX 2":
			pass  # Complex visual effects, simplified
		"Light":
			pass  # Lighting changes, simplified
		"Sparks":
			pass  # Spark particles, simplified
		"Hide Text":
			pass  # Text overlay, simplified


## ─── Helpers ────────────────────────────────────────────────────────────────

func _step_crochet() -> float:
	var scene = get_tree().current_scene
	if scene == null:
		return 60.0 / 205.0 / 4.0
	var clock = scene.get_node_or_null("RubiconLevelClock")
	if clock == null:
		return 60.0 / 205.0 / 4.0
	var changes: Array = clock.get_time_changes() if clock.has_method("get_time_changes") else []
	if changes.size() > 0:
		var tc = changes[0]
		if tc.bpm > 0:
			return 60.0 / tc.bpm / 4.0
	return 60.0 / 205.0 / 4.0
