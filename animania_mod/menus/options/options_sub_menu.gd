class_name OptionsSubMenu
extends Node2D
## Options sub-menu hub — faithful port of animania::states::OptionsSubMenu.
##
## Shows the sub-menu buttons (Gameplay, Appearance, Misc, Experemental, Exit)
## and handles selection/transition between them.

# ─── Constants ─────────────────────────────────────────────────────────────

const SCREEN := Vector2(1920.0, 1080.0)
const SOUND_SWITCH := "res://animania_mod/source/sounds/animania/menu/menu_switch.ogg"
const SOUND_CONFIRM := "res://animania_mod/source/sounds/animania/options/confirm.ogg"

const CATEGORIES := ["Gameplay", "Appearance", "Misc", "Experemental"]
const ITEM_SPACING := 70.0
const LIST_X := 960.0
const LIST_Y_START := 300.0

# ─── Fields ───────────────────────────────────────────────────────────────

var options_screen: Node2D  ## Reference to the parent OptionsScreen
var cur_selected: int = 0
var optionss: Array[Node2D] = []
var animating: bool = false
var categoties: Array[String] = []  ## typo preserved from binary

## Static memory for remembering selection across visits
static var cur_select_memory: int = 0

var item_container: Node2D
var title_spr: Sprite2D
var bg_art: Sprite2D

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	# Restore last selection
	cur_selected = cur_select_memory

	_build_ui()
	_create_title()
	_create_bg_art()
	_create_category_items()
	_refresh_selection()


func _unhandled_input(event: InputEvent) -> void:
	if animating:
		return
	if event.is_action_pressed("ui_up"):
		change_item(-1)
	elif event.is_action_pressed("ui_down"):
		change_item(1)
	elif event.is_action_pressed("ui_accept"):
		do_selection()
	elif event.is_action_pressed("ui_cancel"):
		exit_to_main_menu()


# ─── UI building ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	item_container = Node2D.new()
	item_container.name = "ItemContainer"
	add_child(item_container)


func _create_title() -> void:
	title_spr = Sprite2D.new()
	title_spr.name = "TitleImage"
	title_spr.texture = load("res://animania_mod/source/images/menus/options/eng/options.png") as Texture2D
	title_spr.position = Vector2(SCREEN.x * 0.5, 120)
	add_child(title_spr)


func _create_bg_art() -> void:
	bg_art = Sprite2D.new()
	bg_art.name = "BgArt"
	bg_art.texture = load("res://animania_mod/source/images/menus/options/optionsbgart.png") as Texture2D
	bg_art.position = Vector2(SCREEN.x * 0.5, SCREEN.y * 0.5)
	bg_art.modulate.a = 0.3
	bg_art.z_index = -5
	add_child(bg_art)


# ─── Category items ───────────────────────────────────────────────────────

func _create_category_items() -> void:
	# Add category buttons
	for cat in CATEGORIES:
		categoties.append(cat)
		var item := _make_category_button(cat)
		optionss.append(item)
		item.position = Vector2(LIST_X, LIST_Y_START + (optionss.size() - 1) * ITEM_SPACING)
		item_container.add_child(item)

	# Add exit button at the bottom
	var exit_item := _make_exit_button()
	optionss.append(exit_item)
	exit_item.position = Vector2(LIST_X, LIST_Y_START + (optionss.size() - 1) * ITEM_SPACING)
	item_container.add_child(exit_item)


func _make_category_button(cat_name: String) -> Node2D:
	var container := Node2D.new()
	container.set_meta("category", cat_name)

	var label := Label.new()
	label.name = "Label"
	label.text = cat_name
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Center the label on the container
	label.position = Vector2(-150, -20)
	label.custom_minimum_size = Vector2(300, 40)
	container.add_child(label)

	return container


func _make_exit_button() -> Node2D:
	var container := Node2D.new()
	container.set_meta("category", "exit")

	var spr := Sprite2D.new()
	spr.texture = load("res://animania_mod/source/images/menus/options/eng/exit.png") as Texture2D
	container.add_child(spr)

	return container


# ─── Navigation ───────────────────────────────────────────────────────────

func change_item(amount: int) -> void:
	if animating:
		return
	cur_selected = clampi(cur_selected + amount, 0, optionss.size() - 1)
	cur_select_memory = cur_selected
	_refresh_selection()
	_play(SOUND_SWITCH)


func _refresh_selection() -> void:
	for i in optionss.size():
		var item := optionss[i]
		if "modulate" in item:
			item.modulate.a = 1.0 if i == cur_selected else 0.4
			if i == cur_selected:
				item.scale = Vector2(1.05, 1.05)
			else:
				item.scale = Vector2(1.0, 1.0)


# ─── Selection ────────────────────────────────────────────────────────────

func do_selection() -> void:
	if optionss.is_empty() or cur_selected >= optionss.size():
		return

	var item := optionss[cur_selected]
	var cat: String = item.get_meta("category", "")

	if cat == "exit":
		exit_to_main_menu()
		return

	animating = true
	_play(SOUND_CONFIRM)

	# Transition out
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func() -> void:
		if options_screen:
			options_screen.open_new_sub_menu(cat)
		queue_free()
	)


# ─── Exit ─────────────────────────────────────────────────────────────────

func exit_to_main_menu() -> void:
	if options_screen:
		options_screen._exit_to_menu()


# ─── Helpers ──────────────────────────────────────────────────────────────

func _play(path: String) -> void:
	if options_screen and options_screen.has_method("_play"):
		options_screen._play(path)
