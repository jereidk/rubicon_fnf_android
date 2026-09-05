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

## Camera Movement state: simple directional nudge on beat.
var _cam_movement_enabled: bool = false
var _cam_movement_direction: int = 0  ## 0=right, 1=left

signal stage_event


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
		"BPM Change": pass
		"Time Signature Change": pass
		"Perfect": pass
		"Kyoko Attack": pass
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


## ─── Gameplay Configuration ─────────────────────────────────────────────────
func _evt_gameplay_config(params: Array) -> void:
	pass


## ─── Scroll Speed Change ────────────────────────────────────────────────────
func _evt_scroll_speed(params: Array) -> void:
	pass


## ─── Helpers ────────────────────────────────────────────────────────────────
func _step_crochet() -> float:
	## step_crochet = 60 / BPM / 4, derived from the clock's time changes.
	var changes: Array = _clock.get_time_changes() if _clock != null else []
	if changes.size() > 0:
		var tc = changes[0]
		if tc.bpm > 0:
			return 60.0 / tc.bpm / 4.0
	return 60.0 / 205.0 / 4.0
