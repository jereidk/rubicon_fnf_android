extends Control
## HQ Goduka Prompt — yes/no wish question shown after several deaths.
## Ports the mod's HQGodukaPrompt substate: yes retries with goduka enabled,
## no retries on a goduka cooldown.

var selection: int = -1
var can_control: bool = false
var _star_offset: float = 0.0

@onready var goduka_tex: TextureRect = $Goduka
@onready var question_label: Label = $QuestionLabel
@onready var song_label: Label = $SongLabel
@onready var yes_label: Label = $YesLabel
@onready var no_label: Label = $NoLabel
@onready var black_overlay: ColorRect = $BlackOverlay
@onready var fade_rect: ColorRect = $FadeRect
@onready var stars_tex: TextureRect = $Stars

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	black_overlay.modulate.a = 1.0
	fade_rect.modulate.a = 1.0
	var scene = get_tree().current_scene
	if scene != null:
		song_label.text = "Song: %s" % scene.name
	# Slide goduka in
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, 1.0).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween()
	tw2.tween_property(goduka_tex, "position:x", goduka_tex.position.x - 250.0, 1.5).set_ease(Tween.EASE_OUT)
	var tw3 := create_tween()
	tw3.tween_interval(1.2)
	tw3.tween_callback(func(): can_control = true)
	# Bob goduka
	var bob := create_tween().set_loops()
	bob.tween_property(goduka_tex, "position:y", goduka_tex.position.y + 5.0, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bob.tween_property(goduka_tex, "position:y", goduka_tex.position.y, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# Bob the question labels
	var qbob := create_tween().set_loops()
	qbob.tween_property(question_label, "position:y", question_label.position.y + 12.0, 2.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	qbob.tween_property(question_label, "position:y", question_label.position.y, 2.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _process(delta: float) -> void:
	_star_offset -= 15.0 * delta
	stars_tex.position.y = _star_offset
	stars_tex.position.y = fposmod(_star_offset, stars_tex.size.y)
	if not can_control:
		return
	if Input.is_action_just_pressed("ui_up") and selection != 0:
		_set_selection(0)
	elif Input.is_action_just_pressed("ui_down") and selection != 1:
		_set_selection(1)
	elif Input.is_action_just_pressed("ui_accept"):
		_confirm()

func _set_selection(idx: int) -> void:
	selection = idx
	yes_label.scale = Vector2(1.25, 1.25) if idx == 0 else Vector2(0.75, 0.75)
	no_label.scale = Vector2(1.25, 1.25) if idx == 1 else Vector2(0.75, 0.75)
	yes_label.modulate.a = 1.0 if idx == 0 else 0.5
	no_label.modulate.a = 1.0 if idx == 1 else 0.5

func _confirm() -> void:
	if selection == -1:
		return
	can_control = false
	if selection == 0:
		HQSaves.goduka_enabled = true
		HQSaves.goduka_cooldown = -1
	else:
		HQSaves.goduka_cooldown = 5
	fade_rect.color = Color.WHITE if selection == 0 else Color.BLACK
	fade_rect.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(fade_rect, "modulate:a", 1.0, 1.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): get_tree().reload_current_scene())
