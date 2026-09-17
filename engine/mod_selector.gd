extends Control
## Escena de arranque del engine. Lee los mods que ModLoader detecto y
## decide a donde ir:
##   - 0 mods  -> arranca la demo del engine.
##   - 1 mod   -> carga directo, sin preguntar.
##   - 2+ mods -> muestra una lista de botones para elegir uno.
##
## Layout responsive: los tamanos y posiciones se calculan en _layout() a
## partir del viewport actual, escalando desde un diseno base de 1920x1080.
## En pantallas mas altas (20:9 en un telefono) el contenido sigue centrado
## y visible en vez de salirse por abajo. La escala usa el lado que menos da
## de si para que en pantallas anchas no se agrande de mas.

const DEMO_SCENE := "res://songs/test/test.tscn"
const MANAGER_SCENE := "res://engine/mod_manager.tscn"
const BASE_SIZE := Vector2(1920.0, 1080.0)

var _title: Label
var _header: Label
var _list: VBoxContainer
var _mods_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_populate()
	resized.connect(_layout)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_title = Label.new()
	_title.text = "Rubicon Engine"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color.WHITE)
	add_child(_title)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	add_child(_header)

	_list = VBoxContainer.new()
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_list)

	_mods_btn = Button.new()
	_mods_btn.text = "Mods..."
	_mods_btn.pressed.connect(_open_manager)
	add_child(_mods_btn)


func _layout() -> void:
	var s: Vector2 = get_viewport_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var k: float = minf(s.x / BASE_SIZE.x, s.y / BASE_SIZE.y)
	var w: float = s.x
	var h: float = s.y

	_title.add_theme_font_size_override("font_size", maxi(24, int(64.0 * k)))
	_title.position = Vector2(0.0, 120.0 * k)
	_title.size = Vector2(w, 100.0 * k)

	_header.add_theme_font_size_override("font_size", maxi(14, int(32.0 * k)))
	_header.position = Vector2(0.0, 240.0 * k)
	_header.size = Vector2(w, 60.0 * k)

	var list_w: float = minf(600.0 * k, w - 80.0)
	var list_h: float = 600.0 * k
	_list.position = Vector2((w - list_w) * 0.5, 340.0 * k)
	_list.size = Vector2(list_w, list_h)
	_list.add_theme_constant_override("separation", maxi(8, int(24.0 * k)))
	for child in _list.get_children():
		if child is Button:
			var b: Button = child
			b.add_theme_font_size_override("font_size", maxi(16, int(40.0 * k)))
			b.custom_minimum_size = Vector2(list_w, 100.0 * k)

	var btn_w: float = minf(400.0 * k, w - 80.0)
	var btn_h: float = 100.0 * k
	_mods_btn.position = Vector2((w - btn_w) * 0.5, h - btn_h - 40.0 * k)
	_mods_btn.size = Vector2(btn_w, btn_h)
	_mods_btn.add_theme_font_size_override("font_size", maxi(16, int(32.0 * k)))


func _populate() -> void:
	for c in _list.get_children():
		c.queue_free()

	var enabled: Array = []
	for m in ModLoader.mods:
		if m.get("enabled", true):
			enabled.append(m)

	if enabled.is_empty():
		_header.text = "No hay mods instalados en:\n%s" % ModLoader.mods_root
		_add_button("Ir a la demo del engine", _go_demo)
		_layout()
		return

	if enabled.size() == 1:
		_launch(enabled[0])
		return

	_header.text = "%d mods disponibles" % enabled.size()
	for m in enabled:
		_add_button(str(m.get("name", m["folder"])), func(): _launch(m))
	_layout()


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	_list.add_child(b)


func _open_manager() -> void:
	get_tree().change_scene_to_file(MANAGER_SCENE)


func _go_demo() -> void:
	get_tree().change_scene_to_file(DEMO_SCENE)


func _launch(m: Dictionary) -> void:
	var scene: String = str(m.get("main_scene", ""))
	if scene.is_empty():
		push_error("[ModSelector] mod %s no define main_scene" % m["folder"])
		_go_demo()
		return
	if not ResourceLoader.exists(scene):
		push_error("[ModSelector] main_scene no encontrada: %s" % scene)
		_go_demo()
		return

	if scene.ends_with(".gd"):
		var script = load(scene)
		if not (script is GDScript):
			push_error("[ModSelector] %s no es un GDScript valido" % scene)
			_go_demo()
			return
		var node := Node.new()
		node.name = "ModRoot"
		node.set_script(script)
		var old := get_tree().current_scene
		get_tree().root.add_child(node)
		get_tree().current_scene = node
		if old != null:
			old.queue_free()
		return

	get_tree().change_scene_to_file(scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_demo()
