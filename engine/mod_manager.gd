extends Control
## Pantalla de gestion de mods. Muestra la lista con activar/desactivar,
## reordenar, desinstalar, y avisos de colisiones y duplicados.
##
## Cada fila muestra la metadata del mod.json: icon, nombre, version,
## autor, descripcion corta y de que raiz viene. Tocar el nombre abre un
## popup con toda la metadata y los paths.
##
## Layout con Containers nativos: no hay posicion absoluta ni factor de
## escala manual, Godot distribuye el espacio solo y funciona en cualquier
## aspecto de pantalla.
##
## Escucha dos signals del ModLoader:
##   mods_changed   -> algo cambio (enabled, orden, scan), refrescar
##   mods_reloaded  -> hot reload al volver del background, mostrar aviso

const SELECTOR_SCENE := "res://engine/mod_selector.tscn"

var _title: Label
var _header: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _back_btn: Button
var _open_btn: Button
var _refresh_btn: Button
var _reload_notice: Label
var _notice_timer: float = 0.0
## Cache de iconos ya cargados: folder -> Texture2D. Se invalida cuando
## el mod cambia (el mtime de la carpeta es distinto), pero para no
## complicar lo dejamos sin invalidar por ahora: el usuario que edita un
## icono puede tocar "Releer" y el ModManager se recrea.
var _icon_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Restaurar el Window al estado original: si venimos de un mod que
	# overrideo stretch/mode o stretch/aspect, hay que devolverlo antes
	# de mostrar la UI del manager.
	ModLoader.restore_default_settings()
	_build_ui()
	ModLoader.mods_changed.connect(_refresh)
	ModLoader.mods_reloaded.connect(_on_mods_reloaded)
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.02, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "Mods"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 56)
	_title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_title)

	_header = Label.new()
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header.add_theme_font_size_override("font_size", 22)
	_header.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	vbox.add_child(_header)

	_reload_notice = Label.new()
	_reload_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reload_notice.add_theme_font_size_override("font_size", 22)
	_reload_notice.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	_reload_notice.visible = false
	vbox.add_child(_reload_notice)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	_scroll.add_child(_list)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(bottom)

	_open_btn = Button.new()
	_open_btn.text = "Abrir carpeta"
	_open_btn.custom_minimum_size = Vector2(0, 90)
	_open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_btn.add_theme_font_size_override("font_size", 24)
	_open_btn.pressed.connect(_open_mods_folder)
	_open_btn.mouse_entered.connect(func(): MenuMusic.play_scroll())
	bottom.add_child(_open_btn)

	_back_btn = Button.new()
	_back_btn.text = "Volver"
	_back_btn.custom_minimum_size = Vector2(0, 90)
	_back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_btn.add_theme_font_size_override("font_size", 24)
	_back_btn.pressed.connect(_go_selector)
	_back_btn.mouse_entered.connect(func(): MenuMusic.play_scroll())
	bottom.add_child(_back_btn)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Releer"
	_refresh_btn.custom_minimum_size = Vector2(0, 90)
	_refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_btn.add_theme_font_size_override("font_size", 24)
	_refresh_btn.pressed.connect(_rescan)
	_refresh_btn.mouse_entered.connect(func(): MenuMusic.play_scroll())
	bottom.add_child(_refresh_btn)


func _process(delta: float) -> void:
	if _notice_timer > 0.0:
		_notice_timer -= delta
		if _notice_timer <= 0.0:
			_reload_notice.visible = false


func _on_mods_reloaded(changed: Array) -> void:
	if changed.is_empty():
		return
	_reload_notice.text = "Cambios detectados en: %s" % ", ".join(changed)
	_reload_notice.visible = true
	_notice_timer = 3.0
	# Los iconos pueden haber cambiado: limpiar el cache para que se
	# recarguen. Es barato, solo se hace cuando hubo un cambio real.
	for folder in changed:
		_icon_cache.erase(folder)


func _refresh() -> void:
	# Recalcular colisiones antes de armar la lista. ModLoader las marca
	# dirty en scan() y en cualquier cambio de enabled/orden. Con HQ
	# (3070 archivos) hacerlo en cada scan eran 15s en el arranque, pero
	# aca solo corre cuando el usuario abre esta pantalla.
	await ModLoader.recompute_collisions_if_dirty()

	for c in _list.get_children():
		c.queue_free()

	if ModLoader.mods.is_empty():
		_header.text = "No hay mods en: %s" % ModLoader.mods_root
		var l := Label.new()
		l.text = "(Crea una carpeta por mod con su mod.json adentro)"
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_list.add_child(l)
		return

	var n_enabled := 0
	var n_colliding := 0
	for m in ModLoader.mods:
		if ModLoader.is_enabled(m["folder"]):
			n_enabled += 1
			if not ModLoader.collisions_for(m["folder"]).is_empty():
				n_colliding += 1

	var header_parts: PackedStringArray = PackedStringArray()
	header_parts.append("%d mods, %d activos" % [ModLoader.mods.size(), n_enabled])
	if n_colliding > 0:
		header_parts.append("⚠ %d con colisiones" % n_colliding)
	if not ModLoader.duplicates.is_empty():
		header_parts.append("%d duplicado(s)" % ModLoader.duplicates.size())
	header_parts.append("en: %s" % _short_root(ModLoader.mods_root))
	_header.text = " · ".join(header_parts)

	for i in ModLoader.mods.size():
		_list.add_child(_build_row(i))


func _short_root(root: String) -> String:
	if root.begins_with("user://"):
		return "app (user://mods)"
	if root.contains("/.WashosEngine/"):
		return "WashosEngine (oculto)"
	if root.contains("/WashosEngine/"):
		return "WashosEngine"
	return root


func _root_badge(root: String) -> String:
	if root.begins_with("user://"):
		return "app"
	if root.contains("/.WashosEngine/"):
		return "ext?"
	return "ext"


## Carga el icono del mod, desde disco, directo. No via res:// porque los
## mods desactivados no tienen el .pck montado y load() devolveria null.
##
## La resolucion del path la hace ModLoader.resolve_icon_path(): prueba
## mod.json["icon"], Icon.png en la raiz, y icon.* en minuscula, en ese
## orden. Aca solo cacheamos y decodificamos.
func _load_icon_for_mod(m: Dictionary) -> Texture2D:
	var folder: String = m["folder"]
	if _icon_cache.has(folder):
		return _icon_cache[folder]

	var path := ModLoader.resolve_icon_path(m)
	if path.is_empty():
		_icon_cache[folder] = null
		return null

	var tex := _load_texture_from_disk(path)
	_icon_cache[folder] = tex
	return tex


func _load_texture_from_disk(path: String) -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	var ext := path.get_extension().to_lower()
	var err := ERR_UNAVAILABLE
	match ext:
		"png":
			err = img.load_png_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
		"ktx":
			err = img.load_ktx_from_buffer(bytes)
		"svg":
			err = img.load_svg_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)


func _build_row(idx: int) -> Control:
	var m: Dictionary = ModLoader.mods[idx]
	var folder: String = m["folder"]

	# Fila contenedora con dos sub-filas: arriba los controles, abajo la
	# descripcion. La descripcion es una sola linea cortada con ellipsis.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	outer.add_child(row)

	var check := CheckBox.new()
	check.button_pressed = ModLoader.is_enabled(folder)
	check.custom_minimum_size = Vector2(90, 100)
	check.toggled.connect(func(v): ModLoader.set_enabled(folder, v))
	row.add_child(check)

	var icon_tex := _load_icon_for_mod(m)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(90, 90)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon_tex != null:
		icon.texture = icon_tex
	else:
		# Placeholder de texto cuando no hay icono. Es un Label dentro de un
		# Control del mismo tamano, alineado al centro.
		var ph := Label.new()
		ph.text = "?"
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.add_theme_font_size_override("font_size", 40)
		ph.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		icon.add_child(ph)
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	var name_label := Label.new()
	var display_name := str(m.get("name", folder))
	var marks: PackedStringArray = PackedStringArray()
	var cols := ModLoader.collisions_for(folder)
	if not cols.is_empty():
		marks.append("⚠")
	for dup in ModLoader.duplicates:
		if dup["name"] == folder:
			marks.append("⊕")
			break
	if not marks.is_empty():
		display_name = "%s %s" % [" ".join(marks), display_name]
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	name_label.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_mod_details(m)
		elif ev is InputEventScreenTouch and ev.pressed:
			_show_mod_details(m)
	)
	if not cols.is_empty():
		name_label.tooltip_text = "Colisiones:\n" + "\n".join(cols)
	text_col.add_child(name_label)

	# Sub-linea: version + autor + badge de raiz.
	var meta_parts: PackedStringArray = PackedStringArray()
	meta_parts.append("v" + str(m.get("version", "?")))
	if m.has("author") and not str(m["author"]).is_empty():
		meta_parts.append("por " + str(m["author"]))
	meta_parts.append(_root_badge(m.get("root", "")))
	var meta := Label.new()
	meta.text = " · ".join(meta_parts)
	meta.add_theme_font_size_override("font_size", 20)
	meta.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	meta.clip_text = true
	text_col.add_child(meta)

	var up := Button.new()
	up.text = "▲"
	up.custom_minimum_size = Vector2(80, 90)
	up.add_theme_font_size_override("font_size", 26)
	up.disabled = idx == 0
	up.pressed.connect(func(): ModLoader.move_mod(folder, -1))
	up.mouse_entered.connect(func(): MenuMusic.play_scroll())
	row.add_child(up)

	var down := Button.new()
	down.text = "▼"
	down.custom_minimum_size = Vector2(80, 90)
	down.add_theme_font_size_override("font_size", 26)
	down.disabled = idx == ModLoader.mods.size() - 1
	down.pressed.connect(func(): ModLoader.move_mod(folder, 1))
	down.mouse_entered.connect(func(): MenuMusic.play_scroll())
	row.add_child(down)

	var del := Button.new()
	del.text = "X"
	del.custom_minimum_size = Vector2(80, 90)
	del.add_theme_font_size_override("font_size", 26)
	del.pressed.connect(func(): _confirm_uninstall(folder))
	del.mouse_entered.connect(func(): MenuMusic.play_scroll())
	row.add_child(del)

	# Descripcion debajo, si existe.
	var desc: String = str(m.get("description", ""))
	if not desc.is_empty():
		var dl := Label.new()
		dl.text = desc
		dl.add_theme_font_size_override("font_size", 18)
		dl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.max_lines_visible = 2
		dl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		outer.add_child(dl)

	return outer


## Popup con toda la metadata del mod + paths. Se abre al tocar el nombre.
## Usa un AcceptDialog porque trae su propio boton de cerrar y maneja
## correctamente el foco en Android.
func _show_mod_details(m: Dictionary) -> void:
	var folder: String = m["folder"]

	var lines: PackedStringArray = PackedStringArray()
	lines.append("Nombre:      %s" % m.get("name", folder))
	if m.has("version"):
		lines.append("Version:     %s" % m["version"])
	if m.has("author"):
		lines.append("Autor:       %s" % m["author"])
	lines.append("Carpeta:     %s" % folder)
	lines.append("Raiz:        %s" % _short_root(m.get("root", "")))
	lines.append("Path:        %s" % m.get("path", "?"))
	lines.append("")
	lines.append("Main scene:  %s" % m.get("main_scene", "(no definida)"))
	lines.append("Activo:      %s" % ("si" if ModLoader.is_enabled(folder) else "no"))

	if m.has("description") and not str(m["description"]).is_empty():
		lines.append("")
		lines.append("Descripcion:")
		lines.append(str(m["description"]))

	if m.has("homepage") and not str(m["homepage"]).is_empty():
		lines.append("")
		lines.append("Homepage:    %s" % m["homepage"])

	var cols := ModLoader.collisions_for(folder)
	if not cols.is_empty():
		lines.append("")
		lines.append("⚠ Colisiones con otros mods activos:")
		for c in cols:
			lines.append("  %s" % c)

	var dialog := AcceptDialog.new()
	dialog.title = "Detalles del mod"
	dialog.dialog_text = "\n".join(lines)
	dialog.ok_button_text = "Cerrar"
	dialog.min_size = Vector2(700, 500)
	add_child(dialog)
	dialog.popup_centered()


func _confirm_uninstall(folder: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Desinstalar mod"
	dialog.dialog_text = "¿Desinstalar '%s'?\n\nSe borra la carpeta del mod y su caché .pck.\nNo se puede deshacer." % folder
	dialog.ok_button_text = "Desinstalar"
	dialog.cancel_button_text = "Cancelar"
	dialog.confirmed.connect(func():
		MenuMusic.play_confirm()
		ModLoader.uninstall_mod(folder)
	)
	dialog.canceled.connect(func(): MenuMusic.play_cancel())
	add_child(dialog)
	dialog.popup_centered()


func _rescan() -> void:
	_icon_cache.clear()
	ModLoader.scan()
	_refresh()


func _open_mods_folder() -> void:
	if OS.get_name() == "Android":
		OS.shell_open("file://" + ModLoader.mods_root)
	else:
		OS.shell_open(ModLoader.mods_root)


func _go_selector() -> void:
	MenuMusic.play_cancel()
	get_tree().change_scene_to_file(SELECTOR_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_selector()
