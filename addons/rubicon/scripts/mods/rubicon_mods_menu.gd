extends Control
## Mods menu: pick a mod and press "Jugar" to make it the active one — it's turned on,
## promoted to top priority (Mods.get_current_mod()), and the current scene reloads so
## you're immediately in its flow, mirroring Psych Engine's "top of the enabled list is
## the loaded mod" behavior. The checkbox next to each mod is a secondary control for
## layering extra mods on/off without switching which one is "in front".

@onready var mod_list_container: VBoxContainer = %ModList
@onready var restart_notice: Label = %RestartNotice
@onready var close_button: Button = %CloseButton
@onready var base_game_button: Button = %BaseGameButton

func _ready() -> void:
	close_button.pressed.connect(func() -> void: queue_free())
	base_game_button.pressed.connect(Mods.exit_to_base)
	_populate()

func _populate() -> void:
	for child in mod_list_container.get_children():
		child.queue_free()

	base_game_button.disabled = Mods.get_current_mod() == null

	var mods := Mods.get_mod_list()
	if mods.is_empty():
		var empty_label := Label.new()
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if OS.get_name() == "Android" and not Mods.has_mods_root_access():
			empty_label.text = "Sin acceso a la carpeta de mods.\nActivá \"Acceso a todos los archivos\" para esta app en Ajustes > Apps, y volvé a abrir el juego.\n\n%s" % Mods.get_mods_root()
		else:
			empty_label.text = "No se encontraron mods en:\n%s" % Mods.get_mods_root()
		mod_list_container.add_child(empty_label)
		return

	var current := Mods.get_current_mod()
	for info: RubiconModInfo in mods:
		mod_list_container.add_child(_build_row(info, info == current))

func _build_row(info: RubiconModInfo, is_current: bool) -> Control:
	var row := HBoxContainer.new()

	var check := CheckBox.new()
	check.button_pressed = info.enabled
	check.disabled = info.global
	check.tooltip_text = "Activar/desactivar sin entrar a jugarlo"
	check.toggled.connect(_on_mod_toggled.bind(info.folder_name))
	row.add_child(check)

	var name_label := Label.new()
	var prefix := "> " if is_current else ""
	var suffix := " (global)" if info.global else ""
	name_label.text = "%s%s%s" % [prefix, info.display_name, suffix]
	name_label.tooltip_text = info.description
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)

	if info.version != "":
		var version_label := Label.new()
		version_label.text = "v%s" % info.version
		version_label.modulate.a = 0.6
		row.add_child(version_label)

	var play_button := Button.new()
	play_button.text = "Jugando" if is_current else "Jugar"
	play_button.disabled = is_current
	play_button.pressed.connect(Mods.enter_mod.bind(info.folder_name))
	row.add_child(play_button)

	return row

func _on_mod_toggled(pressed: bool, folder: String) -> void:
	Mods.set_mod_enabled(folder, pressed)
	restart_notice.visible = true
	_populate()
