extends Node
## Chart events — the actions the chart calls by string name.
##
## These are NOT baked onto value tracks: they fire once from the chart's
## method tracks. The chart calls them as function keys on the level clock.
##
## Generic gameplay (combo, splash, HUD lifecycle, camera nudge, etc.)
## lives in animania_module.gd (autoload). This script only handles the
## per-song choreography that chart events trigger.
##
## Per-song scripts extend this and override _on_beat() or add their own
## chart-event methods (FocusCamera, Shake, PlayAnimation, etc.).

## ─── Chart event: FocusCamera ───────────────────────────────────────────────
## Instant camera aim. The chart writes the target as a baked value track
## and this fires the snap from the chart's method track.
var camera: Camera2D

func focus_camera(target: Vector2) -> void:
	if camera == null:
		return
	camera.position_interpolate_target = target
	camera.global_position = target


## ─── Chart event: Shake ─────────────────────────────────────────────────────
## intensity is a fraction of screen width (Flixel convention).
## duration is in seconds.
func shake(intensity: float, duration: float) -> void:
	AnimaniaModule.shake_screen(intensity, duration)


## ─── Chart event: AddCameraZoom ─────────────────────────────────────────────
## One-shot zoom punch. The chart carries the zoom amount.
func add_camera_zoom(amount: float) -> void:
	AnimaniaModule.punch(amount)


## ─── Chart event: SetCameraBop ──────────────────────────────────────────────
## Changes the bumper's automatic beat-bop rate and strength.
## rate is in beats (e.g. 4 = every 4 beats). intensity is a multiplier.
## intensity=0 disables the bop.
func set_camera_bop(bumper: Node, rate: int, intensity: float) -> void:
	AnimaniaModule.set_bop(bumper, rate, intensity)


## ─── Chart event: PlayAnimation ─────────────────────────────────────────────
## Makes a character play an animation the note chart would not.
## force=false means "play but don't restart if already running."
func play_animation(target: StringName, animation: StringName,
		force: bool = false) -> void:
	AnimaniaModule.play_character_animation(target, animation, force)


## ─── Chart event: SetProperty ───────────────────────────────────────────────
## Sets a property on a character. Most commonly:
##   SetProperty boyfriend.idleSuffix "-alt"
## which swaps the idle pose set for the rest of the song.
func set_property(target: StringName, property: String,
		value: Variant) -> void:
	if property == "idleSuffix":
		AnimaniaModule.set_idle_suffix(target, str(value))
	else:
		push_warning("SetProperty: unknown property '%s'" % property)


## ─── Chart event: CinematicBars ─────────────────────────────────────────────
## Top/bottom letterbox bars. The chart calls show_bars/hide_bars.
var bar_top: CanvasItem
var bar_bottom: CanvasItem

func show_cinematic_bars(height: float = 100.0, duration: float = 0.3) -> void:
	AnimaniaModule.show_bars(bar_top, bar_bottom, height, duration)


func hide_cinematic_bars(duration: float = 0.3) -> void:
	AnimaniaModule.hide_bars(bar_top, bar_bottom, duration)


## ─── Chart event: Flash ─────────────────────────────────────────────────────
## White or black screen flash. Duration in seconds.
var flash_rect: ColorRect

func flash(color: Color = Color.WHITE, duration: float = 1.5) -> void:
	AnimaniaModule.flash_screen(flash_rect, color, duration)


## ─── Chart event: Fade ──────────────────────────────────────────────────────
## Screen fade to black.
var fade_rect: ColorRect

func fade_out(duration: float = 3.0) -> void:
	AnimaniaModule.fade_out_node(fade_rect, duration)


## ─── Per-song beat override ─────────────────────────────────────────────────
## Override in subclass for per-song beat choreography.
## Call super._on_beat() to pulse strumlines if needed.
func _on_beat() -> void:
	pass
