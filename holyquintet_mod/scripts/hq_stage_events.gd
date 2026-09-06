extends Node
## HQ Stage Events — handles song-specific stage visual effects.
## Connects to HQEventDispatcher.stage_event and applies per-song effects.

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

## Out-of-Time state
var _oot_sky: Sprite2D
var _oot_intro_gradient: Sprite2D
var _oot_aurora_overlay: ColorRect
var _oot_flashback_overlay: ColorRect
var _oot_clock_back: Sprite2D
var _oot_clock_base: Sprite2D
var _oot_clock_hour: Sprite2D
var _oot_clock_minute: Sprite2D
var _oot_clock_canvas: CanvasLayer
var _oot_rain_overlay: ColorRect

## Partea state
var _pt_darkness: ColorRect
var _pt_band_inside: Sprite2D
var _pt_band_curtain: Sprite2D
var _pt_spotlight: Sprite2D
var _pt_smoke: ColorRect
var _pt_madoka_bg: Sprite2D
var _pt_nagisa_bg: Sprite2D
var _pt_sayaka_bg: Sprite2D
var _pt_mami_bg: Node2D
var _pt_gf_bg: Node2D
var _pt_kyubey_bg: Node2D
var _pt_table: Sprite2D
var _pt_city: Sprite2D
var _pt_inside: Sprite2D
var _pt_couch: Sprite2D
var _pt_objects: Sprite2D
var _pt_speaker: Sprite2D
var _pt_kyubey: Node2D
var _pt_rain_overlay: ColorRect
var _pt_bnw_overlay: ColorRect

## Vexation state
var _vx_fx1_overlay: Sprite2D
var _vx_fx2_overlay: Sprite2D
var _vx_light_overlay: ColorRect
var _vx_sparks_overlay: ColorRect
var _vx_dust_overlay: Sprite2D


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
		"out-of-time":
			_setup_out_of_time()
		"partea":
			_setup_partea()
		"vexation":
			_setup_vexation()


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
	_meguca_top_text = Label.new()
	_meguca_top_text.position = Vector2(1120, 15)
	_meguca_top_text.size = Vector2(600, 50)
	_meguca_top_text.text = "being Meguca is suffering..."
	_meguca_top_text.add_theme_font_size_override("font_size", 36)
	if _ui_layer != null:
		_ui_layer.add_child(_meguca_top_text)

	_meguca_bottom_text = Label.new()
	_meguca_bottom_text.position = Vector2(-395, 538)
	_meguca_bottom_text.size = Vector2(600, 100)
	_meguca_bottom_text.text = "Meguca"
	_meguca_bottom_text.add_theme_font_size_override("font_size", 36)
	_meguca_bottom_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _ui_layer != null:
		_ui_layer.add_child(_meguca_bottom_text)

	_meguca_top_bar = ColorRect.new()
	_meguca_top_bar.color = Color.BLACK
	_meguca_top_bar.position = Vector2(0, -540)
	_meguca_top_bar.size = Vector2(1920, 1080)
	if _ui_layer != null:
		_ui_layer.add_child(_meguca_top_bar)

	_meguca_bottom_bar = ColorRect.new()
	_meguca_bottom_bar.color = Color.BLACK
	_meguca_bottom_bar.position = Vector2(0, 1620)
	_meguca_bottom_bar.size = Vector2(1920, 1080)
	if _ui_layer != null:
		_ui_layer.add_child(_meguca_bottom_bar)


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
			if _stage != null:
				var bf = _stage.get_node_or_null("Boyfriend")
				if bf != null:
					bf.visible = true


## ─── Initium ───────────────────────────────────────────────────────────────

func _setup_initium() -> void:
	if _stage == null:
		return
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
	var outside_path := "res://holyquintet_mod/source/images/stages/initium/building.png"
	if ResourceLoader.exists(outside_path):
		_initium_outside = TextureRect.new()
		_initium_outside.texture = load(outside_path)
		_initium_outside.position = Vector2(-1550, -200)
		_initium_outside.size = Vector2(1920, 1080)
		_initium_outside.visible = false
		_stage.add_child(_initium_outside)
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
			pass


## ─── Out-of-Time ──────────────────────────────────────────────────────────

func _setup_out_of_time() -> void:
	if _stage == null:
		return
	# Find the sky sprite for BG Light color changes
	_oot_sky = _stage.get_node_or_null("Scroll_sky/sky")

	# Intro gradient overlay
	var grad_path := "res://holyquintet_mod/source/images/stages/out-of-time/introgradient.png"
	if ResourceLoader.exists(grad_path):
		_oot_intro_gradient = Sprite2D.new()
		_oot_intro_gradient.texture = load(grad_path)
		_oot_intro_gradient.position = Vector2(0, 0)
		_oot_intro_gradient.scale = Vector2(2.0, 2.0)
		_oot_intro_gradient.modulate.a = 0.0
		_stage.add_child(_oot_intro_gradient)

	# Aurora overlay (colored rect simulating video)
	_oot_aurora_overlay = ColorRect.new()
	_oot_aurora_overlay.color = Color(0.3, 0.6, 1.0, 0.4)
	_oot_aurora_overlay.position = Vector2(0, 0)
	_oot_aurora_overlay.size = Vector2(1920, 1080)
	_oot_aurora_overlay.modulate.a = 0.0
	_oot_aurora_overlay.blend_mode = 1
	_stage.add_child(_oot_aurora_overlay)

	# Flashback overlay (warm flash)
	_oot_flashback_overlay = ColorRect.new()
	_oot_flashback_overlay.color = Color(1.0, 0.9, 0.7, 0.6)
	_oot_flashback_overlay.position = Vector2(0, 0)
	_oot_flashback_overlay.size = Vector2(1920, 1080)
	_oot_flashback_overlay.modulate.a = 0.0
	_oot_flashback_overlay.visible = false
	_oot_flashback_overlay.blend_mode = 1
	_stage.add_child(_oot_flashback_overlay)

	# Rain overlay (subtle blue tint)
	_oot_rain_overlay = ColorRect.new()
	_oot_rain_overlay.color = Color(0.6, 0.7, 1.0, 0.15)
	_oot_rain_overlay.position = Vector2(0, 0)
	_oot_rain_overlay.size = Vector2(1920, 1080)
	_oot_rain_overlay.modulate.a = 0.0
	_stage.add_child(_oot_rain_overlay)

	# Clock overlay
	_oot_clock_canvas = CanvasLayer.new()
	_oot_clock_canvas.layer = 20
	_stage.add_child(_oot_clock_canvas)

	var clock_back_path := "res://holyquintet_mod/source/images/stages/out-of-time/clock/c_back.png"
	var clock_base_path := "res://holyquintet_mod/source/images/stages/out-of-time/clock/c_base.png"
	var clock_hr_path := "res://holyquintet_mod/source/images/stages/out-of-time/clock/c_hrhand.png"
	var clock_min_path := "res://holyquintet_mod/source/images/stages/out-of-time/clock/c_minhand.png"

	if ResourceLoader.exists(clock_back_path):
		_oot_clock_back = Sprite2D.new()
		_oot_clock_back.texture = load(clock_back_path)
		_oot_clock_back.position = Vector2(960, 540)
		_oot_clock_back.modulate.a = 0.0
		_oot_clock_back.visible = false
		_oot_clock_canvas.add_child(_oot_clock_back)

	if ResourceLoader.exists(clock_base_path):
		_oot_clock_base = Sprite2D.new()
		_oot_clock_base.texture = load(clock_base_path)
		_oot_clock_base.position = Vector2(960, 540)
		_oot_clock_base.visible = false
		_oot_clock_canvas.add_child(_oot_clock_base)

	if ResourceLoader.exists(clock_hr_path):
		_oot_clock_hour = Sprite2D.new()
		_oot_clock_hour.texture = load(clock_hr_path)
		_oot_clock_hour.position = Vector2(960, 540)
		_oot_clock_hour.visible = false
		_oot_clock_canvas.add_child(_oot_clock_hour)

	if ResourceLoader.exists(clock_min_path):
		_oot_clock_minute = Sprite2D.new()
		_oot_clock_minute.texture = load(clock_min_path)
		_oot_clock_minute.position = Vector2(960, 540)
		_oot_clock_minute.visible = false
		_oot_clock_canvas.add_child(_oot_clock_minute)


func _handle_out_of_time(action: String, params: Array) -> void:
	match action:
		"BG Light":
			if params.size() < 2:
				return
			var on_off: String = str(params[1])
			var dur_param = params[2] if params.size() > 2 else 0
			var dur: float = float(dur_param) if dur_param != "" and dur_param != 0 else 0.0
			var dur_sec := dur * _step_crochet() / 1000.0 if dur > 0 else 0.0

			if on_off == "On":
				if dur <= 0:
					if _oot_sky != null:
						_oot_sky.modulate = Color.WHITE
					if _oot_intro_gradient != null:
						_oot_intro_gradient.modulate.a = 0.0
				else:
					if _oot_intro_gradient != null:
						var tw := create_tween()
						tw.tween_property(_oot_intro_gradient, "modulate:a", 0.0, dur_sec).set_ease(Tween.EASE_IN_OUT)
					if _oot_sky != null:
						var tw2 := create_tween()
						tw2.tween_property(_oot_sky, "modulate", Color.BLACK, dur_sec * 1.25).set_ease(Tween.EASE_IN_OUT)
			elif on_off == "Off":
				if dur <= 0:
					if _oot_sky != null:
						_oot_sky.modulate = Color.BLACK
					if _oot_intro_gradient != null:
						_oot_intro_gradient.modulate.a = 1.0
				else:
					if _oot_intro_gradient != null:
						var tw := create_tween()
						tw.tween_property(_oot_intro_gradient, "modulate:a", 1.0, dur_sec).set_ease(Tween.EASE_IN_OUT)
					if _oot_sky != null:
						var tw2 := create_tween()
						tw2.tween_property(_oot_sky, "modulate", Color.WHITE, dur_sec * 1.25).set_ease(Tween.EASE_IN_OUT)

		"Aurora":
			if params.size() < 2:
				return
			var mode: String = str(params[1])
			if mode == "Fade In":
				_oot_aurora_overlay.visible = true
				var tw := create_tween()
				tw.tween_property(_oot_aurora_overlay, "modulate:a", 1.0, 1.5).set_ease(Tween.EASE_IN_OUT)
			elif mode == "Fade Out":
				var tw := create_tween()
				tw.tween_property(_oot_aurora_overlay, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN_OUT)
			elif mode == "Instant":
				_oot_aurora_overlay.visible = true
				_oot_aurora_overlay.modulate.a = 1.0

		"Flashback":
			if params.size() < 2:
				return
			var fb_mode: String = str(params[1])
			if fb_mode == "Show":
				_oot_flashback_overlay.visible = true
				_oot_flashback_overlay.modulate.a = 0.0
				var tw := create_tween()
				tw.tween_property(_oot_flashback_overlay, "modulate:a", 1.0, 1.5).set_ease(Tween.EASE_IN_OUT)
			elif fb_mode == "Hide":
				var tw := create_tween()
				tw.tween_property(_oot_flashback_overlay, "modulate:a", 0.0, 1.5).set_ease(Tween.EASE_IN_OUT)

		"Clock":
			if params.size() < 2:
				return
			var clock_action: String = str(params[1])
			if clock_action == "Show":
				# Set clock hands to current time
				var time = Time.get_datetime_dict_from_system()
				if _oot_clock_hour != null:
					_oot_clock_hour.rotation_degrees = time.hour * 30.0 + time.minute * 0.5
					_oot_clock_hour.visible = true
				if _oot_clock_minute != null:
					_oot_clock_minute.rotation_degrees = time.minute * 6.0
					_oot_clock_minute.visible = true
				for spr in [_oot_clock_back, _oot_clock_base]:
					if spr != null:
						spr.visible = true
						spr.modulate.a = 0.0
				if _oot_clock_back != null:
					var tw := create_tween()
					tw.tween_property(_oot_clock_back, "modulate:a", 1.0, 0.75).set_ease(Tween.EASE_OUT)
			elif clock_action == "Tick":
				if _oot_clock_hour != null:
					var tw := create_tween()
					tw.tween_property(_oot_clock_hour, "rotation_degrees", _oot_clock_hour.rotation_degrees + 0.5, 0.1).set_ease(Tween.EASE_OUT)
				if _oot_clock_minute != null:
					var tw := create_tween()
					tw.tween_property(_oot_clock_minute, "rotation_degrees", _oot_clock_minute.rotation_degrees + 6.0, 0.1).set_ease(Tween.EASE_OUT)
			elif clock_action == "Hide":
				for spr in [_oot_clock_back, _oot_clock_base, _oot_clock_hour, _oot_clock_minute]:
					if spr != null:
						spr.visible = false

		"Rain":
			if params.size() < 2:
				return
			var rain_mode: String = str(params[1])
			if rain_mode == "Start":
				_oot_rain_overlay.visible = true
				var tw := create_tween()
				tw.tween_property(_oot_rain_overlay, "modulate:a", 0.015, 3.0).set_ease(Tween.EASE_IN_OUT)
			elif rain_mode == "End":
				var tw := create_tween()
				tw.tween_property(_oot_rain_overlay, "modulate:a", 0.0, 3.0).set_ease(Tween.EASE_IN_OUT)

		"Dad Alt Animation":
			if params.size() > 0:
				AnimaniaModule.set_idle_suffix(&"opponent", str(params[0]))

		"Kyubey Mid-Anim":
			AnimaniaModule.play_character_animation(&"opponent", &"ootmidanim", true)

		"Kyubey Layer":
			# Reorder kyubey below the 'below' sprite
			if _stage != null:
				var kyubey = _stage.get_node_or_null("Kyubey")
				var below = _stage.get_node_or_null("below")
				if kyubey != null and below != null:
					_stage.move_child(kyubey, _stage.get_child_count() - 1)
					# Move 'below' after kyubey to keep layering correct
					var below_idx = _stage.get_child_index(below)
					_stage.move_child(below, below_idx + 1)


## ─── Partea ────────────────────────────────────────────────────────────────

func _setup_partea() -> void:
	if _stage == null:
		return
	# Create intro darkness overlay
	_pt_darkness = ColorRect.new()
	_pt_darkness.color = Color.BLACK
	_pt_darkness.position = Vector2(-1920, -1080)
	_pt_darkness.size = Vector2(5760, 3240)
	_pt_darkness.modulate.a = 1.0
	_stage.add_child(_pt_darkness)

	# Band inside background
	var band_inside_path := "res://holyquintet_mod/source/images/stages/partea/insideband.png"
	if ResourceLoader.exists(band_inside_path):
		_pt_band_inside = Sprite2D.new()
		_pt_band_inside.texture = load(band_inside_path)
		_pt_band_inside.position = Vector2(-800, -1600)
		_pt_band_inside.visible = false
		_stage.add_child(_pt_band_inside)

	# Band curtain
	var curtain_path := "res://holyquintet_mod/source/images/stages/partea/curtain.png"
	if ResourceLoader.exists(curtain_path):
		_pt_band_curtain = Sprite2D.new()
		_pt_band_curtain.texture = load(curtain_path)
		_pt_band_curtain.position = Vector2(-800, -1600)
		_pt_band_curtain.visible = false
		_stage.add_child(_pt_band_curtain)

	# Spotlight
	var spot_path := "res://holyquintet_mod/source/images/stages/partea/spotlight.png"
	if ResourceLoader.exists(spot_path):
		_pt_spotlight = Sprite2D.new()
		_pt_spotlight.texture = load(spot_path)
		_pt_spotlight.position = Vector2(-800, -1600)
		_pt_spotlight.modulate.a = 0.65
		_pt_spotlight.visible = false
		_stage.add_child(_pt_spotlight)

	# Smoke overlay
	_pt_smoke = ColorRect.new()
	_pt_smoke.color = Color(0.5, 0.5, 0.5, 0.5)
	_pt_smoke.position = Vector2(-1920, -1080)
	_pt_smoke.size = Vector2(5760, 3240)
	_pt_smoke.modulate.a = 0.0
	_pt_smoke.visible = false
	_stage.add_child(_pt_smoke)

	# BNW overlay for retro
	_pt_bnw_overlay = ColorRect.new()
	_pt_bnw_overlay.color = Color(0.3, 0.3, 0.3, 0.7)
	_pt_bnw_overlay.position = Vector2(-1920, -1080)
	_pt_bnw_overlay.size = Vector2(5760, 3240)
	_pt_bnw_overlay.modulate.a = 0.0
	_pt_bnw_overlay.visible = false
	_stage.add_child(_pt_bnw_overlay)

	# Rain overlay
	_pt_rain_overlay = ColorRect.new()
	_pt_rain_overlay.color = Color(0.6, 0.7, 1.0, 0.15)
	_pt_rain_overlay.position = Vector2(-1920, -1080)
	_pt_rain_overlay.size = Vector2(5760, 3240)
	_pt_rain_overlay.modulate.a = 0.0
	_pt_rain_overlay.visible = false
	_stage.add_child(_pt_rain_overlay)


func _handle_partea(action: String, params: Array) -> void:
	match action:
		"Char Visible":
			if _stage != null and params.size() >= 3:
				var opponent = _stage.get_node_or_null("Opponent")
				var boyfriend = _stage.get_node_or_null("Boyfriend")
				if opponent != null:
					opponent.visible = (str(params[1]).to_lower() == "true")
				if boyfriend != null:
					boyfriend.visible = (str(params[2]).to_lower() == "true")

		"Start Retro":
			if _pt_bnw_overlay != null:
				_pt_bnw_overlay.visible = true
				_pt_bnw_overlay.modulate.a = 1.0
			if _pt_darkness != null:
				_pt_darkness.modulate.a = 1.0

		"Stop Retro":
			if _pt_bnw_overlay != null:
				_pt_bnw_overlay.visible = false
				_pt_bnw_overlay.modulate.a = 0.0
			if _pt_darkness != null:
				_pt_darkness.modulate.a = 0.0

		"Setup Position":
			if _pt_darkness != null:
				_pt_darkness.modulate.a = 1.0
			# Position boyfriend for intro sequence
			var bf = _stage.get_node_or_null("Boyfriend") if _stage != null else null
			if bf != null:
				bf.position.x -= 150
				bf.position.y -= 50
				bf.modulate.a = 0.0
				var tw := create_tween()
				tw.tween_property(bf, "modulate:a", 0.25, 5.0).set_ease(Tween.EASE_IN_OUT).set_delay(1.0)

		"Pre Partea":
			if _pt_darkness != null:
				_pt_darkness.modulate.a = 0.0
			# Hide regular stage, show band stage
			if _pt_band_inside != null:
				_pt_band_inside.visible = true
				_pt_band_inside.modulate = Color(0.5, 0.5, 0.5)
			if _pt_band_curtain != null:
				_pt_band_curtain.visible = true
				_pt_band_curtain.modulate = Color.BLACK
			if _pt_spotlight != null:
				_pt_spotlight.visible = true
				_pt_spotlight.modulate.a = 0.65
			if _pt_smoke != null:
				_pt_smoke.visible = true
				_pt_smoke.modulate.a = 0.5
			# Hide regular stage props
			for prop_name in ["Scroll_city", "inside", "curtain"]:
				var prop = _stage.get_node_or_null(prop_name)
				if prop != null:
					prop.visible = false

		"Partea":
			# Full band visible, color restored
			if _pt_band_inside != null:
				_pt_band_inside.modulate = Color.WHITE
			if _pt_band_curtain != null:
				_pt_band_curtain.modulate = Color.WHITE
			# Show opponent/bf again
			var opponent = _stage.get_node_or_null("Opponent") if _stage != null else null
			var bf = _stage.get_node_or_null("Boyfriend") if _stage != null else null
			if opponent != null:
				opponent.visible = false
			if bf != null:
				bf.visible = false

		"End Partea":
			# Restore original stage
			if _pt_band_inside != null:
				_pt_band_inside.visible = false
			if _pt_band_curtain != null:
				_pt_band_curtain.visible = false
			if _pt_spotlight != null:
				_pt_spotlight.visible = false
			if _pt_smoke != null:
				_pt_smoke.visible = false
			if _pt_bnw_overlay != null:
				_pt_bnw_overlay.visible = false
			# Show original stage props
			for prop_name in ["Scroll_city", "inside", "curtain"]:
				var prop = _stage.get_node_or_null(prop_name)
				if prop != null:
					prop.visible = true
			# Restore characters
			var opponent = _stage.get_node_or_null("Opponent") if _stage != null else null
			var bf = _stage.get_node_or_null("Boyfriend") if _stage != null else null
			if opponent != null:
				opponent.visible = true
				opponent.modulate = Color.WHITE
			if bf != null:
				bf.visible = true
				bf.modulate = Color.WHITE
				bf.position = Vector2(800, -390)
			if _pt_darkness != null:
				_pt_darkness.modulate.a = 0.0

		"Move Spotlight":
			if _pt_spotlight != null:
				var tw := create_tween()
				tw.tween_property(_pt_spotlight, "position:x", _pt_spotlight.position.x + 1200, 2.0).set_ease(Tween.EASE_IN_OUT)

		"Move Back Spotlight":
			if _pt_spotlight != null:
				var tw := create_tween()
				tw.tween_property(_pt_spotlight, "position:x", _pt_spotlight.position.x - 1200, 2.0).set_ease(Tween.EASE_IN_OUT)

		"Move Center Spotlight":
			if _pt_spotlight != null:
				var tw := create_tween()
				tw.tween_property(_pt_spotlight, "position:x", -50.0, 4.0).set_ease(Tween.EASE_IN_OUT)

		"Spotlight Stop":
			if _pt_spotlight != null:
				var tw := create_tween()
				var dur := 10.0 * _step_crochet()
				tw.tween_property(_pt_spotlight, "scale", Vector2(5.0, 5.0), dur).set_ease(Tween.EASE_IN)
				var tw2 := create_tween()
				tw2.tween_property(_pt_spotlight, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
			if _pt_smoke != null:
				var tw := create_tween()
				tw.tween_property(_pt_smoke, "modulate:a", 0.0, 10.0 * _step_crochet()).set_ease(Tween.EASE_IN)

		"Nagisa Cycle":
			pass  # Handled by character animation system

		"Rain":
			if params.size() >= 3:
				var target_intensity: float = float(params[1])
				var steps: float = float(params[2])
				if _pt_rain_overlay != null:
					_pt_rain_overlay.visible = true
					var tw := create_tween()
					tw.tween_property(_pt_rain_overlay, "modulate:a", target_intensity, steps * _step_crochet()).set_ease(Tween.EASE_IN_OUT)

		"Intro", "Mid Intro", "End Intro":
			pass  # Phase markers, handled by character animations


## ─── Vexation ──────────────────────────────────────────────────────────────

func _setup_vexation() -> void:
	if _stage == null:
		return
	# FX1 overlay (red tint cut-in)
	var fx1_path := "res://holyquintet_mod/source/images/stages/vexation/fx1.png"
	if ResourceLoader.exists(fx1_path):
		_vx_fx1_overlay = Sprite2D.new()
		_vx_fx1_overlay.texture = load(fx1_path)
		_vx_fx1_overlay.position = Vector2(0, 0)
		_vx_fx1_overlay.modulate.a = 0.0
		_vx_fx1_overlay.z_index = 100
		_stage.add_child(_vx_fx1_overlay)

	# FX2 overlay (blue cut-in)
	var fx2_path := "res://holyquintet_mod/source/images/stages/vexation/cutinblue.png"
	if ResourceLoader.exists(fx2_path):
		_vx_fx2_overlay = Sprite2D.new()
		_vx_fx2_overlay.texture = load(fx2_path)
		_vx_fx2_overlay.position = Vector2(0, 0)
		_vx_fx2_overlay.modulate.a = 0.0
		_vx_fx2_overlay.z_index = 100
		_stage.add_child(_vx_fx2_overlay)

	# Light overlay (dimming)
	_vx_light_overlay = ColorRect.new()
	_vx_light_overlay.color = Color.BLACK
	_vx_light_overlay.position = Vector2(-1920, -1080)
	_vx_light_overlay.size = Vector2(5760, 3240)
	_vx_light_overlay.modulate.a = 0.0
	_vx_light_overlay.z_index = 99
	_stage.add_child(_vx_light_overlay)

	# Sparks overlay (bright flash)
	_vx_sparks_overlay = ColorRect.new()
	_vx_sparks_overlay.color = Color(1.0, 0.9, 0.5, 0.8)
	_vx_sparks_overlay.position = Vector2(-1920, -1080)
	_vx_sparks_overlay.size = Vector2(5760, 3240)
	_vx_sparks_overlay.modulate.a = 0.0
	_vx_sparks_overlay.blend_mode = 1
	_vx_sparks_overlay.z_index = 100
	_stage.add_child(_vx_sparks_overlay)

	# Dust overlay
	var dust_path := "res://holyquintet_mod/source/images/stages/vexation/vex_dust.png"
	if ResourceLoader.exists(dust_path):
		_vx_dust_overlay = Sprite2D.new()
		_vx_dust_overlay.texture = load(dust_path)
		_vx_dust_overlay.position = Vector2(0, 0)
		_vx_dust_overlay.modulate.a = 0.0
		_vx_dust_overlay.z_index = 98
		_stage.add_child(_vx_dust_overlay)


func _handle_vexation(action: String, params: Array) -> void:
	match action:
		"FX 1":
			# Red cut-in flash effect
			if _vx_fx1_overlay != null:
				_vx_fx1_overlay.visible = true
				_vx_fx1_overlay.modulate.a = 1.0
				var tw := create_tween()
				tw.tween_property(_vx_fx1_overlay, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
			# Dust kick-up
			if _vx_dust_overlay != null:
				_vx_dust_overlay.visible = true
				_vx_dust_overlay.modulate.a = 0.8
				var tw2 := create_tween()
				tw2.tween_property(_vx_dust_overlay, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)

		"FX 2":
			# Blue cut-in flash effect
			if _vx_fx2_overlay != null:
				_vx_fx2_overlay.visible = true
				_vx_fx2_overlay.modulate.a = 1.0
				var tw := create_tween()
				tw.tween_property(_vx_fx2_overlay, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
			# Dust kick-up
			if _vx_dust_overlay != null:
				_vx_dust_overlay.visible = true
				_vx_dust_overlay.modulate.a = 0.8
				var tw2 := create_tween()
				tw2.tween_property(_vx_dust_overlay, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_IN)

		"Light":
			if params.size() >= 2:
				var mode: String = str(params[1])
				if mode == "Dim":
					# Gradually dim the scene
					if _vx_light_overlay != null:
						_vx_light_overlay.visible = true
						var tw := create_tween()
						tw.tween_property(_vx_light_overlay, "modulate:a", 0.5, 2.0).set_ease(Tween.EASE_IN_OUT)
				elif mode == "Bright":
					# Brighten back
					if _vx_light_overlay != null:
						var tw := create_tween()
						tw.tween_property(_vx_light_overlay, "modulate:a", 0.0, 2.0).set_ease(Tween.EASE_IN_OUT)
				elif mode == "Off":
					if _vx_light_overlay != null:
						_vx_light_overlay.modulate.a = 0.0

		"Sparks":
			# Bright spark flash
			if _vx_sparks_overlay != null:
				_vx_sparks_overlay.visible = true
				_vx_sparks_overlay.modulate.a = 1.0
				var tw := create_tween()
				tw.tween_property(_vx_sparks_overlay, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_OUT)

		"Hide Text":
			# Hide UI text elements
			var scene = get_tree().current_scene
			if scene != null:
				var ui = scene.get_node_or_null("UILayer")
				if ui != null:
					for child in ui.get_children():
						if child is Label:
							var dur: float = float(params[1]) if params.size() > 1 and params[1] != "" else 1.0
							var tw := create_tween()
							tw.tween_property(child, "modulate:a", 0.0, dur * _step_crochet()).set_ease(Tween.EASE_IN_OUT)


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
