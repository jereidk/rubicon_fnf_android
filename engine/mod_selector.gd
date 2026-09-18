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
const AnimatedLogoScript := preload("res://engine/animated_logo.gd")

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

## Overlay de carga que aparece al empaquetar un mod on-demand.
## Con HQ (351 MB) el pck tarda y sin feedback parece que la app se colgo.
var _loading_overlay: Control
var _loading_title: Label
var _loading_phase: Label
var _loading_bar: ProgressBar


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	# Rescan al entrar: si el usuario agrego o quito un mod con el juego
	# abierto, lo ve al volver a esta pantalla sin reiniciar.
	ModLoader.scan()
	_populate()


func _build_ui() -> void:
	_build_background()
	_build_animated_logo()
	_build_loading_overlay()

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
	_title.text = "Washos Engine"
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


## Logo animado (bump) a la izquierda, centrado verticalmente. Usa el
## atlas Sparrow de FNF (logoBumpin.png + .xml). Si los archivos no
## existen, no hace nada: el resto del menu sigue andando.
##
## Escala al 40% del ancho del viewport y lo centra verticalmente con
## anchors. El frame del atlas es 939x703; sin escalar ocuparia casi
## toda la pantalla.
func _build_animated_logo() -> void:
	var png := "res://resources/images/logoBumpin.png"
	var xml := "res://resources/images/logoBumpin.xml"
	if not ResourceLoader.exists(png):
		push_warning("[ModSelector] logoBumpin: no existe " + png)
		return
	# FileAccess.file_exists() con res:// puede fallar para archivos
	# dentro del .pck en Android, aunque el archivo este. En vez de
	# chequear, abrimos el XML directo con XMLParser y si falla salimos.
	# Es el mismo parser que usa AnimatedLogo._parse_xml(), asi que si
	# el open() aca tiene exito, el parseo de adentro tambien.
	var probe := XMLParser.new()
	if probe.open(xml) != OK:
		push_warning("[ModSelector] logoBumpin: no puedo abrir " + xml)
		return

	# Anclar al centro-izquierda: la x queda pegada al borde izquierdo
	# mas un margen, la y al centro vertical.
	var logo: Control = AnimatedLogoScript.new()
	add_child(logo)
	logo.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Escala al 40% del ancho de pantalla.
	var vp := get_viewport_rect().size
	var frame_w := 939.0
	var frame_h := 703.0
	var target_w := vp.x * 0.40
	var scale_factor := target_w / frame_w
	logo.scale = Vector2(scale_factor, scale_factor)

	# Con PRESET_CENTER_LEFT el offset x es hacia la derecha del anchor,
	# y el offset y es hacia arriba/abajo desde el centro. Le restamos
	# la mitad del alto escalado para que quede centrado verticalmente.
	logo.size = Vector2(frame_w, frame_h)
	logo.position = Vector2(40, -frame_h * scale_factor * 0.5)
	logo.pivot_offset = Vector2(0, frame_h * 0.5)

	logo.setup(png, xml)


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
	_loading_title.add_theme_font_size_override("font_size", 56)
	_loading_title.add_theme_color_override("font_color", Color.WHITE)
	_loading_title.add_theme_constant_override("outline_size", 6)
	_loading_title.add_theme_color_override("font_outline_color", Color.BLACK)
	vbox.add_child(_loading_title)

	_loading_phase = Label.new()
	_loading_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_phase.add_theme_font_size_override("font_size", 26)
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
	if phase == "count":
		_loading_phase.text = "Analizando archivos..."
		_loading_bar.value = 0.0
		return
	_loading_phase.text = "Empaquetando %d / %d" % [done, total]
	if total > 0:
		_loading_bar.value = float(done) / float(total)
	else:
		_loading_bar.value = 0.0


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
	#print("[compile_gd] ENTRADA: " + path)
	if not FileAccess.file_exists(path):
	#print("[compile_gd] archivo no existe")
		return null
	var src := FileAccess.get_file_as_string(path)
	#print("[compile_gd] source_code length: %d" % src.length())
	#print("[compile_gd] primeras 120 chars: " + src.substr(0, 120))
	if src.is_empty():
	#print("[compile_gd] source vacio")
		return null
	var gd := GDScript.new()
	gd.source_code = src
	var err := gd.reload()
	#print("[compile_gd] reload() -> %d" % err)
	if err != OK:
	#print("[compile_gd] reload fallo")
		return null
	#print("[compile_gd] can_instantiate: %s" % gd.can_instantiate())
	#print("[compile_gd] base_type: %s" % gd.get_instance_base_type())
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

	# Bake PRIMERO, antes de cualquier check de existencia. Sin el pck
	# montado, ResourceLoader.exists() da false para CUALQUIER path del
	# mod - main_scene incluido - y un check previo abortaba antes de que
	# bake_mod corriera. Montar el pck, y recien despues preguntar si el
	# archivo existe.
	var need: bool = ModLoader.needs_bake(folder)
	DebugLog.log("[ModSelector._launch] needs_bake=%s" % need)
	if need:
		_show_loading_overlay(str(m.get("name", folder)))
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

	get_tree().change_scene_to_file(scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_demo()
