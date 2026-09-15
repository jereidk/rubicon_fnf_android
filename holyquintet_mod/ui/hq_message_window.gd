extends Control
## HQ Message Window UI — shared two-choice prompt used by Setup, Goduka and
## Achievement screens. Ports the mod's MessageWindowUI + ButtonUI exactly:
## real window.png/button-basic.png assets, real layout math (screenCenter
## + ±250 offsets on a 1920x1080 canvas), and the real default of NEITHER
## button selected until the first left/right press (confirmed against
## real PC screenshots: "Keep Flashing Lights?" shows both buttons gray).

const WINDOW_TEX := preload("res://holyquintet_mod/source/images/ui/common/window.png")
const BUTTON_TEX := preload("res://holyquintet_mod/source/images/ui/common/button-basic.png")

var title_text: String = ""
var body_text: String = ""
var left_text: String = "No"
var right_text: String = "Yes"
var icon_name: String = "info"  # warning | danger | info

var on_left: Callable
var on_right: Callable
var on_complete: Callable
var on_back: Callable

# 0 = neither selected (real default), -1 = left, 1 = right.
var _selected: int = 0
var _leaving: bool = false

@onready var dim: ColorRect = $Dim
@onready var content: Control = $Content
@onready var window_box: TextureRect = $Content/WindowBox
@onready var icon_tex: TextureRect = $Content/WindowBox/Icon
@onready var title_label: Label = $Content/WindowBox/TitleLabel
@onready var body_label: Label = $Content/WindowBox/BodyLabel
@onready var left_button: Control = $Content/LeftButton
@onready var left_sprite: TextureRect = $Content/LeftButton/Sprite
@onready var left_highlight: TextureRect = $Content/LeftButton/Highlight
@onready var left_label: Label = $Content/LeftButton/Label
@onready var right_button: Control = $Content/RightButton
@onready var right_sprite: TextureRect = $Content/RightButton/Sprite
@onready var right_highlight: TextureRect = $Content/RightButton/Highlight
@onready var right_label: Label = $Content/RightButton/Label

var _atlas_normal: AtlasTexture
var _atlas_highlighted: AtlasTexture
var _left_highlight_tween: Tween
var _right_highlight_tween: Tween
var _alive: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	tree_exiting.connect(func(): _alive = false)

	window_box.texture = WINDOW_TEX

	_atlas_normal = AtlasTexture.new()
	_atlas_normal.atlas = BUTTON_TEX
	_atlas_normal.region = Rect2(0, 0, 450, 139)

	_atlas_highlighted = AtlasTexture.new()
	_atlas_highlighted.atlas = BUTTON_TEX
	_atlas_highlighted.region = Rect2(0, 139, 450, 139)

	title_label.text = title_text
	body_label.text = body_text
	left_label.text = left_text
	right_label.text = right_text
	_update_icon()
	_refresh()

	# Android has no keyboard/gamepad: a tap directly picks that side. The
	# original .hx only ever ran on desktop with keyboard nav, so this whole
	# touch path is new port-side work, not something to match against source.
	left_button.mouse_filter = Control.MOUSE_FILTER_STOP
	right_button.mouse_filter = Control.MOUSE_FILTER_STOP
	left_button.gui_input.connect(_on_button_gui_input.bind(-1))
	right_button.gui_input.connect(_on_button_gui_input.bind(1))

	_play_entrance()


func _play_entrance() -> void:
	# MessageWindowUI.new(): messageCam.scroll.y -= 15, then
	# FlxTween.num(-15, 0, 0.5, {ease: expoOut}, scroll.y = num) slides
	# everything drawn on messageCam (box, text, buttons) up into place.
	# msgBG (our Dim) separately fades alpha 0 -> 0.75 over the same 0.5s.
	content.position.y = -15.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(content, "position:y", 0.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(dim, "color:a", 0.75, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	# msgIcon starts 25px above its resting spot and invisible, then drops
	# in with an elastic ease while fading in; on completion it spawns one
	# glowPulse ghost, and 'danger' icons keep re-pulsing every 2.5s.
	var icon_rest_y := icon_tex.position.y
	icon_tex.position.y = icon_rest_y - 25.0
	icon_tex.modulate.a = 0.0
	var icon_tw := create_tween()
	icon_tw.set_parallel(true)
	icon_tw.tween_property(icon_tex, "position:y", icon_rest_y, 0.5) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_IN_OUT)
	icon_tw.tween_property(icon_tex, "modulate:a", 1.0, 0.5) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_IN_OUT)
	icon_tw.chain().tween_callback(_on_icon_settled)


func _on_icon_settled() -> void:
	_spawn_icon_glow()
	if icon_name == "danger":
		_danger_pulse_loop()


func _danger_pulse_loop() -> void:
	await get_tree().create_timer(2.5).timeout
	if not _alive:
		return
	_spawn_icon_glow()
	_danger_pulse_loop()


func _spawn_icon_glow() -> void:
	# GenUtil.glowPulse(msgIcon, 1.0, 0.5, 1.0): a copy of the icon, additive
	# blend, alpha 1 -> 0 and scale +0.5 over 1.0s (sineOut), then destroyed.
	var glow := TextureRect.new()
	glow.texture = icon_tex.texture
	glow.size = icon_tex.size
	glow.position = icon_tex.position
	glow.pivot_offset = icon_tex.size / 2.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = icon_tex.expand_mode
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	icon_tex.get_parent().add_child(glow)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(glow, "scale", Vector2(1.5, 1.5), 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(glow, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(glow.queue_free)


func _update_icon() -> void:
	var p := "res://holyquintet_mod/source/images/ui/common/window_icon_%s.png" % icon_name
	if ResourceLoader.exists(p):
		icon_tex.texture = load(p)
		icon_tex.visible = true
	else:
		icon_tex.visible = false


func _refresh() -> void:
	# ButtonUI.set_selected: selected -> 'highlighted' frame + WHITE; not
	# selected -> 'normal' frame + GRAY. Neither button is selected at start.
	left_sprite.texture = _atlas_highlighted if _selected == -1 else _atlas_normal
	left_sprite.modulate = Color.WHITE if _selected == -1 else Color(0.5, 0.5, 0.5)
	left_label.modulate = Color.WHITE if _selected == -1 else Color(0.5, 0.5, 0.5)

	right_sprite.texture = _atlas_highlighted if _selected == 1 else _atlas_normal
	right_sprite.modulate = Color.WHITE if _selected == 1 else Color(0.5, 0.5, 0.5)
	right_label.modulate = Color.WHITE if _selected == 1 else Color(0.5, 0.5, 0.5)

	_left_highlight_tween = _set_pulse(left_highlight, _left_highlight_tween, _selected == -1)
	_right_highlight_tween = _set_pulse(right_highlight, _right_highlight_tween, _selected == 1)


func _set_pulse(highlight: TextureRect, active_tween: Tween, should_pulse: bool) -> Tween:
	if active_tween:
		active_tween.kill()
	if not should_pulse:
		highlight.modulate.a = 0.0
		return null

	# ButtonUI.set_selected: button_Highlight.scale.set(1,1); alpha=1; then
	# FlxTween.tween(..., {'scale.x': 1.05, 'scale.y': 1.05, alpha: 0}, 1.0,
	# {ease: quadOut, type: LOOPING, loopDelay: 0.5}) — a ring that grows and
	# fades every 1.5s while the button stays selected.
	var tw := create_tween()
	tw.set_loops()
	tw.tween_callback(func():
		highlight.scale = Vector2.ONE
		highlight.modulate.a = 1.0)
	tw.tween_property(highlight, "scale", Vector2(1.05, 1.05), 1.0).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(highlight, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	return tw


func _process(_delta: float) -> void:
	if _leaving:
		return
	if Input.is_action_just_pressed("ui_left") and _selected != -1:
		_selected = -1
		_refresh()
	elif Input.is_action_just_pressed("ui_right") and _selected != 1:
		_selected = 1
		_refresh()
	elif Input.is_action_just_pressed("ui_accept") and _selected != 0:
		_confirm(_selected)
	elif Input.is_action_just_pressed("ui_cancel"):
		if on_back.is_valid():
			on_back.call()


func _on_button_gui_input(event: InputEvent, side: int) -> void:
	if _leaving:
		return
	var tapped: bool = false
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		tapped = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		tapped = st.pressed
	if tapped:
		_selected = side
		_refresh()
		_confirm(side)


func _confirm(side: int) -> void:
	_leaving = true
	if side == -1:
		if on_left.is_valid():
			on_left.call()
	else:
		if on_right.is_valid():
			on_right.call()
	if on_complete.is_valid():
		on_complete.call()
