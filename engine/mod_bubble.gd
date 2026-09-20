extends CanvasLayer
## ModBubble — circulo flotante arrastrable que expande a un pill
## horizontal con las acciones disponibles del mod.
##
## Estados:
##   IDLE      circulo con alpha FAB_ALPHA_IDLE
##   PRESSED   alpha sube a FAB_ALPHA_ACTIVE
##   DRAGGING  sigue al dedo con clamp a los bordes (margen EDGE_MARGIN)
##   EXPANDED  pill horizontal al lado del FAB con los botones
##
## Reglas:
##   - Tap sin drag en el FAB -> expandir / colapsar
##   - Drag sobre el FAB -> mover (persiste posicion en disco)
##   - Tap fuera del pill (zona de juego) -> colapsar
##   - Solo visible en escenas de mods (path no empieza con res://engine/)
##   - Animacion de intro zoom+alpha la primera vez que aparece tras
##     entrar a un mod
##
## API publica (compatible con la version anterior):
##   register_option(id, label, icon, color, cb)
##   register_dev_code(prefix, handler)
##   clear_dev_codes()
##   unregister_option(id)

const LAYER := 185
const ENGINE_SCENE_PREFIX := "res://engine/"

# --- Geometria
const FAB_SIZE := 64.0
const OPTION_SIZE := 56.0
const PILL_GAP := 6.0
const EDGE_MARGIN := 16.0

# --- Alpha
const FAB_ALPHA_IDLE := 0.5
const FAB_ALPHA_ACTIVE := 1.0

# --- Deteccion de gestos
const TAP_MAX_TIME := 0.25
const TAP_MAX_DIST := 12.0

# --- Animacion
const ANIM_TIME := 0.22
const INTRO_TIME := 0.45
const INTRO_SCALE := 1.15

# --- Persistencia
const PERSIST_PATH := "user://bubble_pos.cfg"

# --- Iconos
enum IconKind { EXIT, CONSOLE, DEBUG, CUSTOM, FAB_CLOSED, FAB_OPEN }

# --- Colores
const COLOR_EXIT    := Color(0.85, 0.20, 0.20, 1.0)
const COLOR_CONSOLE := Color(0.95, 0.75, 0.25, 1.0)
const COLOR_DEBUG   := Color(0.35, 0.75, 0.95, 1.0)
const COLOR_CUSTOM  := Color(0.55, 0.85, 0.55, 1.0)

var _options: Array[Dictionary] = []
var _dev_codes: Dictionary = {}

var _fab: Control = null
var _option_nodes: Array = []
var _console_root: Control = null
var _console_input: LineEdit = null
var _console_label: Label = null

var _expanded: bool = false
var _dragging: bool = false
var _press_time: float = 0.0
var _drag_dist: float = 0.0
var _drag_offset: Vector2 = Vector2.ZERO
var _expand_dir: int = -1  # -1 = izquierda, +1 = derecha
var _last_scene_path: String = ""
var _home_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fab = _make_button(FAB_SIZE, IconKind.FAB_CLOSED, Color.WHITE, "")
	_fab.name = "FAB"
	_fab.mouse_filter = Control.MOUSE_FILTER_STOP
	_fab.gui_input.connect(_on_fab_input)
	# Arranca invisible: _update_visibility() decide si mostrarlo. Si la
	# escena actual es un mod, _set_visible(true) va a ver was=false y
	# va a disparar la animacion de intro. Sin esta linea el FAB nace
	# visible y el intro nunca corre.
	_fab.visible = false
	_fab.modulate.a = FAB_ALPHA_IDLE
	add_child(_fab)

	_register_base_options()
	# El viewport todavia no tiene su tamano real en _ready() (sobre todo
	# en Android landscape). Diferimos el calculo de _home_pos y el
	# layout al primer frame, cuando el tamano ya es el definitivo.
	_deferred_bootstrap.call_deferred()


func _deferred_bootstrap() -> void:
	_home_pos = _load_or_default_pos()
	_apply_home_pos()
	_update_visibility()


func _register_base_options() -> void:
	register_option("exit", "Salir", IconKind.EXIT, COLOR_EXIT, _do_exit)
	register_option("console", "Consola", IconKind.CONSOLE, COLOR_CONSOLE, _open_console)
	register_option("debug", "Debug", IconKind.DEBUG, COLOR_DEBUG, _toggle_debug)


# ============================================================
# API publica
# ============================================================

func register_option(id: String, label: String, icon: int, color: Color, cb: Callable) -> void:
	for i in _options.size():
		if _options[i]["id"] == id:
			_options[i] = {"id": id, "label": label, "icon": icon, "color": color, "callback": cb}
			_rebuild_option_nodes()
			return
	_options.append({"id": id, "label": label, "icon": icon, "color": color, "callback": cb})
	_rebuild_option_nodes()


func register_dev_code(prefix: String, handler: Callable) -> void:
	_dev_codes[prefix] = handler


func clear_dev_codes() -> void:
	_dev_codes.clear()


func unregister_option(id: String) -> void:
	for i in _options.size():
		if _options[i]["id"] == id:
			_options.remove_at(i)
			_rebuild_option_nodes()
			return


# ============================================================
# Construccion de nodos
# ============================================================

func _rebuild_option_nodes() -> void:
	for n in _option_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_option_nodes.clear()
	for i in _options.size():
		var opt: Dictionary = _options[i]
		var b := _make_button(OPTION_SIZE, opt["icon"], opt["color"], opt["label"])
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.modulate.a = 0.0
		b.visible = false
		b.scale = Vector2.ZERO
		b.pivot_offset = Vector2(OPTION_SIZE, OPTION_SIZE) / 2.0
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
		add_child(b)
		_option_nodes.append(b)
	_update_layout()


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
	var script := load("res://engine/mod_bubble_button.gd")
	if script != null:
		b.set_script(script)
	return b


# ============================================================
# Layout
# ============================================================

## Calcula donde va el FAB cuando esta idle y donde va cada boton
## del pill cuando esta expandido, segun la direccion de expansion.
func _update_layout() -> void:
	if _fab == null:
		return
	var vp := get_viewport().get_visible_rect().size

	# FAB en su home (o donde lo dejo el usuario al arrastrar).
	_fab.position = _home_pos
	_fab.size = Vector2(FAB_SIZE, FAB_SIZE)

	# Direccion de expansion: si el FAB esta en la mitad izquierda,
	# crece hacia la derecha; si esta en la mitad derecha, hacia la
	# izquierda.
	_expand_dir = 1 if _home_pos.x + FAB_SIZE / 2.0 < vp.x / 2.0 else -1

	# Posiciona cada boton del pill en fila horizontal, segun la
	# direccion. El primer boton arranca pegado al borde del FAB
	# (con PILL_GAP de separacion).
	var fab_center_y := _home_pos.y + FAB_SIZE / 2.0
	for i in _option_nodes.size():
		var b: Control = _option_nodes[i]
		b.size = Vector2(OPTION_SIZE, OPTION_SIZE)
		b.pivot_offset = Vector2(OPTION_SIZE, OPTION_SIZE) / 2.0
		var offset_x: float
		if _expand_dir > 0:
			offset_x = _home_pos.x + FAB_SIZE + PILL_GAP + i * (OPTION_SIZE + PILL_GAP)
		else:
			offset_x = _home_pos.x - PILL_GAP - OPTION_SIZE - i * (OPTION_SIZE + PILL_GAP)
		var offset_y := fab_center_y - OPTION_SIZE / 2.0
		b.position = Vector2(offset_x, offset_y)


# ============================================================
# Interaccion
# ============================================================

func _on_fab_input(ev: InputEvent) -> void:
	# Touch start.
	if ev is InputEventScreenTouch and ev.pressed:
		_press_time = Time.get_ticks_msec() / 1000.0
		_drag_dist = 0.0
		_drag_offset = _home_pos - ev.position
		_dragging = false
		if _fab:
			_fab.modulate.a = FAB_ALPHA_ACTIVE
		return
	# Mouse start (desktop / debug).
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_press_time = Time.get_ticks_msec() / 1000.0
		_drag_dist = 0.0
		_drag_offset = _home_pos - ev.position
		_dragging = false
		if _fab:
			_fab.modulate.a = FAB_ALPHA_ACTIVE
		return
	# Drag.
	if ev is InputEventScreenDrag:
		_drag_dist += ev.relative.length()
		if _drag_dist > TAP_MAX_DIST:
			_dragging = true
			_move_fab_to(_drag_offset + ev.position)
		return
	# Release.
	if (ev is InputEventScreenTouch and not ev.pressed) \
	or (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed):
		var now := Time.get_ticks_msec() / 1000.0
		var elapsed := now - _press_time
		var is_tap := elapsed < TAP_MAX_TIME and _drag_dist < TAP_MAX_DIST and not _dragging
		if _fab:
			# Si el FAB queda visible sin expandir, vuelve a alpha idle.
			if not _expanded:
				_fab.modulate.a = FAB_ALPHA_IDLE
		if is_tap:
			if _expanded:
				_close()
			else:
				_open()
			MenuMusic.play_confirm()
		elif _dragging:
			# Fin de drag: guardar posicion persistida.
			_save_pos()
			_update_layout()
		_dragging = false


## Mueve el FAB a una posicion absoluta, con clamp a los bordes.
func _move_fab_to(pos: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var x := clampf(pos.x, EDGE_MARGIN, vp.x - FAB_SIZE - EDGE_MARGIN)
	var y := clampf(pos.y, EDGE_MARGIN, vp.y - FAB_SIZE - EDGE_MARGIN)
	_home_pos = Vector2(x, y)
	if _fab:
		_fab.position = _home_pos
	# Si se movio con el pill abierto, recalculamos el pill.
	_update_layout()


func _input(event: InputEvent) -> void:
	# Colapsar cuando el usuario toca afuera del FAB y fuera del pill.
	if not _expanded:
		return
	if not (event is InputEventScreenTouch or event is InputEventMouseButton):
		return
	if not event.pressed:
		return
	var pos: Vector2 = event.position
	# ¿Dentro del FAB?
	if Rect2(_fab.position, _fab.size).has_point(pos):
		return
	# ¿Dentro de algun boton del pill?
	for b in _option_nodes:
		if not is_instance_valid(b):
			continue
		var btn: Control = b
		if not btn.visible:
			continue
		if Rect2(btn.position, btn.size).has_point(pos):
			return
	# Tap afuera -> colapsar.
	_close()


func _open() -> void:
	if _expanded:
		return
	_expanded = true
	if _fab != null:
		# El icono cambia de "..." a X. NO rotamos el nodo: el icono
		# FAB_OPEN ya dibuja la X. Rotar daba una X inclinada, ilegible.
		_fab.set_meta("icon_kind", IconKind.FAB_OPEN)
		_fab.modulate.a = FAB_ALPHA_ACTIVE
		_fab.queue_redraw()

	# Recalcular layout para asegurar posiciones correctas.
	_update_layout()

	# Animar cada boton: salen del centro del FAB hacia su posicion.
	var fab_center := _home_pos + Vector2(FAB_SIZE, FAB_SIZE) / 2.0
	for i in _option_nodes.size():
		var btn: Control = _option_nodes[i]
		btn.visible = true
		btn.modulate.a = 0.0
		btn.scale = Vector2.ZERO
		var target: Vector2 = btn.position
		# Arranca visualmente desde el centro del FAB.
		btn.position = fab_center - Vector2(OPTION_SIZE, OPTION_SIZE) / 2.0
		var tw: Tween = btn.create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_property(btn, "position", target, ANIM_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(btn, "modulate:a", 1.0, ANIM_TIME * 0.6)
		tw.parallel().tween_property(btn, "scale", Vector2.ONE, ANIM_TIME * 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close() -> void:
	if not _expanded:
		return
	_expanded = false
	if _fab != null:
		_fab.set_meta("icon_kind", IconKind.FAB_CLOSED)
		_fab.modulate.a = FAB_ALPHA_IDLE
		_fab.queue_redraw()
	for b in _option_nodes:
		if not is_instance_valid(b):
			continue
		var btn: Control = b
		var tw: Tween = btn.create_tween()
		tw.tween_property(btn, "modulate:a", 0.0, ANIM_TIME * 0.6)
		tw.parallel().tween_property(btn, "scale", Vector2.ZERO, ANIM_TIME * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): btn.visible = false)


# ============================================================
# Persistencia
# ============================================================

func _load_or_default_pos() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	# Default: borde derecho, centro vertical.
	var default_pos := Vector2(
		vp.x - FAB_SIZE - EDGE_MARGIN,
		(vp.y - FAB_SIZE) / 2.0,
	)
	if not FileAccess.file_exists(PERSIST_PATH):
		return default_pos
	var cfg := ConfigFile.new()
	if cfg.load(PERSIST_PATH) != OK:
		return default_pos
	var xr: float = cfg.get_value("bubble", "x_ratio", -1.0)
	var yr: float = cfg.get_value("bubble", "y_ratio", -1.0)
	if xr < 0.0 or yr < 0.0:
		return default_pos
	var x := clampf(xr * vp.x, EDGE_MARGIN, vp.x - FAB_SIZE - EDGE_MARGIN)
	var y := clampf(yr * vp.y, EDGE_MARGIN, vp.y - FAB_SIZE - EDGE_MARGIN)
	return Vector2(x, y)


func _save_pos() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("bubble", "x_ratio", _home_pos.x / vp.x)
	cfg.set_value("bubble", "y_ratio", _home_pos.y / vp.y)
	cfg.save(PERSIST_PATH)


func _apply_home_pos() -> void:
	if _fab == null:
		return
	_fab.position = _home_pos
	_update_layout()


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
	get_tree().change_scene_to_file("res://engine/mod_selector.tscn")


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

	var vp := get_viewport().get_visible_rect().size
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	sb.border_color = Color(0.5, 0.7, 0.9, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(vp.x / 2.0 - 400.0, vp.y / 2.0 - 80.0)
	panel.custom_minimum_size = Vector2(800, 0)
	_console_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_console_label = Label.new()
	_console_label.text = "Dev Console — escribi un comando"
	_console_label.add_theme_font_size_override("font_size", 20)
	_console_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_console_label)

	_console_input = LineEdit.new()
	_console_input.placeholder_text = "comando (ej: unlock ChamberOfLight)"
	_console_input.virtual_keyboard_enabled = true
	_console_input.text_submitted.connect(_on_console_submit)
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
	if _console_label != null:
		_console_label.text = "Comando desconocido: %s" % text
		_console_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
		MenuMusic.play_cancel()
		_console_input.text = ""


# ============================================================
# Visibilidad por escena + animacion de intro
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
		_set_visible(false)
		return
	var scene := tree.current_scene
	if scene == null:
		_set_visible(false)
		return
	var path: String = scene.scene_file_path
	# Solo visible en escenas del mod (cualquier cosa que no sea del engine).
	var is_engine_ui: bool = path.begins_with(ENGINE_SCENE_PREFIX) or path.is_empty()
	_set_visible(not is_engine_ui)
	if is_engine_ui:
		_close()
		_close_console()


## Cambia visibilidad del FAB + botones. Si pasa de invisible a
## visible, dispara la animacion de intro (zoom + alpha).
func _set_visible(v: bool) -> void:
	if _fab == null:
		return
	var was := _fab.visible
	_fab.visible = v
	if not v:
		for b in _option_nodes:
			if is_instance_valid(b):
				b.visible = false
	if v and not was:
		# Transicion invisible -> visible: animacion de intro.
		_play_intro()


## Animacion de "aqui estoy": arranca invisible + escala 0, crece
## rapido a INTRO_SCALE con alpha 1.0, y vuelve suave a escala 1 con
## alpha FAB_ALPHA_IDLE.
func _play_intro() -> void:
	if _fab == null:
		return
	_fab.scale = Vector2.ZERO
	_fab.modulate.a = 0.0
	_fab.pivot_offset = Vector2(FAB_SIZE, FAB_SIZE) / 2.0
	var tw := create_tween()
	tw.tween_property(_fab, "scale", Vector2(INTRO_SCALE, INTRO_SCALE), INTRO_TIME * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_fab, "modulate:a", FAB_ALPHA_ACTIVE, INTRO_TIME * 0.5)
	tw.tween_property(_fab, "scale", Vector2.ONE, INTRO_TIME * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_fab, "modulate:a", FAB_ALPHA_IDLE, INTRO_TIME * 0.4)
