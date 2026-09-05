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
        "Perfect": pass
        "Kyoko Attack": pass
        "Camera Alpha": pass
        "Camera Movement": pass
        "Camera Modulo Change": pass
        "BPM Change": pass
        "Time Signature Change": pass
        _: pass


func _evt_camera_zoom(params: Array) -> void:
    if params.size() < 2 or camera == null:
        return
    var tween_it: bool = params[0]
    var zoom_val: float = params[1]
    if tween_it:
        var steps: float = params[3] if params.size() > 3 else 4.0
        var dur := steps * 60.0 / 205.0
        var tw = create_tween()
        tw.tween_property(camera, "zoom", Vector2(zoom_val, zoom_val), dur)
    else:
        camera.zoom = Vector2(zoom_val, zoom_val)


func _evt_camera_position(params: Array) -> void:
    if params.size() < 2 or camera == null:
        return
    var x: float = params[0]
    var y: float = params[1]
    var tween_it: bool = params[2] if params.size() > 2 else false
    if tween_it:
        var steps: float = params[3] if params.size() > 3 else 4.0
        var dur := steps * 60.0 / 205.0
        var tw = create_tween()
        tw.tween_property(camera, "position", Vector2(x, y), dur)
    else:
        camera.position = Vector2(x, y)


func _evt_camera_flash(params: Array) -> void:
    if params.size() < 3:
        return
    var color_val: int = params[1]
    var duration: int = params[2]
    _ensure_flash_rect()
    _flash_rect.color = Color(color_val)
    _flash_rect.modulate.a = 1.0
    var dur := duration * 60.0 / 205.0
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


func _evt_camera_bop(params: Array) -> void:
    var rate: int = params[0] if params.size() > 0 else 4
    if camera == null:
        return
    var bumper = camera.get_node_or_null("RubiconCameraBumper")
    if bumper:
        if "bump_interval" in bumper:
            bumper.bump_interval = rate


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


func _evt_add_camera_zoom(params: Array) -> void:
    var amount: float = params[0] if params.size() > 0 else 0.1
    AnimaniaModule.punch(amount)


func _evt_play_animation(params: Array) -> void:
    if params.size() < 2:
        return
    var anim_name: String = params[1]
    var force: bool = params[2] if params.size() > 2 else false
    AnimaniaModule.play_character_animation(&"opponent", StringName(anim_name), force)


func _evt_gameplay_config(params: Array) -> void:
    pass


func _evt_scroll_speed(params: Array) -> void:
    pass
