extends CanvasLayer
## Burbuja flotante de acciones por mod. Reemplaza al antiguo boton X
## viejo (que era solo un X de salida) y agrega tres opciones base:
##   - Salir del mod (antes el X)
##   - Dev Console (antes el boton rojo del mod Holy Quintet)
##   - Debug Info (toggle del autoload DebugDisplay)
##
## Los mods pueden registrar opciones extra + codigos de dev console via
## la API publica (register_option / register_dev_code).
##
## Vive como autoload del engine en layer 185: por debajo de DebugDisplay
## (190) y ErrorToast (200), por encima del gameplay. Los dialogos de
## confirmacion heredan el layer porque son hijos directos.
##
## Visible solo cuando la escena actual NO es el ModSelector ni el
## ModManager (misma regla que tenia el boton X viejo).
##
## Uso desde un mod (en _ready()):
##   var bubble := get_node_or_null("/root/ModBubble")
##   if bubble != null:
##       bubble.register_dev_code("unlock", func(args): ...)
##       bubble.register_dev_code("lockall", func(_args): ...)

const LAYER := 185
const SELECTOR_SCENE := "res://engine/mod_selector.tscn"
const MANAGER_SCENE := "res://engine/mod_manager.tscn"

const FAB_SIZE := 72.0
const FAB_MARGIN := 24.0
const FAB_ALPHA := 0.6
const OPTION_SIZE := 60.0
const OPTION_SPACING := 8.0
const OPTION_ALPHA := 0.55
const ANIM_TIME := 0.22

const FONT_PATH := "res://resources/fonts/fnt_vcr.ttf"

## Colores por tipo de opcion. Consistente con la paleta del engine.
const COLOR_EXIT   := Color(0.85, 0.20, 0.20, 1.0)  # rojo
const COLOR_CONSOLE := Color(0.95, 0.75, 0.25, 1.0)  # amarillo
const COLOR_DEBUG  := Color(0.35, 0.75, 0.95, 1.0)  # celeste
const COLOR_CUSTOM := Color(0.55, 0.85, 0.55, 1.0)  # verde

## Icono dibujado para cada opcion base.
enum IconKind { EXIT, CONSOLE, DEBUG, CUSTOM, FAB_CLOSED, FAB_OPEN }

## Opcion del bubble: {id, label, icon, color, callback, node}
var _options: Array[Dictionary] = []
## Codigos de dev console registrados por el mod.
## Estructura: {prefix: String -> Callable(args)}
var _dev_codes: Dictionary = {}

## Nodos UI.
var _fab: Control = null
var _option_root: Control = null
var _option_nodes: Array = []
## Input del dev console (creado on-demand).
var _console_root: Control = null
var _console_input: LineEdit = null
var _console_label: Label = null

var _expanded: bool = false
var _last_scene_path: String = ""


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_option_root = Control.new()
	_option_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_option_root.position = Vector2.ZERO
	add_child(_option_root)

	_fab = _make_button(FAB_SIZE, IconKind.FAB_CLOSED, Color.WHITE, "")
	_fab.name = "FAB"
	_fab.mouse_filter = Control.MOUSE_FILTER_STOP
	_fab.gui_input.connect(_on_fab_input)
	_fab.mouse_entered.connect(func(): MenuMusic.play_scroll())
	add_child(_fab)

	_register_base_options()

	_update_visibility()


## Las 3 opciones base del engine.
func _register_base_options() -> void:
	register_option("exit", "Salir", IconKind.EXIT, COLOR_EXIT, _do_exit)
	register_option("console", "Consola", IconKind.CONSOLE, COLOR_CONSOLE, _open_console)
	register_option("debug", "Debug", IconKind.DEBUG, COLOR_DEBUG, _toggle_debug)


## ============================================================
# API publica
# ============================================================

## Registra una opcion extra en el bubble. Se apila por encima de las
## base, con color verde por defecto.
## id: identificador unico (para desregistrar despues)
## label: texto corto que aparece al lado del icono
## icon: IconKind (default CUSTOM)
## color: color del icono dibujado
## cb: Callable sin argumentos
func register_option(id: String, label: String, icon: int, color: Color, cb: Callable) -> void:
	# Reemplazar si ya existe.
	for i in _options.size():
		if _options[i]["id"] == id:
			_options[i] = {"id": id, "label": label, "icon": icon, "color": color, "callback": cb}
			_rebuild_option_nodes()
			return
	_options.append({"id": id, "label": label, "icon": icon, "color": color, "callback": cb})
	_rebuild_option_nodes()


## Registra un handler para codigos de dev console. El handler recibe el
## texto pasado despues del prefix:
##   bubble.register_dev_code("unlock", func(args): ...)
## Un input "unlock ChamberOfLight" llama handler("ChamberOfLight").
func register_dev_code(prefix: String, handler: Callable) -> void:
	_dev_codes[prefix] = handler


## Limpia todos los codigos registrados. Util para re-registrar desde
## cero cuando un mod se recarga.
func clear_dev_codes() -> void:
	_dev_codes.clear()


## Desregistra una opcion custom.
func unregister_option(id: String) -> void:
	for i in _options.size():
		if _options[i]["id"] == id:
			_options.remove_at(i)
			_rebuild_option_nodes()
			return


## ============================================================
# Construccion de nodos
# ============================================================

func _rebuild_option_nodes() -> void:
	for n in _option_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_option_nodes.clear()
	_build_option_nodes()


func _build_option_nodes() -> void:
	for i in _options.size():
		var opt: Dictionary = _options[i]
		var b := _make_button(OPTION_SIZE, opt["icon"], opt["color"], opt["label"])
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var cb: Callable = opt["callback"]
		b.gui_input.connect(func(ev):
			if not (ev is InputEventScreenTouch or ev is InputEventMouseButton):
				return
			if not ev.pressed:
				return
			MenuMusic.play_confirm()
			_close()
			if cb.is_valid():
				cb.call()
		)
		_option_root.add_child(b)
		_option_nodes.append(b)
	_update_layout()


## Posiciona el FAB abajo-derecha y apila los sub-botones arriba.
func _update_layout() -> void:
	if _fab == null:
		return
	var vp := get_viewport().get_visible_rect().size
	# FAB anclado abajo-derecha.
	var fx := vp.x - FAB_MARGIN - FAB_SIZE
	var fy := vp.y - FAB_MARGIN - FAB_SIZE
	_fab.position = Vector2(fx, fy)
	_fab.size = Vector2(FAB_SIZE, FAB_SIZE)

	# Sub-botones apilados arriba del FAB.
	var cx := fx + (FAB_SIZE - OPTION_SIZE) / 2.0
	var base_y := fy - OPTION_SPACING
	for i in _option_nodes.size():
		var b: Control = _option_nodes[i]
		var y := base_y - OPTION_SIZE - i * (OPTION_SIZE + OPTION_SPACING)
		b.position = Vector2(cx, y)
		b.size = Vector2(OPTION_SIZE, OPTION_SIZE)


func _make_button(size: float, icon: int, color: Color, label: String) -> Control:
	var b := Control.new()
	b.custom_minimum_size = Vector2(size, size)
	b.size = Vector2(size, size)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.set_meta("icon_kind", icon)
	b.set_meta("icon_color", color)
	b.set_meta("label", label)
	b.set_meta("size_px", size)
	b.pivot_offset = Vector2(size, size) / 2.0
	# Asignar el script de dibujado (mod_bubble_button.gd) via set_script.
	# GDScript no permite clases inline en runtime: es el patron estandar.
	var script := load("res://engine/mod_bubble_button.gd")
	if script != null:
		b.set_script(script)
	return b


# ============================================================
# Interaccion
# ============================================================

func _on_fab_input(ev: InputEvent) -> void:
	var tapped := false
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif ev is InputEventScreenTouch and ev.pressed:
		tapped = true
	if not tapped:
		return
	MenuMusic.play_confirm()
	if _expanded:
		_close()
	else:
		_open()


func _open() -> void:
	if _expanded:
		return
	_expanded = true
	if _fab != null:
		_fab.set_meta("icon_kind", IconKind.FAB_OPEN)
		_fab.queue_redraw()
		var tw := _fab.create_tween()
		tw.tween_property(_fab, "rotation", deg_to_rad(45.0), ANIM_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Sub-botones: animacion de stagger desde abajo.
	for i in _option_nodes.size():
		var b: Control = _option_nodes[i]
		b.visible = true
		b.modulate.a = 0.0
		var target := b.position
		b.position.y = target.y + 40.0
		var tw := b.create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_property(b, "position", target, ANIM_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "modulate:a", 1.0, ANIM_TIME)


func _close() -> void:
	if not _expanded:
		return
	_expanded = false
	if _fab != null:
		_fab.set_meta("icon_kind", IconKind.FAB_CLOSED)
		_fab.queue_redraw()
		var tw := _fab.create_tween()
		tw.tween_property(_fab, "rotation", 0.0, ANIM_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for b in _option_nodes:
		if not is_instance_valid(b):
			continue
		var tw := b.create_tween()
		tw.tween_property(b, "modulate:a", 0.0, ANIM_TIME)
		tw.tween_callback(func(): b.visible = false)


# ============================================================
# Acciones base
# ============================================================

func _do_exit() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Salir del mod"
	dialog.dialog_text = "¿Volver al menu principal?\nEl mod se cerrara."
	dialog.ok_button_text = "Si"
	dialog.cancel_button_text = "No"
	dialog.confirmed.connect(_on_confirm_exit)
	dialog.canceled.connect(func(): MenuMusic.play_cancel())
	add_child(dialog)
	dialog.popup_centered()


func _on_confirm_exit() -> void:
	MenuMusic.play_cancel()
	ModLoader.restore_default_settings()
	get_tree().change_scene_to_file(SELECTOR_SCENE)


func _toggle_debug() -> void:
	var dd := get_node_or_null("/root/DebugDisplay")
	if dd == null:
		return
	dd.visible = not dd.visible


# ============================================================
# Dev Console
# ============================================================

func _open_console() -> void:
	if _console_root != null and is_instance_valid(_console_root):
		return
	_console_root = Control.new()
	_console_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_console_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_console_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev):
		if ev is InputEventScreenTouch and ev.pressed:
			_close_console()
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_console()
	)
	_console_root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	sb.border_color = Color(0.5, 0.7, 0.9, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(1920.0 / 2.0 - 400.0, 1080.0 / 2.0 - 80.0)
	panel.custom_minimum_size = Vector2(800, 0)
	_console_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_console_label = Label.new()
	_console_label.text = "Dev Console — escribi un comando"
	if ResourceLoader.exists(FONT_PATH):
		_console_label.add_theme_font_override("font", load(FONT_PATH))
	_console_label.add_theme_font_size_override("font_size", 20)
	_console_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_console_label)

	_console_input = LineEdit.new()
	_console_input.placeholder_text = "comando (ej: unlock ChamberOfLight)"
	_console_input.virtual_keyboard_enabled = true
	_console_input.text_submitted.connect(_on_console_submit)
	if ResourceLoader.exists(FONT_PATH):
		_console_input.add_theme_font_override("font", load(FONT_PATH))
	_console_input.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_console_input)

	_console_input.grab_focus()


func _close_console() -> void:
	if _console_root != null and is_instance_valid(_console_root):
		_console_root.queue_free()
	_console_root = null
	_console_input = null
	_console_label = null


func _on_console_submit(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		_close_console()
		return
	# Match por prefix mas largo primero (asi "unlockall" no es capturado
	# por "unlock " cuando el usuario quiere el comando exacto).
	var prefixes := _dev_codes.keys()
	prefixes.sort_custom(func(a, b): return a.length() > b.length())
	for prefix in prefixes:
		if text == prefix or text.begins_with(prefix + " "):
			var args := text.substr(prefix.length()).strip_edges()
			var cb: Callable = _dev_codes[prefix]
			if cb.is_valid():
				cb.call(args)
			_close_console()
			return
	# No match.
	if _console_label != null:
		_console_label.text = "Comando desconocido: %s" % text
		_console_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		MenuMusic.play_cancel()
		_console_input.text = ""


# ============================================================
# Visibilidad por escena
# ============================================================

func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	var path := "" if scene == null else scene.scene_file_path
	if path != _last_scene_path:
		_last_scene_path = path
		_update_visibility()
		_update_layout()


func _update_visibility() -> void:
	if _fab == null:
		return
	var tree := get_tree()
	if tree == null:
		_fab.visible = false
		return
	var scene := tree.current_scene
	if scene == null:
		_fab.visible = false
		return
	var path: String = scene.scene_file_path
	var is_engine_ui: bool = path.ends_with("mod_selector.tscn") or path.ends_with("mod_manager.tscn")
	_fab.visible = not is_engine_ui
	# Si nos vamos a una escena del engine, cerramos el bubble y la consola.
	if is_engine_ui:
		_close()
		_close_console()
