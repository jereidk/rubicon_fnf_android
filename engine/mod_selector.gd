extends Control
## Escena de arranque del engine. Lee los mods que ModLoader detecto y
## decide a donde ir:
##   - 0 mods  -> muestra la demo del engine.
##   - 1+ mods -> siempre muestra la lista (nunca auto-carga).
##
## Layout: dos columnas. Izquierda la lista de mods + boton PLAY +
## "Administrar mods". Derecha el preview del mod seleccionado: si el
## mod.json declara "icon", se muestra ese PNG; si no, cae al logoBumpin
## animado de FNF.
##
## Por que nunca auto-carga con un solo mod: si el unico mod falla al
## cargar (script con error, main_scene mal escrito, .pck que no se monto),
## auto-cargarlo sin mostrar la lista ocultaba el error y el usuario
## terminaba en la demo sin saber por que. Mostrando la lista siempre, el
## usuario ve el mod, lo toca, y si falla ve el mensaje de error.

const DEMO_SCENE := "res://songs/test/test.tscn"
const AnimatedLogoScript := preload("res://engine/animated_logo.gd")
const FONT_PATH := "res://resources/fonts/fnt_vcr.ttf"

## Fondo opcional. Si el archivo no existe, se usa un ColorRect oscuro
## solido. Los PNG de FNF son menuBGBlue.png y menuBGMagenta.png, que
## se pueden copiar a resources/images/ con cualquiera de esos nombres.
const BG_CANDIDATES: Array[String] = [
	"res://resources/images/menuBGBlue.png",
	"res://resources/images/menu_bg.png",
	"res://resources/images/menu_bg.ktx",
]

const COLOR_ACCENT := Color("#4FC3F7")
const COLOR_BG_NORMAL := Color(0, 0, 0, 0.7)
const COLOR_BG_HOVER := Color(0.1, 0.1, 0.15, 0.85)
const COLOR_BG_SELECTED := Color(0.15, 0.3, 0.45, 0.9)
const COLOR_BORDER := Color.WHITE

var _header: Label
var _list: VBoxContainer
var _play_btn: Button
var _manager_btn: Button
var _error_label: Label

var _preview_rect: Control
var _preview_texture: TextureRect
var _preview_logo: Control = null

var _vcr_font: Font = null
var _button_group: ButtonGroup = null
var _selected_mod: Dictionary = {}
## folder -> path fisico del icono, "" si no tiene.
var _mod_icons: Dictionary = {}

## Overlay de carga que aparece al empaquetar un mod on-demand.
## Con HQ (351 MB) el pck tarda y sin feedback parece que la app se colgo.
var _loading_overlay: Control
var _loading_title: Label
var _loading_phase: Label
var _loading_bar: ProgressBar


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Restaurar el Window al estado original: si venimos de un mod que
	# overrideo stretch/mode o stretch/aspect, hay que devolverlo antes
	# de mostrar la UI del selector.
	ModLoader.restore_default_settings()
	_load_font()
	_build_ui()
	# Rescan al entrar: si el usuario agrego o quito un mod con el juego
	# abierto, lo ve al volver a esta pantalla sin reiniciar.
	ModLoader.scan()
	_populate()
	# Al final: en Godot el ultimo hijo se dibuja encima. El overlay tiene
	# que ser el ULTIMO hijo del ModSelector para tapar todo lo demas
	# (botones, lista de mods, boton Mods...). Ponerlo en _build_ui lo
	# dejaba debajo de la MarginContainer que se agrega despues.
	_build_loading_overlay()


## Carga la fuente VCR una sola vez. Si falla, todos los controles usan
## la fuente por defecto del engine. No es fatal pero rompe la estetica.
func _load_font() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_vcr_font = load(FONT_PATH)
	else:
		push_warning("[ModSelector] no encontre la fuente " + FONT_PATH)


## Aplica la fuente VCR (si esta cargada) y opcionalmente un tamano.
func _apply_font(ctrl: Control, size: int = 0) -> void:
	if _vcr_font != null:
		ctrl.add_theme_font_override("font", _vcr_font)
	if size > 0:
		ctrl.add_theme_font_size_override("font_size", size)


func _build_ui() -> void:
	_build_background()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 32)
	margin.add_child(hbox)

	_build_left_panel(hbox)
	_build_right_panel(hbox)


## Columna izquierda: titulo, contador, lista scrolleable de mods,
## error, y fila [PLAY expandido] [Administrar mods].
func _build_left_panel(parent: HBoxContainer) -> void:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Ratio 45:55 -> 0.9 : 1.1 (Godot divide por la suma, da 45% / 55%).
	left.size_flags_stretch_ratio = 0.9
	left.add_theme_constant_override("separation", 16)
	parent.add_child(left)

	# Title es local: solo vive en el panel izquierdo, no hace falta
	# guardarlo como miembro.
	var title := Label.new()
	title.text = "Washos Engine"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_font(title, 56)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	left.add_child(title)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(_header, 22)
	_header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	left.add_child(_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Sin scroll horizontal: los botones ocupan todo el ancho del panel.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.alignment = BoxContainer.ALIGNMENT_BEGIN
	_list.add_theme_constant_override("separation", 12)
	scroll.add_child(_list)

	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_font(_error_label, 18)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_error_label.visible = false
	left.add_child(_error_label)

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	left.add_child(bottom_row)

	_play_btn = Button.new()
	_play_btn.text = "\u25B6  PLAY"
	_play_btn.custom_minimum_size = Vector2(0, 80)
	_play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_btn.disabled = true
	_apply_font(_play_btn, 36)
	_style_button(_play_btn, true)
	_play_btn.pressed.connect(_on_play_pressed)
	_play_btn.mouse_entered.connect(func(): MenuMusic.play_scroll())
	bottom_row.add_child(_play_btn)

	_manager_btn = Button.new()
	_manager_btn.text = "Administrar mods"
	_manager_btn.custom_minimum_size = Vector2(240, 80)
	_apply_font(_manager_btn, 22)
	_style_button(_manager_btn, false)
	_manager_btn.pressed.connect(_open_manager)
	_manager_btn.mouse_entered.connect(func(): MenuMusic.play_scroll())
	bottom_row.add_child(_manager_btn)


## Columna derecha: preview del mod seleccionado. Muestra el "icon" del
## mod.json si lo tiene, o el logoBumpin animado si no.
func _build_right_panel(parent: HBoxContainer) -> void:
	_preview_rect = Control.new()
	_preview_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Ratio 55% (complementa al 45% de la izquierda).
	_preview_rect.size_flags_stretch_ratio = 1.1
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_preview_rect)

	_preview_texture = TextureRect.new()
	_preview_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_texture.visible = false
	_preview_rect.add_child(_preview_texture)


## Aplica un estilo FNF a un boton. "primary" es el PLAY celeste, el
## resto son los botones oscuros con borde blanco (o celeste si estan
## seleccionados por toggle).
func _style_button(b: Button, primary: bool) -> void:
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	var pressed := StyleBoxFlat.new()
	var focus := StyleBoxFlat.new()
	var disabled := StyleBoxFlat.new()

	if primary:
		normal.bg_color = COLOR_ACCENT
		normal.border_color = Color.WHITE
		normal.set_border_width_all(3)
		normal.set_corner_radius_all(8)
		normal.set_content_margin_all(12)

		hover = normal.duplicate()
		hover.bg_color = COLOR_ACCENT.lightened(0.15)

		pressed = normal.duplicate()
		pressed.bg_color = COLOR_ACCENT.darkened(0.15)

		focus = normal.duplicate()

		disabled = normal.duplicate()
		disabled.bg_color = Color(0.2, 0.2, 0.25, 0.6)
		disabled.border_color = Color(0.4, 0.4, 0.4)
	else:
		normal.bg_color = COLOR_BG_NORMAL
		normal.border_color = COLOR_BORDER
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(8)
		normal.set_content_margin_all(12)

		hover = normal.duplicate()
		hover.bg_color = COLOR_BG_HOVER
		hover.set_border_width_all(3)

		# "pressed" es el estado toggle activo.
		pressed = normal.duplicate()
		pressed.bg_color = COLOR_BG_SELECTED
		pressed.border_color = COLOR_ACCENT
		pressed.set_border_width_all(4)

		focus = pressed.duplicate()

		disabled = normal.duplicate()
		disabled.bg_color = Color(0.1, 0.1, 0.15, 0.5)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))


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


## Muestra el logoBumpin animado en el panel derecho. Lo crea la primera
## vez y despues solo lo hace visible. Si el PNG o el XML no existen, no
## hace nada y el panel queda vacio.
func _show_logo_bumpin() -> void:
	if _preview_logo != null and is_instance_valid(_preview_logo):
		_preview_logo.visible = true
		return

	var png := "res://resources/images/logoBumpin.png"
	var xml := "res://resources/images/logoBumpin.xml"
	if not ResourceLoader.exists(png):
		return
	# FileAccess.file_exists() con res:// puede fallar para archivos
	# dentro del .pck en Android, aunque el archivo este. En vez de
	# chequear, abrimos el XML directo con XMLParser y si falla salimos.
	var probe := XMLParser.new()
	if probe.open(xml) != OK:
		return

	var logo: Control = AnimatedLogoScript.new()
	_preview_rect.add_child(logo)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Frame del atlas logoBumpin: 939x703.
	var frame_w := 939.0
	var frame_h := 703.0

	# Centrado en el panel: anchor al centro, offsets que dejan la caja
	# centrada, y pivot en el centro para que el scale no desplace.
	logo.anchor_left = 0.5
	logo.anchor_top = 0.5
	logo.anchor_right = 0.5
	logo.anchor_bottom = 0.5
	logo.offset_left = -frame_w * 0.5
	logo.offset_top = -frame_h * 0.5
	logo.offset_right = frame_w * 0.5
	logo.offset_bottom = frame_h * 0.5
	logo.pivot_offset = Vector2(frame_w * 0.5, frame_h * 0.5)

	# Escalar al 45% del ancho del viewport. Es un poco mas conservador
	# que el 40% de antes porque ahora comparte el espacio con la lista.
	var vp := get_viewport_rect().size
	var target_w := vp.x * 0.45
	var scale_factor := target_w / frame_w
	logo.scale = Vector2(scale_factor, scale_factor)

	logo.setup(png, xml)
	_preview_logo = logo


## Actualiza el preview del panel derecho segun el mod seleccionado.
## Si el mod tiene un icon valido, lo muestra. Si no, cae al logoBumpin.
func _update_preview(m: Dictionary) -> void:
	if not m.is_empty():
		var folder: String = str(m.get("folder", ""))
		var icon_path: String = str(_mod_icons.get(folder, ""))
		if not icon_path.is_empty():
			var bytes := FileAccess.get_file_as_bytes(icon_path)
			if not bytes.is_empty():
				var img := Image.new()
				if img.load_png_from_buffer(bytes) == OK:
					_preview_texture.texture = ImageTexture.create_from_image(img)
					_preview_texture.visible = true
					if _preview_logo != null and is_instance_valid(_preview_logo):
						_preview_logo.visible = false
					return

	# Fallback: logoBumpin animado.
	_preview_texture.visible = false
	_preview_texture.texture = null
	_show_logo_bumpin()


func _build_loading_overlay() -> void:
	_loading_overlay = Control.new()
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.visible = false
	add_child(_loading_overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.04, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -80
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_loading_title = Label.new()
	_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(_loading_title, 56)
	_loading_title.add_theme_color_override("font_color", Color.WHITE)
	_loading_title.add_theme_constant_override("outline_size", 6)
	_loading_title.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(_loading_title)

	_loading_phase = Label.new()
	_loading_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_font(_loading_phase, 26)
	_loading_phase.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(_loading_phase)

	_loading_bar = ProgressBar.new()
	_loading_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_loading_bar.offset_top = -40
	_loading_bar.offset_bottom = 0
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 1.0
	_loading_bar.value = 0.0
	_loading_bar.show_percentage = false
	_loading_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(_loading_bar)


func _show_loading_overlay(mod_name: String) -> void:
	_loading_title.text = "Cargando %s..." % mod_name
	_loading_phase.text = "Preparando..."
	_loading_bar.value = 0.0
	_loading_overlay.visible = true


func _hide_loading_overlay() -> void:
	_loading_overlay.visible = false


func _on_bake_progress(done: int, total: int, phase: String) -> void:
	match phase:
		"count":
			_loading_phase.text = "Preparando..."
			_loading_bar.value = 0.0
		"scan":
			# Sin total conocido: mostrar el count. Barra en 0.
			_loading_phase.text = "Analizando: %d archivos..." % done
			_loading_bar.value = 0.0
		"fingerprint":
			_loading_phase.text = "Verificando cambios: %d / %d" % [done, total]
			if total > 0:
				_loading_bar.value = float(done) / float(total)
		"pack":
			_loading_phase.text = "Empaquetando %d / %d" % [done, total]
			if total > 0:
				_loading_bar.value = float(done) / float(total)
			else:
				_loading_bar.value = 0.0
		_:
			_loading_phase.text = "%s %d / %d" % [phase, done, total]


func _populate() -> void:
	for c in _list.get_children():
		c.queue_free()
	_error_label.visible = false
	_mod_icons.clear()
	_button_group = ButtonGroup.new()
	# allow_unpress=false: tocar el mod ya seleccionado no lo destilda.
	# Sin esto, el borde celeste desaparecia y _selected_mod seguia
	# apuntando al mismo mod (PLAY funcionaba) pero el usuario no veia
	# cual estaba elegido.
	_button_group.allow_unpress = false
	_selected_mod = {}

	var enabled: Array = []
	for m in ModLoader.mods:
		if m.get("enabled", true):
			enabled.append(m)
			_mod_icons[m["folder"]] = ModLoader.resolve_icon_path(m)

	if enabled.is_empty():
		_header.text = "No hay mods instalados en:\n%s" % ModLoader.mods_root
		_add_button("Ir a la demo del engine", _go_demo)
		_update_preview({})
		_update_play_state()
		return

	_header.text = "%d mod%s instalado%s" % [
		enabled.size(),
		"" if enabled.size() == 1 else "s",
		"" if enabled.size() == 1 else "s",
	]
	for m in enabled:
		_add_mod_button(m)

	_update_preview({})
	_update_play_state()


## Boton toggle: click selecciona el mod, no lo ejecuta. La accion de
## arrancar el mod la hace el boton PLAY.
func _add_mod_button(m: Dictionary) -> void:
	var b := Button.new()
	b.text = "   " + str(m.get("name", m["folder"]))
	b.toggle_mode = true
	b.button_group = _button_group
	b.custom_minimum_size = Vector2(0, 80)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_apply_font(b, 26)
	_style_button(b, false)
	b.pressed.connect(_on_mod_selected.bind(m))
	b.mouse_entered.connect(func(): MenuMusic.play_scroll())
	_list.add_child(b)


## Boton de accion directa (sin toggle). Lo usa el fallback de la demo.
func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 80)
	_apply_font(b, 26)
	_style_button(b, false)
	b.pressed.connect(cb)
	b.focus_entered.connect(func(): MenuMusic.play_scroll())
	b.mouse_entered.connect(func(): MenuMusic.play_scroll())
	_list.add_child(b)


func _on_mod_selected(m: Dictionary) -> void:
	_selected_mod = m
	_update_preview(m)
	_update_play_state()


func _update_play_state() -> void:
	_play_btn.disabled = _selected_mod.is_empty()


func _on_play_pressed() -> void:
	if _selected_mod.is_empty():
		return
	_launch(_selected_mod)


func _open_manager() -> void:
	# Mismo patron que _launch(): no usar change_scene_to_file porque
	# el .tscn resuelve su ExtResource via ResourceLoader.load(), que
	# devuelve un GDScript roto (base RefCounted) cuando hay un .pck
	# de mod montado. Compilamos el .gd a mano y construimos el nodo.
	var gd := _compile_gd_from_bytes("res://engine/mod_manager.gd")
	if gd == null or not gd.can_instantiate():
		_show_error("mod_manager.gd no compila")
		return
	var node = gd.new()
	if not (node is Node):
		_show_error("mod_manager.gd no extiende Node")
		return
	node.name = "ModManager"
	if node is Control:
		node.set_anchors_preset(Control.PRESET_FULL_RECT)
	var old := get_tree().current_scene
	get_tree().root.add_child(node)
	get_tree().current_scene = node
	if old != null:
		old.queue_free()


func _go_demo() -> void:
	MenuMusic.play_confirm()
	MenuMusic.fade_out_music(0.4)
	get_tree().change_scene_to_file(DEMO_SCENE)


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
	# Antes solo pintaba un Label rojo: el error no llegaba a debug.log
	# ni a washos_*.error, asi que un fallo de carga era invisible en los
	# archivos. Ahora va a los dos.
	DebugLog.log("[ModSelector] ERROR: " + msg.replace("\n", " | "))
	push_warning("[ModSelector] " + msg.replace("\n", " | "))


## Compila un .gd leyendolo como bytes y forzando reload().
##
## ResourceLoader.load() sobre un .gd dentro de un .pck montado en runtime
## devuelve un GDScript hueco en Android: el parser no lo compila y la
## clase base queda en RefCounted, lo que revienta al asignarlo a un nodo.
## Compilar manualmente desde bytes saltea el pck y el ResourceLoader.
func _compile_gd_from_bytes(path: String) -> GDScript:
	if not FileAccess.file_exists(path):
		return null
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		return null
	var gd := GDScript.new()
	gd.source_code = src
	if gd.reload() != OK:
		return null
	return gd


func _launch(m: Dictionary) -> void:
	var folder: String = str(m.get("folder", "?"))
	var scene: String = str(m.get("main_scene", ""))
	DebugLog.log("[ModSelector._launch] mod=%s scene=%s" % [folder, scene])

	MenuMusic.play_confirm()
	MenuMusic.fade_out_music(0.4)

	if scene.is_empty():
		_show_error("Mod '%s' no define main_scene.\nFolder: %s" % [m["folder"], m["path"]])
		return

	# Overlay PRIMERO, siempre. needs_bake() corre el walk completo del
	# mod (con HQ son 19s) y bake_mod lo repite. Mostrar el overlay despues
	# de needs_bake congelaba la pantalla anterior 19s antes de que se
	# viera la pantalla de carga.
	#
	# El await process_frame es la clave: sin el, Godot no redibuja el
	# frame con el overlay visible, y la UI previa (los botones del
	# ModSelector) quedaba congelada encima de la pantalla de carga.
	_show_loading_overlay(str(m.get("name", folder)))
	_loading_phase.text = "Analizando archivos..."
	await get_tree().process_frame
	await get_tree().process_frame

	var need: bool = await ModLoader.needs_bake(folder, _on_bake_progress)
	DebugLog.log("[ModSelector._launch] needs_bake=%s" % need)
	DebugLog.log("[ModSelector._launch] llamando bake_mod...")
	var baked: bool = await ModLoader.bake_mod(m, _on_bake_progress)
	DebugLog.log("[ModSelector._launch] bake_mod devolvio %s" % baked)
	_hide_loading_overlay()
	if not baked:
		_show_error("No se pudo preparar el mod: %s" % folder)
		return

	var exists: bool = ResourceLoader.exists(scene)
	DebugLog.log("[ModSelector._launch] ResourceLoader.exists(%s)=%s" % [scene, exists])
	if not exists:
		_show_error("No encontrado: %s\nVerifica que el archivo exista dentro del mod." % scene)
		return

	# Aplicar settings del mod (whitelist: stretch/mode, stretch/aspect).
	# Va DESPUES de las verificaciones (bake ok, scene existe) y ANTES
	# del cambio de escena real. Si algo falla antes, no queremos haber
	# cambiado el Window sin razon.
	ModLoader.apply_mod_settings(m)

	if scene.ends_with(".gd"):
		var script := _compile_gd_from_bytes(scene)
		if script == null or not script.can_instantiate():
			_show_error("El .gd del mod no compila: %s" % scene)
			return
		# script.new() crea una instancia del tipo correcto. Antes usabamos
		# Node.new() + set_script() pero eso falla si el script extends
		# Control, CanvasItem, Node2D, Node3D o cualquier subclase de Node:
		# GDScript rechaza reasignar el tipo nativo de un objeto ya creado.
		# "Script inherits from native type 'Control', so it can't be assigned
		# to an object of type 'Node'."
		var node = script.new()
		if not (node is Node):
			_show_error("El script del mod no extiende Node: %s" % scene)
			return
		node.name = "ModRoot"
		var old := get_tree().current_scene
		get_tree().root.add_child(node)
		get_tree().current_scene = node
		if old != null:
			old.queue_free()
		return

	DebugLog.log("[ModSelector._launch] change_scene_to_file(%s)" % scene)
	get_tree().change_scene_to_file(scene)
	DebugLog.log("[ModSelector._launch] change_scene_to_file devolvio")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_demo()
