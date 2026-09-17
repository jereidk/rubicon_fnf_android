extends Control
## Pantalla de gestion de mods. Lee ModLoader.mods y permite activar/
## desactivar, reordenar y abrir la carpeta de mods en el explorador
## del telefono. Los cambios se persisten en config/mods.json via
## ModLoader.set_enabled / move_mod.
##
## Layout responsive calculado en _layout(). Los botones de accion
## (checkbox, flechas) son de 120x120 escalados, comodos para dedo
## grande en pantallas de telefono.

const SELECTOR_SCENE := "res://engine/mod_selector.tscn"
const BASE_SIZE := Vector2(1920.0, 1080.0)

var _title: Label
var _header: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _back_btn: Button
var _open_btn: Button
var _refresh_btn: Button
var _rows: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	ModLoader.mods_changed.connect(_refresh)
	_refresh()
	resized.connect(_layout)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_title = Label.new()
	_title.text = "Mods"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color.WHITE)
	add_child(_title)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_header)

	_scroll = ScrollContainer.new()
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_back_btn = Button.new()
	_back_btn.text = "Volver"
	_back_btn.pressed.connect(_go_selector)
	add_child(_back_btn)

	_open_btn = Button.new()
	_open_btn.text = "Abrir carpeta"
	_open_btn.pressed.connect(_open_mods_folder)
	add_child(_open_btn)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Releer"
	_refresh_btn.pressed.connect(_rescan)
	add_child(_refresh_btn)


func _layout() -> void:
	var s: Vector2 = get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var k: float = minf(s.x / BASE_SIZE.x, s.y / BASE_SIZE.y)
	var w: float = s.x
	var h: float = s.y
	var pad: float = 40.0 * k

	_title.add_theme_font_size_override("font_size", maxi(24, int(56.0 * k)))
	_title.position = Vector2(0.0, pad)
	_title.size = Vector2(w, 80.0 * k)

	_header.add_theme_font_size_override("font_size", maxi(12, int(24.0 * k)))
	_header.position = Vector2(pad, 125.0 * k)
	_header.size = Vector2(w - pad * 2.0, 60.0 * k)

	var btn_h: float = 100.0 * k
	var bottom_y: float = h - btn_h - pad
	var scroll_h: float = bottom_y - 200.0 * k - pad

	_scroll.position = Vector2(pad * 4.0, 200.0 * k)
	_scroll.size = Vector2(w - pad * 8.0, maxf(200.0, scroll_h))
	_list.add_theme_constant_override("separation", maxi(6, int(12.0 * k)))

	for row in _rows:
		if not is_instance_valid(row):
			continue
		if row is HBoxContainer:
			row.add_theme_constant_override("separation", maxi(8, int(16.0 * k)))
			for child in row.get_children():
				if child is Button or child is CheckBox:
					child.custom_minimum_size = Vector2(120.0 * k, 120.0 * k)
					child.add_theme_font_size_override("font_size", maxi(20, int(32.0 * k)))
				elif child is Label:
					child.add_theme_font_size_override("font_size", maxi(16, int(32.0 * k)))
					child.custom_minimum_size = Vector2(0.0, 120.0 * k)

	var gap: float = 20.0 * k
	var back_w: float = minf(400.0 * k, (w - gap * 4.0) / 3.0)
	var open_w: float = back_w
	var refresh_w: float = back_w
	var start_x: float = (w - (back_w + open_w + refresh_w + gap * 2.0)) * 0.5

	_open_btn.position = Vector2(start_x, bottom_y)
	_open_btn.size = Vector2(open_w, btn_h)
	_open_btn.add_theme_font_size_override("font_size", maxi(14, int(24.0 * k)))

	_back_btn.position = Vector2(start_x + open_w + gap, bottom_y)
	_back_btn.size = Vector2(back_w, btn_h)
	_back_btn.add_theme_font_size_override("font_size", maxi(14, int(24.0 * k)))

	_refresh_btn.position = Vector2(start_x + open_w + gap + back_w + gap, bottom_y)
	_refresh_btn.size = Vector2(refresh_w, btn_h)
	_refresh_btn.add_theme_font_size_override("font_size", maxi(14, int(24.0 * k)))


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
		_layout()
		return

	_header.text = "%d mods en: %s" % [ModLoader.mods.size(), ModLoader.mods_root]
	for i in ModLoader.mods.size():
		var row := _build_row(i)
		_list.add_child(row)
		_rows.append(row)

	_layout()


func _build_row(idx: int) -> Control:
	var m: Dictionary = ModLoader.mods[idx]
	var row := HBoxContainer.new()

	var check := CheckBox.new()
	check.button_pressed = ModLoader.is_enabled(m["folder"])
	check.toggled.connect(func(v): ModLoader.set_enabled(m["folder"], v))
	row.add_child(check)

	var name_label := Label.new()
	name_label.text = str(m.get("name", m["folder"]))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var ver_label := Label.new()
	ver_label.text = "v" + str(m.get("version", "?"))
	ver_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ver_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ver_label)

	var up := Button.new()
	up.text = "▲"
	up.disabled = idx == 0
	up.pressed.connect(func(): ModLoader.move_mod(m["folder"], -1))
	row.add_child(up)

	var down := Button.new()
	down.text = "▼"
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
