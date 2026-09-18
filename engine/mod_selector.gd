extends Control
## Escena de arranque del engine. Lee los mods que ModLoader detecto y
## decide a donde ir:
##   - 0 mods  -> muestra la demo del engine.
##   - 1+ mods -> siempre muestra la lista (nunca auto-carga).
##
## Layout con Containers nativos: no hay posicion absoluta ni factor de
## escala manual. Godot distribuye el espacio solo y funciona en cualquier
## aspecto de pantalla (16:9, 20:9, tablet, lo que sea).
##
## Por que nunca auto-carga con un solo mod: si el unico mod falla al
## cargar (script con error, main_scene mal escrito, .pck que no se monto),
## auto-cargarlo sin mostrar la lista ocultaba el error y el usuario
## terminaba en la demo sin saber por que. Mostrando la lista siempre, el
## usuario ve el mod, lo toca, y si falla ve el mensaje de error.

const DEMO_SCENE := "res://songs/test/test.tscn"
const MANAGER_SCENE := "res://engine/mod_manager.tscn"

## Fondo opcional. Si el archivo no existe, se usa un ColorRect oscuro
## solido. Los PNG de FNF son menuBGBlue.png y menuBGMagenta.png, que
## se pueden copiar a resources/images/ con cualquiera de esos nombres.
const BG_CANDIDATES: Array[String] = [
	"res://resources/images/menuBGBlue.png",
	"res://resources/images/menu_bg.png",
	"res://resources/images/menu_bg.ktx",
]

var _title: Label
var _header: Label
var _list: VBoxContainer
var _mods_btn: Button
var _error_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# Rescan al entrar: si el usuario agrego o quito un mod con el juego
	# abierto, lo ve al volver a esta pantalla sin reiniciar.
	ModLoader.scan()
	_populate()


func _build_ui() -> void:
	_build_background()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "Rubicon Engine"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 64)
	_title.add_theme_color_override("font_color", Color.WHITE)
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	vbox.add_child(_title)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header.add_theme_font_size_override("font_size", 28)
	_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_theme_constant_override("separation", 16)
	scroll.add_child(_list)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.add_theme_font_size_override("font_size", 22)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_error_label.visible = false
	vbox.add_child(_error_label)

	_mods_btn = Button.new()
	_mods_btn.text = "Mods..."
	_mods_btn.custom_minimum_size = Vector2(0, 90)
	_mods_btn.add_theme_font_size_override("font_size", 32)
	_mods_btn.pressed.connect(_open_manager)
	_mods_btn.mouse_entered.connect(func(): MenuMusic.play_scroll())
	vbox.add_child(_mods_btn)


## Fondo: si hay un PNG de menuBG en el repo, se dibuja estirado y
## centrado. Si no, se usa un ColorRect oscuro como fallback.
func _build_background() -> void:
	var bg_tex: Texture2D = null
	for path in BG_CANDIDATES:
		if ResourceLoader.exists(path):
			bg_tex = load(path)
			break

	if bg_tex != null:
		var tr := TextureRect.new()
		tr.texture = bg_tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.05, 0.02, 0.08, 1.0)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)


func _populate() -> void:
	for c in _list.get_children():
		c.queue_free()
	_error_label.visible = false

	var enabled: Array = []
	for m in ModLoader.mods:
		if m.get("enabled", true):
			enabled.append(m)

	if enabled.is_empty():
		_header.text = "No hay mods instalados en:\n%s" % ModLoader.mods_root
		_add_button("Ir a la demo del engine", _go_demo)
		return

	_header.text = "%d mod%s disponible%s" % [
		enabled.size(),
		"" if enabled.size() == 1 else "s",
		"" if enabled.size() == 1 else "s",
	]
	for m in enabled:
		_add_button(str(m.get("name", m["folder"])), func(): _launch(m))


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 100)
	b.add_theme_font_size_override("font_size", 36)
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): MenuMusic.play_scroll())
	b.mouse_entered.connect(func(): MenuMusic.play_scroll())
	_list.add_child(b)


func _open_manager() -> void:
	get_tree().change_scene_to_file(MANAGER_SCENE)


func _go_demo() -> void:
	MenuMusic.play_confirm()
	MenuMusic.fade_out_music(0.4)
	get_tree().change_scene_to_file(DEMO_SCENE)


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true


func _launch(m: Dictionary) -> void:
	MenuMusic.play_confirm()
	MenuMusic.fade_out_music(0.4)
	var scene: String = str(m.get("main_scene", ""))
	if scene.is_empty():
		_show_error("Mod '%s' no define main_scene.\nFolder: %s" % [m["folder"], m["path"]])
		return
	if not ResourceLoader.exists(scene):
		_show_error("No encontrado: %s\nVerifica que el archivo exista dentro del mod." % scene)
		return

	if scene.ends_with(".gd"):
		var script = load(scene)
		if not (script is GDScript):
			_show_error("No es un GDScript valido: %s" % scene)
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
