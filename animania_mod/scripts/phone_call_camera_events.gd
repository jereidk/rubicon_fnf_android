extends Node
## The two camera events that are actions rather than values.
##
## Everything else the chart does to the camera - FocusCamera, ZoomCamera, CinematicBars -
## is a target being tweened, so it bakes into a value track and needs no code. These two
## do not:
##
##   * AddCameraZoom is a one-shot punch. RubiconCameraBumper's own bump is `zoom +=`, and
##     the camera's _process eases it back out, so a punch is that same one line fired off
##     the animation instead of off the beat. It is not a setting - the giveaway is that
##     the first of the twelve is 0.05 at 6.5s, in the stretch where SetCameraBop has the
##     automatic bop switched off, which is a manual accent where the automatic one cannot
##     reach.
##   * SetCameraBop changes the bumper's rate and strength for everything after it.
##
## Both arrive as method-track keys on the level clock's animation.

## Funkin's default per-bop game zoom. SetCameraBop's `intensity` is a multiplier on it,
## which is why the chart's AddCameraZoom events mostly carry this exact number.
const DEFAULT_BOP := 0.015

@export var camera: Camera2D
@export var bumper: Node
## The UI canvas, for the HUD half of a punch.
@export var hud: CanvasLayer

var _hud_rest: Vector2 = Vector2.ONE


func _ready() -> void:
	if hud != null:
		_hud_rest = hud.scale


## AddCameraZoom. `hud_zoom` is applied to the UI canvas about the middle of the screen -
## a CanvasLayer scales from its top-left corner, so scaling alone would slide the whole
## HUD up and to the left instead of pulsing it in place.
func punch(game_zoom: float, hud_zoom: float) -> void:
	if camera != null:
		camera.zoom += Vector2.ONE * game_zoom

	if hud == null:
		return
	var screen: Vector2 = Vector2(hud.get_viewport().get_visible_rect().size)
	hud.scale = _hud_rest + Vector2.ONE * hud_zoom
	hud.offset = -screen * 0.5 * (hud.scale - Vector2.ONE)


## SetCameraBop. `rate` is in beats.
func set_bop(rate: int, intensity: float) -> void:
	if bumper == null:
		return
	bumper.bump_interval = maxi(1, rate)
	bumper.bump_amount = DEFAULT_BOP * intensity
	bumper.enabled = intensity > 0.0


## The HUD punch has to decay the way the camera's does; the camera gets that free from
## RubiconInterpolatedCamera2D's own lerp, and the CanvasLayer has no equivalent.
func _process(delta: float) -> void:
	if hud == null or hud.scale.is_equal_approx(_hud_rest):
		return

	hud.scale = hud.scale.lerp(_hud_rest, minf(1.0, 3.0 * delta))
	var screen: Vector2 = Vector2(hud.get_viewport().get_visible_rect().size)
	hud.offset = -screen * 0.5 * (hud.scale - Vector2.ONE)
