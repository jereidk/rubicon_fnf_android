extends CanvasLayer
## Muestra cada error del engine como un cartel rojo arriba de la
## pantalla. Los apila como una consola y cada uno se desvanece a los
## 3 segundos con un tween de alpha.
##
## Se engancha al signal `captured` del autoload ErrorLog, que emite por
## cada error nuevo (no por repeticiones). Solo muestra los ERROR, no
## los WARNING, porque el usuario pidio solo errores.
##
## Va en su propio CanvasLayer con layer alto para quedar arriba de
## cualquier pantalla (menu, ModManager, incluso durante un mod). Layer
## 200 esta por encima del MobileControls (80) y muy por debajo del
## HQTransition (4096), asi que la pantalla de transicion los tapa
## cuando aparece, que es lo que queremos.

const LAYER := 200
## Cuanto tiempo queda visible antes de empezar a desvanecerse.
const HOLD_SECONDS := 3.0
## Cuanto dura el fade in / fade out.
const FADE_IN_SECONDS := 0.15
const FADE_OUT_SECONDS := 0.5
## Maximo de carteles simultaneos. Si llegan mas, los viejos se van
## inmediatamente para no tapar toda la pantalla.
const MAX_VISIBLE := 6

const BG_COLOR := Color(0.78, 0.10, 0.10, 0.92)
const TEXT_COLOR := Color.WHITE
const FONT_SIZE := 22
const OUTLINE_SIZE := 4
const OUTLINE_COLOR := Color(0.05, 0.02, 0.02, 1.0)
const SEPARATION := 4

## Carteles vivos, de mas viejo a mas nuevo. Se usa para sacar los
## viejos cuando llega uno nuevo y se pasa de MAX_VISIBLE.
var _toasts: Array[Control] = []
var _vbox: VBoxContainer


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	# VBox a pantalla completa en horizontal, pegado arriba. Los hijos se
	# apilan de arriba hacia abajo.
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vbox = VBoxContainer.new()
	_vbox.name = "VBox"
	_vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_theme_constant_override("separation", SEPARATION)
	root.add_child(_vbox)

	# Engancharse al ErrorLog. Si por alguna razon el autoload no esta o
	# no tiene el signal (una version vieja), no se hace nada.
	if Engine.has_singleton("ErrorLog"):
		var el: Object = Engine.get_singleton("ErrorLog")
		if el != null and el.has_signal("captured"):
			el.captured.connect(_on_error_captured)
	elif has_node("/root/ErrorLog"):
		var el: Node = get_node("/root/ErrorLog")
		if el.has_signal("captured"):
			el.captured.connect(_on_error_captured)


func _on_error_captured(kind: String, _where: String, message: String) -> void:
	# Solo errores, no warnings. El kind viene del ErrorLog, que traduce
	# los 4 ErrorType de Godot a "ERROR" / "WARNING".
	if kind != "ERROR":
		return
	_show(message)


## Crea un cartel con el mensaje, lo agrega arriba de la pila y programa
## su fade in + hold + fade out + free.
func _show(message: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	panel.add_child(label)

	# Fade in: arranca invisible y sube a 1.0 en FADE_IN_SECONDS.
	panel.modulate.a = 0.0
	_vbox.add_child(panel)

	# Si nos pasamos del maximo, sacar los viejos del frente.
	while _toasts.size() >= MAX_VISIBLE:
		var old: Control = _toasts.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	_toasts.append(panel)

	# Tween: fade in -> hold -> fade out -> free.
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, FADE_IN_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD_SECONDS)
	tw.tween_property(panel, "modulate:a", 0.0, FADE_OUT_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(panel):
			panel.queue_free()
		_toasts.erase(panel)
	)
