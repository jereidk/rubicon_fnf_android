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
var _confirm_root: Control = null
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
## Estado de _expanded al momento del press, para no toggle-ar dos veces
## en el mismo tap (open en el press branch viejo + close en el release).
var _was_expanded_at_press: bool = false
## Frame en el que se abrio el pill. _input ignora eventos del mismo frame
## para evitar que el press que abre sea procesado tambien como "tap afuera".
var _last_open_frame: int = -1


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
	_dbg("_ready FAB creado size=%s alpha=%s visible=%s" % [FAB_SIZE, FAB_ALPHA_IDLE, _fab.visible])

	_register_base_options()
	# El viewport todavia no tiene su tamano real en _ready() (sobre todo
	# en Android landscape). Diferimos el calculo de _home_pos y el
	# layout al primer frame, cuando el tamano ya es el definitivo.
	_deferred_bootstrap.call_deferred()


func _deferred_bootstrap() -> void:
	var vp := _vp_size()
	var vp_phys := get_viewport().get_visible_rect().size
	_home_pos = _load_or_default_pos()
	_dbg("_deferred_bootstrap vp_virtual=%s vp_fisico=%s home=%s" % [vp, vp_phys, _home_pos])
	_apply_home_pos()
	_update_visibility()
	_dbg("bootstrap fin: fab.visible=%s fab.pos=%s fab.scale=%s fab.alpha=%s" % [
		_fab.visible, _fab.position, _fab.scale, _fab.modulate.a
	])


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
		# bind() en vez de lambda: GDScript captura variables por
		# REFERENCIA en lambdas, asi que todos los botones compartirian
		# el mismo `cb` (la del ultimo item). Con bind() el valor viaja
		# como argumento, sin captura.
		b.gui_input.connect(_on_option_gui_input.bind(cb))
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


## Handler de tap en un boton del pill. Separado de _rebuild_option_nodes
## para no usar lambda (captura por referencia). Recibe el Callable via
## bind() para que cada boton tenga el suyo.
func _on_option_gui_input(ev: InputEvent, cb: Callable) -> void:
	if not (ev is InputEventScreenTouch or ev is InputEventMouseButton):
		return
	if not ev.pressed:
		return
	_dbg("_on_option_gui_input frame=%d cb_valid=%s" % [Engine.get_process_frames(), cb.is_valid()])
	MenuMusic.play_confirm()
	_close()
	if cb.is_valid():
		_dbg("  llamando cb")
		cb.call()
		_dbg("  cb retorno")
	else:
		_dbg("  cb INVALIDO")


# ============================================================
# Layout
# ============================================================

## Calcula donde va el FAB cuando esta idle y donde va cada boton
## del pill cuando esta expandido, segun la direccion de expansion.
func _update_layout() -> void:
	if _fab == null:
		return
	var vp := _vp_size()

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
		_dragging = false
		_was_expanded_at_press = _expanded
		if _fab:
			_fab.modulate.a = FAB_ALPHA_ACTIVE
		return
	# Mouse start (desktop / debug).
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		_press_time = Time.get_ticks_msec() / 1000.0
		_drag_dist = 0.0
		_dragging = false
		_was_expanded_at_press = _expanded
		if _fab:
			_fab.modulate.a = FAB_ALPHA_ACTIVE
		return
	# Drag: usamos ev.relative (delta desde el ultimo drag event) en vez de
	# recomputar desde ev.position, porque en gui_input ev.position esta en
	# coords locales del FAB, no del CanvasLayer - mezclar sistemas daba
	# saltos enormes en el movimiento.
	if ev is InputEventScreenDrag:
		_drag_dist += ev.relative.length()
		if _drag_dist > TAP_MAX_DIST:
			_dragging = true
			_move_fab_to(_home_pos + ev.relative)
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
			# Usar el estado al momento del press, no el actual. Si no,
			# un toggle rapido (press->open, release->close) cierra lo
			# que acaba de abrir en el mismo gesto.
			if _was_expanded_at_press:
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
	var vp := _vp_size()
	var x := clampf(pos.x, EDGE_MARGIN, vp.x - FAB_SIZE - EDGE_MARGIN)
	var y := clampf(pos.y, EDGE_MARGIN, vp.y - FAB_SIZE - EDGE_MARGIN)
	_home_pos = Vector2(x, y)
	if _fab:
		_fab.position = _home_pos
	# Solo recalcular el pill si esta abierto. Sin esto, cada evento de drag
	# hace 3+ iteraciones de _update_layout (que crea tweens y reposiciona
	# cada boton), aunque el pill no se vea - eso tilda el arrastre.
	if _expanded:
		_update_layout()


func _input(event: InputEvent) -> void:
	# Colapsar cuando el usuario toca afuera del FAB y fuera del pill.
	if not _expanded:
		return
	# Ignorar eventos del mismo frame en que se abrio. Sin esto, el press
	# que dispara _open() (via gui_input) llega tambien aca un frame
	# despues y cierra el pill inmediatamente.
	if Engine.get_process_frames() == _last_open_frame:
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
	_dbg("_input tap-afuera frame=%d pos=%s" % [Engine.get_process_frames(), pos])
	_close()


func _open() -> void:
	if _expanded:
		return
	_expanded = true
	_last_open_frame = Engine.get_process_frames()
	_dbg("_open frame=%d, botones=%d" % [Engine.get_process_frames(), _option_nodes.size()])
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
	_dbg("_close frame=%d" % Engine.get_process_frames())
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
	var vp := _vp_size()
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
	var vp := _vp_size()
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
	_dbg("do_exit llamado")
	_show_confirm(
		"Salir del mod",
		"¿Volver al menu principal?\nEl mod se cerrara.",
		"Si, salir",
		"No, cancelar",
		_on_confirm_exit
	)


func _on_confirm_exit() -> void:
	MenuMusic.play_cancel()
	ModLoader.restore_default_settings()
	get_tree().change_scene_to_file("res://engine/mod_selector.tscn")


## Panel de confirmacion custom. Reemplaza a ConfirmationDialog porque
## en Android el Window nativo no hereda el content_scale del proyecto
## (canvas_items + keep) y sale microscopico. Aca dibujamos un Control
## full-rect con dim + PanelContainer centrado con font/botones grandes.
func _show_confirm(title: String, text: String, ok_label: String, cancel_label: String, on_ok: Callable) -> void:
	# Si ya hay uno abierto, no abrimos otro.
	if _confirm_root != null and is_instance_valid(_confirm_root):
		return

	_confirm_root = Control.new()
	_confirm_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm_root)

	# Dim de fondo.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev):
		if (ev is InputEventScreenTouch and ev.pressed) \
		or (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
			MenuMusic.play_cancel()
			_close_confirm()
	)
	_confirm_root.add_child(dim)

	var vp := _vp_size()

	# Panel centrado.
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	sb.border_color = Color(0.7, 0.7, 0.75, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	var panel_w := 900.0
	var panel_h := 380.0
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	panel.size = Vector2(panel_w, panel_h)
	panel.position = Vector2((vp.x - panel_w) / 2.0, (vp.y - panel_h) / 2.0)
	_confirm_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	panel.add_child(vbox)

	# Titulo.
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	vbox.add_child(title_lbl)

	# Separador.
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Texto.
	var text_lbl := Label.new()
	text_lbl.text = text
	text_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.add_theme_font_size_override("font_size", 32)
	text_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
	text_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(text_lbl)

	# Botones en fila.
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	var btn_cancel := _make_confirm_button(cancel_label, Color(0.35, 0.35, 0.4))
	btn_cancel.pressed.connect(func():
		MenuMusic.play_cancel()
		_close_confirm()
	)
	hbox.add_child(btn_cancel)

	var btn_ok := _make_confirm_button(ok_label, Color(0.75, 0.25, 0.25))
	btn_ok.pressed.connect(func():
		MenuMusic.play_confirm()
		_close_confirm()
		if on_ok.is_valid():
			on_ok.call()
	)
	hbox.add_child(btn_ok)


func _make_confirm_button(label: String, color: Color) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(240, 72)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color.WHITE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(12)
	var hover := StyleBoxFlat.new()
	hover.bg_color = color.lightened(0.15)
	hover.set_corner_radius_all(8)
	hover.set_content_margin_all(12)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = color.darkened(0.2)
	pressed.set_corner_radius_all(8)
	pressed.set_content_margin_all(12)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	return b


func _close_confirm() -> void:
	if _confirm_root != null and is_instance_valid(_confirm_root):
		_confirm_root.queue_free()
	_confirm_root = null


func _toggle_debug() -> void:
	_dbg("toggle_debug llamado")
	var dd := get_node_or_null("/root/DebugDisplay")
	if dd == null:
		return
	dd.visible = not dd.visible


# ============================================================
# Dev Console
# ============================================================

func _open_console() -> void:
	_dbg("open_console llamado")
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

	var vp := _vp_size()
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
	# Solo ocultamos cuando EXPLICITAMENTE sabemos que la escena es del
	# engine. Los .tscn del mod los carga el RuntimeResourceLoader custom,
	# que no setea el path en el PackedScene (ver packed_scene.cpp:2522:
	# el scene_file_path de la instancia hereda del PackedScene.get_path).
	# Resultado: para escenas del mod, path == "". Ocultar en ese caso
	# dejaba la burbuja invisible siempre.
	var is_engine_ui: bool = path.begins_with(ENGINE_SCENE_PREFIX)
	_dbg("_update_visibility path='%s' is_engine=%s" % [path, is_engine_ui])
	_set_visible(not is_engine_ui)
	if is_engine_ui:
		_close()
		_close_confirm()
		_close_console()


## Cambia visibilidad del FAB + botones. Si pasa de invisible a
## visible, dispara la animacion de intro (zoom + alpha).
func _set_visible(v: bool) -> void:
	if _fab == null:
		return
	var was := _fab.visible
	_dbg("_set_visible(%s) was=%s" % [v, was])
	_fab.visible = v
	if not v:
		for b in _option_nodes:
			if is_instance_valid(b):
				b.visible = false
	if v and not was:
		# Transicion invisible -> visible: animacion de intro.
		_play_intro()


## Tamano virtual del proyecto (1920x1080 tipicamente), NO el fisico.
## El viewport fisico del moto G53 5G es 2400x1080 con bandas negras
## por el aspect keep. Los Controles del CanvasLayer viven en
## coordenadas virtuales (post-stretch), asi que hay que usar el
## viewport_width/height de ProjectSettings, no get_visible_rect().
func _vp_size() -> Vector2:
	var w: int = ProjectSettings.get_setting("display/window/size/viewport_width", 1920)
	var h: int = ProjectSettings.get_setting("display/window/size/viewport_height", 1080)
	return Vector2(w, h)


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
	tw.finished.connect(func():
		_dbg("intro done scale=%s alpha=%s visible=%s" % [_fab.scale, _fab.modulate.a, _fab.visible])
		# Safety: si por alguna razon quedo con escala 0 o alpha 0,
		# forzar el estado final para que se vea.
		if _fab.scale.length() < 0.5:
			_fab.scale = Vector2.ONE
		if _fab.modulate.a < 0.1 and not _expanded:
			_fab.modulate.a = FAB_ALPHA_IDLE
	)



# ============================================================
# Debug logging (diagnostico)
# ============================================================

func _dbg(msg: String) -> void:
	var dl := get_node_or_null("/root/DebugLog")
	if dl != null and dl.has_method("log"):
		dl.log("[ModBubble] " + msg)
