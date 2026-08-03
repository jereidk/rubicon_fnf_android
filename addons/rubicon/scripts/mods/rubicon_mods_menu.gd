extends Control
## Minimal mods menu: lists every mod found by the "Mods" autoload, lets the user
## toggle non-global mods on/off, and warns when a restart is needed for the change to
## take effect (only true for mods that ship a .pck; loose-file overrides apply live).
## Meant to be instanced from a pause/options menu, similar to Psych's ModsMenuState.

@onready var mod_list_container: VBoxContainer = %ModList
@onready var restart_notice: Label = %RestartNotice
@onready var close_button: Button = %CloseButton

func _ready() -> void:
	close_button.pressed.connect(func() -> void: queue_free())
	_populate()

func _populate() -> void:
	for child in mod_list_container.get_children():
		child.queue_free()

	var mods := Mods.get_mod_list()
	if mods.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No se encontraron mods en:\n%s" % Mods.get_mods_root()
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mod_list_container.add_child(empty_label)
		return

	for info: RubiconModInfo in mods:
		mod_list_container.add_child(_build_row(info))

func _build_row(info: RubiconModInfo) -> Control:
	var row := HBoxContainer.new()

	var check := CheckBox.new()
	check.button_pressed = info.enabled
	check.disabled = info.global
	check.toggled.connect(_on_mod_toggled.bind(info.folder_name))
	row.add_child(check)

	var name_label := Label.new()
	var suffix := " (global)" if info.global else ""
	name_label.text = "%s%s" % [info.display_name, suffix]
	name_label.tooltip_text = info.description
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)

	if info.version != "":
		var version_label := Label.new()
		version_label.text = "v%s" % info.version
		version_label.modulate.a = 0.6
		row.add_child(version_label)

	return row

func _on_mod_toggled(pressed: bool, folder: String) -> void:
	Mods.set_mod_enabled(folder, pressed)
	restart_notice.visible = true
