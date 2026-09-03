extends Node2D
## Base class for all options sub-menus.
## Faithful port of animania::states::BaseSubMenu.
##
## Provides the common structure: title image, scrollable item list,
## description text, camera follow with lerp, and input handling.

# ─── Constants ─────────────────────────────────────────────────────────────

const SCREEN := Vector2(1920.0, 1080.0)
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/animania/options/confirm.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"

## Font for option text
const FONT_PATH := "res://animania_mod/source/fonts/VCR OSD Mono Cyr.ttf"
const FONT_SIZE := 28

## Item spacing in the scrollable list
const ITEM_SPACING := 50.0
const LIST_X := 400.0
const LIST_Y_START := 250.0

# ─── Fields ───────────────────────────────────────────────────────────────

var options_screen: Node2D  ## Reference to the parent OptionsScreen
var cur_selected: int = 0
var items: Array[Node2D] = []
var description_text: Label
var items_camera: Camera2D
var cam_follow: Node2D
var _change_hold_time: float = 0.0
var target_cam_y: float = 0.0
var lerp_cam_y: float = 0.0
var _hold_dir: float = 0.0
var _hold_delay: float = 0.0
var _hold_speed: float = 0.0
var item_container: Node2D

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_base_ui()
	create_title()
	setup_camera()
	setup_ui()
	create_pref_items()
	_refresh_selection()


func _process(delta: float) -> void:
	# Camera lerp
	if items_camera and cam_follow:
		target_cam_y = cam_follow.position.y
		lerp_cam_y = lerp(lerp_cam_y, target_cam_y, 8.0 * delta)
		items_camera.position.y = lerp_cam_y

	# Hold repeat for up/down
	if _hold_dir != 0.0:
		_hold_delay -= delta
		if _hold_delay <= 0.0:
			_change_selection(_hold_dir)
			_hold_speed = maxf(_hold_speed * 0.85, 0.05)
			_hold_delay = _hold_speed


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_change_selection(-1.0)
		_hold_dir = -1.0
		_hold_delay = 0.4
		_hold_speed = 0.4
	elif event.is_action_released("ui_up") and _hold_dir == -1.0:
		_hold_dir = 0.0
	elif event.is_action_pressed("ui_down"):
		_change_selection(1.0)
		_hold_dir = 1.0
		_hold_delay = 0.4
		_hold_speed = 0.4
	elif event.is_action_released("ui_down") and _hold_dir == 1.0:
		_hold_dir = 0.0
	elif event.is_action_pressed("ui_left"):
		_handle_item_change(-1)
	elif event.is_action_pressed("ui_right"):
		_handle_item_change(1)
	elif event.is_action_pressed("ui_accept"):
		do_selection()
	elif event.is_action_pressed("ui_cancel"):
		exit_to_options()


# ─── Scene building ───────────────────────────────────────────────────────

func _build_base_ui() -> void:
	item_container = Node2D.new()
	item_container.name = "ItemContainer"
	add_child(item_container)

	description_text = Label.new()
	description_text.name = "DescriptionText"
	description_text.position = Vector2(SCREEN.x * 0.5, SCREEN.y - 80)
	description_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_text.add_theme_font_size_override("font_size", 22)
	description_text.modulate.a = 0.7
	add_child(description_text)


# ─── createTitle ──────────────────────────────────────────────────────────

func create_title() -> void:
	# Override in subclasses to load the title image
	pass


func _load_title_image(path: String) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.name = "TitleImage"
	spr.texture = load(path) as Texture2D
	spr.position = Vector2(SCREEN.x * 0.5, 80)
	add_child(spr)
	return spr


# ─── setupCamera ──────────────────────────────────────────────────────────

func setup_camera() -> void:
	items_camera = Camera2D.new()
	items_camera.name = "SubMenuCamera"
	items_camera.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	add_child(items_camera)

	cam_follow = Node2D.new()
	cam_follow.name = "CamFollow"
	cam_follow.position = Vector2(0, LIST_Y_START)
	add_child(cam_follow)

	lerp_cam_y = LIST_Y_START


# ─── setupUI ──────────────────────────────────────────────────────────────

func setup_ui() -> void:
	# Override in subclasses for additional UI
	pass


# ─── createPrefItems ──────────────────────────────────────────────────────

func create_pref_items() -> void:
	# Override in subclasses to add option items
	pass


# ─── Item management ──────────────────────────────────────────────────────

func add_option_item(node: Node2D) -> void:
	items.append(node)
	node.position = Vector2(LIST_X, LIST_Y_START + items.size() * ITEM_SPACING)
	item_container.add_child(node)


func _change_selection(dir: float) -> void:
	if items.is_empty():
		return
	cur_selected = clampi(cur_selected + int(dir), 0, items.size() - 1)
	_refresh_selection()
	_play(SOUND_SWITCH)


func _refresh_selection() -> void:
	for i in items.size():
		var item := items[i]
		if item.has_method("set_selected"):
			item.set_selected(i == cur_selected)
		elif "modulate" in item:
			item.modulate.a = 1.0 if i == cur_selected else 0.5

	# Update camera follow
	if not items.is_empty() and cur_selected < items.size():
		var target_y := LIST_Y_START + cur_selected * ITEM_SPACING
		cam_follow.position.y = target_y


# ─── Item change (left/right) ─────────────────────────────────────────────

func _handle_item_change(dir: int) -> void:
	if items.is_empty() or cur_selected >= items.size():
		return
	var item := items[cur_selected]
	if item.has_method("change_value"):
		item.change_value(dir)
		_play(SOUND_SWITCH)


# ─── get_currentOption ────────────────────────────────────────────────────

func get_current_option() -> String:
	if items.is_empty() or cur_selected >= items.size():
		return ""
	var item := items[cur_selected]
	if "option_name" in item:
		return item.option_name
	return ""


# ─── doSelection ──────────────────────────────────────────────────────────

func do_selection() -> void:
	if items.is_empty() or cur_selected >= items.size():
		return
	var item := items[cur_selected]
	if item.has_method("toggle"):
		item.toggle()
		_play(SOUND_CONFIRM)
	elif item.has_method("change_value"):
		item.change_value(1)
		_play(SOUND_CONFIRM)


# ─── exitToOptions ────────────────────────────────────────────────────────

func exit_to_options() -> void:
	_play(SOUND_CANCEL)
	if options_screen and options_screen.has_method("change_sub_menu"):
		options_screen.change_sub_menu(0)  # refresh current


# ─── _floatTitle ──────────────────────────────────────────────────────────

func _float_title(spr: Sprite2D) -> void:
	if spr == null:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(spr, "position:y", spr.position.y - 5.0, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spr, "position:y", spr.position.y, 1.0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


# ─── destroy ──────────────────────────────────────────────────────────────

func destroy() -> void:
	queue_free()


# ─── Helpers ──────────────────────────────────────────────────────────────

func _play(path: String) -> void:
	if options_screen and options_screen.has_method("_play"):
		options_screen._play(path)


func _make_label(text: String, pos: Vector2, size: int = FONT_SIZE, color: Color = Color.WHITE) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
