extends Node
## Loads and dispatches HQ-format chart events (events.json) during gameplay.
##
## Attach to a Node child of the song scene. On _ready() it reads
## the events JSON and fires each event when its timestamp is reached.

@export var events_path: String = ""

var _events: Array = []
var _clock: Node = null
var _next_idx: int = 0
var camera: Camera2D
var stage: Node2D
var ui_layer: CanvasLayer
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _flash_rect: ColorRect
var _bars_visible: bool = false
var _bars_tween: Tween

## Camera Alpha: black overlay covering the game viewport.
var _cam_alpha_overlay: ColorRect
var _cam_alpha_tween: Tween
var _cam_alpha_canvas: CanvasLayer

## Camera Modulo Change state.
var _cur_modulo: int = 16
var _cam_strength: float = 1.0
var _cam_modulo_offset: float = 0.0
var _last_step_bopped: float = -1.0
var _wait_til_next_step: bool = false

## Subtitle text overlay state.
var _subtitle_label: Label
var _subtitle_canvas: CanvasLayer

## Perfect popup state.
var _perfect_label: Label
var _perfect_canvas: CanvasLayer

## Sayaka Heal state.
var _sayaka_healing: bool = false
var _sayaka_health_drain: float = 0.0

## Camera Movement state: simple directional nudge on beat.
var _cam_movement_enabled: bool = false
var _cam_movement_direction: int = 0  ## 0=right, 1=left

signal stage_event


func _process(delta: float) -> void:
	_apply_sayaka_drain(delta)
	_poll_dodge()


func _ready() -> void:
	if events_path.is_empty():
		return
	await get_tree().process_frame
	var song_root = _find_song_root()
	if song_root == null:
		return
	_clock = song_root.get_node_or_null("RubiconLevelClock")
	if _clock == null:
		return
	camera = _find_camera(song_root)
	stage = song_root.get_node_or_null("Stage")
	ui_layer = song_root.get_node_or_null("UILayer")
	_load_events()
	_clock.step_change.connect(_on_step)


func _find_song_root() -> Node:
	var node = get_parent()
	while node != null:
		if node.has_node("RubiconLevelClock"):
			return node
		node = node.get_parent()
	return null


func _find_camera(root: Node) -> Camera2D:
	for child in root.get_children():
		if child is Camera2D:
			return child
	return null


func _load_events() -> void:
	var full_path = events_path if events_path.begins_with("res://") else "res://" + events_path
	if not FileAccess.file_exists(full_path):
		push_warning("HQEventDispatcher: not found: %s" % full_path)
		return
	var file = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data = json.data
	if data is Dictionary and data.has("events"):
		_events = data["events"]
	elif data is Array:
		_events = data
	_events.sort_custom(func(a, b): return a.get("time", 0) < b.get("time", 0))
	_next_idx = 0


func _on_step(_step: int) -> void:
	if _events.is_empty() or _clock == null:
		return
	var ms: float = _clock.time_milliseconds
	while _next_idx < _events.size():
		var ev: Dictionary = _events[_next_idx]
		if ev.get("time", 0.0) > ms:
			break
		_fire_event(ev)
		_next_idx += 1
	# Camera Modulo: apply zoom pulse on matching steps.
	_apply_cam_modulo()


func _fire_event(ev: Dictionary) -> void:
	var ev_name: String = ev.get("name", "")
	var params: Array = ev.get("params", [])
	match ev_name:
		"Camera Zoom": _evt_camera_zoom(params)
		"Camera Position": _evt_camera_position(params)
		"Camera Flash": _evt_camera_flash(params)
		"Camera Bop": _evt_camera_bop(params)
		"Black Bars": _evt_black_bars(params)
		"UI Visability": _evt_ui_visibility(params)
		"Add Camera Zoom": _evt_add_camera_zoom(params)
		"Play Animation": _evt_play_animation(params)
		"Stage Event": stage_event.emit(params)
		"Gameplay Configuration": _evt_gameplay_config(params)
		"Scroll Speed Change": _evt_scroll_speed(params)
		"Camera Alpha": _evt_camera_alpha(params)
		"Camera Movement": _evt_camera_movement(params)
		"Camera Modulo Change": _evt_camera_modulo_change(params)
		"BPM Change": _evt_bpm_change(params)
		"Time Signature Change": _evt_time_sig_change(params)
		"Perfect": _evt_perfect(params)
		"Subtitle": _evt_subtitle(params)
		"Sayaka Heal": _evt_sayaka_heal(params)
		"Kyoko Attack": _evt_kyoko_attack(params)
		_: pass

## ─── Camera Zoom ────────────────────────────────────────────────────────────
func _evt_camera_zoom(params: Array) -> void:
	if params.size() < 2 or camera == null:
		return
	var tween_it: bool = params[0]
	var zoom_val: float = params[1]
	if tween_it:
		var steps: float = params[3] if params.size() > 3 else 4.0
		var dur := steps * _step_crochet()
		var tw = create_tween()
		tw.tween_property(camera, "zoom", Vector2(zoom_val, zoom_val), dur)
	else:
		camera.zoom = Vector2(zoom_val, zoom_val)


## ─── Camera Position ────────────────────────────────────────────────────────
func _evt_camera_position(params: Array) -> void:
	if params.size() < 2 or camera == null:
		return
	var x: float = params[0]
	var y: float = params[1]
	var tween_it: bool = params[2] if params.size() > 2 else false
	if tween_it:
		var steps: float = params[3] if params.size() > 3 else 4.0
		var dur := steps * _step_crochet()
		var tw = create_tween()
		tw.tween_property(camera, "position_interpolate_target", Vector2(x, y), dur)
	else:
		camera.position_interpolate_target = Vector2(x, y)
		camera.global_position = Vector2(x, y)


## ─── Camera Flash ───────────────────────────────────────────────────────────
func _evt_camera_flash(params: Array) -> void:
	if params.size() < 3:
		return
	var color_val: int = params[1]
	var duration: int = params[2]
	_ensure_flash_rect()
	_flash_rect.color = Color(color_val)
	_flash_rect.modulate.a = 1.0
	var dur := duration * _step_crochet()
	var tw = create_tween()
	tw.tween_property(_flash_rect, "modulate:a", 0.0, dur).set_ease(Tween.EASE_OUT)


func _ensure_flash_rect() -> void:
	if _flash_rect != null:
		return
	var canvas = CanvasLayer.new()
	canvas.layer = 20
	get_tree().current_scene.add_child(canvas)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color.WHITE
	_flash_rect.modulate.a = 0.0
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(_flash_rect)


## ─── Camera Bop ─────────────────────────────────────────────────────────────
func _evt_camera_bop(params: Array) -> void:
	var rate: int = params[0] if params.size() > 0 else 4
	if camera == null:
		return
	var bumper = camera.get_node_or_null("RubiconCameraBumper")
	if bumper:
		if "bump_interval" in bumper:
			bumper.bump_interval = rate


## ─── Black Bars ─────────────────────────────────────────────────────────────
func _evt_black_bars(params: Array) -> void:
	if params.size() < 1:
		return
	var distance: float = params[0]
	_ensure_bars()
	if distance > 0:
		_bars_visible = true
		var target_y: float = distance / 100.0 * get_viewport().size.y * 0.5
		_bar_top.size.y = target_y
		_bar_bottom.size.y = target_y
		_bar_bottom.position.y = get_viewport().size.y - target_y
		_bar_top.visible = true
		_bar_bottom.visible = true
	else:
		_bars_visible = false
		_bar_top.visible = false
		_bar_bottom.visible = false


func _ensure_bars() -> void:
	if _bar_top != null:
		return
	var canvas = CanvasLayer.new()
	canvas.layer = 20
	get_tree().current_scene.add_child(canvas)
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.size.y = 0
	_bar_top.visible = false
	canvas.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.size.y = 0
	_bar_bottom.visible = false
	canvas.add_child(_bar_bottom)


## ─── UI Visibility ──────────────────────────────────────────────────────────
func _evt_ui_visibility(params: Array) -> void:
	if ui_layer == null:
		return
	var ui = ui_layer.get_node_or_null("UI")
	if ui == null:
		return
	if params.size() > 3:
		var notes_vis: bool = params[3]
		var opp = ui.get_node_or_null("Opponent")
		var plr = ui.get_node_or_null("Player")
		if opp: opp.visible = notes_vis
		if plr: plr.visible = notes_vis
	if params.size() > 0:
		var hb = ui.get_node_or_null("HealthBar")
		if hb: hb.visible = params[0]


## ─── Add Camera Zoom ────────────────────────────────────────────────────────
func _evt_add_camera_zoom(params: Array) -> void:
	var amount: float = params[0] if params.size() > 0 else 0.1
	AnimaniaModule.punch(amount)


## ─── Play Animation ─────────────────────────────────────────────────────────
func _evt_play_animation(params: Array) -> void:
	if params.size() < 2:
		return
	var anim_name: String = params[1]
	var force: bool = params[2] if params.size() > 2 else false
	AnimaniaModule.play_character_animation(&"opponent", StringName(anim_name), force)


## ─── Camera Alpha ───────────────────────────────────────────────────────────
## Params: [camera_name, alpha, tween_bool, duration_steps, ease_type, ease_dir]
## camera_name: "camGame" (overlay), "camHUD", or "camUI"
func _evt_camera_alpha(params: Array) -> void:
	if params.size() < 2:
		return
	var cam_name: String = params[0]
	var alpha_val: float = params[1]
	var tween_it: bool = params[2] if params.size() > 2 else false
	_ensure_cam_alpha_overlay()
	if not tween_it:
		match cam_name:
			"camGame":
				_cam_alpha_overlay.modulate.a = 1.0 - alpha_val
			"camHUD":
				if ui_layer != null:
					ui_layer.modulate.a = alpha_val
	else:
		var steps: float = params[3] if params.size() > 3 else 4.0
		var dur := steps * _step_crochet()
		if _cam_alpha_tween != null and _cam_alpha_tween.is_valid():
			_cam_alpha_tween.kill()
		match cam_name:
			"camGame":
				_cam_alpha_tween = create_tween()
				_cam_alpha_tween.tween_property(_cam_alpha_overlay, "modulate:a",
					1.0 - alpha_val, dur)
			"camHUD":
				if ui_layer != null:
					_cam_alpha_tween = create_tween()
					_cam_alpha_tween.tween_property(ui_layer, "modulate:a",
						alpha_val, dur)


func _ensure_cam_alpha_overlay() -> void:
	if _cam_alpha_overlay != null:
		return
	_cam_alpha_canvas = CanvasLayer.new()
	_cam_alpha_canvas.layer = 19
	get_tree().current_scene.add_child(_cam_alpha_canvas)
	_cam_alpha_overlay = ColorRect.new()
	_cam_alpha_overlay.color = Color.BLACK
	_cam_alpha_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_alpha_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cam_alpha_overlay.modulate.a = 0.0
	_cam_alpha_canvas.add_child(_cam_alpha_overlay)


## ─── Camera Movement ────────────────────────────────────────────────────────
## Params: [target, tween_bool, duration_steps, ease_type, ease_dir]
## In the original engine, this creates a camera sway/shift on beat.
## Simplified: we nudge the camera offset based on direction.
func _evt_camera_movement(params: Array) -> void:
	if params.size() < 1 or camera == null:
		return
	var target: int = params[0]
	_cam_movement_enabled = (target != 0)
	_cam_movement_direction = target


## ─── Camera Modulo Change ───────────────────────────────────────────────────
## Params: [modulo, strength, "STEP", offset]
## Creates a beat-synced zoom pulse every N steps.
func _evt_camera_modulo_change(params: Array) -> void:
	if params.size() < 2:
		return
	_cur_modulo = int(params[0])
	_cam_strength = params[1]
	if params.size() > 3:
		_cam_modulo_offset = params[3]
	else:
		_cam_modulo_offset = 0.0
	_wait_til_next_step = false


func _apply_cam_modulo() -> void:
	if _clock == null or _cur_modulo <= 0 or camera == null:
		return
	var cur_step: float = _clock.time_step
	var check_step: float = cur_step + _cam_modulo_offset
	if _wait_til_next_step and check_step != _last_step_bopped:
		_wait_til_next_step = false
	if fmod(check_step, _cur_modulo) < 0.01 and not _wait_til_next_step:
		var punch_amount := 0.03 * _cam_strength
		camera.zoom = camera.zoom * (1.0 + punch_amount)
		_wait_til_next_step = true
		_last_step_bopped = check_step


## ─── Perfect ────────────────────────────────────────────────────────────────
## Params: [] — triggers when player has 0 misses at event time.
func _evt_perfect(_params: Array) -> void:
	_ensure_perfect_ui()
	var scene = get_tree().current_scene
	if scene == null:
		return
	var player = scene.get_node_or_null("UILayer/UI/Player")
	if player != null and player.performance_hits_miss > 0:
		return  # Only show when no misses
	_perfect_label.text = "PERFECT!"
	_perfect_label.modulate.a = 1.0
	_perfect_label.scale = Vector2(1.5, 1.5)
	_perfect_label.visible = true
	# Flash in
	var tw := create_tween()
	tw.tween_property(_perfect_label, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(_perfect_label, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _perfect_label.visible = false)


func _ensure_perfect_ui() -> void:
	if _perfect_label != null:
		return
	_perfect_canvas = CanvasLayer.new()
	_perfect_canvas.layer = 25
	get_tree().current_scene.add_child(_perfect_canvas)
	_perfect_label = Label.new()
	_perfect_label.text = "PERFECT!"
	_perfect_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_perfect_label.offset_top = 180
	_perfect_label.add_theme_font_size_override("font_size", 72)
	_perfect_label.add_theme_color_override("font_color", Color(1, 0.85, 0, 1))
	_perfect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_perfect_label.visible = false
	_perfect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_perfect_canvas.add_child(_perfect_label)


## ─── Subtitle ───────────────────────────────────────────────────────────────
## Params: [text_string] — shows text during gameplay.
func _evt_subtitle(params: Array) -> void:
	if params.is_empty():
		return
	var text: String = str(params[0])
	_ensure_subtitle_ui()
	_subtitle_label.text = text
	_subtitle_label.visible = text != ""
	if text != "":
		_subtitle_label.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_property(_subtitle_label, "modulate:a", 0.0, 3.0).set_ease(Tween.EASE_IN).set_delay(2.0)


func _ensure_subtitle_ui() -> void:
	if _subtitle_label != null:
		return
	_subtitle_canvas = CanvasLayer.new()
	_subtitle_canvas.layer = 25
	get_tree().current_scene.add_child(_subtitle_canvas)
	_subtitle_label = Label.new()
	_subtitle_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle_label.offset_bottom = -80
	_subtitle_label.offset_top = -160
	_subtitle_label.size = Vector2(1920, 80)
	_subtitle_label.add_theme_font_size_override("font_size", 42)
	_subtitle_label.add_theme_color_override("font_color", Color(1, 1, 0, 1))
	_subtitle_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.visible = false
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_canvas.add_child(_subtitle_label)


## ─── Sayaka Heal ─────────────────────────────────────────────────────────────
## Params: [is_healing: bool, drain_rate: float]
## When healing starts, health drains over time. Visual effects on opponent.
func _evt_sayaka_heal(params: Array) -> void:
	if params.is_empty():
		return
	var is_healing: bool = params[0]
	if is_healing:
		var drain: float = params[1] if params.size() > 1 else 0.01
		_sayaka_healing = true
		_sayaka_health_drain = drain
		# Play healstart animation on opponent
		AnimaniaModule.play_character_animation(&"opponent", &"healstart", true)
		# Switch icon
		var scene = get_tree().current_scene
		if scene != null:
			var icon = scene.get_node_or_null("UILayer/UI/HealthBar/OpponentIcon")
			if icon != null and icon.has_method("set_icon"):
				icon.set_icon("sayaka-heal")
	else:
		_sayaka_healing = false
		_sayaka_health_drain = 0.0
		AnimaniaModule.play_character_animation(&"opponent", &"healend", true)


func _apply_sayaka_drain(delta: float) -> void:
	if _sayaka_healing and _sayaka_health_drain > 0.0:
		var scene = get_tree().current_scene
		if scene != null:
			var health = scene.get_node_or_null("RubiconHealthModule")
			if health != null and health.has_method("change_health"):
				health.change_health(-_sayaka_health_drain * delta)


## ─── Kyoko Attack ────────────────────────────────────────────────────────────
## Params: [damage: float]
## Dodge mechanic (Kyoko Attack.hx): press dodge (SPACE / mobile button) inside
## the window. Timing decides the result - before 8.5 steps is a miss-early,
## 8.5-11.5 is a dodge, after 11.5 is a dodge-perfect, never pressing is a
## miss-late. HarderMechanics narrows the perfect window to 11 steps.
const KYOKO_DODGE_FRAME_INDEX: Dictionary = {
	"miss-early": 0,
	"miss-late": 1,
	"dodge": 2,
	"dodge-perfect": 3,
}

var _kyoko_can_dodge: bool = false
var _kyoko_current_result: String = ""  ## Advances: miss-early -> dodge -> dodge-perfect
var _kyoko_dodge_result: String = ""    ## Captured at the moment dodge is pressed.


func _ensure_dodge_action() -> void:
	if InputMap.has_action("dodge"):
		return
	InputMap.add_action("dodge")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	InputMap.action_add_event("dodge", key)


func _poll_dodge() -> void:
	if not _kyoko_can_dodge:
		return
	_ensure_dodge_action()
	if Input.is_action_just_pressed("dodge"):
		_kyoko_dodge_result = _kyoko_current_result
		_kyoko_can_dodge = false
		_play_bf_dodge_anim()


func _evt_kyoko_attack(params: Array) -> void:
	if params.is_empty():
		return
	var damage: float = params[0]
	_kyoko_can_dodge = true
	_kyoko_current_result = "miss-early"
	_kyoko_dodge_result = ""
	_show_kyoko_warning(Color.YELLOW)
	# After 4 steps, Kyoko attacks + second warning.
	var tw := create_tween()
	tw.tween_interval(4.0 * _step_crochet())
	tw.tween_callback(func():
		_play_kyoko_attack_anim()
		_show_kyoko_warning(Color.YELLOW)
	)
	# After 8 steps, red warning.
	var tw1 := create_tween()
	tw1.tween_interval(8.0 * _step_crochet())
	tw1.tween_callback(func(): _show_kyoko_warning(Color.RED))
	# After 8.5 steps, dodge window opens (unchanged on HarderMechanics).
	var tw2 := create_tween()
	tw2.tween_interval(8.5 * _step_crochet())
	tw2.tween_callback(func():
		if not HQSaves.cur_gauntlet_mods.has("HarderMechanics"):
			_kyoko_current_result = "dodge"
	)
	# After 11.5 steps (11 on HarderMechanics), perfect dodge window.
	var window_steps := 11.5
	if HQSaves.cur_gauntlet_mods.has("HarderMechanics"):
		window_steps = 11.0
	var tw3 := create_tween()
	tw3.tween_interval(window_steps * _step_crochet())
	tw3.tween_callback(func(): _kyoko_current_result = "dodge-perfect")
	# After 13 steps, execute the result.
	var tw4 := create_tween()
	tw4.tween_interval(13.0 * _step_crochet())
	tw4.tween_callback(func(): _execute_kyoko_result(damage))


func _play_kyoko_attack_anim() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var kyoko: Node = scene.get_node_or_null("Stage/Kyoko")
	if kyoko == null or not kyoko.has_method("play"):
		return
	var anim_player: Variant = kyoko.get("animation_player")
	if anim_player != null and anim_player.has_animation(&"attack"):
		kyoko.play(&"attack")


func _play_bf_dodge_anim() -> void:
	var scene = get_tree().current_scene
	if scene == null:
		return
	var bf: Node = scene.get_node_or_null("Stage/Boyfriend")
	if bf == null or not bf.has_method("play"):
		return
	var direction := randi_range(0, 3)
	var candidates: Array[StringName] = [
		[&"dodgeLEFT", &"dodgeRIGHT", &"dodgeUP", &"dodgeDOWN"][direction],
		&"dodge",
		&"hey",
	]
	_play_first_available_anim(bf, candidates)


func _show_kyoko_warning(col: Color) -> void:
	var tex_path := "res://holyquintet_mod/source/images/game/mechanics/kyoko/warning.png"
	var canvas := CanvasLayer.new()
	canvas.layer = 25
	get_tree().current_scene.add_child(canvas)
	if not ResourceLoader.exists(tex_path):
		var label := Label.new()
		label.text = "WARNING!"
		label.set_anchors_preset(Control.PRESET_CENTER)
		label.add_theme_font_size_override("font_size", 80)
		label.add_theme_color_override("font_color", col)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.add_child(label)
		var tw := create_tween()
		tw.tween_property(label, "scale", Vector2(1.5, 1.5), 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.5)
		tw.tween_property(label, "scale", Vector2(0.0, 0.0), 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): canvas.queue_free())
		return
	var sprite := Sprite2D.new()
	sprite.texture = load(tex_path)
	sprite.modulate = col
	sprite.modulate.a = 0.0
	sprite.scale = Vector2(1.6, 1.6)
	sprite.rotation_degrees = randi_range(-5, 5)
	sprite.position = canvas.get_viewport().get_visible_rect().size / 2.0
	canvas.add_child(sprite)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(1.5, 1.5), 2.0 * _step_crochet()).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate:a", 1.0, 2.0 * _step_crochet()).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "scale", Vector2(0.0, 0.0), 4.0 * _step_crochet()).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(sprite, "rotation_degrees", sprite.rotation_degrees * 15.0, 4.0 * _step_crochet()).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(sprite, "modulate:a", 0.0, 4.0 * _step_crochet()).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): canvas.queue_free())


func _execute_kyoko_result(damage: float) -> void:
	_kyoko_can_dodge = false
	var result := _kyoko_dodge_result
	if result.is_empty():
		result = "miss-late"
	if HQSaves.cur_story_diff == "easy":
		damage *= 0.5
	_show_dodge_judgement(result)
	var scene = get_tree().current_scene
	var health: Node = null
	if scene != null:
		health = scene.get_node_or_null("RubiconHealthModule")
	match result:
		"miss-early", "miss-late":
			_damage_player(health, damage)
			HQSaves.hq_atks_sustained = true
			if scene != null:
				var kyubey: Node = scene.get_node_or_null("Stage/Kyubey")
				if kyubey != null:
					_play_first_available_anim(kyubey, [&"sad"])
				_play_first_available_anim(scene.get_node_or_null("Stage/Boyfriend"), [&"hurt-short"])
			if HQSaves.cur_gauntlet_mods.has("InstantKillMechanics"):
				_kill_player_via_health(health)
		"dodge", "dodge-perfect":
			if scene != null:
				var kyubey: Node = scene.get_node_or_null("Stage/Kyubey")
				if kyubey != null:
					_play_first_available_anim(kyubey, [&"hey"])
			if result == "dodge-perfect":
				_heal_player(health, 0.05)
				HQSaves.hq_dodge_perfects += 1
	_kyoko_current_result = ""
	_kyoko_dodge_result = ""


func _damage_player(health: Node, damage: float) -> void:
	if health == null:
		return
	var min_health: Variant = health.get("min_health")
	var max_health: Variant = health.get("max_health")
	var low := float(min_health) if min_health != null else 0.0
	var high := float(max_health) if max_health != null else 100.0
	health.health = clampf(float(health.health) - damage / 50.0, low, high)


func _heal_player(health: Node, amount: float) -> void:
	if health == null:
		return
	var max_health: Variant = health.get("max_health")
	var high := float(max_health) if max_health != null else 100.0
	health.health = minf(float(health.health) + amount, high)


func _kill_player_via_health(health: Node) -> void:
	if health == null:
		return
	var min_health: Variant = health.get("min_health")
	health.health = float(min_health) if min_health != null else 0.0


func _play_first_available_anim(node: Node, candidates: Array[StringName]) -> void:
	if node == null or not node.has_method("play"):
		return
	var anim_player: Variant = node.get("animation_player")
	for anim: StringName in candidates:
		if anim_player != null and anim_player.has_animation(anim):
			node.play(anim)
			return


func _show_dodge_judgement(result: String) -> void:
	var tex_path := "res://holyquintet_mod/source/images/game/judgement/dodges.png"
	if not ResourceLoader.exists(tex_path):
		return
	var frame_index: int = KYOKO_DODGE_FRAME_INDEX.get(result, 2)
	var canvas := CanvasLayer.new()
	canvas.layer = 24
	get_tree().current_scene.add_child(canvas)
	var sprite := Sprite2D.new()
	sprite.texture = load(tex_path)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, frame_index * 120.0, 400.0, 120.0)
	sprite.scale = Vector2(1.25, 1.25)
	sprite.rotation_degrees = randi_range(-5, 5)
	sprite.position = canvas.get_viewport().get_visible_rect().size / 2.0
	sprite.position.x = minf(sprite.position.x * 1.4, canvas.get_viewport().get_visible_rect().size.x - 220.0)
	canvas.add_child(sprite)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(1.0, 1.0), 4.0 * _step_crochet()).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sprite, "modulate:a", 1.0, 4.0 * _step_crochet()).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "position:y", sprite.position.y - 25.0, 8.0 * _step_crochet()).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(sprite, "modulate:a", 0.0, 8.0 * _step_crochet()).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): canvas.queue_free())


## ─── BPM Change ─────────────────────────────────────────────────────────────
## Params: [bpm: float]
func _evt_bpm_change(params: Array) -> void:
	if params.is_empty():
		return
	var new_bpm: float = params[0]
	if _clock != null and _clock.has_method("set_bpm"):
		_clock.set_bpm(new_bpm)


## ─── Time Signature Change ──────────────────────────────────────────────────
## Params: [numerator: int, denominator: int]
func _evt_time_sig_change(params: Array) -> void:
	if params.size() < 2:
		return
	# Time signature changes affect step calculations, simplified
	pass


## ─── Gameplay Configuration ─────────────────────────────────────────────────
func _evt_gameplay_config(params: Array) -> void:
	pass


## ─── Scroll Speed Change ────────────────────────────────────────────────────
## Params: [speed: float, tween: bool, duration: float]
func _evt_scroll_speed(params: Array) -> void:
	if params.is_empty():
		return
	var target_speed: float = params[0]
	var scene = get_tree().current_scene
	if scene == null:
		return
	# Find note controllers and update their scroll speed
	for child in scene.get_children():
		if child.has_method("set") and "scroll_speed" in child:
			child.scroll_speed = target_speed
	# Also try to find via UILayer/UI/Player
	var player_ui = scene.get_node_or_null("UILayer/UI/Player")
	if player_ui != null and "scroll_speed" in player_ui:
		player_ui.scroll_speed = target_speed


## ─── Helpers ────────────────────────────────────────────────────────────────
func _step_crochet() -> float:
	## step_crochet = 60 / BPM / 4, derived from the clock's time changes.
	var changes: Array = _clock.get_time_changes() if _clock != null else []
	if changes.size() > 0:
		var tc = changes[0]
		if tc.bpm > 0:
			return 60.0 / tc.bpm / 4.0
	return 60.0 / 205.0 / 4.0
