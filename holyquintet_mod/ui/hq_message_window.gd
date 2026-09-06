extends Control
## HQ Message Window UI — shared two-choice prompt used by Setup, Goduka and
## Achievement screens. Ports the mod's MessageWindowUI with the common window
## art and a left/right selection between two actions.

var title_text: String = ""
var body_text: String = ""
var left_text: String = "No"
var right_text: String = "Yes"
var icon_name: String = "info"  # warning | danger | info

var on_left: Callable
var on_right: Callable
var on_complete: Callable
var on_back: Callable

var _selected_right: bool = true
var _leaving: bool = false

@onready var title_label: Label = $CenterContainer/VBox/TitleLabel
@onready var body_label: Label = $CenterContainer/VBox/BodyLabel
@onready var choices_label: Label = $CenterContainer/VBox/ChoicesLabel
@onready var icon_tex: TextureRect = $CenterContainer/VBox/Icon
@onready var bg_rect: ColorRect = $Dim


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.text = title_text
	body_label.text = body_text
	_update_icon()
	_refresh()


func _update_icon() -> void:
	var p := "res://holyquintet_mod/source/images/ui/common/window_icon_%s.png" % icon_name
	if ResourceLoader.exists(p):
		icon_tex.texture = load(p)
		icon_tex.visible = true
	else:
		icon_tex.visible = false


func _refresh() -> void:
	choices_label.text = ("►  " if _selected_right else "     ") + right_text + "\n" \
		+ ("     " if _selected_right else "►  ") + left_text


func _process(_delta: float) -> void:
	if _leaving:
		return
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		_selected_right = not _selected_right
		_refresh()
	elif Input.is_action_just_pressed("ui_accept"):
		_leaving = true
		if _selected_right:
			if on_right.is_valid():
				on_right.call()
		else:
			if on_left.is_valid():
				on_left.call()
		if on_complete.is_valid():
			on_complete.call()
		queue_free()
	elif Input.is_action_just_pressed("ui_cancel"):
		_leaving = true
		if on_back.is_valid():
			on_back.call()
		queue_free()
