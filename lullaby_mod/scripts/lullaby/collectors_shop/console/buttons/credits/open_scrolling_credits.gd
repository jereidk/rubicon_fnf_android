extends Button


@export var action: StringName = &"open_cartridge_bag"

@onready var keybind_label: Label = $KeybindLabel


func _ready() -> void :
	# Rubicon addition: this is a real Button, but the real mod never wired
	# its own click to _pressed() — only the F-key shortcut worked, so
	# tapping/clicking it was a silent no-op.
	pressed.connect(_pressed)

	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var keycode: Key = event.keycode
			if keycode == 0:
				# Solo donde el servidor de pantalla sepa mapearlo. En Android
				# no hay teclado fisico que consultar y la llamada suelta un
				# error rojo - "Not supported by this display server",
				# display_server.cpp:1224 - cada vez que se formatea la nota.
				# El fallback es el propio physical_keycode, que para las
				# teclas de letra da el mismo nombre en un teclado QWERTY.
				if OS.has_feature("mobile"):
					keycode = event.physical_keycode
				else:
					keycode = DisplayServer.keyboard_get_keycode_from_physical(
						event.physical_keycode)

			keybind_label.text = "[%s]" % OS.get_keycode_string(keycode)
			break

	if !SaveData.get_flag(&"credits_scroll_seen"):
		hide()


func _input(event: InputEvent) -> void :
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(action):
		_pressed()


func _pressed() -> void :
	SceneChanger.change_to("uid://c56x7ch1lypk3", &"hypno")
