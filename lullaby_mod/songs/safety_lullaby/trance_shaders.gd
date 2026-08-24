extends Node

@export var pendulum_server: LullabyPendulumServer

## Water distortion, HSV and contrast used to be three separate full-screen
## passes (each its own hint_screen_texture backbuffer copy) chained in
## draw order with nothing drawn between them - fused into one shader/pass
## (shd_trance_water_hsv_contrast.gdshader) since chaining them inline
## produces the same result. Radial blur stays a separate pass since it's a
## spatial multi-tap operation that doesn't commute with a straight-line
## color chain the way HSV/contrast do.
@onready var water: ShaderMaterial = %WaterEffect.material
@onready var radial: ShaderMaterial = %RadialEffect.material

## Los dos rects, para poder esconderlos cuando el efecto no hace nada.
##
## Los dos son ColorRect a pantalla completa sobre `hint_screen_texture`, o
## sea que cada uno cuesta una copia de framebuffer - lo más caro que se le
## puede pedir a una GPU de tiles, porque obliga al tile a resolverse a
## memoria - más una mezcla a pantalla completa. Y los dos tienen una rama de
## identidad: `shd_radial_blur` con `BLUR_STRENGTH <= 0.0` y
## `shd_trance_water_hsv_contrast` con `WAVE_STRENGTH <= 0.0` y HSV/contraste
## en sus valores neutros copian la pantalla y la vuelven a escribir igual.
##
## Que es el estado por defecto de esta canción: los cuatro parámetros salen
## de `_effects_strength`, que es `(100 - retention) / 100`, o sea 0 mientras
## el jugador lleve bien el péndulo. Medido en aislado sobre la ruta del
## teléfono (Vulkan, Forward Mobile, 1600x720, el mismo shader):
##
##     activo (15 muestras/píxel)   49.7ms   draws=2
##     identidad                    20.0ms   draws=2
##     oculto                        6.7ms   draws=1
##
## O sea que el pase identidad cuesta 13.3ms de un frame de 20 -tres veces lo
## que cuesta todo lo que hay debajo- y esconderlo se lleva la copia con él,
## que es lo que dice el `draws=2 -> 1`.
##
## Los dos shaders están en `EFFECT_SHADER_PATHS`, así que a Very Low ya se
## quitan enteros; esto cae en Low, Medium y High, que es donde el jugador no
## pidió degradar nada.
@onready var water_rect: ColorRect = %WaterEffect
@onready var radial_rect: ColorRect = %RadialEffect

## Por debajo de esto el efecto no llega a un paso de cuantización.
##
## El término que más pesa con `_effects_strength = e` es la saturación, que
## sale `1 - 0.275 * e`, o sea una desviación de como mucho `0.275 * e` sobre
## un canal. Para que no llegue a medio paso de 8 bits hace falta
## `0.275 * e < 0.5 / 255`, es decir `e < 0.0071`. Con 0.002 hay 3.6x de
## margen sobre el peor píxel posible, y los otros tres términos quedan mucho
## más abajo: a e=0.002 el contraste es 1.00009, el desplazamiento del agua
## son 2.5e-4 píxeles en una pantalla de 2340, y `BLUR_STRENGTH` 2.7e-4.
const NEUTRAL_EPSILON := 0.002

var _effects_strength: float = 0.0
var _nullify_strength: bool = false

func _ready() -> void :
	# Sin materiales no hay nada que conducir, y hay que retirarse, no fallar.
	#
	# El comentario de `water_rect` de arriba ya lo decía - los dos shaders
	# están en `EFFECT_SHADER_PATHS`, así que a Very Low se quitan enteros -
	# pero el código no lo manejaba, y Very Low es el preset con el que sale el
	# juego. El `.error` del 2026-08-24 lo tenía:
	#
	#     Cannot call method 'set_shader_parameter' on a null value.
	#     trance_shaders.gd:77 _process
	#
	# En `_process`: **un error rojo por frame** de Safety Lullaby, con
	# `_process` abortando en esa línea y sin ejecutar nada de lo que sigue.
	# Formatear un error y recorrer su traza no sale gratis en la canción que
	# ya va a 30fps.
	if water == null or radial == null:
		# Guardar los rects antes de irse, no solo dejar de conducirlos.
		#
		# La escena los trae visibles con `color = Color(0,0,0,0)`; quien los
		# escondía era `_update_rect_visibility()`, aquí abajo. Un `return`
		# antes de esa llamada los deja dibujándose para siempre: dos ColorRect
		# a pantalla completa, invisibles pero mezclados cada frame, en la
		# canción que ya está limitada por relleno. La primera versión de este
		# arreglo hacía exactamente eso.
		if water_rect != null:
			water_rect.visible = false
		if radial_rect != null:
			radial_rect.visible = false
		set_process(false)
		return

	# `_effects_strength` arranca a 0, así que sin esto los dos rects harían un
	# frame de pase identidad antes del primer `_process`.
	_update_rect_visibility()

## Se sigue escribiendo cada parámetro aunque el rect esté oculto - así, cuando
## vuelve, el material ya trae el valor bueno y no hay un frame de salto.
func _update_rect_visibility() -> void :
	var active: bool = _effects_strength > NEUTRAL_EPSILON
	if water_rect.visible != active:
		water_rect.visible = active
	if radial_rect.visible != active:
		radial_rect.visible = active

func _process(delta: float) -> void :
	var target_strength = 0.0 if _nullify_strength else (100.0 - pendulum_server.retention_value) / 100.0
	_effects_strength = lerp(_effects_strength, target_strength, 1.0 - pow(0.2, delta))

	var water_amount = clamp(_effects_strength * 0.95, 0.0, 1.0)
	water.set_shader_parameter("WAVE_STRENGTH", min(EasingFunctions.ease_in_out_sine(0.0, 1.0, water_amount) * 0.95, 0.65))
	water.set_shader_parameter("GHOST_STRENGTH", min(EasingFunctions.ease_in_out_quad(0.0, 1.0, water_amount) * 0.25, 0.15))

	var saturation_amount = 1.0 - (_effects_strength * 0.275)
	water.set_shader_parameter("SATURATION", saturation_amount)

	var contrast_amount = 1.0 + (_effects_strength * 0.04575)
	water.set_shader_parameter("CONTRAST", contrast_amount)

	var radial_amount = _effects_strength * 0.135
	radial.set_shader_parameter("BLUR_STRENGTH", radial_amount)

	_update_rect_visibility()

func _on_lullaby_pendulum_server_mechanic_failed() -> void :
	_nullify_strength = true

func _on_health_module_health_depleted() -> void :
	_nullify_strength = true
