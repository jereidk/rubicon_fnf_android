extends RichTextLabel


var last_text: String


func _ready() -> void :
	last_text = text
	update_text_format()


func _process(_delta: float) -> void :
	if text != last_text:
		last_text = text
		update_text_format()


func update_text_format() -> void :
	for event: InputEvent in InputMap.action_get_events(&"lullaby_special"):
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

			text = text.replace("$SPECIAL", "[ %s ]" % OS.get_keycode_string(keycode))
			break
