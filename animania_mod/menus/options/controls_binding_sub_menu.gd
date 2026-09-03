class_name ControlsBindingSubMenu
extends Node2D
## Controls binding sub-menu — faithful port of animania::states::ControlsBindingSubMenu.
##
## Shows key binding categories (Gameplay, Interface, MISC) with interactive rebinding.
## Each category has a list of bindable actions. Pressing Enter starts rebinding;
## the next key pressed becomes the new binding.

# ─── Constants ─────────────────────────────────────────────────────────────

const SCREEN := Vector2(1920.0, 1080.0)
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/animania/options/confirm.ogg"
const SOUND_CANCEL := "res://animania_mod/source/sounds/cancelMenu.ogg"
const SOUND_HAMMER := "res://animania_mod/source/sounds/animania/options/hammer.ogg"
const SOUND_TAPE := "res://animania_mod/source/sounds/animania/options/tape.ogg"

const ITEM_SPACING := 50.0
const LIST_X := 400.0
const LIST_Y_START := 250.0

## Binding categories and their actions, matching the binary exactly.
## Each entry: [display_name, internal_action_name, sign_image_path]
const CATEGORIES := {
	"Gameplay": [
		["NOTE LEFT", "note_left", "left note sign"],
		["NOTE DOWN", "note_down", "down note sign"],
		["NOTE UP", "note_up", "up note sign"],
		["NOTE RIGHT", "note_right", "right note sign"],
	],
	"Interface": [
		["UI LEFT", "ui_left", ""],
		["UI DOWN", "ui_down", ""],
		["UI UP", "ui_up", ""],
		["UI RIGHT", "ui_right", ""],
		["RESET", "reset", ""],
		["ACCEPT", "ui_accept", ""],
		["BACK", "ui_cancel", ""],
		["PAUSE", "ui_pause", ""],
	],
	"MISC": [
		["VOLUME UP", "volume_up", ""],
		["VOLUME DOWN", "volume_down", ""],
		["VOLUME MUTE", "volume_mute", ""],
		["FULLSCREEN", "fullscreen", ""],
		["SCREENSHOT", "screenshot", ""],
		["DEBUG", "debug", ""],
	],
}

const CATEGORY_NAMES := ["Gameplay", "Interface", "MISC"]

## Default key mappings (matching Rubicon engine defaults)
const DEFAULT_BINDINGS := {
	"note_left": KEY_D,
	"note_down": KEY_F,
	"note_up": KEY_J,
	"note_right": KEY_K,
	"ui_left": KEY_LEFT,
	"ui_down": KEY_DOWN,
	"ui_up": KEY_UP,
	"ui_right": KEY_RIGHT,
	"reset": KEY_R,
	"ui_accept": KEY_ENTER,
	"ui_cancel": KEY_ESCAPE,
	"ui_pause": KEY_ESCAPE,
	"volume_up": KEY_KP_ADD,
	"volume_down": KEY_KP_SUBTRACT,
	"volume_mute": KEY_KP_0,
	"fullscreen": KEY_F11,
	"screenshot": KEY_PRINT,
	"debug": KEY_F12,
}

# ─── Fields ───────────────────────────────────────────────────────────────

var options_screen: Node2D  ## Reference to the parent OptionsScreen
var cur_selected: int = 0
var current_category_index: int = 0
var current_bindings: Array = []  ## Current category's bindings
var items: Array[Node2D] = []
var item_container: Node2D
var category_label: Label
var description_text: Label
var busy: bool = false
var binding_button: Node2D  ## The currently binding item
var key_used_to_enter_prompt: String = ""
var _wait_text_sine: float = 0.0
var _is_binding: bool = false
var _binding_item_index: int = -1
var memo_box: ColorRect
var memo_text: Label
var hammer_spr: Sprite2D
var tape_spr: Sprite2D
var wow_bg: ColorRect

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()
	_create_category_display()
	_create_memo_box()
	_create_binding_sprites()
	_load_binding_images()
	_build_controls()


func _process(delta: float) -> void:
	if _is_binding:
		_wait_text_sine += delta * 6.0
		if memo_text:
			memo_text.modulate.a = 0.5 + 0.5 * sin(_wait_text_sine)


func _unhandled_input(event: InputEvent) -> void:
	if busy:
		return

	if _is_binding:
		_handle_binding_input(event)
		return

	if event.is_action_pressed("ui_up"):
		change_item(-1)
	elif event.is_action_pressed("ui_down"):
		change_item(1)
	elif event.is_action_pressed("ui_left"):
		_change_category(-1)
	elif event.is_action_pressed("ui_right"):
		_change_category(1)
	elif event.is_action_pressed("ui_accept"):
		do_selection()
	elif event.is_action_pressed("ui_cancel"):
		exit_to_options()


# ─── Scene building ───────────────────────────────────────────────────────

func _build_ui() -> void:
	item_container = Node2D.new()
	item_container.name = "ItemContainer"
	add_child(item_container)

	# Category label
	category_label = Label.new()
	category_label.name = "CategoryLabel"
	category_label.add_theme_font_size_override("font_size", 36)
	category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category_label.position = Vector2(SCREEN.x * 0.5 - 150, 120)
	category_label.custom_minimum_size = Vector2(300, 50)
	add_child(category_label)

	# Description text
	description_text = Label.new()
	description_text.name = "DescriptionText"
	description_text.position = Vector2(SCREEN.x * 0.5, SCREEN.y - 80)
	description_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_text.add_theme_font_size_override("font_size", 22)
	description_text.modulate.a = 0.7
	add_child(description_text)

	# Wow BG (dark overlay)
	wow_bg = ColorRect.new()
	wow_bg.name = "WowBg"
	wow_bg.offset_right = SCREEN.x
	wow_bg.offset_bottom = SCREEN.y
	wow_bg.color = Color(0, 0, 0, 0.5)
	wow_bg.visible = false
	wow_bg.z_index = 5
	add_child(wow_bg)


func _create_category_display() -> void:
	pass  # Category is shown via category_label


func _create_memo_box() -> void:
	# Memo box - instruction panel shown during binding
	memo_box = ColorRect.new()
	memo_box.name = "MemoBox"
	memo_box.offset_right = 400
	memo_box.offset_bottom = 60
	memo_box.position = Vector2(SCREEN.x * 0.5 - 200, SCREEN.y * 0.5 - 30)
	memo_box.color = Color(0.1, 0.1, 0.15, 0.9)
	memo_box.visible = false
	memo_box.z_index = 10
	add_child(memo_box)

	memo_text = Label.new()
	memo_text.name = "MemoText"
	memo_text.text = "Press a key..."
	memo_text.add_theme_font_size_override("font_size", 24)
	memo_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	memo_text.position = Vector2(10, 15)
	memo_text.custom_minimum_size = Vector2(380, 30)
	memo_box.add_child(memo_text)


func _create_binding_sprites() -> void:
	# Hammer sprite (decorative)
	hammer_spr = Sprite2D.new()
	hammer_spr.name = "HammerSpr"
	hammer_spr.position = Vector2(SCREEN.x * 0.8, SCREEN.y * 0.3)
	hammer_spr.modulate.a = 0.0
	add_child(hammer_spr)

	# Tape sprite (decorative)
	tape_spr = Sprite2D.new()
	tape_spr.name = "TapeSpr"
	tape_spr.position = Vector2(SCREEN.x * 0.2, SCREEN.y * 0.7)
	tape_spr.modulate.a = 0.0
	add_child(tape_spr)


func _load_binding_images() -> void:
	# Load hammer sprite from atlas
	var hammer_atlas := load("res://animania_mod/source/images/menus/options/key_bindings.png") as Texture2D
	if hammer_atlas:
		# Use the first frame region from the XML
		var atlas := AtlasTexture.new()
		atlas.atlas = hammer_atlas
		atlas.region = Rect2(0, 0, 200, 200)
		hammer_spr.texture = atlas

	# Load tape sprite
	var tape_atlas := load("res://animania_mod/source/images/menus/options/long_binding.png") as Texture2D
	if tape_atlas:
		var atlas := AtlasTexture.new()
		atlas.atlas = tape_atlas
		atlas.region = Rect2(0, 0, 200, 200)
		tape_spr.texture = atlas


# ─── Controls building ────────────────────────────────────────────────────

func _build_controls() -> void:
	# Clear old items
	for item in items:
		if is_instance_valid(item):
			item.queue_free()
	items.clear()

	# Get current category
	if current_category_index >= CATEGORY_NAMES.size():
		current_category_index = 0
	var cat_name := CATEGORY_NAMES[current_category_index]
	current_bindings = CATEGORIES[cat_name]

	# Update category label
	if category_label:
		category_label.text = "CATEGORY: %s" % cat_name

	# Create binding items
	for i in current_bindings.size():
		var binding: Array = current_bindings[i]
		var display_name: String = binding[0]
		var action_name: String = binding[1]

		var item := _create_binding_item(display_name, action_name, i)
		items.append(item)
		item.position = Vector2(LIST_X, LIST_Y_START + i * ITEM_SPACING)
		item_container.add_child(item)

	cur_selected = clampi(cur_selected, 0, items.size() - 1)
	_refresh_selection()


func _create_binding_item(display_name: String, action_name: String, index: int) -> Node2D:
	var container := Node2D.new()
	container.set_meta("action_name", action_name)
	container.set_meta("display_name", display_name)
	container.set_meta("index", index)

	# Label
	var label := Label.new()
	label.name = "Label"
	label.text = display_name
	label.add_theme_font_size_override("font_size", 26)
	label.position = Vector2(0, -15)
	container.add_child(label)

	# Key name display
	var key_label := Label.new()
	key_label.name = "KeyLabel"
	key_label.add_theme_font_size_override("font_size", 26)
	key_label.position = Vector2(350, -15)
	key_label.text = _get_key_name(action_name)
	container.add_child(key_label)

	# Arrow indicators
	var arrow_left := Label.new()
	arrow_left.name = "ArrowLeft"
	arrow_left.text = "<"
	arrow_left.add_theme_font_size_override("font_size", 20)
	arrow_left.position = Vector2(320, -12)
	arrow_left.modulate.a = 0.0
	container.add_child(arrow_left)

	var arrow_right := Label.new()
	arrow_right.name = "ArrowRight"
	arrow_right.text = ">"
	arrow_right.add_theme_font_size_override("font_size", 20)
	arrow_right.position = Vector2(500, -12)
	arrow_right.modulate.a = 0.0
	container.add_child(arrow_right)

	return container


# ─── Key name resolution ──────────────────────────────────────────────────

func _get_key_name(action_name: String) -> String:
	# Check Godot's InputMap for the action
	if InputMap.has_action(action_name):
		var events := InputMap.action_get_events(action_name)
		if events.size() > 0:
			var event := events[0]
			if event is InputEventKey:
				return OS.get_keycode_string(event.keycode) if event.keycode != 0 else OS.get_keycode_string(event.physical_keycode)

	# Check our defaults
	if action_name in DEFAULT_BINDINGS:
		return OS.get_keycode_string(DEFAULT_BINDINGS[action_name])

	return "NONE"


func _set_key_binding(action_name: String, keycode: int) -> void:
	# Remove existing bindings
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)

	# Add new binding
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action_name, key_event)

	# Save to game options
	GameOptions.set_value("key_%s" % action_name, keycode)


# ─── Navigation ───────────────────────────────────────────────────────────

func change_item(amount: int) -> void:
	cur_selected = clampi(cur_selected + amount, 0, items.size() - 1)
	_refresh_selection()
	_play(SOUND_SWITCH)


func _change_category(dir: int) -> void:
	current_category_index = (current_category_index + dir) % CATEGORY_NAMES.size()
	if current_category_index < 0:
		current_category_index = CATEGORY_NAMES.size() - 1
	cur_selected = 0
	_build_controls()
	_play(SOUND_SWITCH)


func _refresh_selection() -> void:
	for i in items.size():
		var item := items[i]
		if "modulate" in item:
			item.modulate.a = 1.0 if i == cur_selected else 0.5
		if i == cur_selected:
			item.scale = Vector2(1.05, 1.05)
		else:
			item.scale = Vector2(1.0, 1.0)


# ─── Selection / Binding ──────────────────────────────────────────────────

func do_selection() -> void:
	if items.is_empty() or cur_selected >= items.size():
		return

	_is_binding = true
	_binding_item_index = cur_selected
	_wait_text_sine = 0.0

	# Show memo box
	if memo_box:
		memo_box.visible = true
	if memo_text:
		var item := items[cur_selected]
		var display: String = item.get_meta("display_name", "")
		memo_text.text = "Press a key for %s..." % display
		memo_text.modulate.a = 1.0
	if wow_bg:
		wow_bg.visible = true

	_play(SOUND_CONFIRM)


func _handle_binding_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var item := items[_binding_item_index]
		var action_name: String = item.get_meta("action_name", "")

		# Map Animania action names to Godot actions
		var godot_action := _map_action(action_name)

		# Set the binding
		_set_key_binding(godot_action, event.keycode)

		# Update display
		var key_label := item.get_node_or_null("KeyLabel") as Label
		if key_label:
			key_label.text = OS.get_keycode_string(event.keycode)

		# Hide memo box
		if memo_box:
			memo_box.visible = false
		if wow_bg:
			wow_bg.visible = false

		_is_binding = false
		_binding_item_index = -1

		# Play hammer animation
		_play_hammer_animation()

		_play(SOUND_CONFIRM)


func _map_action(action_name: String) -> String:
	# Map Animania action names to Godot's built-in actions
	match action_name:
		"ui_left": return "ui_left"
		"ui_down": return "ui_down"
		"ui_up": return "ui_up"
		"ui_right": return "ui_right"
		"ui_accept": return "ui_accept"
		"ui_cancel": return "ui_cancel"
		"ui_pause": return "ui_pause"
		_: return action_name


# ─── Animations ───────────────────────────────────────────────────────────

func _play_hammer_animation() -> void:
	if hammer_spr == null:
		return
	hammer_spr.modulate.a = 1.0
	hammer_spr.position.y -= 20
	var tw := create_tween()
	tw.tween_property(hammer_spr, "position:y", hammer_spr.position.y + 40, 0.1).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(hammer_spr, "modulate:a", 0.0, 0.3).set_delay(0.1)
	_play(SOUND_HAMMER)


func _play_tape_animation() -> void:
	if tape_spr == null:
		return
	tape_spr.modulate.a = 0.8
	var tw := create_tween()
	tw.tween_property(tape_spr, "modulate:a", 0.0, 0.5)
	_play(SOUND_TAPE)


# ─── Exit ─────────────────────────────────────────────────────────────────

func exit_to_options() -> void:
	if _is_binding:
		# Cancel binding
		_is_binding = false
		_binding_item_index = -1
		if memo_box:
			memo_box.visible = false
		if wow_bg:
			wow_bg.visible = false
		return

	_play(SOUND_CANCEL)
	if options_screen and options_screen.has_method("change_sub_menu"):
		options_screen.change_sub_menu(0)


# ─── Helpers ──────────────────────────────────────────────────────────────

func _play(path: String) -> void:
	if options_screen and options_screen.has_method("_play"):
		options_screen._play(path)
