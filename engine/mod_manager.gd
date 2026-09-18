extends Control
## Pantalla de gestion de mods. Muestra la lista con activar/desactivar,
## reordenar, desinstalar, y avisos de colisiones y duplicados.
##
## Layout con Containers nativos: no hay posicion absoluta ni factor de
## escala manual, Godot distribuye el espacio solo y funciona en cualquier
## aspecto de pantalla (16:9, 20:9, tablet, lo que sea).
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


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	bottom.add_child(_open_btn)

	_back_btn = Button.new()
	_back_btn.text = "Volver"
	_back_btn.custom_minimum_size = Vector2(0, 90)
	_back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_btn.add_theme_font_size_override("font_size", 24)
	_back_btn.pressed.connect(_go_selector)
	bottom.add_child(_back_btn)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Releer"
	_refresh_btn.custom_minimum_size = Vector2(0, 90)
	_refresh_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh_btn.add_theme_font_size_override("font_size", 24)
	_refresh_btn.pressed.connect(_rescan)
	bottom.add_child(_refresh_btn)


func _process(delta: float) -> void:
	# El aviso de "recargado" vive 3 segundos y se va solo.
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


func _refresh() -> void:
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
	if root.contains("/RubiconEngine/"):
		return "RubiconEngine"
	if root.contains("/.RubiconEngine/"):
		return "RubiconEngine (oculto)"
	return root


func _root_badge(root: String) -> String:
	if root.begins_with("user://"):
		return "📱"
	if root.contains("/.RubiconEngine/"):
		return "📁?"
	return "📁"


func _build_row(idx: int) -> Control:
	var m: Dictionary = ModLoader.mods[idx]
	var folder: String = m["folder"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var check := CheckBox.new()
	check.button_pressed = ModLoader.is_enabled(folder)
	check.custom_minimum_size = Vector2(100, 100)
	check.toggled.connect(func(v): ModLoader.set_enabled(folder, v))
	row.add_child(check)

	var badge := Label.new()
	badge.text = _root_badge(m.get("root", ""))
	badge.add_theme_font_size_override("font_size", 28)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.custom_minimum_size = Vector2(50, 0)
	row.add_child(badge)

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
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.clip_text = true
	if not cols.is_empty():
		name_label.tooltip_text = "Colisiones:\n" + "\n".join(cols)
	row.add_child(name_label)

	var ver_label := Label.new()
	ver_label.text = "v" + str(m.get("version", "?"))
	ver_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ver_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ver_label.add_theme_font_size_override("font_size", 22)
	row.add_child(ver_label)

	var up := Button.new()
	up.text = "▲"
	up.custom_minimum_size = Vector2(90, 100)
	up.add_theme_font_size_override("font_size", 28)
	up.disabled = idx == 0
	up.pressed.connect(func(): ModLoader.move_mod(folder, -1))
	row.add_child(up)

	var down := Button.new()
	down.text = "▼"
	down.custom_minimum_size = Vector2(90, 100)
	down.add_theme_font_size_override("font_size", 28)
	down.disabled = idx == ModLoader.mods.size() - 1
	down.pressed.connect(func(): ModLoader.move_mod(folder, 1))
	row.add_child(down)

	var del := Button.new()
	del.text = "🗑"
	del.custom_minimum_size = Vector2(90, 100)
	del.add_theme_font_size_override("font_size", 28)
	del.pressed.connect(func(): _confirm_uninstall(folder))
	row.add_child(del)

	return row


func _confirm_uninstall(folder: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Desinstalar mod"
	dialog.dialog_text = "¿Desinstalar '%s'?\n\nSe borra la carpeta del mod y su caché .pck.\nNo se puede deshacer." % folder
	dialog.ok_button_text = "Desinstalar"
	dialog.cancel_button_text = "Cancelar"
	dialog.confirmed.connect(func(): ModLoader.uninstall_mod(folder))
	add_child(dialog)
	dialog.popup_centered()


func _rescan() -> void:
	ModLoader.scan()
	ModLoader._load_all_enabled()
	_refresh()


func _open_mods_folder() -> void:
	if OS.get_name() == "Android":
		OS.shell_open("file://" + ModLoader.mods_root)
	else:
		OS.shell_open(ModLoader.mods_root)


func _go_selector() -> void:
	get_tree().change_scene_to_file(SELECTOR_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_selector()
