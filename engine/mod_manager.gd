extends Control
## Pantalla de gestion de mods. Lee ModLoader.mods y permite activar/
## desactivar, reordenar y abrir la carpeta de mods en el explorador
## del telefono. Los cambios se persisten en config/mods.json via
## ModLoader.set_enabled / move_mod.

const SELECTOR_SCENE := "res://engine/mod_selector.tscn"

var _list: VBoxContainer
var _header: Label
var _rows: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	ModLoader.mods_changed.connect(_refresh)
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "Mods"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 40)
	title.size = Vector2(1920, 80)
	add_child(title)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 24)
	_header.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.position = Vector2(0, 125)
	_header.size = Vector2(1920, 40)
	add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(160, 200)
	scroll.size = Vector2(1600, 700)
	add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	var back := Button.new()
	back.text = "Volver"
	back.add_theme_font_size_override("font_size", 32)
	back.position = Vector2(760, 960)
	back.size = Vector2(400, 80)
	back.pressed.connect(_go_selector)
	add_child(back)

	var open_btn := Button.new()
	open_btn.text = "Abrir carpeta de mods"
	open_btn.add_theme_font_size_override("font_size", 24)
	open_btn.position = Vector2(160, 960)
	open_btn.size = Vector2(420, 80)
	open_btn.pressed.connect(_open_mods_folder)
	add_child(open_btn)

	var refresh_btn := Button.new()
	refresh_btn.text = "Releer carpeta"
	refresh_btn.add_theme_font_size_override("font_size", 24)
	refresh_btn.position = Vector2(1340, 960)
	refresh_btn.size = Vector2(420, 80)
	refresh_btn.pressed.connect(_rescan)
	add_child(refresh_btn)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()

	if ModLoader.mods.is_empty():
		_header.text = "No hay mods en: " + ModLoader.mods_root
		var l := Label.new()
		l.text = "(Crea una carpeta por mod con su mod.json adentro)"
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_list.add_child(l)
		return

	_header.text = "%d mods en: %s" % [ModLoader.mods.size(), ModLoader.mods_root]
	for i in ModLoader.mods.size():
		_list.add_child(_build_row(i))


func _build_row(idx: int) -> Control:
	var m: Dictionary = ModLoader.mods[idx]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var check := CheckBox.new()
	check.button_pressed = ModLoader.is_enabled(m["folder"])
	check.custom_minimum_size = Vector2(60, 80)
	check.toggled.connect(func(v): ModLoader.set_enabled(m["folder"], v))
	row.add_child(check)

	var name_label := Label.new()
	name_label.text = str(m.get("name", m["folder"]))
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.custom_minimum_size = Vector2(700, 80)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var ver_label := Label.new()
	ver_label.text = "v" + str(m.get("version", "?"))
	ver_label.add_theme_font_size_override("font_size", 22)
	ver_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ver_label.custom_minimum_size = Vector2(140, 80)
	ver_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ver_label)

	var up := Button.new()
	up.text = "▲"
	up.add_theme_font_size_override("font_size", 28)
	up.custom_minimum_size = Vector2(80, 80)
	up.disabled = idx == 0
	up.pressed.connect(func(): ModLoader.move_mod(m["folder"], -1))
	row.add_child(up)

	var down := Button.new()
	down.text = "▼"
	down.add_theme_font_size_override("font_size", 28)
	down.custom_minimum_size = Vector2(80, 80)
	down.disabled = idx == ModLoader.mods.size() - 1
	down.pressed.connect(func(): ModLoader.move_mod(m["folder"], 1))
	row.add_child(down)

	return row


func _rescan() -> void:
	ModLoader.scan()
	ModLoader._load_all_enabled()
	_refresh()


func _open_mods_folder() -> void:
	if OS.get_name() == "Android":
		OS.shell_open("file://" + ModLoader.mods_root)
	else:
		OS.shell_open(ModLoader.mods_root)


func _go_selector() -> void:
	get_tree().change_scene_to_file(SELECTOR_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_selector()
