extends Control
## Escena de arranque del engine. Lee los mods que ModLoader detecto y
## decide a donde ir:
##   - 0 mods  -> arranca la demo del engine.
##   - 1 mod   -> carga directo, sin preguntar.
##   - 2+ mods -> muestra una lista de botones para elegir uno.

const DEMO_SCENE := "res://songs/test/test.tscn"

var _list: VBoxContainer
var _header: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_populate()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var title := Label.new()
	title.text = "Rubicon Engine"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 120)
	title.size = Vector2(1920, 100)
	add_child(title)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 32)
	_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.position = Vector2(0, 240)
	_header.size = Vector2(1920, 60)
	add_child(_header)

	_list = VBoxContainer.new()
	_list.position = Vector2(660, 340)
	_list.size = Vector2(600, 600)
	_list.add_theme_constant_override("separation", 24)
	add_child(_list)

func _populate() -> void:
	var enabled: Array = []
	for m in ModLoader.mods:
		if m.get("enabled", true):
			enabled.append(m)

	if enabled.is_empty():
		_header.text = "No hay mods instalados en:\n%s" % ModLoader.mods_root
		_add_button("Ir a la demo del engine", _go_demo)
		return

	if enabled.size() == 1:
		_launch(enabled[0])
		return

	_header.text = "%d mods disponibles" % enabled.size()
	for m in enabled:
		_add_button(str(m.get("name", m["folder"])), func(): _launch(m))

func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 40)
	b.custom_minimum_size = Vector2(600, 100)
	b.pressed.connect(cb)
	_list.add_child(b)

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
	get_tree().change_scene_to_file(scene)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_demo()
