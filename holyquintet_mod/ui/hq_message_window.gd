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

@onready var window_box: TextureRect = $WindowBox
@onready var icon_tex: TextureRect = $WindowBox/Icon
@onready var title_label: Label = $WindowBox/TitleLabel
@onready var body_label: Label = $WindowBox/BodyLabel
@onready var left_sprite: TextureRect = $LeftButton/Sprite
@onready var left_label: Label = $LeftButton/Label
@onready var right_sprite: TextureRect = $RightButton/Sprite
@onready var right_label: Label = $RightButton/Label

var _atlas_normal: AtlasTexture
var _atlas_highlighted: AtlasTexture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)

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
		_leaving = true
		if _selected == -1:
			if on_left.is_valid():
				on_left.call()
		else:
			if on_right.is_valid():
				on_right.call()
		if on_complete.is_valid():
			on_complete.call()
	elif Input.is_action_just_pressed("ui_cancel"):
		if on_back.is_valid():
			on_back.call()
