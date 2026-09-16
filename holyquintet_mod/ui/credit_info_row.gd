extends Control
## Referenced via preload(), not class_name: the global script class cache
## only updates after the editor rescans the project, which headless test
## runs don't trigger, causing "Could not find type" false negatives (same
## reasoning as gen_util.gd's own header).
## Ports ui/CreditInfoUI.hx: one row in the credits list — a border strip
## (freeplay/borders/base.png, frame 0 of a 980x122-per-frame spritesheet,
## same asset Freeplay's own song rows use), a small icon, a name, and a
## role line (shifted up 8px with one point smaller text when the real
## data marks it "tworow", for names whose role text needs 2 lines).

const BASE_TEX := preload("res://holyquintet_mod/source/images/ui/freeplay/borders/base.png")
const FONT := preload("res://holyquintet_mod/source/fonts/shingo.otf")
## Real: 0x880D090D (Flixel AARRGGBB) — the same outline color used
## elsewhere in this port at full alpha, here at the real class's own
## partial (0x88) alpha.
const OUTLINE_COLOR := Color(0x0d / 255.0, 0x09 / 255.0, 0x0d / 255.0, 0x88 / 255.0)
const GRAY := Color(0x80 / 255.0, 0x80 / 255.0, 0x80 / 255.0, 1.0)

## Mobile-only addition, not in the real game: tapping a row jumps the
## selection to it, since browsing Credits has no touch equivalent to
## Up/Down otherwise.
signal activated(row_index: int)

var row_index: int = -1
var selected: bool = false:
	set(v):
		selected = v
		_refresh_colors()

var sprite: TextureRect
var icon: TextureRect
var name_label: Label
var role_label: Label


func setup(data: Dictionary, index: int) -> void:
	row_index = index
	size = Vector2(980.0, 122.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	sprite = TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = BASE_TEX
	atlas.region = Rect2(0, 0, 980, 122)
	sprite.texture = atlas
	sprite.size = Vector2(980.0, 122.0)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)

	icon = TextureRect.new()
	icon.texture = load("res://holyquintet_mod/source/images/ui/credits/icons/%s.png" % data["img_name"])
	icon.size = Vector2(150.0, 150.0)
	icon.position = Vector2(-5.0, -20.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

	name_label = Label.new()
	name_label.position = Vector2(150.0, 20.0)
	name_label.size = Vector2(980.0 + 980.0 * 0.35, 60.0)
	name_label.add_theme_font_override("font", FONT)
	name_label.add_theme_font_size_override("font_size", 48)
	name_label.add_theme_constant_override("outline_size", 7)
	name_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = data["name"]
	add_child(name_label)

	role_label = Label.new()
	var role_y := 75.0
	var role_size := 24
	if data.get("tworow", false):
		role_y -= 8.0
		role_size -= 1
	role_label.position = Vector2(150.0, role_y)
	role_label.size = Vector2(980.0, 80.0)
	role_label.add_theme_font_override("font", FONT)
	role_label.add_theme_font_size_override("font_size", role_size)
	role_label.add_theme_constant_override("outline_size", 7)
	role_label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	role_label.text = data["role"]
	add_child(role_label)

	_refresh_colors()


func _refresh_colors() -> void:
	if not is_instance_valid(sprite):
		return
	var c := Color.WHITE if selected else GRAY
	sprite.modulate = c
	icon.modulate = c
	name_label.modulate = c
	role_label.modulate = c


func _on_gui_input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton:
		tapped = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = event.pressed
	if tapped:
		activated.emit(row_index)
