class_name OptionBoxBool
extends Node2D
## Boolean toggle option — faithful port of animania::states::OptionBoxBool.
##
## Shows a label and a checkmark that toggles on/off.
## Uses the checkmark sprite animation from the binary.

# ─── Constants ─────────────────────────────────────────────────────────────

const CHECKMARK_PATH := "res://animania_mod/source/images/menus/options/checkmark/spritemap1.png"
const FONT_SIZE := 26

# ─── Fields ───────────────────────────────────────────────────────────────

var option_name: String  ## Internal option key
var display_name: String  ## Shown label
var cur_value: bool = false
var change_func: Callable  ## Called with new value on change
var label: Label
var checkmark: Sprite2D
var _is_selected: bool = false
var _drill_sound: AudioStreamPlayer

# ─── Init ─────────────────────────────────────────────────────────────────

func setup(p_name: String, p_display: String, p_default: bool, p_change: Callable = Callable()) -> void:
	option_name = p_name
	display_name = p_display
	change_func = p_change
	cur_value = GameOptions.get_bool(p_name) if p_name in GameOptions.defaults else p_default


func _ready() -> void:
	# Label
	label = Label.new()
	label.name = "Label"
	label.text = display_name
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.position = Vector2(0, -15)
	add_child(label)

	# Checkmark
	checkmark = Sprite2D.new()
	checkmark.name = "Checkmark"
	checkmark.position = Vector2(350, 0)
	_setup_checkmark_frames()
	add_child(checkmark)

	_refresh()


# ─── Checkmark frames ─────────────────────────────────────────────────────

func _setup_checkmark_frames() -> void:
	var sf := SpriteFrames.new()
	sf.add_animation(&"idle")

	var tex := load(CHECKMARK_PATH) as Texture2D
	if tex == null:
		return

	# Unchecked state: sprite 0000 (x=196,y=59,w=56,h=53)
	var atlas_unchecked := AtlasTexture.new()
	atlas_unchecked.atlas = tex
	atlas_unchecked.region = Rect2(196, 59, 56, 53)

	# Checked state: sprite 0005 (x=196,y=1,w=55,h=57)
	var atlas_checked := AtlasTexture.new()
	atlas_checked.atlas = tex
	atlas_checked.region = Rect2(196, 1, 55, 57)

	sf.add_frame(&"idle", atlas_unchecked)
	sf.add_frame(&"idle", atlas_checked)

	checkmark.sprite_frames = sf
	checkmark.animation = &"idle"
	checkmark.frame = 0


# ─── Toggle ───────────────────────────────────────────────────────────────

func toggle() -> void:
	cur_value = not cur_value
	GameOptions.set_value(option_name, cur_value)
	_refresh()
	if change_func.is_valid():
		change_func.call(cur_value)


func _refresh() -> void:
	if checkmark:
		# Frame 0 = unchecked, frame 1 = checked
		checkmark.frame = 1 if cur_value else 0


# ─── Selection ────────────────────────────────────────────────────────────

func set_selected(selected: bool) -> void:
	_is_selected = selected
	if label:
		label.modulate = Color.WHITE if selected else Color(0.7, 0.7, 0.7)
	if selected:
		# Scale pulse
		scale = Vector2(1.05, 1.05)
	else:
		scale = Vector2(1.0, 1.0)
