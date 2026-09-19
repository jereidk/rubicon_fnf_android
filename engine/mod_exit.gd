extends CanvasLayer
## Boton flotante de "salir al menu principal" para mods.
##
## Los mods se cargan con change_scene_to_file() y reemplazan la escena
## actual. El ModSelector se destruye, asi que su boton "Volver" no sirve
## una vez adentro. Este autoload vive a nivel raiz del arbol (CanvasLayer
## en layer 185), asi que sobrevive cualquier cambio de escena.
##
## Visible solo cuando la escena actual NO es el ModSelector ni el
## ModManager. En esas dos pantallas la navegacion natural ya existe y
## no hace falta el boton flotante.
##
## Layer 185: por debajo del DebugDisplay (190) y del ErrorToast (200),
## por encima del gameplay. Los dialogos de confirmacion se abren como
## hijos de este CanvasLayer, asi que heredan su layer y se ven encima
## de todo lo que hay debajo de 185.

const LAYER := 185
const SELECTOR_SCENE := "res://engine/mod_selector.tscn"
const MANAGER_SCENE := "res://engine/mod_manager.tscn"
const BUTTON_SIZE := Vector2(72, 72)
const BUTTON_MARGIN := 24.0
const BUTTON_ALPHA := 0.6
const FONT_PATH := "res://resources/fonts/fnt_vcr.ttf"
const ICON_TEXT := "X"

## Estilo del boton: caja redonda, fondo negro, borde blanco suave.
var _button: Button = null
## Ultima escena vista, para actualizar visibility solo cuando cambia.
var _last_scene_path: String = ""


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_button = Button.new()
	_button.text = ICON_TEXT
	_button.size = BUTTON_SIZE
	_button.custom_minimum_size = BUTTON_SIZE

	# Anclado arriba-derecha.
	_button.anchor_left = 1.0
	_button.anchor_right = 1.0
	_button.anchor_top = 0.0
	_button.anchor_bottom = 0.0
	_button.offset_left = -(BUTTON_SIZE.x + BUTTON_MARGIN)
	_button.offset_right = -BUTTON_MARGIN
	_button.offset_top = BUTTON_MARGIN
	_button.offset_bottom = BUTTON_MARGIN + BUTTON_SIZE.y

	# Pivot al centro: el scale de la animacion de tap escala desde el
	# centro, no desde la esquina superior izquierda.
	_button.pivot_offset = BUTTON_SIZE / 2.0

	# Fondo negro alpha 0.6, borde blanco alpha 0.4, radio 32 (circulo).
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, BUTTON_ALPHA)
	normal.border_color = Color(1, 1, 1, 0.4)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(32)
	normal.set_content_margin_all(0)

	var hover := normal.duplicate()
	hover.bg_color = Color(0, 0, 0, 0.75)
	hover.border_color = Color(1, 1, 1, 0.7)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.2, 0.2, 0.2, 0.9)
	pressed.border_color = Color(1, 1, 1, 0.9)

	var focus := normal.duplicate()

	_button.add_theme_stylebox_override("normal", normal)
	_button.add_theme_stylebox_override("hover", hover)
	_button.add_theme_stylebox_override("pressed", pressed)
	_button.add_theme_stylebox_override("focus", focus)
	_button.add_theme_color_override("font_color", Color.WHITE)
	_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	_button.add_theme_color_override("font_focus_color", Color.WHITE)

	if ResourceLoader.exists(FONT_PATH):
		_button.add_theme_font_override("font", load(FONT_PATH))
	_button.add_theme_font_size_override("font_size", 32)

	_button.visible = false
	_button.pressed.connect(_on_button_pressed)
	_button.mouse_entered.connect(func(): MenuMusic.play_scroll())

	add_child(_button)
	_update_visibility()


func _process(_delta: float) -> void:
	# Chequear si la escena cambio. Comparacion de string, virtualmente
	# gratis. Alternativa: no hay signal nativo de "current_scene cambio",
	# tree_changed dispara por cada nodo agregado/sacado y es demasiado.
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	var path := "" if scene == null else scene.scene_file_path
	if path != _last_scene_path:
		_last_scene_path = path
		_update_visibility()


## El boton esta visible cuando la escena actual no es el selector ni el
## manager. Cualquier otra cosa (un mod cargado, la demo, etc) muestra
## el boton.
func _update_visibility() -> void:
	if _button == null:
		return
	var tree := get_tree()
	if tree == null:
		_button.visible = false
		return
	var scene := tree.current_scene
	if scene == null:
		_button.visible = false
		return
	var path: String = scene.scene_file_path
	var is_engine_ui: bool = path.ends_with("mod_selector.tscn") or path.ends_with("mod_manager.tscn")
	_button.visible = not is_engine_ui


func _on_button_pressed() -> void:
	MenuMusic.play_confirm()
	_play_tap_animation()
	_show_confirm_dialog()


## Zoom rapido: 1.0 -> 0.85 -> 1.0. El TRANS_BACK da un pelin de rebote
## al volver, tipico de UI movil.
func _play_tap_animation() -> void:
	if _button == null:
		return
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_BACK)
	tw.tween_property(_button, "scale", Vector2(0.85, 0.85), 0.08)
	tw.tween_property(_button, "scale", Vector2.ONE, 0.18)


func _show_confirm_dialog() -> void:
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
	# Restaurar settings del Window (stretch/mode, stretch/aspect) antes
	# de cambiar al selector. Si el mod los overrideo, hay que devolver
	# el estado original.
	ModLoader.restore_default_settings()
	get_tree().change_scene_to_file(SELECTOR_SCENE)
