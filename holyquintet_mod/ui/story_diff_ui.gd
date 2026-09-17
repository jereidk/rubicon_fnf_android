extends Control
## Ports ui/StoryDiffUI.hx — the one-time "Select your difficulty" popup
## shown on a fresh save's first Story confirm. The real component's own
## FlxCamera scroll-in + BlurFilter intro are replaced with a plain slide
## tween on this whole Control (no separate render camera in this port).

const GenUtil := preload("res://holyquintet_mod/scripts/gen_util.gd")

var left_action: Callable
var right_action: Callable
var back_action: Callable

var _cur_sel: String = ""

@onready var bg: ColorRect = $BG
@onready var header: Label = $Header
@onready var easy_sprite: TextureRect = $Easy
@onready var hard_sprite: TextureRect = $Hard


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

	position.y = -15.0
	create_tween().tween_property(self, "position:y", 0.0, 0.5) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	bg.modulate.a = 0.0
	create_tween().tween_property(bg, "modulate:a", 0.75, 0.5) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	header.text = "Select your difficulty:"
	# Touch/mouse: keyboard-only port of StoryDiffUI in the .tscn leaves
	# both sprites at MOUSE_FILTER_IGNORE. Override here and route taps
	# to the same left_action/right_action calls _unhandled_input uses.
	easy_sprite.mouse_filter = Control.MOUSE_FILTER_STOP
	hard_sprite.mouse_filter = Control.MOUSE_FILTER_STOP
	easy_sprite.gui_input.connect(_on_diff_gui_input.bind("easy"))
	hard_sprite.gui_input.connect(_on_diff_gui_input.bind("hard"))
	GenUtil.play_ui_sound(self, "open")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left") and _cur_sel != "easy":
		_cur_sel = "easy"
		GenUtil.play_ui_sound(self, "move")
		easy_sprite.modulate = Color.WHITE
		easy_sprite.scale = Vector2.ONE
		hard_sprite.modulate = Color(0.5, 0.5, 0.5)
		hard_sprite.scale = Vector2(0.75, 0.75)
		_play_diff_sound("diff_easy")
		_spawn_glow(easy_sprite)
	elif event.is_action_pressed("ui_right") and _cur_sel != "hard":
		_cur_sel = "hard"
		GenUtil.play_ui_sound(self, "move")
		hard_sprite.modulate = Color.WHITE
		hard_sprite.scale = Vector2.ONE
		easy_sprite.modulate = Color(0.5, 0.5, 0.5)
		easy_sprite.scale = Vector2(0.75, 0.75)
		_play_diff_sound("diff_hard")
		_spawn_glow(hard_sprite)
	elif event.is_action_pressed("ui_accept") and _cur_sel != "":
		if _cur_sel == "easy":
			left_action.call()
		else:
			right_action.call()
		GenUtil.play_ui_sound(self, "confirm")
		queue_free()
	elif event.is_action_pressed("ui_cancel"):
		back_action.call()
		GenUtil.play_ui_sound(self, "close")
		queue_free()


func _play_diff_sound(name: String) -> void:
	var path := "res://holyquintet_mod/source/sounds/ui/freeplay/%s.ogg" % name
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer.new()
	player.stream = load(path)
	get_tree().root.add_child.call_deferred(player)
	player.finished.connect(player.queue_free)
	player.play.call_deferred()


func _spawn_glow(spr: TextureRect) -> void:
	# GenUtil.glowPulse(sprite, startingAlpha, size, time) — same additive
	# ghost-copy pattern already used for hq_message_window's icon glow.
	var glow := TextureRect.new()
	glow.texture = spr.texture
	glow.size = spr.size
	glow.position = spr.position
	glow.scale = spr.scale
	glow.pivot_offset = spr.pivot_offset
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.modulate = spr.modulate
	spr.get_parent().add_child(glow)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(glow, "scale", spr.scale * 1.1, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(glow, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(glow.queue_free)

func _on_diff_gui_input(event: InputEvent, diff: String) -> void:
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if not tapped:
		return

	_cur_sel = diff
	if diff == "easy":
		left_action.call()
	else:
		right_action.call()
	GenUtil.play_ui_sound(self, "confirm")
	queue_free()
