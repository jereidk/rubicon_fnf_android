extends CanvasLayer
## HQ Dodge Button — mobile dodge input for the Kyoko Attack mechanic.
## Shows the mod's "dodge" prompt art on the right edge and fires the `dodge`
## action (SPACE) while held, mirroring controls.DODGE in Kyoko Attack.hx.

const DODGE_TEXTURE := "res://holyquintet_mod/source/images/game/mechanics/kyoko/dodge.png"

var _button: TouchScreenButton


func _ready() -> void:
	layer = 16
	if not InputMap.has_action("dodge"):
		InputMap.add_action("dodge")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_SPACE
		InputMap.action_add_event("dodge", key)
	if not ResourceLoader.exists(DODGE_TEXTURE):
		return
	_button = TouchScreenButton.new()
	_button.name = "DodgeButton"
	_button.texture_normal = load(DODGE_TEXTURE)
	_button.scale = Vector2(0.22, 0.22)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(550.0, 475.0)
	_button.shape = shape
	var viewport_size := get_viewport().get_visible_rect().size
	_button.position = Vector2(viewport_size.x - 201.0, viewport_size.y * 0.42 - 52.0)
	_button.z_index = 100
	_button.pressed.connect(func(): Input.action_press("dodge"))
	_button.released.connect(func(): Input.action_release("dodge"))
	add_child(_button)
