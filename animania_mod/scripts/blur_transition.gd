extends CanvasLayer
## Blur transition — faithful port of Animania's blurX/blurY transition system.
##
## The binary uses ShaderMaterial with blurX and blurY parameters to create
## smooth transitions between states. This script provides a reusable
## blur overlay that can be added to any scene.

# ─── Constants ─────────────────────────────────────────────────────────────

const BLUR_SHADER := "res://animania_mod/shaders/gaussian_blur.gdshader"

# ─── Fields ───────────────────────────────────────────────────────────────

var _blur_rect: ColorRect
var _shader_material: ShaderMaterial
var _blur_x: float = 0.0
var _blur_y: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 5
	_setup_blur_overlay()


func _setup_blur_overlay() -> void:
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = load(BLUR_SHADER) as Shader
	_shader_material.set_shader_parameter("blur_x", 0.0)
	_shader_material.set_shader_parameter("blur_y", 0.0)

	# Full-screen ColorRect that captures and blurs the screen
	# Using SCREEN_TEXTURE in the shader handles the capture
	_blur_rect = ColorRect.new()
	_blur_rect.name = "BlurOverlay"
	_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_rect.material = _shader_material
	_blur_rect.visible = false
	add_child(_blur_rect)


# ─── Blur control ─────────────────────────────────────────────────────────

func set_blur(x: float, y: float) -> void:
	_blur_x = x
	_blur_y = y
	if _shader_material:
		_shader_material.set_shader_parameter("blur_x", x)
		_shader_material.set_shader_parameter("blur_y", y)
	# Show overlay when blur is active
	if _blur_rect:
		_blur_rect.visible = (x > 0.0 or y > 0.0)


func get_blur_x() -> float:
	return _blur_x


func get_blur_y() -> float:
	return _blur_y


## Smoothly transition blur over time.
## The Animania binary uses this for song end/exit effects.
func tween_blur(target_x: float, target_y: float, duration: float = 0.5) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_method(set_blur_value_x, _blur_x, target_x, duration).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(set_blur_value_y, _blur_y, target_y, duration).set_ease(Tween.EASE_IN_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.chain().tween_callback(func() -> void:
		if target_x <= 0.0 and target_y <= 0.0:
			if _blur_rect:
				_blur_rect.visible = false
	)


func set_blur_value_x(value: float) -> void:
	_blur_x = value
	if _shader_material:
		_shader_material.set_shader_parameter("blur_x", value)


func set_blur_value_y(value: float) -> void:
	_blur_y = value
	if _shader_material:
		_shader_material.set_shader_parameter("blur_y", value)


## Apply the standard Animania blur-in effect (no blur → full blur).
func blur_in(duration: float = 0.5) -> void:
	if _blur_rect:
		_blur_rect.visible = true
	tween_blur(5.0, 5.0, duration)


## Apply the standard Animania blur-out effect (full blur → no blur).
func blur_out(duration: float = 0.5) -> void:
	tween_blur(0.0, 0.0, duration)


## Clear blur instantly.
func clear_blur() -> void:
	set_blur(0.0, 0.0)
	if _blur_rect:
		_blur_rect.visible = false


## Combined fade + blur transition (like Animania's song end/exit).
func fade_and_blur(fade_target: float, blur_target: float, duration: float = 0.5) -> void:
	tween_blur(blur_target, blur_target, duration)
	# Parent node should handle fade separately via modulate
